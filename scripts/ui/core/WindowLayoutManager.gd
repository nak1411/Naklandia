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

var inventory_window_state: Dictionary = {"is_open": false, "position": Vector2.ZERO, "size": Vector2.ZERO, "was_open_on_exit": false}


func _ready():
	add_to_group("window_layout_manager")
	print("WindowLayoutManager: Starting initialization")

	# Wait for other systems to initialize
	await get_tree().process_frame
	await get_tree().process_frame

	# Find required managers
	_find_managers()

	# Auto-load layout if enabled
	if auto_load_enabled:
		print("WindowLayoutManager: About to auto-load layout")
		call_deferred("_auto_load_layout")
	else:
		print("WindowLayoutManager: Auto-load disabled")


func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		print("WindowLayoutManager: Close request received")
		if auto_save_enabled:
			_auto_save_layout()
		else:
			print("WindowLayoutManager: Auto-save disabled, not saving on exit")
		get_tree().quit()


# ==============================================================================
# MANAGER DISCOVERY
# ==============================================================================


func _find_managers():
	"""Find the required managers in the scene"""
	print("WindowLayoutManager: Searching for managers...")

	# Find UI Manager
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	print("WindowLayoutManager: Found %d nodes in ui_manager group" % ui_managers.size())
	if ui_managers.size() > 0:
		ui_manager = ui_managers[0]
		print("WindowLayoutManager: Found UIManager: %s" % ui_manager.name)
		_connect_ui_manager_signals()
	else:
		print("WindowLayoutManager: UIManager not found in group")

	# Find Inventory Manager
	var inventory_managers = get_tree().get_nodes_in_group("inventory_manager")
	print("WindowLayoutManager: Found %d nodes in inventory_manager group" % inventory_managers.size())
	if inventory_managers.size() > 0:
		inventory_manager = inventory_managers[0]
		print("WindowLayoutManager: Found InventoryManager: %s" % inventory_manager.name)
	else:
		# Alternative: search recursively
		inventory_manager = _find_inventory_manager_recursive(get_tree().current_scene)
		if inventory_manager:
			print("WindowLayoutManager: Found InventoryManager recursively: %s" % inventory_manager.name)
		else:
			print("WindowLayoutManager: InventoryManager not found anywhere")


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
		print("WindowLayoutManager: Immediate save triggered by window change")
		save_complete_layout()


func connect_window_signals(window: Window_Base):
	"""Connect to window movement/resize signals for immediate auto-saving"""
	if not window:
		return

	print("WindowLayoutManager: Connecting signals for window %s" % window.name)

	var window_type = window.get_meta("window_type", "")

	# Connect to window resize
	if window.has_signal("window_resized"):
		if not window.window_resized.is_connected(_on_immediate_window_change):
			window.window_resized.connect(func(_size): _on_immediate_window_change(window, "resize"))
			print("WindowLayoutManager: Connected to window_resized signal")

	# For inventory window, also monitor open/close state
	if window_type == "main_inventory" or window_type == "inventory":
		_connect_inventory_specific_signals(window)

	# Monitor position changes in real-time
	_start_realtime_position_monitoring(window)

	# Monitor drag events
	connect_window_drag_signals(window)


func _connect_inventory_specific_signals(window: Window_Base):
	"""Connect inventory-specific signals"""
	print("WindowLayoutManager: Connecting inventory-specific signals")

	# Monitor visibility changes
	if window.has_signal("visibility_changed"):
		if not window.visibility_changed.is_connected(_on_inventory_visibility_changed):
			window.visibility_changed.connect(_on_inventory_visibility_changed.bind(window))

	# Monitor window close
	if window.has_signal("window_closed"):
		if not window.window_closed.is_connected(_on_inventory_window_closed):
			window.window_closed.connect(_on_inventory_window_closed.bind(window))


func _on_immediate_window_change(window: Window_Base, change_type: String):
	"""Handle immediate window changes"""
	print("WindowLayoutManager: Window %s changed (%s) - saving immediately" % [window.name, change_type])
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

	print("WindowLayoutManager: Started real-time position monitoring for %s" % window.name)


func _check_window_position_realtime(window: Window_Base, timer: Timer):
	"""Check window position in real-time and save if changed"""
	if not is_instance_valid(window):
		timer.queue_free()
		return

	var last_position = window.get_meta("last_saved_position", Vector2.ZERO)
	if window.position != last_position:
		print("WindowLayoutManager: Position changed from %s to %s - saving" % [last_position, window.position])
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
					print("WindowLayoutManager: Drag ended - saving window position")
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
		print("WindowLayoutManager: Failed to save main window settings: ", error)
		return false

	return true


