# InventoryWindowContent.gd - Updated with debugging and proper initialization
class_name InventoryWindowContent
extends HSplitContainer

# UI Components
var container_list: ItemList
var inventory_grid: InventoryGrid
var mass_info_bar: Panel
var mass_info_label: Label
var is_drag_highlighting_active: bool = false
var current_display_mode: InventoryDisplayMode.Mode = InventoryDisplayMode.Mode.GRID
var list_view: InventoryListView
var pending_dummy_slots: Array[InventorySlot] = []

# References
var inventory_manager: InventoryManager
var current_container: InventoryContainer_Base
var open_containers: Array[InventoryContainer_Base] = []

# Signals
signal container_selected(container: InventoryContainer_Base)
signal item_activated(item: InventoryItem_Base, slot: InventorySlot)
signal item_context_menu(item: InventoryItem_Base, slot: InventorySlot, position: Vector2)
signal empty_area_context_menu(position: Vector2)

func _ready():
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Set dynamic split offset based on window size
	_update_split_offset()
	
	_remove_split_container_outline()
	_setup_content()
	
	# Connect gui_input for drop handling
	gui_input.connect(_gui_input)
	
	# Connect to size changes to update split offset
	resized.connect(_on_content_resized)
	
	var cleanup_timer = Timer.new()
	cleanup_timer.wait_time = 2.0  # Clean up every 2 seconds
	cleanup_timer.timeout.connect(_cleanup_dummy_slots)
	add_child(cleanup_timer)
	cleanup_timer.start()
	
func set_display_mode(mode: InventoryDisplayMode.Mode):
	if mode == current_display_mode:
		return
		
	# FIXED: Only disconnect the mode we're switching FROM
	match current_display_mode:
		InventoryDisplayMode.Mode.GRID:
			if inventory_grid:
				inventory_grid._disconnect_container_signals()
		InventoryDisplayMode.Mode.LIST:
			if list_view:
				list_view._disconnect_container_signals()
	
	current_display_mode = mode
	
	match mode:
		InventoryDisplayMode.Mode.GRID:
			_switch_to_grid_mode()
		InventoryDisplayMode.Mode.LIST:
			_switch_to_list_mode()
	
	# Connect new mode to container signals
	if current_container:
		_connect_container_signals()
		call_deferred("_refresh_current_display")
		
func _refresh_current_display():
	"""Force refresh the currently visible display"""
	if not current_container:
		return
		
	match current_display_mode:
		InventoryDisplayMode.Mode.GRID:
			if inventory_grid and inventory_grid.visible:
				inventory_grid.refresh_display()
		InventoryDisplayMode.Mode.LIST:
			if list_view and list_view.visible:
				list_view.refresh_display()

func _switch_to_list_mode():
	# Hide grid
	if inventory_grid:
		inventory_grid.visible = false
	
	# Create or show list view
	if not list_view:
		list_view = InventoryListView.new()
		list_view.name = "ListView"
		list_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list_view.clip_contents = true
		
		var grid_parent = inventory_grid.get_parent()
		if grid_parent:
			grid_parent.add_child(list_view)
			list_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		
		# Connect list view signals
		list_view.item_selected.connect(_on_list_item_selected)
		list_view.item_context_menu.connect(_on_item_context_menu_from_list)
		list_view.empty_area_context_menu.connect(_on_empty_area_context_menu)  # ADD THIS
	
	list_view.visible = true
	
	# Force proper sizing using set_deferred to avoid anchor warning
	if list_view.get_parent():
		list_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		list_view.set_deferred("size", list_view.get_parent().size)
	
	# CRITICAL: Set container and refresh if we have one
	if current_container:
		list_view.set_container(current_container, current_container.container_id if current_container else "")
		list_view.refresh_display()

func _switch_to_grid_mode():
	# Hide list view
	if list_view:
		list_view.visible = false
	
	# Show grid
	if inventory_grid:
		inventory_grid.visible = true
		
		# Refresh grid display when switching back
		if current_container:
			inventory_grid.refresh_display()

