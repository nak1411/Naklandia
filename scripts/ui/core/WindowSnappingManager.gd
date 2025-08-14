# WindowSnappingManager.gd - Complete version with mouse release snapping
extends Node

# Signals
signal window_snapped(window: Window_Base, snap_type: String, target_pos: Vector2)
signal window_resize_snapped(window: Window_Base, snap_type: String, final_size: Vector2, final_position: Vector2)

# Snap distance threshold (pixels)
@export var snap_distance: float = 10.0
@export var preview_distance: float = 10.0 # Show indicators when closer than this
@export var snap_to_windows: bool = true
@export var snap_to_edges: bool = true
@export var show_snap_guides: bool = true
@export var show_debug_lines: bool = false # Debug option
@export var show_padding_lines: bool = false # Debug option for padding lines
@export var use_edge_glow: bool = true # Edge glow option
@export var edge_padding: float = 5.0 # Padding for screen edge snapping
@export var window_edge_padding: float = 5.0 # Padding for window edge-to-edge snapping
@export var window_align_padding: float = 0.0 # Padding for window edge alignment
@export var window_indicator_offset: float = -5.0 # Distance outside window edges
@export var screen_indicator_offset: float = edge_padding # Distance outside screen edges

# Reference to UI manager
var ui_manager: UIManager

var resizing_window: Window_Base
var current_resize_mode: Window_Base.ResizeMode
var current_resize_preview: Dictionary = {}

# Debug line guides (old system)
var snap_guides: Array[Line2D] = []
var guides_container: Control

# Edge glow system (new system)
var edge_glow_container: Control
var active_edge_glows: Array[Control] = []
var active_snap_indicators: Array[Node] = []

# Currently dragging window
var dragging_window: Window_Base

# Snap targets cache
var snap_targets: Array[Dictionary] = []

# Snap preview info (shown during drag, applied on release)
var current_snap_preview: Dictionary = {}


func _ready():
	# Find UI manager
	ui_manager = get_node("/root/UIManager") if has_node("/root/UIManager") else null

	# Create visual systems
	_setup_snap_guides()
	_setup_edge_glow_system()


func _setup_edge_glow_system():
	"""Create the edge glow visual system"""
	edge_glow_container = Control.new()
	edge_glow_container.name = "EdgeGlowContainer"
	edge_glow_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edge_glow_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge_glow_container.z_index = 999 # Just below debug lines

	# Add to same location as guides
	if ui_manager and ui_manager.pause_canvas:
		ui_manager.pause_canvas.add_child(edge_glow_container)
	else:
		var scene_root = get_tree().current_scene
		if scene_root:
			scene_root.add_child(edge_glow_container)
		else:
			get_viewport().add_child(edge_glow_container)


func _setup_snap_guides():
	"""Create debug line guide system"""
	guides_container = Control.new()
	guides_container.name = "SnapGuides"
	guides_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	guides_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guides_container.z_index = 1000
	guides_container.visible = show_debug_lines # Only show if debug enabled

	# Add to highest UI layer
	if ui_manager and ui_manager.pause_canvas:
		ui_manager.pause_canvas.add_child(guides_container)
	else:
		var scene_root = get_tree().current_scene
		if scene_root:
			scene_root.add_child(guides_container)
		else:
			get_viewport().add_child(guides_container)


func start_window_drag(window: Window_Base):
	"""Called when window drag starts"""
	dragging_window = window
	current_snap_preview = {}
	_cache_snap_targets()
	_show_snap_guides()


func update_window_drag(window: Window_Base, new_position: Vector2) -> Vector2:
	"""Update window position during drag - only shows preview, no snapping"""
	if window != dragging_window:
		return new_position

	# Only show preview indicators, don't actually snap during drag
	var preview_info_combined = {}

	# Check for preview indicators (shown before snapping)
	if snap_to_edges:
		var edge_preview = _check_edge_preview(window, new_position)
		if edge_preview.has("preview"):
			preview_info_combined.merge(edge_preview)

	if snap_to_windows:
		var window_preview = _check_window_preview(window, new_position)
		if window_preview.has("preview"):
			preview_info_combined.merge(window_preview)

	# Store the preview info for potential snapping on release
	current_snap_preview = preview_info_combined

	# Show indicators
	_update_snap_guides(preview_info_combined, new_position)

	# Return original position - no snapping during drag
	return new_position


func end_window_drag(window: Window_Base):
	"""Called when window drag ends - apply snapping here"""
	if window != dragging_window:
		return

	# Apply snapping based on current preview
	if not current_snap_preview.is_empty():
		var snapped_position = _calculate_snap_position(window, window.position)
		if snapped_position != window.position:
			window.position = snapped_position
			window_snapped.emit(window, current_snap_preview.get("type", ""), snapped_position)

	# Clean up
	dragging_window = null
	current_snap_preview = {}
	_hide_snap_guides()
	snap_targets.clear()


func _calculate_snap_position(window: Window_Base, current_pos: Vector2) -> Vector2:
	"""Calculate the final snap position based on current preview"""
	var final_pos = current_pos

	# Apply edge snapping
	if current_snap_preview.get("type") == "edge":
		var edge_snap = _check_edge_snapping(window, current_pos)
		if edge_snap.has("position"):
			final_pos = edge_snap.position

	# Apply window snapping
	elif current_snap_preview.get("type") == "window":
		var window_snap = _check_multi_axis_window_snapping(window, current_pos)
		if window_snap.has("position"):
			final_pos = window_snap.position

	return final_pos


func _cache_snap_targets():
	"""Cache all potential snap targets"""
	snap_targets.clear()

	# Get screen bounds
	var screen_size = get_viewport().get_visible_rect().size
	snap_targets.append({"type": "screen_edge", "rect": Rect2(Vector2.ZERO, screen_size)})

	# Try multiple ways to find windows
	var all_windows: Array[Window_Base] = []

	# Method 1: UIManager active windows
	if ui_manager and ui_manager.has_method("get_all_windows"):
		var ui_windows = ui_manager.get_all_windows()
		for window in ui_windows:
			if is_instance_valid(window) and window != dragging_window:
				all_windows.append(window)

	# Method 2: Search the scene tree for Window_Base nodes
	var scene_root = get_tree().current_scene
	if scene_root:
		var found_windows = _find_window_base_nodes(scene_root)
		for window in found_windows:
			if is_instance_valid(window) and window != dragging_window and window not in all_windows:
				all_windows.append(window)

	# Method 3: Check specific canvas layers
	var canvas_layers = ["InventoryCanvas", "MenuUICanvas", "GameUICanvas"]
	for layer_name in canvas_layers:
		var layer = get_node_or_null("/root/" + layer_name)
		if not layer and scene_root:
			layer = scene_root.get_node_or_null(layer_name)

		if layer:
			var layer_windows = _find_window_base_nodes(layer)
			for window in layer_windows:
				if is_instance_valid(window) and window != dragging_window and window not in all_windows:
					all_windows.append(window)

	# Add all found windows as snap targets
	for window in all_windows:
		if window.visible:
			snap_targets.append({"type": "window", "window": window, "rect": Rect2(window.position, window.size)})


func _find_window_base_nodes(node: Node) -> Array[Window_Base]:
	"""Recursively find all Window_Base nodes in a tree"""
	var windows: Array[Window_Base] = []

	if node is Window_Base:
		windows.append(node)

	for child in node.get_children():
		windows.append_array(_find_window_base_nodes(child))

	return windows


