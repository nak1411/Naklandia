# InventoryWindowUI.gd - Main inventory window with EVE-like interface
class_name InventoryWindowUI
extends Window

# Window properties
@export var window_title: String = "Inventory"
@export var min_window_size: Vector2 = Vector2(400, 300)
@export var default_size: Vector2 = Vector2(800, 600)

# UI Components
var main_container: VBoxContainer
var header_container: HBoxContainer
var content_container: HSplitContainer
var container_list: ItemList
var inventory_grid: InventoryGridUI
var info_panel: VBoxContainer

# Header components
var title_label: Label
var close_button: Button
var minimize_button: Button
var container_selector: OptionButton
var search_field: LineEdit
var filter_options: OptionButton
var sort_button: MenuButton

# Info panel components
var container_info_label: RichTextLabel
var volume_bar: ProgressBar
var item_info_panel: Panel
var selected_item_info: RichTextLabel

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
	
	# Enable window dragging and resizing
	set_flag(Window.FLAG_RESIZE_DISABLED, false)
	set_flag(Window.FLAG_BORDERLESS, false)
	
	# Start hidden and centered
	visible = false
	
	# Set initial position to center (will be properly centered in _ready)
	position = Vector2i(
		(DisplayServer.screen_get_size().x - size.x) / 2,
		(DisplayServer.screen_get_size().y - size.y) / 2
	)

func _ready():
	_setup_ui()
	_connect_signals()
	_find_inventory_manager()
	
	# Apply custom styling
	apply_custom_theme()
	
	# Center the window properly
	_center_window()
	
	# Ensure window starts hidden
	visible = false
	hide()

func _center_window():
	# Get screen size
	var screen_size = DisplayServer.screen_get_size()
	var window_size = size
	
	# Calculate center position
	var center_pos = Vector2i(
		(screen_size.x - window_size.x) / 2,
		(screen_size.y - window_size.y) / 2
	)
	
	position = center_pos
	print("Window centered at: ", center_pos)

func _is_window_on_screen() -> bool:
	var screen_size = DisplayServer.screen_get_size()
	var window_rect = Rect2i(position, size)
	var screen_rect = Rect2i(Vector2i.ZERO, screen_size)
	
	# Check if at least 100x100 pixels of the window are visible
	var visible_area = window_rect.intersection(screen_rect)
	return visible_area.size.x >= 100 and visible_area.size.y >= 100

func _reset_window_if_offscreen():
	if not _is_window_on_screen():
		print("Window is off-screen, resetting position...")
		_center_window()

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
	
	# Info panel
	_setup_info_panel()

func _setup_header():
	header_container = HBoxContainer.new()
	header_container.name = "Header"
	header_container.custom_minimum_size.y = 40
	main_container.add_child(header_container)
	
	# Title (make it draggable)
	title_label = Label.new()
	title_label.text = window_title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_container.add_child(title_label)
	
	# Make the header draggable
	_setup_window_dragging()
	
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
	
	# Window controls
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_container.add_child(spacer)
	
	minimize_button = Button.new()
	minimize_button.text = "_"
	minimize_button.custom_minimum_size = Vector2(30, 30)
	header_container.add_child(minimize_button)
	
	close_button = Button.new()
	close_button.text = "×"
	close_button.custom_minimum_size = Vector2(30, 30)
	header_container.add_child(close_button)

func _setup_window_dragging():
	# The window should be draggable by default in Godot 4
	# If it's not working, we can implement custom dragging
	var drag_enabled = true
	
	if drag_enabled:
		# Make sure the window can be dragged by the title bar
		# This is usually automatic, but we can force it
		borderless = false
		unresizable = false
		
		# If automatic dragging doesn't work, implement manual dragging
		var is_dragging = false
		var drag_offset = Vector2()
		
		title_label.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton:
				var mouse_event = event as InputEventMouseButton
				if mouse_event.button_index == MOUSE_BUTTON_LEFT:
					if mouse_event.pressed:
						is_dragging = true
						drag_offset = mouse_event.global_position - Vector2(position)
					else:
						is_dragging = false
			
			elif event is InputEventMouseMotion and is_dragging:
				var mouse_event = event as InputEventMouseMotion
				position = Vector2i(mouse_event.global_position - drag_offset)
		)

