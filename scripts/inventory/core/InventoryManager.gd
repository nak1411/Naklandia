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
var is_split_drop_operation: bool = false

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
	# Ensure it allows all item types by keeping allowed_item_types empty
	player_inventory.allowed_item_types.clear()
	add_container(player_inventory)
	
	# Create player cargo hold (larger space)
	player_cargo = InventoryContainer_Base.new("player_cargo", "Cargo Hold", 500.0)
	player_cargo.grid_width = 15
	player_cargo.grid_height = 20
	player_cargo.container_type = InventoryItem_Base.ContainerType.SHIP_CARGO
	# Ensure cargo also allows all item types
	player_cargo.allowed_item_types.clear()
	add_container(player_cargo)
	
	# Create hangar containers
	for i in range(3):
		var hangar = InventoryContainer_Base.new("hangar_%d" % i, "Hangar Division %d" % (i + 1), 1000.0)
		hangar.grid_width = 20
		hangar.grid_height = 25
		hangar.container_type = InventoryItem_Base.ContainerType.HANGAR_DIVISION
		hangar.requires_docking = true
		# Ensure hangars allow all item types
		hangar.allowed_item_types.clear()
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
	
	print("=== TRANSFER DEBUG START ===")
	print("Item: ", item.item_name, " (", item.item_type, ")")
	print("From container: ", from_container_id if from_container else "NULL")
	print("To container: ", to_container_id if to_container else "NULL")
	print("Position: ", position)
	print("Quantity: ", quantity)
	
	if not from_container or not to_container:
		print("ERROR: Container not found!")
		return false
	
	if not item in from_container.items:
		print("ERROR: Item not in source container!")
		return false
	
	# Handle transfer quantity
	var transfer_quantity = quantity if quantity > 0 else item.quantity
	var transfer_item = item
	
	print("Transfer quantity: ", transfer_quantity)
	print("Item quantity: ", item.quantity)
	
	# Declare transaction variable once at function level
	var transaction: Dictionary
	
	# For same container transfers to specific positions, check if target has stackable item
	if from_container == to_container and position != Vector2i(-1, -1):
		print("Same container transfer to specific position")
		var target_item = _get_item_at_position(to_container, position)
		if target_item and target_item != item and item.can_stack_with(target_item):
			print("Stacking with target item")
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
				print("=== TRANSFER SUCCESS (STACKED) ===")
				return true
	
	# Check if we can stack with existing items in target container (for different containers)
	if from_container != to_container:
		print("Different container transfer - checking for stackable items")
		var stackable_item = to_container.find_stackable_item(item)
		if stackable_item and transfer_quantity <= (stackable_item.max_stack_size - stackable_item.quantity):
			print("Found stackable item, stacking")
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
			print("=== TRANSFER SUCCESS (CROSS-CONTAINER STACK) ===")
			return true
	
	# Can't stack or only partial stack possible - handle as separate item
	print("No stacking possible, handling as separate item")
	if transfer_quantity < item.quantity:
		print("Splitting stack")
		transfer_item = item.split_stack(transfer_quantity)
		if not transfer_item:
			print("ERROR: Failed to split stack!")
			return false
	
	# Check if target container can accept the item
	print("Checking if target container can accept item...")
	print("Target container allowed types: ", to_container.allowed_item_types)
	print("Item type: ", transfer_item.item_type)
	print("Item volume: ", transfer_item.get_total_volume())
	print("Container available volume: ", to_container.get_available_volume())
	
	if not to_container.can_add_item(transfer_item, item if from_container == to_container else null, position):
		print("ERROR: Target container cannot accept item!")
		print("  - Volume check: ", to_container.get_available_volume() >= transfer_item.get_total_volume())
		print("  - Type check: ", to_container.allowed_item_types.is_empty() or transfer_item.item_type in to_container.allowed_item_types)
		print("  - Grid space check: ", to_container.find_free_position() != Vector2i(-1, -1))
		
		# If we split the stack, restore it
		if transfer_quantity < item.quantity and transfer_item:
			item.add_to_stack(transfer_item.quantity)
		print("=== TRANSFER FAILED (CAN'T ADD) ===")
		return false
	
	print("Target container can accept item, proceeding...")
	
	# Remove from source container
	var remove_success = from_container.remove_item(transfer_item if transfer_quantity < item.quantity else item)
	if not remove_success:
		print("ERROR: Failed to remove from source container!")
		# If we split the stack, restore it
		if transfer_quantity < item.quantity and transfer_item:
			item.add_to_stack(transfer_item.quantity)
		print("=== TRANSFER FAILED (REMOVE) ===")
		return false
	
	print("Removed from source container, adding to target...")
	
	# Add to target container
	var add_success = to_container.add_item(transfer_item, position)
	if not add_success:
		print("ERROR: Failed to add to target container!")
		# Restore to source container
		from_container.add_item(transfer_item if transfer_quantity < item.quantity else item)
		# Restore split if we made one
		if transfer_quantity < item.quantity and transfer_item:
			item.add_to_stack(transfer_item.quantity)
		print("=== TRANSFER FAILED (ADD) ===")
		return false
	
	print("Successfully added to target container!")
	
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
	print("=== TRANSFER SUCCESS ===")
	return true
	
