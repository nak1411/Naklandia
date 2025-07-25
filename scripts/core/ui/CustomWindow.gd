# CustomWindow.gd - Custom window implementation with full control
class_name CustomWindow
extends Window

# Window properties
@export var window_title: String = "Custom Window"
@export var can_drag: bool = true
@export var can_close: bool = true
@export var can_minimize: bool = true
@export var can_maximize: bool = true
@export var debug_hover_rects: bool = true  # Enable debug rectangle drawing

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

# Transparency popup management
var hover_timer: Timer
var current_transparency_popup: PopupMenu
var popup_hover_grace_timer: Timer

# Debug visualization
var debug_overlay: Control
var debug_rects: Array[Dictionary] = []

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
	_setup_debug_overlay()

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
	bg_style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	content_background.add_theme_stylebox_override("panel", bg_style)
	
	content_area.add_child(content_background)

func add_content(content: Control):
	if content_area:
		content_area.add_child(content)

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
	
	# Debug overlay setup is now handled in _setup_debug_overlay()

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
	if not title_bar:
		return
		
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
	
	# Clear any existing items first
	popup.clear()
	
	# Add menu items
	popup.add_check_item("Lock Window", 0)
	popup.add_separator()
	popup.add_item("Transparency", 2)
	popup.add_separator()
	popup.add_item("Reset Transparency", 4)
	
	# Connect main popup signals
	popup.id_pressed.connect(_on_options_menu_selected)
	
	# Add proper hover detection for transparency submenu
	popup.mouse_entered.connect(_start_hover_detection)
	popup.popup_hide.connect(_on_options_popup_hidden)

func _start_hover_detection():
	_stop_hover_detection()  # Clean up any existing timer
	
	hover_timer = Timer.new()
	hover_timer.wait_time = 0.05  # Check every 50ms for responsiveness
	hover_timer.timeout.connect(_check_hover)
	add_child(hover_timer)
	hover_timer.start()

func _stop_hover_detection():
	if hover_timer and is_instance_valid(hover_timer):
		hover_timer.queue_free()
		hover_timer = null

func _on_options_popup_hidden():
	# Don't immediately close everything if transparency popup is open
	if current_transparency_popup and is_instance_valid(current_transparency_popup) and current_transparency_popup.visible:
		# Keep hover detection running to manage the transparency popup
		return
	
	_stop_hover_detection()
	_close_transparency_popup()

