# MultiMeshToInteractable.gd
# Converts MultiMesh instances to interactable nodes on-hover for harvesting
# This maintains performance by keeping everything as MultiMesh until needed
class_name MultiMeshToInteractable
extends Node

# Currently active interactable (converted from MultiMesh)
var active_interactable: InteractableFoliage = null
var active_source_mmi: MultiMeshInstance3D = null
var active_all_mmis: Array[MultiMeshInstance3D] = []  # ALL MMIs for this layer (trunk, leaves, etc.)
var active_instance_index: int = -1
var active_layer: FoliageLayer = null
var active_original_transforms: Dictionary = {}  # MMI -> Transform3D mapping for restoration

# Reference to spawner
var foliage_spawner: ProceduralFoliageSpawner = null


func _ready():
	# Find the foliage spawner
	foliage_spawner = get_parent() if get_parent() is ProceduralFoliageSpawner else null


func check_multimesh_hover(raycast_hit: Dictionary) -> InteractableFoliage:
	"""
	Check if raycast hit a MultiMeshInstance3D and convert it to interactable.
	Returns the interactable node if created, null otherwise.
	"""
	if not raycast_hit.has("collider"):
		_cleanup_active_interactable()
		return null

	var collider = raycast_hit["collider"]

	# Check if we hit a MultiMeshInstance3D
	if not collider is MultiMeshInstance3D:
		_cleanup_active_interactable()
		return null

	var mmi: MultiMeshInstance3D = collider

	# Get which instance was hit
	if not raycast_hit.has("shape"):
		_cleanup_active_interactable()
		return null

	var instance_index: int = raycast_hit["shape"]

	# Check if this is the same instance we already have active
	if active_interactable and active_source_mmi == mmi and active_instance_index == instance_index:
		return active_interactable

	# Different instance - cleanup old one
	_cleanup_active_interactable()

	# Find which layer this MMI belongs to
	var layer = _find_layer_for_mmi(mmi)
	if not layer or not layer.is_interactable:
		return null

	# Convert this specific instance to an interactable node
	return _convert_instance_to_interactable(mmi, instance_index, layer)


func _find_layer_for_mmi(mmi: MultiMeshInstance3D) -> FoliageLayer:
	"""Find which FoliageLayer this MultiMeshInstance3D belongs to"""
	if not foliage_spawner:
		return null

	# Check all loaded chunks and layers
	for chunk_data in foliage_spawner.loaded_chunks.values():
		for layer_name in chunk_data.layers.keys():
			var layer_data = chunk_data.layers[layer_name]
			if mmi in layer_data.multimesh_instances:
				# Find the actual FoliageLayer resource
				for layer in foliage_spawner.foliage_layers:
					if layer.layer_name == layer_name:
						return layer
	return null


