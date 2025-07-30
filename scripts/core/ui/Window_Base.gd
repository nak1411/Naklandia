# Window_Base.gd - Updated custom window implementation with debugging
class_name Window_Base
extends Window

# Window properties
@export var window_title: String = "Custom Window"
@export var can_drag: bool = true
@export var can_close: bool = true
@export var can_minimize: bool = true
@export var can_maximize: bool = true
@export var can_resize: bool = true
@export var resize_border_width: float = 8.0
@export var resize_corner_size: float = 16.0

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
var resize_mode: ResizeMode = ResizeMode.NONE
var resize_start_position: Vector2i
var resize_start_size: Vector2i
var resize_start_mouse: Vector2i

# Resize overlay controls
var resize_overlay: Control
var resize_areas: Array[Control] = []

enum ResizeMode {
	NONE,
	LEFT,
	RIGHT,
	TOP,
	BOTTOM,
	TOP_LEFT,
	TOP_RIGHT,
	BOTTOM_LEFT,
	BOTTOM_RIGHT
}

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
	
	# Connect resize signals
	size_changed.connect(_on_size_changed)

func _process(_delta):
	# Handle smooth dragging
	if is_dragging and can_drag:
		var current_mouse_pos = Vector2i(get_viewport().get_mouse_position())
		position += current_mouse_pos - drag_start_position
	
	# Handle resizing
	elif is_resizing and can_resize:
		print("_process: handling resize")
		_handle_resize()
		
func _input(event: InputEvent):
	# Only handle if we're currently resizing
	if is_resizing and event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			_handle_resize_end()
			get_viewport().set_input_as_handled()
		
func _unhandled_input(event: InputEvent):
	if not can_resize or window_locked or is_maximized:
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_handle_resize_start(mouse_event.global_position)
			else:
				_handle_resize_end()
	elif event is InputEventMouseMotion:
		# Handle cursor updates on mouse motion
		if not is_resizing and not is_dragging:
			_update_resize_cursor()

func _setup_custom_ui():
	print("_setup_custom_ui() called BASE WINDOW")
	# Main container fills the entire window
	main_container = Control.new()
	main_container.name = "MainContainer"
	main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(main_container)
	
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
	
	if can_resize:
		_create_resize_overlay()

func add_content(content: Control):
	
	if not content_area:
		return
		
	if not content:
		return
	
	content_area.add_child(content)

func _create_window_buttons():	
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

func _connect_signals():	
	# Title bar dragging
	if title_bar:
		title_bar.gui_input.connect(_on_title_bar_input)
	
	# Window buttons
	if close_button:
		close_button.pressed.connect(_on_close_button_pressed)
		close_button.mouse_entered.connect(_on_button_hover.bind(close_button, true))
		close_button.mouse_exited.connect(_on_button_hover.bind(close_button, false))
	
	if minimize_button:
		minimize_button.pressed.connect(_on_minimize_button_pressed)
		minimize_button.mouse_entered.connect(_on_button_hover.bind(minimize_button, true))
		minimize_button.mouse_exited.connect(_on_button_hover.bind(minimize_button, false))
	
	if maximize_button:
		maximize_button.pressed.connect(_on_maximize_button_pressed)
		maximize_button.mouse_entered.connect(_on_button_hover.bind(maximize_button, true))
		maximize_button.mouse_exited.connect(_on_button_hover.bind(maximize_button, false))

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
	if window_locked:
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# Check for resize area first
				if can_resize:
					var resize_area = _get_resize_area(mouse_event.global_position)
					if resize_area != ResizeMode.NONE:
						_handle_resize_start(mouse_event.global_position)
						get_viewport().set_input_as_handled()
						return
				
				# If not resizing and can drag, start dragging
				if can_drag:
					is_dragging = true
					drag_start_position = get_viewport().get_mouse_position()
					drag_start_window_position = position
					Input.set_default_cursor_shape(Input.CURSOR_MOVE)
					get_viewport().set_input_as_handled()
			else:
				# Handle mouse release for both dragging and resizing
				if is_resizing:
					_handle_resize_end()
				elif is_dragging:
					is_dragging = false
					Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.double_click:
			# Double-click to maximize/restore
			if can_maximize:
				if is_maximized:
					restore_window()
				else:
					maximize_window()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		# Update cursor based on position
		if not is_dragging and not is_resizing and can_resize:
			_update_resize_cursor()

# Window button handlers
func _on_close_button_pressed():
	close_window()

func _on_minimize_button_pressed():
	minimize_window()

