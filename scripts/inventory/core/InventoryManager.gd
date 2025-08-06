class_name InventoryManager
extends Node

# Container management
var containers: Dictionary = {}  # container_id -> InventoryContainer_Base
var active_containers: Array[String] = []  # Currently open container IDs

# Default containers
var player_inventory: InventoryContainer_Base
var player_cargo: InventoryContainer_Base
var hangar_containers: Array[InventoryContainer_Base] = []

# Transaction system
var pending_transfers: Array[Dictionary] = []
var transaction_history: Array[Dictionary] = []

# Settings
@export var auto_stack: bool = true
@export var auto_sort: bool = false
@export var save_file_path: String = "user://inventory_save.dat"

# Signals
signal container_added(container: InventoryContainer_Base)
signal container_removed(container_id: String)
signal item_transferred(item: InventoryItem_Base, from_container: String, to_container: String)
signal transaction_completed(transaction: Dictionary)
signal inventory_loaded()
signal inventory_saved()

func _ready():
	_initialize_default_containers()
	_setup_autosave()

func _input(_event):
	pass

func _initialize_default_containers():
	# Create player inventory (limited space, always accessible)
	player_inventory = InventoryContainer_Base.new("player_inventory", "Personal Inventory", 25.0)
	player_inventory.grid_width = 5
	player_inventory.grid_height = 8
	add_container(player_inventory)
	
	# Create player cargo hold (larger space)
	player_cargo = InventoryContainer_Base.new("player_cargo", "Cargo Hold", 500.0)
	player_cargo.grid_width = 15
	player_cargo.grid_height = 20
	player_cargo.container_type = InventoryItem_Base.ContainerType.SHIP_CARGO
	add_container(player_cargo)
	
	# Create hangar containers
	for i in range(3):
		var hangar = InventoryContainer_Base.new("hangar_%d" % i, "Hangar Division %d" % (i + 1), 1000.0)
		hangar.grid_width = 20
		hangar.grid_height = 25
		hangar.container_type = InventoryItem_Base.ContainerType.HANGAR_DIVISION
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
func add_container(container: InventoryContainer_Base) -> bool:
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

func get_container(container_id: String) -> InventoryContainer_Base:
	return containers.get(container_id, null)

func get_all_containers() -> Array[InventoryContainer_Base]:
	var container_list: Array[InventoryContainer_Base] = []
	for container in containers.values():
		container_list.append(container)
	return container_list

func get_accessible_containers() -> Array[InventoryContainer_Base]:
	var accessible: Array[InventoryContainer_Base] = []
	
	for container in containers.values():
		if not container.requires_docking:
			accessible.append(container)
		# TODO: Add docking check for hangar containers
	
	return accessible

# Item operations
func add_item_to_container(item: InventoryItem_Base, container_id: String, position: Vector2i = Vector2i(-1, -1), _auto_stack: bool = true) -> bool:
	var container = get_container(container_id)
	if not container:
		return false
	
	return container.add_item(item, position, auto_stack)

func remove_item_from_container(item: InventoryItem_Base, container_id: String) -> bool:
	var container = get_container(container_id)
	if not container:
		return false
	return container.remove_item(item)

