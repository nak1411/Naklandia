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
var container: InventoryContainer_Base  # Original container reference
var container_view: ContainerView  # Independent view of the container
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
	"""Handle input with higher priority for cross-window drops"""
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var window_rect = Rect2(global_position, size)
		var viewport = get_viewport()

		# Check if drop is within our window bounds
		if window_rect.has_point(event.global_position):
			var all_windows = get_tree().get_nodes_in_group("external_container_windows")
			var topmost_window = null
			var highest_z = -999999

			for window in all_windows:
				if is_instance_valid(window):
					var w_rect = Rect2(window.global_position, window.size)
					if w_rect.has_point(event.global_position):
						if window.z_index > highest_z:
							highest_z = window.z_index
							topmost_window = window

			# Only process if we're the topmost windowii
			if topmost_window != self:
				print("TEAROFF: Not topmost window, ignoring input")
				return
			# Check if there's an active drag operation
			if viewport and viewport.has_meta("current_drag_data"):
				var drag_data = viewport.get_meta("current_drag_data")
				var source_slot = drag_data.get("source_slot")
				var source_row = drag_data.get("source_row")

				# Check if drag is from an external source (not our container)
				var source_container_id = ""
				if source_slot and source_slot.has_method("get_container_id"):
					source_container_id = source_slot.get_container_id()
				elif source_row and source_row.has_method("_get_container_id"):
					source_container_id = source_row._get_container_id()

				if source_container_id != "":
					var our_container_id = container_view.container_id if container_view else container.container_id

					# Check if it's a cross-container drop
					if source_container_id != our_container_id:
						# Check if drop is over a valid drop area
						var target_container = _get_tearoff_target_container(event.global_position)
						if target_container:
							# Valid cross-container drop - handle it and block event
							if _handle_cross_window_drop(drag_data):
								get_viewport().set_input_as_handled()
								return

						# Invalid drop area but cross-container - block and cleanup
						_cleanup_failed_drop(drag_data)
						get_viewport().set_input_as_handled()
						return

					# Same container drop - block and cleanup
					_cleanup_failed_drop(drag_data)
					get_viewport().set_input_as_handled()
					return

			# No drag operation active - regular window interaction
			return

		# Handle drops FROM this tearoff TO external containers
		if viewport and viewport.has_meta("current_drag_data"):
			var drag_data = viewport.get_meta("current_drag_data")
			var source_slot = drag_data.get("source_slot")
			var source_row = drag_data.get("source_row")
			var source_container_id = ""

			if source_slot and source_slot.has_method("get_container_id"):
				source_container_id = source_slot.get_container_id()
			elif source_row and source_row.has_method("_get_container_id"):
				source_container_id = source_row._get_container_id()

			var our_container_id = container_view.container_id if container_view else container.container_id

			# Process drops to external windows ONLY if drag is from THIS tearoff
			if source_container_id == our_container_id or source_container_id == "tearoff_" + our_container_id:
				var external_windows = get_tree().get_nodes_in_group("external_container_windows")
				for window in external_windows:
					if window != self and is_instance_valid(window):
						var external_window_rect = Rect2(window.global_position, window.size)
						if external_window_rect.has_point(event.global_position):
							get_viewport().set_input_as_handled()

							if window is ContainerTearOffWindow:
								var external_tearoff = window as ContainerTearOffWindow
								var target_container = external_tearoff.container_view if external_tearoff.container_view else external_tearoff.container

								if target_container and target_container.container_id != our_container_id:
									_handle_transfer_to_external_tearoff(drag_data, target_container)
									return
							else:
								# Handle drop to InteractableContainer's window
								if window.has_meta("external_container"):
									var external_container = window.get_meta("external_container")
									if external_container and window.has_meta("interactable_container"):
										var interactable_container = window.get_meta("interactable_container")
										if interactable_container and interactable_container.has_method("_handle_cross_window_drop_to_container"):
											interactable_container._handle_cross_window_drop_to_container(drag_data)
											return

								# Handle main inventory window
								elif window.has_meta("window_type") and window.get_meta("window_type") == "main_inventory":
									var inventory_window = window as InventoryWindow
									if inventory_window and inventory_window.has_method("_handle_cross_window_drop_to_main"):
										var target_container = inventory_window._get_target_container_for_drop(event.global_position)
										if target_container:
											inventory_window._handle_cross_window_drop_to_main(drag_data, target_container)
											return


