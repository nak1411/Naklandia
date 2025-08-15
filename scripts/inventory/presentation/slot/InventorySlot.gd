# InventorySlot.gd - Simplified main slot class using component system
class_name InventorySlot
extends Control

# Signals
signal slot_clicked(slot: InventorySlot, event: InputEvent)
signal slot_right_clicked(slot: InventorySlot, event: InputEvent)
signal item_drag_started(slot: InventorySlot, item: InventoryItem_Base)
signal item_drag_ended(slot: InventorySlot, success: bool)
signal item_dropped_on_slot(source_slot: InventorySlot, target_slot: InventorySlot)

# Core properties
@export var slot_size: Vector2 = Vector2(64, 96)
var item: InventoryItem_Base
var grid_position: Vector2i
var container_id: String

# Component systems
var visuals: InventorySlotVisualManager
var drag_handler: InventorySlotDragHandler
var tooltip_manager: InventorySlotTooltipManager

# State (simplified)
var is_highlighted: bool = false
var is_selected: bool = false
var is_hovered: bool = false

# Drag state properties (delegate to drag handler)
var is_dragging: bool:
	get:
		if drag_handler:
			return drag_handler.is_dragging
		return false
	set(value):
		if drag_handler:
			drag_handler.is_dragging = value

var drag_preview_created: bool:
	get:
		if drag_handler:
			return drag_handler.drag_preview_created
		return false
	set(value):
		if drag_handler:
			drag_handler.drag_preview_created = value

var drag_start_position: Vector2:
	get:
		if drag_handler:
			return drag_handler.drag_start_position
		return Vector2.ZERO
	set(value):
		if drag_handler:
			drag_handler.drag_start_position = value


func _init():
	custom_minimum_size = slot_size
	size = slot_size


func _ready():
	_setup_components()
	_connect_signals()

	if visuals and item:
		visuals.update_item_display()


func _setup_components():
	"""Initialize all component systems"""
	visuals = InventorySlotVisualManager.new(self)
	drag_handler = InventorySlotDragHandler.new(self)
	tooltip_manager = InventorySlotTooltipManager.new(self)

	if not visuals:
		push_error("InventorySlot: Failed to create SlotVisualManager")
		return

	if not drag_handler:
		push_error("InventorySlot: Failed to create SlotDragHandler")
		return

	if not tooltip_manager:
		push_error("InventorySlot: Failed to create SlotTooltipManager")
		return

	visuals.setup_visual_components()
	tooltip_manager.setup_tooltip()

	# Connect drag handler signals
	if drag_handler.drag_started.connect(_on_drag_started) != OK:
		push_error("InventorySlot: Failed to connect drag_started signal")
	if drag_handler.drag_ended.connect(_on_drag_ended) != OK:
		push_error("InventorySlot: Failed to connect drag_ended signal")
	if drag_handler.item_dropped_on_slot.connect(_on_item_dropped_on_slot) != OK:
		push_error("InventorySlot: Failed to connect item_dropped_on_slot signal")


func _connect_signals():
	"""Connect internal signals"""
	mouse_filter = Control.MOUSE_FILTER_PASS
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _process(delta):
	"""Process component updates"""
	tooltip_manager.process_tooltip_timer(delta)


func _on_gui_input(event: InputEvent):
	"""Handle input events - delegate to appropriate handlers"""
	if drag_handler.should_handle_input(event):
		if event is InputEventMouseButton:
			drag_handler.handle_mouse_button(event)
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				slot_clicked.emit(self, event)
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				slot_right_clicked.emit(self, event)
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion:
			drag_handler.handle_mouse_motion(event)
	else:
		# Handle non-drag inputs
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				slot_clicked.emit(self, event)
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				slot_right_clicked.emit(self, event)
				get_viewport().set_input_as_handled()


