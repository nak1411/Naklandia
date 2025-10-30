class_name EquipmentVisualManager
extends Node

## Manages 3D model visuals for equipped items using a socket-based system
## Sockets are EquipmentSocket nodes placed in the scene tree with editor-defined transforms

# Reference to the player character
var player: CharacterBody3D

# Dictionary mapping socket names to EquipmentSocket nodes
var sockets: Dictionary = {}

# Dictionary mapping equipment slot types to currently active model instances
# Key: EquipmentSlotType enum value, Value: Node3D instance
var active_models: Dictionary = {}

func _ready():
	player = get_parent()
	_discover_sockets()

	# Wait a bit for the game to load, then sync with equipment state
	call_deferred("_sync_on_startup")

## Find all EquipmentSocket nodes in the player hierarchy
func _discover_sockets():
	var socket_nodes = _find_nodes_by_type(player, EquipmentSocket)
	for socket in socket_nodes:
		if socket is EquipmentSocket:
			sockets[socket.socket_name] = socket
			print("EquipmentVisualManager: Discovered socket '", socket.socket_name, "' (", socket.socket_category, ")")

	if sockets.is_empty():
		push_warning("EquipmentVisualManager: No EquipmentSocket nodes found in player hierarchy")

## Recursively find all nodes of a specific type
func _find_nodes_by_type(node: Node, type) -> Array:
	var found_nodes = []
	if is_instance_of(node, type):
		found_nodes.append(node)
	for child in node.get_children():
		found_nodes.append_array(_find_nodes_by_type(child, type))
	return found_nodes

## Equip a 3D model for the given item in the specified slot
func equip_visual(item: InventoryItem_Base, slot_type: int) -> void:
	print("EquipmentVisualManager: equip_visual called for item: ", item.item_id if item else "null")

	if not item:
		return

	# Get model path from item metadata
	var model_path = item.get_meta("model_path", "")
	print("  model_path: ", model_path)
	if model_path.is_empty():
		print("EquipmentVisualManager: No model_path found for item: ", item.item_id)
		return

	# Get socket name from item metadata
	var socket_name = item.get_meta("equipment_socket", "")
	print("  equipment_socket: ", socket_name)
	if socket_name.is_empty():
		push_warning("EquipmentVisualManager: No equipment_socket specified for item: ", item.item_id)
		return

	# Find the socket
	print("  Available sockets: ", sockets.keys())
	if not socket_name in sockets:
		push_error("EquipmentVisualManager: Socket '", socket_name, "' not found for item: ", item.item_id)
		return

	var socket: EquipmentSocket = sockets[socket_name]
	print("  Found socket: ", socket.name, " enabled: ", socket.enabled)
	if not socket.enabled:
		push_warning("EquipmentVisualManager: Socket '", socket_name, "' is disabled")
		return

	# Check if file exists
	if not ResourceLoader.exists(model_path):
		push_error("EquipmentVisualManager: Model file not found: ", model_path)
		return

	# Remove any existing model in this slot first
	unequip_visual(slot_type)

	# Load and instantiate the model
	var model_scene = load(model_path)
	if not model_scene:
		push_error("EquipmentVisualManager: Failed to load model: ", model_path)
		return

	var model_instance = model_scene.instantiate()
	if not model_instance:
		push_error("EquipmentVisualManager: Failed to instantiate model: ", model_path)
		return

	# The socket's transform defines where the model appears
	# Simply attach the model as a child of the socket
	socket.add_child(model_instance)

	# Reset model's local transform since socket position is already set in editor
	model_instance.transform = Transform3D.IDENTITY

	# Ensure the model is visible
	if model_instance.has_method("set_visible"):
		model_instance.set_visible(true)
	model_instance.visible = true

	# Store reference to active model
	active_models[slot_type] = model_instance

	print("EquipmentVisualManager: Equipped '", item.item_id, "' to socket '", socket_name, "'")
	print("  Model instance: ", model_instance)
	print("  Model visible: ", model_instance.visible)
	print("  Model global_transform: ", model_instance.global_transform)
	print("  Socket path: ", socket.get_path())
	print("  Model children count: ", socket.get_child_count())

