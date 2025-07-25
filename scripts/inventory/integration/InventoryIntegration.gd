# InventoryIntegration.gd - Integrates inventory system with player
class_name InventoryIntegration
extends Node

# References
var player: Player
var inventory_manager: InventoryManager
var inventory_window: InventoryWindowUI

# UI Management
var ui_canvas: CanvasLayer
var is_inventory_open: bool = false
var input_consumed: bool = false

# Input action names
const TOGGLE_INVENTORY = "toggle_inventory"

# Signals
signal inventory_toggled(is_open: bool)
signal item_used(item: InventoryItem)

func _ready():
	_setup_input_actions()
	_initialize_inventory_system()
	
	# Wait for everything to be ready
	await get_tree().process_frame
	_setup_ui()
	await get_tree().process_frame
	_connect_signals()
	
	# Add test items AFTER everything is set up
	await get_tree().process_frame
	_add_initial_test_items()

func _add_initial_test_items():
	if inventory_manager:
		# Clear any existing items first
		var player_inv = inventory_manager.get_player_inventory()
		if player_inv:
			player_inv.clear()
		
		# Create sample items
		inventory_manager.create_sample_items()
		
		# Force UI refresh
		if inventory_window:
			inventory_window.refresh_display()

func _setup_input_actions():
	# Add inventory input actions if they don't exist
	if not InputMap.has_action(TOGGLE_INVENTORY):
		InputMap.add_action(TOGGLE_INVENTORY)
		var key_event = InputEventKey.new()
		key_event.keycode = KEY_I
		InputMap.action_add_event(TOGGLE_INVENTORY, key_event)

func _initialize_inventory_system():
	# Create inventory manager
	inventory_manager = InventoryManager.new()
	inventory_manager.name = "InventoryManager"
	add_child(inventory_manager)
	
	# Load inventory data
	inventory_manager.load_inventory()

func _setup_ui():
	# Create UI canvas layer
	ui_canvas = CanvasLayer.new()
	ui_canvas.name = "InventoryUI"
	ui_canvas.layer = 10  # Above other UI
	add_child(ui_canvas)
	
	# Create inventory window (initially hidden)
	inventory_window = InventoryWindowUI.new()
	inventory_window.name = "InventoryWindow"
	inventory_window.visible = false
	ui_canvas.add_child(inventory_window)
	
	# Ensure everything is properly initialized
	await get_tree().process_frame
	
	# Double-check window is hidden
	if inventory_window:
		inventory_window.hide()
		inventory_window.visible = false

func _on_inventory_item_transferred(item: InventoryItem, from_container: String, to_container: String):
	# Only refresh if transfer involves player inventory
	var player_inv = inventory_manager.get_player_inventory()
	if player_inv and (from_container == player_inv.container_id or to_container == player_inv.container_id):
		_schedule_ui_refresh()

func _on_inventory_transaction_completed(transaction: Dictionary):
	# Only refresh if transaction involves player inventory
	var player_inv = inventory_manager.get_player_inventory()
	if player_inv:
		var from_container = transaction.get("from_container", "")
		var to_container = transaction.get("to_container", "")
		if from_container == player_inv.container_id or to_container == player_inv.container_id:
			_schedule_ui_refresh()

var _refresh_scheduled: bool = false

func _schedule_ui_refresh():
	if _refresh_scheduled:
		return
	_refresh_scheduled = true
	call_deferred("_do_ui_refresh")

func _do_ui_refresh():
	_refresh_scheduled = false
	if inventory_window and inventory_window.visible:
		inventory_window.refresh_display()

func _connect_signals():
	# Player reference
	player = get_parent() as Player
	
	# Inventory window signals
	if inventory_window:
		if not inventory_window.window_closed.is_connected(_on_inventory_window_closed):
			inventory_window.window_closed.connect(_on_inventory_window_closed)
		inventory_window.container_switched.connect(_on_container_switched)
	
	# Inventory manager signals
	if inventory_manager:
		inventory_manager.item_transferred.connect(_on_inventory_item_transferred)
		inventory_manager.transaction_completed.connect(_on_inventory_transaction_completed)
		
		# Connect to all container signals for immediate UI updates
		_connect_all_container_signals()

