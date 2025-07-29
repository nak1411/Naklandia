# InventoryIntegration.gd - Clean production version with CanvasLayer support
class_name InventoryIntegration
extends Node

# References
var player: Player
var inventory_manager: InventoryManager
var inventory_window: InventoryWindow
var inventory_canvas: CanvasLayer

# UI Management
var is_inventory_open: bool = false
var setup_complete: bool = false

# Position saving
var saved_position: Vector2i = Vector2i.ZERO
var position_save_file: String = "user://inventory_window_position.dat"

# Input action names
const TOGGLE_INVENTORY = "toggle_inventory"

# Signals
signal inventory_toggled(is_open: bool)
signal setup_completed()

func _ready():
	# Set process mode to work even when paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Find the existing InventoryLayer in the scene hierarchy
	var scene_root = get_tree().current_scene
	inventory_canvas = scene_root.get_node_or_null("InventoryLayer")
	
	if not inventory_canvas:
		push_error("InventoryLayer not found in scene! Please add a CanvasLayer named 'InventoryLayer' to your scene.")
		return
	
	# Setup input actions
	_setup_input_actions()
	
	# Create inventory manager
	inventory_manager = InventoryManager.new()
	inventory_manager.name = "InventoryManager"
	add_child(inventory_manager)
	inventory_manager.load_inventory()
	
	# Wait for scene to be ready
	await get_tree().process_frame
	
	# Create inventory window
	inventory_window = InventoryWindow.new()
	inventory_window.name = "InventoryWindow"
	
	# Add to the existing InventoryLayer
	inventory_canvas.add_child(inventory_window)
	
	# Wait for initialization
	await get_tree().process_frame
	
	# Set inventory manager on the window
	if inventory_window.has_method("set_inventory_manager"):
		inventory_window.set_inventory_manager(inventory_manager)
	
	# Connect signals
	_connect_signals()
	
	# Load saved position
	_load_and_apply_position()
	
	# Hide the window initially
	inventory_window.visible = false
	
	# Add test items
	_add_initial_test_items()
	
	setup_complete = true
	setup_completed.emit()

func _setup_input_actions():
	if not InputMap.has_action(TOGGLE_INVENTORY):
		InputMap.add_action(TOGGLE_INVENTORY)
	else:
		InputMap.action_erase_events(TOGGLE_INVENTORY)
	
	var key_event = InputEventKey.new()
	key_event.keycode = KEY_I
	key_event.pressed = true
	InputMap.action_add_event(TOGGLE_INVENTORY, key_event)

func _connect_signals():
	# Connect inventory manager signals
	if inventory_manager.has_signal("item_added"):
		inventory_manager.item_added.connect(_on_item_added)
	if inventory_manager.has_signal("item_removed"):
		inventory_manager.item_removed.connect(_on_item_removed)
	
	# Connect inventory window signals
	if inventory_window:
		inventory_window.container_switched.connect(_on_container_switched)
		inventory_window.window_resized.connect(_on_window_resized)

func _load_and_apply_position():
	var loaded_position = _load_window_position()
	if loaded_position != Vector2i.ZERO:
		saved_position = loaded_position
		
		if _is_position_valid(saved_position):
			inventory_window.position = saved_position
		else:
			inventory_window.center_on_screen()
	else:
		inventory_window.center_on_screen()

func _add_initial_test_items():
	if inventory_manager:
		var player_inv = inventory_manager.get_player_inventory()
		if player_inv:
			player_inv.clear()
		inventory_manager.create_sample_items()

func _input(event):
	if not setup_complete:
		return
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_I:
		toggle_inventory()
		get_viewport().set_input_as_handled()

func toggle_inventory():
	if not inventory_window:
		return
	
	is_inventory_open = !is_inventory_open
	
	if is_inventory_open:
		# Show and center the window
		inventory_window.show_window()
		
		# Center with safety check
		if inventory_window.get_viewport():
			inventory_window.center_on_screen()
		
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
	else:
		# Save position before closing
		_save_window_position()
		
		inventory_window.hide_window()
		
		# Hide mouse cursor for FPS gameplay (unless pause menu is open)
		if not _is_pause_menu_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	inventory_toggled.emit(is_inventory_open)

func _is_pause_menu_open() -> bool:
	# Check if pause menu exists and is visible
	var pause_menus = get_tree().get_nodes_in_group("pause_menu")
	for menu in pause_menus:
		if menu.visible:
			return true
	
	# Alternative check - look for pause menu by name
	var scene_root = get_tree().current_scene
	var pause_menu = _find_node_by_name_recursive(scene_root, "PauseMenu")
	if pause_menu and pause_menu.visible:
		return true
	
	return false

func _find_node_by_name_recursive(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	
	for child in node.get_children():
		var result = _find_node_by_name_recursive(child, target_name)
		if result:
			return result
	
	return null

func _save_window_position():
	if inventory_window:
		saved_position = inventory_window.position
		var file = FileAccess.open(position_save_file, FileAccess.WRITE)
		if file:
			file.store_var(saved_position)
			file.close()

func _load_window_position() -> Vector2i:
	if FileAccess.file_exists(position_save_file):
		var file = FileAccess.open(position_save_file, FileAccess.READ)
		if file:
			var loaded_pos = file.get_var()
			file.close()
			return loaded_pos
	return Vector2i.ZERO

func _is_position_valid(pos: Vector2i) -> bool:
	var viewport = get_viewport()
	if not viewport:
		return false
	
	var screen_size = viewport.get_visible_rect().size
	return pos.x >= 0 and pos.y >= 0 and pos.x < screen_size.x and pos.y < screen_size.y

# Signal handlers
func _on_item_added(item_id: String, quantity: int):
	pass

func _on_item_removed(item_id: String, quantity: int):
	pass

func _on_container_switched(container: InventoryContainer_Base):
	pass

func _on_window_resized(new_size: Vector2i):
	pass

# Public interface methods
func is_inventory_window_open() -> bool:
	return is_inventory_open and inventory_window != null and inventory_window.visible

func get_inventory_window() -> InventoryWindow:
	return inventory_window

func get_inventory_manager() -> InventoryManager:
	return inventory_manager

func close_inventory():
	if is_inventory_open:
		toggle_inventory()

func open_inventory():
	if not is_inventory_open:
		toggle_inventory()
