# InventoryWindowUI.gd - Main inventory window with EVE-like interface
class_name InventoryWindowUI
extends Window

# Window properties
@export var window_title: String = "Inventory"
@export var min_window_size: Vector2 = Vector2(400, 300)
@export var default_size: Vector2 = Vector2(800, 600)

# Context menu properties
@export var popup_offset: Vector2 = Vector2(20,20)

# UI Components
var main_container: VBoxContainer
var header_container: HBoxContainer
var content_container: HSplitContainer
var container_list: ItemList
var inventory_grid: InventoryGridUI
var mass_info_bar: Panel
var mass_info_label: Label

# Header components
var container_selector: OptionButton
var search_field: LineEdit
var filter_options: OptionButton
var sort_button: MenuButton

# State
var inventory_manager: InventoryManager
var current_container: InventoryContainer
var open_containers: Array[InventoryContainer] = []

# Signals
signal window_closed()
signal container_switched(container: InventoryContainer)

func _init():
	title = window_title
	size = default_size
	min_size = min_window_size
	
	# Enable window dragging and resizing with native title bar
	set_flag(Window.FLAG_RESIZE_DISABLED, false)
	set_flag(Window.FLAG_BORDERLESS, false)
	
	# Start hidden and centered
	visible = false
	
	# Set initial position to center (will be properly centered in _ready)
	position = Vector2i(
		(DisplayServer.screen_get_size().x - size.x / 2) / 2,
		(DisplayServer.screen_get_size().y - size.y / 2) / 2
	)

func _ready():
	_setup_ui()
	_connect_signals()
	_find_inventory_manager()
	
	# Apply custom styling
	apply_custom_theme()
	
	# Set the fine-tuned centered position
	position = Vector2i(1040, 410)
	
	# Start hidden
	visible = false
	
func _set_initial_position():
	var main_window = get_tree().root
	if main_window.mode == Window.MODE_FULLSCREEN:
		# Center on screen for fullscreen
		var screen_size = DisplayServer.screen_get_size(1)
		position = Vector2i(
			(screen_size.x - size.x) / 2,
			(screen_size.y - size.y) / 2
		)
	else:
		# Center within game window for windowed mode
		var main_pos = main_window.position
		var main_size = main_window.size
		position = Vector2i(
			main_pos.x + (main_size.x - size.x) / 2,
			main_pos.y + (main_size.y - size.y) / 2
		)

func _on_window_resized():
	# Update inventory grid layout when window is resized
	if inventory_grid and current_container:
		# Call a method to recalculate grid layout
		_update_grid_layout()

func _update_grid_layout():
	# This will be called when the window is resized
	# The InventoryGridUI should handle its own layout updates
	if inventory_grid:
		# Force the grid to refresh its layout
		inventory_grid.queue_redraw()

func _get_available_grid_space() -> Vector2:
	if not inventory_grid or not inventory_grid.get_parent():
		return Vector2.ZERO
	
	var scroll_container = inventory_grid.get_parent()
	if not scroll_container is ScrollContainer:
		return Vector2.ZERO
	
	# Get the available space in the scroll container
	var available_size = scroll_container.size
	
	# Account for scrollbar space
	available_size.x -= 20  # Approximate scrollbar width
	available_size.y -= 20  # Approximate scrollbar height
	
	return available_size

func _center_window_sync():
	center_on_main_screen()

func _find_main_screen() -> int:
	var screen_count = DisplayServer.get_screen_count()
	var main_screen = 0
	var largest_area = 0
	
	# Look for the screen at (0,0) first, or fall back to largest screen
	for i in screen_count:
		var screen_pos = DisplayServer.screen_get_position(i)
		var screen_size = DisplayServer.screen_get_size(i)
		var area = screen_size.x * screen_size.y
		
		
		# Prefer screen at origin (0,0)
		if screen_pos == Vector2i(0, 0):
			return i
		
		# Track largest screen as fallback
		if area > largest_area:
			largest_area = area
			main_screen = i
	
	return main_screen