func _check_edge_snapping(window: Window_Base, pos: Vector2) -> Dictionary:
	"""Check for snapping to screen edges with padding"""
	var screen_size = get_viewport().get_visible_rect().size
	var window_size = window.size
	var snap_info = {}

	var snapped_x = pos.x
	var snapped_y = pos.y

	# Left edge snapping with padding
	if abs(pos.x - edge_padding) <= snap_distance:
		snapped_x = edge_padding
		snap_info["left_edge"] = true

	# Right edge snapping with padding
	elif abs(pos.x + window_size.x - (screen_size.x - edge_padding)) <= snap_distance:
		snapped_x = screen_size.x - window_size.x - edge_padding
		snap_info["right_edge"] = true

	# Top edge snapping with padding
	if abs(pos.y - edge_padding) <= snap_distance:
		snapped_y = edge_padding
		snap_info["top_edge"] = true

	# Bottom edge snapping with padding
	elif abs(pos.y + window_size.y - (screen_size.y - edge_padding)) <= snap_distance:
		snapped_y = screen_size.y - window_size.y - edge_padding
		snap_info["bottom_edge"] = true

	if snap_info.size() > 0:
		snap_info["type"] = "edge"
		snap_info["position"] = Vector2(snapped_x, snapped_y)

	return snap_info


func _check_edge_preview(window: Window_Base, pos: Vector2) -> Dictionary:
	"""Check for edge snapping preview with padding"""
	var screen_size = get_viewport().get_visible_rect().size
	var window_size = window.size
	var preview_info = {}

	# Left edge preview with padding
	if abs(pos.x - edge_padding) <= preview_distance:
		preview_info["left_edge"] = true

	# Right edge preview with padding
	elif abs(pos.x + window_size.x - (screen_size.x - edge_padding)) <= preview_distance:
		preview_info["right_edge"] = true

	# Top edge preview with padding
	if abs(pos.y - edge_padding) <= preview_distance:
		preview_info["top_edge"] = true

	# Bottom edge preview with padding
	elif abs(pos.y + window_size.y - (screen_size.y - edge_padding)) <= preview_distance:
		preview_info["bottom_edge"] = true

	if preview_info.size() > 0:
		preview_info["type"] = "edge"
		preview_info["preview"] = true

	return preview_info


func _check_multi_axis_window_snapping(window: Window_Base, pos: Vector2) -> Dictionary:
	"""Check for window snapping that can work on both X and Y axes independently"""
	var window_size = window.size
	var window_rect = Rect2(pos, window_size)
	var snap_info = {}
	var final_pos = pos

	var best_x_snap = {}
	var best_y_snap = {}
	var min_x_distance = snap_distance + 1
	var min_y_distance = snap_distance + 1

	# Check all window targets for the best X and Y snaps independently
	for target in snap_targets:
		if target.type != "window":
			continue

		var target_rect = target.rect

		# Check X-axis snaps (left/right edges and alignment)
		var x_snaps = _get_x_axis_snaps(window_rect, target_rect)
		for x_snap in x_snaps:
			if x_snap.distance < min_x_distance:
				min_x_distance = x_snap.distance
				best_x_snap = x_snap
				best_x_snap["target_window"] = target.window

		# Check Y-axis snaps (top/bottom edges and alignment)
		var y_snaps = _get_y_axis_snaps(window_rect, target_rect)
		for y_snap in y_snaps:
			if y_snap.distance < min_y_distance:
				min_y_distance = y_snap.distance
				best_y_snap = y_snap
				best_y_snap["target_window"] = target.window

	# Apply the best snaps
	if best_x_snap.has("new_x") and min_x_distance <= snap_distance:
		final_pos.x = best_x_snap.new_x
		snap_info["x_snap_type"] = best_x_snap.type
		snap_info["x_target_window"] = best_x_snap.target_window

	if best_y_snap.has("new_y") and min_y_distance <= snap_distance:
		final_pos.y = best_y_snap.new_y
		snap_info["y_snap_type"] = best_y_snap.type
		snap_info["y_target_window"] = best_y_snap.target_window

	if snap_info.size() > 0:
		snap_info["type"] = "window"
		snap_info["position"] = final_pos

	return snap_info


func _check_window_preview(window: Window_Base, pos: Vector2) -> Dictionary:
	"""Check for window snapping preview"""
	var window_size = window.size
	var window_rect = Rect2(pos, window_size)
	var preview_info = {}

	var best_x_preview = {}
	var best_y_preview = {}
	var min_x_distance = preview_distance + 1
	var min_y_distance = preview_distance + 1

	# Check all window targets for preview
	for target in snap_targets:
		if target.type != "window":
			continue

		var target_rect = target.rect

		# Check X-axis previews
		var x_snaps = _get_x_axis_snaps(window_rect, target_rect)
		for x_snap in x_snaps:
			if x_snap.distance < min_x_distance and x_snap.distance <= preview_distance:
				min_x_distance = x_snap.distance
				best_x_preview = x_snap
				best_x_preview["target_window"] = target.window

		# Check Y-axis previews
		var y_snaps = _get_y_axis_snaps(window_rect, target_rect)
		for y_snap in y_snaps:
			if y_snap.distance < min_y_distance and y_snap.distance <= preview_distance:
				min_y_distance = y_snap.distance
				best_y_preview = y_snap
				best_y_preview["target_window"] = target.window

	# Set preview info
	if best_x_preview.has("type"):
		preview_info["x_snap_type"] = best_x_preview.type
		preview_info["x_target_window"] = best_x_preview.target_window

	if best_y_preview.has("type"):
		preview_info["y_snap_type"] = best_y_preview.type
		preview_info["y_target_window"] = best_y_preview.target_window

	if preview_info.size() > 0:
		preview_info["type"] = "window"
		preview_info["preview"] = true

	return preview_info


func _get_x_axis_snaps(window_rect: Rect2, target_rect: Rect2) -> Array[Dictionary]:
	"""Get all possible X-axis snaps between windows with padding"""
	var snaps: Array[Dictionary] = []

	# Left edge to right edge of target (edge-to-edge with padding)
	var left_to_right_pos = target_rect.end.x + window_edge_padding
	snaps.append({"distance": abs(window_rect.position.x - left_to_right_pos), "new_x": left_to_right_pos, "type": "left_to_right"})

	# Right edge to left edge of target (edge-to-edge with padding)
	var right_to_left_pos = target_rect.position.x - window_rect.size.x - window_edge_padding
	snaps.append({"distance": abs(window_rect.end.x - (target_rect.position.x - window_edge_padding)), "new_x": right_to_left_pos, "type": "right_to_left"})

	# Align left edges (alignment with padding)
	var align_left_pos = target_rect.position.x + window_align_padding
	snaps.append({"distance": abs(window_rect.position.x - align_left_pos), "new_x": align_left_pos, "type": "align_left"})

	# Align right edges (alignment with padding)
	var align_right_pos = target_rect.end.x - window_rect.size.x - window_align_padding
	snaps.append({"distance": abs(window_rect.end.x - (target_rect.end.x - window_align_padding)), "new_x": align_right_pos, "type": "align_right"})

	return snaps