func _setup_content():
	content_container = HSplitContainer.new()
	content_container.name = "Content"
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_container.add_child(content_container)
	
	# Container list (left side)
	var left_panel = VBoxContainer.new()
	left_panel.custom_minimum_size.x = 200
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
	container_list.custom_minimum_size = Vector2(180, 200)
	container_list.auto_height = true
	container_list.fixed_column_width = 180
	left_panel.add_child(container_list)
	
	# Inventory grid (center)
	var grid_scroll = ScrollContainer.new()
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.custom_minimum_size.x = 400
	content_container.add_child(grid_scroll)
	
	inventory_grid = InventoryGridUI.new()
	inventory_grid.name = "InventoryGrid"
	grid_scroll.add_child(inventory_grid)

func _setup_info_panel():
	info_panel = VBoxContainer.new()
	info_panel.name = "InfoPanel"
	info_panel.custom_minimum_size.x = 250
	info_panel.size_flags_horizontal = Control.SIZE_FILL
	info_panel.add_theme_constant_override("separation", 4)
	content_container.add_child(info_panel)
	
	# Create tab container for different info panels
	var tab_container = TabContainer.new()
	tab_container.name = "InfoTabs"
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_container.custom_minimum_size.y = 400
	info_panel.add_child(tab_container)
	
	# Container Info Tab
	_setup_container_info_tab(tab_container)
	
	# Selected Item Tab
	_setup_selected_item_tab(tab_container)
	
	# Actions Tab
	_setup_actions_tab(tab_container)

func _setup_container_info_tab(tab_container: TabContainer):
	var container_tab = VBoxContainer.new()
	container_tab.name = "Container"
	container_tab.add_theme_constant_override("separation", 8)
	tab_container.add_child(container_tab)
	
	# Container info
	container_info_label = RichTextLabel.new()
	container_info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container_info_label.bbcode_enabled = true
	container_info_label.fit_content = true
	container_info_label.scroll_active = true
	container_info_label.add_theme_constant_override("content_margin_left", 8)
	container_info_label.add_theme_constant_override("content_margin_right", 8)
	container_info_label.add_theme_constant_override("content_margin_top", 8)
	container_info_label.add_theme_constant_override("content_margin_bottom", 8)
	container_tab.add_child(container_info_label)
	
	# Volume bar section
	var volume_section = VBoxContainer.new()
	volume_section.add_theme_constant_override("separation", 4)
	container_tab.add_child(volume_section)
	
	var volume_label = Label.new()
	volume_label.text = "Volume Usage"
	volume_label.add_theme_color_override("font_color", Color.CYAN)
	volume_label.add_theme_font_size_override("font_size", 12)
	volume_label.custom_minimum_size.y = 20
	volume_section.add_child(volume_label)
	
	volume_bar = ProgressBar.new()
	volume_bar.max_value = 100
	volume_bar.value = 0
	volume_bar.show_percentage = true
	volume_bar.custom_minimum_size.y = 25
	volume_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_section.add_child(volume_bar)

func _setup_selected_item_tab(tab_container: TabContainer):
	var item_tab = VBoxContainer.new()
	item_tab.name = "Selected Item"
	tab_container.add_child(item_tab)
	
	selected_item_info = RichTextLabel.new()
	selected_item_info.bbcode_enabled = true
	selected_item_info.fit_content = true
	selected_item_info.scroll_active = true
	selected_item_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	selected_item_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_item_info.add_theme_constant_override("content_margin_left", 8)
	selected_item_info.add_theme_constant_override("content_margin_right", 8)
	selected_item_info.add_theme_constant_override("content_margin_top", 8)
	selected_item_info.add_theme_constant_override("content_margin_bottom", 8)
	item_tab.add_child(selected_item_info)

