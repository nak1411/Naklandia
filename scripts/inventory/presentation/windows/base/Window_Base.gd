# Window_Base.gd - Base class for all custom windows using CanvasLayer system
class_name Window_Base
extends Control

# Signals
signal window_closed
signal window_minimized
signal window_maximized
signal window_restored
signal window_resized(new_size: Vector2i)
signal window_moved(new_position: Vector2i)
signal window_property_changed(property: String, value)

enum BloomState { NONE, SUBTLE, ACTIVE, ALERT, CRITICAL }
enum ResizeMode { NONE, LEFT, RIGHT, TOP, BOTTOM, TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }

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

var ui_manager: UIManager = null
var snapping_manager: WindowSnappingManager
var options_dropdown: DropDownMenu_Base

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

var edge_bloom_material: WindowEdgeBloomMaterial
var edge_bloom_overlay: Control
var edge_bloom_tween: Tween
var current_bloom_state: BloomState = BloomState.NONE
var last_known_size: Vector2

# Resize overlay
var resize_overlay: Control
var resize_areas: Array[Control] = []

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

# Window styling
var title_bar_height: float = 50.0
var border_width: float = 1.0
var title_bar_color: Color = Color(0.1, 0.1, 0.1, 1.0)
var border_color: Color = Color(0.2, 0.2, 0.2, 1.0)
var background_color: Color = Color(0.15, 0.15, 0.15, 1.0)
var _transparency_value: float = 1.0
var _was_resizing: bool = false
var _is_transparency_locked: bool = false


func _init():
	# Set up as a window-like control
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = default_size
	position = Vector2(200, 100)
	visible = false

	# Enable input handling
	mouse_filter = Control.MOUSE_FILTER_PASS
	var font = SystemFont.new()
	font.msdf_pixel_range = 8


func _ready():
	_setup_window_ui()
	_setup_resize_overlay()
	_setup_edge_bloom()

	last_known_size = size
	window_resized.connect(_on_window_resized)

	set_process_unhandled_input(true)

	# Call virtual method for child classes to override
	call_deferred("_setup_window_content")
	# Find and connect to UIManager
	_connect_to_ui_manager()

	mouse_entered.connect(_on_mouse_entered)
	gui_input.connect(_on_window_gui_input)

	snapping_manager = get_node("/root/WindowSnappingManager") if has_node("/root/WindowSnappingManager") else null


func _process(_delta):
	if edge_bloom_overlay and size != last_known_size:
		_update_edge_bloom_size()
		last_known_size = size


func _connect_to_ui_manager():
	"""Connect to UIManager for focus management"""
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	if ui_managers.size() > 0:
		ui_manager = ui_managers[0]


func _unhandled_input(event: InputEvent):
	"""Handle unhandled input - catch resize motion that other systems missed AND window focusing"""

	# Handle window focusing on any unhandled left click
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Check if the click is within this window's bounds
		var local_pos = global_position
		var window_rect = Rect2(local_pos, size)

		if window_rect.has_point(event.global_position):
			# Don't interfere with resize operations
			var resize_mode = _get_resize_area_at_position(event.global_position)
			if resize_mode != ResizeMode.NONE:
				return

			# Focus the window
			_bring_to_front()
			# Don't set as handled - let other systems continue processing

	# Handle mouse release globally during ANY operation (resize OR drag)
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_resizing:
			_end_resize()
			get_viewport().set_input_as_handled()
		elif is_dragging:
			is_dragging = false
			drag_initiated = false
			mouse_pressed = false
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			# END DRAG - notify snapping manager
			if snapping_manager:
				snapping_manager.end_window_drag(self)
			get_viewport().set_input_as_handled()

	# Existing resize handling
	if not is_resizing:
		return

	if event is InputEventMouseMotion:
		_handle_resize_motion(event.global_position)
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent):
	"""Handle input events for window interaction"""

	# CRITICAL: Check for resize FIRST
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			# Check if we're over a resize area FIRST
			var resize_mode = _get_resize_area_at_position(mouse_event.global_position)

			if resize_mode != ResizeMode.NONE:
				if mouse_event.pressed:
					_start_resize(resize_mode, mouse_event.global_position)
					get_viewport().set_input_as_handled()
					return  # Stop processing
				if is_resizing:
					_end_resize()
					get_viewport().set_input_as_handled()
					return  # Stop processing

	# Handle resize motion
	if is_resizing and event is InputEventMouseMotion:
		_handle_resize_motion(event.global_position)
		get_viewport().set_input_as_handled()
		return

	# Update edge bloom based on current mouse position when not resizing
	if not is_resizing and event is InputEventMouseMotion:
		var resize_mode = _get_resize_area_at_position(event.global_position)
		if resize_mode != ResizeMode.NONE and not is_locked and not is_maximized:
			_show_edge_bloom(resize_mode)
			_set_resize_cursor(resize_mode)
		else:
			_hide_edge_bloom()
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _on_window_gui_input(event: InputEvent):
	"""Handle any input on the window"""
	if event is InputEventMouseButton and event.pressed:
		_bring_to_front()


