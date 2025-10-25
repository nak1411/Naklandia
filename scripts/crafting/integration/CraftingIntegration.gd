# CraftingIntegration.gd - Main integration point for crafting system
# Attach this to your Player node
# Place in: scripts/crafting/integration/CraftingIntegration.gd
class_name CraftingIntegration
extends Node

var crafting_manager: CraftingManager
var crafting_window: CraftingStationWindow
var ui_manager: UIManager
var inventory_integration: InventoryIntegration

# Current station info
var current_station_type: String = ""
var current_station_node: Node = null
var is_crafting_open_flag: bool = false


func _ready():
	add_to_group("crafting_integration")
	call_deferred("_initialize_crafting_system")


func _initialize_crafting_system():
	"""Initialize crafting system after other systems are ready"""
	# Get existing managers
	_get_manager_references()

	# Create crafting manager
	_create_crafting_manager()

	# Connect to inventory system
	_connect_to_inventory()

	print("✓ Crafting system initialized")


func _get_manager_references():
	"""Get references to existing managers"""
	# Get UI Manager
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	if ui_managers.size() > 0:
		ui_manager = ui_managers[0]
		print("✓ Found UIManager")
	else:
		push_warning("CraftingIntegration: No UI Manager found")

	# Get Inventory Integration from player
	var player = get_parent()  # Assumes this is attached to player
	if player:
		inventory_integration = player.get_node_or_null("InventoryIntegration")
		if inventory_integration:
			print("✓ Found InventoryIntegration")
		else:
			push_warning("CraftingIntegration: No InventoryIntegration found on player")


func _create_crafting_manager():
	"""Create and configure crafting manager"""
	crafting_manager = CraftingManager.new()
	crafting_manager.name = "CraftingManager"
	add_child(crafting_manager)
	print("✓ Created CraftingManager")


func _connect_to_inventory():
	"""Connect crafting to inventory system"""
	if inventory_integration and inventory_integration.inventory_manager:
		crafting_manager.set_inventory_manager(inventory_integration.inventory_manager)
		print("✓ Connected to InventoryManager")
	else:
		push_warning("CraftingIntegration: No inventory manager found - crafting won't work")


# PUBLIC API


func open_crafting_station(station_type: String, station_node: Node = null):
	"""Open crafting station of specified type"""
	if not ui_manager:
		push_error("CraftingIntegration: No UIManager - cannot open crafting window")
		return

	if not crafting_manager:
		push_error("CraftingIntegration: No CraftingManager - system not initialized")
		return

	# Set current station
	current_station_type = station_type
	current_station_node = station_node
	crafting_manager.set_active_station(station_type)

	# Create or show window
	if not crafting_window or not is_instance_valid(crafting_window):
		_create_crafting_window()
	else:
		crafting_window.show_window()

	# Update window title based on station
	_update_window_title()

	# Disable player input and show mouse
	_set_player_input_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	is_crafting_open_flag = true

	print("✓ Opened crafting station: %s" % station_type)


func _create_crafting_window():
	"""Create the crafting window"""
	crafting_window = CraftingStationWindow.new()
	crafting_window.name = "CraftingStationWindow"

	# Register with UI manager
	ui_manager.register_window(crafting_window, "dialog")

	# Show the window immediately
	crafting_window.show_window()

	# Connect to window close signal
	if crafting_window.has_signal("window_closed"):
		crafting_window.window_closed.connect(_on_crafting_window_closed)

	# Set the crafting manager (async - will populate recipes when ready)
	crafting_window.set_crafting_manager(crafting_manager)

	print("✓ Created CraftingStationWindow")


func _set_player_input_enabled(enabled: bool):
	"""Enable or disable player input"""
	var player_node = get_tree().get_first_node_in_group("player")
	if player_node and player_node.has_method("set_input_enabled"):
		player_node.set_input_enabled(enabled)


func _on_crafting_window_closed():
	"""Handle crafting window being closed"""
	# Re-enable player input
	_set_player_input_enabled(true)

	# Restore mouse mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Clear current station
	current_station_type = ""
	current_station_node = null
	is_crafting_open_flag = false

	print("Crafting window closed")


func _update_window_title():
	"""Update window title based on station type"""
	if not crafting_window:
		return

	match current_station_type:
		"basic_workbench":
			crafting_window.window_title = "Basic Workbench"
		"advanced_fabricator":
			crafting_window.window_title = "Advanced Fabricator"
		"chemical_station":
			crafting_window.window_title = "Chemical Laboratory"
		_:
			crafting_window.window_title = "Crafting Station"


func close_crafting_station():
	"""Close the crafting window"""
	if crafting_window and is_instance_valid(crafting_window):
		crafting_window.hide_window()

	# Re-enable player input
	_set_player_input_enabled(true)

	# Restore mouse mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	current_station_type = ""
	current_station_node = null
	is_crafting_open_flag = false


func is_crafting_open() -> bool:
	"""Check if crafting window is open"""
	return is_crafting_open_flag and crafting_window and is_instance_valid(crafting_window) and crafting_window.visible


func get_crafting_manager() -> CraftingManager:
	"""Get the crafting manager"""
	return crafting_manager


# RECIPE MANAGEMENT


func discover_recipe(recipe_id: String):
	"""Discover a new recipe"""
	if crafting_manager:
		crafting_manager.discover_recipe(recipe_id)


func add_custom_recipe(recipe: CraftingRecipe):
	"""Add a custom recipe"""
	if crafting_manager:
		crafting_manager.add_recipe(recipe)


# STATION INTERACTION


func can_use_station(station_type: String) -> bool:
	"""Check if player can use this station type - extend with your skill system"""
	# TODO: Add skill checks, unlock requirements, etc.
	return true


# DEBUG / TESTING


func add_test_materials():
	"""Add test materials for testing crafting - call this from debug menu"""
	if not inventory_integration or not inventory_integration.inventory_manager:
		push_warning("Cannot add test materials - no inventory manager")
		return

	var inventory_manager = inventory_integration.inventory_manager
	var player_inventory = inventory_manager.get_player_inventory()

	if not player_inventory:
		push_warning("Cannot add test materials - no player inventory")
		return

	# Helper to create and add items
	var add_item = func(id: String, name: String, qty: int):
		var item = InventoryItem_Base.new()
		item.item_id = id
		item.item_name = name
		item.quantity = qty
		item.max_stack_size = 999
		item.volume = 0.1
		item.mass = 0.1
		item.item_type = ItemTypes.Type.RESOURCE
		item.base_value = 10.0
		inventory_manager.add_item_to_container(item, player_inventory.container_id)

	# Add materials for example recipes
	add_item.call("metal_plate", "Metal Plate", 10)
	add_item.call("screw", "Screw", 20)
	add_item.call("pcb_blank", "PCB Blank", 5)
	add_item.call("electronic_component", "Electronic Component", 50)
	add_item.call("solder", "Solder", 30)
	add_item.call("base_chemical", "Base Chemical", 200)
	add_item.call("catalyst", "Catalyst", 20)
	add_item.call("stabilizer", "Stabilizer", 50)

	print("✓ Added crafting test materials to player inventory")


func discover_all_recipes():
	"""Discover all recipes for testing"""
	if not crafting_manager:
		return

	for recipe in crafting_manager.get_all_recipes():
		crafting_manager.discover_recipe(recipe.recipe_id)

	print("✓ Discovered all recipes (%d total)" % crafting_manager.get_all_recipes().size())
