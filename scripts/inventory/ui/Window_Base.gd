# Window_Base.gd - Base class for all custom windows using CanvasLayer system
class_name Window_Base
extends Control

# Window properties
@export var window_title: String = "Window"
@export var default_size: Vector2 = Vector2(800, 600)
@export var min_window_size: Vector2 = Vector2(400, 300)
@export var max_window_size: Vector2 = Vector2(1400, 1000)
@export var can_resize: bool = true
@export var can_drag: bool = true
@export var can_close: bool = true
@export var can_minimize: bool = false
@export var can_maximize: bool = true
@export var resize_border_width: float = 8.0
@export var resize_corner_size: float = 8.0

# Window state
var is_maximized: bool = false
var restore_position: Vector2
var restore_size: Vector2
var drag_threshold: float = 5.0
var click_start_position: Vector2
var drag_initiated: bool = false
var mouse_pressed: bool = false
var is_locked: bool = false
var is_dragging: bool = false
var drag_start_position: Vector2
var is_resizing: bool = false
var resize_mode: ResizeMode = ResizeMode.NONE
var resize_start_position: Vector2
var resize_start_size: Vector2
var resize_start_mouse: Vector2
var _was_resizing: bool = false

# UI Components
var main_container: Control
var title_bar: Panel
var title_label: Label
var close_button: Button
var minimize_button: Button
var maximize_button: Button
var content_area: Control
var background_panel: Panel
var lock_indicator: Label
var resize_border_visual: Control
var border_lines: Array[ColorRect] = []
var corner_indicators: Array[ColorRect] = []
var options_button: Button
var options_dropdown: DropDownMenu_Base

# Resize overlay
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

# Window styling
var title_bar_height: float = 32.0
var border_width: float = 2.0
var title_bar_color: Color = Color(0.1, 0.1, 0.1, 1.0)
var border_color: Color = Color(0.4, 0.4, 0.4, 1.0)
var background_color: Color = Color(0.15, 0.15, 0.15, 1.0)

# Signals
signal window_closed()
signal window_minimized()
signal window_maximized()
signal window_restored()
signal window_resized(new_size: Vector2i)
signal window_moved(new_position: Vector2i)

func _init():
	# Set up as a window-like control
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = default_size
	position = Vector2(200, 100)
	visible = false
	
	# Enable input handling
	mouse_filter = Control.MOUSE_FILTER_PASS

func _ready():
	_setup_window_ui()
	_setup_resize_overlay()
	
	# Call virtual method for child classes to override
	call_deferred("_setup_window_content")

func _input(event: InputEvent):
	if not visible or is_locked:
		return
		
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_handle_mouse_press(mouse_event.global_position)
			else:
				_handle_mouse_release()
	elif event is InputEventMouseMotion and (is_dragging or is_resizing or mouse_pressed):
		_handle_mouse_motion(event as InputEventMouseMotion)

func _handle_mouse_press(global_pos: Vector2):
	# Check if we're starting a resize operation first
	if can_resize and not is_maximized:
		var resize_area = _get_resize_area_at_position(global_pos)
		if resize_area != ResizeMode.NONE:
			_start_resize(resize_area, global_pos)
			return
	
	# Otherwise, handle as potential drag start (but title bar input will override this)
	mouse_pressed = true
	click_start_position = global_pos
	drag_initiated = false

func _handle_mouse_release():
	if is_dragging:
		is_dragging = false
		drag_initiated = false
	
	if is_resizing:
		_end_resize()
	
	mouse_pressed = false

func _handle_mouse_motion(motion_event: InputEventMouseMotion):
	if is_resizing:
		_handle_resize_motion(motion_event.global_position)
	# Dragging motion is handled in the title bar input handler
	
