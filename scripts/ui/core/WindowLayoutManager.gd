extends Node

# Comprehensive window layout manager - handles all UI/window positioning, state, saving/loading

# Signals
signal layout_saved
signal layout_loaded
signal layout_cleared

# Configuration
var config_file_path: String = "user://window_layout.cfg"
var auto_save_enabled: bool = true
var auto_load_enabled: bool = true

# Manager references
var inventory_manager: InventoryManager
var ui_manager: UIManager

# State tracking
var is_saving_layout: bool = false
var is_loading_layout: bool = false

# Real-time tracking
var drag_save_windows: Array[Window_Base] = []
var closed_tearoff_containers: Array[String] = []

var inventory_window_state: Dictionary = {"is_open": false, "position": Vector2.ZERO, "size": Vector2.ZERO, "was_open_on_exit": false}


func _ready():
	add_to_group("window_layout_manager")

	# Wait for other systems to initialize
	await get_tree().process_frame
	await get_tree().process_frame

	# Find required managers
	_find_managers()

	# Auto-load layout if enabled
	if auto_load_enabled:
		call_deferred("_auto_load_layout")


func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if auto_save_enabled:
			_auto_save_layout()
		get_tree().quit()


# ==============================================================================
# MANAGER DISCOVERY
# ==============================================================================


func _find_managers():
	"""Find the required managers in the scene"""

	# Find UI Manager
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	if ui_managers.size() > 0:
		ui_manager = ui_managers[0]
		_connect_ui_manager_signals()

	# Find Inventory Manager
	var inventory_managers = get_tree().get_nodes_in_group("inventory_manager")
	if inventory_managers.size() > 0:
		inventory_manager = inventory_managers[0]
	else:
		# Alternative: search recursively
		inventory_manager = _find_inventory_manager_recursive(get_tree().current_scene)


func _find_inventory_manager_recursive(node: Node) -> InventoryManager:
	"""Recursively find InventoryManager"""
	if node is InventoryManager:
		return node

	for child in node.get_children():
		var result = _find_inventory_manager_recursive(child)
		if result:
			return result

	return null


func _connect_ui_manager_signals():
	"""Connect to UI manager signals for real-time saving"""
	if ui_manager.has_signal("window_focused"):
		ui_manager.window_focused.connect(_on_window_changed)
	if ui_manager.has_signal("window_closed"):
		ui_manager.window_closed.connect(_on_window_changed)


# ==============================================================================
# REAL-TIME WINDOW MONITORING
# ==============================================================================


func _on_window_changed(_window: Window_Base = null):
	"""Called when any window changes - save immediately"""
	if auto_save_enabled and not is_saving_layout:
		save_complete_layout()


func connect_window_signals(window: Window_Base):
	"""Connect to window movement/resize signals for immediate auto-saving"""
	if not window:
		return

	var window_type = window.get_meta("window_type", "")

	# Connect to window resize
	if window.has_signal("window_resized"):
		if not window.window_resized.is_connected(_on_immediate_window_change):
			window.window_resized.connect(func(_size): _on_immediate_window_change(window, "resize"))

	# Connect to window close for tearoff windows
	if window_type == "tearoff":
		if window.has_signal("window_closed"):
			if not window.window_closed.is_connected(_on_tearoff_window_closed):
				window.window_closed.connect(_on_tearoff_window_closed.bind(window))

	# For inventory window, also monitor open/close state
	if window_type == "main_inventory" or window_type == "inventory":
		_connect_inventory_specific_signals(window)

	# Monitor position changes in real-time
	_start_realtime_position_monitoring(window)

	# Monitor drag events
	connect_window_drag_signals(window)


func _connect_inventory_specific_signals(window: Window_Base):
	"""Connect inventory-specific signals"""

	# Monitor visibility changes
	if window.has_signal("visibility_changed"):
		if not window.visibility_changed.is_connected(_on_inventory_visibility_changed):
			window.visibility_changed.connect(_on_inventory_visibility_changed.bind(window))

	# Monitor window close
	if window.has_signal("window_closed"):
		if not window.window_closed.is_connected(_on_inventory_window_closed):
			window.window_closed.connect(_on_inventory_window_closed.bind(window))


func _on_immediate_window_change(_window: Window_Base, _change_type: String):
	"""Handle immediate window changes"""
	if auto_save_enabled and not is_saving_layout:
		save_complete_layout()


