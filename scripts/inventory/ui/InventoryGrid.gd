# InventoryGridUI.gd - Grid-based inventory display with volume-based infinite slots
class_name InventoryGrid
extends Control

# Grid properties
@export var slot_size: Vector2 = Vector2(64, 64)
@export var slot_spacing: int = 0
@export var min_grid_width: int = 10  # Minimum grid width
@export var min_grid_height: int = 10  # Minimum grid height
@export var slots_per_row_expansion: int = 2  # How many columns to add when expanding
@export var enable_virtual_scrolling: bool = false
@export var virtual_item_height: int = 96  # Match your slot_size.y
@export var virtual_buffer_items: int = 3  # Extra items to render outside viewport

# Visual properties
@export var background_color: Color = Color(0.1, 0.1, 0.1, 1.0)
@export var grid_line_color: Color = Color(0.1, 0.1, 0.1, 1.0)
@export var grid_line_width: float = 1.0

var original_grid_styles: Dictionary = {}
var grid_transparency_init: bool = false

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
var _resize_complete_timer: Timer
var _needs_reflow: bool = false

# Virtual scrolling state
var virtual_items: Array[InventoryItem_Base] = []
var virtual_scroll_container: ScrollContainer
var virtual_content: Control
var virtual_rendered_slots: Array[InventorySlot] = []
var virtual_first_visible: int = 0
var virtual_last_visible: int = 0
var virtual_viewport_height: int = 0
var virtual_items_per_row: int = 1
var virtual_total_height: int = 0

# UI components
var background_panel: Panel
var grid_container: GridContainer
var slots: Array = []  # 2D array of InventorySlotUI
var selected_slots: Array[InventorySlot] = []
var current_filter_type: int = 0  # 0 = All Items
var current_search_text: String = ""

enum DisplayMode {
	GRID,
	LIST
}

var current_display_mode: DisplayMode = DisplayMode.GRID
var list_view: InventoryListView

# Signals
signal item_selected(item: InventoryItem_Base, slot: InventorySlot)
signal item_activated(item: InventoryItem_Base, slot: InventorySlot)
signal item_context_menu(item: InventoryItem_Base, slot: InventorySlot, position: Vector2)

func _ready():
	if enable_virtual_scrolling:
		_setup_virtual_scrolling()
	else:
		_setup_background()
		_setup_grid()
	
	set_focus_mode(Control.FOCUS_ALL)
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	set_grid_size(25, 20)
	
	# Create timer for resize complete handling
	_resize_complete_timer = Timer.new()
	_resize_complete_timer.wait_time = 0.1
	_resize_complete_timer.one_shot = true
	_resize_complete_timer.timeout.connect(_perform_compact_reflow)
	add_child(_resize_complete_timer)
	
	# Connect to visibility changes to fix initial layout
	visibility_changed.connect(_on_visibility_changed)
	
func _setup_virtual_scrolling():
	"""Setup virtual scrolling container"""	
	# Create scroll container
	virtual_scroll_container = ScrollContainer.new()
	virtual_scroll_container.name = "VirtualScrollContainer"
	virtual_scroll_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	virtual_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	virtual_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	virtual_scroll_container.mouse_filter = Control.MOUSE_FILTER_PASS
	
	add_child(virtual_scroll_container)
	
	# Create content container
	virtual_content = Control.new()
	virtual_content.name = "VirtualContent"
	virtual_content.mouse_filter = Control.MOUSE_FILTER_STOP
	virtual_scroll_container.add_child(virtual_content)
	
	# Connect scroll events
	virtual_scroll_container.get_v_scroll_bar().value_changed.connect(_on_virtual_scroll)
	virtual_scroll_container.resized.connect(_on_virtual_container_resized)
	
	# Set background color
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = background_color
	virtual_scroll_container.add_theme_stylebox_override("panel", style_box)
		
func _on_virtual_content_input(event: InputEvent):
	"""Handle drops on empty virtual content area"""
	if not enable_virtual_scrolling:
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			# Check if we have drag data (mouse released after drag)
			var viewport = get_viewport()
			if viewport and viewport.has_meta("current_drag_data"):
				var drag_data = viewport.get_meta("current_drag_data")
				var source_slot = drag_data.get("source_slot")
				
				if source_slot and source_slot.has_item():
					# Drop on empty area - add item to container
					_handle_drop_on_empty_area(source_slot, mouse_event.global_position)
					
func _handle_drop_on_empty_area(source_slot: InventorySlot, drop_position: Vector2) -> bool:
	"""Handle dropping an item at a specific position in the virtual grid"""	
	if not source_slot or not source_slot.has_item():
		return false
	
	var source_item = source_slot.get_item()
	
	# Calculate which grid position was dropped on
	var local_pos = drop_position - virtual_content.global_position
	var grid_col = int(local_pos.x / slot_size.x)
	var grid_row = int(local_pos.y / virtual_item_height)
	var target_grid_pos = Vector2i(grid_col, grid_row)
		
	# Same container - move item to specific position
	if source_slot.container_id == container_id:
		
		# Clear the source slot visually
		source_slot.clear_item()
		
		# Store the item's new position (we'll need to implement position persistence)
		# For now, just refresh and the item will appear in the dropped area
		call_deferred("_refresh_virtual_display")
		return true
	else:
		# Cross-container transfer to specific position
		var inventory_manager = _get_inventory_manager()
		if not inventory_manager:
			return false
		
		var success = inventory_manager.transfer_item(source_item, source_slot.container_id, container_id)
		if success:
			call_deferred("_refresh_virtual_display")
			return true
	
	return false
	