func _get_resize_area_at_position(global_pos: Vector2) -> ResizeMode:
	"""Check if global position is over a resize area"""
	var local_pos = global_pos - global_position
	
	# Check if mouse is within resize borders
	var in_left = local_pos.x <= resize_border_width
	var in_right = local_pos.x >= size.x - resize_border_width
	var in_top = local_pos.y <= resize_border_width
	var in_bottom = local_pos.y >= size.y - resize_border_width
	
	# Check corners first (they take priority)
	if in_top and in_left and local_pos.x <= resize_corner_size and local_pos.y <= resize_corner_size:
		return ResizeMode.TOP_LEFT
	elif in_top and in_right and local_pos.x >= size.x - resize_corner_size and local_pos.y <= resize_corner_size:
		return ResizeMode.TOP_RIGHT
	elif in_bottom and in_left and local_pos.x <= resize_corner_size and local_pos.y >= size.y - resize_corner_size:
		return ResizeMode.BOTTOM_LEFT
	elif in_bottom and in_right and local_pos.x >= size.x - resize_corner_size and local_pos.y >= size.y - resize_corner_size:
		return ResizeMode.BOTTOM_RIGHT
	
	# Check edges - but exclude corner areas
	elif in_left and not (local_pos.y <= resize_corner_size or local_pos.y >= size.y - resize_corner_size):
		return ResizeMode.LEFT
	elif in_right and not (local_pos.y <= resize_corner_size or local_pos.y >= size.y - resize_corner_size):
		return ResizeMode.RIGHT
	elif in_top and not (local_pos.x <= resize_corner_size or local_pos.x >= size.x - resize_corner_size):
		return ResizeMode.TOP
	elif in_bottom and not (local_pos.x <= resize_corner_size or local_pos.x >= size.x - resize_corner_size):
		return ResizeMode.BOTTOM
	
	return ResizeMode.NONE

func _is_point_in_title_bar(global_pos: Vector2) -> bool:
	if not title_bar:
		return false
	
	# Convert to title bar's local coordinate space
	var title_bar_global_rect = Rect2(title_bar.global_position, title_bar.size)
	return title_bar_global_rect.has_point(global_pos)

func _setup_window_ui():
	# Main container
	main_container = Control.new()
	main_container.name = "MainContainer"
	main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(main_container)
	
	# Background panel
	background_panel = Panel.new()
	background_panel.name = "BackgroundPanel"
	background_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_container.add_child(background_panel)
	
	# Style background
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = background_color
	bg_style.border_width_left = border_width
	bg_style.border_width_right = border_width
	bg_style.border_width_top = border_width
	bg_style.border_width_bottom = border_width
	bg_style.border_color = border_color
	background_panel.add_theme_stylebox_override("panel", bg_style)
	
	# Title bar
	title_bar = Panel.new()
	title_bar.name = "TitleBar"
	title_bar.anchor_left = 0.0
	title_bar.anchor_top = 0.0
	title_bar.anchor_right = 1.0
	title_bar.anchor_bottom = 0.0
	title_bar.offset_bottom = title_bar_height
	title_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	main_container.add_child(title_bar)
	
	title_bar.gui_input.connect(_on_title_bar_input)
	
	# Style title bar - match original styling
	var title_style = StyleBoxFlat.new()
	title_style.bg_color = title_bar_color
	title_bar.add_theme_stylebox_override("panel", title_style)
	
	# Title label - match original positioning
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = window_title
	title_label.anchor_left = 0.0
	title_label.anchor_top = 0.0
	title_label.anchor_right = 1.0
	title_label.anchor_bottom = 1.0
	title_label.offset_left = 10  # Match original offset
	title_label.offset_right = -100  # Leave space for buttons
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(title_label)
	
	# Window buttons
	_setup_window_buttons()
	
	# Content area
	content_area = Control.new()
	content_area.name = "ContentArea"
	content_area.anchor_left = 0.0
	content_area.anchor_top = 0.0
	content_area.anchor_right = 1.0
	content_area.anchor_bottom = 1.0
	content_area.offset_left = border_width
	content_area.offset_top = title_bar_height + border_width
	content_area.offset_right = -border_width
	content_area.offset_bottom = -border_width
	content_area.mouse_filter = Control.MOUSE_FILTER_PASS
	main_container.add_child(content_area)

