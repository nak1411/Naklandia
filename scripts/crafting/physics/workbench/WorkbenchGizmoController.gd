class_name WorkbenchGizmoController
extends RefCounted

## Manages transform gizmo interactions and dragging operations.
##
## Handles:
## - Gizmo axis detection (move, rotate, scale)
## - Drag operations with precise calculations
## - Snap to grid and angle snapping
## - Fine control with modifier keys (Shift, Ctrl, X)
## - Transform statistics display

signal transform_started(mode: int)
signal transform_updated(operation: String, value: float, axis: Vector3)
signal transform_completed(mode: int)
signal gizmo_visibility_changed(visible: bool)

# Transform modes enum (must match WorkbenchWindow)
enum TransformMode { SELECT, MOVE, ROTATE, SCALE, CONNECT }

# References
var camera: Camera3D
var viewport: SubViewport
var viewport_container: SubViewportContainer
var transform_gizmo: TransformGizmo
var gizmo_scale: float = 1.0

# Gizmo state
var is_gizmo_dragging: bool = false
var gizmo_drag_axis: Vector3 = Vector3.ZERO
var gizmo_drag_start_mouse: Vector2
var gizmo_drag_plane_origin: Vector3 = Vector3.ZERO
var gizmo_drag_camera_distance: float = 0.0

# Transform initial values
var gizmo_drag_initial_positions: Dictionary = {}  # PhysicalItem -> Vector3
var gizmo_drag_initial_rotations: Dictionary = {}  # PhysicalItem -> Basis
var gizmo_drag_initial_scales: Dictionary = {}  # PhysicalItem -> Vector3

# Modifier key states (tracked during drag)
var was_shift_pressed: bool = false
var was_ctrl_pressed: bool = false
var was_x_pressed: bool = false

# Snap settings
var snap_to_grid_enabled: bool = false
var grid_snap_size: float = 1.0

# Negative scale warning
var negative_scale_warning_active: bool = false

# Current mode
var current_transform_mode: TransformMode = TransformMode.SELECT


func _init(
	p_camera: Camera3D,
	p_viewport: SubViewport,
	p_viewport_container: SubViewportContainer,
	p_transform_gizmo: TransformGizmo,
	p_gizmo_scale: float = 1.0
) -> void:
	"""Initialize the gizmo controller."""
	camera = p_camera
	viewport = p_viewport
	viewport_container = p_viewport_container
	transform_gizmo = p_transform_gizmo
	gizmo_scale = p_gizmo_scale


func set_transform_mode(mode: TransformMode) -> void:
	"""Set the current transform mode."""
	current_transform_mode = mode

	# Update the visual gizmo to match the mode
	if transform_gizmo:
		match mode:
			TransformMode.SELECT:
				# Hide gizmo in select mode (handled by update_gizmo_position)
				pass
			TransformMode.MOVE:
				transform_gizmo.set_mode(TransformGizmo.GizmoMode.MOVE)
			TransformMode.ROTATE:
				transform_gizmo.set_mode(TransformGizmo.GizmoMode.ROTATE)
			TransformMode.SCALE:
				transform_gizmo.set_mode(TransformGizmo.GizmoMode.SCALE)
			TransformMode.CONNECT:
				# Hide gizmo in connect mode
				pass


func set_snap_to_grid(enabled: bool) -> void:
	"""Enable or disable snap to grid."""
	snap_to_grid_enabled = enabled
	print("Grid snap mode: ", "ENABLED" if enabled else "DISABLED")


func set_grid_snap_size(size: float) -> void:
	"""Set the grid snap size."""
	grid_snap_size = size


func try_start_gizmo_drag(mouse_pos: Vector2, selected_items: Array[PhysicalItem]) -> bool:
	"""Try to start dragging on a gizmo axis. Returns true if drag started."""
	if not transform_gizmo or not transform_gizmo.visible or selected_items.is_empty():
		return false

	var viewport_pos = viewport_container.get_local_mouse_position()
	var gizmo_pos = transform_gizmo.global_position

	# Check each axis/element
	var axis_detected = _detect_gizmo_axis(viewport_pos, gizmo_pos)
	print("Gizmo detection - Mode: %s, Axis detected: %s" % [TransformMode.keys()[current_transform_mode], axis_detected])

	# For move mode, allow detection; for rotate/scale, require axis detection
	if current_transform_mode == TransformMode.MOVE:
		if axis_detected == Vector3.ZERO:
			return false

		_start_move_drag(viewport_pos, gizmo_pos, axis_detected, selected_items)

	elif current_transform_mode == TransformMode.ROTATE:
		if axis_detected == Vector3.ZERO:
			return false

		_start_rotate_drag(viewport_pos, gizmo_pos, axis_detected, selected_items)

	elif current_transform_mode == TransformMode.SCALE:
		if axis_detected == Vector3.ZERO:
			return false

		_start_scale_drag(viewport_pos, gizmo_pos, axis_detected, selected_items)

	else:
		return false

	transform_started.emit(current_transform_mode)
	return true


