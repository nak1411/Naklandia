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
var object_info_label: Label
var viewport: SubViewport
var camera: Camera3D
var world: Node3D
var grid: MeshInstance3D
var part_list: ItemList
var category_filter: OptionButton
var add_object_button: Button
var validate_button: Button
var clear_button: Button
var help_label: Label
var controls_visible: bool = false
var initialized: bool = false
var sidebar_panel: PanelContainer
var separator: Control
var context_menu: ContextMenu_Base

# Transform input panel
var transform_panel: PanelContainer
var position_x_input: SpinBox
var position_y_input: SpinBox
var position_z_input: SpinBox
var rotation_x_input: SpinBox
var rotation_y_input: SpinBox
var rotation_z_input: SpinBox
var scale_x_input: SpinBox
var scale_y_input: SpinBox
var scale_z_input: SpinBox
var is_updating_transform_inputs: bool = false  # Flag to prevent recursion

# Transform mode buttons
var select_button: Button
var move_button: Button
var rotate_button: Button
var scale_button: Button

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
var was_ctrl_pressed: bool = false  # Track Ctrl state during drag
var was_x_pressed: bool = false  # Track X state during drag (snap to grid)
var gizmo_drag_plane_origin: Vector3 = Vector3.ZERO  # Initial drag plane origin in world space
var gizmo_drag_camera_distance: float = 0.0  # Initial camera distance when drag started

# Sidebar dragging state
var is_dragging_separator: bool = false
var sidebar_drag_start_x: float = 0.0
var sidebar_initial_width: float = 250.0

# Snap to grid settings
var snap_to_grid_enabled: bool = false  # True when X key is held
var grid_snap_size: float = 1.0  # Grid size for snapping (1 unit)

# Undo/Redo system
const MAX_UNDO_OPERATIONS: int = 10
var undo_history: Array = []  # Array of command dictionaries
var redo_history: Array = []  # Array of command dictionaries for redo

# Negative scale warning
var negative_scale_warning_active: bool = false

# Command structure:
# {
#   "type": "move" | "rotate" | "scale",
#   "items": Array[PhysicalItem],
#   "old_values": Dictionary,  # Item -> old transform
#   "new_values": Dictionary   # Item -> new transform
# }

# Available parts to spawn
var available_parts: Dictionary = {
	"small_wooden_board": "res://scenes/crafting/parts/wooden_board_small.tscn",
	"large_wooden_board": "res://scenes/crafting/parts/wooden_board_large.tscn",
	"table_leg": "res://scenes/crafting/parts/table_leg.tscn",
	"tabletop": "res://scenes/crafting/parts/tabletop.tscn",
	"fixed_joint": "res://scenes/crafting/hardware/joint_helper_fixed.tscn",
	"hinge_joint": "res://scenes/crafting/hardware/joint_helper_hinge.tscn",
	"ball_joint": "res://scenes/crafting/hardware/joint_helper_ball.tscn",
}

# Part categories for filtering
var part_categories: Dictionary = {
	"small_wooden_board": "structural_items",
	"large_wooden_board": "structural_items",
	"table_leg": "structural_items",
	"tabletop": "structural_items",
	"fixed_joint": "hardware",
	"hinge_joint": "hardware",
	"ball_joint": "hardware",
}

# Fastener system
var selected_fastener_id: String = "fastener_steel_bolt"  # Default fastener
var available_fasteners: Array[String] = [
	"fastener_iron_nail",
	"fastener_steel_screw",
	"fastener_steel_bolt",
	"fastener_hinge",
	"fastener_ball_joint"
]

# Category filter options
enum CategoryFilter { ALL, STRUCTURAL_ITEMS, COSMETIC, HARDWARE, CONTAINERS }
var current_category_filter: CategoryFilter = CategoryFilter.ALL

# Signals
signal item_validated(success: bool, report: Dictionary)
signal workbench_closed


func _ready() -> void:
	# Add to workbench_window group so InputManager can detect when it's open
	add_to_group("workbench_window")

	# Get node references
	viewport_container = $VBoxContainer/MainContent/ViewportContainer
	selection_overlay = $VBoxContainer/MainContent/ViewportContainer/SelectionOverlay
	transform_stats_label = $VBoxContainer/MainContent/ViewportContainer/TransformStatsLabel
	object_info_label = $VBoxContainer/MainContent/ViewportContainer/ObjectInfoLabel
	viewport = $VBoxContainer/MainContent/ViewportContainer/SubViewport
	camera = $VBoxContainer/MainContent/ViewportContainer/SubViewport/Camera3D
	world = $VBoxContainer/MainContent/ViewportContainer/SubViewport/World
	grid = $VBoxContainer/MainContent/ViewportContainer/SubViewport/World/Grid
	part_list = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/PartsSection/PartList
	category_filter = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/PartsSection/CategoryFilterContainer/CategoryFilter
	add_object_button = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/PartsSection/ButtonContainer/AddObjectButton
	validate_button = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/ValidateButton
	clear_button = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/ClearButton
	help_label = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/HelpLabel
	sidebar_panel = $VBoxContainer/MainContent/SidebarPanel
	separator = $VBoxContainer/MainContent/Separator

	# Create context menu (kept persistent like inventory system)
	context_menu = ContextMenu_Base.new()
	context_menu.name = "WorkbenchContextMenu"
	add_child(context_menu)

	# Connect context menu signals
	context_menu.item_selected.connect(_on_context_menu_item_selected)
	context_menu.menu_closed.connect(_on_context_menu_closed)

	# Get transform panel references
	transform_panel = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel
	position_x_input = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/PositionX/SpinBox
	position_y_input = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/PositionY/SpinBox
	position_z_input = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/PositionZ/SpinBox
	rotation_x_input = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/RotationX/SpinBox
	rotation_y_input = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/RotationY/SpinBox
	rotation_z_input = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/RotationZ/SpinBox
	scale_x_input = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/ScaleX/SpinBox
	scale_y_input = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/ScaleY/SpinBox
	scale_z_input = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/ScaleZ/SpinBox

	# Get transform mode button references
	select_button = $VBoxContainer/MainContent/ViewportContainer/TransformModeButtons/SelectButton
	move_button = $VBoxContainer/MainContent/ViewportContainer/TransformModeButtons/MoveButton
	rotate_button = $VBoxContainer/MainContent/ViewportContainer/TransformModeButtons/RotateButton
	scale_button = $VBoxContainer/MainContent/ViewportContainer/TransformModeButtons/ScaleButton

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
	if category_filter:
		category_filter.item_selected.connect(_on_category_filter_changed)
	if add_object_button:
		add_object_button.pressed.connect(_on_add_object_pressed)
	if clear_button:
		clear_button.pressed.connect(_on_clear_button_pressed)

	# Connect transform mode button signals
	if select_button:
		select_button.pressed.connect(_on_select_button_pressed)
	if move_button:
		move_button.pressed.connect(_on_move_button_pressed)
	if rotate_button:
		rotate_button.pressed.connect(_on_rotate_button_pressed)
	if scale_button:
		scale_button.pressed.connect(_on_scale_button_pressed)

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

	# Connect viewport container mouse exit signal
	if viewport_container:
		viewport_container.mouse_exited.connect(_on_viewport_mouse_exited)

	# Connect separator signals for dragging
	if separator:
		separator.gui_input.connect(_on_separator_gui_input)

	# Connect transform input signals
	if position_x_input:
		position_x_input.value_changed.connect(_on_position_x_changed)
	if position_y_input:
		position_y_input.value_changed.connect(_on_position_y_changed)
	if position_z_input:
		position_z_input.value_changed.connect(_on_position_z_changed)
	if rotation_x_input:
		rotation_x_input.value_changed.connect(_on_rotation_x_changed)
	if rotation_y_input:
		rotation_y_input.value_changed.connect(_on_rotation_y_changed)
	if rotation_z_input:
		rotation_z_input.value_changed.connect(_on_rotation_z_changed)
	if scale_x_input:
		scale_x_input.value_changed.connect(_on_scale_x_changed)
	if scale_y_input:
		scale_y_input.value_changed.connect(_on_scale_y_changed)
	if scale_z_input:
		scale_z_input.value_changed.connect(_on_scale_z_changed)

	# Initialize sidebar width
	if sidebar_panel:
		sidebar_initial_width = sidebar_panel.custom_minimum_size.x

	# Update camera initial position
	_update_camera_transform()

	# Initialize button states to match current mode
	_update_mode_buttons()

	# Initialize help label visibility
	if help_label:
		help_label.visible = controls_visible

	initialized = true
	print("WorkbenchWindow ready - Use Alt+Mouse to navigate, Q/W/E/R for tools")