func _on_maximize_button_pressed():
	if is_maximized:
		restore_window()
	else:
		maximize_window()

func close_window():
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
	return style

# Window state management
func minimize_window():
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
	if maximize_button:
		maximize_button.text = "❐"  # Restore icon
	window_maximized.emit()

func restore_window():
	if not is_maximized:
		return
		
	# Restore previous position and size
	position = restore_position
	size = restore_size
	
	is_maximized = false
	if maximize_button:
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
	set_dragging_enabled(not locked)
	window_locked_changed.emit(locked)

func get_transparency() -> float:
	return window_transparency

func set_transparency(value: float):
	window_transparency = value
	
	# Simply modulate the entire content area (everything except title bar)
	if content_area:
		content_area.modulate.a = value
	
	transparency_changed.emit(value)

func get_content_area() -> Control:
	return content_area

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
		
func _handle_resize_start(mouse_pos: Vector2):
	var resize_area = _get_resize_area(mouse_pos)
	if resize_area != ResizeMode.NONE:
		is_resizing = true
		resize_mode = resize_area
		resize_start_position = position
		resize_start_size = size
		resize_start_mouse = Vector2i(mouse_pos)
		get_viewport().set_input_as_handled()

func _handle_resize_end():
	if is_resizing:
		is_resizing = false
		resize_mode = ResizeMode.NONE
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _handle_resize():
	if not is_resizing:
		return
		
	var current_mouse = Vector2i(get_viewport().get_mouse_position())
	var mouse_delta = current_mouse - resize_start_mouse
	
	print("Handling resize - mouse_delta: ", mouse_delta, " mode: ", resize_mode)
	
	var new_position = resize_start_position
	var new_size = resize_start_size
	
	match resize_mode:
		ResizeMode.LEFT:
			new_position.x = resize_start_position.x + mouse_delta.x
			new_size.x = resize_start_size.x - mouse_delta.x
		ResizeMode.RIGHT:
			new_size.x = resize_start_size.x + mouse_delta.x
		ResizeMode.TOP:
			new_position.y = resize_start_position.y + mouse_delta.y
			new_size.y = resize_start_size.y - mouse_delta.y
		ResizeMode.BOTTOM:
			new_size.y = resize_start_size.y + mouse_delta.y
		ResizeMode.TOP_LEFT:
			new_position.x = resize_start_position.x + mouse_delta.x
			new_position.y = resize_start_position.y + mouse_delta.y
			new_size.x = resize_start_size.x - mouse_delta.x
			new_size.y = resize_start_size.y - mouse_delta.y
		ResizeMode.TOP_RIGHT:
			new_position.y = resize_start_position.y + mouse_delta.y
			new_size.x = resize_start_size.x + mouse_delta.x
			new_size.y = resize_start_size.y - mouse_delta.y
		ResizeMode.BOTTOM_LEFT:
			new_position.x = resize_start_position.x + mouse_delta.x
			new_size.x = resize_start_size.x - mouse_delta.x
			new_size.y = resize_start_size.y + mouse_delta.y
		ResizeMode.BOTTOM_RIGHT:
			new_size.x = resize_start_size.x + mouse_delta.x
			new_size.y = resize_start_size.y + mouse_delta.y
	
	# Apply minimum size constraints
	new_size.x = maxi(new_size.x, min_size.x)
	new_size.y = maxi(new_size.y, min_size.y)
	
	# Adjust position if we hit minimum size while resizing from top/left
	if resize_mode in [ResizeMode.LEFT, ResizeMode.TOP_LEFT, ResizeMode.BOTTOM_LEFT]:
		if new_size.x == min_size.x:
			new_position.x = resize_start_position.x + resize_start_size.x - min_size.x
	
	if resize_mode in [ResizeMode.TOP, ResizeMode.TOP_LEFT, ResizeMode.TOP_RIGHT]:
		if new_size.y == min_size.y:
			new_position.y = resize_start_position.y + resize_start_size.y - min_size.y
	
	print("Setting new position: ", new_position, " new size: ", new_size)
	
	# Apply new position and size
	position = new_position
	size = new_size

