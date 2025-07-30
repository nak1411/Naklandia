# InventoryWindow.gd - Complete Control-based version with full inventory functionality
class_name InventoryWindow
extends Control

# Window properties
@export var inventory_title: String = "Inventory"
@export var default_size: Vector2 = Vector2(800, 600)
@export var min_window_size: Vector2 = Vector2(400, 300)
@export var max_window_size: Vector2 = Vector2(1400, 1000)
@export var can_resize: bool = true
@export var resize_border_width: float = 8.0
@export var resize_corner_size: float = 8.0

# UI Components
var main_container: Control
var title_bar: Panel
var title_label: Label
var close_button: Button
var content_area: Control
var background_panel: Panel
var lock_indicator: Label
var resize_border_visual: Control
var border_lines: Array[ColorRect] = []
var corner_indicators: Array[ColorRect] = []

# Inventory components
var inventory_manager: InventoryManager
var inventory_container: VBoxContainer
var header: InventoryWindowHeader
var content: InventoryWindowContent
var item_actions: InventoryItemActions

# Window state
var is_dragging: bool = false
var drag_start_position: Vector2
var open_containers: Array[InventoryContainer_Base] = []
var current_container: InventoryContainer_Base
var is_locked: bool = false
var last_window_size: Vector2i
var is_resizing: bool = false
var resize_mode: ResizeMode = ResizeMode.NONE
var resize_start_position: Vector2
var resize_start_size: Vector2
var resize_start_mouse: Vector2

# Resize overlay
var resize_overlay: Control
var resize_areas: Array[Control] = []

enum ResizeMode {
	NONE,
	LEFT,
	RIGHT,
	TOP,
	BOTTOM,
	TOP_LEFT,
	TOP_RIGHT,
	BOTTOM_LEFT,
	BOTTOM_RIGHT
}

# Options dropdown
var options_button: Button
var options_dropdown: DropDownMenu_Base

# Window styling
var title_bar_height: float = 32.0
var border_width: float = 2.0
var title_bar_color: Color = Color(0.1, 0.1, 0.1, 1.0)
var border_color: Color = Color(0.4, 0.4, 0.4, 1.0)
var background_color: Color = Color(0.15, 0.15, 0.15, 1.0)

# Signals
signal container_switched(container: InventoryContainer_Base)
signal window_resized(new_size: Vector2i)

func _init():
	# Set up as a window-like control
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = default_size
	position = Vector2(200, 100)
	visible = false
	
	# Enable input handling
	mouse_filter = Control.MOUSE_FILTER_PASS
	last_window_size = Vector2i(size)

func _ready():
	_setup_window_ui()
	_setup_content()
	
	# Make sure window starts hidden
	visible = false

func _process(_delta):
	# Check if size changed and update buttons accordingly
	if Vector2i(size) != last_window_size:
		last_window_size = Vector2i(size)
		_on_size_changed()
	
	# Handle resizing
	if is_resizing and can_resize:
		_handle_resize()
	
	if can_resize and not is_locked:
		_update_resize_cursor()
		
func _update_resize_cursor():
	var mouse_pos = get_global_mouse_position()
	var resize_area = _get_resize_area(mouse_pos)
	
	match resize_area:
		ResizeMode.LEFT, ResizeMode.RIGHT:
			mouse_default_cursor_shape = Control.CURSOR_HSIZE
		ResizeMode.TOP, ResizeMode.BOTTOM:
			mouse_default_cursor_shape = Control.CURSOR_VSIZE
		ResizeMode.TOP_LEFT, ResizeMode.BOTTOM_RIGHT:
			mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
		ResizeMode.TOP_RIGHT, ResizeMode.BOTTOM_LEFT:
			mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
		ResizeMode.NONE:
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			
	_update_border_visuals(resize_area)
			
		
func _update_border_visuals(resize_area: ResizeMode):
	# Hide all borders first
	for line in border_lines:
		_animate_border_visibility(line, false)
	for corner in corner_indicators:
		_animate_border_visibility(corner, false)
	
	# Show only the relevant border/corner
	match resize_area:
		ResizeMode.LEFT:
			if border_lines.size() > 0:
				_animate_border_visibility(border_lines[0], true)  # Left border
		ResizeMode.RIGHT:
			if border_lines.size() > 1:
				_animate_border_visibility(border_lines[1], true)  # Right border
		ResizeMode.TOP:
			if border_lines.size() > 2:
				_animate_border_visibility(border_lines[2], true)  # Top border
		ResizeMode.BOTTOM:
			if border_lines.size() > 3:
				_animate_border_visibility(border_lines[3], true)  # Bottom border
		ResizeMode.TOP_LEFT:
			if corner_indicators.size() > 0:
				_animate_border_visibility(corner_indicators[0], true)  # Top-left corner
		ResizeMode.TOP_RIGHT:
			if corner_indicators.size() > 1:
				_animate_border_visibility(corner_indicators[1], true)  # Top-right corner
		ResizeMode.BOTTOM_LEFT:
			if corner_indicators.size() > 2:
				_animate_border_visibility(corner_indicators[2], true)  # Bottom-left corner
		ResizeMode.BOTTOM_RIGHT:
			if corner_indicators.size() > 3:
				_animate_border_visibility(corner_indicators[3], true)  # Bottom-right corner
		
