# InventoryWindow.gd - Inventory-specific window implementation
class_name InventoryWindow
extends Window_Base

# Inventory-specific signals
signal container_switched(container: InventoryContainer_Base)

# Inventory-specific properties
var inventory_manager: InventoryManager
var inventory_container: VBoxContainer
var header: InventoryWindowHeader
var content: InventoryWindowContent
var item_actions: InventoryItemActions
var tearoff_manager: ContainerTearOffManager

# Inventory-specific state
var open_containers: Array[InventoryContainer_Base] = []
var current_container: InventoryContainer_Base


func _init():
	super._init()

	# Set inventory-specific defaults
	window_title = "Inventory"
	default_size = Vector2(800, 600)
	min_window_size = Vector2(400, 300)
	max_window_size = Vector2(1400, 1000)

	set_process_input(true)


func _input(event: InputEvent):
	"""Handle cross-window drops to main inventory window"""
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var window_rect = Rect2(global_position, size)

		# Only handle drops that happen WITHIN our window bounds
		if window_rect.has_point(event.global_position):
			var viewport = get_viewport()
			if viewport and viewport.has_meta("current_drag_data"):
				var drag_data = viewport.get_meta("current_drag_data")
				var source_slot = drag_data.get("source_slot")
				var source_row = drag_data.get("source_row")

				# Check if drag is from an external source (tearoff window) - HANDLE BOTH SLOT AND ROW
				var source_container_id = ""
				if source_slot and source_slot.has_method("get_container_id"):
					source_container_id = source_slot.get_container_id()
				elif source_row and source_row.has_method("_get_container_id"):
					source_container_id = source_row._get_container_id()

				if source_container_id != "":
					# Check if this is from a tearoff container (starts with "tearoff_")
					if source_container_id.begins_with("tearoff_"):
						# Extract the original container ID
						var original_container_id = source_container_id.replace("tearoff_", "")

						# Find which of our containers should receive this
						var target_container = _get_target_container_for_drop(event.global_position)
						if target_container and target_container.container_id != original_container_id:
							if _handle_cross_window_drop_to_main(drag_data, target_container):
								get_viewport().set_input_as_handled()
								return
		else:
			# Handle drops OUTSIDE our window (to external container windows)
			var viewport = get_viewport()
			if viewport and viewport.has_meta("current_drag_data"):
				var drag_data = viewport.get_meta("current_drag_data")

				# Check for drops to external container windows
				var external_windows = get_tree().get_nodes_in_group("external_container_windows")
				for window in external_windows:
					if window != self and is_instance_valid(window):
						var external_window_rect = Rect2(window.global_position, window.size)
						if external_window_rect.has_point(event.global_position):
							# This drop is targeting an external container window
							var external_container = window.get_meta("external_container", null)
							if external_container:
								var interactable_container = window.get_meta("interactable_container", null)
								if interactable_container and interactable_container.has_method("_handle_cross_window_drop_to_container"):
									if interactable_container._handle_cross_window_drop_to_container(drag_data):
										get_viewport().set_input_as_handled()
										return


func _setup_window_content():
	"""Override base method to add inventory-specific content"""
	# Call the original content setup method
	_setup_content()


func _setup_content():
	"""Setup inventory-specific content"""
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Create main inventory container
	inventory_container = VBoxContainer.new()
	inventory_container.name = "InventoryContainer"
	inventory_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_content(inventory_container)

	# Create the header (search, filter, sort)
	header = InventoryWindowHeader.new()
	header.name = "InventoryHeader"
	inventory_container.add_child(header)

	# Create main content using InventoryWindowContent
	content = InventoryWindowContent.new()
	content.name = "InventoryContent"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_container.add_child(content)

	# Wait for content to be ready
	await get_tree().process_frame

	# FIXED: Setup item actions BEFORE initializing inventory content
	call_deferred("_setup_item_actions")

	# Connect header signals AFTER both header and content are created
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

		# Connect window resize to trigger grid reflow
		window_resized.connect(_on_window_resized_for_grid)

	# Initialize content with inventory manager if available
	if inventory_manager:
		_initialize_inventory_content()

	# Setup tearoff functionality
	if not tearoff_manager:
		tearoff_manager = ContainerTearOffManager.new(self)
		tearoff_manager.setup_tearoff_functionality()

	call_deferred("setup_child_focus_handlers")