func _get_resize_area(mouse_pos: Vector2) -> ResizeMode:
	# Convert global mouse position to window-local coordinates
	var window_rect = Rect2(Vector2(position), Vector2(size))
	
	# Check if mouse is within window bounds
	if not window_rect.has_point(mouse_pos):
		return ResizeMode.NONE
	
	# Get position relative to window
	var local_pos = mouse_pos - Vector2(position)
	var window_size = Vector2(size)
	
	# Make sure we're not in the title bar area (except for top resize)
	if local_pos.y <= title_bar_height and local_pos.y > resize_border_width:
		# In title bar, only allow top resize at the very edge
		if local_pos.y > resize_border_width:
			return ResizeMode.NONE
	
	# Check if mouse is within resize borders
	var in_left = local_pos.x <= resize_border_width
	var in_right = local_pos.x >= window_size.x - resize_border_width
	var in_top = local_pos.y <= resize_border_width
	var in_bottom = local_pos.y >= window_size.y - resize_border_width
	
	# Check corners first (they take priority)
	if in_top and in_left and local_pos.x <= resize_corner_size and local_pos.y <= resize_corner_size:
		return ResizeMode.TOP_LEFT
	elif in_top and in_right and local_pos.x >= window_size.x - resize_corner_size and local_pos.y <= resize_corner_size:
		return ResizeMode.TOP_RIGHT
	elif in_bottom and in_left and local_pos.x <= resize_corner_size and local_pos.y >= window_size.y - resize_corner_size:
		return ResizeMode.BOTTOM_LEFT
	elif in_bottom and in_right and local_pos.x >= window_size.x - resize_corner_size and local_pos.y >= window_size.y - resize_corner_size:
		return ResizeMode.BOTTOM_RIGHT
	
	# Check edges
	elif in_left:
		return ResizeMode.LEFT
	elif in_right:
		return ResizeMode.RIGHT
	elif in_top:
		return ResizeMode.TOP
	elif in_bottom:
		return ResizeMode.BOTTOM
	
	return ResizeMode.NONE

func _update_resize_cursor():
	var mouse_pos = get_viewport().get_mouse_position()
	var resize_area = _get_resize_area(mouse_pos)
	
	match resize_area:
		ResizeMode.LEFT, ResizeMode.RIGHT:
			Input.set_default_cursor_shape(Input.CURSOR_HSIZE)
		ResizeMode.TOP, ResizeMode.BOTTOM:
			Input.set_default_cursor_shape(Input.CURSOR_VSIZE)
		ResizeMode.TOP_LEFT, ResizeMode.BOTTOM_RIGHT:
			Input.set_default_cursor_shape(Input.CURSOR_FDIAGSIZE)
		ResizeMode.TOP_RIGHT, ResizeMode.BOTTOM_LEFT:
			Input.set_default_cursor_shape(Input.CURSOR_BDIAGSIZE)
		ResizeMode.NONE:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			
func _create_resize_overlay():
	# Create invisible overlay for resize detection
	resize_overlay = Control.new()
	resize_overlay.name = "ResizeOverlay"
	resize_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resize_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resize_overlay.z_index = 200  # Above everything else
	main_container.add_child(resize_overlay)
	
	# Create resize areas
	_create_resize_areas()

func _create_resize_areas():
	resize_areas.clear()
	
	# Left edge
	var left_area = _create_resize_area("LeftResize", ResizeMode.LEFT)
	left_area.anchor_left = 0.0
	left_area.anchor_right = 0.0
	left_area.anchor_top = 0.0
	left_area.anchor_bottom = 1.0
	left_area.offset_right = resize_border_width
	
	# Right edge  
	var right_area = _create_resize_area("RightResize", ResizeMode.RIGHT)
	right_area.anchor_left = 1.0
	right_area.anchor_right = 1.0
	right_area.anchor_top = 0.0
	right_area.anchor_bottom = 1.0
	right_area.offset_left = -resize_border_width
	
	# Top edge
	var top_area = _create_resize_area("TopResize", ResizeMode.TOP)
	top_area.anchor_left = 0.0
	top_area.anchor_right = 1.0
	top_area.anchor_top = 0.0
	top_area.anchor_bottom = 0.0
	top_area.offset_bottom = resize_border_width
	
	# Bottom edge
	var bottom_area = _create_resize_area("BottomResize", ResizeMode.BOTTOM)
	bottom_area.anchor_left = 0.0
	bottom_area.anchor_right = 1.0
	bottom_area.anchor_top = 1.0
	bottom_area.anchor_bottom = 1.0
	bottom_area.offset_top = -resize_border_width
	
	# Corners (higher priority)
	var corner_size = resize_border_width * 2
	
	# Top-left corner
	var tl_corner = _create_resize_area("TopLeftCorner", ResizeMode.TOP_LEFT)
	tl_corner.anchor_left = 0.0
	tl_corner.anchor_right = 0.0
	tl_corner.anchor_top = 0.0
	tl_corner.anchor_bottom = 0.0
	tl_corner.offset_right = corner_size
	tl_corner.offset_bottom = corner_size
	
	# Top-right corner
	var tr_corner = _create_resize_area("TopRightCorner", ResizeMode.TOP_RIGHT)
	tr_corner.anchor_left = 1.0
	tr_corner.anchor_right = 1.0
	tr_corner.anchor_top = 0.0
	tr_corner.anchor_bottom = 0.0
	tr_corner.offset_left = -corner_size
	tr_corner.offset_bottom = corner_size
	
	# Bottom-left corner
	var bl_corner = _create_resize_area("BottomLeftCorner", ResizeMode.BOTTOM_LEFT)
	bl_corner.anchor_left = 0.0
	bl_corner.anchor_right = 0.0
	bl_corner.anchor_top = 1.0
	bl_corner.anchor_bottom = 1.0
	bl_corner.offset_right = corner_size
	bl_corner.offset_top = -corner_size
	
	# Bottom-right corner
	var br_corner = _create_resize_area("BottomRightCorner", ResizeMode.BOTTOM_RIGHT)
	br_corner.anchor_left = 1.0
	br_corner.anchor_right = 1.0
	br_corner.anchor_top = 1.0
	br_corner.anchor_bottom = 1.0
	br_corner.offset_left = -corner_size
	br_corner.offset_top = -corner_size