func load_main_window_position():
	"""Load and apply saved main window position"""
	var config = ConfigFile.new()
	var error = config.load(config_file_path)

	if error != OK:
		print("WindowLayoutManager: No layout file found for main window")
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
		print("WindowLayoutManager: Main window position restored")
	else:
		print("WindowLayoutManager: Invalid main window position, using default")

	# Apply size if valid
	if size_x > 0 and size_y > 0:
		DisplayServer.window_set_size(Vector2i(size_x, size_y))
		print("WindowLayoutManager: Main window size restored")

	return true


# ==============================================================================
# INVENTORY WINDOW MANAGEMENT
# ==============================================================================


# Update save_inventory_window_state() to be more comprehensive:
func save_inventory_window_state():
	"""Save main inventory window state"""
	# Don't save inventory state while we're loading layout
	if is_loading_layout:
		print("WindowLayoutManager: Skipping inventory save during layout loading")
		return true

	var config = ConfigFile.new()
	_load_existing_config(config)

	# Find the main inventory window
	var inventory_window = _find_main_inventory_window()
	var is_open = inventory_window != null and inventory_window.visible

	print("WindowLayoutManager: Saving inventory window state - open: %s" % is_open)

	config.set_value("inventory_window", "is_open", is_open)
	config.set_value("inventory_window", "was_open_on_exit", is_open)

	if inventory_window and is_open:
		print("WindowLayoutManager: Inventory window found, saving properties...")
		print("  Position: %s" % inventory_window.position)
		print("  Size: %s" % inventory_window.size)
		print("  Modulate: %s" % inventory_window.modulate)
		print("  Visible: %s" % inventory_window.visible)

		# Basic properties
		config.set_value("inventory_window", "position_x", inventory_window.position.x)
		config.set_value("inventory_window", "position_y", inventory_window.position.y)
		config.set_value("inventory_window", "size_x", inventory_window.size.x)
		config.set_value("inventory_window", "size_y", inventory_window.size.y)
		config.set_value("inventory_window", "modulate_a", inventory_window.modulate.a)

		# Check for additional properties and save them
		if "is_locked" in inventory_window:
			config.set_value("inventory_window", "is_locked", inventory_window.is_locked)
			print("  Lock state: %s" % inventory_window.is_locked)

		if "is_maximized" in inventory_window:
			config.set_value("inventory_window", "is_maximized", inventory_window.is_maximized)
			print("  Maximized: %s" % inventory_window.is_maximized)

		# Save additional window properties if available
		if inventory_window.has_method("get_save_data"):
			var save_data = inventory_window.get_save_data()
			if not save_data.is_empty():
				config.set_value("inventory_window", "window_data", save_data)
				print("  Window data: %s" % save_data)

		# Save container selection state if available
		if inventory_window.has_method("get_current_container"):
			var current_container = inventory_window.get_current_container()
			if current_container:
				config.set_value("inventory_window", "selected_container_id", current_container.container_id)
				print("  Selected container: %s" % current_container.container_id)

		# Save window view state if available
		if inventory_window.has_method("get_view_state"):
			var view_state = inventory_window.get_view_state()
			if not view_state.is_empty():
				config.set_value("inventory_window", "view_state", view_state)
				print("  View state: %s" % view_state)

		# Save any filter/search state
		if inventory_window.has_method("get_filter_state"):
			var filter_state = inventory_window.get_filter_state()
			if not filter_state.is_empty():
				config.set_value("inventory_window", "filter_state", filter_state)
				print("  Filter state: %s" % filter_state)

	var error = config.save(config_file_path)
	if error != OK:
		print("WindowLayoutManager: Failed to save inventory window state: ", error)
		return false

	print("WindowLayoutManager: Inventory window state saved successfully")

	# Verify what was actually saved
	var verify_config = ConfigFile.new()
	if verify_config.load(config_file_path) == OK:
		if verify_config.has_section("inventory_window"):
			var keys = verify_config.get_section_keys("inventory_window")
			print("WindowLayoutManager: Saved inventory keys: %s" % keys)
		else:
			print("WindowLayoutManager: No inventory_window section found in saved file")

	return true


