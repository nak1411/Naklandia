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
	{"id": "icon", "title": "", "width": 40, "sortable": false},
	{"id": "name", "title": "Name", "width": 200, "sortable": true},
	{"id": "quantity", "title": "Qty", "width": 60, "sortable": true},
	{"id": "type", "title": "Type", "width": 120, "sortable": true},
	{"id": "rarity", "title": "Rarity", "width": 80, "sortable": true},
	{"id": "volume", "title": "Volume", "width": 80, "sortable": true},
	{"id": "total_volume", "title": "Total Vol", "width": 80, "sortable": true}
]

# Signals
signal item_selected(item: InventoryItem_Base)
signal item_activated(item: InventoryItem_Base)
signal item_context_menu(item: InventoryItem_Base, position: Vector2)

func _ready():
	_setup_ui()

func _setup_ui():
	# Create main horizontal split
	main_hsplit = HSplitContainer.new()
	main_hsplit.name = "MainHSplit"
	main_hsplit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_hsplit.split_offset = size.x - detail_panel_width if show_details else size.x
	add_child(main_hsplit)
	
	# Create list panel
	list_panel = Control.new()
	list_panel.name = "ListPanel"
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hsplit.add_child(list_panel)
	
	# Create detail panel
	if show_details:
		detail_panel = Control.new()
		detail_panel.name = "DetailPanel"
		detail_panel.custom_minimum_size.x = detail_panel_width
		main_hsplit.add_child(detail_panel)
		_setup_detail_panel()
	
	_setup_list_panel()

func _setup_list_panel():
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	list_panel.add_child(vbox)
	
	# Create header
	_setup_header(vbox)
	
	# Create scrollable list
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll_container)
	
	list_container = VBoxContainer.new()
	list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(list_container)

func _setup_header(parent: Control):
	header_container = HBoxContainer.new()
	header_container.custom_minimum_size.y = header_height
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
	
	# Create column headers
	for column in columns:
		var header_button = Button.new()
		header_button.text = column.title
		header_button.custom_minimum_size.x = column.width
		header_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if column.width > 100 else Control.SIZE_SHRINK_CENTER
		header_button.flat = true
		header_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
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
	container = new_container
	container_id = new_container_id
	
	if container:
		# Connect container signals
		if not container.item_added.is_connected(_on_container_item_added):
			container.item_added.connect(_on_container_item_added)
		if not container.item_removed.is_connected(_on_container_item_removed):
			container.item_removed.connect(_on_container_item_removed)
		if not container.item_moved.is_connected(_on_container_item_moved):
			container.item_moved.connect(_on_container_item_moved)
	
	refresh_display()

func refresh_display():
	if not container:
		_clear_list()
		return
	
	_clear_list()
	
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
	
	# Sort items
	items.sort_custom(_compare_items)
	
	return items

func _should_show_item(item: InventoryItem_Base) -> bool:
	# Apply search filter
	if current_search_text.length() > 0:
		if not item.item_name.to_lower().contains(current_search_text.to_lower()):
			return false
	
	# Apply type filter
	if current_filter_type > 0:
		# Implement type filtering based on your item type system
		pass
	
	return true

func _compare_items(a: InventoryItem_Base, b: InventoryItem_Base) -> bool:
	var result: bool = false
	
	match current_sort_column:
		"name":
			result = a.item_name < b.item_name
		"quantity":
			result = a.quantity < b.quantity
		"type":
			result = str(a.item_type) < str(b.item_type)
		"rarity":
			result = a.item_rarity < b.item_rarity
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
	
	main_hsplit.split_offset = size.x - detail_panel_width if show_details else size.x

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

func _on_container_item_added(item: InventoryItem_Base, position: Vector2i):
	refresh_display()

func _on_container_item_removed(item: InventoryItem_Base, position: Vector2i):
	refresh_display()

func _on_container_item_moved(item: InventoryItem_Base, old_position: Vector2i, new_position: Vector2i):
	refresh_display()
