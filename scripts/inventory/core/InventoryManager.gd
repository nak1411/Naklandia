# InventoryManager.gd - Central inventory management system
class_name InventoryManager
extends Node

# Container management
var containers: Dictionary = {}  # container_id -> InventoryContainer
var active_containers: Array[String] = []  # Currently open container IDs

# Default containers
var player_inventory: InventoryContainer
var player_cargo: InventoryContainer
var hangar_containers: Array[InventoryContainer] = []

# Transaction system
var pending_transfers: Array[Dictionary] = []
var transaction_history: Array[Dictionary] = []

# Settings
@export var auto_stack: bool = true
@export var auto_sort: bool = false
@export var save_file_path: String = "user://inventory_save.dat"

# Signals
signal container_added(container: InventoryContainer)
signal container_removed(container_id: String)
signal item_transferred(item: InventoryItem, from_container: String, to_container: String)
signal transaction_completed(transaction: Dictionary)
signal inventory_loaded()
signal inventory_saved()

func _ready():
	_initialize_default_containers()
	_setup_autosave()

func _initialize_default_containers():
	# Create player inventory (limited space, always accessible)
	player_inventory = InventoryContainer.new("player_inventory", "Personal Inventory", 25.0)
	player_inventory.grid_width = 5
	player_inventory.grid_height = 8
	add_container(player_inventory)
	
	# Create player cargo hold (larger space)
	player_cargo = InventoryContainer.new("player_cargo", "Cargo Hold", 500.0)
	player_cargo.grid_width = 15
	player_cargo.grid_height = 20
	player_cargo.container_type = InventoryItem.ContainerType.SHIP_CARGO
	add_container(player_cargo)
	
	# Create hangar containers
	for i in range(3):
		var hangar = InventoryContainer.new("hangar_%d" % i, "Hangar Division %d" % (i + 1), 1000.0)
		hangar.grid_width = 20
		hangar.grid_height = 25
		hangar.container_type = InventoryItem.ContainerType.HANGAR_DIVISION
		hangar.requires_docking = true
		hangar_containers.append(hangar)
		add_container(hangar)

func _setup_autosave():
	# Save inventory periodically
	var timer = Timer.new()
	timer.wait_time = 30.0  # Save every 30 seconds
	timer.timeout.connect(save_inventory)
	timer.autostart = true
	add_child(timer)

# Container management
func add_container(container: InventoryContainer) -> bool:
	if container.container_id in containers:
		return false
	
	containers[container.container_id] = container
	
	# Connect container signals
	container.item_added.connect(_on_container_item_added)
	container.item_removed.connect(_on_container_item_removed)
	container.item_moved.connect(_on_container_item_moved)
	
	container_added.emit(container)
	return true

func remove_container(container_id: String) -> bool:
	if not container_id in containers:
		return false
	
	var container = containers[container_id]
	
	# Disconnect signals
	if container.item_added.is_connected(_on_container_item_added):
		container.item_added.disconnect(_on_container_item_added)
	if container.item_removed.is_connected(_on_container_item_removed):
		container.item_removed.disconnect(_on_container_item_removed)
	if container.item_moved.is_connected(_on_container_item_moved):
		container.item_moved.disconnect(_on_container_item_moved)
	
	containers.erase(container_id)
	active_containers.erase(container_id)
	
	container_removed.emit(container_id)
	return true

func get_container(container_id: String) -> InventoryContainer:
	return containers.get(container_id, null)

func get_all_containers() -> Array[InventoryContainer]:
	var container_list: Array[InventoryContainer] = []
	for container in containers.values():
		container_list.append(container)
	return container_list

func get_accessible_containers() -> Array[InventoryContainer]:
	var accessible: Array[InventoryContainer] = []
	
	for container in containers.values():
		if not container.requires_docking:
			accessible.append(container)
		# TODO: Add docking check for hangar containers
	
	return accessible

# Item operations
func add_item_to_container(item: InventoryItem, container_id: String, position: Vector2i = Vector2i(-1, -1)) -> bool:
	var container = get_container(container_id)
	if not container:
		return false
	
	return container.add_item(item, position)

func remove_item_from_container(item: InventoryItem, container_id: String) -> bool:
	var container = get_container(container_id)
	if not container:
		return false
	return container.remove_item(item)

func transfer_item(item: InventoryItem, from_container_id: String, to_container_id: String, 
				  position: Vector2i = Vector2i(-1, -1), quantity: int = -1) -> bool:
	var from_container = get_container(from_container_id)
	var to_container = get_container(to_container_id)
	
	if not from_container or not to_container:
		return false
	
	if not item in from_container.items:
		return false
	
	# Handle partial transfer
	var transfer_quantity = quantity if quantity > 0 else item.quantity
	var transfer_item = item
	
	if transfer_quantity < item.quantity:
		transfer_item = item.split_stack(transfer_quantity)
		if not transfer_item:
			return false
	
	# Attempt transfer
	if to_container.add_item(transfer_item, position):
		if transfer_quantity >= item.quantity:
			from_container.remove_item(item)
		
		# Record transaction
		var transaction = {
			"item_name": transfer_item.item_name,
			"quantity": transfer_item.quantity,
			"from_container": from_container_id,
			"to_container": to_container_id,
			"timestamp": Time.get_unix_time_from_system()
		}
		transaction_history.append(transaction)
		
		item_transferred.emit(transfer_item, from_container_id, to_container_id)
		transaction_completed.emit(transaction)
		return true
	else:
		# Transfer failed, restore original item if it was split
		if transfer_quantity < item.quantity and transfer_item:
			item.add_to_stack(transfer_item.quantity)
		return false