func _on_mouse_entered():
	"""Handle mouse enter - only highlight if slot has an item"""
	is_hovered = true

	# Only set highlighted state for slots WITH items
	if has_item() and not is_highlighted:
		is_highlighted = true
		if visuals:
			visuals.update_visual_state(is_highlighted, is_selected, has_item())

	tooltip_manager.start_tooltip_timer()


func _on_mouse_exited():
	"""Handle mouse exit"""
	is_hovered = false

	# Clear highlighted state when not hovering
	if is_highlighted and not is_selected:
		is_highlighted = false
		if visuals:
			visuals.update_visual_state(is_highlighted, is_selected, has_item())

	tooltip_manager.hide_tooltip()


func _on_drag_started(source_slot: InventorySlot, drag_item: InventoryItem_Base):
	"""Handle drag started"""
	item_drag_started.emit(source_slot, drag_item)


func _on_drag_ended(source_slot: InventorySlot, success: bool):
	"""Handle drag ended"""
	item_drag_ended.emit(source_slot, success)


func _on_item_dropped_on_slot(source_slot: InventorySlot, target_slot: InventorySlot):
	"""Handle item dropped on slot - forward to main signal"""
	item_dropped_on_slot.emit(source_slot, target_slot)


func _update_item_display():
	"""Legacy method - delegate to visual manager"""
	if visuals:
		visuals.update_item_display()
	else:
		# If visuals aren't ready yet, defer the call
		call_deferred("_deferred_update_item_display")


func _update_visual_state():
	"""Legacy method - delegate to visual manager"""
	if visuals:
		visuals.update_visual_state(is_highlighted, is_selected, has_item())


func _deferred_update_item_display():
	"""Deferred version for when visuals aren't ready"""
	if visuals:
		visuals.update_item_display()


func _clear_item_display():
	"""Legacy method - delegate to visual manager"""
	if visuals:
		visuals._clear_item_display()


func _show_hover_glow():
	"""Legacy method - visual effects handled by components now"""
	# This is now handled by mouse_entered signal and tooltip manager


func _hide_hover_glow():
	"""Legacy method - visual effects handled by components now"""
	# This is now handled by mouse_exited signal and tooltip manager


func _show_tooltip():
	"""Legacy method - delegate to tooltip manager"""
	if tooltip_manager:
		tooltip_manager.show_tooltip()


func _hide_tooltip():
	"""Legacy method - delegate to tooltip manager"""
	if tooltip_manager:
		tooltip_manager.hide_tooltip()


func cleanup_glow():
	"""Legacy method - cleanup handled by components"""
	# Cleanup is now handled in _exit_tree() by calling component cleanup methods


func _get_inventory_grid():
	"""Legacy helper method"""
	var current = get_parent()
	while current:
		if current.get_script() and current.get_script().get_global_name() == "InventoryGrid":
			return current
		current = current.get_parent()
	return null


func _show_volume_feedback(can_drop: bool):
	"""Legacy method - visual feedback for volume constraints"""
	if can_drop:
		# Green tint for valid drop
		modulate = Color(0.8, 1.2, 0.8, 1.0)
	else:
		# Red tint for invalid drop (volume exceeded)
		modulate = Color(1.2, 0.8, 0.8, 1.0)


func _clear_volume_feedback():
	"""Legacy method - clear volume feedback colors"""
	modulate = Color(1.0, 1.0, 1.0, 1.0)


# Public API (simplified)
func set_item(new_item: InventoryItem_Base):
	"""Set the item for this slot"""
	item = new_item

	_ensure_components_ready()
	if visuals:
		visuals.update_item_display()


func _ensure_components_ready():
	"""Ensure all components are initialized"""
	if not visuals:
		visuals = InventorySlotVisualManager.new(self)
		if visuals:
			visuals.setup_visual_components()

	if not drag_handler:
		drag_handler = InventorySlotDragHandler.new(self)

	if not tooltip_manager:
		tooltip_manager = InventorySlotTooltipManager.new(self)
		if tooltip_manager:
			tooltip_manager.setup_tooltip()