func _convert_instance_to_interactable(mmi: MultiMeshInstance3D, instance_index: int, layer: FoliageLayer) -> InteractableFoliage:
	"""Convert a specific MultiMesh instance to an InteractableFoliage node"""
	if not mmi.multimesh or instance_index >= mmi.multimesh.instance_count:
		return null

	# Find ALL MMIs for this layer FIRST
	var all_mmis = _find_all_mmis_for_layer(mmi, layer)
	# Get the ORIGINAL world-space transform from metadata that was stored
	# during chunk generation (before local offsets were applied).
	var stored_transforms: Array = mmi.get_meta("item_transforms", [])
	if instance_index >= stored_transforms.size():
		push_error("[MultiMeshToInteractable] Instance index ", instance_index, " out of bounds (", stored_transforms.size(), " transforms)")
		return null

	# This is the original world-space transform from ProceduralFoliageSpawner.generate_items_for_layer()
	var original_world_transform: Transform3D = stored_transforms[instance_index]
	var world_transform = original_world_transform

	# Create the interactable node
	var foliage_instance = layer.scene.instantiate()

	# DEBUG: Print the scene hierarchy and mesh info
	print("[MMI2Interactable] Converting instance ", instance_index, " of layer '", layer.layer_name, "'")
	print("[MMI2Interactable] Instantiated scene structure:")
	_debug_print_scene_hierarchy(foliage_instance, "  ")

	var interactable_node: InteractableFoliage
	var scene_root_node: Node3D = null  # Track the actual scene root for transform

	# Wrap the scene in an InteractableFoliage node if needed
	if foliage_instance is InteractableFoliage:
		interactable_node = foliage_instance
		scene_root_node = foliage_instance  # The scene root IS the interactable
	else:
		interactable_node = InteractableFoliage.new()
		interactable_node.add_child(foliage_instance)
		scene_root_node = foliage_instance as Node3D  # The scene root is the child

	# Configure properties from layer BEFORE adding to scene
	interactable_node.foliage_type = layer.foliage_type_name
	interactable_node.health = layer.foliage_health
	interactable_node.max_health = layer.foliage_health
	interactable_node.respawn_time = layer.foliage_respawn_time
	interactable_node.harvest_items = layer.harvest_items.duplicate()
	interactable_node.harvest_experience = layer.harvest_experience

	# Configure physical drop properties
	interactable_node.drop_physical_items = layer.drop_physical_items
	interactable_node.physical_item_scene_path = layer.physical_item_scene_path
	interactable_node.physical_drop_count_min = layer.physical_drop_count_min
	interactable_node.physical_drop_count_max = layer.physical_drop_count_max
	interactable_node.scale_affects_drops = layer.scale_affects_drops
	interactable_node.drop_spread_radius = layer.drop_spread_radius

	# Check if the scene already has a collision shape - if so, don't add another one
	var existing_collision = _find_collision_shape(foliage_instance)
	if not existing_collision:
		# Only add collision if the scene has a collision shape defined
		if layer.cached_collision_shape:
			# Use the collision shape defined in the scene file
			var collision_shape = CollisionShape3D.new()
			collision_shape.shape = layer.cached_collision_shape
			collision_shape.transform = layer.cached_collision_transform
			interactable_node.add_child(collision_shape)

			# Add debug visualization if spawner has it enabled
			if foliage_spawner and foliage_spawner.debug_show_collision_shapes:
				var debug_mesh = _create_debug_collision_mesh(collision_shape)
				if debug_mesh:
					interactable_node.add_child(debug_mesh)
		else:
			print("WARNING: No collision shape found in scene for layer ", layer.layer_name)

	# CRITICAL FIX: Reset the scene root's transform to identity BEFORE adding to tree
	# The cached transforms already include the scene root's scale/rotation/position
	# If we don't reset it, we'll apply the scene's transform twice!
	if scene_root_node and scene_root_node != interactable_node:
		# The scene root is a child of the wrapper - reset its transform to identity
		scene_root_node.transform = Transform3D.IDENTITY

	# CRITICAL: Copy materials from ALL MMIs to match the MultiMesh appearance
	# Each MMI (trunk, leaves, etc.) has its own material_override for fading
	# We need to match the cached meshes with the scene's mesh instances
	_copy_materials_from_all_mmis(all_mmis, layer, scene_root_node if scene_root_node else interactable_node)

	# Add to scene FIRST
	get_tree().current_scene.add_child(interactable_node)

	# THEN set the world transform on the interactable wrapper
	# This transform already has everything baked in from the MultiMesh
	interactable_node.global_transform = world_transform

	# CRITICAL: Set original_scale AFTER adding to tree and setting the scale
	# This is needed for the scale-based drop calculation in _spawn_physical_drops()
	interactable_node.original_scale = interactable_node.scale

	# Store ALL MMIs for this layer (already found at the beginning of this function)
	active_all_mmis = all_mmis

	# Store references
	active_interactable = interactable_node
	active_source_mmi = mmi
	active_instance_index = instance_index
	active_layer = layer

	# Store original transforms from metadata (NOT from MMI, which might be corrupted/hidden!)
	# We need to store the MMI-relative transforms so we can restore them when unhovered
	active_original_transforms.clear()
	for mmi_to_hide in active_all_mmis:
		if mmi_to_hide.multimesh and instance_index < mmi_to_hide.multimesh.instance_count:
			# CRITICAL: Read the CURRENT transform from the MMI BEFORE we modify it
			# This is the actual transform being used for rendering
			var current_mmi_transform = mmi_to_hide.multimesh.get_instance_transform(instance_index)

			print("[DEBUG] Storing original transform for instance ", instance_index)
			print("[DEBUG]   Current MMI transform scale: ", current_mmi_transform.basis.get_scale())
			print("[DEBUG]   Current MMI transform origin: ", current_mmi_transform.origin)

			# Store the current transform (not from metadata, which might have different offsets applied!)
			active_original_transforms[mmi_to_hide] = current_mmi_transform
		else:
			push_warning("[MultiMeshToInteractable] Instance index out of bounds, cannot store transform")

	# Hide this instance in ALL MultiMeshes (trunk, leaves, etc.)
	for mmi_to_hide in active_all_mmis:
		_hide_multimesh_instance(mmi_to_hide, instance_index)

	# Connect to harvest signal
	interactable_node.interacted.connect(_on_interactable_harvested)

	return interactable_node