func _setup_window_buttons():
	var button_size = Vector2(title_bar_height - 8, title_bar_height - 8)  # Leave more margin
	var button_margin = 4.0
	var current_x = -button_margin
	
	# Close button
	if can_close:
		close_button = Button.new()
		close_button.name = "CloseButton"
		close_button.text = "×"
		close_button.size = button_size
		close_button.anchor_left = 1.0
		close_button.anchor_top = 0.0
		close_button.anchor_right = 1.0
		close_button.anchor_bottom = 0.0
		close_button.offset_left = current_x - button_size.x
		close_button.offset_top = (title_bar_height - button_size.y) / 2
		close_button.offset_right = current_x
		close_button.offset_bottom = (title_bar_height - button_size.y) / 2 + button_size.y
		close_button.flat = true
		close_button.pressed.connect(_on_close_pressed)
		title_bar.add_child(close_button)
		current_x -= button_size.x + button_margin
	
	# Maximize button
	if can_maximize:
		maximize_button = Button.new()
		maximize_button.name = "MaximizeButton"
		maximize_button.text = "□"
		maximize_button.size = button_size
		maximize_button.anchor_left = 1.0
		maximize_button.anchor_top = 0.0
		maximize_button.anchor_right = 1.0
		maximize_button.anchor_bottom = 0.0
		maximize_button.offset_left = current_x - button_size.x
		maximize_button.offset_top = (title_bar_height - button_size.y) / 2
		maximize_button.offset_right = current_x
		maximize_button.offset_bottom = (title_bar_height - button_size.y) / 2 + button_size.y
		maximize_button.flat = true
		maximize_button.pressed.connect(_on_maximize_pressed)
		title_bar.add_child(maximize_button)
		current_x -= button_size.x + button_margin
	
	# Minimize button
	if can_minimize:
		minimize_button = Button.new()
		minimize_button.name = "MinimizeButton"
		minimize_button.text = "−"
		minimize_button.size = button_size
		minimize_button.anchor_left = 1.0
		minimize_button.anchor_top = 0.0
		minimize_button.anchor_right = 1.0
		minimize_button.anchor_bottom = 0.0
		minimize_button.offset_left = current_x - button_size.x
		minimize_button.offset_top = (title_bar_height - button_size.y) / 2
		minimize_button.offset_right = current_x
		minimize_button.offset_bottom = (title_bar_height - button_size.y) / 2 + button_size.y
		minimize_button.flat = true
		minimize_button.pressed.connect(_on_minimize_pressed)
		title_bar.add_child(minimize_button)
		current_x -= button_size.x + button_margin
	
	# Options button (leftmost)
	options_button = Button.new()
	options_button.name = "OptionsButton"
	options_button.text = "⋯"
	options_button.size = button_size
	options_button.anchor_left = 1.0
	options_button.anchor_top = 0.0
	options_button.anchor_right = 1.0
	options_button.anchor_bottom = 0.0
	options_button.offset_left = current_x - button_size.x
	options_button.offset_top = (title_bar_height - button_size.y) / 2
	options_button.offset_right = current_x
	options_button.offset_bottom = (title_bar_height - button_size.y) / 2 + button_size.y
	options_button.flat = true
	options_button.pressed.connect(_on_options_pressed)
	title_bar.add_child(options_button)

func _setup_resize_overlay():
	if not can_resize:
		return
	
	resize_overlay = Control.new()
	resize_overlay.name = "ResizeOverlay"
	resize_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resize_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resize_overlay.z_index = 200
	main_container.add_child(resize_overlay)
	
	# Create resize areas
	_create_resize_areas()
	
	# Create visual border indicators
	_create_resize_border_visuals()

func _create_resize_areas():
	resize_areas.clear()
	
	# Create EDGES first
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
	
	# Create CORNERS last (so they have higher priority in mouse detection)
	
	# Top-left corner
	var tl_corner = _create_resize_area("TopLeftCorner", ResizeMode.TOP_LEFT)
	tl_corner.anchor_left = 0.0
	tl_corner.anchor_right = 0.0
	tl_corner.anchor_top = 0.0
	tl_corner.anchor_bottom = 0.0
	tl_corner.offset_right = resize_corner_size
	tl_corner.offset_bottom = resize_corner_size
	
	# Top-right corner
	var tr_corner = _create_resize_area("TopRightCorner", ResizeMode.TOP_RIGHT)
	tr_corner.anchor_left = 1.0
	tr_corner.anchor_right = 1.0
	tr_corner.anchor_top = 0.0
	tr_corner.anchor_bottom = 0.0
	tr_corner.offset_left = -resize_corner_size
	tr_corner.offset_bottom = resize_corner_size
	
	# Bottom-left corner
	var bl_corner = _create_resize_area("BottomLeftCorner", ResizeMode.BOTTOM_LEFT)
	bl_corner.anchor_left = 0.0
	bl_corner.anchor_right = 0.0
	bl_corner.anchor_top = 1.0
	bl_corner.anchor_bottom = 1.0
	bl_corner.offset_right = resize_corner_size
	bl_corner.offset_top = -resize_corner_size
	
	# Bottom-right corner
	var br_corner = _create_resize_area("BottomRightCorner", ResizeMode.BOTTOM_RIGHT)
	br_corner.anchor_left = 1.0
	br_corner.anchor_right = 1.0
	br_corner.anchor_top = 1.0
	br_corner.anchor_bottom = 1.0
	br_corner.offset_left = -resize_corner_size
	br_corner.offset_top = -resize_corner_size
	
