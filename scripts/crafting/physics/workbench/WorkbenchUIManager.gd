class_name WorkbenchUIManager
extends RefCounted

## Manages all UI elements, panels, and input handling for the workbench.
##
## Handles:
## - Part list and category filtering
## - Transform mode buttons
## - Transform input panel (position, rotation, scale spinboxes)
## - Transform stats display
## - Object info display
## - Viewport settings dialog
## - Fastener selection dialog

signal mode_button_pressed(mode: int)
signal part_spawn_requested(scene_path: String)
signal clear_requested()
signal validate_requested()
signal category_filter_changed(category: int)
signal transform_input_changed(component: String, axis: String, value: float)
signal viewport_settings_changed(grid_size: float, gizmo_scale: float, bg_color: Color, floor_color: Color)
signal fastener_selected(fastener_id: String)

# Transform modes enum
enum TransformMode { SELECT, MOVE, ROTATE, SCALE, CONNECT }

# Category filter enum
enum CategoryFilter { ALL, STRUCTURAL_ITEMS, COSMETIC, HARDWARE, CONTAINERS }

# UI References
var part_list: ItemList
var category_filter: OptionButton
var add_object_button: Button
var validate_button: Button
var clear_button: Button
var help_label: Label

# Transform mode buttons
var select_button: Button
var move_button: Button
var rotate_button: Button
var scale_button: Button
var connect_mode_button: Button

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
var is_updating_transform_inputs: bool = false

# Info labels
var transform_stats_label: Label
var object_info_label: Label

# Sidebar
var sidebar_panel: PanelContainer
var separator: Control
var is_dragging_separator: bool = false
var sidebar_drag_start_x: float = 0.0
var sidebar_initial_width: float = 250.0

# Dialog state
var is_dialog_open: bool = false

# Part data
var available_parts: Dictionary = {}
var part_categories: Dictionary = {}
var current_category_filter: CategoryFilter = CategoryFilter.ALL

# Available fasteners
var available_fasteners: Array[String] = [
	"fastener_iron_nail",
	"fastener_steel_screw",
	"fastener_steel_bolt",
	"fastener_hinge",
	"fastener_ball_joint"
]

# Scene references
var world_environment: WorldEnvironment
var ground_plane: MeshInstance3D
var grid: MeshInstance3D
var transform_gizmo: TransformGizmo


func setup_ui_references(ui_refs: Dictionary) -> void:
	"""Setup all UI element references from the main window."""
	# Part list and controls
	part_list = ui_refs.get("part_list")
	category_filter = ui_refs.get("category_filter")
	add_object_button = ui_refs.get("add_object_button")
	validate_button = ui_refs.get("validate_button")
	clear_button = ui_refs.get("clear_button")
	help_label = ui_refs.get("help_label")

	# Transform mode buttons
	select_button = ui_refs.get("select_button")
	move_button = ui_refs.get("move_button")
	rotate_button = ui_refs.get("rotate_button")
	scale_button = ui_refs.get("scale_button")
	connect_mode_button = ui_refs.get("connect_mode_button")

	# Transform panel
	transform_panel = ui_refs.get("transform_panel")
	position_x_input = ui_refs.get("position_x_input")
	position_y_input = ui_refs.get("position_y_input")
	position_z_input = ui_refs.get("position_z_input")
	rotation_x_input = ui_refs.get("rotation_x_input")
	rotation_y_input = ui_refs.get("rotation_y_input")
	rotation_z_input = ui_refs.get("rotation_z_input")
	scale_x_input = ui_refs.get("scale_x_input")
	scale_y_input = ui_refs.get("scale_y_input")
	scale_z_input = ui_refs.get("scale_z_input")

	# Labels
	transform_stats_label = ui_refs.get("transform_stats_label")
	object_info_label = ui_refs.get("object_info_label")

	# Sidebar
	sidebar_panel = ui_refs.get("sidebar_panel")
	separator = ui_refs.get("separator")

	# Scene references
	world_environment = ui_refs.get("world_environment")
	ground_plane = ui_refs.get("ground_plane")
	grid = ui_refs.get("grid")
	transform_gizmo = ui_refs.get("transform_gizmo")

	# Available parts and categories
	available_parts = ui_refs.get("available_parts", {})
	part_categories = ui_refs.get("part_categories", {})


func populate_part_list() -> void:
	"""Fill the part list with available items to spawn, filtered by category."""
	if not part_list:
		return
	part_list.clear()

	for part_name in available_parts.keys():
		if _should_show_part(part_name):
			part_list.add_item(part_name.replace("_", " ").capitalize())


