# BlueprintPickup.gd
class_name BlueprintPickup
extends PickupableItem

@export var blueprint_name: String = "Pickupable Module"

func _configure_item_properties():
	# Set consistent properties for all ammo pickups
	item_id_override = "blueprint_hybrid_charges"
	item_type_override = InventoryItem_Base.ItemType.BLUEPRINT
	item_name_override = "Hybrid Charge Blueprint"
	item_description_override = "Blueprint for manufacturing Hybrid Charges."
	item_volume_override = 0.015
	item_mass_override = 0.01
	item_value_override = 100000.0
	item_quantity = 1
	icon_path_override = "res://assets/textures/ui/icons/blueprint.png"

func _generate_item_data():
	"""Override to ensure blueprint has proper max_stack_size"""
	super._generate_item_data()
	
	if item_data:
		item_data.max_stack_size = 999999