func _connect_all_container_signals():
	if not inventory_manager:
		return
		
	var containers = inventory_manager.get_all_containers()
	for container in containers:
		if not container.item_added.is_connected(_on_container_item_changed):
			container.item_added.connect(_on_container_item_changed)
		if not container.item_removed.is_connected(_on_container_item_changed):
			container.item_removed.connect(_on_container_item_changed)
		if not container.item_moved.is_connected(_on_container_item_moved):
			container.item_moved.connect(_on_container_item_moved)

func _on_container_item_changed(item: InventoryItem, position: Vector2i):
	# Immediate UI refresh when any container changes
	_schedule_ui_refresh()
	# Also refresh the inventory window's container list text
	if inventory_window and inventory_window.visible:
		inventory_window.refresh_container_list()

func _on_container_item_moved(item: InventoryItem, from_pos: Vector2i, to_pos: Vector2i):
	# Immediate UI refresh when items are moved
	_schedule_ui_refresh()

func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_I:
			toggle_inventory()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and is_inventory_open:
			close_inventory()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and !is_inventory_open:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F9:  # Debug key
			refresh_all_ui()  # Force complete UI refresh
			get_viewport().set_input_as_handled()

# Inventory management
func toggle_inventory():
	if input_consumed:
		return
	
	input_consumed = true
	get_tree().process_frame.connect(func(): input_consumed = false, CONNECT_ONE_SHOT)
	
	if not inventory_window:
		print("Inventory window not ready!")
		return
	
	# Check current state and toggle
	if inventory_window.visible:
		# Close the inventory - this will also close dialog windows
		close_inventory()
	else:
		# Open the inventory
		is_inventory_open = true
		inventory_window.position = Vector2i(((DisplayServer.screen_get_size().x / 2) - 200) / 2, ((DisplayServer.screen_get_size().y / 2) - 200) / 2)
		inventory_window.visible = true
		inventory_window.grab_focus()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	inventory_toggled.emit(is_inventory_open)

func _on_inventory_window_closed():
	# Close any open dialog windows when inventory window is closed
	if inventory_window and inventory_window.item_actions and inventory_window.item_actions.has_method("close_all_dialogs"):
		inventory_window.item_actions.close_all_dialogs()
	
	is_inventory_open = false
	# Ensure mouse mode is captured for gameplay
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	inventory_toggled.emit(is_inventory_open)

func open_inventory():
	if not inventory_window:
		print("Inventory window not ready!")
		return
	if not is_inventory_open:
		toggle_inventory()

func close_inventory():
	if not inventory_window:
		return
	if is_inventory_open:
		# Close any open dialog windows first
		if inventory_window and inventory_window.item_actions and inventory_window.item_actions.has_method("close_all_dialogs"):
			inventory_window.item_actions.close_all_dialogs()
		
		inventory_window.visible = false
		is_inventory_open = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		inventory_toggled.emit(is_inventory_open)

# Item management
func add_item_to_inventory(item: InventoryItem) -> bool:
	var player_inventory = inventory_manager.get_player_inventory()
	var success = inventory_manager.add_item_to_container(item, player_inventory.container_id)
	
	if success:
		# Show pickup notification
		_show_item_pickup_notification(item)
	
	return success

func remove_item_from_inventory(item: InventoryItem) -> bool:
	var player_inventory = inventory_manager.get_player_inventory()
	return inventory_manager.remove_item_from_container(item, player_inventory.container_id)

func has_item(item_id: String) -> bool:
	var result = inventory_manager.find_item_globally(item_id)
	return not result.is_empty()

func get_item_quantity(item_id: String) -> int:
	var results = inventory_manager.find_items_by_name_globally(item_id)
	var total_quantity = 0
	
	for result in results:
		total_quantity += result.item.quantity
	
	return total_quantity

