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
@export var interaction_radius: float = 3.0

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
		# Use node path for stable ID across game sessions
		var path_hash = str(get_path()).hash()
		container_id = "container_" + str(path_hash)

	# Set interaction text
	if interaction_text == "Interact":
		interaction_text = "Open " + container_name

	# Find managers with delay to ensure scene is ready
	call_deferred("_delayed_setup")


func _process(_delta: float):
	# Check distance if container is open
	if is_container_open:
		_check_player_distance()


func _delayed_setup():
	"""Setup called after scene is fully ready"""
	await _wait_for_inventory_manager()
	_setup_container()


func _wait_for_inventory_manager():
	"""Wait for the InventoryManager to be ready"""
	var max_attempts = 100  # 10 seconds at 100ms per attempt
	var attempt = 0

	while attempt < max_attempts:
		_find_managers()

		if inventory_manager:
			return

		await get_tree().create_timer(0.1).timeout
		attempt += 1

	push_error("InteractableContainer: Timed out waiting for InventoryManager!")


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
	"""Set up or retrieve the container"""
	if not inventory_manager:
		push_error("InteractableContainer: No inventory manager found!")
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

		# Load saved data if available
		if persistent:
			_load_persistent_data()

	# Ensure the container is not auto-opened or shown in main inventory
	inventory_container.requires_docking = true


func _check_player_distance():
	"""Check if player is within interaction radius"""
	var player = get_player_reference()
	if not player or not is_container_open:
		return

	var distance = global_position.distance_to(player.global_position)

	if distance > interaction_radius:
		close_container()


func interact() -> bool:
	"""Override interact to open container window"""
	if not super.interact():
		return false

	# Check distance before allowing interaction
	var player = get_player_reference()
	if player:
		var distance = global_position.distance_to(player.global_position)
		if distance > interaction_radius:
			return false

	# Prevent rapid multiple interactions
	if is_container_open:
		return true

	if not inventory_container:
		push_error("InteractableContainer: No container data available!")
		# Try to reinitialize
		call_deferred("_delayed_setup")
		return false

	_open_container_window()
	return true


func _open_container_window():
	"""Open container window using the existing tearoff system"""
	# Prevent multiple windows from opening
	if container_window and is_instance_valid(container_window) and not container_window.is_queued_for_deletion():
		container_window.visible = true
		container_window.move_to_front()
		return

	# Clear invalid reference
	if container_window and (not is_instance_valid(container_window) or container_window.is_queued_for_deletion()):
		container_window = null

	# Get main inventory window
	var main_inventory_window = await _get_main_inventory_window()
	if not main_inventory_window:
		push_error("Cannot find main inventory window!")
		return

	# Check if tearoff manager already has this container
	if main_inventory_window.tearoff_manager:
		var existing_tearoff = main_inventory_window.tearoff_manager.get_tearoff_window(inventory_container)
		if existing_tearoff and is_instance_valid(existing_tearoff) and not existing_tearoff.is_queued_for_deletion():
			container_window = existing_tearoff
			is_container_open = true
			container_window.move_to_front()
			return

	# Use tearoff manager to create window properly
	if main_inventory_window.tearoff_manager:
		# Center on screen
		var viewport = get_viewport()
		var window_pos = Vector2(100, 100)
		if viewport:
			var screen_size = viewport.get_visible_rect().size
			var window_size = Vector2(500, 400)
			window_pos = (screen_size - window_size) / 2

		# Create through tearoff manager (prevents duplicates)
		main_inventory_window.tearoff_manager._create_tearoff_window(inventory_container, window_pos, Vector2(500, 400))

		# Wait a frame for window to be created
		await get_tree().process_frame

		# Get the newly created window
		container_window = main_inventory_window.tearoff_manager.get_tearoff_window(inventory_container)

		if not container_window:
			push_error("Failed to create tearoff window through manager!")
			return
	else:
		push_error("Tearoff manager not available!")
		return

	# Mark as interactable container window (don't save window state)
	container_window.set_meta("is_interactable_container", true)
	container_window.set_meta("interactable_container_id", container_id)

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


func _on_container_window_closed():
	"""Handle container window being closed"""
	# Clear state
	is_container_open = false

	# Save the container data when window closes
	if inventory_manager and inventory_manager.has_method("save_inventory"):
		inventory_manager.save_inventory()

	# Clean up external container registration if window still exists
	if container_window and is_instance_valid(container_window):
		if container_window.is_in_group("external_container_windows"):
			container_window.remove_from_group("external_container_windows")

		# Disconnect signal if connected
		if container_window.has_signal("window_closed") and container_window.window_closed.is_connected(_on_container_window_closed):
			container_window.window_closed.disconnect(_on_container_window_closed)

	# Clear reference
	container_window = null

	# Re-enable player input
	var player = get_player_reference()
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(true)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	container_closed.emit()


func close_container():
	"""Manually close the container window"""
	if container_window and is_instance_valid(container_window):
		# Clear state immediately
		is_container_open = false
		var window_to_close = container_window
		container_window = null

		# Queue free to trigger proper cleanup and signal emission
		window_to_close.queue_free()


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


func _load_persistent_data():
	"""Load this container's data from the save file if it exists"""
	if not inventory_manager or not inventory_manager.save_system:
		return

	var save_path = inventory_manager.save_system.save_file_path
	if not FileAccess.file_exists(save_path):
		return

	var file = FileAccess.open(save_path, FileAccess.READ)
	if not file:
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_string) != OK:
		return

	var save_data = json.data
	if not save_data is Dictionary:
		return

	var containers_data = save_data.get("containers", {})
	if containers_data.has(container_id):
		var container_data = containers_data[container_id]
		if container_data is Dictionary and inventory_container.has_method("from_dict"):
			inventory_container.from_dict(container_data)
