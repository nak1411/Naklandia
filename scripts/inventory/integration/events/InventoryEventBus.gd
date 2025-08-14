# Central event coordination for inventory system
class_name InventoryEventBus
extends Node

# Integration events
signal integration_ready
signal integration_shutdown

# Inventory events
signal inventory_opened
signal inventory_closed
signal inventory_state_changed(state: String)

# Item events
signal item_picked_up(item_data: Dictionary)
signal item_dropped(item_data: Dictionary)
signal item_used(item_data: Dictionary)
signal item_equipped(item_data: Dictionary)
signal item_unequipped(item_data: Dictionary)

# Container events
signal container_opened(container_id: String)
signal container_closed(container_id: String)
signal item_moved(from_container: String, to_container: String, item_data: Dictionary)

# Player events
signal player_interaction_started(target: Node)
signal player_interaction_ended
signal player_state_changed(state: String)

# UI events
signal ui_focus_changed(has_focus: bool)
signal ui_input_mode_changed(mode: String)

# Game state events
signal game_paused
signal game_unpaused
signal save_requested
signal load_requested

var event_throttle: Dictionary = {}
var throttle_time: float = 0.016  # ~60fps throttling


func _ready():
	name = "InventoryEventBus"
	add_to_group("inventory_event_bus")


# Event emission helpers
func emit_integration_ready():
	integration_ready.emit()


func emit_inventory_opened():
	inventory_opened.emit()


func emit_inventory_closed():
	inventory_closed.emit()


func emit_item_picked_up(item_data: Dictionary):
	item_picked_up.emit(item_data)


func emit_item_dropped(item_data: Dictionary):
	item_dropped.emit(item_data)


func emit_item_used(item_data: Dictionary):
	item_used.emit(item_data)


func emit_container_opened(container_id: String):
	container_opened.emit(container_id)


func emit_container_closed(container_id: String):
	container_closed.emit(container_id)


func emit_player_interaction_started(target: Node):
	player_interaction_started.emit(target)


func emit_player_interaction_ended():
	player_interaction_ended.emit()


func emit_ui_focus_changed(has_focus: bool):
	if _should_emit_event("ui_focus_changed"):
		ui_focus_changed.emit(has_focus)


func emit_inventory_state_changed(state: String):
	inventory_state_changed.emit(state)


func emit_item_equipped(item_data: Dictionary):
	item_equipped.emit(item_data)


func emit_item_unequipped(item_data: Dictionary):
	item_unequipped.emit(item_data)


func emit_item_moved(from_container: String, to_container: String, item_data: Dictionary):
	item_moved.emit(from_container, to_container, item_data)


func emit_save_requested():
	save_requested.emit()


func emit_load_requested():
	load_requested.emit()


func emit_game_paused():
	game_paused.emit()


func emit_game_unpaused():
	game_unpaused.emit()


# Event subscription helpers
func subscribe_to_inventory_events(subscriber: Node, callback_prefix: String = "_on_inventory_"):
	"""Subscribe a node to all inventory events with automatic callback naming"""
	if subscriber.has_method(callback_prefix + "opened"):
		inventory_opened.connect(subscriber.get(callback_prefix + "opened"))

	if subscriber.has_method(callback_prefix + "closed"):
		inventory_closed.connect(subscriber.get(callback_prefix + "closed"))

	if subscriber.has_method(callback_prefix + "state_changed"):
		inventory_state_changed.connect(subscriber.get(callback_prefix + "state_changed"))


func subscribe_to_item_events(subscriber: Node, callback_prefix: String = "_on_item_"):
	"""Subscribe a node to all item events"""
	if subscriber.has_method(callback_prefix + "picked_up"):
		item_picked_up.connect(subscriber.get(callback_prefix + "picked_up"))

	if subscriber.has_method(callback_prefix + "dropped"):
		item_dropped.connect(subscriber.get(callback_prefix + "dropped"))

	if subscriber.has_method(callback_prefix + "used"):
		item_used.connect(subscriber.get(callback_prefix + "used"))


func _should_emit_event(event_name: String) -> bool:
	"""Check if event should be emitted based on throttling"""
	var current_time = Time.get_time_dict_from_system()["second"] + Time.get_time_dict_from_system()["millisecond"] / 1000.0

	if not event_throttle.has(event_name):
		event_throttle[event_name] = current_time
		return true

	var last_time = event_throttle[event_name]
	if current_time - last_time >= throttle_time:
		event_throttle[event_name] = current_time
		return true

	return false


# Cleanup
func cleanup():
	# Disconnect all signals
	for connection in get_signal_list():
		if is_connected(connection.name, Callable()):
			disconnect(connection.name, Callable())