# Item searching across all containers
func find_item_globally(item_id: String) -> Dictionary:
	for container_id in containers:
		var container = containers[container_id]
		var item = container.find_item_by_id(item_id)
		if item:
			return {
				"item": item,
				"container_id": container_id,
				"position": container.get_item_position(item)
			}
	
	return {}

func find_items_by_name_globally(name: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	
	for container_id in containers:
		var container = containers[container_id]
		var items = container.find_items_by_name(name)
		for item in items:
			results.append({
				"item": item,
				"container_id": container_id,
				"position": container.get_item_position(item)
			})
	
	return results

func find_items_by_type_globally(item_type: InventoryItem.ItemType) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	
	for container_id in containers:
		var container = containers[container_id]
		var items = container.find_items_by_type(item_type)
		for item in items:
			results.append({
				"item": item,
				"container_id": container_id,
				"position": container.get_item_position(item)
			})
	
	return results

# Auto-stacking and sorting
func auto_stack_container(container_id: String):
	var container = get_container(container_id)
	if not container:
		return
	
	var items_to_process = container.items.duplicate()
	
	for i in range(items_to_process.size()):
		var item = items_to_process[i]
		if not item in container.items:  # Item might have been merged
			continue
		
		# Find stackable items
		for j in range(i + 1, items_to_process.size()):
			var other_item = items_to_process[j]
			if not other_item in container.items:
				continue
			
			if item.can_stack_with(other_item):
				var remaining = item.add_to_stack(other_item.quantity)
				if remaining == 0:
					container.remove_item(other_item)
				else:
					other_item.quantity = remaining
	
	# Compact after stacking to eliminate gaps
	container.compact_items()

func auto_stack_all_containers():
	for container_id in containers:
		auto_stack_container(container_id)
		
func compact_container(container_id: String):
	"""Compacts a container to remove gaps between items"""
	var container = get_container(container_id)
	if container:
		container.compact_items()

func compact_all_containers():
	"""Compacts all containers to remove gaps"""
	for container_id in containers:
		compact_container(container_id)

func sort_container(container_id: String, sort_type: SortType = SortType.BY_NAME):
	var container = get_container(container_id)
	if not container:
		return
	
	var sorted_items = container.items.duplicate()
	
	match sort_type:
		SortType.BY_NAME:
			sorted_items.sort_custom(func(a, b): return a.item_name < b.item_name)
		SortType.BY_TYPE:
			sorted_items.sort_custom(func(a, b): return a.item_type < b.item_type)
		SortType.BY_VALUE:
			sorted_items.sort_custom(func(a, b): return a.get_total_value() > b.get_total_value())
		SortType.BY_VOLUME:
			sorted_items.sort_custom(func(a, b): return a.get_total_volume() > b.get_total_volume())
		SortType.BY_RARITY:
			sorted_items.sort_custom(func(a, b): return a.item_rarity > b.item_rarity)
	
	# Clear container and re-add items in sorted order
	container.clear()
	for item in sorted_items:
		container.add_item(item)

enum SortType {
	BY_NAME,
	BY_TYPE,
	BY_VALUE,
	BY_VOLUME,
	BY_RARITY
}

# Container access management
func open_container(container_id: String) -> bool:
	var container = get_container(container_id)
	if not container:
		return false
	
	# Check access requirements
	if container.requires_docking:
		# TODO: Add docking status check
		pass
	
	if not container_id in active_containers:
		active_containers.append(container_id)
	
	return true

func close_container(container_id: String):
	active_containers.erase(container_id)

func is_container_open(container_id: String) -> bool:
	return container_id in active_containers

func get_open_containers() -> Array[InventoryContainer]:
	var open_containers: Array[InventoryContainer] = []
	for container_id in active_containers:
		var container = get_container(container_id)
		if container:
			open_containers.append(container)
	return open_containers

# Statistics and reports
func get_total_inventory_value() -> float:
	var total_value = 0.0
	for container in containers.values():
		total_value += container.get_total_value()
	return total_value

func get_total_inventory_volume() -> float:
	var total_volume = 0.0
	for container in containers.values():
		total_volume += container.get_current_volume()
	return total_volume

func get_total_inventory_mass() -> float:
	var total_mass = 0.0
	for container in containers.values():
		total_mass += container.get_total_mass()
	return total_mass

func get_inventory_summary() -> Dictionary:
	var summary = {
		"total_containers": containers.size(),
		"open_containers": active_containers.size(),
		"total_items": 0,
		"total_value": get_total_inventory_value(),
		"total_volume": get_total_inventory_volume(),
		"total_mass": get_total_inventory_mass(),
		"recent_transactions": transaction_history.slice(-10)  # Last 10 transactions
	}
	
	for container in containers.values():
		summary.total_items += container.get_item_count()
	
	return summary

# Item creation helpers
func create_item(item_id: String, name: String, quantity: int = 1) -> InventoryItem:
	var item = InventoryItem.new(item_id, name)
	item.quantity = quantity
	return item

func create_sample_items():
	var items = [
		{
			"id": "tritanium_ore",
			"name": "Tritanium Ore",
			"type": InventoryItem.ItemType.RESOURCE,
			"volume": 0.01,
			"mass": 0.01,
			"max_stack": 1000,
			"value": 5.0,
			"rarity": InventoryItem.ItemRarity.COMMON
		},
		{
			"id": "laser_crystal",
			"name": "Laser Focusing Crystal",
			"type": InventoryItem.ItemType.MODULE,
			"volume": 5.0,
			"mass": 2.0,
			"max_stack": 1,
			"value": 15000.0,
			"rarity": InventoryItem.ItemRarity.RARE
		},
		{
			"id": "ammo_hybrid",
			"name": "Hybrid Charges",
			"type": InventoryItem.ItemType.AMMUNITION,
			"volume": 0.025,
			"mass": 0.01,
			"max_stack": 500,
			"value": 100.0,
			"rarity": InventoryItem.ItemRarity.COMMON
		},
		{
			"id": "blueprint_frigate",
			"name": "Frigate Blueprint",
			"type": InventoryItem.ItemType.BLUEPRINT,
			"volume": 0.1,
			"mass": 0.1,
			"max_stack": 1,
			"value": 50000.0,
			"rarity": InventoryItem.ItemRarity.EPIC
		}
	]
	
	for item_data in items:
		var item = InventoryItem.new(item_data.id, item_data.name)
		item.item_type = item_data.type
		item.volume = item_data.volume
		item.mass = item_data.mass
		item.max_stack_size = item_data.max_stack
		item.base_value = item_data.value
		item.item_rarity = item_data.rarity
		
		# Add to player inventory
		player_inventory.add_item(item)

# Signal handlers
func _on_container_item_added(item: InventoryItem, position: Vector2i):
	if auto_stack:
		# Find which container this came from by checking all containers
		for container_id in containers:
			var container = containers[container_id]
			if item in container.items:
				auto_stack_container(container_id)
				break

func _on_container_item_removed(item: InventoryItem, position: Vector2i):
	# Handle item removal cleanup
	pass

func _on_container_item_moved(item: InventoryItem, from_pos: Vector2i, to_pos: Vector2i):
	# Handle item movement
	pass

# Save/Load system
func save_inventory():
	var save_data = {
		"version": "1.0",
		"timestamp": Time.get_unix_time_from_system(),
		"containers": {},
		"transaction_history": transaction_history,
		"settings": {
			"auto_stack": auto_stack,
			"auto_sort": auto_sort
		}
	}
	
	for container_id in containers:
		save_data.containers[container_id] = containers[container_id].to_dict()
	
	var file = FileAccess.open(save_file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))
		file.close()
		inventory_saved.emit()
		print("Inventory saved to: ", save_file_path)
	else:
		print("Failed to save inventory!")

