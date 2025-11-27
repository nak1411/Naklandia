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

	# Find ALL MMIs for this layer FIRST to get consistent transform
	var all_mmis = _find_all_mmis_for_layer(mmi, layer)

	# IMPORTANT: Use the FIRST MMI's transform as the reference point
	# This ensures consistent positioning regardless of which mesh part was hit
	var reference_mmi = all_mmis[0] if all_mmis.size() > 0 else mmi
	print("[DEBUG] Hit MMI: ", mmi.name, " | Using reference MMI: ", reference_mmi.name, " | Total MMIs: ", all_mmis.size())

	# Get the transform of this specific instance (relative to reference MMI)
	var instance_transform = reference_mmi.multimesh.get_instance_transform(instance_index)

	# CRITICAL: The instance_transform includes a mesh-specific local offset that was applied
	# in ProceduralFoliageSpawner at line 744: final_transform = relative_transform * local_offset
	# We need to REMOVE this local offset to get back to the base item transform
	# The local offset is stored in layer.cached_mesh_transforms[0] for the reference MMI
	var reference_local_offset = layer.cached_mesh_transforms[0] if layer.cached_mesh_transforms.size() > 0 else Transform3D.IDENTITY

	# IMPORTANT: Extract the scale BEFORE removing the local offset
	# The instance_transform contains the randomized scale we need to preserve
	var original_scale = instance_transform.basis.get_scale()

	# Create a transform from instance_transform but with scale normalized
	var instance_no_scale = Transform3D()
	instance_no_scale.origin = instance_transform.origin
	instance_no_scale.basis = instance_transform.basis.orthonormalized()

	# Create a local offset without scale (only position and rotation)
	var local_offset_no_scale = Transform3D()
	local_offset_no_scale.origin = reference_local_offset.origin
	local_offset_no_scale.basis = reference_local_offset.basis.orthonormalized()

	# Remove the local offset from the position/rotation
	var base_transform_no_scale = instance_no_scale * local_offset_no_scale.inverse()

	# Now create the final base_transform with the original scale applied
	var base_transform = Transform3D()
	base_transform.origin = base_transform_no_scale.origin
	base_transform.basis = base_transform_no_scale.basis.scaled(original_scale)

	print("[DEBUG] Instance transform origin: ", instance_transform.origin)
	print("[DEBUG] Instance transform basis scale: ", instance_transform.basis.get_scale())
	print("[DEBUG] Original scale from MMI: ", original_scale)
	print("[DEBUG] Local offset: ", reference_local_offset.origin)
	print("[DEBUG] Base transform origin: ", base_transform.origin)
	print("[DEBUG] Base transform basis scale: ", base_transform.basis.get_scale())

	# Convert to world space using reference MMI position and base transform
	var world_transform = reference_mmi.global_transform * base_transform

	# Create the interactable node
	print("[DEBUG] Converting MMI to interactable - Layer: ", layer.layer_name, " | Scene: ", layer.scene_path)
	print("[DEBUG] Layer has ", layer.cached_meshes.size(), " cached meshes")
	var foliage_instance = layer.scene.instantiate()
	var interactable_node: InteractableFoliage

	# Get the default scale of the scene before we modify it
	var scene_default_scale = Vector3.ONE
	if foliage_instance is InteractableFoliage:
		interactable_node = foliage_instance
		scene_default_scale = interactable_node.scale
	else:
		interactable_node = InteractableFoliage.new()
		scene_default_scale = foliage_instance.scale if foliage_instance is Node3D else Vector3.ONE
		interactable_node.add_child(foliage_instance)

	print("[DEBUG] Scene default scale: ", scene_default_scale, " | MultiMesh scale: ", instance_transform.basis.get_scale())

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

	# Add to scene FIRST
	get_tree().current_scene.add_child(interactable_node)

	# THEN set position, rotation, and scale using the transform directly
	# Extract rotation basis without scale (orthonormalized)
	var rotation_basis = world_transform.basis.orthonormalized()

	# Set position
	interactable_node.global_position = world_transform.origin

	# Apply scale and rotation together to avoid overwriting
	# The MMI scale is already the absolute final scale we want
	# The scene has a base scale of 0.1, but the MMI scale already accounts for this
	var multimesh_scale = original_scale
	var adjusted_scale = multimesh_scale / scene_default_scale

	# IMPORTANT: Apply scale to the rotation basis BEFORE setting it
	# Otherwise setting global_transform.basis will overwrite the scale we just set!
	var scaled_rotation_basis = rotation_basis.scaled(adjusted_scale)
	interactable_node.global_transform.basis = scaled_rotation_basis

	print("[DEBUG] MultiMesh scale: ", multimesh_scale, " | Scene default: ", scene_default_scale, " | Adjusted: ", adjusted_scale)
	print("[DEBUG] After setting scale - Node scale: ", interactable_node.scale, " | Global scale: ", interactable_node.global_transform.basis.get_scale())

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
	active_original_transforms.clear()
	for mmi_to_hide in active_all_mmis:
		if mmi_to_hide.multimesh and instance_index < mmi_to_hide.multimesh.instance_count:
			# Get the ORIGINAL transform from metadata, not from the MMI
			var item_transforms: Array = mmi_to_hide.get_meta("item_transforms", [])
			if instance_index < item_transforms.size():
				# Convert world-space transform to MMI-relative transform
				var item_world_transform = item_transforms[instance_index]
				var mmi_relative = Transform3D()
				mmi_relative.origin = item_world_transform.origin - mmi_to_hide.global_position
				mmi_relative.basis = item_world_transform.basis

				# Apply local mesh offset (same as in ProceduralFoliageSpawner)
				var mesh_idx = active_all_mmis.find(mmi_to_hide)
				if mesh_idx >= 0 and mesh_idx < layer.cached_mesh_transforms.size():
					var local_transform = layer.cached_mesh_transforms[mesh_idx]
					var local_offset = Transform3D()
					local_offset.origin = local_transform.origin
					local_offset.basis = local_transform.basis.orthonormalized()
					mmi_relative = mmi_relative * local_offset

				active_original_transforms[mmi_to_hide] = mmi_relative
			else:
				# Fallback: read from MMI (might be wrong if already hidden!)
				active_original_transforms[mmi_to_hide] = mmi_to_hide.multimesh.get_instance_transform(instance_index)

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
	hidden_transform.basis = original.basis
	hidden_transform.origin = original.origin
	hidden_transform.origin.y -= 10000.0  # Move underground

	print("[DEBUG] Hiding instance ", instance_index, " - Original Y: ", original.origin.y, " | Hidden Y: ", hidden_transform.origin.y)
	mmi.multimesh.set_instance_transform(instance_index, hidden_transform)


func _restore_multimesh_instance(mmi: MultiMeshInstance3D, instance_index: int, original_transform: Transform3D):
	"""Restore a hidden MultiMesh instance"""
	if not mmi.multimesh or instance_index >= mmi.multimesh.instance_count:
		return

	mmi.multimesh.set_instance_transform(instance_index, original_transform)


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