func try_start_free_movement(mouse_pos: Vector2, selected_items: Array[PhysicalItem]) -> bool:
	"""Try to start free movement by clicking on a selected object."""
	if not camera or selected_items.is_empty():
		return false

	var viewport_pos = viewport_container.get_local_mouse_position()
	var from = camera.project_ray_origin(viewport_pos)
	var to = from + camera.project_ray_normal(viewport_pos) * 100.0

	var space_state = viewport.world_3d.direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 4  # Layer 3 for physical items

	var result = space_state.intersect_ray(query)

	# If we clicked on a selected object, start free movement
	if result and result.collider is PhysicalItem:
		var item = result.collider as PhysicalItem
		if item in selected_items:
			# Start free movement drag (all axes)
			is_gizmo_dragging = true
			gizmo_drag_start_mouse = viewport_pos
			gizmo_drag_axis = Vector3(1, 1, 1)  # All axes for free movement
			was_shift_pressed = Input.is_key_pressed(KEY_SHIFT)
			was_x_pressed = Input.is_key_pressed(KEY_X)

			# Store initial plane origin and camera distance
			var gizmo_pos = transform_gizmo.global_position
			gizmo_drag_plane_origin = gizmo_pos
			gizmo_drag_camera_distance = gizmo_pos.distance_to(camera.global_position)

			# Store initial positions
			gizmo_drag_initial_positions.clear()
			for selected_item in selected_items:
				gizmo_drag_initial_positions[selected_item] = selected_item.global_position

			print("Free movement drag started")
			transform_started.emit(current_transform_mode)
			return true

	return false


func update_gizmo_hover(mouse_pos: Vector2) -> void:
	"""Update gizmo highlighting based on mouse position."""
	if not transform_gizmo or not transform_gizmo.visible or not camera:
		return

	var viewport_pos = viewport_container.get_local_mouse_position()
	var gizmo_pos = transform_gizmo.global_position

	# Detect which axis/element is hovered
	var hovered_axis = _detect_gizmo_axis(viewport_pos, gizmo_pos)

	# Update gizmo highlighting based on what's hovered
	_update_gizmo_highlighting(hovered_axis)


func update_gizmo_drag(mouse_pos: Vector2, selected_items: Array[PhysicalItem]) -> void:
	"""Update object transformations during gizmo drag."""
	if not is_gizmo_dragging or not camera:
		return

	var viewport_pos = viewport_container.get_local_mouse_position()

	# Clamp mouse position to viewport bounds for gizmo dragging
	var viewport_rect = Rect2(Vector2.ZERO, viewport_container.size)
	viewport_pos.x = clamp(viewport_pos.x, viewport_rect.position.x, viewport_rect.position.x + viewport_rect.size.x)
	viewport_pos.y = clamp(viewport_pos.y, viewport_rect.position.y, viewport_rect.position.y + viewport_rect.size.y)

	var mouse_delta = viewport_pos - gizmo_drag_start_mouse

	if current_transform_mode == TransformMode.MOVE:
		_update_move_drag(mouse_delta, selected_items)
	elif current_transform_mode == TransformMode.ROTATE:
		_update_rotate_drag(mouse_delta, selected_items)
	elif current_transform_mode == TransformMode.SCALE:
		_update_scale_drag(mouse_delta, selected_items)


func finish_gizmo_drag() -> void:
	"""Finish the current gizmo drag operation."""
	if is_gizmo_dragging:
		is_gizmo_dragging = false
		gizmo_drag_axis = Vector3.ZERO
		gizmo_drag_initial_positions.clear()
		gizmo_drag_initial_rotations.clear()
		gizmo_drag_initial_scales.clear()

		# Clear negative scale warning
		negative_scale_warning_active = false

		transform_completed.emit(current_transform_mode)


func cancel_gizmo_drag(selected_items: Array[PhysicalItem]) -> void:
	"""Cancel the current gizmo drag operation and restore initial values."""
	if not is_gizmo_dragging:
		return

	# Restore original positions
	for item in gizmo_drag_initial_positions.keys():
		if item:
			item.global_position = gizmo_drag_initial_positions[item]

	# Restore original rotations
	for item in gizmo_drag_initial_rotations.keys():
		if item:
			item.basis = gizmo_drag_initial_rotations[item]

	# Restore original scales
	for item in gizmo_drag_initial_scales.keys():
		if item:
			item.scale = gizmo_drag_initial_scales[item]

	# Clear negative scale feedback
	_update_negative_scale_feedback(false, selected_items)

	finish_gizmo_drag()
	print("Gizmo drag canceled")