func _notification(what: int) -> void:
	"""Handle window notifications for focus changes."""
	match what:
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_reset_all_drag_states()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_reset_all_drag_states()


func _reset_all_drag_states() -> void:
	"""Reset all dragging and input states to prevent stuck controls."""
	# Reset camera dragging
	if is_dragging_camera:
		is_dragging_camera = false
		drag_button = -1
		print("Camera drag cancelled (focus lost)")

	# Reset gizmo dragging
	if is_gizmo_dragging:
		# Don't cancel the operation, just stop the drag
		# This preserves any partial transformations
		is_gizmo_dragging = false
		gizmo_drag_initial_positions.clear()
		gizmo_drag_initial_rotations.clear()
		gizmo_drag_initial_scales.clear()
		_clear_transform_stats()
		# Clear any negative scale warning
		_update_negative_scale_feedback(false)
		print("Gizmo drag cancelled (focus lost)")

	# Reset box selection
	if is_box_selecting:
		is_box_selecting = false
		if selection_overlay:
			selection_overlay.queue_redraw()
		print("Box selection cancelled (focus lost)")

	# Reset separator dragging
	if is_dragging_separator:
		is_dragging_separator = false

	# Reset modifier key states
	is_alt_held = false
	snap_to_grid_enabled = false


func _on_viewport_mouse_exited() -> void:
	"""Handle mouse leaving the viewport area."""
	# Don't reset on mouse exit - let the global input handlers deal with it
	# This prevents canceling operations during normal dragging outside viewport
	pass


func _on_separator_gui_input(event: InputEvent) -> void:
	"""Handle input events on the separator for dragging."""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Start dragging
				is_dragging_separator = true
				sidebar_drag_start_x = get_global_mouse_position().x
				if sidebar_panel:
					sidebar_initial_width = sidebar_panel.custom_minimum_size.x
			else:
				# Stop dragging
				is_dragging_separator = false

	elif event is InputEventMouseMotion and is_dragging_separator:
		# Update sidebar width based on mouse position
		var current_x = get_global_mouse_position().x
		var delta_x = current_x - sidebar_drag_start_x

		if sidebar_panel:
			var new_width = sidebar_initial_width + delta_x
			# Clamp to reasonable values (min 150px, max 600px)
			new_width = clamp(new_width, 150.0, 600.0)
			sidebar_panel.custom_minimum_size.x = new_width


func _populate_part_list() -> void:
	"""Fill the part list with available items to spawn, filtered by category."""
	if not part_list:
		return
	part_list.clear()

	for part_name in available_parts.keys():
		# Check if part matches current filter
		if _should_show_part(part_name):
			part_list.add_item(part_name.replace("_", " ").capitalize())


func _should_show_part(part_name: String) -> bool:
	"""Check if a part should be shown based on the current category filter."""
	if current_category_filter == CategoryFilter.ALL:
		return true

	# Get the part's category
	var part_category = part_categories.get(part_name, "")

	# Match filter to category
	match current_category_filter:
		CategoryFilter.STRUCTURAL_ITEMS:
			return part_category == "structural_items"
		CategoryFilter.COSMETIC:
			return part_category == "cosmetic"
		CategoryFilter.HARDWARE:
			return part_category == "hardware"
		CategoryFilter.CONTAINERS:
			return part_category == "containers"

	return false