func _start_realtime_position_monitoring(window: Window_Base):
	"""Start real-time position monitoring for a window"""
	if not window:
		return

	# Store initial position
	window.set_meta("last_saved_position", window.position)

	# Create a high-frequency timer for position checking
	var position_timer = Timer.new()
	position_timer.wait_time = 0.1  # Check every 100ms
	position_timer.autostart = true
	position_timer.timeout.connect(_check_window_position_realtime.bind(window, position_timer))
	window.add_child(position_timer)


func _check_window_position_realtime(window: Window_Base, timer: Timer):
	"""Check window position in real-time and save if changed"""
	if not is_instance_valid(window):
		timer.queue_free()
		return

	var last_position = window.get_meta("last_saved_position", Vector2.ZERO)
	if window.position != last_position:
		window.set_meta("last_saved_position", window.position)
		_on_immediate_window_change(window, "move")


func connect_window_drag_signals(window: Window_Base):
	"""Connect to window drag events for ultra-responsive saving"""
	if not window:
		return

	# Connect to mouse events to detect dragging
	if not window.gui_input.is_connected(_on_window_input):
		window.gui_input.connect(_on_window_input.bind(window))


func _on_window_input(event: InputEvent, window: Window_Base):
	"""Handle window input for drag detection"""
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# Start drag tracking
				if window not in drag_save_windows:
					drag_save_windows.append(window)
			else:
				# End drag - save position
				if window in drag_save_windows:
					drag_save_windows.erase(window)
					_on_immediate_window_change(window, "drag_end")


func disconnect_window_signals(window: Window_Base):
	"""Disconnect window signals when window is destroyed"""
	if not window:
		return

	# Remove from drag tracking
	if window in drag_save_windows:
		drag_save_windows.erase(window)

	# Since we're using lambdas, disconnect all our connections
	if window.has_signal("window_resized"):
		for connection in window.window_resized.get_connections():
			if connection.callable.get_object() == self:
				window.window_resized.disconnect(connection.callable)

	if window.has_signal("gui_input"):
		for connection in window.gui_input.get_connections():
			if connection.callable.get_object() == self:
				window.gui_input.disconnect(connection.callable)


# ==============================================================================
# MAIN WINDOW MANAGEMENT
# ==============================================================================


func save_main_window_position():
	"""Save main window position and properties"""
	var config = ConfigFile.new()
	_load_existing_config(config)

	var window_pos = DisplayServer.window_get_position()
	var window_size = DisplayServer.window_get_size()
	var window_mode = DisplayServer.window_get_mode()

	config.set_value("main_window", "position_x", window_pos.x)
	config.set_value("main_window", "position_y", window_pos.y)
	config.set_value("main_window", "size_x", window_size.x)
	config.set_value("main_window", "size_y", window_size.y)
	config.set_value("main_window", "mode", window_mode)

	var error = config.save(config_file_path)
	if error != OK:
		return false

	return true


func load_main_window_position():
	"""Load and apply saved main window position"""
	var config = ConfigFile.new()
	var error = config.load(config_file_path)

	if error != OK:
		return false

	var pos_x = config.get_value("main_window", "position_x", -1)
	var pos_y = config.get_value("main_window", "position_y", -1)
	var size_x = config.get_value("main_window", "size_x", -1)
	var size_y = config.get_value("main_window", "size_y", -1)
	var mode = config.get_value("main_window", "mode", DisplayServer.WINDOW_MODE_WINDOWED)

	# Apply window mode first
	if mode != DisplayServer.window_get_mode():
		DisplayServer.window_set_mode(mode)

	# Apply position if valid
	if pos_x >= 0 and pos_y >= 0 and _is_position_valid(Vector2i(pos_x, pos_y)):
		DisplayServer.window_set_position(Vector2i(pos_x, pos_y))

	# Apply size if valid
	if size_x > 0 and size_y > 0:
		DisplayServer.window_set_size(Vector2i(size_x, size_y))

	return true


# ==============================================================================
# INVENTORY WINDOW MANAGEMENT
# ==============================================================================


