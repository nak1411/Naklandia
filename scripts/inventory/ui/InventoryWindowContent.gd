class_name InventoryWindowContent
extends HSplitContainer

# UI Components
var container_list: ItemList
var inventory_grid: InventoryGrid
var mass_info_bar: Panel
var mass_info_label: Label
var external_container_list: ItemList = null
var using_external_container_list: bool = false

# References
var inventory_manager: InventoryManager
var current_container: InventoryContainer_Base
var open_containers: Array[InventoryContainer_Base] = []

# Signals
signal container_selected(container: InventoryContainer_Base)
signal item_activated(item: InventoryItem_Base, slot: InventorySlot)
signal item_context_menu(item: InventoryItem_Base, slot: InventorySlot, position: Vector2)

func _ready():
	print("InventoryWindowContent _ready() starting...")
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_offset = 200
	_setup_content()
	print("InventoryWindowContent _ready() completed")

func _setup_content():
	print("Setting up InventoryWindowContent...")
	if using_external_container_list:
		_setup_right_panel_only()
	else:
		_setup_full_content()

func _setup_full_content():
	print("Setting up full content with container list...")
	var left_panel = VBoxContainer.new()
	left_panel.name = "LeftPanel"
	left_panel.custom_minimum_size.x = 180
	left_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(left_panel)
	
	var list_label = Label.new()
	list_label.text = "Containers"
	list_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_panel.add_child(list_label)
	
	container_list = ItemList.new()
	container_list.name = "ContainerList"
	container_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container_list.item_selected.connect(_on_container_list_selected)
	left_panel.add_child(container_list)
	
	_setup_right_panel()
	print("Full content setup completed")

func _setup_right_panel_only():
	print("Setting up right panel only...")
	var inventory_area = VBoxContainer.new()
	inventory_area.name = "InventoryArea"
	inventory_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(inventory_area)
	
	_setup_mass_info_bar(inventory_area)
	
	var grid_scroll = ScrollContainer.new()
	grid_scroll.name = "GridScrollContainer"
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_area.add_child(grid_scroll)
	
	inventory_grid = InventoryGrid.new()
	inventory_grid.name = "InventoryGrid"
	inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.add_child(inventory_grid)
	
	inventory_grid.item_activated.connect(_on_item_activated)
	inventory_grid.item_context_menu.connect(_on_item_context_menu)
	print("Right panel only setup completed")

func _setup_right_panel():
	print("Setting up right panel...")
	var inventory_area = VBoxContainer.new()
	inventory_area.name = "InventoryArea"
	inventory_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(inventory_area)
	
	_setup_mass_info_bar(inventory_area)
	
	var grid_scroll = ScrollContainer.new()
	grid_scroll.name = "GridScrollContainer"
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_area.add_child(grid_scroll)
	
	inventory_grid = InventoryGrid.new()
	inventory_grid.name = "InventoryGrid"
	inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.add_child(inventory_grid)
	
	inventory_grid.item_activated.connect(_on_item_activated)
	inventory_grid.item_context_menu.connect(_on_item_context_menu)
	print("Right panel setup completed")

func _setup_mass_info_bar(parent: Control):
	print("Setting up mass info bar...")
	mass_info_bar = Panel.new()
	mass_info_bar.name = "MassInfoBar"
	mass_info_bar.custom_minimum_size.y = 35
	mass_info_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(mass_info_bar)
	
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	style_box.border_width_left = 1
	style_box.border_width_right = 1
	style_box.border_width_top = 1
	style_box.border_width_bottom = 1
	style_box.border_color = Color(0.3, 0.3, 0.3, 1.0)
	mass_info_bar.add_theme_stylebox_override("panel", style_box)
	
	mass_info_label = Label.new()
	mass_info_label.text = "Mass: 0/0 kg | Volume: 0/0 m³"
	mass_info_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mass_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mass_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mass_info_label.add_theme_constant_override("margin_left", 10)
	mass_info_label.add_theme_constant_override("margin_right", 10)
	mass_info_bar.add_child(mass_info_label)
	print("Mass info bar setup completed")

