# InventoryWindowContent.gd - Updated with debugging and proper initialization
class_name InventoryWindowContent
extends HSplitContainer

# UI Components
var container_list: ItemList
var inventory_grid: InventoryGrid
var mass_info_bar: Panel
var mass_info_label: Label
var external_container_list: ItemList = null
var using_external_container_list: bool = false
var original_content_styles: Dictionary = {}
var content_transparency_init: bool = false

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
	_remove_split_container_outline()
	_setup_content()
	
	# Connect gui_input for drop handling
	gui_input.connect(_gui_input)
	print("InventoryWindowContent _ready() completed")

func _remove_split_container_outline():
	# Remove the default HSplitContainer theme that creates outlines
	var theme = Theme.new()
	
	# Create custom grabber style without outlines
	var grabber_style = StyleBoxFlat.new()
	grabber_style.bg_color = Color(0.4, 0.4, 0.4, 1.0)
	
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

func set_external_container_list(external_list: ItemList):
	external_container_list = external_list
	using_external_container_list = true
	
	# If the content is already set up, we need to reconnect signals
	if external_list:
		container_list = external_list  # Use the external list as our container_list reference

# Modified _setup_content method
func _setup_content():
	print("Setting up InventoryWindowContent...")
	if using_external_container_list:
		# Only setup right panel since left panel is handled externally
		_setup_right_panel_only()
	else:
		# Setup both panels
		_setup_left_panel()
		_setup_right_panel()
	print("InventoryWindowContent setup completed")

func _setup_left_panel():
	print("Setting up left panel...")
	var left_panel = VBoxContainer.new()
	left_panel.name = "LeftPanel"
	left_panel.custom_minimum_size.x = 180
	left_panel.size_flags_horizontal = Control.SIZE_FILL
	
	add_child(left_panel)
	
	container_list = ItemList.new()
	container_list.name = "ContainerList"
	container_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container_list.custom_minimum_size = Vector2(160, 200)
	container_list.auto_height = true
	container_list.allow_rmb_select = false
	
	# Set up drop detection on container list
	container_list.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Add padding for items inside the container list
	container_list.add_theme_constant_override("h_separation", 4)
	container_list.add_theme_constant_override("v_separation", 2)
	container_list.add_theme_constant_override("item_h_separation", 4)
	container_list.add_theme_constant_override("item_v_separation", 2)
	
	# Keep normal dark background for container list
	var list_style = StyleBoxFlat.new()
	list_style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	list_style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	list_style.border_width_left = 1
	list_style.border_width_right = 1
	list_style.border_width_top = 1
	list_style.border_width_bottom = 1
	list_style.content_margin_left = 6
	list_style.content_margin_right = 6
	list_style.content_margin_top = 4
	list_style.content_margin_bottom = 4
	container_list.add_theme_stylebox_override("panel", list_style)
	
	left_panel.add_child(container_list)
	
	container_list.item_selected.connect(_on_container_list_selected)
	container_list.gui_input.connect(_on_container_list_input)
	
	# Set up drop area handling
	_setup_container_drop_handling()
	print("Left panel setup completed")

func _setup_right_panel_only():
	print("Setting up right panel only...")
	# Create the right panel content directly (no HSplitContainer needed)
	var inventory_area = VBoxContainer.new()
	inventory_area.name = "InventoryArea"
	inventory_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_area.add_theme_constant_override("separation", 4)
	add_child(inventory_area)
	
	_setup_mass_info_bar(inventory_area)
	
	var grid_scroll = ScrollContainer.new()
	grid_scroll.name = "GridScrollContainer"
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	grid_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	inventory_area.add_child(grid_scroll)
	
	inventory_grid = InventoryGrid.new()
	inventory_grid.name = "InventoryGrid"
	inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.add_child(inventory_grid)
	
	# Connect grid signals properly
	inventory_grid.item_activated.connect(_on_item_activated)
	inventory_grid.item_context_menu.connect(_on_item_context_menu)
	print("Right panel only setup completed")

func _setup_right_panel():
	print("Setting up right panel...")
	var inventory_area = VBoxContainer.new()
	inventory_area.name = "InventoryArea"
	inventory_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_area.add_theme_constant_override("separation", 4)
	add_child(inventory_area)
	
	_setup_mass_info_bar(inventory_area)
	
	var grid_scroll = ScrollContainer.new()
	grid_scroll.name = "GridScrollContainer"
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	grid_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	inventory_area.add_child(grid_scroll)
	
	inventory_grid = InventoryGrid.new()
	inventory_grid.name = "InventoryGrid"
	inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.add_child(inventory_grid)
	
	# Connect grid signals properly
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
	style_box.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	style_box.border_color = Color(0.4, 0.4, 0.4, 1.0)
	style_box.border_width_left = 1
	style_box.border_width_right = 1
	style_box.border_width_top = 1
	style_box.border_width_bottom = 1
	mass_info_bar.add_theme_stylebox_override("panel", style_box)
	
	# Create a margin container for padding inside the mass info bar
	var margin_container = MarginContainer.new()
	margin_container.name = "MassInfoMargin"
	margin_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_left", 8)
	margin_container.add_theme_constant_override("margin_right", 8)
	margin_container.add_theme_constant_override("margin_top", 4)
	margin_container.add_theme_constant_override("margin_bottom", 4)
	mass_info_bar.add_child(margin_container)
	
	mass_info_label = Label.new()
	mass_info_label.name = "MassInfoLabel"
	mass_info_label.text = "No container selected"
	mass_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mass_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mass_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mass_info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mass_info_label.add_theme_color_override("font_color", Color.WHITE)
	mass_info_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	mass_info_label.add_theme_constant_override("shadow_offset_x", 1)
	mass_info_label.add_theme_constant_override("shadow_offset_y", 1)
	mass_info_label.add_theme_font_size_override("font_size", 12)
	
	# Enable text clipping to prevent overflow
	mass_info_label.clip_contents = true
	mass_info_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	mass_info_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	
	margin_container.add_child(mass_info_label)
	print("Mass info bar setup completed")

