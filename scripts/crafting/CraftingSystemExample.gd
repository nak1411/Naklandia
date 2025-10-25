# CraftingSystemExample.gd - Example of how to integrate the crafting system
# This script demonstrates how to set up and use the crafting system
# Attach this to a Node in your game scene

extends Node

var crafting_manager: CraftingManager
var crafting_window: CraftingStationWindow
var ui_manager: UIManager
var inventory_manager: InventoryManager


func _ready():
	# Wait for other systems to initialize
	await get_tree().process_frame

	_setup_crafting_system()
	_add_test_materials()


func _setup_crafting_system():
	"""Initialize the crafting system"""

	# Get or create managers
	ui_manager = _get_or_create_ui_manager()
	inventory_manager = _get_or_create_inventory_manager()

	# Create crafting manager
	crafting_manager = CraftingManager.new()
	crafting_manager.name = "CraftingManager"
	add_child(crafting_manager)

	# Connect to inventory system
	crafting_manager.set_inventory_manager(inventory_manager)

	# Set active station type (this determines which recipes are available)
	crafting_manager.set_active_station("advanced_fabricator")  # Or "basic_workbench", "chemical_station"

	print("✓ Crafting system initialized")


func _get_or_create_ui_manager() -> UIManager:
	"""Get existing UI manager or create one"""
	var managers = get_tree().get_nodes_in_group("ui_manager")
	if managers.size() > 0:
		return managers[0]

	# Create new one if needed
	var manager = UIManager.new()
	manager.name = "UIManager"
	get_tree().root.add_child(manager)
	return manager


func _get_or_create_inventory_manager() -> InventoryManager:
	"""Get existing inventory manager or create one"""
	var managers = get_tree().get_nodes_in_group("inventory_manager")
	if managers.size() > 0:
		return managers[0]

	# In production, you'd have this set up already
	# This is just for demonstration
	print("Warning: No inventory manager found. Crafting system needs inventory integration.")
	return null


func _add_test_materials():
	"""Add test materials to player inventory for demonstration"""
	if not inventory_manager:
		return

	var player_inventory = inventory_manager.get_player_inventory()
	if not player_inventory:
		return

	# Add some test materials
	_add_test_item("metal_plate", "Metal Plate", ItemTypes.Type.RESOURCE, 10)
	_add_test_item("screw", "Screw", ItemTypes.Type.RESOURCE, 20)
	_add_test_item("pcb_blank", "PCB Blank", ItemTypes.Type.RESOURCE, 5)
	_add_test_item("electronic_component", "Electronic Component", ItemTypes.Type.RESOURCE, 50)
	_add_test_item("solder", "Solder", ItemTypes.Type.RESOURCE, 30)
	_add_test_item("base_chemical", "Base Chemical", ItemTypes.Type.RESOURCE, 200)
	_add_test_item("catalyst", "Catalyst", ItemTypes.Type.RESOURCE, 20)
	_add_test_item("stabilizer", "Stabilizer", ItemTypes.Type.RESOURCE, 50)

	print("✓ Test materials added to inventory")


func _add_test_item(id: String, name: String, type: ItemTypes.Type, quantity: int):
	"""Helper to add test items"""
	if not inventory_manager:
		return

	var player_inventory = inventory_manager.get_player_inventory()
	if not player_inventory:
		return

	var item = InventoryItem_Base.new()
	item.item_id = id
	item.item_name = name
	item.item_type = type
	item.quantity = quantity
	item.max_stack_size = 999
	item.volume = 0.1
	item.mass = 0.1
	item.base_value = 10.0

	inventory_manager.add_item_to_container(item, player_inventory.container_id)


func open_crafting_station():
	"""Open the crafting station UI"""
	if not ui_manager or not crafting_manager:
		return

	# Create crafting window if it doesn't exist
	if not crafting_window or not is_instance_valid(crafting_window):
		crafting_window = CraftingStationWindow.new()
		crafting_window.name = "CraftingStationWindow"

		# Set the crafting manager and wait for recipes to load
		await crafting_window.set_crafting_manager(crafting_manager)

		# Register with UI manager
		ui_manager.register_window(crafting_window, "dialog")
	else:
		# Just show existing window
		crafting_window.show_window()

	print("✓ Crafting station opened")


func _input(event):
	"""Example input handling - press C to open crafting"""
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_C:
			open_crafting_station()


# Public API for other scripts


func get_crafting_manager() -> CraftingManager:
	"""Get the crafting manager instance"""
	return crafting_manager


func set_station_type(station_type: String):
	"""Change the active crafting station type"""
	if crafting_manager:
		crafting_manager.set_active_station(station_type)
		print("Crafting station changed to: ", station_type)


func discover_recipe(recipe_id: String):
	"""Discover a new recipe"""
	if crafting_manager:
		crafting_manager.discover_recipe(recipe_id)


func add_custom_recipe(recipe: CraftingRecipe):
	"""Add a custom recipe to the crafting system"""
	if crafting_manager:
		crafting_manager.add_recipe(recipe)