func _on_virtual_container_resized():
	"""Handle virtual scroll container resize - recalculate grid to fill new space"""	
	# Immediately recalculate the grid layout for the new size
	call_deferred("_update_virtual_viewport")
	
func _on_virtual_scroll(value: float):
	"""Handle virtual scroll position changes"""
	if not enable_virtual_scrolling or virtual_items.is_empty():
		return
	
	_update_virtual_viewport()

func _update_virtual_viewport():
	"""Update the virtual viewport when scrolling or resizing"""
	if not virtual_scroll_container:
		return
	
	# Recalculate grid when container size changes
	virtual_items_per_row = max(1, int((virtual_scroll_container.size.x - 20) / slot_size.x))
	
	# Always render items to fill the available space
	_render_virtual_items()
	
func cleanup_all_glows():
	"""Clean up glow effects on all slots"""
	if enable_virtual_scrolling:
		# Clean up virtual rendered slots
		for slot in virtual_rendered_slots:
			if slot and is_instance_valid(slot) and slot.has_method("cleanup_glow"):
				slot.cleanup_glow()
	else:
		# Clean up traditional grid slots
		for row in slots:
			if row:
				for slot in row:
					if slot and is_instance_valid(slot) and slot.has_method("cleanup_glow"):
						slot.cleanup_glow()
		
func _clear_virtual_slots():
	"""Clear all virtual rendered slots"""
	for slot in virtual_rendered_slots:
		if is_instance_valid(slot):
			slot.queue_free()
	virtual_rendered_slots.clear()
	
#func add_test_items_for_virtual_scroll():
	#"""Add many test items to verify virtual scrolling"""
	#if not container:
		#return
	#
	#for i in range(100):  # Add 100 test items
		#var test_item = InventoryItem_Base.new()
		#test_item.item_name = "Test Item " + str(i + 1)
		#test_item.quantity = 1
		#test_item.volume = 1.0
		#test_item.mass = 1.0
		#container.items.append(test_item)
	#
	#refresh_display()

func _render_virtual_items():
	"""Render a dynamic grid that fills the available window space, like EVE Online"""
	if not virtual_content:
		print("ERROR: virtual_content is null")
		return
		
	
	_cleanup_virtual_rendered_slots()
	
	# Calculate grid dimensions based on available space
	var available_width = virtual_scroll_container.size.x - 20  # Account for scrollbar
	var available_height = virtual_scroll_container.size.y
	
	virtual_items_per_row = max(1, int(available_width / slot_size.x))
	var max_visible_rows = max(1, int(available_height / slot_size.y))
	
	# Calculate total grid size - much more reasonable like EVE
	var items_rows = (virtual_items.size() + virtual_items_per_row - 1) / virtual_items_per_row if virtual_items.size() > 0 else 0
	var total_rows = max(max_visible_rows, items_rows + 3)  # Just 3 extra rows below items
		
	# Create item position mapping
	var item_positions = {}
	
	# Place items compactly for now
	for i in range(virtual_items.size()):
		var row = i / virtual_items_per_row
		var col = i % virtual_items_per_row
		item_positions[virtual_items[i]] = Vector2i(col, row)
	
	# Calculate which slots are currently visible
	var scroll_offset = virtual_scroll_container.scroll_vertical
	var first_visible_row = max(0, int(scroll_offset / slot_size.y) - 1)  # Small buffer above
	var last_visible_row = min(total_rows, int((scroll_offset + available_height) / slot_size.y) + 2)  # Small buffer below
		
	# Render visible grid slots
	var rendered_count = 0
	for row in range(first_visible_row, last_visible_row):
		for col in range(virtual_items_per_row):
			var grid_pos = Vector2i(col, row)
			
			# Create the slot
			var slot = InventorySlot.new()
			slot.slot_size = slot_size
			slot.position = Vector2(col * slot_size.x, row * slot_size.y)
			slot.mouse_filter = Control.MOUSE_FILTER_PASS
			
			# Set grid position
			slot.set_grid_position(grid_pos)
			slot.set_container_id(container_id)
			
			# Connect signals
			slot.slot_clicked.connect(_on_slot_clicked)
			slot.slot_right_clicked.connect(_on_slot_right_clicked)
			slot.item_drag_started.connect(_on_item_drag_started)
			slot.item_drag_ended.connect(_on_item_drag_ended)
			slot.item_dropped_on_slot.connect(_on_item_dropped_on_slot)
			
			# Add to scene
			virtual_content.add_child(slot)
			
			# Check if any item should be in this position
			var item_for_this_slot = null
			for item in item_positions:
				if item_positions[item] == grid_pos:
					item_for_this_slot = item
					break
			
			# Set item if one belongs here
			if item_for_this_slot:
				slot.set_item(item_for_this_slot)
				slot.call_deferred("_update_item_display")
			
			virtual_rendered_slots.append(slot)
			rendered_count += 1
		
	# Update content size - much smaller now
	virtual_total_height = total_rows * slot_size.y
	var content_width = virtual_items_per_row * slot_size.x
	virtual_content.custom_minimum_size = Vector2(content_width, virtual_total_height)
	virtual_content.size = Vector2(content_width, virtual_total_height)
	
