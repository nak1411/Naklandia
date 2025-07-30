# InventoryWindow.gd - Complete Control-based version with full inventory functionality
class_name InventoryWindow
extends Control

# Window properties
@export var inventory_title: String = "Inventory"
@export var default_size: Vector2 = Vector2(800, 600)
@export var min_window_size: Vector2 = Vector2(400, 300)
@export var max_window_size: Vector2 = Vector2(1400, 1000)

# UI Components
var main_container: Control
var title_bar: Panel
var title_label: Label
var close_button: Button
var content_area: Control
var background_panel: Panel

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

# Options dropdown
var options_button: Button
var options_dropdown: DropDownMenu_Base

# Resizing properties
var auto_resize_grid: bool = true
var min_grid_size: Vector2i = Vector2i(8, 6)

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
	
	# Connect signals
	title_bar.gui_input.connect(_on_title_bar_input)
	close_button.pressed.connect(_on_close_pressed)
	options_button.pressed.connect(_on_options_pressed)
	
	# Create options dropdown
	_setup_options_dropdown()

func _setup_content():
	print("Setting up inventory content...")
	
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
		print("✓ Header signals connected")
	
	# Create main content using InventoryWindowContent
	content = InventoryWindowContent.new()
	content.name = "InventoryContent"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_container.add_child(content)
	
	print("Content setup - waiting for content to be ready...")
	await get_tree().process_frame
	
	# Connect content signals with correct function names
	if content:
		content.container_selected.connect(_on_container_selected_from_content)
		content.item_activated.connect(_on_item_activated_from_content)
		content.item_context_menu.connect(_on_item_context_menu_from_content)
		print("✓ Content signals connected")
	
	# Debug content state
	if content.has_method("debug_content_state"):
		content.debug_content_state()
	
	# Initialize content with inventory manager if available
	if inventory_manager:
		_initialize_inventory_content()
	
	_setup_item_actions()
	
	print("✓ Inventory content setup complete")
	
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
	
	print("✓ Item actions handler initialized")
	
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
	
	# Add dropdown menu items
	options_dropdown.add_menu_item("transparency", "Window Transparency")
	options_dropdown.add_menu_item("lock_window", "Lock Window Position")
	options_dropdown.add_menu_item("auto_resize", "Auto Resize Grid")
	options_dropdown.add_menu_item("resize_to_fit", "Resize Grid to Fit Content")
	options_dropdown.add_menu_item("manual_resize", "Manual Grid Resize")
	options_dropdown.add_menu_item("reset_position", "Reset Window Position")
	options_dropdown.add_menu_item("reset_size", "Reset Window Size")
	
	# Connect dropdown signals
	options_dropdown.item_selected.connect(_on_options_dropdown_selected)
	
	# Connect dropdown close signal if available to clean up
	if options_dropdown.has_signal("menu_closed"):
		options_dropdown.menu_closed.connect(_on_options_dropdown_closed)

func _initialize_inventory_content():
	"""Initialize the inventory content with the inventory manager"""
	print("Initializing inventory content with manager...")
	
	if content and content.has_method("set_inventory_manager"):
		content.set_inventory_manager(inventory_manager)
		print("✓ Content connected to inventory manager")
	
	# Get all accessible containers, not just player inventory
	var all_containers = inventory_manager.get_accessible_containers()
	print("Found ", all_containers.size(), " accessible containers:")
	for container in all_containers:
		print("  - ", container.container_name, " (", container.container_id, ")")
	
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
			print("✓ Selected default container in content: ", default_container.container_name)
		
		print("✓ Default container selected: ", default_container.container_name)
	
	# Update containers list in content with ALL containers
	if content and content.has_method("update_containers"):
		content.update_containers(all_containers)
		print("✓ Updated containers in content with all accessible containers")
		
		# Select the default container in the list
		var default_index = 0
		for i in range(all_containers.size()):
			if all_containers[i] == current_container:
				default_index = i
				break
		
		if content.has_method("select_container_index"):
			content.select_container_index(default_index)
			print("✓ Selected container index ", default_index, " in list")
	
	# Force a refresh of the display
	if content and content.has_method("refresh_display"):
		content.refresh_display()
		print("✓ Refreshed content display")
		
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
		"auto_resize":
			_toggle_auto_resize()
		"resize_to_fit":
			resize_grid_to_fit_content()
		"manual_resize":
			_show_manual_resize_dialog()
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
	
	if close_button:
		close_button.position = Vector2(start_x, button_y)
		start_x -= button_spacing
	
	if options_button:
		options_button.position = Vector2(start_x, button_y)

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
	print("InventoryWindow: Container selected from content: ", container.container_name if container else "None")
	
	# Update our current container 
	current_container = container
	
	# IMPORTANT: Also call select_container on the content to update the grid and mass info
	if content and content.has_method("select_container"):
		# Don't emit the signal again since we're already handling it
		content.select_container(container)
		print("✓ Updated content with selected container")
	
	container_switched.emit(container)