func _create_resize_area(area_name: String, mode: ResizeMode) -> Control:
	var area = Control.new()
	area.name = area_name
	area.mouse_filter = Control.MOUSE_FILTER_PASS
	area.set_meta("resize_mode", mode)
	
	# Connect signals for mouse enter/exit (for cursor and glow)
	area.mouse_entered.connect(_on_resize_area_entered.bind(mode))
	area.mouse_exited.connect(_on_resize_area_exited.bind(mode))
	area.gui_input.connect(_on_resize_area_input.bind(area))
	
	resize_overlay.add_child(area)
	resize_areas.append(area)
	
	return area
	
func _create_resize_border_visuals():
	border_lines.clear()
	corner_indicators.clear()
	
	# Create visual container
	resize_border_visual = Control.new()
	resize_border_visual.name = "ResizeBorderVisual"
	resize_border_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resize_border_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resize_border_visual.z_index = 199  # Below the resize areas
	main_container.add_child(resize_border_visual)
	
	# Left border
	var left_line = ColorRect.new()
	left_line.name = "LeftBorder"
	left_line.color = Color(0.5, 0.8, 1.0, 0.0)  # Start invisible
	left_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_line.anchor_top = 0.0
	left_line.anchor_bottom = 1.0
	left_line.anchor_left = 0.0
	left_line.anchor_right = 0.0
	left_line.offset_right = 2
	resize_border_visual.add_child(left_line)
	border_lines.append(left_line)
	
	# Right border
	var right_line = ColorRect.new()
	right_line.name = "RightBorder"
	right_line.color = Color(0.5, 0.8, 1.0, 0.0)  # Start invisible
	right_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_line.anchor_top = 0.0
	right_line.anchor_bottom = 1.0
	right_line.anchor_left = 1.0
	right_line.anchor_right = 1.0
	right_line.offset_left = -2
	resize_border_visual.add_child(right_line)
	border_lines.append(right_line)
	
	# Top border
	var top_line = ColorRect.new()
	top_line.name = "TopBorder"
	top_line.color = Color(0.5, 0.8, 1.0, 0.0)  # Start invisible
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_line.anchor_left = 0.0
	top_line.anchor_right = 1.0
	top_line.anchor_top = 0.0
	top_line.anchor_bottom = 0.0
	top_line.offset_bottom = 2
	resize_border_visual.add_child(top_line)
	border_lines.append(top_line)
	
	# Bottom border
	var bottom_line = ColorRect.new()
	bottom_line.name = "BottomBorder"
	bottom_line.color = Color(0.5, 0.8, 1.0, 0.0)  # Start invisible
	bottom_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_line.anchor_left = 0.0
	bottom_line.anchor_right = 1.0
	bottom_line.anchor_top = 1.0
	bottom_line.anchor_bottom = 1.0
	bottom_line.offset_top = -2
	resize_border_visual.add_child(bottom_line)
	border_lines.append(bottom_line)
	
	# Corner indicators
	_create_corner_indicators()

func _create_corner_indicators():
	var corner_color = Color(0.5, 0.8, 1.0, 0.0)  # Start invisible
	
	# Top-left corner
	var tl_corner = ColorRect.new()
	tl_corner.name = "TopLeftCorner"
	tl_corner.color = corner_color
	tl_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl_corner.anchor_left = 0.0
	tl_corner.anchor_right = 0.0
	tl_corner.anchor_top = 0.0
	tl_corner.anchor_bottom = 0.0
	tl_corner.offset_right = resize_corner_size
	tl_corner.offset_bottom = resize_corner_size
	resize_border_visual.add_child(tl_corner)
	corner_indicators.append(tl_corner)
	
	# Top-right corner
	var tr_corner = ColorRect.new()
	tr_corner.name = "TopRightCorner"
	tr_corner.color = corner_color
	tr_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr_corner.anchor_left = 1.0
	tr_corner.anchor_right = 1.0
	tr_corner.anchor_top = 0.0
	tr_corner.anchor_bottom = 0.0
	tr_corner.offset_left = -resize_corner_size
	tr_corner.offset_bottom = resize_corner_size
	resize_border_visual.add_child(tr_corner)
	corner_indicators.append(tr_corner)
	
	# Bottom-left corner
	var bl_corner = ColorRect.new()
	bl_corner.name = "BottomLeftCorner"
	bl_corner.color = corner_color
	bl_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bl_corner.anchor_left = 0.0
	bl_corner.anchor_right = 0.0
	bl_corner.anchor_top = 1.0
	bl_corner.anchor_bottom = 1.0
	bl_corner.offset_right = resize_corner_size
	bl_corner.offset_top = -resize_corner_size
	resize_border_visual.add_child(bl_corner)
	corner_indicators.append(bl_corner)
	
	# Bottom-right corner
	var br_corner = ColorRect.new()
	br_corner.name = "BottomRightCorner"
	br_corner.color = corner_color
	br_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	br_corner.anchor_left = 1.0
	br_corner.anchor_right = 1.0
	br_corner.anchor_top = 1.0
	br_corner.anchor_bottom = 1.0
	br_corner.offset_left = -resize_corner_size
	br_corner.offset_top = -resize_corner_size
	resize_border_visual.add_child(br_corner)
	corner_indicators.append(br_corner)