func _on_empty_area_context_menu_from_content(_global_position: Vector2):
	"""Handle empty area context menu from content"""
	if item_actions and item_actions.has_method("show_empty_area_context_menu"):
		item_actions.show_empty_area_context_menu(global_position)


func _on_window_resized_for_inventory(_new_size: Vector2i):
	"""Handle window resize for inventory components"""
	if content:
		# Trigger content resize handling
		call_deferred("_handle_content_resize")


func _handle_content_resize():
	if not content:
		return

	# Let the content handle its own resize
	if content.has_method("_handle_display_resize"):
		content._handle_display_resize()


func _on_display_mode_changed(mode: InventoryDisplayMode.Mode):
	if content and content.has_method("set_display_mode"):
		content.set_display_mode(mode)


func _on_container_list_item_selected(index: int):
	"""Handle container list selection"""
	if index >= 0 and index < open_containers.size():
		var selected_container = open_containers[index]
		# Update current container
		current_container = selected_container

		# Set container on content
		if content and content.has_method("select_container"):
			content.select_container(selected_container)

		# Update item actions
		if item_actions and item_actions.has_method("set_current_container"):
			item_actions.set_current_container(selected_container)

		# Emit signal
		container_switched.emit(selected_container)


func _setup_inventory_content():
	"""Initialize inventory-specific UI components"""
	# Create main inventory container
	inventory_container = VBoxContainer.new()
	inventory_container.name = "InventoryContainer"
	inventory_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_content(inventory_container)

	# Create header
	header = InventoryWindowHeader.new()
	header.name = "InventoryHeader"
	inventory_container.add_child(header)

	# Create content
	content = InventoryWindowContent.new()
	content.name = "InventoryContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_container.add_child(content)

	# Connect signals
	if header:
		if header.has_signal("container_selected"):
			header.container_selected.connect(_on_container_selected_from_header)
		if header.has_signal("search_text_changed"):
			header.search_text_changed.connect(_on_search_text_changed_from_header)

	if content:
		if content.has_signal("container_selected"):
			content.container_selected.connect(_on_container_selected_from_content)
		if content.has_signal("item_activated"):
			content.item_activated.connect(_on_item_activated_from_content)
		if content.has_signal("item_context_menu"):
			content.item_context_menu.connect(_on_item_context_menu_from_content)

		# Connect window resize to trigger grid reflow
		window_resized.connect(_on_window_resized_for_grid)

	# Initialize content with inventory manager if available
	if inventory_manager:
		_initialize_inventory_content()

	_setup_item_actions()


func _setup_options_dropdown():
	"""Setup the options dropdown for inventory-specific actions"""
	options_dropdown = DropDownMenu_Base.new()
	options_dropdown.name = "OptionsDropdown"

	# Add inventory-specific options
	_update_options_dropdown_text()

	# Connect dropdown signals
	if options_dropdown.has_signal("item_selected"):
		options_dropdown.item_selected.connect(_on_options_dropdown_selected)
	if options_dropdown.has_signal("menu_closed"):
		options_dropdown.menu_closed.connect(_on_options_dropdown_closed)


func _setup_item_actions():
	"""Initialize the item actions handler for context menus"""
	var scene_window = get_viewport()
	if scene_window is Window:
		item_actions = InventoryItemActions.new(scene_window)
	else:
		var parent_window = _find_parent_window()
		if parent_window:
			item_actions = InventoryItemActions.new(parent_window)
		else:
			push_error("Could not find parent window for InventoryItemActions")
			return

	# Set the inventory manager on item_actions
	if inventory_manager:
		item_actions.set_inventory_manager(inventory_manager)

	# Connect to inventory manager updates
	if item_actions.has_signal("container_refreshed"):
		item_actions.container_refreshed.connect(_on_container_refreshed)
	if content and content.has_method("set_item_actions"):
		content.set_item_actions(item_actions)


func _find_parent_window() -> Window:
	"""Find the parent window in the scene tree"""
	var current = get_parent()
	while current:
		if current is Window:
			return current
		current = current.get_parent()
	return null


