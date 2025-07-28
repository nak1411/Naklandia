# InventoryWindow.gd - Simplified with integrated title bar controls
class_name InventoryWindow
extends Window_Base

# Window properties
@export var inventory_title: String = "Inventory"
@export var min_window_size: Vector2 = Vector2(400, 300)
@export var default_size: Vector2 = Vector2(800, 600)
@export var max_window_size: Vector2 = Vector2(1400, 1000)

# UI Modules (restored header)
var inventory_container: VBoxContainer
var header: InventoryWindowHeader  # Restored the header
var content: InventoryWindowContent
var item_actions: InventoryItemActions

# Options dropdown
var options_dropdown: DropDownMenu_Base

# Resizing properties
var auto_resize_grid: bool = true
var min_grid_size: Vector2i = Vector2i(8, 6)

# State
var inventory_manager: InventoryManager
var open_containers: Array[InventoryContainer_Base] = []
var current_container: InventoryContainer_Base
var active_context_menu: InventoryItemActions

# Window state
var is_locked: bool = false
var last_window_size: Vector2i

# Signals
signal container_switched(container: InventoryContainer_Base)
signal window_resized(new_size: Vector2i)

func _init():
	super._init()
	set_window_title(inventory_title)
	size = Vector2i(default_size)
	min_size = Vector2i(min_window_size)
	max_size = Vector2i(max_window_size)
	
	# Enable resizing
	unresizable = false
	
	visible = false
	position = Vector2i(1040, 410)
	last_window_size = size

func _ready():
	print("InventoryWindow _ready() called")
	super._ready()
	await get_tree().process_frame
	
	# Add controls to the existing title bar
	_add_title_bar_controls()
	
	# Initialize UI
	_setup_inventory_ui()
	
	# Then find and connect inventory manager
	_find_inventory_manager()
	
	# Connect signals
	_connect_inventory_signals()
	_connect_resize_signals()
	
	# Apply theme
	apply_custom_theme()
	
	# Make sure window starts hidden
	visible = false
	
	# Wait a frame then initialize content
	await get_tree().process_frame
	_initialize_content()
	
	# Debug the state
	debug_inventory_state()

func _add_title_bar_controls():
	"""Add minimal controls to the existing Window_Base title bar"""
	print("Adding controls to title bar...")
	
	if not title_bar:
		print("ERROR: No title bar available!")
		return
	
	# Use or create the options button (check if Window_Base already has one)
	if not options_button:
		options_button = Button.new()
		options_button.name = "OptionsButton"
		title_bar.add_child(options_button)
	
	# Configure the options button
	options_button.text = "⚙"  # Gear icon
	options_button.size = Vector2(title_bar_height - 6, title_bar_height - 6)
	options_button.position = Vector2(size.x - 150, 3)  # Leave room for window buttons
	options_button.flat = true  # Make it flat to remove default styling
	
	# Create completely transparent style to remove all borders/boxes
	var transparent_style = StyleBoxEmpty.new()
	
	# Apply transparent style to all states
	options_button.add_theme_stylebox_override("normal", transparent_style)
	options_button.add_theme_stylebox_override("hover", transparent_style)
	options_button.add_theme_stylebox_override("pressed", transparent_style)
	options_button.add_theme_stylebox_override("focus", transparent_style)
	options_button.add_theme_stylebox_override("disabled", transparent_style)
	
	# Set font color
	options_button.add_theme_color_override("font_color", Color.WHITE)
	options_button.add_theme_color_override("font_hover_color", Color.LIGHT_GRAY)
	options_button.add_theme_color_override("font_pressed_color", Color.GRAY)
	
	# Connect signal (disconnect any existing connections first)
	if options_button.pressed.is_connected(_on_options_pressed):
		options_button.pressed.disconnect(_on_options_pressed)
	options_button.pressed.connect(_on_options_pressed)
	
	# Create the options dropdown menu
	_create_options_dropdown()
	
	print("Title bar options button configured")