func load_inventory_window_state():
	"""Load and apply saved inventory window state"""
	print("WindowLayoutManager: load_inventory_window_state() called")

	var config = ConfigFile.new()
	var error = config.load(config_file_path)

	if error != OK:
		print("WindowLayoutManager: No layout file found for inventory window: ", error)
		return false

	if not config.has_section("inventory_window"):
		print("WindowLayoutManager: No inventory_window section found in config")
		return false

	print("WindowLayoutManager: Found inventory_window section in config")

	var was_open = config.get_value("inventory_window", "was_open_on_exit", false)
	print("WindowLayoutManager: Inventory window was open on exit: %s" % was_open)

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

		print("WindowLayoutManager: Loaded inventory config:")
		print("  Position: (%s, %s)" % [pos_x, pos_y])
		print("  Size: (%s, %s)" % [size_x, size_y])
		print("  Transparency: %s" % modulate_a)
		print("  Locked: %s" % is_locked)
		print("  Maximized: %s" % is_maximized)
		print("  Selected container: %s" % selected_container_id)

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

		print("WindowLayoutManager: Stored inventory window state for restoration")

		# Try to open the inventory if we can find the integration
		await _restore_inventory_open_state()

		return true

	print("WindowLayoutManager: Inventory was closed on exit, keeping it closed")
	inventory_window_state["was_open_on_exit"] = false

	return false


func _restore_inventory_open_state():
	"""Try to open the inventory and restore its state"""
	print("WindowLayoutManager: _restore_inventory_open_state() called")

	# Find inventory integration to open the inventory
	var integration = _find_inventory_integration()
	print("WindowLayoutManager: Found inventory integration: %s" % (integration.name if integration else "null"))

	if integration:
		# Check what methods are available
		print("WindowLayoutManager: Integration methods:")
		if integration.has_method("open_inventory"):
			print("  - has open_inventory()")
		if integration.has_method("toggle_inventory"):
			print("  - has toggle_inventory()")
		if integration.has_method("show_inventory"):
			print("  - has show_inventory()")

		# Try different methods to open the inventory
		if integration.has_method("open_inventory"):
			print("WindowLayoutManager: Calling open_inventory()")
			integration.open_inventory()
		elif integration.has_method("toggle_inventory"):
			print("WindowLayoutManager: Calling toggle_inventory()")
			integration.toggle_inventory()
		elif integration.has_method("show_inventory"):
			print("WindowLayoutManager: Calling show_inventory()")
			integration.show_inventory()
		else:
			print("WindowLayoutManager: No suitable method found to open inventory")
			return

		# Wait multiple frames for the inventory to open
		print("WindowLayoutManager: Waiting for inventory to open...")
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame

		# Check if inventory is now open
		var inventory_window = _find_main_inventory_window()
		if inventory_window:
			print("WindowLayoutManager: Inventory window found after opening, applying state...")
			_apply_inventory_window_state()
		else:
			print("WindowLayoutManager: Inventory window still not found after opening attempt")
	else:
		print("WindowLayoutManager: Could not find inventory integration to restore state")


func _apply_inventory_window_state():
	"""Apply saved state to the inventory window"""
	var inventory_window = _find_main_inventory_window()
	if not inventory_window:
		print("WindowLayoutManager: Could not find inventory window to apply state")
		return

	print("WindowLayoutManager: Applying saved state to inventory window")

	# Apply position and size
	if _is_position_valid(Vector2i(inventory_window_state.position)):
		inventory_window.position = inventory_window_state.position
		print("  Applied position: %s" % inventory_window_state.position)

	inventory_window.size = inventory_window_state.size
	print("  Applied size: %s" % inventory_window_state.size)

	inventory_window.modulate.a = inventory_window_state.get("modulate_a", 1.0)
	print("  Applied transparency: %s" % inventory_window_state.get("modulate_a", 1.0))

	# Apply lock state
	if inventory_window_state.get("is_locked", false) and inventory_window.has_method("set_window_locked"):
		inventory_window.set_window_locked(true)
		print("  Applied lock state: true")

	# Apply maximized state
	if inventory_window_state.get("is_maximized", false) and inventory_window.has_method("_maximize_window"):
		inventory_window._maximize_window()
		print("  Applied maximized state: true")

	# Apply additional saved data
	if inventory_window_state.has("window_data") and inventory_window.has_method("load_save_data"):
		inventory_window.load_save_data(inventory_window_state["window_data"])
		print("  Applied window data")

	if inventory_window_state.has("view_state") and inventory_window.has_method("restore_view_state"):
		inventory_window.restore_view_state(inventory_window_state["view_state"])
		print("  Applied view state")

	if inventory_window_state.has("filter_state") and inventory_window.has_method("restore_filter_state"):
		inventory_window.restore_filter_state(inventory_window_state["filter_state"])
		print("  Applied filter state")

	# Restore selected container if available
	if inventory_window_state.has("selected_container_id") and inventory_window.has_method("select_container_by_id"):
		inventory_window.select_container_by_id(inventory_window_state["selected_container_id"])
		print("  Applied selected container")

	print("WindowLayoutManager: Inventory window state applied")