func _on_category_filter_changed(index: int) -> void:
	"""Handle category filter selection change."""
	current_category_filter = index as CategoryFilter
	_populate_part_list()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Track Alt key for camera controls globally (even outside viewport)
	# This prevents Alt from getting stuck when released outside the window
	if event is InputEventKey:
		if event.keycode == KEY_ALT:
			var was_alt_held = is_alt_held
			is_alt_held = event.pressed

			# If Alt was released while dragging camera, stop the camera drag
			if was_alt_held and not is_alt_held and is_dragging_camera:
				is_dragging_camera = false
				drag_button = -1
				print("Camera drag cancelled (Alt released)")

	# Track mouse button releases globally to prevent stuck drags
	# Only handle releases outside the viewport to prevent interference with normal operation
	if event is InputEventMouseButton and not event.pressed:
		var mouse_over_viewport = _is_mouse_over_viewport()

		# If mouse is NOT over viewport, handle releases to prevent stuck states
		if not mouse_over_viewport:
			# If the mouse button that was being used for dragging is released, stop dragging
			if is_dragging_camera and event.button_index == drag_button:
				is_dragging_camera = false
				drag_button = -1
				print("Camera drag ended (outside viewport)")

			# If left mouse is released, cancel gizmo drag or box selection
			if event.button_index == MOUSE_BUTTON_LEFT:
				if is_gizmo_dragging:
					# Record the operation for undo before clearing
					_record_transform_operation()
					is_gizmo_dragging = false
					gizmo_drag_initial_positions.clear()
					gizmo_drag_initial_rotations.clear()
					gizmo_drag_initial_scales.clear()
					_clear_transform_stats()
					# Clear any negative scale warning
					_update_negative_scale_feedback(false)
					print("Gizmo drag ended (outside viewport)")

				if is_box_selecting:
					is_box_selecting = false
					if selection_overlay:
						selection_overlay.queue_redraw()
					print("Box selection ended (outside viewport)")

	# Check if we're in the middle of an operation
	var is_active_operation = is_gizmo_dragging or is_dragging_camera or is_box_selecting

	# Only check viewport bounds if we're not in the middle of an operation
	if not is_active_operation and not _is_mouse_over_viewport():
		return

	# Track other keys for workbench controls
	if event is InputEventKey:
		# Track X key for snap to grid
		if event.keycode == KEY_X:
			snap_to_grid_enabled = event.pressed
			if event.pressed:
				print("Snap to grid enabled (grid size: ", grid_snap_size, ")")
			else:
				print("Snap to grid disabled")

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
			elif event.keycode == KEY_Z and Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_SHIFT):
				_undo_last_operation()
			# Redo (Ctrl+Shift+Z or Ctrl+Y)
			elif (event.keycode == KEY_Z and Input.is_key_pressed(KEY_CTRL) and Input.is_key_pressed(KEY_SHIFT)) or (event.keycode == KEY_Y and Input.is_key_pressed(KEY_CTRL)):
				_redo_last_operation()
			# Delete selected objects (DEL or Backspace)
			elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
				_delete_selected_items()
			# Duplicate selected objects (Ctrl+D)
			elif event.keycode == KEY_D and Input.is_key_pressed(KEY_CTRL):
				_duplicate_selected_items()

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

		# Clear any negative scale warning
		_update_negative_scale_feedback(false)
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
			# Calculate dynamic pitch limit to prevent camera from going through the floor
			var min_pitch = _calculate_min_pitch_for_target()
			camera_rotation.y = clamp(camera_rotation.y + delta.y * 0.3, min_pitch, 89)
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
			var mouse_pos = selection_overlay.get_local_mouse_position()
			# Clamp to viewport bounds
			var viewport_rect = Rect2(Vector2.ZERO, viewport_container.size)
			mouse_pos.x = clamp(mouse_pos.x, viewport_rect.position.x, viewport_rect.position.x + viewport_rect.size.x)
			mouse_pos.y = clamp(mouse_pos.y, viewport_rect.position.y, viewport_rect.position.y + viewport_rect.size.y)
			box_select_end = mouse_pos

	# Gizmo hover detection (when not dragging anything)
	elif not is_dragging_camera and not is_box_selecting:
		_update_gizmo_hover(event.position)

	last_mouse_pos = event.position


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


func _update_camera_transform() -> void:
	"""Update camera position based on orbit controls."""
	if not camera:
		return

	# Convert rotation to radians
	var yaw_rad = deg_to_rad(camera_rotation.x)
	var pitch_rad = deg_to_rad(camera_rotation.y)

	# Calculate camera position
	var offset = Vector3(cos(pitch_rad) * sin(yaw_rad), sin(pitch_rad), cos(pitch_rad) * cos(yaw_rad)) * camera_distance

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
		was_x_pressed = Input.is_key_pressed(KEY_X)

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
		was_ctrl_pressed = Input.is_key_pressed(KEY_CTRL)

		# Store initial plane origin and camera distance
		gizmo_drag_plane_origin = gizmo_pos
		gizmo_drag_camera_distance = gizmo_pos.distance_to(camera.global_position)

		# Store initial rotations (use Dictionary to store rotation as Basis)
		gizmo_drag_initial_positions.clear()
		gizmo_drag_initial_rotations.clear()
		for item in selected_items:
			gizmo_drag_initial_rotations[item] = item.basis

		# If CTRL is held, immediately snap to nearest 15-degree increment
		if was_ctrl_pressed:
			_snap_rotation_to_increment(axis_detected)

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
		var axes = [{"dir": Vector3.RIGHT, "vec": Vector3.RIGHT}, {"dir": Vector3.UP, "vec": Vector3.UP}, {"dir": Vector3.BACK, "vec": Vector3.BACK}]

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

	if current_transform_mode == TransformMode.ROTATE:
		# Rotate gizmo detection: ImGuizmo-style approach
		# Uses ray-plane intersection + screen-space distance for reliable detection
		# Torus is created with radius 0.70 * gizmo_size (where gizmo_size = 1.5)
		# Then scaled by gizmo_scale, so actual radius = 0.70 * 1.5 * gizmo_scale = 1.05 * gizmo_scale
		var circle_radius = 1.05 * gizmo_scale
		var axes = [{"axis": Vector3.RIGHT, "name": "X"}, {"axis": Vector3.UP, "name": "Y"}, {"axis": Vector3.BACK, "name": "Z"}]

		# Sort axes by visibility: circles most perpendicular to camera view are most visible
		# This prioritizes the "front-facing" circles when overlapping
		var camera_forward = -camera.global_transform.basis.z
		var sorted_axes = []
		for axis_data in axes:
			var axis = axis_data["axis"]
			# Circle is most visible when its normal (rotation axis) is perpendicular to camera
			var perpendicularity = abs(axis.dot(camera_forward))
			sorted_axes.append({"axis": axis, "name": axis_data["name"], "priority": perpendicularity})

		# Sort by priority: lower priority = more perpendicular = more visible = test first
		sorted_axes.sort_custom(func(a, b): return a["priority"] < b["priority"])

		var closest_screen_dist = INF
		var closest_axis = Vector3.ZERO
		var ray_origin = camera.project_ray_origin(mouse_pos)
		var ray_dir = camera.project_ray_normal(mouse_pos)

		# Test axes in visibility order (most visible first)
		for axis_data in sorted_axes:
			var axis = axis_data["axis"]
			var priority = axis_data["priority"]

			# Build plane containing the rotation circle (plane normal = axis)
			var plane_normal = axis
			var plane = Plane(plane_normal, gizmo_pos.dot(plane_normal))

			# Intersect ray with plane
			var intersection = plane.intersects_ray(ray_origin, ray_dir)
			if intersection == null:
				continue

			# Get local position on plane relative to gizmo center
			var local_pos = intersection - gizmo_pos

			# Check if intersection is behind gizmo (basic depth test)
			var to_intersection = intersection - gizmo_pos
			var to_camera = camera.global_position - gizmo_pos
			if to_intersection.dot(to_camera) < 0:
				continue

			# Project to circle: normalize and scale to circle radius
			var local_distance = local_pos.length()
			if local_distance < 0.001:
				continue  # Too close to center

			var ideal_pos_on_circle = (local_pos / local_distance) * circle_radius
			var world_pos_on_circle = gizmo_pos + ideal_pos_on_circle

			# No backface culling - full circle is detectable
			# Visibility sorting handles which circle takes priority when overlapping

			# Convert to screen space and measure distance
			var screen_pos_on_circle = camera.unproject_position(world_pos_on_circle)
			var screen_dist = mouse_pos.distance_to(screen_pos_on_circle)

			# Use a reasonable threshold (ImGuizmo uses 8, we use 12 for easier selection)
			var threshold = 12.0

			if screen_dist < threshold:
				# Prefer circles with better visibility when distances are close
				# If this circle is significantly closer OR has better priority with similar distance
				var distance_improvement = closest_screen_dist - screen_dist
				if screen_dist < closest_screen_dist or (distance_improvement < 3.0 and priority < 0.3):
					closest_screen_dist = screen_dist
					closest_axis = axis

		return closest_axis

	if current_transform_mode == TransformMode.SCALE:
		# Scale gizmo detection: check center box first, then handles
		var center_screen = camera.unproject_position(gizmo_pos)
		if mouse_pos.distance_to(center_screen) < 25.0:
			return Vector3(1, 1, 1)  # Uniform scale

		# Then check scale handles (similar to arrows)
		var handle_length = 0.7 * gizmo_scale
		var axes = [{"dir": Vector3.RIGHT, "vec": Vector3.RIGHT}, {"dir": Vector3.UP, "vec": Vector3.UP}, {"dir": Vector3.BACK, "vec": Vector3.BACK}]

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