func clear_item():
	"""Clear the item from this slot"""
	item = null

	_ensure_components_ready()
	if visuals:
		visuals.update_item_display()


func get_item() -> InventoryItem_Base:
	return item


func has_item() -> bool:
	return item != null


func set_highlighted(highlighted: bool):
	"""Set highlight state"""
	is_highlighted = highlighted
	if visuals:
		visuals.update_visual_state(is_highlighted, is_selected, has_item())


func set_selected(selected: bool):
	"""Set selection state"""
	is_selected = selected
	visuals.update_visual_state(is_highlighted, is_selected, has_item())


func set_grid_position(pos: Vector2i):
	"""Set grid position"""
	grid_position = pos


func get_container_id() -> String:
	"""Get the container ID"""
	return container_id


func set_container_id(id: String):
	"""Set container ID"""
	container_id = id


func force_visual_refresh():
	"""Force a complete visual refresh"""
	visuals.force_visual_refresh()


func _trigger_grid_refresh(grid):
	"""Helper to trigger grid refresh - same pattern as list view"""
	if grid and is_instance_valid(grid):
		if grid.enable_virtual_scrolling:
			grid._refresh_virtual_display()
		else:
			grid.refresh_display()


func cleanup():
	"""Clean up all components"""
	if visuals:
		visuals.cleanup()
	if drag_handler:
		drag_handler.cleanup()
	if tooltip_manager:
		tooltip_manager.cleanup()


func _exit_tree():
	"""Clean up when slot is removed"""
	cleanup()


# Legacy methods for compatibility with existing code
func _attempt_drop_on_slot(target_slot: InventorySlot) -> bool:
	"""Legacy method - handle dropping on another slot"""
	if not target_slot or not has_item():
		return false

	var inventory_manager = _get_inventory_manager()
	if not inventory_manager:
		return false

	# Same container - use existing logic
	if target_slot.container_id == container_id:
		return _handle_same_container_drop(target_slot)

	# Different containers - existing cross-container logic
	var target_container = inventory_manager.get_container(target_slot.container_id)
	if not target_container:
		return false

	var available_volume = target_container.get_available_volume()
	var max_transferable = int(available_volume / item.volume) if item.volume > 0 else item.quantity

	if max_transferable <= 0:
		return false

	var transfer_amount = min(item.quantity, max_transferable)

	if target_slot.has_item():
		var target_item = target_slot.get_item()
		if item.can_stack_with(target_item):
			var stack_space = target_item.max_stack_size - target_item.quantity
			transfer_amount = min(transfer_amount, stack_space)

		if transfer_amount <= 0:
			return false

	# Use the transaction manager for the transfer
	var success = inventory_manager.transfer_item(item, container_id, target_slot.container_id, Vector2i(-1, -1), transfer_amount)

	if success:
		if item.quantity <= 0:
			clear_item()
		else:
			visuals.update_item_display()

		# Refresh target display
		target_slot.visuals.update_item_display()

	return success


func _attempt_drop_on_container_list(end_position: Vector2) -> bool:
	"""Legacy method - handle dropping on container list"""
	var content = _find_inventory_content()
	if not content:
		return false

	var container_list = content.container_list
	if not container_list:
		return false

	var container_rect = Rect2(container_list.global_position, container_list.size)

	if not container_rect.has_point(end_position):
		return false

	var local_pos = end_position - container_list.global_position
	var item_index = container_list.get_item_at_position(local_pos, true)

	if item_index == -1 or item_index >= content.open_containers.size():
		return false

	var target_container = content.open_containers[item_index]
	var inventory_manager = _get_inventory_manager()

	if not inventory_manager or not target_container or not has_item():
		return false

	# Check if it's the same container
	if target_container.container_id == container_id:
		return false

	# Calculate transfer amount based on available volume
	var available_volume = target_container.get_available_volume()
	var max_transferable = int(available_volume / item.volume) if item.volume > 0 else item.quantity
	var transfer_amount = min(item.quantity, max_transferable)

	if transfer_amount <= 0:
		return false

	# Perform the transfer
	var success = inventory_manager.transfer_item(item, container_id, target_container.container_id, Vector2i(-1, -1), transfer_amount)

	if success:
		if item.quantity <= 0:
			clear_item()
		else:
			visuals.update_item_display()

	return success


