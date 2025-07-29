# CustomContextMenu.gd - Context menu with CanvasLayer to appear on top
class_name ContextMenu_Base
extends Control

# Menu structure
var menu_items: Array[Dictionary] = []
var main_popup: PopupPanel
var submenu_popup: PopupPanel
var context_canvas: CanvasLayer  # New: Canvas layer for proper z-ordering

# Visual properties
var item_height: int = 33
var menu_width: int = 180
var submenu_width: int = 120
var item_padding_horizontal: int = 12
var item_padding_vertical: int = 6

# Context menu specific properties
var auto_size: bool = true
var min_width: int = 120
var max_width: int = 250

# State
var hovered_item_index: int = -1
var submenu_visible: bool = false
var current_submenu_index: int = -1
var manually_hiding_submenu: bool = false
var context_data: Dictionary = {}

# Input polling for right-click detection
var _previous_right_click_state: bool = false

# Signals
signal item_selected(item_id: String, item_data: Dictionary, context_data: Dictionary)
signal menu_closed()

func _init():
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(min_width, item_height)

func add_menu_item(id: String, text: String, icon: Texture2D = null, enabled: bool = true, has_submenu: bool = false, submenu_items: Array = []):
	var item = {
		"id": id,
		"text": text,
		"icon": icon,
		"enabled": enabled,
		"has_submenu": has_submenu,
		"submenu_items": submenu_items
	}
	menu_items.append(item)

func add_separator():
	"""Add a visual separator line between menu items"""
	var separator = {
		"id": "_separator_" + str(menu_items.size()),
		"text": "",
		"is_separator": true,
		"enabled": false,
		"has_submenu": false,
		"submenu_items": []
	}
	menu_items.append(separator)

func show_context_menu(show_position: Vector2, data: Dictionary = {}, parent_window: Window = null):
	print("ContextMenu_Base: show_context_menu called at position: ", show_position)
	context_data = data
	_create_main_popup()
	
	# Get viewport and calculate proper position
	var viewport = get_viewport()
	if not viewport:
		print("ContextMenu_Base: ERROR - No viewport found!")
		return
	
	print("ContextMenu_Base: Viewport found, creating canvas layer")
	
	var final_position: Vector2
	
	# If we have a parent window (like inventory window), use its positioning
	if parent_window:
		final_position = show_position + Vector2(parent_window.position)
		print("ContextMenu_Base: Using parent window position: ", parent_window.position)
	else:
		# Fallback to viewport positioning
		final_position = show_position
		print("ContextMenu_Base: Using viewport positioning")
	
	# Add small offset to avoid cursor overlap
	var popup_offset = Vector2i(15, 15)
	final_position += Vector2(popup_offset)
	
	# Create CanvasLayer for proper z-ordering (same approach as drag preview)
	context_canvas = CanvasLayer.new()
	context_canvas.name = "ContextMenuLayer"
	context_canvas.layer = 101  # Higher than drag layer (100) to appear on top
	viewport.add_child(context_canvas)
	print("ContextMenu_Base: Canvas layer created and added to viewport")
	
	# Add the popup to the canvas layer instead of viewport
	context_canvas.add_child(main_popup)
	print("ContextMenu_Base: Popup added to canvas layer")
	
	# Set position and show
	main_popup.position = Vector2i(final_position)
	main_popup.popup()
	print("ContextMenu_Base: Popup shown at position: ", final_position)
	
	# Enable input processing
	set_process_unhandled_input(true)
	set_process_input(true)
	
	# Start input polling for reliable click detection with delay
	_start_input_polling_delayed()
	
	# Delay input processing to avoid immediate closure
	await get_tree().process_frame
	print("ContextMenu_Base: Context menu setup complete")

