# scripts/inventory/presentation/actions/handlers/ItemTransferHandler.gd
class_name ItemTransferHandler
extends RefCounted


static func transfer_item(item: InventoryItem_Base, from_container_id: String, to_container_id: String, inventory_manager: InventoryManager, amount: int = -1) -> bool:
	"""Handle item transfer between containers"""
	if not inventory_manager or from_container_id == to_container_id:
		return false

	var transfer_amount = amount if amount > 0 else item.quantity
	return inventory_manager.transfer_item(item, from_container_id, to_container_id, Vector2i(-1, -1), transfer_amount)


static func get_available_containers(inventory_manager: InventoryManager, exclude_container_id: String = "") -> Array[String]:
	"""Get list of available target containers"""
	var available_containers: Array[String] = []

	for container_id in ["player_inventory", "player_cargo", "hangar_0", "hangar_1", "hangar_2"]:
		if container_id != exclude_container_id and inventory_manager.has_container(container_id):
			available_containers.append(container_id)

	return available_containers