# Update save_inventory_window_state() to be more comprehensive:
func save_inventory_window_state():
	"""Save main inventory window state"""
	# Don't save inventory state while we're loading layout
	if is_loading_layout:
		return true

	var config = ConfigFile.new()
	_load_existing_config(config)

	# Find the main inventory window
	var inventory_window = _find_main_inventory_window()
	var is_open = inventory_window != null and inventory_window.visible

	config.set_value("inventory_window", "is_open", is_open)
	config.set_value("inventory_window", "was_open_on_exit", is_open)

	if inventory_window and is_open:
		# Basic properties
		config.set_value("inventory_window", "position_x", inventory_window.position.x)
		config.set_value("inventory_window", "position_y", inventory_window.position.y)
		config.set_value("inventory_window", "size_x", inventory_window.size.x)
		config.set_value("inventory_window", "size_y", inventory_window.size.y)
		config.set_value("inventory_window", "modulate_a", inventory_window.modulate.a)

		# Check for additional properties and save them
		if "is_locked" in inventory_window:
			config.set_value("inventory_window", "is_locked", inventory_window.is_locked)

		if "is_maximized" in inventory_window:
			config.set_value("inventory_window", "is_maximized", inventory_window.is_maximized)

		# Save additional window properties if available
		if inventory_window.has_method("get_save_data"):
			var save_data = inventory_window.get_save_data()
			if not save_data.is_empty():
				config.set_value("inventory_window", "window_data", save_data)

		# Save container selection state if available
		if inventory_window.has_method("get_current_container"):
			var current_container = inventory_window.get_current_container()
			if current_container:
				config.set_value("inventory_window", "selected_container_id", current_container.container_id)

		# Save window view state if available
		if inventory_window.has_method("get_view_state"):
			var view_state = inventory_window.get_view_state()
			if not view_state.is_empty():
				config.set_value("inventory_window", "view_state", view_state)

		# Save any filter/search state
		if inventory_window.has_method("get_filter_state"):
			var filter_state = inventory_window.get_filter_state()
			if not filter_state.is_empty():
				config.set_value("inventory_window", "filter_state", filter_state)

	var error = config.save(config_file_path)
	if error != OK:
		return false

	# Verify what was actually saved
	var verify_config = ConfigFile.new()
	if verify_config.load(config_file_path) == OK:
		if verify_config.has_section("inventory_window"):
			var keys = verify_config.get_section_keys("inventory_window")

	return true


func load_inventory_window_state():
	"""Load and apply saved inventory window state"""

	var config = ConfigFile.new()
	var error = config.load(config_file_path)

	if error != OK:
		return false

	if not config.has_section("inventory_window"):
		return false

	var was_open = config.get_value("inventory_window", "was_open_on_exit", false)

	if was_open:
		# Get saved properties
		var pos_x = config.get_value("inventory_window", "position_x", 200)
		var pos_y = config.get_value("inventory_window", "position_y", 100)
		var size_x = config.get_value("inventory_window", "size_x", 800)
		var size_y = config.get_value("inventory_window", "size_y", 600)
		var modulate_a = config.get_value("inventory_window", "modulate_a", 1.0)
		var is_locked = config.get_value("inventory_window", "is_locked", false)
		var is_maximized = config.get_value("inventory_window", "is_maximized", false)
		var selected_container_id = config.get_value("inventory_window", "selected_container_id", "")

		# Store the state to apply when inventory opens
		inventory_window_state = {
			"is_open": true,
			"position": Vector2(pos_x, pos_y),
			"size": Vector2(size_x, size_y),
			"modulate_a": modulate_a,
			"is_locked": is_locked,
			"is_maximized": is_maximized,
			"selected_container_id": selected_container_id,
			"was_open_on_exit": was_open
		}

		# Try to open the inventory if we can find the integration
		await _restore_inventory_open_state()

		return true

	inventory_window_state["was_open_on_exit"] = false

	return false


func _restore_inventory_open_state():
	"""Try to open the inventory and restore its state"""

	# Find inventory integration to open the inventory
	var integration = _find_inventory_integration()

	if integration:
		# Try different methods to open the inventory
		if integration.has_method("open_inventory"):
			integration.open_inventory()
		elif integration.has_method("toggle_inventory"):
			integration.toggle_inventory()
		elif integration.has_method("show_inventory"):
			integration.show_inventory()
		else:
			return

		# Wait multiple frames for the inventory to open
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame

		# Check if inventory is now open
		var inventory_window = _find_main_inventory_window()
		if inventory_window:
			_apply_inventory_window_state()