func _find_inventory_integration():
	"""Find the inventory integration in the scene"""
	print("WindowLayoutManager: Searching for inventory integration...")

	# Search for inventory integration
	var integrations = get_tree().get_nodes_in_group("inventory_integration")
	print("WindowLayoutManager: Found %d nodes in inventory_integration group" % integrations.size())

	if integrations.size() > 0:
		print("WindowLayoutManager: Using integration from group: %s" % integrations[0].name)
		return integrations[0]

	# Alternative: search by class name or script
	print("WindowLayoutManager: Searching recursively for InventoryIntegration...")
	var result = _find_node_recursive(get_tree().current_scene, "InventoryIntegration")
	if result:
		print("WindowLayoutManager: Found integration recursively: %s" % result.name)
	else:
		print("WindowLayoutManager: No InventoryIntegration found")

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
	print("WindowLayoutManager: Inventory visibility changed to: %s" % window.visible)
	inventory_window_state["is_open"] = window.visible

	if auto_save_enabled and not is_saving_layout:
		save_complete_layout()


func _on_inventory_window_closed(_window: Window_Base):
	"""Handle inventory window being closed"""
	print("WindowLayoutManager: Inventory window closed")
	inventory_window_state["is_open"] = false

	if auto_save_enabled and not is_saving_layout:
		save_complete_layout()


# ==============================================================================
# TEAROFF WINDOW MANAGEMENT
# ==============================================================================


func save_tearoff_window_states():
	"""Save all tearoff window states"""
	print("WindowLayoutManager: save_tearoff_window_states() called")

	if not ui_manager:
		print("WindowLayoutManager: No UIManager available for tearoff save")
		return false

	var config = ConfigFile.new()
	_load_existing_config(config)

	print("WindowLayoutManager: UIManager found, getting all windows...")
	var all_windows = ui_manager.get_all_windows()
	print("WindowLayoutManager: Found %d total windows" % all_windows.size())

	var tearoff_windows: Array[Window_Base] = []
	for window in all_windows:
		if window.get_meta("window_type", "") == "tearoff":
			tearoff_windows.append(window)

	print("WindowLayoutManager: Found %d tearoff windows" % tearoff_windows.size())

	# ONLY clear existing tearoff data if we have new tearoff windows to save
	# This prevents wiping saved tearoff data during startup when no tearoffs exist yet
	if tearoff_windows.size() > 0:
		_clear_tearoff_sections(config)
		print("WindowLayoutManager: Cleared old tearoff sections, saving new ones")
	else:
		print("WindowLayoutManager: No tearoff windows to save, preserving existing tearoff data")

	# Save each tearoff window (if any)
	for i in range(tearoff_windows.size()):
		var window = tearoff_windows[i] as ContainerTearOffWindow
		if not window or not is_instance_valid(window):
			print("WindowLayoutManager: Skipping invalid tearoff window %d" % i)
			continue

		if not _save_tearoff_window(config, window, i):
			print("WindowLayoutManager: Failed to save tearoff window %d" % i)

	var error = config.save(config_file_path)
	if error != OK:
		print("WindowLayoutManager: Failed to save tearoff states: ", error)
		return false

	print("WindowLayoutManager: Config file saved successfully")
	return true


