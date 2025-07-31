# InventoryGridUI.gd - Grid-based inventory display with volume-based infinite slots
class_name InventoryGrid
extends Control

# Grid properties
@export var slot_size: Vector2 = Vector2(64, 64)
@export var slot_spacing: int = 0
@export var min_grid_width: int = 10  # Minimum grid width
@export var min_grid_height: int = 10  # Minimum grid height
@export var slots_per_row_expansion: int = 2  # How many columns to add when expanding


# Visual properties
@export var background_color: Color = Color(0.1, 0.1, 0.1, 1.0)
@export var grid_line_color: Color = Color(0.1, 0.1, 0.1, 1.0)
@export var grid_line_width: float = 1.0

# Container reference
var container: InventoryContainer_Base
var window = InventoryWindowContent
var container_id: String

# Dynamic grid properties
var current_grid_width: int = 0
var current_grid_height: int = 0
var available_slots: Array = []  # Track which slots are available
var _is_expanding_grid: bool = false
var _is_shrinking_grid: bool = false
var _is_refreshing_display: bool = false
var item_positions: Dictionary = {}  # Dictionary[InventoryItem_Base, Vector2i]
var _is_adapting_width: bool = false
var _resize_timer: Timer = null
var _resize_complete_timer: Timer
var _pending_width_refresh: bool = false
var _last_known_width: int = 0
var _needs_reflow: bool = false

# UI components
var background_panel: Panel
var grid_container: GridContainer
var slots: Array = []  # 2D array of InventorySlotUI
var selected_slots: Array[InventorySlot] = []
var original_grid_styles: Dictionary = {}
var grid_transparency_init: bool = false
var current_filter_type: int = 0  # 0 = All Items
var current_search_text: String = ""

# Signals
signal item_selected(item: InventoryItem_Base, slot: InventorySlot)
signal item_activated(item: InventoryItem_Base, slot: InventorySlot)
signal item_context_menu(item: InventoryItem_Base, slot: InventorySlot, position: Vector2)

func _ready():
	_setup_background()
	set_focus_mode(Control.FOCUS_ALL)
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Create timer for resize complete handling
	_resize_complete_timer = Timer.new()
	_resize_complete_timer.wait_time = 0.1
	_resize_complete_timer.one_shot = true
	_resize_complete_timer.timeout.connect(_perform_compact_reflow)
	add_child(_resize_complete_timer)
	
func handle_resize_complete():
	"""Called when window resize is complete"""
	print("Grid handling resize complete")
	_resize_complete_timer.start()

func _perform_compact_reflow():
	"""Perform a compact reflow of all items"""
	if not container:
		return
	
	print("Performing compact reflow")
	
	# Temporarily disable all refresh operations
	_is_refreshing_display = true
	
	# Calculate new grid width based on current size
	var available_width = size.x - 16
	if available_width <= slot_size.x:
		_is_refreshing_display = false
		return
	
	var slots_per_row = max(1, int(available_width / (slot_size.x + slot_spacing)))
	var new_width = max(1, min(slots_per_row, 20))
	
	# Get all visible items
	var items_to_place: Array[InventoryItem_Base] = []
	for item in container.items:
		if _should_show_item(item):
			items_to_place.append(item)
	
	print("Reflowing ", items_to_place.size(), " items into ", new_width, " columns")
	
	# Calculate required height
	var required_rows = (items_to_place.size() + new_width - 1) / new_width if items_to_place.size() > 0 else min_grid_height
	var new_height = max(min_grid_height, required_rows + 1)
	
	# Update dimensions
	current_grid_width = new_width
	current_grid_height = new_height
	
	# Ensure we have enough slots
	_ensure_adequate_slots()
	
	# Clear ALL slots completely
	_clear_all_slots_completely()
	
	# Place items in compact order
	_place_items_compactly(items_to_place)
	
	# Update grid container
	if grid_container:
		grid_container.columns = current_grid_width
	
	_update_grid_size()
	force_all_slots_refresh()
	
	_is_refreshing_display = false
	
	print("Reflow complete: ", current_grid_width, "x", current_grid_height)

func _ensure_adequate_slots():
	"""Ensure we have enough slots for the current dimensions"""
	var needed_total = current_grid_width * current_grid_height
	var current_total = 0
	
	for row in slots:
		if row:
			current_total += row.size()
	
	if current_total >= needed_total and slots.size() == current_grid_height:
		return # We have enough
	
	print("Rebuilding slots: need ", needed_total, ", have ", current_total)
	_rebuild_slots_completely()

