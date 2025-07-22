# InventoryGridUI.gd - Grid-based inventory display with drag-and-drop
class_name InventoryGridUI
extends Control

# Grid properties
@export var slot_size: Vector2 = Vector2(64, 64)
@export var slot_spacing: float = 2.0
@export var grid_width: int = 10
@export var grid_height: int = 10

# Visual properties
@export var background_color: Color = Color(0.1, 0.1, 0.1, 0.9)
@export var grid_line_color: Color = Color(0.3, 0.3, 0.3, 0.5)
@export var grid_line_width: float = 1.0

# Container reference
var container: InventoryContainer
var container_id: String

# UI components
var background_panel: Panel
var grid_container: GridContainer
var slots: Array = []  # 2D array of InventorySlotUI (untyped for 2D array)
var selected_slots: Array[InventorySlotUI] = []

# Drag and drop state
var drag_source_slot: InventorySlotUI
var drag_target_slot: InventorySlotUI
var is_receiving_drag: bool = false

# Signals
signal item_selected(item: InventoryItem, slot: InventorySlotUI)
signal item_activated(item: InventoryItem, slot: InventorySlotUI)
signal item_context_menu(item: InventoryItem, slot: InventorySlotUI, position: Vector2)
signal items_transferred(items: Array[InventoryItem], from_container: String, to_container: String)

func _ready():
	_setup_background()
	_setup_grid()
	
	# Enable focus for keyboard input
	set_focus_mode(Control.FOCUS_ALL)
	
	# Connect to drag and drop system
	set_process_mode(Node.PROCESS_MODE_ALWAYS)

func _setup_background():
	# Background panel
	background_panel = Panel.new()
	background_panel.name = "Background"
	background_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	# Calculate total grid size
	var total_width = grid_width * slot_size.x + (grid_width - 1) * slot_spacing
	var total_height = grid_height * slot_size.y + (grid_height - 1) * slot_spacing
	
	custom_minimum_size = Vector2(total_width, total_height)
	size = custom_minimum_size
	
	# Create grid container
	grid_container = GridContainer.new()
	grid_container.name = "GridContainer"
	grid_container.columns = grid_width
	grid_container.add_theme_constant_override("h_separation", slot_spacing)
	grid_container.add_theme_constant_override("v_separation", slot_spacing)
	grid_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(grid_container)
	
	# Initialize slots array
	slots.clear()
	slots.resize(grid_height)
	for y in grid_height:
		slots[y] = []
		slots[y].resize(grid_width)
	
	# Create slot UI elements
	for y in grid_height:
		for x in grid_width:
			var slot = InventorySlotUI.new()
			slot.slot_size = slot_size
			slot.set_grid_position(Vector2i(x, y))
			slot.set_container_id(container_id)
			
			# Connect slot signals
			slot.slot_clicked.connect(_on_slot_clicked)
			slot.slot_right_clicked.connect(_on_slot_right_clicked)
			slot.drag_started.connect(_on_drag_started)
			slot.drag_ended.connect(_on_drag_ended)
			slot.item_dropped.connect(_on_item_dropped)
			
			slots[y][x] = slot
			grid_container.add_child(slot)

# Container management
func set_container(new_container: InventoryContainer):
	if container:
		_disconnect_container_signals()
	
	container = new_container
	container_id = container.container_id if container else ""
	
	if container:
		grid_width = container.grid_width
		grid_height = container.grid_height
		_connect_container_signals()
		_rebuild_grid()
		refresh_display()

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
	# Clear existing grid
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

func _clear_all_slots():
	for y in grid_height:
		if y >= slots.size():
			continue
			
		for x in grid_width:
			if x >= slots[y].size():
				continue
				
			if slots[y][x]:
				slots[y][x].clear_item()

# Improve the _place_item_in_grid method with debug output
func _place_item_in_grid(item: InventoryItem, position: Vector2i):
	if not _is_valid_position(position):
		return
	
	var item_size = item.get_grid_size()
	
	# Check if we can access the slot
	if position.y >= slots.size() or position.x >= slots[position.y].size():
		return
	
	# Set the main slot (top-left)
	var main_slot = slots[position.y][position.x]
	if not main_slot:
		return
	
	main_slot.set_item(item)
	
	# For multi-slot items, mark occupied slots
	if item_size.x > 1 or item_size.y > 1:
		for y in range(position.y, position.y + item_size.y):
			for x in range(position.x, position.x + item_size.x):
				if _is_valid_position(Vector2i(x, y)) and not (x == position.x and y == position.y):
					if y < slots.size() and x < slots[y].size() and slots[y][x]:
						slots[y][x].is_occupied = true

	
func force_all_slots_refresh():
	print("InventoryGridUI: Forcing visual refresh on all slots...")
	
	var refreshed_count = 0
	
	for y in range(slots.size()):
		for x in range(slots[y].size()):
			var slot = slots[y][x]
			if slot and slot.has_method("force_visual_refresh"):
				slot.force_visual_refresh()
				refreshed_count += 1
	
	print("InventoryGridUI: Refreshed %d slots" % refreshed_count)