func _create_options_dropdown():
	"""Create the options dropdown menu"""
	print("Creating options dropdown...")
	
	options_dropdown = DropDownMenu_Base.new()
	options_dropdown.name = "OptionsDropdown"
	
	# Add options menu items
	options_dropdown.add_menu_item("transparency", "Window Transparency")
	options_dropdown.add_menu_item("lock_window", "Lock Window Position")
	options_dropdown.add_menu_item("auto_resize", "Auto-Resize Grid")
	options_dropdown.add_menu_item("resize_to_fit", "Resize Grid to Fit Content")
	options_dropdown.add_menu_item("manual_resize", "Manual Grid Resize...")
	options_dropdown.add_menu_item("reset_position", "Reset Window Position")
	options_dropdown.add_menu_item("reset_size", "Reset Window Size")
	
	# Connect selection signal
	if options_dropdown.has_signal("item_selected"):
		options_dropdown.item_selected.connect(_on_options_dropdown_selected)
	
	# Connect menu close signal
	if options_dropdown.has_signal("tree_exiting"):
		options_dropdown.tree_exiting.connect(_on_options_dropdown_closed)
	
	print("Options dropdown created with menu items")

func _setup_inventory_ui():
	"""Set up the main inventory content WITH separate header"""
	print("Setting up inventory UI...")
	
	# Create main inventory container
	inventory_container = VBoxContainer.new()
	inventory_container.name = "InventoryContainer"
	inventory_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_content(inventory_container)
	
	# Create the header (under title bar) with search, filter, sort
	header = InventoryWindowHeader.new()
	header.name = "InventoryHeader"
	inventory_container.add_child(header)
	
	# Connect header signals
	if header:
		header.search_changed.connect(_on_search_changed)
		header.filter_changed.connect(_on_filter_changed)
		header.sort_requested.connect(_on_sort_requested)
		print("Header signals connected")
	
	# Create main content using your existing InventoryWindowContent
	content = InventoryWindowContent.new()
	content.name = "InventoryContent"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_container.add_child(content)
	print("InventoryContent added to container")
	
	# Connect content signals
	if content:
		content.container_selected.connect(_on_content_container_selected)
		content.item_activated.connect(_on_content_item_activated)
		content.item_context_menu.connect(_on_content_item_context_menu)
		print("Content signals connected")
	
	print("Inventory UI setup completed")

# Title bar control handlers
func _on_options_pressed():
	print("Options button pressed")
	
	if not options_dropdown:
		print("ERROR: No options dropdown!")
		return
		
	# Show dropdown at button position
	var button_pos = options_button.get_screen_position()
	var dropdown_pos = Vector2(button_pos.x, button_pos.y + options_button.size.y)
	
	print("Showing options dropdown at position: ", dropdown_pos)
	
	# Add dropdown to scene so it can access viewport
	get_viewport().add_child(options_dropdown)
	
	# Show the menu
	if options_dropdown.has_method("show_menu"):
		options_dropdown.show_menu(dropdown_pos)
	else:
		print("ERROR: Options dropdown doesn't have show_menu method!")

func _on_options_dropdown_selected(item_id: String, item_data: Dictionary):
	print("Options dropdown selected: ", item_id)
	
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
	print("Options dropdown closed")
	if options_dropdown and options_dropdown.get_parent():
		options_dropdown.get_parent().remove_child(options_dropdown)

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
	slider.value = get_transparency()
	slider.custom_minimum_size.x = 250
	vbox.add_child(slider)
	
	dialog.add_child(vbox)
	slider.value_changed.connect(func(value): set_transparency(value))
	
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())

func _toggle_window_lock():
	var locked = get_window_locked()
	set_window_locked(not locked)

func _toggle_auto_resize():
	auto_resize_grid = not auto_resize_grid

