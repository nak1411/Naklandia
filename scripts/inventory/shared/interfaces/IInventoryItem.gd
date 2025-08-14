# scripts/inventory/shared/interfaces/IInventoryItem.gd
class_name IInventoryItem

# Item interface definition
# All inventory items should implement these methods


# Core item operations
func can_stack_with(_other_item: InventoryItem_Base) -> bool:
	push_error("IInventoryItem.can_stack_with() not implemented")
	return false


func add_to_stack(amount: int) -> int:
	push_error("IInventoryItem.add_to_stack() not implemented")
	return amount


func remove_from_stack(_amount: int) -> int:
	push_error("IInventoryItem.remove_from_stack() not implemented")
	return 0


# Item properties
func get_item_id() -> String:
	push_error("IInventoryItem.get_item_id() not implemented")
	return ""


func get_item_name() -> String:
	push_error("IInventoryItem.get_item_name() not implemented")
	return ""


func get_total_volume() -> float:
	push_error("IInventoryItem.get_total_volume() not implemented")
	return 0.0


func get_total_mass() -> float:
	push_error("IInventoryItem.get_total_mass() not implemented")
	return 0.0


func get_total_value() -> float:
	push_error("IInventoryItem.get_total_value() not implemented")
	return 0.0


# Item validation
func is_valid_item() -> bool:
	push_error("IInventoryItem.is_valid_item() not implemented")
	return false
