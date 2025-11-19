class_name WorkbenchWindow
extends Control

## A dedicated 3D assembly window with industry-standard controls.
##
## This is the modular version that delegates functionality to specialized managers.
## See the workbench/ subfolder for individual module documentation.

# Signals
signal workbench_closed

# Transform modes
enum TransformMode { SELECT, MOVE, ROTATE, SCALE, CONNECT }
var current_transform_mode: TransformMode = TransformMode.SELECT

# Module instances
var camera_controller: WorkbenchCameraController
var selection_manager: WorkbenchSelectionManager
var gizmo_controller: WorkbenchGizmoController
var undo_redo_manager: WorkbenchUndoRedo
var ui_manager: WorkbenchUIManager
var assembly_manager: WorkbenchAssemblyManager

# Core UI References (direct scene tree references)
var viewport_container: SubViewportContainer
var selection_overlay: Control
var edit_mode_border: Panel
var edit_mode_label: Label
var viewport: SubViewport
var camera: Camera3D
var world: Node3D
var grid: MeshInstance3D
var ground_plane: MeshInstance3D
var world_environment: WorldEnvironment
var transform_gizmo: TransformGizmo
var context_menu: ContextMenu_Base
var tab_container: TabContainer

# Tab management
var current_tab: int = 0  # 0 = Design, 1 = Assemblies
var design_items: Array[Node] = []  # Items in design tab
var assembly_items: Array[Node] = []  # Items in assemblies tab

# Input state
var is_alt_held: bool = false
var is_shift_held: bool = false
var is_ctrl_held: bool = false
var initialized: bool = false
var controls_visible: bool = false
var ghost_mode_enabled: bool = false
var input_enabled: bool = true  # Flag to completely disable input processing
var is_closing: bool = false  # Flag to prevent re-enabling during close

# Gizmo scale
var gizmo_scale: float = 1.0

# Manual transform input tracking (for undo/redo)
var manual_transform_initial_values: Dictionary = {}
var manual_transform_operation_type: String = ""
var manual_transform_timer: Timer = null
var manual_transform_is_editing: bool = false

# Assembly edit mode tracking
var is_editing_assembly: bool = false
var editing_assembly_id: String = ""

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

	# Populate the assemblies list (assemblies are already loaded in manager's _init)
	_refresh_assemblies_list()

	# Initialize tab state - ensure we start on Design tab with no assembly items visible
	current_tab = 0  # Design tab
	_hide_all_items()  # Hide any items that might exist
	_show_current_tab_items()  # Show only design items (if any)

	initialized = true
	print("WorkbenchWindow ready (Refactored) - Use Alt+Mouse to navigate, Q/W/E/R for tools")


func _setup_node_references() -> void:
	"""Get all required node references from the scene tree."""
	viewport_container = $VBoxContainer/MainContent/ViewportContainer
	selection_overlay = $VBoxContainer/MainContent/ViewportContainer/SelectionOverlay
	# Optional nodes - may not exist in scene
	edit_mode_border = get_node_or_null("VBoxContainer/MainContent/ViewportContainer/EditModeBorder")
	edit_mode_label = get_node_or_null("VBoxContainer/MainContent/ViewportContainer/EditModeLabel")
	viewport = $VBoxContainer/MainContent/ViewportContainer/SubViewport
	camera = $VBoxContainer/MainContent/ViewportContainer/SubViewport/Camera3D
	world = $VBoxContainer/MainContent/ViewportContainer/SubViewport/World
	grid = $VBoxContainer/MainContent/ViewportContainer/SubViewport/World/Grid
	ground_plane = $VBoxContainer/MainContent/ViewportContainer/SubViewport/World/GroundPlane
	world_environment = $VBoxContainer/MainContent/ViewportContainer/SubViewport/WorldEnvironment
	tab_container = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer

	# Set up viewport
	if viewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		# Note: stretch = true on SubViewportContainer handles automatic sizing

	# Create context menu
	context_menu = ContextMenu_Base.new()
	context_menu.name = "WorkbenchContextMenu"
	add_child(context_menu)

	# Create transform gizmo
	transform_gizmo = TransformGizmo.new()
	world.add_child(transform_gizmo)
	transform_gizmo.visible = false

	# Connect tab change signal
	if tab_container:
		tab_container.tab_changed.connect(_on_tab_changed)


func _initialize_managers() -> void:
	"""Initialize all manager instances."""
	# Camera controller
	camera_controller = WorkbenchCameraController.new(camera, viewport)

	# Selection manager
	selection_manager = WorkbenchSelectionManager.new(camera, viewport, viewport_container, world, selection_overlay)

	# Gizmo controller
	gizmo_controller = WorkbenchGizmoController.new(camera, viewport, viewport_container, transform_gizmo, gizmo_scale)
	gizmo_controller.set_transform_mode(current_transform_mode as WorkbenchGizmoController.TransformMode)

	# Undo/redo manager
	undo_redo_manager = WorkbenchUndoRedo.new()

	# UI manager
	ui_manager = WorkbenchUIManager.new()

	# Assembly manager
	assembly_manager = WorkbenchAssemblyManager.new()


