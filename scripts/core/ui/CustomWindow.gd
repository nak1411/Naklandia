# CustomWindow.gd - Custom window implementation with full control
class_name CustomWindow
extends Window

# Window properties
@export var window_title: String = "Custom Window"
@export var can_drag: bool = true
@export var can_close: bool = true
@export var can_minimize: bool = true
@export var can_maximize: bool = true

# Visual properties
@export var title_bar_height: float = 32.0
@export var border_width: float = 2.0
@export var corner_radius: float = 8.0

# Colors
@export var title_bar_color: Color = Color(0.15, 0.15, 0.15, 1.0)
@export var title_bar_active_color: Color = Color(0.2, 0.2, 0.2, 1.0)
@export var border_color: Color = Color(0.4, 0.4, 0.4, 1.0)
@export var border_active_color: Color = Color(0.6, 0.6, 0.8, 1.0)
@export var button_hover_color: Color = Color(0.3, 0.3, 0.3, 1.0)
@export var close_button_hover_color: Color = Color(0.8, 0.2, 0.2, 1.0)

# UI Components
var main_container: Control
var title_bar: Panel
var title_label: Label
var close_button: Button
var minimize_button: Button
var maximize_button: Button
var options_button: MenuButton
var content_area: Control
var content_background: Panel  # Separate background panel we can control

# State
var is_dragging: bool = false
var is_resizing: bool = false
var drag_start_position: Vector2i
var drag_start_window_position: Vector2i
var is_window_focused: bool = true
var is_maximized: bool = false
var restore_position: Vector2i
var restore_size: Vector2i
var window_locked: bool = false
var window_transparency: float = 1.0

# Signals
signal window_closed()
signal window_minimized()
signal window_maximized()
signal window_restored()
signal window_focus_changed(focused: bool)
signal window_locked_changed(locked: bool)
signal transparency_changed(value: float)

func _init():
	# Make window borderless so we can draw our own
	set_flag(Window.FLAG_BORDERLESS, true)
	# Enable transparency for the window
	set_flag(Window.FLAG_TRANSPARENT, true)
	
	# Set up basic window properties
	title = window_title
	min_size = Vector2i(300, 200)
	
	# Connect window signals
	focus_entered.connect(_on_window_focus_entered)
	focus_exited.connect(_on_window_focus_exited)

func _ready():
	_setup_custom_ui()
	_connect_signals()

func _process(_delta):
	# Handle smooth dragging
	if is_dragging and can_drag:
		var current_mouse_pos = Vector2i(get_viewport().get_mouse_position())
		
		position += current_mouse_pos - drag_start_position

func _setup_custom_ui():
	# Main container fills the entire window
	main_container = Control.new()
	main_container.name = "MainContainer"
	main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(main_container)
	
	# Title bar
	title_bar = Panel.new()
	title_bar.name = "TitleBar"
	title_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title_bar.size.y = title_bar_height
	title_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	main_container.add_child(title_bar)
	
	# Style title bar
	_update_title_bar_style()
	
	# Title label
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = window_title
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.position = Vector2(12, 0)
	title_label.size = Vector2(200, title_bar_height)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(title_label)
	
	# Window control buttons
	_create_window_buttons()
	
	# Content area (below title bar)
	content_area = Control.new()
	content_area.name = "ContentArea"
	content_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_area.position.y = title_bar_height
	content_area.size.y -= title_bar_height
	content_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_container.add_child(content_area)
	
	# Create a separate background panel that we can control transparency on
	content_background = Panel.new()
	content_background.name = "ContentBackground"
	content_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Style the background panel
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.1, 1.0)  # Dark background
	content_background.add_theme_stylebox_override("panel", bg_style)
	
	content_area.add_child(content_background)

