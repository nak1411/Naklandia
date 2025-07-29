# InventorySlotUI.gd - Individual inventory slot with new drag-and-drop system
class_name InventorySlot
extends Control

# Slot properties
@export var slot_size: Vector2 = Vector2(64, 64)
@export var border_color: Color = Color.GRAY
@export var border_width: float = 2.0
@export var highlight_color: Color = Color.YELLOW
@export var selection_color: Color = Color.CYAN

# Content
var item: InventoryItem_Base
var grid_position: Vector2i
var container_id: String

# Visual components
var background_panel: Panel
var item_icon: TextureRect
var quantity_label: Label
var rarity_border: NinePatchRect

# State
var is_highlighted: bool = false
var is_selected: bool = false
var is_occupied: bool = false

# Drag and drop state
var is_dragging: bool = false
var drag_start_position: Vector2
var drag_threshold: float = 5.0

# Signals
signal slot_clicked(slot: InventorySlot, event: InputEvent)
signal slot_right_clicked(slot: InventorySlot, event: InputEvent)
signal item_drag_started(slot: InventorySlot, item: InventoryItem_Base)
signal item_drag_ended(slot: InventorySlot, success: bool)
signal item_dropped_on_slot(source_slot: InventorySlot, target_slot: InventorySlot)

func _init():
	custom_minimum_size = slot_size
	size = slot_size

func _ready():
	_setup_visual_components()
	_setup_signals()

func _setup_visual_components():
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Background panel
	background_panel = Panel.new()
	background_panel.name = "Background"
	background_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background_panel)
	
	# Style the background
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	style_box.border_width_left = border_width
	style_box.border_width_right = border_width
	style_box.border_width_top = border_width
	style_box.border_width_bottom = border_width
	style_box.border_color = border_color
	style_box.corner_radius_top_left = 4
	style_box.corner_radius_top_right = 4
	style_box.corner_radius_bottom_left = 4
	style_box.corner_radius_bottom_right = 4
	background_panel.add_theme_stylebox_override("panel", style_box)
	
	# Item icon
	item_icon = TextureRect.new()
	item_icon.name = "ItemIcon"
	item_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	item_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(item_icon)
	
	# Quantity label
	quantity_label = Label.new()
	quantity_label.name = "QuantityLabel"
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	quantity_label.position = Vector2(slot_size.x - 20, slot_size.y - 16)
	quantity_label.size = Vector2(18, 14)
	quantity_label.add_theme_color_override("font_color", Color.WHITE)
	quantity_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	quantity_label.add_theme_constant_override("shadow_offset_x", 1)
	quantity_label.add_theme_constant_override("shadow_offset_y", 1)
	quantity_label.add_theme_font_size_override("font_size", 10)
	quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quantity_label.visible = false
	add_child(quantity_label)
	
	# Rarity border
	rarity_border = NinePatchRect.new()
	rarity_border.name = "RarityBorder"
	rarity_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rarity_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rarity_border.visible = false
	add_child(rarity_border)

func _setup_signals():
	gui_input.connect(_on_gui_input)

# Item management
func set_item(new_item: InventoryItem_Base):
	item = new_item
	_update_display()

func get_item() -> InventoryItem_Base:
	return item

func has_item() -> bool:
	return item != null

func clear_item():
	item = null
	_update_display()

func set_grid_position(pos: Vector2i):
	grid_position = pos

func get_grid_position() -> Vector2i:
	return grid_position

func set_container_id(id: String):
	container_id = id

func get_container_id() -> String:
	return container_id

func _update_display():
	is_occupied = has_item()
	
	if not item:
		item_icon.texture = null
		quantity_label.visible = false
		rarity_border.visible = false
		tooltip_text = ""
		_update_visual_state()
		return
	
	# Set item icon
	var texture = item.get_icon_texture()
	if texture:
		item_icon.texture = texture
	else:
		_create_fallback_icon()
	
	# Set quantity
	if item.quantity > 1:
		quantity_label.text = str(item.quantity)
		quantity_label.visible = true
	else:
		quantity_label.visible = false
	
	# Set rarity border
	if rarity_border:
		if item.item_rarity != InventoryItem_Base.ItemRarity.COMMON:
			_show_rarity_border()
		else:
			rarity_border.visible = false
	
	# Set tooltip
	_update_tooltip()
	
	queue_redraw()