func transfer_item(item: InventoryItem_Base, from_container_id: String, to_container_id: String, position: Vector2i = Vector2i(-1, -1), quantity: int = 0) -> bool:
	var from_container = get_container(from_container_id)
	var to_container = get_container(to_container_id)
	
	if not from_container or not to_container:
		return false
	
	if not item in from_container.items:
		return false
	
	# Handle transfer quantity
	var transfer_quantity = quantity if quantity > 0 else item.quantity
	var _transfer_item = item
	
	# Declare transaction variable once at function level
	var transaction: Dictionary
	
	# For same container transfers to specific positions, check if target has stackable item
	if from_container == to_container and position != Vector2i(-1, -1):
		var target_item = _get_item_at_position(to_container, position)
		if target_item and target_item != item and item.can_stack_with(target_item):
			# Stack with target item
			var space_available = target_item.max_stack_size - target_item.quantity
			var amount_to_stack = min(transfer_quantity, space_available)
			
			if amount_to_stack > 0:
				target_item.quantity += amount_to_stack
				item.quantity -= amount_to_stack
				
				if item.quantity <= 0:
					from_container.remove_item(item)
				
				# Record transaction
				transaction = {
					"item_name": item.item_name,
					"quantity": amount_to_stack,
					"from_container": from_container_id,
					"to_container": to_container_id,
					"timestamp": Time.get_unix_time_from_system(),
					"stacked": true
				}
				transaction_history.append(transaction)
				
				item_transferred.emit(item, from_container_id, to_container_id)
				transaction_completed.emit(transaction)
				return true
	
	# Check if we can stack with existing items in target container (for different containers)
	if from_container != to_container:
		var stackable_item = to_container.find_stackable_item(item)
		if stackable_item:
			# Calculate available stack space
			var stack_space = stackable_item.max_stack_size - stackable_item.quantity
			
			# Calculate volume constraint - how many items can fit by volume
			var stack_available_volume = to_container.get_available_volume()
			var volume_limited_quantity = int(stack_available_volume / item.volume) if item.volume > 0 else transfer_quantity
			
			# Use the minimum of stack space, volume constraints, and requested quantity
			var max_stackable = min(stack_space, min(volume_limited_quantity, transfer_quantity))
			
			if max_stackable > 0:
				# We can stack at least some quantity
				if max_stackable < item.quantity:
					# Partial transfer - reduce source quantity
					item.quantity -= max_stackable
					stackable_item.quantity += max_stackable
				else:
					# Complete transfer - remove from source and add to target stack
					from_container.remove_item(item)
					stackable_item.quantity += max_stackable
				
				# Record transaction
				transaction = {
					"item_name": item.item_name,
					"quantity": max_stackable,
					"from_container": from_container_id,
					"to_container": to_container_id,
					"timestamp": Time.get_unix_time_from_system(),
					"stacked": true
				}
				transaction_history.append(transaction)
				
				item_transferred.emit(item, from_container_id, to_container_id)
				transaction_completed.emit(transaction)
				return true
	
	# Calculate maximum transferable quantity based on volume for new items
	var available_volume = to_container.get_available_volume()
	var max_transferable_by_volume = int(available_volume / item.volume) if item.volume > 0 else transfer_quantity
	
	# Limit transfer quantity to what can actually fit
	transfer_quantity = min(transfer_quantity, max_transferable_by_volume)
	
	if transfer_quantity <= 0:
		return false  # Nothing can be transferred
	
	# Handle partial vs full transfer
	if transfer_quantity >= item.quantity:
		# Full transfer - move entire item
		_transfer_item = item
		
		# Check if target container can accept the item
		if not to_container.can_add_item(_transfer_item):
			return false
		
		# Remove from source and add to target
		if not from_container.remove_item(_transfer_item):
			return false
		
		if not to_container.add_item(_transfer_item, position):
			# Failed to add - restore to source
			from_container.add_item(_transfer_item)
			return false
	else:
		# Partial transfer - use split_stack which handles quantity reduction
		_transfer_item = item.split_stack(transfer_quantity)
		if not _transfer_item:
			return false
		
		# Check if target container can accept the split item
		if not to_container.can_add_item(_transfer_item):
			# Restore the split by adding back to original item
			item.add_to_stack(_transfer_item.quantity)
			return false
		
		# Add split item to target container
		if not to_container.add_item(_transfer_item, position):
			# Failed to add - restore the split
			item.add_to_stack(_transfer_item.quantity)
			return false
	
	# Record transaction
	transaction = {
		"item_name": _transfer_item.item_name,
		"quantity": _transfer_item.quantity,
		"from_container": from_container_id,
		"to_container": to_container_id,
		"timestamp": Time.get_unix_time_from_system(),
		"stacked": false
	}
	transaction_history.append(transaction)
	
	item_transferred.emit(transfer_item, from_container_id, to_container_id)
	transaction_completed.emit(transaction)
	return true
	
func _get_item_at_position(container: InventoryContainer_Base, position: Vector2i) -> InventoryItem_Base:
	if position.y >= 0 and position.y < container.grid_slots.size():
		if position.x >= 0 and position.x < container.grid_slots[position.y].size():
			return container.grid_slots[position.y][position.x]
	return null

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

func find_items_by_name_globally(_name: String) -> Array[Dictionary]:
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

func find_items_by_type_globally(item_type: InventoryItem_Base.ItemType) -> Array[Dictionary]:
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
	
	# Auto-stack before sorting
	container.auto_stack_items()
	
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
	
	# Clear container and re-add items in sorted order
	container.clear()
	for item in sorted_items:
		container.add_item(item)

