# ContainerTearOffWindow.gd - Identical to main inventory window but with independent container view
class_name ContainerTearOffWindow
extends Window_Base

# Same signals as main window
signal container_switched(container: InventoryContainer_Base)

# Tearoff-specific signals
signal window_torn_off(container: InventoryContainer_Base, window: ContainerTearOffWindow)
signal window_reattached(container: InventoryContainer_Base)

# Identical structure to InventoryWindow
var inventory_manager: InventoryManager
var inventory_container: VBoxContainer
var header: InventoryWindowHeader
var content: InventoryWindowContent
var item_actions: InventoryItemActions

# Tearoff-specific properties
var container: InventoryContainer_Base # Original container reference
var container_view: ContainerView # Independent view of the container
var parent_window: InventoryWindow
var _suppress_auto_refresh: bool = false


func _init(tear_container: InventoryContainer_Base, parent_inv_window: InventoryWindow):
	super._init()

	container = tear_container
	parent_window = parent_inv_window

	if container:
		window_title = container.container_name
	else:
		window_title = "Container"


func _ready():
	# Same defaults as main inventory window
	default_size = Vector2(500, 400)
	min_window_size = Vector2(300, 250)
	max_window_size = Vector2(1200, 800)

	super._ready()

	mouse_filter = Control.MOUSE_FILTER_STOP
	# Same resize handling as main window
	window_resized.connect(_on_window_resized_for_grid)

	# ENABLE CROSS-WINDOW DRAG/DROP
	set_process_input(true)


func _input(event: InputEvent):
	"""Handle input with higher priority"""
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var window_rect = Rect2(global_position, size)
		
		# Only handle drops that happen WITHIN our window bounds
		if window_rect.has_point(event.global_position):
			# Check if drop is over a valid drop area
			var target_container = _get_tearoff_target_container(event.global_position)
			if not target_container:
				return # Not over a valid drop area
			
			var viewport = get_viewport()
			if viewport and viewport.has_meta("current_drag_data"):
				var drag_data = viewport.get_meta("current_drag_data")
				var source_slot = drag_data.get("source_slot")
				var source_row = drag_data.get("source_row")
				
				# Check if drag is from an external source (not our container) - HANDLE BOTH SLOT AND ROW
				var source_container_id = ""
				if source_slot and source_slot.has_method("get_container_id"):
					source_container_id = source_slot.get_container_id()
				elif source_row and source_row.has_method("_get_container_id"):
					source_container_id = source_row._get_container_id()
				
				if source_container_id != "":
					var our_container_id = container_view.container_id if container_view else container.container_id
					
					# Only accept drops from OTHER containers
					if source_container_id != our_container_id:
						if _handle_cross_window_drop(drag_data):
							get_viewport().set_input_as_handled()
							return

func _get_tearoff_target_container(drop_position: Vector2) -> InventoryContainer_Base:
	"""Check if drop position is over valid drop area in tearoff window"""
	if not content:
		return null
	
	# Check if dropping on container list area (even though it's just one container)
	if content.container_list:
		var list_rect = Rect2(content.container_list.global_position, content.container_list.size)
		if list_rect.has_point(drop_position):
			# Since tearoff windows only show one container, always return our container
			return container_view if container_view else container
	
	# Check if dropping on the inventory grid/list view area
	if content.inventory_grid and content.inventory_grid.visible:
		var grid_rect = Rect2(content.inventory_grid.global_position, content.inventory_grid.size)
		if grid_rect.has_point(drop_position):
			return container_view if container_view else container
	
	if content.list_view and content.list_view.visible:
		var list_view_rect = Rect2(content.list_view.global_position, content.list_view.size)
		if list_view_rect.has_point(drop_position):
			return container_view if container_view else container
	
	# If not over any valid drop area, reject
	return null