func _on_item_activated_from_content(item: InventoryItem_Base, _slot: InventorySlot):
	print("Item activated: ", item.item_name)

func _on_item_context_menu_from_content(item: InventoryItem_Base, slot: InventorySlot, _position: Vector2):
	print("Item context menu for: ", item.item_name)
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
	
	print("InventoryWindow: Selecting container: ", container.container_name if container else "None")
	if container:
		print("  - Container grid size: ", container.grid_width, "x", container.grid_height)
	
	current_container = container
	if content and content.has_method("select_container"):
		content.select_container(container)
		print("✓ Selected container in content")
		
		# Force the grid to update its size
		var grid = get_inventory_grid()
		if grid and container:
			print("  - Updating grid dimensions to: ", container.grid_width, "x", container.grid_height)
			grid.grid_width = container.grid_width
			grid.grid_height = container.grid_height
			if grid.has_method("_rebuild_grid"):
				await grid._rebuild_grid()
			grid.refresh_display()
			print("✓ Grid updated for new container")
	
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

func _toggle_auto_resize():
	auto_resize_grid = !auto_resize_grid

func resize_grid_to_fit_content():
	if not current_container:
		return
	
	var items = _get_all_container_items()
	if items.is_empty():
		return
	
	var max_x = 0
	var max_y = 0
	
	for item in items:
		var pos = Vector2i(-1, -1)
		if current_container.has_method("get_item_position"):
			pos = current_container.get_item_position(item)
		
		if pos != Vector2i(-1, -1):
			var item_size = Vector2i(1, 1)
			if item.has_method("get_grid_size"):
				item_size = item.get_grid_size()
			
			max_x = max(max_x, pos.x + item_size.x)
			max_y = max(max_y, pos.y + item_size.y)
	
	max_x += 2
	max_y += 2
	max_x = max(max_x, min_grid_size.x)
	max_y = max(max_y, min_grid_size.y)
	
	_resize_inventory_grid(Vector2i(max_x, max_y))

func _show_manual_resize_dialog():
	var dialog = AcceptDialog.new()
	dialog.title = "Manual Grid Resize"
	dialog.size = Vector2i(300, 200)
	
	var vbox = VBoxContainer.new()
	var hbox = HBoxContainer.new()
	
	var width_spinbox = SpinBox.new()
	width_spinbox.min_value = min_grid_size.x
	width_spinbox.max_value = 50
	width_spinbox.value = 10
	
	var height_spinbox = SpinBox.new()
	height_spinbox.min_value = min_grid_size.y
	height_spinbox.max_value = 50
	height_spinbox.value = 8
	
	hbox.add_child(Label.new())
	hbox.add_child(width_spinbox)
	hbox.add_child(Label.new())
	hbox.add_child(height_spinbox)
	vbox.add_child(hbox)
	
	dialog.add_child(vbox)
	
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func():
		_resize_inventory_grid(Vector2i(width_spinbox.value, height_spinbox.value))
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

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