func _initialize_inventory_content():
	"""Initialize the inventory content with the inventory manager"""

	if not content or not inventory_manager:
		return

	# Set inventory manager on content
	if content.has_method("set_inventory_manager"):
		content.set_inventory_manager(inventory_manager)

	# Get all accessible containers, not just player inventory
	var all_containers = inventory_manager.get_accessible_containers()

	if all_containers.size() > 0:
		open_containers.clear()
		open_containers.append_array(all_containers)

		# Set player inventory as default if available, otherwise use first container
		var default_container = null
		for container in all_containers:
			if container.container_id == "player_inventory":
				default_container = container
				break

		if not default_container:
			default_container = all_containers[0]

		# IMPORTANT: Set the current container first
		current_container = default_container

		# FIXED: Set current container on item_actions too
		if item_actions and item_actions.has_method("set_current_container"):
			item_actions.set_current_container(current_container)

		# Update containers list in content with ALL containers
		if content.has_method("update_containers"):
			content.update_containers(all_containers)

		# Then select it in the content
		if content.has_method("select_container"):
			content.select_container(default_container)


func _update_options_dropdown_text():
	"""Update options dropdown with inventory-specific options"""
	if not options_dropdown:
		return

	var options = ["Sort by Name", "Sort by Type", "Sort by Quantity", "---", "Auto-Stack Items", "Show Item Details", "---", "Export Inventory", "Import Inventory"]

	if options_dropdown.has_method("set_items"):
		options_dropdown.set_items(options)


# Signal handlers for inventory-specific events
func _on_container_selected_from_header(container: InventoryContainer_Base):
	_switch_container(container)


func _on_container_selected_from_content(container: InventoryContainer_Base):
	"""Handle container selection from content"""
	current_container = container

	# FIXED: Set current container on item_actions
	if item_actions and item_actions.has_method("set_current_container"):
		item_actions.set_current_container(container)

	container_switched.emit(container)


func _get_target_container_for_drop(drop_position: Vector2) -> InventoryContainer_Base:
	"""Determine which container should receive the drop based on position - only valid drop areas"""
	if not content:
		return null

	# Check if dropping on container list area
	if content.container_list:
		var list_rect = Rect2(content.container_list.global_position, content.container_list.size)
		if list_rect.has_point(drop_position):
			# Get the container under the mouse
			var local_pos = drop_position - content.container_list.global_position
			var item_index = content.container_list.get_item_at_position(local_pos, true)
			if item_index >= 0 and item_index < content.open_containers.size():
				return content.open_containers[item_index]
			# If clicking container list but not on a specific container, reject
			return null

	# Check if dropping on the inventory grid/list view area
	if content.inventory_grid and content.inventory_grid.visible:
		var grid_rect = Rect2(content.inventory_grid.global_position, content.inventory_grid.size)
		if grid_rect.has_point(drop_position):
			return content.current_container

	if content.list_view and content.list_view.visible:
		var list_view_rect = Rect2(content.list_view.global_position, content.list_view.size)
		if list_view_rect.has_point(drop_position):
			return content.current_container

	# If not over any valid drop area, reject the drop
	return null


func _handle_cross_window_drop_to_main(drag_data: Dictionary, target_container: InventoryContainer_Base) -> bool:
	"""Handle drop from tearoff window to main inventory"""
	var source_slot = drag_data.get("source_slot")
	var source_row = drag_data.get("source_row")
	var item = drag_data.get("item")

	if not item or not inventory_manager or not target_container:
		return false

	# Get source container ID from either slot or row
	var source_container_id = ""
	if source_slot and source_slot.has_method("get_container_id"):
		source_container_id = source_slot.get_container_id()
	elif source_row and source_row.has_method("_get_container_id"):
		source_container_id = source_row._get_container_id()

	if source_container_id == "" or source_container_id == target_container.container_id:
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

	# Use the existing transaction manager
	var success = inventory_manager.transfer_item(item, source_container_id, target_container.container_id, Vector2i(-1, -1), transfer_amount)

	if success:
		# Refresh main window display
		content.refresh_display()

		# Notify source of successful drop
		if source_slot and source_slot.has_method("_on_external_drop_result"):
			source_slot._on_external_drop_result(true)
		elif source_row and source_row.has_method("_on_external_drop_result"):
			source_row._on_external_drop_result(true)

	return success