func _handle_cross_window_drop(drag_data: Dictionary) -> bool:
	"""Handle cross-window item drop with debug"""
	print("ContainerTearOffWindow: _handle_cross_window_drop called")
	
	var source_slot = drag_data.get("source_slot")
	var source_row = drag_data.get("source_row")
	var item = drag_data.get("item")
	
	print("ContainerTearOffWindow: source_slot=", source_slot, " source_row=", source_row, " item=", item)
	
	if not item or not inventory_manager:
		print("ContainerTearOffWindow: Missing item or inventory_manager")
		return false
	
	# Get source container ID
	var source_container_id = ""
	if source_slot and source_slot.has_method("get_container_id"):
		source_container_id = source_slot.get_container_id()
	elif source_row and source_row.has_method("_get_container_id"):
		source_container_id = source_row._get_container_id()
	
	print("ContainerTearOffWindow: source_container_id=", source_container_id)
	
	if source_container_id == "":
		print("ContainerTearOffWindow: Empty source container ID")
		return false
	
	# Get target container
	var target_container = container_view.source_container if container_view else container
	print("ContainerTearOffWindow: target_container=", target_container)
	print("ContainerTearOffWindow: target_container.container_id=", target_container.container_id if target_container else "null")
	
	if not target_container or source_container_id == target_container.container_id:
		print("ContainerTearOffWindow: Same container or no target")
		return false
	
	# Check if target can accept the item
	if not target_container.can_add_item(item):
		print("ContainerTearOffWindow: Target cannot accept item")
		return false
	
	# Calculate transfer amount
	var available_volume = target_container.get_available_volume()
	var max_transferable = int(available_volume / item.volume) if item.volume > 0 else item.quantity
	var transfer_amount = min(item.quantity, max_transferable)
	
	print("ContainerTearOffWindow: transfer_amount=", transfer_amount)
	
	if transfer_amount <= 0:
		print("ContainerTearOffWindow: No transferable amount")
		return false
	
	# Use the existing transaction manager
	print("ContainerTearOffWindow: Attempting transfer...")
	var success = inventory_manager.transfer_item(
		item,
		source_container_id,
		target_container.container_id,
		Vector2i(-1, -1),
		transfer_amount
	)
	
	print("ContainerTearOffWindow: Transfer result=", success)
	
	if success:
		# Force refresh our view
		if container_view:
			container_view.force_refresh()
		if content:
			content.refresh_display()
	
	return success


func _on_content_input(event: InputEvent):
	"""Handle input on content areas"""
	if event is InputEventMouseButton and event.pressed:
		bring_to_front()

func _on_content_gui_input(event: InputEvent):
	"""Handle drops on content area with debug"""
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			print("ContainerTearOffWindow: Content got mouse release")
			var viewport = get_viewport()
			if viewport and viewport.has_meta("current_drag_data"):
				print("ContainerTearOffWindow: Content has drag data")
				var drag_data = viewport.get_meta("current_drag_data")
				if _handle_cross_window_drop(drag_data):
					print("ContainerTearOffWindow: Successfully handled drop")
					return
			else:
				print("ContainerTearOffWindow: Content no drag data")


func _setup_window_content():
	"""Setup identical content to main inventory window"""
	_setup_content()


func _setup_content():
	"""Setup inventory-specific content - IDENTICAL to InventoryWindow"""
	# Get inventory manager from parent
	if parent_window:
		inventory_manager = parent_window.inventory_manager
	
	# Create main inventory container - SAME AS MAIN WINDOW
	inventory_container = VBoxContainer.new()
	inventory_container.name = "InventoryContainer"
	inventory_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_content(inventory_container)
	
	# Create the header (search, filter, sort) - SAME AS MAIN WINDOW
	header = InventoryWindowHeader.new()
	header.name = "InventoryHeader"
	inventory_container.add_child(header)
	
	# Create main content using InventoryWindowContent - SAME AS MAIN WINDOW
	content = InventoryWindowContent.new()
	content.name = "InventoryContent"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_container.add_child(content)
	
	# Wait for content to be ready
	await get_tree().process_frame
	
	# Setup item actions BEFORE initializing inventory content - SAME AS MAIN WINDOW
	_setup_item_actions()
	
	# ENABLE CROSS-WINDOW DROPS ON CONTENT
	if content and not content.gui_input.is_connected(_on_content_gui_input):
		content.gui_input.connect(_on_content_gui_input)
	
	# Connect header signals AFTER both header and content are created - SAME AS MAIN WINDOW
	if header:
		if header.has_signal("search_changed"):
			header.search_changed.connect(_on_search_changed)
		if header.has_signal("filter_changed"):
			header.filter_changed.connect(_on_filter_changed)
		if header.has_signal("sort_requested"):
			header.sort_requested.connect(_on_sort_requested)
		if header.has_signal("display_mode_changed"):
			header.display_mode_changed.connect(_on_display_mode_changed)
	
	if content:
		if content.has_signal("container_selected"):
			content.container_selected.connect(_on_container_selected_from_content)
		if content.has_signal("item_activated"):
			content.item_activated.connect(_on_item_activated_from_content)
		if content.has_signal("item_context_menu"):
			content.item_context_menu.connect(_on_item_context_menu_from_content)
		if content.has_signal("empty_area_context_menu"):
			content.empty_area_context_menu.connect(_on_empty_area_context_menu_from_content)
	
	# TEAROFF-SPECIFIC: Initialize with independent container view
	if inventory_manager and container:
		_initialize_tearoff_content()
	
	call_deferred("setup_child_focus_handlers")
	call_deferred("_resize_tearoff_window")


