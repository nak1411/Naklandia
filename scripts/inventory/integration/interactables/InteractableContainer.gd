# InteractableContainer.gd - Container that can be interacted with to open inventory
class_name InteractableContainer
extends Interactable

# Container-specific signals
signal container_opened(container: InventoryContainer_Base)
signal container_closed

# Container properties
@export_group("Container Settings")
@export var container_id: String = ""
@export var container_name: String = "Container"
@export var max_volume: float = 100.0
@export var grid_width: int = 5
@export var grid_height: int = 8
@export var container_type: ContainerTypes.Type = ContainerTypes.Type.LOOT_CONTAINER

@export_group("Container Persistence")
@export var auto_generate_id: bool = true
@export var persistent: bool = true

# Internal container data
var inventory_container: InventoryContainer_Base
var container_window: ContainerTearOffWindow
var is_container_open: bool = false

# References
var inventory_manager: InventoryManager
var ui_manager: Node


func _ready():
	super._ready()

	# Generate unique ID if needed
	if auto_generate_id and container_id == "":
		container_id = "container_" + str(get_instance_id())

	# Set interaction text
	if interaction_text == "Interact":
		interaction_text = "Open " + container_name

	# Find managers with delay to ensure scene is ready
	call_deferred("_delayed_setup")


func _delayed_setup():
	"""Setup called after scene is fully ready"""
	_find_managers()
	_setup_container()


func _find_managers():
	"""Find the inventory manager and UI manager in the scene"""
	var scene_root = get_tree().current_scene

	# Method 1: Try to find by group first
	var managers = get_tree().get_nodes_in_group("inventory_manager")
	if managers.size() > 0:
		inventory_manager = managers[0]

	# Method 2: Look for InventoryIntegration and get its inventory_manager
	if not inventory_manager:
		var integrations = get_tree().get_nodes_in_group("inventory_integration")
		if integrations.size() > 0:
			var integration = integrations[0]
			if integration.has_method("get_inventory_manager"):
				inventory_manager = integration.get_inventory_manager()

		# Alternative: Look for InventoryIntegration nodes directly and check their properties
		if not inventory_manager:
			var all_integrations = _find_nodes_by_class(scene_root, "InventoryIntegration")
			for integration in all_integrations:
				var manager = integration.get("inventory_manager")
				if manager:
					inventory_manager = manager
					break

	# Method 3: Check specifically under Player node
	if not inventory_manager:
		var players = get_tree().get_nodes_in_group("player")
		for player in players:
			var integration = player.get_node_or_null("InventoryIntegration")
			if integration:
				var manager = integration.get("inventory_manager")
				if manager:
					inventory_manager = manager
					break

	# Method 4: Recursive search as fallback
	if not inventory_manager:
		inventory_manager = _find_node_recursive(scene_root, func(node): return node is InventoryManager)

	# Find UI manager
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	if ui_managers.size() > 0:
		ui_manager = ui_managers[0]


func _find_nodes_by_class(node: Node, scene_name: String) -> Array:
	"""Find all nodes with a specific class name"""
	var found_nodes = []

	if node.get_script() and node.get_script().get_global_name() == scene_name:
		found_nodes.append(node)

	for child in node.get_children():
		found_nodes.append_array(_find_nodes_by_class(child, scene_name))

	return found_nodes


func _find_node_recursive(node: Node, condition: Callable) -> Node:
	"""Recursively find a node matching the condition"""
	if not node:
		return null

	if condition.call(node):
		return node

	for child in node.get_children():
		var result = _find_node_recursive(child, condition)
		if result:
			return result

	return null


func _setup_container():
	"""Setup the container data"""
	if not inventory_manager:
		push_error("InteractableContainer: No InventoryManager found in scene!")
		return

	# Check if container already exists
	if inventory_manager.containers.has(container_id):
		inventory_container = inventory_manager.containers[container_id]
	else:
		# Create new container
		inventory_container = InventoryContainer_Base.new(container_id, container_name, max_volume)
		inventory_container.grid_width = grid_width
		inventory_container.grid_height = grid_height
		inventory_container.container_type = container_type
		inventory_container.requires_docking = false

		# Add to inventory manager
		inventory_manager.add_container(inventory_container)

	# Ensure the container is accessible
	var requires_docking = inventory_container.get("requires_docking")
	if requires_docking == null:
		requires_docking = false

	if requires_docking:
		inventory_container.requires_docking = false

	# Fix the active_containers list
	var active_containers = inventory_manager.get("active_containers")
	if active_containers != null:
		active_containers.clear()
		for container_id_key in inventory_manager.containers.keys():
			var container = inventory_manager.containers[container_id_key]
			var container_requires_docking = container.get("requires_docking")
			if container_requires_docking == null:
				container_requires_docking = false

			if not container_requires_docking and not container.has_meta("is_tearoff_view"):
				active_containers.append(container_id_key)


