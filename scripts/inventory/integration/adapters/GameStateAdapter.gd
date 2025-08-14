# integration/adapters/GameStateAdapter.gd
# Interface between inventory system and game state
class_name GameStateAdapter
extends Node

var event_bus: InventoryEventBus
var connected_game_state: Node


func _ready():
	name = "GameStateAdapter"


func setup_event_connections(bus: InventoryEventBus):
	"""Connect this adapter to the event bus"""
	event_bus = bus

	# Listen for events that affect game state
	if event_bus:
		event_bus.save_requested.connect(_on_save_requested)
		event_bus.load_requested.connect(_on_load_requested)
		event_bus.inventory_opened.connect(_on_inventory_opened)
		event_bus.inventory_closed.connect(_on_inventory_closed)


func connect_to_game_state(game_state: Node):
	"""Connect to the game state management system"""
	connected_game_state = game_state

	# Connect to game state signals
	if game_state.has_signal("game_paused"):
		game_state.game_paused.connect(_on_game_paused)

	if game_state.has_signal("game_unpaused"):
		game_state.game_unpaused.connect(_on_game_unpaused)

	if game_state.has_signal("save_completed"):
		game_state.save_completed.connect(_on_save_completed)

	if game_state.has_signal("load_completed"):
		game_state.load_completed.connect(_on_load_completed)


# Game state event handlers
func _on_game_paused():
	"""Handle game pause"""
	if event_bus:
		event_bus.emit_game_paused()


func _on_game_unpaused():
	"""Handle game unpause"""
	if event_bus:
		event_bus.emit_game_unpaused()


func _on_save_completed():
	"""Handle save completion"""
	# Notify inventory system that save is complete


func _on_load_completed():
	"""Handle load completion"""
	# Notify inventory system that load is complete


# Inventory event handlers
func _on_inventory_opened():
	"""Handle inventory opening - may pause game"""
	if connected_game_state and connected_game_state.has_method("request_pause"):
		connected_game_state.request_pause("inventory_open")


func _on_inventory_closed():
	"""Handle inventory closing - may unpause game"""
	if connected_game_state and connected_game_state.has_method("request_unpause"):
		connected_game_state.request_unpause("inventory_open")


func _on_save_requested():
	"""Handle save requests from inventory"""
	if connected_game_state and connected_game_state.has_method("save_game"):
		connected_game_state.save_game("inventory_save")


func _on_load_requested():
	"""Handle load requests from inventory"""
	if connected_game_state and connected_game_state.has_method("load_game"):
		connected_game_state.load_game()


# Public interface
func get_game_data() -> Dictionary:
	"""Get current game state data"""
	if connected_game_state and connected_game_state.has_method("get_save_data"):
		return connected_game_state.get_save_data()
	return {}


func set_game_data(data: Dictionary):
	"""Set game state data"""
	if connected_game_state and connected_game_state.has_method("load_save_data"):
		connected_game_state.load_save_data(data)


func is_game_paused() -> bool:
	"""Check if game is currently paused"""
	if connected_game_state and connected_game_state.has_method("is_paused"):
		return connected_game_state.is_paused()
	return false
