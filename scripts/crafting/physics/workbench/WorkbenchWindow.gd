class_name WorkbenchWindow
extends Control

## A dedicated 3D assembly window with industry-standard controls.
##
## This is the modular version that delegates functionality to specialized managers.
## See the workbench/ subfolder for individual module documentation.

# Signals
signal item_validated(success: bool, report: Dictionary)
signal workbench_closed

# Transform modes
enum TransformMode { SELECT, MOVE, ROTATE, SCALE, CONNECT }
var current_transform_mode: TransformMode = TransformMode.SELECT

# Module instances
var camera_controller: WorkbenchCameraController
var selection_manager: WorkbenchSelectionManager
var gizmo_controller: WorkbenchGizmoController
var connect_mode: WorkbenchConnectMode
var undo_redo_manager: WorkbenchUndoRedo
var ui_manager: WorkbenchUIManager

# Core UI References (direct scene tree references)
var viewport_container: SubViewportContainer
var selection_overlay: Control
var viewport: SubViewport
var camera: Camera3D
var world: Node3D
var grid: MeshInstance3D
var ground_plane: MeshInstance3D
var world_environment: WorldEnvironment
var transform_gizmo: TransformGizmo
var context_menu: ContextMenu_Base

# Input state
var is_alt_held: bool = false
var initialized: bool = false
var controls_visible: bool = false

# Gizmo scale
var gizmo_scale: float = 1.0

# Manual transform input tracking (for undo/redo)
var manual_transform_initial_values: Dictionary = {}
var manual_transform_operation_type: String = ""
var manual_transform_timer: Timer = null
var manual_transform_is_editing: bool = false

# Part data
var available_parts: Dictionary = {
	"wooden_board_small": "res://scenes/crafting/parts/wooden_board_small.tscn",
	"wooden_board_large": "res://scenes/crafting/parts/wooden_board_large.tscn",
	"table_leg": "res://scenes/crafting/parts/table_leg.tscn",
	"tabletop": "res://scenes/crafting/parts/tabletop.tscn",
}

var part_categories: Dictionary = {
	"wooden_board_small": "structural_items",
	"wooden_board_large": "structural_items",
	"table_leg": "structural_items",
	"tabletop": "structural_items",
}


func _ready() -> void:
	add_to_group("workbench_window")

	# Get all node references
	_setup_node_references()

	# Initialize all managers
	_initialize_managers()

	# Setup manual transform timer for undo/redo
	manual_transform_timer = Timer.new()
	manual_transform_timer.wait_time = 0.5  # Wait 0.5 seconds after last edit
	manual_transform_timer.one_shot = true
	manual_transform_timer.timeout.connect(_on_manual_transform_timeout)
	add_child(manual_transform_timer)

	# Setup UI and get references
	var ui_refs = _setup_ui()

	# Connect signals
	_connect_all_signals(ui_refs)

	initialized = true
	print("WorkbenchWindow ready (Refactored) - Use Alt+Mouse to navigate, Q/W/E/R for tools")


func _setup_node_references() -> void:
	"""Get all required node references from the scene tree."""
	viewport_container = $VBoxContainer/MainContent/ViewportContainer
	selection_overlay = $VBoxContainer/MainContent/ViewportContainer/SelectionOverlay
	viewport = $VBoxContainer/MainContent/ViewportContainer/SubViewport
	camera = $VBoxContainer/MainContent/ViewportContainer/SubViewport/Camera3D
	world = $VBoxContainer/MainContent/ViewportContainer/SubViewport/World
	grid = $VBoxContainer/MainContent/ViewportContainer/SubViewport/World/Grid
	ground_plane = $VBoxContainer/MainContent/ViewportContainer/SubViewport/World/GroundPlane
	world_environment = $VBoxContainer/MainContent/ViewportContainer/SubViewport/WorldEnvironment

	# Set up viewport
	if viewport and viewport_container:
		viewport.size = viewport_container.size
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# Create context menu
	context_menu = ContextMenu_Base.new()
	context_menu.name = "WorkbenchContextMenu"
	add_child(context_menu)

	# Create transform gizmo
	transform_gizmo = TransformGizmo.new()
	world.add_child(transform_gizmo)
	transform_gizmo.visible = false


func _initialize_managers() -> void:
	"""Initialize all manager instances."""
	# Camera controller
	camera_controller = WorkbenchCameraController.new(camera, viewport)

	# Selection manager
	selection_manager = WorkbenchSelectionManager.new(camera, viewport, viewport_container, world, selection_overlay)

	# Gizmo controller
	gizmo_controller = WorkbenchGizmoController.new(camera, viewport, viewport_container, transform_gizmo, gizmo_scale)
	gizmo_controller.set_transform_mode(current_transform_mode as WorkbenchGizmoController.TransformMode)

	# Connect mode
	connect_mode = WorkbenchConnectMode.new(camera, viewport, viewport_container, world)

	# Undo/redo manager
	undo_redo_manager = WorkbenchUndoRedo.new()

	# UI manager
	ui_manager = WorkbenchUIManager.new()