func _setup_ui() -> Dictionary:
	"""Setup UI elements and references. Returns the ui_refs dictionary."""
	# Collect all UI references
	var ui_refs = {
		"part_list": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Design/VBoxContainer/PartsSection/PartList,
		"category_filter": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Design/VBoxContainer/PartsSection/CategoryFilterContainer/CategoryFilter,
		"add_object_button": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Design/VBoxContainer/ButtonContainer/VBoxContainer/AddObjectButton,
		"help_label": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/HelpLabel,
		"select_button": $VBoxContainer/MainContent/ViewportContainer/TransformModeButtons/SelectButton,
		"move_button": $VBoxContainer/MainContent/ViewportContainer/TransformModeButtons/MoveButton,
		"rotate_button": $VBoxContainer/MainContent/ViewportContainer/TransformModeButtons/RotateButton,
		"scale_button": $VBoxContainer/MainContent/ViewportContainer/TransformModeButtons/ScaleButton,
		"ghost_mode_button": $VBoxContainer/MainContent/ViewportContainer/TransformModeButtons/GhostModeButton,
		"transform_panel": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Design/VBoxContainer/TransformSection/TransformPanel,
		"position_x_input":
		$VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Design/VBoxContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/PositionX/SpinBox,
		"position_y_input":
		$VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Design/VBoxContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/PositionY/SpinBox,
		"position_z_input":
		$VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Design/VBoxContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/PositionZ/SpinBox,
		"rotation_x_input":
		$VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Design/VBoxContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/RotationX/SpinBox,
		"rotation_y_input":
		$VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Design/VBoxContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/RotationY/SpinBox,
		"rotation_z_input":
		$VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Design/VBoxContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/RotationZ/SpinBox,
		"scale_x_input":
		$VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Design/VBoxContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/ScaleX/SpinBox,
		"scale_y_input":
		$VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Design/VBoxContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/ScaleY/SpinBox,
		"scale_z_input":
		$VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Design/VBoxContainer/TransformSection/TransformPanel/ScrollContainer/MarginContainer/VBoxContainer/ScaleZ/SpinBox,
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
		"assemble_button": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Design/VBoxContainer/ButtonContainer/VBoxContainer/AssembleButton,
		"assemblies_list": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Assemblies/VBoxContainer/AssembliesSection/AssembliesList,
		"edit_assembly_button": $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Assemblies/VBoxContainer/AssembliesSection/AssemblyButtonContainer/HBoxContainer/EditAssemblyButton,
		"add_to_inventory_button":
		$VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Assemblies/VBoxContainer/AssembliesSection/AssemblyButtonContainer/HBoxContainer/AddToInventoryButton,
		"delete_assembly_button":
		$VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Assemblies/VBoxContainer/AssembliesSection/AssemblyButtonContainer/HBoxContainer/DeleteAssemblyButton,
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

	# Undo/redo signals
	undo_redo_manager.history_changed.connect(func(_undo_count, _redo_count): pass)

	# Camera controller signals
	camera_controller.camera_moved.connect(func(_pos, _rot): pass)

	# UI Manager signals
	ui_manager.viewport_settings_changed.connect(_on_viewport_settings_changed)

	# Assembly manager signals
	assembly_manager.assembly_created.connect(
		func(_assembly):
			print("WorkbenchWindow: assembly_created signal received for '%s'" % _assembly.assembly_name)
			_refresh_assemblies_list.call_deferred()
	)
	assembly_manager.assembly_deleted.connect(
		func(_assembly_id):
			print("WorkbenchWindow: assembly_deleted signal received for '%s'" % _assembly_id)
			_refresh_assemblies_list.call_deferred()
	)

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
		"add_object_button": func(): _on_add_object_pressed(),
		"select_button": func(): _set_transform_mode(TransformMode.SELECT),
		"move_button": func(): _set_transform_mode(TransformMode.MOVE),
		"rotate_button": func(): _set_transform_mode(TransformMode.ROTATE),
		"scale_button": func(): _set_transform_mode(TransformMode.SCALE),
		"assemble_button": func(): _on_assemble_button_pressed(),
		"edit_assembly_button": func(): _on_edit_assembly_button_pressed(),
		"add_to_inventory_button": func(): _on_add_to_inventory_button_pressed(),
		"delete_assembly_button": func(): _on_delete_assembly_button_pressed(),
	}

	# Ghost mode button (toggle)
	var ghost_btn = ui_refs.get("ghost_mode_button")
	if ghost_btn:
		ghost_btn.toggled.connect(_on_ghost_mode_toggled)

	for button_name in buttons:
		var button = ui_refs.get(button_name)
		if button:
			button.pressed.connect(buttons[button_name])

	# Category filter
	var cat_filter = ui_refs.get("category_filter")
	if cat_filter:
		cat_filter.item_selected.connect(func(_index): ui_manager.populate_part_list())

	# Assemblies list - single click to select and load
	var assemblies_list = ui_refs.get("assemblies_list")
	if assemblies_list:
		assemblies_list.item_selected.connect(_on_assembly_selected)

	# Transform inputs
	_connect_transform_inputs(ui_refs)

	# Populate assemblies list
	_refresh_assemblies_list()


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
		NOTIFICATION_VISIBILITY_CHANGED:
			if not visible:
				_on_window_hidden()
			else:
				_on_window_shown()


func _reset_all_drag_states() -> void:
	"""Reset all drag states when focus is lost."""
	is_alt_held = false
	is_shift_held = false
	is_ctrl_held = false
	camera_controller.end_drag()
	gizmo_controller.cancel_gizmo_drag(selection_manager.selected_items)
	selection_manager.cancel_box_select()


func _on_window_shown() -> void:
	"""Called when the window is shown - re-enable input processing."""
	# Use call_deferred to check if we're really being shown or if this is a spurious call during close
	call_deferred("_deferred_window_shown")


func _deferred_window_shown() -> void:
	"""Deferred handler to actually enable input - allows us to check if window is truly showing."""
	# If marked as closing, ignore this show event (spurious during close sequence)
	if is_closing:
		return

	# Legitimately showing - enable input
	input_enabled = true
	set_process_input(true)
	set_process_unhandled_input(true)


func _on_window_hidden() -> void:
	"""Called when the window is hidden - clean up all input state."""
	# Set closing flag to prevent re-enabling during close transition
	is_closing = true

	# CRITICAL: Disable all input processing when hidden
	input_enabled = false
	set_process_input(false)
	set_process_unhandled_input(false)

	# Reset all input states
	_reset_all_drag_states()

	# Reset transform mode to SELECT
	current_transform_mode = TransformMode.SELECT

	# Update UI to reflect default state
	if ui_manager:
		ui_manager.update_mode_buttons(TransformMode.SELECT as WorkbenchUIManager.TransformMode)

	# Hide and reset gizmo
	if transform_gizmo:
		transform_gizmo.visible = false

	# Clear any manual transform editing state
	if manual_transform_timer:
		manual_transform_timer.stop()
	manual_transform_is_editing = false
	manual_transform_initial_values.clear()
	manual_transform_operation_type = ""

	# Exit assembly edit mode if active
	if is_editing_assembly:
		_exit_assembly_edit_mode()

	# Clear the workbench to ensure clean state on reopen
	clear_workbench()

	# Reset is_closing flag after the close sequence completes
	# This allows the window to be reopened properly
	call_deferred("_finalize_window_close")