# Slot interaction
func _on_slot_clicked(slot: InventorySlotUI, event: InputEvent):
	var mouse_event = event as InputEventMouseButton
	
	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		if Input.is_action_pressed("ui_select_multi"):  # Ctrl/Cmd for multi-select
			_toggle_slot_selection(slot)
		else:
			_select_single_slot(slot)
		
		if slot.has_item():
			item_selected.emit(slot.get_item(), slot)
			
			# Double-click detection for activation
			if mouse_event.double_click:
				item_activated.emit(slot.get_item(), slot)

func _on_slot_right_clicked(slot: InventorySlotUI, event: InputEvent):
	if slot.has_item():
		var mouse_event = event as InputEventMouseButton
		var global_pos = slot.global_position + mouse_event.position
		item_context_menu.emit(slot.get_item(), slot, global_pos)

func _select_single_slot(slot: InventorySlotUI):
	# Clear previous selection
	for selected_slot in selected_slots:
		selected_slot.set_selected(false)
	
	selected_slots.clear()
	
	# Select new slot
	if slot.has_item():
		slot.set_selected(true)
		selected_slots.append(slot)

func _toggle_slot_selection(slot: InventorySlotUI):
	if slot in selected_slots:
		slot.set_selected(false)
		selected_slots.erase(slot)
	else:
		if slot.has_item():
			slot.set_selected(true)
			selected_slots.append(slot)

# Drag and drop handling
func _on_drag_started(slot: InventorySlotUI, item: InventoryItem):
	drag_source_slot = slot
	
	# Highlight valid drop zones
	_highlight_valid_drop_zones(item)

func _on_drag_ended(slot: InventorySlotUI, item: InventoryItem):
	drag_source_slot = null
	
	# Remove drop zone highlights
	_clear_drop_zone_highlights()

func _on_item_dropped(target_slot: InventorySlotUI, dropped_item: InventoryItem):
	if not drag_source_slot or not container:
		return
	
	var source_pos = drag_source_slot.get_grid_position()
	var target_pos = target_slot.get_grid_position()
	
	# Check if this is a move within the same container
	if drag_source_slot.get_container_id() == target_slot.get_container_id():
		_handle_internal_move(dropped_item, source_pos, target_pos)
	else:
		_handle_external_drop(dropped_item, target_slot)

func _handle_internal_move(item: InventoryItem, from_pos: Vector2i, to_pos: Vector2i):
	if container.move_item(item, to_pos):
		refresh_display()

func _handle_external_drop(item: InventoryItem, target_slot: InventorySlotUI):
	# This handles drops from other containers
	var target_container_id = target_slot.get_container_id()
	var source_container_id = drag_source_slot.get_container_id()
	
	# Get inventory manager to handle the transfer
	var inventory_manager = _get_inventory_manager()
	if inventory_manager:
		var target_pos = target_slot.get_grid_position()
		var success = inventory_manager.transfer_item(
			item, source_container_id, target_container_id, target_pos
		)
		
		if success:
			refresh_display()
			items_transferred.emit([item], source_container_id, target_container_id)

func _highlight_valid_drop_zones(item: InventoryItem):
	var item_size = item.get_grid_size()
	
	for y in grid_height:
		for x in grid_width:
			var pos = Vector2i(x, y)
			if container and container.is_area_free(pos, item_size, item):
				var slot = slots[y][x]
				slot.set_highlighted(true)

func _clear_drop_zone_highlights():
	for y in grid_height:
		for x in grid_width:
			if slots[y] and x < slots[y].size():
				var slot = slots[y][x]
				if not slot.is_selected:
					slot.set_highlighted(false)

# Utility functions
func _is_valid_position(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_width and pos.y >= 0 and pos.y < grid_height

func get_slot_at_position(global_pos: Vector2) -> InventorySlotUI:
	for y in grid_height:
		for x in grid_width:
			if slots[y] and x < slots[y].size():
				var slot = slots[y][x]
				var slot_rect = Rect2(slot.global_position, slot.size)
				if slot_rect.has_point(global_pos):
					return slot
	return null

func get_slot_at_grid_position(grid_pos: Vector2i) -> InventorySlotUI:
	if _is_valid_position(grid_pos):
		return slots[grid_pos.y][grid_pos.x]
	return null

func _get_inventory_manager() -> InventoryManager:
	# Find inventory manager in scene tree
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

# Container event handlers
func _on_container_item_added(item: InventoryItem, position: Vector2i):
	refresh_display()

func _on_container_item_removed(item: InventoryItem, position: Vector2i):
	refresh_display()

func _on_container_item_moved(item: InventoryItem, from_pos: Vector2i, to_pos: Vector2i):
	refresh_display()

# Selection management
func get_selected_items() -> Array[InventoryItem]:
	var items: Array[InventoryItem] = []
	for slot in selected_slots:
		if slot.has_item():
			items.append(slot.get_item())
	return items

func clear_selection():
	for slot in selected_slots:
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

# Focus management for keyboard input
func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		grab_focus()

func _can_drop_data(position: Vector2, data) -> bool:
	return data is Dictionary and "item" in data and "source_container" in data

func _drop_data(position: Vector2, data):
	if not _can_drop_data(position, data):
		return
	
	var item = data.item as InventoryItem
	var source_container_id = data.source_container
	var target_slot = get_slot_at_position(global_position + position)
	
	if target_slot:
		_handle_external_drop(item, target_slot)