func _setup_actions_tab(tab_container: TabContainer):
	var actions_tab = VBoxContainer.new()
	actions_tab.name = "Actions"
	actions_tab.add_theme_constant_override("separation", 8)
	tab_container.add_child(actions_tab)
	
	# Container actions
	var container_actions_label = Label.new()
	container_actions_label.text = "Container Actions"
	container_actions_label.add_theme_color_override("font_color", Color.CYAN)
	container_actions_label.add_theme_font_size_override("font_size", 14)
	container_actions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	actions_tab.add_child(container_actions_label)
	
	var container_actions = VBoxContainer.new()
	container_actions.add_theme_constant_override("separation", 4)
	actions_tab.add_child(container_actions)
	
	var stack_all_button = Button.new()
	stack_all_button.text = "Stack All Items"
	stack_all_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack_all_button.custom_minimum_size.y = 30
	container_actions.add_child(stack_all_button)
	stack_all_button.pressed.connect(_on_stack_all_pressed)
	
	var sort_container_button = Button.new()
	sort_container_button.text = "Sort Container"
	sort_container_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sort_container_button.custom_minimum_size.y = 30
	container_actions.add_child(sort_container_button)
	sort_container_button.pressed.connect(_on_sort_container_pressed)
	
	var clear_container_button = Button.new()
	clear_container_button.text = "Clear Container"
	clear_container_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_container_button.custom_minimum_size.y = 30
	clear_container_button.modulate = Color.RED
	container_actions.add_child(clear_container_button)
	clear_container_button.pressed.connect(_on_clear_container_pressed)
	
	# Spacer
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	actions_tab.add_child(spacer)
	
	# Item actions
	var item_actions_label = Label.new()
	item_actions_label.text = "Item Actions"
	item_actions_label.add_theme_color_override("font_color", Color.CYAN)
	item_actions_label.add_theme_font_size_override("font_size", 14)
	item_actions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	actions_tab.add_child(item_actions_label)
	
	var item_actions = VBoxContainer.new()
	item_actions.add_theme_constant_override("separation", 4)
	actions_tab.add_child(item_actions)
	
	var use_item_button = Button.new()
	use_item_button.text = "Use Selected Item"
	use_item_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	use_item_button.custom_minimum_size.y = 30
	item_actions.add_child(use_item_button)
	use_item_button.pressed.connect(_on_use_selected_item)
	
	var drop_item_button = Button.new()
	drop_item_button.text = "Drop Selected Item"
	drop_item_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop_item_button.custom_minimum_size.y = 30
	item_actions.add_child(drop_item_button)
	drop_item_button.pressed.connect(_on_drop_selected_item)
	
	var destroy_item_button = Button.new()
	destroy_item_button.text = "Destroy Selected Item"
	destroy_item_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	destroy_item_button.custom_minimum_size.y = 30
	destroy_item_button.modulate = Color.RED
	item_actions.add_child(destroy_item_button)
	destroy_item_button.pressed.connect(_on_destroy_selected_item)

func _connect_signals():
	# Window controls
	close_button.pressed.connect(_on_close_pressed)
	minimize_button.pressed.connect(_on_minimize_pressed)
	close_requested.connect(_on_close_requested)
	
	# Container selection
	container_selector.item_selected.connect(_on_container_selector_changed)
	container_list.item_selected.connect(_on_container_list_selected)
	
	# Search and filter
	search_field.text_changed.connect(_on_search_text_changed)
	filter_options.item_selected.connect(_on_filter_changed)
	
	# Sort menu
	var sort_popup = sort_button.get_popup()
	sort_popup.id_pressed.connect(_on_sort_selected)
	
	# Inventory grid
	if inventory_grid:
		inventory_grid.item_selected.connect(_on_item_selected)
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
	
	for container in containers:
		var container_text = "%s (%d)" % [container.container_name, container.get_item_count()]
		
		# Add to option button (header)
		container_selector.add_item(container_text)
		
		# Add to item list (left panel) with proper sizing
		container_list.add_item(container_text)
		# Set item text to wrap if too long
		var item_index = container_list.get_item_count() - 1
		container_list.set_item_tooltip(item_index, container_text)
		
		open_containers.append(container)
	
	# Select first container by default
	if not open_containers.is_empty():
		_switch_to_container(open_containers[0])
		container_selector.selected = 0
		container_list.select(0)

func _switch_to_container(container: InventoryContainer):
	current_container = container
	
	if inventory_grid:
		inventory_grid.set_container(container)
	
	_update_container_info()
	_update_volume_bar()
	_clear_item_info()
	
	container_switched.emit(container)

