# InteractionRaycaster.gd - Enhanced with distance tracking
extends Node

# Signals
signal interactable_detected(interactable: Interactable, distance: float)
signal interactable_lost

# Raycast settings
var raycast_distance: float = 5.0
var raycast_layer: int = 2

# References
var camera: Camera3D
var space_state: PhysicsDirectSpaceState3D
var current_interactable: Interactable
var current_distance: float = 0.0
var multimesh_converter: MultiMeshToInteractable = null


func _ready():
	_find_camera_reference()


func setup_raycaster(distance: float, layer: int):
	raycast_distance = distance
	raycast_layer = layer


func _find_camera_reference():
	var player = get_parent().get_parent()
	if player and player.has_node("CameraPivot/Camera3D"):
		camera = player.get_node("CameraPivot/Camera3D")


func update_raycast():
	if not camera:
		return

	space_state = get_viewport().world_3d.direct_space_state
	if not space_state:
		return

	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * raycast_distance)

	# Use physics raycast for ALL interactables
	var exclude_objects = []
	exclude_objects.append(get_parent().get_parent())  # Player

	# Find and exclude floor/ground objects on layer 1
	var scene_root = get_tree().current_scene
	_find_and_exclude_floors(scene_root, exclude_objects)

	# IMPORTANT: Exclude Terrain3D so it doesn't block foliage raycasts
	var terrain = get_tree().get_first_node_in_group("terrain")
	if terrain:
		exclude_objects.append(terrain)

	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = 1 << (raycast_layer - 1)  # Only layer 2
	query.collide_with_areas = true  # IMPORTANT: Allow raycasts to hit Area3D nodes
	query.collide_with_bodies = true
	query.exclude = exclude_objects

	var result = space_state.intersect_ray(query)
	_process_raycast_result(result, from)


func _find_and_exclude_floors(node: Node, exclude_list: Array):
	# Exclude any StaticBody3D that might be floor/walls
	if node is StaticBody3D and node.collision_layer == 1:
		exclude_list.append(node)

	for child in node.get_children():
		_find_and_exclude_floors(child, exclude_list)


func _process_raycast_result(result: Dictionary, ray_origin: Vector3):
	var hit_interactable: Interactable = null
	var hit_distance: float = 0.0

	if result.has("collider"):
		var collider = result.collider

		if collider is Node:
			# Check if this is MultiMesh foliage collision (using Area3D)
			if collider is Area3D and collider.name == "FoliageCollision" and collider.get_parent() is MultiMeshInstance3D:
				# This is MultiMesh foliage - convert to interactable on-hover
				hit_interactable = _convert_multimesh_to_interactable(result, collider)
				if hit_interactable and result.has("position"):
					hit_distance = ray_origin.distance_to(result.position)
			else:
				# Regular interactable
				hit_interactable = _find_interactable_in_hierarchy(collider)
				if hit_interactable and result.has("position"):
					hit_distance = ray_origin.distance_to(result.position)

	if hit_interactable != current_interactable:
		if current_interactable:
			current_interactable.end_hover()
			interactable_lost.emit()

			# If we're switching away from a MultiMesh-converted foliage, clean it up WITH restore
			if current_interactable is InteractableFoliage and multimesh_converter:
				var converter_active = multimesh_converter.get_active_interactable()
				if converter_active == current_interactable:
					multimesh_converter._cleanup_active_interactable(true)

		current_interactable = hit_interactable
		current_distance = hit_distance

		if current_interactable and current_interactable.can_interact():
			current_interactable.start_hover()
			interactable_detected.emit(current_interactable, hit_distance)
		else:
			current_interactable = null
			current_distance = 0.0
	elif current_interactable:
		# Update distance for existing interactable
		current_distance = hit_distance


func _find_interactable_in_hierarchy(node: Node) -> Interactable:
	if node is Interactable:
		return node

	var parent = node.get_parent()
	var depth = 0
	while parent and depth < 3:
		if parent is Interactable:
			return parent
		parent = parent.get_parent()
		depth += 1

	return null


# Public interface
func set_raycast_distance(distance: float):
	raycast_distance = distance


func set_raycast_layer(layer: int):
	raycast_layer = layer


func get_current_interactable() -> Interactable:
	return current_interactable


func get_current_distance() -> float:
	return current_distance


func force_clear_interactable():
	if current_interactable:
		current_interactable.end_hover()
		current_interactable = null
		current_distance = 0.0
		interactable_lost.emit()


func _convert_multimesh_to_interactable(raycast_result: Dictionary, foliage_area: Area3D) -> Interactable:
	"""Convert a MultiMesh instance to an interactable foliage node on-hover"""
	# Lazy-load the converter
	if not multimesh_converter:
		var converters = get_tree().get_nodes_in_group("multimesh_converter")
		if converters.size() > 0:
			multimesh_converter = converters[0]
		else:
			# Create one if it doesn't exist
			var spawners = get_tree().get_nodes_in_group("foliage_spawner")
			if spawners.size() > 0:
				multimesh_converter = MultiMeshToInteractable.new()
				multimesh_converter.add_to_group("multimesh_converter")
				spawners[0].add_child(multimesh_converter)

	if not multimesh_converter:
		return null

	# Get the MMI that was hit
	var mmi = foliage_area.get_parent() as MultiMeshInstance3D
	if not mmi:
		return null

	var hit_position = raycast_result.get("position", Vector3.ZERO)

	# Find the closest collision shape to the hit position
	var collision_shape: CollisionShape3D = null
	var closest_distance = 999999.0

	for child in foliage_area.get_children():
		if child is CollisionShape3D:
			var child_global_pos = foliage_area.global_position + child.position
			var distance = hit_position.distance_to(child_global_pos)
			if distance < closest_distance:
				closest_distance = distance
				collision_shape = child

	if not collision_shape:
		return null

	# Get metadata
	var instance_index = collision_shape.get_meta("multimesh_instance_index", -1)
	var layer: FoliageLayer = collision_shape.get_meta("foliage_layer", null)

	if instance_index < 0 or not layer:
		return null

	# Use the converter to create/get the interactable
	return multimesh_converter.convert_to_interactable({"mmi": mmi, "instance_index": instance_index, "layer": layer, "position": raycast_result.get("position", Vector3.ZERO)})
