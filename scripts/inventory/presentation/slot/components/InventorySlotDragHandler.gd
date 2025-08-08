# InventorySlotDragHandler.gd - Manages drag and drop functionality for inventory slots
class_name InventorySlotDragHandler
extends RefCounted

# References
var slot: InventorySlot

# Drag state
var is_dragging: bool = false
var drag_start_position: Vector2
var drag_threshold: float = 5.0
var drag_preview_created: bool = false

# Signals
signal drag_started(slot: InventorySlot, item: InventoryItem_Base)
signal drag_ended(slot: InventorySlot, success: bool)
signal item_dropped_on_slot(source_slot: InventorySlot, target_slot: InventorySlot)

func _init(inventory_slot: InventorySlot):
	slot = inventory_slot

func handle_mouse_button(event: InputEventMouseButton):
	"""Handle mouse button events for drag initiation"""
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if slot.has_item():
				is_dragging = true
				drag_preview_created = false
				drag_start_position = event.global_position
		else:
			# Mouse button released
			if is_dragging:
				_handle_drag_end(event.global_position)
				is_dragging = false
				drag_preview_created = false

func handle_mouse_motion(event: InputEventMouseMotion):
	"""Handle mouse motion during drag operations"""
	if not is_dragging or not slot.has_item():
		return
	
	var current_position = event.global_position
	var distance = drag_start_position.distance_to(current_position)
	var inventory_window = _find_inventory_window()
	
	# Start drag preview if we've moved far enough
	if distance > drag_threshold and not drag_preview_created:
		# Check if shift is held and item can be split
		if Input.is_key_pressed(KEY_SHIFT) and slot.get_item().quantity > 1:
			inventory_window.item_actions.show_split_stack_dialog(slot.get_item(), slot)
			is_dragging = false
			drag_preview_created = false
			return
		
		_create_drag_preview()
		drag_preview_created = true
		
		# Store drag data
		var viewport = slot.get_viewport()
		var drag_data = {
			"source_slot": slot,
			"item": slot.get_item(),
			"drag_type": "inventory_item"
		}
		viewport.set_meta("current_drag_data", drag_data)
		
		# Emit drag started signal
		drag_started.emit(slot, slot.get_item())

func _create_drag_preview() -> Control:
	"""Create a visual preview for the dragged item"""
	# Disable integration input processing during drag
	var ui_adapter = _get_ui_input_adapter()
	if ui_adapter:
		ui_adapter.set_drag_in_progress(true)
	var preview = Control.new()
	preview.name = "DragPreview"
	
	# Make the preview smaller
	var scale_factor = 0.8
	preview.size = slot.size * scale_factor
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Copy visual elements
	var preview_bg = Panel.new()
	preview_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if slot.visuals and slot.visuals.background_panel:
		preview_bg.add_theme_stylebox_override("panel", slot.visuals.background_panel.get_theme_stylebox("panel"))
	preview_bg.modulate.a = 0.8
	preview.add_child(preview_bg)
	
	var item = slot.get_item()
	if item and slot.visuals and slot.visuals.item_icon:
		var preview_icon = TextureRect.new()
		preview_icon.texture = slot.visuals.item_icon.texture
		preview_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview_icon.modulate.a = 0.9
		preview.add_child(preview_icon)
		
		# Add quantity label if needed
		if item.quantity > 1:
			var preview_quantity = Label.new()
			preview_quantity.text = str(item.quantity)
			preview_quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			preview_quantity.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			preview_quantity.position = Vector2(preview.size.x - 28 * scale_factor, preview.size.y - 26 * scale_factor)
			preview_quantity.size = Vector2(24 * scale_factor, 20 * scale_factor)
			preview_quantity.add_theme_color_override("font_color", Color.WHITE)
			preview_quantity.add_theme_color_override("font_shadow_color", Color.BLACK)
			preview_quantity.add_theme_constant_override("shadow_offset_x", 1)
			preview_quantity.add_theme_constant_override("shadow_offset_y", 1)
			preview_quantity.add_theme_font_size_override("font_size", int(18 * scale_factor))
			preview.add_child(preview_quantity)
	
	# Add to a high-level canvas layer
	var drag_canvas = CanvasLayer.new()
	drag_canvas.name = "DragCanvas"
	drag_canvas.layer = 100
	slot.get_viewport().add_child(drag_canvas)
	drag_canvas.add_child(preview)
	
	# Store references for cleanup
	preview.set_meta("drag_canvas", drag_canvas)
	preview.set_meta("source_slot", slot)
	
	# Start following mouse
	_update_preview_position(preview)
	
	# Create timer for continuous position updates
	var timer = Timer.new()
	timer.wait_time = 0.016  # ~60 FPS
	timer.timeout.connect(_update_preview_position.bind(preview))
	drag_canvas.add_child(timer)
	timer.start()
	
	preview.set_meta("position_timer", timer)
	return preview

func _update_preview_position(preview: Control):
	"""Update drag preview position to follow mouse"""
	if not is_instance_valid(preview) or not is_dragging:
		# Clean up the timer if dragging stopped
		var timer = preview.get_meta("position_timer", null) if preview else null
		if timer and is_instance_valid(timer):
			timer.stop()
			timer.queue_free()
		return
	
	# Check if this preview belongs to this slot
	var source_slot = preview.get_meta("source_slot", null)
	if source_slot != slot:
		return
	
	var mouse_pos = slot.get_global_mouse_position()
	preview.global_position = mouse_pos - preview.size / 2

