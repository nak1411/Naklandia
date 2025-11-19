# InventoryListRow.gd - Individual row in the inventory list view
class_name ListRowManager
extends Control

# Signals
signal row_clicked(row: ListRowManager, item: InventoryItem_Base, event: InputEvent)
signal row_right_clicked(row: ListRowManager, item: InventoryItem_Base, position: Vector2)
signal item_drag_started(row: ListRowManager, item: InventoryItem_Base)
signal item_drag_ended(row: ListRowManager, success: bool)

var item: InventoryItem_Base
var columns: Array[Dictionary]
var row_height: int
var is_selected: bool = false
var is_hovered: bool = false
var is_dragging: bool = false
var drag_start_position: Vector2
var drag_threshold: float = 5.0
var drag_preview_created: bool = false

var tooltip_manager: ListRowTooltipManager

var background: Panel
var content_container: GridContainer
var cells: Array[Control] = []
var hover_overlay: Panel

# Colors
var normal_color: Color = Color.TRANSPARENT
var alternate_color: Color = Color(0.12, 0.12, 0.12, 1.0)
var selected_color: Color = Color(0.3, 0.4, 0.6, 1.0)
var hover_color: Color = Color(0.2, 0.2, 0.2, 1.0)
var use_alternate: bool = false
var hover_tween: Tween


func _ready():
	custom_minimum_size.y = row_height
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(true)


func setup(new_item: InventoryItem_Base, new_columns: Array[Dictionary], new_row_height: int):
	item = new_item
	columns = new_columns
	row_height = new_row_height

	_setup_ui()
	_populate_cells()
	call_deferred("_setup_tooltip_manager")


func _setup_tooltip_manager():
	"""Setup tooltip manager after row is fully in scene tree"""
	tooltip_manager = ListRowTooltipManager.new(self)
	if tooltip_manager:
		tooltip_manager.setup_tooltip()


func _process(delta):
	# Handle tooltip delay
	if tooltip_manager:
		tooltip_manager.process_tooltip_timer(delta)


func _setup_ui():
	# Background panel
	background = Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_setup_hover_overlay()

	# Content container using GridContainer
	content_container = GridContainer.new()
	content_container.columns = columns.size()
	content_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_container.offset_left = 0
	content_container.offset_top = 0
	content_container.offset_right = 0
	content_container.offset_bottom = 0
	content_container.add_theme_constant_override("h_separation", 1)
	content_container.add_theme_constant_override("v_separation", 0)
	content_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content_container)

	# Add invisible button overlay for clicks
	var click_overlay = Button.new()
	click_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_overlay.flat = true
	click_overlay.modulate = Color.TRANSPARENT
	click_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
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


# Replace the icon creation part in the _create_cell function with this:
func _create_cell(column: Dictionary) -> Control:
	var cell = Panel.new()
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.custom_minimum_size.y = row_height

	# Set sizing to match header exactly
	if column.id == "name":
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.custom_minimum_size.x = 100
	else:
		cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.custom_minimum_size.x = column.width

	# Style the cell with subtle borders
	var style = StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_width_right = 1
	style.border_color = Color(0.2, 0.2, 0.2, 0.5)
	cell.add_theme_stylebox_override("panel", style)

	# Add content based on column type
	match column.id:
		"name":
			# Create horizontal container for icon + name
			var hbox = HBoxContainer.new()
			hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			hbox.offset_left = 4
			hbox.offset_right = -4
			hbox.add_theme_constant_override("separation", 6)
			cell.add_child(hbox)

			# Create icon container - no clipping, just size constraint
			var icon_container = Control.new()
			icon_container.size = Vector2(18, 18)
			icon_container.custom_minimum_size = Vector2(18, 18)
			icon_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			icon_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			# NO clip_contents = true - we want scaling, not clipping
			hbox.add_child(icon_container)

			# Create icon with proper scaling
			var icon = TextureRect.new()
			var texture = item.get_icon_texture()
			if texture:
				icon.texture = texture
			else:
				var fallback_image = Image.create(18, 18, false, Image.FORMAT_RGB8)
				fallback_image.fill(item.get_type_color())
				var fallback_texture = ImageTexture.new()
				fallback_texture.set_image(fallback_image)
				icon.texture = fallback_texture

			# FIXED: Use anchors and proper stretch mode for scaling
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_container.add_child(icon)

			# Add name label
			var label = Label.new()
			label.text = item.item_name
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			label.clip_contents = true
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			label.add_theme_font_size_override("font_size", 12)
			hbox.add_child(label)

		# Rest of columns remain the same...
		"quantity":
			var label = Label.new()
			label.text = str(item.quantity) + " "
			label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.add_theme_font_size_override("font_size", 12)
			cell.add_child(label)

		"type":
			var label = Label.new()
			label.text = ItemTypes.get_type_name(item.item_type)  # ← NEW
			label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			label.offset_left = 4
			label.offset_right = -4
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.clip_contents = true
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			label.add_theme_font_size_override("font_size", 12)
			cell.add_child(label)

		"volume":
			var label = Label.new()
			var total_volume = item.volume * item.quantity
			label.text = "%.1f " % total_volume
			label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.add_theme_font_size_override("font_size", 12)
			cell.add_child(label)

		"base_value":
			var label = Label.new()
			var total_value = item.base_value * item.quantity
			label.text = _format_currency(total_value)
			label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.add_theme_font_size_override("font_size", 12)
			cell.add_child(label)

	return cell


