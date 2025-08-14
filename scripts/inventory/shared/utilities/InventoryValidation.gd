# scripts/inventory/shared/utilities/InventoryValidation.gd
class_name InventoryValidation


# Item validation
static func is_valid_item(item: InventoryItem_Base) -> bool:
	if not item:
		return false

	return not item.item_name.is_empty() and item.volume > 0.0 and item.mass >= 0.0 and item.quantity > 0 and item.max_stack_size > 0


static func can_stack_items(item1: InventoryItem_Base, item2: InventoryItem_Base) -> bool:
	if not item1 or not item2:
		return false

	return item1.item_id == item2.item_id and item1.max_stack_size > 1 and item2.max_stack_size > 1 and not item1.is_unique and not item2.is_unique


# Container validation
static func can_fit_item(container: InventoryContainer_Base, item: InventoryItem_Base) -> bool:
	if not container or not item:
		return false

	var available_volume = container.get_available_volume()
	var item_volume = item.get_total_volume()

	return available_volume >= item_volume


static func validate_transfer(from_container: InventoryContainer_Base, to_container: InventoryContainer_Base, item: InventoryItem_Base, quantity: int = -1) -> Dictionary:
	var result = {"valid": false, "error": "", "max_transferable": 0}

	if not from_container or not to_container or not item:
		result.error = "Invalid containers or item"
		return result

	if not from_container.has_item(item):
		result.error = "Item not found in source container"
		return result

	var transfer_quantity = quantity if quantity > 0 else item.quantity
	var available_space = to_container.get_available_volume()
	var item_unit_volume = item.volume

	var max_transferable = floori(available_space / item_unit_volume)
	max_transferable = mini(max_transferable, transfer_quantity)

	result.max_transferable = max_transferable

	if max_transferable > 0:
		result.valid = true
	else:
		result.error = "Insufficient space in target container"

	return result