func _get_y_axis_snaps(window_rect: Rect2, target_rect: Rect2) -> Array[Dictionary]:
	"""Get all possible Y-axis snaps between windows with padding"""
	var snaps: Array[Dictionary] = []

	# Top edge to bottom edge of target (edge-to-edge with padding)
	var top_to_bottom_pos = target_rect.end.y + window_edge_padding
	snaps.append({"distance": abs(window_rect.position.y - top_to_bottom_pos), "new_y": top_to_bottom_pos, "type": "top_to_bottom"})

	# Bottom edge to top edge of target (edge-to-edge with padding)
	var bottom_to_top_pos = target_rect.position.y - window_rect.size.y - window_edge_padding
	snaps.append({"distance": abs(window_rect.end.y - (target_rect.position.y - window_edge_padding)), "new_y": bottom_to_top_pos, "type": "bottom_to_top"})

	# Align top edges (alignment with padding)
	var align_top_pos = target_rect.position.y + window_align_padding
	snaps.append({"distance": abs(window_rect.position.y - align_top_pos), "new_y": align_top_pos, "type": "align_top"})

	# Align bottom edges (alignment with padding)
	var align_bottom_pos = target_rect.end.y - window_rect.size.y - window_align_padding
	snaps.append({"distance": abs(window_rect.end.y - (target_rect.end.y - window_align_padding)), "new_y": align_bottom_pos, "type": "align_bottom"})

	return snaps


func _update_snap_guides(snap_info: Dictionary, window_pos: Vector2):
	"""Update visual feedback with window position"""
	# Clear existing visuals
	_clear_debug_guides()
	_clear_edge_glows()

	if snap_info.is_empty():
		return

	# Show debug lines if enabled
	if show_debug_lines and guides_container:
		guides_container.visible = true
		_create_debug_guides(snap_info)

	# Show edge indicators if enabled
	if use_edge_glow and edge_glow_container:
		edge_glow_container.visible = true
		_create_edge_indicators(snap_info, window_pos)


func _clear_debug_guides():
	"""Clear debug line guides"""
	for guide in snap_guides:
		if is_instance_valid(guide):
			guide.queue_free()
	snap_guides.clear()


func _clear_edge_glows():
	"""Clear edge glow effects and indicators"""
	for glow in active_edge_glows:
		if is_instance_valid(glow):
			# Kill the tween to stop infinite animation
			var tween = glow.get_meta("glow_tween", null)
			if tween and is_instance_valid(tween):
				tween.kill()
			glow.queue_free()
	active_edge_glows.clear()

	# Clear snap indicators
	for indicator in active_snap_indicators:
		if is_instance_valid(indicator):
			# Only Controls have indicator tweens, Line2D objects don't
			if indicator is Control:
				var tween = indicator.get_meta("indicator_tween", null)
				if tween and is_instance_valid(tween):
					tween.kill()
			indicator.queue_free()
	active_snap_indicators.clear()


func _create_debug_guides(snap_info: Dictionary):
	"""Create debug line guides (old system)"""
	match snap_info.get("type", ""):
		"edge":
			_create_edge_guides(snap_info)
		"window":
			_create_window_guides(snap_info)


func _create_edge_indicators(snap_info: Dictionary, window_pos: Vector2):
	"""Create edge indicators based on dragging window position"""
	match snap_info.get("type", ""):
		"edge":
			_create_screen_edge_indicators(snap_info, window_pos)
		"window":
			_create_window_edge_indicators(snap_info, window_pos)


# DEBUG LINE GUIDE FUNCTIONS (for debug mode)
func _create_edge_guides(snap_info: Dictionary):
	"""Create visual guides for edge snapping"""
	var screen_size = get_viewport().get_visible_rect().size

	if snap_info.has("left_edge") or snap_info.has("right_edge"):
		var guide = _create_guide_line(Color.CYAN)
		var x = 0 if snap_info.has("left_edge") else screen_size.x
		guide.add_point(Vector2(x, 0))
		guide.add_point(Vector2(x, screen_size.y))

	if snap_info.has("top_edge") or snap_info.has("bottom_edge"):
		var guide = _create_guide_line(Color.CYAN)
		var y = 0 if snap_info.has("top_edge") else screen_size.y
		guide.add_point(Vector2(0, y))
		guide.add_point(Vector2(screen_size.x, y))


func _create_window_guides(snap_info: Dictionary):
	"""Create visual guides for window snapping - supports multi-axis snapping"""
	# Handle X-axis snap
	if snap_info.has("x_snap_type") and snap_info.has("x_target_window"):
		var x_target_window = snap_info.x_target_window
		if is_instance_valid(x_target_window):
			_create_x_axis_guide(snap_info.x_snap_type, x_target_window)

	# Handle Y-axis snap
	if snap_info.has("y_snap_type") and snap_info.has("y_target_window"):
		var y_target_window = snap_info.y_target_window
		if is_instance_valid(y_target_window):
			_create_y_axis_guide(snap_info.y_snap_type, y_target_window)

	# Handle legacy single-axis snapping (fallback)
	if snap_info.has("target_window") and snap_info.has("snap_type"):
		var target_window = snap_info.target_window
		var snap_type = snap_info.snap_type
		if is_instance_valid(target_window):
			_create_legacy_window_guide(snap_type, target_window)


func _create_x_axis_guide(snap_type: String, target_window: Window_Base):
	"""Create guide for X-axis snapping"""
	var target_rect = Rect2(target_window.position, target_window.size)
	var edge_color = Color.CYAN
	var align_color = Color.YELLOW

	match snap_type:
		"left_to_right":
			var guide = _create_guide_line(edge_color)
			guide.add_point(Vector2(target_rect.end.x, target_rect.position.y))
			guide.add_point(Vector2(target_rect.end.x, target_rect.end.y))

		"right_to_left":
			var guide = _create_guide_line(edge_color)
			guide.add_point(Vector2(target_rect.position.x, target_rect.position.y))
			guide.add_point(Vector2(target_rect.position.x, target_rect.end.y))

		"align_left":
			var guide = _create_guide_line(align_color)
			var screen_height = get_viewport().get_visible_rect().size.y
			guide.add_point(Vector2(target_rect.position.x, 0))
			guide.add_point(Vector2(target_rect.position.x, screen_height))

		"align_right":
			var guide = _create_guide_line(align_color)
			var screen_height = get_viewport().get_visible_rect().size.y
			guide.add_point(Vector2(target_rect.end.x, 0))
			guide.add_point(Vector2(target_rect.end.x, screen_height))


func _create_y_axis_guide(snap_type: String, target_window: Window_Base):
	"""Create guide for Y-axis snapping"""
	var target_rect = Rect2(target_window.position, target_window.size)
	var edge_color = Color.CYAN
	var align_color = Color.YELLOW

	match snap_type:
		"top_to_bottom":
			var guide = _create_guide_line(edge_color)
			guide.add_point(Vector2(target_rect.position.x, target_rect.end.y))
			guide.add_point(Vector2(target_rect.end.x, target_rect.end.y))

		"bottom_to_top":
			var guide = _create_guide_line(edge_color)
			guide.add_point(Vector2(target_rect.position.x, target_rect.position.y))
			guide.add_point(Vector2(target_rect.end.x, target_rect.position.y))

		"align_top":
			var guide = _create_guide_line(align_color)
			var screen_width = get_viewport().get_visible_rect().size.x
			guide.add_point(Vector2(0, target_rect.position.y))
			guide.add_point(Vector2(screen_width, target_rect.position.y))

		"align_bottom":
			var guide = _create_guide_line(align_color)
			var screen_width = get_viewport().get_visible_rect().size.x
			guide.add_point(Vector2(0, target_rect.end.y))
			guide.add_point(Vector2(screen_width, target_rect.end.y))


