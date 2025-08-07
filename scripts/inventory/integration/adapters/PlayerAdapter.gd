# integration/adapters/PlayerAdapter.gd
# Interface between inventory system and player
class_name PlayerAdapter
extends Node

var event_bus: InventoryEventBus
var connected_player: Player
var player_inventory_component: Node

func _ready():
	name = "PlayerAdapter"

func setup_event_connections(bus: InventoryEventBus):
	"""Connect this adapter to the event bus"""
	event_bus = bus
	
	# Listen for inventory events that affect player
	if event_bus:
		event_bus.inventory_opened.connect(_on_inventory_opened)
		event_bus.inventory_closed.connect(_on_inventory_closed)
		event_bus.item_used.connect(_on_item_used)
		event_bus.item_equipped.connect(_on_item_equipped)
		event_bus.item_unequipped.connect(_on_item_unequipped)

func connect_to_player(player: Player):
	"""Connect to the player system"""
	connected_player = player
	
	# Connect to player signals if they exist
	if player.has_signal("state_changed"):
		player.state_changed.connect(_on_player_state_changed)
	
	# Look for inventory component on player
	player_inventory_component = player.get_node_or_null("InventoryComponent")
	
	# Connect interaction system if available
	var interaction_system = player.get_interaction_system()
	if interaction_system:
		interaction_system.interaction_performed.connect(_on_player_interaction)

# Player event handlers
func _on_player_state_changed(new_state):
	"""Handle player state changes"""
	if event_bus:
		event_bus.emit_signal("player_state_changed", str(new_state))

func _on_player_interaction(interactable: Node):
	"""Handle player interactions"""
	if event_bus:
		event_bus.emit_player_interaction_started(interactable)
		
	# Check if interaction is with an inventory container
	if interactable.has_method("get_container_data"):
		var container_data = interactable.get_container_data()
		if event_bus:
			event_bus.emit_container_opened(container_data.get("id", "unknown"))

# Inventory event handlers
func _on_inventory_opened():
	"""Handle inventory opening - may need to affect player state"""
	if connected_player and connected_player.has_method("set_input_enabled"):
		# Disable player movement when inventory is open
		connected_player.set_input_enabled(false)

func _on_inventory_closed():
	"""Handle inventory closing - restore player state"""
	if connected_player and connected_player.has_method("set_input_enabled"):
		# Re-enable player movement when inventory closes
		connected_player.set_input_enabled(true)

func _on_item_used(item_data: Dictionary):
	"""Handle item usage - may affect player stats or state"""
	if not connected_player:
		return
		
	var item_type = item_data.get("type", "")
	var item_id = item_data.get("id", "")
	
	# Handle different item types
	match item_type:
		"consumable":
			_handle_consumable_use(item_data)
		"tool":
			_handle_tool_use(item_data)
		"weapon":
			_handle_weapon_use(item_data)

func _handle_consumable_use(item_data: Dictionary):
	"""Handle consumable item effects on player"""
	var effects = item_data.get("effects", {})
	
	# Apply health effects
	if effects.has("health"):
		if connected_player.has_method("modify_health"):
			connected_player.modify_health(effects["health"])
	
	# Apply stamina effects
	if effects.has("stamina"):
		if connected_player.has_method("modify_stamina"):
			connected_player.modify_stamina(effects["stamina"])

func _handle_tool_use(item_data: Dictionary):
	"""Handle tool usage"""
	# Tools might modify player capabilities temporarily
	pass

func _handle_weapon_use(item_data: Dictionary):
	"""Handle weapon usage"""
	# Weapons might change player combat state
	pass

func _on_item_equipped(item_data: Dictionary):
	"""Handle item equipment - may modify player stats"""
	if not connected_player:
		return
		
	# Apply equipment bonuses
	var bonuses = item_data.get("bonuses", {})
	if connected_player.has_method("apply_equipment_bonuses"):
		connected_player.apply_equipment_bonuses(bonuses)

func _on_item_unequipped(item_data: Dictionary):
	"""Handle item unequipment - remove bonuses"""
	if not connected_player:
		return
		
	# Remove equipment bonuses
	var bonuses = item_data.get("bonuses", {})
	if connected_player.has_method("remove_equipment_bonuses"):
		connected_player.remove_equipment_bonuses(bonuses)

# Public interface
func get_player_position() -> Vector3:
	"""Get current player position"""
	if connected_player:
		return connected_player.global_position
	return Vector3.ZERO

func get_player_state():
	"""Get current player state"""
	if connected_player and connected_player.has_method("get_current_state"):
		return connected_player.get_current_state()
	return null

func is_player_in_range(position: Vector3, max_distance: float) -> bool:
	"""Check if player is within range of a position"""
	if connected_player:
		var distance = connected_player.global_position.distance_to(position)
		return distance <= max_distance
	return false