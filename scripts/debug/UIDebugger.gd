# UIDebugger.gd
class_name UIDebugger
extends CanvasLayer

# Toggle state
var is_active: bool = false

# Debug settings
var show_bounds: bool = true
var show_snapping_guides: bool = false
var show_info: bool = true
var show_only_visible: bool = true
var show_only_focused: bool = true
var bounds_color: Color = Color.CYAN
var bounds_width: float = 1.0
var info_color: Color = Color.WHITE
var info_background_color: Color = Color(0, 0, 0, 0.7)

# Tracked elements
var tracked_elements: Array[Control] = []
var debug_overlays: Array[Control] = []
var known_element_ids: Dictionary = {}

# UI elements
var debug_panel: Control
var info_panel: Panel
var info_scroll: ScrollContainer
var info_label: RichTextLabel
var title_bar: Panel
var title_label: Label

# Focus tracking
var focused_element: Control = null
var hovered_element: Control = null

# Dynamic discovery
var discovery_timer: Timer
var discovery_interval: float = 0.5

# Dragging (following Window_Base pattern)
var is_dragging: bool = false
var mouse_pressed: bool = false
var drag_initiated: bool = false
var click_start_position: Vector2 = Vector2.ZERO
var drag_start_position: Vector2 = Vector2.ZERO
var drag_threshold: float = 5.0


func _ready():
	name = "UIDebugger"
	layer = 999
	visible = false
	add_to_group("ui_debugger")

	_setup_debug_ui()
	_setup_discovery_timer()
	print("UIDebugger initialized")


func _setup_debug_ui():
	# Create main debug panel
	debug_panel = Control.new()
	debug_panel.name = "DebugPanel"
	debug_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(debug_panel)

	# Create draggable info panel with fixed size
	info_panel = Panel.new()
	info_panel.name = "InfoPanel"
	info_panel.position = Vector2(10, 10)
	info_panel.size = Vector2(300, 500)
	info_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	debug_panel.add_child(info_panel)

	# Style the info panel
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = info_background_color
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = bounds_color
	info_panel.add_theme_stylebox_override("panel", panel_style)

	# Create draggable title bar
	title_bar = Panel.new()
	title_bar.name = "TitleBar"
	title_bar.anchor_left = 0.0
	title_bar.anchor_right = 1.0
	title_bar.anchor_top = 0.0
	title_bar.anchor_bottom = 0.0
	title_bar.offset_left = 2
	title_bar.offset_right = -2
	title_bar.offset_top = 2
	title_bar.offset_bottom = 30
	title_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	info_panel.add_child(title_bar)

	# Style the title bar
	var title_style = StyleBoxFlat.new()
	title_style.bg_color = bounds_color
	title_bar.add_theme_stylebox_override("panel", title_style)

	# Create title label
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "UI Debug Info"
	title_label.anchor_left = 0.0
	title_label.anchor_right = 1.0
	title_label.anchor_top = 0.0
	title_label.anchor_bottom = 1.0
	title_label.offset_left = 8
	title_label.offset_right = -8
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(title_label)

	# Add title label theme
	title_label.add_theme_color_override("font_color", Color.BLACK)

	# Connect title bar input events (following Window_Base pattern)
	title_bar.gui_input.connect(_on_title_bar_input)

	# Create scroll container (moved down to make room for title bar)
	info_scroll = ScrollContainer.new()
	info_scroll.name = "InfoScroll"
	info_scroll.anchor_left = 0.0
	info_scroll.anchor_right = 1.0
	info_scroll.anchor_top = 0.0
	info_scroll.anchor_bottom = 1.0
	info_scroll.offset_left = 5
	info_scroll.offset_top = 35  # Below title bar
	info_scroll.offset_right = -5
	info_scroll.offset_bottom = -5
	info_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	info_panel.add_child(info_scroll)

	# Create info display inside scroll container
	info_label = RichTextLabel.new()
	info_label.name = "InfoLabel"
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_label.bbcode_enabled = true
	info_label.scroll_active = false
	info_label.fit_content = true
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_scroll.add_child(info_label)