func _find_all_mmis_for_layer(source_mmi: MultiMeshInstance3D, layer: FoliageLayer) -> Array[MultiMeshInstance3D]:
	"""Find all MultiMeshInstance3D nodes for this layer (trunk, leaves, etc.)"""
	var all_mmis: Array[MultiMeshInstance3D] = []

	if not foliage_spawner:
		# Fallback: just return the one we have
		all_mmis.append(source_mmi)
		return all_mmis

	# Search through all loaded chunks to find MMIs for this layer
	for chunk_data in foliage_spawner.loaded_chunks.values():
		if chunk_data.layers.has(layer.layer_name):
			var layer_data = chunk_data.layers[layer.layer_name]
			# Check if our source_mmi is in this chunk's MMIs
			if source_mmi in layer_data.multimesh_instances:
				# Found it! Return ALL MMIs from this chunk's layer
				for mmi in layer_data.multimesh_instances:
					all_mmis.append(mmi)
				return all_mmis

	# Fallback: just return the one we have
	all_mmis.append(source_mmi)
	return all_mmis


func _hide_multimesh_instance(mmi: MultiMeshInstance3D, instance_index: int):
	"""Hide a specific instance in the MultiMesh by moving it far away"""
	if not mmi.multimesh or instance_index >= mmi.multimesh.instance_count:
		return

	# Get the original transform for this specific MMI
	if not active_original_transforms.has(mmi):
		print("[ERROR] No original transform stored for MMI!")
		return

	# Move the instance 10000 units down (underground) to hide it
	# This avoids the "determinant == 0" warning from using zero scale
	# IMPORTANT: Create a proper deep copy of the transform so we don't modify the original!
	var original = active_original_transforms[mmi]
	var hidden_transform = Transform3D()
	# Properly copy the basis by creating a new Basis from the original's components
	hidden_transform.basis = Basis(original.basis.x, original.basis.y, original.basis.z)
	hidden_transform.origin = Vector3(original.origin.x, original.origin.y - 10000.0, original.origin.z)

	print("[DEBUG] Hiding instance ", instance_index, " - Original Y: ", original.origin.y, " | Hidden Y: ", hidden_transform.origin.y)
	mmi.multimesh.set_instance_transform(instance_index, hidden_transform)


func _restore_multimesh_instance(mmi: MultiMeshInstance3D, instance_index: int, original_transform: Transform3D):
	"""Restore a hidden MultiMesh instance"""
	if not mmi.multimesh or instance_index >= mmi.multimesh.instance_count:
		return

	print("[DEBUG] Restoring instance ", instance_index)
	print("[DEBUG]   Original transform scale: ", original_transform.basis.get_scale())
	print("[DEBUG]   Original transform origin: ", original_transform.origin)

	mmi.multimesh.set_instance_transform(instance_index, original_transform)

	# Verify the restore worked
	var restored = mmi.multimesh.get_instance_transform(instance_index)
	print("[DEBUG]   After restore scale: ", restored.basis.get_scale())
	print("[DEBUG]   After restore origin: ", restored.origin)


func _disable_collision_for_instance(mmi: MultiMeshInstance3D, instance_index: int):
	"""Disable the collision shape for a specific instance (when harvested)"""
	if not is_instance_valid(mmi):
		return

	# Find the FoliageCollision Area3D
	var foliage_area = mmi.get_node_or_null("FoliageCollision")
	if not foliage_area:
		print("[DEBUG] No FoliageCollision found on MMI")
		return

	# Find and disable the collision shape for this instance
	for child in foliage_area.get_children():
		if child is CollisionShape3D:
			var shape_instance_index = child.get_meta("multimesh_instance_index", -1)
			if shape_instance_index == instance_index:
				print("[DEBUG] Disabling collision shape for instance ", instance_index)
				# Disable the collision shape instead of removing it
				# (removing causes issues with physics updates)
				child.disabled = true

				# Also hide any debug visualization
				var debug_mesh = foliage_area.get_node_or_null("DebugMesh_" + str(instance_index))
				if debug_mesh:
					debug_mesh.queue_free()

				return


