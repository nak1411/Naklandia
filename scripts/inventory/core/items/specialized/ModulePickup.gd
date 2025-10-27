# ModulePickup.gd
class_name ModulePickup
extends PickupableItem

@export var module_name: String = "Pickupable Module"  # For backward compatibility with scenes
@export var item_id: String = "module_gauss_turret"
@export var pickup_quantity: int = 1


func _configure_item_properties():
	var item_database = get_node_or_null("/root/ItemDatabase")
	if not item_database:
		push_error("ModulePickup: ItemDatabase singleton not found! Make sure it's set up as an AutoLoad.")
		return

	var item_def = item_database.get_item(item_id)

	if not item_def:
		push_error("ModulePickup: Item not found in database: " + item_id)
		return

	item_id_override = item_def.item_id
	item_type_override = item_def.item_type
	item_name_override = item_def.name
	item_description_override = item_def.description
	item_volume_override = item_def.volume
	item_mass_override = item_def.mass
	item_value_override = item_def.value
	item_quantity = pickup_quantity
	icon_path_override = item_def.icon_path
	max_stack_size_override = item_def.max_stack_size


func _generate_item_data():
	"""Override to ensure module has proper max_stack_size"""
	super._generate_item_data()

	if item_data:
		item_data.max_stack_size = 999999
