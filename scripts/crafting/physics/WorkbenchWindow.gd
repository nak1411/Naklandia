class_name WorkbenchWindow
extends Control

## A dedicated 3D assembly window with industry-standard controls.
##
## Controls (Blender/Maya style):
## - Alt + Left Mouse: Orbit camera
## - Alt + Middle Mouse: Pan camera
## - Alt + Right Mouse: Zoom camera
## - Left Click: Select object
## - Left Click + Drag: Box select
## - Right Click: Context menu
## - Q: Select mode
## - W: Move mode (translate gizmo)
## - E: Rotate mode (rotate gizmo)
## - R: Scale mode (scale gizmo)

# UI References
var viewport_container: SubViewportContainer
var selection_overlay: Control
var transform_stats_label: Label
var viewport: SubViewport
var camera: Camera3D
var world: Node3D
var grid: MeshInstance3D
var part_list: ItemList
var validate_button: Button
var initialized: bool = false

# Transform gizmo
var transform_gizmo: TransformGizmo = null
var gizmo_dragger: GizmoDragger = null
var is_dragging_gizmo: bool = false

# Camera controls
var camera_distance: float = 5.0
var camera_rotation: Vector2 = Vector2(-45, 30)  # Yaw, Pitch
var camera_target: Vector3 = Vector3.ZERO
var is_alt_held: bool = false

# Selection
var selected_items: Array[PhysicalItem] = []
var hovered_item: PhysicalItem = null

# Transform modes
enum TransformMode { SELECT, MOVE, ROTATE, SCALE }
var current_transform_mode: TransformMode = TransformMode.SELECT

# Box selection
var is_box_selecting: bool = false
var box_select_start: Vector2
var box_select_end: Vector2

# Dragging state
var is_dragging_camera: bool = false
var drag_button: int = -1  # Which mouse button is being dragged
var last_mouse_pos: Vector2
var is_gizmo_dragging: bool = false  # Dragging on gizmo axis
var gizmo_drag_axis: Vector3 = Vector3.ZERO
var gizmo_drag_start_mouse: Vector2
var gizmo_drag_initial_positions: Dictionary = {}  # PhysicalItem -> Vector3
var gizmo_drag_initial_rotations: Dictionary = {}  # PhysicalItem -> Basis
var gizmo_drag_initial_scales: Dictionary = {}  # PhysicalItem -> Vector3
var was_shift_pressed: bool = false  # Track Shift state during drag
var gizmo_drag_plane_origin: Vector3 = Vector3.ZERO  # Initial drag plane origin in world space
var gizmo_drag_camera_distance: float = 0.0  # Initial camera distance when drag started

# Undo system
const MAX_UNDO_OPERATIONS: int = 10
var undo_history: Array = []  # Array of command dictionaries

# Command structure:
# {
#   "type": "move" | "rotate" | "scale",
#   "items": Array[PhysicalItem],
#   "old_values": Dictionary,  # Item -> old transform
#   "new_values": Dictionary   # Item -> new transform
# }

# Available parts to spawn
var available_parts: Dictionary = {
	"wooden_board": "res://scenes/crafting/wooden_board.tscn",
}

# Signals
signal item_validated(success: bool, report: Dictionary)
signal workbench_closed


func _ready() -> void:
	# Get node references
	viewport_container = $VBoxContainer/ViewportContainer
	selection_overlay = $VBoxContainer/ViewportContainer/SelectionOverlay
	transform_stats_label = $VBoxContainer/ViewportContainer/TransformStatsLabel
	viewport = $VBoxContainer/ViewportContainer/SubViewport
	camera = $VBoxContainer/ViewportContainer/SubViewport/Camera3D
	world = $VBoxContainer/ViewportContainer/SubViewport/World
	grid = $VBoxContainer/ViewportContainer/SubViewport/World/Grid
	part_list = $VBoxContainer/ToolbarPanel/HBoxContainer/PartList
	validate_button = $VBoxContainer/ToolbarPanel/HBoxContainer/ValidateButton

	# Set up viewport
	if viewport and viewport_container:
		viewport.size = viewport_container.size
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# Populate part list
	_populate_part_list()

	# Connect signals
	if validate_button:
		validate_button.pressed.connect(_on_validate_pressed)
	if part_list:
		part_list.item_activated.connect(_on_part_selected)

	# Create transform gizmo
	transform_gizmo = TransformGizmo.new()
	world.add_child(transform_gizmo)
	transform_gizmo.visible = false  # Hidden until something is selected

	# Create gizmo dragger
	gizmo_dragger = GizmoDragger.new()
	add_child(gizmo_dragger)

	# Connect selection overlay draw signal
	if selection_overlay:
		selection_overlay.draw.connect(_draw_selection_box)

	# Update camera initial position
	_update_camera_transform()

	initialized = true
	print("WorkbenchWindow ready - Use Alt+Mouse to navigate, Q/W/E/R for tools")


func _populate_part_list() -> void:
	"""Fill the part list with available items to spawn."""
	if not part_list:
		return
	part_list.clear()
	for part_name in available_parts.keys():
		part_list.add_item(part_name.replace("_", " ").capitalize())