func _apply_inventory_window_state():
	"""Apply saved state to the inventory window"""
	var inventory_window = _find_main_inventory_window()
	if not inventory_window:
		return

	# Apply position and size
	if _is_position_valid(Vector2i(inventory_window_state.position)):
		inventory_window.position = inventory_window_state.position

	inventory_window.size = inventory_window_state.size

	inventory_window.modulate.a = inventory_window_state.get("modulate_a", 1.0)

	# Apply lock state
	if inventory_window_state.get("is_locked", false) and inventory_window.has_method("set_window_locked"):
		inventory_window.set_window_locked(true)

	# Apply maximized state
	if inventory_window_state.get("is_maximized", false) and inventory_window.has_method("_maximize_window"):
		inventory_window._maximize_window()

	# Apply additional saved data
	if inventory_window_state.has("window_data") and inventory_window.has_method("load_save_data"):
		inventory_window.load_save_data(inventory_window_state["window_data"])

	if inventory_window_state.has("view_state") and inventory_window.has_method("restore_view_state"):
		inventory_window.restore_view_state(inventory_window_state["view_state"])

	if inventory_window_state.has("filter_state") and inventory_window.has_method("restore_filter_state"):
		inventory_window.restore_filter_state(inventory_window_state["filter_state"])

	# Restore selected container if available
	if inventory_window_state.has("selected_container_id") and inventory_window.has_method("select_container_by_id"):
		inventory_window.select_container_by_id(inventory_window_state["selected_container_id"])


func _find_inventory_integration():
	"""Find the inventory integration in the scene"""

	# Search for inventory integration
	var integrations = get_tree().get_nodes_in_group("inventory_integration")

	if integrations.size() > 0:
		return integrations[0]

	# Alternative: search by class name or script
	var result = _find_node_recursive(get_tree().current_scene, "InventoryIntegration")

	return result


func _find_node_recursive(node: Node, target_class_name: String) -> Node:
	"""Recursively find a node by class name"""
	if node.get_class() == target_class_name or (node.get_script() and node.get_script().get_global_name() == target_class_name):
		return node

	for child in node.get_children():
		var result = _find_node_recursive(child, target_class_name)
		if result:
			return result

	return null


func _on_inventory_visibility_changed(window: Window_Base):
	"""Handle inventory window visibility changes"""
	inventory_window_state["is_open"] = window.visible

	if auto_save_enabled and not is_saving_layout:
		save_complete_layout()


func _on_inventory_window_closed(_window: Window_Base):
	"""Handle inventory window being closed"""
	inventory_window_state["is_open"] = false

	if auto_save_enabled and not is_saving_layout:
		save_complete_layout()


# ==============================================================================
# TEAROFF WINDOW MANAGEMENT
# ==============================================================================


func save_tearoff_window_states():
	"""Save all tearoff window states"""

	if not ui_manager:
		return false

	var config = ConfigFile.new()
	_load_existing_config(config)

	var all_windows = ui_manager.get_all_windows()

	for i in range(all_windows.size()):
		var window = all_windows[i]
		var window_type = window.get_meta("window_type", "NONE")
		var window_name = window.name if window.name else "UNNAMED"

	var tearoff_windows: Array[Window_Base] = []
	for window in all_windows:
		var window_type = window.get_meta("window_type", "")
		if window_type == "tearoff":
			tearoff_windows.append(window)

	# ALWAYS clear old tearoff sections and rebuild them
	# This ensures closed windows are removed from save data
	_clear_tearoff_sections(config)

	# Save currently open tearoff windows
	for i in range(tearoff_windows.size()):
		var window = tearoff_windows[i] as ContainerTearOffWindow
		if not window or not is_instance_valid(window):
			continue

	var error = config.save(config_file_path)
	if error != OK:
		return false
	return true


func _save_tearoff_window(config: ConfigFile, window: ContainerTearOffWindow, index: int) -> bool:
	"""Save a single tearoff window"""
	var container = window.get_original_container()
	if not container:
		return false

	var section = "tearoff_" + str(index)

	# Save basic window properties
	config.set_value(section, "container_id", container.container_id)
	config.set_value(section, "container_name", container.container_name)
	config.set_value(section, "position_x", window.position.x)
	config.set_value(section, "position_y", window.position.y)
	config.set_value(section, "size_x", window.size.x)
	config.set_value(section, "size_y", window.size.y)

	# Save advanced window properties
	config.set_value(section, "is_maximized", window.is_maximized)
	config.set_value(section, "modulate_a", window.modulate.a)

	# Save lock state if available
	if window.has_method("get_lock_state"):
		config.set_value(section, "is_locked", window.get_lock_state())
	elif "is_locked" in window:
		config.set_value(section, "is_locked", window.is_locked)
	else:
		config.set_value(section, "is_locked", false)

	# Save view state if available
	if window.has_method("get_view_state"):
		var view_state = window.get_view_state()
		if not view_state.is_empty():
			config.set_value(section, "view_state", view_state)

	# Save window-specific properties
	if window.has_method("get_save_data"):
		var save_data = window.get_save_data()
		if not save_data.is_empty():
			config.set_value(section, "window_data", save_data)

	return true