func _create_legacy_window_guide(snap_type: String, target_window: Window_Base):
	"""Create guide for legacy single-axis snapping (fallback)"""
	if "left" in snap_type or "right" in snap_type:
		_create_x_axis_guide(snap_type, target_window)
	else:
		_create_y_axis_guide(snap_type, target_window)


func _create_guide_line(color: Color = Color.CYAN) -> Line2D:
	"""Create a snap guide line"""
	var guide = Line2D.new()
	guide.width = 2.0
	guide.default_color = color
	guide.modulate.a = 0.8
	guide.z_index = 1000
	guides_container.add_child(guide)
	snap_guides.append(guide)
	return guide


# EDGE INDICATOR FUNCTIONS (for elegant visual feedback)
func _create_screen_edge_indicators(snap_info: Dictionary, window_pos: Vector2):
	"""Create indicators for screen edge snapping with optional padding visualization"""
	var screen_size = get_viewport().get_visible_rect().size
	var window_size = dragging_window.size if dragging_window else Vector2(100, 100)
	var window_center = window_pos + window_size / 2
	var glow_color = Color.CYAN

	if snap_info.has("left_edge"):
		# Show indicator at the padded left edge
		var clamped_y = clampf(window_center.y, 12, screen_size.y - 12)
		var indicator_x = edge_padding - screen_indicator_offset
		_create_screen_edge_indicator(Vector2(indicator_x, clamped_y), "right", glow_color)

		# Show padding line only in debug mode
		if show_padding_lines and edge_padding > 0:
			_create_padding_line(Vector2(edge_padding, 0), Vector2(edge_padding, screen_size.y), glow_color)

	if snap_info.has("right_edge"):
		# Show indicator at the padded right edge
		var clamped_y = clampf(window_center.y, 12, screen_size.y - 12)
		var indicator_x = screen_size.x - edge_padding + screen_indicator_offset
		_create_screen_edge_indicator(Vector2(indicator_x, clamped_y), "left", glow_color)

		# Show padding line only in debug mode
		if show_padding_lines and edge_padding > 0:
			_create_padding_line(Vector2(screen_size.x - edge_padding, 0), Vector2(screen_size.x - edge_padding, screen_size.y), glow_color)

	if snap_info.has("top_edge"):
		# Show indicator at the padded top edge
		var clamped_x = clampf(window_center.x, 12, screen_size.x - 12)
		var indicator_y = edge_padding - screen_indicator_offset
		_create_screen_edge_indicator(Vector2(clamped_x, indicator_y), "down", glow_color)

		# Show padding line only in debug mode
		if show_padding_lines and edge_padding > 0:
			_create_padding_line(Vector2(0, edge_padding), Vector2(screen_size.x, edge_padding), glow_color)

	if snap_info.has("bottom_edge"):
		# Show indicator at the padded bottom edge
		var clamped_x = clampf(window_center.x, 12, screen_size.x - 12)
		var indicator_y = screen_size.y - edge_padding + screen_indicator_offset
		_create_screen_edge_indicator(Vector2(clamped_x, indicator_y), "up", glow_color)

		# Show padding line only in debug mode
		if show_padding_lines and edge_padding > 0:
			_create_padding_line(Vector2(0, screen_size.y - edge_padding), Vector2(screen_size.x, screen_size.y - edge_padding), glow_color)


func _create_window_edge_indicators(snap_info: Dictionary, window_pos: Vector2):
	"""Create indicators for window edge snapping based on window center"""
	var window_size = dragging_window.size if dragging_window else Vector2(100, 100)
	var window_center = window_pos + window_size / 2

	# Handle X-axis snaps
	if snap_info.has("x_snap_type") and snap_info.has("x_target_window"):
		var x_target_window = snap_info.x_target_window
		if is_instance_valid(x_target_window):
			_create_window_x_indicator(snap_info.x_snap_type, x_target_window, window_center)

	# Handle Y-axis snaps
	if snap_info.has("y_snap_type") and snap_info.has("y_target_window"):
		var y_target_window = snap_info.y_target_window
		if is_instance_valid(y_target_window):
			_create_window_y_indicator(snap_info.y_snap_type, y_target_window, window_center)

	# Handle legacy single-axis snapping
	if snap_info.has("target_window") and snap_info.has("snap_type"):
		var target_window = snap_info.target_window
		var snap_type = snap_info.snap_type
		if is_instance_valid(target_window):
			_create_legacy_window_indicator(snap_type, target_window, window_center)


func _create_window_x_indicator(snap_type: String, target_window: Window_Base, window_center: Vector2):
	"""Create indicator for X-axis window snapping with optional padding visualization"""
	var target_rect = Rect2(target_window.position, target_window.size)
	var edge_color = Color.CYAN
	var align_color = Color.YELLOW

	# Clamp indicator Y position to target window bounds
	var clamped_y = clampf(window_center.y, target_rect.position.y + 12, target_rect.end.y - 12)

	match snap_type:
		"left_to_right":
			# Arrow pointing right, positioned at padded distance
			var indicator_x = target_rect.end.x + window_edge_padding + window_indicator_offset
			_create_window_edge_indicator(Vector2(indicator_x, clamped_y), "right", edge_color)

			# Show padding line only in debug mode
			if show_padding_lines and window_edge_padding > 0:
				var line_x = target_rect.end.x + window_edge_padding
				_create_padding_line(Vector2(line_x, target_rect.position.y), Vector2(line_x, target_rect.end.y), edge_color)

		"right_to_left":
			# Arrow pointing left, positioned at padded distance
			var indicator_x = target_rect.position.x - window_edge_padding - window_indicator_offset
			_create_window_edge_indicator(Vector2(indicator_x, clamped_y), "left", edge_color)

			# Show padding line only in debug mode
			if show_padding_lines and window_edge_padding > 0:
				var line_x = target_rect.position.x - window_edge_padding
				_create_padding_line(Vector2(line_x, target_rect.position.y), Vector2(line_x, target_rect.end.y), edge_color)

		"align_left":
			# Arrow pointing right, positioned at aligned + padded position
			var indicator_x = target_rect.position.x + window_align_padding - window_indicator_offset
			_create_window_edge_indicator(Vector2(indicator_x, clamped_y), "right", align_color)

			# Show padding line only in debug mode
			if show_padding_lines and window_align_padding > 0:
				var line_x = target_rect.position.x + window_align_padding
				_create_padding_line(Vector2(line_x, target_rect.position.y), Vector2(line_x, target_rect.end.y), align_color)

		"align_right":
			# Arrow pointing left, positioned at aligned + padded position
			var indicator_x = target_rect.end.x - window_align_padding + window_indicator_offset
			_create_window_edge_indicator(Vector2(indicator_x, clamped_y), "left", align_color)

			# Show padding line only in debug mode
			if show_padding_lines and window_align_padding > 0:
				var line_x = target_rect.end.x - window_align_padding
				_create_padding_line(Vector2(line_x, target_rect.position.y), Vector2(line_x, target_rect.end.y), align_color)