func _update_container_info():
	if not current_container or not container_info_label:
		return
	
	var info = current_container.get_container_info()
	var text = "[center][b][color=cyan][font_size=16]%s[/font_size][/color][/b][/center]\n\n" % info.name
	
	# Basic Stats
	text += "[color=yellow][b]Basic Information[/b][/color]\n"
	text += "[color=white]Container ID:[/color] [color=gray]%s[/color]\n" % current_container.container_id
	text += "[color=white]Container Type:[/color] [color=cyan]%s[/color]\n" % InventoryItem.ContainerType.keys()[current_container.container_type]
	text += "[color=white]Grid Size:[/color] [color=white]%dx%d[/color]\n" % [current_container.grid_width, current_container.grid_height]
	
	if info.is_secure:
		text += "[color=green]● Secure Container[/color]\n"
	
	if current_container.requires_docking:
		text += "[color=orange]● Requires Docking[/color]\n"
	
	text += "\n"
	
	# Content Stats
	text += "[color=yellow][b]Content Statistics[/b][/color]\n"
	text += "[color=white]Total Items:[/color] [color=yellow]%d[/color]\n" % info.item_count
	text += "[color=white]Volume Used:[/color] [color=yellow]%.1f m³[/color] / [color=green]%.1f m³[/color]\n" % [info.volume_used, info.volume_max]
	text += "[color=white]Volume Free:[/color] [color=green]%.1f m³[/color] (%.1f%%)\n" % [info.volume_max - info.volume_used, (info.volume_max - info.volume_used) / info.volume_max * 100 if info.volume_max > 0 else 0]
	text += "[color=white]Total Mass:[/color] [color=yellow]%.1f kg[/color]\n" % info.total_mass
	text += "[color=white]Total Value:[/color] [color=gold]%.0f ISK[/color]\n" % info.total_value
	
	# Item breakdown if there are items
	if info.item_count > 0:
		text += "\n[color=yellow][b]Item Types[/b][/color]\n"
		var item_types = {}
		
		for item in current_container.items:
			var type_name = InventoryItem.ItemType.keys()[item.item_type]
			if type_name in item_types:
				item_types[type_name] += item.quantity
			else:
				item_types[type_name] = item.quantity
		
		for type_name in item_types:
			var count = item_types[type_name]
			text += "[color=white]%s:[/color] [color=cyan]%d[/color]\n" % [type_name.capitalize().replace("_", " "), count]
	
	# Restrictions
	if not current_container.allowed_item_types.is_empty():
		text += "\n[color=yellow][b]Restrictions[/b][/color]\n"
		text += "[color=white]Allowed Types:[/color]\n"
		for item_type in current_container.allowed_item_types:
			var type_name = InventoryItem.ItemType.keys()[item_type]
			text += "  [color=cyan]• %s[/color]\n" % type_name.capitalize().replace("_", " ")
	
	container_info_label.text = text

func _update_volume_bar():
	if not current_container or not volume_bar:
		return
	
	var percentage = current_container.get_volume_percentage()
	volume_bar.value = percentage
	
	# Color coding
	if percentage > 90:
		volume_bar.modulate = Color.RED
	elif percentage > 75:
		volume_bar.modulate = Color.YELLOW
	else:
		volume_bar.modulate = Color.GREEN

# Item information
func _on_item_selected(item: InventoryItem, slot: InventorySlotUI):
	_show_item_info(item)

func _show_item_info(item: InventoryItem):
	if not item or not selected_item_info:
		return
	
	var text = "[b][color=white]%s[/color][/b]\n" % item.item_name
	text += "[color=%s]%s[/color]\n\n" % [item.get_rarity_color().to_html(), InventoryItem.ItemRarity.keys()[item.item_rarity]]
	
	text += "[color=cyan][b]Type:[/b][/color] [color=white]%s[/color]\n" % InventoryItem.ItemType.keys()[item.item_type]
	text += "[color=cyan][b]Quantity:[/b][/color] [color=yellow]%d[/color]\n" % item.quantity
	
	if item.quantity > 1:
		text += "[color=cyan][b]Volume:[/b][/color] [color=white]%.2f m³[/color] ([color=yellow]%.2f m³[/color] total)\n" % [item.volume, item.get_total_volume()]
		text += "[color=cyan][b]Mass:[/b][/color] [color=white]%.2f kg[/color] ([color=yellow]%.2f kg[/color] total)\n" % [item.mass, item.get_total_mass()]
		text += "[color=cyan][b]Value:[/b][/color] [color=white]%.0f ISK[/color] ([color=gold]%.0f ISK[/color] total)\n\n" % [item.base_value, item.get_total_value()]
	else:
		text += "[color=cyan][b]Volume:[/b][/color] [color=yellow]%.2f m³[/color]\n" % item.volume
		text += "[color=cyan][b]Mass:[/b][/color] [color=yellow]%.2f kg[/color]\n" % item.mass
		text += "[color=cyan][b]Value:[/b][/color] [color=gold]%.0f ISK[/color]\n\n" % item.base_value
	
	if not item.description.is_empty():
		text += "[color=cyan][b]Description:[/b][/color]\n[color=light_gray]%s[/color]" % item.description
	
	selected_item_info.text = text