func load_tearoff_window_states():
	"""Load and restore all tearoff window states"""

	if not inventory_manager:
		return false

	if not ui_manager:
		return false

	var config = ConfigFile.new()
	var error = config.load(config_file_path)

	if error != OK:
		return false

	var sections = config.get_sections()

	var tearoff_sections: Array[String] = []
	for section in sections:
		if section.begins_with("tearoff_"):
			tearoff_sections.append(section)

	if tearoff_sections.size() == 0:
		return false

	var restored_count = 0
	for section in tearoff_sections:
		if await _restore_tearoff_window(config, section):
			restored_count += 1

	return restored_count > 0


func _restore_tearoff_window(config: ConfigFile, section: String) -> bool:
	"""Restore a single tearoff window"""
	var container_id = config.get_value(section, "container_id", "")
	var container_name = config.get_value(section, "container_name", "")

	if container_id.is_empty():
		return false

	# Find the container in inventory manager
	var container = inventory_manager.get_container(container_id)
	if not container:
		# Debug: List available containers
		if inventory_manager.has_method("get_all_containers"):
			var available_containers = inventory_manager.get_all_containers()
		return false

	# Get saved properties
	var pos_x = config.get_value(section, "position_x", 100)
	var pos_y = config.get_value(section, "position_y", 100)
	var size_x = config.get_value(section, "size_x", 500)
	var size_y = config.get_value(section, "size_y", 400)

	var restore_position = Vector2(pos_x, pos_y)
	var restore_size = Vector2(size_x, size_y)

	# Validate position
	if not _is_position_valid(Vector2i(pos_x, pos_y)):
		restore_position = _get_safe_window_position()

	# Get the main inventory window to create tearoff through proper system
	var main_inventory_window = _find_main_inventory_window()
	if not main_inventory_window:
		return false

	# Get the tearoff manager
	var tearoff_manager = main_inventory_window.get_tearoff_manager()
	if not tearoff_manager:
		return false

	# Create tearoff window through the proper system with our desired position and size
	tearoff_manager._create_tearoff_window(container, restore_position, restore_size)

	# Wait a frame for the window to be created
	await get_tree().process_frame

	# Find the newly created tearoff window
	var tearoff_window = tearoff_manager.get_tearoff_window(container)
	if not tearoff_window:
		return false

	# Restore other properties
	var modulate_a = config.get_value(section, "modulate_a", 1.0)
	tearoff_window.modulate.a = clamp(modulate_a, 0.1, 1.0)

	# Apply maximized state
	var is_maximized = config.get_value(section, "is_maximized", false)
	if is_maximized and tearoff_window.has_method("_maximize_window"):
		tearoff_window._maximize_window()

	# Apply lock state
	var is_locked = config.get_value(section, "is_locked", false)
	if is_locked and tearoff_window.has_method("set_window_locked"):
		tearoff_window.set_window_locked(true)

	# Restore view state
	var view_state = config.get_value(section, "view_state", {})
	if not view_state.is_empty() and tearoff_window.has_method("restore_view_state"):
		tearoff_window.restore_view_state(view_state)

	# Restore window-specific data
	var window_data = config.get_value(section, "window_data", {})
	if not window_data.is_empty() and tearoff_window.has_method("load_save_data"):
		tearoff_window.load_save_data(window_data)

	return true


func _find_main_inventory_window():
	"""Find the main inventory window"""
	if not ui_manager:
		return null

	var all_windows = ui_manager.get_all_windows()
	for window in all_windows:
		var window_type = window.get_meta("window_type", "")
		if window_type == "main_inventory" or window_type == "inventory":
			return window

	# Alternative: search by class type
	for window in all_windows:
		if window.get_script() and window.get_script().get_global_name() == "InventoryWindow":
			return window

	return null


# ==============================================================================
# COMPLETE LAYOUT MANAGEMENT
# ==============================================================================


func save_complete_layout():
	"""Save complete window layout (main + inventory + tearoffs)"""
	if is_saving_layout:
		return false

	# Don't trigger saves during loading process
	if is_loading_layout:
		return false

	is_saving_layout = true

	var main_saved = save_main_window_position()
	var inventory_saved = save_inventory_window_state()
	var tearoffs_saved = save_tearoff_window_states()

	is_saving_layout = false

	if main_saved or inventory_saved or tearoffs_saved:
		layout_saved.emit()
		return true

	return false