func _closest_point_on_circle_to_ray(circle_center: Vector3, circle_normal: Vector3, circle_radius: float, ray_origin: Vector3, ray_dir: Vector3) -> Dictionary:
	"""
	Calculate the closest point on a 3D circle to a ray.
	Returns a dictionary with 'point' and 'distance', or null if no valid solution.

	Algorithm:
	1. Find the closest point on the ray to the circle's plane
	2. Project that point onto the circle
	3. Calculate the distance from the ray to that circle point
	"""
	circle_normal = circle_normal.normalized()
	ray_dir = ray_dir.normalized()

	# Step 1: Find intersection of ray with the plane containing the circle
	var denom = circle_normal.dot(ray_dir)

	# If ray is parallel to the plane, use a different approach
	if abs(denom) < 0.0001:
		# Ray is parallel to circle plane - find closest point on ray to circle center
		var to_center = circle_center - ray_origin
		var t = to_center.dot(ray_dir)
		var closest_on_ray = ray_origin + ray_dir * max(0.0, t)

		# Project this point onto the circle's plane
		var offset = circle_center - closest_on_ray
		var plane_dist = offset.dot(circle_normal)
		var point_on_plane = closest_on_ray + circle_normal * plane_dist

		# Find the closest point on the circle to this point
		var radial = point_on_plane - circle_center
		var radial_in_plane = radial - circle_normal * radial.dot(circle_normal)
		var dist_from_center = radial_in_plane.length()

		if dist_from_center < 0.0001:
			# Point is at circle center, pick arbitrary point on circle
			var arbitrary_dir = Vector3.UP if abs(circle_normal.y) < 0.9 else Vector3.RIGHT
			radial_in_plane = circle_normal.cross(arbitrary_dir).normalized()
			dist_from_center = 1.0

		var closest_on_circle = circle_center + radial_in_plane.normalized() * circle_radius
		var distance = closest_on_circle.distance_to(closest_on_ray)

		return {"point": closest_on_circle, "distance": distance}

	# Step 2: Ray intersects plane - find the intersection point
	var to_plane = circle_center - ray_origin
	var t = to_plane.dot(circle_normal) / denom

	# Use the intersection point (even if behind ray, we'll cull it later)
	var plane_intersection = ray_origin + ray_dir * t

	# Step 3: Find closest point on circle to the plane intersection
	var radial = plane_intersection - circle_center

	# Remove the component along the normal (project onto plane)
	var radial_in_plane = radial - circle_normal * radial.dot(circle_normal)
	var dist_from_center = radial_in_plane.length()

	# Handle special case: intersection is at circle center
	if dist_from_center < 0.0001:
		# Pick a direction perpendicular to both ray and normal
		var perp = ray_dir.cross(circle_normal)
		if perp.length_squared() < 0.0001:
			# Ray is along the normal, pick arbitrary direction
			var arbitrary = Vector3.UP if abs(circle_normal.y) < 0.9 else Vector3.RIGHT
			perp = circle_normal.cross(arbitrary)
		radial_in_plane = perp.normalized()
		dist_from_center = 1.0

	# Project onto circle
	var closest_on_circle = circle_center + radial_in_plane.normalized() * circle_radius

	# Step 4: Calculate minimum distance from ray to this circle point
	# Find closest point on ray to the circle point
	var to_circle_point = closest_on_circle - ray_origin
	var ray_t = to_circle_point.dot(ray_dir)
	var closest_on_ray = ray_origin + ray_dir * max(0.0, ray_t)
	var distance = closest_on_circle.distance_to(closest_on_ray)

	return {"point": closest_on_circle, "distance": distance}


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

	# Clamp mouse position to viewport bounds for gizmo dragging
	var viewport_rect = Rect2(Vector2.ZERO, viewport_container.size)
	viewport_pos.x = clamp(viewport_pos.x, viewport_rect.position.x, viewport_rect.position.x + viewport_rect.size.x)
	viewport_pos.y = clamp(viewport_pos.y, viewport_rect.position.y, viewport_rect.position.y + viewport_rect.size.y)

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

	# Detect if X key state changed during drag (snap to grid)
	var is_x_pressed = Input.is_key_pressed(KEY_X)
	if is_x_pressed != was_x_pressed:
		# X state changed - store current positions as new initial positions
		var viewport_pos = viewport_container.get_local_mouse_position()
		gizmo_drag_start_mouse = viewport_pos
		was_x_pressed = is_x_pressed

		# Update initial positions to current positions
		for item in selected_items:
			if item in gizmo_drag_initial_positions:
				gizmo_drag_initial_positions[item] = item.global_position

		# Reset mouse_delta since we're starting fresh
		mouse_delta = Vector2.ZERO

	var world_offset = Vector3.ZERO

	# Check if dragging on a plane (2 axes) or single axis
	var num_axes = int(gizmo_drag_axis.x != 0) + int(gizmo_drag_axis.y != 0) + int(gizmo_drag_axis.z != 0)

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
			var new_position = gizmo_drag_initial_positions[item] + world_offset

			# Apply snap to grid if X key is held
			if snap_to_grid_enabled:
				new_position.x = round(new_position.x / grid_snap_size) * grid_snap_size
				new_position.y = round(new_position.y / grid_snap_size) * grid_snap_size
				new_position.z = round(new_position.z / grid_snap_size) * grid_snap_size

			item.global_position = new_position


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

	# Detect if Ctrl state changed during drag (for angle snapping)
	var is_ctrl_pressed = Input.is_key_pressed(KEY_CTRL)
	if is_ctrl_pressed != was_ctrl_pressed:
		# Ctrl state changed
		var viewport_pos = viewport_container.get_local_mouse_position()
		gizmo_drag_start_mouse = viewport_pos
		was_ctrl_pressed = is_ctrl_pressed

		# Update initial rotations to current rotations
		for item in selected_items:
			if item in gizmo_drag_initial_rotations:
				gizmo_drag_initial_rotations[item] = item.basis

		# If CTRL was just pressed, snap to nearest increment
		if is_ctrl_pressed:
			_snap_rotation_to_increment(gizmo_drag_axis)

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