func _cleanup_virtual_rendered_slots():
	"""Properly clean up existing virtual rendered slots"""
	print("Cleaning up ", virtual_rendered_slots.size(), " virtual rendered slots")
	
	# Disconnect signals and free slots
	for slot in virtual_rendered_slots:
		if slot and is_instance_valid(slot):
			# Disconnect all signals to prevent memory leaks
			if slot.slot_clicked.is_connected(_on_slot_clicked):
				slot.slot_clicked.disconnect(_on_slot_clicked)
			if slot.slot_right_clicked.is_connected(_on_slot_right_clicked):
				slot.slot_right_clicked.disconnect(_on_slot_right_clicked)
			if slot.item_drag_started.is_connected(_on_item_drag_started):
				slot.item_drag_started.disconnect(_on_item_drag_started)
			if slot.item_drag_ended.is_connected(_on_item_drag_ended):
				slot.item_drag_ended.disconnect(_on_item_drag_ended)
			if slot.item_dropped_on_slot.is_connected(_on_item_dropped_on_slot):
				slot.item_dropped_on_slot.disconnect(_on_item_dropped_on_slot)
			
			# Remove from scene tree and free
			if slot.get_parent():
				slot.get_parent().remove_child(slot)
			slot.queue_free()
	
	# Clear the array
	virtual_rendered_slots.clear()
	
	# Also clear all children from virtual_content to be safe
	if virtual_content:
		for child in virtual_content.get_children():
			child.queue_free()
		
func _on_visibility_changed():
	"""Handle visibility changes to fix initial layout"""
	if visible and container and container.items.size() > 0:
		# When becoming visible, ensure proper layout
		call_deferred("_check_and_fix_initial_layout")

func _check_and_fix_initial_layout():
	"""Check if we have a bad initial layout and fix it"""
	# Check if we have a suspiciously narrow grid with items
	if current_grid_width <= 2 and container and container.items.size() > 2:
		# Wait a bit more for layout to settle
		await get_tree().create_timer(0.2).timeout
		
		# Force a proper recalculation
		_initialize_with_proper_size()
	
func handle_resize_complete():
	"""Called when window resize is complete"""
	_resize_complete_timer.start()
	
func _update_container_positions_from_visual():
	"""Update container item positions to match current visual placement"""
	if not container:
		return
	
	# Go through all slots and update container positions
	for y in current_grid_height:
		for x in current_grid_width:
			if y < slots.size() and x < slots[y].size():
				var slot = slots[y][x]
				if slot and slot.has_item():
					var item = slot.get_item()
					var position = Vector2i(x, y)
					
					# Update position tracking
					item_positions[item] = position
					
					# Update position in container if it supports it
					if container.has_method("set_item_position"):
						container.set_item_position(item, position)
						
func set_dynamic_grid_size(max_width: int = 20, initial_height: int = 5):
	"""Set up a dynamic grid that expands as needed"""
	min_grid_width = max_width
	min_grid_height = initial_height
	current_grid_width = max_width
	current_grid_height = initial_height
	_rebuild_grid()
	
func ensure_slots_for_items(item_count: int):
	"""Ensure we have enough slots for the given number of items"""
	var slots_needed = item_count + 10  # Add some buffer slots
	var current_slots = current_grid_width * current_grid_height
	
	if slots_needed > current_slots:
		var new_height = (slots_needed + current_grid_width - 1) / current_grid_width
		if new_height > current_grid_height:
			current_grid_height = new_height
			_rebuild_grid()

func _ensure_adequate_slots():
	"""Ensure we have enough slots for the current dimensions"""
	if enable_virtual_scrolling:
		return
	var needed_total = current_grid_width * current_grid_height
	var current_total = 0
	
	for row in slots:
		if row:
			current_total += row.size()
	
	# Rebuild if dimensions changed or wrong number of children
	var should_rebuild = false
	
	if slots.size() != current_grid_height:
		should_rebuild = true
	elif slots.size() > 0 and slots[0].size() != current_grid_width:
		should_rebuild = true
	elif grid_container and grid_container.get_child_count() != needed_total:
		should_rebuild = true
	
	if should_rebuild:
		_rebuild_slots_completely()

func _rebuild_slots_completely():
	"""Completely rebuild the slots structure"""
	if enable_virtual_scrolling:
		return
	_disconnect_container_signals()
	
	# Clear existing slots
	for row in slots:
		if row:
			for slot in row:
				if slot:
					slot.queue_free()
	
	# Clear grid container
	if grid_container:
		for child in grid_container.get_children():
			child.queue_free()
	
	slots.clear()
	available_slots.clear()
	
	# Wait for cleanup
	await get_tree().process_frame
	
	# Rebuild with exact dimensions
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
	
	_connect_container_signals()

func _clear_all_slots_completely():
	"""Clear all slots of items"""
	if enable_virtual_scrolling:
		return
		
	for row_idx in range(slots.size()):
		var row = slots[row_idx]
		if row:
			for col_idx in range(row.size()):
				var slot = row[col_idx]
				if slot:
					slot.clear_item()
	
	# Reset available slots
	available_slots.clear()
	for y in current_grid_height:
		for x in current_grid_width:
			available_slots.append(Vector2i(x, y))
	
	item_positions.clear()

func _place_items_compactly(items: Array[InventoryItem_Base]):
	"""Place items in compact left-to-right, top-to-bottom order"""
	if enable_virtual_scrolling:
		return
		
	var placed_items = 0
	
	for y in current_grid_height:
		if placed_items >= items.size():
			break
			
		if y >= slots.size():
			break
		
		if not slots[y] or slots[y].size() < current_grid_width:
			continue
			
		for x in current_grid_width:
			if placed_items >= items.size():
				break
				
			var slot = slots[y][x]
			if not slot:
				continue
			
			slot.clear_item()
			
			var item = items[placed_items]
			var new_pos = Vector2i(x, y)
			
			slot.set_item(item)
			item_positions[item] = new_pos
			available_slots.erase(new_pos)
			placed_items += 1
		