func center_on_main_screen():
	# Fine-tuned position closer to perfect center
	var centered_position = Vector2i(1040, 410)  # Slightly higher than mathematical center
	
	position = centered_position
	
func _try_alternative_centering(screen_pos: Vector2i, screen_size: Vector2i):

	
	# Method 1: Use move_to_center() if available
	if has_method("move_to_center"):
		call("move_to_center")
	
	# Method 2: Manual calculation with different approach
	var alt_center = Vector2i(
		screen_pos.x + screen_size.x / 2 - size.x / 2,
		screen_pos.y + screen_size.y / 2 - size.y / 2
	)
	
	# Method 3: Try popup_centered equivalent
	var popup_center = Vector2i(
		screen_pos.x + (screen_size.x - size.x) / 2,
		screen_pos.y + (screen_size.y - size.y) / 2
	)
	
	
	# Use the alternative calculation
	position = alt_center
	
func test_manual_positions():
	
	var screen_size = DisplayServer.screen_get_size(_find_main_screen())
	
	# Test various positions
	var test_positions = [
		Vector2i(100, 100),  # Top-left
		Vector2i(screen_size.x / 4, screen_size.y / 4),  # Quarter screen
		Vector2i(screen_size.x / 2 - 400, screen_size.y / 2 - 300),  # Manual center
		Vector2i(screen_size.x / 3, screen_size.y / 3),  # Third screen
	]
	
	for i in range(test_positions.size()):
		var test_pos = test_positions[i]
		position = test_pos
		await get_tree().create_timer(0.5).timeout
	

func _center_window():
	# Simple async wrapper
	_center_window_sync()

func _is_window_on_screen() -> bool:
	var screen_rect = DisplayServer.screen_get_usable_rect()
	var window_rect = Rect2i(position, size)
	
	# Check if at least 100x100 pixels of the window are visible
	var intersection = window_rect.intersection(screen_rect)
	return intersection.size.x >= 100 and intersection.size.y >= 100

func _reset_window_if_offscreen():
	if not _is_window_on_screen():
		_center_window_sync()

func _setup_ui():
	# Main container
	main_container = VBoxContainer.new()
	main_container.name = "MainContainer"
	main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_container)
	
	# Header
	_setup_header()
	
	# Content area
	_setup_content()

func _setup_header():
	header_container = HBoxContainer.new()
	header_container.name = "Header"
	header_container.custom_minimum_size.y = 40
	main_container.add_child(header_container)
	
	# Add some spacing at the start
	var left_spacer = Control.new()
	left_spacer.custom_minimum_size.x = 8
	header_container.add_child(left_spacer)
	
	# Container selector
	container_selector = OptionButton.new()
	container_selector.custom_minimum_size.x = 150
	container_selector.selected = -1
	header_container.add_child(container_selector)
	
	# Search field
	search_field = LineEdit.new()
	search_field.placeholder_text = "Search items..."
	search_field.custom_minimum_size.x = 120
	header_container.add_child(search_field)
	
	# Filter options
	filter_options = OptionButton.new()
	filter_options.add_item("All Items")
	filter_options.add_item("Weapons")
	filter_options.add_item("Armor")
	filter_options.add_item("Consumables")
	filter_options.add_item("Resources")
	filter_options.add_item("Blueprints")
	filter_options.add_item("Modules")
	filter_options.add_item("Ships")
	filter_options.add_item("Containers")
	filter_options.add_item("Ammunition")
	filter_options.add_item("Implants")
	filter_options.add_item("Skill Books")
	filter_options.custom_minimum_size.x = 100
	header_container.add_child(filter_options)
	
	# Sort button
	sort_button = MenuButton.new()
	sort_button.text = "Sort"
	var sort_popup = sort_button.get_popup()
	sort_popup.add_item("By Name")
	sort_popup.add_item("By Type")
	sort_popup.add_item("By Value")
	sort_popup.add_item("By Volume")
	sort_popup.add_item("By Rarity")
	header_container.add_child(sort_button)
	
	# Right spacer to push everything left
	var right_spacer = Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_container.add_child(right_spacer)