func update_gizmo_position(selected_items: Array[PhysicalItem], cluster_pivot_active: bool, cluster_pivot_point: Vector3) -> void:
	"""Update gizmo position and visibility based on selection."""
	if not transform_gizmo:
		return

	# Hide gizmo if nothing selected or in select mode
	if selected_items.is_empty() or current_transform_mode == TransformMode.SELECT:
		transform_gizmo.visible = false
		gizmo_visibility_changed.emit(false)
		return

	# Calculate center of selection
	var center = Vector3.ZERO

	# Use cluster pivot if active (for bonded assemblies)
	if cluster_pivot_active:
		center = cluster_pivot_point
	else:
		# Default: average of all selected item positions
		for item in selected_items:
			center += item.global_position
		center /= selected_items.size()

	# Distance-based culling: hide gizmo if too far away
	if camera:
		var distance = center.distance_to(camera.global_position)
		var max_distance = 50.0  # Maximum distance for gizmo interaction

		if distance > max_distance:
			transform_gizmo.visible = false
			gizmo_visibility_changed.emit(false)
			return

	# Position and show gizmo
	transform_gizmo.set_target_position(center)
	transform_gizmo.visible = true
	gizmo_visibility_changed.emit(true)


func get_initial_transform_data() -> Dictionary:
	"""Get the initial transform data for undo/redo recording."""
	return {
		"positions": gizmo_drag_initial_positions.duplicate(true),
		"rotations": gizmo_drag_initial_rotations.duplicate(true),
		"scales": gizmo_drag_initial_scales.duplicate(true)
	}


# Private helper methods

func _start_move_drag(viewport_pos: Vector2, gizmo_pos: Vector3, axis: Vector3, selected_items: Array[PhysicalItem]) -> void:
	"""Start a move drag operation."""
	is_gizmo_dragging = true
	gizmo_drag_start_mouse = viewport_pos
	gizmo_drag_axis = axis
	was_shift_pressed = Input.is_key_pressed(KEY_SHIFT)
	was_x_pressed = Input.is_key_pressed(KEY_X)

	gizmo_drag_plane_origin = gizmo_pos
	gizmo_drag_camera_distance = gizmo_pos.distance_to(camera.global_position)

	gizmo_drag_initial_positions.clear()
	for item in selected_items:
		gizmo_drag_initial_positions[item] = item.global_position

	print("Move drag started on axis: ", gizmo_drag_axis)


func _start_rotate_drag(viewport_pos: Vector2, gizmo_pos: Vector3, axis: Vector3, selected_items: Array[PhysicalItem]) -> void:
	"""Start a rotate drag operation."""
	is_gizmo_dragging = true
	gizmo_drag_start_mouse = viewport_pos
	gizmo_drag_axis = axis
	was_shift_pressed = Input.is_key_pressed(KEY_SHIFT)
	was_ctrl_pressed = Input.is_key_pressed(KEY_CTRL)

	gizmo_drag_plane_origin = gizmo_pos
	gizmo_drag_camera_distance = gizmo_pos.distance_to(camera.global_position)

	gizmo_drag_initial_positions.clear()
	gizmo_drag_initial_rotations.clear()
	for item in selected_items:
		gizmo_drag_initial_rotations[item] = item.basis
		gizmo_drag_initial_positions[item] = item.global_position

	# If CTRL is held, immediately snap to nearest 15-degree increment
	if was_ctrl_pressed:
		_snap_rotation_to_increment(axis, selected_items)

	print("Rotate drag started on axis: ", gizmo_drag_axis)


func _start_scale_drag(viewport_pos: Vector2, gizmo_pos: Vector3, axis: Vector3, selected_items: Array[PhysicalItem]) -> void:
	"""Start a scale drag operation."""
	is_gizmo_dragging = true
	gizmo_drag_start_mouse = viewport_pos
	gizmo_drag_axis = axis
	was_shift_pressed = Input.is_key_pressed(KEY_SHIFT)

	gizmo_drag_plane_origin = gizmo_pos
	gizmo_drag_camera_distance = gizmo_pos.distance_to(camera.global_position)

	gizmo_drag_initial_scales.clear()
	for item in selected_items:
		gizmo_drag_initial_scales[item] = item.scale

	print("Scale drag started on axis: ", gizmo_drag_axis)