func transfer_item_no_stack(item: InventoryItem_Base, from_container_id: String, to_container_id: String, 
				  position: Vector2i = Vector2i(-1, -1), quantity: int = -1) -> bool:
	"""Transfer item without any automatic stacking - used for split operations"""
	var from_container = get_container(from_container_id)
	var to_container = get_container(to_container_id)
	
	print("=== NO-STACK TRANSFER DEBUG START ===")
	print("Item: ", item.item_name, " (", item.item_type, ")")
	print("From container: ", from_container_id if from_container else "NULL")
	print("To container: ", to_container_id if to_container else "NULL")
	print("Position: ", position)
	print("Quantity: ", quantity)
	
	if not from_container or not to_container:
		print("ERROR: Container not found!")
		return false
	
	if not item in from_container.items:
		print("ERROR: Item not in source container!")
		return false
	
	# Handle transfer quantity
	var transfer_quantity = quantity if quantity > 0 else item.quantity
	var transfer_item = item
	
	print("Transfer quantity: ", transfer_quantity)
	print("Item quantity: ", item.quantity)
	
	# For partial transfers, split the stack
	if transfer_quantity < item.quantity:
		print("Splitting stack for partial transfer")
		transfer_item = item.split_stack(transfer_quantity)
		if not transfer_item:
			print("ERROR: Failed to split stack!")
			return false
	
	# Check if target container can accept the item (without stacking)
	print("Checking if target container can accept item (no stacking)...")
	if not to_container.can_add_item(transfer_item, item if from_container == to_container else null, position):
		print("ERROR: Target container cannot accept item!")
		# If we split the stack, restore it
		if transfer_quantity < item.quantity and transfer_item:
			item.add_to_stack(transfer_item.quantity)
		return false
	
	print("Target container can accept item, proceeding...")
	
	# Remove from source container
	var remove_success = from_container.remove_item(transfer_item if transfer_quantity < item.quantity else item)
	if not remove_success:
		print("ERROR: Failed to remove from source container!")
		# If we split the stack, restore it
		if transfer_quantity < item.quantity and transfer_item:
			item.add_to_stack(transfer_item.quantity)
		return false
	
	print("Removed from source container, adding to target...")
	
	# Add to target container with auto_stack disabled and prevent_merge enabled
	var add_success = to_container.add_item(transfer_item, position, false, true)  # auto_stack=false, prevent_merge=true
	if not add_success:
		print("ERROR: Failed to add to target container!")
		# Restore to source container
		from_container.add_item(transfer_item if transfer_quantity < item.quantity else item)
		# Restore split if we made one
		if transfer_quantity < item.quantity and transfer_item:
			item.add_to_stack(transfer_item.quantity)
		return false
	
	print("Successfully added to target container!")
	
	# Record transaction
	var transaction = {
		"item_name": transfer_item.item_name,
		"quantity": transfer_item.quantity,
		"from_container": from_container_id,
		"to_container": to_container_id,
		"timestamp": Time.get_unix_time_from_system(),
		"stacked": false,
		"split_operation": true
	}
	transaction_history.append(transaction)
	
	item_transferred.emit(transfer_item, from_container_id, to_container_id)
	transaction_completed.emit(transaction)
	print("=== NO-STACK TRANSFER SUCCESS ===")
	return true
	