func _rebuild_slots_completely():
	"""Completely rebuild the slots structure"""
	# Disconnect container signals temporarily
	_disconnect_container_signals()
	
	# Clear existing
	for row in slots:
		if row:
			for slot in row:
				if slot:
					slot.queue_free()
	
	# Clear the grid container
	if grid_container:
		for child in grid_container.get_children():
			child.queue_free()
	
	slots.clear()
	available_slots.clear()
	
	# Wait for cleanup
	await get_tree().process_frame
	
	# Rebuild
	slots.resize(current_grid_height)
	for y in current_grid_height:
		slots[y] = []
		slots[y].resize(current_grid_width)
		
		for x in current_grid_width:
			var slot = InventorySlot.new()
			slot.slot_size = slot_size
			slot.set_grid_position(Vector2i(x, y))
			slot.set_container_id(container_id)
			
			# Connect signals
			slot.slot_clicked.connect(_on_slot_clicked)
			slot.slot_right_clicked.connect(_on_slot_right_clicked)
			slot.item_drag_started.connect(_on_item_drag_started)
			slot.item_drag_ended.connect(_on_item_drag_ended)
			slot.item_dropped_on_slot.connect(_on_item_dropped_on_slot)
			
			slots[y][x] = slot
			grid_container.add_child(slot)
			available_slots.append(Vector2i(x, y))
	
	# Reconnect container signals
	_connect_container_signals()

func _clear_all_slots_completely():
	"""Clear all slots of items"""
	for row in slots:
		if row:
			for slot in row:
				if slot:
					slot.clear_item()
	
	# Reset available slots
	available_slots.clear()
	for y in current_grid_height:
		for x in current_grid_width:
			available_slots.append(Vector2i(x, y))

func _place_items_compactly(items: Array[InventoryItem_Base]):
	"""Place items in compact left-to-right, top-to-bottom order"""
	var item_index = 0
	
	for y in current_grid_height:
		for x in current_grid_width:
			if item_index >= items.size():
				return
			
			if y < slots.size() and x < slots[y].size():
				var slot = slots[y][x]
				if slot:
					var item = items[item_index]
					slot.set_item(item)
					available_slots.erase(Vector2i(x, y))
					item_index += 1
	
func _handle_resize_complete():
	"""Called after resize is complete - just adjust the minimum grid width"""
	if not container or size.x <= 0:
		return
	
	var available_width = size.x - 16
	if available_width <= slot_size.x:
		return
	
	var slot_width_with_spacing = slot_size.x + slot_spacing
	var max_columns = max(1, int(available_width / slot_width_with_spacing))
	var ideal_width = max(1, max_columns)
	
	# Only change min_grid_width, don't touch current_grid_width
	if ideal_width != min_grid_width:
		min_grid_width = ideal_width
		
		# Let the existing system handle everything
		if container:
			call_deferred("refresh_display")

func _setup_background():
	background_panel = Panel.new()
	background_panel.name = "Background"
	background_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(background_panel)
	
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = background_color
	background_panel.add_theme_stylebox_override("panel", style_box)

func _setup_grid():
	# Start with minimum grid size
	current_grid_width = min_grid_width
	current_grid_height = min_grid_height
	
	# Create grid container
	grid_container = GridContainer.new()
	grid_container.name = "GridContainer"
	grid_container.columns = current_grid_width
	grid_container.add_theme_constant_override("h_separation", 0)
	grid_container.add_theme_constant_override("v_separation", 0)
	grid_container.mouse_filter = Control.MOUSE_FILTER_PASS
	background_panel.add_child(grid_container)
	
	# Initialize slots array and available slots
	_initialize_slot_arrays()
	_create_initial_slots()
	

func _initialize_slot_arrays():
	slots.clear()
	available_slots.clear()
	slots.resize(current_grid_height)
	
	for y in current_grid_height:
		slots[y] = []
		slots[y].resize(current_grid_width)
		for x in current_grid_width:
			available_slots.append(Vector2i(x, y))
			
func _create_initial_slots():
	# Create slot UI elements
	for y in current_grid_height:
		for x in current_grid_width:
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