func consume_item(item_id: String, quantity: int = 1) -> bool:
	var result = inventory_manager.find_item_globally(item_id)
	if result.is_empty():
		return false
	
	var item = result.item as InventoryItem
	var container_id = result.container_id as String
	
	if item.quantity >= quantity:
		item.remove_from_stack(quantity)
		if item.quantity <= 0:
			inventory_manager.remove_item_from_container(item, container_id)
		return true
	
	return false

# Interaction with game systems
func pickup_item(interactable_item: Node):
	# Convert world item to inventory item
	var item = _convert_world_item_to_inventory_item(interactable_item)
	if item:
		var success = add_item_to_inventory(item)
		if success:
			# Remove from world
			interactable_item.queue_free()
			
			# Play pickup sound
			_play_pickup_sound()

func drop_item(item: InventoryItem, world_position: Vector3):
	# Remove from inventory
	var player_inventory = inventory_manager.get_player_inventory()
	var success = inventory_manager.remove_item_from_container(item, player_inventory.container_id)
	
	if success:
		# Create world item
		_create_world_item_from_inventory_item(item, world_position)

# Crafting integration
func has_recipe_materials(recipe: Dictionary) -> bool:
	var required_materials = recipe.get("materials") if recipe.has("materials") else {}
	
	for material_id in required_materials:
		var required_quantity = required_materials[material_id]
		var available_quantity = get_item_quantity(material_id)
		
		if available_quantity < required_quantity:
			return false
	
	return true

func consume_recipe_materials(recipe: Dictionary) -> bool:
	if not has_recipe_materials(recipe):
		return false
	
	var required_materials = recipe.get("materials") if recipe.has("materials") else {}
	
	for material_id in required_materials:
		var required_quantity = required_materials[material_id]
		if not consume_item(material_id, required_quantity):
			return false  # This shouldn't happen if has_recipe_materials passed
	
	return true

# Equipment system integration
func equip_item(item: InventoryItem) -> bool:
	# TODO: Integrate with equipment system
	match item.item_type:
		InventoryItem.ItemType.WEAPON:
			return _equip_weapon(item)
		InventoryItem.ItemType.ARMOR:
			return _equip_armor(item)
		InventoryItem.ItemType.MODULE:
			return _equip_module(item)
		_:
			return false

func _equip_weapon(item: InventoryItem) -> bool:
	# TODO: Implement weapon equipping
	print("Equipping weapon: ", item.item_name)
	return true

func _equip_armor(item: InventoryItem) -> bool:
	# TODO: Implement armor equipping
	print("Equipping armor: ", item.item_name)
	return true

func _equip_module(item: InventoryItem) -> bool:
	# TODO: Implement module equipping
	print("Equipping module: ", item.item_name)
	return true

# Event handlers
func _on_container_switched(container: InventoryContainer):
	print("Switched to container: ", container.container_name)

func _on_item_transferred(item: InventoryItem, from_container: String, to_container: String):
	print("Item transferred: %s from %s to %s" % [item.item_name, from_container, to_container])

func _on_transaction_completed(transaction: Dictionary):
	_show_transaction_notification(transaction)

# Item usage
func _use_item(item: InventoryItem):
	match item.item_type:
		InventoryItem.ItemType.CONSUMABLE:
			_use_consumable_item(item)
		InventoryItem.ItemType.WEAPON, InventoryItem.ItemType.ARMOR, InventoryItem.ItemType.MODULE:
			equip_item(item)
		InventoryItem.ItemType.SKILL_BOOK:
			_learn_skill_book(item)
		_:
			print("Cannot use item: ", item.item_name)
	
	item_used.emit(item)

func _use_consumable_item(item: InventoryItem):
	# TODO: Implement consumable effects
	match item.item_name.to_lower():
		"health potion":
			_heal_player(50)
		"energy drink":
			_restore_energy(30)
		"repair kit":
			_repair_equipment(25)
		_:
			print("Unknown consumable: ", item.item_name)
	
	# Consume one item
	consume_item(item.item_id, 1)

func _learn_skill_book(item: InventoryItem):
	# TODO: Integrate with skill system
	print("Learning skill: ", item.item_name)
	consume_item(item.item_id, 1)

# Player effects
func _heal_player(amount: int):
	# TODO: Integrate with player health system
	print("Healing player for %d health" % amount)

