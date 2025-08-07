# AmmoPickup.gd
class_name AmmoPickup
extends PickupableItem

@export var ammo_name: String = "Pickupable Ammo"

func _configure_item_properties():
	# Set consistent properties for all ammo pickups
	item_id_override = "ammo_hybrid_charges"
	item_type_override = ItemTypes.Type.AMMUNITION
	item_name_override = "Hybrid Charges"
	item_description_override = "Standard ammunition for hybrid weapon systems."
	item_volume_override = 0.025
	item_mass_override = 0.01
	item_value_override = 1000.0
	item_quantity = 10
	icon_path_override = "res://assets/textures/ui/icons/ammo.png"

func _generate_item_data():
	"""Override to ensure ammunition has proper max_stack_size"""
	super._generate_item_data()
	
	if item_data:
		item_data.max_stack_size = 999999