func _setup_content():
	content_container = HSplitContainer.new()
	content_container.name = "Content"
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.split_offset = 200  # Set initial split position
	main_container.add_child(content_container)
	
	# Container list (left side)
	var left_panel = VBoxContainer.new()
	left_panel.custom_minimum_size.x = 180
	left_panel.size_flags_horizontal = Control.SIZE_FILL
	content_container.add_child(left_panel)
	
	var container_list_label = Label.new()
	container_list_label.text = "Containers"
	container_list_label.add_theme_font_size_override("font_size", 14)
	container_list_label.add_theme_color_override("font_color", Color.WHITE)
	container_list_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container_list_label.custom_minimum_size.y = 25
	left_panel.add_child(container_list_label)
	
	container_list = ItemList.new()
	container_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container_list.custom_minimum_size = Vector2(160, 200)
	container_list.auto_height = true
	left_panel.add_child(container_list)
	
	# Inventory area (right side) - includes mass bar and grid
	var inventory_area = VBoxContainer.new()
	inventory_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_area.add_theme_constant_override("separation", 4)
	content_container.add_child(inventory_area)
	
	# Mass info bar
	_setup_mass_info_bar(inventory_area)
	
	# Inventory grid in scroll container
	var grid_scroll = ScrollContainer.new()
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	grid_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	inventory_area.add_child(grid_scroll)
	
	inventory_grid = InventoryGridUI.new()
	inventory_grid.name = "InventoryGrid"
	inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.add_child(inventory_grid)

func _setup_mass_info_bar(parent: Control):
	# Create mass info bar
	mass_info_bar = Panel.new()
	mass_info_bar.name = "MassInfoBar"
	mass_info_bar.custom_minimum_size.y = 35
	mass_info_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(mass_info_bar)
	
	# Style the mass info bar
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	style_box.border_color = Color(0.4, 0.4, 0.4, 1.0)
	style_box.border_width_left = 1
	style_box.border_width_right = 1
	style_box.border_width_top = 1
	style_box.border_width_bottom = 1
	style_box.corner_radius_top_left = 4
	style_box.corner_radius_top_right = 4
	style_box.corner_radius_bottom_left = 4
	style_box.corner_radius_bottom_right = 4
	mass_info_bar.add_theme_stylebox_override("panel", style_box)
	
	# Create mass info label
	mass_info_label = Label.new()
	mass_info_label.name = "MassInfoLabel"
	mass_info_label.text = "No container selected"
	mass_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mass_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mass_info_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mass_info_label.add_theme_color_override("font_color", Color.WHITE)
	mass_info_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	mass_info_label.add_theme_constant_override("shadow_offset_x", 1)
	mass_info_label.add_theme_constant_override("shadow_offset_y", 1)
	mass_info_label.add_theme_font_size_override("font_size", 12)
	mass_info_bar.add_child(mass_info_label)

func _connect_signals():
	# Connect native window close signal
	close_requested.connect(_on_close_requested)
	
	# Container selection
	if container_selector:
		container_selector.item_selected.connect(_on_container_selector_changed)
	if container_list:
		container_list.item_selected.connect(_on_container_list_selected)
	
	# Search and filter
	if search_field:
		search_field.text_changed.connect(_on_search_text_changed)
	if filter_options:
		filter_options.item_selected.connect(_on_filter_changed)
	
	# Sort menu
	if sort_button:
		var sort_popup = sort_button.get_popup()
		sort_popup.id_pressed.connect(_on_sort_selected)
	
	# Inventory grid
	if inventory_grid:
		inventory_grid.item_activated.connect(_on_item_activated)
		inventory_grid.item_context_menu.connect(_on_item_context_menu)