func _on_title_bar_input(event: InputEvent):
	"""Handle title bar input events - following Window_Base pattern"""
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				# Store initial click position and state for dragging
				mouse_pressed = true
				is_dragging = false
				drag_initiated = false
				click_start_position = mouse_event.global_position
				# Store the offset from mouse to panel position
				drag_start_position = mouse_event.global_position - info_panel.global_position
				get_viewport().set_input_as_handled()
			else:
				# Handle mouse release - reset all drag states
				mouse_pressed = false
				if is_dragging:
					is_dragging = false
					Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				drag_initiated = false

	elif event is InputEventMouseMotion and mouse_pressed and not drag_initiated:
		# Check if we should start dragging
		var motion_event = event as InputEventMouseMotion
		var current_mouse_pos = motion_event.global_position
		var distance = click_start_position.distance_to(current_mouse_pos)

		if distance > drag_threshold:
			# Start actual dragging
			drag_initiated = true
			is_dragging = true
			Input.set_default_cursor_shape(Input.CURSOR_MOVE)

	elif event is InputEventMouseMotion and is_dragging and drag_initiated:
		# Handle actual dragging
		var motion_event = event as InputEventMouseMotion

		# Calculate new position: mouse position minus the original offset
		var new_position = motion_event.global_position - drag_start_position

		# Clamp to screen bounds
		var viewport_size = get_viewport().get_visible_rect().size
		new_position.x = clampf(new_position.x, 0, viewport_size.x - info_panel.size.x)
		new_position.y = clampf(new_position.y, 0, viewport_size.y - info_panel.size.y)

		info_panel.position = new_position


func _setup_discovery_timer():
	"""Set up timer for continuous element discovery"""
	discovery_timer = Timer.new()
	discovery_timer.name = "DiscoveryTimer"
	discovery_timer.wait_time = discovery_interval
	discovery_timer.timeout.connect(_discover_new_elements)
	add_child(discovery_timer)


func _input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F3:
				toggle_debugger()
				get_viewport().set_input_as_handled()
			KEY_F4:
				if is_active:
					toggle_bounds()
					get_viewport().set_input_as_handled()
			KEY_F5:
				if is_active:
					toggle_info()
					get_viewport().set_input_as_handled()
			KEY_F6:
				if is_active:
					toggle_visible_only()
					get_viewport().set_input_as_handled()
			KEY_F7:
				if is_active:
					toggle_focused_only()
					get_viewport().set_input_as_handled()
			KEY_F8:
				if is_active:
					force_refresh_elements()
					get_viewport().set_input_as_handled()
			KEY_F9:
				if is_active:
					reset_panel_position()
					get_viewport().set_input_as_handled()
			KEY_F10:
				if is_active:
					toggle_snapping_guides()
					get_viewport().set_input_as_handled()
			KEY_QUOTELEFT:  # Backtick key
				toggle_debugger()
				get_viewport().set_input_as_handled()


func toggle_debugger():
	"""Toggle the entire debugger on/off"""
	is_active = !is_active
	visible = is_active
	print("UI Debugger: ", "ON" if is_active else "OFF")

	if is_active:
		_start_debugging()
	else:
		_stop_debugging()


func toggle_snapping_guides():
	"""Toggle bounding box display"""
	show_snapping_guides = !show_snapping_guides
	WindowSnappingManager.show_padding_lines = show_snapping_guides
	WindowSnappingManager.show_debug_lines = show_snapping_guides
	print("UI Debugger snapping guides: ", "ON" if show_snapping_guides else "OFF")
	_update_debug_display()


func toggle_bounds():
	"""Toggle bounding box display"""
	show_bounds = !show_bounds
	print("UI Debugger bounds: ", "ON" if show_bounds else "OFF")
	_update_debug_display()


func toggle_info():
	"""Toggle info panel display"""
	show_info = !show_info
	info_panel.visible = show_info
	print("UI Debugger info: ", "ON" if show_info else "OFF")