func _perform_reflow():
	"""Reflow items into new grid layout"""
	if not container or not _needs_reflow:
		return
	
	_needs_reflow = false
	
	# Calculate new grid width based on available space
	var available_width = size.x - 16
	if available_width <= slot_size.x:
		return
	
	var slots_per_row = max(1, int(available_width / (slot_size.x + slot_spacing)))
	var new_width = max(1, min(slots_per_row, 20))  # Cap at reasonable maximum
	
	if new_width == current_grid_width:
		return  # No change needed
	
	# Collect all items that should be visible
	var items_to_place: Array[InventoryItem_Base] = []
	for item in container.items:
		if _should_show_item(item):
			items_to_place.append(item)
	
	if items_to_place.is_empty():
		return
	
	# Calculate required height
	var required_rows = (items_to_place.size() + new_width - 1) / new_width
	var new_height = max(min_grid_height, required_rows + 1)
	
	# Update dimensions
	current_grid_width = new_width
	current_grid_height = new_height
	
	# Rebuild grid structure if needed
	_ensure_grid_size()
	
	# Clear all slots
	_clear_all_slots()
	
	# Place items in simple left-to-right, top-to-bottom order
	var item_index = 0
	for row in range(current_grid_height):
		for col in range(current_grid_width):
			if item_index < items_to_place.size():
				var item = items_to_place[item_index]
				var position = Vector2i(col, row)
				_place_item_at_position(item, position)
				item_index += 1
			else:
				break
		if item_index >= items_to_place.size():
			break
	
	# Update grid container
	if grid_container:
		grid_container.columns = current_grid_width
	
	_update_grid_size()
	force_all_slots_refresh()

func _ensure_grid_size():
	"""Ensure we have enough slots for current dimensions"""
	var needed_slots = current_grid_width * current_grid_height
	var current_slots = 0
	
	for row in slots:
		if row:
			current_slots += row.size()
	
	if needed_slots <= current_slots and slots.size() == current_grid_height:
		return  # We have enough slots
	
	# Need to rebuild slots
	_rebuild_slots_structure()

func _rebuild_slots_structure():
	"""Rebuild the slots array structure"""
	# Clear existing slots
	for row in slots:
		if row:
			for slot in row:
				if slot:
					slot.queue_free()
	
	slots.clear()
	available_slots.clear()
	
	# Wait for cleanup
	await get_tree().process_frame
	
	# Create new structure
	slots.resize(current_grid_height)
	for y in current_grid_height:
		slots[y] = []
		slots[y].resize(current_grid_width)
		
		for x in current_grid_width:
			var slot = InventorySlot.new()
			slot.slot_size = slot_size
			slot.set_grid_position(Vector2i(x, y))
			slot.set_container_id(container_id)
			
			# Connect signals
			slot.slot_clicked.connect(_on_slot_clicked)
			slot.slot_right_clicked.connect(_on_slot_right_clicked)
			slot.item_drag_started.connect(_on_item_drag_started)
			slot.item_drag_ended.connect(_on_item_drag_ended)
			slot.item_dropped_on_slot.connect(_on_item_dropped_on_slot)
			
			slots[y][x] = slot
			grid_container.add_child(slot)
			available_slots.append(Vector2i(x, y))

func _place_item_at_position(item: InventoryItem_Base, position: Vector2i):
	"""Place an item at a specific grid position"""
	if position.y >= slots.size() or position.x >= slots[position.y].size():
		return
	
	var slot = slots[position.y][position.x]
	if slot:
		slot.set_item(item)
		available_slots.erase(position)

func _calculate_required_slots() -> int:
	"""Calculate how many slots we need based on current items - NO RECURSION"""
	if not container:
		return min_grid_width * min_grid_height
	
	# Simple calculation: number of items + small buffer
	var items_count = container.items.size()
	var buffer_slots = 10  # Fixed buffer instead of volume-based calculation
	var total_needed = items_count + buffer_slots
	var min_required = min_grid_width * min_grid_height
	
	return max(total_needed, min_required)