func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Check if we're in the middle of an operation
	var is_active_operation = is_gizmo_dragging or is_dragging_camera or is_box_selecting

	# Only check viewport bounds if we're not in the middle of an operation
	if not is_active_operation and not _is_mouse_over_viewport():
		return

	# Track Alt key
	if event is InputEventKey:
		if event.keycode == KEY_ALT:
			is_alt_held = event.pressed

		# Transform mode shortcuts (only when not holding Alt)
		if event.pressed and not is_alt_held:
			if event.keycode == KEY_Q:
				_set_transform_mode(TransformMode.SELECT)
			elif event.keycode == KEY_W:
				_set_transform_mode(TransformMode.MOVE)
			elif event.keycode == KEY_E:
				_set_transform_mode(TransformMode.ROTATE)
			elif event.keycode == KEY_R:
				_set_transform_mode(TransformMode.SCALE)
			elif event.keycode == KEY_F:
				_frame_selection()  # Frame selected object(s)
			elif event.keycode == KEY_ESCAPE:
				if is_gizmo_dragging:
					_cancel_gizmo_drag()
				else:
					# Deselect all items
					_clear_selection()
			# Undo (Ctrl+Z)
			elif event.keycode == KEY_Z and Input.is_key_pressed(KEY_CTRL):
				_undo_last_operation()

	# Mouse button events
	if event is InputEventMouseButton:
		if event.pressed:
			_handle_mouse_press(event)
		else:
			_handle_mouse_release(event)

	# Mouse motion
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_mouse_press(event: InputEventMouseButton) -> void:
	"""Handle mouse button press events."""
	last_mouse_pos = event.position

	# Alt + Mouse = Camera controls
	if is_alt_held:
		is_dragging_camera = true
		drag_button = event.button_index

	# Left click without Alt = Check for gizmo or selection
	elif event.button_index == MOUSE_BUTTON_LEFT:
		# Try to click on gizmo first
		if _try_start_gizmo_drag(event.position):
			return

		# Check if clicking on an object while in move mode (for free movement)
		if current_transform_mode == TransformMode.MOVE and not selected_items.is_empty():
			if _try_start_free_movement(event.position):
				return

		# Otherwise start box selection
		is_box_selecting = true
		# Convert to selection overlay's local coordinates for drawing
		if selection_overlay:
			box_select_start = selection_overlay.get_local_mouse_position()
			box_select_end = box_select_start

	# Right click = Context menu
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_show_context_menu(event.position)

	# Scroll wheel = Zoom (even without Alt for convenience)
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera_distance = max(1.0, camera_distance - 0.5)
		_update_camera_transform()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera_distance = min(20.0, camera_distance + 0.5)
		_update_camera_transform()


func _handle_mouse_release(event: InputEventMouseButton) -> void:
	"""Handle mouse button release events."""
	# End gizmo drag
	if is_gizmo_dragging and event.button_index == MOUSE_BUTTON_LEFT:
		# Record the operation for undo before clearing
		_record_transform_operation()

		is_gizmo_dragging = false
		gizmo_drag_initial_positions.clear()
		gizmo_drag_initial_rotations.clear()
		gizmo_drag_initial_scales.clear()
		_clear_transform_stats()  # Clear stats display
		return

	# End camera drag
	if is_dragging_camera and event.button_index == drag_button:
		is_dragging_camera = false
		drag_button = -1

	# End box selection
	if is_box_selecting and event.button_index == MOUSE_BUTTON_LEFT:
		# If mouse barely moved, it's a single click
		var drag_distance = (box_select_end - box_select_start).length()
		if drag_distance < 5.0:
			_try_select_single(event.position)
		else:
			_try_box_select()

		# Clear box selection and force redraw to remove the box
		is_box_selecting = false
		if selection_overlay:
			selection_overlay.queue_redraw()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	"""Handle mouse motion events."""
	var delta = event.position - last_mouse_pos

	# Gizmo drag mode
	if is_gizmo_dragging:
		_update_gizmo_drag(event.position)

	# Camera controls (Alt + drag)
	elif is_dragging_camera:
		if drag_button == MOUSE_BUTTON_LEFT:
			# Orbit (inverted for natural feel)
			camera_rotation.x -= delta.x * 0.3
			camera_rotation.y = clamp(camera_rotation.y + delta.y * 0.3, -89, 89)
			_update_camera_transform()

		elif drag_button == MOUSE_BUTTON_MIDDLE:
			# Pan
			var right = camera.global_transform.basis.x
			var up = camera.global_transform.basis.y
			camera_target -= right * delta.x * 0.01 * camera_distance * 0.1
			camera_target += up * delta.y * 0.01 * camera_distance * 0.1
			_update_camera_transform()

		elif drag_button == MOUSE_BUTTON_RIGHT:
			# Smooth zoom
			camera_distance = clamp(camera_distance + delta.y * 0.05, 1.0, 20.0)
			_update_camera_transform()

	# Box selection (update end point)
	elif is_box_selecting:
		# Convert to selection overlay's local coordinates for drawing
		if selection_overlay:
			box_select_end = selection_overlay.get_local_mouse_position()

	# Gizmo hover detection (when not dragging anything)
	elif not is_dragging_camera and not is_box_selecting:
		_update_gizmo_hover(event.position)

	last_mouse_pos = event.position


func _update_camera_transform() -> void:
	"""Update camera position based on orbit controls."""
	if not camera:
		return

	# Convert rotation to radians
	var yaw_rad = deg_to_rad(camera_rotation.x)
	var pitch_rad = deg_to_rad(camera_rotation.y)

	# Calculate camera position
	var offset = (
		Vector3(cos(pitch_rad) * sin(yaw_rad), sin(pitch_rad), cos(pitch_rad) * cos(yaw_rad))
		* camera_distance
	)

	camera.global_position = camera_target + offset
	camera.look_at(camera_target, Vector3.UP)