func _create_fallback_icon():
	var image = Image.create(64, 64, false, Image.FORMAT_RGB8)
	var type_color = item.get_type_color()
	image.fill(type_color)
	
	var texture = ImageTexture.new()
	texture.set_image(image)
	item_icon.texture = texture

func _show_rarity_border():
	rarity_border.visible = true
	var rarity_color = item.get_rarity_color()
	rarity_border.modulate = rarity_color

func _update_tooltip():
	if not item:
		tooltip_text = ""
		return
	
	var tooltip = "%s\n" % item.item_name
	tooltip += "Type: %s\n" % InventoryItem_Base.ItemType.keys()[item.item_type]
	tooltip += "Quantity: %d\n" % item.quantity
	tooltip += "Volume: %.2f m³ (%.2f m³ total)\n" % [item.volume, item.get_total_volume()]
	tooltip += "Mass: %.2f kg (%.2f kg total)\n" % [item.mass, item.get_total_mass()]
	tooltip += "Value: %.2f ISK (%.2f ISK total)\n" % [item.base_value, item.get_total_value()]
	
	if not item.description.is_empty():
		tooltip += "\n%s" % item.description
	
	tooltip_text = tooltip

# Calculate tooltip position (same position where Godot would show the tooltip)
func get_tooltip_position() -> Vector2:
	# Position the popup just to the right and slightly below the slot
	var tooltip_offset = Vector2(slot_size.x + 5, 0)
	return global_position + tooltip_offset

# Visual state management
func set_highlighted(highlighted: bool):
	is_highlighted = highlighted
	_update_visual_state()

func set_selected(selected: bool):
	is_selected = selected
	_update_visual_state()

func _update_visual_state():
	if not background_panel:
		return
	
	var style_box = background_panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	
	if is_selected:
		style_box.border_color = selection_color
		style_box.bg_color = selection_color.darkened(0.8)
	elif is_highlighted:
		style_box.border_color = highlight_color
		style_box.bg_color = highlight_color.darkened(0.9)
	elif is_occupied:
		style_box.border_color = border_color.lightened(0.3)
		style_box.bg_color = Color(0.3, 0.3, 0.3, 0.9)
	else:
		style_box.border_color = border_color
		style_box.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	
	background_panel.add_theme_stylebox_override("panel", style_box)

# New drag and drop input handling
func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				if has_item():
					is_dragging = true
					drag_start_position = mouse_event.global_position
				slot_clicked.emit(self, mouse_event)
			else:
				# Mouse button released
				if is_dragging:
					_handle_drag_end(mouse_event.global_position)
					is_dragging = false
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			print("InventorySlot: Right-click detected on slot with item: ", item.item_name if item else "no item")
			slot_right_clicked.emit(self, mouse_event)
			get_viewport().set_input_as_handled()
	
	elif event is InputEventMouseMotion and is_dragging:
		var distance = event.global_position.distance_to(drag_start_position)
		if distance > drag_threshold and has_item():
			_start_drag()

func _start_drag():
	if not has_item():
		return  # No item to drag
	
	# Check if already dragging by looking for existing drag layer
	var existing_layer = get_viewport().get_node_or_null("DragLayer")
	if existing_layer:
		return  # Already dragging
	
	# Check if shift is held for partial transfer indication
	var is_partial_transfer = Input.is_key_pressed(KEY_SHIFT) and item.quantity > 1
	
	# Create drag data for container list drops
	var drag_data = {
		"source_slot": self,
		"item": item,
		"container_id": container_id,
		"partial_transfer": is_partial_transfer,
		"success_callback": _on_external_drop_result
	}
	
	# Set the drag data globally so container list can access it
	get_viewport().set_meta("current_drag_data", drag_data)
	
	# Create drag preview
	var preview = _create_drag_preview()
	
	# Create a CanvasLayer to ensure the preview is on top of everything
	var drag_layer = CanvasLayer.new()
	drag_layer.name = "DragLayer"
	drag_layer.layer = 100  # Very high layer to be on top
	get_viewport().add_child(drag_layer)
	drag_layer.add_child(preview)
	
	# Store reference to the layer for cleanup
	preview.set_meta("drag_layer", drag_layer)
	
	# Add visual indicator for partial transfer
	if is_partial_transfer:
		_add_partial_transfer_indicator(preview)
	
	# Start following mouse
	_follow_mouse(preview)
	
	# Force initial position update
	var mouse_pos = get_global_mouse_position()
	preview.global_position = mouse_pos - preview.size / 2
	
	# Emit drag started signal
	item_drag_started.emit(self, item)