func swap_items_no_stack(item1: InventoryItem_Base, container1_id: String, pos1: Vector2i,
				item2: InventoryItem_Base, container2_id: String, pos2: Vector2i) -> bool:
	"""Swap items without allowing auto-stacking - used for split operations"""
	var container1 = get_container(container1_id)
	var container2 = get_container(container2_id)
	
	if not container1 or not container2:
		print("ERROR: Invalid containers for no-stack swap")
		return false
	
	if not item1 in container1.items or not item2 in container2.items:
		print("ERROR: Items not in their respective containers")
		return false
	
	print("=== NO-STACK SWAP DEBUG START ===")
	print("Item1: ", item1.item_name, " at ", pos1, " in ", container1_id)
	print("Item2: ", item2.item_name, " at ", pos2, " in ", container2_id)
	
	# Check if both containers can accept the swapped items
	if not container1.can_add_item(item2, item1, pos1):
		print("ERROR: Container1 cannot accept item2")
		return false
	
	if not container2.can_add_item(item1, item2, pos2):
		print("ERROR: Container2 cannot accept item1")
		return false
	
	# Perform the swap by temporarily removing both items and then placing them
	var remove1_success = container1.remove_item(item1)
	var remove2_success = container2.remove_item(item2)
	
	if not remove1_success or not remove2_success:
		print("ERROR: Failed to remove items for no-stack swap")
		# Restore items if one removal failed
		if remove1_success:
			container1.add_item(item1, pos1, false, true)  # no auto-stack, prevent merge
		if remove2_success:
			container2.add_item(item2, pos2, false, true)  # no auto-stack, prevent merge
		return false
	
	# Add items to their new positions with auto_stack=false and prevent_merge=true
	var add1_success = container2.add_item(item1, pos2, false, true)  # auto_stack=false, prevent_merge=true
	var add2_success = container1.add_item(item2, pos1, false, true)  # auto_stack=false, prevent_merge=true
	
	if not add1_success or not add2_success:
		print("ERROR: Failed to add items during no-stack swap - restoring original positions")
		# Restore original positions
		if not add1_success:
			container1.add_item(item1, pos1, false, true)
		if not add2_success:
			container2.add_item(item2, pos2, false, true)
		return false
	
	# Record transactions for both items
	var transaction1 = {
		"item_name": item1.item_name,
		"quantity": item1.quantity,
		"from_container": container1_id,
		"to_container": container2_id,
		"timestamp": Time.get_unix_time_from_system(),
		"swapped": true,
		"split_operation": true
	}
	
	var transaction2 = {
		"item_name": item2.item_name,
		"quantity": item2.quantity,
		"from_container": container2_id,
		"to_container": container1_id,
		"timestamp": Time.get_unix_time_from_system(),
		"swapped": true,
		"split_operation": true
	}
	
	transaction_history.append(transaction1)
	transaction_history.append(transaction2)
	
	# Emit signals
	item_transferred.emit(item1, container1_id, container2_id)
	item_transferred.emit(item2, container2_id, container1_id)
	transaction_completed.emit(transaction1)
	transaction_completed.emit(transaction2)
	
	print("=== NO-STACK SWAP SUCCESS ===")
	return true
	
