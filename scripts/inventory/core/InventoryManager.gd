# InventoryManager.gd - Simplified coordinator for inventory system
class_name InventoryManager
extends Node

# Signals (delegate to subsystems)
signal container_added(container: InventoryContainer_Base)
signal container_removed(container_id: String)
signal item_added(item: InventoryItem_Base, container: InventoryContainer_Base)
signal item_removed(item: InventoryItem_Base, container: InventoryContainer_Base)
signal item_transferred(item: InventoryItem_Base, from_container: String, to_container: String)
signal transaction_completed(transaction: Dictionary)
signal inventory_loaded
signal inventory_saved

# Core systems
var transaction_manager: InventoryTransactionManager
var save_system: InventorySaveSystem

# Container management
var containers: Dictionary = {}  # container_id -> InventoryContainer_Base
var active_containers: Array[String] = []

# Default containers (references to specialized containers)
var player_inventory: InventoryContainer_Base
var player_cargo: InventoryContainer_Base
var hangar_containers: Array[InventoryContainer_Base] = []

# Settings
var settings: Dictionary = {"auto_stack": true, "auto_sort": false}


func _ready():
	add_to_group("inventory_manager")
	_initialize_core_systems()
	_initialize_default_containers()

	# Initialize save system with references after containers are created
	_update_subsystem_references()

	if save_system.save_exists():
		load_inventory()

	_setup_autosave()


func _initialize_core_systems():
	# Create core subsystems
	transaction_manager = InventoryTransactionManager.new()
	save_system = InventorySaveSystem.new()

	# Connect subsystem signals
	transaction_manager.item_transferred.connect(_on_item_transferred)
	transaction_manager.transaction_completed.connect(_on_transaction_completed)
	save_system.inventory_saved.connect(_on_inventory_saved)
	save_system.inventory_loaded.connect(_on_inventory_loaded)


func _initialize_default_containers():
	# Create default containers (simplified - no longer creates specialized types here)
	player_inventory = InventoryContainer_Base.new("player_inventory", "Personal Inventory", 25.0)
	player_inventory.grid_width = 5
	player_inventory.grid_height = 8
	add_container(player_inventory)

	player_cargo = InventoryContainer_Base.new("player_cargo", "Cargo Hold", 500.0)
	player_cargo.grid_width = 15
	player_cargo.grid_height = 20
	player_cargo.container_type = ContainerTypes.Type.SHIP_CARGO
	add_container(player_cargo)

	# Create hangar containers
	for i in range(3):
		var hangar = InventoryContainer_Base.new("hangar_%d" % i, "Hangar Division %d" % (i + 1), 1000.0)
		hangar.grid_width = 20
		hangar.grid_height = 25
		hangar.container_type = ContainerTypes.Type.HANGAR_DIVISION
		hangar.requires_docking = true
		hangar_containers.append(hangar)
		add_container(hangar)


func _setup_autosave():
	var timer = Timer.new()
	timer.wait_time = 30.0
	timer.timeout.connect(save_inventory)
	timer.autostart = true
	add_child(timer)


func _exit_tree():
	# Save inventory when the manager is about to be removed (game exit)
	print("InventoryManager: Saving inventory on exit...")
	save_inventory()


# Container management (simplified)
func add_container(container: InventoryContainer_Base) -> bool:
	if container.container_id in containers:
		return false

	containers[container.container_id] = container
	_update_subsystem_references()

	# Connect container signals (simplified) - use lambdas to capture container reference
	container.item_added.connect(func(item, pos): _on_container_item_added(item, pos, container))
	container.item_removed.connect(func(item, pos): _on_container_item_removed(item, pos, container))
	container.item_moved.connect(func(item, old_pos, new_pos): _on_container_item_moved(item, old_pos, new_pos))

	container_added.emit(container)
	return true


func sort_container(container_id: String, sort_type: InventorySortType.Type = InventorySortType.Type.BY_NAME):
	var container = get_container(container_id)
	if not container:
		return

	# Auto-stack before sorting
	container.auto_stack_items()

	var sorted_items = container.items.duplicate()

	match sort_type:
		InventorySortType.Type.BY_NAME:
			sorted_items.sort_custom(func(a, b): return a.item_name < b.item_name)
		InventorySortType.Type.BY_TYPE:
			sorted_items.sort_custom(func(a, b): return a.item_type < b.item_type)
		InventorySortType.Type.BY_VOLUME:
			sorted_items.sort_custom(func(a, b): return a.get_total_volume() > b.get_total_volume())
		InventorySortType.Type.BY_VALUE:
			sorted_items.sort_custom(func(a, b): return a.get_total_value() > b.get_total_value())

	# Clear and re-add items in sorted order
	container.clear()
	for item in sorted_items:
		container.add_item(item)


func remove_container(container_id: String) -> bool:
	if not containers.has(container_id):
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
	_update_subsystem_references()

	container_removed.emit(container_id)
	return true


func _update_subsystem_references():
	# Update subsystems with current container references
	if transaction_manager:
		transaction_manager.set_container_registry(containers)
	if save_system and transaction_manager:
		save_system.initialize(containers, transaction_manager.transaction_history, settings)