func _handle_drag_end(end_position: Vector2):
	"""Handle the end of a drag operation"""
	# Re-enable integration input processing after drag
	var ui_adapter = _get_ui_input_adapter()
	if ui_adapter:
		ui_adapter.set_drag_in_progress(false)

	# Always reset visual state first
	slot.modulate.a = 1.0
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	
	_cleanup_all_drag_previews()
	
	var drop_successful = false
	
	# Find target slot first
	var target_slot = _find_slot_at_position(end_position)
	
	if target_slot and target_slot != slot:
		drop_successful = _attempt_drop_on_slot(target_slot)
	else:
		# Check for other drop targets (virtual content, container list, etc.)
		drop_successful = _attempt_drop_on_other_targets(end_position)
	
	# Clear drag data
	var viewport = slot.get_viewport()
	if viewport and viewport.has_meta("current_drag_data"):
		viewport.remove_meta("current_drag_data")
	
	# Clear highlights
	var content = _find_inventory_content()
	if content and content.has_method("force_clear_highlights"):
		content.force_clear_highlights()
	
	# Reset all drag state
	is_dragging = false
	drag_preview_created = false
	
	drag_ended.emit(slot, drop_successful)

func _cleanup_all_drag_previews():
	"""Clean up all drag preview elements"""
	var viewport = slot.get_viewport()
	if not viewport:
		return
	
	# Find and clean up drag canvases
	for child in viewport.get_children():
		if child is CanvasLayer and child.name == "DragCanvas":
			child.queue_free()

func _find_slot_at_position(global_pos: Vector2) -> InventorySlot:
	"""Find an inventory slot at the given global position"""
	# Implementation would depend on your grid system
	# This is a simplified version
	var grid = _get_inventory_grid()
	if grid and grid.has_method("get_slot_at_position"):
		return grid.get_slot_at_position(global_pos)
	return null

func _attempt_drop_on_slot(target_slot: InventorySlot) -> bool:
	"""Attempt to drop item on another slot"""
	if not target_slot or not slot.has_item():
		return false
	
	# Emit the drop signal first
	item_dropped_on_slot.emit(slot, target_slot)
	
	# Then handle the actual drop
	var inventory_manager = _get_inventory_manager()
	if not inventory_manager:
		return false
	
	# Use the inventory manager's transfer system
	var success = inventory_manager.transfer_item(
		slot.get_item(), 
		slot.container_id, 
		target_slot.container_id, 
		target_slot.grid_position
	)
	
	if success:
		# Update visuals
		slot.visuals.update_item_display()
		target_slot.visuals.update_item_display()
	
	return success

func _attempt_drop_on_other_targets(end_position: Vector2) -> bool:
	"""Attempt to drop on other valid targets"""
	# Check virtual content area
	var grid = _get_inventory_grid()
	if grid and grid.enable_virtual_scrolling and grid.virtual_content:
		var content_rect = Rect2(grid.virtual_content.global_position, grid.virtual_content.size)
		if content_rect.has_point(end_position):
			if grid.has_method("_handle_drop_on_empty_area"):
				return grid._handle_drop_on_empty_area(slot, end_position)
	
	# Check container list drop
	var content = _find_inventory_content()
	if content and slot.has_method("_attempt_drop_on_container_list"):
		return slot._attempt_drop_on_container_list(end_position)
	
	return false

func _get_inventory_grid():
	"""Get the inventory grid"""
	var current = slot.get_parent()
	while current:
		if current.get_script() and current.get_script().get_global_name() == "InventoryGrid":
			return current
		current = current.get_parent()
	return null

func _get_ui_input_adapter():
	"""Get reference to UI input adapter"""
	if not slot:
		return null
		
	var integration = slot.get_tree().get_first_node_in_group("inventory_integration")
	if integration and integration.has_method("get_ui_input_adapter"):
		return integration.get_ui_input_adapter()
	return null

func _find_inventory_content():
	"""Find the inventory content"""
	var current = slot.get_parent()
	while current:
		if current.get_script() and current.get_script().get_global_name() == "InventoryWindowContent":
			return current
		current = current.get_parent()
	return null

func _find_inventory_window():
	"""Find the InventoryWindow in the scene tree"""
	var current = slot.get_parent()
	while current:
		if current.get_script() and current.get_script().get_global_name() == "InventoryWindow":
			return current
		current = current.get_parent()
	return null

func _get_inventory_manager() -> InventoryManager:
	"""Find the inventory manager in the scene hierarchy"""
	# First try the parent chain looking for InventoryWindow
	var current = slot.get_parent()
	while current:
		if current.get_script() and current.get_script().get_global_name() == "InventoryWindow":
			return current.inventory_manager
		current = current.get_parent()
	
	# Fallback - look for InventoryManager in scene tree
	var scene_root = slot.get_tree().current_scene
	return _find_inventory_manager_recursive(scene_root)

func _find_inventory_manager_recursive(node: Node) -> InventoryManager:
	"""Recursively find InventoryManager in scene tree"""
	if node is InventoryManager:
		return node
	
	for child in node.get_children():
		var result = _find_inventory_manager_recursive(child)
		if result:
			return result
	
	return null

func should_handle_input(event: InputEvent) -> bool:
	"""Check if this handler should process the input event"""
	return event is InputEventMouseButton or (event is InputEventMouseMotion and is_dragging)

func cleanup():
	"""Clean up drag handler"""
	_cleanup_all_drag_previews()
	is_dragging = false
	drag_preview_created = false