func _expand_grid_if_needed():
	"""Expand the grid if we need more slots - PREVENT RECURSION"""
	# Prevent recursive calls during expansion
	if _is_expanding_grid:
		return
	
	_is_expanding_grid = true
	
	var required_slots = _calculate_required_slots()
	var current_slots = current_grid_width * current_grid_height
	
	if required_slots <= current_slots:
		_is_expanding_grid = false
		return  # No expansion needed
	
	# Calculate new grid dimensions
	var slots_to_add = required_slots - current_slots
	var rows_to_add = (slots_to_add + current_grid_width - 1) / current_grid_width  # Ceiling division
	
	var new_height = current_grid_height + rows_to_add
	
	# Update grid dimensions
	current_grid_height = new_height
	grid_container.columns = current_grid_width
	
	# Resize slots array
	slots.resize(current_grid_height)
	
	# Create new rows
	for y in range(current_grid_height - rows_to_add, current_grid_height):
		slots[y] = []
		slots[y].resize(current_grid_width)
		
		for x in current_grid_width:
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
			
			# Add to available slots
			available_slots.append(Vector2i(x, y))
	
	_update_grid_size()
	_is_expanding_grid = false

func _shrink_grid_if_possible():
	"""Shrink the grid if we have too many empty rows - PREVENT RECURSION"""
	# Prevent recursive calls during shrinking
	if _is_shrinking_grid or not container:
		return
	
	_is_shrinking_grid = true
	
	# Find the last row with an item
	var last_used_row = -1
	for item in container.items:
		var pos = container.get_item_position(item)
		if pos != Vector2i(-1, -1):
			last_used_row = max(last_used_row, pos.y)
	
	# Keep at least min_grid_height and add 2 rows buffer
	var target_height = max(min_grid_height, last_used_row + 3)
	
	if target_height >= current_grid_height:
		_is_shrinking_grid = false
		return  # No shrinking needed
	
	# Remove excess rows
	var rows_to_remove = current_grid_height - target_height
	
	for y in range(target_height, current_grid_height):
		if y < slots.size():
			for x in current_grid_width:
				if x < slots[y].size() and slots[y][x]:
					slots[y][x].queue_free()
					# Remove from available slots
					available_slots.erase(Vector2i(x, y))
	
	# Resize arrays
	slots.resize(target_height)
	current_grid_height = target_height
	
	_update_grid_size()
	_is_shrinking_grid = false

func _update_available_slots():
	"""Update the list of available slots based on our position tracking"""
	available_slots.clear()
	
	for y in current_grid_height:
		for x in current_grid_width:
			var pos = Vector2i(x, y)
			var is_occupied = false
			
			# Check if any item occupies this position in our tracking
			for item in item_positions.keys():
				if item_positions[item] == pos:
					is_occupied = true
					break
			
			if not is_occupied:
				available_slots.append(pos)

func _can_add_item_volume_check(item: InventoryItem_Base) -> bool:
	"""Check if we can add an item based on volume constraints only"""
	if not container:
		return false
	
	return container.has_volume_for_item(item)

func _update_grid_size():
	if grid_container:
		var total_height = current_grid_height * slot_size.y + (current_grid_height - 1) * slot_spacing
		grid_container.custom_minimum_size = Vector2(0, total_height)
		custom_minimum_size = Vector2(0, total_height + 16)

# Container management
func set_container(new_container: InventoryContainer_Base):
	# Clear position tracking when changing containers
	item_positions.clear()
	
	# If it's the same container, don't rebuild - just refresh display
	if container == new_container and new_container != null:
		refresh_display()
		return
	
	if container:
		_disconnect_container_signals()
	
	container = new_container
	container_id = container.container_id if container else ""
	
	if container:
		# Override container grid size - we manage our own now
		await _rebuild_grid()
		
		_connect_container_signals()
		# Only compact if auto_stack is enabled in inventory manager
		var inventory_manager = _get_inventory_manager()
		if inventory_manager and inventory_manager.auto_stack:
			container.compact_items()
		refresh_display()
	else:
		# No container - clear everything
		current_grid_width = min_grid_width
		current_grid_height = min_grid_height
		if grid_container:
			grid_container.queue_free()
			grid_container = null
		slots.clear()
		available_slots.clear()

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
	for y in current_grid_height:
		for x in current_grid_width:
			if y < slots.size() and x < slots[y].size() and slots[y][x]:
				slots[y][x].set_container_id(container_id)

