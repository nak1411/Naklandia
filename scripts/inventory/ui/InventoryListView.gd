# InventoryListView.gd - List/Detail view for inventory (Eve Online style)
class_name InventoryListView
extends Control

# List properties
@export var row_height: int = 32
@export var header_height: int = 28
@export var detail_panel_width: int = 300
@export var show_details: bool = true

# Visual properties
@export var row_alternate_color: Color = Color(0.12, 0.12, 0.12, 1.0)
@export var row_selected_color: Color = Color(0.3, 0.4, 0.6, 1.0)
@export var row_hover_color: Color = Color(0.2, 0.2, 0.2, 1.0)

# Container reference
var container: InventoryContainer_Base
var container_id: String

# UI components
var main_hsplit: HSplitContainer
var list_panel: Control
var detail_panel: Control
var scroll_container: ScrollContainer
var list_container: VBoxContainer
var header_container: HBoxContainer

# List management
var item_rows: Array[InventoryListRow] = []
var selected_items: Array[InventoryItem_Base] = []
var current_sort_column: String = "name"
var sort_ascending: bool = true
var current_filter_type: int = 0
var current_search_text: String = ""

# Columns configuration
var columns: Array[Dictionary] = [
	{"id": "icon", "title": "", "width": 32, "sortable": false},
	{"id": "name", "title": "Name", "width": 150, "sortable": true},  # Reduced from 200
	{"id": "quantity", "title": "Qty", "width": 50, "sortable": true},  # Reduced from 60
	{"id": "type", "title": "Type", "width": 100, "sortable": true},   # Reduced from 120
	{"id": "volume", "title": "Vol", "width": 60, "sortable": true},   # Reduced and shortened title
	{"id": "total_volume", "title": "Total", "width": 60, "sortable": true} # Reduced from 80
]

# Signals
signal item_selected(item: InventoryItem_Base)
signal item_activated(item: InventoryItem_Base)
signal item_context_menu(item: InventoryItem_Base, position: Vector2)

func _ready():
	_setup_ui()
	resized.connect(_on_resized)

func _setup_ui():
	# Create a simple VBox layout with proper clipping
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.clip_contents = true  # IMPORTANT: Clip the entire list view
	add_child(main_vbox)
	
	# Create header
	_setup_header(main_vbox)
	
	# Create main list area
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # Force no horizontal scrolling
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.clip_contents = true  # Clip scroll content
	main_vbox.add_child(scroll_container)
	
	list_container = VBoxContainer.new()
	list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_container.clip_contents = true  # Clip list items
	scroll_container.add_child(list_container)

func _convert_to_split_layout():
	# Only convert to split layout if we need the detail panel
	# This keeps the simple layout when details aren't needed
	pass  # Implement if you want the detail panel

func _setup_list_panel():
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.clip_contents = true  # Prevent overflow
	list_panel.add_child(vbox)
	
	# Create header
	_setup_header(vbox)
	
	# Create scrollable list
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.clip_contents = true  # Prevent horizontal overflow
	vbox.add_child(scroll_container)
	
	list_container = VBoxContainer.new()
	list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_container.clip_contents = true  # Prevent overflow
	scroll_container.add_child(list_container)

func _setup_header(parent: Control):
	header_container = HBoxContainer.new()
	header_container.custom_minimum_size.y = header_height
	header_container.clip_contents = true  # IMPORTANT: Clip header content
	parent.add_child(header_container)
	
	# Create header background
	var header_bg = Panel.new()
	header_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header_bg.z_index = -1
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08, 1.0)
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	header_bg.add_theme_stylebox_override("panel", style)
	header_container.add_child(header_bg)
	
	# Create column headers with better constraints
	for i in columns.size():
		var column = columns[i]
		var header_button = Button.new()
		header_button.text = column.title
		header_button.flat = true
		header_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header_button.clip_contents = true  # Clip button text
		
		# Set sizing based on column type with minimum constraints
		if column.width <= 100:  # Fixed width columns (icon, qty, etc.)
			header_button.custom_minimum_size.x = max(20, column.width)  # Minimum 20px
			header_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		else:  # Expandable columns (name, type, etc.)
			header_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			header_button.custom_minimum_size.x = 50  # Minimum width for expandable columns
		
		if column.sortable:
			header_button.pressed.connect(_on_header_clicked.bind(column.id))
			# Add sort indicator
			if current_sort_column == column.id:
				header_button.text += " ↑" if sort_ascending else " ↓"
		
		header_container.add_child(header_button)