func toggle_visible_only():
	"""Toggle showing only visible elements"""
	show_only_visible = !show_only_visible
	print("UI Debugger visible only: ", "ON" if show_only_visible else "OFF")
	_update_debug_display()


func toggle_focused_only():
	"""Toggle showing only focused/hovered elements"""
	show_only_focused = !show_only_focused
	print("UI Debugger focused only: ", "ON" if show_only_focused else "OFF")
	_update_debug_display()


func force_refresh_elements():
	"""Force a complete refresh of all elements"""
	print("UI Debugger: Force refreshing elements...")
	_clear_debug_overlays()
	_cleanup_focus_tracking()
	tracked_elements.clear()
	known_element_ids.clear()
	_find_all_ui_elements()
	_setup_focus_tracking()
	_create_all_debug_overlays()
	_update_debug_display()


func reset_panel_position():
	"""Reset panel to default position"""
	info_panel.position = Vector2(10, 10)
	print("UI Debugger: Panel position reset")


func _start_debugging():
	"""Start the debugging process"""
	_find_all_ui_elements()
	_setup_focus_tracking()
	_create_all_debug_overlays()
	_update_debug_display()

	# Start continuous discovery
	discovery_timer.start()


func _stop_debugging():
	"""Stop the debugging process"""
	discovery_timer.stop()
	_clear_debug_overlays()
	_cleanup_focus_tracking()

	# Stop any active dragging
	is_dragging = false
	mouse_pressed = false
	drag_initiated = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


# [Rest of the methods remain the same as before - no changes needed]
func _discover_new_elements():
	"""Continuously discover new UI elements"""
	if not is_active:
		return

	var initial_count = tracked_elements.size()

	# Find new elements
	_find_all_ui_elements_incremental()

	# If we found new elements, set up tracking for them
	if tracked_elements.size() > initial_count:
		var new_count = tracked_elements.size() - initial_count

		# Set up focus tracking for new elements only
		_setup_focus_tracking_for_new_elements(initial_count)

		# Create overlays for new elements
		_create_overlays_for_new_elements(initial_count)


func _find_all_ui_elements():
	"""Find all UI elements in the scene (initial scan)"""
	tracked_elements.clear()
	known_element_ids.clear()
	_recursive_find_controls(get_tree().root)
	_cleanup_invalid_elements()
	print("Found %d UI elements to track" % tracked_elements.size())


func _find_all_ui_elements_incremental():
	"""Find new UI elements without clearing existing ones"""
	_cleanup_invalid_elements()

	# Update known_element_ids for current valid elements
	var current_ids: Dictionary = {}
	for element in tracked_elements:
		if is_instance_valid(element):
			current_ids[element.get_instance_id()] = true
	known_element_ids = current_ids

	# Recursively find all controls
	_recursive_find_controls_incremental(get_tree().root)


func _recursive_find_controls(node: Node):
	"""Recursively find all Control nodes (initial scan)"""
	if not is_instance_valid(node):
		return

	if node is Control and not _is_debugger_element(node):
		tracked_elements.append(node)
		known_element_ids[node.get_instance_id()] = true

	for child in node.get_children():
		_recursive_find_controls(child)


func _recursive_find_controls_incremental(node: Node):
	"""Recursively find new Control nodes (incremental scan)"""
	if not is_instance_valid(node):
		return

	if node is Control and not _is_debugger_element(node):
		var element_id = node.get_instance_id()
		# Only add if we haven't seen this element before
		if not known_element_ids.has(element_id):
			tracked_elements.append(node)
			known_element_ids[element_id] = true

	# Always check children for new elements
	for child in node.get_children():
		_recursive_find_controls_incremental(child)