# Display management
func refresh_display():
	if not container or _is_refreshing_display or _needs_reflow:
		if not container:
			_clear_all_slots()
		return
	
	# If we haven't done initial sizing, do it now
	if current_grid_width == 0 or current_grid_height == 0:
		current_grid_width = min_grid_width
		current_grid_height = min_grid_height
		_setup_grid()
	
	_is_refreshing_display = true
	
	# Expand grid if needed
	if not _is_expanding_grid:
		_expand_grid_if_needed()
	
	# Clear and place items normally
	_clear_all_slots()
	_update_available_slots()
	
	for item in container.items:
		if not _should_show_item(item):
			continue
		
		var free_pos = _find_first_free_position()
		if free_pos != Vector2i(-1, -1):
			_place_item_in_grid(item, free_pos)
	
	force_all_slots_refresh()
	_is_refreshing_display = false

func _find_first_free_position() -> Vector2i:
	# Return the first available slot from our tracked list
	if available_slots.size() > 0:
		return available_slots[0]
	
	# Fallback to traditional search if available_slots is somehow empty
	for y in current_grid_height:
		for x in current_grid_width:
			if y < slots.size() and x < slots[y].size():
				var slot = slots[y][x]
				if slot and not slot.has_item():
					return Vector2i(x, y)
	
	return Vector2i(-1, -1)

func _clear_all_slots():
	for y in current_grid_height:
		if y >= slots.size():
			continue
		for x in current_grid_width:
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
		# Set the position in our tracking
		item_positions[item] = position
		# Set the item in the slot
		slot.set_item(item)
		# Remove from available slots
		available_slots.erase(position)

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
					# Right-clicked on empty area - show container menu
					_show_container_context_menu(mouse_event.global_position)

func _focus_inventory_window():
	"""Focus the inventory window for keyboard input"""
	var parent = get_parent()
	while parent:
		if parent.has_method("grab_focus"):
			parent.set_focus_mode(Control.FOCUS_ALL)
			parent.grab_focus()
			break
		parent = parent.get_parent()

func _show_container_context_menu(position: Vector2):
	"""Show context menu for container operations"""
	# This will be implemented by the UI system
	pass
		
func _single_refresh_after_resize():
	"""Single refresh after resize is complete"""
	if not _is_refreshing_display and not _is_adapting_width:
		refresh_display()
		
func _get_items_in_visual_order() -> Array[InventoryItem_Base]:
	"""Get items in their current visual order (top-to-bottom, left-to-right)"""
	var ordered_items: Array[InventoryItem_Base] = []
	
	# Go through slots in reading order and collect items
	for y in current_grid_height:
		if y >= slots.size():
			continue
		if slots[y] == null:  # Check if the row exists
			continue
		for x in current_grid_width:
			if x >= slots[y].size():
				continue
			var slot = slots[y][x]
			if slot == null:  # Check if the slot exists
				continue
			if slot.has_item():
				var item = slot.get_item()
				if item and _should_show_item(item):
					ordered_items.append(item)
	
	# If we didn't get all items from slots (shouldn't happen), add any missing ones
	for item in container.items:
		if _should_show_item(item) and item not in ordered_items:
			ordered_items.append(item)
	
	return ordered_items

func _place_items_in_reading_order(items: Array[InventoryItem_Base]):
	"""Place items in reading order (left-to-right, top-to-bottom)"""
	var item_index = 0
	
	for y in current_grid_height:
		for x in current_grid_width:
			if item_index >= items.size():
				return  # No more items to place
			
			if y < slots.size() and x < slots[y].size():
				var slot = slots[y][x]
				if slot:
					var item = items[item_index]
					slot.set_item(item)
					available_slots.erase(Vector2i(x, y))
					item_index += 1

func _clear_all_container_positions():
	"""Clear all item positions in the container to avoid conflicts"""
	if not container:
		return
	
	# Temporarily disconnect signals to avoid triggering refresh_display
	_disconnect_container_signals()
	
	# Clear grid positions for all items
	for item in container.items:
		if container.has_method("clear_item_position"):
			container.clear_item_position(item)
		elif container.has_method("set_item_position"):
			container.set_item_position(item, Vector2i(-1, -1))
	
	# Reconnect signals
	_connect_container_signals()