func swap_items(item1: InventoryItem_Base, container1_id: String, pos1: Vector2i,
				item2: InventoryItem_Base, container2_id: String, pos2: Vector2i) -> bool:
	var container1 = get_container(container1_id)
	var container2 = get_container(container2_id)
	
	if not container1 or not container2:
		print("ERROR: Invalid containers for swap")
		return false
	
	if not item1 in container1.items or not item2 in container2.items:
		print("ERROR: Items not in their respective containers")
		return false
	
	print("=== SWAP DEBUG START ===")
	print("Item1: ", item1.item_name, " at ", pos1, " in ", container1_id)
	print("Item2: ", item2.item_name, " at ", pos2, " in ", container2_id)
	
	# Check if both containers can accept the swapped items
	if not container1.can_add_item(item2, item1, pos1):
		print("ERROR: Container1 cannot accept item2")
		return false
	
	if not container2.can_add_item(item1, item2, pos2):
		print("ERROR: Container2 cannot accept item1")
		return false
	
	# Perform the swap by temporarily removing both items and then placing them
	var remove1_success = container1.remove_item(item1)
	var remove2_success = container2.remove_item(item2)
	
	if not remove1_success or not remove2_success:
		print("ERROR: Failed to remove items for swap")
		# Restore items if one removal failed
		if remove1_success:
			container1.add_item(item1, pos1)
		if remove2_success:
			container2.add_item(item2, pos2)
		return false
	
	# Add items to their new positions
	var add1_success = container2.add_item(item1, pos2)
	var add2_success = container1.add_item(item2, pos1)
	
	if not add1_success or not add2_success:
		print("ERROR: Failed to add items during swap - restoring original positions")
		# Restore original positions
		if not add1_success:
			container1.add_item(item1, pos1)
		if not add2_success:
			container2.add_item(item2, pos2)
		return false
	
	# Record transactions for both items
	var transaction1 = {
		"item_name": item1.item_name,
		"quantity": item1.quantity,
		"from_container": container1_id,
		"to_container": container2_id,
		"timestamp": Time.get_unix_time_from_system(),
		"swapped": true
	}
	
	var transaction2 = {
		"item_name": item2.item_name,
		"quantity": item2.quantity,
		"from_container": container2_id,
		"to_container": container1_id,
		"timestamp": Time.get_unix_time_from_system(),
		"swapped": true
	}
	
	transaction_history.append(transaction1)
	transaction_history.append(transaction2)
	
	# Emit signals
	item_transferred.emit(item1, container1_id, container2_id)
	item_transferred.emit(item2, container2_id, container1_id)
	transaction_completed.emit(transaction1)
	transaction_completed.emit(transaction2)
	
	print("=== SWAP SUCCESS ===")
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
	# Don't auto-stack during split operations
	if is_split_drop_operation:
		return
		
	var container = get_container(container_id)
	if not container:
		return
	
	# Rest of existing auto_stack_container logic...
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
	
	# Compact after stacking to eliminate gaps (only if not split operation)
	if not is_split_drop_operation:
		container.compact_items()

func compact_container(container_id: String):
	"""Compacts a container to remove gaps between items"""
	# Don't compact during split operations
	if is_split_drop_operation:
		return
		
	var container = get_container(container_id)
	if container:
		container.compact_items()

func auto_stack_all_containers():
	for container_id in containers:
		auto_stack_container(container_id)

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
	# Don't auto-stack if auto_stack is disabled (which happens during split operations)
	if auto_stack:
		print("Auto-stacking item: ", item.item_name)
		# Find which container this came from by checking all containers
		for container_id in containers:
			var container = containers[container_id]
			if item in container.items:
				auto_stack_container(container_id)
				break
	else:
		print("Auto-stack disabled, skipping for item: ", item.item_name)
					
func _check_for_active_split_operations(node: Node) -> bool:
	"""Recursively check for active split operations in the scene tree"""
	# Check if this node has item_actions with active split operation
	if "item_actions" in node and node.item_actions != null:
		if node.item_actions.has_method("is_split_operation_active") and node.item_actions.is_split_operation_active():
			print("Found active split operation in: ", node.name)
			return true
	
	# Check children
	for child in node.get_children():
		if _check_for_active_split_operations(child):
			return true
	
	return false

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