func _setup_resize_area_geometry(area: Control, mode: ResizeMode):
	var border = resize_border_width
	var corner = resize_corner_size
	
	match mode:
		ResizeMode.LEFT:
			area.anchor_left = 0.0
			area.anchor_top = 0.0
			area.anchor_right = 0.0
			area.anchor_bottom = 1.0
			area.offset_right = border
			area.offset_top = corner
			area.offset_bottom = -corner
		ResizeMode.RIGHT:
			area.anchor_left = 1.0
			area.anchor_top = 0.0
			area.anchor_right = 1.0
			area.anchor_bottom = 1.0
			area.offset_left = -border
			area.offset_top = corner
			area.offset_bottom = -corner
		ResizeMode.TOP:
			area.anchor_left = 0.0
			area.anchor_top = 0.0
			area.anchor_right = 1.0
			area.anchor_bottom = 0.0
			area.offset_left = corner
			area.offset_right = -corner
			area.offset_bottom = border
		ResizeMode.BOTTOM:
			area.anchor_left = 0.0
			area.anchor_top = 1.0
			area.anchor_right = 1.0
			area.anchor_bottom = 1.0
			area.offset_left = corner
			area.offset_right = -corner
			area.offset_top = -border
		ResizeMode.TOP_LEFT:
			area.anchor_left = 0.0
			area.anchor_top = 0.0
			area.anchor_right = 0.0
			area.anchor_bottom = 0.0
			area.offset_right = corner
			area.offset_bottom = corner
		ResizeMode.TOP_RIGHT:
			area.anchor_left = 1.0
			area.anchor_top = 0.0
			area.anchor_right = 1.0
			area.anchor_bottom = 0.0
			area.offset_left = -corner
			area.offset_bottom = corner
		ResizeMode.BOTTOM_LEFT:
			area.anchor_left = 0.0
			area.anchor_top = 1.0
			area.anchor_right = 0.0
			area.anchor_bottom = 1.0
			area.offset_right = corner
			area.offset_top = -corner
		ResizeMode.BOTTOM_RIGHT:
			area.anchor_left = 1.0
			area.anchor_top = 1.0
			area.anchor_right = 1.0
			area.anchor_bottom = 1.0
			area.offset_left = -corner
			area.offset_top = -corner

func _on_resize_area_input(event: InputEvent, source_area: Control):
	var mode = source_area.get_meta("resize_mode") as ResizeMode
	
	if not can_resize or is_locked:
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_start_resize(mode, mouse_event.global_position)
			else:
				_end_resize()

func _on_resize_area_entered(mode: ResizeMode):
	"""Handle mouse entering a resize area"""
	if not can_resize or is_locked or is_maximized or is_dragging:
		return
	
	# Set appropriate cursor
	match mode:
		ResizeMode.LEFT, ResizeMode.RIGHT:
			mouse_default_cursor_shape = Control.CURSOR_HSIZE
		ResizeMode.TOP, ResizeMode.BOTTOM:
			mouse_default_cursor_shape = Control.CURSOR_VSIZE
		ResizeMode.TOP_LEFT, ResizeMode.BOTTOM_RIGHT:
			mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
		ResizeMode.TOP_RIGHT, ResizeMode.BOTTOM_LEFT:
			mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
	
	# Show border glow
	_update_border_visuals(mode)

func _on_resize_area_exited(mode: ResizeMode):
	"""Handle mouse exiting a resize area"""
	if not is_resizing:
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		# Hide all border glows
		_hide_all_border_visuals()
		