func _resize_tearoff_window():
	"""Resize tearoff window to smaller default size"""
	size = Vector2(500, 400)
	# Ensure it stays within screen bounds
	var viewport = get_viewport()
	if viewport:
		var screen_size = viewport.get_visible_rect().size
		position.x = clampf(position.x, 0, screen_size.x - size.x)
		position.y = clampf(position.y, 0, screen_size.y - size.y)


func _setup_item_actions():
	"""Initialize the item actions handler - SAME AS MAIN WINDOW"""
	var scene_window = get_viewport()
	if scene_window is Window:
		item_actions = InventoryItemActions.new(scene_window)
	else:
		var parent_window_ref = _find_parent_window()
		if parent_window_ref:
			item_actions = InventoryItemActions.new(parent_window_ref)
		else:
			push_error("Could not find parent window for InventoryItemActions")
			return

	# Set the inventory manager on item_actions - SAME AS MAIN WINDOW
	if inventory_manager:
		item_actions.set_inventory_manager(inventory_manager)

	# Connect to inventory manager updates - SAME AS MAIN WINDOW
	if item_actions.has_signal("container_refreshed"):
		item_actions.container_refreshed.connect(_on_container_refreshed)
	if content and content.has_method("set_item_actions"):
		content.set_item_actions(item_actions)


func _find_parent_window() -> Window:
	"""Find the parent window in the scene tree - SAME AS MAIN WINDOW"""
	var current = get_parent()
	while current:
		if current is Window:
			return current
		current = current.get_parent()
	return null


func _initialize_tearoff_content():
	"""Initialize content with independent container view - TEAROFF-SPECIFIC"""
	if not content or not inventory_manager or not container:
		return

	# CRITICAL: Create independent view instead of using container directly
	container_view = ContainerView.new(container, "tearoff_" + container.container_id)

	# REGISTER THE CONTAINER VIEW WITH INVENTORY MANAGER
	if inventory_manager.has_method("add_container"):
		inventory_manager.add_container(container_view)

	# FORCE REFRESH ON ANY CONTAINER CHANGES
	if container_view.has_signal("container_changed"):
		container_view.container_changed.connect(_on_view_changed)

	# Set inventory manager on content - SAME AS MAIN WINDOW
	if content.has_method("set_inventory_manager"):
		content.set_inventory_manager(inventory_manager)

	# Create single container array with the VIEW, not the original container
	var single_container_array: Array[InventoryContainer_Base] = [container_view]

	# Set current container on item_actions to use the VIEW
	if item_actions and item_actions.has_method("set_current_container"):
		item_actions.set_current_container(container_view)

	# Update containers list in content with the VIEW
	if content.has_method("update_containers"):
		content.update_containers(single_container_array)

	# Select the VIEW in the content
	if content.has_method("select_container"):
		content.select_container(container_view)


func _on_view_changed():
	"""Handle when the container view changes"""
	if _suppress_auto_refresh:
		return
		
	if content:
		content.refresh_display()


# ALL THE SAME EVENT HANDLERS AS MAIN WINDOW BUT WORKING WITH VIEW
func _on_search_changed(search_text: String):
	"""Handle search text changes - TEAROFF-SPECIFIC (affects only this view)"""
	if not container_view:
		return
	
	# Temporarily suppress automatic refreshes to avoid lag
	_suppress_auto_refresh = true
	
	# Update search without triggering container_changed
	container_view.search_filter = search_text
	container_view._refresh_view()
	container_view.items = container_view.view_items
	
	# Re-enable refreshes and do ONE final refresh
	_suppress_auto_refresh = false
	if content:
		content.refresh_display()


func _on_filter_changed(filter_type: int):
	"""Handle filter changes - TEAROFF-SPECIFIC (affects only this view)"""
	if container_view:
		container_view.set_type_filter(filter_type)


