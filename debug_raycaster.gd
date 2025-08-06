# debug_raycaster.gd - Temporary debug version of InteractionRaycaster
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
	print("Raycaster setup - distance: ", distance, " layer: ", layer)

func _find_camera_reference():
	var player = get_parent().get_parent()
	if player and player.has_node("CameraPivot/Camera3D"):
		camera = player.get_node("CameraPivot/Camera3D")
		print("Camera found: ", camera)
	else:
		print("Camera NOT found!")

func update_raycast():
	if not camera:
		return
	
	space_state = get_viewport().world_3d.direct_space_state
	if not space_state:
		return
	
	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * raycast_distance)
	
	# DEBUG: Print raycast info every few frames
	if Engine.get_process_frames() % 60 == 0:  # Every second at 60 FPS
		print("Raycasting from: ", from, " to: ", to)
		print("Direction: ", -camera.global_transform.basis.z)
	
	# Get all objects that need to be excluded
	var exclude_objects = []
	exclude_objects.append(get_parent().get_parent())  # Player
	
	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = 1 << (raycast_layer - 1)  # Only layer 2
	query.exclude = exclude_objects
	
	var result = space_state.intersect_ray(query)
	
	# DEBUG: Print what we hit
	if result.has("collider"):
		if Engine.get_process_frames() % 60 == 0:
			print("Hit something: ", result.collider.name, " at: ", result.position)
			print("Collider type: ", result.collider.get_class())
			print("Collider collision_layer: ", result.collider.collision_layer)
	
	_process_raycast_result(result)

func _process_raycast_result(result: Dictionary):
	var hit_interactable: Interactable = null
	
	if result.has("collider"):
		var collider = result.collider
		print("Processing hit on: ", collider.name)
		if collider is Node:
			hit_interactable = _find_interactable_in_hierarchy(collider)
			if hit_interactable:
				print("Found interactable: ", hit_interactable.name)
			else:
				print("No interactable found in hierarchy")
	
	if hit_interactable != current_interactable:
		if current_interactable:
			current_interactable.end_hover()
			interactable_lost.emit()
			print("Lost interactable: ", current_interactable.name)
		
		current_interactable = hit_interactable
		if current_interactable and current_interactable.can_interact():
			current_interactable.start_hover()
			interactable_detected.emit(current_interactable)
			print("Detected interactable: ", current_interactable.name)
		else:
			current_interactable = null

func _find_interactable_in_hierarchy(node: Node) -> Interactable:
	print("Searching for interactable in: ", node.name)
	
	if node is Interactable:
		print("Found interactable directly: ", node.name)
		return node
	
	# Check children
	for child in node.get_children():
		if child is Interactable:
			print("Found interactable in children: ", child.name)
			return child
	
	# Check parent
	var parent = node.get_parent()
	var depth = 0
	while parent and depth < 3:
		if parent is Interactable:
			print("Found interactable in parent: ", parent.name)
			return parent
		parent = parent.get_parent()
		depth += 1
	
	print("No interactable found in hierarchy for: ", node.name)
	return null

# Public interface
func get_current_interactable() -> Interactable:
	return current_interactable