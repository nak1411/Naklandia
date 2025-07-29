# InventoryGridUI.gd - Grid-based inventory display with new drag-and-drop system
class_name InventoryGrid
extends Control

# Grid properties
@export var slot_size: Vector2 = Vector2(64, 64)
@export var slot_spacing: int = 2
@export var grid_width: int = 0
@export var grid_height: int = 0

# Visual properties
@export var background_color: Color = Color(0.1, 0.1, 0.1, 0.9)
@export var grid_line_color: Color = Color(0.3, 0.3, 0.3, 0.5)
@export var grid_line_width: float = 1.0

# Container reference
var container: InventoryContainer_Base
var container_id: String

# UI components
var background_panel: Panel
var grid_container: GridContainer
var slots: Array = []  # 2D array of InventorySlotUI
var selected_slots: Array[InventorySlot] = []
var original_grid_styles: Dictionary = {}
var grid_transparency_init: bool = false

# Signals
signal item_selected(item: InventoryItem_Base, slot: InventorySlot)
signal item_activated(item: InventoryItem_Base, slot: InventorySlot)
signal item_context_menu(item: InventoryItem_Base, slot: InventorySlot, position: Vector2)

func _ready():
	_setup_background()
	set_focus_mode(Control.FOCUS_ALL)
	mouse_filter = Control.MOUSE_FILTER_PASS

func _setup_background():
	background_panel = Panel.new()
	background_panel.name = "Background"
	background_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(background_panel)
	
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = background_color
	style_box.border_width_left = 1
	style_box.border_width_right = 1
	style_box.border_width_top = 1
	style_box.border_width_bottom = 1
	style_box.border_color = grid_line_color.lightened(0.3)
	background_panel.add_theme_stylebox_override("panel", style_box)

func _setup_grid():
	if grid_width <= 0 or grid_height <= 0:
		return
	
	# Create grid container
	grid_container = GridContainer.new()
	grid_container.name = "GridContainer"
	grid_container.columns = grid_width
	grid_container.add_theme_constant_override("h_separation", slot_spacing)
	grid_container.add_theme_constant_override("v_separation", slot_spacing)
	grid_container.mouse_filter = Control.MOUSE_FILTER_PASS
	background_panel.add_child(grid_container)
	
	# Initialize slots array
	slots.clear()
	slots.resize(grid_height)
	
	# Create slot UI elements
	for y in grid_height:
		slots[y] = []
		slots[y].resize(grid_width)
		
		for x in grid_width:
			var slot = InventorySlot.new()
			slot.slot_size = slot_size
			slot.set_grid_position(Vector2i(x, y))
			slot.set_container_id(container_id)
			
			# Connect drag and drop signals
			slot.slot_clicked.connect(_on_slot_clicked)
			slot.slot_right_clicked.connect(_on_slot_right_clicked)
			slot.item_drag_started.connect(_on_item_drag_started)
			slot.item_drag_ended.connect(_on_item_drag_ended)
			slot.item_dropped_on_slot.connect(_on_item_dropped_on_slot)
			
			slots[y][x] = slot
			grid_container.add_child(slot)
	
	# Update grid container size
	_update_grid_size()

func _update_grid_size():
	if grid_container:
		var total_width = grid_width * slot_size.x + (grid_width - 1) * slot_spacing
		var total_height = grid_height * slot_size.y + (grid_height - 1) * slot_spacing
		grid_container.custom_minimum_size = Vector2(total_width, total_height)
		custom_minimum_size = Vector2(total_width + 16, total_height + 16)  # Add padding

# Container management
func set_container(new_container: InventoryContainer_Base):
	# If it's the same container, don't rebuild - just refresh display
	if container == new_container and new_container != null:
		refresh_display()
		return
	
	if container:
		_disconnect_container_signals()
	
	container = new_container
	container_id = container.container_id if container else ""
	
	if container:
		# Always update grid size to match container exactly
		grid_width = container.grid_width
		grid_height = container.grid_height
		
		await _rebuild_grid()
		
		_connect_container_signals()
		# Only compact if auto_stack is enabled in inventory manager
		var inventory_manager = _get_inventory_manager()
		if inventory_manager and inventory_manager.auto_stack:
			container.compact_items()
		refresh_display()
	else:
		# No container - clear everything
		grid_width = 0
		grid_height = 0
		if grid_container:
			grid_container.queue_free()
			grid_container = null
		slots.clear()