func _on_sort_requested(sort_type: InventorySortType.Type):
	"""Handle sort requests - TEAROFF-SPECIFIC (affects only this view)"""
	if not inventory_manager or not container_view:
		return
	
	# Temporarily suppress automatic refreshes to avoid lag
	_suppress_auto_refresh = true
	
	# FIRST: Sort the source container like the main window does
	inventory_manager.sort_container(container_view.source_container.container_id, sort_type)
	
	# SECOND: Update the view's sort settings (but don't emit container_changed)
	container_view.sort_type = sort_type
	container_view.sort_ascending = true
	container_view._apply_current_sort()
	container_view.items = container_view.view_items
	
	# THIRD: Re-enable refreshes and do ONE final refresh
	_suppress_auto_refresh = false
	if content and content.inventory_grid:
		await get_tree().process_frame # Wait for sort to complete
		content.inventory_grid.refresh_display()


func _on_display_mode_changed(mode: InventoryDisplayMode.Mode):
	"""Handle display mode changes - SAME AS MAIN WINDOW"""
	if content and content.has_method("set_display_mode"):
		content.set_display_mode(mode)


func _on_container_selected_from_content(selected_container: InventoryContainer_Base):
	"""Handle container selection - TEAROFF-SPECIFIC (should only be the view)"""
	# In tearoff window, this should only ever be the container view
	if selected_container == container_view:
		if item_actions and item_actions.has_method("set_current_container"):
			item_actions.set_current_container(container_view)
		container_switched.emit(container_view)


func _on_item_activated_from_content(item: InventoryItem_Base, slot: InventorySlot):
	"""Handle item activation - SAME AS MAIN WINDOW"""
	if item_actions and item_actions.has_method("handle_item_activation"):
		item_actions.handle_item_activation(item, slot)


func _on_item_context_menu_from_content(item: InventoryItem_Base, slot: InventorySlot, position: Vector2):
	"""Handle item context menu - SAME AS MAIN WINDOW"""
	if item_actions and item_actions.has_method("show_item_context_menu"):
		item_actions.show_item_context_menu(item, slot, position)


func _on_empty_area_context_menu_from_content(global_position: Vector2):
	"""Handle empty area context menu - SAME AS MAIN WINDOW"""
	if item_actions and item_actions.has_method("show_empty_area_context_menu"):
		item_actions.show_empty_area_context_menu(global_position)


func _on_window_resized_for_grid(_new_size: Vector2i):
	"""Handle window resize for grid reflow - SAME AS MAIN WINDOW"""
	if content:
		call_deferred("_handle_content_resize")


func _handle_content_resize():
	"""Handle content resize - SAME AS MAIN WINDOW"""
	if not content:
		return

	# Let the content handle its own resize
	if content.has_method("_handle_display_resize"):
		content._handle_display_resize()


func _on_container_refreshed():
	"""Handle container refresh from item actions - SAME AS MAIN WINDOW"""
	# Refresh the display when items change
	if content and content.has_method("refresh_display"):
		content.refresh_display()


# TEAROFF-SPECIFIC METHODS
func get_container() -> InventoryContainer_Base:
	"""Get the container view this window represents"""
	return container_view if container_view else container


func get_original_container() -> InventoryContainer_Base:
	"""Get the original container (not the view)"""
	return container


func reattach_to_parent():
	"""Reattach this container to the parent window"""
	# Check if parent window still exists
	if not parent_window or not is_instance_valid(parent_window):
		print("ContainerTearOffWindow: Cannot reattach - parent window no longer exists")
		# Just close this window since there's nowhere to reattach to
		hide_window()
		queue_free()
		return

	window_reattached.emit(container) # Emit original container, not view
	hide_window()
	queue_free()


# SAME CLEANUP AS MAIN WINDOW WITH VIEW CLEANUP
func hide_window():
	"""Override to ensure proper cleanup - SAME AS MAIN WINDOW + VIEW CLEANUP"""
	if item_actions:
		item_actions.close_all_dialogs()

	# TEAROFF-SPECIFIC: Clean up the independent view
	if container_view:
		container_view.cleanup()
		container_view = null

	super.hide_window()