func _calculate_screen_position(desired_position: Vector2) -> Vector2:
	"""Calculate menu position ensuring it stays within screen bounds"""
	var viewport = get_viewport()
	if not viewport:
		return desired_position
	
	var viewport_size = viewport.get_visible_rect().size
	var estimated_menu_size = Vector2(menu_width, _calculate_total_height())
	var final_pos = desired_position
	
	# Ensure menu doesn't go off right edge of viewport
	if final_pos.x + estimated_menu_size.x > viewport_size.x:
		final_pos.x = viewport_size.x - estimated_menu_size.x - 10
	
	# Ensure menu doesn't go off bottom edge of viewport
	if final_pos.y + estimated_menu_size.y > viewport_size.y:
		final_pos.y = viewport_size.y - estimated_menu_size.y - 10
	
	# Ensure menu doesn't go off left or top edges
	if final_pos.x < 10:
		final_pos.x = 10
	
	if final_pos.y < 10:
		final_pos.y = 10
	
	return final_pos

func _create_main_popup():
	print("ContextMenu_Base: _create_main_popup called")
	# Clean up existing popup
	if main_popup and is_instance_valid(main_popup):
		if main_popup.get_parent():
			main_popup.get_parent().remove_child(main_popup)
		main_popup.queue_free()
		main_popup = null
	
	main_popup = PopupPanel.new()
	main_popup.name = "ContextMenuPopup"
	print("ContextMenu_Base: PopupPanel created")
	
	# Create container for menu items
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	main_popup.add_child(vbox)
	
	# Calculate menu width if auto-sizing
	if auto_size:
		_calculate_optimal_width()
	
	print("ContextMenu_Base: Creating ", menu_items.size(), " menu items")
	# Create menu items
	for i in range(menu_items.size()):
		var item_data = menu_items[i]
		
		if item_data.get("is_separator", false):
			var separator = _create_separator()
			vbox.add_child(separator)
		else:
			var item_button = _create_menu_item_button(item_data, i)
			vbox.add_child(item_button)
	
	# Set popup size through content
	var popup_height = _calculate_total_height()
	vbox.custom_minimum_size = Vector2(menu_width, popup_height)
	print("ContextMenu_Base: Popup size set to: ", Vector2(menu_width, popup_height))
	
	# Style the popup
	_style_popup(main_popup)
	
	# Connect popup signals
	main_popup.popup_hide.connect(_on_main_popup_hide)
	main_popup.visibility_changed.connect(_on_main_popup_visibility_changed)

func _calculate_optimal_width():
	"""Calculate optimal width based on menu item text lengths"""
	if menu_items.is_empty():
		return
	
	var max_text_width = min_width
	var font = ThemeDB.fallback_font
	var font_size = 12
	
	for item in menu_items:
		if item.get("is_separator", false):
			continue
		
		var text = item.text
		if item.has_submenu:
			text += " ▶"
		
		var text_width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var item_width = text_width + (item_padding_horizontal * 2) + 20  # Extra space for icon/margins
		
		max_text_width = max(max_text_width, item_width)
	
	menu_width = min(max_text_width, max_width)

func _calculate_total_height() -> int:
	"""Calculate total height including separators"""
	var total_height = 0
	var separator_height = 1
	
	for item in menu_items:
		if item.get("is_separator", false):
			total_height += separator_height
		else:
			total_height += item_height
	
	return total_height

func _create_separator() -> Control:
	"""Create a visual separator line"""
	var separator_container = Control.new()
	separator_container.custom_minimum_size = Vector2(0, 1)
	separator_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	separator_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var line = Panel.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.add_theme_constant_override("margin_left", 4)
	line.add_theme_constant_override("margin_right", 4)
	line.custom_minimum_size = Vector2(0, 1)
	
	var line_style = StyleBoxFlat.new()
	line_style.bg_color = Color.DIM_GRAY
	line_style.border_width_left = 0
	line_style.border_width_right = 0
	line_style.border_width_top = 0
	line_style.border_width_bottom = 0
	line.add_theme_stylebox_override("panel", line_style)
	
	separator_container.add_child(line)
	return separator_container

func _create_menu_item_button(item_data: Dictionary, index: int) -> Button:
	var button = Button.new()
	button.text = item_data.text
	button.custom_minimum_size = Vector2(menu_width, item_height)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.flat = false
	button.disabled = not item_data.get("enabled", true)
	
	# Add icon if provided
	if item_data.get("icon"):
		button.icon = item_data.icon
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	# Add submenu indicator
	if item_data.has_submenu:
		button.text += " ▶"
	
	# Style the button with padding
	_style_menu_button(button, item_data.get("enabled", true))
	
	# Connect signals only if enabled
	if item_data.get("enabled", true):
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
	popup.add_theme_stylebox_override("panel", style_box)

