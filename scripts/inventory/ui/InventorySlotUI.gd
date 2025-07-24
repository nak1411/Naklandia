# InventorySlotUI.gd - Individual inventory slot with new drag-and-drop system
class_name InventorySlotUI
extends Control

# Slot properties
@export var slot_size: Vector2 = Vector2(64, 64)
@export var border_color: Color = Color.GRAY
@export var border_width: float = 2.0
@export var highlight_color: Color = Color.YELLOW
@export var selection_color: Color = Color.CYAN

# Content
var item: InventoryItem
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
signal slot_clicked(slot: InventorySlotUI, event: InputEvent)
signal slot_right_clicked(slot: InventorySlotUI, event: InputEvent)
signal item_drag_started(slot: InventorySlotUI, item: InventoryItem)
signal item_drag_ended(slot: InventorySlotUI, success: bool)
signal item_dropped_on_slot(source_slot: InventorySlotUI, target_slot: InventorySlotUI)

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
	quantity_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	quantity_label.position = Vector2(-20, -16)
	quantity_label.size = Vector2(18, 14)
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	quantity_label.add_theme_font_size_override("font_size", 10)
	quantity_label.add_theme_color_override("font_color", Color.WHITE)
	quantity_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	quantity_label.add_theme_constant_override("shadow_offset_x", 1)
	quantity_label.add_theme_constant_override("shadow_offset_y", 1)
	quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(quantity_label)
	
	# Rarity border (initially hidden)
	rarity_border = NinePatchRect.new()
	rarity_border.name = "RarityBorder"
	rarity_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rarity_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rarity_border.visible = false
	add_child(rarity_border)
	
	_update_visual_state()

func _setup_signals():
	mouse_filter = Control.MOUSE_FILTER_PASS
	gui_input.connect(_on_gui_input)

# Item management
func set_item(new_item: InventoryItem):
	if item and item.quantity_changed.is_connected(_on_item_quantity_changed):
		item.quantity_changed.disconnect(_on_item_quantity_changed)
	
	item = new_item
	is_occupied = item != null
	
	if item:
		item.quantity_changed.connect(_on_item_quantity_changed)
	
	_update_item_display()
	
	if visible:
		queue_redraw()
	
func force_visual_refresh():
	queue_redraw()
	_update_visual_state()

func clear_item():
	set_item(null)

func get_item() -> InventoryItem:
	return item

func has_item() -> bool:
	return item != null

# Visual updates
func _update_item_display():
	if not item:
		if item_icon:
			item_icon.texture = null
			item_icon.visible = false
		if quantity_label:
			quantity_label.text = ""
			quantity_label.visible = false
		if rarity_border:
			rarity_border.visible = false
		tooltip_text = ""
		return
	
	# Set icon
	var icon_texture = item.get_icon_texture()
	if icon_texture:
		item_icon.texture = icon_texture
		item_icon.visible = true
	else:
		_create_fallback_icon()
		item_icon.visible = true
	
	# Always show quantity for any amount > 1
	if item.quantity > 1:
		quantity_label.text = str(item.quantity)
		quantity_label.visible = true
	else:
		quantity_label.text = "1"
		quantity_label.visible = true
	
	# Set rarity border
	if rarity_border:
		if item.item_rarity != InventoryItem.ItemRarity.COMMON:
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
	tooltip += "Type: %s\n" % InventoryItem.ItemType.keys()[item.item_type]
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
			slot_right_clicked.emit(self, mouse_event)
			get_viewport().set_input_as_handled()
	
	elif event is InputEventMouseMotion and is_dragging:
		var distance = event.global_position.distance_to(drag_start_position)
		if distance > drag_threshold and has_item():
			_start_drag()

func _start_drag():
	if not has_item() or get_viewport().get_node_or_null("DragPreview"):
		return  # Already dragging or no item
	
	# Create drag data for container list drops
	var drag_data = {
		"source_slot": self,
		"item": item,
		"container_id": container_id,
		"success_callback": _on_external_drop_result
	}
	
	# Set the drag data globally so container list can access it
	get_viewport().set_meta("current_drag_data", drag_data)
	
	# Create drag preview
	var preview = _create_drag_preview()
	get_viewport().add_child(preview)
	
	# Start following mouse
	_follow_mouse(preview)
	
	# Emit drag started signal
	item_drag_started.emit(self, item)