func _gui_input(event: InputEvent):
	if not can_resize or is_locked:
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_handle_resize_start(mouse_event.global_position)
			else:
				_handle_resize_end()

func _setup_window_ui():
	# Main container
	main_container = Control.new()
	main_container.name = "MainContainer"
	main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(main_container)
	
	# Background panel
	background_panel = Panel.new()
	background_panel.name = "BackgroundPanel"
	background_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_container.add_child(background_panel)
	
	# Style background
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = background_color
	bg_style.border_width_left = border_width
	bg_style.border_width_right = border_width
	bg_style.border_width_top = border_width
	bg_style.border_width_bottom = border_width
	bg_style.border_color = border_color
	background_panel.add_theme_stylebox_override("panel", bg_style)
	
	# Title bar
	title_bar = Panel.new()
	title_bar.name = "TitleBar"
	title_bar.anchor_left = 0.0
	title_bar.anchor_top = 0.0
	title_bar.anchor_right = 1.0
	title_bar.anchor_bottom = 0.0
	title_bar.offset_bottom = title_bar_height
	title_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	main_container.add_child(title_bar)
	
	# Style title bar
	var title_style = StyleBoxFlat.new()
	title_style.bg_color = title_bar_color
	title_bar.add_theme_stylebox_override("panel", title_style)
	
	# Title label
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = inventory_title
	title_label.anchor_left = 0.0
	title_label.anchor_top = 0.0
	title_label.anchor_right = 1.0
	title_label.anchor_bottom = 1.0
	title_label.offset_left = 10
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_bar.add_child(title_label)
	
	# Options button in title bar
	options_button = Button.new()
	options_button.name = "OptionsButton"
	options_button.text = "⋯"
	options_button.size = Vector2(title_bar_height - 4, title_bar_height - 4)
	options_button.position = Vector2(size.x - title_bar_height - 30, 2)
	title_bar.add_child(options_button)
	
	# Close button
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "×"
	close_button.size = Vector2(title_bar_height - 4, title_bar_height - 4)
	close_button.position = Vector2(size.x - title_bar_height, 2)
	title_bar.add_child(close_button)
	
	# Content area
	content_area = Control.new()
	content_area.name = "ContentArea"
	content_area.anchor_left = 0.0
	content_area.anchor_top = 0.0
	content_area.anchor_right = 1.0
	content_area.anchor_bottom = 1.0
	content_area.offset_top = title_bar_height
	content_area.offset_left = border_width
	content_area.offset_right = -border_width
	content_area.offset_bottom = -border_width
	main_container.add_child(content_area)
	
	# IMPORTANT: Setup lock indicator AFTER content_area is created
	_setup_lock_indicator()
	
	# Connect signals
	title_bar.gui_input.connect(_on_title_bar_input)
	close_button.pressed.connect(_on_close_pressed)
	options_button.pressed.connect(_on_options_pressed)
	
	# Create options dropdown
	_setup_options_dropdown()
	
	if can_resize:
		_create_resize_overlay()
	
func _setup_lock_indicator():
	# Create lock indicator icon using a label with lock emoji
	lock_indicator = Label.new()
	lock_indicator.name = "LockIndicator"
	lock_indicator.text = "🔒"
	lock_indicator.add_theme_font_size_override("font_size", 16)
	lock_indicator.add_theme_color_override("font_color", Color.YELLOW)
	lock_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock_indicator.size = Vector2(24, 24)
	lock_indicator.visible = false
	title_bar.add_child(lock_indicator)

func _update_lock_visual():
	if not lock_indicator:
		return
	
	if is_locked:
		# Show lock indicator next to options button
		lock_indicator.visible = true
		# Position it to the left of the options button
		var options_x = options_button.position.x
		lock_indicator.position = Vector2(options_x - 28, (title_bar_height - 24) / 2)
	else:
		# Hide indicator
		lock_indicator.visible = false
	
	# Remove title bar color changes - keep it normal
	if title_bar:
		title_bar.modulate = Color.WHITE