func _setup_detail_panel():
	if not detail_panel:
		return
	
	var detail_bg = Panel.new()
	detail_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	style.border_width_left = 1
	style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	detail_bg.add_theme_stylebox_override("panel", style)
	detail_panel.add_child(detail_bg)
	
	var detail_scroll = ScrollContainer.new()
	detail_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Apply margins manually instead of using the old parameter
	detail_scroll.position = Vector2(8, 8)
	detail_scroll.size = detail_panel.size - Vector2(16, 16)
	detail_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	detail_scroll.offset_left = 8
	detail_scroll.offset_top = 8
	detail_scroll.offset_right = -8
	detail_scroll.offset_bottom = -8
	detail_panel.add_child(detail_scroll)
	
	var detail_content = InventoryItemDetailPanel.new()
	detail_content.name = "DetailContent"
	detail_scroll.add_child(detail_content)

func set_container(new_container: InventoryContainer_Base, new_container_id: String):	
	# Disconnect from old container - only if signals are actually connected
	if container and is_instance_valid(container):
		if container.item_added.is_connected(_on_container_item_added):
			container.item_added.disconnect(_on_container_item_added)
		if container.item_removed.is_connected(_on_container_item_removed):
			container.item_removed.disconnect(_on_container_item_removed)
		if container.item_moved.is_connected(_on_container_item_moved):
			container.item_moved.disconnect(_on_container_item_moved)
	
	container = new_container
	container_id = new_container_id
	
	# Connect to new container - only if not already connected
	if container and is_instance_valid(container):
		if not container.item_added.is_connected(_on_container_item_added):
			container.item_added.connect(_on_container_item_added)
		if not container.item_removed.is_connected(_on_container_item_removed):
			container.item_removed.connect(_on_container_item_removed)  # Fixed: was disconnect
		if not container.item_moved.is_connected(_on_container_item_moved):
			container.item_moved.connect(_on_container_item_moved)
	
	# Always refresh the display, even if container is null (to clear it)
	refresh_display()

func refresh_display():	
	# Always clear first
	_clear_list()
	
	if not container or not is_instance_valid(container):
		return
	
	# Get filtered and sorted items
	var items = _get_filtered_sorted_items()
	
	# Create rows for items
	for i in items.size():
		var item = items[i]
		var row = InventoryListRow.new()
		row.setup(item, columns, row_height)
		row.set_alternate_color(i % 2 == 1, row_alternate_color)
		
		# Connect row signals
		row.row_clicked.connect(_on_row_clicked)
		row.row_double_clicked.connect(_on_row_double_clicked)
		row.row_right_clicked.connect(_on_row_right_clicked)
		
		list_container.add_child(row)
		item_rows.append(row)
	
func _get_filtered_sorted_items() -> Array[InventoryItem_Base]:
	var items: Array[InventoryItem_Base] = []
	
	# Filter items
	for item in container.items:
		if not _should_show_item(item):
			continue
		items.append(item)
	
	# Sort items - THIS IS VISUAL ONLY, doesn't modify container
	items.sort_custom(_compare_items)
	
	return items

func _should_show_item(item: InventoryItem_Base) -> bool:
	# Apply search filter first
	if not current_search_text.is_empty():
		if not item.item_name.to_lower().contains(current_search_text):
			return false
	
	# Apply type filter
	if current_filter_type == 0:  # All Items
		return true
	
	# Map filter indices to ItemType enum values
	var item_type_filter = _get_item_type_from_filter(current_filter_type)
	return item.item_type == item_type_filter
	