func _handle_resize_complete():
	"""Called after resize is complete - DISABLED to prevent conflicts"""
	# This method is intentionally disabled to prevent conflicts with _perform_compact_reflow
	# The timer-based approach in handle_resize_complete() is the single source of truth
	pass
		
	# Calculate new width based on available space
	var available_width = size.x - 16
	if available_width <= slot_size.x:
		return
	
	var slots_per_row = max(1, int(available_width / (slot_size.x + slot_spacing)))
	var new_width = max(1, min(slots_per_row, 20))
	
	# If width changed, force immediate reflow
	if new_width != current_grid_width:
		
		# Update dimensions
		current_grid_width = new_width
		
		# Calculate new height for current items
		var visible_items = 0
		for item in container.items:
			if _should_show_item(item):
				visible_items += 1
		
		if visible_items > 0:
			var required_rows = (visible_items + new_width - 1) / new_width
			current_grid_height = max(min_grid_height, required_rows + 1)
		
		# Force immediate refresh
		_is_refreshing_display = false
		_needs_reflow = false
		refresh_display()

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
	if enable_virtual_scrolling:
		return
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
			
func _create_virtual_slot(item: InventoryItem_Base, virtual_index: int) -> InventorySlot:
	var slot = InventorySlot.new()
	slot.slot_size = slot_size
	slot.set_container_id(container_id)
	slot.set_item(item)
	
	# CRITICAL: Set grid position based on virtual layout
	var row = virtual_index / virtual_items_per_row
	var col = virtual_index % virtual_items_per_row
	slot.set_grid_position(Vector2i(col, row))
	
	# Connect all necessary signals
	slot.slot_clicked.connect(_on_slot_clicked)
	slot.slot_right_clicked.connect(_on_slot_right_clicked)
	slot.item_drag_started.connect(_on_item_drag_started)
	slot.item_drag_ended.connect(_on_item_drag_ended)
	slot.item_dropped_on_slot.connect(_on_item_dropped_on_slot)
	
	# CRITICAL: Calculate and set the position manually for virtual slots
	# FIX: use slot_size.x and slot_size.y
	var x_pos = col * slot_size.x
	var y_pos = row * slot_size.y
	slot.position = Vector2(x_pos, y_pos)
	slot.size = slot_size  # This is fine since slot.size expects Vector2
	
	return slot
			
func _create_initial_slots():
	if enable_virtual_scrolling:
		return
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

func _perform_compact_reflow():
	"""Perform a compact reflow of all items"""
	if enable_virtual_scrolling:
		return
	if not container:
		return
	
	# Block all other refresh operations during compacting
	_is_refreshing_display = true
	_needs_reflow = false
	_is_adapting_width = false
	_is_expanding_grid = false
	_is_shrinking_grid = false
	
	# Calculate new grid width based on current size
	var available_width = _get_actual_available_width()
	if available_width <= slot_size.x:
		_is_refreshing_display = false
		return
	
	var slots_per_row = max(1, int(available_width / (slot_size.x + slot_spacing)))
	var new_width = max(1, min(slots_per_row, 20))
	
	# Only proceed if width actually changed
	if new_width == current_grid_width:
		_is_refreshing_display = false
		return
	
	# Get all visible items
	var items_to_place: Array[InventoryItem_Base] = []
	for item in container.items:
		if _should_show_item(item):
			items_to_place.append(item)
	
	# Calculate required height
	var required_rows = (items_to_place.size() + new_width - 1) / new_width if items_to_place.size() > 0 else min_grid_height
	var new_height = max(min_grid_height, required_rows + 1)
	
	# Update dimensions
	current_grid_width = new_width
	current_grid_height = new_height
	
	# Update GridContainer columns immediately
	if grid_container:
		grid_container.columns = current_grid_width
		grid_container.queue_redraw()
		grid_container.notification(NOTIFICATION_RESIZED)
	
	# Ensure we have enough slots
	_ensure_adequate_slots()
	
	# Wait a frame for the grid container to update
	await get_tree().process_frame
	
	# Clear and place items
	_clear_all_slots_completely()
	_place_items_compactly(items_to_place)
	
	# Force layout update after placement
	if grid_container:
		grid_container.queue_redraw()
		await get_tree().process_frame
	
	_update_grid_size()
	force_all_slots_refresh()
	
	_is_refreshing_display = false
	
func _get_actual_available_width() -> float:
	"""Get the actual available width by walking up the parent chain"""
	var split_container = _find_split_container()
	if split_container:
		var total_width = split_container.size.x
		var split_offset = split_container.split_offset
		var right_side_width = total_width - split_offset
		
		# Account for overhead
		var mass_bar_overhead = 36
		var container_margins = 12
		var scrollbar_width = 18
		
		var available = right_side_width - mass_bar_overhead - container_margins - scrollbar_width
		return max(available, slot_size.x)
	
	# Fallback to scroll container method
	var scroll_container = _find_scroll_container()
	if scroll_container:
		var scroll_width = scroll_container.size.x
		var scrollbar_width = 20
		var available = scroll_width - scrollbar_width - 16
		return available
	
	# Last resort
	return size.x - 16

	
func _find_scroll_container() -> ScrollContainer:
	"""Find the parent scroll container"""
	var current = get_parent()
	while current:
		if current is ScrollContainer:
			return current
		current = current.get_parent()
	return null

func _find_window_content() -> Control:
	"""Find the InventoryWindowContent"""
	var current = get_parent()
	while current:
		if current.get_script() and current.get_script().get_global_name() == "InventoryWindowContent":
			return current
		current = current.get_parent()
	return null