func _cleanup_active_interactable(restore_multimesh: bool = true):
	"""Remove the active interactable and optionally restore the MultiMesh instance"""
	if not active_interactable:
		return

	print("[DEBUG] _cleanup_active_interactable called - restore:", restore_multimesh)

	# Check if the interactable was harvested
	var was_harvested = active_interactable.is_destroyed if is_instance_valid(active_interactable) else false
	print("[DEBUG] Was harvested:", was_harvested, " | Valid:", is_instance_valid(active_interactable))

	# Clean up the interactable node
	if is_instance_valid(active_interactable):
		active_interactable.queue_free()

	# Restore the MultiMesh instance ONLY if:
	# 1. It wasn't harvested
	# 2. We're told to restore it (not switching to another instance)
	if restore_multimesh and not was_harvested:
		print("[DEBUG] Restoring ", active_all_mmis.size(), " MMIs for instance ", active_instance_index)
		# Restore ALL MMIs (trunk, leaves, etc.) using their individual original transforms
		for mmi_to_restore in active_all_mmis:
			if is_instance_valid(mmi_to_restore) and active_original_transforms.has(mmi_to_restore):
				var original = active_original_transforms[mmi_to_restore]
				print("[DEBUG] Original transform for MMI: ", original.origin)
				_restore_multimesh_instance(mmi_to_restore, active_instance_index, original)
				print("[DEBUG] Restored MMI - new transform: ", mmi_to_restore.multimesh.get_instance_transform(active_instance_index).origin)

	active_interactable = null
	active_source_mmi = null
	active_all_mmis.clear()
	active_original_transforms.clear()
	active_instance_index = -1
	active_layer = null


func _on_interactable_harvested(_player):
	"""Called when the interactable is harvested"""
	# Don't restore the MultiMesh instance - it's been harvested
	# But we need to remove the collision shapes for this instance

	print("[DEBUG] Bush harvested - removing collision shapes for instance ", active_instance_index)

	# Remove collision shapes from ALL MMIs for this harvested instance
	for mmi in active_all_mmis:
		if is_instance_valid(mmi):
			_disable_collision_for_instance(mmi, active_instance_index)

	# Cleanup the interactable node
	if active_interactable and is_instance_valid(active_interactable):
		active_interactable.queue_free()

	active_interactable = null
	active_source_mmi = null
	active_all_mmis.clear()
	active_original_transforms.clear()
	active_instance_index = -1
	active_layer = null


func get_active_interactable() -> InteractableFoliage:
	"""Get the currently active interactable node"""
	return active_interactable


func _find_collision_shape(node: Node) -> CollisionShape3D:
	"""Recursively find the first CollisionShape3D node"""
	if node is CollisionShape3D:
		return node

	for child in node.get_children():
		var result = _find_collision_shape(child)
		if result:
			return result

	return null


func _fix_scene_materials(scene_root: Node, layer: FoliageLayer) -> void:
	"""Fix UV stretching by matching scene meshes with cached meshes by mesh data, not by order"""
	# Find all MeshInstance3D nodes in the scene
	var mesh_instances = _get_all_mesh_instances_recursive(scene_root)

	# Match each scene mesh with its corresponding cached mesh by comparing the mesh resource
	for scene_mesh_inst in mesh_instances:
		if not scene_mesh_inst.mesh:
			continue

		# Find the matching cached mesh by comparing mesh resources
		for i in range(layer.cached_meshes.size()):
			var cached_mesh = layer.cached_meshes[i]

			# Check if this is the same mesh (same resource)
			if scene_mesh_inst.mesh == cached_mesh:
				# Found a match! But we don't need to copy the material because
				# they're using the same mesh resource, which already has the correct material
				# The issue must be something else
				break


func _get_all_mesh_instances_recursive(node: Node) -> Array[MeshInstance3D]:
	"""Recursively find all MeshInstance3D nodes"""
	var result: Array[MeshInstance3D] = []

	if node is MeshInstance3D:
		result.append(node)

	for child in node.get_children():
		result.append_array(_get_all_mesh_instances_recursive(child))

	return result


func _debug_print_scene_hierarchy(node: Node, indent: String = "  ") -> void:
	"""Debug helper to print scene hierarchy"""
	print("[DEBUG] ", indent, node.get_class(), " | Name: ", node.name)
	if node is Node3D:
		var n3d = node as Node3D
		print("[DEBUG] ", indent, "  Transform: pos=", n3d.position, " rot=", n3d.rotation, " scale=", n3d.scale)
	if node is MeshInstance3D:
		var mesh_inst = node as MeshInstance3D
		if mesh_inst.mesh and mesh_inst.mesh.get_surface_count() > 0:
			var mat = mesh_inst.mesh.surface_get_material(0)
			print("[DEBUG] ", indent, "  Mesh surfaces: ", mesh_inst.mesh.get_surface_count())
			print("[DEBUG] ", indent, "  Material: ", mat.get_class() if mat else "None")
	for child in node.get_children():
		_debug_print_scene_hierarchy(child, indent + "  ")


