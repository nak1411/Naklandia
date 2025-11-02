class_name GizmoDragger
extends Node

## Handles dragging objects using transform gizmos.
## Calculates mouse-to-world-axis movement for precise manipulation.

var is_dragging: bool = false
var drag_axis: Vector3 = Vector3.ZERO  # Which axis we're dragging (e.g., Vector3.RIGHT for X)
var drag_start_mouse: Vector2
var drag_start_positions: Dictionary = {}  # PhysicalItem -> Vector3 (starting position)
var camera: Camera3D


func start_drag(axis: Vector3, mouse_pos: Vector2, items: Array[PhysicalItem], cam: Camera3D) -> void:
	"""Start dragging items along the specified axis."""
	is_dragging = true
	drag_axis = axis.normalized()
	drag_start_mouse = mouse_pos
	camera = cam

	# Store starting positions
	drag_start_positions.clear()
	for item in items:
		drag_start_positions[item] = item.global_position


func update_drag(mouse_pos: Vector2) -> void:
	"""Update item positions based on mouse movement."""
	if not is_dragging or not camera:
		return

	var delta = mouse_pos - drag_start_mouse

	# Convert screen-space delta to world-space movement along the drag axis
	var movement = _calculate_axis_movement(delta)

	# Apply movement to all dragged items
	for item in drag_start_positions.keys():
		if item:
			item.global_position = drag_start_positions[item] + drag_axis * movement


func end_drag() -> void:
	"""Stop dragging."""
	is_dragging = false
	drag_start_positions.clear()


func _calculate_axis_movement(screen_delta: Vector2) -> float:
	"""Convert screen-space mouse delta to world-space movement along drag axis."""
	if not camera:
		return 0.0

	# Simple approximation: project screen delta onto axis
	# This works reasonably well for most cases
	var axis_on_screen = _get_axis_screen_direction()

	# Dot product to get movement along axis
	var movement = screen_delta.dot(axis_on_screen) * 0.01

	return movement


func _get_axis_screen_direction() -> Vector2:
	"""Get the screen-space direction of the drag axis."""
	if not camera:
		return Vector2.ZERO

	# Get a point along the axis in world space
	var origin = Vector3.ZERO
	var point_on_axis = drag_axis

	# Project to screen
	var origin_screen = camera.unproject_position(origin)
	var axis_screen = camera.unproject_position(point_on_axis)

	# Get direction in screen space
	return (axis_screen - origin_screen).normalized()