func _finalize_window_close() -> void:
	"""Called after the close sequence completes to reset the closing flag."""
	# Use double-defer to ensure this happens AFTER any deferred show events
	call_deferred("_finalize_window_close_deferred")


func _finalize_window_close_deferred() -> void:
	"""Actually reset the closing flag after all deferred calls complete."""
	# If input is still disabled, we're truly closed - reset the flag
	if not input_enabled:
		is_closing = false


func _input(event: InputEvent) -> void:
	"""Handle global input events."""
	# CRITICAL: Stop processing ALL input when input is disabled or window not initialized
	# Note: Don't check 'visible' here as it updates asynchronously after _on_window_hidden
	if not initialized or not input_enabled:
		return

	# Track Alt, Shift, and Ctrl keys globally
	if event is InputEventKey:
		if event.keycode == KEY_ALT:
			is_alt_held = event.pressed
			if not is_alt_held and camera_controller.is_dragging:
				camera_controller.end_drag()
		elif event.keycode == KEY_SHIFT:
			is_shift_held = event.pressed
		elif event.keycode == KEY_CTRL:
			is_ctrl_held = event.pressed

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
				ui_manager.update_object_info(selection_manager.selected_items, false)
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	"""Process frame updates."""

	# Redraw selection box if needed
	if selection_manager.is_box_selecting and selection_overlay:
		selection_overlay.queue_redraw()

	# Update selection pivot - now done automatically in select_item()
	# (pivot is average center of all selected items)

	# Always update gizmo position if items are selected AND we're in a mode where editing is allowed
	# Only allow gizmo in: Design tab, OR Assembly tab + edit mode
	var editing_allowed = (current_tab == 0) or (current_tab == 1 and is_editing_assembly)

	if not selection_manager.selected_items.is_empty():
		if editing_allowed:
			# Verify that selected items are actually visible
			var has_visible_selection = false
			for item in selection_manager.selected_items:
				if item and item.visible:
					has_visible_selection = true
					break

			if has_visible_selection:
				_update_gizmo()
			else:
				# Selected items exist but aren't visible - clear selection
				selection_manager.clear_selection()
				if gizmo_controller:
					gizmo_controller.reset_gizmo_state()
				if transform_gizmo:
					transform_gizmo.visible = false
		else:
			# Not in an editable mode - force clear selection and hide gizmo
			selection_manager.clear_selection()
			if gizmo_controller:
				gizmo_controller.reset_gizmo_state()
			if transform_gizmo:
				transform_gizmo.visible = false

	# Update gizmo scale based on camera distance
	if transform_gizmo and transform_gizmo.visible and camera:
		transform_gizmo.update_scale_for_camera(camera.global_position)

	# Update object info display
	if not selection_manager.selected_items.is_empty():
		ui_manager.update_object_info(selection_manager.selected_items, false)


func _gui_input(event: InputEvent) -> void:
	"""Handle GUI input events."""
	if not initialized or not _is_mouse_over_viewport() or not input_enabled:
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
		# Try gizmo drag
		if gizmo_controller.try_start_gizmo_drag(event.position, selection_manager.selected_items):
			return

		# Try free movement in move mode
		if current_transform_mode == TransformMode.MOVE and not selection_manager.selected_items.is_empty():
			if gizmo_controller.try_start_free_movement(event.position, selection_manager.selected_items):
				return

		# Start box selection (which will handle single click if box is too small)
		# The shift state will be passed when the box selection finishes
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
		selection_manager.finish_box_select(is_shift_held, is_ctrl_held)
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

	current_transform_mode = mode
	gizmo_controller.set_transform_mode(mode as WorkbenchGizmoController.TransformMode)

	# Update UI
	ui_manager.update_mode_buttons(mode as WorkbenchUIManager.TransformMode)
	_update_gizmo()


func _update_gizmo() -> void:
	"""Update gizmo position and visibility."""
	gizmo_controller.update_gizmo_position(selection_manager.selected_items, false, selection_manager.selection_pivot_point)


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
					initial_values[item] = {"basis": initial_rotations[item], "position": initial_positions[item]}
					final_values[item] = {"basis": item.basis, "position": item.global_position}

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
	print("WorkbenchWindow: _on_selection_changed called, _selected_items.size() = %d" % _selected_items.size())
	print("  selection_manager.selected_items.size() = %d" % selection_manager.selected_items.size())
	_update_gizmo()
	ui_manager.update_object_info(selection_manager.selected_items, false)


func _on_transform_updated(operation: String, value: float, axis: Vector3) -> void:
	"""Handle transform update from gizmo controller."""
	ui_manager.update_transform_stats(operation, value, axis, gizmo_controller.snap_to_grid_enabled, gizmo_controller.grid_snap_size)


