# ModulePickup.gd
class_name ModulePickup
extends PickupableItem

@export var module_name: String = "Pickupable Module"

func _configure_item_properties():
	# Set consistent properties for all ammo pickups
	item_id_override = "module_gauss_turret"
	item_type_override = InventoryItem_Base.ItemType.MODULE
	item_name_override = "Gauss Turret"
	item_description_override = "Turret firing a high velocity solid charge."
	item_volume_override = 3.62
	item_mass_override = 0.125
	item_value_override = 50000.0
	item_quantity = 1
	icon_path_override = "res://assets/textures/ui/icons/module.png"

func _generate_item_data():
	"""Override to ensure module has proper max_stack_size"""
	super._generate_item_data()
	
	if item_data:
		item_data.max_stack_size = 999999