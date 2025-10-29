# integration/InventoryIntegration.gd
# Simplified combined integration system
class_name InventoryIntegration
extends Node

# Signals
signal inventory_toggled(is_open: bool)
signal setup_completed

# Integration layer components
var player_adapter: PlayerAdapter
var game_state_adapter: GameStateAdapter
var ui_input_adapter: UIInputAdapter
var event_bus: InventoryEventBus
var event_handlers: GameEventHandlers

# Original inventory system references
var player: Player
var inventory_manager: InventoryManager
var inventory_window: InventoryWindow
var inventory_canvas: CanvasLayer

# UI Management
var is_inventory_open: bool = false
var setup_complete: bool = false

# Position saving
var saved_position: Vector2i = Vector2i.ZERO
var position_save_file: String = "user://inventory_window_position.dat"


func _ready():
	add_to_group("inventory_integration")
	name = "InventoryIntegration"
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Setup integration layer first
	_setup_integration_layer()

	# Then setup original inventory system
	call_deferred("_setup_original_inventory_system")

	# Set up periodic window checking to track all UI windows
	call_deferred("_setup_window_tracking")


func _unhandled_input(event: InputEvent):
	"""Global handler to catch drops outside any window"""
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var viewport = get_viewport()
		if viewport and viewport.has_meta("current_drag_data"):
			var drag_data = viewport.get_meta("current_drag_data")
			var source_slot = drag_data.get("source_slot")

			print("[InventoryIntegration] Unhandled drop detected - returning item to source")

			# Notify source slot that drop failed
			if source_slot and source_slot.has_method("_on_external_drop_result"):
				source_slot._on_external_drop_result(false)

			# Force refresh all inventory displays immediately
			_refresh_inventory_display()

			# Clean up drag metadata
			viewport.remove_meta("current_drag_data")
			get_viewport().set_input_as_handled()


func _setup_integration_layer():
	"""Setup the integration layer components"""
	# Create event bus first
	event_bus = InventoryEventBus.new()
	event_bus.name = "EventBus"
	add_child(event_bus)

	# Create event handlers
	event_handlers = GameEventHandlers.new()
	event_handlers.name = "EventHandlers"
	add_child(event_handlers)

	# Setup event handlers after next frame
	call_deferred("_setup_event_handlers")

	# Create adapters
	player_adapter = PlayerAdapter.new()
	player_adapter.name = "PlayerAdapter"
	add_child(player_adapter)

	game_state_adapter = GameStateAdapter.new()
	game_state_adapter.name = "GameStateAdapter"
	add_child(game_state_adapter)

	ui_input_adapter = UIInputAdapter.new()
	ui_input_adapter.name = "UIInputAdapter"
	add_child(ui_input_adapter)

	# Connect everything after next frame
	call_deferred("_connect_integration_layer")


func _setup_event_handlers():
	"""Setup event handlers after components are ready"""
	if event_handlers and event_bus:
		event_handlers.setup(event_bus, self)


func _connect_integration_layer():
	"""Connect all integration components"""

	# Connect adapters to event bus
	if player_adapter and event_bus:
		player_adapter.setup_event_connections(event_bus)

	if game_state_adapter and event_bus:
		game_state_adapter.setup_event_connections(event_bus)

	if ui_input_adapter and event_bus:
		ui_input_adapter.setup_event_connections(event_bus)

	# Connect to external systems
	_connect_external_signals()

	# Connect to integration events
	if event_bus:
		event_bus.inventory_opened.connect(_on_inventory_opened_event)
		event_bus.inventory_closed.connect(_on_inventory_closed_event)


func _setup_window_tracking():
	"""Set up tracking for all UI windows to manage input/cursor centrally"""
	var ui_manager = _get_ui_manager()
	if ui_manager and ui_manager.has_signal("window_focused"):
		# Connect to window signals to track visibility changes
		if not ui_manager.window_closed.is_connected(_on_any_window_closed):
			ui_manager.window_closed.connect(_on_any_window_closed)

	print("[InventoryIntegration] Window tracking set up")


