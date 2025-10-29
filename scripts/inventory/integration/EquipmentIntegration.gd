# EquipmentIntegration.gd - Equipment window integration for player
# Attach this to your Player node
class_name EquipmentIntegration
extends Node

var equipment_window: EquipmentWindow
var ui_manager: UIManager
var inventory_integration: InventoryIntegration

var is_equipment_open_flag: bool = false


func _ready():
	add_to_group("equipment_integration")
	call_deferred("_initialize_equipment_system")


func _initialize_equipment_system():
	"""Initialize equipment system after other systems are ready"""
	_get_manager_references()

	print("✓ Equipment system initialized")


func _get_manager_references():
	"""Get references to existing managers"""
	# Get UI Manager
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	if ui_managers.size() > 0:
		ui_manager = ui_managers[0]
		print("✓ Found UIManager")
	else:
		push_warning("EquipmentIntegration: No UI Manager found")

	# Get Inventory Integration from player
	var player = get_parent()
	if player:
		inventory_integration = player.get_node_or_null("InventoryIntegration")
		if inventory_integration:
			print("✓ Found InventoryIntegration")
		else:
			push_warning("EquipmentIntegration: No InventoryIntegration found on player")


func open_equipment_window():
	"""Open the equipment window"""
	print("=== open_equipment_window called ===")

	if not ui_manager:
		push_warning("Cannot open equipment - missing UI manager")
		return

	# Create equipment window if it doesn't exist
	if not equipment_window or not is_instance_valid(equipment_window):
		print("Creating new equipment window...")
		equipment_window = EquipmentWindow.new()
		equipment_window.name = "EquipmentWindow"

		# Register with UI manager
		print("Registering window with UI manager...")
		ui_manager.register_window(equipment_window, "dialog")

		# Wait for window to be ready
		if not equipment_window.is_node_ready():
			print("Waiting for window ready...")
			await equipment_window.ready

		# Wait one more frame to ensure UI is fully built
		await get_tree().process_frame

		print("Window is ready, setting inventory manager...")
		# Set the inventory manager
		if inventory_integration and inventory_integration.inventory_manager:
			equipment_window.set_inventory_manager(inventory_integration.inventory_manager)

			# Register equipment window with save system for persistence
			var inv_manager = inventory_integration.inventory_manager
			if inv_manager.save_system:
				inv_manager.save_system.set_equipment_window(equipment_window)
				print("✓ Equipment window registered with save system")

		# Connect to window closed signal
		if not equipment_window.window_closed.is_connected(_on_equipment_window_closed):
			equipment_window.window_closed.connect(_on_equipment_window_closed)

		# Show the window
		print("Showing window...")
		equipment_window.show_window()

		print("✓ Equipment window created and initialized")
	else:
		print("Showing existing equipment window...")
		equipment_window.show_window()
		equipment_window.refresh_display()

	is_equipment_open_flag = true

	# Disable player input
	_set_player_input_enabled(false)

	# Show mouse
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	print("✓ Equipment window opened, visible=%s" % str(equipment_window.visible))


func close_equipment_window():
	"""Close the equipment window"""
	if equipment_window and is_instance_valid(equipment_window):
		equipment_window.hide_window()

	_set_player_input_enabled(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	is_equipment_open_flag = false


func _on_equipment_window_closed():
	"""Handle equipment window being closed"""
	_set_player_input_enabled(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	is_equipment_open_flag = false

	print("Equipment window closed")


func _set_player_input_enabled(enabled: bool):
	"""Enable/disable player input"""
	var player = get_parent()
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(enabled)


func is_equipment_open() -> bool:
	"""Check if equipment window is open"""
	return is_equipment_open_flag and equipment_window and is_instance_valid(equipment_window) and equipment_window.visible


func get_equipment_window() -> EquipmentWindow:
	"""Get the equipment window"""
	return equipment_window


func equip_item(item: InventoryItem_Base, slot_type: EquipmentWindow.EquipmentSlotType):
	"""Equip an item in the specified slot"""
	if equipment_window:
		equipment_window._equip_item(item, slot_type)


func unequip_item(slot_type: EquipmentWindow.EquipmentSlotType):
	"""Unequip an item from the specified slot"""
	if equipment_window:
		equipment_window._unequip_item(slot_type)


func get_equipped_item(slot_type: EquipmentWindow.EquipmentSlotType) -> InventoryItem_Base:
	"""Get the item equipped in a specific slot"""
	if equipment_window:
		return equipment_window.get_equipped_item(slot_type)
	return null


func _input(event):
	"""Handle input for opening/closing equipment"""
	if event is InputEventKey and event.pressed and not event.echo:
		# Press 'E' to toggle equipment window
		if event.keycode == KEY_C:
			if is_equipment_open():
				close_equipment_window()
			else:
				open_equipment_window()
			get_viewport().set_input_as_handled()