func _frame_selection() -> void:
	"""Frame selected objects in view and zoom to extents (F key - industry standard)."""
	if selected_items.is_empty():
		return

	# Calculate bounding box of selection
	var min_pos = Vector3(INF, INF, INF)
	var max_pos = Vector3(-INF, -INF, -INF)

	for item in selected_items:
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
	if camera:
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

	_update_camera_transform()
	print("Framed and zoomed to extents")


func _try_start_gizmo_drag(_mouse_pos: Vector2) -> bool:
	"""Try to start dragging on a gizmo axis. Returns true if drag started."""
	if not transform_gizmo or not transform_gizmo.visible or selected_items.is_empty():
		return false

	# Use distance-based detection to gizmo elements
	var viewport_pos = viewport_container.get_local_mouse_position()
	var gizmo_pos = transform_gizmo.global_position

	# Check each axis/element
	var axis_detected = _detect_gizmo_axis(viewport_pos, gizmo_pos)

	# For move mode, allow free movement even without axis detection
	# For rotate/scale, require axis detection
	if current_transform_mode == TransformMode.MOVE:
		# Move mode - if no axis detected, don't start drag (let selection happen)
		if axis_detected == Vector3.ZERO:
			return false

		# Start drag
		is_gizmo_dragging = true
		gizmo_drag_start_mouse = viewport_pos
		gizmo_drag_axis = axis_detected
		was_shift_pressed = Input.is_key_pressed(KEY_SHIFT)

		# Store initial plane origin and camera distance
		gizmo_drag_plane_origin = gizmo_pos
		gizmo_drag_camera_distance = gizmo_pos.distance_to(camera.global_position)

		# Store initial positions
		gizmo_drag_initial_positions.clear()
		for item in selected_items:
			gizmo_drag_initial_positions[item] = item.global_position

		print("Move drag started on axis: ", gizmo_drag_axis)

	elif current_transform_mode == TransformMode.ROTATE:
		# Rotate mode - must have an axis
		if axis_detected == Vector3.ZERO:
			return false

		# Start drag
		is_gizmo_dragging = true
		gizmo_drag_start_mouse = viewport_pos
		gizmo_drag_axis = axis_detected
		was_shift_pressed = Input.is_key_pressed(KEY_SHIFT)

		# Store initial plane origin and camera distance
		gizmo_drag_plane_origin = gizmo_pos
		gizmo_drag_camera_distance = gizmo_pos.distance_to(camera.global_position)

		# Store initial rotations (use Dictionary to store rotation as Basis)
		gizmo_drag_initial_positions.clear()
		gizmo_drag_initial_rotations.clear()
		for item in selected_items:
			gizmo_drag_initial_rotations[item] = item.basis

		print("Rotate drag started on axis: ", gizmo_drag_axis)

	elif current_transform_mode == TransformMode.SCALE:
		# Scale mode - must have an axis or center
		if axis_detected == Vector3.ZERO:
			return false

		# Start drag
		is_gizmo_dragging = true
		gizmo_drag_start_mouse = viewport_pos
		gizmo_drag_axis = axis_detected
		was_shift_pressed = Input.is_key_pressed(KEY_SHIFT)

		# Store initial plane origin and camera distance
		gizmo_drag_plane_origin = gizmo_pos
		gizmo_drag_camera_distance = gizmo_pos.distance_to(camera.global_position)

		# Store initial scales for scaling
		gizmo_drag_initial_scales.clear()
		for item in selected_items:
			gizmo_drag_initial_scales[item] = item.scale

		print("Scale drag started on axis: ", gizmo_drag_axis)

	return true


func _try_start_free_movement(_mouse_pos: Vector2) -> bool:
	"""Try to start free movement by clicking on a selected object."""
	if not camera:
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

			# Store initial plane origin and camera distance
			var gizmo_pos = transform_gizmo.global_position
			gizmo_drag_plane_origin = gizmo_pos
			gizmo_drag_camera_distance = gizmo_pos.distance_to(camera.global_position)

			# Store initial positions
			gizmo_drag_initial_positions.clear()
			for selected_item in selected_items:
				gizmo_drag_initial_positions[selected_item] = selected_item.global_position

			print("Free movement drag started")
			return true

	return false