func _refresh_after_width_change():
	"""Safely refresh display after width change"""
	if not container:
		return
	
	_is_refreshing_display = true
	
	# Clear all visual slots first
	_clear_all_slots()
	
	# Update available slots list for new dimensions
	_update_available_slots()
	
	# Reposition all items without regard to their old positions
	for item in container.items:
		if not _should_show_item(item):
			continue
		
		# Find the next available position and place the item there
		var free_pos = _find_first_free_position()
		if free_pos != Vector2i(-1, -1):
			# Set the new position in the container
			if container.has_method("set_item_position"):
				container.set_item_position(item, free_pos)
			elif container.has_method("move_item"):
				container.move_item(item, free_pos)
			
			# Place visually in the grid
			_place_item_in_grid(item, free_pos)
	
	# Force visual refresh on all slots
	force_all_slots_refresh()
	
	_is_refreshing_display = false

func _redistribute_items_for_new_width():
	"""Redistribute items when grid width changes"""
	if not container:
		return
	
	# Calculate if we need more rows for the same number of items
	var total_items = container.items.size()
	if total_items == 0:
		return
	
	var required_rows = (total_items + current_grid_width - 1) / current_grid_width  # Ceiling division
	var new_height = max(min_grid_height, required_rows + 2)  # Add buffer
	
	if new_height != current_grid_height:
		var old_height = current_grid_height
		current_grid_height = new_height
		
		# Rebuild the grid if height changed significantly
		if new_height > old_height:
			_expand_grid_to_new_height(new_height)
		
		_update_grid_size()
		
func _expand_grid_to_new_height(new_height: int):
	"""Expand grid to accommodate new height"""
	# Resize slots array
	slots.resize(new_height)
	
	# Create new rows if needed
	for y in range(current_grid_height, new_height):
		slots[y] = []
		slots[y].resize(current_grid_width)
		
		for x in current_grid_width:
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
			
			# Add to available slots
			available_slots.append(Vector2i(x, y))

# Drag and drop event handlers
func _on_slot_clicked(slot: InventorySlot, event: InputEvent):
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if slot.has_item():
				if Input.is_key_pressed(KEY_CTRL):
					_toggle_slot_selection(slot)
				else:
					clear_selection()
					item_selected.emit(slot.get_item(), slot)

func _on_slot_right_clicked(slot: InventorySlot, event: InputEvent):
	if slot.has_item():
		item_context_menu.emit(slot.get_item(), slot, event.global_position)

func _on_item_drag_started(slot: InventorySlot, item: InventoryItem_Base):
	pass  # Handled by slot

func _on_item_drag_ended(slot: InventorySlot, success: bool):
	if success:
		# Update available slots after successful drag
		_update_available_slots()
		# Try to shrink grid if possible
		call_deferred("_shrink_grid_if_possible")

func _on_item_dropped_on_slot(source_slot: InventorySlot, target_slot: InventorySlot):
	# Update available slots after drop
	_update_available_slots()

func _toggle_slot_selection(slot: InventorySlot):
	if slot in selected_slots:
		slot.set_selected(false)
		selected_slots.erase(slot)
	else:
		slot.set_selected(true)
		selected_slots.append(slot)

func clear_all_highlighting():
	"""Clear all highlighting from all slots"""
	for y in current_grid_height:
		for x in current_grid_width:
			if y < slots.size() and x < slots[y].size():
				var slot = slots[y][x]
				if slot:
					slot.set_highlighted(false)
					slot.set_selected(false)

# Utility functions
func get_item_position(item: InventoryItem_Base) -> Vector2i:
	"""Get item position from our grid tracking"""
	return item_positions.get(item, Vector2i(-1, -1))

func set_item_position(item: InventoryItem_Base, position: Vector2i):
	"""Set item position in our grid tracking"""
	if item in container.items:
		item_positions[item] = position