func _update_move_drag(mouse_delta: Vector2, selected_items: Array[PhysicalItem]) -> void:
	"""Update object positions during move drag."""
	# Detect if Shift state changed during drag
	var is_shift_pressed = Input.is_key_pressed(KEY_SHIFT)
	if is_shift_pressed != was_shift_pressed:
		var viewport_pos = viewport_container.get_local_mouse_position()
		gizmo_drag_start_mouse = viewport_pos
		was_shift_pressed = is_shift_pressed

		for item in selected_items:
			if item in gizmo_drag_initial_positions:
				gizmo_drag_initial_positions[item] = item.global_position

		mouse_delta = Vector2.ZERO

	# Detect if X key state changed during drag (snap to grid)
	var is_x_pressed = Input.is_key_pressed(KEY_X)
	if is_x_pressed != was_x_pressed:
		var viewport_pos = viewport_container.get_local_mouse_position()
		gizmo_drag_start_mouse = viewport_pos
		was_x_pressed = is_x_pressed

		for item in selected_items:
			if item in gizmo_drag_initial_positions:
				gizmo_drag_initial_positions[item] = item.global_position

		mouse_delta = Vector2.ZERO

	var world_offset = Vector3.ZERO

	# Check if dragging on a plane (2 axes) or single axis
	var num_axes = int(gizmo_drag_axis.x != 0) + int(gizmo_drag_axis.y != 0) + int(gizmo_drag_axis.z != 0)

	# Fine mode multiplier (Shift = 10x slower for precision)
	var fine_multiplier = 0.1 if is_shift_pressed else 1.0

	# Calculate proper viewport-aware scaling
	var viewport_size = viewport.size
	var gizmo_to_camera = gizmo_drag_camera_distance

	var fov_rad = deg_to_rad(camera.fov)
	var viewport_world_height = 2.0 * tan(fov_rad / 2.0) * gizmo_to_camera
	var viewport_world_width = viewport_world_height * (float(viewport_size.x) / float(viewport_size.y))
	var pixels_to_world_x = viewport_world_width / viewport_size.x
	var pixels_to_world_y = viewport_world_height / viewport_size.y

	if num_axes == 3:
		# Free movement on all axes (parallel to camera view)
		var right = camera.global_transform.basis.x
		var up = camera.global_transform.basis.y
		world_offset = ((right * mouse_delta.x * pixels_to_world_x - up * mouse_delta.y * pixels_to_world_y) * fine_multiplier)

	elif num_axes == 2:
		# Plane dragging (e.g., XY, XZ, YZ)
		var right = camera.global_transform.basis.x
		var up = camera.global_transform.basis.y

		var camera_offset = (right * mouse_delta.x * pixels_to_world_x - up * mouse_delta.y * pixels_to_world_y) * fine_multiplier

		# Constrain to the plane by zeroing out the axis we're NOT dragging
		if gizmo_drag_axis.x == 0:
			camera_offset.x = 0
		if gizmo_drag_axis.y == 0:
			camera_offset.y = 0
		if gizmo_drag_axis.z == 0:
			camera_offset.z = 0

		world_offset = camera_offset

	else:
		# Single axis dragging - project mouse movement onto the screen-space axis
		var axis_end = gizmo_drag_plane_origin + gizmo_drag_axis * 0.5

		var screen_start = camera.unproject_position(gizmo_drag_plane_origin)
		var screen_end = camera.unproject_position(axis_end)
		var screen_axis = (screen_end - screen_start).normalized()

		# Project mouse delta onto the screen-space axis direction
		var movement_on_axis = mouse_delta.dot(screen_axis)

		# Convert screen pixels to world units
		var avg_pixels_to_world = (pixels_to_world_x + pixels_to_world_y) / 2.0
		world_offset = gizmo_drag_axis * movement_on_axis * avg_pixels_to_world * fine_multiplier

	# Apply position snapping if CTRL is held (0.25 unit increments)
	if Input.is_key_pressed(KEY_CTRL):
		var snap_increment = 0.25
		world_offset.x = round(world_offset.x / snap_increment) * snap_increment
		world_offset.y = round(world_offset.y / snap_increment) * snap_increment
		world_offset.z = round(world_offset.z / snap_increment) * snap_increment

	# Update stats display
	var move_distance = world_offset.length()
	transform_updated.emit("Move", move_distance, gizmo_drag_axis)

	# Apply movement to all selected items
	for item in gizmo_drag_initial_positions.keys():
		if item:
			var new_position = gizmo_drag_initial_positions[item] + world_offset

			# Apply snap to grid if X key is held
			if snap_to_grid_enabled:
				new_position.x = round(new_position.x / grid_snap_size) * grid_snap_size
				new_position.y = round(new_position.y / grid_snap_size) * grid_snap_size
				new_position.z = round(new_position.z / grid_snap_size) * grid_snap_size

			item.global_position = new_position