func _on_any_window_closed(window: Window_Base):
	"""Called whenever ANY window closes - check if we should restore input"""
	var window_name = "null"
	var window_type = "unknown"
	if is_instance_valid(window):
		window_name = window.name
		window_type = window.get_meta("window_type", "unknown")
	print("[InventoryIntegration] Window closed signal received: ", window_name, " (type: ", window_type, ")")

	# Check if we should restore input based on remaining windows
	if _should_restore_player_input():
		print("[InventoryIntegration] Restoring input after window close")
		_set_player_input_enabled(true)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		print("[InventoryIntegration] NOT restoring input - other windows still open")


func _connect_external_signals():
	"""Connect to external game system signals"""
	# Connect to player signals
	var player_node = get_tree().get_first_node_in_group("player")
	if player_node and player_adapter:
		player_adapter.connect_to_player(player_node)

	# Connect to UI manager
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	if ui_managers.size() > 0 and ui_input_adapter:
		ui_input_adapter.connect_to_ui_manager(ui_managers[0])

	# Connect to game state manager
	var game_state_nodes = get_tree().get_nodes_in_group("game_state")
	if game_state_nodes.size() > 0 and game_state_adapter:
		game_state_adapter.connect_to_game_state(game_state_nodes[0])


func _setup_original_inventory_system():
	"""Setup the original inventory system"""
	# Find or create the inventory canvas layer
	var scene_root = get_tree().current_scene
	inventory_canvas = scene_root.get_node_or_null("InventoryLayer")

	if not inventory_canvas:
		inventory_canvas = CanvasLayer.new()
		inventory_canvas.name = "InventoryLayer"
		inventory_canvas.layer = 50
		scene_root.add_child(inventory_canvas)

	# FIXED: Only create InventoryManager once
	if not inventory_manager:
		inventory_manager = InventoryManager.new()
		inventory_manager.add_to_group("inventory_manager")
		inventory_manager.name = "InventoryManager"
		add_child(inventory_manager)
		# Wait for InventoryManager._ready() to complete (which loads inventory)
		await get_tree().process_frame

	# Wait for scene to be ready
	await get_tree().process_frame

	# Create inventory window
	inventory_window = InventoryWindow.new()
	inventory_window.name = "InventoryWindow"

	# Get UIManager and register the main inventory window
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	if ui_managers.size() > 0:
		var ui_manager = ui_managers[0]
		if ui_manager.has_method("add_main_inventory_window"):
			ui_manager.add_main_inventory_window(inventory_window)
		else:
			# Fallback to inventory canvas
			inventory_canvas.add_child(inventory_window)
	else:
		# Fallback to inventory canvas
		inventory_canvas.add_child(inventory_window)

	# Wait for initialization
	await get_tree().process_frame

	# Set inventory manager on the window
	if inventory_window.has_method("set_inventory_manager"):
		inventory_window.set_inventory_manager(inventory_manager)

	# Connect signals
	_connect_signals()

	# Load saved position
	_load_and_apply_position()

	# Hide the window initially
	inventory_window.visible = false

	setup_complete = true
	setup_completed.emit()


# Event handlers for integration layer
func _on_inventory_opened_event():
	"""Handle inventory opened event from integration system"""
	if not is_inventory_open:
		_show_inventory()


func _on_inventory_closed_event():
	"""Handle inventory closed event from integration system"""
	if is_inventory_open:
		_hide_inventory()


func _show_inventory():
	"""Show the inventory window"""
	print("[InventoryIntegration] _show_inventory called")

	# Check if inventory window was destroyed and recreate if needed
	if not inventory_window or not is_instance_valid(inventory_window):
		await _recreate_inventory_window()

	if not inventory_window or not setup_complete:
		return

	# Update the main inventory with filtered containers (excluding tearoff views)
	if inventory_window.content and inventory_window.content.has_method("update_containers"):
		var filtered_containers = _get_filtered_containers_for_main_inventory()
		inventory_window.content.update_containers(filtered_containers)

		# Select first container if we have any and no current selection
		if not inventory_window.content.current_container and filtered_containers.size() > 0:
			inventory_window.content.select_container(filtered_containers[0])

	is_inventory_open = true

	# ALWAYS disable input and show cursor when opening inventory
	# The window tracking will prevent re-enabling when other windows are still open
	print("[InventoryIntegration] Disabling player input and showing cursor")
	_set_player_input_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	inventory_window.visible = true
	inventory_window.move_to_front()

	# Emit signal
	inventory_toggled.emit(true)