func _connect_container_signals():
	if container:
		container.item_added.connect(_on_container_item_added)
		container.item_removed.connect(_on_container_item_removed)
		container.item_moved.connect(_on_container_item_moved)

func _disconnect_container_signals():
	if container:
		if container.item_added.is_connected(_on_container_item_added):
			container.item_added.disconnect(_on_container_item_added)
		if container.item_removed.is_connected(_on_container_item_removed):
			container.item_removed.disconnect(_on_container_item_removed)
		if container.item_moved.is_connected(_on_container_item_moved):
			container.item_moved.disconnect(_on_container_item_moved)

func _rebuild_grid():
	if grid_container:
		grid_container.queue_free()
	
	_setup_grid()
	
	# Update all slot container IDs
	for y in grid_height:
		for x in grid_width:
			if slots[y][x]:
				slots[y][x].set_container_id(container_id)

# Display management
func refresh_display():
	if not container:
		_clear_all_slots()
		return
	
	# Clear all slots first
	_clear_all_slots()
	
	# Place items in their grid positions
	for item in container.items:
		var position = container.get_item_position(item)
		if position != Vector2i(-1, -1):
			_place_item_in_grid(item, position)
		else:
			# If item has no position, find next available spot
			var free_pos = _find_first_free_position()
			if free_pos != Vector2i(-1, -1):
				container.move_item(item, free_pos)
				_place_item_in_grid(item, free_pos)
	
	# Force visual refresh on all slots
	force_all_slots_refresh()

func _find_first_free_position() -> Vector2i:
	for y in grid_height:
		for x in grid_width:
			if y < slots.size() and x < slots[y].size():
				var slot = slots[y][x]
				if slot and not slot.has_item():
					return Vector2i(x, y)
	return Vector2i(-1, -1)

func _clear_all_slots():
	for y in grid_height:
		if y >= slots.size():
			continue
		for x in grid_width:
			if x >= slots[y].size():
				continue
			if slots[y][x]:
				slots[y][x].clear_item()

func _place_item_in_grid(item: InventoryItem_Base, position: Vector2i):
	if not _is_valid_position(position):
		return
	
	if position.y >= slots.size() or position.x >= slots[position.y].size():
		return
	
	var slot = slots[position.y][position.x]
	if slot:
		slot.set_item(item)

func force_all_slots_refresh():
	for y in range(slots.size()):
		for x in range(slots[y].size()):
			var slot = slots[y][x]
			if slot and slot.has_method("force_visual_refresh"):
				slot.force_visual_refresh()

# Input handling for focus management
func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed:
			# Focus the inventory window when clicking anywhere in the grid
			_focus_inventory_window()
			
			if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
				# Handle right-click on empty area
				var clicked_slot = get_slot_at_position(mouse_event.global_position)
				if not clicked_slot or not clicked_slot.has_item():
					# Right-clicked on empty area - show empty area context menu
					_show_empty_area_context_menu(mouse_event.global_position)
					get_viewport().set_input_as_handled()
		
		# Always grab focus for keyboard input
		grab_focus()
		
func _is_shift_held() -> bool:
	"""Check if shift key is currently held down"""
	return Input.is_key_pressed(KEY_SHIFT)

func _is_ctrl_held() -> bool:
	"""Check if ctrl key is currently held down"""
	return Input.is_key_pressed(KEY_CTRL)

func _focus_inventory_window():
	# Find the inventory window and focus it
	var current_node = get_parent()
	while current_node:
		if current_node is Window:
			current_node.grab_focus()
			break
		current_node = current_node.get_parent()
		
func _check_for_active_dialogs() -> bool:
	"""Check if there are any active dialogs that should prevent focus changes"""
	var viewport = get_viewport()
	if not viewport:
		return false
	
	# Look for any dialogs with high z_index (our dialog windows)
	for child in viewport.get_children():
		if child is AcceptDialog or child is ConfirmationDialog:
			if child.visible and child.z_index >= 2000:
				return true
	
	return false