func _format_currency(value: float) -> String:
	return InventoryMath.format_currency(value)


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


func set_alternate_color(alternate: bool, color: Color):
	use_alternate = alternate
	alternate_color = color
	_update_background()


func set_selected(selected: bool):
	is_selected = selected

	# Kill any running hover animations immediately
	if hover_tween and hover_tween.is_valid():
		hover_tween.kill()
		hover_tween = null

	# Force immediate background and overlay update
	_update_background()

	# Critical: Properly manage hover overlay when selection changes
	if hover_overlay:
		if is_selected:
			# When selected, hide hover overlay completely
			hover_overlay.modulate.a = 0.0
		elif is_hovered:
			# If still hovered but not selected, show hover overlay
			hover_overlay.modulate.a = 0.3
		else:
			# Not selected and not hovered, hide overlay
			hover_overlay.modulate.a = 0.0


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

	_update_background_color(color)


func _mouse_entered():
	is_hovered = true
	_animate_hover_in()
	if item and tooltip_manager:
		tooltip_manager.start_tooltip_timer()


func _mouse_exited():
	is_hovered = false
	_animate_hover_out()
	if tooltip_manager:
		tooltip_manager.hide_tooltip()


func _update_background_color(color: Color):
	if not background:
		return

	var style = StyleBoxFlat.new()
	style.bg_color = color
	background.add_theme_stylebox_override("panel", style)


func _get_current_background_color() -> Color:
	if not background:
		return Color.TRANSPARENT

	var style = background.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		return style.bg_color

	return Color.TRANSPARENT


func _animate_hover_in():
	if hover_tween:
		hover_tween.kill()

	if is_selected:
		return

	hover_tween = create_tween()
	hover_tween.set_parallel(true)

	# Subtle fade in the hover overlay
	hover_tween.tween_property(hover_overlay, "modulate:a", 0.3, 0.12)
	hover_tween.tween_property(self, "scale", Vector2(0.998, 1.0), 0.1)


# Replace the _animate_hover_out function
func _animate_hover_out():
	if hover_tween:
		hover_tween.kill()

	if is_selected:
		return

	hover_tween = create_tween()
	hover_tween.set_parallel(true)

	# Subtle fade out the hover overlay
	hover_tween.tween_property(hover_overlay, "modulate:a", 0.0, 0.08)
	hover_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)


func _setup_hover_overlay():
	hover_overlay = Panel.new()
	hover_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hover_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_overlay.modulate.a = 0.0  # Start invisible

	var style = StyleBoxFlat.new()
	# Brighter hover color - lighter and more saturated
	style.bg_color = Color(0.5, 0.8, 1.0, 1.0)  # Increased from the original hover_color
	hover_overlay.add_theme_stylebox_override("panel", style)

	add_child(hover_overlay)


func _on_overlay_input(event: InputEvent):
	"""Enhanced input handling with drag and drop support"""
	if not item:
		return

	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton

		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# Start potential drag
				drag_start_position = mouse_event.global_position
				is_dragging = false
				drag_preview_created = false
			else:
				# Mouse released
				if is_dragging:
					_end_drag()
				else:
					# Regular click
					row_clicked.emit(self, item, event)

		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			row_right_clicked.emit(self, item, mouse_event.global_position)

	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if not is_dragging and drag_start_position != Vector2.ZERO:
			var distance = event.global_position.distance_to(drag_start_position)
			if distance > drag_threshold:
				# Check if shift is held and item can be split
				if Input.is_key_pressed(KEY_SHIFT) and item.quantity > 1:
					var inventory_window = _find_inventory_window()
					if inventory_window and inventory_window.item_actions:
						# Create a temporary slot for compatibility with the dialog
						var temp_slot = InventorySlot.new()
						temp_slot.set_item(item)
						temp_slot.set_container_id(_get_container_id())
						inventory_window.item_actions.show_split_stack_dialog(item, temp_slot)
						is_dragging = false
						drag_preview_created = false
						drag_start_position = Vector2.ZERO
					return
				_start_drag()


