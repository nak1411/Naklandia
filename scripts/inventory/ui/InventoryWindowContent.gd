# InventoryWindowContent.gd - Content area with container list and grid
class_name InventoryWindowContent
extends HSplitContainer

# UI Components
var container_list: ItemList
var inventory_grid: InventoryGridUI
var mass_info_bar: Panel
var mass_info_label: Label

# References
var inventory_manager: InventoryManager
var current_container: InventoryContainer
var open_containers: Array[InventoryContainer] = []

# Signals
signal container_selected(container: InventoryContainer)
signal item_activated(item: InventoryItem, slot: InventorySlotUI)
signal item_context_menu(item: InventoryItem, slot: InventorySlotUI, position: Vector2)

func _ready():
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_offset = 200
	_remove_split_container_outline()
	_setup_content()

func _remove_split_container_outline():
	# Remove the default HSplitContainer theme that creates outlines
	var theme = Theme.new()
	
	# Create custom grabber style without outlines
	var grabber_style = StyleBoxFlat.new()
	grabber_style.bg_color = Color(0.4, 0.4, 0.4, 1.0)
	grabber_style.corner_radius_top_left = 2
	grabber_style.corner_radius_top_right = 2
	grabber_style.corner_radius_bottom_left = 2
	grabber_style.corner_radius_bottom_right = 2
	
	# Remove any border/outline styling
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color.TRANSPARENT
	panel_style.border_width_left = 0
	panel_style.border_width_right = 0
	panel_style.border_width_top = 0
	panel_style.border_width_bottom = 0
	
	theme.set_stylebox("grabber", "HSplitContainer", grabber_style)
	theme.set_stylebox("panel", "HSplitContainer", panel_style)
	theme.set_stylebox("bg", "HSplitContainer", panel_style)
	
	set_theme(theme)

func _setup_content():
	_setup_left_panel()
	_setup_right_panel()

func _setup_left_panel():
	var left_panel = VBoxContainer.new()
	left_panel.custom_minimum_size.x = 180
	left_panel.size_flags_horizontal = Control.SIZE_FILL
	add_child(left_panel)
	
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
	
	# Keep normal dark background for container list
	var list_style = StyleBoxFlat.new()
	list_style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	list_style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	list_style.border_width_left = 1
	list_style.border_width_right = 1
	list_style.border_width_top = 1
	list_style.border_width_bottom = 1
	container_list.add_theme_stylebox_override("panel", list_style)
	
	left_panel.add_child(container_list)
	
	container_list.item_selected.connect(_on_container_list_selected)

func _setup_right_panel():
	var inventory_area = VBoxContainer.new()
	inventory_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_area.add_theme_constant_override("separation", 4)
	add_child(inventory_area)
	
	_setup_mass_info_bar(inventory_area)
	
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
	
	# Connect grid signals properly
	inventory_grid.item_activated.connect(_on_item_activated)
	inventory_grid.item_context_menu.connect(_on_item_context_menu)

func _setup_mass_info_bar(parent: Control):
	mass_info_bar = Panel.new()
	mass_info_bar.name = "MassInfoBar"
	mass_info_bar.custom_minimum_size.y = 35
	mass_info_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(mass_info_bar)
	
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

func _on_container_list_selected(index: int):
	if index >= 0 and index < open_containers.size():
		container_selected.emit(open_containers[index])

func _on_item_activated(item: InventoryItem, slot: InventorySlotUI):
	item_activated.emit(item, slot)

func _on_item_context_menu(item: InventoryItem, slot: InventorySlotUI, position: Vector2):
	item_context_menu.emit(item, slot, position)

# Public interface
func set_inventory_manager(manager: InventoryManager):
	inventory_manager = manager

func update_containers(containers: Array[InventoryContainer]):
	open_containers = containers
	container_list.clear()
	
	for container in containers:
		var total_qty = container.get_total_quantity()
		var unique_items = container.get_item_count()
		
		var container_text = container.container_name
		
		container_list.add_item(container_text)
		var item_index = container_list.get_item_count() - 1
		container_list.set_item_tooltip(item_index, container_text)

func select_container(container: InventoryContainer):
	current_container = container
	
	if inventory_grid:
		if container and container.get_item_count() > 0:
			container.compact_items()
		
		inventory_grid.set_container(container)
		await get_tree().process_frame
		refresh_display()
	
	update_mass_info()

func select_container_index(index: int):
	if index >= 0 and index < open_containers.size():
		container_list.select(index)

func refresh_display():
	if inventory_grid and current_container:
		inventory_grid.set_container(current_container)
		await get_tree().process_frame
		inventory_grid.refresh_display()
	update_mass_info()

func update_mass_info():
	if not current_container or not mass_info_label:
		mass_info_label.text = "No container selected"
		return
	
	var info = current_container.get_container_info()
	
	var text = "%s  |  " % current_container.container_name
	text += "Items: %d (%d types)  |  " % [info.total_quantity, info.item_count]
	text += "Volume: %.1f/%.1f m³ (%.1f%%)  |  " % [info.volume_used, info.volume_max, info.volume_percentage]
	text += "Mass: %.1f kg  |  " % info.total_mass
	text += "Value: %.0f ISK" % info.total_value
	
	mass_info_label.text = text
	
	if info.volume_percentage > 90:
		mass_info_label.add_theme_color_override("font_color", Color.RED)
	elif info.volume_percentage > 75:
		mass_info_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		mass_info_label.add_theme_color_override("font_color", Color.WHITE)

func get_current_container() -> InventoryContainer:
	return current_container

func get_inventory_grid() -> InventoryGridUI:
	return inventory_grid