func _save_tearoff_window(config: ConfigFile, window: ContainerTearOffWindow, index: int) -> bool:
	"""Save a single tearoff window"""
	var container = window.get_original_container()
	if not container:
		print("WindowLayoutManager: No container found for tearoff window")
		return false

	var section = "tearoff_" + str(index)

	print("WindowLayoutManager: SAVING tearoff window to section '%s'" % section)
	print("  Container: %s (%s)" % [container.container_name, container.container_id])
	print("  Position: %s" % window.position)
	print("  Size: %s" % window.size)
	print("  Window reported size: %s" % window.size)
	print("  Window custom_minimum_size: %s" % window.custom_minimum_size)

	# Save basic window properties
	config.set_value(section, "container_id", container.container_id)
	config.set_value(section, "container_name", container.container_name)
	config.set_value(section, "position_x", window.position.x)
	config.set_value(section, "position_y", window.position.y)
	config.set_value(section, "size_x", window.size.x)
	config.set_value(section, "size_y", window.size.y)

	print("WindowLayoutManager: Config values set - size_x: %s, size_y: %s" % [window.size.x, window.size.y])

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

	print("WindowLayoutManager: Successfully saved tearoff window data for section '%s'" % section)
	return true


func load_tearoff_window_states():
	"""Load and restore all tearoff window states"""
	print("WindowLayoutManager: load_tearoff_window_states() called")

	if not inventory_manager:
		print("WindowLayoutManager: InventoryManager not available for tearoff restore")
		return false

	if not ui_manager:
		print("WindowLayoutManager: UIManager not available for tearoff restore")
		return false

	var config = ConfigFile.new()
	var error = config.load(config_file_path)

	if error != OK:
		print("WindowLayoutManager: No layout file found for tearoff restoration: ", error)
		return false

	print("WindowLayoutManager: Config file loaded successfully")

	var sections = config.get_sections()
	print("WindowLayoutManager: Config file contains sections: %s" % sections)

	var tearoff_sections: Array[String] = []
	for section in sections:
		if section.begins_with("tearoff_"):
			tearoff_sections.append(section)

	print("WindowLayoutManager: Found %d tearoff sections to restore: %s" % [tearoff_sections.size(), tearoff_sections])

	if tearoff_sections.size() == 0:
		print("WindowLayoutManager: No tearoff sections found in config")
		return false

	var restored_count = 0
	for section in tearoff_sections:
		print("WindowLayoutManager: Attempting to restore section: %s" % section)
		if await _restore_tearoff_window(config, section):
			restored_count += 1
			print("WindowLayoutManager: Successfully restored section: %s" % section)
		else:
			print("WindowLayoutManager: Failed to restore section: %s" % section)

	print("WindowLayoutManager: Restored %d of %d tearoff windows" % [restored_count, tearoff_sections.size()])
	return restored_count > 0


func _restore_tearoff_window(config: ConfigFile, section: String) -> bool:
	"""Restore a single tearoff window"""
	print("WindowLayoutManager: _restore_tearoff_window() called for section: %s" % section)
	var container_id = config.get_value(section, "container_id", "")
	var container_name = config.get_value(section, "container_name", "")
	print("WindowLayoutManager: Attempting to restore container: %s (%s)" % [container_name, container_id])

	if container_id.is_empty():
		print("WindowLayoutManager: Invalid container_id in section %s" % section)
		return false

	# Find the container in inventory manager
	var container = inventory_manager.get_container(container_id)
	if not container:
		print("WindowLayoutManager: Container %s (%s) not found in InventoryManager" % [container_name, container_id])
		# Debug: List available containers
		if inventory_manager.has_method("get_all_containers"):
			var available_containers = inventory_manager.get_all_containers()
			print("WindowLayoutManager: Available containers: %s" % available_containers.keys())
		return false

	print("WindowLayoutManager: Found container: %s" % container.container_name)

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
		print("WindowLayoutManager: Main inventory window not found, cannot create tearoff")
		return false

	# Get the tearoff manager
	var tearoff_manager = main_inventory_window.get_tearoff_manager()
	if not tearoff_manager:
		print("WindowLayoutManager: Tearoff manager not found")
		return false

	# Create tearoff window through the proper system with our desired position and size
	tearoff_manager._create_tearoff_window(container, restore_position, restore_size)

	# Wait a frame for the window to be created
	await get_tree().process_frame

	# Find the newly created tearoff window
	var tearoff_window = tearoff_manager.get_tearoff_window(container)
	if not tearoff_window:
		print("WindowLayoutManager: Failed to create tearoff window for %s" % container_name)
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

	print("WindowLayoutManager: Restored tearoff window for container: %s" % container_name)
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
		print("WindowLayoutManager: Skipping save during layout loading")
		return false

	is_saving_layout = true
	print("WindowLayoutManager: Starting complete layout save")

	var main_saved = save_main_window_position()
	var inventory_saved = save_inventory_window_state()
	var tearoffs_saved = save_tearoff_window_states()

	is_saving_layout = false

	if main_saved or inventory_saved or tearoffs_saved:
		layout_saved.emit()
		print("WindowLayoutManager: Complete layout saved successfully")
		return true

	print("WindowLayoutManager: Failed to save complete layout")
	return false


