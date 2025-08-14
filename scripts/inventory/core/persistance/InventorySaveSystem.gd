# InventorySaveSystem.gd - Handle all save/load operations
class_name InventorySaveSystem
extends RefCounted

# Signals
signal inventory_saved
signal inventory_loaded

var save_file_path: String = "user://inventory_save.dat"

# References (will be injected by InventoryManager)
var containers_ref: Dictionary
var transaction_history_ref: Array[Dictionary]
var settings_ref: Dictionary


func initialize(containers: Dictionary, transactions: Array[Dictionary], settings: Dictionary):
	containers_ref = containers
	transaction_history_ref = transactions
	settings_ref = settings


func save_inventory() -> bool:
	var save_data = {"version": "1.0", "timestamp": Time.get_unix_time_from_system(), "containers": {}, "transaction_history": transaction_history_ref, "settings": settings_ref}

	# Serialize all containers
	for container_id in containers_ref:
		var container = containers_ref[container_id]
		if container and container.has_method("to_dict"):
			save_data.containers[container_id] = container.to_dict()

	var file = FileAccess.open(save_file_path, FileAccess.WRITE)
	if not file:
		push_error("InventorySaveSystem: Failed to open save file for writing: " + save_file_path)
		return false

	file.store_string(JSON.stringify(save_data))
	file.close()

	inventory_saved.emit()
	print("InventorySaveSystem: Inventory saved to: ", save_file_path)
	return true


func load_inventory() -> bool:
	var file = FileAccess.open(save_file_path, FileAccess.READ)
	if not file:
		push_warning("InventorySaveSystem: No save file found: " + save_file_path)
		return false

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		push_error("InventorySaveSystem: Failed to parse save file!")
		return false

	var save_data = json.data
	if not save_data is Dictionary:
		push_error("InventorySaveSystem: Invalid save data format!")
		return false

	return _apply_save_data(save_data)


func _apply_save_data(save_data: Dictionary) -> bool:
	# Load containers
	var containers_data = save_data.get("containers", {})
	for container_id in containers_data:
		var container = containers_ref.get(container_id)
		if container and container.has_method("from_dict"):
			var container_data = containers_data[container_id]
			container.from_dict(container_data)

	# Load transaction history
	var history_data = save_data.get("transaction_history", [])
	transaction_history_ref.clear()
	for transaction in history_data:
		if transaction is Dictionary:
			transaction_history_ref.append(transaction)

	# Load settings
	var loaded_settings = save_data.get("settings", {})
	for key in loaded_settings:
		settings_ref[key] = loaded_settings[key]

	inventory_loaded.emit()
	print("InventorySaveSystem: Inventory loaded from: ", save_file_path)
	return true


func set_save_path(path: String):
	save_file_path = path


func save_exists() -> bool:
	return FileAccess.file_exists(save_file_path)
