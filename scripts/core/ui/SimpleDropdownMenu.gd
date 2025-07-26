# SimpleDropdownMenu.gd - Clean dropdown menu with submenu support and proper right-click handling
class_name SimpleDropdownMenu
extends Control

# Menu structure
var menu_items: Array[Dictionary] = []
var main_popup: PopupPanel
var submenu_popup: PopupPanel

# Visual properties
var item_height: int = 33
var menu_width: int = 150
var submenu_width: int = 100

# State
var hovered_item_index: int = -1
var submenu_visible: bool = false
var current_submenu_index: int = -1
var manually_hiding_submenu: bool = false

# Input polling for right-click detection
var _previous_right_click_state: bool = false

# Signals
signal item_selected(item_id: String, item_data: Dictionary)

func _init():
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(menu_width, item_height)

func add_menu_item(id: String, text: String, has_submenu: bool = false, submenu_items: Array = []):
	var item = {
		"id": id,
		"text": text,
		"has_submenu": has_submenu,
		"submenu_items": submenu_items,
		"enabled": true
	}
	menu_items.append(item)

func show_menu(show_position: Vector2 = Vector2.ZERO):
	_create_main_popup()
	
	if show_position != Vector2.ZERO:
		main_popup.position = Vector2i(show_position)
	else:
		main_popup.position = Vector2i(global_position)
	
	main_popup.popup()
	
	# Enable input processing
	set_process_unhandled_input(true)
	set_process_input(true)
	
	# Start input polling for reliable click detection
	_start_input_polling()

func _create_main_popup():
	# Clean up existing popup
	if main_popup and is_instance_valid(main_popup):
		main_popup.queue_free()
		main_popup = null
	
	main_popup = PopupPanel.new()
	main_popup.name = "MainMenuPopup"
	
	# Create container for menu items
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	main_popup.add_child(vbox)
	
	# Create menu items
	for i in range(menu_items.size()):
		var item_data = menu_items[i]
		var item_button = _create_menu_item_button(item_data, i)
		vbox.add_child(item_button)
	
	# Set popup size through content
	var popup_height = menu_items.size() * item_height
	vbox.custom_minimum_size = Vector2(menu_width, popup_height)
	
	# Style the popup
	_style_popup(main_popup)
	
	# Add to scene
	get_viewport().add_child(main_popup)
	
	# Connect popup hide signal to prevent unwanted closure during submenu operations
	main_popup.popup_hide.connect(_on_main_popup_hide)
	main_popup.visibility_changed.connect(_on_main_popup_visibility_changed)

func _create_menu_item_button(item_data: Dictionary, index: int) -> Button:
	var button = Button.new()
	button.text = item_data.text
	button.custom_minimum_size = Vector2(menu_width, item_height)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.flat = false  # Enable default button styling including hover
	
	# Add submenu indicator
	if item_data.has_submenu:
		button.text += " ▶"
	
	# Style the button
	_style_menu_button(button)
	
	# Connect signals
	button.pressed.connect(_on_menu_item_pressed.bind(index))
	button.mouse_entered.connect(_on_menu_item_hovered.bind(index))
	button.gui_input.connect(_on_menu_item_input.bind(index))
	
	return button

func _style_popup(popup: PopupPanel):
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.2, 0.2, 0.2, 0.95)
	style_box.border_width_left = 1
	style_box.border_width_right = 1
	style_box.border_width_top = 1
	style_box.border_width_bottom = 1
	style_box.border_color = Color(0.4, 0.4, 0.4, 1.0)
	style_box.corner_radius_top_left = 2
	style_box.corner_radius_top_right = 2
	style_box.corner_radius_bottom_left = 2
	style_box.corner_radius_bottom_right = 2
	popup.add_theme_stylebox_override("panel", style_box)

func _style_menu_button(button: Button):
	# Only override what we need, let Godot handle hover automatically
	button.add_theme_color_override("font_color", Color.WHITE)
	button.focus_mode = Control.FOCUS_NONE
	
	# Set a subtle normal background so hover shows contrast
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.15, 0.15, 0.15, 1.0)  # Dark background
	normal_style.expand_margin_left = 5
	button.add_theme_stylebox_override("normal", normal_style)
	
	# Let Godot's default hover styling work - don't override it!

