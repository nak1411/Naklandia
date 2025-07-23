# InteractionRaycaster.gd - Clean production version
extends Node

# Raycast settings
var raycast_distance: float = 5.0
var raycast_layer: int = 2

# References
var camera: Camera3D
var space_state: PhysicsDirectSpaceState3D
var current_interactable: Interactable

# Signals
signal interactable_detected(interactable: Interactable)
signal interactable_lost()

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
	
	# Get all objects that need to be excluded
	var exclude_objects = []
	exclude_objects.append(get_parent().get_parent())  # Player
	
	# Find and exclude floor/ground objects on layer 1
	var scene_root = get_tree().current_scene
	_find_and_exclude_floors(scene_root, exclude_objects)
	
	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = 1 << (raycast_layer - 1)  # Only layer 2
	query.exclude = exclude_objects
	
	var result = space_state.intersect_ray(query)
	_process_raycast_result(result)

func _find_and_exclude_floors(node: Node, exclude_list: Array):
	# Exclude any StaticBody3D that might be floor/walls
	if node is StaticBody3D and node.collision_layer == 1:
		exclude_list.append(node)
	
	for child in node.get_children():
		_find_and_exclude_floors(child, exclude_list)

func _process_raycast_result(result: Dictionary):
	var hit_interactable: Interactable = null
	
	if result.has("collider"):
		var collider = result.collider
		if collider is Node:
			hit_interactable = _find_interactable_in_hierarchy(collider)
	
	if hit_interactable != current_interactable:
		if current_interactable:
			current_interactable.end_hover()
			interactable_lost.emit()
		
		current_interactable = hit_interactable
		if current_interactable and current_interactable.can_interact():
			current_interactable.start_hover()
			interactable_detected.emit(current_interactable)
		else:
			current_interactable = null

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

func force_clear_interactable():
	if current_interactable:
		current_interactable.end_hover()
		current_interactable = null
		interactable_lost.emit()