# Add these drag and drop methods
func _start_drag():
	"""Start dragging this list row item"""
	if not item or is_dragging:
		return

	is_dragging = true
	drag_preview_created = false

	# Store drag data globally for compatibility with container drops
	var drag_data = {
		"source_row": self,
		"item": item,
		"container_id": _get_container_id(),
		"partial_transfer": Input.is_key_pressed(KEY_SHIFT) and item.quantity > 1,
		"success_callback": _on_external_drop_result
	}

	get_viewport().set_meta("current_drag_data", drag_data)

	# Create drag preview
	var preview = _create_drag_preview()

	# Create canvas layer for preview
	var drag_canvas = CanvasLayer.new()
	drag_canvas.name = "DragCanvas"
	drag_canvas.layer = 200
	get_tree().root.add_child(drag_canvas)
	drag_canvas.add_child(preview)

	preview.set_meta("drag_canvas", drag_canvas)

	# Add partial transfer indicator if needed
	if drag_data.partial_transfer:
		_add_partial_transfer_indicator(preview)

	# Start following mouse
	_follow_mouse(preview)

	# FIXED: Use background color change instead of modulate for visual feedback
	_update_background_color_with_alpha(0.6)  # Fade the background instead of the whole row

	# Emit signal
	item_drag_started.emit(self, item)


func _create_drag_preview() -> Control:
	"""Create a simple item icon preview for dragging"""
	var preview = Control.new()
	preview.name = "DragPreview"
	preview.size = Vector2(32, 32)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Try to get the texture
	var texture: Texture2D = item.get_icon_texture()

	if texture:
		# Use the actual item icon
		var icon = TextureRect.new()
		icon.texture = texture
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.add_child(icon)
	else:
		# Create a colored fallback like the slot does
		var fallback = ColorRect.new()
		fallback.color = item.get_type_color()
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview.add_child(fallback)

		# Add item type text as identifier
		var label = Label.new()
		label.text = item.item_name.substr(0, 3).to_upper()
		label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 8)
		label.add_theme_color_override("font_color", Color.WHITE)
		preview.add_child(label)

	# Quantity badge
	if item.quantity > 1:
		var qty_label = Label.new()
		qty_label.text = str(item.quantity)
		qty_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		qty_label.offset_left = -12
		qty_label.offset_top = -12
		qty_label.add_theme_font_size_override("font_size", 8)
		qty_label.add_theme_color_override("font_color", Color.WHITE)
		qty_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		qty_label.add_theme_constant_override("shadow_offset_x", 1)
		qty_label.add_theme_constant_override("shadow_offset_y", 1)
		preview.add_child(qty_label)

	return preview


func _add_preview_icon(container: HBoxContainer):
	"""Add icon to drag preview"""
	var icon_cell = Control.new()
	icon_cell.custom_minimum_size.x = 20
	icon_cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var icon = TextureRect.new()
	icon.texture = item.get_icon_texture()
	icon.custom_minimum_size = Vector2(16, 16)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	icon_cell.add_child(icon)

	container.add_child(icon_cell)


func _add_preview_name(container: HBoxContainer):
	"""Add name to drag preview"""
	var name_cell = Control.new()
	name_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label = Label.new()
	label.text = item.item_name
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 4
	label.offset_right = -4
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_contents = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color.WHITE)
	name_cell.add_child(label)

	container.add_child(name_cell)


func _add_preview_quantity(container: HBoxContainer):
	"""Add quantity to drag preview"""
	var qty_cell = Control.new()
	qty_cell.custom_minimum_size.x = 40
	qty_cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var label = Label.new()
	var qty_text = str(item.quantity)
	if item.quantity >= 1000:
		qty_text = "%.1fk" % (item.quantity / 1000.0)
	label.text = qty_text
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 10)
	qty_cell.add_child(label)

	container.add_child(qty_cell)


func _add_partial_transfer_indicator(preview: Control):
	"""Add visual indicator for partial transfer"""
	var indicator = Label.new()
	indicator.text = "½"
	indicator.position = Vector2(preview.size.x - 15, -5)
	indicator.size = Vector2(12, 12)
	indicator.add_theme_font_size_override("font_size", 10)
	indicator.add_theme_color_override("font_color", Color.YELLOW)
	indicator.add_theme_color_override("font_shadow_color", Color.BLACK)
	preview.add_child(indicator)


func _follow_mouse(preview: Control):
	"""Make the preview follow the mouse cursor"""
	# Start a continuous update using a Timer instead of Tween
	var timer = Timer.new()
	timer.wait_time = 0.016  # ~60 FPS
	timer.timeout.connect(_update_preview_position.bind(preview, timer))
	preview.add_child(timer)
	timer.start()

	# Set initial position
	_update_preview_position(preview, timer)