func _on_transform_completed(_mode: int) -> void:
	"""Handle transform completion."""
	ui_manager.clear_transform_stats()


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
				final_values[item] = {"basis": item.basis, "position": item.global_position}
			"scale":
				# Match the format of initial values (Dictionary with scale and position)
				final_values[item] = {"scale": item.scale, "position": item.global_position}

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
	undo_redo_manager.record_transform(operation_type, selection_manager.selected_items, filtered_initial_values, final_values)

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
				final_values[item] = {"basis": item.basis, "position": item.global_position}
				print("  Storing final rotation basis for item: ", item.name)
				print("    Rotation degrees: ", item.rotation_degrees)
				print("    Basis: ", item.basis)
			"scale":
				# Match the format of initial values (Dictionary with scale and position)
				final_values[item] = {"scale": item.scale, "position": item.global_position}

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
	undo_redo_manager.record_transform(operation_type, selection_manager.selected_items, filtered_initial_values, final_values)

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
		if selection_manager.selected_items.size() > 1 and false:
			initial_pivot = selection_manager.selection_pivot_point
			manual_transform_initial_values["__pivot__"] = initial_pivot
			print("  Storing cluster pivot: ", initial_pivot)

		# Store initial values - for rotation/scale we need BOTH position and basis/scale
		for item in selection_manager.selected_items:
			match component:
				"position":
					manual_transform_initial_values[item] = item.global_position
				"rotation":
					# Store both basis and position for rotation
					manual_transform_initial_values[item] = {"basis": item.basis, "position": item.global_position}
					print("  Storing initial rotation basis for item: ", item.name)
					print("    Rotation degrees: ", item.rotation_degrees)
					print("    Basis: ", item.basis)
				"scale":
					# Store both scale and position for scaling
					manual_transform_initial_values[item] = {"scale": item.scale, "position": item.global_position}

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
			ui_manager.update_object_info(selection_manager.selected_items, false)
		"redo":
			undo_redo_manager.redo()
			_update_gizmo()
			ui_manager.update_object_info(selection_manager.selected_items, false)
		"duplicate":
			_duplicate_selected_items()
		"delete":
			selection_manager.delete_selected_items()


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


func _on_ghost_mode_toggled(enabled: bool) -> void:
	"""Toggle ghost mode (semi-transparent objects)."""
	ghost_mode_enabled = enabled
	_apply_ghost_mode_to_all_items()
	print("Ghost mode: ", "enabled" if enabled else "disabled")


func _apply_ghost_mode_to_all_items() -> void:
	"""Apply or remove ghost mode transparency to all items in the workbench."""
	for child in world.get_children():
		if child is PhysicalItem:
			_set_item_ghost_mode(child, ghost_mode_enabled)


func _set_item_ghost_mode(item: PhysicalItem, enabled: bool) -> void:
	"""Set ghost mode (transparency) for a single item."""
	# Get all MeshInstance3D children recursively
	var meshes: Array[MeshInstance3D] = []
	_get_all_mesh_instances(item, meshes)

	for mesh in meshes:
		if enabled:
			# Enable transparency
			mesh.transparency = 0.5
		else:
			# Disable transparency
			mesh.transparency = 0.0


func _get_all_mesh_instances(node: Node, meshes: Array[MeshInstance3D]) -> void:
	"""Recursively find all MeshInstance3D nodes."""
	if node is MeshInstance3D:
		meshes.append(node)

	for child in node.get_children():
		_get_all_mesh_instances(child, meshes)


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
		# Apply ghost mode if it's currently enabled
		if ghost_mode_enabled:
			_set_item_ghost_mode(node, true)
		print("SUCCESS: Spawned PhysicalItem: %s at origin (collision_layer: %d, collision_mask: %d)" % [node.item_name, node.collision_layer, node.collision_mask])
	else:
		print("SUCCESS: Spawned node (not PhysicalItem): %s" % node.name)

	# Add to design items array (parts are always added to design tab)
	if node not in design_items:
		design_items.append(node)

	return node


func clear_workbench() -> void:
	"""Clear all items from the workbench."""
	for child in world.get_children():
		if child is PhysicalItem:
			child.queue_free()

	# Clear tracking arrays
	design_items.clear()
	assembly_items.clear()

	selection_manager.clear_selection()
	undo_redo_manager.clear_history()

	# Exit edit mode if active
	if is_editing_assembly:
		is_editing_assembly = false
		editing_assembly_id = ""
		_update_assembly_buttons_for_edit_mode(false)

	print("Workbench cleared")


func get_all_items() -> Array[PhysicalItem]:
	"""Get all PhysicalItem objects in the workbench (visible in current tab)."""
	var items: Array[PhysicalItem] = []
	for child in world.get_children():
		if child is PhysicalItem and child.visible:
			items.append(child)
	return items


func _clear_assembly_items() -> void:
	"""Clear only items in the assemblies tab."""
	for item in assembly_items:
		if is_instance_valid(item) and item is PhysicalItem:
			item.queue_free()
	assembly_items.clear()
	print("Cleared assembly items")


# Tab Management


func _on_tab_changed(tab: int) -> void:
	"""Handle tab switching between Design and Assemblies."""
	print("WorkbenchWindow: Tab changed to %d (0=Design, 1=Assemblies)" % tab)

	# FIRST: Clear selection and reset gizmo state BEFORE any other operations
	# This prevents the gizmo from appearing in the new tab
	selection_manager.clear_selection()
	if gizmo_controller:
		gizmo_controller.reset_gizmo_state()
	if transform_gizmo:
		transform_gizmo.visible = false

	# If switching away from Assemblies tab while in edit mode, exit edit mode
	if current_tab == 1 and is_editing_assembly:
		print("WorkbenchWindow: Exiting edit mode due to tab change")
		_exit_assembly_edit_mode()

	# Store current tab items before switching
	_store_current_tab_items()

	# Update current tab
	current_tab = tab

	# Hide all items in the world
	_hide_all_items()

	# Show items for the new tab
	_show_current_tab_items()


func _store_current_tab_items() -> void:
	"""Store items visible in the current tab before switching."""
	# Get all visible items in world
	var visible_items: Array[Node] = []
	for child in world.get_children():
		if child is PhysicalItem and child.visible:
			visible_items.append(child)

	# Store based on current tab
	if current_tab == 0:  # Design tab
		design_items = visible_items
		print("Stored %d design items" % design_items.size())
	elif current_tab == 1:  # Assemblies tab
		assembly_items = visible_items
		print("Stored %d assembly items" % assembly_items.size())


func _hide_all_items() -> void:
	"""Hide all items in the world."""
	for child in world.get_children():
		if child is PhysicalItem:
			child.visible = false


