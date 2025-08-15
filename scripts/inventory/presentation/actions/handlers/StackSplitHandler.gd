# scripts/inventory/presentation/actions/handlers/StackSplitHandler.gd
class_name StackSplitHandler
extends RefCounted


static func perform_split(item: InventoryItem_Base, split_amount: int, container: InventoryContainer_Base, inventory_manager: InventoryManager) -> bool:
	"""Perform the item stack split operation - extracted from InventoryItemActions"""
	if not inventory_manager or not container or not item:
		return false

	if split_amount <= 0 or split_amount >= item.quantity:
		return false

	var new_item = item.split_stack(split_amount)
	if not new_item:
		return false

	if not container.has_volume_for_item(new_item):
		item.add_to_stack(new_item.quantity)
		return false

	var temp_auto_stack = inventory_manager.settings.auto_stack
	inventory_manager.settings.auto_stack = false

	var success = container.add_item(new_item, Vector2i(-1, -1), false)
	if not success:
		item.add_to_stack(new_item.quantity)

	inventory_manager.settings.auto_stack = temp_auto_stack
	return success


static func validate_split_params(item: InventoryItem_Base, split_amount: int) -> bool:
	"""Validate split parameters"""
	return item != null and split_amount > 0 and split_amount < item.quantity