func _find_split_container() -> HSplitContainer:
	"""Find the parent HSplitContainer"""
	var current = get_parent()
	while current:
		if current is HSplitContainer:
			return current
		current = current.get_parent()
	return null

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
	if enable_virtual_scrolling:
		return
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
	# Prevent recursive calls during shrinking OR if resize timer is active
	if _is_shrinking_grid or not container or _resize_complete_timer.time_left > 0.0:
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
	if enable_virtual_scrolling:
		return
		
	if grid_container:
		var total_height = current_grid_height * slot_size.y + (current_grid_height - 1) * slot_spacing
		grid_container.custom_minimum_size = Vector2(0, total_height)
		custom_minimum_size = Vector2(0, total_height + 16)

# Container management
func set_container(new_container: InventoryContainer_Base):
	# Clear position tracking when changing containers
	item_positions.clear()
	
	if container:
		_disconnect_container_signals()
	
	container = new_container
	container_id = container.container_id if container else ""
	
	if container:
		_connect_container_signals()
		
		# Use the original refresh system that was working before virtual scrolling
		call_deferred("refresh_display")
	else:
		# No container - clear everything
		current_grid_width = min_grid_width
		current_grid_height = min_grid_height
		if grid_container:
			grid_container.queue_free()
			grid_container = null
		slots.clear()
		available_slots.clear()
		
	if list_view:
		list_view.set_container(container, container_id)
		
func _initialize_with_proper_size():
	"""Initialize the grid with proper size after layout is complete"""
	if not container:
		return
	
	# Wait additional frames to ensure parent containers have proper sizes
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Force trigger the compact refresh regardless of size
	# The fallback method handles insufficient width properly
	_trigger_compact_refresh_with_fallback()
		
func _trigger_compact_refresh_with_fallback():
	"""Trigger compact refresh with fallback width calculation"""
	if not container:
		return
	
	_is_refreshing_display = true
	
	# Get all visible items
	var items_to_place: Array[InventoryItem_Base] = []
	for item in container.items:
		if _should_show_item(item):
			items_to_place.append(item)
	
	if items_to_place.is_empty():
		_is_refreshing_display = false
		return
	
	# Get actual available width first, with fallback
	var available_width = _get_actual_available_width()
	if available_width < 100:  # If still no good width info
		available_width = max(400, size.x - 32)  # Use our own size or reasonable default
	
	var slots_per_row = max(1, int(available_width / (slot_size.x + slot_spacing)))
	var optimal_width = max(3, min(slots_per_row, 20))  # At least 3 columns
	
	var required_rows = (items_to_place.size() + optimal_width - 1) / optimal_width
	var optimal_height = max(min_grid_height, required_rows + 1)
	
	# Update dimensions
	current_grid_width = optimal_width
	current_grid_height = optimal_height
	
	if grid_container:
		grid_container.columns = current_grid_width
	
	_ensure_adequate_slots()
	await get_tree().process_frame
	
	# Clear and compact
	_clear_all_slots_completely()
	_place_items_compactly(items_to_place)
	
	force_all_slots_refresh()
	_is_refreshing_display = false

func trigger_compact_refresh():
	"""Public method to trigger a compact refresh"""
	_trigger_compact_refresh()

func _trigger_compact_refresh():
	"""Trigger a compact refresh without full reflow"""
	if not container:
		return
	
	# Block normal refresh and force compact placement
	_is_refreshing_display = true
	
	# Get all visible items
	var items_to_place: Array[InventoryItem_Base] = []
	for item in container.items:
		if _should_show_item(item):
			items_to_place.append(item)
	
	if items_to_place.is_empty():
		_is_refreshing_display = false
		return
	
	# Calculate optimal dimensions for current items
	var available_width = _get_actual_available_width()
	var slots_per_row = max(1, int(available_width / (slot_size.x + slot_spacing)))
	var optimal_width = max(1, min(slots_per_row, 20))
	
	var required_rows = (items_to_place.size() + optimal_width - 1) / optimal_width
	var optimal_height = max(min_grid_height, required_rows + 1)
	
	# Update dimensions if needed
	if optimal_width != current_grid_width or optimal_height != current_grid_height:
		current_grid_width = optimal_width
		current_grid_height = optimal_height
		
		if grid_container:
			grid_container.columns = current_grid_width
		
		_ensure_adequate_slots()
		await get_tree().process_frame
	
	# Clear and compact
	_clear_all_slots_completely()
	_place_items_compactly(items_to_place)
	
	force_all_slots_refresh()
	_is_refreshing_display = false

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
	if enable_virtual_scrolling:
		return
	if grid_container:
		grid_container.queue_free()
	
	_setup_grid()
	
	# Update all slot container IDs
	for y in current_grid_height:
		for x in current_grid_width:
			if y < slots.size() and x < slots[y].size() and slots[y][x]:
				slots[y][x].set_container_id(container_id)

# Display management
func set_display_mode(mode: DisplayMode):
	if mode == current_display_mode:
		return
	
	current_display_mode = mode
	
	match mode:
		DisplayMode.GRID:
			_switch_to_grid_mode()
		DisplayMode.LIST:
			_switch_to_list_mode()

func _switch_to_grid_mode():
	if list_view:
		list_view.visible = false
	
	if virtual_scroll_container:
		virtual_scroll_container.visible = true
	elif background_panel and grid_container:
		background_panel.visible = true
		grid_container.visible = true

func _switch_to_list_mode():
	# Hide grid components
	if virtual_scroll_container:
		virtual_scroll_container.visible = false
	elif background_panel and grid_container:
		background_panel.visible = false
		grid_container.visible = false
	
	# Create or show list view
	if not list_view:
		list_view = InventoryListView.new()
		list_view.name = "ListView"
		add_child(list_view)
		
		# Connect list view signals to grid signals
		list_view.item_selected.connect(func(item): item_selected.emit(item, null))
		list_view.item_activated.connect(func(item): item_activated.emit(item, null))
		list_view.item_context_menu.connect(func(item, pos): item_context_menu.emit(item, null, pos))
	
	list_view.visible = true
	list_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Set container if we have one
	if container:
		list_view.set_container(container, container_id)