func _show_current_tab_items() -> void:
	"""Show items for the current tab."""
	var items_to_show: Array[Node] = []

	if current_tab == 0:  # Design tab
		items_to_show = design_items
		print("Showing %d design items" % items_to_show.size())
	elif current_tab == 1:  # Assemblies tab
		items_to_show = assembly_items
		print("Showing %d assembly items" % items_to_show.size())

	# Show the items
	for item in items_to_show:
		if is_instance_valid(item) and item is PhysicalItem:
			item.visible = true


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
		context_menu.add_menu_item("frame_selected", "Frame Selected", null, not selection_manager.selected_items.is_empty())
		context_menu.add_separator()
		context_menu.add_menu_item("select_all", "Select All")
		context_menu.add_menu_item("select_none", "Select None", null, not selection_manager.selected_items.is_empty())
	else:
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
			new_item.global_position = item.global_position
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
	ui_manager.update_object_info(selection_manager.selected_items, false)


# Assembly Management


func _on_assemble_button_pressed() -> void:
	"""Handle the Assemble button press - create a new assembly from selected items."""
	print("WorkbenchWindow: _on_assemble_button_pressed() called")
	print("  Selected items count: %d" % selection_manager.selected_items.size())

	if selection_manager.selected_items.is_empty():
		print("WorkbenchWindow: Cannot assemble - no items selected")
		return

	print("WorkbenchWindow: Creating assembly name dialog...")
	# Prompt for assembly name
	var dialog = _create_assembly_name_dialog()
	print("WorkbenchWindow: Showing dialog...")
	dialog.popup_centered()


func _create_assembly_name_dialog() -> AcceptDialog:
	"""Create a dialog to input assembly name."""
	print("WorkbenchWindow: _create_assembly_name_dialog() started")
	var dialog = AcceptDialog.new()
	dialog.title = "Create Assembly"
	dialog.dialog_text = "Enter a name for this assembly:"
	dialog.ok_button_text = "Create"

	# Create input field
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 0)

	var line_edit = LineEdit.new()
	line_edit.name = "AssemblyNameInput"
	line_edit.placeholder_text = "Assembly Name"
	line_edit.text = "Assembly %d" % (assembly_manager.get_all_assemblies().size() + 1)
	vbox.add_child(line_edit)

	# Add to dialog (replace the label)
	for child in dialog.get_children():
		if child is Label:
			child.queue_free()

	dialog.add_child(vbox)
	add_child(dialog)

	# Connect accept signal
	dialog.confirmed.connect(
		func():
			print("WorkbenchWindow: Dialog confirmed! Assembly name: '%s'" % line_edit.text)
			_finalize_assembly_creation(line_edit.text, dialog)
	)
	dialog.close_requested.connect(
		func():
			print("WorkbenchWindow: Dialog closed")
			dialog.queue_free()
	)

	print("WorkbenchWindow: Dialog created and signals connected")
	return dialog


func _finalize_assembly_creation(assembly_name: String, dialog: AcceptDialog) -> void:
	"""Finalize the assembly creation with the given name."""
	print("WorkbenchWindow: _finalize_assembly_creation() called with name: '%s'" % assembly_name)
	if assembly_name.strip_edges().is_empty():
		assembly_name = "Assembly %d" % (assembly_manager.get_all_assemblies().size() + 1)
		print("WorkbenchWindow: Using default assembly name: '%s'" % assembly_name)

	# Frame the selected items for a good thumbnail shot
	camera_controller.frame_objects(selection_manager.selected_items)

	# Wait for camera to finish framing and rendering to complete
	# Note: We use a timer instead of await camera_framed to avoid potential deadlock
	await get_tree().create_timer(0.2).timeout
	print("WorkbenchWindow: Camera framed, capturing thumbnail...")

	# Capture viewport image for thumbnail
	var viewport_image = await camera_controller.capture_viewport_image()

	# Create assembly from selected items
	var assembly = assembly_manager.create_assembly_from_items(selection_manager.selected_items, assembly_name)

	if assembly:
		# Generate and save thumbnail
		if viewport_image:
			var thumbnail_path = assembly_manager.generate_thumbnail_from_image(viewport_image, assembly.assembly_id)
			if not thumbnail_path.is_empty():
				assembly.icon_path = thumbnail_path
				assembly.preview_texture = assembly_manager.load_thumbnail(thumbnail_path)

				# Save assembly with updated thumbnail info
				var save_path = assembly_manager.ASSEMBLY_SAVE_DIR + assembly.assembly_id + ".tres"
				assembly.save_to_file(save_path)

				print("WorkbenchWindow: Created assembly '%s' with thumbnail" % assembly.assembly_name)
			else:
				print("WorkbenchWindow: Created assembly '%s' but failed to generate thumbnail" % assembly.assembly_name)
		else:
			print("WorkbenchWindow: Created assembly '%s' but failed to capture viewport" % assembly.assembly_name)

		# Wait a frame before refreshing to ensure everything is ready
		await get_tree().process_frame
		_refresh_assemblies_list()
		print("WorkbenchWindow: Refreshed assemblies list after creation")
	else:
		print("WorkbenchWindow: Failed to create assembly")

	dialog.queue_free()


func _refresh_assemblies_list() -> void:
	"""Refresh the assemblies list UI."""
	var assemblies_list = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Assemblies/VBoxContainer/AssembliesSection/AssembliesList
	if not assemblies_list:
		print("WorkbenchWindow: ERROR - assemblies_list node not found in _refresh_assemblies_list")
		return

	var all_assemblies = assembly_manager.get_all_assemblies()
	print("WorkbenchWindow: Refreshing assemblies list with %d assemblies" % all_assemblies.size())

	assemblies_list.clear()

	for assembly in all_assemblies:
		assemblies_list.add_item(assembly.assembly_name)
		# Store assembly_id as metadata
		var index = assemblies_list.item_count - 1
		assemblies_list.set_item_metadata(index, assembly.assembly_id)
		print("  Added '%s' to list at index %d" % [assembly.assembly_name, index])


func _on_assembly_selected(index: int) -> void:
	"""Handle selection of an assembly - just show it in the viewport (not editable until Edit mode)."""
	# If we're already in edit mode, don't reload the assembly
	if is_editing_assembly:
		print("WorkbenchWindow: Already in edit mode, ignoring selection")
		return

	# Defer the loading to avoid blocking the UI selection
	_load_assembly_for_preview(index)