func _on_search_text_changed_from_header(search_text: String):
	if content and content.has_method("filter_items"):
		content.filter_items(search_text)


func _on_item_activated_from_content(item: InventoryItem_Base, slot: InventorySlot):
	if item_actions and item_actions.has_method("handle_item_activation"):
		item_actions.handle_item_activation(item, slot)


func _on_item_context_menu_from_content(item: InventoryItem_Base, slot: InventorySlot, _global_position: Vector2):
	if item_actions and item_actions.has_method("show_item_context_menu"):
		item_actions.show_item_context_menu(item, slot, global_position)


func _on_window_resized_for_grid(_new_size: Vector2i):
	"""Handle window resize for inventory grid"""
	if content and content.inventory_grid and content.inventory_grid.has_method("handle_window_resize"):
		content.inventory_grid.handle_window_resize()


func _on_options_dropdown_selected(_index: int):
	"""Handle options dropdown selection"""
	# Implement inventory-specific option handling


func _on_options_dropdown_closed():
	"""Handle options dropdown close"""


func _on_container_refreshed():
	"""Handle container refresh from item actions"""
	if content and content.has_method("refresh_display"):
		content.refresh_display()


func _switch_container(container: InventoryContainer_Base):
	"""Switch to a different inventory container"""
	current_container = container

	# FIXED: Update current container on item_actions
	if item_actions and item_actions.has_method("set_current_container"):
		item_actions.set_current_container(container)

	container_switched.emit(container)

	if content and content.has_method("display_container"):
		content.display_container(container)


# Override base class close behavior
func _on_window_closed():
	"""Handle main inventory window being closed"""

	# Check if there are tearoff windows that should remain open
	var should_restore_input = true
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	if ui_managers.size() > 0:
		var ui_manager = ui_managers[0]
		if ui_manager.has_method("get_all_windows"):
			var remaining_windows = ui_manager.get_all_windows()
			# Filter out this main inventory window since it's closing
			var other_windows = remaining_windows.filter(func(w): return w != self and is_instance_valid(w))

			# Check if there are tearoff windows remaining
			var tearoff_windows = other_windows.filter(func(w): return w.get_meta("window_type", "") == "tearoff")

			if tearoff_windows.size() > 0:
				should_restore_input = false

	# Find the inventory integration and close properly
	var integration = _find_inventory_integration(get_tree().current_scene)
	if integration:
		# ALWAYS set inventory as closed when main window closes
		integration.is_inventory_open = false

		# Handle input restoration based on tearoff windows
		if should_restore_input:
			integration._set_player_input_enabled(true)
			integration.inventory_toggled.emit(false)
			if integration.event_bus:
				integration.event_bus.emit_inventory_closed()

		# Save position
		integration._save_window_position()
	else:
		# Fallback if integration not found
		if should_restore_input:
			_reenable_player_input_fallback()


func _save_inventory_state():
	"""Save inventory-specific state"""
	# Implement inventory state saving if needed


# Public interface methods for inventory management
func set_inventory_manager(manager: InventoryManager):
	inventory_manager = manager

	# Set up item actions now that we have inventory manager
	if not item_actions:
		_setup_item_actions()

	# Also set/update it on item_actions if it exists
	if item_actions and item_actions.has_method("set_inventory_manager"):
		item_actions.set_inventory_manager(inventory_manager)

	# Initialize content with inventory manager
	if manager:
		_initialize_inventory_content()


func get_current_container() -> InventoryContainer_Base:
	return current_container


func get_tearoff_manager() -> ContainerTearOffManager:
	return tearoff_manager


func show_window():
	"""Show inventory window with grid layout fix"""
	super.show_window()
	move_to_front()
	_fix_initial_grid_layout()


# Lock visual implementation
func _update_lock_visual():
	"""Update lock indicator visibility"""
	if not lock_indicator:
		_setup_lock_indicator()

	if is_locked:
		lock_indicator.visible = true
		# Position it to the left of the options button
		if options_button:
			var options_x = options_button.position.x
			lock_indicator.position = Vector2(options_x - 28, (title_bar_height - 24) / 2)
	else:
		lock_indicator.visible = false