func _on_item_context_menu_from_list(item: InventoryItem_Base, position: Vector2):
	# Check if we still have a valid container
	if not current_container:
		return
	
	# Create a dummy slot for compatibility with existing context menu system
	var dummy_slot = InventorySlot.new()
	dummy_slot.set_item(item)
	dummy_slot.set_container_id(current_container.container_id)
	
	# Store the dummy slot so we can clean it up later
	pending_dummy_slots.append(dummy_slot)
	
	item_context_menu.emit(item, dummy_slot, position)
	
func _on_list_item_selected(item: InventoryItem_Base):
	# Check if we still have a valid container
	if not current_container:
		return
	
	# Create a dummy slot for compatibility with existing systems
	var dummy_slot = InventorySlot.new()
	dummy_slot.set_item(item)
	dummy_slot.set_container_id(current_container.container_id)
	
	# Store the dummy slot so we can clean it up later
	pending_dummy_slots.append(dummy_slot)
	
	# Emit the existing signal that other systems expect
	item_activated.emit(item, dummy_slot)
	
func _cleanup_dummy_slots():
	"""Clean up any pending dummy slots"""
	for slot in pending_dummy_slots:
		if is_instance_valid(slot):
			slot.queue_free()
	pending_dummy_slots.clear()
	
func _update_split_offset():
	"""Update split offset based on available space"""
	await get_tree().process_frame
	
	var available_width = size.x
	if available_width <= 0:
		split_offset = 180
		return
	
	# More aggressive space optimization for small windows
	var min_left_width = 140
	var max_left_width = 200
	var max_left_percentage = 0.35
	
	# For very small windows, use even smaller left panel
	if available_width <= 450:
		max_left_percentage = 0.3
		min_left_width = 120
	
	var calculated_left = min(max_left_width, available_width * max_left_percentage)
	var new_split_offset = max(min_left_width, calculated_left)
	
	split_offset = new_split_offset

func _on_content_resized():
	"""Called when the content area is resized"""
	_update_split_offset()
	call_deferred("_handle_display_resize")
	
func _handle_display_resize():
	match current_display_mode:
		InventoryDisplayMode.Mode.GRID:
			if inventory_grid and inventory_grid.has_method("handle_window_resize"):
				inventory_grid.handle_window_resize()
		InventoryDisplayMode.Mode.LIST:
			if list_view and list_view.has_method("_on_resized"):
				list_view._on_resized()

func _remove_split_container_outline():
	# Remove the default HSplitContainer theme that creates outlines
	var theme = Theme.new()
	
	# Create custom grabber style without outlines
	var grabber_style = StyleBoxFlat.new()
	grabber_style.bg_color = Color(0.4, 0.4, 0.4, 1.0)
	
	# Remove any border/outline styling
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color.TRANSPARENT
	panel_style.border_width_left = 0
	panel_style.border_width_right = 0
	panel_style.border_width_top = 0
	panel_style.border_width_bottom = 0
	
	theme.set_stylebox("grabber", "HSplitContainer", grabber_style)
	theme.set_stylebox("panel", "HSplitContainer", panel_style)
	theme.set_stylebox("bg", "HSplitContainer", panel_style)
	
	set_theme(theme)

# Modified _setup_content method
func _setup_content():
	# Setup both panels
	_setup_left_panel()
	_setup_right_panel()

func _setup_left_panel():
	var left_panel = VBoxContainer.new()
	left_panel.name = "LeftPanel"
	left_panel.custom_minimum_size.x = 180
	left_panel.size_flags_horizontal = Control.SIZE_FILL
	
	add_child(left_panel)
	
	container_list = ItemList.new()
	container_list.name = "ContainerList"
	container_list.mouse_filter = Control.MOUSE_FILTER_PASS
	container_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container_list.custom_minimum_size = Vector2(160, 200)
	container_list.auto_height = true
	container_list.allow_rmb_select = false
	container_list.focus_mode = Control.FOCUS_NONE
	
	# Set up drop detection on container list
	container_list.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Add padding for items inside the container list
	container_list.add_theme_constant_override("h_separation", 4)
	container_list.add_theme_constant_override("v_separation", 2)
	container_list.add_theme_constant_override("item_h_separation", 4)
	container_list.add_theme_constant_override("item_v_separation", 2)
	
	# Keep normal dark background for container list
	var list_style = StyleBoxFlat.new()
	list_style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	list_style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	list_style.border_width_left = 1
	list_style.border_width_right = 1
	list_style.border_width_top = 1
	list_style.border_width_bottom = 1
	list_style.content_margin_left = 6
	list_style.content_margin_right = 6
	list_style.content_margin_top = 4
	list_style.content_margin_bottom = 4
	container_list.add_theme_stylebox_override("panel", list_style)
	
	left_panel.add_child(container_list)
	
	container_list.item_selected.connect(_on_container_list_selected)
	container_list.gui_input.connect(_on_container_list_input)
	
	# Set up drop area handling
	_setup_container_drop_handling()

