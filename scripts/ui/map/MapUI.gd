extends Control

signal map_closed
signal map_opened

@export var default_zoom: float = 0.1
@export var min_zoom: float = 0.05
@export var max_zoom: float = 0.5
@export var zoom_step: float = 0.05
@export var background_color: Color = Color(0.05, 0.05, 0.05, 0.95)
@export var player_color: Color = Color(0.0, 1.0, 0.0, 1.0)
@export var player_marker_size: float = 12.0
@export var brightness_boost: float = 2.5
@export var contrast: float = 0.4

var is_map_open: bool = false
var current_zoom: float = 0.1
var is_dragging: bool = false
var drag_start_pos: Vector2 = Vector2.ZERO
var drag_start_offset: Vector2 = Vector2.ZERO

var player: Node3D
var camera: Camera3D
var camera_pivot: Node3D

var render_viewport: SubViewport
var map_camera: Camera3D
var viewport_display: TextureRect
var map_shader: ShaderMaterial
var overlay: Control

@onready var map_container: Control = $MapContainer
@onready var close_button: Button = $CloseButton
@onready var zoom_in_button: Button = $ZoomInButton
@onready var zoom_out_button: Button = $ZoomOutButton
@onready var reset_button: Button = $ResetButton


func _ready():
	visible = false
	_setup_ui()
	_setup_map_viewport()
	_find_player_reference()
	_connect_signals()


func _setup_ui():
	map_container = Control.new()
	map_container.name = "MapContainer"
	map_container.anchor_right = 1.0
	map_container.anchor_bottom = 1.0
	map_container.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(map_container)

	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close (M)"
	close_button.position = Vector2(10, 10)
	close_button.size = Vector2(100, 30)
	add_child(close_button)

	zoom_in_button = Button.new()
	zoom_in_button.name = "ZoomInButton"
	zoom_in_button.text = "+"
	zoom_in_button.position = Vector2(10, 50)
	zoom_in_button.size = Vector2(40, 40)
	add_child(zoom_in_button)

	zoom_out_button = Button.new()
	zoom_out_button.name = "ZoomOutButton"
	zoom_out_button.text = "-"
	zoom_out_button.position = Vector2(60, 50)
	zoom_out_button.size = Vector2(40, 40)
	add_child(zoom_out_button)

	reset_button = Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "Reset"
	reset_button.position = Vector2(110, 50)
	reset_button.size = Vector2(60, 40)
	add_child(reset_button)


func _setup_map_viewport():
	render_viewport = SubViewport.new()
	render_viewport.size = Vector2i(get_viewport_rect().size)
	render_viewport.transparent_bg = true
	render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_viewport.debug_draw = SubViewport.DEBUG_DRAW_UNSHADED
	add_child(render_viewport)

	map_camera = Camera3D.new()
	map_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	map_camera.size = 100.0 / default_zoom
	map_camera.cull_mask = 1
	render_viewport.add_child(map_camera)

	_setup_map_shader()

	current_zoom = default_zoom


func _setup_map_shader():
	var shader_code = """shader_type canvas_item;

uniform float brightness_boost = 1.5;
uniform float contrast = 1.2;

vec3 get_terrain_color(float luminance) {
	vec3 water = vec3(0.2, 0.3, 0.5);
	vec3 sand = vec3(0.8, 0.75, 0.6);
	vec3 grass = vec3(0.4, 0.5, 0.3);
	vec3 dirt = vec3(0.5, 0.4, 0.3);
	vec3 rock = vec3(0.55, 0.55, 0.55);
	vec3 snow = vec3(0.85, 0.85, 0.9);
	
	vec3 color;
	
	if (luminance < 0.2) {
		color = mix(water, sand, smoothstep(0.0, 0.2, luminance));
	} else if (luminance < 0.4) {
		color = mix(sand, grass, smoothstep(0.2, 0.4, luminance));
	} else if (luminance < 0.6) {
		color = mix(grass, dirt, smoothstep(0.4, 0.6, luminance));
	} else if (luminance < 0.75) {
		color = mix(dirt, rock, smoothstep(0.6, 0.75, luminance));
	} else {
		color = mix(rock, snow, smoothstep(0.75, 1.0, luminance));
	}
	
	return color;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float lum = dot(tex.rgb, vec3(0.99, 0.187, 0.114));
	lum = (lum - 0.5) * contrast + 0.5;
	lum *= brightness_boost;
	lum = clamp(lum, 0.0, 1.0);
	COLOR = vec4(get_terrain_color(lum), 1.0);
}
"""

	var terrain_shader = Shader.new()
	terrain_shader.code = shader_code
	map_shader = ShaderMaterial.new()
	map_shader.shader = terrain_shader
	map_shader.set_shader_parameter("brightness_boost", brightness_boost)
	map_shader.set_shader_parameter("contrast", contrast)

	viewport_display = TextureRect.new()
	viewport_display.material = map_shader
	viewport_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	viewport_display.stretch_mode = TextureRect.STRETCH_SCALE
	map_container.add_child(viewport_display)

	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	map_container.add_child(overlay)

	var shader = Shader.new()
	shader.code = shader_code
	map_shader = ShaderMaterial.new()
	map_shader.shader = shader

	viewport_display = TextureRect.new()
	viewport_display.material = map_shader
	viewport_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	viewport_display.stretch_mode = TextureRect.STRETCH_SCALE
	map_container.add_child(viewport_display)

	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	map_container.add_child(overlay)