func refresh_display():
	match current_display_mode:
		DisplayMode.GRID:
			if enable_virtual_scrolling:
				_refresh_virtual_display()
			else:
				_refresh_traditional_display()
		DisplayMode.LIST:
			if list_view:
				list_view.refresh_display()

func _refresh_traditional_display():
	if enable_virtual_scrolling:
		return
	# Block refresh during resize timer operations
	if not container or _is_refreshing_display or _needs_reflow or _resize_complete_timer.time_left > 0.0:
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
	
func _refresh_virtual_display():
	"""Optimized refresh - avoid unnecessary work"""
	
	if not container or _is_refreshing_display:
		return
	
	_is_refreshing_display = true
	
	# Collect visible items (this is fast)
	virtual_items.clear()
	for item in container.items:
		if _should_show_item(item):
			virtual_items.append(item)
	
	# Update existing slots instead of recreating everything
	_render_virtual_items()
	
	_is_refreshing_display = false
	
func set_virtual_scrolling_enabled(enabled: bool):
	"""Switch between virtual and traditional modes"""
	if enabled == enable_virtual_scrolling:
		return
	
	enable_virtual_scrolling = enabled
	
	if enabled:
		# Switch to virtual mode
		if background_panel:
			background_panel.queue_free()
		if grid_container:
			grid_container.queue_free()
		_setup_virtual_scrolling()
	else:
		# Switch to traditional mode
		if virtual_scroll_container:
			virtual_scroll_container.queue_free()
		_setup_background()
		_setup_grid()
	
	# Refresh display with new mode
	refresh_display()

func get_virtual_item_count() -> int:
	"""Get total number of virtual items"""
	return virtual_items.size() if enable_virtual_scrolling else 0

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
	if enable_virtual_scrolling:
		# For virtual scrolling, refresh the virtual rendered slots
		for slot in virtual_rendered_slots:
			if slot and is_instance_valid(slot) and slot.has_method("force_visual_refresh"):
				slot.force_visual_refresh()
	else:
		# Traditional grid refresh
		if not slots or slots.size() == 0:
			return
			
		for y in range(slots.size()):
			if not slots[y]:
				continue
			for x in range(slots[y].size()):
				var slot = slots[y][x]
				if slot and slot.has_method("force_visual_refresh"):
					slot.force_visual_refresh()

# Input handling for focus management
func _gui_input(event: InputEvent):
	if enable_virtual_scrolling and event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		
		# Handle scroll wheel for virtual scrolling
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if virtual_scroll_container:
				virtual_scroll_container.scroll_vertical -= 50
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if virtual_scroll_container:
				virtual_scroll_container.scroll_vertical += 50
			get_viewport().set_input_as_handled()
		else:
			# Let other mouse events pass through to slots
			pass
	elif not enable_virtual_scrolling:
		# Traditional mode handling (your existing code)
		if event is InputEventMouseButton:
			var mouse_event = event as InputEventMouseButton
			if mouse_event.pressed:
				_focus_inventory_window()
				
				if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
					var clicked_slot = get_slot_at_position(mouse_event.global_position)
					if not clicked_slot or not clicked_slot.has_item():
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

# Drag and drop event handlers
func _on_slot_clicked(slot: InventorySlot, event: InputEvent):
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if slot.has_item():
				if Input.is_key_pressed(KEY_CTRL):
					_toggle_slot_selection(slot)
				else:
					# Only clear selection if we're not already selecting this specific slot
					if not (selected_slots.size() == 1 and selected_slots[0] == slot):
						clear_selection()
					item_selected.emit(slot.get_item(), slot)

func _on_slot_right_clicked(slot: InventorySlot, event: InputEvent):
	if slot.has_item():
		item_context_menu.emit(slot.get_item(), slot, event.global_position)

func _on_item_drag_started(slot: InventorySlot, item: InventoryItem_Base):
	
	if enable_virtual_scrolling:
		# Store the item being dragged and find its index in virtual_items
		var item_index = virtual_items.find(item)
		
		# Store comprehensive drag data
		get_viewport().set_meta("virtual_drag_data", {
			"item": item,
			"source_item_index": item_index,
			"source_slot": slot,
			"source_container_id": container_id
		})

func _on_item_drag_ended(slot: InventorySlot, success: bool):
	if success:
		if enable_virtual_scrolling:
			# Refresh virtual display after successful drag
			call_deferred("_shrink_grid_if_possible")
		else:
			# Traditional handling
			_update_available_slots()
			call_deferred("_shrink_grid_if_possible")

func _on_item_dropped_on_slot(source_slot: InventorySlot, target_slot: InventorySlot):
	
	if enable_virtual_scrolling:
		# For virtual scrolling, use the existing slot logic but prevent refresh_display
		_is_refreshing_display = true  # Block refresh during operation
		
		var result = source_slot._attempt_drop_on_slot(target_slot)
		
		_is_refreshing_display = false  # Re-enable refresh
		
		# Only refresh if successful
		if result:
			call_deferred("_refresh_virtual_display")
	else:
		# Traditional drop handling
		var result = source_slot._attempt_drop_on_slot(target_slot)
		if result:
			_update_available_slots()
			
