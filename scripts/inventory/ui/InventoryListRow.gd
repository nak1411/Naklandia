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
	
	# Content container with proper sizing
	content_container = HBoxContainer.new()
	content_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_container.offset_left = 4
	content_container.offset_top = 2
	content_container.offset_right = -4
	content_container.offset_bottom = -2
	content_container.clip_contents = true
	content_container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let clicks pass through
	add_child(content_container)
	
	# CRITICAL: Add invisible button overlay to capture ALL clicks
	var click_overlay = Button.new()
	click_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_overlay.flat = true
	click_overlay.modulate = Color.TRANSPARENT  # Make it invisible
	click_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Connect button signals to our row signals
	click_overlay.gui_input.connect(_on_overlay_input)
	click_overlay.mouse_entered.connect(_mouse_entered)
	click_overlay.mouse_exited.connect(_mouse_exited)
	
	add_child(click_overlay)

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
	cell.clip_contents = true  # IMPORTANT: Prevent overflow
	
	# Set sizing with absolute minimums
	if column.width <= 100:  # Fixed width columns
		cell.custom_minimum_size.x = max(16, column.width)  # Absolute minimum 16px
		cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	else:  # Expandable columns
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.custom_minimum_size.x = 30  # Minimum 30px for expandable
	
	match column.id:
		"icon":
			var icon = TextureRect.new()
			var texture = item.get_icon_texture()
			if texture:
				icon.texture = texture
			else:
				# Create a very small fallback colored square
				var fallback_image = Image.create(16, 16, false, Image.FORMAT_RGB8)
				fallback_image.fill(item.get_type_color())
				var fallback_texture = ImageTexture.new()
				fallback_texture.set_image(fallback_image)
				icon.texture = fallback_texture
			
			icon.custom_minimum_size = Vector2(16, 16)  # Very small icon
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			cell.add_child(icon)
		
		"name":
			var label = Label.new()
			label.text = item.item_name
			label.set_anchors_preset(Control.PRESET_FULL_RECT)
			label.offset_left = 2  # Reduced padding
			label.offset_right = -2
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.clip_contents = true
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			label.add_theme_font_size_override("font_size", 11)  # Smaller font
			label.add_theme_color_override("font_color", item.get_rarity_color())
			cell.add_child(label)
		
		"quantity":
			var label = Label.new()
			# Shorten quantity display for very small spaces
			var qty_text = str(item.quantity)
			if item.quantity >= 1000:
				qty_text = "%.1fk" % (item.quantity / 1000.0)
			label.text = qty_text
			label.set_anchors_preset(Control.PRESET_FULL_RECT)
			label.offset_left = 1
			label.offset_right = -1
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.clip_contents = true
			label.add_theme_font_size_override("font_size", 10)  # Smaller font
			cell.add_child(label)
		
		"type":
			var label = Label.new()
			# Use abbreviations for type in small spaces
			var type_text = _get_short_type_name(str(item.item_type))
			label.text = type_text
			label.set_anchors_preset(Control.PRESET_FULL_RECT)
			label.offset_left = 2
			label.offset_right = -2
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.clip_contents = true
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			label.add_theme_font_size_override("font_size", 10)
			cell.add_child(label)
		
		"rarity":
			var label = Label.new()
			# Use single letter for rarity in small spaces
			var rarity_text = _get_short_rarity_name(str(item.item_rarity))
			label.text = rarity_text
			label.set_anchors_preset(Control.PRESET_FULL_RECT)
			label.offset_left = 2
			label.offset_right = -2
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_color_override("font_color", item.get_rarity_color())
			label.clip_contents = true
			label.add_theme_font_size_override("font_size", 10)
			cell.add_child(label)
		
		"volume":
			var label = Label.new()
			var vol_text = "%.1f" % item.volume
			if item.volume >= 1000:
				vol_text = "%.1fk" % (item.volume / 1000.0)
			label.text = vol_text
			label.set_anchors_preset(Control.PRESET_FULL_RECT)
			label.offset_left = 1
			label.offset_right = -1
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.clip_contents = true
			label.add_theme_font_size_override("font_size", 9)
			cell.add_child(label)
		
		"total_volume":
			var label = Label.new()
			var total_vol = item.volume * item.quantity
			var total_text = "%.1f" % total_vol
			if total_vol >= 1000:
				total_text = "%.1fk" % (total_vol / 1000.0)
			label.text = total_text
			label.set_anchors_preset(Control.PRESET_FULL_RECT)
			label.offset_left = 1
			label.offset_right = -1
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.clip_contents = true
			label.add_theme_font_size_override("font_size", 9)
			cell.add_child(label)
	
	return cell
	
func _get_short_type_name(type_name: String) -> String:
	match type_name.to_upper():
		"WEAPON":
			return "Wpn"
		"ARMOR":
			return "Arm"
		"CONSUMABLE":
			return "Con"
		"RESOURCE":
			return "Res"
		"BLUEPRINT":
			return "BP"
		"MODULE":
			return "Mod"
		"SHIP":
			return "Ship"
		"CONTAINER":
			return "Box"
		"AMMUNITION":
			return "Ammo"
		"IMPLANT":
			return "Imp"
		"SKILL_BOOK":
			return "Book"
		_:
			return type_name.substr(0, 3)

func _get_short_rarity_name(rarity_name: String) -> String:
	match rarity_name.to_upper():
		"COMMON":
			return "C"
		"UNCOMMON":
			return "U"
		"RARE":
			return "R"
		"EPIC":
			return "E"
		"LEGENDARY":
			return "L"
		"ARTIFACT":
			return "A"
		_:
			return rarity_name.substr(0, 1)

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

func _on_overlay_input(event: InputEvent):
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