func _style_menu_button(button: Button, enabled: bool = true):
	# Set font properties
	button.add_theme_color_override("font_color", Color.WHITE if enabled else Color.GRAY)
	button.focus_mode = Control.FOCUS_NONE
	
	if enabled:
		# Create normal style with padding
		var normal_style = StyleBoxFlat.new()
		normal_style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
		normal_style.content_margin_left = item_padding_horizontal
		normal_style.content_margin_right = item_padding_horizontal
		normal_style.content_margin_top = item_padding_vertical
		normal_style.content_margin_bottom = item_padding_vertical
		button.add_theme_stylebox_override("normal", normal_style)
		
		# Create hover style with padding
		var hover_style = StyleBoxFlat.new()
		hover_style.bg_color = Color(0.3, 0.3, 0.3, 1.0)
		hover_style.content_margin_left = item_padding_horizontal
		hover_style.content_margin_right = item_padding_horizontal
		hover_style.content_margin_top = item_padding_vertical
		hover_style.content_margin_bottom = item_padding_vertical
		button.add_theme_stylebox_override("hover", hover_style)
		
		# Create pressed style with padding
		var pressed_style = StyleBoxFlat.new()
		pressed_style.bg_color = Color(0.25, 0.25, 0.25, 1.0)
		pressed_style.content_margin_left = item_padding_horizontal
		pressed_style.content_margin_right = item_padding_horizontal
		pressed_style.content_margin_top = item_padding_vertical
		pressed_style.content_margin_bottom = item_padding_vertical
		button.add_theme_stylebox_override("pressed", pressed_style)
	else:
		# Disabled style
		var disabled_style = StyleBoxFlat.new()
		disabled_style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
		disabled_style.content_margin_left = item_padding_horizontal
		disabled_style.content_margin_right = item_padding_horizontal
		disabled_style.content_margin_top = item_padding_vertical
		disabled_style.content_margin_bottom = item_padding_vertical
		button.add_theme_stylebox_override("disabled", disabled_style)

func _start_input_polling():
	# Use a timer to poll for input - this bypasses event routing issues
	var input_timer = Timer.new()
	input_timer.name = "InputPollingTimer"
	input_timer.wait_time = 0.05  # Poll at 20fps for responsiveness
	input_timer.timeout.connect(_poll_for_input)
	add_child(input_timer)
	input_timer.start()

func _start_input_polling_delayed():
	# Start input polling with a slight delay to avoid immediate closure
	var delay_timer = Timer.new()
	delay_timer.name = "DelayTimer"
	delay_timer.wait_time = 0.1  # 100ms delay
	delay_timer.one_shot = true
	delay_timer.timeout.connect(_start_input_polling)
	add_child(delay_timer)
	delay_timer.start()

func _poll_for_input():
	if not is_menu_visible():
		return
	
	# Check if right mouse button was just pressed or escape
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
	
	if not item.get("enabled", true):
		return
	
	if not item.has_submenu:
		# Regular item selected
		item_selected.emit(item.id, item, context_data)
		hide_menu()

func _on_menu_item_input(event: InputEvent, _index: int):
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			# Right-click anywhere in menu should close it
			hide_menu()
			get_viewport().set_input_as_handled()