func _on_container_list_selected(index: int):
	print("Container list item selected: ", index)
	if index >= 0 and index < open_containers.size():
		var selected_container = open_containers[index]
		print("Emitting container_selected for: ", selected_container.container_name)
		container_selected.emit(selected_container)

func _on_item_activated(item: InventoryItem_Base, slot: InventorySlot):
	print("Item activated: ", item.item_name)
	item_activated.emit(item, slot)

func _on_item_context_menu(item: InventoryItem_Base, slot: InventorySlot, position: Vector2):
	print("Item context menu requested for: ", item.item_name)
	item_context_menu.emit(item, slot, position)

# Public interface with debug output
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
		var _total_qty = container.get_total_quantity()
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
	print("InventoryWindowContent.refresh_display() called")
	
	if not inventory_grid:
		print("ERROR: No inventory grid to refresh!")
		return
	
	if not current_container:
		print("WARNING: No current container to display")
		return
	
	print("Refreshing display for container: ", current_container.container_name)
	print("Container has ", current_container.get_item_count(), " items")
	
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

func get_current_container() -> InventoryContainer_Base:
	return current_container

func get_inventory_grid() -> InventoryGrid:
	return inventory_grid

# Debug method
func debug_content_state():
	print("\n=== INVENTORY CONTENT DEBUG ===")
	print("inventory_manager: ", inventory_manager)
	print("current_container: ", current_container)
	print("open_containers count: ", open_containers.size())
	print("inventory_grid: ", inventory_grid)
	print("mass_info_bar: ", mass_info_bar)
	print("mass_info_label: ", mass_info_label)
	print("container_list: ", container_list)
	print("using_external_container_list: ", using_external_container_list)
	
	if inventory_grid:
		print("Grid container: ", inventory_grid.container)
		print("Grid dimensions: ", inventory_grid.grid_width, "x", inventory_grid.grid_height)
	
	print("=== END CONTENT DEBUG ===\n")

# Container drop handling methods
func _setup_container_drop_handling():
	"""Set up the container list to accept drops from inventory slots"""
	if not container_list:
		return
		
	# Create an invisible overlay on the container list to detect drops
	var drop_detector = Control.new()
	drop_detector.name = "ContainerDropDetector"
	drop_detector.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drop_detector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_detector.z_index = 10
	container_list.add_child(drop_detector)

func _process(_delta):
	# Check for ongoing drags and highlight valid drop targets
	if get_viewport().has_meta("current_drag_data"):
		_update_container_drop_highlights()

func _update_container_drop_highlights():
	var drag_data = get_viewport().get_meta("current_drag_data", null)
	if not drag_data or not container_list:
		return
	
	var item = drag_data.get("item") as InventoryItem_Base
	if not item:
		return
	
	var mouse_pos = get_global_mouse_position()
	var container_rect = Rect2(container_list.global_position, container_list.size)
	
	if container_rect.has_point(mouse_pos):
		# Mouse is over container list - highlight valid containers
		for i in range(open_containers.size()):
			var container = open_containers[i]
			if container != current_container and container.can_add_item(item):
				container_list.set_item_custom_bg_color(i, Color.GREEN.darkened(0.5))
			else:
				container_list.set_item_custom_bg_color(i, Color.TRANSPARENT)
	else:
		# Clear all highlights
		for i in range(container_list.get_item_count()):
			container_list.set_item_custom_bg_color(i, Color.TRANSPARENT)

func _gui_input(_event: InputEvent):
	# Handle container list input for drag and drop
	pass

func _on_container_list_input(_event: InputEvent):
	# Handle specific container list input events
	pass

# Transparency handling
func set_transparency(transparency: float):
	# Store originals on first call
	if not content_transparency_init:
		_store_original_content_styles()
		content_transparency_init = true
	
	modulate.a = transparency
	
	# Apply transparency using stored originals
	_apply_content_transparency_from_originals(transparency)

func _store_original_content_styles():
	if mass_info_bar:
		var style = mass_info_bar.get_theme_stylebox("panel")
		if style and style is StyleBoxFlat:
			original_content_styles["mass_panel"] = style.duplicate()

func _apply_content_transparency_from_originals(transparency: float):
	# Apply to mass info bar
	if mass_info_bar and original_content_styles.has("mass_panel"):
		var original = original_content_styles["mass_panel"] as StyleBoxFlat
		var new_style = original.duplicate() as StyleBoxFlat
		var orig_color = original.bg_color
		new_style.bg_color = Color(orig_color.r, orig_color.g, orig_color.b, orig_color.a * transparency)
		mass_info_bar.add_theme_stylebox_override("panel", new_style)
	
	# Apply to inventory grid
	if inventory_grid and inventory_grid.has_method("set_transparency"):
		inventory_grid.set_transparency(transparency)