func _cleanup_invalid_elements():
	"""Clean up references to freed/invalid elements"""
	# Clean up tracked elements
	for i in range(tracked_elements.size() - 1, -1, -1):
		var element = tracked_elements[i]
		if not is_instance_valid(element):
			var element_id = element.get_instance_id() if element else 0
			tracked_elements.remove_at(i)
			if known_element_ids.has(element_id):
				known_element_ids.erase(element_id)

	# Clean up focus references
	if focused_element and not is_instance_valid(focused_element):
		focused_element = null
	if hovered_element and not is_instance_valid(hovered_element):
		hovered_element = null

	# Clean up overlays for invalid elements
	for i in range(debug_overlays.size() - 1, -1, -1):
		var overlay = debug_overlays[i]
		if not is_instance_valid(overlay):
			debug_overlays.remove_at(i)
			continue

		var element = overlay.get_meta("tracked_element", null)
		if not is_instance_valid(element):
			overlay.queue_free()
			debug_overlays.remove_at(i)


func _setup_focus_tracking():
	"""Set up focus and hover tracking for all elements"""
	_cleanup_invalid_elements()
	_setup_focus_tracking_for_new_elements(0)


func _setup_focus_tracking_for_new_elements(start_index: int):
	"""Set up focus tracking for newly discovered elements"""
	for i in range(start_index, tracked_elements.size()):
		var element = tracked_elements[i]
		if not is_instance_valid(element):
			continue

		_connect_element_signals(element)


func _connect_element_signals(element: Control):
	"""Connect signals for a single element"""
	if not is_instance_valid(element):
		return

	# Connect focus signals if available
	if element.has_signal("focus_entered"):
		if not element.focus_entered.is_connected(_on_element_focused):
			element.focus_entered.connect(_on_element_focused.bind(element))
	if element.has_signal("focus_exited"):
		if not element.focus_exited.is_connected(_on_element_focus_exited):
			element.focus_exited.connect(_on_element_focus_exited.bind(element))

	# Connect mouse signals if available
	if element.has_signal("mouse_entered"):
		if not element.mouse_entered.is_connected(_on_element_hovered):
			element.mouse_entered.connect(_on_element_hovered.bind(element))
	if element.has_signal("mouse_exited"):
		if not element.mouse_exited.is_connected(_on_element_hover_exited):
			element.mouse_exited.connect(_on_element_hover_exited.bind(element))


func _cleanup_focus_tracking():
	"""Clean up focus tracking connections"""
	for element in tracked_elements:
		if not is_instance_valid(element):
			continue

		_disconnect_element_signals(element)


func _disconnect_element_signals(element: Control):
	"""Disconnect signals for a single element"""
	if not is_instance_valid(element):
		return

	# Safely disconnect signals
	if element.has_signal("focus_entered") and element.focus_entered.is_connected(_on_element_focused):
		element.focus_entered.disconnect(_on_element_focused)
	if element.has_signal("focus_exited") and element.focus_exited.is_connected(_on_element_focus_exited):
		element.focus_exited.disconnect(_on_element_focus_exited)
	if element.has_signal("mouse_entered") and element.mouse_entered.is_connected(_on_element_hovered):
		element.mouse_entered.disconnect(_on_element_hovered)
	if element.has_signal("mouse_exited") and element.mouse_exited.is_connected(_on_element_hover_exited):
		element.mouse_exited.disconnect(_on_element_hover_exited)


func _on_element_focused(element: Control):
	if is_instance_valid(element):
		focused_element = element
		_update_debug_display()


func _on_element_focus_exited(element: Control):
	if is_instance_valid(element) and focused_element == element:
		focused_element = null
		_update_debug_display()


func _on_element_hovered(element: Control):
	if is_instance_valid(element):
		hovered_element = element
		_update_debug_display()


func _on_element_hover_exited(element: Control):
	if is_instance_valid(element) and hovered_element == element:
		hovered_element = null
		_update_debug_display()


func _is_debugger_element(node: Node) -> bool:
	"""Check if a node is part of the debugger UI"""
	if not is_instance_valid(node):
		return false

	var parent = node
	while parent:
		if parent == self or parent == debug_panel or parent == info_panel:
			return true
		parent = parent.get_parent()
	return false