func _update_preview_position(preview: Control, timer: Timer):
	"""Update preview position to follow mouse"""
	if not is_instance_valid(preview) or not is_dragging:
		if is_instance_valid(timer):
			timer.queue_free()
		return

	var mouse_pos = get_global_mouse_position()
	preview.global_position = mouse_pos + Vector2(10, -preview.size.y * 0.5)  # Offset slightly from cursor


func _attempt_drop_on_inventory(end_position: Vector2) -> bool:
	"""Try to drop on inventory grid slots"""
	var content = _find_inventory_content()
	if not content:
		return false

	var inventory_grid = content.get_inventory_grid()
	if not inventory_grid:
		return false

	# Check if drop position is over the inventory grid
	var grid_rect = Rect2(inventory_grid.global_position, inventory_grid.size)
	if not grid_rect.has_point(end_position):
		return false

	# Find slot at drop position
	var target_slot = inventory_grid.get_slot_at_position(end_position)
	if target_slot:
		# Drop on specific slot
		return _handle_drop_on_slot(target_slot)

	# Drop on empty grid area
	return _handle_drop_on_empty_grid(inventory_grid, end_position)


func _attempt_drop_on_container_list(end_position: Vector2) -> bool:
	"""Try to drop on container list"""
	var content = _find_inventory_content()
	if not content or not content.container_list:
		return false

	var container_list = content.container_list
	var container_rect = Rect2(container_list.global_position, container_list.size)

	if not container_rect.has_point(end_position):
		return false

	var local_pos = end_position - container_list.global_position
	var item_index = container_list.get_item_at_position(local_pos, true)

	if item_index == -1 or item_index >= content.open_containers.size():
		return false

	var target_container = content.open_containers[item_index]
	var current_container_id = _get_container_id()

	if target_container.container_id == current_container_id:
		return false

	var inventory_manager = _get_inventory_manager()
	if not inventory_manager:
		return false

	# Determine transfer quantity
	var transfer_quantity = item.quantity
	if Input.is_key_pressed(KEY_SHIFT) and item.quantity > 1:
		transfer_quantity = max(1, int(item.quantity / 2.0))  # Transfer half

	# Perform transfer
	var success = inventory_manager.transfer_item(
		item,
		current_container_id,
		target_container.container_id,
		Vector2i(-1, -1),
		transfer_quantity
	)

	if success:
		# Refresh displays
		content.refresh_display()
		return true

	return false


func _attempt_drop_on_equipment_slots(end_position: Vector2) -> bool:
	"""Try to drop on equipment slots or equipment window (character preview panel)"""
	if not item:
		return false

	# First, check if dropping on the equipment window itself
	var equipment_window = get_tree().get_first_node_in_group("equipment_window")
	if equipment_window and is_instance_valid(equipment_window):
		if equipment_window.visible and equipment_window.is_inside_tree():
			var window_rect = Rect2(equipment_window.global_position, equipment_window.size)
			if window_rect.has_point(end_position):
				print("ListRowManager: Drop is on equipment window - checking if it can handle it")

				# Set drag data on viewport so EquipmentWindow can access it
				var window_drag_data = {
					"item": item, "source_row": self, "container_id": _get_container_id()
				}

				get_viewport().set_meta("current_drag_data", window_drag_data)

				# Let the EquipmentWindow handle the drop
				# It will check for character preview panel and auto-equip
				if equipment_window.has_method("_handle_equipment_drop"):
					var handled = equipment_window._handle_equipment_drop(
						window_drag_data, end_position
					)

					# Clean up drag data
					get_viewport().remove_meta("current_drag_data")

					if handled:
						print("ListRowManager: Equipment window handled the drop")
						# Refresh the list view
						var list_view = _find_list_view()
						if list_view:
							list_view.refresh_display()
						return true

	# If not handled by equipment window, check individual equipment slots
	var equipment_slots = get_tree().get_nodes_in_group("equipment_slots")
	if equipment_slots.is_empty():
		return false

	var slot_drag_data = {"item": item, "source_row": self, "container_id": _get_container_id()}

	# Check each equipment slot
	for equipment_slot in equipment_slots:
		if not is_instance_valid(equipment_slot):
			continue

		if not equipment_slot.visible or not equipment_slot.is_inside_tree():
			continue

		# Check if drop position is within this equipment slot's bounds
		var slot_rect = Rect2(equipment_slot.global_position, equipment_slot.size)
		if slot_rect.has_point(end_position):
			print("ListRowManager: Found equipment slot at drop position: ", equipment_slot.name)

			# Check if the item can be equipped
			if not equipment_slot.can_drop_data(end_position, slot_drag_data):
				print("ListRowManager: Equipment slot rejected the item")
				continue

			# Perform the drop
			equipment_slot.drop_data(end_position, slot_drag_data)
			print("ListRowManager: Item drop handled by equipment slot")

			# Remove item from source container
			var inventory_manager = _get_inventory_manager()
			if inventory_manager:
				var source_container = inventory_manager.get_container(_get_container_id())
				if source_container:
					source_container.remove_item(item)

					# Refresh the list view
					var list_view = _find_list_view()
					if list_view:
						list_view.refresh_display()

			return true

	return false