func _detect_gizmo_axis(mouse_pos: Vector2, gizmo_pos: Vector3) -> Vector3:
	"""Detect which gizmo axis or plane the mouse is over."""
	var gizmo_scale = transform_gizmo.scale.x

	if current_transform_mode == TransformMode.MOVE:
		# Move gizmo detection: check plane handles first, then arrows
		var planes = [
			{"axes": Vector3(1, 1, 0), "pos": (Vector3.RIGHT + Vector3.UP) * 0.15 * gizmo_scale},  # XY
			{"axes": Vector3(1, 0, -1), "pos": (Vector3.RIGHT + Vector3.BACK) * 0.15 * gizmo_scale},  # XZ
			{"axes": Vector3(0, 1, -1), "pos": (Vector3.UP + Vector3.BACK) * 0.15 * gizmo_scale}  # YZ
		]

		for plane_data in planes:
			var plane_world_pos = gizmo_pos + plane_data["pos"]
			var plane_screen_pos = camera.unproject_position(plane_world_pos)
			var dist = mouse_pos.distance_to(plane_screen_pos)

			if dist < 20.0:  # Reduced from 30.0 for tighter detection
				return plane_data["axes"]

		# Then check arrows
		var arrow_length = 0.95 * gizmo_scale
		var axes = [
			{"dir": Vector3.RIGHT, "vec": Vector3.RIGHT},
			{"dir": Vector3.UP, "vec": Vector3.UP},
			{"dir": Vector3.BACK, "vec": Vector3.BACK}
		]

		var closest_dist = 20.0  # Reduced from 30.0 for tighter detection
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

	elif current_transform_mode == TransformMode.ROTATE:
		# Rotate gizmo detection: check if mouse is near the visible torus ring
		var major_radius = 0.71 * gizmo_scale  # Radius from center to middle of torus
		var axes = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]

		var closest_score = INF
		var closest_axis = Vector3.ZERO

		for axis in axes:
			# Project mouse position into 3D ray
			var ray_origin = camera.project_ray_origin(mouse_pos)
			var ray_dir = camera.project_ray_normal(mouse_pos)

			# Find closest point on the torus circle to the mouse ray
			var best_dist_on_circle = INF
			var sample_count = 64

			for i in range(sample_count):
				var angle = (float(i) / sample_count) * TAU
				var circle_point = Vector3.ZERO

				# Calculate point on the circle centerline based on axis
				if axis == Vector3.RIGHT:
					# X axis - circle in YZ plane
					circle_point = Vector3(0, cos(angle), sin(angle)) * major_radius
				elif axis == Vector3.UP:
					# Y axis - circle in XZ plane
					circle_point = Vector3(cos(angle), 0, sin(angle)) * major_radius
				elif axis == Vector3.BACK:
					# Z axis - circle in XY plane
					circle_point = Vector3(cos(angle), sin(angle), 0) * major_radius

				var world_point = gizmo_pos + circle_point

				# Calculate distance from ray to this point on the circle
				var to_point = world_point - ray_origin
				var projection = to_point.dot(ray_dir)
				var closest_on_ray = ray_origin + ray_dir * projection
				var dist_3d = world_point.distance_to(closest_on_ray)

				# Also check visibility - only consider points in front of camera
				if projection > 0:
					best_dist_on_circle = min(best_dist_on_circle, dist_3d)

			# Convert 3D distance to screen-space equivalent score
			# Closer to circle = lower score
			if best_dist_on_circle < closest_score:
				# Check if within acceptable threshold (scaled by distance to camera)
				var dist_to_gizmo = gizmo_pos.distance_to(camera.global_position)
				var threshold = 0.08 * dist_to_gizmo  # Adaptive threshold based on distance

				if best_dist_on_circle < threshold:
					closest_score = best_dist_on_circle
					closest_axis = axis

		return closest_axis

	elif current_transform_mode == TransformMode.SCALE:
		# Scale gizmo detection: check center box first, then handles
		var center_screen = camera.unproject_position(gizmo_pos)
		if mouse_pos.distance_to(center_screen) < 25.0:
			return Vector3(1, 1, 1)  # Uniform scale

		# Then check scale handles (similar to arrows)
		var handle_length = 0.7 * gizmo_scale
		var axes = [
			{"dir": Vector3.RIGHT, "vec": Vector3.RIGHT},
			{"dir": Vector3.UP, "vec": Vector3.UP},
			{"dir": Vector3.BACK, "vec": Vector3.BACK}
		]

		var closest_dist = 30.0
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

	return Vector3.ZERO


