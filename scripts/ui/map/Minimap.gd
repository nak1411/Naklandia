extends Control

# Minimap configuration
@export var minimap_size: Vector2 = Vector2(200, 200)
@export var zoom_level: float = 0.1
@export var border_width: int = 2
@export var background_color: Color = Color(0.1, 0.1, 0.1, 0.8)
@export var border_color: Color = Color(0.3, 0.3, 0.3, 1.0)
@export var player_color: Color = Color(0.0, 1.0, 0.0, 1.0)
@export var player_marker_size: float = 8.0
@export var north_indicator_color: Color = Color(1.0, 0.0, 0.0, 1.0)
@export var marker_icon_color: Color = Color(1.0, 0.0, 0.0, 1.0)
@export var marker_size: float = 6.0

# References
var player: Node3D
var camera: Camera3D
var camera_pivot: Node3D
var map_manager: Node

# Minimap texture
var minimap_image: Image
var minimap_texture: ImageTexture
var render_viewport: SubViewport
var minimap_camera: Camera3D


func _ready():
	custom_minimum_size = minimap_size
	_setup_minimap_viewport()
	_find_player_reference()
	_find_map_manager()


func _setup_minimap_viewport():
	render_viewport = SubViewport.new()
	render_viewport.size = Vector2i(minimap_size)
	render_viewport.transparent_bg = true
	render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(render_viewport)

	# Create simplified environment for minimap (no shadows, flat unlighted color)
	var minimap_env = Environment.new()
	minimap_env.background_mode = Environment.BG_COLOR
	minimap_env.background_color = Color(0.1, 0.1, 0.1, 1.0)
	minimap_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	minimap_env.ambient_light_color = Color(1.0, 1.0, 1.0, 1.0)
	minimap_env.ambient_light_energy = 100.0
	minimap_env.ssao_enabled = false
	minimap_env.sdfgi_enabled = false
	minimap_env.glow_enabled = false
	minimap_env.volumetric_fog_enabled = false
	minimap_env.ssil_enabled = false
	minimap_env.ssr_enabled = false

	var world_env = WorldEnvironment.new()
	world_env.environment = minimap_env
	render_viewport.add_child(world_env)

	# Add directional light with no shadows for flat unlit appearance
	var dir_light = DirectionalLight3D.new()
	dir_light.light_energy = 1.0
	dir_light.shadow_enabled = false
	dir_light.rotation_degrees = Vector3(-90, 0, 0)
	render_viewport.add_child(dir_light)

	minimap_camera = Camera3D.new()
	minimap_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	minimap_camera.size = 50.0 / zoom_level
	# Cull mask: exclude layer 2 (grass particles)
	minimap_camera.cull_mask = 0b11111111111111111101
	render_viewport.add_child(minimap_camera)

	minimap_texture = ImageTexture.new()


func _find_player_reference():
	var player_node = get_tree().get_first_node_in_group("player")
	if player_node:
		player = player_node
		if player.has_node("CameraPivot/Camera3D"):
			camera = player.get_node("CameraPivot/Camera3D")
		if player.has_node("CameraPivot"):
			camera_pivot = player.get_node("CameraPivot")


func _find_map_manager():
	var map_managers = get_tree().get_nodes_in_group("map_manager")
	if map_managers.size() > 0:
		map_manager = map_managers[0]


func _process(_delta):
	if player and minimap_camera:
		var player_pos = player.global_position
		minimap_camera.global_position = Vector3(player_pos.x, player_pos.y + 50, player_pos.z)
		var look_target = Vector3(player_pos.x, player_pos.y, player_pos.z)
		minimap_camera.look_at(look_target, Vector3.BACK)

	queue_redraw()


func _draw():
	var rect = Rect2(Vector2.ZERO, minimap_size)

	draw_rect(rect, background_color, true)

	if render_viewport and render_viewport.get_texture():
		draw_texture_rect(render_viewport.get_texture(), rect, false)

	var center = minimap_size / 2.0
	_draw_map_markers(center)
	_draw_player_marker(center)
	_draw_north_indicator(center)

	draw_rect(rect, border_color, false, border_width)


func _draw_player_marker(center: Vector2):
	var half_size = player_marker_size / 2.0
	var rotation: float = 0.0

	if player:
		rotation = -player.global_rotation.y - PI

	var points = PackedVector2Array(
		[center + Vector2(0, -half_size * 1.5).rotated(rotation), center + Vector2(-half_size, half_size).rotated(rotation), center + Vector2(half_size, half_size).rotated(rotation)]
	)

	draw_colored_polygon(points, player_color)


func _draw_north_indicator(center: Vector2):
	var north_pos = center + Vector2(0, -minimap_size.y / 2.0 + 15)
	draw_circle(north_pos, 3, north_indicator_color)
	draw_string(ThemeDB.fallback_font, north_pos + Vector2(-3, -5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, north_indicator_color)


func _draw_map_markers(center: Vector2):
	if not player or not minimap_camera or not map_manager:
		return

	var map_ui = _get_map_ui()
	if not map_ui:
		return

	# Check if map_ui has the map_markers property
	if not "map_markers" in map_ui:
		return

	var markers = map_ui.map_markers
	if markers.is_empty():
		return

	var camera_pos = minimap_camera.global_position
	var player_pos = player.global_position
	var pixels_per_unit = minimap_size.y / minimap_camera.size

	for marker in markers:
		var marker_pos: Vector3 = marker.position
		var marker_col: Color = marker.get("color", marker_icon_color)

		# Calculate offset from player (who is at center)
		var offset_x = marker_pos.x - player_pos.x
		var offset_z = marker_pos.z - player_pos.z

		# Convert to screen coordinates (relative to center) - negate Z to flip
		var screen_offset_x = -offset_x * pixels_per_unit
		var screen_offset_z = -offset_z * pixels_per_unit

		var marker_screen_pos = center + Vector2(screen_offset_x, screen_offset_z)

		# Only draw if within minimap bounds
		if marker_screen_pos.x < 0 or marker_screen_pos.x > minimap_size.x:
			continue
		if marker_screen_pos.y < 0 or marker_screen_pos.y > minimap_size.y:
			continue

		# Draw marker as diamond
		var half_marker = marker_size / 2.0
		var points = PackedVector2Array(
			[marker_screen_pos + Vector2(0, -half_marker), marker_screen_pos + Vector2(half_marker, 0), marker_screen_pos + Vector2(0, half_marker), marker_screen_pos + Vector2(-half_marker, 0)]
		)

		draw_colored_polygon(points, marker_col)
		draw_polyline(points + PackedVector2Array([points[0]]), Color.WHITE, 1.0)


func _get_map_ui():
	if not map_manager:
		return null

	# Check if map_manager has full_map property
	if not "full_map" in map_manager:
		return null

	return map_manager.full_map


func set_zoom(new_zoom: float):
	zoom_level = clamp(new_zoom, 0.05, 1.0)
	if minimap_camera:
		minimap_camera.size = 50.0 / zoom_level