func _find_inventory_manager():
	var scene_root = get_tree().current_scene
	inventory_manager = _find_inventory_manager_recursive(scene_root)
	
	if inventory_manager:
		_populate_container_list()

func _find_inventory_manager_recursive(node: Node) -> InventoryManager:
	if node is InventoryManager:
		return node
	
	for child in node.get_children():
		var result = _find_inventory_manager_recursive(child)
		if result:
			return result
	
	return null

# Container management
func _populate_container_list():
	if not inventory_manager:
		return
	
	container_selector.clear()
	container_list.clear()
	open_containers.clear()
	
	var containers = inventory_manager.get_accessible_containers()
	
	# Compact all containers before displaying them
	for container in containers:
		if container.get_item_count() > 0:
			container.compact_items()
	
	# Sort containers to put player inventory first
	containers.sort_custom(func(a, b): 
		if a.container_id == "player_inventory":
			return true
		elif b.container_id == "player_inventory":
			return false
		return a.container_name < b.container_name
	)
	
	for container in containers:
		# Show total quantity instead of unique item count
		var total_qty = container.get_total_quantity()
		var unique_items = container.get_item_count()
		
		# Format: "Container Name (50 items)" or "Container Name (50 items, 3 types)"
		var container_text = ""
		if unique_items > 1:
			container_text = "%s (%d items, %d types)" % [container.container_name, total_qty, unique_items]
		else:
			container_text = "%s (%d items)" % [container.container_name, total_qty]
		
		container_selector.add_item(container_text)
		container_list.add_item(container_text)
		var item_index = container_list.get_item_count() - 1
		container_list.set_item_tooltip(item_index, container_text)
		
		open_containers.append(container)
	
	# Select player inventory first
	if not open_containers.is_empty():
		_switch_to_container(open_containers[0])
		container_selector.selected = 0
		container_list.select(0)
		
func refresh_container_list():
	"""Refreshes the container list display after validating container integrity"""
	if not inventory_manager:
		return
	
	var selected_index = container_selector.selected
	var selected_container = current_container
	
	# Update container text for each container
	for i in range(open_containers.size()):
		var container = open_containers[i]
		
		var total_qty = container.get_total_quantity()
		var unique_items = container.get_item_count()
		
		# Format: "Container Name (50 items)" or "Container Name (50 items, 3 types)"
		var container_text = ""
		if unique_items > 1:
			container_text = "%s (%d items, %d types)" % [container.container_name, total_qty, unique_items]
		else:
			container_text = "%s (%d items)" % [container.container_name, total_qty]
		
		# Update both the selector and list
		container_selector.set_item_text(i, container_text)
		container_list.set_item_text(i, container_text)
		container_list.set_item_tooltip(i, container_text)
	
	# Maintain selection
	if selected_index >= 0 and selected_index < open_containers.size():
		container_selector.selected = selected_index
		container_list.select(selected_index)


func _switch_to_container(container: InventoryContainer):
	current_container = container
	
	if inventory_grid:
		# Compact the container first before displaying it
		if container and container.get_item_count() > 0:
			print("InventoryWindow: Compacting container '%s' on initial display" % container.container_name)
			container.compact_items()
		
		inventory_grid.set_container(container)
		
		# Wait a frame then force refresh
		await get_tree().process_frame
		refresh_display()
		
		# Update grid layout to fit the window
		_update_grid_layout()
	
	_update_mass_info()
	container_switched.emit(container)
	

func _update_mass_info():
	if not current_container or not mass_info_label:
		mass_info_label.text = "No container selected"
		return
	
	var info = current_container.get_container_info()
	
	# Create comprehensive info text with total quantity
	var text = "%s  |  " % current_container.container_name
	text += "Items: %d (%d types)  |  " % [info.total_quantity, info.item_count]
	text += "Volume: %.1f/%.1f m³ (%.1f%%)  |  " % [info.volume_used, info.volume_max, info.volume_percentage]
	text += "Mass: %.1f kg  |  " % info.total_mass
	text += "Value: %.0f ISK" % info.total_value
	
	mass_info_label.text = text
	
	# Color coding based on volume percentage
	if info.volume_percentage > 90:
		mass_info_label.add_theme_color_override("font_color", Color.RED)
	elif info.volume_percentage > 75:
		mass_info_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		mass_info_label.add_theme_color_override("font_color", Color.WHITE)

