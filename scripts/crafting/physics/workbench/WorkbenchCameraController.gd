class_name WorkbenchCameraController
extends RefCounted

## Manages camera movement and orbit controls for the workbench.
##
## Provides Blender/Maya-style camera controls:
## - Alt + Left Mouse: Orbit camera
## - Alt + Middle Mouse: Pan camera
## - Alt + Right Mouse: Zoom camera
## - F: Frame selection

signal camera_moved(new_position: Vector3, new_rotation: Vector2)
signal camera_framed

# Camera state
var camera: Camera3D
var viewport: SubViewport
var camera_distance: float = 5.0
var camera_rotation: Vector2 = Vector2(-45, 30)  # Yaw, Pitch
var camera_target: Vector3 = Vector3.ZERO

# Input state
var is_alt_held: bool = false
var is_dragging: bool = false
var drag_button: int = -1
var last_mouse_pos: Vector2


func _init(p_camera: Camera3D, p_viewport: SubViewport) -> void:
	"""Initialize the camera controller with a camera reference."""
	camera = p_camera
	viewport = p_viewport
	update_transform()


func set_target(target_pos: Vector3) -> void:
	"""Set the camera's orbit target point."""
	camera_target = target_pos
	update_transform()


func set_distance(distance: float) -> void:
	"""Set the camera's distance from target."""
	camera_distance = max(0.5, distance)
	update_transform()


func set_rotation(rotation: Vector2) -> void:
	"""Set the camera's rotation (yaw, pitch in degrees)."""
	camera_rotation = rotation
	# Clamp pitch to prevent camera from going through floor
	var min_pitch = _calculate_min_pitch_for_target()
	camera_rotation.y = clamp(camera_rotation.y, min_pitch, 89.0)
	update_transform()


func update_transform() -> void:
	"""Update camera position based on orbit controls."""
	if not camera:
		return

	# Clamp pitch to prevent camera from going through floor
	var min_pitch = _calculate_min_pitch_for_target()
	camera_rotation.y = clamp(camera_rotation.y, min_pitch, 89.0)

	# Convert rotation to radians
	var yaw_rad = deg_to_rad(camera_rotation.x)
	var pitch_rad = deg_to_rad(camera_rotation.y)

	# Calculate camera position
	var offset = Vector3(cos(pitch_rad) * sin(yaw_rad), sin(pitch_rad), cos(pitch_rad) * cos(yaw_rad)) * camera_distance

	camera.global_position = camera_target + offset
	camera.look_at(camera_target, Vector3.UP)

	camera_moved.emit(camera.global_position, camera_rotation)


func handle_orbit(mouse_delta: Vector2, sensitivity: float = 0.3) -> void:
	"""Handle camera orbit (Alt + Left Mouse)."""
	camera_rotation.x -= mouse_delta.x * sensitivity
	camera_rotation.y += mouse_delta.y * sensitivity

	# Clamp pitch
	var min_pitch = _calculate_min_pitch_for_target()
	camera_rotation.y = clamp(camera_rotation.y, min_pitch, 89.0)

	update_transform()


func handle_pan(mouse_delta: Vector2, sensitivity: float = 0.001) -> void:
	"""Handle camera pan (Alt + Middle Mouse)."""
	if not camera:
		return

	# Get camera's right and up vectors
	var right = camera.global_transform.basis.x
	var up = camera.global_transform.basis.y

	# Move target based on mouse delta
	camera_target -= right * mouse_delta.x * sensitivity * camera_distance
	camera_target += up * mouse_delta.y * sensitivity * camera_distance

	update_transform()


func handle_zoom(mouse_delta: Vector2, sensitivity: float = 0.01) -> void:
	"""Handle camera zoom (Alt + Right Mouse or scroll wheel)."""
	camera_distance += mouse_delta.y * sensitivity * camera_distance
	camera_distance = clamp(camera_distance, 0.5, 100.0)
	update_transform()


func handle_scroll_zoom(scroll_delta: float, sensitivity: float = 0.1) -> void:
	"""Handle mouse wheel zoom."""
	camera_distance *= (1.0 + scroll_delta * sensitivity)
	camera_distance = clamp(camera_distance, 0.5, 100.0)
	update_transform()