## Remove the 3D model from the specified equipment slot
func unequip_visual(slot_type: int) -> void:
	if slot_type in active_models:
		var model_instance = active_models[slot_type]
		if is_instance_valid(model_instance):
			model_instance.queue_free()
		active_models.erase(slot_type)
		print("EquipmentVisualManager: Unequipped model from slot ", slot_type)

## Clear all equipped models
func clear_all_visuals() -> void:
	for slot_type in active_models.keys():
		unequip_visual(slot_type)

## Get the currently equipped model in a slot (if any)
func get_equipped_model(slot_type: int) -> Node3D:
	return active_models.get(slot_type, null)

## Sync visuals on startup by finding equipment integration
func _sync_on_startup() -> void:
	print("EquipmentVisualManager: Attempting to sync on startup")

	# Find the equipment integration
	if not player.has_node("EquipmentIntegration"):
		print("EquipmentVisualManager: No EquipmentIntegration found on player")
		return

	var equipment_integration = player.get_node("EquipmentIntegration")

	# Try to get existing equipment window
	var equipment_window = equipment_integration.get_equipment_window()

	if equipment_window and is_instance_valid(equipment_window):
		print("EquipmentVisualManager: Found existing equipment window, syncing visuals")
		sync_with_equipment_window(equipment_window)
		return

	# Equipment window doesn't exist yet - we need to create it invisibly to get equipment state
	# Find the inventory integration to get the save system
	if not player.has_node("InventoryIntegration"):
		print("EquipmentVisualManager: No InventoryIntegration found, can't check equipment state")
		return

	var inventory_integration = player.get_node("InventoryIntegration")
	if not inventory_integration.inventory_manager:
		print("EquipmentVisualManager: No inventory manager found")
		return

	var save_system = inventory_integration.inventory_manager.save_system
	if not save_system:
		print("EquipmentVisualManager: No save system found")
		return

	# Check if there's cached equipment data
	if not save_system.cached_equipment_data.is_empty():
		print("EquipmentVisualManager: Found cached equipment data, creating window to apply it")
		# Force create the equipment window (but don't show it)
		_force_create_equipment_window_for_visuals(equipment_integration)
	else:
		print("EquipmentVisualManager: No cached equipment data, nothing to display")

## Force create equipment window invisibly just to load equipment state
func _force_create_equipment_window_for_visuals(equipment_integration) -> void:
	# Create the window without showing it
	var equipment_window = EquipmentWindow.new()
	equipment_window.name = "EquipmentWindow"

	# Get the UI manager
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	if ui_managers.size() == 0:
		print("EquipmentVisualManager: No UI manager found, can't create equipment window")
		equipment_window.queue_free()
		return

	var ui_manager = ui_managers[0]

	# Register with UI manager but keep it hidden
	ui_manager.register_window(equipment_window, "equipment")
	equipment_window.visible = false  # Keep it invisible

	# Set the window reference in the integration
	equipment_integration.equipment_window = equipment_window

	# Wait for it to be ready
	await get_tree().process_frame

	# Set inventory manager
	var inventory_integration = player.get_node("InventoryIntegration")
	if inventory_integration and inventory_integration.inventory_manager:
		equipment_window.set_inventory_manager(inventory_integration.inventory_manager)

		# Register with save system - this will apply cached equipment data
		var save_system = inventory_integration.inventory_manager.save_system
		if save_system:
			save_system.set_equipment_window(equipment_window)
			print("EquipmentVisualManager: Equipment window registered, cached data applied")

			# Now sync visuals
			await get_tree().process_frame
			sync_with_equipment_window(equipment_window)

## Sync visuals with equipment window state (useful for initialization)
func sync_with_equipment_window(equipment_window) -> void:
	if not equipment_window:
		return

	print("EquipmentVisualManager: Syncing visuals with equipment window")

	# Clear all current visuals first
	clear_all_visuals()

	# Re-equip all items that are currently equipped
	for slot_type in equipment_window.equipped_items:
		var item = equipment_window.equipped_items[slot_type]
		if item:
			print("  Syncing slot ", slot_type, ": ", item.item_id)
			equip_visual(item, slot_type)