func _snap_rotation_to_increment(axis: Vector3) -> void:
	"""Snap the current rotation to the nearest 15-degree increment on the specified axis."""
	var snap_increment = deg_to_rad(15.0)

	for item in selected_items:
		# Get current rotation as Euler angles
		var current_euler = item.rotation

		# Snap the rotation on the specified axis
		if axis == Vector3.RIGHT:
			# X axis rotation
			var snapped_angle = round(current_euler.x / snap_increment) * snap_increment
			item.rotation.x = snapped_angle
		elif axis == Vector3.UP:
			# Y axis rotation
			var snapped_angle = round(current_euler.y / snap_increment) * snap_increment
			item.rotation.y = snapped_angle
		elif axis == Vector3.BACK:
			# Z axis rotation
			var snapped_angle = round(current_euler.z / snap_increment) * snap_increment
			item.rotation.z = snapped_angle

		# Update the initial rotation to the snapped value to prevent jumping
		if item in gizmo_drag_initial_rotations:
			gizmo_drag_initial_rotations[item] = item.basis

	# Update gizmo position
	_update_gizmo()

	print("Snapped rotation to nearest 15° increment")


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
		scale_multiplier = max(0.01, scale_multiplier)  # Prevent zero or negative scale

	var num_axes = int(gizmo_drag_axis.x != 0) + int(gizmo_drag_axis.y != 0) + int(gizmo_drag_axis.z != 0)

	# Update stats display
	_update_transform_stats("Scale", scale_multiplier, gizmo_drag_axis)

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
	_update_negative_scale_feedback(has_negative_scale)


func _update_negative_scale_feedback(is_negative: bool) -> void:
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


func _is_mouse_over_viewport() -> bool:
	"""Check if mouse is currently over the 3D viewport."""
	if not viewport_container:
		return false

	var mouse_pos = viewport_container.get_local_mouse_position()
	var rect = Rect2(Vector2.ZERO, viewport_container.size)
	if not rect.has_point(mouse_pos):
		return false

	# Check if mouse is over UI buttons
	if _is_mouse_over_ui():
		return false

	return true


func _is_mouse_over_ui() -> bool:
	"""Check if mouse is over any UI elements in the viewport."""
	# Check transform mode buttons
	if select_button and select_button.get_global_rect().has_point(get_global_mouse_position()):
		return true
	if move_button and move_button.get_global_rect().has_point(get_global_mouse_position()):
		return true
	if rotate_button and rotate_button.get_global_rect().has_point(get_global_mouse_position()):
		return true
	if scale_button and scale_button.get_global_rect().has_point(get_global_mouse_position()):
		return true

	return false


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
		print("Raycast hit item: %s (instance: %s)" % [item.item_name, item.get_instance_id()])

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
		print("Raycast hit nothing")
		# Clicked empty space - deselect all
		if not Input.is_key_pressed(KEY_SHIFT):
			_clear_selection()


func _try_box_select() -> void:
	"""Select all items within the box selection area."""
	if not camera or not world:
		return

	# Create selection rectangle (normalize in case user dragged backwards)
	var rect_min = Vector2(min(box_select_start.x, box_select_end.x), min(box_select_start.y, box_select_end.y))
	var rect_max = Vector2(max(box_select_start.x, box_select_end.x), max(box_select_start.y, box_select_end.y))
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

			# For JointHelper, use a small AABB around the cross shape (15cm bars)
			if item is JointHelper:
				aabb = AABB(Vector3(-0.075, -0.075, -0.075), Vector3(0.15, 0.15, 0.15))
			elif item.has_node("MeshInstance3D"):
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

			# Check visibility: only select if object is in front of camera
			var is_in_front = false
			for corner in corners:
				var to_corner = corner - camera.global_position
				var forward = -camera.global_transform.basis.z
				if to_corner.dot(forward) > 0:
					is_in_front = true
					break

			if not is_in_front:
				continue

			# Project all corners to screen space
			var screen_corners: Array[Vector2] = []
			for corner in corners:
				screen_corners.append(camera.unproject_position(corner))

			# Create screen-space bounding rect for the item
			var screen_min = Vector2(INF, INF)
			var screen_max = Vector2(-INF, -INF)
			for screen_pos in screen_corners:
				screen_min.x = min(screen_min.x, screen_pos.x)
				screen_min.y = min(screen_min.y, screen_pos.y)
				screen_max.x = max(screen_max.x, screen_pos.x)
				screen_max.y = max(screen_max.y, screen_pos.y)
			var item_screen_rect = Rect2(screen_min, screen_max - screen_min)

			# Proper intersection test: check if rectangles actually overlap
			# This prevents false positives when selection box is near but not touching
			if selection_rect.intersects(item_screen_rect, true):
				# Additional accuracy check: verify that at least one corner is actually inside
				# This helps with rotated objects where AABB might be larger than visual bounds
				var has_real_overlap = false

				# Check if any object corner is inside selection rect
				for screen_pos in screen_corners:
					if selection_rect.has_point(screen_pos):
						has_real_overlap = true
						break

				# Check if any selection rect corner is inside object rect
				if not has_real_overlap:
					var sel_corners = [
						selection_rect.position,
						selection_rect.position + Vector2(selection_rect.size.x, 0),
						selection_rect.position + Vector2(0, selection_rect.size.y),
						selection_rect.position + selection_rect.size
					]
					for sel_corner in sel_corners:
						if item_screen_rect.has_point(sel_corner):
							has_real_overlap = true
							break

				if has_real_overlap:
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
	_update_object_info()


func _deselect_item(item: PhysicalItem) -> void:
	"""Deselect a specific item."""
	if item in selected_items:
		selected_items.erase(item)
		item.show_highlight(false)
		print("Deselected: ", item.item_name)
	_update_object_info()


func _clear_selection() -> void:
	"""Clear all selected items."""
	for item in selected_items:
		item.show_highlight(false)
	selected_items.clear()
	_update_gizmo()
	_update_object_info()


func _delete_selected_items() -> void:
	"""Delete all currently selected items."""
	if selected_items.is_empty():
		return

	var count = selected_items.size()

	# Remove all selected items from the scene
	for item in selected_items:
		if is_instance_valid(item):
			item.queue_free()

	# Clear selection array
	selected_items.clear()

	# Update UI
	_update_gizmo()
	_update_object_info()

	print("Deleted ", count, " object(s)")


func _select_all_items() -> void:
	"""Select all PhysicalItem objects in the world."""
	# Clear current selection first
	_clear_selection()

	# Find all PhysicalItems in the world
	for child in world.get_children():
		if child is PhysicalItem:
			var item = child as PhysicalItem
			_select_item(item, true)

	print("Selected all items (", selected_items.size(), " object(s))")


