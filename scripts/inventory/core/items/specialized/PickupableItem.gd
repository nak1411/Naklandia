class_name PickupableItem
extends Interactable

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

var last_failed_attempt: float = 0.0
var failure_cooldown: float = 2.0


func _ready():
	super._ready()

	is_repeatable = false
	interaction_cooldown = 0.5

	_configure_item_properties()

	if auto_generate_item and not item_data:
		_generate_item_data()

	if item_data:
		interaction_text = "Pick up " + item_data.item_name
	else:
		interaction_text = "Pick up Item"

	interaction_key = "E"
	is_repeatable = false


func _configure_item_properties():
	pass


func _generate_item_data():
	item_data = InventoryItem_Base.new()

	if not item_id_override.is_empty():
		item_data.item_id = item_id_override

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

	if not icon_path_override.is_empty():
		item_data.icon_path = icon_path_override

	# CRITICAL: Set equipment_category metadata
	_set_equipment_category(item_data)


func _set_equipment_category(item: InventoryItem_Base):
	"""Set equipment_category metadata based on item type"""
	match item.item_type:
		ItemTypes.Type.WEAPON:
			item.set_meta("equipment_category", "weapon")
		ItemTypes.Type.TOOL:
			item.set_meta("equipment_category", "tool")
		ItemTypes.Type.ARMOR:
			item.set_meta("equipment_category", "armor")
		ItemTypes.Type.AMMUNITION:
			item.set_meta("equipment_category", "ammunition")
		ItemTypes.Type.IMPLANT:
			item.set_meta("equipment_category", "accessory")
		_:
			pass


func _perform_interaction() -> bool:
	if not item_data:
		print("ERROR: No item data configured!")
		push_error("PickupableItem: No item data configured!")
		return false

	var player = get_player_reference()
	if not player:
		print("ERROR: No player found!")
		push_warning("PickupableItem: No player found!")
		return false

	var inventory_integration = player.get_node_or_null("InventoryIntegration")
	if not inventory_integration:
		print("ERROR: Player doesn't have InventoryIntegration!")
		push_warning("PickupableItem: Player doesn't have InventoryIntegration!")
		return false

	var inventory_manager = inventory_integration.inventory_manager
	if not inventory_manager:
		print("ERROR: No inventory manager found!")
		print("inventory_integration.inventory_manager is: ", inventory_integration.inventory_manager)
		push_warning("PickupableItem: No inventory manager found!")
		return false

	var player_inventory = inventory_manager.get_player_inventory()
	if not player_inventory:
		print("ERROR: No player inventory found!")
		print("get_player_inventory() returned: ", player_inventory)
		push_warning("PickupableItem: No player inventory found!")
		return false

	var can_add = player_inventory.can_add_item(item_data)

	if not can_add:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_failed_attempt >= failure_cooldown:
			NotificationManager.show_warning("Inventory is full!")
			last_failed_attempt = current_time
		return false

	var success = player_inventory.add_item(item_data)

	if success:
		NotificationManager.show_item_pickup(item_data.item_name, item_data.quantity)

		if inventory_integration.is_inventory_window_open():
			var inventory_window = inventory_integration.get_inventory_window()
			if inventory_window and inventory_window.content:
				var correct_container = inventory_manager.get_player_inventory()

				inventory_window.content.current_container = correct_container
				if inventory_window.content.inventory_grid:
					inventory_window.content.inventory_grid.set_container(correct_container)
				if inventory_window.content.list_view:
					inventory_window.content.list_view.set_container(correct_container, correct_container.container_id)

				inventory_window.content.refresh_display()

		queue_free()
		return true

	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_failed_attempt >= failure_cooldown:
		NotificationManager.show_error("Failed to pick up item")
		last_failed_attempt = current_time
	return false