func load_complete_layout():
	"""Load complete window layout"""
	if is_loading_layout:
		print("WindowLayoutManager: Load already in progress")
		return false

	is_loading_layout = true
	print("WindowLayoutManager: ===== STARTING COMPLETE LAYOUT LOAD =====")

	# Load main window first
	print("WindowLayoutManager: Loading main window position...")
	var main_loaded = load_main_window_position()
	print("WindowLayoutManager: Main window load result: %s" % main_loaded)

	# Wait a frame for main window to settle
	print("WindowLayoutManager: Waiting for main window to settle...")
	await get_tree().process_frame

	# Load inventory window state
	print("WindowLayoutManager: Loading inventory window state...")
	var inventory_loaded = await load_inventory_window_state()
	print("WindowLayoutManager: Inventory window load result: %s" % inventory_loaded)

	# Wait another frame
	print("WindowLayoutManager: Waiting before loading tearoffs...")
	await get_tree().process_frame

	# Then restore tearoffs
	print("WindowLayoutManager: Loading tearoff windows...")
	var tearoffs_loaded = await load_tearoff_window_states()
	print("WindowLayoutManager: Tearoff windows load result: %s" % tearoffs_loaded)

	is_loading_layout = false

	print("WindowLayoutManager: ===== LAYOUT LOAD COMPLETE =====")
	print("WindowLayoutManager: Results - Main: %s, Inventory: %s, Tearoffs: %s" % [main_loaded, inventory_loaded, tearoffs_loaded])

	if main_loaded or inventory_loaded or tearoffs_loaded:
		layout_loaded.emit()
		print("WindowLayoutManager: Complete layout loaded successfully")
		return true
	else:
		print("WindowLayoutManager: No layout data found to load")
		return false


func clear_saved_layout():
	"""Clear all saved window layout data"""
	var config = ConfigFile.new()
	var error = config.save(config_file_path)

	if error == OK:
		layout_cleared.emit()
		print("WindowLayoutManager: Layout data cleared")
		return true

	print("WindowLayoutManager: Failed to clear layout data: ", error)
	return false


# ==============================================================================
# AUTO SAVE/LOAD
# ==============================================================================


func _auto_load_layout():
	"""Auto-load layout when ready"""
	print("WindowLayoutManager: _auto_load_layout() called")

	if not auto_load_enabled:
		print("WindowLayoutManager: Auto-load disabled")
		return

	# Ensure managers are available
	if not inventory_manager:
		print("WindowLayoutManager: InventoryManager not available for auto-load")
		return

	if not ui_manager:
		print("WindowLayoutManager: UIManager not available for auto-load")
		return

	print("WindowLayoutManager: Both managers available, checking for saved layout")

	# Check if there's actually saved data
	if not has_saved_layout():
		print("WindowLayoutManager: No saved layout data found")
		return

	var layout_info = get_layout_info()
	print("WindowLayoutManager: Layout info: %s" % layout_info)

	print("WindowLayoutManager: Starting auto-load process")
	await load_complete_layout()
	print("WindowLayoutManager: Auto-load process completed")


func _auto_save_layout():
	"""Auto-save layout on exit"""
	if not auto_save_enabled:
		print("WindowLayoutManager: Auto-save disabled, skipping")
		return

	print("WindowLayoutManager: Auto-saving layout on exit")
	var result = save_complete_layout()
	print("WindowLayoutManager: Auto-save result: %s" % result)


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


# ==============================================================================
# PUBLIC API
# ==============================================================================


func set_auto_save_enabled(enabled: bool):
	"""Enable or disable automatic saving"""
	auto_save_enabled = enabled
	print("WindowLayoutManager: Auto-save %s" % ("enabled" if enabled else "disabled"))


func set_auto_load_enabled(enabled: bool):
	"""Enable or disable automatic loading on startup"""
	auto_load_enabled = enabled
	print("WindowLayoutManager: Auto-load %s" % ("enabled" if enabled else "disabled"))


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
	print("WindowLayoutManager: Config file path set to: %s" % path)
