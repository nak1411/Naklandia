# PickupableItem.gd - Updated to treat all items consistently
class_name PickupableItem
extends Interactable

# Item properties
@export var item_data: InventoryItem_Base
@export var auto_generate_item: bool = true
@export var item_type_override: ItemTypes.Type = ItemTypes.Type.MISCELLANEOUS
@export var item_name_override: String = ""
@export var item_description_override: String = ""
@export var item_volume_override: float = 1.0
@export var item_mass_override: float = 1.0
@export var item_value_override: float = 10.0
@export var item_quantity: int = 1
@export var icon_path_override: String = ""
@export var item_id_override: String = ""
@export var max_stack_size_override: int = 1

func _ready():
	super._ready()
	
	is_repeatable = false  # One time use
	
	# Allow derived classes to customize before generation
	_configure_item_properties()
	
	# Auto-generate item data if needed
	if auto_generate_item and not item_data:
		_generate_item_data()

	# Now set interaction properties with the proper item name
	if item_data:
		interaction_text = "Pick up " + item_data.item_name
	else:
		interaction_text = "Pick up Item"  # Fallback
	
	interaction_key = "E"
	is_repeatable = false  # One time use

# Virtual method - override in derived classes to set default properties
func _configure_item_properties():
	# Base implementation does nothing
	pass

func _generate_item_data():
	"""Generate item data based on export properties"""
	item_data = InventoryItem_Base.new()
	
	# Set the item ID first
	if not item_id_override.is_empty():
		item_data.item_id = item_id_override
	
	# Use overrides or generate from name
	if not item_name_override.is_empty():
		item_data.item_name = item_name_override
	else:
		item_data.item_name = name.replace("_", " ").capitalize()
	
	item_data.item_type = item_type_override
	item_data.description = item_description_override if not item_description_override.is_empty() else "A useful item."
	item_data.volume = item_volume_override
	item_data.mass = item_mass_override
	item_data.base_value = item_value_override
	item_data.quantity = item_quantity

	item_data.max_stack_size = max_stack_size_override
	
	# Set icon path if provided
	if not icon_path_override.is_empty():
		item_data.icon_path = icon_path_override

# Rest of your existing methods...
func _perform_interaction() -> bool:
	"""Handle pickup interaction"""
	if not item_data:
		push_error("PickupableItem: No item data configured!")
		return false
	
	var player = get_player_reference()
	if not player:
		push_warning("PickupableItem: No player found!")
		return false
	
	# Get the inventory integration from player
	var inventory_integration = player.get_node_or_null("InventoryIntegration")
	if not inventory_integration:
		push_warning("PickupableItem: Player doesn't have InventoryIntegration!")
		return false
	
	# Get the inventory manager
	var inventory_manager = inventory_integration.inventory_manager
	if not inventory_manager:
		push_warning("PickupableItem: No inventory manager found!")
		return false
	
	# Get the player inventory
	var player_inventory = inventory_manager.get_player_inventory()
	if not player_inventory:
		push_warning("PickupableItem: No player inventory found!")
		return false
	
	# Check if we can add the item first
	if not player_inventory.can_add_item(item_data):
		print("Inventory is full or cannot accept this item!")
		return false
	
	# Try to add the item (returns bool, not remaining quantity)
	var success = player_inventory.add_item(item_data)
	
	if success:
		# Item was successfully added to inventory
		print("Picked up: ", item_data.item_name, " (x", item_data.quantity, ")")
		
		# Remove from world
		queue_free()
		return true
	else:
		# Failed to add item
		print("Failed to pick up item!")
		return false