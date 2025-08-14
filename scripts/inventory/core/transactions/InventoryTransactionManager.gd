# InventoryTransactionManager.gd - Handle all item transfers and transactions
class_name InventoryTransactionManager
extends RefCounted

# Signals
signal item_transferred(item: InventoryItem_Base, from_container: String, to_container: String)
signal transaction_completed(transaction: Dictionary)

# Transaction state
var pending_transfers: Array[Dictionary] = []
var transaction_history: Array[Dictionary] = []

# References
var container_registry: Dictionary = {}  # Will be set by InventoryManager


func set_container_registry(containers: Dictionary):
	container_registry = containers


func transfer_item(item: InventoryItem_Base, from_container_id: String, to_container_id: String, position: Vector2i = Vector2i(-1, -1), quantity: int = 0) -> bool:
	var from_container = container_registry.get(from_container_id)
	var to_container = container_registry.get(to_container_id)

	if not from_container or not to_container:
		push_error("InventoryTransactionManager: Invalid container IDs")
		return false

	# Same container - just move position
	if from_container_id == to_container_id:
		return _handle_same_container_move(item, from_container, position)

	# Cross-container transfer
	return _handle_cross_container_transfer(item, from_container, to_container, position, quantity)


func _handle_same_container_move(item: InventoryItem_Base, container: InventoryContainer_Base, new_position: Vector2i) -> bool:
	# Implementation for moving within same container
	var old_position = container.get_item_position(item)
	if container.move_item(item, new_position):
		_record_transaction("move", item, container.container_id, container.container_id, old_position, new_position)
		return true
	return false


func _handle_cross_container_transfer(item: InventoryItem_Base, from_container: InventoryContainer_Base, to_container: InventoryContainer_Base, position: Vector2i, quantity: int) -> bool:
	# Extract existing transfer logic from InventoryManager
	var transfer_quantity = quantity if quantity > 0 else item.quantity
	transfer_quantity = min(transfer_quantity, item.quantity)

	if transfer_quantity <= 0:
		return false

	# Check if target can accept the item/quantity
	if not _can_transfer(item, from_container, to_container, transfer_quantity):
		return false

	# Perform the transfer
	var success = false

	if transfer_quantity >= item.quantity:
		# Transfer entire item
		if from_container.remove_item(item) and to_container.add_item(item, position):
			success = true
	else:
		# Partial transfer - create new item
		var transferred_item = _create_partial_item(item, transfer_quantity)
		if transferred_item and to_container.add_item(transferred_item, position):
			item.remove_from_stack(transfer_quantity)
			success = true

	if success:
		_record_transaction("transfer", item, from_container.container_id, to_container.container_id, Vector2i(-1, -1), position, transfer_quantity)
		item_transferred.emit(item, from_container.container_id, to_container.container_id)

	return success


func _can_transfer(item: InventoryItem_Base, from_container: InventoryContainer_Base, to_container: InventoryContainer_Base, quantity: int) -> bool:
	# Validation logic extracted from current transfer methods
	if not item or not from_container or not to_container:
		return false

	# Check if item exists in from_container
	if not item in from_container.items:
		return false

	# Check volume constraints
	var transfer_volume = quantity * item.volume
	return to_container.get_available_volume() >= transfer_volume


func _create_partial_item(original_item: InventoryItem_Base, quantity: int) -> InventoryItem_Base:
	# Create a duplicate with specified quantity
	var new_item = InventoryItem_Base.new(original_item.item_id, original_item.item_name)
	new_item.description = original_item.description
	new_item.icon_path = original_item.icon_path
	new_item.volume = original_item.volume
	new_item.mass = original_item.mass
	new_item.quantity = quantity
	new_item.max_stack_size = original_item.max_stack_size
	new_item.item_type = original_item.item_type
	new_item.base_value = original_item.base_value
	return new_item


func _record_transaction(type: String, item: InventoryItem_Base, from_container_id: String, to_container_id: String, from_pos: Vector2i, to_pos: Vector2i, quantity: int = 0):
	var transaction = {
		"type": type,
		"timestamp": Time.get_unix_time_from_system(),
		"item_id": item.item_id,
		"item_name": item.item_name,
		"from_container": from_container_id,
		"to_container": to_container_id,
		"from_position": from_pos,
		"to_position": to_pos,
		"quantity": quantity if quantity > 0 else item.quantity
	}

	transaction_history.append(transaction)

	# Keep only last 100 transactions
	if transaction_history.size() > 100:
		transaction_history = transaction_history.slice(-100)

	transaction_completed.emit(transaction)


func get_transaction_history() -> Array[Dictionary]:
	return transaction_history.duplicate()


func clear_transaction_history():
	transaction_history.clear()