func _setup_content():	
	# Create main inventory container
	inventory_container = VBoxContainer.new()
	inventory_container.name = "InventoryContainer"
	inventory_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_area.add_child(inventory_container)
	
	# Create the header (search, filter, sort)
	header = InventoryWindowHeader.new()
	header.name = "InventoryHeader"
	inventory_container.add_child(header)
	
	# Connect header signals
	if header:
		header.search_changed.connect(_on_search_changed)
		header.filter_changed.connect(_on_filter_changed)
		header.sort_requested.connect(_on_sort_requested)
	
	# Create main content using InventoryWindowContent
	content = InventoryWindowContent.new()
	content.name = "InventoryContent"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_container.add_child(content)
	
	await get_tree().process_frame
	
	# Connect content signals with correct function names
	if content:
		content.container_selected.connect(_on_container_selected_from_content)
		content.item_activated.connect(_on_item_activated_from_content)
		content.item_context_menu.connect(_on_item_context_menu_from_content)
	
	# Debug content state
	if content.has_method("debug_content_state"):
		content.debug_content_state()
	
	# Initialize content with inventory manager if available
	if inventory_manager:
		_initialize_inventory_content()
	
	_setup_item_actions()
		
func _setup_item_actions():
	"""Initialize the item actions handler for context menus"""
	# Get the scene's main window
	var scene_window = get_viewport()
	if scene_window is Window:
		item_actions = InventoryItemActions.new(scene_window)
	else:
		# Fallback - try to find a parent window
		var parent_window = _find_parent_window()
		if parent_window:
			item_actions = InventoryItemActions.new(parent_window)
		else:
			push_error("Could not find parent window for InventoryItemActions")
			return
	
	# Connect to inventory manager updates
	if item_actions.has_signal("container_refreshed"):
		item_actions.container_refreshed.connect(_on_container_refreshed)
		
func _find_parent_window() -> Window:
	"""Find the parent window in the scene tree"""
	var current = get_parent()
	while current:
		if current is Window:
			return current
		current = current.get_parent()
	return null

func _setup_options_dropdown():
	# Create options dropdown menu
	options_dropdown = DropDownMenu_Base.new()
	options_dropdown.name = "OptionsDropdown"
	
	# Use the dynamic update function to set initial items
	_update_options_dropdown_text()
	
	# Connect dropdown signals
	options_dropdown.item_selected.connect(_on_options_dropdown_selected)
	
	# Connect dropdown close signal if available to clean up
	if options_dropdown.has_signal("menu_closed"):
		options_dropdown.menu_closed.connect(_on_options_dropdown_closed)

func _initialize_inventory_content():
	"""Initialize the inventory content with the inventory manager"""
	
	if content and content.has_method("set_inventory_manager"):
		content.set_inventory_manager(inventory_manager)
	
	# Get all accessible containers, not just player inventory
	var all_containers = inventory_manager.get_accessible_containers()
	
	if all_containers.size() > 0:
		open_containers.clear()
		open_containers.append_array(all_containers)
		
		# Set player inventory as default if available, otherwise use first container
		var default_container = null
		for container in all_containers:
			if container.container_id == "player_inventory":
				default_container = container
				break
		
		if not default_container:
			default_container = all_containers[0]
		
		# IMPORTANT: Set the current container first
		current_container = default_container
		
		# Then select it in the content
		if content and content.has_method("select_container"):
			content.select_container(default_container)
		
	
	# Update containers list in content with ALL containers
	if content and content.has_method("update_containers"):
		content.update_containers(all_containers)
		
		# Select the default container in the list
		var default_index = 0
		for i in range(all_containers.size()):
			if all_containers[i] == current_container:
				default_index = i
				break
		
		if content.has_method("select_container_index"):
			content.select_container_index(default_index)
	
	# Force a refresh of the display
	if content and content.has_method("refresh_display"):
		content.refresh_display()
		
func _on_container_refreshed():
	"""Handle container refresh from item actions"""
	if content and content.has_method("refresh_display"):
		content.refresh_display()

func _on_title_bar_input(event: InputEvent):
	if is_locked:
		return
		
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				is_dragging = true
				drag_start_position = get_global_mouse_position() - global_position
			else:
				is_dragging = false
	
	elif event is InputEventMouseMotion and is_dragging:
		global_position = get_global_mouse_position() - drag_start_position