func _point_to_segment_distance(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> float:
	"""Calculate distance from point to line segment."""
	var segment = seg_end - seg_start
	var segment_length_sq = segment.length_squared()

	if segment_length_sq == 0.0:
		return point.distance_to(seg_start)

	var t = clamp((point - seg_start).dot(segment) / segment_length_sq, 0.0, 1.0)
	var projection = seg_start + t * segment

	return point.distance_to(projection)


func _cancel_gizmo_drag() -> void:
	"""Cancel the current gizmo drag operation."""
	if not is_gizmo_dragging:
		return

	# Restore original positions
	for item in gizmo_drag_initial_positions.keys():
		if item:
			item.global_position = gizmo_drag_initial_positions[item]

	is_gizmo_dragging = false
	gizmo_drag_initial_positions.clear()
	print("Gizmo drag cancelled")


func _update_gizmo_drag(_mouse_pos: Vector2) -> void:
	"""Update object transformations during gizmo drag."""
	if not is_gizmo_dragging or not camera:
		return

	var viewport_pos = viewport_container.get_local_mouse_position()
	var mouse_delta = viewport_pos - gizmo_drag_start_mouse

	if current_transform_mode == TransformMode.MOVE:
		_update_move_drag(mouse_delta)
	elif current_transform_mode == TransformMode.ROTATE:
		_update_rotate_drag(mouse_delta)
	elif current_transform_mode == TransformMode.SCALE:
		_update_scale_drag(mouse_delta)

	# Update gizmo position
	_update_gizmo()


func _update_move_drag(mouse_delta: Vector2) -> void:
	"""Update object positions during move drag."""
	# Detect if Shift state changed during drag
	var is_shift_pressed = Input.is_key_pressed(KEY_SHIFT)
	if is_shift_pressed != was_shift_pressed:
		# Shift state changed - store current positions as new initial positions
		# and reset the drag start to prevent jumping
		var viewport_pos = viewport_container.get_local_mouse_position()
		gizmo_drag_start_mouse = viewport_pos
		was_shift_pressed = is_shift_pressed

		# Update initial positions to current positions
		for item in selected_items:
			if item in gizmo_drag_initial_positions:
				gizmo_drag_initial_positions[item] = item.global_position

		# Reset mouse_delta since we're starting fresh
		mouse_delta = Vector2.ZERO

	var world_offset = Vector3.ZERO

	# Check if dragging on a plane (2 axes) or single axis
	var num_axes = (
		int(gizmo_drag_axis.x != 0) + int(gizmo_drag_axis.y != 0) + int(gizmo_drag_axis.z != 0)
	)

	# Fine mode multiplier (Shift = 10x slower for precision)
	var fine_multiplier = 0.1 if is_shift_pressed else 1.0

	# Calculate proper viewport-aware scaling using the INITIAL drag distance
	# This ensures the object moves at the same speed as the mouse cursor without drift
	var viewport_size = viewport.size

	# Use the stored initial camera distance (not current distance) to prevent exponential drift
	var gizmo_to_camera = gizmo_drag_camera_distance

	# Calculate pixel-to-world ratio at the initial drag distance
	# This makes the movement speed consistent regardless of camera distance
	var fov_rad = deg_to_rad(camera.fov)
	var viewport_world_height = 2.0 * tan(fov_rad / 2.0) * gizmo_to_camera
	var viewport_world_width = (
		viewport_world_height * (float(viewport_size.x) / float(viewport_size.y))
	)
	var pixels_to_world_x = viewport_world_width / viewport_size.x
	var pixels_to_world_y = viewport_world_height / viewport_size.y

	if num_axes == 3:
		# Free movement on all axes (parallel to camera view)
		var right = camera.global_transform.basis.x
		var up = camera.global_transform.basis.y
		world_offset = (
			(right * mouse_delta.x * pixels_to_world_x - up * mouse_delta.y * pixels_to_world_y)
			* fine_multiplier
		)

	elif num_axes == 2:
		# Plane dragging (e.g., XY, XZ, YZ)
		var right = camera.global_transform.basis.x
		var up = camera.global_transform.basis.y

		var camera_offset = (
			(right * mouse_delta.x * pixels_to_world_x - up * mouse_delta.y * pixels_to_world_y)
			* fine_multiplier
		)

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
		# Use the initial plane origin for consistent screen-space projection
		var axis_end = gizmo_drag_plane_origin + gizmo_drag_axis * 0.5

		var screen_start = camera.unproject_position(gizmo_drag_plane_origin)
		var screen_end = camera.unproject_position(axis_end)
		var screen_axis = (screen_end - screen_start).normalized()

		# Project mouse delta onto the screen-space axis direction
		var movement_on_axis = mouse_delta.dot(screen_axis)

		# Convert screen pixels to world units using proper perspective calculation
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
	_update_transform_stats("Move", move_distance, gizmo_drag_axis)

	# Apply movement to all selected items
	for item in gizmo_drag_initial_positions.keys():
		if item:
			item.global_position = gizmo_drag_initial_positions[item] + world_offset


func _update_rotate_drag(mouse_delta: Vector2) -> void:
	"""Update object rotations during rotate drag."""
	# Detect if Shift state changed during drag
	var is_shift_pressed = Input.is_key_pressed(KEY_SHIFT)
	if is_shift_pressed != was_shift_pressed:
		# Shift state changed - store current rotations as new initial rotations
		# and reset the drag start to prevent jumping
		var viewport_pos = viewport_container.get_local_mouse_position()
		gizmo_drag_start_mouse = viewport_pos
		was_shift_pressed = is_shift_pressed

		# Update initial rotations to current rotations
		for item in selected_items:
			if item in gizmo_drag_initial_rotations:
				gizmo_drag_initial_rotations[item] = item.basis

		# Reset mouse_delta since we're starting fresh
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
	_update_transform_stats("Rotate", rad_to_deg(angle), axis_world)

	# Apply rotation from initial state
	for item in gizmo_drag_initial_rotations.keys():
		if item:
			# Get the initial rotation
			var initial_basis = gizmo_drag_initial_rotations[item]

			# Create rotation around the axis
			var rotation_basis = Basis(axis_world, angle)

			# Apply rotation to the initial state
			item.basis = rotation_basis * initial_basis


func _update_scale_drag(mouse_delta: Vector2) -> void:
	"""Update object scales during scale drag."""
	# Detect if Shift state changed during drag
	var is_shift_pressed = Input.is_key_pressed(KEY_SHIFT)
	if is_shift_pressed != was_shift_pressed:
		# Shift state changed - store current scales as new initial scales
		# and reset the drag start to prevent jumping
		var viewport_pos = viewport_container.get_local_mouse_position()
		gizmo_drag_start_mouse = viewport_pos
		was_shift_pressed = is_shift_pressed

		# Update initial scales to current scales
		for item in selected_items:
			if item in gizmo_drag_initial_scales:
				gizmo_drag_initial_scales[item] = item.scale

		# Reset mouse_delta since we're starting fresh
		mouse_delta = Vector2.ZERO

	# Fine mode multiplier (Shift = 10x slower for precision)
	var fine_multiplier = 0.1 if is_shift_pressed else 1.0

	# Calculate scale factor based on mouse movement change
	var scale_speed = 0.01 * fine_multiplier
	var scale_delta = -mouse_delta.y * scale_speed  # Negative because up = increase scale
	var scale_multiplier = 1.0 + scale_delta

	# Apply scale snapping if CTRL is held (0.1x increments)
	if Input.is_key_pressed(KEY_CTRL):
		var snap_increment = 0.1
		scale_multiplier = round(scale_multiplier / snap_increment) * snap_increment
		scale_multiplier = max(0.1, scale_multiplier)  # Prevent zero or negative scale

	var num_axes = (
		int(gizmo_drag_axis.x != 0) + int(gizmo_drag_axis.y != 0) + int(gizmo_drag_axis.z != 0)
	)

	# Update stats display
	_update_transform_stats("Scale", scale_multiplier, gizmo_drag_axis)

	for item in gizmo_drag_initial_scales.keys():
		if item:
			var initial_scale = gizmo_drag_initial_scales[item]

			if num_axes == 3:
				# Uniform scaling (all axes)
				item.scale = initial_scale * scale_multiplier
			else:
				# Non-uniform scaling on specific axis
				var new_scale = initial_scale
				if gizmo_drag_axis.x != 0:
					new_scale.x = initial_scale.x * scale_multiplier
				if gizmo_drag_axis.y != 0:
					new_scale.y = initial_scale.y * scale_multiplier
				if gizmo_drag_axis.z != 0:
					new_scale.z = initial_scale.z * scale_multiplier

				item.scale = new_scale


func _is_mouse_over_viewport() -> bool:
	"""Check if mouse is currently over the 3D viewport."""
	if not viewport_container:
		return false

	var mouse_pos = viewport_container.get_local_mouse_position()
	var rect = Rect2(Vector2.ZERO, viewport_container.size)
	return rect.has_point(mouse_pos)


func _update_hover_detection(_mouse_pos: Vector2) -> void:
	"""Update which item is being hovered over. (Disabled - no longer needed)"""
	pass


func _update_gizmo_hover(_mouse_pos: Vector2) -> void:
	"""Update gizmo highlighting based on mouse hover."""
	if not transform_gizmo or not transform_gizmo.visible:
		return

	if not camera or not viewport_container:
		return

	var viewport_pos = viewport_container.get_local_mouse_position()
	var gizmo_pos = transform_gizmo.global_position

	# Detect which axis is being hovered
	var hovered_axis = _detect_gizmo_axis(viewport_pos, gizmo_pos)

	# Update gizmo highlighting
	transform_gizmo.set_hover(hovered_axis)


func _set_hovered_item(item: PhysicalItem) -> void:
	"""Set the currently hovered item. (Disabled - no longer needed)"""
	hovered_item = item


func _try_select_single(_mouse_pos: Vector2) -> void:
	"""Try to select a single item at mouse position."""
	if not camera:
		return

	var viewport_pos = viewport_container.get_local_mouse_position()
	var from = camera.project_ray_origin(viewport_pos)
	var to = from + camera.project_ray_normal(viewport_pos) * 100.0

	var space_state = viewport.world_3d.direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 4

	var result = space_state.intersect_ray(query)

	if result and result.collider is PhysicalItem:
		var item = result.collider as PhysicalItem

		# Check if Shift is held for multi-select
		if Input.is_key_pressed(KEY_SHIFT):
			if item in selected_items:
				_deselect_item(item)
			else:
				_select_item(item, true)  # Add to selection
		else:
			# Single select (clear others)
			_clear_selection()
			_select_item(item, false)
	else:
		# Clicked empty space - deselect all
		if not Input.is_key_pressed(KEY_SHIFT):
			_clear_selection()


func _try_box_select() -> void:
	"""Select all items within the box selection area."""
	if not camera or not world:
		return

	# Create selection rectangle (normalize in case user dragged backwards)
	var rect_min = Vector2(
		min(box_select_start.x, box_select_end.x), min(box_select_start.y, box_select_end.y)
	)
	var rect_max = Vector2(
		max(box_select_start.x, box_select_end.x), max(box_select_start.y, box_select_end.y)
	)
	var selection_rect = Rect2(rect_min, rect_max - rect_min)

	# Check if box is too small (probably just a click)
	if selection_rect.size.length() < 5.0:
		# Treat as single click selection
		_try_select_single(box_select_start)
		return

	# Find all PhysicalItems in the world
	var items_to_select: Array[PhysicalItem] = []
	for child in world.get_children():
		if child is PhysicalItem:
			var item = child as PhysicalItem

			# Get the item's AABB (bounding box) in local space
			var aabb: AABB
			if item.has_node("MeshInstance3D"):
				var mesh_instance = item.get_node("MeshInstance3D") as MeshInstance3D
				if mesh_instance and mesh_instance.mesh:
					aabb = mesh_instance.get_aabb()
			else:
				# Fallback: use a small box around the origin
				aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1))

			# Transform the 8 corners of the AABB to world space
			var item_transform = item.global_transform
			var corners = [
				item_transform * (aabb.position),
				item_transform * (aabb.position + Vector3(aabb.size.x, 0, 0)),
				item_transform * (aabb.position + Vector3(0, aabb.size.y, 0)),
				item_transform * (aabb.position + Vector3(0, 0, aabb.size.z)),
				item_transform * (aabb.position + Vector3(aabb.size.x, aabb.size.y, 0)),
				item_transform * (aabb.position + Vector3(aabb.size.x, 0, aabb.size.z)),
				item_transform * (aabb.position + Vector3(0, aabb.size.y, aabb.size.z)),
				item_transform * (aabb.position + aabb.size)
			]

			# Project all corners to screen space and find screen-space bounding box
			var screen_min = Vector2(INF, INF)
			var screen_max = Vector2(-INF, -INF)

			for corner in corners:
				var screen_pos = camera.unproject_position(corner)
				screen_min.x = min(screen_min.x, screen_pos.x)
				screen_min.y = min(screen_min.y, screen_pos.y)
				screen_max.x = max(screen_max.x, screen_pos.x)
				screen_max.y = max(screen_max.y, screen_pos.y)

			# Create screen-space bounding rect for the item
			var item_screen_rect = Rect2(screen_min, screen_max - screen_min)

			# Check if selection rect intersects with item's screen rect
			if selection_rect.intersects(item_screen_rect):
				items_to_select.append(item)

	# Update selection
	if items_to_select.size() > 0:
		_clear_selection()
		for item in items_to_select:
			_select_item(item, true)
		print("Box selected ", items_to_select.size(), " item(s)")
	else:
		# No items selected - clear selection
		_clear_selection()