func _create_window_buttons():
	var button_size = Vector2(title_bar_height - 4, title_bar_height - 4)
	var button_y = 2
	var button_spacing = 2
	
	# Close button (rightmost)
	if can_close:
		close_button = Button.new()
		close_button.name = "CloseButton"
		close_button.text = "×"
		close_button.size = button_size
		close_button.position = Vector2(size.x - button_size.x - 8, button_y)
		close_button.flat = true
		close_button.add_theme_font_size_override("font_size", 16)
		close_button.add_theme_color_override("font_color", Color.WHITE)
		title_bar.add_child(close_button)
	
	# Maximize button
	if can_maximize:
		maximize_button = Button.new()
		maximize_button.name = "MaximizeButton"
		maximize_button.text = "□"
		maximize_button.size = button_size
		var max_x = size.x - button_size.x - 8
		if can_close:
			max_x -= button_size.x + button_spacing
		maximize_button.position = Vector2(max_x, button_y)
		maximize_button.flat = true
		maximize_button.add_theme_font_size_override("font_size", 12)
		maximize_button.add_theme_color_override("font_color", Color.WHITE)
		title_bar.add_child(maximize_button)
	
	# Minimize button
	if can_minimize:
		minimize_button = Button.new()
		minimize_button.name = "MinimizeButton"
		minimize_button.text = "−"
		minimize_button.size = button_size
		var min_x = size.x - button_size.x - 8
		if can_close:
			min_x -= button_size.x + button_spacing
		if can_maximize:
			min_x -= button_size.x + button_spacing
		minimize_button.position = Vector2(min_x, button_y)
		minimize_button.flat = true
		minimize_button.add_theme_font_size_override("font_size", 12)
		minimize_button.add_theme_color_override("font_color", Color.WHITE)
		title_bar.add_child(minimize_button)
	
	# Options button
	options_button = MenuButton.new()
	options_button.name = "OptionsButton"
	options_button.text = "⚙"
	options_button.size = button_size
	var options_x = size.x - button_size.x - 8
	if can_close:
		options_x -= button_size.x + button_spacing
	if can_maximize:
		options_x -= button_size.x + button_spacing
	if can_minimize:
		options_x -= button_size.x + button_spacing
	options_button.position = Vector2(options_x, button_y)
	options_button.flat = true
	options_button.add_theme_font_size_override("font_size", 12)
	options_button.add_theme_color_override("font_color", Color.WHITE)
	title_bar.add_child(options_button)
	
	_setup_options_menu()

func _connect_signals():
	# Title bar dragging
	title_bar.gui_input.connect(_on_title_bar_input)
	
	# Window control buttons
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)
		close_button.mouse_entered.connect(_on_close_button_hover.bind(true))
		close_button.mouse_exited.connect(_on_close_button_hover.bind(false))
	
	if minimize_button:
		minimize_button.pressed.connect(_on_minimize_button_pressed)
		minimize_button.mouse_entered.connect(_on_button_hover.bind(minimize_button, true))
		minimize_button.mouse_exited.connect(_on_button_hover.bind(minimize_button, false))
	
	if maximize_button:
		maximize_button.pressed.connect(_on_maximize_button_pressed)
		maximize_button.mouse_entered.connect(_on_button_hover.bind(maximize_button, true))
		maximize_button.mouse_exited.connect(_on_button_hover.bind(maximize_button, false))
	
	if options_button:
		options_button.mouse_entered.connect(_on_button_hover.bind(options_button, true))
		options_button.mouse_exited.connect(_on_button_hover.bind(options_button, false))

func _update_title_bar_style():
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = title_bar_active_color if is_window_focused else title_bar_color
	style_box.border_width_left = 0
	style_box.border_width_right = 0
	style_box.border_width_top = 0
	style_box.border_width_bottom = 1
	style_box.border_color = border_active_color if is_window_focused else border_color
	style_box.corner_radius_top_left = corner_radius
	style_box.corner_radius_top_right = corner_radius
	title_bar.add_theme_stylebox_override("panel", style_box)

func _setup_options_menu():
	var popup = options_button.get_popup()
	popup.add_check_item("Lock Window")
	popup.add_separator()
	popup.add_item("Transparency: 100%")
	popup.add_item("Reset Transparency")
	
	popup.id_pressed.connect(_on_options_menu_selected)

func _on_options_menu_selected(id: int):
	var popup = options_button.get_popup()
	match id:
		0:  # Lock Window
			window_locked = not window_locked
			popup.set_item_checked(0, window_locked)
			set_dragging_enabled(not window_locked)
			window_locked_changed.emit(window_locked)
		2:  # Transparency (placeholder - opens dialog)
			_show_transparency_dialog()
		3:  # Reset Transparency
			_set_transparency(1.0)