func _on_close_pressed():
	if item_actions:
		item_actions.cleanup()
		item_actions = null
	visible = false

func _on_options_pressed():
	if not options_dropdown:
		return
	
	# Show dropdown at button position
	var button_pos = options_button.get_screen_position()
	var dropdown_pos = Vector2(button_pos.x, button_pos.y + options_button.size.y)
	
	# Only add to scene if it doesn't have a parent
	if not options_dropdown.get_parent():
		get_viewport().add_child(options_dropdown)
	
	# Show the menu
	if options_dropdown.has_method("show_menu"):
		options_dropdown.show_menu(dropdown_pos)

func _on_options_dropdown_selected(item_id: String, _item_data: Dictionary):
	match item_id:
		"transparency":
			_show_transparency_dialog()
		"lock_window":
			_toggle_window_lock()
		"reset_position":
			_reset_window_position()
		"reset_size":
			_reset_window_size()

func _on_options_dropdown_closed():
	# Remove dropdown from scene when it closes
	if options_dropdown and options_dropdown.get_parent():
		options_dropdown.get_parent().remove_child(options_dropdown)

func _on_size_changed():
	# Update button positions when window is resized
	if title_bar and options_button and close_button:
		_update_button_positions()
	
	window_resized.emit(Vector2i(size))

func _update_button_positions():
	if not title_bar:
		return
		
	var button_size = Vector2(title_bar_height - 4, title_bar_height - 4)
	var button_y = 2
	var button_spacing = button_size.x + 2
	var start_x = size.x - button_spacing
	
	# Account for lock indicator space when positioning buttons
	var lock_offset = 28 if (is_locked and lock_indicator and lock_indicator.visible) else 0
	
	if close_button:
		close_button.position = Vector2(start_x, button_y)
		start_x -= button_spacing
	
	if options_button:
		options_button.position = Vector2(start_x - lock_offset, button_y)
		
		# Update lock indicator position relative to options button
		if is_locked and lock_indicator:
			lock_indicator.position = Vector2(start_x - lock_offset - 28, (title_bar_height - 24) / 2)

# Header signal handlers
func _on_search_changed(text: String):
	# TODO: Implement search filtering
	pass

func _on_filter_changed(filter_type: int):
	# TODO: Implement filtering
	pass

func _on_sort_requested(sort_type):
	# TODO: Implement sorting
	pass
	


# Content signal handlers - FIXED FUNCTION NAMES
func _on_container_selected_from_content(container: InventoryContainer_Base):
	
	# Update our current container 
	current_container = container
	
	# IMPORTANT: Also call select_container on the content to update the grid and mass info
	if content and content.has_method("select_container"):
		# Don't emit the signal again since we're already handling it
		content.select_container(container)
	
	container_switched.emit(container)

func _on_item_activated_from_content(item: InventoryItem_Base, _slot: InventorySlot):
	print("Item activated: ", item.item_name)

func _on_item_context_menu_from_content(item: InventoryItem_Base, slot: InventorySlot, _position: Vector2):
	if item_actions:
		# Update item actions with current state
		item_actions.set_inventory_manager(inventory_manager)
		item_actions.set_current_container(current_container)
		
		# Show the context menu
		item_actions.show_item_context_menu(item, slot, position)

# Container management
func select_container(container: InventoryContainer_Base):
	if container == current_container:
		return
	
	current_container = container
	if content and content.has_method("select_container"):
		content.select_container(container)
		
		# Force the grid to update its size
		var grid = get_inventory_grid()
		if grid and container:
			grid.grid_width = container.grid_width
			grid.grid_height = container.grid_height
			if grid.has_method("_rebuild_grid"):
				await grid._rebuild_grid()
			grid.refresh_display()
	
	container_switched.emit(container)

func update_mass_info():
	"""Update the mass info bar - delegate to content"""
	if content and content.has_method("update_mass_info"):
		content.update_mass_info()

# Window management methods
func show_window():
	visible = true
	move_to_front()

func hide_window():
	visible = false

func center_on_screen():
	var viewport = get_viewport()
	if not viewport:
		return
	
	var screen_size = viewport.get_visible_rect().size
	position = Vector2(
		(screen_size.x - size.x) / 2,
		(screen_size.y - size.y) / 2
	)