func _create_window_y_indicator(snap_type: String, target_window: Window_Base, window_center: Vector2):
	"""Create indicator for Y-axis window snapping with optional padding visualization"""
	var target_rect = Rect2(target_window.position, target_window.size)
	var edge_color = Color.CYAN
	var align_color = Color.YELLOW

	# Clamp indicator X position to target window bounds
	var clamped_x = clampf(window_center.x, target_rect.position.x + 12, target_rect.end.x - 12)

	match snap_type:
		"top_to_bottom":
			# Arrow pointing down, positioned at padded distance
			var indicator_y = target_rect.end.y + window_edge_padding + window_indicator_offset
			_create_window_edge_indicator(Vector2(clamped_x, indicator_y), "down", edge_color)

			# Show padding line only in debug mode
			if show_padding_lines and window_edge_padding > 0:
				var line_y = target_rect.end.y + window_edge_padding
				_create_padding_line(Vector2(target_rect.position.x, line_y), Vector2(target_rect.end.x, line_y), edge_color)

		"bottom_to_top":
			# Arrow pointing up, positioned at padded distance
			var indicator_y = target_rect.position.y - window_edge_padding - window_indicator_offset
			_create_window_edge_indicator(Vector2(clamped_x, indicator_y), "up", edge_color)

			# Show padding line only in debug mode
			if show_padding_lines and window_edge_padding > 0:
				var line_y = target_rect.position.y - window_edge_padding
				_create_padding_line(Vector2(target_rect.position.x, line_y), Vector2(target_rect.end.x, line_y), edge_color)

		"align_top":
			# Arrow pointing down, positioned at aligned + padded position
			var indicator_y = target_rect.position.y + window_align_padding - window_indicator_offset
			_create_window_edge_indicator(Vector2(clamped_x, indicator_y), "down", align_color)

			# Show padding line only in debug mode
			if show_padding_lines and window_align_padding > 0:
				var line_y = target_rect.position.y + window_align_padding
				_create_padding_line(Vector2(target_rect.position.x, line_y), Vector2(target_rect.end.x, line_y), align_color)

		"align_bottom":
			# Arrow pointing up, positioned at aligned + padded position
			var indicator_y = target_rect.end.y - window_align_padding + window_indicator_offset
			_create_window_edge_indicator(Vector2(clamped_x, indicator_y), "up", align_color)

			# Show padding line only in debug mode
			if show_padding_lines and window_align_padding > 0:
				var line_y = target_rect.end.y - window_align_padding
				_create_padding_line(Vector2(target_rect.position.x, line_y), Vector2(target_rect.end.x, line_y), align_color)


func _create_padding_line(start_pos: Vector2, end_pos: Vector2, color: Color):
	"""Create a subtle line to show where padding will place the window"""
	var line = Line2D.new()
	line.width = 1.0
	line.default_color = color
	line.modulate.a = 0.4 # More subtle than indicators
	line.add_point(start_pos)
	line.add_point(end_pos)

	edge_glow_container.add_child(line)

	active_snap_indicators.append(line)


func _create_legacy_window_indicator(snap_type: String, target_window: Window_Base, window_center: Vector2):
	"""Create indicator for legacy single-axis snapping"""
	if "left" in snap_type or "right" in snap_type:
		_create_window_x_indicator(snap_type, target_window, window_center)
	else:
		_create_window_y_indicator(snap_type, target_window, window_center)


func _create_screen_edge_indicator(position: Vector2, direction: String, color: Color):
	"""Create a small arrow indicator for screen edges"""
	var indicator = Control.new()
	indicator.custom_minimum_size = Vector2(16, 16)
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Create the arrow shape using a Polygon2D
	var arrow = Polygon2D.new()
	arrow.color = color

	# Define arrow shapes based on direction
	match direction:
		"right":
			# Arrow pointing right (triangle)
			arrow.polygon = PackedVector2Array([Vector2(0, -6), Vector2(10, 0), Vector2(0, 6)]) # Top left  # Point  # Bottom left
			indicator.position = position - Vector2(0, 0)

		"left":
			# Arrow pointing left
			arrow.polygon = PackedVector2Array([Vector2(10, -6), Vector2(0, 0), Vector2(10, 6)]) # Top right  # Point  # Bottom right
			indicator.position = position - Vector2(10, 0)

		"down":
			# Arrow pointing down
			arrow.polygon = PackedVector2Array([Vector2(-6, 0), Vector2(0, 10), Vector2(6, 0)]) # Left  # Point  # Right
			indicator.position = position - Vector2(0, 0)

		"up":
			# Arrow pointing up
			arrow.polygon = PackedVector2Array([Vector2(-6, 10), Vector2(0, 0), Vector2(6, 10)]) # Bottom left  # Point  # Bottom right
			indicator.position = position - Vector2(0, 10)

	# Add glow effect
	arrow.modulate = color.lightened(0.2)

	indicator.add_child(arrow)
	edge_glow_container.add_child(indicator)
	active_snap_indicators.append(indicator)

	# Add subtle pulsing
	_animate_indicator_pulse(indicator)


func _create_window_edge_indicator(position: Vector2, direction: String, color: Color):
	"""Create a small arrow indicator for window edges"""
	var indicator = Control.new()
	indicator.custom_minimum_size = Vector2(12, 12)
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Create the arrow shape using a Polygon2D
	var arrow = Polygon2D.new()
	arrow.color = color

	# Define arrow shapes based on direction
	match direction:
		"right":
			arrow.polygon = PackedVector2Array([Vector2(0, -5), Vector2(8, 0), Vector2(0, 5)])
			indicator.position = position - Vector2(0, 0)

		"left":
			arrow.polygon = PackedVector2Array([Vector2(8, -5), Vector2(0, 0), Vector2(8, 5)])
			indicator.position = position - Vector2(8, 0)

		"down":
			arrow.polygon = PackedVector2Array([Vector2(-5, 0), Vector2(0, 8), Vector2(5, 0)])
			indicator.position = position - Vector2(0, 0)

		"up":
			arrow.polygon = PackedVector2Array([Vector2(-5, 8), Vector2(0, 0), Vector2(5, 8)])
			indicator.position = position - Vector2(0, 8)

	# Add subtle border
	var border = Line2D.new()
	border.width = 1.0
	border.default_color = color.lightened(0.5)
	border.add_point(Vector2.ZERO)
	arrow.add_child(border)

	indicator.add_child(arrow)
	edge_glow_container.add_child(indicator)
	active_snap_indicators.append(indicator)

	# Add subtle pulsing
	_animate_indicator_pulse(indicator)


func start_window_resize(window: Window_Base, resize_mode: Window_Base.ResizeMode):
	"""Called when window resize starts"""
	resizing_window = window
	current_resize_mode = resize_mode
	current_resize_preview = {}
	_cache_snap_targets()
	_show_snap_guides()