func _handle_resize_input(event: InputEvent) -> bool:
	"""Handle resize input directly - returns true if event was consumed"""
	if not can_resize or is_locked or is_maximized:
		return false

	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var resize_mode = _get_resize_area_at_position(mouse_event.global_position)

			if resize_mode != ResizeMode.NONE:
				if mouse_event.pressed:
					_start_resize(resize_mode, mouse_event.global_position)
					get_viewport().set_input_as_handled()
					return true
				if is_resizing:
					_end_resize()
					get_viewport().set_input_as_handled()
					return true

	elif event is InputEventMouseMotion:
		if is_resizing:
			_handle_resize_motion(event.global_position)
			get_viewport().set_input_as_handled()
			return true

		# Update cursor for hover
		var resize_mode = _get_resize_area_at_position(event.global_position)
		if resize_mode != ResizeMode.NONE:
			_set_resize_cursor(resize_mode)
		else:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	return false


func _set_resize_cursor(mode: ResizeMode):
	"""Set cursor for resize mode"""
	match mode:
		ResizeMode.LEFT, ResizeMode.RIGHT:
			Input.set_default_cursor_shape(Input.CURSOR_HSIZE)
		ResizeMode.TOP, ResizeMode.BOTTOM:
			Input.set_default_cursor_shape(Input.CURSOR_VSIZE)
		ResizeMode.TOP_LEFT, ResizeMode.BOTTOM_RIGHT:
			Input.set_default_cursor_shape(Input.CURSOR_FDIAGSIZE)
		ResizeMode.TOP_RIGHT, ResizeMode.BOTTOM_LEFT:
			Input.set_default_cursor_shape(Input.CURSOR_BDIAGSIZE)


func _handle_mouse_press(global_pos: Vector2):
	# FOCUS HANDLING - Add this first
	_bring_to_front()

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
	if not can_resize or is_locked or is_maximized:
		return ResizeMode.NONE

	var local_pos = global_pos - global_position

	# Bounds check
	if local_pos.x < 0 or local_pos.y < 0 or local_pos.x > size.x or local_pos.y > size.y:
		return ResizeMode.NONE

	var border = resize_border_width
	var corner = resize_corner_size

	var in_left = local_pos.x <= border
	var in_right = local_pos.x >= size.x - border
	var in_top = local_pos.y <= border
	var in_bottom = local_pos.y >= size.y - border

	# Check corners first (higher priority)
	if in_top and in_left:
		return ResizeMode.TOP_LEFT
	if in_top and in_right:
		return ResizeMode.TOP_RIGHT
	if in_bottom and in_left:
		return ResizeMode.BOTTOM_LEFT
	if in_bottom and in_right:
		return ResizeMode.BOTTOM_RIGHT
	# Check edges
	if in_left:
		return ResizeMode.LEFT
	if in_right:
		return ResizeMode.RIGHT
	if in_top:
		return ResizeMode.TOP
	if in_bottom:
		return ResizeMode.BOTTOM

	return ResizeMode.NONE