# Event handlers
func _on_close_requested():
	_close_window()

func _close_window():
	visible = false
	# Force mouse capture restoration
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	window_closed.emit()

func _on_container_selector_changed(index: int):
	if index >= 0 and index < open_containers.size():
		var new_container = open_containers[index]
		if new_container != current_container:
			_switch_to_container(new_container)
			container_list.select(index)

func _on_container_list_selected(index: int):
	if index >= 0 and index < open_containers.size():
		var new_container = open_containers[index]
		if new_container != current_container:
			_switch_to_container(new_container)
			container_selector.selected = index

func _on_search_text_changed(new_text: String):
	_apply_filters()

func _on_filter_changed(index: int):
	_apply_filters()

func _apply_filters():
	# TODO: Implement filtering logic
	# This would filter the displayed items based on search text and selected filter
	pass

func _on_sort_selected(id: int):
	if not inventory_manager or not current_container:
		return
	
	var sort_type = id as InventoryManager.SortType
	inventory_manager.sort_container(current_container.container_id, sort_type)

func _on_item_activated(item: InventoryItem, slot: InventorySlotUI):
	# Double-click action - could open item details, use item, etc.
	_show_item_details_dialog(item)

func _on_item_context_menu(item: InventoryItem, slot: InventorySlotUI, position: Vector2):
	_show_item_context_menu(item, slot, position)

func _show_item_context_menu(item: InventoryItem, slot: InventorySlotUI, position: Vector2):
	var popup = PopupMenu.new()
	
	# Store the context for this popup
	popup.set_meta("context_item", item)
	popup.set_meta("context_slot", slot)
	
	# Item-specific actions first
	popup.add_item("Item Information", 0)
	
	if item.quantity > 1:
		popup.add_item("Split Stack", 1)
	
	popup.add_item("Move to...", 2)
	
	# Item type specific actions
	match item.item_type:
		InventoryItem.ItemType.CONSUMABLE:
			popup.add_item("Use Item", 10)
		InventoryItem.ItemType.CONTAINER:
			popup.add_item("Open Container", 11)
		InventoryItem.ItemType.BLUEPRINT:
			popup.add_item("View Blueprint", 12)
	
	popup.add_separator()
	
	# Container actions
	popup.add_item("Stack All Items", 20)
	popup.add_item("Sort Container", 21)
	
	popup.add_separator()
	
	# Destructive actions
	if item.can_be_destroyed:
		popup.add_item("Destroy Item", 3)
	
	popup.add_item("Clear Container", 22)
	
	add_child(popup)
	
	# Get current mouse position relative to this window
	var mouse_pos = (get_mouse_position() + Vector2(self.position)) + popup_offset
	popup.position = Vector2i(mouse_pos)
	popup.show()
	
	# Connect signal with proper parameter handling
	popup.id_pressed.connect(_on_context_menu_item_selected.bind(popup))

func _show_empty_area_context_menu(position: Vector2):
	var popup = PopupMenu.new()
	
	# Store context - no item or slot for empty area
	popup.set_meta("context_item", null)
	popup.set_meta("context_slot", null)
	
	# Container actions only
	popup.add_item("Stack All Items", 20)
	popup.add_item("Sort Container", 21)
	popup.add_separator()
	popup.add_item("Clear Container", 22)
	
	add_child(popup)
	popup.position = Vector2i(position)
	popup.show()
	
	# Connect signal
	popup.id_pressed.connect(_on_context_menu_item_selected.bind(popup))