func update_window_resize(window: Window_Base, new_position: Vector2, new_size: Vector2, resize_mode: Window_Base.ResizeMode) -> Dictionary:
	"""Update window position/size during resize - shows preview and returns snapped values"""
	if window != resizing_window:
		return {"position": new_position, "size": new_size}

	var preview_info_combined = {}
	var snapped_position = new_position
	var snapped_size = new_size

	# Check for edge snapping during resize
	if snap_to_edges:
		var edge_snap_result = _check_resize_edge_snapping(window, new_position, new_size, resize_mode)
		if edge_snap_result.has("snap_applied"):
			preview_info_combined.merge(edge_snap_result)
			snapped_position = edge_snap_result.get("position", new_position)
			snapped_size = edge_snap_result.get("size", new_size)

	# Check for window edge snapping during resize
	if snap_to_windows:
		var window_snap_result = _check_resize_window_snapping(window, snapped_position, snapped_size, resize_mode)
		if window_snap_result.has("snap_applied"):
			preview_info_combined.merge(window_snap_result)
			snapped_position = window_snap_result.get("position", snapped_position)
			snapped_size = window_snap_result.get("size", snapped_size)

	# Store preview for visual feedback
	current_resize_preview = preview_info_combined

	# Update visual guides
	_update_resize_guides(preview_info_combined, snapped_position, snapped_size)

	return {"position": snapped_position, "size": snapped_size}


func end_window_resize(window: Window_Base):
	"""Called when window resize ends"""
	if window != resizing_window:
		return

	# Emit signal if snapping occurred
	if not current_resize_preview.is_empty():
		window_resize_snapped.emit(window, current_resize_preview.get("type", ""), window.size, window.position)

	# Clean up
	resizing_window = null
	current_resize_mode = Window_Base.ResizeMode.NONE
	current_resize_preview = {}
	_hide_snap_guides()
	snap_targets.clear()


func _check_resize_edge_snapping(window: Window_Base, pos: Vector2, window_size: Vector2, resize_mode: Window_Base.ResizeMode) -> Dictionary:
	"""Check for screen edge snapping during resize"""
	var screen_size = get_viewport().get_visible_rect().size
	var snap_info = {}
	var snapped_pos = pos
	var snapped_size = window_size

	# Only snap the edges that are being resized
	match resize_mode:
		Window_Base.ResizeMode.LEFT:
			# Snap left edge to screen left
			if abs(pos.x - edge_padding) <= snap_distance:
				var size_change = pos.x - edge_padding
				snapped_pos.x = edge_padding
				snapped_size.x += size_change
				snap_info["left_edge"] = true

		Window_Base.ResizeMode.RIGHT:
			# Snap right edge to screen right
			if abs(pos.x + window_size.x - (screen_size.x - edge_padding)) <= snap_distance:
				snapped_size.x = screen_size.x - pos.x - edge_padding
				snap_info["right_edge"] = true

		Window_Base.ResizeMode.TOP:
			# Snap top edge to screen top
			if abs(pos.y - edge_padding) <= snap_distance:
				var size_change = pos.y - edge_padding
				snapped_pos.y = edge_padding
				snapped_size.y += size_change
				snap_info["top_edge"] = true

		Window_Base.ResizeMode.BOTTOM:
			# Snap bottom edge to screen bottom
			if abs(pos.y + window_size.y - (screen_size.y - edge_padding)) <= snap_distance:
				snapped_size.y = screen_size.y - pos.y - edge_padding
				snap_info["bottom_edge"] = true

		Window_Base.ResizeMode.TOP_LEFT:
			# Check both top and left edges
			if abs(pos.x - edge_padding) <= snap_distance:
				var size_change = pos.x - edge_padding
				snapped_pos.x = edge_padding
				snapped_size.x += size_change
				snap_info["left_edge"] = true
			if abs(pos.y - edge_padding) <= snap_distance:
				var size_change = pos.y - edge_padding
				snapped_pos.y = edge_padding
				snapped_size.y += size_change
				snap_info["top_edge"] = true

		Window_Base.ResizeMode.TOP_RIGHT:
			# Check top and right edges
			if abs(pos.x + window_size.x - (screen_size.x - edge_padding)) <= snap_distance:
				snapped_size.x = screen_size.x - pos.x - edge_padding
				snap_info["right_edge"] = true
			if abs(pos.y - edge_padding) <= snap_distance:
				var size_change = pos.y - edge_padding
				snapped_pos.y = edge_padding
				snapped_size.y += size_change
				snap_info["top_edge"] = true

		Window_Base.ResizeMode.BOTTOM_LEFT:
			# Check bottom and left edges
			if abs(pos.x - edge_padding) <= snap_distance:
				var size_change = pos.x - edge_padding
				snapped_pos.x = edge_padding
				snapped_size.x += size_change
				snap_info["left_edge"] = true
			if abs(pos.y + window_size.y - (screen_size.y - edge_padding)) <= snap_distance:
				snapped_size.y = screen_size.y - pos.y - edge_padding
				snap_info["bottom_edge"] = true

		Window_Base.ResizeMode.BOTTOM_RIGHT:
			# Check bottom and right edges
			if abs(pos.x + window_size.x - (screen_size.x - edge_padding)) <= snap_distance:
				snapped_size.x = screen_size.x - pos.x - edge_padding
				snap_info["right_edge"] = true
			if abs(pos.y + window_size.y - (screen_size.y - edge_padding)) <= snap_distance:
				snapped_size.y = screen_size.y - pos.y - edge_padding
				snap_info["bottom_edge"] = true

	if snap_info.size() > 0:
		snap_info["type"] = "edge_resize"
		snap_info["position"] = snapped_pos
		snap_info["size"] = snapped_size
		snap_info["snap_applied"] = true

	return snap_info


