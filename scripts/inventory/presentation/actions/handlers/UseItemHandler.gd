# scripts/inventory/presentation/actions/handlers/UseItemHandler.gd
class_name UseItemHandler
extends RefCounted


static func use_item(item: InventoryItem_Base, inventory_manager: InventoryManager) -> bool:
	"""Handle item usage"""
	if not item or not inventory_manager:
		return false

	# Check if item is usable
	if not item.has_method("use") or not item.can_use():
		return false

	# Use the item
	var success = item.use()

	if success and item.is_consumable:
		# Remove one from stack or delete item
		if item.quantity > 1:
			item.quantity -= 1
		else:
			# Remove item from container
			var container = inventory_manager.find_container_with_item(item)
			if container:
				container.remove_item(item)

	return success


static func can_use_item(item: InventoryItem_Base) -> bool:
	"""Check if item can be used"""
	return item != null and item.has_method("use") and item.can_use()