func _toggle_grid_visibility() -> void:
	"""Toggle the visibility of the grid."""
	if grid:
		grid.visible = not grid.visible
		var status = "visible" if grid.visible else "hidden"
		print("Grid is now ", status)


func _duplicate_selected_items() -> void:
	"""Duplicate all currently selected items (industry standard: duplicate in place)."""
	if selected_items.is_empty():
		return

	var duplicated_items: Array[PhysicalItem] = []

	# Store original selection to deselect later
	var original_items = selected_items.duplicate()

	# First, deselect all originals to remove blue highlight
	# This ensures the duplicates don't copy the blue material
	_clear_selection()

	# Duplicate each item
	for item in original_items:
		if not is_instance_valid(item):
			continue

		# Duplicate the item (now that it's deselected, no blue material)
		var duplicated_item = item.duplicate(DUPLICATE_USE_INSTANTIATION) as PhysicalItem
		if not duplicated_item:
			continue

		# Add to world
		world.add_child(duplicated_item)

		# Position at exact same location as original (no offset - industry standard)
		duplicated_item.global_position = item.global_position
		duplicated_item.rotation = item.rotation
		duplicated_item.scale = item.scale

		# Keep frozen state
		duplicated_item.freeze = true

		duplicated_items.append(duplicated_item)

	# Now select only the duplicates
	for item in duplicated_items:
		_select_item(item, true)

	print("Duplicated ", duplicated_items.size(), " object(s) in place")


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

	# Update button states
	_update_mode_buttons()

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
	if not context_menu:
		return

	# Clear existing menu items
	context_menu.clear_items()

	# Check if we clicked on an item
	var clicked_on_item = false
	if hovered_item != null:
		clicked_on_item = true

	if clicked_on_item:
		# Context menu for when an item is clicked
		context_menu.add_menu_item("duplicate", "Duplicate")
		context_menu.add_menu_item("delete", "Delete")
		context_menu.add_separator()

		# Fastener attachment options (only if 2+ items selected)
		if selected_items.size() >= 2:
			context_menu.add_menu_item("attach_fastener", "Attach with Fastener...")
			context_menu.add_separator()

		context_menu.add_menu_item("frame_selected", "Frame Selected", null, not selected_items.is_empty())
		context_menu.add_separator()
		context_menu.add_menu_item("select_all", "Select All")
		context_menu.add_menu_item("select_none", "Select None", null, not selected_items.is_empty())
	else:
		# Context menu for when clicking on empty space
		# Fastener attachment options (only if 2+ items selected)
		if selected_items.size() >= 2:
			context_menu.add_menu_item("attach_fastener", "Attach with Fastener...")
			context_menu.add_separator()

		context_menu.add_menu_item("select_all", "Select All")
		context_menu.add_menu_item("select_none", "Select None", null, not selected_items.is_empty())
		context_menu.add_separator()
		context_menu.add_menu_item("frame_selected", "Frame Selected", null, not selected_items.is_empty())
		context_menu.add_separator()
		var grid_text = "Hide Grid" if grid.visible else "Show Grid"
		context_menu.add_menu_item("toggle_grid", grid_text)
		context_menu.add_separator()
		context_menu.add_menu_item("undo", "Undo", null, not undo_history.is_empty())
		context_menu.add_menu_item("redo", "Redo", null, not redo_history.is_empty())

	# Show the menu at mouse position
	var context_data = {}
	# Pass the window reference for proper positioning (important for editor scene testing)
	var parent_window = get_window() if get_window() else null
	context_menu.show_context_menu(Vector2.ZERO, context_data, parent_window)


func _on_context_menu_item_selected(item_id: String, _item_data: Dictionary, _context_data: Dictionary) -> void:
	"""Handle context menu item selection."""
	match item_id:
		"select_all":
			_select_all_items()
		"select_none":
			_clear_selection()
		"frame_selected":
			_frame_selection()
		"toggle_grid":
			_toggle_grid_visibility()
		"undo":
			_undo_last_operation()
		"redo":
			_redo_last_operation()
		"duplicate":
			_duplicate_selected_items()
		"delete":
			_delete_selected_items()
		"attach_fastener":
			_show_fastener_selection_dialog()


func _on_context_menu_closed() -> void:
	"""Handle context menu closure."""
	# Just grab focus back like inventory system does
	grab_focus()


func _on_part_selected(index: int) -> void:
	"""Spawn a new part when double-clicked from list."""
	var part_name = part_list.get_item_text(index).to_lower().replace(" ", "_")
	if part_name in available_parts:
		spawn_part(available_parts[part_name])


func _on_add_object_pressed() -> void:
	"""Add the selected object from the list when the Add Object button is pressed."""
	if not part_list:
		return

	var selected_indices = part_list.get_selected_items()
	if selected_indices.is_empty():
		print("No object selected in the list")
		return

	# Get the first selected item (ItemList should be in single-select mode)
	var index = selected_indices[0]
	var part_name = part_list.get_item_text(index).to_lower().replace(" ", "_")
	if part_name in available_parts:
		spawn_part(available_parts[part_name])


func _on_toggle_controls_pressed() -> void:
	"""Toggle visibility of the controls help text."""
	controls_visible = !controls_visible
	if help_label:
		help_label.visible = controls_visible
	print("Controls text ", "shown" if controls_visible else "hidden")


func _on_clear_button_pressed() -> void:
	"""Handle clear button press to clear all items from the workbench."""
	clear_workbench()


func _on_select_button_pressed() -> void:
	"""Handle select button press."""
	_set_transform_mode(TransformMode.SELECT)


func _on_move_button_pressed() -> void:
	"""Handle move button press."""
	_set_transform_mode(TransformMode.MOVE)


func _on_rotate_button_pressed() -> void:
	"""Handle rotate button press."""
	_set_transform_mode(TransformMode.ROTATE)


func _on_scale_button_pressed() -> void:
	"""Handle scale button press."""
	_set_transform_mode(TransformMode.SCALE)


# Transform input change handlers
func _on_position_x_changed(value: float) -> void:
	"""Handle position X input change."""
	if is_updating_transform_inputs or selected_items.is_empty():
		return

	for item in selected_items:
		var new_pos = item.global_position
		new_pos.x = value
		item.global_position = new_pos

	_update_gizmo()
	print("Position X set to: ", value)


func _on_position_y_changed(value: float) -> void:
	"""Handle position Y input change."""
	if is_updating_transform_inputs or selected_items.is_empty():
		return

	for item in selected_items:
		var new_pos = item.global_position
		new_pos.y = value
		item.global_position = new_pos

	_update_gizmo()
	print("Position Y set to: ", value)


