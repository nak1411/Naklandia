# integration/events/GameEventHandlers.gd
# Handles game-wide event responses for inventory system
class_name GameEventHandlers
extends Node

var event_bus: InventoryEventBus
var integration: InventoryIntegration

# Handler state
var active_handlers: Dictionary = {}
var event_history: Array = []
var max_history_size: int = 100


func _ready():
	name = "GameEventHandlers"


func setup(bus: InventoryEventBus, integration_ref: InventoryIntegration):
	"""Initialize handlers with event bus and integration references"""
	event_bus = bus
	integration = integration_ref

	if event_bus:
		_connect_all_handlers()
		_register_custom_handlers()


func _connect_all_handlers():
	"""Connect all event handlers to the event bus"""
	# Integration events
	event_bus.integration_ready.connect(_on_integration_ready)
	event_bus.integration_shutdown.connect(_on_integration_shutdown)

	# Inventory events
	event_bus.inventory_opened.connect(_on_inventory_opened)
	event_bus.inventory_closed.connect(_on_inventory_closed)
	event_bus.inventory_state_changed.connect(_on_inventory_state_changed)

	# Item events
	event_bus.item_picked_up.connect(_on_item_picked_up)
	event_bus.item_dropped.connect(_on_item_dropped)
	event_bus.item_used.connect(_on_item_used)
	event_bus.item_equipped.connect(_on_item_equipped)
	event_bus.item_unequipped.connect(_on_item_unequipped)

	# Container events
	event_bus.container_opened.connect(_on_container_opened)
	event_bus.container_closed.connect(_on_container_closed)
	event_bus.item_moved.connect(_on_item_moved)

	# Player events
	event_bus.player_interaction_started.connect(_on_player_interaction_started)
	event_bus.player_interaction_ended.connect(_on_player_interaction_ended)
	event_bus.player_state_changed.connect(_on_player_state_changed)

	# UI events
	event_bus.ui_focus_changed.connect(_on_ui_focus_changed)
	event_bus.ui_input_mode_changed.connect(_on_ui_input_mode_changed)

	# Game state events
	event_bus.game_paused.connect(_on_game_paused)
	event_bus.game_unpaused.connect(_on_game_unpaused)


func _register_custom_handlers():
	"""Register custom event handler combinations"""
	# Register compound event handlers
	active_handlers["inventory_session"] = false
	active_handlers["interaction_session"] = false
	active_handlers["item_transfer_session"] = false


# Integration event handlers
func _on_integration_ready():
	"""Handle integration system ready"""
	_log_event("integration_ready")
	print("GameEventHandlers: Integration system ready")

	# Perform any initialization that requires all systems to be ready
	_initialize_cross_system_features()


func _on_integration_shutdown():
	"""Handle integration system shutdown"""
	_log_event("integration_shutdown")
	_cleanup_handlers()


# Inventory event handlers
func _on_inventory_opened():
	"""Handle inventory opening"""
	_log_event("inventory_opened")
	active_handlers["inventory_session"] = true

	# Trigger related systems
	_handle_inventory_session_start()


func _on_inventory_closed():
	"""Handle inventory closing"""
	_log_event("inventory_closed")
	active_handlers["inventory_session"] = false

	# Trigger cleanup
	_handle_inventory_session_end()


func _on_inventory_state_changed(state: String):
	"""Handle inventory state changes"""
	_log_event("inventory_state_changed", {"state": state})


# Item event handlers
func _on_item_picked_up(item_data: Dictionary):
	"""Handle item pickup"""
	_log_event("item_picked_up", item_data)

	# Play pickup effects
	_trigger_pickup_effects(item_data)

	# Update game statistics
	_update_pickup_stats(item_data)


func _on_item_dropped(item_data: Dictionary):
	"""Handle item dropping"""
	_log_event("item_dropped", item_data)

	# Play drop effects
	_trigger_drop_effects(item_data)

	# Handle world item spawning if needed
	_spawn_world_item(item_data)


func _on_item_used(item_data: Dictionary):
	"""Handle item usage"""
	_log_event("item_used", item_data)

	# Play usage effects
	_trigger_usage_effects(item_data)

	# Handle item consumption
	_handle_item_consumption(item_data)


func _on_item_equipped(item_data: Dictionary):
	"""Handle item equipment"""
	_log_event("item_equipped", item_data)

	# Play equip effects
	_trigger_equip_effects(item_data)

	# Update player visuals if applicable
	_update_player_equipment_visuals(item_data, true)