func _on_context_menu_item_selected(id: int, popup: PopupMenu):
	# Retrieve context from popup metadata
	var item = popup.get_meta("context_item", null) as InventoryItem
	var slot = popup.get_meta("context_slot", null) as InventorySlotUI
	
	match id:
		0:  # Item Information
			_show_item_details_dialog(item)
		1:  # Split Stack
			_show_split_stack_dialog(item, slot)
		2:  # Move to...
			_show_move_item_dialog(item, slot)
		3:  # Destroy Item
			_show_destroy_item_confirmation(item, slot)
		10: # Use Item
			_use_item(item, slot)
		11: # Open Container
			_open_container_item(item)
		12: # View Blueprint
			_view_blueprint(item)
		20: # Stack All Items
			_on_stack_all_pressed()
		21: # Sort Container
			_on_sort_container_pressed()
		22: # Clear Container
			_on_clear_container_pressed()
	
	# Refresh container list after any action that might change item counts
	refresh_container_list()
	
	popup.queue_free()

func _show_item_details_dialog(item: InventoryItem):
	# Create a detailed item information dialog
	var dialog = AcceptDialog.new()
	dialog.title = item.item_name
	dialog.size = Vector2(400, 300)
	
	var content = RichTextLabel.new()
	content.bbcode_enabled = true
	content.text = _generate_detailed_item_info(item)
	content.fit_content = true
	
	dialog.add_child(content)
	add_child(dialog)
	dialog.popup_centered()
	
	# Clean up dialog when closed
	dialog.close_requested.connect(func(): dialog.queue_free())

func _generate_detailed_item_info(item: InventoryItem) -> String:
	var text = "[center][b][font_size=16]%s[/font_size][/b][/center]\n" % item.item_name
	text += "[center][color=%s]%s[/color][/center]\n\n" % [item.get_rarity_color().to_html(), InventoryItem.ItemRarity.keys()[item.item_rarity]]
	
	text += "[b]General Information[/b]\n"
	text += "Type: %s\n" % InventoryItem.ItemType.keys()[item.item_type]
	text += "Quantity: %d\n" % item.quantity
	text += "Max Stack Size: %d\n" % item.max_stack_size
	text += "Grid Size: %dx%d\n\n" % [item.grid_width, item.grid_height]
	
	text += "[b]Physical Properties[/b]\n"
	text += "Volume: %.3f m³ (%.3f m³ total)\n" % [item.volume, item.get_total_volume()]
	text += "Mass: %.3f kg (%.3f kg total)\n\n" % [item.mass, item.get_total_mass()]
	
	text += "[b]Economic Information[/b]\n"
	text += "Base Value: %.2f ISK\n" % item.base_value
	text += "Total Value: %.2f ISK\n\n" % item.get_total_value()
	
	if item.is_container:
		text += "[b]Container Properties[/b]\n"
		text += "Container Volume: %.2f m³\n" % item.container_volume
		text += "Container Type: %s\n\n" % InventoryItem.ContainerType.keys()[item.container_type]
	
	text += "[b]Flags[/b]\n"
	text += "Unique: %s\n" % ("Yes" if item.is_unique else "No")
	text += "Contraband: %s\n" % ("Yes" if item.is_contraband else "No")
	text += "Can be destroyed: %s\n\n" % ("Yes" if item.can_be_destroyed else "No")
	
	if not item.description.is_empty():
		text += "[b]Description[/b]\n%s" % item.description
	
	return text