func _setup_lock_indicator():
	"""Create lock indicator icon"""
	if lock_indicator:
		return

	lock_indicator = Label.new()
	lock_indicator.name = "LockIndicator"
	lock_indicator.text = "🔒"
	lock_indicator.add_theme_font_size_override("font_size", 16)
	lock_indicator.add_theme_color_override("font_color", Color.YELLOW)
	lock_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock_indicator.size = Vector2(24, 24)
	lock_indicator.visible = false
	title_bar.add_child(lock_indicator)


# Options dropdown methods
func _show_transparency_dialog():
	"""Show transparency adjustment dialog"""
	var dialog = AcceptDialog.new()
	dialog.title = "Window Transparency"
	dialog.size = Vector2i(300, 150)

	var vbox = VBoxContainer.new()
	var label = Label.new()
	label.text = "Adjust window transparency:"
	vbox.add_child(label)

	var slider = HSlider.new()
	slider.min_value = 0.3
	slider.max_value = 1.0
	slider.step = 0.1
	slider.value = modulate.a
	slider.custom_minimum_size.x = 250
	vbox.add_child(slider)

	dialog.add_child(vbox)
	slider.value_changed.connect(func(value): modulate.a = value)

	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())


func _toggle_window_lock():
	"""Toggle window lock state"""
	set_window_locked(!is_locked)
	_update_options_dropdown_text()


# Grid layout fix
func _fix_initial_grid_layout():
	"""Fix the initial grid layout after window is shown"""
	await get_tree().process_frame

	if content and content.inventory_grid and content.current_container:
		content.inventory_grid._initialize_with_proper_size()


# Inventory-specific helpers
func get_inventory_grid():
	"""Get reference to the inventory grid"""
	if content and content.has_method("get_inventory_grid"):
		return content.get_inventory_grid()
	return null


func update_mass_info():
	"""Update the mass info bar - delegate to content"""
	if content and content.has_method("update_mass_info"):
		content.update_mass_info()


# Helper methods for player input management
func _find_inventory_integration(node: Node) -> InventoryIntegration:
	if node is InventoryIntegration:
		return node

	for child in node.get_children():
		var result = _find_inventory_integration(child)
		if result:
			return result
	return null


func _reenable_player_input_fallback():
	"""Fallback method to re-enable player input"""
	var scene_root = get_tree().current_scene
	var player_node = _find_node_by_name_recursive(scene_root, "Player")

	if player_node:
		player_node.process_mode = Node.PROCESS_MODE_INHERIT

	var input_managers = get_tree().get_nodes_in_group("input_managers")
	for input_manager in input_managers:
		input_manager.process_mode = Node.PROCESS_MODE_INHERIT

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _find_node_by_name_recursive(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node

	for child in node.get_children():
		var result = _find_node_by_name_recursive(child, target_name)
		if result:
			return result
	return null


# Header signal handlers
func _on_search_changed(text: String):
	"""Handle search text changes from header"""
	if not content:
		return

	# Apply to grid view
	var grid = get_inventory_grid()
	if grid and grid.has_method("apply_search"):
		grid.apply_search(text)

	# Apply to list view using the same interface
	if content.list_view and content.list_view.has_method("apply_search"):
		content.list_view.apply_search(text)


func _on_filter_changed(filter_type: int):
	"""Handle filter changes from header"""
	if not content:
		return

	# Apply to grid view
	var grid = get_inventory_grid()
	if grid and grid.has_method("apply_filter"):
		grid.apply_filter(filter_type)

	# Apply to list view using the same interface
	if content.list_view and content.list_view.has_method("apply_filter"):
		content.list_view.apply_filter(filter_type)


func _on_sort_requested(sort_type: InventorySortType.Type):
	"""Handle sort requests from header"""

	if not inventory_manager:
		return

	if not current_container:
		return

	# Use the enum directly now
	inventory_manager.sort_container(current_container.container_id, sort_type)

	# Force grid refresh after sort
	if content and content.inventory_grid:
		await get_tree().process_frame  # Wait for sort to complete
		content.inventory_grid.refresh_display()