func load_inventory():
	var file = FileAccess.open(save_file_path, FileAccess.READ)
	if not file:
		print("No save file found, creating sample items")
		create_sample_items()
		return false
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		print("Failed to parse save file!")
		return false
	
	var save_data = json.data
	
	# Clear existing containers (except defaults)
	containers.clear()
	_initialize_default_containers()
	
	# Load containers
	var containers_data = save_data.get("containers") if save_data.has("containers") else {}
	for container_id in containers_data:
		var container_data = containers_data[container_id]
		var container = get_container(container_id)
		if container:
			container.from_dict(container_data)
		else:
			# Create new container if it doesn't exist
			container = InventoryContainer.new()
			container.from_dict(container_data)
			add_container(container)
	
	# Load transaction history
	var history_data = save_data.get("transaction_history") if save_data.has("transaction_history") else []
	transaction_history.clear()
	for transaction in history_data:
		if transaction is Dictionary:
			transaction_history.append(transaction)
	
	# Load settings
	var settings = save_data.get("settings") if save_data.has("settings") else {}
	auto_stack = settings.get("auto_stack") if settings.has("auto_stack") else true
	auto_sort = settings.get("auto_sort") if settings.has("auto_sort") else false
	
	inventory_loaded.emit()
	print("Inventory loaded from: ", save_file_path)
	return true

# Public interface for UI
func get_player_inventory() -> InventoryContainer:
	return player_inventory

func get_player_cargo() -> InventoryContainer:
	return player_cargo

func get_hangar_containers() -> Array[InventoryContainer]:
	return hangar_containers

func _exit_tree():
	save_inventory()