func _select_item(item: PhysicalItem, add_to_selection: bool) -> void:
	"""Select an item."""
	if not add_to_selection:
		_clear_selection()

	if item not in selected_items:
		selected_items.append(item)
		item.show_highlight(true)
		print("Selected: ", item.item_name, " (", selected_items.size(), " total)")

	_update_gizmo()


func _deselect_item(item: PhysicalItem) -> void:
	"""Deselect a specific item."""
	if item in selected_items:
		selected_items.erase(item)
		item.show_highlight(false)
		print("Deselected: ", item.item_name)


func _clear_selection() -> void:
	"""Clear all selected items."""
	for item in selected_items:
		item.show_highlight(false)
	selected_items.clear()
	_update_gizmo()


func _set_transform_mode(mode: TransformMode) -> void:
	"""Set the current transform mode."""
	current_transform_mode = mode

	var mode_name = ""
	match mode:
		TransformMode.SELECT:
			mode_name = "Select"
		TransformMode.MOVE:
			mode_name = "Move"
		TransformMode.ROTATE:
			mode_name = "Rotate"
		TransformMode.SCALE:
			mode_name = "Scale"

	print("Transform mode: ", mode_name)

	# Update gizmo mode
	if transform_gizmo:
		var gizmo_mode = TransformGizmo.GizmoMode.MOVE
		match mode:
			TransformMode.MOVE:
				gizmo_mode = TransformGizmo.GizmoMode.MOVE
			TransformMode.ROTATE:
				gizmo_mode = TransformGizmo.GizmoMode.ROTATE
			TransformMode.SCALE:
				gizmo_mode = TransformGizmo.GizmoMode.SCALE
			TransformMode.SELECT:
				transform_gizmo.visible = false
				return

		transform_gizmo.set_mode(gizmo_mode)
		_update_gizmo()