func _handle_drop_on_slot(target_slot: InventorySlot) -> bool:
	"""Handle dropping on a specific inventory slot"""
	var inventory_manager = _get_inventory_manager()
	if not inventory_manager:
		return false

	var current_container_id = _get_container_id()
	var target_container_id = target_slot.get_container_id()

	if target_slot.has_item():
		var target_item = target_slot.get_item()

		# Try stacking
		if item.can_stack_with(target_item):
			var space_available = target_item.max_stack_size - target_item.quantity
			var amount_to_transfer = min(item.quantity, space_available)

			if amount_to_transfer > 0:
				var success = inventory_manager.transfer_item(
					item,
					current_container_id,
					target_container_id,
					Vector2i(-1, -1),
					amount_to_transfer
				)
				return success

		# Try swapping (same container only)
		if current_container_id == target_container_id:
			# Create temporary slots for swap
			var temp_source_slot = InventorySlot.new()
			temp_source_slot.set_item(item)
			temp_source_slot.set_container_id(current_container_id)

			return temp_source_slot._handle_item_swap(target_slot, target_item)
	else:
		# Empty slot - transfer item
		var success = inventory_manager.transfer_item(
			item, current_container_id, target_container_id
		)
		return success

	return false


func _handle_drop_on_empty_grid(grid: InventoryGrid, _position: Vector2) -> bool:
	"""Handle dropping on empty grid area"""
	var inventory_manager = _get_inventory_manager()
	if not inventory_manager:
		return false

	var current_container_id = _get_container_id()
	var grid_container_id = grid.container_id

	if current_container_id == grid_container_id:
		return false  # Same container, no need to move

	# Transfer to target container
	var success = inventory_manager.transfer_item(item, current_container_id, grid_container_id)
	return success


func _on_external_drop_result(success: bool):
	"""Callback for external drop operations"""
	if success:
		# Reset visual state immediately
		modulate.a = 1.0
		is_dragging = false
		drag_preview_created = false
		_set_merge_highlight(false)
		mouse_filter = Control.MOUSE_FILTER_PASS  # Re-enable interaction

		# Clean up any remaining drag state
		var viewport = get_viewport()
		if viewport and viewport.has_meta("current_drag_data"):
			viewport.remove_meta("current_drag_data")

		# Check if this row represents an empty item (quantity <= 0)
		if item and item.quantity <= 0:
			# This row should be removed, make it invisible and disable interaction
			modulate.a = 0.0
			mouse_filter = Control.MOUSE_FILTER_IGNORE

			# Trigger a deferred refresh to clean up properly
			var list_view = _find_list_view()
			if list_view:
				call_deferred("_trigger_list_refresh", list_view)
		elif item:
			# Partial transfer - update the quantity display immediately
			_refresh_display()


# Helper methods
func _get_container_id() -> String:
	var list_view = _find_list_view()
	if list_view:
		return list_view.container_id
	return ""


func _find_inventory_window():
	"""Find the InventoryWindow in the scene tree"""
	var current = get_parent()
	while current:
		if current.get_script() and current.get_script().get_global_name() == "InventoryWindow":
			return current
		current = current.get_parent()
	return null


func _get_inventory_manager() -> InventoryManager:
	var scene_root = get_tree().current_scene
	return _find_inventory_manager_recursive(scene_root)


func _find_inventory_manager_recursive(node: Node) -> InventoryManager:
	if node is InventoryManager:
		return node

	for child in node.get_children():
		var result = _find_inventory_manager_recursive(child)
		if result:
			return result

	return null


func _find_inventory_content() -> InventoryWindowContent:
	var current = get_parent()
	while current:
		if (
			current.get_script()
			and current.get_script().get_global_name() == "InventoryWindowContent"
		):
			return current
		current = current.get_parent()
	return null


func _find_list_view() -> InventoryListView:
	var current = get_parent()
	while current:
		if current.get_script() and current.get_script().get_global_name() == "InventoryListView":
			return current
		current = current.get_parent()
	return null


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	"""Check if we can accept a drop and provide visual feedback"""

	if not item or not data:
		return false

	var source_item = data.get("item") as InventoryItem_Base
	var source_row = data.get("source_row") as ListRowManager

	if not source_item or source_row == self:
		return false

	# Check if items can stack/merge
	if item.can_stack_with(source_item):
		_set_merge_highlight(true)
		return true

	_set_merge_highlight(false)
	return false