func _show_empty_area_context_menu(global_pos: Vector2):
	# Find the item actions handler and show empty area menu
	var inventory_window = _find_inventory_window()
	if inventory_window and inventory_window.has_method("_show_empty_area_context_menu"):
		inventory_window._show_empty_area_context_menu(global_pos)

func _find_inventory_window():
	var current_node = get_parent()
	while current_node:
		if current_node.get_script() and current_node.get_script().get_global_name() == "InventoryWindowUI":
			return current_node
		current_node = current_node.get_parent()
	return null

# Slot interaction handlers
func _on_slot_clicked(slot: InventorySlot, event: InputEvent):
	# Focus window on any slot click
	_focus_inventory_window()
	
	var mouse_event = event as InputEventMouseButton
	
	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		if Input.is_action_pressed("ui_select_multi"):
			_toggle_slot_selection(slot)
		else:
			_select_single_slot(slot)
		
		if slot.has_item():
			item_selected.emit(slot.get_item(), slot)
			
			if mouse_event.double_click:
				item_activated.emit(slot.get_item(), slot)

func _on_slot_right_clicked(slot: InventorySlot, event: InputEvent):
	# Focus window on right click
	_focus_inventory_window()
	
	if slot.has_item():
		var mouse_event = event as InputEventMouseButton
		var global_pos = mouse_event.global_position
		item_context_menu.emit(slot.get_item(), slot, global_pos)
		get_viewport().set_input_as_handled()

func _select_single_slot(slot: InventorySlot):
	for selected_slot in selected_slots:
		if is_instance_valid(selected_slot):
			selected_slot.set_selected(false)
	
	selected_slots.clear()
	
	if slot and is_instance_valid(slot) and slot.has_item():
		slot.set_selected(true)
		selected_slots.append(slot)

func _toggle_slot_selection(slot: InventorySlot):
	if not slot or not is_instance_valid(slot):
		return
		
	if slot in selected_slots:
		slot.set_selected(false)
		selected_slots.erase(slot)
	else:
		if slot.has_item():
			slot.set_selected(true)
			selected_slots.append(slot)

# New drag and drop handlers
func _on_item_drag_started(slot: InventorySlot, item: InventoryItem_Base):
	# Highlight valid drop targets
	_highlight_valid_drop_targets(item)
	
	# Dim the source slot
	slot.modulate.a = 0.5

func _on_item_drag_ended(slot: InventorySlot, success: bool):
	# Clear highlighting on all slots, including the source slot
	_clear_all_highlights()
	
	# Restore source slot appearance
	slot.modulate.a = 1.0
	
	# Refresh display after any successful drop
	if success:
		call_deferred("refresh_display")

func _on_item_dropped_on_slot(_source_slot: InventorySlot, _target_slot: InventorySlot):
	# This is called after a successful drop operation
	# The container has already been updated, so just update UI info
	
	# Update container info in parent window if available
	call_deferred("_update_parent_info")

func _update_parent_info():
	if get_parent() and get_parent().has_method("_update_mass_info"):
		get_parent()._update_mass_info()
	
	if get_parent() and get_parent().has_method("refresh_container_list"):
		get_parent().refresh_container_list()

func _highlight_valid_drop_targets(dragged_item: InventoryItem_Base):
	for y in grid_height:
		for x in grid_width:
			var slot = slots[y][x]
			if not slot:
				continue
			
			var can_drop = false
			
			if not slot.has_item():
				# Empty slot - always valid
				can_drop = true
			elif slot.has_item():
				var target_item = slot.get_item()
				# Can stack or swap
				can_drop = dragged_item.can_stack_with(target_item) or true  # Always allow swapping
			
			if can_drop:
				slot.set_highlighted(true)

func _clear_drop_target_highlights():
	for y in grid_height:
		for x in grid_width:
			var slot = slots[y][x]
			if slot:
				slot.set_highlighted(false)

func _clear_all_highlights():
	"""Clear all highlighting from all slots"""
	for y in grid_height:
		for x in grid_width:
			var slot = slots[y][x]
			if slot:
				slot.set_highlighted(false)
				slot.set_selected(false)

