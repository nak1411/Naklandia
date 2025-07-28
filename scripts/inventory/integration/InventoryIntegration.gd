# InventoryIntegration.gd - Updated with detailed centering debug
class_name InventoryIntegration
extends Node

# References
var player: Player
var inventory_manager: InventoryManager
var inventory_window: InventoryWindow
var ui_manager: UIManager
var fallback_canvas: CanvasLayer  # For when UIManager isn't found

# UI Management
var is_inventory_open: bool = false
var input_consumed: bool = false

# Setup tracking
var setup_complete: bool = false

# Position saving
var saved_position: Vector2i = Vector2i.ZERO
var position_save_file: String = "user://inventory_window_position.dat"

# Input action names
const TOGGLE_INVENTORY = "toggle_inventory"

# Signals
signal inventory_toggled(is_open: bool)
signal item_used(item: InventoryItem_Base)
signal setup_completed()

func _ready():
	print("Setting up inventory system...")
	
	# Find UI Manager in the scene more thoroughly
	ui_manager = _find_ui_manager()
	
	if not ui_manager:
		print("Warning: UIManager not found! Creating fallback CanvasLayer")
		_create_fallback_ui()
	else:
		print("Found UIManager: ", ui_manager.name)
	
	# Initialize in sequence
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
	
	# Mark setup as complete
	setup_complete = true
	setup_completed.emit()
	print("Inventory system initialized. Press I to open inventory!")

func _find_ui_manager() -> UIManager:
	# Try multiple ways to find UIManager
	print("Looking for UIManager...")
	
	# First, check if it's in a group
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	print("UI managers in group: ", ui_managers.size())
	if ui_managers.size() > 0:
		print("Found UIManager in group: ", ui_managers[0])
		return ui_managers[0] as UIManager
	
	# Then look in the current scene
	var scene_root = get_tree().current_scene
	print("Scene root: ", scene_root.name, " children: ", scene_root.get_children().size())
	
	for child in scene_root.get_children():
		print("Child: ", child.name, " type: ", child.get_class())
		if child.name == "UIManager":
			print("Found node named UIManager: ", child)
			# Check if it has UIManager methods instead of type checking
			if child.has_method("add_window") and child.has_method("get_ui_canvas"):
				print("UIManager has correct methods - returning it")
				return child as UIManager
			else:
				print("UIManager node doesn't have expected methods")
		if child is UIManager:
			print("Found UIManager as child: ", child)
			return child as UIManager
	
	var ui_manager_node = _find_node_by_name_recursive(scene_root, "UIManager")
	if ui_manager_node:
		print("Found UIManager recursively: ", ui_manager_node)
		if ui_manager_node.has_method("add_window") and ui_manager_node.has_method("get_ui_canvas"):
			print("Recursive UIManager has correct methods - returning it")
			return ui_manager_node as UIManager
	
	print("UIManager not found anywhere!")
	return null

