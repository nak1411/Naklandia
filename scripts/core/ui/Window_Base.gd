# Window_Base.gd - Updated custom window implementation with debugging
class_name Window_Base
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
@export var corner_radius: float = 0.0

# Colors
@export var title_bar_color: Color = Color(0.15, 0.15, 0.15, 1.0)
@export var title_bar_active_color: Color = Color(0.2, 0.2, 0.2, 1.0)
@export var border_color: Color = Color(0.4, 0.4, 0.4, 1.0)
@export var border_active_color: Color = Color(0.2, 0.2, 0.2, 1.0)
@export var button_hover_color: Color = Color(0.3, 0.3, 0.3, 1.0)
@export var close_button_hover_color: Color = Color(0.8, 0.2, 0.2, 1.0)

# UI Components
var main_container: Control
var title_bar: Panel
var title_label: Label
var close_button: Button
var minimize_button: Button
var maximize_button: Button
var options_button: Button
var content_area: Control
var content_background: Panel

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
	print("Window_Base _init() called for: ", window_title)
	
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
	
	print("Window_Base _init() completed")

func _ready():
	print("Window_Base _ready() called for: ", window_title)
	_setup_custom_ui()
	_connect_signals()
	print("Window_Base _ready() completed")

func _process(_delta):
	# Handle smooth dragging
	if is_dragging and can_drag:
		var current_mouse_pos = Vector2i(get_viewport().get_mouse_position())
		position += current_mouse_pos - drag_start_position

func _setup_custom_ui():
	print("Setting up custom UI for Window_Base...")
	
	# Main container fills the entire window
	main_container = Control.new()
	main_container.name = "MainContainer"
	main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(main_container)
	print("Created main container")
	
	# Title bar - make sure it's at the top and receives input
	title_bar = Panel.new()
	title_bar.name = "TitleBar"
	title_bar.anchor_left = 0.0
	title_bar.anchor_top = 0.0
	title_bar.anchor_right = 1.0
	title_bar.anchor_bottom = 0.0
	title_bar.offset_bottom = title_bar_height
	title_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	title_bar.z_index = 100  # Ensure title bar is on top
	main_container.add_child(title_bar)
	print("Created title bar")
	
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
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let title bar handle input
	title_bar.add_child(title_label)
	print("Created title label: ", window_title)
	
	# Window control buttons
	_create_window_buttons()
	
	# Content area (below title bar) - adjust position and size
	content_area = Control.new()
	content_area.name = "ContentArea"
	content_area = Control.new()
	content_area.name = "ContentArea"
	content_area.anchor_left = 0.0
	content_area.anchor_top = 0.0
	content_area.anchor_right = 1.0
	content_area.anchor_bottom = 1.0
	content_area.offset_top = title_bar_height
	content_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_area.z_index = 1  # Below title bar
	main_container.add_child(content_area)
	print("Created content area")
	
	# Create a separate background panel that we can control transparency on
	content_background = Panel.new()
	content_background.name = "ContentBackground"
	content_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Style the background panel
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	content_background.add_theme_stylebox_override("panel", bg_style)
	
	content_area.add_child(content_background)
	print("Created content background")
	
	print("Window_Base UI setup completed")

func add_content(content: Control):
	
	if not content_area:
		print("ERROR: No content area available!")
		return
		
	if not content:
		print("ERROR: Cannot add null content!")
		return
	
	content_area.add_child(content)
	print("Content added successfully")

