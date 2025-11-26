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
var active_original_transform: Transform3D  # Store original transform for restoration

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

	# Get the transform of this specific instance (relative to MMI)
	var instance_transform = mmi.multimesh.get_instance_transform(instance_index)

	# IMPORTANT: Store original transform BEFORE hiding
	active_original_transform = instance_transform

	# Convert to world space
	var world_transform = mmi.global_transform * instance_transform

	# Create the interactable node
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

	# THEN set position and rotation
	interactable_node.global_position = world_transform.origin
	interactable_node.global_rotation = world_transform.basis.get_euler()

	# Apply scale - the MultiMesh scale needs to be adjusted for the scene's base scale
	# If scene is 0.1 and MultiMesh is 0.163, we want final scale of 0.163
	# So we need to set node scale to: 0.163 / 0.1 = 1.63
	var multimesh_scale = instance_transform.basis.get_scale()
	var adjusted_scale = multimesh_scale / scene_default_scale
	interactable_node.scale = adjusted_scale

	print("[DEBUG] MultiMesh scale: ", multimesh_scale, " | Scene default: ", scene_default_scale, " | Adjusted: ", adjusted_scale)

	# Find ALL MMIs for this layer (trunk, leaves, etc.) by checking the spawner
	active_all_mmis = _find_all_mmis_for_layer(mmi, layer)

	# Store references
	active_interactable = interactable_node
	active_source_mmi = mmi
	active_instance_index = instance_index
	active_layer = layer

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

	# Move the instance 10000 units down (underground) to hide it
	# This avoids the "determinant == 0" warning from using zero scale
	# IMPORTANT: Make a copy of the transform so we don't modify the original!
	var hidden_transform = Transform3D(active_original_transform)
	hidden_transform.origin.y -= 10000.0  # Move underground
	mmi.multimesh.set_instance_transform(instance_index, hidden_transform)


func _restore_multimesh_instance(mmi: MultiMeshInstance3D, instance_index: int, original_transform: Transform3D):
	"""Restore a hidden MultiMesh instance"""
	if not mmi.multimesh or instance_index >= mmi.multimesh.instance_count:
		return

	mmi.multimesh.set_instance_transform(instance_index, original_transform)


func _cleanup_active_interactable(restore_multimesh: bool = true):
	"""Remove the active interactable and optionally restore the MultiMesh instance"""
	if not active_interactable:
		return

	# Check if the interactable was harvested
	var was_harvested = active_interactable.is_destroyed if is_instance_valid(active_interactable) else false

	# Clean up the interactable node
	if is_instance_valid(active_interactable):
		active_interactable.queue_free()

	# Restore the MultiMesh instance ONLY if:
	# 1. It wasn't harvested
	# 2. We're told to restore it (not switching to another instance)
	if restore_multimesh and not was_harvested:
		# Restore ALL MMIs (trunk, leaves, etc.)
		for mmi_to_restore in active_all_mmis:
			if is_instance_valid(mmi_to_restore):
				_restore_multimesh_instance(mmi_to_restore, active_instance_index, active_original_transform)

	active_interactable = null
	active_source_mmi = null
	active_all_mmis.clear()
	active_instance_index = -1
	active_layer = null


func _on_interactable_harvested(_player):
	"""Called when the interactable is harvested"""
	# Don't restore the MultiMesh instance - it's been harvested
	# Just cleanup the interactable node
	if active_interactable and is_instance_valid(active_interactable):
		active_interactable.queue_free()

	active_interactable = null
	active_source_mmi = null
	active_all_mmis.clear()
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

	# Different instance - cleanup old one WITHOUT restoring (we're about to create a new one)
	_cleanup_active_interactable(false)

	# Check if layer is interactable
	if not layer.is_interactable:
		return null

	# Convert this specific instance to an interactable node
	return _convert_instance_to_interactable(mmi, instance_index, layer)