func _get_filtered_containers_for_main_inventory() -> Array[InventoryContainer_Base]:
	"""Get containers for main inventory, excluding tearoff views"""
	if not inventory_manager:
		return []

	var accessible_containers = inventory_manager.get_accessible_containers()
	var filtered_containers: Array[InventoryContainer_Base] = []

	for container in accessible_containers:
		# Skip tearoff views in main inventory
		if container.has_meta("is_tearoff_view"):
			continue
		filtered_containers.append(container)

	return filtered_containers


func _recreate_inventory_window():
	"""Recreate the inventory window if it was destroyed"""
	# Create inventory window
	inventory_window = InventoryWindow.new()
	inventory_window.name = "InventoryWindow"

	# Get UIManager and register the main inventory window
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	if ui_managers.size() > 0:
		var ui_manager = ui_managers[0]
		if ui_manager.has_method("add_main_inventory_window"):
			ui_manager.add_main_inventory_window(inventory_window)
		else:
			# Fallback to inventory canvas
			inventory_canvas.add_child(inventory_window)
	else:
		# Fallback to inventory canvas
		inventory_canvas.add_child(inventory_window)

	# Wait for initialization
	await get_tree().process_frame

	# Set inventory manager on the window
	if inventory_window.has_method("set_inventory_manager"):
		inventory_window.set_inventory_manager(inventory_manager)

	# Update with filtered containers
	if inventory_window.content and inventory_window.content.has_method("update_containers"):
		var filtered_containers = _get_filtered_containers_for_main_inventory()
		inventory_window.content.update_containers(filtered_containers)

		# Select first container if we have any
		if filtered_containers.size() > 0:
			inventory_window.content.select_container(filtered_containers[0])

	# Reconnect signals
	_connect_window_signals()

	# Load saved position
	_load_and_apply_position()

	# Hide the window initially
	inventory_window.visible = false


func _hide_inventory():
	"""Hide the inventory window"""
	print("[InventoryIntegration] _hide_inventory called")

	if not inventory_window:
		return

	is_inventory_open = false
	inventory_window.visible = false

	# Save position
	_save_window_position()

	# Only restore player input and hide cursor if NO other UI windows are open
	if _should_restore_player_input():
		print("[InventoryIntegration] Restoring player input and hiding cursor")
		# Re-enable player input
		_set_player_input_enabled(true)
		# Restore mouse mode
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		print("[InventoryIntegration] NOT restoring input - other windows still open")

	# Emit signal
	inventory_toggled.emit(false)


func _refresh_inventory_display():
	"""Force refresh the inventory display"""
	if inventory_window and inventory_window.content and inventory_window.visible:
		# FIX: Synchronize container references before refreshing
		var correct_container = inventory_manager.get_player_inventory()
		if correct_container and inventory_window.content.current_container != correct_container:
			inventory_window.content.current_container = correct_container

			if inventory_window.content.inventory_grid:
				inventory_window.content.inventory_grid.set_container(correct_container)

			if inventory_window.content.list_view:
				inventory_window.content.list_view.set_container(correct_container, correct_container.container_id)

		inventory_window.content.refresh_display()

		# Also refresh the specific display mode
		if inventory_window.content.inventory_grid and inventory_window.content.inventory_grid.visible:
			inventory_window.content.inventory_grid.refresh_display()
		if inventory_window.content.list_view and inventory_window.content.list_view.visible:
			inventory_window.content.list_view.refresh_display()


func _connect_signals():
	"""Connect inventory manager signals"""
	if inventory_manager and inventory_manager.has_signal("item_added"):
		inventory_manager.item_added.connect(_on_item_added)
	if inventory_manager and inventory_manager.has_signal("item_removed"):
		inventory_manager.item_removed.connect(_on_item_removed)

	# Connect window signals
	_connect_window_signals()