func _setup_ui() -> Dictionary:
	"""Setup UI elements and references. Returns the ui_refs dictionary."""
	# Collect all UI references
	var ui_refs = {
		"part_list": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/PartsSection/PartList,
		"category_filter": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/PartsSection/CategoryFilterContainer/CategoryFilter,
		"add_object_button": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/PartsSection/ButtonContainer/AddObjectButton,
		"validate_button": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/ValidateButton,
		"clear_button": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/ClearButton,
		"connect_mode_button": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/ConnectModeButton,
		"help_label": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/HelpLabel,
		"select_button": $VBoxContainer/MainContent/ViewportContainer/TransformModeButtons/SelectButton,
		"move_button": $VBoxContainer/MainContent/ViewportContainer/TransformModeButtons/MoveButton,
		"rotate_button": $VBoxContainer/MainContent/ViewportContainer/TransformModeButtons/RotateButton,
		"scale_button": $VBoxContainer/MainContent/ViewportContainer/TransformModeButtons/ScaleButton,
		"transform_panel": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel,
		"position_x_input": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/PositionX/SpinBox,
		"position_y_input": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/PositionY/SpinBox,
		"position_z_input": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/PositionZ/SpinBox,
		"rotation_x_input": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/RotationX/SpinBox,
		"rotation_y_input": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/RotationY/SpinBox,
		"rotation_z_input": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/RotationZ/SpinBox,
		"scale_x_input": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/ScaleX/SpinBox,
		"scale_y_input": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/ScaleY/SpinBox,
		"scale_z_input": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/VSplitContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/ScaleZ/SpinBox,
		"transform_stats_label": $VBoxContainer/MainContent/ViewportContainer/TransformStatsLabel,
		"object_info_label": $VBoxContainer/MainContent/ViewportContainer/ObjectInfoLabel,
		"sidebar_panel": $VBoxContainer/MainContent/SidebarPanel,
		"separator": $VBoxContainer/MainContent/Separator,
		"world_environment": world_environment,
		"ground_plane": ground_plane,
		"grid": grid,
		"transform_gizmo": transform_gizmo,
		"available_parts": available_parts,
		"part_categories": part_categories,
	}

	ui_manager.setup_ui_references(ui_refs)
	ui_manager.populate_part_list()
	ui_manager.load_viewport_settings()

	return ui_refs


func _connect_all_signals(ui_refs: Dictionary) -> void:
	"""Connect all signal handlers for managers and UI."""
	# Context menu
	context_menu.item_selected.connect(_on_context_menu_item_selected)
	context_menu.menu_closed.connect(func(): grab_focus())

	# Selection overlay
	if selection_overlay:
		selection_overlay.draw.connect(func(): selection_manager.draw_selection_box(selection_overlay))

	# Viewport mouse events
	if viewport_container:
		viewport_container.mouse_exited.connect(_reset_all_drag_states)

	# Selection manager signals
	selection_manager.selection_changed.connect(_on_selection_changed)
	selection_manager.items_deleted.connect(func(_count): _update_all_ui())

	# Gizmo controller signals
	gizmo_controller.transform_started.connect(func(_mode): pass)
	gizmo_controller.transform_updated.connect(_on_transform_updated)
	gizmo_controller.transform_completed.connect(_on_transform_completed)
	gizmo_controller.gizmo_visibility_changed.connect(func(_vis): pass)

	# Connect mode signals
	connect_mode.fastener_placed.connect(_on_fastener_placed)
	connect_mode.connect_mode_toggled.connect(_on_connect_mode_toggled)

	# Undo/redo signals
	undo_redo_manager.history_changed.connect(func(_undo_count, _redo_count): pass)

	# Camera controller signals
	camera_controller.camera_moved.connect(func(_pos, _rot): pass)

	# UI Manager signals
	ui_manager.viewport_settings_changed.connect(_on_viewport_settings_changed)
	ui_manager.fastener_selected.connect(_on_fastener_selected)

	# Connect UI button signals
	_connect_ui_button_signals(ui_refs)


func _connect_ui_button_signals(ui_refs: Dictionary) -> void:
	"""Connect all UI button press signals."""
	# Part list
	var part_list_node = ui_refs.get("part_list")
	if part_list_node:
		print("WorkbenchWindow: Connecting item_activated signal to part_list")
		part_list_node.item_activated.connect(_on_part_selected)
	else:
		print("ERROR: part_list_node is null during signal connection")

	# Buttons
	var buttons = {
		"validate_button": func(): _on_validate_pressed(),
		"clear_button": func(): clear_workbench(),
		"add_object_button": func(): _on_add_object_pressed(),
		"select_button": func(): _set_transform_mode(TransformMode.SELECT),
		"move_button": func(): _set_transform_mode(TransformMode.MOVE),
		"rotate_button": func(): _set_transform_mode(TransformMode.ROTATE),
		"scale_button": func(): _set_transform_mode(TransformMode.SCALE),
	}

	for button_name in buttons:
		var button = ui_refs.get(button_name)
		if button:
			button.pressed.connect(buttons[button_name])

	# Connect mode button (toggle)
	var connect_btn = ui_refs.get("connect_mode_button")
	if connect_btn:
		connect_btn.toggled.connect(_on_connect_mode_button_toggled)

	# Category filter
	var cat_filter = ui_refs.get("category_filter")
	if cat_filter:
		cat_filter.item_selected.connect(func(_index): ui_manager.populate_part_list())

	# Transform inputs
	_connect_transform_inputs(ui_refs)