func _check_resize_window_snapping(window: Window_Base, pos: Vector2, window_size: Vector2, resize_mode: Window_Base.ResizeMode) -> Dictionary:
	"""Check for window-to-window edge snapping AND alignment during resize"""
	var window_rect = Rect2(pos, window_size)
	var snap_info = {}
	var snapped_pos = pos
	var snapped_size = window_size
	var best_snap_distance = snap_distance + 1
	
	# Check against all window targets
	for target in snap_targets:
		if target.type != "window":
			continue
		
		var target_rect = target.rect
		
		# Check snapping based on resize mode
		match resize_mode:
			Window_Base.ResizeMode.LEFT:
				# Check both edge-to-edge snapping and alignment
				var left_snaps = _get_resize_left_edge_snaps(window_rect, target_rect, pos)
				for snap in left_snaps:
					if snap.distance <= snap_distance and snap.distance < best_snap_distance:
						snapped_pos.x = snap.new_pos_x
						snapped_size.x = snap.new_size_x
						snap_info["target_window"] = target.window
						snap_info["snap_type"] = snap.type
						best_snap_distance = snap.distance
			
			Window_Base.ResizeMode.RIGHT:
				var right_snaps = _get_resize_right_edge_snaps(window_rect, target_rect, pos)
				for snap in right_snaps:
					if snap.distance <= snap_distance and snap.distance < best_snap_distance:
						snapped_size.x = snap.new_size_x
						snap_info["target_window"] = target.window
						snap_info["snap_type"] = snap.type
						best_snap_distance = snap.distance
			
			Window_Base.ResizeMode.TOP:
				var top_snaps = _get_resize_top_edge_snaps(window_rect, target_rect, pos)
				for snap in top_snaps:
					if snap.distance <= snap_distance and snap.distance < best_snap_distance:
						snapped_pos.y = snap.new_pos_y
						snapped_size.y = snap.new_size_y
						snap_info["target_window"] = target.window
						snap_info["snap_type"] = snap.type
						best_snap_distance = snap.distance
			
			Window_Base.ResizeMode.BOTTOM:
				var bottom_snaps = _get_resize_bottom_edge_snaps(window_rect, target_rect, pos)
				for snap in bottom_snaps:
					if snap.distance <= snap_distance and snap.distance < best_snap_distance:
						snapped_size.y = snap.new_size_y
						snap_info["target_window"] = target.window
						snap_info["snap_type"] = snap.type
						best_snap_distance = snap.distance
			
			# For corner resizing, handle both axes independently
			Window_Base.ResizeMode.TOP_LEFT, Window_Base.ResizeMode.TOP_RIGHT, Window_Base.ResizeMode.BOTTOM_LEFT, Window_Base.ResizeMode.BOTTOM_RIGHT:
				# Handle X-axis snapping for corner modes
				if resize_mode in [Window_Base.ResizeMode.TOP_LEFT, Window_Base.ResizeMode.BOTTOM_LEFT]:
					var left_snaps = _get_resize_left_edge_snaps(window_rect, target_rect, pos)
					for snap in left_snaps:
						if snap.distance <= snap_distance:
							snapped_pos.x = snap.new_pos_x
							snapped_size.x = snap.new_size_x
							snap_info["target_window"] = target.window
							snap_info["x_snap_type"] = snap.type
				
				elif resize_mode in [Window_Base.ResizeMode.TOP_RIGHT, Window_Base.ResizeMode.BOTTOM_RIGHT]:
					var right_snaps = _get_resize_right_edge_snaps(window_rect, target_rect, pos)
					for snap in right_snaps:
						if snap.distance <= snap_distance:
							snapped_size.x = snap.new_size_x
							snap_info["target_window"] = target.window
							snap_info["x_snap_type"] = snap.type
				
				# Handle Y-axis snapping for corner modes
				if resize_mode in [Window_Base.ResizeMode.TOP_LEFT, Window_Base.ResizeMode.TOP_RIGHT]:
					var top_snaps = _get_resize_top_edge_snaps(window_rect, target_rect, pos)
					for snap in top_snaps:
						if snap.distance <= snap_distance:
							snapped_pos.y = snap.new_pos_y
							snapped_size.y = snap.new_size_y
							snap_info["target_window"] = target.window
							snap_info["y_snap_type"] = snap.type
				
				elif resize_mode in [Window_Base.ResizeMode.BOTTOM_LEFT, Window_Base.ResizeMode.BOTTOM_RIGHT]:
					var bottom_snaps = _get_resize_bottom_edge_snaps(window_rect, target_rect, pos)
					for snap in bottom_snaps:
						if snap.distance <= snap_distance:
							snapped_size.y = snap.new_size_y
							snap_info["target_window"] = target.window
							snap_info["y_snap_type"] = snap.type
	
	if snap_info.size() > 0:
		snap_info["type"] = "window_resize"
		snap_info["position"] = snapped_pos
		snap_info["size"] = snapped_size
		snap_info["snap_applied"] = true
	
	return snap_info

func _get_resize_left_edge_snaps(window_rect: Rect2, target_rect: Rect2, current_pos: Vector2) -> Array[Dictionary]:
	"""Get all possible left edge resize snaps - both edge-to-edge and alignment"""
	var snaps: Array[Dictionary] = []
	
	# Edge-to-edge: Left edge snaps to right edge of target
	var snap_x = target_rect.end.x + window_edge_padding
	var size_change = current_pos.x - snap_x
	var new_size_x = window_rect.size.x + size_change
	if new_size_x > 0: # Ensure positive size
		snaps.append({
			"distance": abs(current_pos.x - snap_x),
			"new_pos_x": snap_x,
			"new_size_x": new_size_x,
			"type": "left_to_right"
		})
	
	# Alignment: Left edge aligns with left edge of target
	var align_x = target_rect.position.x + window_align_padding
	size_change = current_pos.x - align_x
	new_size_x = window_rect.size.x + size_change
	if new_size_x > 0:
		snaps.append({
			"distance": abs(current_pos.x - align_x),
			"new_pos_x": align_x,
			"new_size_x": new_size_x,
			"type": "align_left"
		})
	
	# Alignment: Left edge aligns with right edge of target
	align_x = target_rect.end.x - window_align_padding
	size_change = current_pos.x - align_x
	new_size_x = window_rect.size.x + size_change
	if new_size_x > 0:
		snaps.append({
			"distance": abs(current_pos.x - align_x),
			"new_pos_x": align_x,
			"new_size_x": new_size_x,
			"type": "align_right"
		})
	
	return snaps

func _get_resize_right_edge_snaps(window_rect: Rect2, target_rect: Rect2, current_pos: Vector2) -> Array[Dictionary]:
	"""Get all possible right edge resize snaps - both edge-to-edge and alignment"""
	var snaps: Array[Dictionary] = []
	
	# Edge-to-edge: Right edge snaps to left edge of target
	var snap_x = target_rect.position.x - window_edge_padding
	var new_size_x = snap_x - current_pos.x
	if new_size_x > 0:
		snaps.append({
			"distance": abs(current_pos.x + window_rect.size.x - snap_x),
			"new_size_x": new_size_x,
			"type": "right_to_left"
		})
	
	# Alignment: Right edge aligns with left edge of target
	var align_x = target_rect.position.x + window_align_padding
	new_size_x = align_x - current_pos.x
	if new_size_x > 0:
		snaps.append({
			"distance": abs(current_pos.x + window_rect.size.x - align_x),
			"new_size_x": new_size_x,
			"type": "align_left"
		})
	
	# Alignment: Right edge aligns with right edge of target
	align_x = target_rect.end.x - window_align_padding
	new_size_x = align_x - current_pos.x
	if new_size_x > 0:
		snaps.append({
			"distance": abs(current_pos.x + window_rect.size.x - align_x),
			"new_size_x": new_size_x,
			"type": "align_right"
		})
	
	return snaps

func _get_resize_top_edge_snaps(window_rect: Rect2, target_rect: Rect2, current_pos: Vector2) -> Array[Dictionary]:
	"""Get all possible top edge resize snaps - both edge-to-edge and alignment"""
	var snaps: Array[Dictionary] = []
	
	# Edge-to-edge: Top edge snaps to bottom edge of target
	var snap_y = target_rect.end.y + window_edge_padding
	var size_change = current_pos.y - snap_y
	var new_size_y = window_rect.size.y + size_change
	if new_size_y > 0:
		snaps.append({
			"distance": abs(current_pos.y - snap_y),
			"new_pos_y": snap_y,
			"new_size_y": new_size_y,
			"type": "top_to_bottom"
		})
	
	# Alignment: Top edge aligns with top edge of target
	var align_y = target_rect.position.y + window_align_padding
	size_change = current_pos.y - align_y
	new_size_y = window_rect.size.y + size_change
	if new_size_y > 0:
		snaps.append({
			"distance": abs(current_pos.y - align_y),
			"new_pos_y": align_y,
			"new_size_y": new_size_y,
			"type": "align_top"
		})
	
	# Alignment: Top edge aligns with bottom edge of target
	align_y = target_rect.end.y - window_align_padding
	size_change = current_pos.y - align_y
	new_size_y = window_rect.size.y + size_change
	if new_size_y > 0:
		snaps.append({
			"distance": abs(current_pos.y - align_y),
			"new_pos_y": align_y,
			"new_size_y": new_size_y,
			"type": "align_bottom"
		})
	
	return snaps