func _on_empty_area_context_menu(position: Vector2):
	"""Handle empty area context menu from grid"""
	empty_area_context_menu.emit(position)

func set_item_actions(actions: InventoryItemActions):
	"""Set item actions on the inventory grid"""
	if inventory_grid and inventory_grid.has_method("set_item_actions"):
		inventory_grid.set_item_actions(actions)

func _setup_right_panel():
	var inventory_area = VBoxContainer.new()
	inventory_area.name = "InventoryArea"
	inventory_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_area.add_theme_constant_override("separation", 4)
	# Enable clipping for the entire right panel area
	inventory_area.clip_contents = true
	add_child(inventory_area)
	
	_setup_mass_info_bar(inventory_area)
	
	# Create a container specifically for the grid with clipping
	var grid_container = Control.new()
	grid_container.name = "GridContainer"
	grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_container.clip_contents = true  # This will clip the grid content
	
	inventory_area.add_child(grid_container)
	
	inventory_grid = InventoryGrid.new()
	inventory_grid.name = "InventoryGrid"
	inventory_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# SET PROPERTIES BEFORE ADDING TO SCENE
	inventory_grid.enable_virtual_scrolling = true
	inventory_grid.slot_size = Vector2(64, 64)  # Correct property name
	inventory_grid.virtual_item_height = 64
	grid_container.add_child(inventory_grid)
	
	# Connect signals
	inventory_grid.item_activated.connect(_on_item_activated)
	inventory_grid.item_context_menu.connect(_on_item_context_menu)
	inventory_grid.empty_area_context_menu.connect(_on_empty_area_context_menu)

func _setup_mass_info_bar(parent: Control):
	var mass_bar_container = MarginContainer.new()
	parent.add_child(mass_bar_container)
	
	mass_bar_container.add_theme_constant_override("margin_right", 0)
	
	mass_info_bar = Panel.new()
	mass_info_bar.name = "MassInfoBar"
	mass_info_bar.custom_minimum_size.y = 24
	mass_info_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	mass_bar_container.add_child(mass_info_bar)
	
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	style_box.border_color = Color(0.4, 0.4, 0.4, 1.0)
	style_box.border_width_left = 1
	style_box.border_width_right = 1
	style_box.border_width_top = 1
	style_box.border_width_bottom = 1
	mass_info_bar.add_theme_stylebox_override("panel", style_box)
	
	# Create a margin container for padding inside the mass info bar
	var margin_container = MarginContainer.new()
	margin_container.name = "MassInfoMargin"
	margin_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_left", 8)
	margin_container.add_theme_constant_override("margin_right", 8)
	margin_container.add_theme_constant_override("margin_top", 4)
	margin_container.add_theme_constant_override("margin_bottom", 4)
	mass_info_bar.add_child(margin_container)
	
	mass_info_label = Label.new()
	mass_info_label.name = "MassInfoLabel"
	mass_info_label.text = "No container selected"
	mass_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mass_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mass_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mass_info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mass_info_label.add_theme_color_override("font_color", Color.WHITE)
	mass_info_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	mass_info_label.add_theme_constant_override("shadow_offset_x", 1)
	mass_info_label.add_theme_constant_override("shadow_offset_y", 1)
	mass_info_label.add_theme_font_size_override("font_size", 12)
	
	# Enable text clipping to prevent overflow
	mass_info_label.clip_contents = true
	mass_info_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	mass_info_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	
	margin_container.add_child(mass_info_label)

func _format_currency(value: float) -> String:
	return InventoryMath.format_currency(value)

