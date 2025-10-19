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

# References
var player: Node3D
var camera: Camera3D
var camera_pivot: Node3D

# Minimap texture
var minimap_image: Image
var minimap_texture: ImageTexture
var render_viewport: SubViewport
var minimap_camera: Camera3D


func _ready():
	custom_minimum_size = minimap_size
	_setup_minimap_viewport()
	_find_player_reference()


func _setup_minimap_viewport():
	render_viewport = SubViewport.new()
	render_viewport.size = Vector2i(minimap_size)
	render_viewport.transparent_bg = true
	render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(render_viewport)

	minimap_camera = Camera3D.new()
	minimap_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	minimap_camera.size = 50.0 / zoom_level
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


func set_zoom(new_zoom: float):
	zoom_level = clamp(new_zoom, 0.05, 1.0)
	if minimap_camera:
		minimap_camera.size = 50.0 / zoom_level