func _create_drag_preview() -> Control:
	var preview = Control.new()
	preview.name = "DragPreview"
	preview.size = size
	preview.z_index = 1000
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Copy visual elements
	var preview_bg = Panel.new()
	preview_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_bg.add_theme_stylebox_override("panel", background_panel.get_theme_stylebox("panel"))
	preview_bg.modulate.a = 0.8
	preview.add_child(preview_bg)
	
	var preview_icon = TextureRect.new()
	preview_icon.texture = item_icon.texture
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
	
	# Clean up drag preview and timer
	var preview = get_viewport().get_node_or_null("DragPreview")
	if preview and preview.get_meta("source_slot", null) == self:
		var timer = preview.get_meta("position_timer", null)
		if timer and is_instance_valid(timer):
			timer.queue_free()
		preview.queue_free()
	
	var success = false
	
	# Check if we dropped on container list first
	var container_content = _find_inventory_content()
	if container_content:
		# Try container list drop first
		if get_viewport().has_meta("current_drag_data"):
			var drag_data = get_viewport().get_meta("current_drag_data")
			success = container_content._try_drop_on_container_list(end_position, drag_data)
	
	# If container drop failed, try slot drop
	if not success:
		var target_slot = _find_slot_at_position(end_position)
		if target_slot and target_slot != self:
			success = _attempt_drop_on_slot(target_slot)
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

func _find_slot_at_position(global_pos: Vector2) -> InventorySlotUI:
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

func _attempt_drop_on_slot(target_slot: InventorySlotUI) -> bool:
	if not target_slot or not has_item():
		return false
	
	var inventory_manager = _get_inventory_manager()
	if not inventory_manager:
		return false
	
	# Get containers
	var source_container = inventory_manager.get_container(container_id)
	var target_container = inventory_manager.get_container(target_slot.container_id)
	
	if not source_container or not target_container:
		return false
	
	# Handle different drop scenarios
	if target_slot.has_item():
		var target_item = target_slot.get_item()
		
		# Try stacking if items are compatible
		if item.can_stack_with(target_item):
			return _handle_stack_merge(target_slot, target_item)
		else:
			# Swap items
			return _handle_item_swap(target_slot, target_item, inventory_manager)
	else:
		# Move to empty slot
		return _handle_move_to_empty(target_slot, inventory_manager)

func _handle_stack_merge(target_slot: InventorySlotUI, target_item: InventoryItem) -> bool:
	
	var space_available = target_item.max_stack_size - target_item.quantity
	var amount_to_transfer = min(item.quantity, space_available)
	
	
	if amount_to_transfer <= 0:
		return false
	
	# Direct stacking without using transfer system for same container
	if container_id == target_slot.container_id:
		# Update quantities directly
		target_item.quantity += amount_to_transfer
		item.quantity -= amount_to_transfer
		
		
		# Update displays
		target_slot._update_item_display()
		
		if item.quantity <= 0:
			# Source item fully consumed
			var source_container = _get_inventory_manager().get_container(container_id)
			if source_container:
				source_container.remove_item(item)
			clear_item()
		else:
			_update_item_display()
		
		return true
	else:
		# Different container stacking - use transfer system
		var inventory_manager = _get_inventory_manager()
		if not inventory_manager:
			return false
		
		# Use the inventory manager's transfer system for different containers
		var success = inventory_manager.transfer_item(item, container_id, target_slot.container_id, target_slot.grid_position, amount_to_transfer)
		
		if success:
			# Update displays - the transfer system handles the logic
			if item.quantity <= 0:
				# Source item fully consumed
				clear_item()
			else:
				_update_item_display()
			
			# Update target display
			target_slot._update_item_display()
			
			return true
		
		return false