func _on_container_list_selected(index: int):
	if index >= 0 and index < open_containers.size():
		var selected_container = open_containers[index]
		select_container(selected_container)
		container_selected.emit(selected_container)

func _on_item_activated(item: InventoryItem_Base, slot: InventorySlot):
	item_activated.emit(item, slot)

func _on_item_context_menu(item: InventoryItem_Base, slot: InventorySlot, position: Vector2):
	item_context_menu.emit(item, slot, position)

# Public interface with debug output
func set_inventory_manager(manager: InventoryManager):
	inventory_manager = manager

func update_containers(containers: Array[InventoryContainer_Base]):
	open_containers = containers
	
	# Use external container list if available, otherwise use internal one
	var list_to_update = container_list
	
	if not list_to_update:
		return
	
	list_to_update.clear()
	
	for i in range(containers.size()):
		var container = containers[i]
		var _total_qty = container.get_total_quantity()
		var unique_items = container.get_item_count()
		
		var container_text = container.container_name
		
		list_to_update.add_item(container_text)
		var item_index = list_to_update.get_item_count() - 1
		container_list.set_item_tooltip_enabled(item_index, false)

func select_container(container: InventoryContainer_Base):	
	# Disconnect from previous container if exists
	if current_container:
		_disconnect_container_signals()
	
	current_container = container
	
	# Connect to new container signals
	if container:
		_connect_container_signals()
	
	# Set container on both views, but don't double-refresh
	if container:
		
		# Set container on grid - this already calls refresh_display internally
		if inventory_grid:
			inventory_grid.set_container(container)
			await get_tree().process_frame
			if inventory_grid.visible:
				inventory_grid.refresh_display()
		
		# Set container on list view - this already calls refresh_display internally
		if list_view:
			list_view.set_container(container, container.container_id)
			# REMOVE THIS LINE: list_view.refresh_display()
	else:
		# Clear both displays
		if inventory_grid:
			inventory_grid.set_container(null)
		if list_view:
			list_view.set_container(null, "")
	
	update_mass_info()
	
func _connect_container_signals():
	"""Connect to container signals for real-time updates"""
	if current_container:
		if not current_container.item_added.is_connected(_on_container_item_added):
			current_container.item_added.connect(_on_container_item_added)
		if not current_container.item_removed.is_connected(_on_container_item_removed):
			current_container.item_removed.connect(_on_container_item_removed)
		if not current_container.item_moved.is_connected(_on_container_item_moved):
			current_container.item_moved.connect(_on_container_item_moved)
		
		# SIMPLIFIED: Just connect both - only the visible one will actually refresh
		if inventory_grid and not inventory_grid._is_connected_to_container():
			inventory_grid._connect_container_signals()
		
		if list_view and not list_view._is_connected_to_container():
			list_view._connect_container_signals()

func _disconnect_container_signals():
	"""Disconnect from container signals"""
	if current_container:
		if current_container.item_added.is_connected(_on_container_item_added):
			current_container.item_added.disconnect(_on_container_item_added)
		if current_container.item_removed.is_connected(_on_container_item_removed):
			current_container.item_removed.disconnect(_on_container_item_removed)
		if current_container.item_moved.is_connected(_on_container_item_moved):
			current_container.item_moved.disconnect(_on_container_item_moved)
		
		# Disconnect from item quantity changes
		for item in current_container.items:
			if item.quantity_changed.is_connected(_on_item_quantity_changed):
				item.quantity_changed.disconnect(_on_item_quantity_changed)
			
func _on_item_quantity_changed(new_quantity: int):
	"""Handle item quantity changes - update mass info"""
	update_mass_info()
			
func _on_container_item_added(item: InventoryItem_Base, position: Vector2i):
	"""Handle item added to current container - update mass info and connect to item signals"""
	# Connect to the new item's quantity change signal
	if not item.quantity_changed.is_connected(_on_item_quantity_changed):
		item.quantity_changed.connect(_on_item_quantity_changed)
	
	update_mass_info()