func _get_item_type_from_filter(filter_index: int) -> InventoryItem_Base.ItemType:
	match filter_index:
		1: return InventoryItem_Base.ItemType.WEAPON
		2: return InventoryItem_Base.ItemType.ARMOR
		3: return InventoryItem_Base.ItemType.CONSUMABLE
		4: return InventoryItem_Base.ItemType.RESOURCE
		5: return InventoryItem_Base.ItemType.BLUEPRINT
		6: return InventoryItem_Base.ItemType.MODULE
		7: return InventoryItem_Base.ItemType.SHIP
		8: return InventoryItem_Base.ItemType.CONTAINER
		9: return InventoryItem_Base.ItemType.AMMUNITION
		10: return InventoryItem_Base.ItemType.IMPLANT
		11: return InventoryItem_Base.ItemType.SKILL_BOOK
		_: return InventoryItem_Base.ItemType.MISCELLANEOUS

func _compare_items(a: InventoryItem_Base, b: InventoryItem_Base) -> bool:
	var result: bool = false
	
	match current_sort_column:
		"name":
			result = a.item_name < b.item_name
		"quantity":
			result = a.quantity < b.quantity
		"type":
			result = str(a.item_type) < str(b.item_type)
		"volume":
			result = a.volume < b.volume
		"total_volume":
			result = (a.volume * a.quantity) < (b.volume * b.quantity)
		_:
			result = a.item_name < b.item_name
	
	return result if sort_ascending else not result

func _clear_list():
	for row in item_rows:
		if is_instance_valid(row):
			row.queue_free()
	item_rows.clear()
	selected_items.clear()

func set_search_filter(search_text: String):
	current_search_text = search_text
	refresh_display()

func set_type_filter(filter_type: int):
	current_filter_type = filter_type
	refresh_display()

func toggle_detail_panel():
	show_details = not show_details
	
	if show_details and not detail_panel:
		detail_panel = Control.new()
		detail_panel.name = "DetailPanel"
		detail_panel.custom_minimum_size.x = detail_panel_width
		main_hsplit.add_child(detail_panel)
		_setup_detail_panel()
	elif not show_details and detail_panel:
		detail_panel.queue_free()
		detail_panel = null
	
	main_hsplit.split_offset = int(size.x - detail_panel_width) if show_details else int(size.x)
	
func apply_search(search_text: String):
	"""Apply search filter - matches grid view interface"""
	set_search_filter(search_text)

func apply_filter(filter_type: int):
	"""Apply type filter - matches grid view interface"""
	set_type_filter(filter_type)

# Signal handlers
func _on_header_clicked(column_id: String):
	if current_sort_column == column_id:
		sort_ascending = not sort_ascending
	else:
		current_sort_column = column_id
		sort_ascending = true
	
	# Update header display
	_update_header_sort_indicators()
	refresh_display()

func _update_header_sort_indicators():
	var headers = header_container.get_children()
	for i in range(1, headers.size()):  # Skip background panel
		var header = headers[i]
		if header is Button:
			var column = columns[i-1]
			header.text = column.title
			if column.sortable and current_sort_column == column.id:
				header.text += " ↑" if sort_ascending else " ↓"

func _on_row_clicked(row: InventoryListRow, item: InventoryItem_Base, event: InputEvent):
	if event is InputEventMouseButton:
		if Input.is_action_pressed("ui_select_multi"):
			# Multi-select
			if item in selected_items:
				selected_items.erase(item)
				row.set_selected(false)
			else:
				selected_items.append(item)
				row.set_selected(true)
		else:
			# Single select
			_clear_selection()
			selected_items.append(item)
			row.set_selected(true)
			
			# Update detail panel
			if detail_panel:
				var detail_content = detail_panel.get_node_or_null("ScrollContainer/DetailContent")
				if detail_content and detail_content.has_method("display_item"):
					detail_content.display_item(item)
		
		item_selected.emit(item)

