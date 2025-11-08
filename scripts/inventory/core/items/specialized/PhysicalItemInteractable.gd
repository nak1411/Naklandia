# PhysicalItemInteractable.gd
# Script for the Area3D child of PhysicalItem that handles E key interaction
extends Interactable

var physical_item: PhysicalItem = null


func _ready():
	super._ready()

	if not physical_item:
		physical_item = get_parent() as PhysicalItem

	if physical_item:
		interaction_text = "Pick up " + physical_item.item_name
		interaction_key = "E"
		is_repeatable = false
		interaction_cooldown = 0.5
	else:
		push_error("PhysicalItemInteractable: No PhysicalItem parent found!")


func _perform_interaction() -> bool:
	"""Called when player presses E on this item."""
	if not physical_item:
		return false

	var player = get_player_reference()
	if not player:
		return false

	# Call the PhysicalItem's inventory pickup function
	return physical_item.pickup_to_inventory(player)


func get_player_reference() -> Node:
	"""Get reference to the player node."""
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null