func _add_partial_transfer_indicator(preview: Control):
	"""Add visual indicator showing this is a partial transfer"""
	var indicator = Label.new()
	indicator.text = "½"
	indicator.position = Vector2(preview.size.x - 15, -5)
	indicator.size = Vector2(12, 12)
	indicator.add_theme_font_size_override("font_size", 10)
	indicator.add_theme_color_override("font_color", Color.YELLOW)
	indicator.add_theme_color_override("font_shadow_color", Color.BLACK)
	indicator.add_theme_constant_override("shadow_offset_x", 1)
	indicator.add_theme_constant_override("shadow_offset_y", 1)
	preview.add_child(indicator)

func _create_drag_preview() -> Control:
	var preview = Control.new()
	preview.name = "DragPreview"
	preview.size = size
	preview.z_index = 4096  # Much higher z_index to ensure it's on top
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Copy visual elements
	var preview_bg = Panel.new()
	preview_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_bg.add_theme_stylebox_override("panel", background_panel.get_theme_stylebox("panel"))
	preview_bg.modulate.a = 0.8
	preview.add_child(preview_bg)
	
	var preview_icon = TextureRect.new()
	preview_icon.texture = item_icon.texture
	# Remove debug prints and fix preview position to actually follow mouse
	print("Original texture: ", item_icon.texture, " Item has get_icon_texture: ", item.has_method("get_icon_texture") if item else "no item")
	preview_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_icon.modulate.a = 0.9
	preview.add_child(preview_icon)
	
	if item.quantity > 1:
		var preview_quantity = Label.new()
		preview_quantity.text = str(item.quantity)
		preview_quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		preview_quantity.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		# Position relative to preview size, not copying original position
		preview_quantity.position = Vector2(preview.size.x - 20, preview.size.y - 16)
		preview_quantity.size = Vector2(18, 14)
		preview_quantity.add_theme_color_override("font_color", Color.WHITE)
		preview_quantity.add_theme_color_override("font_shadow_color", Color.BLACK)
		preview_quantity.add_theme_constant_override("shadow_offset_x", 1)
		preview_quantity.add_theme_constant_override("shadow_offset_y", 1)
		preview_quantity.add_theme_font_size_override("font_size", 10)
		preview.add_child(preview_quantity)
	
	return preview

func _follow_mouse(preview: Control):
	# Store reference and start immediate positioning
	preview.set_meta("source_slot", self)
	_update_preview_position(preview)
	
	# Create a timer to update position continuously
	var timer = Timer.new()
	timer.wait_time = 0.016  # ~60 FPS
	timer.timeout.connect(_update_preview_position.bind(preview))
	add_child(timer)
	timer.start()
	
	# Store timer reference to clean it up later
	preview.set_meta("position_timer", timer)

func _update_preview_position(preview: Control):
	if not is_instance_valid(preview):
		return
	
	# Check if this preview belongs to this slot
	var source_slot = preview.get_meta("source_slot", null)
	if source_slot != self:
		return
	
	var mouse_pos = get_global_mouse_position()
	preview.global_position = mouse_pos - preview.size / 2

func _handle_drag_end(end_position: Vector2):
	if not has_item():
		is_dragging = false
		return
	
	# Clean up drag preview, timer, and layer
	var preview = null
	var drag_layer = get_viewport().get_node_or_null("DragLayer")
	if drag_layer:
		preview = drag_layer.get_node_or_null("DragPreview")
	
	if not preview:
		# Fallback: try finding it directly in viewport
		preview = get_viewport().get_node_or_null("DragPreview")
	
	if preview and preview.get_meta("source_slot", null) == self:
		var timer = preview.get_meta("position_timer", null)
		if timer and is_instance_valid(timer):
			timer.queue_free()
		
		# Clean up the canvas layer (which will also clean up the preview)
		if drag_layer and is_instance_valid(drag_layer):
			drag_layer.queue_free()
		elif preview:
			preview.queue_free()
	
	var success = false
	
	# Debug the drop attempt
	print("Attempting drop at position: ", end_position)
	
	# Check if we dropped on container list first
	var container_content = _find_inventory_content()
	if container_content:
		# Try container list drop first
		if get_viewport().has_meta("current_drag_data"):
			var drag_data = get_viewport().get_meta("current_drag_data")
			success = container_content._try_drop_on_container_list(end_position, drag_data)
			print("Container drop result: ", success)
	
	# If container drop failed, try slot drop
	if not success:
		var target_slot = _find_slot_at_position(end_position)
		print("Target slot found: ", target_slot)
		if target_slot and target_slot != self:
			success = _attempt_drop_on_slot(target_slot)
			print("Slot drop result: ", success)
			if success:
				# Emit the dropped signal for successful drops
				item_dropped_on_slot.emit(self, target_slot)
	
	# Clear drag data
	get_viewport().remove_meta("current_drag_data")
	
	# Reset dragging state immediately
	is_dragging = false
	
	# Clear any highlighting on this slot
	set_highlighted(false)
	
	# Emit drag ended signal
	item_drag_ended.emit(self, success)