func _on_row_double_clicked(row: InventoryListRow, item: InventoryItem_Base):
	item_activated.emit(item)

func _on_row_right_clicked(row: InventoryListRow, item: InventoryItem_Base, position: Vector2):
	item_context_menu.emit(item, position)

func _clear_selection():
	for row in item_rows:
		row.set_selected(false)
	selected_items.clear()
	
func _on_resized():
	# Recalculate column widths when the view is resized
	call_deferred("_calculate_column_widths")
	call_deferred("_update_header_widths")
	call_deferred("_handle_responsive_columns")
	
func _set_column_visibility(column_id: String, visible: bool):
	"""Show/hide a column by ID"""
	for i in columns.size():
		if columns[i].id == column_id:
			# Find the header button
			if header_container and i + 1 < header_container.get_child_count():
				var header_button = header_container.get_child(i + 1)  # +1 for background
				if header_button:
					header_button.visible = visible
			
			# Update all rows
			for row in item_rows:
				if is_instance_valid(row) and row.cells.size() > i:
					row.cells[i].visible = visible
			break
	
func _handle_responsive_columns():
	"""Hide less important columns when space is very limited"""
	var available_width = size.x
	
	if available_width < 300:  # Very small - hide optional columns
		_set_column_visibility("total_volume", false)
		_set_column_visibility("volume", false)
	elif available_width < 400:  # Small - hide some columns
		_set_column_visibility("total_volume", false)
		_set_column_visibility("volume", false)
	else:  # Normal - show all columns
		_set_column_visibility("total_volume", true)
		_set_column_visibility("volume", true)
	
func _calculate_column_widths():
	if size.x <= 0:
		return  # Not ready yet
		
	var available_width = size.x - 20  # Account for scrollbar and margins
	var fixed_width_total = 0
	var expandable_columns = 0
	
	# Calculate fixed width total
	for column in columns:
		if column.width <= 100:
			fixed_width_total += column.width
		else:
			expandable_columns += 1
	
	# Calculate remaining width for expandable columns
	var remaining_width = available_width - fixed_width_total
	if remaining_width > 0 and expandable_columns > 0:
		var expandable_width = remaining_width / expandable_columns
		
		# Update expandable column widths
		for column in columns:
			if column.width > 100:
				column.width = max(80, expandable_width)  # Minimum 80px
	
	# Refresh the display with new widths
	_update_header_widths()

func _update_header_widths():
	if not header_container:
		return
		
	var headers = header_container.get_children()
	# Skip the background panel (first child)
	for i in range(1, min(headers.size(), columns.size() + 1)):
		var header = headers[i]
		var column = columns[i - 1]
		
		if header is Button:
			if column.width <= 100:  # Fixed width
				header.custom_minimum_size.x = column.width
				header.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			else:  # Expandable
				header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				header.clip_contents = true

func _on_container_item_added(item: InventoryItem_Base, position: Vector2i):
	if container and is_instance_valid(container):
		refresh_display()

func _on_container_item_removed(item: InventoryItem_Base, position: Vector2i):
	if container and is_instance_valid(container):
		refresh_display()

func _on_container_item_moved(item: InventoryItem_Base, old_position: Vector2i, new_position: Vector2i):
	if container and is_instance_valid(container):
		refresh_display()
		
func _is_connected_to_container() -> bool:
	return container and container.item_added.is_connected(_on_container_item_added)

func _connect_container_signals():
	if container and not _is_connected_to_container():
		container.item_added.connect(_on_container_item_added)
		container.item_removed.connect(_on_container_item_removed)
		container.item_moved.connect(_on_container_item_moved)

func _disconnect_container_signals():
	if container and _is_connected_to_container():
		if container.item_added.is_connected(_on_container_item_added):
			container.item_added.disconnect(_on_container_item_added)
		if container.item_removed.is_connected(_on_container_item_removed):
			container.item_removed.disconnect(_on_container_item_removed)
		if container.item_moved.is_connected(_on_container_item_moved):
			container.item_moved.disconnect(_on_container_item_moved)
