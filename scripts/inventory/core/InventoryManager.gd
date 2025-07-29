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

func _input(event):
	# Debug key to regenerate sample items
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F10:
			print("F10 pressed - regenerating sample items")
			# Clear all containers completely
			for container in containers.values():
				container.clear()
			
			# Reinitialize containers to make sure they're empty
			_initialize_default_containers()
			
			# Create fresh sample items
			create_sample_items()
			print("Sample items regenerated with correct stack sizes")
		elif event.keycode == KEY_F11:
			print("F11 pressed - debugging item properties")
			var player_inv = get_player_inventory()
			if player_inv:
				for item in player_inv.items:
					print("Item: %s, ID: %s, Qty: %d, Max: %d, Unique: %s" % [
						item.item_name, item.item_id, item.quantity, item.max_stack_size, item.is_unique
					])
		elif event.keycode == KEY_F12:
			print("F12 pressed - fixing existing item IDs")
			var player_inv = get_player_inventory()
			if player_inv:
				for item in player_inv.items:
					# Fix laser crystals
					if item.item_name == "Laser Focusing Crystal":
						item.item_id = "laser_crystal"
						item.max_stack_size = 10
						print("Fixed laser crystal: %s" % item.item_id)
					# Fix blueprints
					elif item.item_name == "Frigate Blueprint":
						item.item_id = "blueprint_frigate"
						item.max_stack_size = 5
						print("Fixed blueprint: %s" % item.item_id)
					# Fix tritanium
					elif item.item_name == "Tritanium Ore":
						item.item_id = "tritanium_ore"
						item.max_stack_size = 1000
						print("Fixed tritanium: %s" % item.item_id)
					# Fix ammo
					elif item.item_name == "Hybrid Charges":
						item.item_id = "ammo_hybrid"
						item.max_stack_size = 500
						print("Fixed ammo: %s" % item.item_id)

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
func add_item_to_container(item: InventoryItem_Base, container_id: String, position: Vector2i = Vector2i(-1, -1), auto_stack: bool = true) -> bool:
	var container = get_container(container_id)
	if not container:
		return false
	
	return container.add_item(item, position, auto_stack)

func remove_item_from_container(item: InventoryItem_Base, container_id: String) -> bool:
	var container = get_container(container_id)
	if not container:
		return false
	return container.remove_item(item)

func transfer_item(item: InventoryItem_Base, from_container_id: String, to_container_id: String, 
				  position: Vector2i = Vector2i(-1, -1), quantity: int = -1) -> bool:
	var from_container = get_container(from_container_id)
	var to_container = get_container(to_container_id)
	
	if not from_container or not to_container:
		return false
	
	if not item in from_container.items:
		return false
	
	# Handle transfer quantity
	var transfer_quantity = quantity if quantity > 0 else item.quantity
	var transfer_item = item
	
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
				
				# Record transaction (reuse the declared variable)
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
		if stackable_item and transfer_quantity <= (stackable_item.max_stack_size - stackable_item.quantity):
			# We can stack completely - handle the stacking
			if transfer_quantity < item.quantity:
				# Partial transfer - reduce source quantity
				item.quantity -= transfer_quantity
				stackable_item.quantity += transfer_quantity
			else:
				# Complete transfer - remove from source and add to target stack
				from_container.remove_item(item)
				stackable_item.quantity += transfer_quantity
			
			# Record transaction
				transaction = {
				"item_name": item.item_name,
				"quantity": transfer_quantity,
				"from_container": from_container_id,
				"to_container": to_container_id,
				"timestamp": Time.get_unix_time_from_system(),
				"stacked": true
			}
			transaction_history.append(transaction)
			
			item_transferred.emit(transfer_item, from_container_id, to_container_id)
			transaction_completed.emit(transaction)
			return true
	
	# Can't stack or only partial stack possible - handle as separate item
	if transfer_quantity < item.quantity:
		transfer_item = item.split_stack(transfer_quantity)
		if not transfer_item:
			return false
	
	# Check if target container can accept the item
	if not to_container.can_add_item(transfer_item):
		# If we split the stack, restore it
		if transfer_quantity < item.quantity and transfer_item:
			item.add_to_stack(transfer_item.quantity)
		return false
	
	# Remove from source container
	var remove_success = from_container.remove_item(transfer_item if transfer_quantity < item.quantity else item)
	if not remove_success:
		# If we split the stack, restore it
		if transfer_quantity < item.quantity and transfer_item:
			item.add_to_stack(transfer_item.quantity)
		return false
	
	# Add to target container
	var add_success = to_container.add_item(transfer_item, position)
	if not add_success:
		# Restore to source container
		from_container.add_item(transfer_item if transfer_quantity < item.quantity else item)
		# Restore split if we made one
		if transfer_quantity < item.quantity and transfer_item:
			item.add_to_stack(transfer_item.quantity)
		return false
	
	# Record transaction
	transaction = {
		"item_name": transfer_item.item_name,
		"quantity": transfer_item.quantity,
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
func create_item(item_id: String, name: String, quantity: int = 1) -> InventoryItem_Base:
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
			"max_stack": 1000,
			"value": 5.0,
			"rarity": InventoryItem_Base.ItemRarity.COMMON
		},
		{
			"id": "laser_crystal",
			"name": "Laser Focusing Crystal",
			"type": InventoryItem_Base.ItemType.MODULE,
			"volume": 5.0,
			"mass": 2.0,
			"max_stack": 10,  # Changed from 1 to 10
			"value": 15000.0,
			"rarity": InventoryItem_Base.ItemRarity.RARE
		},
		{
			"id": "ammo_hybrid",
			"name": "Hybrid Charges",
			"type": InventoryItem_Base.ItemType.AMMUNITION,
			"volume": 0.025,
			"mass": 0.01,
			"max_stack": 500,
			"value": 100.0,
			"rarity": InventoryItem_Base.ItemRarity.COMMON
		},
		{
			"id": "blueprint_frigate",
			"name": "Frigate Blueprint",
			"type": InventoryItem_Base.ItemType.BLUEPRINT,
			"volume": 0.1,
			"mass": 0.1,
			"max_stack": 5,  # Changed from 1 to 5
			"value": 50000.0,
			"rarity": InventoryItem_Base.ItemRarity.EPIC
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
		base_item.item_rarity = item_data.rarity
		
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
				item.item_rarity = item_data.rarity
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

# Public interface for UI
func get_player_inventory() -> InventoryContainer_Base:
	return player_inventory

func get_player_cargo() -> InventoryContainer_Base:
	return player_cargo

func get_hangar_containers() -> Array[InventoryContainer_Base]:
	return hangar_containers

func _exit_tree():
	save_inventory()