func _update_border_visuals(resize_mode: ResizeMode):
	"""Update border glow visuals based on resize mode"""
	# Hide all borders first
	for line in border_lines:
		_animate_border_visibility(line, false)
	for corner in corner_indicators:
		_animate_border_visibility(corner, false)
	
	# Show only the relevant border/corner
	match resize_mode:
		ResizeMode.LEFT:
			if border_lines.size() > 0:
				_animate_border_visibility(border_lines[0], true)  # Left border
		ResizeMode.RIGHT:
			if border_lines.size() > 1:
				_animate_border_visibility(border_lines[1], true)  # Right border
		ResizeMode.TOP:
			if border_lines.size() > 2:
				_animate_border_visibility(border_lines[2], true)  # Top border
		ResizeMode.BOTTOM:
			if border_lines.size() > 3:
				_animate_border_visibility(border_lines[3], true)  # Bottom border
		ResizeMode.TOP_LEFT:
			if corner_indicators.size() > 0:
				_animate_border_visibility(corner_indicators[0], true)  # Top-left corner
		ResizeMode.TOP_RIGHT:
			if corner_indicators.size() > 1:
				_animate_border_visibility(corner_indicators[1], true)  # Top-right corner
		ResizeMode.BOTTOM_LEFT:
			if corner_indicators.size() > 2:
				_animate_border_visibility(corner_indicators[2], true)  # Bottom-left corner
		ResizeMode.BOTTOM_RIGHT:
			if corner_indicators.size() > 3:
				_animate_border_visibility(corner_indicators[3], true)  # Bottom-right corner

func _hide_all_border_visuals():
	"""Hide all border visual indicators"""
	for line in border_lines:
		_animate_border_visibility(line, false)
	for corner in corner_indicators:
		_animate_border_visibility(corner, false)

func _animate_border_visibility(element: ColorRect, show: bool):
	"""Animate border visibility with smooth transition"""
	var current_color = element.color
	var target_alpha = 1.0 if show else 0.0
	var target_color = Color(current_color.r, current_color.g, current_color.b, target_alpha)
	
	var tween = create_tween()
	tween.tween_property(element, "color", target_color, 0.15)

func _start_resize(mode: ResizeMode, mouse_pos: Vector2):
	is_resizing = true
	resize_mode = mode
	resize_start_position = position
	resize_start_size = size
	resize_start_mouse = mouse_pos

func _end_resize():
	if is_resizing:
		is_resizing = false
		resize_mode = ResizeMode.NONE
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _handle_resize_motion(mouse_pos: Vector2):
	if not is_resizing:
		return
	
	var delta = mouse_pos - resize_start_mouse
	var new_position = resize_start_position
	var new_size = resize_start_size
	
	match resize_mode:
		ResizeMode.LEFT:
			new_position.x += delta.x
			new_size.x -= delta.x
		ResizeMode.RIGHT:
			new_size.x += delta.x
		ResizeMode.TOP:
			new_position.y += delta.y
			new_size.y -= delta.y
		ResizeMode.BOTTOM:
			new_size.y += delta.y
		ResizeMode.TOP_LEFT:
			new_position.x += delta.x
			new_position.y += delta.y
			new_size.x -= delta.x
			new_size.y -= delta.y
		ResizeMode.TOP_RIGHT:
			new_position.y += delta.y
			new_size.x += delta.x
			new_size.y -= delta.y
		ResizeMode.BOTTOM_LEFT:
			new_position.x += delta.x
			new_size.x -= delta.x
			new_size.y += delta.y
		ResizeMode.BOTTOM_RIGHT:
			new_size.x += delta.x
			new_size.y += delta.y
	
	# Apply size constraints
	new_size.x = max(min_window_size.x, min(new_size.x, max_window_size.x))
	new_size.y = max(min_window_size.y, min(new_size.y, max_window_size.y))
	
	# Update position and size
	position = new_position
	size = new_size
	
	window_resized.emit(Vector2i(size))

# Button callbacks
func _on_close_pressed():
	_on_window_close_requested()

func _on_minimize_pressed():
	visible = false
	window_minimized.emit()

func _on_maximize_pressed():
	if is_maximized:
		_restore_window()
	else:
		_maximize_window()

func _maximize_window():
	if is_maximized:
		return
	
	# Save current state
	restore_position = position
	restore_size = size
	is_maximized = true
	
	# Get viewport size
	var viewport = get_viewport()
	if viewport:
		var screen_size = viewport.get_visible_rect().size
		position = Vector2.ZERO
		size = screen_size
	
	if maximize_button:
		maximize_button.text = "❐"
	
	window_maximized.emit()