# Options implementation
func _show_transparency_dialog():
	var dialog = AcceptDialog.new()
	dialog.title = "Window Transparency"
	dialog.size = Vector2i(300, 150)
	
	var vbox = VBoxContainer.new()
	var label = Label.new()
	label.text = "Adjust window transparency:"
	vbox.add_child(label)
	
	var slider = HSlider.new()
	slider.min_value = 0.3
	slider.max_value = 1.0
	slider.step = 0.1
	slider.value = modulate.a
	slider.custom_minimum_size.x = 250
	vbox.add_child(slider)
	
	dialog.add_child(vbox)
	slider.value_changed.connect(func(value): modulate.a = value)
	
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())

func _toggle_window_lock():
	is_locked = !is_locked
	_update_lock_visual()  # Add this line
	
	# Recreate the options dropdown to reflect the new lock state
	_update_options_dropdown_text()
	
func _update_options_dropdown_text():
	if not options_dropdown:
		return
	
	# Clear existing items and recreate with updated text
	options_dropdown.clear_items()
	
	# Add items with current state
	options_dropdown.add_menu_item("transparency", "Window Transparency")
	
	# Dynamic lock text based on current state
	var lock_text = "Unlock Window Position" if is_locked else "Lock Window Position"
	options_dropdown.add_menu_item("lock_window", lock_text)
	
	options_dropdown.add_menu_item("reset_position", "Reset Window Position")
	options_dropdown.add_menu_item("reset_size", "Reset Window Size")

func _reset_window_position():
	center_on_screen()

func _reset_window_size():
	size = default_size

func _get_all_container_items() -> Array[InventoryItem_Base]:
	if not current_container:
		return []
	
	var items: Array[InventoryItem_Base] = []
	if current_container.has_method("get_all_items"):
		items = current_container.get_all_items()
	elif "items" in current_container:
		items = current_container.items
	
	return items

func _resize_inventory_grid(new_size: Vector2i):
	if content and content.has_method("resize_grid"):
		content.resize_grid(new_size)

func get_inventory_grid() -> InventoryGrid:
	if content and content.has_method("get_inventory_grid"):
		return content.get_inventory_grid()
	elif content:
		# Try to find the grid manually if the method doesn't exist
		var grid = _find_node_recursive(content, "InventoryGrid")
		if grid and grid is InventoryGrid:
			return grid as InventoryGrid
	return null

