# integration/InventoryIntegration.gd
# Simplified combined integration system
class_name InventoryIntegration
extends Node

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

# Signals
signal inventory_toggled(is_open: bool)
signal setup_completed()

func _ready():
	name = "InventoryIntegration"
	process_mode = Node.PROCESS_MODE_ALWAYS
		
	# Setup integration layer first
	_setup_integration_layer()
	
	# Then setup original inventory system
	call_deferred("_setup_original_inventory_system")

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
	
	# Create inventory manager
	inventory_manager = InventoryManager.new()
	inventory_manager.name = "InventoryManager"
	add_child(inventory_manager)
	inventory_manager.load_inventory()
	
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
			print("InventoryIntegration: Registering main inventory window with UIManager")
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
	
	print("InventoryIntegration: Setup complete!")

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
	if not inventory_window or not setup_complete:
		print("InventoryIntegration: Cannot show inventory - not ready")
		return
		
	is_inventory_open = true
	inventory_window.visible = true
	inventory_window.move_to_front()
	
	# Disable player input
	_set_player_input_enabled(false)
	
	# Set mouse mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Emit signal
	inventory_toggled.emit(true)

func _hide_inventory():
	"""Hide the inventory window"""
	if not inventory_window:
		return
		
	is_inventory_open = false
	inventory_window.visible = false
	
	# Save position
	_save_window_position()
	
	# Re-enable player input
	_set_player_input_enabled(true)
	
	# Restore mouse mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Emit signal
	inventory_toggled.emit(false)

func _refresh_inventory_display():
	"""Force refresh the inventory display"""
	if inventory_window and inventory_window.content and inventory_window.visible:
		print("Forcing inventory display refresh...")
		
		# FIX: Synchronize container references before refreshing
		var correct_container = inventory_manager.get_player_inventory()
		if correct_container and inventory_window.content.current_container != correct_container:
			print("Synchronizing container references...")
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
	if inventory_window:
		if inventory_window.has_signal("window_closed"):
			inventory_window.window_closed.connect(_on_window_closed)
		if inventory_window.has_signal("container_switched"):
			inventory_window.container_switched.connect(_on_container_switched)

func _set_player_input_enabled(enabled: bool):
	"""Enable or disable player input"""
	var player_node = get_tree().get_first_node_in_group("player")
	if player_node and player_node.has_method("set_input_enabled"):
		player_node.set_input_enabled(enabled)

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
func _on_item_added(_item_id: String, _quantity: int):
	pass

func _on_item_removed(_item_id: String, _quantity: int):
	pass

func _on_container_switched(_container: InventoryContainer_Base):
	pass

func _on_window_closed():
	"""Handle window being closed"""
	if event_bus:
		event_bus.emit_inventory_closed()

func _is_pause_menu_open() -> bool:
	"""Check if pause menu is currently open"""
	var ui_manager = get_tree().get_first_node_in_group("ui_manager")
	if ui_manager and ui_manager.has_method("is_any_overlay_visible"):
		return ui_manager.is_any_overlay_visible()
	return false

func set_integration_enabled(enabled: bool):
	"""Enable/disable integration system processing"""
	if ui_input_adapter:
		ui_input_adapter.set_input_processing_enabled(enabled)
	
	# Also disable event processing in event handlers
	if event_handlers:
		event_handlers.set_process_mode(Node.PROCESS_MODE_DISABLED if not enabled else Node.PROCESS_MODE_INHERIT)

# Public interface methods
func is_inventory_window_open() -> bool:
	return is_inventory_open and inventory_window != null and inventory_window.visible

func get_inventory_window() -> InventoryWindow:
	return inventory_window

func get_inventory_manager() -> InventoryManager:
	return inventory_manager

func close_inventory():
	if event_bus:
		event_bus.emit_inventory_closed()

func open_inventory():
	if event_bus:
		event_bus.emit_inventory_opened()

func get_event_bus() -> InventoryEventBus:
	return event_bus

func get_player_adapter() -> PlayerAdapter:
	return player_adapter

func get_ui_input_adapter():
	"""Get reference to UI input adapter"""
	return ui_input_adapter