func _drop_data(_position: Vector2, data: Variant):
	"""Handle the actual drop"""
	_set_merge_highlight(false)

	if not data:
		return

	var source_row = data.get("source_row") as ListRowManager
	var source_item = data.get("item") as InventoryItem_Base

	if not source_row or not source_item or source_row == self:
		return

	_handle_merge_with_source(source_row, source_item)


func _set_merge_highlight(enabled: bool):
	"""Set visual feedback for potential merge"""
	if enabled:
		# Green highlight for valid merge - don't use modulate, use direct color setting
		_update_background_color(Color(0.2, 0.6, 0.2, 1.0))
	else:
		# Reset to normal color based on current state
		_update_background()


func _handle_merge_with_source(source_row: ListRowManager, source_item: InventoryItem_Base):
	"""Handle merging items from source row to this row"""

	if not item.can_stack_with(source_item):
		return

	var inventory_manager = _get_inventory_manager()
	if not inventory_manager:
		return

	# Get the list view and temporarily disable auto-refresh
	var list_view = _find_list_view()
	var was_auto_refreshing = false
	if list_view and list_view.has_method("set_auto_refresh"):
		was_auto_refreshing = list_view.get_auto_refresh()
		list_view.set_auto_refresh(false)

	# Calculate how much we can stack
	var space_available = item.max_stack_size - item.quantity
	var amount_to_transfer = min(source_item.quantity, space_available)

	if amount_to_transfer <= 0:
		# Re-enable auto-refresh before returning
		if list_view and was_auto_refreshing:
			list_view.set_auto_refresh(true)
		return

	# Perform the merge directly on the items
	item.quantity += amount_to_transfer
	source_item.quantity -= amount_to_transfer

	# Store if the source item will be completely consumed
	var source_will_be_empty = source_item.quantity <= 0

	# Immediately update source row visuals if it will be empty
	if source_will_be_empty:
		source_row.modulate.a = 0.0  # Make it invisible immediately
		source_row.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Disable interaction

	# Remove source item if empty (but don't refresh yet)
	var container = _get_current_container()
	if source_will_be_empty and container:
		container.remove_item(source_item)

	# Update this row's display immediately to show new quantity
	_refresh_display()

	# Re-enable auto-refresh and do a single controlled refresh
	if list_view:
		if was_auto_refreshing:
			list_view.set_auto_refresh(true)
		# Do a single deferred refresh to clean up the empty row
		call_deferred("_deferred_refresh_list", list_view)

	# Notify that drop was successful
	source_row._on_external_drop_result(true)


func _deferred_refresh_list(list_view: InventoryListView):
	"""Deferred refresh to ensure proper cleanup"""
	if list_view and is_instance_valid(list_view):
		list_view.refresh_display()


func _refresh_display():
	"""Refresh this row's display"""
	# Update the quantity cell if it exists
	for i in range(cells.size()):
		if i < columns.size() and columns[i].id == "quantity":
			var cell = cells[i]
			if cell.get_child_count() > 0:
				var label = cell.get_child(0) as Label
				if label:
					var qty_text = str(item.quantity)
					if item.quantity >= 1000:
						qty_text = "%.1fk" % (item.quantity / 1000.0)
					label.text = qty_text


func _trigger_list_refresh(list_view: InventoryListView):
	"""Helper to trigger list refresh"""
	if list_view and is_instance_valid(list_view):
		list_view.refresh_display()


func _get_current_container() -> InventoryContainer_Base:
	var list_view = _find_list_view()
	if list_view:
		return list_view.container
	return null


func get_drag_data(_position: Vector2) -> Variant:
	"""Provide drag data for Godot's built-in drag system"""
	if not item:
		return null

	var drag_data = {"source_row": self, "item": item, "container_id": _get_container_id()}

	return drag_data


func _end_drag():
	"""End the drag operation"""
	if not is_dragging:
		return

	var drop_successful = false
	var end_position = get_global_mouse_position()

	drop_successful = _attempt_drop_on_list_rows(end_position)

	if not drop_successful:
		drop_successful = _attempt_drop_on_inventory(end_position)

	if not drop_successful:
		drop_successful = _attempt_drop_on_container_list(end_position)

	if not drop_successful:
		drop_successful = _attempt_drop_on_equipment_slots(end_position)

	# Check if drop is over any UI window - if not, drop into world
	if not drop_successful and not _is_drop_over_ui_window(end_position):
		print("  [LIST ROW] Attempting world drop (async)...")
		# Call the async world drop and return early - it will handle cleanup
		_handle_async_world_drop(end_position)
		return  # Early return - world drop will handle everything

	_cleanup_drag_preview()

	is_dragging = false
	drag_preview_created = false

	# FIXED: Reset background properly instead of using modulate
	_update_background()
	_set_merge_highlight(false)

	var viewport = get_viewport()
	if viewport and viewport.has_meta("current_drag_data"):
		viewport.remove_meta("current_drag_data")

	var content = _find_inventory_content()
	if content:
		content._clear_all_container_highlights()

	item_drag_ended.emit(self, drop_successful)