func _restore_energy(amount: int):
	# TODO: Integrate with player energy system
	print("Restoring %d energy" % amount)

func _repair_equipment(amount: int):
	# TODO: Integrate with equipment durability system
	print("Repairing equipment for %d points" % amount)

# World item conversion
func _convert_world_item_to_inventory_item(world_item: Node) -> InventoryItem:
	# TODO: Convert world objects to inventory items
	# This would read properties from the world object and create an InventoryItem
	
	# Example implementation
	var item = InventoryItem.new()
	item.item_name = world_item.name
	var fallback_id = world_item.name.to_lower().replace(" ", "_")
	item.item_id = world_item.get("item_id") if world_item.has("item_id") else fallback_id
	
	# Set properties based on world item
	if world_item.has_method("get_item_properties"):
		var properties = world_item.get_item_properties()
		item.volume = properties.get("volume") if properties.has("volume") else 1.0
		item.mass = properties.get("mass") if properties.has("mass") else 1.0
		item.base_value = properties.get("value") if properties.has("value") else 0.0
		item.item_type = properties.get("type") if properties.has("type") else InventoryItem.ItemType.MISCELLANEOUS
	
	return item

func _create_world_item_from_inventory_item(item: InventoryItem, position: Vector3):
	# TODO: Create world objects from inventory items
	# This would spawn a physical object in the world that can be picked up
	print("Dropping item %s at position %s" % [item.item_name, position])

# UI notifications
func _show_item_pickup_notification(item: InventoryItem):
	# Create pickup notification
	var notification = _create_notification("+ %s" % item.item_name, Color.GREEN)
	_show_notification(notification, 2.0)

func _show_transaction_notification(transaction: Dictionary):
	var message = "Moved %s to %s" % [transaction.item_name, transaction.to_container]
	var notification = _create_notification(message, Color.CYAN)
	_show_notification(notification, 1.5)

func _create_notification(text: String, color: Color) -> Label:
	var notification = Label.new()
	notification.text = text
	notification.add_theme_color_override("font_color", color)
	notification.add_theme_color_override("font_shadow_color", Color.BLACK)
	notification.add_theme_constant_override("shadow_offset_x", 1)
	notification.add_theme_constant_override("shadow_offset_y", 1)
	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return notification

func _show_notification(notification: Label, duration: float):
	ui_canvas.add_child(notification)
	
	# Position at top of screen
	notification.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	notification.position.y = 50
	
	# Animate
	var tween = create_tween()
	tween.parallel().tween_property(notification, "position:y", 10, 0.3)
	tween.parallel().tween_property(notification, "modulate:a", 1.0, 0.3)
	
	# Wait then fade out
	tween.tween_delay(duration - 0.6)
	tween.parallel().tween_property(notification, "position:y", -30, 0.3)
	tween.parallel().tween_property(notification, "modulate:a", 0.0, 0.3)
	
	tween.tween_callback(func(): notification.queue_free())

# Audio
func _play_pickup_sound():
	# TODO: Play pickup sound effect
	pass

# Save/Load integration
func save_inventory_state() -> Dictionary:
	var state = {
		"inventory_manager": {},
		"settings": {}
	}
	
	if inventory_manager:
		# Inventory manager handles its own serialization
		pass
	
	return state

func load_inventory_state(state: Dictionary):
	var settings = state.get("settings", {})
	# No HUD settings to load

# Public interface
func get_inventory_manager() -> InventoryManager:
	return inventory_manager

func get_inventory_window() -> InventoryWindowUI:
	return inventory_window

func is_inventory_window_open() -> bool:
	return is_inventory_open

# Debug functions
func add_test_items():
	if inventory_manager:
		inventory_manager.create_sample_items()

func print_inventory_status():
	if inventory_manager:
		inventory_manager.print_inventory_status()

func clear_all_inventories():
	if inventory_manager:
		for container in inventory_manager.get_all_containers():
			container.clear()

func refresh_all_ui():
	"""Refresh window display"""
	_schedule_ui_refresh()

func refresh_window():
	if inventory_window:
		inventory_window.refresh_display()
