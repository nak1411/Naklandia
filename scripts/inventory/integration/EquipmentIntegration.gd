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

	# Debug logging
	if equipment_window:
		if is_instance_valid(equipment_window):
			print("Equipment window exists: is_valid=true visible=", equipment_window.visible)
		else:
			print("Equipment window exists but is NOT valid")
	else:
		print("Equipment window is null")

	# Create equipment window if it doesn't exist
	if not equipment_window or not is_instance_valid(equipment_window):
		print("Creating new equipment window...")
		equipment_window = EquipmentWindow.new()
		equipment_window.name = "EquipmentWindow"
		print("  Window created, reference: ", equipment_window)

		# Register with UI manager as "equipment" type (persistent window)
		print("Registering window with UI manager...")
		var canvas = ui_manager.register_window(equipment_window, "equipment")
		print("  Window registered, got canvas: ", canvas)
		if canvas:
			print("  Canvas layer:", canvas.layer, " visible:", canvas.visible)
		print("  Window reference after registration: ", equipment_window)
		print("  Window is_valid after registration: ", is_instance_valid(equipment_window))

		# Wait for window to be ready
		print("  Checking if window is ready: is_node_ready=", equipment_window.is_node_ready(), " is_inside_tree=", equipment_window.is_inside_tree())

		# The window should be ready after being added to the scene tree by UIManager
		# Just wait one frame for UI setup to complete
		await get_tree().process_frame
		print("  After one frame - is_node_ready=", equipment_window.is_node_ready())

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

		# Sync visuals with any equipment that was loaded from save
		_sync_equipment_visuals()

		# Show the window
		print("Showing window...")
		print("  Before show - visible:", equipment_window.visible, " position:", equipment_window.position, " size:", equipment_window.size)
		equipment_window.show_window()
		print("  After show - visible:", equipment_window.visible, " position:", equipment_window.position, " size:", equipment_window.size)
		print("  Parent:", equipment_window.get_parent())
		print("  Is inside tree:", equipment_window.is_inside_tree())

		print("✓ Equipment window created and initialized")
	else:
		print("Showing existing equipment window...")
		# Debug: Check equipment state before showing
		print("  Equipment count before show:", equipment_window.equipped_items.size())
		print("  Window position before show:", equipment_window.position)
		equipment_window.show_window()
		equipment_window.refresh_display()
		# Debug: Check equipment state after refresh
		print("  Equipment count after refresh:", equipment_window.equipped_items.size())
		print("  Window position after refresh:", equipment_window.position)

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
		# Note: Window_Base.hide_window() will call notify_ui_window_closed()
		# which will check if input should be restored

	is_equipment_open_flag = false


func _on_equipment_window_closed():
	"""Handle equipment window being closed via X button"""
	print("=== _on_equipment_window_closed called (X button clicked) ===")

	# Debug: Check window state BEFORE anything else
	print("  equipment_window reference before: ", equipment_window)
	if equipment_window:
		print("  is_instance_valid: ", is_instance_valid(equipment_window))
		if is_instance_valid(equipment_window):
			print("  visible: ", equipment_window.visible)
			print("  is_queued_for_deletion: ", equipment_window.is_queued_for_deletion())

	is_equipment_open_flag = false

	# Only restore player input and hide cursor if NO other UI windows are open
	if _should_restore_player_input():
		print("[EquipmentIntegration] Restoring player input and hiding cursor")
		# Re-enable player input
		_set_player_input_enabled(true)
		# Restore mouse mode
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		print("[EquipmentIntegration] NOT restoring input - other windows still open")

	# Debug: Check window state AFTER setting flag
	print("  equipment_window reference after: ", equipment_window)
	if equipment_window and is_instance_valid(equipment_window):
		print("  Window still valid after close")
	else:
		print("  WARNING: Window is invalid or null after close!")


func _sync_equipment_visuals():
	"""Sync equipment visuals with the equipment window state"""
	var player = get_parent()
	if player and player.has_node("EquipmentVisualManager"):
		var visual_manager = player.get_node("EquipmentVisualManager")
		if visual_manager.has_method("sync_with_equipment_window"):
			visual_manager.sync_with_equipment_window(equipment_window)


func _should_restore_player_input() -> bool:
	"""Check if player input should be restored (no UI windows open)"""
	if not ui_manager:
		print("[EquipmentIntegration] No UI manager found, safe to restore input")
		return true  # No UI manager, safe to restore

	# Check if any UI windows are still open
	var all_windows = ui_manager.get_all_windows()
	var ui_windows_open = 0

	for window in all_windows:
		if not is_instance_valid(window):
			continue

		# Only count visible windows
		if window.visible:
			var window_type = window.get_meta("window_type", "")
			# Count all window types that require input disabled
			if window_type in ["main_inventory", "tearoff", "dialog", "crafting", "character", "equipment", "workbench"]:
				ui_windows_open += 1
				print("[EquipmentIntegration] Found open window: ", window.name, " (type: ", window_type, ")")

	var should_restore = ui_windows_open == 0
	print("[EquipmentIntegration] Open UI windows: ", ui_windows_open, " - Should restore input: ", should_restore)
	return should_restore


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
	# Don't allow equipment toggle when game is paused
	if get_tree().paused:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		# Press 'C' to toggle equipment window
		if event.keycode == KEY_C:
			if is_equipment_open():
				close_equipment_window()
			else:
				open_equipment_window()
			get_viewport().set_input_as_handled()