func _clear_item_info():
	if selected_item_info:
		selected_item_info.text = "[color=gray][i]No item selected[/i][/color]"

# Event handlers
func _on_close_pressed():
	_close_window()

func _on_minimize_pressed():
	visible = false

func _on_close_requested():
	_close_window()

func _close_window():
	visible = false
	window_closed.emit()

func _on_container_selector_changed(index: int):
	if index >= 0 and index < open_containers.size():
		_switch_to_container(open_containers[index])
		container_list.select(index)

func _on_container_list_selected(index: int):
	if index >= 0 and index < open_containers.size():
		_switch_to_container(open_containers[index])
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

func _show_item_context_menu(item: InventoryItem, slot: InventorySlotUI, position: Vector2):
	var popup = PopupMenu.new()
	
	# Basic actions
	popup.add_item("Item Information", 0)
	popup.add_separator()
	
	if item.quantity > 1:
		popup.add_item("Split Stack", 1)
	
	popup.add_item("Move to...", 2)
	
	if item.can_be_destroyed:
		popup.add_separator()
		popup.add_item("Destroy Item", 3)
	
	# Item-specific actions
	match item.item_type:
		InventoryItem.ItemType.CONSUMABLE:
			popup.add_separator()
			popup.add_item("Use Item", 10)
		InventoryItem.ItemType.CONTAINER:
			popup.add_separator()
			popup.add_item("Open Container", 11)
		InventoryItem.ItemType.BLUEPRINT:
			popup.add_separator()
			popup.add_item("View Blueprint", 12)
	
	add_child(popup)
	popup.position = Vector2i(position)
	popup.popup()
	
	# Connect signal
	popup.id_pressed.connect(_on_context_menu_item_selected.bind(popup, item, slot))

func _on_context_menu_item_selected(popup: PopupMenu, item: InventoryItem, slot: InventorySlotUI, id: int):
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
	
	popup.queue_free()

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

func _on_use_selected_item():
	var selected_items = inventory_grid.get_selected_items() if inventory_grid else []
	if selected_items.is_empty():
		_show_notification("No item selected")
		return
	
	var item = selected_items[0]
	# TODO: Integrate with item usage system
	_show_notification("Used: " + item.item_name)

func _on_drop_selected_item():
	var selected_items = inventory_grid.get_selected_items() if inventory_grid else []
	if selected_items.is_empty():
		_show_notification("No item selected")
		return
	
	var item = selected_items[0]
	# TODO: Integrate with world drop system
	_show_notification("Dropped: " + item.item_name)

func _on_destroy_selected_item():
	var selected_items = inventory_grid.get_selected_items() if inventory_grid else []
	if selected_items.is_empty():
		_show_notification("No item selected")
		return
	
	var item = selected_items[0]
	if not item.can_be_destroyed:
		_show_notification("This item cannot be destroyed")
		return
	
	var dialog = ConfirmationDialog.new()
	dialog.title = "Destroy Item"
	dialog.dialog_text = "Are you sure you want to destroy %s? This action cannot be undone." % item.item_name
	
	add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func():
		if inventory_manager and current_container:
			inventory_manager.remove_item_from_container(item, current_container.container_id)
			_show_notification("Destroyed: " + item.item_name)
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
	if inventory_grid:
		inventory_grid.refresh_display()
	_update_container_info()
	_update_volume_bar()

# Window state management
func toggle_visibility():
	if visible:
		hide()
	else:
		# Reset position if window was dragged off-screen
		_reset_window_if_offscreen()
		show()
		grab_focus()

func bring_to_front():
	# Reset position if window was dragged off-screen
	_reset_window_if_offscreen()
	grab_focus()