func update_mode_buttons(current_mode: TransformMode) -> void:
	"""Update the visual state of transform mode buttons based on current mode."""
	if not select_button or not move_button or not rotate_button or not scale_button:
		return

	select_button.set_pressed_no_signal(current_mode == TransformMode.SELECT)
	move_button.set_pressed_no_signal(current_mode == TransformMode.MOVE)
	rotate_button.set_pressed_no_signal(current_mode == TransformMode.ROTATE)
	scale_button.set_pressed_no_signal(current_mode == TransformMode.SCALE)


func update_transform_stats(operation: String, value: float, axis: Vector3, snap_to_grid: bool, grid_snap_size: float) -> void:
	"""Update the transform stats label during operations."""
	if not transform_stats_label:
		return

	var axis_name = _get_axis_name(axis)

	var text = ""
	if operation == "Move":
		text = "Move: %.2f units (%s)" % [value, axis_name]
		if snap_to_grid:
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

	transform_stats_label.text = text


func clear_transform_stats() -> void:
	"""Clear the transform stats label."""
	if transform_stats_label:
		transform_stats_label.text = ""


func update_object_info(selected_items: Array[PhysicalItem], is_cluster: bool = false) -> void:
	"""Update the object info label showing selected object's transform data."""
	if not object_info_label:
		return

	# Update transform panel visibility and values
	update_transform_panel(selected_items)

	if selected_items.is_empty():
		object_info_label.text = ""
		return

	if selected_items.size() > 1:
		# Multiple objects - show count and joint/fastener info
		var text = ""
		if is_cluster:
			text = "Cluster Selected (%d objects)" % selected_items.size()
		else:
			text = "Multiple Selected (%d objects)" % selected_items.size()

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

	# Single object selected - show its transform info
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


func update_transform_panel(selected_items: Array[PhysicalItem]) -> void:
	"""Update the transform panel with current selection's transform values."""
	if not transform_panel:
		return

	# Show panel only when items are selected
	if selected_items.is_empty():
		transform_panel.visible = false
		return

	transform_panel.visible = true

	# Determine what values to display
	var pos: Vector3
	var rot: Vector3
	var scale_vec: Vector3

	# Get the first item's values as reference
	var item = selected_items[0]

	# For clustered objects (multiple items with active pivot), show pivot's position
	# For rotation/scale, still show first item's values as reference
	if selected_items.size() > 1:
		# TODO: For now, show first item's values
		# In the future, could show pivot position for clustered objects
		pos = item.global_position
		rot = item.rotation_degrees
		scale_vec = item.scale
	else:
		# Single selection - show item's values
		pos = item.global_position
		rot = item.rotation_degrees
		scale_vec = item.scale

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


func show_fastener_selection_dialog(selected_items: Array[PhysicalItem], parent_node: Node) -> void:
	"""Show a dialog to select which fastener to use for attaching selected items."""
	print("show_fastener_selection_dialog called with %d selected items" % selected_items.size())

	if selected_items.size() < 2:
		print("ERROR: Need at least 2 items selected to attach with fastener")
		return

	# Remove any existing popup
	var existing_popup = parent_node.get_node_or_null("FastenerSelectionPopup")
	if existing_popup:
		existing_popup.queue_free()

	# Create simple popup menu for fastener selection
	var popup = PopupMenu.new()
	popup.name = "FastenerSelectionPopup"

	# Add fastener options
	for i in range(available_fasteners.size()):
		var fastener_id = available_fasteners[i]
		var fastener_name = get_fastener_display_name(fastener_id)
		popup.add_item(fastener_name, i)

	# Connect signals
	popup.id_pressed.connect(func(index: int): _on_fastener_popup_selected(index))
	popup.popup_hide.connect(func(): popup.queue_free())

	# Add to scene and show
	parent_node.add_child(popup)
	var mouse_pos = parent_node.get_global_mouse_position()
	popup.position = Vector2i(mouse_pos)
	popup.popup()


func show_viewport_settings_dialog(parent_node: Node, grid_snap_size: float) -> void:
	"""Show viewport settings dialog for configuring grid size, gizmo scale, etc."""
	print("ViewportSettings: Opening dialog")

	# Disable selection and translation while dialog is open
	is_dialog_open = true

	# Get current settings
	var current_grid_size = grid_snap_size
	var current_gizmo_scale = transform_gizmo.gizmo_size if transform_gizmo else 1.5
	var current_bg_color = Color(0.2, 0.2, 0.25, 1.0)
	var current_floor_color = Color(0.15, 0.15, 0.15, 1.0)

	# Get current background color
	if world_environment and world_environment.environment:
		if world_environment.environment.background_mode == Environment.BG_COLOR:
			current_bg_color = world_environment.environment.background_color

	# Get current floor color
	if ground_plane:
		var floor_material = ground_plane.get_surface_override_material(0) as StandardMaterial3D
		if floor_material:
			current_floor_color = floor_material.albedo_color

	# Create the settings dialog
	var settings_dialog = ViewportSettingsDialog.new(
		current_grid_size,
		current_gizmo_scale,
		current_bg_color,
		current_floor_color
	)

	# Add to scene
	var ui_manager = parent_node.get_tree().get_first_node_in_group("ui_manager")
	if ui_manager and ui_manager.has_method("get_pause_canvas"):
		ui_manager.get_pause_canvas().add_child(settings_dialog)
	else:
		parent_node.get_tree().current_scene.add_child(settings_dialog)

	# Setup async initialization
	_setup_viewport_dialog_async(settings_dialog, parent_node)