func _start_input_polling():
	# Use a timer to poll for input - this bypasses event routing issues
	var input_timer = Timer.new()
	input_timer.name = "InputPollingTimer"
	input_timer.wait_time = 0.05  # Poll at 20fps for responsiveness
	input_timer.timeout.connect(_poll_for_input)
	add_child(input_timer)
	input_timer.start()

func _poll_for_input():
	if not is_menu_visible():
		return
	
	# Check if right mouse button was just pressed
	if Input.is_action_just_pressed("ui_cancel") or _is_right_click_just_pressed():
		var mouse_pos = get_global_mouse_position()
		
		# Check if we should close menu
		if _should_close_menu_at_position(mouse_pos):
			hide_menu()

func _is_right_click_just_pressed() -> bool:
	var current_state = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var just_pressed = current_state and not _previous_right_click_state
	_previous_right_click_state = current_state
	return just_pressed

func _should_close_menu_at_position(mouse_pos: Vector2) -> bool:
	# Check if click is inside main popup
	if main_popup and is_instance_valid(main_popup):
		var main_rect = Rect2(main_popup.position, main_popup.size)
		if main_rect.has_point(mouse_pos):
			return false  # Don't close if inside main menu
	
	# Check if click is inside submenu popup
	if submenu_popup and is_instance_valid(submenu_popup) and submenu_visible:
		var submenu_rect = Rect2(submenu_popup.position, submenu_popup.size)
		if submenu_rect.has_point(mouse_pos):
			return false  # Don't close if inside submenu
	
	return true  # Close menu

func _on_menu_item_pressed(index: int):
	var item = menu_items[index]
	
	if not item.has_submenu:
		# Regular item selected
		item_selected.emit(item.id, item)
		hide_menu()

func _on_menu_item_input(event: InputEvent, index: int):
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			# Right-click anywhere in menu should close it
			hide_menu()
			get_viewport().set_input_as_handled()

func _on_menu_item_hovered(index: int):
	hovered_item_index = index
	var item = menu_items[index]
	
	if item.has_submenu:
		_show_submenu(index)
	else:
		_hide_submenu()

func _show_submenu(item_index: int):
	var item = menu_items[item_index]
	
	if not item.has_submenu or item.submenu_items.is_empty():
		_hide_submenu()
		return
	
	# If showing the same submenu, don't recreate it
	if current_submenu_index == item_index and submenu_visible:
		return
	
	current_submenu_index = item_index
	_hide_submenu()  # Hide any existing submenu first
	
	# Create new submenu popup
	submenu_popup = PopupPanel.new()
	submenu_popup.name = "SubmenuPopup"
	
	# Create submenu container
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	submenu_popup.add_child(vbox)
	
	# Create submenu items
	for submenu_item in item.submenu_items:
		var submenu_button = Button.new()
		submenu_button.text = submenu_item.text
		submenu_button.custom_minimum_size = Vector2(submenu_width, item_height)
		submenu_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		submenu_button.flat = false  # Enable default hover styling
		
		# Style submenu button
		_style_menu_button(submenu_button)
		
		# Connect submenu button signals
		submenu_button.pressed.connect(_on_submenu_item_pressed.bind(submenu_item))
		submenu_button.gui_input.connect(_on_submenu_item_input.bind(submenu_item))
		
		vbox.add_child(submenu_button)
	
	# Set submenu size through content
	var submenu_height = item.submenu_items.size() * item_height
	vbox.custom_minimum_size = Vector2(submenu_width, submenu_height)
	
	# Style submenu
	_style_popup(submenu_popup)
	
	# Position submenu to the right of main menu
	var submenu_pos = Vector2i(
		main_popup.position.x + menu_width,
		main_popup.position.y + (item_index * item_height)
	)
	submenu_popup.position = submenu_pos
	
	# Add to scene and show
	get_viewport().add_child(submenu_popup)
	submenu_popup.show()
	submenu_visible = true