func _find_player_reference():
	var player_node = get_tree().get_first_node_in_group("player")
	if player_node:
		player = player_node
		if player.has_node("CameraPivot/Camera3D"):
			camera = player.get_node("CameraPivot/Camera3D")
		if player.has_node("CameraPivot"):
			camera_pivot = player.get_node("CameraPivot")


func _connect_signals():
	close_button.pressed.connect(_on_close_pressed)
	zoom_in_button.pressed.connect(_on_zoom_in_pressed)
	zoom_out_button.pressed.connect(_on_zoom_out_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	map_container.gui_input.connect(_on_map_gui_input)


func _input(event):
	if event.is_action_pressed("ui_cancel") and is_map_open:
		close_map()
		get_viewport().set_input_as_handled()


func _process(_delta):
	if is_map_open:
		# Update shader parameters in case they changed
		if map_shader:
			map_shader.set_shader_parameter("brightness_boost", brightness_boost)
			map_shader.set_shader_parameter("contrast", contrast)

		queue_redraw()
		if overlay:
			overlay.queue_redraw()


func _draw():
	if not is_map_open:
		return

	var rect = Rect2(Vector2.ZERO, size)
	draw_rect(rect, background_color, true)

	if render_viewport and render_viewport.get_texture() and viewport_display:
		viewport_display.texture = render_viewport.get_texture()
		viewport_display.size = size
		viewport_display.position = Vector2.ZERO


func _draw_overlay():
	if not is_map_open or not player:
		return

	_draw_player_marker_on(overlay)


func _draw_player_marker_on(control: Control):
	if not player or not map_camera:
		return

	var player_pos = player.global_position
	var camera_pos = map_camera.global_position

	var offset_x = player_pos.x - camera_pos.x
	var offset_z = player_pos.z - camera_pos.z

	var pixels_per_unit = size.y / map_camera.size

	var screen_x = size.x / 2.0 - offset_z * pixels_per_unit
	var screen_y = size.y / 2.0 + offset_x * pixels_per_unit

	var center = Vector2(screen_x, screen_y)
	var half_size = player_marker_size / 2.0
	var rotation: float = 0.0

	if player:
		rotation = -player.global_rotation.y - PI - PI / 2

	var points = PackedVector2Array(
		[center + Vector2(-half_size, half_size).rotated(rotation), center + Vector2(half_size, half_size).rotated(rotation), center + Vector2(0, -half_size * 1.5).rotated(rotation)]
	)

	control.draw_colored_polygon(points, player_color)
	control.draw_circle(center, player_marker_size + 2, Color(1.0, 1.0, 1.0, 0.5), false, 2.0)


func _on_map_gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
				drag_start_pos = event.position
				if map_camera:
					drag_start_offset = Vector2(map_camera.global_position.x, map_camera.global_position.z)
			else:
				is_dragging = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_out()

	elif event is InputEventMouseMotion and is_dragging:
		if map_camera:
			var delta = event.position - drag_start_pos
			var pixels_per_unit = size.x / map_camera.size

			var new_z = drag_start_offset.y + delta.x / pixels_per_unit
			var new_x = drag_start_offset.x - delta.y / pixels_per_unit

			map_camera.global_position = Vector3(new_x, map_camera.global_position.y, new_z)
			map_camera.look_at(Vector3(new_x, 0, new_z), Vector3.UP)


func _on_close_pressed():
	close_map()


func _on_zoom_in_pressed():
	_zoom_in()


func _on_zoom_out_pressed():
	_zoom_out()


func _on_reset_pressed():
	if player and map_camera:
		var player_pos = player.global_position
		map_camera.global_position = Vector3(player_pos.x, map_camera.global_position.y, player_pos.z)
		map_camera.look_at(player_pos, Vector3.UP)

	current_zoom = default_zoom
	if map_camera:
		map_camera.size = 100.0 / current_zoom


func _zoom_in():
	current_zoom = clamp(current_zoom + zoom_step, min_zoom, max_zoom)
	if map_camera:
		map_camera.size = 100.0 / current_zoom


func _zoom_out():
	current_zoom = clamp(current_zoom - zoom_step, min_zoom, max_zoom)
	if map_camera:
		map_camera.size = 100.0 / current_zoom


func open_map():
	is_map_open = true
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if player and map_camera:
		var player_pos = player.global_position
		map_camera.global_position = Vector3(player_pos.x, player_pos.y + 100, player_pos.z)
		map_camera.look_at(player_pos, Vector3.UP)

	map_opened.emit()


func close_map():
	is_map_open = false
	visible = false
	is_dragging = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	map_closed.emit()


func toggle_map():
	if is_map_open:
		close_map()
	else:
		open_map()