func _is_valid_position(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < current_grid_width and pos.y >= 0 and pos.y < current_grid_height

func get_slot_at_position(global_pos: Vector2) -> InventorySlot:
	for y in current_grid_height:
		for x in current_grid_width:
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
	if not _is_any_slot_dragging() and not _is_refreshing_display:
		call_deferred("refresh_display")

func _on_container_item_removed(_item: InventoryItem_Base, _position: Vector2i):
	if not _is_any_slot_dragging() and not _is_refreshing_display:
		call_deferred("refresh_display")

func _on_container_item_moved(_item: InventoryItem_Base, _from_pos: Vector2i, _to_pos: Vector2i):
	if not _is_any_slot_dragging() and not _is_refreshing_display:
		call_deferred("refresh_display")

func _is_any_slot_dragging() -> bool:
	for y in current_grid_height:
		for x in current_grid_width:
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
	for y in current_grid_height:
		for x in current_grid_width:
			if y < slots.size() and x < slots[y].size():
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
	# Override to use minimum values
	min_grid_width = max(width, 5)  # Minimum 5 columns
	min_grid_height = max(height, 5)  # Minimum 5 rows
	current_grid_width = min_grid_width
	current_grid_height = min_grid_height
	_rebuild_grid()

func get_grid_size() -> Vector2i:
	return Vector2i(current_grid_width, current_grid_height)

func set_slot_size(new_size: Vector2):
	slot_size = new_size
	for y in current_grid_height:
		for x in current_grid_width:
			if y < slots.size() and x < slots[y].size() and slots[y][x]:
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

# Volume-based capacity display
func get_capacity_info() -> Dictionary:
	if not container:
		return {}
	
	return {
		"current_volume": container.get_current_volume(),
		"max_volume": container.max_volume,
		"available_volume": container.get_available_volume(),
		"volume_percentage": container.get_volume_percentage(),
		"current_slots": current_grid_width * current_grid_height,
		"used_slots": container.items.size()
	}
	
func get_volume_display_text() -> String:
	"""Get formatted text showing volume usage"""
	if not container:
		return "No Container"
	
	var current_vol = container.get_current_volume()
	var max_vol = container.max_volume
	var percentage = container.get_volume_percentage()
	
	return "Volume: %.1f/%.1f m³ (%.1f%%)" % [current_vol, max_vol, percentage]

func get_volume_color() -> Color:
	"""Get color based on volume usage"""
	if not container:
		return Color.WHITE
	
	var percentage = container.get_volume_percentage()
	
	if percentage < 50.0:
		return Color.GREEN
	elif percentage < 80.0:
		return Color.YELLOW
	elif percentage < 90.0:
		return Color.ORANGE
	else:
		return Color.RED

func should_show_volume_warning() -> bool:
	"""Check if we should show volume warning"""
	if not container:
		return false
	
	return container.get_volume_percentage() > 85.0

# Add method to get capacity statistics
func get_capacity_statistics() -> Dictionary:
	if not container:
		return {}
	
	var stats = {
		"volume_used": container.get_current_volume(),
		"volume_max": container.max_volume,
		"volume_available": container.get_available_volume(),
		"volume_percentage": container.get_volume_percentage(),
		"slots_used": 0,
		"slots_available": available_slots.size(),
		"slots_total": current_grid_width * current_grid_height,
		"items_count": container.items.size(),
		"unique_items": container.items.size()  # Each stack counts as one unique item
	}
	
	# Count used slots
	for y in current_grid_height:
		for x in current_grid_width:
			if y < slots.size() and x < slots[y].size():
				var slot = slots[y][x]
				if slot and slot.has_item():
					stats.slots_used += 1
	
	return stats
	
func apply_filter(filter_type: int):
	current_filter_type = filter_type
	refresh_display()

func apply_search(search_text: String):
	current_search_text = search_text.to_lower()
	refresh_display()

func _should_show_item(item: InventoryItem_Base) -> bool:
	# Apply search filter first
	if not current_search_text.is_empty():
		if not item.item_name.to_lower().contains(current_search_text):
			return false
	
	# Apply type filter
	if current_filter_type == 0:  # All Items
		return true
	
	# Map filter indices to ItemType enum values
	var item_type_filter = _get_item_type_from_filter(current_filter_type)
	return item.item_type == item_type_filter

func _get_item_type_from_filter(filter_index: int) -> InventoryItem_Base.ItemType:
	match filter_index:
		1: return InventoryItem_Base.ItemType.WEAPON
		2: return InventoryItem_Base.ItemType.ARMOR
		3: return InventoryItem_Base.ItemType.CONSUMABLE
		4: return InventoryItem_Base.ItemType.RESOURCE
		5: return InventoryItem_Base.ItemType.BLUEPRINT
		6: return InventoryItem_Base.ItemType.MODULE
		7: return InventoryItem_Base.ItemType.SHIP
		8: return InventoryItem_Base.ItemType.CONTAINER
		9: return InventoryItem_Base.ItemType.AMMUNITION
		10: return InventoryItem_Base.ItemType.IMPLANT
		11: return InventoryItem_Base.ItemType.SKILL_BOOK
		_: return InventoryItem_Base.ItemType.MISCELLANEOUS