func _restore_window():
	if not is_maximized:
		return
	
	position = restore_position
	size = restore_size
	is_maximized = false
	
	if maximize_button:
		maximize_button.text = "□"
	
	window_restored.emit()

func _on_window_close_requested():
	# Virtual method - override in child classes
	_on_window_closed()
	
	# Default behavior
	visible = false
	window_closed.emit()

func _on_window_closed():
	"""Override this method in child classes for custom close behavior"""
	pass

# Public interface methods
func set_window_title(title: String):
	window_title = title
	if title_label:
		title_label.text = title

func add_content(content_node: Control):
	"""Add content to the window's content area"""
	if content_area:
		content_area.add_child(content_node)

func get_window_locked() -> bool:
	return is_locked

func set_window_locked(locked: bool):
	is_locked = locked

func get_transparency() -> float:
	return modulate.a

func set_transparency(value: float):
	modulate.a = value

func set_resizing_enabled(enabled: bool):
	can_resize = enabled
	if resize_overlay:
		resize_overlay.visible = enabled
	if not enabled and is_resizing:
		_end_resize()

func get_resizing_enabled() -> bool:
	return can_resize
	
func show_window():
	"""Show the window"""
	visible = true

func hide_window():
	"""Hide the window"""
	visible = false

func toggle_window():
	"""Toggle window visibility"""
	visible = !visible
	
func center_on_screen():
	"""Center the window on the screen"""
	var viewport = get_viewport()
	if viewport:
		var screen_size = viewport.get_visible_rect().size
		position = (screen_size - size) / 2

func center_on_parent(parent_control: Control):
	"""Center the window on a parent control"""
	if parent_control:
		var parent_center = parent_control.global_position + parent_control.size / 2
		position = parent_center - size / 2
	else:
		center_on_screen()

# Position and size reset methods
func _reset_window_position():
	"""Reset window to default position"""
	center_on_screen()

func _reset_window_size():
	"""Reset window to default size"""
	size = default_size

# Virtual method for lock visual updates (override in child classes)
func _update_lock_visual():
	"""Update visual indicators for lock state - override in child classes"""
	pass
	
func _on_options_pressed():
	"""Handle options button press - virtual method for child classes to override"""
	_show_default_options_menu()

func _show_default_options_menu():
	"""Show default options menu - can be overridden by child classes"""
	if not options_dropdown:
		_setup_default_options_dropdown()
	
	# Show dropdown at button position
	var button_pos = options_button.get_screen_position()
	var dropdown_pos = Vector2(button_pos.x, button_pos.y + options_button.size.y)
	
	# Only add to scene if it doesn't have a parent
	if not options_dropdown.get_parent():
		get_viewport().add_child(options_dropdown)
	
	# Show the menu
	if options_dropdown.has_method("show_menu"):
		options_dropdown.show_menu(dropdown_pos)

func _setup_default_options_dropdown():
	"""Setup default options dropdown - can be overridden by child classes"""
	options_dropdown = DropDownMenu_Base.new()
	options_dropdown.name = "OptionsDropdown"
	
	# Add basic window options
	_update_default_options_dropdown()
	
	# Connect dropdown signals
	if options_dropdown.has_signal("item_selected"):
		options_dropdown.item_selected.connect(_on_default_options_selected)
	if options_dropdown.has_signal("menu_closed"):
		options_dropdown.menu_closed.connect(_on_default_options_closed)

func _update_default_options_dropdown():
	"""Update default options dropdown"""
	if not options_dropdown:
		return
	
	options_dropdown.clear_items()
	options_dropdown.add_menu_item("transparency", "Window Transparency")
	
	var lock_text = "Unlock Window Position" if is_locked else "Lock Window Position"
	options_dropdown.add_menu_item("lock_window", lock_text)
	
	options_dropdown.add_menu_item("reset_position", "Reset Window Position")
	options_dropdown.add_menu_item("reset_size", "Reset Window Size")

func _on_default_options_selected(item_id: String, _item_data: Dictionary):
	"""Handle default options selection"""
	match item_id:
		"transparency":
			_show_default_transparency_dialog()
		"lock_window":
			set_window_locked(!is_locked)
			_update_default_options_dropdown()
		"reset_position":
			_reset_window_position()
		"reset_size":
			_reset_window_size()

func _on_default_options_closed():
	"""Handle options dropdown close"""
	if options_dropdown and options_dropdown.get_parent():
		options_dropdown.get_parent().remove_child(options_dropdown)