func _show_split_stack_dialog(item: InventoryItem, slot: InventorySlotUI):
	var dialog = AcceptDialog.new()
	dialog.title = "Split Stack"
	dialog.size = Vector2(300, 150)
	
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	var label = Label.new()
	label.text = "Split %s (Current: %d)" % [item.item_name, item.quantity]
	vbox.add_child(label)
	
	var spinbox = SpinBox.new()
	spinbox.min_value = 1
	spinbox.max_value = item.quantity - 1
	spinbox.value = 1
	vbox.add_child(spinbox)
	
	var button_container = HBoxContainer.new()
	vbox.add_child(button_container)
	
	var split_button = Button.new()
	split_button.text = "Split"
	button_container.add_child(split_button)
	
	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	button_container.add_child(cancel_button)
	
	add_child(dialog)
	dialog.popup_centered()
	
	split_button.pressed.connect(func():
		var split_amount = int(spinbox.value)
		if inventory_manager:
			var new_item = item.split_stack(split_amount)
			if new_item:
				# Try to add to same container
				inventory_manager.add_item_to_container(new_item, current_container.container_id)
		dialog.queue_free()
	)
	
	cancel_button.pressed.connect(func(): dialog.queue_free())

func _show_move_item_dialog(item: InventoryItem, slot: InventorySlotUI):
	var dialog = AcceptDialog.new()
	dialog.title = "Move Item"
	dialog.size = Vector2(350, 200)
	
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	var label = Label.new()
	label.text = "Move %s to:" % item.item_name
	vbox.add_child(label)
	
	var container_list = ItemList.new()
	container_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(container_list)
	
	# Populate with available containers
	if inventory_manager:
		var containers = inventory_manager.get_accessible_containers()
		for container in containers:
			if container != current_container:
				container_list.add_item(container.container_name)
	
	var button_container = HBoxContainer.new()
	vbox.add_child(button_container)
	
	var move_button = Button.new()
	move_button.text = "Move"
	button_container.add_child(move_button)
	
	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	button_container.add_child(cancel_button)
	
	add_child(dialog)
	dialog.popup_centered()
	
	move_button.pressed.connect(func():
		var selected_index = container_list.get_selected_items()
		if not selected_index.is_empty() and inventory_manager:
			var containers = inventory_manager.get_accessible_containers()
			var target_container_index = 0
			for i in range(containers.size()):
				if containers[i] != current_container:
					if target_container_index == selected_index[0]:
						inventory_manager.transfer_item(item, current_container.container_id, containers[i].container_id)
						break
					target_container_index += 1
		dialog.queue_free()
	)
	
	cancel_button.pressed.connect(func(): dialog.queue_free())

func _show_destroy_item_confirmation(item: InventoryItem, slot: InventorySlotUI):
	var dialog = ConfirmationDialog.new()
	dialog.title = "Destroy Item"
	dialog.dialog_text = "Are you sure you want to destroy %s? This action cannot be undone." % item.item_name
	
	add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func():
		if inventory_manager:
			inventory_manager.remove_item_from_container(item, current_container.container_id)
			# Wait a frame then refresh everything
			await get_tree().process_frame
			refresh_display()
			refresh_container_list()
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func(): dialog.queue_free())

func _use_item(item: InventoryItem, slot: InventorySlotUI):
	# TODO: Implement item usage system
	print("Using item: ", item.item_name)

func _open_container_item(item: InventoryItem):
	# TODO: Implement container opening
	print("Opening container: ", item.item_name)

func _view_blueprint(item: InventoryItem):
	# TODO: Implement blueprint viewer
	print("Viewing blueprint: ", item.item_name)

# Action button handlers
func _on_stack_all_pressed():
	if inventory_manager and current_container:
		inventory_manager.auto_stack_container(current_container.container_id)

func _on_sort_container_pressed():
	if inventory_manager and current_container:
		inventory_manager.sort_container(current_container.container_id, InventoryManager.SortType.BY_NAME)

func _on_clear_container_pressed():
	if not current_container:
		return
	
	var dialog = ConfirmationDialog.new()
	dialog.title = "Clear Container"
	dialog.dialog_text = "Are you sure you want to clear all items from %s? This action cannot be undone." % current_container.container_name
	
	add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func():
		if current_container:
			current_container.clear()
			refresh_display()
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func(): dialog.queue_free())