func _load_assembly_for_preview(index: int) -> void:
	"""Load an assembly for preview only (not selectable/editable until Edit mode)."""
	var assemblies_list = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Assemblies/VBoxContainer/AssembliesSection/AssembliesList
	if not assemblies_list:
		return

	var assembly_id = assemblies_list.get_item_metadata(index)
	var assembly = assembly_manager.get_assembly(assembly_id)

	if not assembly:
		print("WorkbenchWindow: Assembly not found")
		return

	# Show assembly info in console
	print("Loading assembly for preview:\n%s" % assembly.get_summary())

	# Clear only assembly items (not design items)
	_clear_assembly_items()

	# Spawn assembly into workbench (without physics, and non-interactive)
	# Pass enable_selection=false to prevent selecting items in preview mode
	var spawned_items = await assembly_manager.spawn_assembly(assembly_id, world, Vector3.ZERO, false, false)

	if not spawned_items.is_empty():
		print("WorkbenchWindow: Loaded assembly '%s' for preview (not editable)" % assembly.assembly_name)

		# Add spawned items to assembly_items array
		for item in spawned_items:
			if item is PhysicalItem:
				print("  Item '%s' - collision_layer: %d, collision_mask: %d" % [item.item_name, item.collision_layer, item.collision_mask])
				if item not in assembly_items:
					assembly_items.append(item)
				# Hide if we're not on the assemblies tab
				if current_tab != 1:
					item.visible = false

		# Wait a frame to ensure items are fully in the tree
		await get_tree().process_frame

		# Frame the items in view (only if we're on assemblies tab)
		if current_tab == 1:
			camera_controller.frame_objects(spawned_items)
	else:
		print("WorkbenchWindow: Failed to load assembly for preview")


func _load_assembly_for_editing(index: int) -> void:
	"""Load an assembly and make it editable (selectable/transformable)."""
	var assemblies_list = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Assemblies/VBoxContainer/AssembliesSection/AssembliesList
	if not assemblies_list:
		return

	var assembly_id = assemblies_list.get_item_metadata(index)
	var assembly = assembly_manager.get_assembly(assembly_id)

	if not assembly:
		print("WorkbenchWindow: Assembly not found")
		return

	# Show assembly info in console
	print("Loading assembly for editing:\n%s" % assembly.get_summary())

	# Clear only assembly items (not design items)
	_clear_assembly_items()

	# Spawn assembly into workbench for editing (without physics, but selectable)
	# Pass enable_selection=true to allow selecting items in edit mode
	var spawned_items = await assembly_manager.spawn_assembly(assembly_id, world, Vector3.ZERO, false, true)

	if not spawned_items.is_empty():
		# Items spawned with enable_selection=true have collision_layer=4 for selection
		print("WorkbenchWindow: Loaded assembly '%s' for editing with %d items" % [assembly.assembly_name, spawned_items.size()])

		# Add spawned items to assembly_items array
		for item in spawned_items:
			if item is PhysicalItem:
				if item not in assembly_items:
					assembly_items.append(item)
				# Hide if we're not on the assemblies tab
				if current_tab != 1:
					item.visible = false

		# Wait a frame to ensure items are fully in the tree
		await get_tree().process_frame

		# Frame the items in view (only if we're on assemblies tab)
		if current_tab == 1:
			camera_controller.frame_objects(spawned_items)
	else:
		print("WorkbenchWindow: Failed to load assembly for editing")


func _enable_selection_on_loaded_items() -> void:
	"""Enable selection on items that are already loaded in preview mode."""
	var items = get_all_items()
	for item in items:
		if item is PhysicalItem:
			item.collision_layer = 4  # Enable layer 3 for workbench selection
			item.collision_mask = 0  # Keep collisions disabled

	print("WorkbenchWindow: Enabled selection on %d loaded items" % items.size())


func _disable_selection_on_loaded_items() -> void:
	"""Disable selection on items (make them preview-only)."""
	var items = get_all_items()
	print("WorkbenchWindow: Disabling selection on %d items..." % items.size())
	for item in items:
		if item is PhysicalItem:
			print("  Setting '%s' collision_layer from %d to 0" % [item.item_name, item.collision_layer])
			item.collision_layer = 0  # Disable selection layer
			item.collision_mask = 0  # Keep collisions disabled
			print("  Verified '%s' collision_layer is now: %d" % [item.item_name, item.collision_layer])

	# Clear any active selection
	selection_manager.clear_selection()

	print("WorkbenchWindow: Disabled selection on %d loaded items" % items.size())


func _on_add_to_inventory_button_pressed() -> void:
	"""Add the selected assembly as an item to the player's inventory."""
	# Disable input while processing to prevent double-clicks
	input_enabled = false
	await _add_assembly_to_inventory_with_thumbnail()
	input_enabled = true