func _hide_submenu():
	manually_hiding_submenu = true
	
	if submenu_popup and is_instance_valid(submenu_popup):
		submenu_popup.visible = false
		if submenu_popup.get_parent():
			submenu_popup.get_parent().remove_child(submenu_popup)
		submenu_popup.queue_free()
		submenu_popup = null
	
	submenu_visible = false
	current_submenu_index = -1
	
	# Use a timer to reset the flag after a short delay to catch delayed signals
	get_tree().create_timer(0.1).timeout.connect(func(): manually_hiding_submenu = false)

func _on_submenu_item_pressed(submenu_item: Dictionary):
	item_selected.emit(submenu_item.id, submenu_item)
	hide_menu()

func _on_submenu_item_input(event: InputEvent, submenu_item: Dictionary):
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			# Right-click anywhere in submenu should close entire menu
			hide_menu()
			get_viewport().set_input_as_handled()

func _on_main_popup_hide():
	if manually_hiding_submenu:
		# Prevent main popup from closing during submenu operations
		if main_popup and is_instance_valid(main_popup):
			main_popup.visible = true
		return

func _on_main_popup_visibility_changed():
	if manually_hiding_submenu:
		# Force the main popup to stay visible during submenu operations
		if main_popup and is_instance_valid(main_popup) and not main_popup.visible:
			main_popup.visible = true
		return

func hide_menu():
	# Disable input processing methods
	set_process_unhandled_input(false)
	set_process_input(false)
	
	# Clean up polling timer
	var timer = get_node_or_null("InputPollingTimer")
	if timer:
		timer.queue_free()
	
	# Reset right-click state
	_previous_right_click_state = false
	
	if main_popup and is_instance_valid(main_popup):
		main_popup.hide()
		main_popup.queue_free()
	main_popup = null
	
	_hide_submenu()

func _unhandled_input(event: InputEvent):
	if not is_menu_visible():
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed:
			var click_pos = mouse_event.global_position
			
			# Check if click is inside main popup
			if main_popup and is_instance_valid(main_popup):
				var main_rect = Rect2(main_popup.position, main_popup.size)
				if main_rect.has_point(click_pos):
					return  # Click inside main menu, let menu handle it
			
			# Check if click is inside submenu popup
			if submenu_popup and is_instance_valid(submenu_popup) and submenu_visible:
				var submenu_rect = Rect2(submenu_popup.position, submenu_popup.size)
				if submenu_rect.has_point(click_pos):
					return  # Click inside submenu, let submenu handle it
			
			# Click outside menu system - close everything (both left and right clicks)
			hide_menu()
			get_viewport().set_input_as_handled()

func _input(event: InputEvent):
	if not is_menu_visible():
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed:
			var click_pos = mouse_event.global_position
			
			# Check if click is inside main popup
			if main_popup and is_instance_valid(main_popup):
				var main_rect = Rect2(main_popup.position, main_popup.size)
				if main_rect.has_point(click_pos):
					return  # Click inside main menu, let menu handle it
			
			# Check if click is inside submenu popup
			if submenu_popup and is_instance_valid(submenu_popup) and submenu_visible:
				var submenu_rect = Rect2(submenu_popup.position, submenu_popup.size)
				if submenu_rect.has_point(click_pos):
					return  # Click inside submenu, let submenu handle it
			
			# Click outside menu system - close everything (both left and right clicks)
			hide_menu()
			get_viewport().set_input_as_handled()

# Public interface
func is_menu_visible() -> bool:
	return main_popup != null and is_instance_valid(main_popup) and main_popup.visible

func clear_items():
	menu_items.clear()

func setup_window_options_menu():
	"""Setup typical window options menu with transparency submenu"""
	clear_items()
	
	# Lock Window
	add_menu_item("lock_window", "Lock Window")
	
	# Transparency with submenu
	var transparency_items = []
	for i in range(10, 101, 10):
		transparency_items.append({
			"id": "transparency_" + str(i),
			"text": str(i) + "%"
		})
	
	add_menu_item("transparency", "Transparency", true, transparency_items)
	
	# Reset Transparency
	add_menu_item("reset_transparency", "Reset Transparency")