func _create_debug_collision_mesh(collision_shape: CollisionShape3D) -> MeshInstance3D:
	"""Create a visible debug mesh for a collision shape"""
	if not collision_shape or not collision_shape.shape:
		return null

	var mesh_instance = MeshInstance3D.new()
	var shape = collision_shape.shape
	var debug_mesh: Mesh

	# Create appropriate debug mesh based on shape type
	if shape is SphereShape3D:
		var sphere = SphereMesh.new()
		sphere.radius = shape.radius
		sphere.height = shape.radius * 2.0
		debug_mesh = sphere
	elif shape is BoxShape3D:
		var box = BoxMesh.new()
		box.size = shape.size
		debug_mesh = box
	elif shape is CapsuleShape3D:
		var capsule = CapsuleMesh.new()
		capsule.radius = shape.radius
		capsule.height = shape.height
		debug_mesh = capsule
	else:
		return null

	mesh_instance.mesh = debug_mesh
	mesh_instance.position = collision_shape.position
	mesh_instance.rotation = collision_shape.rotation
	mesh_instance.scale = collision_shape.scale  # Apply the same scale as the collision shape

	# Create wireframe material for visibility
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 0, 0.5)  # Red semi-transparent (to distinguish from MultiMesh debug)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	mat.no_depth_test = true  # Show through objects
	mesh_instance.material_override = mat

	return mesh_instance


func _copy_materials_from_all_mmis(all_mmis: Array[MultiMeshInstance3D], layer: FoliageLayer, target_node: Node3D) -> void:
	"""Copy material overrides from all MMIs to match their corresponding meshes in the scene"""
	if not is_instance_valid(target_node):
		return

	print("[MMI2Interactable] Copying materials from ", all_mmis.size(), " MMIs to interactable")

	# Get all mesh instances in the target scene
	var scene_mesh_instances = _get_all_mesh_instances_recursive(target_node)
	print("[MMI2Interactable]   Found ", scene_mesh_instances.size(), " mesh instances in scene")

	# Match each MMI with its corresponding scene mesh by comparing with cached meshes
	for i in range(min(all_mmis.size(), layer.cached_meshes.size())):
		var source_mmi = all_mmis[i]
		var cached_mesh = layer.cached_meshes[i]

		if not is_instance_valid(source_mmi):
			continue

		# Find the scene mesh instance that uses this cached mesh
		for scene_mesh_inst in scene_mesh_instances:
			if scene_mesh_inst.mesh == cached_mesh:
				print("[MMI2Interactable]   Matching MMI[", i, "] to scene mesh '", scene_mesh_inst.name, "'")

				# Copy material override from this specific MMI
				if source_mmi.material_override:
					# CRITICAL: Duplicate to avoid sharing state
					var duplicated_material = source_mmi.material_override.duplicate()
					print("[MMI2Interactable]     Applying material override: ", duplicated_material.get_class())
					scene_mesh_inst.material_override = duplicated_material
				else:
					print("[MMI2Interactable]     No material override, using mesh default")
				break


func convert_to_interactable(hit_data: Dictionary) -> InteractableFoliage:
	"""
	Convert a MultiMesh instance to an InteractableFoliage node.

	hit_data should contain:
	- mmi: MultiMeshInstance3D
	- instance_index: int
	- layer: FoliageLayer
	- position: Vector3 (optional, for distance calculation)
	"""
	if not hit_data.has("mmi") or not hit_data.has("instance_index") or not hit_data.has("layer"):
		return null

	var mmi: MultiMeshInstance3D = hit_data["mmi"]
	var instance_index: int = hit_data["instance_index"]
	var layer: FoliageLayer = hit_data["layer"]

	# Check if this is the same instance we already have active
	if active_interactable and active_source_mmi == mmi and active_instance_index == instance_index:
		return active_interactable

	# Different instance - cleanup old one WITH restore (so it doesn't stay hidden)
	# When switching between overlapping bushes, we need to restore the previous one
	_cleanup_active_interactable(true)

	# Check if layer is interactable
	if not layer.is_interactable:
		return null

	# Convert this specific instance to an interactable node
	return _convert_instance_to_interactable(mmi, instance_index, layer)
