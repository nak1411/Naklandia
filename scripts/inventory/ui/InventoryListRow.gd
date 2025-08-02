# InventoryListRow.gd - Individual row in the inventory list view
class_name InventoryListRow
extends Control

var item: InventoryItem_Base
var columns: Array[Dictionary]
var row_height: int
var is_selected: bool = false
var is_hovered: bool = false

var background: Panel
var content_container: HBoxContainer
var cells: Array[Control] = []

# Colors
var normal_color: Color = Color.TRANSPARENT
var alternate_color: Color = Color(0.12, 0.12, 0.12, 1.0)
var selected_color: Color = Color(0.3, 0.4, 0.6, 1.0)
var hover_color: Color = Color(0.2, 0.2, 0.2, 1.0)
var use_alternate: bool = false

# Signals
signal row_clicked(row: InventoryListRow, item: InventoryItem_Base, event: InputEvent)
signal row_double_clicked(row: InventoryListRow, item: InventoryItem_Base)
signal row_right_clicked(row: InventoryListRow, item: InventoryItem_Base, position: Vector2)

func _ready():
	custom_minimum_size.y = row_height
	mouse_filter = Control.MOUSE_FILTER_PASS

func setup(new_item: InventoryItem_Base, new_columns: Array[Dictionary], new_row_height: int):
	item = new_item
	columns = new_columns
	row_height = new_row_height
	
	_setup_ui()
	_populate_cells()

func _setup_ui():
	# Background panel
	background = Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	
	# Content container
	content_container = HBoxContainer.new()
	content_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Apply margins manually
	content_container.offset_left = 4
	content_container.offset_top = 4
	content_container.offset_right = -4
	content_container.offset_bottom = -4
	add_child(content_container)

func _populate_cells():
	# Clear existing cells
	for cell in cells:
		if is_instance_valid(cell):
			cell.queue_free()
	cells.clear()
	
	# Create cells for each column
	for column in columns:
		var cell = _create_cell(column)
		content_container.add_child(cell)
		cells.append(cell)

func _create_cell(column: Dictionary) -> Control:
	var cell = Control.new()
	cell.custom_minimum_size.x = column.width
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL if column.width > 100 else Control.SIZE_SHRINK_CENTER
	
	match column.id:
		"icon":
			var icon = TextureRect.new()
			icon.texture = item.get_icon_texture()  # Changed from item.icon
			icon.custom_minimum_size = Vector2(24, 24)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			cell.add_child(icon)
		
		"name":
			var label = Label.new()
			label.text = item.item_name
			label.set_anchors_preset(Control.PRESET_FULL_RECT)
			label.offset_left = 4
			label.offset_right = -4
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.clip_contents = true
			
			# Color by rarity
			label.add_theme_color_override("font_color", item.get_rarity_color())
			cell.add_child(label)
		
		"quantity":
			var label = Label.new()
			label.text = str(item.quantity)
			label.set_anchors_preset(Control.PRESET_FULL_RECT)
			label.offset_left = 4
			label.offset_right = -4
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cell.add_child(label)
		
		"type":
			var label = Label.new()
			label.text = str(item.item_type).capitalize()
			label.set_anchors_preset(Control.PRESET_FULL_RECT)
			label.offset_left = 4
			label.offset_right = -4
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cell.add_child(label)
		
		"rarity":
			var label = Label.new()
			label.text = str(item.item_rarity).capitalize()
			label.set_anchors_preset(Control.PRESET_FULL_RECT)
			label.offset_left = 4
			label.offset_right = -4
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_color_override("font_color", item.get_rarity_color())
			cell.add_child(label)
		
		"volume":
			var label = Label.new()
			label.text = "%.1f" % item.volume
			label.set_anchors_preset(Control.PRESET_FULL_RECT)
			label.offset_left = 4
			label.offset_right = -4
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cell.add_child(label)
		
		"total_volume":
			var label = Label.new()
			label.text = "%.1f" % (item.volume * item.quantity)
			label.set_anchors_preset(Control.PRESET_FULL_RECT)
			label.offset_left = 4
			label.offset_right = -4
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cell.add_child(label)
	
	return cell

func set_alternate_color(alternate: bool, color: Color):
	use_alternate = alternate
	alternate_color = color
	_update_background()

func set_selected(selected: bool):
	is_selected = selected
	_update_background()

func _update_background():
	if not background:
		return
	
	var color: Color
	if is_selected:
		color = selected_color
	elif is_hovered:
		color = hover_color
	elif use_alternate:
		color = alternate_color
	else:
		color = normal_color
	
	var style = StyleBoxFlat.new()
	style.bg_color = color
	background.add_theme_stylebox_override("panel", style)

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					if event.double_click:
						row_double_clicked.emit(self, item)
					else:
						row_clicked.emit(self, item, event)
				MOUSE_BUTTON_RIGHT:
					row_right_clicked.emit(self, item, event.global_position)

func _mouse_entered():
	is_hovered = true
	_update_background()

func _mouse_exited():
	is_hovered = false
	_update_background()