func interact() -> bool:
	"""Override interact to open container window"""
	if not super.interact():
		return false

	# Prevent rapid multiple interactions
	if is_container_open:
		return true

	if not inventory_container:
		push_error("InteractableContainer: No container data available!")
		_setup_container()
		if not inventory_container:
			return false

	# Set a brief flag to prevent multiple rapid interactions
	is_container_open = true
	_open_container_window()
	return true


func _open_container_window():
	"""Open container window using the existing tearoff system"""
	# Prevent multiple windows from opening
	if container_window and is_instance_valid(container_window):
		container_window.visible = true
		container_window.move_to_front()
		return

	# Also check if tearoff manager already has this container
	var main_inventory_window = await _get_main_inventory_window()
	if main_inventory_window and main_inventory_window.tearoff_manager:
		var existing_tearoff = main_inventory_window.tearoff_manager.get_tearoff_window(inventory_container)
		if existing_tearoff and is_instance_valid(existing_tearoff):
			container_window = existing_tearoff
			is_container_open = true
			container_window.move_to_front()
			return

	if not main_inventory_window:
		push_error("Cannot find main inventory window!")
		return

	# Wait for tearoff manager to be ready
	var attempts = 0
	while not main_inventory_window.tearoff_manager and attempts < 10:
		await get_tree().process_frame
		attempts += 1

	var tearoff_manager = main_inventory_window.tearoff_manager
	if not tearoff_manager:
		push_error("No tearoff manager found after waiting!")
		return

	# Check once more if tearoff already exists
	var existing_tearoff = tearoff_manager.get_tearoff_window(inventory_container)
	if existing_tearoff and is_instance_valid(existing_tearoff):
		container_window = existing_tearoff
		is_container_open = true
		container_window.move_to_front()
		return

	# Use the tearoff manager's method to create the tearoff window properly
	tearoff_manager._create_tearoff_window(inventory_container)

	# Wait for creation
	await get_tree().process_frame

	# Get the created window from the tearoff manager
	container_window = tearoff_manager.get_tearoff_window(inventory_container)

	if not container_window:
		push_error("Failed to create tearoff window!")
		return

	# Register as external container window for cross-window drops
	container_window.add_to_group("external_container_windows")
	container_window.set_meta("external_container", inventory_container)
	container_window.set_meta("interactable_container", self)

	# Connect window close signal
	if container_window.has_signal("window_closed"):
		if not container_window.window_closed.is_connected(_on_container_window_closed):
			container_window.window_closed.connect(_on_container_window_closed)

	is_container_open = true

	# Disable player input
	var player = get_player_reference()
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(false)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	container_opened.emit(inventory_container)


func _get_main_inventory_window() -> InventoryWindow:
	"""Get the main inventory window"""
	var inventory_integration = get_tree().get_first_node_in_group("inventory_integration")
	if not inventory_integration:
		return null

	if inventory_integration.has_method("get_inventory_window"):
		var window = inventory_integration.get_inventory_window()
		if window and is_instance_valid(window):
			return window

	# If window doesn't exist or is invalid, try to recreate it
	if inventory_integration.has_method("_recreate_inventory_window"):
		await inventory_integration._recreate_inventory_window()
		if inventory_integration.has_method("get_inventory_window"):
			var new_window = inventory_integration.get_inventory_window()
			if new_window and is_instance_valid(new_window):
				return new_window

	return null