func _show_context_menu(_mouse_pos: Vector2) -> void:
	"""Show context menu at mouse position."""
	# TODO: Implement context menu
	print("Context menu (right-click) - Not yet implemented")


func _on_part_selected(index: int) -> void:
	"""Spawn a new part when double-clicked from list."""
	var part_name = part_list.get_item_text(index).to_lower().replace(" ", "_")
	if part_name in available_parts:
		spawn_part(available_parts[part_name])


func spawn_part(scene_path: String) -> PhysicalItem:
	"""Spawn a new part in the workbench."""
	var scene = load(scene_path) as PackedScene
	if not scene:
		push_error("Failed to load part scene: ", scene_path)
		return null

	var item = scene.instantiate() as PhysicalItem
	if not item:
		push_error("Scene is not a PhysicalItem: ", scene_path)
		return null

	# Add to world
	world.add_child(item)

	# Position at camera target, well above the grid (minimum Y of 1.0)
	var spawn_pos = camera_target + Vector3(0, 1.0, 0)
	spawn_pos.y = max(spawn_pos.y, 1.0)  # Ensure always above floor
	item.global_position = spawn_pos

	# Initially frozen for placement
	item.freeze = true

	print("Spawned: ", item.item_name)
	return item


func _update_transform_stats(operation: String, value: float, axis: Vector3) -> void:
	"""Update the transform stats label during operations."""
	if not transform_stats_label:
		return

	var axis_name = ""
	if axis == Vector3.RIGHT:
		axis_name = "X"
	elif axis == Vector3.UP:
		axis_name = "Y"
	elif axis == Vector3.BACK:
		axis_name = "Z"
	elif axis == Vector3(1, 1, 0):
		axis_name = "XY"
	elif axis == Vector3(1, 0, 1):
		axis_name = "XZ"
	elif axis == Vector3(0, 1, 1):
		axis_name = "YZ"
	elif axis == Vector3(1, 1, 1):
		axis_name = "All"
	else:
		# Multi-axis
		axis_name = ""
		if axis.x != 0:
			axis_name += "X"
		if axis.y != 0:
			axis_name += "Y"
		if axis.z != 0:
			axis_name += "Z"

	var text = ""
	if operation == "Move":
		text = "Move: %.2f units (%s)" % [value, axis_name]
		if Input.is_key_pressed(KEY_CTRL):
			text += " [Snapping: 0.25]"
		if Input.is_key_pressed(KEY_SHIFT):
			text += " [Fine Mode]"
	elif operation == "Rotate":
		text = "Rotate: %.1f° (%s)" % [value, axis_name]
		if Input.is_key_pressed(KEY_CTRL):
			text += " [Snapping: 15°]"
		if Input.is_key_pressed(KEY_SHIFT):
			text += " [Fine Mode]"
	elif operation == "Scale":
		text = "Scale: %.2fx (%s)" % [value, axis_name]
		if Input.is_key_pressed(KEY_CTRL):
			text += " [Snapping: 0.1x]"
		if Input.is_key_pressed(KEY_SHIFT):
			text += " [Fine Mode]"

	# Add selected object count
	text += (
		"\nSelected: %d object%s"
		% [selected_items.size(), "s" if selected_items.size() != 1 else ""]
	)

	transform_stats_label.text = text