func _show_default_transparency_dialog():
	"""Show default transparency dialog"""
	var dialog = AcceptDialog.new()
	dialog.title = "Window Transparency"
	dialog.size = Vector2i(300, 150)
	
	var vbox = VBoxContainer.new()
	var label = Label.new()
	label.text = "Adjust window transparency:"
	vbox.add_child(label)
	
	var slider = HSlider.new()
	slider.min_value = 0.3
	slider.max_value = 1.0
	slider.step = 0.1
	slider.value = modulate.a
	slider.custom_minimum_size.x = 250
	vbox.add_child(slider)
	
	dialog.add_child(vbox)
	slider.value_changed.connect(func(value): modulate.a = value)
	
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())

# Virtual methods for child classes to override
func _setup_options_dropdown():
	"""Virtual method - override in child classes for custom options"""
	_setup_default_options_dropdown()
	
func _on_title_bar_input(event: InputEvent):
	"""Handle title bar input events"""
	if is_locked:
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			# Handle double-click first, before any other logic
			if mouse_event.double_click and can_maximize:
				# Double-click to maximize/restore
				if is_maximized:
					_restore_window()
				else:
					_maximize_window()
				
				# Reset all drag states when double-clicking
				mouse_pressed = false
				is_dragging = false
				drag_initiated = false
				get_viewport().set_input_as_handled()
				return  # Exit early to prevent other logic
			
			if mouse_event.pressed:
				# Store initial click position and state for dragging
				mouse_pressed = true
				is_dragging = false
				drag_initiated = false
				click_start_position = mouse_event.global_position
				# Store the offset from mouse to window position
				drag_start_position = mouse_event.global_position - global_position
				get_viewport().set_input_as_handled()
			else:
				# Handle mouse release - reset all drag states
				mouse_pressed = false
				if is_dragging:
					is_dragging = false
					Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				drag_initiated = false
	
	elif event is InputEventMouseMotion and mouse_pressed and not drag_initiated and not is_locked and can_drag:
		# Declare motion_event here for this scope
		var motion_event = event as InputEventMouseMotion
		
		# Check if we should start dragging
		var current_mouse_pos = motion_event.global_position
		var distance = click_start_position.distance_to(current_mouse_pos)
		
		if distance > drag_threshold:
			# Start actual dragging
			drag_initiated = true
			is_dragging = true
			
			# If window is maximized, restore it and adjust position
			if is_maximized:
				# Calculate relative position within the maximized window
				var mouse_relative_x = click_start_position.x / size.x
				
				# Restore the window first
				_restore_window()
				
				# Position the restored window so the mouse stays over the title bar
				var new_x = click_start_position.x - (restore_size.x * mouse_relative_x)
				var new_y = click_start_position.y - (title_bar_height / 2)
				
				# Clamp to screen bounds
				var viewport_size = get_viewport().get_visible_rect().size
				new_x = clampf(new_x, 0, viewport_size.x - restore_size.x)
				new_y = clampf(new_y, 0, viewport_size.y - restore_size.y)
				
				position = Vector2(new_x, new_y)
				
				# Update drag offset for the new window size
				drag_start_position = current_mouse_pos - position
	
	elif event is InputEventMouseMotion and is_dragging and drag_initiated and not is_locked and can_drag:
		# Declare motion_event here for this scope
		var motion_event = event as InputEventMouseMotion
		
		# Handle actual dragging (only if not maximized)
		if not is_maximized:
			# Calculate new position: mouse position minus the original offset
			var new_position = motion_event.global_position - drag_start_position
			
			# Optional: Clamp to screen bounds
			var viewport_size = get_viewport().get_visible_rect().size
			new_position.x = clampf(new_position.x, 0, viewport_size.x - size.x)
			new_position.y = clampf(new_position.y, 0, viewport_size.y - size.y)
			
			position = new_position
			window_moved.emit(Vector2i(position))
			
func _enable_resize_visuals():
	"""Enable resize cursors and edge glows"""
	if not can_resize or is_locked or is_maximized:
		return
	
	# Re-enable mouse detection on resize areas
	if resize_overlay:
		resize_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Keep overlay itself as ignore
	
	for area in resize_areas:
		if area:
			area.mouse_filter = Control.MOUSE_FILTER_PASS
			
func _disable_resize_visuals():
	"""Disable all resize cursors and edge glows"""
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_hide_all_border_visuals()
	
	# Disable mouse detection on resize areas
	if resize_overlay:
		resize_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	for area in resize_areas:
		if area:
			area.mouse_filter = Control.MOUSE_FILTER_IGNORE
