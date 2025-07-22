# InteractionRaycaster.gd - Handles raycast detection for interactions
class_name InteractionRaycaster
extends Node

# Raycast settings
var raycast_distance: float = 3.0
var raycast_layer: int = 1
var debug_draw: bool = false

# References
var camera: Camera3D
var space_state: PhysicsDirectSpaceState3D
var current_interactable: Interactable

# Signals
signal interactable_detected(interactable: Interactable)
signal interactable_lost()

func _ready():
	# Find camera reference
	_find_camera_reference()

func setup_raycaster(distance: float, layer: int):
	raycast_distance = distance
	raycast_layer = layer

func _find_camera_reference():
	# Look for camera in player
	var player = get_parent().get_parent()  # InteractionSystem -> Player
	if player and player.has_node("CameraPivot/Camera3D"):
		camera = player.get_node("CameraPivot/Camera3D")
	else:
		print("Warning: Could not find camera for interaction raycaster")

func update_raycast():
	if not camera:
		return
	
	# Get the space state
	space_state = get_viewport().world_3d.direct_space_state
	if not space_state:
		return
	
	# Perform raycast from camera center
	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * raycast_distance)
	
	# Setup raycast query
	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = 1 << (raycast_layer - 1)  # Convert to bit mask
	query.exclude = [get_parent().get_parent()]  # Exclude player
	
	# Perform raycast
	var result = space_state.intersect_ray(query)
	
	# Process result
	_process_raycast_result(result)
	
	# Debug visualization
	if debug_draw:
		_draw_debug_ray(from, to, result.has("collider"))

func _process_raycast_result(result: Dictionary):
	var hit_interactable: Interactable = null
	
	if result.has("collider"):
		var collider = result.collider
		
		# Check if the collider or its parent is an Interactable
		hit_interactable = _find_interactable_in_hierarchy(collider)
	
	# Handle interactable state changes
	if hit_interactable != current_interactable:
		# Lost previous interactable
		if current_interactable:
			current_interactable.end_hover()
			interactable_lost.emit()
		
		# Found new interactable
		current_interactable = hit_interactable
		if current_interactable and current_interactable.can_interact():
			current_interactable.start_hover()
			interactable_detected.emit(current_interactable)
		else:
			current_interactable = null

func _find_interactable_in_hierarchy(node: Node) -> Interactable:
	# Check if the node itself is an Interactable
	if node is Interactable:
		return node
	
	# Check parent nodes
	var parent = node.get_parent()
	while parent:
		if parent is Interactable:
			return parent
		parent = parent.get_parent()
	
	return null

func _draw_debug_ray(from: Vector3, to: Vector3, hit: bool):
	# This would require a debug drawing system
	# For now, we'll use print statements for debugging
	if debug_draw:
		var color = Color.GREEN if hit else Color.RED
		print("Debug Ray: ", from, " -> ", to, " Hit: ", hit)

# Public interface
func set_raycast_distance(distance: float):
	raycast_distance = distance

func set_raycast_layer(layer: int):
	raycast_layer = layer

func set_debug_draw(enabled: bool):
	debug_draw = enabled

func get_current_interactable() -> Interactable:
	return current_interactable

func force_clear_interactable():
	if current_interactable:
		current_interactable.end_hover()
		current_interactable = null
		interactable_lost.emit()