func _show_manual_resize_dialog():
	var dialog = AcceptDialog.new()
	dialog.title = "Manual Grid Resize"
	dialog.size = Vector2i(300, 200)
	
	var vbox = VBoxContainer.new()
	var hbox = HBoxContainer.new()
	
	var width_spinbox = SpinBox.new()
	width_spinbox.min_value = min_grid_size.x
	width_spinbox.max_value = 50
	width_spinbox.value = get_inventory_grid().grid_width if get_inventory_grid() else min_grid_size.x
	
	var height_spinbox = SpinBox.new()
	height_spinbox.min_value = min_grid_size.y
	height_spinbox.max_value = 50
	height_spinbox.value = get_inventory_grid().grid_height if get_inventory_grid() else min_grid_size.y
	
	hbox.add_child(Label.new())
	hbox.get_child(0).text = "Width:"
	hbox.add_child(width_spinbox)
	hbox.add_child(Label.new())
	hbox.get_child(2).text = "Height:"
	hbox.add_child(height_spinbox)
	
	vbox.add_child(Label.new())
	vbox.get_child(0).text = "Set grid dimensions:"
	vbox.add_child(hbox)
	dialog.add_child(vbox)
	
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func():
		var new_size = Vector2i(int(width_spinbox.value), int(height_spinbox.value))
		resize_grid_manual(new_size)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

func _reset_window_position():
	position = Vector2i(1040, 410)

func _reset_window_size():
	size = Vector2i(default_size)

# Header control handlers (from InventoryWindowHeader)
func _on_search_changed(text: String):
	print("Search changed: ", text)

func _on_filter_changed(filter_type: int):
	print("Filter changed: ", filter_type)

func _on_sort_requested(sort_type):
	print("Sort requested: ", sort_type)
	if inventory_manager and current_container:
		inventory_manager.sort_container(current_container.container_id, sort_type)
		refresh_display()

# Override size change to update title bar control positions
func _on_size_changed():
	super._on_size_changed()
	_update_title_bar_control_positions()

func _update_title_bar_control_positions():
	if not title_bar or not options_button:
		return
	options_button.position.x = size.x - 150

# Manual grid resize methods
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

func resize_grid_manual(new_size: Vector2i):
	new_size.x = max(new_size.x, min_grid_size.x)
	new_size.y = max(new_size.y, min_grid_size.y)
	_resize_inventory_grid(new_size)

func _get_all_container_items() -> Array[InventoryItem_Base]:
	if not current_container:
		return []
	
	var items: Array[InventoryItem_Base] = []
	if current_container.has_method("get_all_items"):
		items = current_container.get_all_items()
	elif "items" in current_container:
		items = current_container.items
	
	return items

# Debug method
func debug_inventory_state():
	print("\n=== INVENTORY WINDOW DEBUG ===")
	print("Window visible: ", visible)
	print("inventory_manager: ", inventory_manager)
	print("content: ", content)
	print("header: ", header)
	print("=== END DEBUG ===\n")

# Initialize content properly
func _initialize_content():
	print("Initializing inventory window content...")
	if not inventory_manager:
		print("ERROR: No inventory manager found!")
		return
	
	if content:
		content.set_inventory_manager(inventory_manager)
	
	if header:
		header.set_inventory_manager(inventory_manager)
		header.set_inventory_window(self)
	
	refresh_container_list()
	
	var player_inventory = inventory_manager.get_player_inventory()
	if player_inventory:
		select_container(player_inventory)

func _connect_resize_signals():
	size_changed.connect(_on_window_resized)

func _on_window_resized():
	var new_size = size
	if new_size != last_window_size:
		last_window_size = new_size
		_handle_window_resize(new_size)
		window_resized.emit(new_size)

func _handle_window_resize(new_size: Vector2i):
	if not auto_resize_grid:
		return
	
	var available_space = _calculate_available_grid_space()
	var new_grid_size = _calculate_optimal_grid_size(available_space)
	
	var grid = get_inventory_grid()
	if not grid:
		return
		
	var current_grid_size = Vector2i(grid.grid_width, grid.grid_height)
	
	if new_grid_size != current_grid_size:
		_resize_inventory_grid(new_grid_size)