# Item operations (delegate to transaction manager)
func transfer_item(item: InventoryItem_Base, from_container_id: String, to_container_id: String, target_position: Vector2i = Vector2i(-1, -1), quantity: int = -1) -> bool:
	if not transaction_manager:
		return false

	var from_container = get_container(from_container_id)
	var to_container = get_container(to_container_id)

	if not from_container or not to_container:
		return false

	return transaction_manager.transfer_item(item, from_container, to_container, target_position, quantity)


func move_item(item: InventoryItem_Base, container_id: String, from_position: Vector2i, to_position: Vector2i) -> bool:
	if not transaction_manager:
		return false

	var container = get_container(container_id)
	if not container:
		return false

	return transaction_manager.move_item(item, container, from_position, to_position)


func stack_items(source_item: InventoryItem_Base, target_item: InventoryItem_Base, container_id: String) -> bool:
	if not transaction_manager:
		return false

	var container = get_container(container_id)
	if not container:
		return false

	return transaction_manager.stack_items(source_item, target_item, container)


func split_stack(item: InventoryItem_Base, container_id: String, split_quantity: int) -> InventoryItem_Base:
	if not transaction_manager:
		return null

	var container = get_container(container_id)
	if not container:
		return null

	return transaction_manager.split_stack(item, container, split_quantity)


# Save/Load (delegate to save system)
func save_inventory():
	return save_system.save_inventory()


func load_inventory():
	return save_system.load_inventory()


# Public interface (unchanged for compatibility)
func get_container(container_id: String) -> InventoryContainer_Base:
	return containers.get(container_id, null)


func get_all_containers() -> Array[InventoryContainer_Base]:
	var container_list: Array[InventoryContainer_Base] = []
	for container in containers.values():
		# Skip tearoff views - they shouldn't appear in main lists
		if container.has_meta("is_tearoff_view"):
			continue
		container_list.append(container)
	return container_list


func get_accessible_containers() -> Array[InventoryContainer_Base]:
	var accessible: Array[InventoryContainer_Base] = []

	for container in containers.values():
		# Skip tearoff views - they shouldn't appear in main lists
		if container.has_meta("is_tearoff_view"):
			continue

		# Skip LOOT_CONTAINER types - these are opened via interaction, not shown in main inventory
		if container.container_type == ContainerTypes.Type.LOOT_CONTAINER:
			continue

		if not container.requires_docking:
			accessible.append(container)
		# TODO: Add docking check for hangar containers when docking system is implemented
		# For now, hangar containers are accessible if docking status allows

	return accessible


func get_player_inventory() -> InventoryContainer_Base:
	if player_inventory:
		# Try to find it in containers
		var found_container = containers.get("player_inventory")
		if found_container:
			player_inventory = found_container  # Restore the reference
	return player_inventory


func get_player_cargo() -> InventoryContainer_Base:
	return player_cargo


func get_hangar_containers() -> Array[InventoryContainer_Base]:
	return hangar_containers


# Signal handlers (simplified)
func _on_container_item_added(item: InventoryItem_Base, _position: Vector2i, _container: InventoryContainer_Base):
	if settings.auto_stack:
		# Auto-stack with the container that received the item
		auto_stack_with_container(_container, item)

	# Emit signal for item addition
	item_added.emit(item, _container)


func _on_container_item_removed(_item: InventoryItem_Base, _position: Vector2i, _container: InventoryContainer_Base):
	# Emit signal for item removal with the container reference
	item_removed.emit(_item, _container)


func _on_container_item_moved(_item: InventoryItem_Base, _old_position: Vector2i, _new_position: Vector2i):
	# Handle item movement if needed
	pass


func auto_stack_with_container(container: InventoryContainer_Base, new_item: InventoryItem_Base):
	"""Try to stack a new item with existing items in the container"""
	if not container or not new_item:
		return

	for existing_item in container.items:
		if existing_item == new_item:
			continue

		if new_item.can_stack_with(existing_item):
			var space_available = existing_item.max_stack_size - existing_item.quantity
			if space_available > 0:
				var amount_to_transfer = min(new_item.quantity, space_available)
				existing_item.quantity += amount_to_transfer
				new_item.quantity -= amount_to_transfer

				if new_item.quantity <= 0:
					container.remove_item(new_item)
					break


func _on_item_transferred(_item: InventoryItem_Base, _from_container: String, _to_container: String):
	item_transferred.emit(_item, _from_container, _to_container)


func _on_transaction_completed(transaction: Dictionary):
	transaction_completed.emit(transaction)

	# Defer auto-save to next frame so all related operations complete first
	call_deferred("_deferred_auto_save", transaction.get("type", "unknown"))


func _deferred_auto_save(transaction_type: String):
	"""Deferred auto-save to ensure all operations complete before saving"""
	save_inventory()
	print("InventoryManager: Auto-saved after transaction: ", transaction_type)


func _on_inventory_saved():
	inventory_saved.emit()


func _on_inventory_loaded():
	inventory_loaded.emit()


# Settings management
func set_setting(key: String, value):
	settings[key] = value


func get_setting(key: String, default = null):
	return settings.get(key, default)