func _should_show_element(element: Control) -> bool:
	"""Determine if an element should be shown based on current filters"""
	if not is_instance_valid(element):
		return false

	# Check visibility filter
	if show_only_visible and not element.visible:
		return false

	# Check if element is in an active canvas layer
	if show_only_visible:
		var canvas_layer = _find_canvas_layer(element)
		if canvas_layer and not canvas_layer.visible:
			return false

	# Check focus filter
	if show_only_focused:
		return element == focused_element or element == hovered_element

	return true


func _create_all_debug_overlays():
	"""Create debug overlays for all tracked elements"""
	_cleanup_invalid_elements()
	_create_overlays_for_new_elements(0)


func _create_overlays_for_new_elements(start_index: int):
	"""Create overlays for newly discovered elements"""
	for i in range(start_index, tracked_elements.size()):
		var element = tracked_elements[i]
		if is_instance_valid(element):
			_create_debug_overlay(element)


func _create_debug_overlay(element: Control):
	"""Create a debug overlay for a single element"""
	if not is_instance_valid(element):
		return

	# Check if overlay already exists
	for overlay in debug_overlays:
		if is_instance_valid(overlay):
			var tracked = overlay.get_meta("tracked_element", null)
			if tracked == element:
				return

	var overlay = ColorRect.new()
	overlay.name = "DebugOverlay_" + element.name
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.color = Color.TRANSPARENT
	debug_panel.add_child(overlay)

	debug_overlays.append(overlay)
	overlay.set_meta("tracked_element", element)
	overlay.draw.connect(_draw_overlay.bind(overlay))


func _clear_debug_overlays():
	"""Clear all debug overlays"""
	for overlay in debug_overlays:
		if is_instance_valid(overlay):
			overlay.queue_free()
	debug_overlays.clear()


func _update_debug_display():
	"""Update all debug displays"""
	if not is_active:
		return

	_cleanup_invalid_elements()
	_update_bounds_display()
	_update_info_display()


func _update_bounds_display():
	"""Update bounding box displays"""
	for overlay in debug_overlays:
		if not is_instance_valid(overlay):
			continue

		var element = overlay.get_meta("tracked_element", null)
		if not _should_show_element(element):
			overlay.visible = false
			continue

		overlay.visible = show_bounds

		if show_bounds and is_instance_valid(element):
			var global_rect = element.get_global_rect()
			overlay.position = global_rect.position
			overlay.size = global_rect.size
			overlay.queue_redraw()


func _update_info_display():
	"""Update the info panel"""
	if not show_info:
		info_panel.visible = false
		return

	info_panel.visible = true

	var info_text = "[b][color=cyan]Controls[/color][/b]\n"
	info_text += "[color=yellow]F3/`:[/color] Toggle  [color=yellow]F4:[/color] Bounds  [color=yellow]F5:[/color] Info  [color=yellow]F8:[/color] Refresh  [color=yellow]F9:[/color] Reset Pos [color=yellow]F10:[/color] Snapping Guides\n"
	info_text += "[color=yellow]F6:[/color] Visible Only (%s)  [color=yellow]F7:[/color] Focused Only (%s)\n\n" % ["ON" if show_only_visible else "OFF", "ON" if show_only_focused else "OFF"]

	# Filter elements to show
	var elements_to_show: Array[Control] = []
	for element in tracked_elements:
		if is_instance_valid(element) and _should_show_element(element):
			elements_to_show.append(element)

	info_text += "[b]Showing: %d / %d elements[/b]\n" % [elements_to_show.size(), tracked_elements.size()]
	info_text += "[color=gray]Auto-discovering new elements every %.1fs[/color]\n\n" % discovery_interval

	# Show focused/hovered element first
	if is_instance_valid(focused_element) and _should_show_element(focused_element):
		info_text += "[color=lime][b]FOCUSED: %s[/b][/color]\n" % focused_element.name
		info_text += _get_element_info(focused_element)
		info_text += "\n"

	if is_instance_valid(hovered_element) and hovered_element != focused_element and _should_show_element(hovered_element):
		info_text += "[color=orange][b]HOVERED: %s[/b][/color]\n" % hovered_element.name
		info_text += _get_element_info(hovered_element)
		info_text += "\n"

	# Show other elements (limited to prevent overflow)
	var shown_count = 0
	var max_show = 15

	for element in elements_to_show:
		if not is_instance_valid(element):
			continue
		if element == focused_element or element == hovered_element:
			continue

		shown_count += 1
		if shown_count > max_show:
			info_text += "[color=gray]... and %d more elements (use filters to narrow down)[/color]\n" % (elements_to_show.size() - shown_count + 1)
			break

		info_text += "[color=white][b]%s[/b][/color]\n" % element.name
		info_text += _get_element_info(element)
		info_text += "\n"

	info_label.text = info_text