func _on_menu_item_hovered(index: int):
	# Skip separators
	var item = menu_items[index]
	if item.get("is_separator", false) or not item.get("enabled", true):
		return
	
	hovered_item_index = index
	
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
		if submenu_item.get("is_separator", false):
			var separator = _create_separator()
			vbox.add_child(separator)
		else:
			var submenu_button = Button.new()
			submenu_button.text = submenu_item.text
			submenu_button.custom_minimum_size = Vector2(submenu_width, item_height)
			submenu_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			submenu_button.flat = false
			submenu_button.disabled = not submenu_item.get("enabled", true)
			
			# Add icon if provided
			if submenu_item.get("icon"):
				submenu_button.icon = submenu_item.icon
				submenu_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			
			# Style submenu button with padding
			_style_submenu_button(submenu_button, submenu_item.get("enabled", true))
			
			# Connect submenu button signals
			if submenu_item.get("enabled", true):
				submenu_button.pressed.connect(_on_submenu_item_pressed.bind(submenu_item))
				submenu_button.gui_input.connect(_on_submenu_item_input.bind(submenu_item))
			
			vbox.add_child(submenu_button)
	
	# Set submenu size through content
	var submenu_height = _calculate_submenu_height(item.submenu_items)
	vbox.custom_minimum_size = Vector2(submenu_width, submenu_height)
	
	# Style submenu
	_style_popup(submenu_popup)
	
	# Position submenu to the right of main menu
	var submenu_pos = Vector2i(
		main_popup.position.x + menu_width,
		main_popup.position.y + (_calculate_item_y_position(item_index))
	)
	submenu_popup.position = submenu_pos
	
	# Add to same canvas layer if it exists, otherwise to viewport
	if context_canvas:
		context_canvas.add_child(submenu_popup)
	else:
		get_viewport().add_child(submenu_popup)
	
	submenu_popup.show()
	submenu_visible = true

func _calculate_submenu_height(submenu_items: Array) -> int:
	var height = 0
	var separator_height = 1
	
	for item in submenu_items:
		if item.get("is_separator", false):
			height += separator_height
		else:
			height += item_height
	
	return height

func _calculate_item_y_position(item_index: int) -> int:
	"""Calculate Y position of item considering separators"""
	var y_pos = 0
	var separator_height = 1
	
	for i in range(item_index):
		var item = menu_items[i]
		if item.get("is_separator", false):
			y_pos += separator_height
		else:
			y_pos += item_height
	
	return y_pos

func _style_submenu_button(button: Button, enabled: bool = true):
	# Set font properties - match SimpleDropdownMenu exactly
	button.add_theme_color_override("font_color", Color.LIGHT_GRAY if enabled else Color.GRAY)
	button.focus_mode = Control.FOCUS_NONE
	button.flat = false  # Enable default hover styling
	
	if enabled:
		# Create normal style with padding - exact same padding reduction as SimpleDropdownMenu
		var submenu_padding_h = item_padding_horizontal - 2
		var submenu_padding_v = item_padding_vertical - 1
		
		var normal_style = StyleBoxFlat.new()
		normal_style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
		normal_style.content_margin_left = submenu_padding_h
		normal_style.content_margin_right = submenu_padding_h
		normal_style.content_margin_top = submenu_padding_v
		normal_style.content_margin_bottom = submenu_padding_v
		button.add_theme_stylebox_override("normal", normal_style)
		
		# Create hover style with padding - exact same color as SimpleDropdownMenu
		var hover_style = StyleBoxFlat.new()
		hover_style.bg_color = Color(0.3, 0.3, 0.3, 1.0)
		hover_style.content_margin_left = submenu_padding_h
		hover_style.content_margin_right = submenu_padding_h
		hover_style.content_margin_top = submenu_padding_v
		hover_style.content_margin_bottom = submenu_padding_v
		button.add_theme_stylebox_override("hover", hover_style)
		
		# Create pressed style with padding - exact same color as SimpleDropdownMenu
		var pressed_style = StyleBoxFlat.new()
		pressed_style.bg_color = Color(0.25, 0.25, 0.25, 1.0)
		pressed_style.content_margin_left = submenu_padding_h
		pressed_style.content_margin_right = submenu_padding_h
		pressed_style.content_margin_top = submenu_padding_v
		pressed_style.content_margin_bottom = submenu_padding_v
		button.add_theme_stylebox_override("pressed", pressed_style)

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
	if submenu_item.get("enabled", true):
		item_selected.emit(submenu_item.id, submenu_item, context_data)
		hide_menu()

