extends Control

# Compass configuration
@export var compass_height: float = 60.0
@export var compass_width: float = 800.0
@export var background_color: Color = Color(0.1, 0.1, 0.1, 0.7)
@export var border_color: Color = Color(0.3, 0.3, 0.3, 0.8)
@export var border_width: int = 2
@export var tick_color: Color = Color(0.5, 0.5, 0.5, 1.0)
@export var cardinal_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var center_marker_color: Color = Color(1.0, 0.8, 0.0, 1.0)
@export var marker_icon_color: Color = Color(1.0, 0.0, 0.0, 1.0)
@export var marker_distance_threshold: float = 200.0

# References
var player: Node3D
var map_manager: Node

# Compass state
var player_rotation: float = 0.0


func _ready():
	custom_minimum_size = Vector2(compass_width, compass_height)
	_find_references()


func _find_references():
	var player_node = get_tree().get_first_node_in_group("player")
	if player_node:
		player = player_node

	var map_managers = get_tree().get_nodes_in_group("map_manager")
	if map_managers.size() > 0:
		map_manager = map_managers[0]


func _process(_delta):
	if player:
		player_rotation = player.global_rotation.y
	queue_redraw()


func _draw():
	var rect = Rect2(Vector2.ZERO, Vector2(compass_width, compass_height))

	# Draw background
	draw_rect(rect, background_color, true)

	# Draw compass elements
	_draw_compass_ticks()
	_draw_cardinal_directions()
	_draw_map_markers()
	_draw_center_marker()

	# Draw border
	draw_rect(rect, border_color, false, border_width)


func _draw_compass_ticks():
	if not player:
		return

	var center_y = compass_height / 2.0
	var pixels_per_degree = compass_width / 120.0

	var player_deg = rad_to_deg(player_rotation)
	# Add 180 to match minimap coordinate system
	var start_angle = (player_deg + 180.0) - 60.0

	for i in range(-60, 61, 5):
		var angle = start_angle + i
		var normalized_angle = fmod(angle + 360.0, 360.0)

		var x_pos = compass_width / 2.0 + (i * pixels_per_degree)

		if x_pos < 0 or x_pos > compass_width:
			continue

		var is_major = int(normalized_angle) % 45 == 0
		var tick_height = 15.0 if is_major else 8.0
		var tick_width = 2.0 if is_major else 1.0

		draw_line(Vector2(x_pos, center_y - tick_height / 2.0), Vector2(x_pos, center_y + tick_height / 2.0), tick_color, tick_width)


func _draw_cardinal_directions():
	if not player:
		return

	var center_y = compass_height / 2.0
	var pixels_per_degree = compass_width / 120.0

	var player_deg = rad_to_deg(-player_rotation)
	var cardinals = {0.0: "N", 45.0: "NE", 90.0: "E", 135.0: "SE", 180.0: "S", 225.0: "SW", 270.0: "W", 315.0: "NW"}

	for angle in cardinals.keys():
		# Add 180 to match minimap coordinate system
		var corrected_angle = fmod(angle + 180.0, 360.0)
		var relative_angle = corrected_angle - player_deg

		while relative_angle > 180.0:
			relative_angle -= 360.0
		while relative_angle < -180.0:
			relative_angle += 360.0

		if abs(relative_angle) > 60.0:
			continue

		var x_pos = compass_width / 2.0 + (relative_angle * pixels_per_degree)
		var label = cardinals[angle]

		var font_size = 18 if label.length() == 1 else 14
		var string_size = ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)

		draw_string(ThemeDB.fallback_font, Vector2(x_pos - string_size.x / 2.0, center_y - 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, cardinal_color)


func _draw_map_markers():
	if not player or not map_manager:
		return

	var map_ui = _get_map_ui()
	if not map_ui:
		return

	var markers = map_ui.map_markers if "map_markers" in map_ui else []
	if markers.is_empty():
		return

	var center_y = compass_height / 2.0
	var pixels_per_degree = compass_width / 120.0
	var player_pos = player.global_position
	var player_deg = rad_to_deg(player_rotation)

	for marker in markers:
		var marker_pos: Vector3 = marker.position
		var marker_label: String = marker.label
		var marker_col: Color = marker.get("color", marker_icon_color)

		var distance = player_pos.distance_to(marker_pos)
		if distance > marker_distance_threshold:
			continue

		var direction = marker_pos - player_pos
		var angle_to_marker = rad_to_deg(atan2(direction.x, direction.z))

		# Add 180 to match minimap coordinate system
		var corrected_angle = fmod(angle_to_marker + 180.0, 360.0)
		var relative_angle = corrected_angle - player_deg

		while relative_angle > 180.0:
			relative_angle -= 360.0
		while relative_angle < -180.0:
			relative_angle += 360.0

		if abs(relative_angle) > 60.0:
			continue

		var x_pos = compass_width / 2.0 + (-relative_angle * pixels_per_degree)

		_draw_marker_icon(Vector2(x_pos, center_y), marker_col, distance, marker_label)


func _draw_marker_icon(pos: Vector2, color: Color, distance: float, label: String):
	var icon_size = 6.0

	# Draw diamond shape
	var points = PackedVector2Array([pos + Vector2(0, -icon_size), pos + Vector2(icon_size, 0), pos + Vector2(0, icon_size), pos + Vector2(-icon_size, 0)])

	draw_colored_polygon(points, color)
	draw_polyline(points + PackedVector2Array([points[0]]), Color.WHITE, 1.0)

	# Draw label above marker
	var label_font_size = 10
	var label_string_size = ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, label_font_size)
	draw_string(ThemeDB.fallback_font, Vector2(pos.x - label_string_size.x / 2.0, pos.y - icon_size - 2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size, Color.WHITE)

	# Draw distance below marker
	var distance_text = str(int(distance)) + "m"
	var font_size = 10
	var string_size = ThemeDB.fallback_font.get_string_size(distance_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)

	draw_string(ThemeDB.fallback_font, Vector2(pos.x - string_size.x / 2.0, pos.y + icon_size + 12), distance_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_center_marker():
	var center = Vector2(compass_width / 2.0, compass_height / 2.0)
	var marker_height = 20.0

	# Draw vertical line indicator in center
	draw_line(Vector2(center.x, center.y - marker_height), Vector2(center.x, center.y + marker_height), center_marker_color, 3.0)

	# Draw small triangle at bottom
	var tri_size = 4.0
	var tri_points = PackedVector2Array(
		[Vector2(center.x, center.y + marker_height), Vector2(center.x - tri_size, center.y + marker_height - tri_size * 1.5), Vector2(center.x + tri_size, center.y + marker_height - tri_size * 1.5)]
	)
	draw_colored_polygon(tri_points, center_marker_color)


func _get_map_ui():
	if not map_manager:
		return null

	if "full_map" in map_manager:
		return map_manager.full_map

	return null


func set_compass_visible(is_visible: bool):
	visible = is_visible