func _find_node_recursive(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	
	for child in node.get_children():
		var result = _find_node_recursive(child, target_name)
		if result:
			return result
	
	return null
	
func _handle_resize_start(mouse_pos: Vector2):
	var resize_area = _get_resize_area(mouse_pos)
	if resize_area != ResizeMode.NONE:
		is_resizing = true
		resize_mode = resize_area
		resize_start_position = position
		resize_start_size = size
		resize_start_mouse = mouse_pos
		get_viewport().set_input_as_handled()

func _handle_resize_end():
	if is_resizing:
		is_resizing = false
		resize_mode = ResizeMode.NONE
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _handle_resize():
	if not is_resizing:
		return
		
	var current_mouse = get_viewport().get_mouse_position()
	var mouse_delta = current_mouse - resize_start_mouse
	
	var new_position = resize_start_position
	var new_size = resize_start_size
	
	match resize_mode:
		ResizeMode.LEFT:
			new_position.x = resize_start_position.x + mouse_delta.x
			new_size.x = resize_start_size.x - mouse_delta.x
		ResizeMode.RIGHT:
			new_size.x = resize_start_size.x + mouse_delta.x
		ResizeMode.TOP:
			new_position.y = resize_start_position.y + mouse_delta.y
			new_size.y = resize_start_size.y - mouse_delta.y
		ResizeMode.BOTTOM:
			new_size.y = resize_start_size.y + mouse_delta.y
		ResizeMode.TOP_LEFT:
			new_position.x = resize_start_position.x + mouse_delta.x
			new_position.y = resize_start_position.y + mouse_delta.y
			new_size.x = resize_start_size.x - mouse_delta.x
			new_size.y = resize_start_size.y - mouse_delta.y
		ResizeMode.TOP_RIGHT:
			new_position.y = resize_start_position.y + mouse_delta.y
			new_size.x = resize_start_size.x + mouse_delta.x
			new_size.y = resize_start_size.y - mouse_delta.y
		ResizeMode.BOTTOM_LEFT:
			new_position.x = resize_start_position.x + mouse_delta.x
			new_size.x = resize_start_size.x - mouse_delta.x
			new_size.y = resize_start_size.y + mouse_delta.y
		ResizeMode.BOTTOM_RIGHT:
			new_size.x = resize_start_size.x + mouse_delta.x
			new_size.y = resize_start_size.y + mouse_delta.y
	
	# Apply minimum and maximum size constraints
	new_size.x = clampf(new_size.x, min_window_size.x, max_window_size.x)
	new_size.y = clampf(new_size.y, min_window_size.y, max_window_size.y)
	
	# Adjust position if we hit size limits while resizing from top/left
	if resize_mode in [ResizeMode.LEFT, ResizeMode.TOP_LEFT, ResizeMode.BOTTOM_LEFT]:
		if new_size.x == min_window_size.x or new_size.x == max_window_size.x:
			new_position.x = resize_start_position.x + resize_start_size.x - new_size.x
	
	if resize_mode in [ResizeMode.TOP, ResizeMode.TOP_LEFT, ResizeMode.TOP_RIGHT]:
		if new_size.y == min_window_size.y or new_size.y == max_window_size.y:
			new_position.y = resize_start_position.y + resize_start_size.y - new_size.y
	
	# Apply new position and size
	position = new_position
	size = new_size
	# Emit resize signal
	window_resized.emit(Vector2i(size))

func _get_resize_area(mouse_pos: Vector2) -> ResizeMode:
	var local_pos = mouse_pos - global_position
	
	# Check if mouse is within resize borders
	var in_left = local_pos.x <= resize_border_width
	var in_right = local_pos.x >= size.x - resize_border_width
	var in_top = local_pos.y <= resize_border_width
	var in_bottom = local_pos.y >= size.y - resize_border_width
	
	# Check corners first (they take priority) - with proper bounds checking
	if in_top and in_left and local_pos.x <= resize_corner_size and local_pos.y <= resize_corner_size:
		return ResizeMode.TOP_LEFT
	elif in_top and in_right and local_pos.x >= size.x - resize_corner_size and local_pos.y <= resize_corner_size:
		return ResizeMode.TOP_RIGHT
	elif in_bottom and in_left and local_pos.x <= resize_corner_size and local_pos.y >= size.y - resize_corner_size:
		return ResizeMode.BOTTOM_LEFT
	elif in_bottom and in_right and local_pos.x >= size.x - resize_corner_size and local_pos.y >= size.y - resize_corner_size:
		return ResizeMode.BOTTOM_RIGHT
	
	# Check edges - but exclude corner areas
	elif in_left and not (local_pos.y <= resize_corner_size or local_pos.y >= size.y - resize_corner_size):
		return ResizeMode.LEFT
	elif in_right and not (local_pos.y <= resize_corner_size or local_pos.y >= size.y - resize_corner_size):
		return ResizeMode.RIGHT
	elif in_top and not (local_pos.x <= resize_corner_size or local_pos.x >= size.x - resize_corner_size):
		return ResizeMode.TOP
	elif in_bottom and not (local_pos.x <= resize_corner_size or local_pos.x >= size.x - resize_corner_size):
		return ResizeMode.BOTTOM
	
	return ResizeMode.NONE
				
func _create_resize_overlay():
	# Create invisible overlay for resize detection
	resize_overlay = Control.new()
	resize_overlay.name = "ResizeOverlay"
	resize_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resize_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resize_overlay.z_index = 200
	main_container.add_child(resize_overlay)
	
	_create_resize_areas()
	_create_resize_border_visuals()
	
func _create_resize_border_visuals():
	border_lines.clear()
	corner_indicators.clear()
	
	# Create visual container
	resize_border_visual = Control.new()
	resize_border_visual.name = "ResizeBorderVisual"
	resize_border_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resize_border_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resize_border_visual.z_index = 199  # Below the resize areas
	main_container.add_child(resize_border_visual)
	
	# Left border
	var left_line = ColorRect.new()
	left_line.name = "LeftBorder"
	left_line.color = Color(0.5, 0.8, 1.0, 0.0)  # Start invisible
	left_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_line.anchor_top = 0.0
	left_line.anchor_bottom = 1.0
	left_line.anchor_left = 0.0
	left_line.anchor_right = 0.0
	left_line.offset_right = 2
	resize_border_visual.add_child(left_line)
	border_lines.append(left_line)
	
	# Right border
	var right_line = ColorRect.new()
	right_line.name = "RightBorder"
	right_line.color = Color(0.5, 0.8, 1.0, 0.0)  # Start invisible
	right_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_line.anchor_top = 0.0
	right_line.anchor_bottom = 1.0
	right_line.anchor_left = 1.0
	right_line.anchor_right = 1.0
	right_line.offset_left = -2
	resize_border_visual.add_child(right_line)
	border_lines.append(right_line)
	
	# Top border
	var top_line = ColorRect.new()
	top_line.name = "TopBorder"
	top_line.color = Color(0.5, 0.8, 1.0, 0.0)  # Start invisible
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_line.anchor_left = 0.0
	top_line.anchor_right = 1.0
	top_line.anchor_top = 0.0
	top_line.anchor_bottom = 0.0
	top_line.offset_bottom = 2
	resize_border_visual.add_child(top_line)
	border_lines.append(top_line)
	
	# Bottom border
	var bottom_line = ColorRect.new()
	bottom_line.name = "BottomBorder"
	bottom_line.color = Color(0.5, 0.8, 1.0, 0.0)  # Start invisible
	bottom_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_line.anchor_left = 0.0
	bottom_line.anchor_right = 1.0
	bottom_line.anchor_top = 1.0
	bottom_line.anchor_bottom = 1.0
	bottom_line.offset_top = -2
	resize_border_visual.add_child(bottom_line)
	border_lines.append(bottom_line)
	
	# Corner indicators using resize_corner_size
	_create_corner_indicators()

func _create_corner_indicators():
	var corner_color = Color(0.5, 0.8, 1.0, 0.0)  # Start invisible
	
	# Top-left corner
	var tl_corner = ColorRect.new()
	tl_corner.name = "TopLeftCorner"
	tl_corner.color = corner_color
	tl_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl_corner.anchor_left = 0.0
	tl_corner.anchor_right = 0.0
	tl_corner.anchor_top = 0.0
	tl_corner.anchor_bottom = 0.0
	tl_corner.offset_right = resize_corner_size
	tl_corner.offset_bottom = resize_corner_size
	resize_border_visual.add_child(tl_corner)
	corner_indicators.append(tl_corner)
	
	# Top-right corner
	var tr_corner = ColorRect.new()
	tr_corner.name = "TopRightCorner"
	tr_corner.color = corner_color
	tr_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr_corner.anchor_left = 1.0
	tr_corner.anchor_right = 1.0
	tr_corner.anchor_top = 0.0
	tr_corner.anchor_bottom = 0.0
	tr_corner.offset_left = -resize_corner_size
	tr_corner.offset_bottom = resize_corner_size
	resize_border_visual.add_child(tr_corner)
	corner_indicators.append(tr_corner)
	
	# Bottom-left corner
	var bl_corner = ColorRect.new()
	bl_corner.name = "BottomLeftCorner"
	bl_corner.color = corner_color
	bl_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bl_corner.anchor_left = 0.0
	bl_corner.anchor_right = 0.0
	bl_corner.anchor_top = 1.0
	bl_corner.anchor_bottom = 1.0
	bl_corner.offset_right = resize_corner_size
	bl_corner.offset_top = -resize_corner_size
	resize_border_visual.add_child(bl_corner)
	corner_indicators.append(bl_corner)
	
	# Bottom-right corner
	var br_corner = ColorRect.new()
	br_corner.name = "BottomRightCorner"
	br_corner.color = corner_color
	br_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	br_corner.anchor_left = 1.0
	br_corner.anchor_right = 1.0
	br_corner.anchor_top = 1.0
	br_corner.anchor_bottom = 1.0
	br_corner.offset_left = -resize_corner_size
	br_corner.offset_top = -resize_corner_size
	resize_border_visual.add_child(br_corner)
	corner_indicators.append(br_corner)

func _create_resize_areas():
	resize_areas.clear()
	
	# Create EDGES first
	# Left edge
	var left_area = _create_resize_area("LeftResize", ResizeMode.LEFT)
	left_area.anchor_left = 0.0
	left_area.anchor_right = 0.0
	left_area.anchor_top = 0.0
	left_area.anchor_bottom = 1.0
	left_area.offset_right = resize_border_width
	
	# Right edge
	var right_area = _create_resize_area("RightResize", ResizeMode.RIGHT)
	right_area.anchor_left = 1.0
	right_area.anchor_right = 1.0
	right_area.anchor_top = 0.0
	right_area.anchor_bottom = 1.0
	right_area.offset_left = -resize_border_width
	
	# Top edge
	var top_area = _create_resize_area("TopResize", ResizeMode.TOP)
	top_area.anchor_left = 0.0
	top_area.anchor_right = 1.0
	top_area.anchor_top = 0.0
	top_area.anchor_bottom = 0.0
	top_area.offset_bottom = resize_border_width
	
	# Bottom edge
	var bottom_area = _create_resize_area("BottomResize", ResizeMode.BOTTOM)
	bottom_area.anchor_left = 0.0
	bottom_area.anchor_right = 1.0
	bottom_area.anchor_top = 1.0
	bottom_area.anchor_bottom = 1.0
	bottom_area.offset_top = -resize_border_width
	
	# Create CORNERS last (so they have higher priority in mouse detection)
	
	# Top-left corner
	var tl_corner = _create_resize_area("TopLeftCorner", ResizeMode.TOP_LEFT)
	tl_corner.anchor_left = 0.0
	tl_corner.anchor_right = 0.0
	tl_corner.anchor_top = 0.0
	tl_corner.anchor_bottom = 0.0
	tl_corner.offset_right = resize_corner_size
	tl_corner.offset_bottom = resize_corner_size
	
	# Top-right corner
	var tr_corner = _create_resize_area("TopRightCorner", ResizeMode.TOP_RIGHT)
	tr_corner.anchor_left = 1.0
	tr_corner.anchor_right = 1.0
	tr_corner.anchor_top = 0.0
	tr_corner.anchor_bottom = 0.0
	tr_corner.offset_left = -resize_corner_size
	tr_corner.offset_bottom = resize_corner_size
	
	# Bottom-left corner
	var bl_corner = _create_resize_area("BottomLeftCorner", ResizeMode.BOTTOM_LEFT)
	bl_corner.anchor_left = 0.0
	bl_corner.anchor_right = 0.0
	bl_corner.anchor_top = 1.0
	bl_corner.anchor_bottom = 1.0
	bl_corner.offset_right = resize_corner_size
	bl_corner.offset_top = -resize_corner_size
	
	# Bottom-right corner
	var br_corner = _create_resize_area("BottomRightCorner", ResizeMode.BOTTOM_RIGHT)
	br_corner.anchor_left = 1.0
	br_corner.anchor_right = 1.0
	br_corner.anchor_top = 1.0
	br_corner.anchor_bottom = 1.0
	br_corner.offset_left = -resize_corner_size
	br_corner.offset_top = -resize_corner_size

func _create_resize_area(area_name: String, mode: ResizeMode) -> Control:
	var area = Control.new()
	area.name = area_name
	area.mouse_filter = Control.MOUSE_FILTER_PASS
	area.set_meta("resize_mode", mode)
	
	# Connect signals directly without any binding
	area.gui_input.connect(_on_resize_area_input)
	
	resize_overlay.add_child(area)
	resize_areas.append(area)
	
	return area

func _on_resize_area_input(event: InputEvent):
	# Find which resize area triggered this event
	var source_area: Control = null
	for area in resize_areas:
		if area.has_focus() or _is_mouse_over_area(area):
			source_area = area
			break
	
	if not source_area:
		return
		
	var mode = source_area.get_meta("resize_mode") as ResizeMode
	
	if not can_resize or is_locked:
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_start_resize(mode, mouse_event.global_position)
			else:
				_end_resize()
			
# Helper function to check if mouse is over a specific area
func _is_mouse_over_area(area: Control) -> bool:
	var mouse_pos = get_local_mouse_position()
	var area_rect = Rect2(area.global_position - global_position, area.size)
	return area_rect.has_point(mouse_pos)
			
func _animate_border_visibility(element: ColorRect, show: bool):
	var current_color = element.color
	var target_alpha = 1.0 if show else 0.0
	var target_color = Color(current_color.r, current_color.g, current_color.b, target_alpha)
	
	var tween = create_tween()
	tween.tween_property(element, "color", target_color, 0.15)

func _start_resize(mode: ResizeMode, mouse_pos: Vector2):
	is_resizing = true
	resize_mode = mode
	resize_start_position = position
	resize_start_size = size
	resize_start_mouse = mouse_pos

func _end_resize():
	if is_resizing:
		is_resizing = false
		resize_mode = ResizeMode.NONE
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

# Public interface methods
func set_resizing_enabled(enabled: bool):
	can_resize = enabled
	if resize_overlay:
		resize_overlay.visible = enabled
	if not enabled and is_resizing:
		_end_resize()

func get_resizing_enabled() -> bool:
	return can_resize

# Public interface methods
func set_inventory_integration(integration):
	pass

func set_inventory_manager(manager: InventoryManager):
	inventory_manager = manager
	if content_area and inventory_container:
		_initialize_inventory_content()

func get_current_container() -> InventoryContainer_Base:
	return current_container

func set_window_title(title: String):
	inventory_title = title
	if title_label:
		title_label.text = title

func add_content(content_node: Control):
	if content_area:
		content_area.add_child(content_node)

func get_window_locked() -> bool:
	return is_locked

func set_window_locked(locked: bool):
	is_locked = locked

func get_transparency() -> float:
	return modulate.a

func set_transparency(value: float):
	modulate.a = value
