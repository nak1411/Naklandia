# PauseMenu.gd
# Attach this script to a CanvasLayer node for proper layering

extends CanvasLayer

var is_paused = false
var inventory_integration: InventoryIntegration
var inventory_unfocused_once = false

var pause_menu_control: Control
var background_panel: Panel
var menu_panel: Panel
var resume_button: Button
var settings_button: Button
var exit_button: Button

var settings_menu: SettingsMenu

func _ready():
	# Set up the canvas layer to render above everything
	layer = 100  # Very high layer to ensure it's above inventory
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
		
	# Find and setup inventory integration
	_find_and_setup_inventory_integration()
	
	# Create the UI hierarchy programmatically
	_setup_menu_ui()
	_setup_settings_menu()
	
	# Connect button signals
	resume_button.pressed.connect(_on_resume_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	
func _find_and_setup_inventory_integration():
	# Look for InventoryIntegration in the scene
	var scene_root = get_tree().current_scene
	
	for child in scene_root.get_children():
		if child is InventoryIntegration:
			inventory_integration = child
			break
	
	if not inventory_integration:
		# Try to find it by name
		var found_node = _find_node_by_name_recursive(scene_root, "InventoryIntegration")
		if found_node and found_node is InventoryIntegration:
			inventory_integration = found_node
	
	# Add a reference to the pause menu in the inventory integration
	if inventory_integration:
		inventory_integration.set("pause_menu", self)

func _find_node_by_name_recursive(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	
	for child in node.get_children():
		var result = _find_node_by_name_recursive(child, target_name)
		if result:
			return result
	
	return null

# Public method that inventory integration can call
func handle_inventory_escape() -> bool:
	"""Called by inventory integration when escape is pressed. Returns true if handled by pause menu."""
	if not inventory_integration or not inventory_integration.is_inventory_window_open():
		return false
	
	var inventory_window = inventory_integration.get_inventory_window()
	
	# Check if inventory has focus
	if inventory_window and inventory_window.has_focus():
		# First press: unfocus but keep open
		inventory_window.release_focus()
		inventory_unfocused_once = true
		return true  # We handled it
	
	# Second press or inventory not focused: open pause menu
	if inventory_unfocused_once:
		inventory_unfocused_once = false
		toggle_pause()
		return true  # We handled it
	
	return false  # Let inventory handle it normally

func _setup_menu_ui():
	# Create main control container
	pause_menu_control = Control.new()
	pause_menu_control.name = "PauseMenuControl"
	pause_menu_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu_control.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(pause_menu_control)
	
	# Create semi-transparent background
	background_panel = Panel.new()
	background_panel.name = "BackgroundPanel"
	background_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_menu_control.add_child(background_panel)
	
	# Style the background
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0.7)
	background_panel.add_theme_stylebox_override("panel", bg_style)
	
	# Create menu panel
	menu_panel = Panel.new()
	menu_panel.name = "MenuPanel"
	menu_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu_panel.custom_minimum_size = Vector2(400, 300)
	menu_panel.size = Vector2(400, 300)
	# Center the panel by offsetting by half its size
	menu_panel.position = Vector2(-200, -150)  # -width/2, -height/2
	background_panel.add_child(menu_panel)
	
	# Style the menu panel
	var menu_style = StyleBoxFlat.new()
	menu_style.bg_color = Color(0.2, 0.2, 0.2, 0.9)
	menu_style.border_width_left = 2
	menu_style.border_width_right = 2
	menu_style.border_width_top = 2
	menu_style.border_width_bottom = 2
	menu_style.border_color = Color.WHITE
	menu_style.corner_radius_top_left = 10
	menu_style.corner_radius_top_right = 10
	menu_style.corner_radius_bottom_left = 10
	menu_style.corner_radius_bottom_right = 10
	menu_panel.add_theme_stylebox_override("panel", menu_style)
	
	# Create button container
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 20)
	menu_panel.add_child(vbox)
	
	# Add margin container for padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	vbox.add_child(margin)
	
	var button_container = VBoxContainer.new()
	button_container.add_theme_constant_override("separation", 20)
	margin.add_child(button_container)
	
	# Create buttons
	resume_button = Button.new()
	resume_button.name = "ResumeButton"
	resume_button.text = "Resume Game"
	resume_button.custom_minimum_size.y = 50
	button_container.add_child(resume_button)
	
	settings_button = Button.new()
	settings_button.name = "SettingsButton"
	settings_button.text = "Settings"
	settings_button.custom_minimum_size.y = 50
	button_container.add_child(settings_button)
	
	exit_button = Button.new()
	exit_button.name = "ExitButton"
	exit_button.text = "Exit Game"
	exit_button.custom_minimum_size.y = 50
	button_container.add_child(exit_button)

func _setup_settings_menu():
	settings_menu = SettingsMenu.new()
	settings_menu.name = "SettingsMenu"
	settings_menu.visible = false
	settings_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Connect settings signals
	settings_menu.settings_closed.connect(_on_settings_closed)
	
	# Add to the pause canvas
	add_child(settings_menu)

func _input(event):
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		
		# Check inventory status first
		if inventory_integration:
			var inv_open = inventory_integration.is_inventory_window_open()
			var inv_window = inventory_integration.get_inventory_window()
			
			# NEW: Check if search field is focused and clear it first, then open pause menu
			if inv_open and inv_window and inv_window.header and inv_window.header.is_search_focused:
				# Clear search focus and open pause menu immediately
				inv_window.header.clear_search_focus()
				toggle_pause()
				get_viewport().set_input_as_handled()
				return
			
			var inv_has_focus = inv_window.has_focus() if inv_window else false
			
			# If inventory is open and has focus, open pause menu
			if inv_open and inv_has_focus:
				toggle_pause()
				get_viewport().set_input_as_handled()
				return
			
			# If inventory is open but unfocused, open pause menu
			if inv_open and not inv_has_focus:
				toggle_pause()
				get_viewport().set_input_as_handled()
				return
		
		# If no inventory or inventory is closed, toggle pause menu
		toggle_pause()
		get_viewport().set_input_as_handled()

func toggle_pause():
	is_paused = !is_paused
	
	if is_paused:
		# Pause the game
		get_tree().paused = true
		visible = true
		# Show mouse cursor for menu navigation
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# Focus the resume button for gamepad navigation
		resume_button.grab_focus()
	else:
		# Resume the game
		get_tree().paused = false
		visible = false
		
		# Check if inventory is still open before setting mouse mode
		if inventory_integration and inventory_integration.is_inventory_window_open():
			# Keep mouse visible for inventory interaction
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			# Don't re-focus inventory - let it stay unfocused so "I" key works
		else:
			# Hide mouse cursor and capture it for FPS gameplay
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
		# Reset inventory unfocus state when closing pause menu
		inventory_unfocused_once = false

func _on_resume_pressed():
	toggle_pause()

func _on_settings_pressed():
	pause_menu_control.visible = false
	settings_menu.show_settings()

func _on_settings_closed():
	settings_menu.hide_settings()
	pause_menu_control.visible = true

func _on_exit_pressed():
	# Exit the game
	get_tree().quit()