func _on_item_unequipped(item_data: Dictionary):
	"""Handle item unequipment"""
	_log_event("item_unequipped", item_data)

	# Play unequip effects
	_trigger_unequip_effects(item_data)

	# Update player visuals
	_update_player_equipment_visuals(item_data, false)


# Container event handlers
func _on_container_opened(container_id: String):
	"""Handle container opening"""
	_log_event("container_opened", {"container_id": container_id})

	# Play container open sound/animation
	_trigger_container_effects(container_id, "open")


func _on_container_closed(container_id: String):
	"""Handle container closing"""
	_log_event("container_closed", {"container_id": container_id})

	# Play container close sound/animation
	_trigger_container_effects(container_id, "close")


func _on_item_moved(from_container: String, to_container: String, item_data: Dictionary):
	"""Handle item movement between containers"""
	_log_event("item_moved", {"from": from_container, "to": to_container, "item": item_data})

	# Play move sound
	_trigger_item_move_effects(item_data)


# Player event handlers
func _on_player_interaction_started(target: Node):
	"""Handle player interaction start"""
	_log_event("player_interaction_started", {"target": target.name})
	active_handlers["interaction_session"] = true

	# Handle interaction UI updates
	_update_interaction_ui(target, true)


func _on_player_interaction_ended():
	"""Handle player interaction end"""
	_log_event("player_interaction_ended")
	active_handlers["interaction_session"] = false

	# Clean up interaction UI
	_update_interaction_ui(null, false)


func _on_player_state_changed(state: String):
	"""Handle player state changes"""
	_log_event("player_state_changed", {"state": state})

	# Update UI elements based on player state
	_update_ui_for_player_state(state)


# UI event handlers
func _on_ui_focus_changed(has_focus: bool):
	"""Handle UI focus changes"""
	_log_event("ui_focus_changed", {"has_focus": has_focus})


func _on_ui_input_mode_changed(mode: String):
	"""Handle UI input mode changes"""
	_log_event("ui_input_mode_changed", {"mode": mode})

	# Update system behaviors based on input mode
	_adapt_to_input_mode(mode)


# Game state event handlers
func _on_game_paused():
	"""Handle game pause"""
	_log_event("game_paused")

	# Pause inventory-related systems
	_pause_inventory_systems()


func _on_game_unpaused():
	"""Handle game unpause"""
	_log_event("game_unpaused")

	# Resume inventory-related systems
	_resume_inventory_systems()


# Implementation methods
func _initialize_cross_system_features():
	"""Initialize features that require multiple systems"""
	# Set up auto-save triggers
	_setup_autosave_triggers()

	# Initialize performance monitoring
	_setup_performance_monitoring()


func _handle_inventory_session_start():
	"""Handle start of inventory session"""
	# Disable certain game systems while inventory is open
	var game_systems = get_tree().get_nodes_in_group("pausable_systems")
	for system in game_systems:
		if system.has_method("set_paused"):
			system.set_paused(true)


func _handle_inventory_session_end():
	"""Handle end of inventory session"""
	# Re-enable game systems
	var game_systems = get_tree().get_nodes_in_group("pausable_systems")
	for system in game_systems:
		if system.has_method("set_paused"):
			system.set_paused(false)


func _trigger_pickup_effects(item_data: Dictionary):
	"""Trigger visual/audio effects for item pickup"""
	# Play pickup sound
	if integration and integration.get_player_adapter():
		var player_pos = integration.get_player_adapter().get_player_position()
		_play_sound_at_position("item_pickup", player_pos)

	# Trigger pickup particle effect
	_spawn_pickup_particles(item_data)


func _trigger_drop_effects(_item_data: Dictionary):
	"""Trigger visual/audio effects for item dropping"""
	if integration and integration.get_player_adapter():
		var player_pos = integration.get_player_adapter().get_player_position()
		_play_sound_at_position("item_drop", player_pos)


func _trigger_usage_effects(item_data: Dictionary):
	"""Trigger effects for item usage"""
	var effect_type = item_data.get("effect_type", "generic")
	_play_sound_at_position("item_use_" + effect_type, Vector3.ZERO)


func _trigger_equip_effects(item_data: Dictionary):
	"""Trigger equipment effects"""
	var item_type = item_data.get("type", "generic")
	_play_sound_at_position("item_equip_" + item_type, Vector3.ZERO)


func _trigger_unequip_effects(item_data: Dictionary):
	"""Trigger unequipment effects"""
	var item_type = item_data.get("type", "generic")
	_play_sound_at_position("item_unequip_" + item_type, Vector3.ZERO)


func _update_player_equipment_visuals(item_data: Dictionary, equipped: bool):
	"""Update player visual equipment"""
	# This would connect to your player's equipment visual system
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("update_equipment_visual"):
		player.update_equipment_visual(item_data, equipped)