func _create_resize_area(area_name: String, mode: ResizeMode) -> Control:
	var area = Control.new()
	area.name = area_name
	area.mouse_filter = Control.MOUSE_FILTER_PASS
	area.set_meta("resize_mode", mode)
	
	# Debug: Make resize areas visible temporarily
	var debug_style = StyleBoxFlat.new()
	debug_style.bg_color = Color(1, 0, 0, 0.3)  # Semi-transparent red
	var debug_panel = Panel.new()
	debug_panel.add_theme_stylebox_override("panel", debug_style)
	debug_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(debug_panel)
	
	# Connect signals
	area.gui_input.connect(_on_resize_area_input.bind(mode))
	area.mouse_entered.connect(_on_resize_area_entered.bind(mode))
	area.mouse_exited.connect(_on_resize_area_exited)
	
	resize_overlay.add_child(area)
	resize_areas.append(area)
	
	print("Created resize area: ", area_name, " with mode: ", mode)
	
	return area


func _on_resize_area_input(mode: ResizeMode, event: InputEvent):
	print("Resize area input received: ", mode, " event: ", event)
	
	if not can_resize or window_locked or is_maximized:
		print("Resize blocked - can_resize: ", can_resize, " locked: ", window_locked, " maximized: ", is_maximized)
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				print("Starting resize with mode: ", mode)
				_start_resize(mode, mouse_event.global_position)
			else:
				print("Ending resize")
				_end_resize()

func _on_resize_area_entered(mode: ResizeMode):
	print("Mouse entered resize area: ", mode)
	
	if not can_resize or window_locked or is_maximized or is_dragging:
		return
	
	match mode:
		ResizeMode.LEFT, ResizeMode.RIGHT:
			Input.set_default_cursor_shape(Input.CURSOR_HSIZE)
		ResizeMode.TOP, ResizeMode.BOTTOM:
			Input.set_default_cursor_shape(Input.CURSOR_VSIZE)
		ResizeMode.TOP_LEFT, ResizeMode.BOTTOM_RIGHT:
			Input.set_default_cursor_shape(Input.CURSOR_FDIAGSIZE)
		ResizeMode.TOP_RIGHT, ResizeMode.BOTTOM_LEFT:
			Input.set_default_cursor_shape(Input.CURSOR_BDIAGSIZE)

func _on_resize_area_exited():
	if not is_resizing and not is_dragging:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _start_resize(mode: ResizeMode, mouse_pos: Vector2):
	print("_start_resize called with mode: ", mode, " at position: ", mouse_pos)
	is_resizing = true
	resize_mode = mode
	resize_start_position = position
	resize_start_size = size
	resize_start_mouse = Vector2i(mouse_pos)

func _end_resize():
	if is_resizing:
		is_resizing = false
		resize_mode = ResizeMode.NONE
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


# Add public interface methods:
func set_resizing_enabled(enabled: bool):
	can_resize = enabled
	if resize_overlay:
		resize_overlay.visible = enabled
	if not enabled and is_resizing:
		_end_resize()

func get_resizing_enabled() -> bool:
	return can_resize
