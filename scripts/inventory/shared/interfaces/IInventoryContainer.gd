# scripts/inventory/shared/interfaces/IInventoryContainer.gd
class_name IInventoryContainer

# Container interface definition
# All inventory containers should implement these methods

# Core container operations
func add_item(item: InventoryItem_Base, quantity: int = -1) -> bool:
	push_error("IInventoryContainer.add_item() not implemented")
	return false

func remove_item(item: InventoryItem_Base, quantity: int = -1) -> bool:
	push_error("IInventoryContainer.remove_item() not implemented")
	return false

func has_item(item: InventoryItem_Base) -> bool:
	push_error("IInventoryContainer.has_item() not implemented")
	return false

func can_add_item(item: InventoryItem_Base, quantity: int = -1) -> bool:
	push_error("IInventoryContainer.can_add_item() not implemented")
	return false

# Container properties
func get_container_id() -> String:
	push_error("IInventoryContainer.get_container_id() not implemented")
	return ""

func get_container_name() -> String:
	push_error("IInventoryContainer.get_container_name() not implemented")
	return ""

func get_total_volume() -> float:
	push_error("IInventoryContainer.get_total_volume() not implemented")
	return 0.0

func get_available_volume() -> float:
	push_error("IInventoryContainer.get_available_volume() not implemented")
	return 0.0

func get_used_volume() -> float:
	push_error("IInventoryContainer.get_used_volume() not implemented")
	return 0.0

# Item access
func get_items() -> Array[InventoryItem_Base]:
	push_error("IInventoryContainer.get_items() not implemented")
	return []

func get_item_count() -> int:
	push_error("IInventoryContainer.get_item_count() not implemented")
	return 0