func load_viewport_settings() -> void:
	"""Load and apply saved viewport settings on startup."""
	var saved_settings = ViewportSettingsDialog.load_saved_settings()

	# Apply grid visual scale
	if grid:
		var shader_material = grid.material_override as ShaderMaterial
		if not shader_material and grid.get_surface_override_material_count() > 0:
			shader_material = grid.get_surface_override_material(0) as ShaderMaterial

		if shader_material:
			shader_material.set_shader_parameter("grid_scale", saved_settings["grid_size"])

	# Apply gizmo scale - must recreate gizmo visuals after changing size
	if transform_gizmo:
		transform_gizmo.gizmo_size = saved_settings["gizmo_scale"]
		# Recreate gizmo visuals with new size
		transform_gizmo._create_move_gizmo()
		transform_gizmo._create_rotate_gizmo()
		transform_gizmo._create_scale_gizmo()
		# Restore the current mode
		transform_gizmo.set_mode(transform_gizmo.current_mode)

	# Apply background color
	if world_environment:
		if not world_environment.environment:
			world_environment.environment = Environment.new()
		world_environment.environment.background_mode = Environment.BG_COLOR
		world_environment.environment.background_color = saved_settings["background_color"]

	# Apply floor color
	if ground_plane:
		var floor_material = ground_plane.get_surface_override_material(0) as StandardMaterial3D
		if floor_material:
			floor_material.albedo_color = saved_settings["floor_color"]

	print("Loaded viewport settings: grid=%.2f, gizmo=%.2f" % [
		saved_settings["grid_size"],
		saved_settings["gizmo_scale"]
	])


func get_fastener_display_name(fastener_id: String) -> String:
	"""Get display name for fastener from ItemDatabase."""
	if not ItemDatabase:
		return fastener_id

	var item_def = ItemDatabase.get_item(fastener_id)
	if item_def:
		return item_def.name

	return fastener_id


# Private helper methods

func _should_show_part(part_name: String) -> bool:
	"""Check if a part should be shown based on the current category filter."""
	if current_category_filter == CategoryFilter.ALL:
		return true

	var part_category = part_categories.get(part_name, "")

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


func _get_axis_name(axis: Vector3) -> String:
	"""Get display name for an axis vector."""
	if axis == Vector3.RIGHT:
		return "X"
	elif axis == Vector3.UP:
		return "Y"
	elif axis == Vector3.BACK:
		return "Z"
	elif axis == Vector3(1, 1, 0):
		return "XY"
	elif axis == Vector3(1, 0, 1):
		return "XZ"
	elif axis == Vector3(0, 1, 1):
		return "YZ"
	elif axis == Vector3(1, 1, 1):
		return "All"
	else:
		# Multi-axis
		var axis_name = ""
		if axis.x != 0:
			axis_name += "X"
		if axis.y != 0:
			axis_name += "Y"
		if axis.z != 0:
			axis_name += "Z"
		return axis_name


func _on_fastener_popup_selected(index: int) -> void:
	"""Handle fastener selection from popup menu."""
	if index < 0 or index >= available_fasteners.size():
		return

	var selected_fastener_id = available_fasteners[index]
	print("Selected fastener: %s" % selected_fastener_id)
	fastener_selected.emit(selected_fastener_id)


func _setup_viewport_dialog_async(settings_dialog: ViewportSettingsDialog, parent_node: Node) -> void:
	"""Setup viewport dialog connections asynchronously."""
	# Wait for dialog to be ready
	if not settings_dialog.is_node_ready():
		await settings_dialog.ready

	# Initialize dialog content
	settings_dialog._setup_window_content()

	# Wait one more frame
	await parent_node.get_tree().process_frame

	# Connect signals
	settings_dialog.settings_changed.connect(
		func(grid_size: float, gizmo_scale: float, bg_color: Color, floor_color: Color):
			viewport_settings_changed.emit(grid_size, gizmo_scale, bg_color, floor_color)
	)

	settings_dialog.dialog_closed.connect(func(): is_dialog_open = false)
	settings_dialog.dialog_cancelled.connect(func(): is_dialog_open = false)

	# Show the dialog
	settings_dialog.show_dialog(parent_node.get_window())