func _get_element_info(element: Control) -> String:
	"""Get formatted info string for an element"""
	if not is_instance_valid(element):
		return "  [Invalid element]"

	var canvas_layer = _find_canvas_layer(element)
	var layer_num = canvas_layer.layer if canvas_layer else 0

	var info = ""
	info += "  Position: %s\n" % str(element.position)
	info += "  Size: %s\n" % str(element.size)
	info += "  Global Pos: %s\n" % str(element.global_position)
	info += "  Canvas Layer: %d\n" % layer_num
	info += "  Z-Index: %d\n" % element.z_index
	info += "  Visible: %s\n" % str(element.visible)
	info += "  Mouse Filter: %s\n" % _get_mouse_filter_name(element.mouse_filter)
	info += "  Has Focus: %s\n" % str(element.has_focus())
	info += "  Class: %s" % element.get_class()

	return info


func _find_canvas_layer(element: Control) -> CanvasLayer:
	"""Find the CanvasLayer that contains this element"""
	if not is_instance_valid(element):
		return null

	var parent = element.get_parent()
	while parent:
		if parent is CanvasLayer:
			return parent
		parent = parent.get_parent()
	return null


func _get_mouse_filter_name(filter: Control.MouseFilter) -> String:
	"""Get readable name for mouse filter"""
	match filter:
		Control.MOUSE_FILTER_STOP:
			return "STOP"
		Control.MOUSE_FILTER_PASS:
			return "PASS"
		Control.MOUSE_FILTER_IGNORE:
			return "IGNORE"
		_:
			return "UNKNOWN"


func _draw_overlay(overlay: Control):
	"""Draw debug overlay graphics"""
	if not show_bounds or not is_instance_valid(overlay):
		return

	var element = overlay.get_meta("tracked_element", null)
	if not is_instance_valid(element) or not _should_show_element(element):
		return

	# Different colors for different states
	var draw_color = bounds_color
	if element == focused_element:
		draw_color = Color.LIME
	elif element == hovered_element:
		draw_color = Color.ORANGE

	# Draw bounding box
	var rect = Rect2(Vector2.ZERO, overlay.size)
	overlay.draw_rect(rect, draw_color, false, bounds_width)

	# Draw corner markers
	var corner_size = 0.0
	overlay.draw_rect(Rect2(0, 0, corner_size, corner_size), draw_color)
	overlay.draw_rect(Rect2(rect.size.x - corner_size, 0, corner_size, corner_size), draw_color)
	overlay.draw_rect(Rect2(0, rect.size.y - corner_size, corner_size, corner_size), draw_color)
	overlay.draw_rect(Rect2(rect.size.x - corner_size, rect.size.y - corner_size, corner_size, corner_size), draw_color)

	# Draw element name
	var font = ThemeDB.fallback_font
	var font_size = 12
	var text = element.name
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_pos = Vector2(5, text_size.y + 5)

	# Draw text background
	var text_bg_rect = Rect2(text_pos - Vector2(2, text_size.y), text_size + Vector2(4, 2))
	overlay.draw_rect(text_bg_rect, Color(0, 0, 0, 0.8))

	# Draw text
	overlay.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, draw_color)


func _process(_delta):
	"""Update debug display each frame"""
	if is_active:
		_update_debug_display()