func _on_container_item_removed(item: InventoryItem_Base, position: Vector2i):
	"""Handle item removed from current container - update mass info and disconnect from item signals"""
	# Disconnect from the removed item's quantity change signal
	if item.quantity_changed.is_connected(_on_item_quantity_changed):
		item.quantity_changed.disconnect(_on_item_quantity_changed)
	
	update_mass_info()

func _on_container_item_moved(item: InventoryItem_Base, old_position: Vector2i, new_position: Vector2i):
	"""Handle item moved within current container - usually no mass change, but update for consistency"""
	update_mass_info()

func select_container_index(index: int):
	if index >= 0 and index < open_containers.size():
		var list_to_use = container_list
		if list_to_use:
			list_to_use.select(index)

func refresh_display():
	if not inventory_grid:
		return
	
	if not current_container:
		return
	
	# Make sure the grid has the container set
	inventory_grid.set_container(current_container)
	await get_tree().process_frame
	
	# Force compact refresh
	inventory_grid.trigger_compact_refresh()
	
	# Update mass info
	update_mass_info()

func update_mass_info():
	if not current_container or not mass_info_label:
		if mass_info_label:
			mass_info_label.text = "No container selected"
		return
	
	var info = current_container.get_container_info()
	
	var text = "Items: %d (%d types)  |  " % [info.total_quantity, info.item_count]
	text += "Volume: %.1f/%.1f m³ (%.1f%%)  |  " % [info.volume_used, info.volume_max, info.volume_percentage]
	text += "Mass: %.1f t  |  " % info.total_mass
	text += "Value: " + _format_currency(info.total_value)
	
	mass_info_label.text = text
	
	if info.volume_percentage > 90:
		mass_info_label.add_theme_color_override("font_color", Color.RED)
	elif info.volume_percentage > 75:
		mass_info_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		mass_info_label.add_theme_color_override("font_color", Color.WHITE)

func get_current_container() -> InventoryContainer_Base:
	return current_container

func get_inventory_grid() -> InventoryGrid:
	return inventory_grid
	
func get_current_display_mode() -> InventoryDisplayMode.Mode:
	return current_display_mode

# Container drop handling methods
func _setup_container_drop_handling():
	"""Set up the container list to accept drops from inventory slots"""
	if not container_list:
		return

func _process(_delta):
	# Check for ongoing drags and highlight valid drop targets
	var viewport = get_viewport()
	if viewport and viewport.has_meta("current_drag_data"):
		var drag_data = viewport.get_meta("current_drag_data", null)

		_update_container_drop_highlights()
	else:
		# No drag in progress - ensure highlights are cleared
		_clear_all_container_highlights()

func _update_container_drop_highlights():
	var viewport = get_viewport()
	var drag_data = null
	if viewport:
		drag_data = viewport.get_meta("current_drag_data", null)
	
	if not drag_data or not container_list:
		_clear_all_container_highlights()
		return
	
	var item = drag_data.get("item") as InventoryItem_Base
	var source_slot = drag_data.get("source_slot")
	var source_row = drag_data.get("source_row")
	
	# Get the appropriate source object and validate it's still dragging
	var source_dragging = false
	var source_container_id = ""
	
	if source_slot and is_instance_valid(source_slot):
		var slot = source_slot as InventorySlot
		source_dragging = slot.is_dragging
		source_container_id = slot.get_container_id()
	elif source_row and is_instance_valid(source_row):
		var row = source_row as ListRowManager
		source_dragging = row.is_dragging
		source_container_id = row._get_container_id()
	
	# Validate that we have a valid source and item
	if not item or not source_dragging:
		_clear_all_container_highlights()
		viewport.remove_meta("current_drag_data")
		return
	
	var mouse_pos = get_global_mouse_position()
	var container_rect = Rect2(container_list.global_position, container_list.size)
	
	# Check if mouse is over container list area
	if container_rect.has_point(mouse_pos):
		# Get the specific item index under the mouse
		var local_pos = mouse_pos - container_list.global_position
		var hovered_item_index = container_list.get_item_at_position(local_pos, true)
		
		# Clear all highlights first
		_clear_all_container_highlights()
		
		# Only highlight if we have a valid container index
		if hovered_item_index >= 0 and hovered_item_index < open_containers.size():
			var target_container = open_containers[hovered_item_index]
			
			# Don't highlight the same container
			if target_container.container_id == source_container_id:
				return
			
			# Use existing highlight color logic
			var highlight_color = _get_container_highlight_color(target_container, item)
			container_list.set_item_custom_bg_color(hovered_item_index, highlight_color)
	else:
		# Mouse not over container list
		_clear_all_container_highlights()
		