func _cleanup_failed_drop(drag_data: Dictionary):
	"""Clean up failed drag operations"""
	var source_slot = drag_data.get("source_slot")
	var source_row = drag_data.get("source_row")

	# Notify source that drop failed
	if source_slot and source_slot.has_method("_on_external_drop_result"):
		source_slot._on_external_drop_result(false)
	elif source_row and source_row.has_method("_on_external_drop_result"):
		source_row._on_external_drop_result(false)

	# Clean up global drag state
	var viewport = get_viewport()
	if viewport and viewport.has_meta("current_drag_data"):
		viewport.remove_meta("current_drag_data")

	# Clean up any drag previews
	_cleanup_all_drag_previews()


func _cleanup_all_drag_previews():
	"""Clean up all drag preview elements"""
	var root = get_tree().root
	var drag_canvases = []

	# Find all DragCanvas nodes
	for child in root.get_children():
		if child is CanvasLayer and child.name == "DragCanvas":
			drag_canvases.append(child)

	# Clean them up
	for canvas in drag_canvases:
		if is_instance_valid(canvas):
			canvas.queue_free()


func _handle_transfer_to_external_tearoff(drag_data: Dictionary, target_container: InventoryContainer_Base) -> bool:
	"""Handle transferring item to another external tearoff window"""
	var source_slot = drag_data.get("source_slot")
	var source_row = drag_data.get("source_row")
	var item = drag_data.get("item")

	if not item or not inventory_manager or not target_container:
		return false

	# Check if target can accept the item
	if not target_container.can_add_item(item):
		return false

	# Calculate transfer amount
	var available_volume = target_container.get_available_volume()
	var max_transferable = int(available_volume / item.volume) if item.volume > 0 else item.quantity
	var transfer_amount = min(item.quantity, max_transferable)

	if transfer_amount <= 0:
		return false

	# Get source container ID
	var source_container_id = container_view.container_id if container_view else container.container_id

	# Use the inventory manager to transfer
	var success = inventory_manager.transfer_item(item, source_container_id, target_container.container_id, Vector2i(-1, -1), transfer_amount)

	if success:
		# Refresh both windows
		if content:
			content.refresh_display()

		# Find and refresh the target tearoff window
		var external_windows = get_tree().get_nodes_in_group("external_container_windows")
		for window in external_windows:
			if window is ContainerTearOffWindow:
				var tearoff = window as ContainerTearOffWindow
				if tearoff.container == target_container or (tearoff.container_view and tearoff.container_view.source_container == target_container):
					if tearoff.content:
						tearoff.content.refresh_display()
					break

		# Notify source of successful drop
		if source_slot and source_slot.has_method("_on_external_drop_result"):
			source_slot._on_external_drop_result(true)
		elif source_row and source_row.has_method("_on_external_drop_result"):
			source_row._on_external_drop_result(true)

	return success


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

	var source_slot = drag_data.get("source_slot")
	var source_row = drag_data.get("source_row")
	var item = drag_data.get("item")

	if not item or not inventory_manager:
		return false

	# Get source container ID
	var source_container_id = ""
	if source_slot and source_slot.has_method("get_container_id"):
		source_container_id = source_slot.get_container_id()
	elif source_row and source_row.has_method("_get_container_id"):
		source_container_id = source_row._get_container_id()

	if source_container_id == "":
		return false

	# FIXED: Get target container - use the container_view itself, not its source
	var target_container = container_view if container_view else container

	if not target_container or source_container_id == target_container.container_id:
		return false

	# Check if target can accept the item
	if not target_container.can_add_item(item):
		return false

	# Calculate transfer amount
	var available_volume = target_container.get_available_volume()
	var max_transferable = int(available_volume / item.volume) if item.volume > 0 else item.quantity
	var transfer_amount = min(item.quantity, max_transferable)

	if transfer_amount <= 0:
		return false

	# Use the inventory manager to transfer
	var success = inventory_manager.transfer_item(item, source_container_id, target_container.container_id, Vector2i(-1, -1), transfer_amount)

	if success:
		# Refresh both windows
		if content:
			content.refresh_display()

		# Notify source of successful drop
		if source_slot and source_slot.has_method("_on_external_drop_result"):
			source_slot._on_external_drop_result(true)
		elif source_row and source_row.has_method("_on_external_drop_result"):
			source_row._on_external_drop_result(true)

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
			var viewport = get_viewport()
			if viewport and viewport.has_meta("current_drag_data"):
				var drag_data = viewport.get_meta("current_drag_data")
				if _handle_cross_window_drop(drag_data):
					return


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
	inventory_container.clip_contents = true
	add_content(inventory_container)

	# Create the header (search, filter, sort) - SAME AS MAIN WINDOW
	header = InventoryWindowHeader.new()
	header.name = "InventoryHeader"
	inventory_container.add_child(header)

	# Create main content using InventoryWindowContent - SAME AS MAIN WINDOW
	content = InventoryWindowContent.new()
	content.name = "InventoryContent"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.clip_contents = true
	inventory_container.add_child(content)

	# Wait for content to be ready
	await get_tree().process_frame

	# Setup item actions BEFORE initializing inventory content - SAME AS MAIN WINDOW
	call_deferred("_setup_item_actions")

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

	# REGISTER THE CONTAINER VIEW WITH INVENTORY MANAGER (needed for transactions)
	# but mark it as a view so it can be filtered from main UI lists
	if inventory_manager.has_method("add_container"):
		container_view.set_meta("is_tearoff_view", true)  # Mark as tearoff view
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
	"""Handle container view changes - TEAROFF-SPECIFIC"""
	# Simple refresh when view changes
	if content:
		content.refresh_display()


