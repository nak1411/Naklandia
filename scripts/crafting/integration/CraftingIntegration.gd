# CraftingIntegration.gd - Simplified crafting integration for player
# Attach this to your Player node
class_name CraftingIntegration
extends Node

var crafting_manager: CraftingManager
var crafting_window: CraftingStationWindow
var ui_manager: UIManager
var inventory_integration: InventoryIntegration

var is_crafting_open_flag: bool = false


func _ready():
	add_to_group("crafting_integration")
	call_deferred("_initialize_crafting_system")


func _initialize_crafting_system():
	"""Initialize crafting system after other systems are ready"""
	_get_manager_references()
	_create_crafting_manager()
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
	var player = get_parent()
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
		print("✓ Connected crafting to inventory")
	else:
		push_warning("CraftingIntegration: Could not connect to inventory")


func open_crafting_station(_station_type: String = "", _station_node: Node = null):
	"""Open the crafting window (station parameters ignored in simplified system)"""
	print("=== open_crafting_station called ===")

	if not ui_manager or not crafting_manager:
		push_warning("Cannot open crafting - missing managers")
		push_warning("  ui_manager: %s" % str(ui_manager))
		push_warning("  crafting_manager: %s" % str(crafting_manager))
		return

	# Create crafting window if it doesn't exist
	if not crafting_window or not is_instance_valid(crafting_window):
		print("Creating new crafting window...")
		crafting_window = CraftingStationWindow.new()
		crafting_window.name = "CraftingStationWindow"

		# Register with UI manager FIRST (adds to scene tree) as "crafting" type (persistent window)
		print("Registering window with UI manager...")
		ui_manager.register_window(crafting_window, "crafting")

		# Wait for window to be ready in scene tree
		if not crafting_window.is_node_ready():
			print("Waiting for window ready...")
			await crafting_window.ready

		# Wait one more frame to ensure UI is fully built
		await get_tree().process_frame

		print("Window is ready, setting crafting manager...")
		# Now set the crafting manager
		await crafting_window.set_crafting_manager(crafting_manager)

		# Connect to window closed signal
		if not crafting_window.window_closed.is_connected(_on_crafting_window_closed):
			crafting_window.window_closed.connect(_on_crafting_window_closed)

		# EXPLICITLY SHOW THE WINDOW
		print("Showing window...")
		crafting_window.show_window()

		print("✓ Crafting window created and initialized")
	else:
		print("Showing existing crafting window...")
		crafting_window.show_window()
		crafting_window.refresh_display()

	is_crafting_open_flag = true

	# Disable player input
	_set_player_input_enabled(false)

	# Show mouse
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	print("✓ Crafting window opened, visible=%s" % str(crafting_window.visible))


func close_crafting_station():
	"""Close the crafting window"""
	if crafting_window and is_instance_valid(crafting_window):
		crafting_window.hide_window()
		# UIManager will emit window_closed signal
		# InventoryIntegration will check if input should be restored

	is_crafting_open_flag = false


func _on_crafting_window_closed():
	"""Handle crafting window being closed"""
	# UIManager will emit window_closed signal
	# InventoryIntegration will check if input should be restored
	is_crafting_open_flag = false

	print("Crafting window closed")


func _set_player_input_enabled(enabled: bool):
	"""Enable/disable player input"""
	var player = get_parent()
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(enabled)


func is_crafting_open() -> bool:
	"""Check if crafting window is open"""
	return is_crafting_open_flag and crafting_window and is_instance_valid(crafting_window) and crafting_window.visible


func get_crafting_manager() -> CraftingManager:
	"""Get the crafting manager"""
	return crafting_manager


func discover_recipe(recipe_id: String):
	"""Discover a new recipe"""
	if crafting_manager:
		crafting_manager.discover_recipe(recipe_id)


func add_custom_recipe(recipe: CraftingRecipe):
	"""Add a custom recipe"""
	if crafting_manager:
		crafting_manager.add_recipe(recipe)


func can_use_station(_station_type: String) -> bool:
	"""Check if player can use this station type - stub for backward compatibility"""
	# In the simplified system, all stations are usable
	# Extend this with your skill/unlock system if needed
	return true


func _input(event):
	"""Handle input for opening/closing crafting"""
	# Don't allow crafting toggle when game is paused
	if get_tree().paused:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		# Press 'Q' to toggle crafting
		if event.keycode == KEY_Q:
			if is_crafting_open():
				close_crafting_station()
			else:
				open_crafting_station()
			get_viewport().set_input_as_handled()