# Utility functions
func _is_valid_position(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_width and pos.y >= 0 and pos.y < grid_height

func get_slot_at_position(global_pos: Vector2) -> InventorySlot:
	for y in grid_height:
		for x in grid_width:
			if y < slots.size() and x < slots[y].size():
				var slot = slots[y][x]
				if not slot:
					continue
				
				var slot_rect = Rect2(slot.global_position, slot.size)
				if slot_rect.has_point(global_pos):
					return slot
	return null

func get_slot_at_grid_position(grid_pos: Vector2i) -> InventorySlot:
	if _is_valid_position(grid_pos):
		return slots[grid_pos.y][grid_pos.x]
	return null

# Container event handlers - DISABLE these during drag operations
func _on_container_item_added(_item: InventoryItem_Base, _position: Vector2i):
	# Don't refresh during drag operations
	if not _is_any_slot_dragging():
		refresh_display()

func _on_container_item_removed(_item: InventoryItem_Base, _position: Vector2i):
	# Don't refresh during drag operations
	if not _is_any_slot_dragging():
		refresh_display()

func _on_container_item_moved(_item: InventoryItem_Base, _from_pos: Vector2i, _to_pos: Vector2i):
	# Don't refresh during drag operations
	if not _is_any_slot_dragging():
		refresh_display()

func _is_any_slot_dragging() -> bool:
	for y in grid_height:
		for x in grid_width:
			if y < slots.size() and x < slots[y].size():
				var slot = slots[y][x]
				if slot and slot.is_dragging:
					return true
	return false

# Selection management
func get_selected_items() -> Array[InventoryItem_Base]:
	var items: Array[InventoryItem_Base] = []
	for slot in selected_slots:
		if slot.has_item():
			items.append(slot.get_item())
	return items

func clear_selection():
	for slot in selected_slots:
		if is_instance_valid(slot):
			slot.set_selected(false)
	selected_slots.clear()

# Keyboard shortcuts
func _unhandled_key_input(event: InputEvent):
	if not has_focus():
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_A:
				if Input.is_action_pressed("ui_select_multi"):
					_select_all_items()
			KEY_DELETE:
				_delete_selected_items()
			KEY_ESCAPE:
				clear_selection()

func _select_all_items():
	clear_selection()
	for y in grid_height:
		for x in grid_width:
			var slot = slots[y][x]
			if slot and slot.has_item():
				slot.set_selected(true)
				selected_slots.append(slot)

func _delete_selected_items():
	var inventory_manager = _get_inventory_manager()
	if not inventory_manager:
		return
	
	for slot in selected_slots.duplicate():
		if slot.has_item():
			var item = slot.get_item()
			if item.can_be_destroyed:
				inventory_manager.remove_item_from_container(item, container_id)
	
	clear_selection()

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

# Public interface
func set_grid_size(width: int, height: int):
	grid_width = width
	grid_height = height
	_rebuild_grid()

func get_grid_size() -> Vector2i:
	return Vector2i(grid_width, grid_height)

func set_slot_size(new_size: Vector2):
	slot_size = new_size
	for y in grid_height:
		for x in grid_width:
			if slots[y] and x < slots[y].size():
				slots[y][x].slot_size = new_size
				
func set_transparency(transparency: float):
	# Store originals on first call
	if not grid_transparency_init:
		_store_original_grid_styles()
		grid_transparency_init = true
	
	modulate.a = transparency
	
	# Apply transparency using stored originals
	_apply_grid_transparency_from_originals(transparency)

func _store_original_grid_styles():
	if background_panel:
		var style = background_panel.get_theme_stylebox("panel")
		if style and style is StyleBoxFlat:
			original_grid_styles["background_panel"] = style.duplicate()

func _apply_grid_transparency_from_originals(transparency: float):
	# Apply to background panel
	if background_panel and original_grid_styles.has("background_panel"):
		var original = original_grid_styles["background_panel"] as StyleBoxFlat
		var new_style = original.duplicate() as StyleBoxFlat
		var orig_color = original.bg_color
		new_style.bg_color = Color(orig_color.r, orig_color.g, orig_color.b, orig_color.a * transparency)
		background_panel.add_theme_stylebox_override("panel", new_style)
	
	# Apply transparency to all inventory slots
	for row in slots:
		if row:
			for slot in row:
				if slot and slot.has_method("set_transparency"):
					slot.set_transparency(transparency)