# ALL THE SAME EVENT HANDLERS AS MAIN WINDOW BUT WORKING WITH VIEW
func _on_search_changed(search_text: String):
	"""Handle search text changes - TEAROFF-SPECIFIC"""
	if not content:
		return

	# Apply to grid view
	if content.inventory_grid and content.inventory_grid.has_method("apply_search"):
		content.inventory_grid.apply_search(search_text)

	# Apply to list view using the same interface
	if content.list_view and content.list_view.has_method("apply_search"):
		content.list_view.apply_search(search_text)


func _on_filter_changed(filter_type: int):
	"""Handle filter changes - TEAROFF-SPECIFIC"""
	if not content:
		return

	# Apply to grid view
	if content.inventory_grid and content.inventory_grid.has_method("apply_filter"):
		content.inventory_grid.apply_filter(filter_type)

	# Apply to list view using the same interface
	if content.list_view and content.list_view.has_method("apply_filter"):
		content.list_view.apply_filter(filter_type)


func _on_sort_requested(sort_type: InventorySortType.Type):
	"""Handle sort requests - TEAROFF-SPECIFIC"""
	if not inventory_manager or not container_view:
		return

	# Sort the source container (same as main window)
	inventory_manager.sort_container(container_view.source_container.container_id, sort_type)

	# Force the ContainerView to refresh from the sorted source
	container_view.force_refresh()

	# Force refresh of the visible display after sort
	await get_tree().process_frame  # Wait for sort to complete

	if content:
		if content.inventory_grid and content.inventory_grid.visible:
			content.inventory_grid.refresh_display()
		if content.list_view and content.list_view.visible:
			content.list_view.refresh_display()


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
		# Just close this window since there's nowhere to reattach to
		hide_window()
		queue_free()
		return

	window_reattached.emit(container)  # Emit original container, not view
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

		# Remove the view from inventory manager
		if inventory_manager and inventory_manager.has_method("remove_container"):
			inventory_manager.remove_container(container_view.container_id)

		container_view = null

	if item_actions:
		item_actions.close_all_dialogs()
		item_actions.cleanup()

	# CRITICAL FIX: Only emit inventory_closed if ALL UI windows are closing
	# AND the main inventory is also gone
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	if ui_managers.size() > 0:
		var ui_manager = ui_managers[0]
		if ui_manager.has_method("get_all_windows"):
			var remaining_windows = ui_manager.get_all_windows()
			# Filter out this window since it's closing
			var other_windows = remaining_windows.filter(func(w): return w != self and is_instance_valid(w))

			# Check if main inventory is still open
			var has_main_inventory = other_windows.any(func(w): return w.get_meta("window_type", "") == "main_inventory")

			# Only restore input if NO windows are left at all
			if other_windows.size() == 0:
				var integration = _find_inventory_integration(get_tree().current_scene)
				if integration:
					integration._set_player_input_enabled(true)
					integration.inventory_toggled.emit(false)
					if integration.event_bus:
						integration.event_bus.emit_inventory_closed()
				else:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Only try to reattach if parent window still existsi
	if parent_window and is_instance_valid(parent_window):
		# Emit reattach signal when window is closed (use original container)
		reattach_to_parent()
	else:
		# Parent window is gone, just clean up
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
		call_deferred("_setup_item_actions")

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

	# CRITICAL: Ensure we're properly registered with UIManager
	_ensure_ui_manager_registration()

	# Then focus the window
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

		# Check if we're already registered
		var all_windows = ui_manager.get_all_windows()
		var is_already_registered = self in all_windows

		if not is_already_registered:
			# Ensure metadata is set
			if not has_meta("window_type"):
				set_meta("window_type", "tearoff")

			if ui_manager.has_method("register_window"):
				ui_manager.register_window(self, "tearoff")

				# Verify registration worked
				await get_tree().process_frame
				all_windows = ui_manager.get_all_windows()
				is_already_registered = self in all_windows