func _on_external_drop_result(success: bool):
	"""Called when an external drop (like container list) completes"""
	if success:
		clear_item()

func _find_inventory_content():
	"""Find the InventoryWindowContent in the scene tree"""
	var current = get_parent()
	while current:
		if current.get_script() and current.get_script().get_global_name() == "InventoryWindowContent":
			return current
		current = current.get_parent()
	return null

func _find_slot_at_position(global_pos: Vector2) -> InventorySlot:
	var grid = _get_inventory_grid()
	if not grid:
		return null
	
	# Check all slots in the grid for the one under the mouse
	for y in range(grid.slots.size()):
		for x in range(grid.slots[y].size()):
			var slot = grid.slots[y][x]
			if slot and slot != self and is_instance_valid(slot):
				var slot_rect = Rect2(slot.global_position, slot.size)
				# Add small margin for easier dropping
				slot_rect = slot_rect.grow(2)
				if slot_rect.has_point(global_pos):
					return slot
	
	return null

func _attempt_drop_on_slot(target_slot: InventorySlot) -> bool:
	if not target_slot or not has_item():
		return false
	
	# Check for shift+drop with stackable items - open split dialog
	if Input.is_key_pressed(KEY_SHIFT) and item.quantity > 1:
		_show_split_stack_dialog()
		return true
	
	var inventory_manager = _get_inventory_manager()
	if not inventory_manager:
		print("No inventory manager found")
		return false
	
	# Get containers
	var source_container = inventory_manager.get_container(container_id)
	var target_container = inventory_manager.get_container(target_slot.container_id)
	
	if not source_container or not target_container:
		print("Invalid containers - source: ", source_container, " target: ", target_container)
		return false
	
	print("Source container: ", source_container.container_name, " Target container: ", target_container.container_name)
	print("Source item: ", item.item_name, " quantity: ", item.quantity)
	print("Target position: ", target_slot.grid_position)
	print("Target slot has item: ", target_slot.has_item())
	
	# Attempt the transfer
	var success = inventory_manager.transfer_item(
		item,
		container_id,
		target_slot.container_id,
		target_slot.grid_position
	)
	print("Transfer result: ", success)
	return success

func _show_split_stack_dialog():
	# Implementation for splitting stacks would go here
	# For now, just transfer the whole stack
	print("Split stack dialog not implemented yet")
	pass

func _get_inventory_manager():
	# Find the inventory manager in the scene hierarchy
	var current = get_parent()
	while current:
		if current.has_method("get_inventory_manager"):
			return current.get_inventory_manager()
		if current.has_meta("inventory_manager"):
			return current.get_meta("inventory_manager")
		current = current.get_parent()
	
	# Try to find InventoryIntegration in the scene tree
	var scene_root = get_tree().current_scene
	if scene_root:
		var integration = scene_root.find_child("InventoryIntegration", true, false)
		if integration and integration.has_method("get") and integration.get("inventory_manager"):
			return integration.inventory_manager
	
	# Search for Player node with InventoryIntegration component
	var player = scene_root.find_child("Player", true, false) if scene_root else null
	if player:
		var player_integration = player.find_child("InventoryIntegration", true, false)
		if player_integration and player_integration.inventory_manager:
			return player_integration.inventory_manager
	
	return null

func _get_inventory_grid():
	# Find the parent inventory grid
	var current = get_parent()
	while current:
		if current is InventoryGrid:
			return current
		current = current.get_parent()
	return null