func _update_rotate_drag(mouse_delta: Vector2, selected_items: Array[PhysicalItem]) -> void:
	"""Update object rotations during rotate drag."""
	# Detect if Shift state changed during drag
	var is_shift_pressed = Input.is_key_pressed(KEY_SHIFT)
	if is_shift_pressed != was_shift_pressed:
		var viewport_pos = viewport_container.get_local_mouse_position()
		gizmo_drag_start_mouse = viewport_pos
		was_shift_pressed = is_shift_pressed

		for item in selected_items:
			if item in gizmo_drag_initial_rotations:
				gizmo_drag_initial_rotations[item] = item.basis

		mouse_delta = Vector2.ZERO

	# Detect if Ctrl state changed during drag (for angle snapping)
	var is_ctrl_pressed = Input.is_key_pressed(KEY_CTRL)
	if is_ctrl_pressed != was_ctrl_pressed:
		var viewport_pos = viewport_container.get_local_mouse_position()
		gizmo_drag_start_mouse = viewport_pos
		was_ctrl_pressed = is_ctrl_pressed

		for item in selected_items:
			if item in gizmo_drag_initial_rotations:
				gizmo_drag_initial_rotations[item] = item.basis

		if is_ctrl_pressed:
			_snap_rotation_to_increment(gizmo_drag_axis, selected_items)

		mouse_delta = Vector2.ZERO

	# Get the gizmo position in screen space
	var gizmo_pos = transform_gizmo.global_position
	var gizmo_screen = camera.unproject_position(gizmo_pos)

	# Get the rotation axis in world space
	var axis_world = gizmo_drag_axis.normalized()

	# Calculate start and current positions relative to gizmo center
	var start_pos = gizmo_drag_start_mouse - gizmo_screen
	var current_pos = (gizmo_drag_start_mouse + mouse_delta) - gizmo_screen

	# Project the axis onto the screen to get the axis direction
	var axis_end_world = gizmo_pos + axis_world * 0.1
	var axis_end_screen = camera.unproject_position(axis_end_world)
	var axis_screen_dir = (axis_end_screen - gizmo_screen).normalized()

	# Calculate perpendicular (tangent) direction for rotation
	var tangent_screen = Vector2(-axis_screen_dir.y, axis_screen_dir.x)

	# Calculate the change in rotation by projecting movement onto tangent
	var start_tangent = start_pos.dot(tangent_screen)
	var current_tangent = current_pos.dot(tangent_screen)
	var tangent_delta = current_tangent - start_tangent

	# Fine mode multiplier (Shift = 10x slower for precision)
	var fine_multiplier = 0.1 if is_shift_pressed else 1.0

	# Convert to angle based on distance from center
	var avg_distance = (start_pos.length() + current_pos.length()) / 2.0
	var angle = 0.0
	if avg_distance > 1.0:
		angle = tangent_delta / avg_distance * 2.0 * fine_multiplier

	# Apply angle snapping if CTRL is held (15 degree increments)
	if Input.is_key_pressed(KEY_CTRL):
		var snap_increment = deg_to_rad(15.0)
		angle = round(angle / snap_increment) * snap_increment

	# Update stats display
	transform_updated.emit("Rotate", rad_to_deg(angle), axis_world)

	# Get the pivot point (gizmo position)
	var pivot = gizmo_drag_plane_origin

	# Apply rotation from initial state
	for item in gizmo_drag_initial_rotations.keys():
		if item:
			var initial_basis = gizmo_drag_initial_rotations[item]
			var initial_position = gizmo_drag_initial_positions[item]

			# Create rotation around the axis
			var rotation_basis = Basis(axis_world, angle)

			# Apply rotation to the item's basis
			item.basis = rotation_basis * initial_basis

			# Rotate position around the pivot point
			var offset_from_pivot = initial_position - pivot
			var rotated_offset = rotation_basis * offset_from_pivot
			item.global_position = pivot + rotated_offset


func _update_scale_drag(mouse_delta: Vector2, selected_items: Array[PhysicalItem]) -> void:
	"""Update object scales during scale drag."""
	# Detect if Shift state changed during drag
	var is_shift_pressed = Input.is_key_pressed(KEY_SHIFT)
	if is_shift_pressed != was_shift_pressed:
		var viewport_pos = viewport_container.get_local_mouse_position()
		gizmo_drag_start_mouse = viewport_pos
		was_shift_pressed = is_shift_pressed

		for item in selected_items:
			if item in gizmo_drag_initial_scales:
				gizmo_drag_initial_scales[item] = item.scale

		mouse_delta = Vector2.ZERO

	# Fine mode multiplier (Shift = 10x slower for precision)
	var fine_multiplier = 0.1 if is_shift_pressed else 1.0

	# Calculate scale factor based on mouse movement
	var scale_speed = 0.01 * fine_multiplier
	var scale_delta = -mouse_delta.y * scale_speed  # Negative because up = increase scale
	var scale_multiplier = 1.0 + scale_delta

	# Apply scale snapping if CTRL is held (0.1x increments)
	if Input.is_key_pressed(KEY_CTRL):
		var snap_increment = 0.1
		scale_multiplier = round(scale_multiplier / snap_increment) * snap_increment
		scale_multiplier = max(0.01, scale_multiplier)

	var num_axes = int(gizmo_drag_axis.x != 0) + int(gizmo_drag_axis.y != 0) + int(gizmo_drag_axis.z != 0)

	# Update stats display
	transform_updated.emit("Scale", scale_multiplier, gizmo_drag_axis)

	# Track if any object has negative scale for visual feedback
	var has_negative_scale = false

	for item in gizmo_drag_initial_scales.keys():
		if item:
			var initial_scale = gizmo_drag_initial_scales[item]
			var new_scale: Vector3

			if num_axes == 3:
				# Uniform scaling (all axes)
				new_scale = initial_scale * scale_multiplier
			else:
				# Non-uniform scaling on specific axis
				new_scale = initial_scale
				if gizmo_drag_axis.x != 0:
					new_scale.x = initial_scale.x * scale_multiplier
				if gizmo_drag_axis.y != 0:
					new_scale.y = initial_scale.y * scale_multiplier
				if gizmo_drag_axis.z != 0:
					new_scale.z = initial_scale.z * scale_multiplier

			# Clamp each axis to a minimum of 0.01 to prevent negative scaling
			new_scale.x = max(0.01, new_scale.x)
			new_scale.y = max(0.01, new_scale.y)
			new_scale.z = max(0.01, new_scale.z)

			item.scale = new_scale

			# Check if the calculated scale would have been negative (before clamping)
			var unclamped_scale = (
				initial_scale * scale_multiplier
				if num_axes == 3
				else Vector3(
					initial_scale.x * (scale_multiplier if gizmo_drag_axis.x != 0 else 1.0),
					initial_scale.y * (scale_multiplier if gizmo_drag_axis.y != 0 else 1.0),
					initial_scale.z * (scale_multiplier if gizmo_drag_axis.z != 0 else 1.0)
				)
			)

			if unclamped_scale.x < 0 or unclamped_scale.y < 0 or unclamped_scale.z < 0:
				has_negative_scale = true

	# Visual feedback: tint red if attempting negative scale
	_update_negative_scale_feedback(has_negative_scale, selected_items)