func load_complete_layout():
	"""Load complete window layout"""
	if is_loading_layout:
		return false

	is_loading_layout = true

	# Load main window first
	var main_loaded = load_main_window_position()

	# Wait a frame for main window to settle
	await get_tree().process_frame

	# Load inventory window state
	var inventory_loaded = await load_inventory_window_state()

	# Wait another frame
	await get_tree().process_frame

	# Then restore tearoffs
	var tearoffs_loaded = await load_tearoff_window_states()

	is_loading_layout = false

	if main_loaded or inventory_loaded or tearoffs_loaded:
		layout_loaded.emit()
		return true

	return false


func clear_saved_layout():
	"""Clear all saved window layout data"""
	var config = ConfigFile.new()
	var error = config.save(config_file_path)

	if error == OK:
		layout_cleared.emit()
		return true

	return false


# ==============================================================================
# AUTO SAVE/LOAD
# ==============================================================================


func _auto_load_layout():
	"""Auto-load layout when ready"""

	if not auto_load_enabled:
		return

	# Ensure managers are available
	if not inventory_manager:
		return

	if not ui_manager:
		return

	# Check if there's actually saved data
	if not has_saved_layout():
		return

	var layout_info = get_layout_info()

	await load_complete_layout()


func _auto_save_layout():
	"""Auto-save layout on exit"""
	if not auto_save_enabled:
		return

	var result = save_complete_layout()


# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================


func _load_existing_config(config: ConfigFile):
	"""Load existing config or create new one"""
	config.load(config_file_path)  # Ignore errors, file might not exist


func _clear_tearoff_sections(config: ConfigFile):
	"""Clear all existing tearoff sections"""
	var sections = config.get_sections()
	for section in sections:
		if section.begins_with("tearoff_"):
			config.erase_section(section)


func _is_position_valid(pos: Vector2i) -> bool:
	"""Check if position is within any screen bounds with reasonable margins"""
	var screen_count = DisplayServer.get_screen_count()

	for screen_id in screen_count:
		var screen_rect = Rect2i(DisplayServer.screen_get_position(screen_id), DisplayServer.screen_get_size(screen_id))

		# Allow windows to be partially off-screen (common for multi-monitor setups)
		# Just ensure at least 100px of the window would be visible
		var expanded_rect = screen_rect.grow(400)  # Very generous margin

		if expanded_rect.has_point(pos):
			return true

	return false


func _get_safe_window_position() -> Vector2:
	"""Get a safe fallback window position"""
	var primary_screen = DisplayServer.get_primary_screen()
	var screen_size = DisplayServer.screen_get_size(primary_screen)
	var screen_pos = DisplayServer.screen_get_position(primary_screen)

	# Position in upper-left area of primary screen
	return Vector2(screen_pos.x + 100, screen_pos.y + 100)


func _on_tearoff_window_closed(_window: Window_Base):
	"""Handle when a tearoff window is closed"""

	# Trigger immediate save to remove this window from save data
	if auto_save_enabled and not is_saving_layout:
		save_complete_layout()


# ==============================================================================
# PUBLIC API
# ==============================================================================


func set_auto_save_enabled(enabled: bool):
	"""Enable or disable automatic saving"""
	auto_save_enabled = enabled


func set_auto_load_enabled(enabled: bool):
	"""Enable or disable automatic loading on startup"""
	auto_load_enabled = enabled


func has_saved_layout() -> bool:
	"""Check if there is saved layout data"""
	var config = ConfigFile.new()
	return config.load(config_file_path) == OK


func get_layout_info() -> Dictionary:
	"""Get information about saved layout"""
	var config = ConfigFile.new()
	if config.load(config_file_path) != OK:
		return {"has_data": false}

	var sections = config.get_sections()
	var tearoff_count = 0
	for section in sections:
		if section.begins_with("tearoff_"):
			tearoff_count += 1
	var has_main_window = config.has_section("main_window")

	return {"has_data": true, "has_main_window": has_main_window, "tearoff_count": tearoff_count, "sections": sections}


func force_save_layout():
	"""Manually save current layout"""
	return save_complete_layout()


func force_load_layout():
	"""Manually load saved layout"""
	await load_complete_layout()


func get_config_file_path() -> String:
	"""Get the config file path"""
	return config_file_path


func set_config_file_path(path: String):
	"""Set custom config file path"""
	config_file_path = path