func _check_hover():
	# Clear previous debug rects
	_clear_debug_rects()
	
	var options_popup = options_button.get_popup()
	
	# If options popup is not visible but transparency popup is, manage transparency popup independently
	if not options_popup.visible:
		if current_transparency_popup and is_instance_valid(current_transparency_popup) and current_transparency_popup.visible:
			# Check if mouse is still over transparency popup
			var screen_mouse_pos = DisplayServer.mouse_get_position()
			var transparency_rect = Rect2(Vector2(current_transparency_popup.position), current_transparency_popup.size)
			
			# Debug: Draw transparency popup rect
			_draw_debug_rect(transparency_rect, Color.CYAN, "Transparency Popup")
			
			if not transparency_rect.has_point(screen_mouse_pos):
				_close_transparency_popup()
				_stop_hover_detection()
			# Keep checking while transparency popup is open
			return
		else:
			_stop_hover_detection()
			return
	
	var mouse_pos = get_viewport().get_mouse_position()
	
	# Calculate options popup position and rect using screen coordinates
	var options_button_screen_pos = options_button.get_screen_position()
	var popup_screen_pos = Vector2(
		options_button_screen_pos.x,
		options_button_screen_pos.y + options_button.size.y
	)
	
	# Force a larger height for the options rect to include all items
	var calculated_popup_height = 5 * 30  # 5 items (including separators) * 30 pixels each
	var options_rect = Rect2(popup_screen_pos, Vector2(options_popup.size.x, calculated_popup_height))
	
	# Use viewport mouse position converted to screen coordinates
	var viewport_mouse_pos = get_viewport().get_mouse_position()
	var window_screen_pos = position  # Window's position on screen
	var screen_mouse_pos = viewport_mouse_pos + Vector2(window_screen_pos)
	
	if debug_hover_rects:
		# Debug: Print corrected mouse position and popup info
		print("Corrected screen mouse: ", screen_mouse_pos)
		print("Options popup size: ", options_popup.size)
		print("Calculated rect: ", options_rect)
		print("Mouse in options rect: ", options_rect.has_point(screen_mouse_pos))
		
		# Debug: Draw options popup rect
		_draw_debug_rect(options_rect, Color.GREEN, "Options Popup")
	
	# Check if mouse is over transparency popup
	var over_transparency_popup = false
	if current_transparency_popup and is_instance_valid(current_transparency_popup) and current_transparency_popup.visible:
		var transparency_rect = Rect2(Vector2(current_transparency_popup.position), current_transparency_popup.size)
		over_transparency_popup = transparency_rect.has_point(screen_mouse_pos)
		
		if debug_hover_rects:
			# Debug: Draw transparency popup rect
			_draw_debug_rect(transparency_rect, Color.CYAN, "Transparency Popup")
			
			# Debug: Print transparency popup position
			print("Transparency popup at: ", transparency_rect)
	
	if debug_hover_rects:
		# Debug: Draw corrected mouse position
		_draw_debug_rect(Rect2(screen_mouse_pos - Vector2(5, 5), Vector2(10, 10)), Color.RED, "Mouse (Corrected)")
	
	if options_rect.has_point(screen_mouse_pos):
		# Mouse is over options popup - check which item
		var local_mouse = screen_mouse_pos - popup_screen_pos
		var item_height = 28  # Correct item height
		var item_y_offset = 3  # Y offset to align with actual menu items
		var item_spacing = 4  # Spacing between menu items
		var total_item_height = item_height + item_spacing
		var hovered_item = int((local_mouse.y - item_y_offset) / total_item_height)
		
		if debug_hover_rects:
			# Debug: Draw hovered item rect (use screen coordinates directly)
			var item_rect_screen = Rect2(
				popup_screen_pos.x,
				popup_screen_pos.y + item_y_offset + (hovered_item * total_item_height),
				options_rect.size.x,
				item_height
			)
			_draw_debug_rect(item_rect_screen, Color.YELLOW, "Item " + str(hovered_item))
			
			# Debug: Show that we detected mouse over options popup
			_draw_debug_rect(Rect2(screen_mouse_pos - Vector2(7, 7), Vector2(14, 14)), Color.WHITE, "Over Options")
			
			# Debug: Print hovered item to console
			print("Hovered item: ", hovered_item, " at mouse pos: ", local_mouse)
			print("Item calc: (", local_mouse.y, " - ", item_y_offset, ") / ", total_item_height, " = ", (local_mouse.y - item_y_offset) / total_item_height)
		
		# Account for separators: Lock(0), sep(1), Transparency(2), sep(3), Reset Transparency(4)
		print("Processing item: ", hovered_item)
		if hovered_item == 2:  # Transparency item
			print("Opening transparency popup")
			if not current_transparency_popup or not is_instance_valid(current_transparency_popup) or not current_transparency_popup.visible:
				_show_transparency_popup()
		elif hovered_item == 0:  # Lock Window - close transparency popup
			print("Closing transparency popup (Lock Window)")
			_close_transparency_popup()
		elif hovered_item == 3 or hovered_item == 4:
			print("Hovering separator or Reset Transparency - keeping popup open")
		else:
			print("Unknown item ", hovered_item, " - no action")
		# Don't close transparency popup for Reset Transparency (item 4) or separators
		# Reset Transparency is related to transparency, so keep the popup open
	elif over_transparency_popup:
		# Mouse is over transparency popup - keep it open
		if debug_hover_rects:
			# Debug: Show that we detected mouse over transparency popup
			_draw_debug_rect(Rect2(screen_mouse_pos - Vector2(10, 10), Vector2(20, 20)), Color.LIME, "Over Trans Popup")
		pass
	else:
		# Mouse is over NEITHER popup (not options popup and not transparency popup)
		# Only then check if we're in the bridge area
		if current_transparency_popup and is_instance_valid(current_transparency_popup) and current_transparency_popup.visible:
			# Check if mouse is in the "bridge" area between options popup and transparency popup
			var bridge_rect_screen = Rect2(
				options_rect.position.x + options_rect.size.x,
				options_rect.position.y,  # Start from top of options popup
				50,  # Wider bridge to cover the gap better
				options_rect.size.y   # Full height of options popup
			)
			
			if debug_hover_rects:
				# Debug: Draw bridge rect (use screen coordinates directly)
				_draw_debug_rect(bridge_rect_screen, Color.MAGENTA, "Bridge Area")
				
				# Debug: Print bridge area and mouse position
				print("Bridge area: ", bridge_rect_screen)
				print("Mouse in bridge: ", bridge_rect_screen.has_point(screen_mouse_pos))
			
			if not bridge_rect_screen.has_point(screen_mouse_pos):
				if debug_hover_rects:
					print("Closing transparency popup - mouse outside bridge")
				_close_transparency_popup()
			elif debug_hover_rects:
				# Debug: Show that we're in the bridge area
				_draw_debug_rect(Rect2(screen_mouse_pos - Vector2(8, 8), Vector2(16, 16)), Color.CYAN, "In Bridge")