enum SortType {
	BY_NAME,
	BY_TYPE,
	BY_VALUE,
	BY_VOLUME,
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

func get_open_containers() -> Array[InventoryContainer_Base]:
	var open_containers: Array[InventoryContainer_Base] = []
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
func create_item(item_id: String, _name: String, quantity: int = 1) -> InventoryItem_Base:
	var item = InventoryItem_Base.new(item_id, name)
	item.quantity = quantity
	return item

func create_sample_items():
	var items = [
		{
			"id": "tritanium_ore",
			"name": "Tritanium Ore",
			"type": InventoryItem_Base.ItemType.RESOURCE,
			"volume": 0.01,
			"mass": 0.01,
			"max_stack": 999999,
			"value": 5.0,
		},
		{
			"id": "laser_crystal",
			"name": "Laser Focusing Crystal",
			"type": InventoryItem_Base.ItemType.MODULE,
			"volume": 5.0,
			"mass": 2.0,
			"max_stack": 999999,  # Changed from 1 to 10
			"value": 15000.0,
		},
		{
			"id": "ammo_hybrid",
			"name": "Hybrid Charges",
			"type": InventoryItem_Base.ItemType.AMMUNITION,
			"volume": 0.025,
			"mass": 0.01,
			"max_stack": 999999,
			"value": 100.0,
		},
		{
			"id": "blueprint_frigate",
			"name": "Frigate Blueprint",
			"type": InventoryItem_Base.ItemType.BLUEPRINT,
			"volume": 0.1,
			"mass": 0.1,
			"max_stack": 999999,  # Changed from 1 to 5
			"value": 50000.0,
		}
	]
	
	for item_data in items:
		# Create multiple instances of some items for testing stacking
		var base_item = InventoryItem_Base.new(item_data.id, item_data.name)
		base_item.item_type = item_data.type
		base_item.volume = item_data.volume
		base_item.mass = item_data.mass
		base_item.max_stack_size = item_data.max_stack
		base_item.base_value = item_data.value
		
		# Add multiple copies of stackable items for testing
		if item_data.max_stack > 1:
			# Add 3 separate stacks of 1 each (so you can test stacking them)
			for i in range(3):
				var item = InventoryItem_Base.new()
				item.item_id = item_data.id  # Set ID explicitly after creation
				item.item_name = item_data.name
				item.item_type = item_data.type
				item.volume = item_data.volume
				item.mass = item_data.mass
				item.max_stack_size = item_data.max_stack
				item.base_value = item_data.value
				item.quantity = 1
				
				player_inventory.add_item(item)
		else:
			# Just add one for non-stackable items
			base_item.item_id = item_data.id  # Make sure base item has correct ID too
			player_inventory.add_item(base_item)

# Signal handlers
func _on_container_item_added(item: InventoryItem_Base, _position: Vector2i):
	# Only auto-stack if auto_stack is enabled
	if auto_stack:
		# Find which container this came from by checking all containers
		for container_id in containers:
			var container = containers[container_id]
			if item in container.items:
				auto_stack_container(container_id)
				break

func _on_container_item_removed(_item: InventoryItem_Base, _position: Vector2i):
	# Handle item removal cleanup
	pass

func _on_container_item_moved(_item: InventoryItem_Base, _from_pos: Vector2i, _to_pos: Vector2i):
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
		# If save file is corrupted, create new sample items
		create_sample_items()
		return false
	
	var save_data = json.data
	
	# Check if this is an old save file with incorrect stack sizes
	var needs_refresh = false
	var containers_data = save_data.get("containers") if save_data.has("containers") else {}
	if containers_data.has("player_inventory"):
		var player_data = containers_data["player_inventory"]
		var items_data = player_data.get("items") if player_data.has("items") else []
		for item_data in items_data:
			if item_data.get("item_id") == "laser_crystal" and item_data.get("max_stack_size") == 1:
				needs_refresh = true
				break
	
	if needs_refresh:
		print("Old save file detected with incorrect stack sizes, creating fresh sample items")
		create_sample_items()
		return false
	
	# Clear existing containers (except defaults)
	containers.clear()
	_initialize_default_containers()
	
	# Load containers
	for container_id in containers_data:
		var container_data = containers_data[container_id]
		var container = get_container(container_id)
		if container:
			container.from_dict(container_data)
		else:
			# Create new container if it doesn't exist
			container = InventoryContainer_Base.new()
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
	
func can_transfer_item_volume_based(item: InventoryItem_Base, from_container_id: String, to_container_id: String) -> bool:
	"""Check if an item can be transferred based on volume constraints"""
	var from_container = get_container(from_container_id)
	var to_container = get_container(to_container_id)
	