func _snap_rotation_to_increment(axis: Vector3, selected_items: Array[PhysicalItem]) -> void:
	"""Snap the current rotation to the nearest 15-degree increment on the specified axis."""
	var snap_increment = deg_to_rad(15.0)

	for item in selected_items:
		# Get current rotation as Euler angles
		var current_euler = item.rotation

		# Snap the rotation on the specified axis
		if axis == Vector3.RIGHT:
			var snapped_angle = round(current_euler.x / snap_increment) * snap_increment
			item.rotation.x = snapped_angle
		elif axis == Vector3.UP:
			var snapped_angle = round(current_euler.y / snap_increment) * snap_increment
			item.rotation.y = snapped_angle
		elif axis == Vector3.BACK:
			var snapped_angle = round(current_euler.z / snap_increment) * snap_increment
			item.rotation.z = snapped_angle

		# Update the initial rotation to the snapped value
		if item in gizmo_drag_initial_rotations:
			gizmo_drag_initial_rotations[item] = item.basis

	print("Snapped rotation to nearest 15° increment")


func _update_negative_scale_feedback(is_negative: bool, selected_items: Array[PhysicalItem]) -> void:
	"""Apply red tint to selected objects when attempting negative scale."""
	if is_negative == negative_scale_warning_active:
		return  # No change needed

	negative_scale_warning_active = is_negative

	for item in selected_items:
		if not item or not item.mesh_instance:
			continue

		var mesh = item.mesh_instance

		if is_negative:
			# Apply red warning tint
			var warning_material = StandardMaterial3D.new()
			warning_material.albedo_color = Color(1.0, 0.3, 0.3, 1.0)  # Red tint
			warning_material.emission_enabled = true
			warning_material.emission = Color(0.8, 0.2, 0.2, 1.0)  # Red emission
			warning_material.emission_energy_multiplier = 0.7
			mesh.set_surface_override_material(0, warning_material)
		else:
			# Restore original highlight (selected) material
			mesh.set_surface_override_material(0, item.outline_material)


func _detect_gizmo_axis(mouse_pos: Vector2, gizmo_pos: Vector3) -> Vector3:
	"""Detect which gizmo axis or plane the mouse is over."""
	var gizmo_scale_val = transform_gizmo.scale.x

	# Calculate dynamic threshold based on gizmo's actual screen-space size
	var arrow_tip_world = gizmo_pos + Vector3.RIGHT * (0.95 * gizmo_scale_val)
	var gizmo_center_screen = camera.unproject_position(gizmo_pos)
	var arrow_tip_screen = camera.unproject_position(arrow_tip_world)
	var arrow_screen_length = gizmo_center_screen.distance_to(arrow_tip_screen)

	# Calculate thresholds as percentages of the arrow's screen length
	# Increased from original values to make selection easier
	var arrow_threshold = arrow_screen_length * 0.10  # 10% of arrow length (was 6%)
	var plane_threshold = arrow_screen_length * 0.12  # 12% of arrow length (was 8%)
	var rotate_threshold = arrow_screen_length * 0.08  # 8% of arrow length (was 5%)
	var scale_threshold = arrow_screen_length * 0.14  # 14% of arrow length (was 10%)

	if current_transform_mode == TransformMode.MOVE:
		return _detect_move_gizmo_axis(mouse_pos, gizmo_pos, gizmo_scale_val, arrow_threshold, plane_threshold)
	elif current_transform_mode == TransformMode.ROTATE:
		return _detect_rotate_gizmo_axis(mouse_pos, gizmo_pos, gizmo_scale_val, rotate_threshold)
	elif current_transform_mode == TransformMode.SCALE:
		return _detect_scale_gizmo_axis(mouse_pos, gizmo_pos, gizmo_scale_val, scale_threshold)

	return Vector3.ZERO