func _trigger_container_effects(_container_id: String, action: String):
	"""Trigger container interaction effects"""
	var sound_name = "container_" + action
	_play_sound_at_position(sound_name, Vector3.ZERO)


func _trigger_item_move_effects(_item_data: Dictionary):
	"""Trigger item movement effects"""
	_play_sound_at_position("item_move", Vector3.ZERO)


func _update_interaction_ui(target: Node, show: bool):
	"""Update interaction UI elements"""
	var ui_manager = get_tree().get_first_node_in_group("ui_manager")
	if ui_manager and ui_manager.has_method("show_interaction_prompt"):
		if show and target:
			var prompt_text = _get_interaction_prompt(target)
			ui_manager.show_interaction_prompt(prompt_text)
		else:
			ui_manager.hide_interaction_prompt()


func _get_interaction_prompt(target: Node) -> String:
	"""Get interaction prompt text for target"""
	if target.has_method("get_interaction_text"):
		return target.get_interaction_text()
	return "Press E to interact"


func _update_ui_for_player_state(state: String):
	"""Update UI elements based on player state"""
	var ui_manager = get_tree().get_first_node_in_group("ui_manager")
	if ui_manager and ui_manager.has_method("update_for_player_state"):
		ui_manager.update_for_player_state(state)


func _adapt_to_input_mode(mode: String):
	"""Adapt system behaviors to input mode"""
	match mode:
		"inventory":
			# Pause
			_pause_game_systems()
		"game":
			# Restore normal time scale
			_resume_game_systems()
		"menu":
			# Pause game systems
			_pause_game_systems()


func _pause_inventory_systems():
	"""Pause inventory-related systems"""
	var inventory_systems = get_tree().get_nodes_in_group("inventory_systems")
	for system in inventory_systems:
		if system.has_method("pause"):
			system.pause()


func _resume_inventory_systems():
	"""Resume inventory-related systems"""
	var inventory_systems = get_tree().get_nodes_in_group("inventory_systems")
	for system in inventory_systems:
		if system.has_method("resume"):
			system.resume()


func _pause_game_systems():
	"""Pause specific game systems instead of engine time scale"""
	# Pause enemy AI, physics simulations, etc.
	var pausable_systems = get_tree().get_nodes_in_group("pausable_systems")
	for system in pausable_systems:
		if system.has_method("set_paused"):
			system.set_paused(true)


func _resume_game_systems():
	"""Resume specific game systems"""
	var pausable_systems = get_tree().get_nodes_in_group("pausable_systems")
	for system in pausable_systems:
		if system.has_method("set_paused"):
			system.set_paused(false)


func _setup_autosave_triggers():
	"""Set up automatic save triggers"""
	# Auto-save when significant inventory changes occur


func _setup_performance_monitoring():
	"""Set up performance monitoring for inventory operations"""


func _spawn_pickup_particles(_item_data: Dictionary):
	"""Spawn particle effects for item pickup"""
	# Implementation would depend on your particle system


func _spawn_world_item(_item_data: Dictionary):
	"""Spawn item in the world when dropped"""
	# This would connect to your world item spawning system


func _handle_item_consumption(_item_data: Dictionary):
	"""Handle item consumption logic"""


func _update_pickup_stats(_item_data: Dictionary):
	"""Update game statistics for item pickup"""
	# Update player stats, achievements, etc.


func _play_sound_at_position(sound_name: String, position: Vector3):
	"""Play a sound effect at a specific position"""
	# This would connect to your audio system
	var audio_manager = get_tree().get_first_node_in_group("audio_manager")
	if audio_manager and audio_manager.has_method("play_sound_at_position"):
		audio_manager.play_sound_at_position(sound_name, position)


func _log_event(event_name: String, data: Dictionary = {}):
	"""Log event for debugging/monitoring"""
	var event_data = {"event": event_name, "timestamp": Time.get_unix_time_from_system(), "data": data}

	event_history.append(event_data)

	# Keep history size manageable
	if event_history.size() > max_history_size:
		event_history.pop_front()


func _cleanup_handlers():
	"""Clean up handler state"""
	active_handlers.clear()
	event_history.clear()


# Public interface
func get_event_history() -> Array:
	"""Get recent event history for debugging"""
	return event_history.duplicate()


func is_handler_active(handler_name: String) -> bool:
	"""Check if a specific handler is currently active"""
	return active_handlers.get(handler_name, false)


func get_active_handlers() -> Dictionary:
	"""Get all currently active handlers"""
	return active_handlers.duplicate()