func _add_assembly_to_inventory_with_thumbnail() -> void:
	"""Async function to capture thumbnail and add assembly to inventory."""
	print("WorkbenchWindow: _add_assembly_to_inventory_with_thumbnail() called")

	var assemblies_list = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Assemblies/VBoxContainer/AssembliesSection/AssembliesList
	if not assemblies_list:
		print("WorkbenchWindow: ERROR - assemblies_list is null")
		return

	var selected = assemblies_list.get_selected_items()
	if selected.is_empty():
		print("WorkbenchWindow: No assembly selected to add to inventory")
		return

	var index = selected[0]
	var assembly_id = assemblies_list.get_item_metadata(index)
	var assembly = assembly_manager.get_assembly(assembly_id)

	if not assembly:
		print("WorkbenchWindow: Assembly not found")
		return

	# Capture thumbnail from current viewport view (without framing to avoid window closing)
	print("WorkbenchWindow: Capturing thumbnail from current view...")
	var current_items = get_all_items()
	print("WorkbenchWindow: Found %d items in workbench" % current_items.size())

	if not current_items.is_empty():
		# Wait one frame for rendering
		await get_tree().process_frame

		# Capture and save thumbnail
		print("WorkbenchWindow: Capturing viewport image...")
		var viewport_image = await camera_controller.capture_viewport_image()
		if viewport_image:
			print("WorkbenchWindow: Image captured, generating thumbnail...")
			var thumbnail_path = assembly_manager.generate_thumbnail_from_image(viewport_image, assembly.assembly_id)
			if not thumbnail_path.is_empty():
				assembly.icon_path = thumbnail_path
				assembly.preview_texture = assembly_manager.load_thumbnail(thumbnail_path)

				# Save assembly with updated thumbnail
				var save_path = assembly_manager.ASSEMBLY_SAVE_DIR + assembly.assembly_id + ".tres"
				assembly.save_to_file(save_path)
				print("WorkbenchWindow: Generated fresh thumbnail for inventory at: %s" % thumbnail_path)
		else:
			print("WorkbenchWindow: WARNING - Failed to capture viewport image")

	print("WorkbenchWindow: Getting player reference...")
	# Get player reference
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		print("WorkbenchWindow: No player found")
		return

	var player = players[0]
	var inventory_integration = player.get_node_or_null("InventoryIntegration")
	if not inventory_integration:
		print("WorkbenchWindow: Player doesn't have InventoryIntegration")
		return

	var inventory_manager = inventory_integration.inventory_manager
	if not inventory_manager:
		print("WorkbenchWindow: No inventory manager found")
		return

	var player_inventory = inventory_manager.get_player_inventory()
	if not player_inventory:
		print("WorkbenchWindow: No player inventory found")
		return

	print("WorkbenchWindow: Converting assembly to inventory item...")
	# Convert assembly to inventory item
	var item_data = assembly_manager.convert_assembly_to_inventory_item(assembly)
	if not item_data:
		print("WorkbenchWindow: Failed to convert assembly to inventory item")
		return

	print("WorkbenchWindow: Checking if can add item...")
	# Check if can add
	if not player_inventory.can_add_item(item_data):
		NotificationManager.show_warning("Inventory is full!")
		print("WorkbenchWindow: Inventory is full!")
		return

	print("WorkbenchWindow: Adding item to inventory...")
	# Add to inventory
	var success = player_inventory.add_item(item_data)

	if success:
		NotificationManager.show_item_pickup(assembly.assembly_name, 1)
		print("WorkbenchWindow: SUCCESS - Added assembly '%s' to inventory" % assembly.assembly_name)

		# Update inventory window if open
		if inventory_integration.is_inventory_window_open():
			var inventory_window = inventory_integration.get_inventory_window()
			if inventory_window and inventory_window.content:
				inventory_window.content.refresh_display()
				print("WorkbenchWindow: Refreshed inventory display")
	else:
		NotificationManager.show_error("Failed to add assembly to inventory")
		print("WorkbenchWindow: ERROR - Failed to add assembly to inventory")

	print("WorkbenchWindow: _add_assembly_to_inventory_with_thumbnail() completed")


func _on_delete_assembly_button_pressed() -> void:
	"""Delete the selected assembly, or discard edits if in edit mode."""
	# If in edit mode, this is the Discard button
	if is_editing_assembly:
		_discard_assembly_edits()
		return

	# Otherwise, this is the Delete button
	var assemblies_list = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Assemblies/VBoxContainer/AssembliesSection/AssembliesList
	if not assemblies_list:
		return

	var selected = assemblies_list.get_selected_items()
	if selected.is_empty():
		print("WorkbenchWindow: No assembly selected to delete")
		return

	var index = selected[0]
	var assembly_id = assemblies_list.get_item_metadata(index)
	var assembly = assembly_manager.get_assembly(assembly_id)

	if not assembly:
		print("WorkbenchWindow: Assembly not found")
		return

	# Confirm deletion
	var confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Delete Assembly"
	confirm_dialog.dialog_text = "Are you sure you want to delete '%s'?" % assembly.assembly_name
	add_child(confirm_dialog)

	confirm_dialog.confirmed.connect(func(): _finalize_assembly_deletion(assembly_id, confirm_dialog))
	confirm_dialog.close_requested.connect(func(): confirm_dialog.queue_free())
	confirm_dialog.popup_centered()


func _finalize_assembly_deletion(assembly_id: String, dialog: ConfirmationDialog) -> void:
	"""Finalize the assembly deletion."""
	if assembly_manager.delete_assembly(assembly_id):
		print("WorkbenchWindow: Deleted assembly")

		# Clear the assembly items from the viewport
		_clear_assembly_items()

		# Clear selection since the items are gone
		selection_manager.clear_selection()

		# Refresh the assemblies list UI
		_refresh_assemblies_list()
	else:
		print("WorkbenchWindow: Failed to delete assembly")

	dialog.queue_free()


func _on_edit_assembly_button_pressed() -> void:
	"""Handle Edit/Update button press - enter or save edit mode."""
	if is_editing_assembly:
		# We're in edit mode, so this is the Update button
		_update_assembly_edits()
	else:
		# Enter edit mode
		_enter_assembly_edit_mode()


func _enter_assembly_edit_mode() -> void:
	"""Enter edit mode for the selected assembly."""
	var assemblies_list = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Assemblies/VBoxContainer/AssembliesSection/AssembliesList
	if not assemblies_list:
		return

	var selected = assemblies_list.get_selected_items()
	if selected.is_empty():
		print("WorkbenchWindow: No assembly selected to edit")
		return

	var index = selected[0]
	var assembly_id = assemblies_list.get_item_metadata(index)
	var assembly = assembly_manager.get_assembly(assembly_id)

	if not assembly:
		print("WorkbenchWindow: Assembly not found")
		return

	# Enter edit mode
	is_editing_assembly = true
	editing_assembly_id = assembly_id

	# Update button text
	_update_assembly_buttons_for_edit_mode(true)

	# Load assembly for editing (making it selectable/transformable)
	if get_all_items().is_empty():
		_load_assembly_for_editing(index)
	else:
		# Items are already loaded, just enable selection on them
		_enable_selection_on_loaded_items()

	print("WorkbenchWindow: Entered edit mode for assembly '%s'" % assembly.assembly_name)