func _on_submenu_item_input(event: InputEvent, _submenu_item: Dictionary):
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
	print("ContextMenu_Base: hide_menu called")
	# Disable input processing methods
	set_process_unhandled_input(false)
	set_process_input(false)
	
	# Clean up polling timer
	var timer = get_node_or_null("InputPollingTimer")
	if timer:
		timer.queue_free()
	
	# Clean up delay timer
	var delay_timer = get_node_or_null("DelayTimer")
	if delay_timer:
		delay_timer.queue_free()
	
	# Reset right-click state
	_previous_right_click_state = false
	
	if main_popup and is_instance_valid(main_popup):
		main_popup.hide()
		# Remove from parent before freeing
		if main_popup.get_parent():
			main_popup.get_parent().remove_child(main_popup)
		main_popup.queue_free()
	main_popup = null
	
	_hide_submenu()
	
	# Clean up canvas layer
	if context_canvas and is_instance_valid(context_canvas):
		context_canvas.queue_free()
		context_canvas = null
	
	# Emit closed signal
	menu_closed.emit()

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

func set_item_padding(horizontal: int, vertical: int):
	"""Set the padding for menu items"""
	item_padding_horizontal = horizontal
	item_padding_vertical = vertical

func set_auto_size(enabled: bool):
	"""Enable/disable automatic width calculation"""
	auto_size = enabled

func set_width_constraints(min_w: int, max_w: int):
	"""Set minimum and maximum width constraints"""
	min_width = min_w
	max_width = max_w

func get_context_data() -> Dictionary:
	"""Get the context data passed when showing the menu"""
	return context_data

# Quick setup methods for common context menus
func setup_item_context_menu(item: InventoryItem_Base):
	"""Setup a typical inventory item context menu"""
	print("ContextMenu_Base: setup_item_context_menu called for item: ", item.item_name if item else "null")
	print("ContextMenu_Base: Item type: ", item.item_type if item else "null")
	
	clear_items()
	
	add_menu_item("item_info", "Item Information")
	
	if item.quantity > 1:
		add_menu_item("split_stack", "Split Stack")
	
	add_separator()
	
	match item.item_type:
		InventoryItem_Base.ItemType.CONSUMABLE:
			add_menu_item("use_item", "Use Item")
		InventoryItem_Base.ItemType.WEAPON, InventoryItem_Base.ItemType.ARMOR, InventoryItem_Base.ItemType.MODULE:
			add_menu_item("equip_item", "Equip Item")
		InventoryItem_Base.ItemType.CONTAINER:
			add_menu_item("open_container", "Open Container")
		InventoryItem_Base.ItemType.BLUEPRINT:
			add_menu_item("view_blueprint", "View Blueprint")
	
	add_separator()
	
	if item.can_be_destroyed:
		add_menu_item("destroy_item", "Destroy Item")
	
	print("ContextMenu_Base: Menu items added: ", menu_items.size())

func setup_empty_area_context_menu():
	"""Setup context menu for empty inventory areas"""
	clear_items()
	
	add_menu_item("stack_all", "Stack All Items")
	add_menu_item("sort_container", "Sort Container")
	add_separator()
	add_menu_item("clear_container", "Clear Container")

func setup_container_context_menu(_container: InventoryContainer_Base):
	"""Setup context menu for container management"""
	clear_items()
	
	add_menu_item("container_info", "Container Information")
	add_separator()
	
	# Move items submenu
	var move_submenu = []
	move_submenu.append({"id": "move_to_player", "text": "Personal Inventory"})
	move_submenu.append({"id": "move_to_cargo", "text": "Cargo Hold"})
	move_submenu.append({"id": "move_to_hangar", "text": "Hangar", "has_submenu": true, "submenu_items": [
		{"id": "move_to_hangar_1", "text": "Hangar Division 1"},
		{"id": "move_to_hangar_2", "text": "Hangar Division 2"},
		{"id": "move_to_hangar_3", "text": "Hangar Division 3"}
	]})
	
	add_menu_item("move_items", "Move Items", null, true, true, move_submenu)
	
	add_separator()
	add_menu_item("compact_container", "Compact Container")
	
	# Sort submenu
	var sort_submenu = []
	sort_submenu.append({"id": "sort_by_name", "text": "By Name"})
	sort_submenu.append({"id": "sort_by_type", "text": "By Type"})
	sort_submenu.append({"id": "sort_by_value", "text": "By Value"})
	sort_submenu.append({"id": "sort_by_volume", "text": "By Volume"})
	sort_submenu.append({"id": "sort_by_rarity", "text": "By Rarity"})
	
	add_menu_item("sort_container", "Sort Container", null, true, true, sort_submenu)