func _handle_virtual_slot_drop(source_slot: InventorySlot, target_slot: InventorySlot) -> bool:
	"""Handle dropping in virtual scrolling mode without triggering refresh_display"""
	if not source_slot.has_item() or not target_slot:
		return false
	
	var inventory_manager = _get_inventory_manager()
	if not inventory_manager:
		return false
	
	var source_item = source_slot.get_item()
	var target_item = target_slot.get_item() if target_slot.has_item() else null
		
	# Same container operations
	if source_slot.container_id == target_slot.container_id:
		if target_item:
			# Try to stack or swap
			if source_item.can_stack_with(target_item):
				return _handle_virtual_stack_merge(source_slot, target_slot, source_item, target_item)
			else:
				return _handle_virtual_item_swap(source_slot, target_slot, source_item, target_item, inventory_manager)
		else:
			# Move to empty slot - just update the virtual_items array
			return _handle_virtual_move_to_empty(source_slot, target_slot, source_item)
	else:
		# Cross-container transfer
		return _handle_virtual_cross_container_transfer(source_slot, target_slot, source_item, target_item, inventory_manager)
		
func _handle_virtual_stack_merge(source_slot: InventorySlot, target_slot: InventorySlot, source_item: InventoryItem_Base, target_item: InventoryItem_Base) -> bool:
	"""Handle stacking items in virtual mode"""
	var space_available = target_item.max_stack_size - target_item.quantity
	var amount_to_transfer = min(source_item.quantity, space_available)
	
	if amount_to_transfer <= 0:
		return false
	
	# Update the items directly
	target_item.quantity += amount_to_transfer
	source_item.quantity -= amount_to_transfer
	
	# Update slot displays immediately
	target_slot._update_item_display()
	
	if source_item.quantity <= 0:
		# Remove source item from container and virtual_items
		var source_index = virtual_items.find(source_item)
		if source_index != -1:
			virtual_items.remove_at(source_index)
		
		var source_container = container
		if source_container:
			source_container.remove_item(source_item)
		source_slot.clear_item()
	else:
		source_slot._update_item_display()
	
	return true
	
func _handle_virtual_item_swap(source_slot: InventorySlot, target_slot: InventorySlot, source_item: InventoryItem_Base, target_item: InventoryItem_Base, inventory_manager: InventoryManager) -> bool:
	"""Handle swapping items in virtual mode"""
	# For same container, just swap the visual slots
	source_slot.clear_item()
	target_slot.clear_item()
	source_slot.set_item(target_item)
	target_slot.set_item(source_item)
	
	return true

func _handle_virtual_move_to_empty(source_slot: InventorySlot, target_slot: InventorySlot, source_item: InventoryItem_Base) -> bool:
	"""Handle moving item to empty slot in virtual mode"""
	# Same container - just move the visual representation
	source_slot.clear_item()
	target_slot.set_item(source_item)
	return true
	
func _handle_same_container_virtual_drop(source_item: InventoryItem_Base, target_item: InventoryItem_Base, source_slot: InventorySlot, target_slot: InventorySlot) -> bool:
	"""Handle drops within the same container"""
	if not container:
		return false
	
	if target_item:
		# Target slot has an item - try to stack or swap
		if source_item.can_stack_with(target_item):
			# Stack the items
			var space_available = target_item.max_stack_size - target_item.quantity
			var amount_to_transfer = min(source_item.quantity, space_available)
			
			if amount_to_transfer > 0:
				# Update quantities directly
				target_item.quantity += amount_to_transfer
				source_item.quantity -= amount_to_transfer
				
				# If source item is empty, remove it from container
				if source_item.quantity <= 0:
					var source_index = container.items.find(source_item)
					if source_index != -1:
						container.items.remove_at(source_index)
				
				return true
		else:
			# Can't stack - items are swapped automatically by their positions in virtual_items
			return true
	else:
		# Target slot is empty - this is just a visual move within same container
		return true
	
	return false
	
func _handle_cross_container_virtual_drop(source_item: InventoryItem_Base, target_item: InventoryItem_Base, source_slot: InventorySlot, target_slot: InventorySlot) -> bool:
	"""Handle drops between different containers"""
	var inventory_manager = _get_inventory_manager()
	if not inventory_manager:
		return false
	
	var target_container = inventory_manager.get_container(target_slot.container_id)
	if not target_container:
		return false
	
	# Check volume constraints
	var available_volume = target_container.get_available_volume()
	var item_volume = source_item.volume
	var max_transferable = int(available_volume / item_volume) if item_volume > 0 else source_item.quantity
	
	if max_transferable <= 0:
		return false
	
	var transfer_amount = min(source_item.quantity, max_transferable)
	
	# If target slot has an item that can stack
	if target_item and source_item.can_stack_with(target_item):
		var stack_space = target_item.max_stack_size - target_item.quantity
		transfer_amount = min(transfer_amount, stack_space)
		
		if transfer_amount <= 0:
			return false
	
	# Perform the transfer using inventory manager
	var success = inventory_manager.transfer_item(
		source_item, 
		source_slot.container_id, 
		target_slot.container_id, 
		Vector2i(-1, -1),  # Let container decide position
		transfer_amount
	)
	
	return success
	
func _handle_virtual_drop_operation(source_slot: InventorySlot, target_slot: InventorySlot) -> bool:
	"""Handle drop operations in virtual mode by working with container items directly"""
	if not source_slot.has_item() or not target_slot:
		return false
	
	var source_item = source_slot.get_item()
	var target_item = target_slot.get_item() if target_slot.has_item() else null
	
	
	# Same container operations
	if source_slot.container_id == target_slot.container_id:
		return _handle_same_container_virtual_drop(source_item, target_item, source_slot, target_slot)
	else:
		# Different containers - use inventory manager
		return _handle_cross_container_virtual_drop(source_item, target_item, source_slot, target_slot)

