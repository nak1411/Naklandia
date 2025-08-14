# ResourcePickup.gd
class_name ResourcePickup
extends PickupableItem

@export var resource_name: String = "Pickupable Resource"
@export var resource_quantity: int = 500


func _configure_item_properties():
	# Set consistent properties for all ammo pickups
	item_id_override = "resource_noxite"
	item_type_override = ItemTypes.Type.RESOURCE
	item_name_override = "Noxite"
	item_description_override = "A liquid that can be used as a fuel source."
	item_volume_override = 0.125
	item_mass_override = 0.1
	item_value_override = 10.0
	item_quantity = 1
	icon_path_override = "res://assets/textures/ui/icons/resource.png"


func _generate_item_data():
	"""Override to ensure resource has proper max_stack_size"""
	super._generate_item_data()

	if item_data:
		item_data.max_stack_size = 999999