func _handle_item_swap(target_slot: InventorySlotUI, target_item: InventoryItem, inventory_manager: InventoryManager) -> bool:
	var source_container = inventory_manager.get_container(container_id)
	var target_container = inventory_manager.get_container(target_slot.container_id)
	
	# Store items and positions temporarily
	var temp_source_item = item
	var temp_target_item = target_item
	var source_pos = grid_position
	var target_pos = target_slot.grid_position
	
	# For same container swaps, use move_item which is more reliable
	if source_container == target_container:
		# Clear the grid positions manually first
		source_container.clear_grid_area(source_pos)
		source_container.clear_grid_area(target_pos)
		
		# Place items at swapped positions
		source_container.occupy_grid_area(target_pos, temp_source_item)
		source_container.occupy_grid_area(source_pos, temp_target_item)
		
		# Update visual slots immediately
		clear_item()
		target_slot.clear_item()
		target_slot.set_item(temp_source_item)
		set_item(temp_target_item)
		
		# Emit move signals instead of add/remove to avoid refresh_display
		source_container.item_moved.emit(temp_source_item, source_pos, target_pos)
		source_container.item_moved.emit(temp_target_item, target_pos, source_pos)
		
		return true
	else:
		# Different containers - use the existing logic but without signals
		var source_success = source_container.remove_item(temp_source_item)
		var target_success = target_container.remove_item(temp_target_item)
		
		if not source_success or not target_success:
			return false
		
		# Clear visual slots
		clear_item()
		target_slot.clear_item()
		
		# Add to new containers at specific positions
		target_container.occupy_grid_area(target_pos, temp_source_item)
		source_container.occupy_grid_area(source_pos, temp_target_item)
		target_container.items.append(temp_source_item)
		source_container.items.append(temp_target_item)
		
		# Reconnect signals
		temp_source_item.quantity_changed.connect(target_container._on_item_quantity_changed)
		temp_source_item.item_modified.connect(target_container._on_item_modified)
		temp_target_item.quantity_changed.connect(source_container._on_item_quantity_changed)
		temp_target_item.item_modified.connect(source_container._on_item_modified)
		
		# Update visual slots
		target_slot.set_item(temp_source_item)
		set_item(temp_target_item)
		
		# Only emit item_added signals for cross-container moves
		target_container.item_added.emit(temp_source_item, target_pos)
		source_container.item_added.emit(temp_target_item, source_pos)
		
		return true

func _handle_move_to_empty(target_slot: InventorySlotUI, inventory_manager: InventoryManager) -> bool:
	var source_container = inventory_manager.get_container(container_id)
	var target_container = inventory_manager.get_container(target_slot.container_id)
	
	if not source_container or not target_container:
		return false
	
	# Check if target container can accept the item
	if not target_container.can_add_item(item, item):
		return false
	
	# Store the item reference before removing it
	var temp_item = item
	
	# For same container moves, use move_item instead of remove/add
	if source_container == target_container:
		var move_success = source_container.move_item(temp_item, target_slot.grid_position)
		if move_success:
			# Update visual slots immediately - NO compacting
			clear_item()
			target_slot.set_item(temp_item)
			return true
		else:
			return false
	
	# For different containers, remove from source and add to target
	var source_success = source_container.remove_item(temp_item)
	if not source_success:
		return false
	
	# Clear the source slot visually
	clear_item()
	
	# Add to target container at the specific position - NO compacting
	var target_success = target_container.add_item(temp_item, target_slot.grid_position)
	if not target_success:
		# Restore to source if target add failed
		source_container.add_item(temp_item, grid_position)
		set_item(temp_item)
		return false
	
	# Set the target slot visually
	target_slot.set_item(temp_item)
	
	return true

# Helper methods
func _get_inventory_grid() -> InventoryGridUI:
	var parent = get_parent()
	while parent:
		if parent is InventoryGridUI:
			return parent
		parent = parent.get_parent()
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

# Signal handlers
func _on_item_quantity_changed(new_quantity: int):
	_update_item_display()
	
	if new_quantity <= 0:
		clear_item()

# Public interface
func set_grid_position(pos: Vector2i):
	grid_position = pos

func get_grid_position() -> Vector2i:
	return grid_position

func set_container_id(id: String):
	container_id = id

func get_container_id() -> String:
	return container_id