func frame_objects(objects: Array) -> void:
	"""Frame the given objects in view and zoom to fit them (F key)."""
	if objects.is_empty():
		return

	# Calculate bounding box of selection
	var min_pos = Vector3(INF, INF, INF)
	var max_pos = Vector3(-INF, -INF, -INF)

	for item in objects:
		var pos = item.global_position
		min_pos.x = min(min_pos.x, pos.x)
		min_pos.y = min(min_pos.y, pos.y)
		min_pos.z = min(min_pos.z, pos.z)
		max_pos.x = max(max_pos.x, pos.x)
		max_pos.y = max(max_pos.y, pos.y)
		max_pos.z = max(max_pos.z, pos.z)

	# Calculate center and extents
	var center = (min_pos + max_pos) / 2.0
	var extents = (max_pos - min_pos) / 2.0

	# Set camera target to center
	camera_target = center

	# Zoom to extents: Calculate proper distance to fit all objects in view
	if camera and viewport:
		var fov_rad = deg_to_rad(camera.fov)
		var aspect = float(viewport.size.x) / float(viewport.size.y) if viewport.size.y > 0 else 1.0

		# Calculate the bounding sphere radius (diagonal)
		var radius = extents.length()

		# For very small objects, use a minimum radius
		if radius < 0.5:
			radius = 0.5

		# Calculate distance needed for vertical FOV to fit bounding sphere
		var vertical_distance = radius / tan(fov_rad / 2.0)

		# Calculate distance needed for horizontal FOV
		var horizontal_fov = 2.0 * atan(tan(fov_rad / 2.0) * aspect)
		var horizontal_distance = radius / tan(horizontal_fov / 2.0)

		# Use the larger distance to ensure everything fits
		# Reduce padding to 20% for tighter framing
		camera_distance = max(vertical_distance, horizontal_distance) * 1.2
		camera_distance = max(1.5, camera_distance)  # Lower minimum distance
	else:
		# Fallback if no camera
		camera_distance = max(1.5, extents.length() * 2.0)

	update_transform()
	camera_framed.emit()
	print("Framed and zoomed to extents")


func start_drag(mouse_button: int, mouse_pos: Vector2) -> void:
	"""Start a camera drag operation."""
	is_dragging = true
	drag_button = mouse_button
	last_mouse_pos = mouse_pos


func update_drag(mouse_pos: Vector2) -> void:
	"""Update camera drag operation based on button."""
	if not is_dragging:
		return

	var mouse_delta = mouse_pos - last_mouse_pos
	last_mouse_pos = mouse_pos

	match drag_button:
		MOUSE_BUTTON_LEFT:
			handle_orbit(mouse_delta)
		MOUSE_BUTTON_MIDDLE:
			handle_pan(mouse_delta)
		MOUSE_BUTTON_RIGHT:
			handle_zoom(mouse_delta)


func end_drag() -> void:
	"""End the current camera drag operation."""
	is_dragging = false
	drag_button = -1


func reset_camera() -> void:
	"""Reset camera to default position."""
	camera_distance = 5.0
	camera_rotation = Vector2(-45, 30)
	camera_target = Vector3.ZERO
	update_transform()


# Private helper methods


func _calculate_min_pitch_for_target() -> float:
	"""Calculate the minimum pitch angle to prevent camera from going through the floor."""
	# If target is at or below floor level (y <= 0.5), use a safe minimum pitch
	if camera_target.y <= 0.5:
		return 5.0

	# For targets above the floor, calculate the angle where camera would hit floor
	# Using basic trigonometry: tan(angle) = opposite/adjacent
	# opposite = target height, adjacent = horizontal distance (camera_distance projected on XZ plane)
	var target_height = camera_target.y
	var floor_clearance = 0.1  # Keep camera 0.1 units above floor

	# Calculate the pitch angle where camera would be at floor level
	# Negative pitch means looking down past the target toward the floor
	var critical_pitch = rad_to_deg(atan2(-(target_height - floor_clearance), camera_distance))

	# Add a small safety margin (5 degrees) above the critical angle
	return critical_pitch + 5.0