func _clear_transform_stats() -> void:
	"""Clear the transform stats label."""
	if transform_stats_label:
		transform_stats_label.text = ""


func _on_validate_pressed() -> void:
	"""Validate the current construct."""
	print("Validating construct...")

	var items = get_all_items()
	if items.is_empty():
		print("No items to validate")
		return

	# TODO: Implement actual validation in Phase 3
	var report = {
		"total_items": items.size(),
		"selected_items": selected_items.size(),
		"message": "Validation not yet implemented (Phase 3)"
	}

	print("Validation report: ", report)
	item_validated.emit(false, report)


func clear_workbench() -> void:
	"""Remove all items from workbench."""
	for child in world.get_children():
		if child is PhysicalItem:
			child.queue_free()

	selected_items.clear()
	hovered_item = null
	print("Workbench cleared")


func get_all_items() -> Array[PhysicalItem]:
	"""Get all PhysicalItems currently in the workbench."""
	var items: Array[PhysicalItem] = []
	for child in world.get_children():
		if child is PhysicalItem:
			items.append(child)
	return items


# Render box selection overlay
func _draw_selection_box() -> void:
	if is_box_selecting:
		# Normalize rectangle to handle backwards dragging
		var rect_min = Vector2(
			min(box_select_start.x, box_select_end.x), min(box_select_start.y, box_select_end.y)
		)
		var rect_size = Vector2(
			abs(box_select_end.x - box_select_start.x), abs(box_select_end.y - box_select_start.y)
		)
		var rect = Rect2(rect_min, rect_size)

		selection_overlay.draw_rect(rect, Color(0.3, 0.6, 1.0, 0.2), true)  # Fill
		selection_overlay.draw_rect(rect, Color(0.5, 0.8, 1.0, 0.8), false, 2.0)  # Border


func _process(_delta: float) -> void:
	# Redraw for box selection
	if is_box_selecting and selection_overlay:
		selection_overlay.queue_redraw()

	# Update gizmo scale based on camera distance
	if transform_gizmo and transform_gizmo.visible and camera:
		transform_gizmo.update_scale_for_camera(camera.global_position)


func _update_gizmo() -> void:
	"""Update gizmo position and visibility based on selection."""
	if not transform_gizmo:
		return

	# Hide gizmo if nothing selected or in select mode
	if selected_items.is_empty() or current_transform_mode == TransformMode.SELECT:
		transform_gizmo.visible = false
		return

	# Calculate center of selection
	var center = Vector3.ZERO
	for item in selected_items:
		center += item.global_position
	center /= selected_items.size()

	# Position and show gizmo
	transform_gizmo.set_target_position(center)
	transform_gizmo.visible = true


# Undo System Functions


func _record_transform_operation() -> void:
	"""Record a completed transform operation for undo."""
	if selected_items.is_empty():
		return

	var command = {
		"type": "", "items": selected_items.duplicate(), "old_values": {}, "new_values": {}
	}

	# Determine operation type and collect old/new values
	if current_transform_mode == TransformMode.MOVE:
		command["type"] = "move"
		for item in selected_items:
			if item in gizmo_drag_initial_positions:
				command["old_values"][item] = gizmo_drag_initial_positions[item]
				command["new_values"][item] = item.global_position

	elif current_transform_mode == TransformMode.ROTATE:
		command["type"] = "rotate"
		for item in selected_items:
			if item in gizmo_drag_initial_rotations:
				command["old_values"][item] = gizmo_drag_initial_rotations[item]
				command["new_values"][item] = item.basis

	elif current_transform_mode == TransformMode.SCALE:
		command["type"] = "scale"
		for item in selected_items:
			if item in gizmo_drag_initial_scales:
				command["old_values"][item] = gizmo_drag_initial_scales[item]
				command["new_values"][item] = item.scale

	# Only record if we actually have changes
	if command["old_values"].size() > 0:
		# Check if values actually changed
		var has_changes = false
		for item in command["old_values"].keys():
			if command["old_values"][item] != command["new_values"][item]:
				has_changes = true
				break

		if has_changes:
			# Add to history
			undo_history.append(command)

			# Limit history size to MAX_UNDO_OPERATIONS
			if undo_history.size() > MAX_UNDO_OPERATIONS:
				undo_history.pop_front()

			print(
				"Recorded undo: ",
				command["type"],
				" (",
				undo_history.size(),
				"/",
				MAX_UNDO_OPERATIONS,
				" operations)"
			)


func _undo_last_operation() -> void:
	"""Undo the last transform operation."""
	if undo_history.is_empty():
		print("Nothing to undo")
		return

	var command = undo_history.pop_back()

	# Verify all items still exist
	var all_exist = true
	for item in command["items"]:
		if not is_instance_valid(item) or not item.is_inside_tree():
			all_exist = false
			break

	if not all_exist:
		print("Cannot undo: some items no longer exist")
		return

	# Apply the old values
	match command["type"]:
		"move":
			for item in command["old_values"].keys():
				if is_instance_valid(item):
					item.global_position = command["old_values"][item]
			print("Undid move operation")

		"rotate":
			for item in command["old_values"].keys():
				if is_instance_valid(item):
					item.basis = command["old_values"][item]
			print("Undid rotate operation")

		"scale":
			for item in command["old_values"].keys():
				if is_instance_valid(item):
					item.scale = command["old_values"][item]
			print("Undid scale operation")

	# Update gizmo position
	_update_gizmo()

	print("Undo completed (", undo_history.size(), " operations remaining)")