	if not from_container or not to_container:
		return false
	
	if not item in from_container.items:
		return false
	
	# Check if target container has volume for the item
	return to_container.has_volume_for_item(item)
	
func transfer_partial_stack(item: InventoryItem_Base, quantity_to_transfer: int, from_container_id: String, to_container_id: String) -> Dictionary:
	"""Transfer a partial quantity from a stack between containers"""
	var from_container = get_container(from_container_id)
	var to_container = get_container(to_container_id)
	
	if not from_container or not to_container:
		return {"success": false, "transferred": 0, "remaining": item.quantity}
	
	if not item in from_container.items:
		return {"success": false, "transferred": 0, "remaining": item.quantity}
	
	# Calculate how much we can actually transfer based on volume
	var available_volume = to_container.get_available_volume()
	var item_volume_per_unit = item.volume
	var max_transferable_by_volume = int(available_volume / item_volume_per_unit)
	
	# Take the minimum of what we want to transfer and what fits
	var actual_transfer = min(quantity_to_transfer, max_transferable_by_volume)
	actual_transfer = min(actual_transfer, item.quantity)
	
	if actual_transfer <= 0:
		return {"success": false, "transferred": 0, "remaining": item.quantity}
	
	# If transferring entire stack, move the item directly
	if actual_transfer >= item.quantity:
		if to_container.add_item(item):
			from_container.remove_item(item)
			return {"success": true, "transferred": actual_transfer, "remaining": 0}
		else:
			return {"success": false, "transferred": 0, "remaining": item.quantity}
	
	# Partial transfer - create new item for destination
	var _transfer_item = item.duplicate()
	_transfer_item.quantity = actual_transfer
	
	if to_container.add_item(_transfer_item):
		# Reduce quantity in source
		item.quantity -= actual_transfer
		return {"success": true, "transferred": actual_transfer, "remaining": item.quantity}
	else:
		return {"success": false, "transferred": 0, "remaining": item.quantity}

func get_container_capacity_info(container_id: String) -> Dictionary:
	"""Get detailed capacity information for a container"""
	var container = get_container(container_id)
	if not container:
		return {}
	
	return {
		"container_name": container.container_name,
		"volume_used": container.get_current_volume(),
		"volume_max": container.max_volume,
		"volume_available": container.get_available_volume(),
		"volume_percentage": container.get_volume_percentage(),
		"item_count": container.items.size(),
		"total_quantity": container.get_total_quantity(),
		"total_mass": container.get_total_mass(),
		"total_value": container.get_total_value()
	}

func find_container_with_space_for_item(item: InventoryItem_Base, exclude_container: String = "") -> String:
	"""Find a container that has space for the given item"""
	for container_id in containers:
		if container_id == exclude_container:
			continue
		
		var container = containers[container_id]
		if container.has_volume_for_item(item):
			return container_id
	
	return ""

func auto_organize_by_volume():
	"""Organize items across containers to optimize volume usage"""
	var all_items: Array[InventoryItem_Base] = []
	var container_capacities: Dictionary = {}
	
	# Collect all items and container info
	for container_id in containers:
		var container = containers[container_id]
		container_capacities[container_id] = {
			"max_volume": container.max_volume,
			"current_volume": 0.0,
			"items": []
		}
		
		for item in container.items.duplicate():
			all_items.append(item)
			container.remove_item(item)
	
	# Sort items by volume (largest first) for better packing
	all_items.sort_custom(func(a, b): return a.get_total_volume() > b.get_total_volume())
	
	# Distribute items to containers with available space
	for item in all_items:
		var placed = false
		
		# Try to find a container with enough space
		for container_id in containers:
			var container = containers[container_id]
			if container.has_volume_for_item(item):
				container.add_item(item)
				placed = true
				break
		
		if not placed:
			# If no container has space, put it back in the first available container
			# This shouldn't happen in a properly managed system
			if containers.size() > 0:
				var first_container = containers[containers.keys()[0]]
				first_container.add_item(item, Vector2i(-1, -1), false)  # Force add without volume check

# Public interface for UI
func get_player_inventory() -> InventoryContainer_Base:
	return player_inventory

func get_player_cargo() -> InventoryContainer_Base:
	return player_cargo

func get_hangar_containers() -> Array[InventoryContainer_Base]:
	return hangar_containers

func _exit_tree():
	save_inventory()