func _debug_container_transfer_capability(container: InventoryContainer_Base, item: InventoryItem_Base) -> Dictionary:
	"""Debug helper to understand why a container shows red/green"""
	var result = {
		"container_name": container.container_name,
		"item_name": item.item_name,
		"available_volume": container.get_available_volume(),
		"item_volume_per_unit": item.volume,
		"item_quantity": item.quantity,
		"total_item_volume": item.get_total_volume(),
		"can_add_full_stack": container.can_add_item(item),
		"max_transferable": 0,
		"has_stackable_item": false,
		"type_allowed": true
	}
	
	# Calculate max transferable by volume
	if item.volume > 0:
		result.max_transferable = int(container.get_available_volume() / item.volume)
	else:
		result.max_transferable = item.quantity if container.can_add_item(item) else 0
	
	# Check for stackable items
	var stackable_item = container.find_stackable_item(item)
	result.has_stackable_item = stackable_item != null
	if stackable_item:
		result.stack_space = stackable_item.max_stack_size - stackable_item.quantity
	
	# Check type restrictions
	if not container.allowed_item_types.is_empty():
		result.type_allowed = item.item_type in container.allowed_item_types
	
	return result
		
func _get_container_highlight_color(container: InventoryContainer_Base, item: InventoryItem_Base) -> Color:
	"""Determine the highlight color for a container based on transfer capability"""
	
	# Check if item can be transferred at all
	if not container or not item:
		return Color.RED.darkened(0.3)
		
	# Use the new method that properly checks all rejection scenarios
	var can_accept = false
	if container.has_method("can_accept_any_quantity_for_ui"):
		can_accept = container.can_accept_any_quantity_for_ui(item)
	else:
		# Fallback to basic checks
		can_accept = container.get_available_volume() > 0.0 and container.get_available_volume() >= item.volume
	
	if can_accept:
		return Color.GREEN.darkened(0.5)
	else:
		return Color.RED.darkened(0.3)

func _clear_all_container_highlights():
	"""Clear all container list highlights"""
	if not container_list:
		return
	
	for i in range(container_list.get_item_count()):
		container_list.set_item_custom_bg_color(i, Color.TRANSPARENT)
		
func force_clear_highlights():
	"""Force clear all highlights and disable highlighting"""
	is_drag_highlighting_active = false
	_clear_all_container_highlights()

func _gui_input(event: InputEvent):
	if event is InputEventMouseMotion:
		var viewport = get_viewport()
		if not (viewport and viewport.has_meta("current_drag_data")):
			# No drag data - force clear highlights if they somehow got stuck
			if is_drag_highlighting_active:
				_clear_all_container_highlights()
				is_drag_highlighting_active = false

func _on_container_list_input(_event: InputEvent):
	# Handle specific container list input events
	pass

# Transparency handling
func set_transparency(transparency: float):
	
	modulate.a = transparency
	
	# Apply transparency using stored originals
	_apply_content_transparency_from_originals(transparency)

func _apply_content_transparency_from_originals(transparency: float):
	# Apply to mass info bar
	
	# Apply to inventory grid
	if inventory_grid and inventory_grid.has_method("set_transparency"):
		inventory_grid.set_transparency(transparency)
		
func filter_items(search_text: String):
	if current_display_mode == InventoryDisplayMode.Mode.LIST and list_view:
		list_view.set_search_filter(search_text)
	elif inventory_grid:
		inventory_grid.filter_items(search_text)

func set_filter_type(filter_type: int):
	if current_display_mode == InventoryDisplayMode.Mode.LIST and list_view:
		list_view.set_type_filter(filter_type)
	elif inventory_grid:
		inventory_grid.set_filter_type(filter_type)
		
func _add_pending_dummy_slot(slot: InventorySlot):
	"""Add a dummy slot to the cleanup list"""
	pending_dummy_slots.append(slot)