func _attempt_drop_on_list_rows(end_position: Vector2) -> bool:
	"""Try to drop on other list rows for merging"""
	var list_view = _find_list_view()
	if not list_view:
		return false

	# Check all list rows to see if we're dropping on one
	for row in list_view.item_rows:
		if row == self or not is_instance_valid(row):
			continue

		var row_rect = Rect2(row.global_position, row.size)
		if row_rect.has_point(end_position):
			# We're dropping on this row
			var target_item = row.item
			if target_item and item.can_stack_with(target_item):
				row._handle_merge_with_source(self, item)
				return true

	return false


func _update_background_color_with_alpha(alpha: float):
	"""Update background color with specific alpha for drag feedback"""
	if not background:
		return

	var base_color: Color
	if is_selected:
		base_color = selected_color
	elif is_hovered:
		base_color = hover_color
	elif use_alternate:
		base_color = alternate_color
	else:
		base_color = normal_color

	var faded_color = Color(base_color.r, base_color.g, base_color.b, alpha)
	_update_background_color(faded_color)


func _cleanup_drag_preview():
	"""Clean up drag preview and canvas"""
	var root = get_tree().root
	var drag_canvases = []

	# Find all DragCanvas nodes
	for child in root.get_children():
		if child.name == "DragCanvas":
			drag_canvases.append(child)

	# Clean them up
	for canvas in drag_canvases:
		if is_instance_valid(canvas):
			canvas.queue_free()


func _deferred_tooltip_setup():
	"""Deferred tooltip setup for when row is in scene tree"""
	if tooltip_manager:
		tooltip_manager._perform_setup()


func _handle_async_world_drop(drop_position: Vector2):
	"""Handle async world drop with proper cleanup"""
	# This function handles the entire async drop process
	var success = await _attempt_drop_into_world(drop_position)

	if not success:
		print("  [_handle_async_world_drop] World drop failed for list row")

	_cleanup_drag_preview()

	is_dragging = false
	drag_preview_created = false

	# Reset background properly
	_update_background()
	_set_merge_highlight(false)

	var viewport = get_viewport()
	if viewport and viewport.has_meta("current_drag_data"):
		viewport.remove_meta("current_drag_data")

	var content = _find_inventory_content()
	if content:
		content._clear_all_container_highlights()

	item_drag_ended.emit(self, success)


func _is_drop_over_ui_window(drop_position: Vector2) -> bool:
	"""Check if the drop position is over any UI window"""
	if not is_inside_tree():
		return false

	# Get all Window_Base nodes (inventory, equipment, etc.)
	var all_windows = get_tree().get_nodes_in_group("external_container_windows")

	for window in all_windows:
		if not is_instance_valid(window) or not window.visible:
			continue

		# Check if window has a valid global_position and size
		if not window.has_method("get_global_position") or not window.has_method("get_size"):
			continue

		var window_rect = Rect2(window.global_position, window.size)
		if window_rect.has_point(drop_position):
			print("  [_is_drop_over_ui_window] Drop IS over window: ", window.name)
			return true

	print("  [_is_drop_over_ui_window] Drop is NOT over any UI window")
	return false