func _on_position_z_changed(value: float) -> void:
	"""Handle position Z input change."""
	if is_updating_transform_inputs or selected_items.is_empty():
		return

	for item in selected_items:
		var new_pos = item.global_position
		new_pos.z = value
		item.global_position = new_pos

	_update_gizmo()
	print("Position Z set to: ", value)


func _on_rotation_x_changed(value: float) -> void:
	"""Handle rotation X input change."""
	if is_updating_transform_inputs or selected_items.is_empty():
		return

	for item in selected_items:
		var rot = item.rotation_degrees
		rot.x = value
		item.rotation_degrees = rot

	print("Rotation X set to: ", value, "°")


func _on_rotation_y_changed(value: float) -> void:
	"""Handle rotation Y input change."""
	if is_updating_transform_inputs or selected_items.is_empty():
		return

	for item in selected_items:
		var rot = item.rotation_degrees
		rot.y = value
		item.rotation_degrees = rot

	print("Rotation Y set to: ", value, "°")


func _on_rotation_z_changed(value: float) -> void:
	"""Handle rotation Z input change."""
	if is_updating_transform_inputs or selected_items.is_empty():
		return

	for item in selected_items:
		var rot = item.rotation_degrees
		rot.z = value
		item.rotation_degrees = rot

	print("Rotation Z set to: ", value, "°")


func _on_scale_x_changed(value: float) -> void:
	"""Handle scale X input change."""
	if is_updating_transform_inputs or selected_items.is_empty():
		return

	for item in selected_items:
		var new_scale = item.scale
		new_scale.x = value
		item.scale = new_scale

	print("Scale X set to: ", value)


func _on_scale_y_changed(value: float) -> void:
	"""Handle scale Y input change."""
	if is_updating_transform_inputs or selected_items.is_empty():
		return

	for item in selected_items:
		var new_scale = item.scale
		new_scale.y = value
		item.scale = new_scale

	print("Scale Y set to: ", value)


func _on_scale_z_changed(value: float) -> void:
	"""Handle scale Z input change."""
	if is_updating_transform_inputs or selected_items.is_empty():
		return

	for item in selected_items:
		var new_scale = item.scale
		new_scale.z = value
		item.scale = new_scale

	print("Scale Z set to: ", value)


func _update_mode_buttons() -> void:
	"""Update the visual state of transform mode buttons based on current mode."""
	if not select_button or not move_button or not rotate_button or not scale_button:
		return

	# Set button_pressed state without triggering signals
	select_button.set_pressed_no_signal(current_transform_mode == TransformMode.SELECT)
	move_button.set_pressed_no_signal(current_transform_mode == TransformMode.MOVE)
	rotate_button.set_pressed_no_signal(current_transform_mode == TransformMode.ROTATE)
	scale_button.set_pressed_no_signal(current_transform_mode == TransformMode.SCALE)


func spawn_part(scene_path: String) -> Node3D:
	"""Spawn a new part in the workbench."""
	var scene = load(scene_path) as PackedScene
	if not scene:
		push_error("Failed to load part scene: ", scene_path)
		return null

	var node = scene.instantiate()
	if not node:
		push_error("Failed to instantiate scene: ", scene_path)
		return null

	# Add to world
	world.add_child(node)

	# Position at grid origin (0, 0, 0)
	var spawn_pos = Vector3(0, 0, 0)
	node.global_position = spawn_pos

	# If it's a PhysicalItem, freeze it for placement
	if node is PhysicalItem:
		node.freeze = true
		print("Spawned PhysicalItem: %s (instance: %s) at origin" % [node.item_name, node.get_instance_id()])
	else:
		print("Spawned node: ", node.name, " at origin")

	return node


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
		if snap_to_grid_enabled:
			text += " [Grid Snap: %.2f]" % grid_snap_size
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
	text += ("\nSelected: %d object%s" % [selected_items.size(), "s" if selected_items.size() != 1 else ""])

	transform_stats_label.text = text


func _clear_transform_stats() -> void:
	"""Clear the transform stats label."""
	if transform_stats_label:
		transform_stats_label.text = ""


func _update_object_info() -> void:
	"""Update the object info label showing selected object's transform data."""
	if not object_info_label:
		return

	# Update transform panel visibility and values
	_update_transform_panel()

	if selected_items.is_empty():
		object_info_label.text = ""
		return

	if selected_items.size() > 1:
		# Multiple objects - show count and joint/fastener info
		var text = "Multiple Selected (%d objects)" % selected_items.size()
		var total_joints = 0
		var total_fasteners = 0

		for item in selected_items:
			total_joints += item.joints.size()
			total_fasteners += item.fasteners.size()

		if total_joints > 0:
			text += "\nJoints: %d" % total_joints
		if total_fasteners > 0:
			text += "\nFasteners: %d" % total_fasteners

		object_info_label.text = text
		return

	# Single object selected - show its transform info and joint/fastener info
	var item = selected_items[0]
	var pos = item.global_position
	var rot = item.rotation_degrees
	var scale_vec = item.scale

	var text = "Position: (%.2f, %.2f, %.2f)\n" % [pos.x, pos.y, pos.z]
	text += "Rotation: (%.1f°, %.1f°, %.1f°)\n" % [rot.x, rot.y, rot.z]
	text += "Scale: (%.2f, %.2f, %.2f)" % [scale_vec.x, scale_vec.y, scale_vec.z]

	# Add joint and fastener info
	if not item.joints.is_empty():
		text += "\nJoints: %d" % item.joints.size()
	if not item.fasteners.is_empty():
		text += "\nFasteners: %d" % item.fasteners.size()

	object_info_label.text = text


func _update_transform_panel() -> void:
	"""Update the transform panel with current selection's transform values."""
	if not transform_panel:
		return

	# Show panel only when items are selected
	if selected_items.is_empty():
		transform_panel.visible = false
		return

	transform_panel.visible = true

	# Only update if single object is selected (for clarity)
	if selected_items.size() != 1:
		return

	var item = selected_items[0]
	var pos = item.global_position
	var rot = item.rotation_degrees
	var scale_vec = item.scale

	# Set flag to prevent recursion
	is_updating_transform_inputs = true

	# Update position inputs
	if position_x_input:
		position_x_input.set_value_no_signal(pos.x)
	if position_y_input:
		position_y_input.set_value_no_signal(pos.y)
	if position_z_input:
		position_z_input.set_value_no_signal(pos.z)

	# Update rotation inputs
	if rotation_x_input:
		rotation_x_input.set_value_no_signal(rot.x)
	if rotation_y_input:
		rotation_y_input.set_value_no_signal(rot.y)
	if rotation_z_input:
		rotation_z_input.set_value_no_signal(rot.z)

	# Update scale inputs
	if scale_x_input:
		scale_x_input.set_value_no_signal(scale_vec.x)
	if scale_y_input:
		scale_y_input.set_value_no_signal(scale_vec.y)
	if scale_z_input:
		scale_z_input.set_value_no_signal(scale_vec.z)

	# Clear flag
	is_updating_transform_inputs = false