func _show_transparency_popup():
	# Clean up any existing popup
	_close_transparency_popup()
	
	# Create new transparency popup
	current_transparency_popup = PopupMenu.new()
	current_transparency_popup.name = "TransparencyOptions"
	
	# Add transparency options
	current_transparency_popup.add_item("100%", 100)
	current_transparency_popup.add_item("90%", 90)
	current_transparency_popup.add_item("80%", 80)
	current_transparency_popup.add_item("70%", 70)
	current_transparency_popup.add_item("60%", 60)
	current_transparency_popup.add_item("50%", 50)
	current_transparency_popup.add_item("40%", 40)
	current_transparency_popup.add_item("30%", 30)
	current_transparency_popup.add_item("20%", 20)
	current_transparency_popup.add_item("10%", 10)
	
	# Mark current transparency value
	var current_percentage = int(window_transparency * 100)
	for i in current_transparency_popup.get_item_count():
		var item_id = current_transparency_popup.get_item_id(i)
		if item_id == current_percentage:
			current_transparency_popup.set_item_checked(i, true)
			break
	
	# Connect selection and hide events
	current_transparency_popup.id_pressed.connect(_on_transparency_option_selected)
	current_transparency_popup.popup_hide.connect(_on_transparency_popup_hidden)
	
	# Add to viewport for proper global positioning
	get_viewport().add_child(current_transparency_popup)
	
	# Calculate position using screen coordinates to match hover detection
	var options_popup = options_button.get_popup()
	var button_screen_pos = options_button.get_screen_position()
	
	# Position where options dropdown appears
	var dropdown_x = button_screen_pos.x
	var dropdown_y = button_screen_pos.y + options_button.size.y
	
	# Calculate transparency item position (Lock=0, separator=1, Transparency=2)
	var item_height = 18
	var transparency_item_y = 2 * item_height  # Item index 2
	
	# Position transparency popup to the right of the transparency item
	var popup_pos = Vector2i(
		int(dropdown_x + options_popup.size.x - 8),  # Right edge of options popup
		int(dropdown_y + transparency_item_y - 3)   # Aligned with transparency item
	)
	
	current_transparency_popup.position = popup_pos
	current_transparency_popup.popup()

func _close_transparency_popup():
	if current_transparency_popup and is_instance_valid(current_transparency_popup):
		current_transparency_popup.queue_free()
		current_transparency_popup = null

func _on_transparency_popup_hidden():
	# Don't auto-close on hide - let the hover detection handle it
	pass

func _on_options_menu_selected(id: int):
	var popup = options_button.get_popup()
	match id:
		0:  # Lock Window
			window_locked = not window_locked
			popup.set_item_checked(0, window_locked)
			set_dragging_enabled(not window_locked)
			window_locked_changed.emit(window_locked)
		2:  # Transparency - handled by hover, do nothing on click
			pass
		4:  # Reset Transparency
			_set_transparency(1.0)

func _on_transparency_option_selected(id: int):
	var transparency_value = float(id) / 100.0
	_set_transparency(transparency_value)
	_close_transparency_popup()

func _set_transparency(value: float):
	window_transparency = value
	if content_background:
		var current_modulate = content_background.modulate
		current_modulate.a = value
		content_background.modulate = current_modulate
	
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
	if options_button:
		var popup = options_button.get_popup()
		popup.set_item_checked(0, locked)
	set_dragging_enabled(not locked)

func get_transparency() -> float:
	return window_transparency

func set_transparency(value: float):
	_set_transparency(value)

func get_content_area() -> Control:
	return content_area

func _setup_debug_overlay():
	if debug_hover_rects:
		# Create a CanvasLayer for screen-wide debug overlay
		var debug_canvas = CanvasLayer.new()
		debug_canvas.name = "DebugCanvas"
		debug_canvas.layer = 10000  # Much higher layer to be on top of everything
		
		debug_overlay = Control.new()
		debug_overlay.name = "DebugOverlay"
		debug_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		debug_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		debug_overlay.z_index = 10000  # Also increase z_index
		
		# Add to the main scene tree for full screen coverage
		get_tree().current_scene.add_child(debug_canvas)
		debug_canvas.add_child(debug_overlay)
		
		# Connect draw signal immediately
		debug_overlay.draw.connect(_on_debug_overlay_draw)
		print("Debug overlay created and added to main scene with CanvasLayer layer 10000")

func _draw_debug_rect(rect: Rect2, color: Color, label: String = ""):
	if not debug_hover_rects or not debug_overlay:
		return
	
	debug_rects.append({
		"rect": rect,
		"color": color,
		"label": label
	})
	print("Adding debug rect: ", label, " at ", rect)
	debug_overlay.queue_redraw()

func _clear_debug_rects():
	if debug_hover_rects and debug_overlay:
		debug_rects.clear()
		debug_overlay.queue_redraw()
		print("Cleared debug rects")

# Custom draw function for debug overlay
func _on_debug_overlay_draw():
	if not debug_hover_rects or not debug_overlay:
		return
	
	print("Drawing ", debug_rects.size(), " debug rects")
	
	for debug_info in debug_rects:
		var rect = debug_info.rect
		var color = debug_info.color
		var label = debug_info.label
		
		# Draw rectangle outline
		debug_overlay.draw_rect(rect, color, false, 2.0)
		
		# Draw label if provided
		if not label.is_empty():
			var font = ThemeDB.fallback_font
			var font_size = 12
			debug_overlay.draw_string(font, rect.position + Vector2(5, 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