func _setup_window_ui():
	# Main container
	main_container = Control.new()
	main_container.name = "MainContainer"
	main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_container.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(main_container)

	# Connect input to main container for full-window focus
	main_container.gui_input.connect(_on_container_input)

	# Background panel
	background_panel = Panel.new()
	background_panel.name = "BackgroundPanel"
	background_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_panel.mouse_filter = Control.MOUSE_FILTER_PASS  # Allow clicks to pass through to main_container
	main_container.add_child(background_panel)

	# Style background
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = background_color
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
	var button_size = Vector2(title_bar_height - 24, title_bar_height - 24)  # Now 42x42 buttons
	var button_margin = 0  # Reduced from 2.0 to 0.0 for tighter spacing
	var button_offset = -10.0  # Move buttons 15 pixels to the left
	var current_x = button_offset - button_margin  # Start position with offset
	var icon_size = 16  # Increase icon size for larger buttons

	# Close button
	if can_close:
		var button_left = current_x - button_size.x
		var button_top = (title_bar_height - button_size.y) / 2
		var button_right = current_x
		var button_bottom = button_top + button_size.y

		close_button = Button.new()
		close_button.name = "CloseButton"
		close_button.icon = _create_close_icon(icon_size - 3)
		close_button.flat = true
		close_button.size = button_size
		close_button.anchor_left = 1.0
		close_button.anchor_top = 0.0
		close_button.anchor_right = 1.0
		close_button.anchor_bottom = 0.0
		close_button.offset_left = button_left
		close_button.offset_top = button_top
		close_button.offset_right = button_right
		close_button.offset_bottom = button_bottom
		close_button.focus_mode = Control.FOCUS_NONE
		close_button.pressed.connect(_on_close_pressed)
		_style_title_bar_button(close_button, "close")
		title_bar.add_child(close_button)

		current_x -= button_size.x + button_margin

	# Maximize button
	if can_maximize:
		var button_left = current_x - button_size.x
		var button_top = (title_bar_height - button_size.y) / 2
		var button_right = current_x
		var button_bottom = button_top + button_size.y

		maximize_button = Button.new()
		maximize_button.name = "MaximizeButton"
		maximize_button.icon = _create_maximize_icon(icon_size)
		maximize_button.flat = true
		maximize_button.size = button_size
		maximize_button.anchor_left = 1.0
		maximize_button.anchor_top = 0.0
		maximize_button.anchor_right = 1.0
		maximize_button.anchor_bottom = 0.0
		maximize_button.offset_left = button_left
		maximize_button.offset_top = button_top - 1
		maximize_button.offset_right = button_right
		maximize_button.offset_bottom = button_bottom
		maximize_button.focus_mode = Control.FOCUS_NONE
		maximize_button.pressed.connect(_on_maximize_pressed)
		_style_title_bar_button(maximize_button)
		title_bar.add_child(maximize_button)

		current_x -= button_size.x + button_margin

	# Minimize button
	if can_minimize:
		var button_left = current_x - button_size.x
		var button_top = (title_bar_height - button_size.y) / 2
		var button_right = current_x
		var button_bottom = button_top + button_size.y

		minimize_button = Button.new()
		minimize_button.name = "MinimizeButton"
		#minimize_button.icon = _create_minimize_icon(icon_size)
		minimize_button.flat = true
		minimize_button.size = button_size
		minimize_button.anchor_left = 1.0
		minimize_button.anchor_top = 0.0
		minimize_button.anchor_right = 1.0
		minimize_button.anchor_bottom = 0.0
		minimize_button.offset_left = button_left
		minimize_button.offset_top = button_top
		minimize_button.offset_right = button_right
		minimize_button.offset_bottom = button_bottom
		minimize_button.focus_mode = Control.FOCUS_NONE
		minimize_button.pressed.connect(_on_minimize_pressed)
		_style_title_bar_button(minimize_button)
		title_bar.add_child(minimize_button)

		current_x -= button_size.x + button_margin

	# Options button (leftmost)
	var button_left = current_x - button_size.x
	var button_top = (title_bar_height - button_size.y) / 2
	var button_right = current_x
	var button_bottom = button_top + button_size.y

	options_button = Button.new()
	options_button.name = "OptionsButton"
	options_button.icon = _create_options_icon(icon_size)
	options_button.flat = true
	options_button.size = button_size
	options_button.anchor_left = 1.0
	options_button.anchor_top = 0.0
	options_button.anchor_right = 1.0
	options_button.anchor_bottom = 0.0
	options_button.offset_left = button_left + 4
	options_button.offset_top = button_top - 1
	options_button.offset_right = button_right
	options_button.offset_bottom = button_bottom
	options_button.focus_mode = Control.FOCUS_NONE
	options_button.pressed.connect(_on_options_pressed)
	_style_title_bar_button(options_button)
	title_bar.add_child(options_button)


func _style_title_bar_button(button: Button, button_type: String = "default"):
	"""Style title bar buttons with bright icon glow on hover"""
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true

	# Normal state - dimmed icons
	button.add_theme_color_override("icon_normal_color", Color(0.6, 0.6, 0.6, 1.0))

	# Hover state - bright glowing icons
	if button_type == "close":
		button.add_theme_color_override("icon_hover_color", Color(1.5, 0.8, 0.8, 1.0))  # Bright red
	else:
		button.add_theme_color_override("icon_hover_color", Color(0.8, 1.2, 1.6, 1.0))  # Bright blue-white

	# Pressed state
	button.add_theme_color_override("icon_pressed_color", Color(1.0, 1.0, 1.0, 1.0))


func _on_container_input(event: InputEvent):
	"""Handle input on the main container for full-window focus"""
	if event is InputEventMouseButton and event.pressed:
		# Don't interfere with resize operations
		var resize_mode = _get_resize_area_at_position(event.global_position)
		if resize_mode != ResizeMode.NONE:
			return

		# Focus the window for any other click
		_bring_to_front()


func setup_child_focus_handlers():
	"""Setup focus handlers on child controls after they're created"""
	call_deferred("_setup_child_focus_handlers_deferred")


func _setup_child_focus_handlers_deferred():
	"""Setup focus handlers on all interactive child controls"""
	_add_focus_to_nodes_by_name(
		[
			"InventoryGrid",
			"VirtualContent",
			"MassInfoBar",
			"InventoryHeader",
			"ScrollContainer",
			"VScrollBar",
			"HScrollBar",
			"Button",
			"InventorySlot",
			"ContainerList",
			"Search",
		]
	)


func _add_focus_to_nodes_by_name(node_names: Array):
	"""Add focus handlers to nodes with specific names"""
	for node_name in node_names:
		var nodes = _find_nodes_by_name(self, node_name)
		for node in nodes:
			if node is Control:
				var control = node as Control
				if not control.gui_input.is_connected(_on_child_focus_input):
					control.gui_input.connect(_on_child_focus_input)


func _find_nodes_by_name(root: Node, target_name: String) -> Array:
	"""Recursively find all nodes with a specific name"""
	var found_nodes = []

	if root.name.contains(target_name):
		found_nodes.append(root)

	for child in root.get_children():
		found_nodes.append_array(_find_nodes_by_name(child, target_name))

	return found_nodes