func _on_window_closed():
	"""Override close handling - TEAROFF-SPECIFIC"""
	# Clean up the independent view first
	if container_view:
		container_view.cleanup()
		container_view = null

	if item_actions:
		item_actions.close_all_dialogs()
		item_actions.cleanup()

	# Check if this is the last UI window before restoring game input
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	if ui_managers.size() > 0:
		var ui_manager = ui_managers[0]
		if ui_manager.has_method("get_all_windows"):
			var remaining_windows = ui_manager.get_all_windows()
			# Filter out this window since it's closing
			var other_windows = remaining_windows.filter(func(w): return w != self and is_instance_valid(w))

			if other_windows.size() == 0:
				# This is the last UI window - emit inventory_closed to restore game input
				print("ContainerTearOffWindow: Last UI window closing, emitting inventory_closed")
				var integration = _find_inventory_integration(get_tree().current_scene)
				if integration:
					integration._set_player_input_enabled(true)
					integration.inventory_toggled.emit(false)
					if integration.event_bus:
						integration.event_bus.emit_inventory_closed()
				else:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				print("ContainerTearOffWindow: %d UI windows remaining, keeping UI input active" % other_windows.size())

	# Only try to reattach if parent window still exists
	if parent_window and is_instance_valid(parent_window):
		# Emit reattach signal when window is closed (use original container)
		reattach_to_parent()
	else:
		# Parent window is gone, just clean up
		print("ContainerTearOffWindow: Parent window gone, cleaning up independently")
		queue_free()


func _find_inventory_integration(node: Node) -> InventoryIntegration:
	"""Find the inventory integration in the scene tree"""
	if node is InventoryIntegration:
		return node

	for child in node.get_children():
		var result = _find_inventory_integration(child)
		if result:
			return result
	return null


# PUBLIC INTERFACE - SAME AS MAIN WINDOW WITH VIEW AWARENESS
func set_inventory_manager(manager: InventoryManager):
	"""Set inventory manager - SAME AS MAIN WINDOW"""
	inventory_manager = manager

	# Set up item actions now that we have inventory manager
	if not item_actions:
		_setup_item_actions()

	# Also set/update it on item_actions if it exists
	if item_actions and item_actions.has_method("set_inventory_manager"):
		item_actions.set_inventory_manager(inventory_manager)

	# Initialize content with inventory manager
	if manager and container:
		_initialize_tearoff_content()


func get_current_container() -> InventoryContainer_Base:
	"""Get current container - TEAROFF-SPECIFIC (returns the view)"""
	return container_view if container_view else container


func show_window():
	"""Show window and register with UIManager"""
	super.show_window()

	# Make sure we're registered with UIManager
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	if ui_managers.size() > 0:
		var ui_manager = ui_managers[0]
		if ui_manager.has_method("focus_window"):
			ui_manager.focus_window(self)


# TEAROFF-SPECIFIC VIEW CONTROL METHODS
func set_view_search_filter(filter: String):
	"""Set search filter for this tearoff view only"""
	if container_view:
		container_view.set_search_filter(filter)


func set_view_type_filter(filter: ItemTypes.Type):
	"""Set type filter for this tearoff view only"""
	if container_view:
		container_view.set_type_filter(filter)


func set_view_sort(sort_type: InventorySortType.Type, ascending: bool = true):
	"""Set sort for this tearoff view only"""
	if container_view:
		container_view.set_sort(sort_type, ascending)


func get_view_state() -> Dictionary:
	"""Get current view state for saving/restoring"""
	if not container_view:
		return {}

	return {"search_filter": container_view.search_filter, "type_filter": container_view.type_filter, "sort_type": container_view.sort_type, "sort_ascending": container_view.sort_ascending}


func restore_view_state(state: Dictionary):
	"""Restore view state from saved data"""
	if not container_view:
		return

	if state.has("search_filter"):
		container_view.set_search_filter(state.search_filter)
	if state.has("type_filter"):
		container_view.set_type_filter(state.type_filter)
	if state.has("sort_type") and state.has("sort_ascending"):
		container_view.set_sort(state.sort_type, state.sort_ascending)


func _ensure_ui_manager_registration():
	"""Ensure this window is registered with UIManager"""
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	if ui_managers.size() > 0:
		var ui_manager = ui_managers[0]
		if ui_manager.has_method("register_window"):
			print("ContainerTearOffWindow: Registering %s with UIManager" % name)
			ui_manager.register_window(self, "tearoff")
		else:
			print("ContainerTearOffWindow: UIManager doesn't have register_window method")
	else:
		print("ContainerTearOffWindow: No UIManager found")