func _create_window_buttons():
	print("Creating window buttons...")
	
	var button_size = Vector2(title_bar_height - 4, title_bar_height - 4)
	var button_y = 2
	var button_spacing = button_size.x + 2
	
	# Calculate starting X position (from right edge)
	var start_x = size.x - button_spacing
	
	# Close button (rightmost)
	if can_close:
		close_button = Button.new()
		close_button.name = "CloseButton"
		close_button.text = "✕"
		close_button.size = button_size
		close_button.position = Vector2(start_x, button_y)
		close_button.flat = true
		title_bar.add_child(close_button)
		start_x -= button_spacing
		print("Created close button")
	
	# Maximize button
	if can_maximize:
		maximize_button = Button.new()
		maximize_button.name = "MaximizeButton"
		maximize_button.text = "□"
		maximize_button.size = button_size
		maximize_button.position = Vector2(start_x, button_y)
		maximize_button.flat = true
		title_bar.add_child(maximize_button)
		start_x -= button_spacing
		print("Created maximize button")
	
	# Minimize button
	if can_minimize:
		minimize_button = Button.new()
		minimize_button.name = "MinimizeButton"
		minimize_button.text = "−"
		minimize_button.size = button_size
		minimize_button.position = Vector2(start_x, button_y)
		minimize_button.flat = true
		title_bar.add_child(minimize_button)
		start_x -= button_spacing
		print("Created minimize button")

func _connect_signals():
	print("Connecting Window_Base signals...")
	
	# Title bar dragging
	if title_bar:
		title_bar.gui_input.connect(_on_title_bar_input)
		print("Connected title bar input")
	
	# Window buttons
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)
		close_button.mouse_entered.connect(_on_button_hover.bind(close_button, true))
		close_button.mouse_exited.connect(_on_button_hover.bind(close_button, false))
		print("Connected close button")
	
	if minimize_button:
		minimize_button.pressed.connect(_on_minimize_button_pressed)
		minimize_button.mouse_entered.connect(_on_button_hover.bind(minimize_button, true))
		minimize_button.mouse_exited.connect(_on_button_hover.bind(minimize_button, false))
		print("Connected minimize button")
	
	if maximize_button:
		maximize_button.pressed.connect(_on_maximize_button_pressed)
		maximize_button.mouse_entered.connect(_on_button_hover.bind(maximize_button, true))
		maximize_button.mouse_exited.connect(_on_button_hover.bind(maximize_button, false))
		print("Connected maximize button")

func _update_title_bar_style():
	if not title_bar:
		return
		
	var style = StyleBoxFlat.new()
	
	if is_window_focused:
		style.bg_color = title_bar_active_color
		style.border_color = border_active_color
	else:
		style.bg_color = title_bar_color
		style.border_color = border_color
	
	style.border_width_left = int(border_width)
	style.border_width_right = int(border_width)
	style.border_width_top = int(border_width)
	style.border_width_bottom = 1
	
	if corner_radius > 0:
		style.corner_radius_top_left = int(corner_radius)
		style.corner_radius_top_right = int(corner_radius)
	
	title_bar.add_theme_stylebox_override("panel", style)

# Input handling
func _on_title_bar_input(event: InputEvent):
	if not can_drag or window_locked:
		return
		
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# Start dragging
				is_dragging = true
				drag_start_position = get_viewport().get_mouse_position()
				drag_start_window_position = position
				Input.set_default_cursor_shape(Input.CURSOR_MOVE)
				print("Started dragging window")
				# Important: consume the event so it doesn't propagate
				get_viewport().set_input_as_handled()
			else:
				# Stop dragging
				is_dragging = false
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				print("Stopped dragging window")
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.double_click:
			# Double-click to maximize/restore
			if can_maximize:
				if is_maximized:
					restore_window()
				else:
					maximize_window()
				get_viewport().set_input_as_handled()

# Window button handlers
func _on_close_button_pressed():
	print("Close button pressed")
	close_window()

func _on_minimize_button_pressed():
	print("Minimize button pressed")
	minimize_window()

func _on_maximize_button_pressed():
	print("Maximize button pressed")
	if is_maximized:
		restore_window()
	else:
		maximize_window()

func close_window():
	print("Closing window: ", window_title)
	window_closed.emit()
	visible = false