func _handle_virtual_cross_container_transfer(source_slot: InventorySlot, target_slot: InventorySlot, source_item: InventoryItem_Base, target_item: InventoryItem_Base, inventory_manager: InventoryManager) -> bool:
	"""Handle transfer between different containers in virtual mode"""
	var target_container = inventory_manager.get_container(target_slot.container_id)
	if not target_container:
		return false
	
	# Calculate transferable amount based on volume
	var available_volume = target_container.get_available_volume()
	var max_transferable = int(available_volume / source_item.volume) if source_item.volume > 0 else source_item.quantity
	
	if max_transferable <= 0:
		return false
	
	var transfer_amount = min(source_item.quantity, max_transferable)
	
	if target_item and source_item.can_stack_with(target_item):
		# Stack with existing item
		var stack_space = target_item.max_stack_size - target_item.quantity
		transfer_amount = min(transfer_amount, stack_space)
	
	if transfer_amount <= 0:
		return false
	
	# Use inventory manager for actual transfer
	var success = inventory_manager.transfer_item(source_item, source_slot.container_id, target_slot.container_id, Vector2i(-1, -1), transfer_amount)
	
	if success:
		# Update the source item
		if source_item.quantity <= 0:
			# Remove from virtual_items and clear slot
			var source_index = virtual_items.find(source_item)
			if source_index != -1:
				virtual_items.remove_at(source_index)
			source_slot.clear_item()
		else:
			source_slot._update_item_display()
		
		return true
	
	return false
	
func _refresh_virtual_display_after_drop():
	"""Refresh virtual display after a drop operation, preserving scroll position"""
	if not enable_virtual_scrolling or not virtual_scroll_container:
		return
	
	var current_scroll = virtual_scroll_container.scroll_vertical
	_refresh_virtual_display()
	await get_tree().process_frame
	virtual_scroll_container.scroll_vertical = current_scroll

func _toggle_slot_selection(slot: InventorySlot):
	if enable_virtual_scrolling:
		# For virtual scrolling, we need to track selection differently
		if slot in selected_slots:
			slot.set_selected(false)
			selected_slots.erase(slot)
		else:
			slot.set_selected(true)
			selected_slots.append(slot)
	else:
		# Traditional selection logic
		if slot in selected_slots:
			slot.set_selected(false)
			selected_slots.erase(slot)
		else:
			slot.set_selected(true)
			selected_slots.append(slot)

func clear_all_highlighting():
	"""Clear all highlighting from all slots"""
	if enable_virtual_scrolling:
		# For virtual scrolling, clear highlighting from virtual rendered slots
		for slot in virtual_rendered_slots:
			if slot and is_instance_valid(slot):
				slot.set_highlighted(false)
				slot.set_selected(false)
	else:
		# Traditional grid
		if not slots or slots.size() == 0:
			return
			
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
	if enable_virtual_scrolling:
		# Check virtual rendered slots
		for slot in virtual_rendered_slots:
			if slot and is_instance_valid(slot):
				var slot_rect = Rect2(slot.global_position, slot.size)
				if slot_rect.has_point(global_pos):
					return slot
		return null
	else:
		# Traditional grid lookup
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
func _on_container_item_added(item: InventoryItem_Base, position: Vector2i):
	if enable_virtual_scrolling:
		# Just refresh virtual display
		call_deferred("refresh_display")
	else:
		# Traditional handling - always compact when items are added from transfers
		if not _is_refreshing_display and not _resize_complete_timer.time_left > 0.0:
			call_deferred("_trigger_compact_refresh")

func _on_container_item_removed(item: InventoryItem_Base, position: Vector2i):
	if enable_virtual_scrolling:
		# Just refresh virtual display
		call_deferred("refresh_display")
	else:
		# Traditional handling - compact remaining items when items are removed
		if not _is_refreshing_display and not _resize_complete_timer.time_left > 0.0:
			call_deferred("_trigger_compact_refresh")

func _on_container_item_moved(item: InventoryItem_Base, old_position: Vector2i, new_position: Vector2i):
	if enable_virtual_scrolling:
		# In virtual mode, we don't track positions manually
		call_deferred("refresh_display")
	else:
		# Traditional handling
		if not _is_refreshing_display:
			item_positions[item] = new_position

func _is_any_slot_dragging() -> bool:
	if enable_virtual_scrolling:
		# For virtual scrolling, check virtual rendered slots
		for slot in virtual_rendered_slots:
			if slot and is_instance_valid(slot) and slot.is_dragging:
				return true
		return false
	else:
		# Traditional grid
		if not slots or slots.size() == 0:
			return false
			
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
	if enable_virtual_scrolling:
		# For virtual scrolling, select all virtual rendered slots with items
		clear_selection()
		for slot in virtual_rendered_slots:
			if slot and is_instance_valid(slot) and slot.has_item():
				slot.set_selected(true)
				selected_slots.append(slot)
	else:
		# Traditional grid
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

func _get_inventory_manager():
	"""Find the inventory manager"""	
	# First try the parent chain
	var current = get_parent()
	while current:
		if current.has_method("get_inventory_manager"):
			var manager = current.get_inventory_manager()
			return manager
		current = current.get_parent()
	
	# Try to find it in the scene tree
	var scene_root = get_tree().current_scene
	var result = _find_inventory_manager_recursive(scene_root)
	return result

func _find_inventory_manager_recursive(node: Node):
	"""Recursively search for inventory manager"""
	# Check if this node is an inventory manager
	if node.get_script():
		var script_path = str(node.get_script().resource_path)
		if "InventoryManager" in script_path or node.has_method("transfer_item"):
			return node
	
	# Check children
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