func _show_transparency_dialog():
	# Create a new independent window for the dialog
	var dialog_window = Window.new()
	dialog_window.title = "Window Transparency"
	dialog_window.size = Vector2i(300, 120)
	dialog_window.unresizable = true
	dialog_window.always_on_top = true
	dialog_window.set_flag(Window.FLAG_POPUP, false)
	
	# Position relative to this window
	var window_center = position + size / 2
	dialog_window.position = Vector2i(window_center - dialog_window.size / 2)
	
	# Create content container
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("margin_left", 10)
	vbox.add_theme_constant_override("margin_right", 10)
	vbox.add_theme_constant_override("margin_top", 10)
	vbox.add_theme_constant_override("margin_bottom", 10)
	
	var label = Label.new()
	label.text = "Transparency: %d%%" % int(window_transparency * 100)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)
	
	var slider = HSlider.new()
	slider.min_value = 0.1
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = window_transparency
	slider.custom_minimum_size.x = 250
	vbox.add_child(slider)
	
	var close_button = Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(80, 30)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(close_button)
	
	dialog_window.add_child(vbox)
	
	# Connect slider
	slider.value_changed.connect(func(value):
		_set_transparency(value)
		label.text = "Transparency: %d%%" % int(value * 100)
	)
	
	# Add to scene and show
	get_tree().current_scene.add_child(dialog_window)
	dialog_window.popup()
	dialog_window.grab_focus()
	
	# Connect close events
	close_button.pressed.connect(func():
		dialog_window.queue_free()
		grab_focus()
	)
	
	dialog_window.close_requested.connect(func():
		dialog_window.queue_free()
		grab_focus()
	)

func _set_transparency(value: float):
	window_transparency = value
	if content_background:
		var current_modulate = content_background.modulate
		current_modulate.a = value
		content_background.modulate = current_modulate
	
	# Update menu text
	var popup = options_button.get_popup()
	popup.set_item_text(2, "Transparency: %d%%" % int(value * 100))
	
	transparency_changed.emit(value)

# Input handling
func _on_title_bar_input(event: InputEvent):
	if not can_drag or window_locked:
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# Start dragging - store initial positions
				is_dragging = true
				drag_start_position = get_viewport().get_mouse_position()
				drag_start_window_position = position
			else:
				# Stop dragging
				is_dragging = false
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.double_click:
			# Double-click to maximize/restore
			if can_maximize:
				if is_maximized:
					restore_window()
				else:
					maximize_window()

# Window control handlers
func _on_close_button_pressed():
	window_closed.emit()

func _on_minimize_button_pressed():
	minimize_window()

func _on_maximize_button_pressed():
	if is_maximized:
		restore_window()
	else:
		maximize_window()

func _on_close_button_hover(hovering: bool):
	if hovering:
		close_button.add_theme_color_override("font_color", Color.WHITE)
		close_button.add_theme_stylebox_override("normal", _create_hover_style(close_button_hover_color))
	else:
		close_button.remove_theme_color_override("font_color")
		close_button.remove_theme_stylebox_override("normal")

func _on_button_hover(button: Button, hovering: bool):
	if hovering:
		button.add_theme_stylebox_override("normal", _create_hover_style(button_hover_color))
	else:
		button.remove_theme_stylebox_override("normal")

func _create_hover_style(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

# Window state management
func minimize_window():
	# Note: Godot doesn't support true minimization, so we hide the window
	visible = false
	window_minimized.emit()

func maximize_window():
	if is_maximized:
		return
	
	# Store current position and size for restoration
	restore_position = position
	restore_size = size
	
	# Get screen size and maximize
	var screen_size = DisplayServer.screen_get_size()
	position = Vector2i.ZERO
	size = screen_size
	
	is_maximized = true
	maximize_button.text = "❐"  # Restore icon
	window_maximized.emit()

func restore_window():
	if not is_maximized:
		return
	
	# Restore previous position and size
	position = restore_position
	size = restore_size
	
	is_maximized = false
	maximize_button.text = "□"  # Maximize icon
	window_restored.emit()

# Focus handling
func _on_window_focus_entered():
	is_window_focused = true
	_update_title_bar_style()
	window_focus_changed.emit(true)

func _on_window_focus_exited():
	is_window_focused = false
	_update_title_bar_style()
	window_focus_changed.emit(false)

# Public interface
func set_window_title(new_title: String):
	window_title = new_title
	title = new_title
	if title_label:
		title_label.text = new_title

func set_dragging_enabled(enabled: bool):
	can_drag = enabled
	# Reset any drag state when disabling
	if not enabled and is_dragging:
		is_dragging = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func get_window_locked() -> bool:
	return window_locked

func set_window_locked(locked: bool):
	window_locked = locked
	var popup = options_button.get_popup()
	popup.set_item_checked(0, locked)
	set_dragging_enabled(not locked)

func get_transparency() -> float:
	return window_transparency

func set_transparency(value: float):
	_set_transparency(value)

func get_content_area() -> Control:
	return content_area

func add_content(content: Control):
	if content_area:
		content_area.add_child(content)