func _handle_same_container_drop(target_slot: InventorySlot) -> bool:
	"""Handle dropping on a slot within the same container"""
	if target_slot.has_item():
		return _handle_occupied_slot_drop(target_slot)

	return _handle_move_to_empty(target_slot)


func _handle_occupied_slot_drop(target_slot: InventorySlot) -> bool:
	"""Handle dropping on a slot that already has an item"""
	var target_item = target_slot.get_item()

	# Try stacking if items are compatible
	if item.can_stack_with(target_item):
		return _handle_stack_merge(target_slot, target_item)

	# Swap items if they can't stack
	return _handle_item_swap(target_slot, target_item)


func _handle_move_to_empty(target_slot: InventorySlot) -> bool:
	"""Handle moving to an empty slot"""
	var temp_item = item
	clear_item()
	target_slot.set_item(temp_item)
	return true


func _handle_stack_merge(target_slot: InventorySlot, target_item: InventoryItem_Base) -> bool:
	"""Handle merging stacks"""
	var space_available = target_item.max_stack_size - target_item.quantity
	var amount_to_transfer = min(item.quantity, space_available)

	if amount_to_transfer <= 0:
		return false

	# Update quantities
	target_item.quantity += amount_to_transfer
	item.quantity -= amount_to_transfer

	# Update target display immediately
	target_slot.visuals.update_item_display()

	if item.quantity <= 0:
		# SAME AS LIST VIEW: Immediately make source slot invisible
		modulate.a = 0.0
		mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Clear the slot properly
		clear_item()

		# Clean up drag state
		if drag_handler:
			drag_handler.is_dragging = false
			drag_handler.drag_preview_created = false

		# Trigger deferred refresh for grid cleanup (like list view does)
		var grid = _get_inventory_grid()
		if grid:
			call_deferred("_trigger_grid_refresh", grid)
	else:
		# Reset visual state and update display
		modulate.a = 1.0
		mouse_filter = Control.MOUSE_FILTER_PASS
		visuals.update_item_display()

		# Clean up drag state
		if drag_handler:
			drag_handler.is_dragging = false
			drag_handler.drag_preview_created = false

	return true


func _handle_item_swap(target_slot: InventorySlot, target_item: InventoryItem_Base) -> bool:
	"""Handle swapping items between slots"""
	var temp_item = item
	clear_item()
	target_slot.clear_item()

	set_item(target_item)
	target_slot.set_item(temp_item)

	return true


# Helper methods
func _get_inventory_manager() -> InventoryManager:
	"""Find the inventory manager"""
	var current = get_parent()
	while current:
		if current.get_script() and current.get_script().get_global_name() == "InventoryWindow":
			return current.inventory_manager
		current = current.get_parent()

	# Fallback - look for InventoryManager in scene
	var scene_root = get_tree().current_scene
	return _find_inventory_manager_recursive(scene_root)


func _find_inventory_manager_recursive(node: Node) -> InventoryManager:
	"""Recursively find InventoryManager"""
	if node is InventoryManager:
		return node

	for child in node.get_children():
		var result = _find_inventory_manager_recursive(child)
		if result:
			return result

	return null


func _find_inventory_content():
	"""Find the inventory content"""
	var current = get_parent()
	while current:
		if current.get_script() and current.get_script().get_global_name() == "InventoryWindowContent":
			return current
		current = current.get_parent()
	return null