func _detect_move_gizmo_axis(mouse_pos: Vector2, gizmo_pos: Vector3, gizmo_scale_val: float, arrow_threshold: float, plane_threshold: float) -> Vector3:
	"""Detect move gizmo axis or plane."""
	# Check plane handles first
	# Plane handles are small squares at the intersection of two axes
	var gizmo_size = transform_gizmo.gizmo_size
	var plane_size = 0.2 * gizmo_size * gizmo_scale_val  # Size of the plane handle quad

	var planes = [
		{"axes": Vector3(1, 1, 0), "pos": (Vector3.RIGHT + Vector3.UP) * 0.15 * gizmo_size * gizmo_scale_val},
		{"axes": Vector3(1, 0, 1), "pos": (Vector3.RIGHT + Vector3.BACK) * 0.15 * gizmo_size * gizmo_scale_val},
		{"axes": Vector3(0, 1, 1), "pos": (Vector3.UP + Vector3.BACK) * 0.15 * gizmo_size * gizmo_scale_val}
	]

	for plane_data in planes:
		var plane_world_pos = gizmo_pos + plane_data["pos"]
		var plane_screen_pos = camera.unproject_position(plane_world_pos)

		# Check if mouse is within a box around the plane handle (more forgiving)
		var dist = mouse_pos.distance_to(plane_screen_pos)

		# Use larger threshold for planes to make them easier to select
		if dist < plane_threshold * 2.0:
			return plane_data["axes"]

	# Then check arrows
	var arrow_length = 0.95 * gizmo_size * gizmo_scale_val
	var axes = [
		{"dir": Vector3.RIGHT, "vec": Vector3.RIGHT},
		{"dir": Vector3.UP, "vec": Vector3.UP},
		{"dir": Vector3.BACK, "vec": Vector3.BACK}
	]

	var closest_dist = arrow_threshold
	var closest_axis = Vector3.ZERO

	for axis_data in axes:
		var axis_dir = axis_data["dir"]
		var axis_end = gizmo_pos + (axis_dir * arrow_length)

		var screen_start = camera.unproject_position(gizmo_pos)
		var screen_end = camera.unproject_position(axis_end)

		var dist = _point_to_segment_distance(mouse_pos, screen_start, screen_end)

		if dist < closest_dist:
			closest_dist = dist
			closest_axis = axis_data["vec"]

	return closest_axis


func _detect_rotate_gizmo_axis(mouse_pos: Vector2, gizmo_pos: Vector3, gizmo_scale_val: float, rotate_threshold: float) -> Vector3:
	"""Detect rotate gizmo axis (rotation circles)."""
	var gizmo_size = transform_gizmo.gizmo_size
	var circle_radius = 0.70 * gizmo_size * gizmo_scale_val

	var axes = [
		{"axis": Vector3.RIGHT, "name": "X"},
		{"axis": Vector3.UP, "name": "Y"},
		{"axis": Vector3.BACK, "name": "Z"}
	]

	# Sort axes by perpendicularity to camera (most perpendicular = most visible)
	var camera_forward = -camera.global_transform.basis.z.normalized()
	var sorted_axes = []
	for axis_data in axes:
		var axis = axis_data["axis"]
		var perpendicularity = abs(axis.dot(camera_forward))
		sorted_axes.append({"axis": axis, "name": axis_data["name"], "priority": perpendicularity})

	sorted_axes.sort_custom(func(a, b): return a["priority"] < b["priority"])

	var closest_screen_dist = INF
	var closest_axis = Vector3.ZERO
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)

	# Test axes in visibility order
	for axis_data in sorted_axes:
		var axis = axis_data["axis"]
		var priority = axis_data["priority"]

		# Build plane containing the rotation circle
		var plane_normal = axis
		var plane = Plane(plane_normal, gizmo_pos.dot(plane_normal))

		# Intersect ray with plane
		var intersection = plane.intersects_ray(ray_origin, ray_dir)
		if intersection == null:
			continue

		# Get local position on plane relative to gizmo center
		var local_pos = intersection - gizmo_pos

		# Check if intersection is behind gizmo
		var to_intersection = intersection - gizmo_pos
		var to_camera = camera.global_position - gizmo_pos
		if to_intersection.dot(to_camera) < 0:
			continue

		# Project to circle
		var local_distance = local_pos.length()
		if local_distance < 0.001:
			continue

		var ideal_pos_on_circle = (local_pos / local_distance) * circle_radius
		var world_pos_on_circle = gizmo_pos + ideal_pos_on_circle

		# Convert to screen space and measure distance
		var screen_pos_on_circle = camera.unproject_position(world_pos_on_circle)
		var screen_dist = mouse_pos.distance_to(screen_pos_on_circle)

		if screen_dist < rotate_threshold:
			var distance_improvement = closest_screen_dist - screen_dist
			if screen_dist < closest_screen_dist or (distance_improvement < 3.0 and priority < 0.3):
				closest_screen_dist = screen_dist
				closest_axis = axis

	return closest_axis