func _get_resize_bottom_edge_snaps(window_rect: Rect2, target_rect: Rect2, current_pos: Vector2) -> Array[Dictionary]:
	"""Get all possible bottom edge resize snaps - both edge-to-edge and alignment"""
	var snaps: Array[Dictionary] = []
	
	# Edge-to-edge: Bottom edge snaps to top edge of target
	var snap_y = target_rect.position.y - window_edge_padding
	var new_size_y = snap_y - current_pos.y
	if new_size_y > 0:
		snaps.append({
			"distance": abs(current_pos.y + window_rect.size.y - snap_y),
			"new_size_y": new_size_y,
			"type": "bottom_to_top"
		})
	
	# Alignment: Bottom edge aligns with top edge of target
	var align_y = target_rect.position.y + window_align_padding
	new_size_y = align_y - current_pos.y
	if new_size_y > 0:
		snaps.append({
			"distance": abs(current_pos.y + window_rect.size.y - align_y),
			"new_size_y": new_size_y,
			"type": "align_top"
		})
	
	# Alignment: Bottom edge aligns with bottom edge of target
	align_y = target_rect.end.y - window_align_padding
	new_size_y = align_y - current_pos.y
	if new_size_y > 0:
		snaps.append({
			"distance": abs(current_pos.y + window_rect.size.y - align_y),
			"new_size_y": new_size_y,
			"type": "align_bottom"
		})
	
	return snaps


func _update_resize_guides(snap_info: Dictionary, window_pos: Vector2, window_size: Vector2):
	"""Update visual feedback for resize snapping"""
	# Clear existing visuals
	_hide_snap_guides()

	if not show_snap_guides or snap_info.is_empty():
		return

	# Create guides based on snap type
	if snap_info.get("type") == "edge_resize":
		_create_resize_edge_guides(snap_info, window_pos, window_size)
	elif snap_info.get("type") == "window_resize":
		_create_resize_window_guides(snap_info, window_pos, window_size)


func _create_resize_edge_guides(snap_info: Dictionary, window_pos: Vector2, window_size: Vector2):
	"""Create visual guides for edge resize snapping"""
	var screen_size = get_viewport().get_visible_rect().size
	var guide_color = Color.CYAN

	if snap_info.has("left_edge"):
		var guide = _create_guide_line(guide_color)
		guide.add_point(Vector2(edge_padding, 0))
		guide.add_point(Vector2(edge_padding, screen_size.y))

	if snap_info.has("right_edge"):
		var guide = _create_guide_line(guide_color)
		var x = screen_size.x - edge_padding
		guide.add_point(Vector2(x, 0))
		guide.add_point(Vector2(x, screen_size.y))

	if snap_info.has("top_edge"):
		var guide = _create_guide_line(guide_color)
		guide.add_point(Vector2(0, edge_padding))
		guide.add_point(Vector2(screen_size.x, edge_padding))

	if snap_info.has("bottom_edge"):
		var guide = _create_guide_line(guide_color)
		var y = screen_size.y - edge_padding
		guide.add_point(Vector2(0, y))
		guide.add_point(Vector2(screen_size.x, y))


func _create_resize_window_guides(snap_info: Dictionary, window_pos: Vector2, window_size: Vector2):
	"""Create visual guides for window resize snapping"""
	var target_window = snap_info.get("target_window")
	if not is_instance_valid(target_window):
		return
	
	var target_rect = Rect2(target_window.position, target_window.size)
	var edge_color = Color.CYAN
	var align_color = Color.YELLOW
	
	# Create guides based on snap type
	var snap_type = snap_info.get("snap_type", "")
	var x_snap_type = snap_info.get("x_snap_type", "")
	var y_snap_type = snap_info.get("y_snap_type", "")
	
	# Handle X-axis guides
	if snap_type in ["left_to_right", "right_to_left"] or x_snap_type in ["left_to_right", "right_to_left"]:
		var guide_color = edge_color
		var line_x = target_rect.end.x if "left_to_right" in snap_type + x_snap_type else target_rect.position.x
		var guide = _create_guide_line(guide_color)
		guide.add_point(Vector2(line_x, target_rect.position.y))
		guide.add_point(Vector2(line_x, target_rect.end.y))
	
	elif snap_type in ["align_left", "align_right"] or x_snap_type in ["align_left", "align_right"]:
		var guide_color = align_color
		var line_x = target_rect.position.x if "align_left" in snap_type + x_snap_type else target_rect.end.x
		var guide = _create_guide_line(guide_color)
		var screen_height = get_viewport().get_visible_rect().size.y
		guide.add_point(Vector2(line_x, 0))
		guide.add_point(Vector2(line_x, screen_height))
	
	# Handle Y-axis guides
	if snap_type in ["top_to_bottom", "bottom_to_top"] or y_snap_type in ["top_to_bottom", "bottom_to_top"]:
		var guide_color = edge_color
		var line_y = target_rect.end.y if "top_to_bottom" in snap_type + y_snap_type else target_rect.position.y
		var guide = _create_guide_line(guide_color)
		guide.add_point(Vector2(target_rect.position.x, line_y))
		guide.add_point(Vector2(target_rect.end.x, line_y))
	
	elif snap_type in ["align_top", "align_bottom"] or y_snap_type in ["align_top", "align_bottom"]:
		var guide_color = align_color
		var line_y = target_rect.position.y if "align_top" in snap_type + y_snap_type else target_rect.end.y
		var guide = _create_guide_line(guide_color)
		var screen_width = get_viewport().get_visible_rect().size.x
		guide.add_point(Vector2(0, line_y))
		guide.add_point(Vector2(screen_width, line_y))


func _animate_indicator_pulse(indicator: Control):
	"""Add a subtle pulsing animation to indicators"""
	var tween = create_tween()
	tween.set_loops(0) # Infinite loops
	tween.tween_property(indicator, "modulate:a", 0.7, 0.6)
	tween.tween_property(indicator, "modulate:a", 1.0, 0.6)

	# Store the tween reference so we can kill it later
	indicator.set_meta("indicator_tween", tween)


func _show_snap_guides():
	"""Show visual feedback systems"""
	if show_debug_lines and guides_container:
		guides_container.visible = true
	if use_edge_glow and edge_glow_container:
		edge_glow_container.visible = true


func _hide_snap_guides():
	"""Hide all visual feedback"""
	if guides_container:
		guides_container.visible = false
	if edge_glow_container:
		edge_glow_container.visible = false

	_clear_debug_guides()
	_clear_edge_glows()


# Configuration methods
func set_debug_lines_enabled(enabled: bool):
	show_debug_lines = enabled
	if guides_container:
		guides_container.visible = enabled


func set_edge_glow_enabled(enabled: bool):
	use_edge_glow = enabled


func set_window_indicator_offset(offset: float):
	window_indicator_offset = offset


func set_screen_indicator_offset(offset: float):
	screen_indicator_offset = offset


func set_snap_distance(distance: float):
	snap_distance = distance


func set_preview_distance(distance: float):
	preview_distance = distance


func set_edge_snap_enabled(enabled: bool):
	snap_to_edges = enabled


func set_window_snap_enabled(enabled: bool):
	snap_to_windows = enabled


func set_snap_guides_enabled(enabled: bool):
	show_snap_guides = enabled


func set_edge_padding(padding: float):
	edge_padding = padding


func set_window_edge_padding(padding: float):
	window_edge_padding = padding


func set_window_align_padding(padding: float):
	window_align_padding = padding


func set_padding_lines_enabled(enabled: bool):
	show_padding_lines = enabled