func _on_validate_pressed() -> void:
	"""Validate the current construct."""
	print("Validating construct...")

	var items = get_all_items()
	if items.is_empty():
		print("No items to validate")
		return

	# TODO: Implement actual validation in Phase 3
	var report = {"total_items": items.size(), "selected_items": selected_items.size(), "message": "Validation not yet implemented (Phase 3)"}

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
		var rect_min = Vector2(min(box_select_start.x, box_select_end.x), min(box_select_start.y, box_select_end.y))
		var rect_size = Vector2(abs(box_select_end.x - box_select_start.x), abs(box_select_end.y - box_select_start.y))
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

	# Update object info display (to show real-time transform changes)
	if not selected_items.is_empty():
		_update_object_info()


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

	# Distance-based culling: hide gizmo if too far away
	if camera:
		var distance = center.distance_to(camera.global_position)
		var max_distance = 50.0  # Maximum distance for gizmo interaction

		if distance > max_distance:
			transform_gizmo.visible = false
			return

	# Position and show gizmo
	transform_gizmo.set_target_position(center)
	transform_gizmo.visible = true


# Undo System Functions


func _record_transform_operation() -> void:
	"""Record a completed transform operation for undo."""
	if selected_items.is_empty():
		return

	var command = {"type": "", "items": selected_items.duplicate(), "old_values": {}, "new_values": {}}

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

			# Clear redo history when a new operation is recorded
			redo_history.clear()

			# Limit history size to MAX_UNDO_OPERATIONS
			if undo_history.size() > MAX_UNDO_OPERATIONS:
				undo_history.pop_front()

			print("Recorded undo: ", command["type"], " (", undo_history.size(), "/", MAX_UNDO_OPERATIONS, " operations)")


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

	# Add to redo history
	redo_history.append(command)

	# Limit redo history size
	if redo_history.size() > MAX_UNDO_OPERATIONS:
		redo_history.pop_front()

	# Update gizmo position
	_update_gizmo()

	print("Undo completed (", undo_history.size(), " undo | ", redo_history.size(), " redo)")


func _redo_last_operation() -> void:
	"""Redo the last undone operation."""
	if redo_history.is_empty():
		print("Nothing to redo")
		return

	var command = redo_history.pop_back()

	# Verify all items still exist
	var all_exist = true
	for item in command["items"]:
		if not is_instance_valid(item) or not item.is_inside_tree():
			all_exist = false
			break

	if not all_exist:
		print("Cannot redo: some items no longer exist")
		return

	# Apply the new values (the ones that were undone)
	match command["type"]:
		"move":
			for item in command["new_values"].keys():
				if is_instance_valid(item):
					item.global_position = command["new_values"][item]
			print("Redid move operation")

		"rotate":
			for item in command["new_values"].keys():
				if is_instance_valid(item):
					item.basis = command["new_values"][item]
			print("Redid rotate operation")

		"scale":
			for item in command["new_values"].keys():
				if is_instance_valid(item):
					item.scale = command["new_values"][item]
			print("Redid scale operation")

	# Add back to undo history
	undo_history.append(command)

	# Limit undo history size
	if undo_history.size() > MAX_UNDO_OPERATIONS:
		undo_history.pop_front()

	# Update gizmo position
	_update_gizmo()

	print("Redo completed (", undo_history.size(), " undo | ", redo_history.size(), " redo)")


## ========================================
## FASTENER SYSTEM METHODS
## ========================================

func _show_fastener_selection_dialog() -> void:
	"""Show a dialog to select which fastener to use for attaching selected items."""
	print("_show_fastener_selection_dialog called with %d selected items" % selected_items.size())

	if selected_items.size() < 2:
		print("ERROR: Need at least 2 items selected to attach with fastener")
		return

	# Remove any existing popup
	var existing_popup = get_node_or_null("FastenerSelectionPopup")
	if existing_popup:
		existing_popup.queue_free()

	# Create simple popup menu for fastener selection
	var popup = PopupMenu.new()
	popup.name = "FastenerSelectionPopup"

	# Add fastener options
	print("Adding %d fastener options..." % available_fasteners.size())
	for i in range(available_fasteners.size()):
		var fastener_id = available_fasteners[i]
		var fastener_name = _get_fastener_display_name(fastener_id)
		popup.add_item(fastener_name, i)
		print("  Added: %s" % fastener_name)

	# Connect signal
	popup.id_pressed.connect(_on_fastener_selected)
	popup.popup_hide.connect(func(): popup.queue_free())

	# Add to scene and show
	add_child(popup)
	var mouse_pos = get_global_mouse_position()
	popup.position = Vector2i(mouse_pos)
	popup.popup()
	print("Popup shown at %s" % mouse_pos)


func _get_fastener_display_name(fastener_id: String) -> String:
	"""Get display name for fastener from ItemDatabase."""
	if not ItemDatabase:
		return fastener_id

	var item_def = ItemDatabase.get_item(fastener_id)
	if item_def:
		return item_def.name

	return fastener_id


func _on_fastener_selected(index: int) -> void:
	"""Handle fastener selection from popup menu."""
	if index < 0 or index >= available_fasteners.size():
		return

	selected_fastener_id = available_fasteners[index]
	print("Selected fastener: %s" % selected_fastener_id)

	# Attach selected items with this fastener
	_attach_selected_items_with_fastener()


func _attach_selected_items_with_fastener() -> void:
	"""Attach all selected items together using the selected fastener."""
	print("_attach_selected_items_with_fastener called")
	print("  Selected items: %d" % selected_items.size())
	print("  Fastener: %s" % selected_fastener_id)

	if selected_items.size() < 2:
		print("ERROR: Need at least 2 items selected to attach")
		return

	# Get the first item as the base
	var base_item = selected_items[0]
	print("  Base item: %s" % base_item.item_name)

	# Attach all other items to the base
	var attached_count = 0
	for i in range(1, selected_items.size()):
		var target_item = selected_items[i]
		print("  Attempting to attach: %s" % target_item.item_name)

		# Calculate midpoint between items for connection point
		var connection_point = (base_item.global_position + target_item.global_position) / 2.0
		print("    Connection point: %s" % connection_point)

		# Attach using PhysicalItem's method
		var fastener = base_item.attach_with_fastener(
			target_item,
			selected_fastener_id,
			connection_point,
			world  # Use workbench world as parent for joints
		)

		if fastener:
			attached_count += 1
			print("    SUCCESS: Attached %s to %s with %s" % [target_item.item_name, base_item.item_name, selected_fastener_id])
		else:
			print("    FAILED: Could not attach %s to %s" % [target_item.item_name, base_item.item_name])

	if attached_count > 0:
		print("RESULT: Successfully attached %d items with %s" % [attached_count, selected_fastener_id])
		_update_object_info()
	else:
		print("RESULT: Failed to attach any items")