func _on_button_hover(button: Button, hovering: bool):
	if hovering:
		if button == close_button:
			button.add_theme_stylebox_override("normal", _create_hover_style(close_button_hover_color))
		else:
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
	print("Minimizing window: ", window_title)
	visible = false
	window_minimized.emit()

func maximize_window():
	if is_maximized:
		print("Window already maximized")
		return
	
	print("Maximizing window: ", window_title)
	
	# Store current position and size for restoration
	restore_position = position
	restore_size = size
	
	# Get screen size and maximize
	var screen_size = DisplayServer.screen_get_size()
	position = Vector2i.ZERO
	size = screen_size
	
	is_maximized = true
	if maximize_button:
		maximize_button.text = "❐"  # Restore icon
	window_maximized.emit()

func restore_window():
	if not is_maximized:
		print("Window not maximized")
		return
	
	print("Restoring window: ", window_title)
	
	# Restore previous position and size
	position = restore_position
	size = restore_size
	
	is_maximized = false
	if maximize_button:
		maximize_button.text = "□"  # Maximize icon
	window_restored.emit()

# Focus handling
func _on_window_focus_entered():
	print("Window focused: ", window_title)
	is_window_focused = true
	_update_title_bar_style()
	window_focus_changed.emit(true)

func _on_window_focus_exited():
	print("Window unfocused: ", window_title)
	is_window_focused = false
	_update_title_bar_style()
	window_focus_changed.emit(false)

# Public interface
func set_window_title(new_title: String):
	print("Setting window title to: ", new_title)
	window_title = new_title
	title = new_title
	if title_label:
		title_label.text = new_title

func set_dragging_enabled(enabled: bool):
	print("Setting dragging enabled: ", enabled)
	can_drag = enabled
	# Reset any drag state when disabling
	if not enabled and is_dragging:
		is_dragging = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func get_window_locked() -> bool:
	return window_locked

func set_window_locked(locked: bool):
	print("Setting window locked: ", locked)
	window_locked = locked
	set_dragging_enabled(not locked)
	window_locked_changed.emit(locked)

func get_transparency() -> float:
	return window_transparency

func set_transparency(value: float):
	print("Setting transparency to: ", value)
	window_transparency = value
	
	# Simply modulate the entire content area (everything except title bar)
	if content_area:
		content_area.modulate.a = value
	
	transparency_changed.emit(value)

func get_content_area() -> Control:
	return content_area

# Debug method
func debug_window_state():
	print("\n=== WINDOW_BASE DEBUG ===")
	print("Window title: ", window_title)
	print("Window visible: ", visible)
	print("Window size: ", size)
	print("Window position: ", position)
	print("main_container: ", main_container)
	print("title_bar: ", title_bar)
	print("title_label: ", title_label)
	print("content_area: ", content_area)
	print("content_background: ", content_background)
	print("is_dragging: ", is_dragging)
	print("is_window_focused: ", is_window_focused)
	print("is_maximized: ", is_maximized)
	print("window_locked: ", window_locked)
	print("window_transparency: ", window_transparency)
	
	if content_area:
		print("Content area children: ", content_area.get_child_count())
		for i in range(content_area.get_child_count()):
			var child = content_area.get_child(i)
			print("  [", i, "] ", child.name, " (", child.get_class(), ")")
	
	print("=== END WINDOW_BASE DEBUG ===\n")

# Size change handling (for derived classes)
func _on_size_changed():
	# Update button positions when window is resized
	if title_bar and close_button:
		call_deferred("_update_button_positions")

func _update_button_positions():
	if not title_bar:
		return
		
	var button_size = Vector2(title_bar_height - 4, title_bar_height - 4)
	var _button_y = 2
	var button_spacing = button_size.x + 2
	var start_x = size.x - button_spacing
	
	if close_button:
		close_button.position.x = start_x
		start_x -= button_spacing
	
	if maximize_button:
		maximize_button.position.x = start_x
		start_x -= button_spacing
	
	if minimize_button:
		minimize_button.position.x = start_x