func _on_child_focus_input(event: InputEvent):
	"""Handle focus input from child controls"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Don't interfere with resize operations
		var resize_mode = _get_resize_area_at_position(event.global_position)
		if resize_mode != ResizeMode.NONE:
			return

		# Focus the window
		_bring_to_front()


func _create_backbuffer_bloom_effect(button_size: Vector2, button_type: String) -> Control:
	"""Create bloom effect using multiple blurred copies"""
	var bloom_container = Control.new()
	bloom_container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Critical
	bloom_container.z_index = 100  # Relative to its parent's z-index

	# Create the icon for blooming
	var icon_texture = null
	var icon_size = 8  # Larger icons for 50px title bar
	match button_type:
		"close":
			icon_texture = _create_close_icon(icon_size)
		"maximize":
			icon_texture = _create_maximize_icon(icon_size)
		"options":
			icon_texture = _create_options_icon(icon_size)
		_:
			icon_texture = _create_options_icon(icon_size)

	# Adjust bloom for larger buttons
	var bloom_layers = [{"offset": 1, "alpha": 0.4, "scale": 1.0}, {"offset": 2, "alpha": 0.25, "scale": 1.1}, {"offset": 3, "alpha": 0.15, "scale": 1.2}, {"offset": 4, "alpha": 0.08, "scale": 1.3}]

	var bloom_color: Color
	if button_type == "close":
		bloom_color = Color(1.0, 0.3, 0.3, 1.0)
	else:
		bloom_color = Color(0.4, 0.7, 1.0, 1.0)

	# Calculate center of button for proper bloom positioning
	var button_center = button_size / 2

	# Create each bloom layer
	for layer in bloom_layers:
		var blur_container = Control.new()
		blur_container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Critical
		# Center the bloom at the button center (adjust for larger icon)
		blur_container.position = button_center - Vector2(14, 8)  # Half of 16px icon

		# Create multiple offset copies for blur effect
		var offsets = []
		var offset_range = layer.offset
		for x in range(-offset_range, offset_range + 1):
			for y in range(-offset_range, offset_range + 1):
				if x != 0 or y != 0:  # Skip center
					offsets.append(Vector2(x, y))

		# Add the blurred copies
		for offset in offsets:
			var blur_icon = TextureRect.new()
			blur_icon.texture = icon_texture
			blur_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			blur_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			blur_icon.position = offset * 0.5  # Small offset for blur
			blur_icon.size = Vector2(12, 12) * layer.scale  # Larger icon size
			blur_icon.modulate = Color(bloom_color.r, bloom_color.g, bloom_color.b, layer.alpha * 0.6)
			blur_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Critical
			blur_container.add_child(blur_icon)

		bloom_container.add_child(blur_container)

	return bloom_container


func _create_glow_icon_layer(button: Button, button_type: String) -> Control:
	"""Create a glow layer behind the icon using multiple TextureRect copies"""
	var glow_container = Control.new()
	glow_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow_container.z_index = 100
	glow_container.visible = false

	# Position exactly behind the button
	glow_container.anchor_left = button.anchor_left
	glow_container.anchor_top = button.anchor_top
	glow_container.anchor_right = button.anchor_right
	glow_container.anchor_bottom = button.anchor_bottom
	glow_container.offset_left = button.offset_left
	glow_container.offset_top = button.offset_top
	glow_container.offset_right = button.offset_right
	glow_container.offset_bottom = button.offset_bottom

	# Create multiple copies of the icon for glow effect
	var glow_offsets = [
		Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1), Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)
	]

	var glow_color: Color
	if button_type == "close":
		glow_color = Color(1.0, 0.3, 0.3, 0.4)
	else:
		glow_color = Color(0.4, 0.7, 1.0, 0.3)

	# Create glow layers
	for i in range(glow_offsets.size()):
		var glow_rect = TextureRect.new()
		glow_rect.texture = button.icon
		glow_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		glow_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glow_rect.position = Vector2(button.size.x / 2 - 28, button.size.y / 2 - 6) + glow_offsets[i]
		glow_rect.size = Vector2(12, 12)
		glow_rect.modulate = glow_color
		glow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Fade outer layers
		if i >= 8:  # Outer ring
			glow_rect.modulate.a *= 0.5

		glow_container.add_child(glow_rect)

	# Add to title bar behind the button
	title_bar.add_child(glow_container)
	return glow_container


func _on_button_bloom_entered(bloom_container: Control, _button_type: String):
	"""Start the bloom effect"""
	if bloom_container:
		bloom_container.visible = true
		bloom_container.modulate.a = 0.0

		# Animate bloom appearance
		var tween = create_tween()
		tween.tween_property(bloom_container, "modulate:a", 1.0, 0.2)


func _on_button_bloom_exited(bloom_container: Control, _button_type: String):
	"""End the bloom effect"""
	if bloom_container:
		# Animate bloom disappearance
		var tween = create_tween()
		tween.tween_property(bloom_container, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func(): bloom_container.visible = false)


func _create_close_icon(size: int) -> ImageTexture:
	"""Create a close (X) icon programmatically"""
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)

	# Draw X lines
	var color = Color.WHITE
	var thickness = 1

	# Draw diagonal lines for X
	for i in range(thickness):
		for j in range(size):
			# Top-left to bottom-right diagonal
			if j + i < size and j - i >= 0:
				image.set_pixel(j + i, j, color)
			if j - i >= 0 and j + i < size:
				image.set_pixel(j, j + i, color)

			# Top-right to bottom-left diagonal
			if size - 1 - j + i < size and j - i >= 0:
				image.set_pixel(size - 1 - j + i, j, color)
			if j - i >= 0 and size - 1 - j + i < size:
				image.set_pixel(size - 1 - j, j + i, color)

	var texture = ImageTexture.new()
	texture.set_image(image)
	return texture


func _create_restore_icon(size: int) -> ImageTexture:
	"""Create restore icon (two overlapping squares)"""
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)

	var icon_color = Color.WHITE
	var line_width = 1
	var square_size = size - 4

	# Draw back square (offset up and left)
	var back_offset = 8
	var back_rect = Rect2i(back_offset, back_offset, square_size - back_offset, square_size - back_offset)

	# Top border of back square
	for x in range(back_rect.position.x, back_rect.position.x + back_rect.size.x):
		for y in range(back_rect.position.y, back_rect.position.y + line_width):
			if x < size and y < size and x >= 0 and y >= 0:
				image.set_pixel(x, y, icon_color)

	# Bottom border of back square
	for x in range(back_rect.position.x, back_rect.position.x + back_rect.size.x):
		for y in range(back_rect.position.y + back_rect.size.y - line_width, back_rect.position.y + back_rect.size.y):
			if x < size and y < size and x >= 0 and y >= 0:
				image.set_pixel(x, y, icon_color)

	# Left border of back square
	for y in range(back_rect.position.y, back_rect.position.y + back_rect.size.y):
		for x in range(back_rect.position.x, back_rect.position.x + line_width):
			if x < size and y < size and x >= 0 and y >= 0:
				image.set_pixel(x, y, icon_color)

	# Right border of back square
	for y in range(back_rect.position.y, back_rect.position.y + back_rect.size.y):
		for x in range(back_rect.position.x + back_rect.size.x - line_width, back_rect.position.x + back_rect.size.x):
			if x < size and y < size and x >= 0 and y >= 0:
				image.set_pixel(x, y, icon_color)

	# Draw front square (offset down and right)
	var front_offset = 0
	var front_rect = Rect2i(front_offset + 2, front_offset + 2, square_size - 2, square_size - 2)

	# Top border of front square
	for x in range(front_rect.position.x, front_rect.position.x + front_rect.size.x):
		for y in range(front_rect.position.y, front_rect.position.y + line_width):
			if x < size and y < size and x >= 0 and y >= 0:
				image.set_pixel(x, y, icon_color)

	# Bottom border of front square
	for x in range(front_rect.position.x, front_rect.position.x + front_rect.size.x):
		for y in range(front_rect.position.y + front_rect.size.y - line_width, front_rect.position.y + front_rect.size.y):
			if x < size and y < size and x >= 0 and y >= 0:
				image.set_pixel(x, y, icon_color)

	# Left border of front square
	for y in range(front_rect.position.y, front_rect.position.y + front_rect.size.y):
		for x in range(front_rect.position.x, front_rect.position.x + line_width):
			if x < size and y < size and x >= 0 and y >= 0:
				image.set_pixel(x, y, icon_color)

	# Right border of front square
	for y in range(front_rect.position.y, front_rect.position.y + front_rect.size.y):
		for x in range(front_rect.position.x + front_rect.size.x - line_width, front_rect.position.x + front_rect.size.x):
			if x < size and y < size and x >= 0 and y >= 0:
				image.set_pixel(x, y, icon_color)

	var texture = ImageTexture.new()
	texture.set_image(image)
	return texture


func _create_maximize_icon(size: int) -> ImageTexture:
	"""Create a maximize (square) icon programmatically"""
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)

	var color = Color.WHITE
	var border_thickness = 1
	var margin = 2

	# Draw rectangle border
	var rect = Rect2i(margin, margin, size - margin * 2, size - margin * 2)

	# Top and bottom borders
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for t in range(border_thickness):
			image.set_pixel(x, rect.position.y + t, color)  # Top
			image.set_pixel(x, rect.position.y + rect.size.y - 1 - t, color)  # Bottom

	# Left and right borders
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for t in range(border_thickness):
			image.set_pixel(rect.position.x + t, y, color)  # Left
			image.set_pixel(rect.position.x + rect.size.x - 1 - t, y, color)  # Right

	var texture = ImageTexture.new()
	texture.set_image(image)
	return texture


func _create_options_icon(size: int) -> ImageTexture:
	"""Create a three-dot menu icon programmatically"""
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)

	var color = Color.WHITE
	var dot_size = 1
	var spacing = 4

	# Calculate positions for three dots
	var center_x = size / 2
	var start_y = (size - (3 * dot_size + 2 * spacing)) / 2

	# Draw three dots vertically
	for dot in range(3):
		var dot_y = start_y + dot * (dot_size + spacing)
		for x in range(center_x - dot_size / 2, center_x + dot_size / 2 + 1):
			for y in range(dot_y, dot_y + dot_size):
				if x >= 0 and x < size and y >= 0 and y < size:
					image.set_pixel(x, y, color)

	var texture = ImageTexture.new()
	texture.set_image(image)
	return texture


func _create_glowing_icon(base_icon_func: Callable, size: int, _glow_color: Color) -> ImageTexture:
	"""Create an icon with built-in glow effect"""
	var base_image = base_icon_func.call(size)
	var glow_image = Image.create(size + 8, size + 8, false, Image.FORMAT_RGBA8)
	glow_image.fill(Color.TRANSPARENT)

	# Create glow by drawing the icon multiple times with offset and transparency
	var glow_offsets = [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]

	# Draw glow layers
	for offset in glow_offsets:
		glow_image.blit_rect(base_image, Rect2i(Vector2i.ZERO, base_image.get_size()), Vector2i(4, 4) + Vector2i(offset))

	# Draw the main icon on top
	glow_image.blit_rect(base_image, Rect2i(Vector2i.ZERO, base_image.get_size()), Vector2i(4, 4))

	var texture = ImageTexture.new()
	texture.set_image(glow_image)
	return texture


func _setup_resize_overlay():
	if not can_resize:
		return

	resize_overlay = Control.new()
	resize_overlay.name = "ResizeOverlay"
	resize_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resize_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resize_overlay.z_index = 100
	add_child(resize_overlay)

	move_child(resize_overlay, get_child_count() - 1)

	# Create resize areas
	_create_resize_areas()

	# Create visual border indicators
	_create_resize_border_visuals()


func _create_resize_areas():
	resize_areas.clear()

	# Create EDGES first
	# Left edge - FIXED
	var left_area = _create_resize_area("LeftResize", ResizeMode.LEFT)
	left_area.anchor_left = 0.0
	left_area.anchor_right = 0.0
	left_area.anchor_top = 0.0
	left_area.anchor_bottom = 1.0
	left_area.offset_left = 0.0  # Start from actual edge
	left_area.offset_right = resize_border_width
	left_area.offset_top = resize_corner_size
	left_area.offset_bottom = -resize_corner_size

	# Right edge
	var right_area = _create_resize_area("RightResize", ResizeMode.RIGHT)
	right_area.anchor_left = 1.0
	right_area.anchor_right = 1.0
	right_area.anchor_top = 0.0
	right_area.anchor_bottom = 1.0
	right_area.offset_left = -resize_border_width
	right_area.offset_right = 0.0  # End at actual edge
	right_area.offset_top = resize_corner_size
	right_area.offset_bottom = -resize_corner_size

	# Top edge - FIXED
	var top_area = _create_resize_area("TopResize", ResizeMode.TOP)
	top_area.anchor_left = 0.0
	top_area.anchor_right = 1.0
	top_area.anchor_top = 0.0
	top_area.anchor_bottom = 0.0
	top_area.offset_left = resize_corner_size
	top_area.offset_right = -resize_corner_size
	top_area.offset_top = 0.0  # Start from actual edge
	top_area.offset_bottom = resize_border_width

	# Bottom edge
	var bottom_area = _create_resize_area("BottomResize", ResizeMode.BOTTOM)
	bottom_area.anchor_left = 0.0
	bottom_area.anchor_right = 1.0
	bottom_area.anchor_top = 1.0
	bottom_area.anchor_bottom = 1.0
	bottom_area.offset_left = resize_corner_size
	bottom_area.offset_right = -resize_corner_size
	bottom_area.offset_top = -resize_border_width
	bottom_area.offset_bottom = 0.0  # End at actual edge

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
	left_line.color = border_color
	left_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_line.anchor_top = 0.0
	left_line.anchor_bottom = 1.0
	left_line.anchor_left = 0.0
	left_line.anchor_right = 0.0
	left_line.offset_right = 1
	resize_border_visual.add_child(left_line)
	border_lines.append(left_line)

	# Right border
	var right_line = ColorRect.new()
	right_line.name = "RightBorder"
	right_line.color = border_color
	right_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_line.anchor_top = 0.0
	right_line.anchor_bottom = 1.0
	right_line.anchor_left = 1.0
	right_line.anchor_right = 1.0
	right_line.offset_left = -1
	resize_border_visual.add_child(right_line)
	border_lines.append(right_line)

	# Top border
	var top_line = ColorRect.new()
	top_line.name = "TopBorder"
	top_line.color = border_color
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_line.anchor_left = 0.0
	top_line.anchor_right = 1.0
	top_line.anchor_top = 0.0
	top_line.anchor_bottom = 0.0
	top_line.offset_bottom = 1
	resize_border_visual.add_child(top_line)
	border_lines.append(top_line)

	# Bottom border
	var bottom_line = ColorRect.new()
	bottom_line.name = "BottomBorder"
	bottom_line.color = border_color
	bottom_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_line.anchor_left = 0.0
	bottom_line.anchor_right = 1.0
	bottom_line.anchor_top = 1.0
	bottom_line.anchor_bottom = 1.0
	bottom_line.offset_top = -1
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


func _on_window_resized(_new_size: Vector2i):
	_update_edge_bloom_size()


func _update_edge_bloom_size():
	if edge_bloom_material and edge_bloom_overlay:
		var bloom_extend = 60.0  # Shorter extend
		edge_bloom_material.set_window_size(size)
		edge_bloom_material.set_bloom_extend(bloom_extend)
		edge_bloom_overlay.position = Vector2(-bloom_extend, -bloom_extend)
		edge_bloom_overlay.size = size + Vector2(bloom_extend * 2, bloom_extend * 2)


func _on_resize_area_input(event: InputEvent, source_area: Control):
	var mode = source_area.get_meta("resize_mode") as ResizeMode

	if not can_resize or is_locked:
		return

	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_start_resize(mode, mouse_event.global_position)
				get_viewport().set_input_as_handled()
				# Don't bring to front while resizing
			else:
				_end_resize()
				get_viewport().set_input_as_handled()


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

	# Show edge bloom
	_show_edge_bloom(mode)


func _on_resize_area_exited(_mode: ResizeMode):
	"""Handle mouse exiting a resize area"""
	if not is_resizing:
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		_hide_edge_bloom()


func _show_edge_bloom(mode: ResizeMode):
	"""Show edge bloom for specific resize mode with fade in"""
	if edge_bloom_material and edge_bloom_overlay:
		# Kill any existing tween
		if edge_bloom_tween:
			edge_bloom_tween.kill()
			edge_bloom_tween = null

		edge_bloom_material.show_edge(mode)
		edge_bloom_overlay.visible = true

		# Get current intensity to fade from
		var current_intensity = edge_bloom_material.current_intensity

		# Animate fade in
		edge_bloom_tween = create_tween()
		edge_bloom_tween.tween_method(_update_edge_bloom_intensity, current_intensity, edge_bloom_material.base_intensity, 0.15)


func _hide_edge_bloom():
	"""Hide edge bloom with fade out"""
	if edge_bloom_material and edge_bloom_overlay:
		# Kill any existing tween
		if edge_bloom_tween:
			edge_bloom_tween.kill()
			edge_bloom_tween = null

		# Get current intensity
		var current_intensity = edge_bloom_material.current_intensity

		# Animate fade out
		edge_bloom_tween = create_tween()
		edge_bloom_tween.tween_method(_update_edge_bloom_intensity, current_intensity, 0.0, 0.15)
		edge_bloom_tween.finished.connect(
			func():
				if edge_bloom_overlay:
					edge_bloom_overlay.visible = false
				if edge_bloom_material:
					edge_bloom_material.hide_all_edges()
		)


func _update_edge_bloom_intensity(intensity: float):
	"""Update edge bloom intensity for animation"""
	if edge_bloom_material:
		# Use the set_intensity method that exists in WindowEdgeBloomMaterial
		edge_bloom_material.set_intensity(intensity)


func _animate_edge_alpha(mode: ResizeMode, from_alpha: float, to_alpha: float, duration: float):
	"""Animate edge alpha for specific resize mode"""
	match mode:
		ResizeMode.LEFT:
			edge_bloom_tween.tween_method(_set_left_alpha, from_alpha, to_alpha, duration)
		ResizeMode.RIGHT:
			edge_bloom_tween.tween_method(_set_right_alpha, from_alpha, to_alpha, duration)
		ResizeMode.TOP:
			edge_bloom_tween.tween_method(_set_top_alpha, from_alpha, to_alpha, duration)
		ResizeMode.BOTTOM:
			edge_bloom_tween.tween_method(_set_bottom_alpha, from_alpha, to_alpha, duration)
		ResizeMode.TOP_LEFT:
			edge_bloom_tween.tween_method(_set_left_alpha, from_alpha, to_alpha, duration)
			edge_bloom_tween.tween_method(_set_top_alpha, from_alpha, to_alpha, duration)
		ResizeMode.TOP_RIGHT:
			edge_bloom_tween.tween_method(_set_right_alpha, from_alpha, to_alpha, duration)
			edge_bloom_tween.tween_method(_set_top_alpha, from_alpha, to_alpha, duration)
		ResizeMode.BOTTOM_LEFT:
			edge_bloom_tween.tween_method(_set_left_alpha, from_alpha, to_alpha, duration)
			edge_bloom_tween.tween_method(_set_bottom_alpha, from_alpha, to_alpha, duration)
		ResizeMode.BOTTOM_RIGHT:
			edge_bloom_tween.tween_method(_set_right_alpha, from_alpha, to_alpha, duration)
			edge_bloom_tween.tween_method(_set_bottom_alpha, from_alpha, to_alpha, duration)


# Helper methods for tween callbacks
func _set_left_alpha(alpha: float):
	edge_bloom_material.set_shader_parameter("left_edge_alpha", alpha)


func _set_right_alpha(alpha: float):
	edge_bloom_material.set_shader_parameter("right_edge_alpha", alpha)


func _set_top_alpha(alpha: float):
	edge_bloom_material.set_shader_parameter("top_edge_alpha", alpha)


func _set_bottom_alpha(alpha: float):
	edge_bloom_material.set_shader_parameter("bottom_edge_alpha", alpha)


func _get_current_left_alpha() -> float:
	return edge_bloom_material.get_shader_parameter("left_edge_alpha")


func _get_current_right_alpha() -> float:
	return edge_bloom_material.get_shader_parameter("right_edge_alpha")


func _get_current_top_alpha() -> float:
	return edge_bloom_material.get_shader_parameter("top_edge_alpha")


func _get_current_bottom_alpha() -> float:
	return edge_bloom_material.get_shader_parameter("bottom_edge_alpha")


func _start_resize(mode: ResizeMode, mouse_pos: Vector2):
	is_resizing = true
	resize_mode = mode
	resize_start_position = position
	resize_start_size = size
	resize_start_mouse = mouse_pos

	# Notify snapping manager of resize start
	if snapping_manager:
		snapping_manager.start_window_resize(self, mode)


func _end_resize():
	if is_resizing:
		# Notify snapping manager of resize end
		if snapping_manager:
			snapping_manager.end_window_resize(self)

		is_resizing = false
		resize_mode = ResizeMode.NONE
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		# IMPORTANT: Always hide edge bloom when ending resize
		_hide_edge_bloom()


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

	# APPLY RESIZE SNAPPING - get snapped position and size from snapping manager
	if snapping_manager:
		var snap_result = snapping_manager.update_window_resize(self, new_position, new_size, resize_mode)
		new_position = snap_result.get("position", new_position)
		new_size = snap_result.get("size", new_size)

	# Apply size constraints AFTER snapping
	var constrained_size = Vector2(max(min_window_size.x, min(new_size.x, max_window_size.x)), max(min_window_size.y, min(new_size.y, max_window_size.y)))

	# Adjust position if size was constrained (for left/top resizing)
	if resize_mode in [ResizeMode.LEFT, ResizeMode.TOP_LEFT, ResizeMode.BOTTOM_LEFT]:
		if constrained_size.x != new_size.x:
			new_position.x = resize_start_position.x + (resize_start_size.x - constrained_size.x)

	if resize_mode in [ResizeMode.TOP, ResizeMode.TOP_LEFT, ResizeMode.TOP_RIGHT]:
		if constrained_size.y != new_size.y:
			new_position.y = resize_start_position.y + (resize_start_size.y - constrained_size.y)

	# Update position and size
	position = new_position
	size = constrained_size

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
		maximize_button.icon = _create_restore_icon(18)


func _restore_window():
	if not is_maximized:
		return

	position = restore_position
	size = restore_size
	is_maximized = false

	if maximize_button:
		maximize_button.icon = _create_maximize_icon(16)

	window_restored.emit()


func _bring_to_front():
	"""Bring this window to front through UIManager"""
	if ui_manager and ui_manager.has_method("focus_window"):
		ui_manager.focus_window(self)


# Also add a public method for manual focus
func bring_to_front():
	"""Public method to bring window to front"""
	_bring_to_front()


func _on_window_close_requested():
	# Virtual method - override in child classes
	_on_window_closed()

	# Default behavior
	visible = false
	window_closed.emit()


func _on_window_closed():
	"""Override this method in child classes for custom close behavior"""


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
	window_property_changed.emit("locked", locked)


func get_transparency() -> float:
	return modulate.a


func set_transparency(alpha: float):
	modulate.a = alpha
	window_property_changed.emit("transparency", alpha)


func set_resizing_enabled(enabled: bool):
	can_resize = enabled
	if resize_overlay:
		resize_overlay.visible = enabled
	if not enabled and is_resizing:
		_end_resize()


func get_resizing_enabled() -> bool:
	return can_resize


func _on_size_changed():
	_update_edge_bloom_size()


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
	"""Handle title bar input for drag and focus"""
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_bring_to_front()
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
					# END DRAG - notify snapping manager
					if snapping_manager:
						snapping_manager.end_window_drag(self)
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

			# START DRAG - notify snapping manager
			if snapping_manager:
				snapping_manager.start_window_drag(self)

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

		# Calculate new position
		var new_position = motion_event.global_position - drag_start_position

		# APPLY SNAPPING - get snapped position from snapping manager
		if snapping_manager:
			new_position = snapping_manager.update_window_drag(self, new_position)

		# Apply the position (snapped or normal)
		position = new_position

		get_viewport().set_input_as_handled()


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
	#_hide_all_border_visuals()

	# Disable mouse detection on resize areas
	if resize_overlay:
		resize_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for area in resize_areas:
		if area:
			area.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _setup_edge_bloom():
	if not can_resize:
		return

	edge_bloom_overlay = ColorRect.new()
	edge_bloom_overlay.name = "EdgeBloomOverlay"
	edge_bloom_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge_bloom_overlay.color = Color.TRANSPARENT
	edge_bloom_overlay.visible = true  # Keep visible, control with alpha
	edge_bloom_overlay.z_index = 10

	var bloom_extend = 60.0  # Much smaller extend for shorter bloom
	edge_bloom_overlay.position = Vector2(-bloom_extend, -bloom_extend)
	edge_bloom_overlay.size = size + Vector2(bloom_extend * 2, bloom_extend * 2)

	edge_bloom_material = WindowEdgeBloomMaterial.new()
	edge_bloom_material.set_window_size(size)
	edge_bloom_material.set_bloom_extend(bloom_extend)
	edge_bloom_overlay.material = edge_bloom_material

	add_child(edge_bloom_overlay)


func _on_mouse_entered():
	"""Handle mouse entering window area"""
	# Optional: Could bring to front on hover
	# _bring_to_front()


func _on_mouse_exited():
	"""Handle mouse exiting window area"""
	if not is_resizing:
		_hide_edge_bloom()
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _notification(what):
	if what == NOTIFICATION_MOUSE_EXIT:
		# Mouse left the window entirely
		if not is_resizing:
			_hide_edge_bloom()
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	elif what == NOTIFICATION_FOCUS_EXIT:
		# Window lost focus
		if not is_resizing:
			_hide_edge_bloom()
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