func _detect_scale_gizmo_axis(mouse_pos: Vector2, gizmo_pos: Vector3, gizmo_scale_val: float, scale_threshold: float) -> Vector3:
	"""Detect scale gizmo axis or center."""
	# Check center box first
	var center_screen = camera.unproject_position(gizmo_pos)
	if mouse_pos.distance_to(center_screen) < scale_threshold:
		return Vector3(1, 1, 1)  # Uniform scale

	# Then check scale handles
	var gizmo_size = transform_gizmo.gizmo_size
	var handle_length = 0.7 * gizmo_size * gizmo_scale_val
	var axes = [
		{"dir": Vector3.RIGHT, "vec": Vector3.RIGHT},
		{"dir": Vector3.UP, "vec": Vector3.UP},
		{"dir": Vector3.BACK, "vec": Vector3.BACK}
	]

	var closest_dist = scale_threshold
	var closest_axis = Vector3.ZERO

	for axis_data in axes:
		var axis_dir = axis_data["dir"]
		var axis_end = gizmo_pos + (axis_dir * handle_length)

		var screen_start = camera.unproject_position(gizmo_pos)
		var screen_end = camera.unproject_position(axis_end)

		var dist = _point_to_segment_distance(mouse_pos, screen_start, screen_end)

		if dist < closest_dist:
			closest_dist = dist
			closest_axis = axis_data["vec"]

	return closest_axis


func _update_gizmo_highlighting(hovered_axis: Vector3) -> void:
	"""Update gizmo visual highlighting based on hovered axis."""
	if not transform_gizmo:
		return

	# Clear previous highlighting
	transform_gizmo._clear_highlight()

	# No highlighting if nothing is hovered
	if hovered_axis == Vector3.ZERO:
		return

	# Apply highlighting based on mode and axis
	if current_transform_mode == TransformMode.MOVE:
		# Check if it's a plane (2 axes)
		var num_axes = int(hovered_axis.x != 0) + int(hovered_axis.y != 0) + int(hovered_axis.z != 0)

		if num_axes == 2:
			# Highlight plane
			if hovered_axis == Vector3(1, 1, 0) and transform_gizmo.plane_xy_node:
				transform_gizmo._highlight_plane(transform_gizmo.plane_xy_node)
			elif hovered_axis == Vector3(1, 0, 1) and transform_gizmo.plane_xz_node:
				transform_gizmo._highlight_plane(transform_gizmo.plane_xz_node)
			elif hovered_axis == Vector3(0, 1, 1) and transform_gizmo.plane_yz_node:
				transform_gizmo._highlight_plane(transform_gizmo.plane_yz_node)
		else:
			# Highlight arrow
			if hovered_axis == Vector3.RIGHT and transform_gizmo.arrow_x_node:
				transform_gizmo._highlight_arrow(transform_gizmo.arrow_x_node)
			elif hovered_axis == Vector3.UP and transform_gizmo.arrow_y_node:
				transform_gizmo._highlight_arrow(transform_gizmo.arrow_y_node)
			elif hovered_axis == Vector3.BACK and transform_gizmo.arrow_z_node:
				transform_gizmo._highlight_arrow(transform_gizmo.arrow_z_node)

	elif current_transform_mode == TransformMode.ROTATE:
		# Highlight rotation circle
		if hovered_axis == Vector3.RIGHT and transform_gizmo.circle_x_node:
			transform_gizmo._highlight_mesh(transform_gizmo.circle_x_node)
		elif hovered_axis == Vector3.UP and transform_gizmo.circle_y_node:
			transform_gizmo._highlight_mesh(transform_gizmo.circle_y_node)
		elif hovered_axis == Vector3.BACK and transform_gizmo.circle_z_node:
			transform_gizmo._highlight_mesh(transform_gizmo.circle_z_node)

	elif current_transform_mode == TransformMode.SCALE:
		# Check if center or axis
		if hovered_axis == Vector3(1, 1, 1) and transform_gizmo.scale_center_node:
			transform_gizmo._highlight_mesh(transform_gizmo.scale_center_node)
		else:
			# Highlight scale handle
			if hovered_axis == Vector3.RIGHT and transform_gizmo.scale_x_node:
				transform_gizmo._highlight_scale_handle(transform_gizmo.scale_x_node)
			elif hovered_axis == Vector3.UP and transform_gizmo.scale_y_node:
				transform_gizmo._highlight_scale_handle(transform_gizmo.scale_y_node)
			elif hovered_axis == Vector3.BACK and transform_gizmo.scale_z_node:
				transform_gizmo._highlight_scale_handle(transform_gizmo.scale_z_node)


func _point_to_segment_distance(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> float:
	"""Calculate distance from point to line segment."""
	var segment = seg_end - seg_start
	var segment_length_sq = segment.length_squared()

	if segment_length_sq == 0.0:
		return point.distance_to(seg_start)

	var t = clamp((point - seg_start).dot(segment) / segment_length_sq, 0.0, 1.0)
	var projection = seg_start + t * segment

	return point.distance_to(projection)
