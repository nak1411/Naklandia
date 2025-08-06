# InventoryManager.gd - Simplified coordinator for inventory system
class_name InventoryManager
extends Node

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
var settings: Dictionary = {
	"auto_stack": true,
	"auto_sort": false
}

# Signals (delegate to subsystems)
signal container_added(container: InventoryContainer_Base)
signal container_removed(container_id: String)
signal item_transferred(item: InventoryItem_Base, from_container: String, to_container: String)
signal transaction_completed(transaction: Dictionary)
signal inventory_loaded()
signal inventory_saved()

func _ready():
	_initialize_core_systems()
	_initialize_default_containers()
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
	var timer = Timer.new()
	timer.wait_time = 30.0
	timer.timeout.connect(save_inventory)
	timer.autostart = true
	add_child(timer)

# Container management (simplified)
func add_container(container: InventoryContainer_Base) -> bool:
	if container.container_id in containers:
		return false
	
	containers[container.container_id] = container
	_update_subsystem_references()
	
	# Connect container signals (simplified)
	container.item_added.connect(_on_container_item_added)
	container.item_removed.connect(_on_container_item_removed)
	container.item_moved.connect(_on_container_item_moved)
	
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
		InventorySortType.Type.BY_VALUE:
			sorted_items.sort_custom(func(a, b): return a.get_total_value() > b.get_total_value())
		InventorySortType.Type.BY_VOLUME:
			sorted_items.sort_custom(func(a, b): return a.get_total_volume() > b.get_total_volume())
	
	# Clear container and re-add items in sorted order
	container.clear()
	for item in sorted_items:
		container.add_item(item)

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
	_update_subsystem_references()
	
	container_removed.emit(container_id)
	return true

func _update_subsystem_references():
	"""Update references in subsystems when containers change"""
	transaction_manager.set_container_registry(containers)
	save_system.initialize(containers, transaction_manager.transaction_history, settings)

# Delegate operations to subsystems
func transfer_item(item: InventoryItem_Base, from_container_id: String, to_container_id: String, position: Vector2i = Vector2i(-1, -1), quantity: int = 0) -> bool:
	return transaction_manager.transfer_item(item, from_container_id, to_container_id, position, quantity)

func save_inventory():
	save_system.save_inventory()

func load_inventory():
	return save_system.load_inventory()

# Public interface (unchanged for compatibility)
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
		# TODO: Add docking check for hangar containers when docking system is implemented
		# For now, hangar containers are accessible if docking status allows
	
	return accessible

func get_player_inventory() -> InventoryContainer_Base:
	return player_inventory

func get_player_cargo() -> InventoryContainer_Base:
	return player_cargo

func get_hangar_containers() -> Array[InventoryContainer_Base]:
	return hangar_containers

# Signal handlers (simplified)
func _on_container_item_added(item: InventoryItem_Base, position: Vector2i):
	if settings.auto_stack:
		# Find which container this came from
		for container in containers.values():
			if item in container.items:
				auto_stack_container(container.container_id)
				break

func _on_container_item_removed(_item: InventoryItem_Base, _position: Vector2i):
	pass

func _on_container_item_moved(_item: InventoryItem_Base, _from_pos: Vector2i, _to_pos: Vector2i):
	pass

func _on_item_transferred(item: InventoryItem_Base, from_container: String, to_container: String):
	item_transferred.emit(item, from_container, to_container)

func _on_transaction_completed(transaction: Dictionary):
	transaction_completed.emit(transaction)

func _on_inventory_saved():
	inventory_saved.emit()

func _on_inventory_loaded():
	inventory_loaded.emit()

# Keep existing methods for compatibility but simplify implementation
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

# TODO: Implement remaining methods by delegating to appropriate subsystems
func auto_stack_container(container_id: String):
	# Implement auto-stacking logic
	pass

func _exit_tree():
	save_inventory()