func _show_notification(message: String):
	print("Notification: " + message)

# Public interface
func open_container(container: InventoryContainer):
	if container not in open_containers:
		open_containers.append(container)
		var container_text = "%s (%d items)" % [container.container_name, container.get_item_count()]
		container_selector.add_item(container_text)
		container_list.add_item(container_text)
	
	_switch_to_container(container)

func close_container(container: InventoryContainer):
	var index = open_containers.find(container)
	if index != -1:
		open_containers.remove_at(index)
		container_selector.remove_item(index)
		container_list.remove_item(index)

		# Switch to another container if current one was closed
		if container == current_container and not open_containers.is_empty():
			_switch_to_container(open_containers[0])
			

func refresh_display():
	if inventory_grid and current_container:
		inventory_grid.set_container(current_container)
		await get_tree().process_frame
		inventory_grid.refresh_display()
	_update_mass_info()
	refresh_container_list()

# Window state management
func toggle_visibility():
	if visible:
		hide()
	else:
		# Center before showing
		await _center_window()
		show()
		grab_focus()

func bring_to_front():
	# Center if off-screen, then show
	await _reset_window_if_offscreen()
	grab_focus()

# Keyboard shortcuts
func _input(event: InputEvent):
	# Only process if window is visible
	if not visible:
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_I:
				_close_window()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_close_window()
				get_viewport().set_input_as_handled()
			KEY_F5:
				refresh_display()
				get_viewport().set_input_as_handled()
			KEY_HOME:
				_center_window_sync()
				get_viewport().set_input_as_handled()
			KEY_ENTER:
				if search_field and search_field.has_focus():
					_apply_filters()
					get_viewport().set_input_as_handled()
			KEY_F9:
				refresh_display()
				get_viewport().set_input_as_handled()

# Theme and styling
func apply_custom_theme():
	# Apply EVE-like dark theme
	var theme = Theme.new()
	
	# ItemList style
	var itemlist_style = StyleBoxFlat.new()
	itemlist_style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	itemlist_style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	itemlist_style.border_width_left = 1
	itemlist_style.border_width_right = 1
	itemlist_style.border_width_top = 1
	itemlist_style.border_width_bottom = 1
	itemlist_style.content_margin_left = 8
	itemlist_style.content_margin_right = 8
	itemlist_style.content_margin_top = 4
	itemlist_style.content_margin_bottom = 4
	
	# Apply styles
	_apply_container_list_style(itemlist_style)
	
	# Apply theme
	set_theme(theme)

func _apply_container_list_style(itemlist_style: StyleBoxFlat):
	if container_list:
		container_list.add_theme_stylebox_override("panel", itemlist_style)
		container_list.add_theme_color_override("font_color", Color.WHITE)
		container_list.add_theme_color_override("font_selected_color", Color.YELLOW)
		container_list.add_theme_constant_override("line_separation", 4)
		
func debug_grid_ui():
	
	if not inventory_grid:
		print("No inventory grid!")
		return
	
	if inventory_grid.slots.size() > 0:
		
		# Check first few slots for items
		for y in range(min(2, inventory_grid.slots.size())):
			for x in range(min(5, inventory_grid.slots[y].size())):
				var slot = inventory_grid.slots[y][x]
				if slot:
					var has_item = slot.has_item()
					var item_name = slot.get_item().item_name if has_item else "none"

func force_complete_refresh():
	print("=== FORCING COMPLETE REFRESH ===")
	
	if not current_container:
		print("No current container!")
		return
	
	print("Refreshing container: %s with %d items" % [current_container.container_name, current_container.get_item_count()])
	
	# Force grid to rebuild
	if inventory_grid:
		print("Rebuilding grid...")
		inventory_grid.set_container(current_container)  # This should rebuild everything
		await get_tree().process_frame
		inventory_grid.refresh_display()
		await get_tree().process_frame
	
	# Also refresh the window
	refresh_display()
	
	print("Refresh complete!")