func _calculate_available_grid_space() -> Vector2:
	if not content:
		return Vector2.ZERO
	
	var title_bar_space = title_bar_height + 8
	var margin_space = 40
	var container_list_width = 200
	
	var available_width = size.x - container_list_width - margin_space
	var available_height = size.y - title_bar_space - margin_space
	
	return Vector2(max(0, available_width), max(0, available_height))

func _calculate_optimal_grid_size(available_space: Vector2) -> Vector2i:
	var grid = get_inventory_grid()
	if not grid:
		return min_grid_size
	
	var slot_size = grid.slot_size
	var slot_spacing = grid.slot_spacing
	
	var slots_width = int((available_space.x + slot_spacing) / (slot_size.x + slot_spacing))
	var slots_height = int((available_space.y + slot_spacing) / (slot_size.y + slot_spacing))
	
	slots_width = max(slots_width, min_grid_size.x)
	slots_height = max(slots_height, min_grid_size.y)
	
	return Vector2i(slots_width, slots_height)

func _resize_inventory_grid(new_grid_size: Vector2i):
	if not current_container:
		return
	
	if current_container.has_method("set_grid_dimensions"):
		current_container.set_grid_dimensions(new_grid_size.x, new_grid_size.y)
	else:
		current_container.grid_width = new_grid_size.x
		current_container.grid_height = new_grid_size.y
	
	var grid = get_inventory_grid()
	if grid:
		grid.grid_width = new_grid_size.x
		grid.grid_height = new_grid_size.y
		grid._rebuild_grid()
		grid.refresh_display()

# Window management
func set_auto_resize_grid(enabled: bool):
	auto_resize_grid = enabled

func get_auto_resize_grid() -> bool:
	return auto_resize_grid

func set_window_locked(locked: bool):
	is_locked = locked
	unresizable = locked

func get_window_locked() -> bool:
	return is_locked

func set_inventory_manager(manager: InventoryManager):
	inventory_manager = manager
	
	if content:
		content.set_inventory_manager(inventory_manager)
	
	if header:
		header.set_inventory_manager(inventory_manager)
		header.set_inventory_window(self)

func select_container(container: InventoryContainer_Base):
	if not container:
		return
	
	current_container = container
	
	if content:
		content.select_container(container)
	
	container_switched.emit(container)

func refresh_display():
	if not content:
		return
	
	content.refresh_display()

func refresh_container_list():
	if not inventory_manager:
		return
	
	var containers = inventory_manager.get_accessible_containers()
	containers.sort_custom(func(a, b): 
		if a.container_id == "player_inventory":
			return true
		elif b.container_id == "player_inventory":
			return false
		return a.container_name < b.container_name
	)
	
	open_containers = containers
	
	if content:
		content.update_containers(open_containers)

func get_current_container() -> InventoryContainer_Base:
	return current_container

func get_inventory_grid() -> InventoryGrid:
	if content:
		return content.get_inventory_grid()
	return null

# Signal handlers
func _on_close_requested():
	visible = false

func _on_content_container_selected(container: InventoryContainer_Base):
	select_container(container)

func _on_content_item_activated(item: InventoryItem_Base, slot: InventorySlot):
	print("Item activated: ", item.item_name)

func _on_content_item_context_menu(item: InventoryItem_Base, slot: InventorySlot, position: Vector2):
	print("Item context menu for: ", item.item_name)

# Find inventory manager implementation
func _find_inventory_manager():
	var parent = get_parent()
	while parent:
		if parent.has_method("get_inventory_manager"):
			inventory_manager = parent.get_inventory_manager()
			if inventory_manager:
				return
		parent = parent.get_parent()
	
	var scene_root = get_tree().current_scene
	inventory_manager = _find_inventory_manager_recursive(scene_root)

func _find_inventory_manager_recursive(node: Node) -> InventoryManager:
	if node is InventoryManager:
		return node
	
	for child in node.get_children():
		var result = _find_inventory_manager_recursive(child)
		if result:
			return result
	
	return null

func _connect_inventory_signals():
	if inventory_manager:
		print("Connecting inventory manager signals...")

func apply_custom_theme():
	pass