func _handle_cross_window_drop_to_container(drag_data: Dictionary) -> bool:
	"""Handle dropping items from other windows into this container"""
	# Check if our inventory container exists
	if not inventory_container:
		return false

	var source_slot = drag_data.get("source_slot")
	var source_row = drag_data.get("source_row")
	var item: InventoryItem_Base

	# Get the item being dragged
	if source_slot:
		item = source_slot.item
	elif source_row:
		item = source_row.item
	else:
		return false

	if not item:
		return false

	# Get source container ID
	var source_container_id = ""
	if source_slot and source_slot.has_method("get_container_id"):
		source_container_id = source_slot.get_container_id()
	elif source_row and source_row.has_method("_get_container_id"):
		source_container_id = source_row._get_container_id()

	# Don't transfer to same container
	if source_container_id == inventory_container.container_id:
		return false

	# Check if target can accept the item
	if not inventory_container.can_add_item(item):
		return false

	# Calculate transfer amount
	var available_volume = inventory_container.get_available_volume()
	var max_transferable = int(available_volume / item.volume) if item.volume > 0 else item.quantity
	var transfer_amount = min(item.quantity, max_transferable)

	if transfer_amount <= 0:
		return false

	# Direct transfer (bypassing InventoryTransactionManager)
	var source_container = inventory_manager.containers.get(source_container_id)
	var target_container = inventory_manager.containers.get(inventory_container.container_id)

	if source_container and target_container:
		# Create a copy of the item for transfer
		var item_copy = item.duplicate()
		item_copy.quantity = transfer_amount

		# Add to target
		if target_container.add_item(item_copy):
			# Remove from source
			item.quantity -= transfer_amount

			if item.quantity <= 0:
				source_container.remove_item(item)

			# Refresh displays
			if container_window and container_window.content:
				container_window.content.refresh_display()

			# Refresh main inventory
			var inventory_integration = get_tree().get_first_node_in_group("inventory_integration")
			if inventory_integration and inventory_integration.inventory_window and inventory_integration.inventory_window.content:
				inventory_integration.inventory_window.content.refresh_display()

			return true

	return false


func _on_container_window_closed():
	"""Handle container window being closed"""
	is_container_open = false

	# Clean up external container registration
	if container_window and is_instance_valid(container_window):
		container_window.remove_from_group("external_container_windows")

		# Disconnect signal if connected
		if container_window.has_signal("window_closed") and container_window.window_closed.is_connected(_on_container_window_closed):
			container_window.window_closed.disconnect(_on_container_window_closed)

	# Re-enable player input
	var player = get_player_reference()
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(true)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	container_closed.emit()
	container_window = null


func close_container():
	"""Manually close the container window"""
	if container_window and is_instance_valid(container_window):
		# Disconnect signal first
		if container_window.has_signal("window_closed") and container_window.window_closed.is_connected(_on_container_window_closed):
			container_window.window_closed.disconnect(_on_container_window_closed)

		# Close the window
		if container_window.has_method("close_window"):
			container_window.close_window()
		else:
			container_window.queue_free()

		# Handle cleanup manually since signal is disconnected
		_on_container_window_closed()


func get_container() -> InventoryContainer_Base:
	"""Get the container data"""
	return inventory_container


func set_container_items(items: Array[InventoryItem_Base]):
	"""Set the items in this container (useful for pre-populated containers)"""
	if not inventory_container:
		return

	# Clear existing items
	inventory_container.clear()

	# Add new items
	for item in items:
		inventory_container.add_item(item)


func add_item_to_container(item: InventoryItem_Base) -> bool:
	"""Add an item to this container"""
	if not inventory_container:
		return false

	return inventory_container.add_item(item)


func remove_item_from_container(item: InventoryItem_Base) -> bool:
	"""Remove an item from this container"""
	if not inventory_container:
		return false

	return inventory_container.remove_item(item)


func get_container_data() -> Dictionary:
	"""Get container data for interaction events"""
	return {"id": container_id, "name": container_name, "type": container_type, "volume": max_volume, "current_volume": inventory_container.get_current_volume() if inventory_container else 0.0}


func is_container_ready() -> bool:
	"""Check if container is properly initialized"""
	return inventory_container != null and inventory_manager != null


func force_reinitialize():
	"""Force reinitialize the container (useful for debugging)"""
	inventory_container = null
	_delayed_setup()


# Save/Load functionality for persistent containers
func save_container_state() -> Dictionary:
	"""Save the container state for persistence"""
	if not inventory_container:
		return {}

	var save_data = {
		"container_id": container_id,
		"container_name": container_name,
		"max_volume": max_volume,
		"grid_width": grid_width,
		"grid_height": grid_height,
		"container_type": container_type,
		"items": inventory_container.get_save_data() if inventory_container.has_method("get_save_data") else {}
	}

	return save_data


func load_container_state(data: Dictionary):
	"""Load container state from save data"""
	container_id = data.get("container_id", container_id)
	container_name = data.get("container_name", container_name)
	max_volume = data.get("max_volume", max_volume)
	grid_width = data.get("grid_width", grid_width)
	grid_height = data.get("grid_height", grid_height)
	container_type = data.get("container_type", container_type)

	# Recreate container with loaded data
	_setup_container()

	if inventory_container and data.has("items"):
		if inventory_container.has_method("load_save_data"):
			inventory_container.load_save_data(data["items"])