func _update_assembly_edits() -> void:
	"""Save the edited assembly (Update button)."""
	if not is_editing_assembly or editing_assembly_id.is_empty():
		return

	var assembly = assembly_manager.get_assembly(editing_assembly_id)
	if not assembly:
		print("WorkbenchWindow: Assembly not found for update")
		return

	# Get all current items in the workbench
	var current_items = get_all_items()
	if current_items.is_empty():
		print("WorkbenchWindow: No items to update assembly")
		return

	# Exit edit mode FIRST before async operations to prevent getting stuck
	# This also clears selection and cancels any active transforms
	_exit_assembly_edit_mode()

	# Disable selection IMMEDIATELY to prevent interaction during async operations
	_disable_selection_on_loaded_items()

	# Create updated assembly data from current items BEFORE any async operations
	# (framing might cause async issues with item validity)
	var updated_assembly = AssemblyData.from_physical_items(current_items, assembly.assembly_name)
	if not updated_assembly:
		print("WorkbenchWindow: Failed to create updated assembly data")
		return

	# Copy over the new data to the existing assembly (preserving ID and metadata) IMMEDIATELY
	# This must happen BEFORE async operations to ensure the assembly is saved even if async fails
	print("WorkbenchWindow: Copying updated assembly data...")
	assembly.parts = updated_assembly.parts
	assembly.total_mass = updated_assembly.total_mass
	assembly.total_volume = updated_assembly.total_volume
	assembly.assembly_value = updated_assembly.assembly_value
	assembly.bounds_min = updated_assembly.bounds_min
	assembly.bounds_max = updated_assembly.bounds_max
	print("WorkbenchWindow: Assembly data copied")

	# Save to file IMMEDIATELY before async operations
	print("WorkbenchWindow: Saving assembly to file...")
	var save_path = assembly_manager.ASSEMBLY_SAVE_DIR + assembly.assembly_id + ".tres"
	assembly.save_to_file(save_path)
	print("WorkbenchWindow: Updated assembly '%s' with %d parts" % [assembly.assembly_name, assembly.parts.size()])

	# Now try to generate thumbnail (async operations below may fail, but assembly is already saved)
	# Frame all items for a good thumbnail shot
	camera_controller.frame_objects(current_items)

	# Wait for camera to finish framing
	await camera_controller.camera_framed

	# Wait an additional frame to ensure rendering is complete
	await get_tree().process_frame

	# Capture viewport image for updated thumbnail
	var viewport_image = await camera_controller.capture_viewport_image()

	# Generate and save updated thumbnail (if async operations succeeded)
	if viewport_image:
		print("WorkbenchWindow: Generating thumbnail...")
		var thumbnail_path = assembly_manager.generate_thumbnail_from_image(viewport_image, assembly.assembly_id)
		if not thumbnail_path.is_empty():
			assembly.icon_path = thumbnail_path
			assembly.preview_texture = assembly_manager.load_thumbnail(thumbnail_path)
			print("WorkbenchWindow: Updated thumbnail for assembly '%s'" % assembly.assembly_name)
			# Re-save assembly with updated thumbnail info
			assembly.save_to_file(save_path)
	else:
		print("WorkbenchWindow: No viewport image captured")

	# Refresh the list
	_refresh_assemblies_list()


func _discard_assembly_edits() -> void:
	"""Discard edits and reload the original assembly (Discard button)."""
	if not is_editing_assembly or editing_assembly_id.is_empty():
		return

	var assembly = assembly_manager.get_assembly(editing_assembly_id)
	if not assembly:
		print("WorkbenchWindow: Assembly not found for discard")
		_exit_assembly_edit_mode()
		return

	print("WorkbenchWindow: Discarding edits to assembly '%s'" % assembly.assembly_name)

	# Clear the workbench
	clear_workbench()

	# Reload the original assembly
	var assemblies_list = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Assemblies/VBoxContainer/AssembliesSection/AssembliesList
	if assemblies_list:
		# Find the index of the assembly we're editing
		for i in range(assemblies_list.item_count):
			if assemblies_list.get_item_metadata(i) == editing_assembly_id:
				# Temporarily exit edit mode to allow loading
				_exit_assembly_edit_mode()
				# Reload the assembly for editing
				_load_assembly_for_editing(i)
				# Re-enter edit mode
				is_editing_assembly = true
				editing_assembly_id = assemblies_list.get_item_metadata(i)
				_update_assembly_buttons_for_edit_mode(true)
				break
	else:
		_exit_assembly_edit_mode()


func _exit_assembly_edit_mode() -> void:
	"""Exit edit mode."""
	# Cancel any active transforms
	if gizmo_controller.is_gizmo_dragging:
		gizmo_controller.cancel_gizmo_drag(selection_manager.selected_items)

	# Clear selection and reset gizmo state completely
	selection_manager.clear_selection()
	if gizmo_controller:
		gizmo_controller.reset_gizmo_state()

	if transform_gizmo:
		transform_gizmo.visible = false

	is_editing_assembly = false
	editing_assembly_id = ""

	# Update button text back to normal
	_update_assembly_buttons_for_edit_mode(false)

	print("WorkbenchWindow: Exited assembly edit mode")


func _update_assembly_buttons_for_edit_mode(in_edit_mode: bool) -> void:
	"""Update assembly button text based on edit mode state."""
	var edit_button = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Assemblies/VBoxContainer/AssembliesSection/AssemblyButtonContainer/HBoxContainer/EditAssemblyButton
	var delete_button = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/TabContainer/Assemblies/VBoxContainer/AssembliesSection/AssemblyButtonContainer/HBoxContainer/DeleteAssemblyButton

	if in_edit_mode:
		# In edit mode: Edit -> Update, Delete -> Discard
		if edit_button:
			edit_button.text = "Update"
		if delete_button:
			delete_button.text = "Discard"
		# Show yellow border and label to indicate edit mode
		if edit_mode_border:
			edit_mode_border.visible = true
		if edit_mode_label:
			edit_mode_label.visible = true
	else:
		# Normal mode: Update -> Edit, Discard -> Delete
		if edit_button:
			edit_button.text = "Edit"
		if delete_button:
			delete_button.text = "Delete"
		# Hide yellow border and label
		if edit_mode_border:
			edit_mode_border.visible = false
		if edit_mode_label:
			edit_mode_label.visible = false