func _connect_window_signals():
	"""Connect window-specific signals"""
	if not inventory_window:
		return

	if inventory_window.has_signal("window_closed"):
		# Disconnect first to avoid duplicate connections
		if inventory_window.window_closed.is_connected(_on_inventory_window_closed):
			inventory_window.window_closed.disconnect(_on_inventory_window_closed)
		inventory_window.window_closed.connect(_on_inventory_window_closed)


func _set_player_input_enabled(enabled: bool):
	"""Enable or disable player input"""
	var player_node = get_tree().get_first_node_in_group("player")
	if player_node and player_node.has_method("set_input_enabled"):
		player_node.set_input_enabled(enabled)


func _get_ui_manager():
	"""Get UIManager instance"""
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	if ui_managers.size() > 0:
		return ui_managers[0]
	return null


func _should_restore_player_input() -> bool:
	"""Check if player input should be restored (no UI windows open)"""
	var ui_manager = _get_ui_manager()
	if not ui_manager:
		print("[InventoryIntegration] No UI manager found, safe to restore input")
		return true  # No UI manager, safe to restore

	# Check if any UI windows are still open
	var all_windows = ui_manager.get_all_windows()
	var ui_windows_open = 0

	for window in all_windows:
		if not is_instance_valid(window):
			continue

		# Only count visible windows
		if window.visible:
			var window_type = window.get_meta("window_type", "")
			# Count all window types that require input disabled
			if window_type in ["main_inventory", "tearoff", "dialog", "crafting", "character", "equipment"]:
				ui_windows_open += 1
				print("[InventoryIntegration] Found open window: ", window.name, " (type: ", window_type, ")")

	var should_restore = ui_windows_open == 0
	print("[InventoryIntegration] Open UI windows: ", ui_windows_open, " - Should restore input: ", should_restore)
	return should_restore


func _load_and_apply_position():
	var loaded_pos = _load_window_position()
	if loaded_pos != Vector2i.ZERO and _is_position_valid(loaded_pos) and inventory_window:
		inventory_window.position = loaded_pos


func _save_window_position():
	if inventory_window:
		saved_position = inventory_window.position
		var file = FileAccess.open(position_save_file, FileAccess.WRITE)
		if file:
			file.store_var(saved_position)
			file.close()


func _load_window_position() -> Vector2i:
	if FileAccess.file_exists(position_save_file):
		var file = FileAccess.open(position_save_file, FileAccess.READ)
		if file:
			var loaded_pos = file.get_var()
			file.close()
			return loaded_pos
	return Vector2i.ZERO


func _is_position_valid(pos: Vector2i) -> bool:
	var viewport = get_viewport()
	if not viewport:
		return false

	var screen_size = viewport.get_visible_rect().size
	return pos.x >= 0 and pos.y >= 0 and pos.x < screen_size.x and pos.y < screen_size.y


# Signal handlers
func _on_item_added(_item: InventoryItem_Base, _container: InventoryContainer_Base):
	"""Handle item being added to inventory"""
	_refresh_inventory_display()


func _on_item_removed(_item: InventoryItem_Base, _container: InventoryContainer_Base):
	"""Handle item being removed from inventory"""
	_refresh_inventory_display()


func _on_inventory_window_closed():
	"""Handle inventory window being closed"""
	_hide_inventory()


# Public API
func toggle_inventory():
	"""Toggle inventory open/closed"""
	if is_inventory_open:
		_hide_inventory()
	else:
		_show_inventory()


func open_inventory():
	"""Open inventory"""
	if not is_inventory_open:
		_show_inventory()


func close_inventory():
	"""Close inventory"""
	if is_inventory_open:
		_hide_inventory()


func get_inventory_manager() -> InventoryManager:
	"""Get the inventory manager instance"""
	return inventory_manager


func get_inventory_window() -> InventoryWindow:
	"""Get the inventory window instance"""
	return inventory_window


func is_inventory_window_open() -> bool:
	"""Check if inventory window is open"""
	return is_inventory_open