func _attempt_drop_into_world(drop_position: Vector2) -> bool:
	"""Drop the item into the world as a physical object"""
	if not item:
		print("  [_attempt_drop_into_world] ERROR: No item")
		return false

	# Store item data before any operations that might clear it
	var item_name = item.item_name
	var item_id = item.item_id

	print("  [_attempt_drop_into_world] Dropping item: ", item_name, " (ID: ", item_id, ")")

	# Get scene tree
	if not is_inside_tree():
		print("  [_attempt_drop_into_world] ERROR: Row not in tree")
		return false

	var tree = get_tree()
	if not tree:
		print("  [_attempt_drop_into_world] ERROR: Could not access scene tree")
		return false

	# Get player reference
	var players = tree.get_nodes_in_group("player")
	if players.is_empty():
		print("  [_attempt_drop_into_world] ERROR: No player found")
		return false

	var player = players[0]

	# Get world reference
	var world = player.get_parent()
	if not world:
		print("  [_attempt_drop_into_world] ERROR: Could not find world node")
		return false

	# Calculate spawn position in 3D world
	var spawn_position = _calculate_world_spawn_position(player, drop_position)

	# Get the physical scene path for this item
	var physical_scene_path = _get_physical_scene_path_for_item(item)
	if physical_scene_path.is_empty():
		print("  [_attempt_drop_into_world] ERROR: No physical scene found for item: ", item.item_id)
		NotificationManager.show_error("Cannot drop this item type")
		return false

	# Load the physical item scene
	var physical_scene = load(physical_scene_path)
	if not physical_scene:
		print("  [_attempt_drop_into_world] ERROR: Failed to load physical scene: ", physical_scene_path)
		NotificationManager.show_error("Cannot drop item")
		return false

	# Instantiate the physical item
	var physical_item = physical_scene.instantiate()
	if not physical_item:
		print("  [_attempt_drop_into_world] ERROR: Failed to instantiate physical item")
		NotificationManager.show_error("Cannot drop item")
		return false

	print("  [_attempt_drop_into_world] Physical item instantiated: ", physical_item.name)

	# Add to world first (must be in tree before setting properties)
	world.add_child(physical_item)
	physical_item.global_position = spawn_position

	print("  [_attempt_drop_into_world] Physical item added to world at: ", spawn_position)

	# Wait for item to be fully in tree
	await tree.process_frame

	# Add slight physics effects
	if physical_item is RigidBody3D:
		# Add slight angular velocity for natural motion
		physical_item.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		physical_item.gravity_scale = 0.7
		print("  [_attempt_drop_into_world] Applied physics to RigidBody3D")

	# Ensure pickup is enabled and setup interactable area
	if physical_item.has_method("_setup_interactable_area"):
		# Wait another frame to ensure the item is fully initialized
		await tree.process_frame
		physical_item._setup_interactable_area()
		print("  [_attempt_drop_into_world] Called _setup_interactable_area directly")

	# Remove one from inventory
	print("  [_attempt_drop_into_world] Attempting to remove item from inventory...")
	var inventory_manager = _get_inventory_manager()
	if not inventory_manager:
		print("  [_attempt_drop_into_world] ERROR: No inventory manager found")
		return false

	var container_id = _get_container_id()
	print("  [_attempt_drop_into_world] Inventory manager found, container_id: ", container_id)
	var source_container = inventory_manager.get_container(container_id)
	if not source_container:
		print("  [_attempt_drop_into_world] ERROR: Could not find source container: ", container_id)
		return false

	print("  [_attempt_drop_into_world] Source container found: ", source_container.container_name)
	print("  [_attempt_drop_into_world] Item quantity before: ", item.quantity)

	item.quantity -= 1
	print("  [_attempt_drop_into_world] Item quantity after: ", item.quantity)

	if item.quantity <= 0:
		print("  [_attempt_drop_into_world] Removing item completely from container")
		source_container.remove_item(item)

	# Refresh display
	print("  [_attempt_drop_into_world] Refreshing inventory display...")
	var list_view = _find_list_view()
	if list_view:
		await tree.process_frame
		list_view.refresh_display()
		print("  [_attempt_drop_into_world] Display refreshed")
	else:
		print("  [_attempt_drop_into_world] WARNING: Could not find list view to refresh")

	# Show notification
	NotificationManager.show_notification("Dropped %s into world" % item_name)
	print("  [_attempt_drop_into_world] ✓ Successfully dropped %s at position %s" % [item_name, spawn_position])
	return true


func _calculate_world_spawn_position(player: Node, _drop_position: Vector2) -> Vector3:
	"""Calculate the 3D world position to spawn the dropped item"""
	var spawn_position = player.global_position
	var forward_offset = Vector3.ZERO

	# Get player's look direction
	if player.has_method("get_look_direction"):
		var look_dir = player.get_look_direction()
		forward_offset = look_dir * 1.5  # Drop slightly in front
	else:
		# Use player's forward direction from transform
		forward_offset = -player.global_transform.basis.z * 1.5

	# Place in front and slightly above the player
	spawn_position += forward_offset + Vector3(0, 1.2, 0)

	return spawn_position


func _get_physical_scene_path_for_item(item_data: InventoryItem_Base) -> String:
	"""Get the physical scene path for an inventory item"""
	# Define mappings for items that have physical representations
	var scene_mappings = {
		"resource_resinwood_log": "res://assets/models/resources/resinwood_log.tscn",
		"resource_iron_ore": "res://assets/models/resources/iron_ore.tscn",
		"resource_copper_ore": "res://assets/models/resources/copper_ore.tscn",
		# Add more mappings as needed
	}

	return scene_mappings.get(item_data.item_id, "")


func cleanup():
	"""Clean up components"""
	if tooltip_manager:
		tooltip_manager.cleanup()


func _exit_tree():
	if hover_tween:
		hover_tween.kill()
		hover_tween = null
	if hover_overlay:
		hover_overlay.queue_free()
		hover_overlay = null
	cleanup()