# Signal handlers - These forward signals from grid to parent window
func _on_item_activated(item: InventoryItem_Base, slot: InventorySlot):
	print("Item activated: ", item.item_name)
	item_activated.emit(item, slot)

func _on_item_context_menu(item: InventoryItem_Base, slot: InventorySlot, position: Vector2):
	print("Item context menu requested for: ", item.item_name)  
	item_context_menu.emit(item, slot, position)

func _on_container_list_selected(index: int):
	print("Container list item selected: ", index)
	if index >= 0 and index < open_containers.size():
		var selected_container = open_containers[index]
		print("Emitting container_selected for: ", selected_container.container_name)
		container_selected.emit(selected_container)

# Core functionality - THIS IS WHAT WAS WORKING BEFORE
func set_inventory_manager(manager: InventoryManager):
	print("Setting inventory manager on content: ", manager)
	inventory_manager = manager

func update_containers(containers: Array[InventoryContainer_Base]):
	print("Updating containers list. Count: ", containers.size())
	open_containers = containers
	
	# Use external container list if available, otherwise use internal one
	var list_to_update = external_container_list if using_external_container_list else container_list
	
	if not list_to_update:
		print("ERROR: No container list to update!")
		return
	
	list_to_update.clear()
	
	for i in range(containers.size()):
		var container = containers[i]
		var unique_items = container.get_item_count()
		
		var container_text = container.container_name
		print("Adding container to list: ", container_text, " (", unique_items, " items)")
		
		list_to_update.add_item(container_text)
		var item_index = list_to_update.get_item_count() - 1
		list_to_update.set_item_tooltip(item_index, container_text)

func select_container(container: InventoryContainer_Base):
	print("Selecting container: ", container.container_name if container else "NULL")
	current_container = container
	
	if not inventory_grid:
		print("ERROR: No inventory grid to set container on!")
		return
	
	if container:
		print("Container items count: ", container.get_item_count())
		print("Container grid size: ", container.grid_width, "x", container.grid_height)
		
		# Only compact if auto_stack is enabled in inventory manager
		if container.get_item_count() > 0 and inventory_manager and inventory_manager.auto_stack:
			print("Compacting container items...")
			container.compact_items()
		
		print("Setting container on inventory grid...")
		inventory_grid.set_container(container)
		await get_tree().process_frame
		print("Refreshing display...")
		refresh_display()
	else:
		print("Clearing inventory grid (null container)")
		inventory_grid.set_container(null)
	
	update_mass_info()

func select_container_index(index: int):
	print("Selecting container by index: ", index)
	if index >= 0 and index < open_containers.size():
		var list_to_use = external_container_list if using_external_container_list else container_list
		if list_to_use:
			list_to_use.select(index)

func refresh_display():
	if not inventory_grid:
		return
	
	if not current_container:
		return
	# Make sure the grid has the container set
	inventory_grid.set_container(current_container)
	await get_tree().process_frame
	
	# Force refresh the grid display
	inventory_grid.refresh_display()
	
	# Update mass info
	update_mass_info()

func update_mass_info():
	if not current_container or not mass_info_label:
		if mass_info_label:
			mass_info_label.text = "No container selected"
		return
	
	var info = current_container.get_container_info()
	mass_info_label.text = "Mass: %.1f kg | Volume: %.1f/%.1f m³ (%.1f%%)" % [
		info.total_mass, info.volume_used, info.volume_max, info.volume_percentage
	]

func get_inventory_grid() -> InventoryGrid:
	return inventory_grid

func resize_grid(new_size: Vector2i):
	if inventory_grid and current_container:
		current_container.resize_grid(new_size.x, new_size.y)
		inventory_grid.grid_width = new_size.x
		inventory_grid.grid_height = new_size.y
		if inventory_grid.has_method("_rebuild_grid"):
			await inventory_grid._rebuild_grid()
		inventory_grid.refresh_display()

func debug_content_state():
	print("InventoryWindowContent Debug State:")
	print("  - inventory_manager: ", inventory_manager != null)
	print("  - current_container: ", current_container.container_name if current_container else "None")
	print("  - inventory_grid: ", inventory_grid != null)
	print("  - open_containers count: ", open_containers.size())