func _connect_transform_inputs(ui_refs: Dictionary) -> void:
	"""Connect transform input SpinBox signals."""
	var inputs = {
		"position_x_input": {"component": "position", "axis": "x"},
		"position_y_input": {"component": "position", "axis": "y"},
		"position_z_input": {"component": "position", "axis": "z"},
		"rotation_x_input": {"component": "rotation", "axis": "x"},
		"rotation_y_input": {"component": "rotation", "axis": "y"},
		"rotation_z_input": {"component": "rotation", "axis": "z"},
		"scale_x_input": {"component": "scale", "axis": "x"},
		"scale_y_input": {"component": "scale", "axis": "y"},
		"scale_z_input": {"component": "scale", "axis": "z"},
	}

	for input_name in inputs:
		var input = ui_refs.get(input_name)
		if input:
			var component = inputs[input_name]["component"]
			var axis = inputs[input_name]["axis"]

			# Connect value changed signal
			input.value_changed.connect(func(val): _on_transform_input_changed(component, axis, val))

			# Connect focus signals for undo/redo tracking
			# SpinBox has get_line_edit() method to get the internal LineEdit
			if input.has_method("get_line_edit"):
				var line_edit = input.get_line_edit()
				if line_edit:
					print("Connecting focus signals for ", input_name, " (component: ", component, ")")
					line_edit.focus_entered.connect(func(): _on_transform_input_focus_entered(component))
					line_edit.focus_exited.connect(func(): _on_transform_input_focus_exited())
				else:
					print("WARNING: ", input_name, " get_line_edit() returned null")
			else:
				print("WARNING: ", input_name, " does not have get_line_edit() method")


func _notification(what: int) -> void:
	"""Handle window notifications."""
	match what:
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_reset_all_drag_states()


func _reset_all_drag_states() -> void:
	"""Reset all drag states when focus is lost."""
	is_alt_held = false
	camera_controller.end_drag()
	gizmo_controller.cancel_gizmo_drag(selection_manager.selected_items)
	selection_manager.cancel_box_select()


func _input(event: InputEvent) -> void:
	"""Handle global input events."""
	if not visible:
		return

	# Track Alt key globally
	if event is InputEventKey and event.keycode == KEY_ALT:
		is_alt_held = event.pressed
		if not is_alt_held and camera_controller.is_dragging:
			camera_controller.end_drag()

	# Keyboard shortcuts
	if event is InputEventKey and not event.echo:
		# Handle X key for snap mode (both press and release)
		if event.keycode == KEY_X:
			gizmo_controller.set_snap_to_grid(event.pressed)
			return

		# Other shortcuts only on key press
		if event.pressed:
			_handle_keyboard_shortcuts(event)


func _handle_keyboard_shortcuts(event: InputEventKey) -> void:
	"""Handle keyboard shortcut inputs."""
	match event.keycode:
		KEY_Q:
			_set_transform_mode(TransformMode.SELECT)
			get_viewport().set_input_as_handled()
		KEY_W:
			_set_transform_mode(TransformMode.MOVE)
			get_viewport().set_input_as_handled()
		KEY_E:
			_set_transform_mode(TransformMode.ROTATE)
			get_viewport().set_input_as_handled()
		KEY_R:
			_set_transform_mode(TransformMode.SCALE)
			get_viewport().set_input_as_handled()
		KEY_F:
			camera_controller.frame_objects(selection_manager.selected_items)
			get_viewport().set_input_as_handled()
		KEY_G:
			_toggle_grid_visibility()
			get_viewport().set_input_as_handled()
		KEY_DELETE:
			selection_manager.delete_selected_items()
			get_viewport().set_input_as_handled()
		KEY_A:
			if event.ctrl_pressed:
				selection_manager.select_all_items()
				get_viewport().set_input_as_handled()
		KEY_D:
			if event.ctrl_pressed:
				_duplicate_selected_items()
				get_viewport().set_input_as_handled()
		KEY_Z:
			if event.ctrl_pressed:
				# Cancel any ongoing manual transform editing before undo/redo
				if manual_transform_is_editing:
					print("Cancelling manual transform edit before undo/redo")
					manual_transform_timer.stop()
					manual_transform_is_editing = false
					manual_transform_initial_values.clear()
					manual_transform_operation_type = ""

				if event.shift_pressed:
					undo_redo_manager.redo()
				else:
					undo_redo_manager.undo()
				_update_gizmo()
				# Update UI to reflect the undone/redone state
				ui_manager.update_object_info(selection_manager.selected_items)
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if connect_mode.is_active():
				_exit_connect_mode()
				get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	"""Process frame updates."""
	# Update fire line timer for connect mode
	connect_mode.update_fire_line_timer(delta)

	# Redraw selection box if needed
	if selection_manager.is_box_selecting and selection_overlay:
		selection_overlay.queue_redraw()

	# Update all joint visual helpers
	_update_joint_visual_helpers()

	# Update cluster pivot if needed
	if selection_manager.cluster_pivot_active and not selection_manager.selected_items.is_empty():
		selection_manager.update_cluster_pivot()

	# Always update gizmo position if items are selected
	if not selection_manager.selected_items.is_empty():
		_update_gizmo()

	# Update gizmo scale based on camera distance
	if transform_gizmo and transform_gizmo.visible and camera:
		transform_gizmo.update_scale_for_camera(camera.global_position)

	# Update object info display
	if not selection_manager.selected_items.is_empty():
		ui_manager.update_object_info(selection_manager.selected_items)


func _update_joint_visual_helpers() -> void:
	"""Update all joint visual helpers to follow moving objects."""
	for item in world.get_children():
		if item is PhysicalItem:
			for fastener in item.fasteners:
				if fastener.joint:
					fastener.joint.update_visual_helper_position()