func _find_node_by_name_recursive(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	
	for child in node.get_children():
		var result = _find_node_by_name_recursive(child, target_name)
		if result:
			return result
	
	return null

func _create_fallback_ui():
	# Create fallback CanvasLayer if UIManager not found
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "InventoryUI"
	canvas_layer.layer = 15  # Above other UI
	canvas_layer.visible = true  # Make sure it's visible
	get_tree().current_scene.add_child(canvas_layer)
	
	print("Created fallback CanvasLayer with layer: ", canvas_layer.layer)
	
	# Store canvas layer reference separately
	fallback_canvas = canvas_layer

func _add_initial_test_items():
	if inventory_manager:
		# Clear any existing items first
		var player_inv = inventory_manager.get_player_inventory()
		if player_inv:
			player_inv.clear()
		
		# Create sample items
		inventory_manager.create_sample_items()
		
		# Force UI refresh
		#if inventory_window:
			#inventory_window.refresh_display()

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
	# Create inventory window (initially hidden)
	inventory_window = InventoryWindow.new()
	inventory_window.name = "InventoryWindow"
	inventory_window.visible = false
	
	# Override the hardcoded position immediately
	inventory_window.position = Vector2i.ZERO
	
	# Since InventoryWindow extends Window_Base (not Control), add it directly to the scene
	# Windows should be added to the scene root, not CanvasLayers
	get_tree().current_scene.add_child(inventory_window)
	
	# Set up the window to handle its own toggle input
	if inventory_window.has_method("set_inventory_integration"):
		inventory_window.set_inventory_integration(self)
	
	# Load saved position or center the window
	await get_tree().process_frame
	_load_and_apply_position()
	
	# Connect to position change signals to save position when moved
	_connect_position_signals()
	
	# Ensure everything is properly initialized
	await get_tree().process_frame
	
	# Double-check window is hidden and ensure no flicker
	if inventory_window:
		# Make absolutely sure it's hidden
		inventory_window.visible = false
		inventory_window.hide()
		# Force it to stay hidden
		await get_tree().process_frame
		inventory_window.visible = false

func _connect_signals():
	# Player reference
	player = get_parent() as Player
	
	# Inventory window signals
	if inventory_window:
		# Connect your inventory signals here
		pass

func _connect_position_signals():
	if inventory_window:
		# Connect to position change signal
		if inventory_window.has_signal("position_changed"):
			inventory_window.position_changed.connect(_on_window_position_changed)
		
		# Since Window might not have position_changed signal, also check for size_changed
		if inventory_window.has_signal("size_changed"):
			inventory_window.size_changed.connect(_on_window_moved)
		
		# Alternative: use a timer to periodically check for position changes
		var position_timer = Timer.new()
		position_timer.wait_time = 0.5  # Check every half second
		position_timer.timeout.connect(_check_position_change)
		position_timer.autostart = true
		add_child(position_timer)
		
		print("Connected position tracking signals")

func _on_window_position_changed():
	_save_window_position()

func _on_window_moved():
	_save_window_position()

var last_known_position: Vector2i = Vector2i.ZERO

func _check_position_change():
	if inventory_window and inventory_window.position != last_known_position:
		last_known_position = inventory_window.position
		_save_window_position()

func _save_window_position():
	if not inventory_window:
		return
	
	saved_position = inventory_window.position
	
	# Save to file
	var file = FileAccess.open(position_save_file, FileAccess.WRITE)
	if file:
		var save_data = {
			"position": {
				"x": saved_position.x,
				"y": saved_position.y
			},
			"timestamp": Time.get_unix_time_from_system()
		}
		file.store_string(JSON.stringify(save_data))
		file.close()

func _load_and_apply_position():
	# Try to load saved position
	if FileAccess.file_exists(position_save_file):
		var file = FileAccess.open(position_save_file, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			
			var json = JSON.new()
			var parse_result = json.parse(json_string)
			
			if parse_result == OK:
				var save_data = json.data
				if save_data.has("position"):
					var pos_data = save_data.position
					saved_position = Vector2i(pos_data.x, pos_data.y)
					
					# Validate position is still on screen
					if _is_position_valid(saved_position):
						inventory_window.position = saved_position
						last_known_position = saved_position
						print("Loaded and applied saved position: ", saved_position)
						return
					else:
						print("Saved position is off-screen, centering instead")
	
	# If no saved position or invalid position, center the window
	print("No valid saved position found, centering window")
	_center_inventory_window_detailed()
	last_known_position = inventory_window.position

func _is_position_valid(pos: Vector2i) -> bool:
	"""Check if the position is still valid (on screen)"""
	var screen_size = DisplayServer.screen_get_size()
	var window_size = inventory_window.size
	
	# Check if window would be completely off screen
	if pos.x + window_size.x < 0 or pos.y + window_size.y < 0:
		return false
	if pos.x > screen_size.x or pos.y > screen_size.y:
		return false
	
	# Check if at least part of the window is visible
	if pos.x + 100 > screen_size.x or pos.y + 50 > screen_size.y:
		return false
	
	return true

func _input(event):
	if not setup_complete:
		return
		
	if event.is_action_pressed(TOGGLE_INVENTORY):
		toggle_inventory_detailed()
		get_viewport().set_input_as_handled()  # Consume the input
		input_consumed = true

# Also keep the unhandled input as fallback
func _unhandled_input(event):
	if not setup_complete:
		return
		
	if event.is_action_pressed(TOGGLE_INVENTORY) and not input_consumed:
		toggle_inventory_detailed()
		get_viewport().set_input_as_handled()
		input_consumed = true

func toggle_inventory_detailed():
	if not inventory_window:
		return
	
	is_inventory_open = !is_inventory_open
	
	if is_inventory_open:
		# Don't re-center if we have a saved position
		if saved_position == Vector2i.ZERO:
			_center_inventory_window_detailed()
		else:
			# Use saved position but validate it's still on screen
			if _is_position_valid(saved_position):
				inventory_window.position = saved_position
				print("Using saved position: ", saved_position)
			else:
				print("Saved position invalid, centering")
				_center_inventory_window_detailed()
		
		# Show the window
		inventory_window.visible = true
		inventory_window.show()
		
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		# Save position before hiding
		_save_window_position()
		
		inventory_window.visible = false
		inventory_window.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	inventory_toggled.emit(is_inventory_open)

func _center_inventory_window():
	# Redirect to detailed version
	_center_inventory_window_detailed()

func _center_inventory_window_detailed():
	if not inventory_window:
		print("Cannot center - no inventory window")
		return
	
	# Don't use popup_centered during initialization - it makes the window visible
	var during_setup = not setup_complete
	
	if during_setup:
		print("During setup - using manual centering only")
	elif inventory_window.has_method("popup_centered"):
		print("Using popup_centered() method")
		inventory_window.popup_centered()
		print("Position after popup_centered: ", inventory_window.position)
		return
	
	# Manual centering fallback
	var screen_size = DisplayServer.screen_get_size()
	var window_size = inventory_window.size
	var viewport = get_viewport()
	var viewport_size = viewport.get_visible_rect().size if viewport else Vector2.ZERO
	
	print("Screen size: ", screen_size)
	print("Window size: ", window_size)
	print("Viewport size: ", viewport_size)
	
	# Check if we're in fullscreen mode
	var main_window = get_window()
	var is_fullscreen = main_window.mode == Window.MODE_FULLSCREEN if main_window else false
	print("Fullscreen mode: ", is_fullscreen)
	
	if is_fullscreen:
		# In fullscreen, center relative to screen
		var center_pos = Vector2i(
			(screen_size.x - window_size.x) / 2,
			(screen_size.y - window_size.y) / 2
		)
		print("Fullscreen center calculation: ", center_pos)
		inventory_window.position = center_pos
	else:
		# In windowed mode, center relative to the main game window
		if main_window:
			var main_window_pos = main_window.position
			var main_window_size = main_window.size
			
			print("Main window position: ", main_window_pos)
			print("Main window size: ", main_window_size)
			
			# Don't use popup_centered_clamped during setup
			if not during_setup and inventory_window.has_method("popup_centered_clamped"):
				print("Using popup_centered_clamped()")
				inventory_window.popup_centered_clamped(main_window_size)
				print("Position after popup_centered_clamped: ", inventory_window.position)
				return
			
			# Center the inventory window relative to the main game window
			var center_pos = Vector2i(
				main_window_pos.x + (main_window_size.x - window_size.x) / 2,
				main_window_pos.y + (main_window_size.y - window_size.y) / 2
			)
			print("Windowed center calculation: ", center_pos)
			inventory_window.position = center_pos
			
			# Also try setting current_screen to ensure it's on the right display
			if inventory_window.has_method("set_current_screen"):
				var current_screen = DisplayServer.window_get_current_screen()
				print("Current screen: ", current_screen)
				inventory_window.set_current_screen(current_screen)
		else:
			print("No main window found, using screen center")
			var center_pos = Vector2i(
				(screen_size.x - window_size.x) / 2,
				(screen_size.y - window_size.y) / 2
			)
			inventory_window.position = center_pos
	
	print("Final inventory window position: ", inventory_window.position)

# Public interface for InventoryWindow to call
func toggle_from_window():
	"""Called by InventoryWindow when it handles the 'I' key press"""
	toggle_inventory_detailed()

func close_from_window():
	"""Called by InventoryWindow when it handles the ESC key press"""
	if is_inventory_open:
		is_inventory_open = false
		inventory_window.visible = false
		inventory_window.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		inventory_toggled.emit(is_inventory_open)
		print("Inventory closed from window")

# Public interface
func get_inventory_manager() -> InventoryManager:
	return inventory_manager

func get_inventory_window() -> InventoryWindow:
	return inventory_window

func is_inventory_window_open() -> bool:
	return is_inventory_open

func is_setup_complete() -> bool:
	return setup_complete