# Keyboard shortcuts
func _unhandled_key_input(event: InputEvent):
	if not visible:
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_I:
				# Close inventory when I is pressed
				print("I key pressed in inventory window - closing")
				_close_window()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_close_window()
			KEY_F5:
				refresh_display()
			KEY_HOME:
				# Reset window to center
				print("Resetting window position to center...")
				_center_window()
			KEY_ENTER:
				if search_field and search_field.has_focus():
					_apply_filters()

# Theme and styling
func apply_custom_theme():
	# Apply EVE-like dark theme
	var theme = Theme.new()
	
	# Panel styles
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.15, 0.15, 0.95)
	panel_style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	
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
	
	# Tab container style
	var tab_style = StyleBoxFlat.new()
	tab_style.bg_color = Color(0.08, 0.08, 0.08, 0.95)
	tab_style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	tab_style.border_width_left = 1
	tab_style.border_width_right = 1
	tab_style.border_width_top = 1
	tab_style.border_width_bottom = 1
	
	# Tab button styles
	var tab_unselected = StyleBoxFlat.new()
	tab_unselected.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	tab_unselected.border_color = Color(0.4, 0.4, 0.4, 1.0)
	tab_unselected.border_width_left = 1
	tab_unselected.border_width_right = 1
	tab_unselected.border_width_top = 1
	tab_unselected.border_width_bottom = 0
	
	var tab_selected = StyleBoxFlat.new()
	tab_selected.bg_color = Color(0.08, 0.08, 0.08, 1.0)
	tab_selected.border_color = Color(0.6, 0.8, 1.0, 1.0)
	tab_selected.border_width_left = 1
	tab_selected.border_width_right = 1
	tab_selected.border_width_top = 2
	tab_selected.border_width_bottom = 0
	
	# RichTextLabel style
	var info_panel_style = StyleBoxFlat.new()
	info_panel_style.bg_color = Color(0.05, 0.05, 0.05, 0.9)
	info_panel_style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	info_panel_style.border_width_left = 1
	info_panel_style.border_width_right = 1
	info_panel_style.border_width_top = 1
	info_panel_style.border_width_bottom = 1
	info_panel_style.corner_radius_top_left = 4
	info_panel_style.corner_radius_top_right = 4
	info_panel_style.corner_radius_bottom_left = 4
	info_panel_style.corner_radius_bottom_right = 4
	
	# Apply styles
	_apply_container_list_style(itemlist_style)
	_apply_info_panel_styles(info_panel_style)
	_apply_tab_container_styles(tab_style, tab_unselected, tab_selected)
	
	# Apply theme
	set_theme(theme)

func _apply_container_list_style(itemlist_style: StyleBoxFlat):
	if container_list:
		container_list.add_theme_stylebox_override("panel", itemlist_style)
		container_list.add_theme_color_override("font_color", Color.WHITE)
		container_list.add_theme_color_override("font_selected_color", Color.YELLOW)
		container_list.add_theme_constant_override("line_separation", 4)

func _apply_info_panel_styles(info_panel_style: StyleBoxFlat):
	if container_info_label:
		container_info_label.add_theme_stylebox_override("normal", info_panel_style)
		container_info_label.add_theme_color_override("default_color", Color.WHITE)
	
	if selected_item_info:
		selected_item_info.add_theme_color_override("default_color", Color.WHITE)

func _apply_tab_container_styles(tab_style: StyleBoxFlat, tab_unselected: StyleBoxFlat, tab_selected: StyleBoxFlat):
	if not info_panel:
		return
	
	var tab_container = info_panel.get_node("InfoTabs")
	if tab_container:
		tab_container.add_theme_stylebox_override("panel", tab_style)
		tab_container.add_theme_stylebox_override("tab_unselected", tab_unselected)
		tab_container.add_theme_stylebox_override("tab_selected", tab_selected)
		tab_container.add_theme_color_override("font_selected_color", Color.CYAN)
		tab_container.add_theme_color_override("font_unselected_color", Color.LIGHT_GRAY)
		container_list.add_theme_constant_override("line_separation", 4)
	
	# Apply to info panels
	if container_info_label:
		container_info_label.add_theme_stylebox_override("normal", info_panel_style)
		container_info_label.add_theme_color_override("default_color", Color.WHITE)
	
	if item_info_panel:
		item_info_panel.add_theme_stylebox_override("panel", info_panel_style)
	
	if selected_item_info:
		selected_item_info.add_theme_color_override("default_color", Color.WHITE)
	
	# Apply theme
	set_theme(theme)