func _gui_input(event: InputEvent) -> void:
	"""Handle GUI input events."""
	if not initialized or not _is_mouse_over_viewport():
		return

	if event is InputEventMouseButton:
		if event.pressed:
			_handle_mouse_press(event)
		else:
			_handle_mouse_release(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_mouse_press(event: InputEventMouseButton) -> void:
	"""Handle mouse button press events."""
	if ui_manager.is_dialog_open:
		return

	# Alt + Mouse = Camera controls
	if is_alt_held:
		camera_controller.start_drag(event.button_index, event.position)
		return

	# Left click
	if event.button_index == MOUSE_BUTTON_LEFT:
		# Connect mode click
		if connect_mode.is_active():
			connect_mode.place_fastener_at_ray(event.position)
			return

		# Try gizmo drag
		if gizmo_controller.try_start_gizmo_drag(event.position, selection_manager.selected_items):
			return

		# Try free movement in move mode
		if current_transform_mode == TransformMode.MOVE and not selection_manager.selected_items.is_empty():
			if gizmo_controller.try_start_free_movement(event.position, selection_manager.selected_items):
				return

		# Start box selection
		selection_manager.start_box_select(selection_overlay.get_local_mouse_position())

	# Right click = Context menu
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_show_context_menu(event.position)

	# Scroll wheel = Zoom
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera_controller.handle_scroll_zoom(-1.0)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera_controller.handle_scroll_zoom(1.0)


func _handle_mouse_release(event: InputEventMouseButton) -> void:
	"""Handle mouse button release events."""
	# End gizmo drag
	if gizmo_controller.is_gizmo_dragging and event.button_index == MOUSE_BUTTON_LEFT:
		_record_transform_operation()
		gizmo_controller.finish_gizmo_drag()
		ui_manager.clear_transform_stats()
		return

	# End camera drag
	if camera_controller.is_dragging and event.button_index == camera_controller.drag_button:
		camera_controller.end_drag()
		return

	# End box selection
	if selection_manager.is_box_selecting and event.button_index == MOUSE_BUTTON_LEFT:
		selection_manager.finish_box_select()
		if selection_overlay:
			selection_overlay.queue_redraw()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	"""Handle mouse motion events."""
	if ui_manager.is_dialog_open:
		return

	# Gizmo drag
	if gizmo_controller.is_gizmo_dragging:
		gizmo_controller.update_gizmo_drag(event.position, selection_manager.selected_items)
		return

	# Camera controls
	if camera_controller.is_dragging:
		camera_controller.update_drag(event.position)
		return

	# Box selection
	if selection_manager.is_box_selecting:
		selection_manager.update_box_select(selection_overlay.get_local_mouse_position())
		return

	# Gizmo hover detection (for highlighting)
	if transform_gizmo and transform_gizmo.visible and not selection_manager.selected_items.is_empty():
		gizmo_controller.update_gizmo_hover(event.position)


func _set_transform_mode(mode: TransformMode) -> void:
	"""Set the current transform mode."""
	# Exit connect mode if switching away
	if connect_mode.is_active() and mode != TransformMode.CONNECT:
		_exit_connect_mode()

	current_transform_mode = mode
	gizmo_controller.set_transform_mode(mode as WorkbenchGizmoController.TransformMode)

	# Update UI
	ui_manager.update_mode_buttons(mode as WorkbenchUIManager.TransformMode)
	_update_gizmo()

	print("Transform mode: ", ["Select", "Move", "Rotate", "Scale", "Connect"][mode])


func _update_gizmo() -> void:
	"""Update gizmo position and visibility."""
	gizmo_controller.update_gizmo_position(selection_manager.selected_items, selection_manager.cluster_pivot_active, selection_manager.cluster_pivot_point)


func _record_transform_operation() -> void:
	"""Record the current transform operation for undo."""
	if selection_manager.selected_items.is_empty():
		return

	var initial_data = gizmo_controller.get_initial_transform_data()
	var operation_type = ""
	var initial_values = {}
	var final_values = {}

	match current_transform_mode:
		TransformMode.MOVE:
			operation_type = "move"
			initial_values = initial_data["positions"]
			for item in selection_manager.selected_items:
				final_values[item] = item.global_position

		TransformMode.ROTATE:
			operation_type = "rotate"
			# Combine rotations and positions into Dictionary format for consistency with spinbox operations
			var initial_rotations = initial_data["rotations"]
			var initial_positions = initial_data["positions"]
			for item in selection_manager.selected_items:
				if item in initial_rotations and item in initial_positions:
					initial_values[item] = {
						"basis": initial_rotations[item],
						"position": initial_positions[item]
					}
					final_values[item] = {
						"basis": item.basis,
						"position": item.global_position
					}

		TransformMode.SCALE:
			operation_type = "scale"
			initial_values = initial_data["scales"]
			for item in selection_manager.selected_items:
				final_values[item] = item.scale

	if not initial_values.is_empty():
		undo_redo_manager.record_transform(operation_type, selection_manager.selected_items, initial_values, final_values)


# Signal handlers


func _on_selection_changed(_selected_items: Array[PhysicalItem]) -> void:
	"""Handle selection change events."""
	_update_gizmo()
	ui_manager.update_object_info(selection_manager.selected_items)


func _on_transform_updated(operation: String, value: float, axis: Vector3) -> void:
	"""Handle transform update from gizmo controller."""
	ui_manager.update_transform_stats(operation, value, axis, gizmo_controller.snap_to_grid_enabled, gizmo_controller.grid_snap_size)


func _on_transform_completed(_mode: int) -> void:
	"""Handle transform completion."""
	ui_manager.clear_transform_stats()


func _on_fastener_placed(_fastener: Fastener, _item_a: PhysicalItem, _item_b: PhysicalItem) -> void:
	"""Handle fastener placement."""
	ui_manager.update_object_info(selection_manager.selected_items)


func _on_connect_mode_toggled(active: bool) -> void:
	"""Handle connect mode toggle."""
	if active:
		_set_transform_mode(TransformMode.CONNECT)
	else:
		_set_transform_mode(TransformMode.SELECT)


func _on_viewport_settings_changed(grid_size: float, new_gizmo_scale: float, bg_color: Color, floor_color: Color) -> void:
	"""Apply viewport settings changes."""
	gizmo_controller.set_grid_snap_size(grid_size)

	# Update grid visual
	if grid:
		var shader_material = grid.material_override as ShaderMaterial
		if not shader_material and grid.get_surface_override_material_count() > 0:
			shader_material = grid.get_surface_override_material(0) as ShaderMaterial
		if shader_material:
			shader_material.set_shader_parameter("grid_scale", grid_size)

	# Update gizmo scale
	if transform_gizmo:
		transform_gizmo.gizmo_size = new_gizmo_scale
		transform_gizmo._create_move_gizmo()
		transform_gizmo._create_rotate_gizmo()
		transform_gizmo._create_scale_gizmo()
		transform_gizmo.set_mode(transform_gizmo.current_mode)
		_update_gizmo()

	# Update background and floor colors
	if world_environment:
		if not world_environment.environment:
			world_environment.environment = Environment.new()
		world_environment.environment.background_mode = Environment.BG_COLOR
		world_environment.environment.background_color = bg_color

	if ground_plane:
		var floor_material = ground_plane.get_surface_override_material(0) as StandardMaterial3D
		if floor_material:
			floor_material.albedo_color = floor_color


func _on_fastener_selected(fastener_id: String) -> void:
	"""Handle fastener selection from dialog."""
	var count = connect_mode.attach_selected_items_with_fastener(selection_manager.selected_items, fastener_id)
	if count > 0:
		ui_manager.update_object_info(selection_manager.selected_items)


func _on_transform_input_focus_entered(component: String) -> void:
	"""Handle transform input gaining focus - store initial values for undo."""
	print("Transform input focus entered: ", component)
	if selection_manager.selected_items.is_empty():
		print("  No items selected, skipping")
		return

	manual_transform_operation_type = component
	manual_transform_initial_values.clear()

	# Store initial values based on component type
	for item in selection_manager.selected_items:
		match component:
			"position":
				manual_transform_initial_values[item] = item.global_position
			"rotation":
				manual_transform_initial_values[item] = item.basis
			"scale":
				manual_transform_initial_values[item] = item.scale

	print("  Stored initial values for ", manual_transform_initial_values.size(), " items")


func _on_transform_input_focus_exited() -> void:
	"""Handle transform input losing focus - record undo operation."""
	print("Transform input focus exited")
	if manual_transform_initial_values.is_empty():
		print("  No initial values stored, skipping")
		return

	if selection_manager.selected_items.is_empty():
		print("  No items selected, skipping")
		return

	var final_values = {}

	# Collect final values based on operation type
	for item in selection_manager.selected_items:
		match manual_transform_operation_type:
			"position":
				final_values[item] = item.global_position
			"rotation":
				# Match the format of initial values (Dictionary with basis and position)
				final_values[item] = {
					"basis": item.basis,
					"position": item.global_position
				}
			"scale":
				# Match the format of initial values (Dictionary with scale and position)
				final_values[item] = {
					"scale": item.scale,
					"position": item.global_position
				}

	# Filter out the __pivot__ key from initial values (it's not a PhysicalItem)
	var filtered_initial_values = {}
	for key in manual_transform_initial_values:
		# Skip string keys (like "__pivot__"), only include PhysicalItem objects
		if not (key is String):
			filtered_initial_values[key] = manual_transform_initial_values[key]

	# Record the operation
	var operation_type = manual_transform_operation_type
	if operation_type == "position":
		operation_type = "move"
	elif operation_type == "rotation":
		operation_type = "rotate"

	print("  Recording undo for ", operation_type, " with ", final_values.size(), " items")
	undo_redo_manager.record_transform(
		operation_type,
		selection_manager.selected_items,
		filtered_initial_values,
		final_values
	)

	# Clear tracking variables
	manual_transform_initial_values.clear()
	manual_transform_operation_type = ""


func _on_manual_transform_timeout() -> void:
	"""Called when manual transform editing timer expires - record undo operation."""
	if not manual_transform_is_editing:
		return

	manual_transform_is_editing = false

	if manual_transform_initial_values.is_empty() or selection_manager.selected_items.is_empty():
		print("Manual transform timeout: No values to record")
		return

	var final_values = {}

	# Collect final values based on operation type
	for item in selection_manager.selected_items:
		match manual_transform_operation_type:
			"position":
				final_values[item] = item.global_position
			"rotation":
				# Match the format of initial values (Dictionary with basis and position)
				final_values[item] = {
					"basis": item.basis,
					"position": item.global_position
				}
				print("  Storing final rotation basis for item: ", item.name)
				print("    Rotation degrees: ", item.rotation_degrees)
				print("    Basis: ", item.basis)
			"scale":
				# Match the format of initial values (Dictionary with scale and position)
				final_values[item] = {
					"scale": item.scale,
					"position": item.global_position
				}

	# Filter out the __pivot__ key from initial values (it's not a PhysicalItem)
	var filtered_initial_values = {}
	for key in manual_transform_initial_values:
		# Skip string keys (like "__pivot__"), only include PhysicalItem objects
		if not (key is String):
			filtered_initial_values[key] = manual_transform_initial_values[key]

	# Record the operation
	var operation_type = manual_transform_operation_type
	if operation_type == "position":
		operation_type = "move"
	elif operation_type == "rotation":
		operation_type = "rotate"

	print("Manual transform timeout: Recording undo for ", operation_type)
	undo_redo_manager.record_transform(
		operation_type,
		selection_manager.selected_items,
		filtered_initial_values,
		final_values
	)

	# Clear tracking variables
	manual_transform_initial_values.clear()
	manual_transform_operation_type = ""


func _on_transform_input_changed(component: String, axis: String, value: float) -> void:
	"""Handle transform input changes from spinboxes."""
	print("_on_transform_input_changed called: ", component, ".", axis, " = ", value)
	print("  is_updating_transform_inputs: ", ui_manager.is_updating_transform_inputs)
	print("  selected_items count: ", selection_manager.selected_items.size())

	# Ignore if UI is updating programmatically or no items selected
	if ui_manager.is_updating_transform_inputs or selection_manager.selected_items.is_empty():
		print("  SKIPPED - UI updating or no selection")
		return

	# If this is the first edit, store initial values
	if not manual_transform_is_editing:
		manual_transform_is_editing = true
		manual_transform_operation_type = component
		manual_transform_initial_values.clear()

		# For clustered objects, also store the initial pivot point
		var initial_pivot: Vector3
		if selection_manager.selected_items.size() > 1 and selection_manager.cluster_pivot_active:
			initial_pivot = selection_manager.cluster_pivot_point
			manual_transform_initial_values["__pivot__"] = initial_pivot
			print("  Storing cluster pivot: ", initial_pivot)

		# Store initial values - for rotation/scale we need BOTH position and basis/scale
		for item in selection_manager.selected_items:
			match component:
				"position":
					manual_transform_initial_values[item] = item.global_position
				"rotation":
					# Store both basis and position for rotation
					manual_transform_initial_values[item] = {
						"basis": item.basis,
						"position": item.global_position
					}
					print("  Storing initial rotation basis for item: ", item.name)
					print("    Rotation degrees: ", item.rotation_degrees)
					print("    Basis: ", item.basis)
				"scale":
					# Store both scale and position for scaling
					manual_transform_initial_values[item] = {
						"scale": item.scale,
						"position": item.global_position
					}

		print("Manual transform edit started: ", component, " (stored ", manual_transform_initial_values.size(), " items)")

	# For single selection, apply directly to the item
	if selection_manager.selected_items.size() == 1:
		var item = selection_manager.selected_items[0]
		match component:
			"position":
				var pos = item.global_position
				match axis:
					"x":
						pos.x = value
					"y":
						pos.y = value
					"z":
						pos.z = value
				item.global_position = pos

			"rotation":
				var rot = item.rotation_degrees
				match axis:
					"x":
						rot.x = value
					"y":
						rot.y = value
					"z":
						rot.z = value
				item.rotation_degrees = rot

			"scale":
				var scl = item.scale
				match axis:
					"x":
						scl.x = value
					"y":
						scl.y = value
					"z":
						scl.z = value
				item.scale = scl
	else:
		# Multiple selection - apply cluster-aware transformation
		_apply_cluster_aware_transform(component, axis, value)

	_update_gizmo()

	# Restart the timer - undo will be recorded 0.5s after the last change
	manual_transform_timer.start()


func _apply_cluster_aware_transform(component: String, axis: String, value: float) -> void:
	"""Apply transformation to multiple objects using pivot point as the group's origin.

	For clustered objects, the spinbox value represents the pivot's transform value.
	All objects transform together relative to this pivot."""

	# Get the initial pivot point
	var initial_pivot: Vector3
	if "__pivot__" in manual_transform_initial_values:
		initial_pivot = manual_transform_initial_values["__pivot__"] as Vector3
	else:
		# No stored pivot - calculate from initial positions
		initial_pivot = Vector3.ZERO
		var count = 0
		for item in selection_manager.selected_items:
			if item in manual_transform_initial_values:
				var item_data = manual_transform_initial_values[item]
				if item_data is Vector3:
					initial_pivot += item_data
				elif item_data is Dictionary and "position" in item_data:
					initial_pivot += item_data["position"] as Vector3
				count += 1
		if count > 0:
			initial_pivot /= count

	match component:
		"position":
			# Spinbox value represents where the PIVOT should be
			# Calculate delta from initial pivot position
			var pivot_delta = Vector3.ZERO
			match axis:
				"x":
					pivot_delta.x = value - initial_pivot.x
				"y":
					pivot_delta.y = value - initial_pivot.y
				"z":
					pivot_delta.z = value - initial_pivot.z

			# Move all items by this delta (translating the entire group)
			for item in selection_manager.selected_items:
				if item in manual_transform_initial_values:
					var item_initial_pos = manual_transform_initial_values[item] as Vector3
					item.global_position = item_initial_pos + pivot_delta

		"rotation":
			# Spinbox value represents the absolute rotation angle around the pivot
			# This rotates the entire group around the pivot point
			var angle_rad = deg_to_rad(value)
			var rotation_axis: Vector3
			match axis:
				"x":
					rotation_axis = Vector3.RIGHT
				"y":
					rotation_axis = Vector3.UP
				"z":
					rotation_axis = Vector3.BACK

			# Create rotation basis from absolute angle
			var rotation_basis = Basis(rotation_axis, angle_rad)

			# Apply rotation to all items around the pivot from their INITIAL state
			for item in selection_manager.selected_items:
				if item in manual_transform_initial_values:
					var item_data = manual_transform_initial_values[item]
					var item_initial_basis = item_data["basis"] as Basis
					var item_initial_pos = item_data["position"] as Vector3

					# Rotate the item's orientation
					item.basis = rotation_basis * item_initial_basis

					# Rotate the item's position around the pivot
					var offset_from_pivot = item_initial_pos - initial_pivot
					var rotated_offset = rotation_basis * offset_from_pivot
					item.global_position = initial_pivot + rotated_offset

		"scale":
			# Spinbox value represents the scale multiplier to apply to the group
			# For uniform scaling based on the first item's initial scale
			var first_item = selection_manager.selected_items[0]
			if first_item in manual_transform_initial_values:
				var first_item_data = manual_transform_initial_values[first_item]
				var initial_scale = first_item_data["scale"] as Vector3
				var scale_multiplier: float = 1.0
				match axis:
					"x":
						scale_multiplier = value / initial_scale.x if initial_scale.x != 0 else 1.0
					"y":
						scale_multiplier = value / initial_scale.y if initial_scale.y != 0 else 1.0
					"z":
						scale_multiplier = value / initial_scale.z if initial_scale.z != 0 else 1.0

				# Apply scale to all items
				for item in selection_manager.selected_items:
					if item in manual_transform_initial_values:
						var item_data = manual_transform_initial_values[item]
						var item_initial_scale = item_data["scale"] as Vector3
						var scl = item_initial_scale
						match axis:
							"x":
								scl.x *= scale_multiplier
							"y":
								scl.y *= scale_multiplier
							"z":
								scl.z *= scale_multiplier
						item.scale = scl

						# Scale position distance from pivot
						var item_initial_pos = item_data["position"] as Vector3
						var offset_from_pivot = item_initial_pos - initial_pivot
						match axis:
							"x":
								offset_from_pivot.x *= scale_multiplier
							"y":
								offset_from_pivot.y *= scale_multiplier
							"z":
								offset_from_pivot.z *= scale_multiplier
						item.global_position = initial_pivot + offset_from_pivot


func _on_context_menu_item_selected(item_id: String, _item_data: Dictionary, _context_data: Dictionary) -> void:
	"""Handle context menu item selection."""
	match item_id:
		"select_all":
			selection_manager.select_all_items()
		"select_none":
			selection_manager.clear_selection()
		"frame_selected":
			camera_controller.frame_objects(selection_manager.selected_items)
		"toggle_grid":
			_toggle_grid_visibility()
		"viewport_settings":
			ui_manager.show_viewport_settings_dialog(self, gizmo_controller.grid_snap_size)
		"undo":
			undo_redo_manager.undo()
			_update_gizmo()
			ui_manager.update_object_info(selection_manager.selected_items)
		"redo":
			undo_redo_manager.redo()
			_update_gizmo()
			ui_manager.update_object_info(selection_manager.selected_items)
		"duplicate":
			_duplicate_selected_items()
		"delete":
			selection_manager.delete_selected_items()
		"attach_fastener":
			ui_manager.show_fastener_selection_dialog(selection_manager.selected_items, self)


func _on_part_selected(index: int) -> void:
	"""Spawn a part when double-clicked from list."""
	var part_list = ui_manager.part_list
	if not part_list:
		print("ERROR: part_list is null")
		return

	var part_name = part_list.get_item_text(index).to_lower().replace(" ", "_")
	print("Double-click: Attempting to spawn part: '%s'" % part_name)
	if part_name in available_parts:
		spawn_part(available_parts[part_name])
	else:
		print("ERROR: Part '%s' not found in available_parts" % part_name)
		print("Available parts: ", available_parts.keys())


func _on_add_object_pressed() -> void:
	"""Add the selected object from the list."""
	var part_list = ui_manager.part_list
	if not part_list:
		print("ERROR: part_list is null")
		return

	var selected_indices = part_list.get_selected_items()
	if selected_indices.is_empty():
		print("ERROR: No item selected in part list")
		return

	var index = selected_indices[0]
	var part_name = part_list.get_item_text(index).to_lower().replace(" ", "_")
	print("Add button: Attempting to spawn part: '%s'" % part_name)
	if part_name in available_parts:
		spawn_part(available_parts[part_name])
	else:
		print("ERROR: Part '%s' not found in available_parts" % part_name)
		print("Available parts: ", available_parts.keys())


func _on_validate_pressed() -> void:
	"""Validate the current workbench assembly."""
	var report = {"valid": true, "errors": []}
	item_validated.emit(true, report)
	print("Workbench validated successfully")


func _on_connect_mode_button_toggled(button_pressed: bool) -> void:
	"""Handle connect mode button toggle."""
	if button_pressed:
		if selection_manager.selected_items.size() != 2:
			print("Connect Mode requires exactly 2 items selected")
			var btn = ui_manager.connect_mode_button
			if btn:
				btn.button_pressed = false
			return

		if connect_mode.enter_connect_mode(selection_manager.selected_items):
			_set_transform_mode(TransformMode.CONNECT)
	else:
		_exit_connect_mode()


func _exit_connect_mode() -> void:
	"""Exit connect mode."""
	connect_mode.exit_connect_mode()
	_set_transform_mode(TransformMode.SELECT)


# Public API


func spawn_part(scene_path: String) -> Node3D:
	"""Spawn a new part in the workbench."""
	print("spawn_part called with path: '%s'" % scene_path)

	var scene = load(scene_path) as PackedScene
	if not scene:
		push_error("Failed to load part scene: ", scene_path)
		print("ERROR: Failed to load scene from path: '%s'" % scene_path)
		return null

	var node = scene.instantiate()
	if not node:
		push_error("Failed to instantiate scene: ", scene_path)
		print("ERROR: Failed to instantiate scene from path: '%s'" % scene_path)
		return null

	world.add_child(node)
	node.global_position = Vector3.ZERO

	if node is PhysicalItem:
		node.freeze = true
		print("SUCCESS: Spawned PhysicalItem: %s at origin" % node.item_name)
	else:
		print("SUCCESS: Spawned node (not PhysicalItem): %s" % node.name)

	return node


func clear_workbench() -> void:
	"""Clear all items from the workbench."""
	for child in world.get_children():
		if child is PhysicalItem:
			child.queue_free()

	selection_manager.clear_selection()
	connect_mode.clear_fasteners()
	undo_redo_manager.clear_history()
	print("Workbench cleared")


func get_all_items() -> Array[PhysicalItem]:
	"""Get all PhysicalItem objects in the workbench."""
	var items: Array[PhysicalItem] = []
	for child in world.get_children():
		if child is PhysicalItem:
			items.append(child)
	return items


# Helper methods


func _show_context_menu(_mouse_pos: Vector2) -> void:
	"""Show context menu at mouse position."""
	if not context_menu:
		return

	context_menu.clear_items()

	var clicked_on_item = selection_manager.hovered_item != null

	if clicked_on_item:
		context_menu.add_menu_item("duplicate", "Duplicate")
		context_menu.add_menu_item("delete", "Delete")
		context_menu.add_separator()

		if selection_manager.selected_items.size() >= 2:
			context_menu.add_menu_item("attach_fastener", "Attach with Fastener...")
			context_menu.add_separator()

		context_menu.add_menu_item("frame_selected", "Frame Selected", null, not selection_manager.selected_items.is_empty())
		context_menu.add_separator()
		context_menu.add_menu_item("select_all", "Select All")
		context_menu.add_menu_item("select_none", "Select None", null, not selection_manager.selected_items.is_empty())
	else:
		if selection_manager.selected_items.size() >= 2:
			context_menu.add_menu_item("attach_fastener", "Attach with Fastener...")
			context_menu.add_separator()

		context_menu.add_menu_item("select_all", "Select All")
		context_menu.add_menu_item("select_none", "Select None", null, not selection_manager.selected_items.is_empty())
		context_menu.add_separator()
		context_menu.add_menu_item("frame_selected", "Frame Selected", null, not selection_manager.selected_items.is_empty())
		context_menu.add_separator()
		var grid_text = "Hide Grid" if grid.visible else "Show Grid"
		context_menu.add_menu_item("toggle_grid", grid_text)
		context_menu.add_menu_item("viewport_settings", "Viewport Settings...")
		context_menu.add_separator()
		context_menu.add_menu_item("undo", "Undo", null, undo_redo_manager.has_undo())
		context_menu.add_menu_item("redo", "Redo", null, undo_redo_manager.has_redo())

	context_menu.show_context_menu(Vector2.ZERO, {}, get_window())


func _toggle_grid_visibility() -> void:
	"""Toggle the visibility of the grid."""
	if grid:
		grid.visible = not grid.visible
		print("Grid is now ", "visible" if grid.visible else "hidden")


func _duplicate_selected_items() -> void:
	"""Duplicate the currently selected items."""
	var items_to_duplicate = selection_manager.selected_items.duplicate()
	if items_to_duplicate.is_empty():
		return

	selection_manager.clear_selection()

	for item in items_to_duplicate:
		var scene = item.scene_file_path
		if scene.is_empty():
			continue

		var new_item = spawn_part(scene)
		if new_item:
			new_item.global_position = item.global_position + Vector3(0.5, 0, 0.5)
			new_item.rotation = item.rotation
			new_item.scale = item.scale

			if new_item is PhysicalItem:
				selection_manager.select_item(new_item, true)

	print("Duplicated ", items_to_duplicate.size(), " item(s)")


func _is_mouse_over_viewport() -> bool:
	"""Check if mouse is currently over the 3D viewport."""
	if not viewport_container:
		return false

	var mouse_pos = viewport_container.get_local_mouse_position()
	var rect = Rect2(Vector2.ZERO, viewport_container.size)
	return rect.has_point(mouse_pos)


func _update_all_ui() -> void:
	"""Update all UI elements."""
	_update_gizmo()
	ui_manager.update_object_info(selection_manager.selected_items)
