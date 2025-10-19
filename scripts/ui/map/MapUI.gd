extends Control

signal map_closed
signal map_opened

# Map configuration
@export var default_zoom: float = 0.1
@export var min_zoom: float = 0.05
@export var max_zoom: float = 0.5
@export var zoom_step: float = 0.05
@export var background_color: Color = Color(0.05, 0.05, 0.05, 0.95)
@export var player_color: Color = Color(0.0, 1.0, 0.0, 1.0)
@export var player_marker_size: float = 12.0

# Grid configuration
@export_group("Grid Settings")
@export var show_grid: bool = true
@export var major_grid_spacing: float = 100.0
@export var minor_grid_spacing: float = 10.0
@export var major_grid_color: Color = Color(0.5, 0.5, 0.5, 0.6)
@export var minor_grid_color: Color = Color(0.3, 0.3, 0.3, 0.4)
@export var major_grid_width: float = 2.0
@export var minor_grid_width: float = 1.0
@export var show_grid_labels: bool = true
@export var grid_label_color: Color = Color(0.8, 0.8, 0.8, 0.9)
@export var grid_label_size: int = 12

# State
var is_map_open: bool = false
var current_zoom: float = 0.1
var is_dragging: bool = false
var drag_start_pos: Vector2 = Vector2.ZERO
var drag_start_offset: Vector2 = Vector2.ZERO
var right_click_pos: Vector2 = Vector2.ZERO

# Markers
var map_markers: Array[Dictionary] = []
var marker_color: Color = Color(1.0, 0.0, 0.0, 1.0)
var marker_size: float = 8.0

# Waypoints
var waypoint_nodes: Array[Node3D] = []
var waypoint_container: Node3D

# References
var player: Node3D
var camera: Camera3D
var camera_pivot: Node3D

# Rendering
var render_viewport: SubViewport
var map_camera: Camera3D

# UI Elements
var map_container: Control
var close_button: Button
var zoom_in_button: Button
var zoom_out_button: Button
var reset_button: Button
var context_menu: ContextMenu_Base


func _ready():
	visible = false
	_setup_ui()
	_setup_map_viewport()
	_setup_context_menu()
	call_deferred("_setup_waypoint_container")
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
	add_child(render_viewport)

	# Create simplified environment for map (no shadows, no post-processing)
	var map_env = Environment.new()
	map_env.background_mode = Environment.BG_COLOR
	map_env.background_color = Color(0.05, 0.05, 0.05, 1.0)
	map_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	map_env.ambient_light_color = Color(1.0, 1.0, 1.0, 1.0)
	map_env.ambient_light_energy = 1.0
	map_env.ssao_enabled = false
	map_env.sdfgi_enabled = false
	map_env.glow_enabled = false
	map_env.volumetric_fog_enabled = false

	var world_env = WorldEnvironment.new()
	world_env.environment = map_env
	render_viewport.add_child(world_env)

	map_camera = Camera3D.new()
	map_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	map_camera.size = 100.0 / default_zoom
	# Cull mask: exclude layer 2 (grass particles)
	map_camera.cull_mask = 0b11111111111111111101
	render_viewport.add_child(map_camera)

	current_zoom = default_zoom


func _setup_context_menu():
	context_menu = ContextMenu_Base.new()
	context_menu.name = "MapContextMenu"
	add_child(context_menu)


func _setup_waypoint_container():
	# Find or create waypoint container in the world
	var existing_container = get_tree().get_first_node_in_group("waypoint_container")
	if existing_container:
		waypoint_container = existing_container
		print("Found existing waypoint container at: ", waypoint_container.get_path())
	else:
		# Get the actual game scene (not the UI scene)
		var scene_root = get_tree().current_scene
		if not scene_root:
			scene_root = get_tree().root.get_child(get_tree().root.get_child_count() - 1)

		print("Scene root: ", scene_root.name, " at path: ", scene_root.get_path())

		waypoint_container = Node3D.new()
		waypoint_container.name = "WaypointContainer"
		waypoint_container.add_to_group("waypoint_container")

		# Add to the scene root
		scene_root.add_child(waypoint_container)

		# Verify it was added
		await get_tree().process_frame
		print("Created new waypoint container at: ", waypoint_container.get_path())
		print("Container is in tree: ", waypoint_container.is_inside_tree())


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

	if context_menu:
		context_menu.item_selected.connect(_on_context_menu_item_selected)


func _input(event):
	if event.is_action_pressed("ui_cancel") and is_map_open:
		close_map()
		get_viewport().set_input_as_handled()


func _process(_delta):
	if is_map_open:
		queue_redraw()


func _draw():
	if not is_map_open:
		return

	var rect = Rect2(Vector2.ZERO, size)
	draw_rect(rect, background_color, true)

	if render_viewport and render_viewport.get_texture():
		draw_texture_rect(render_viewport.get_texture(), rect, false)

	if show_grid:
		_draw_grid()

	if player:
		_draw_player_marker()

	# Draw map markers
	_draw_map_markers()


func _draw_grid():
	if not map_camera:
		return

	var camera_pos = map_camera.global_position
	var pixels_per_unit = size.y / map_camera.size

	# Calculate visible world bounds
	var half_width = map_camera.size * (size.x / size.y) / 2.0
	var half_height = map_camera.size / 2.0

	var world_min_x = camera_pos.x - half_width
	var world_max_x = camera_pos.x + half_width
	var world_min_z = camera_pos.z - half_height
	var world_max_z = camera_pos.z + half_height

	# Draw minor grid lines first
	if minor_grid_spacing > 0 and current_zoom > 0.15:
		_draw_grid_lines(world_min_x, world_max_x, world_min_z, world_max_z, minor_grid_spacing, minor_grid_color, minor_grid_width, pixels_per_unit, camera_pos, false)

	# Draw major grid lines
	if major_grid_spacing > 0:
		_draw_grid_lines(world_min_x, world_max_x, world_min_z, world_max_z, major_grid_spacing, major_grid_color, major_grid_width, pixels_per_unit, camera_pos, true)


func _draw_grid_lines(min_x: float, max_x: float, min_z: float, max_z: float, spacing: float, color: Color, width: float, pixels_per_unit: float, camera_pos: Vector3, show_labels: bool):
	# Vertical lines (X axis)
	var start_x = floor(min_x / spacing) * spacing
	var x = start_x
	while x <= max_x:
		var screen_x = size.x / 2.0 - (x - camera_pos.x) * pixels_per_unit
		draw_line(Vector2(screen_x, 0), Vector2(screen_x, size.y), color, width)

		if show_labels and show_grid_labels:
			var label = str(int(x))
			draw_string(ThemeDB.fallback_font, Vector2(screen_x + 5, 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, grid_label_size, grid_label_color)

		x += spacing

	# Horizontal lines (Z axis)
	var start_z = floor(min_z / spacing) * spacing
	var z = start_z
	while z <= max_z:
		var screen_y = size.y / 2.0 - (z - camera_pos.z) * pixels_per_unit
		draw_line(Vector2(0, screen_y), Vector2(size.x, screen_y), color, width)

		if show_labels and show_grid_labels:
			var label = str(int(z))
			draw_string(ThemeDB.fallback_font, Vector2(5, screen_y - 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, grid_label_size, grid_label_color)

		z += spacing


func _draw_player_marker():
	if not player or not map_camera:
		return

	var camera_pos = map_camera.global_position
	var player_pos = player.global_position
	var pixels_per_unit = size.y / map_camera.size

	var offset_x = player_pos.x - camera_pos.x
	var offset_z = player_pos.z - camera_pos.z

	var center_x = size.x / 2.0 - offset_x * pixels_per_unit
	var center_y = size.y / 2.0 - offset_z * pixels_per_unit

	var center = Vector2(center_x, center_y)
	var half_size = player_marker_size / 2.0
	var rotation: float = 0.0

	if player:
		rotation = -player.global_rotation.y - PI

	var points = PackedVector2Array(
		[center + Vector2(0, -half_size * 1.5).rotated(rotation), center + Vector2(-half_size, half_size).rotated(rotation), center + Vector2(half_size, half_size).rotated(rotation)]
	)

	draw_colored_polygon(points, player_color)

	draw_circle(center, player_marker_size + 2, Color(1.0, 1.0, 1.0, 0.5), false, 2.0)


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
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				right_click_pos = event.position
				_show_context_menu(event.global_position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_out()

	elif event is InputEventMouseMotion and is_dragging:
		if map_camera:
			var delta = event.position - drag_start_pos
			var pixels_per_unit = size.x / map_camera.size

			var new_z = drag_start_offset.y + delta.y / pixels_per_unit
			var new_x = drag_start_offset.x + delta.x / pixels_per_unit

			map_camera.global_position = Vector3(new_x, map_camera.global_position.y, new_z)
			var look_target = Vector3(new_x, 0, new_z)
			map_camera.look_at(look_target, Vector3.BACK)


func _show_context_menu(global_pos: Vector2):
	if context_menu:
		# Update the toggle grid menu item text based on current state
		context_menu.clear_items()
		context_menu.add_menu_item("center_player", "Center on Player")
		context_menu.add_menu_item("toggle_grid", "Hide Grid" if show_grid else "Show Grid")
		context_menu.add_separator()
		context_menu.add_menu_item("zoom_in", "Zoom In")
		context_menu.add_menu_item("zoom_out", "Zoom Out")
		context_menu.add_menu_item("reset_view", "Reset View")
		context_menu.add_separator()
		context_menu.add_menu_item("place_marker", "Place Marker Here")
		if not map_markers.is_empty():
			context_menu.add_menu_item("remove_last_marker", "Remove Last Marker")
			context_menu.add_menu_item("clear_markers", "Clear All Markers")

		context_menu.show_context_menu(global_pos, {"click_position": right_click_pos})


func _on_context_menu_item_selected(item_id: String, _item_data: Dictionary, _context_data: Dictionary):
	match item_id:
		"center_player":
			_center_on_player()
		"toggle_grid":
			show_grid = not show_grid
			queue_redraw()
		"zoom_in":
			_zoom_in()
		"zoom_out":
			_zoom_out()
		"reset_view":
			_on_reset_pressed()
		"place_marker":
			_place_marker_at_position(_context_data.get("click_position", Vector2.ZERO))
		"remove_last_marker":
			_remove_last_marker()
		"clear_markers":
			_clear_all_markers()


func _center_on_player():
	if player and map_camera:
		var player_pos = player.global_position
		map_camera.global_position = Vector3(player_pos.x, map_camera.global_position.y, player_pos.z)
		var look_target = Vector3(player_pos.x, 0, player_pos.z)
		map_camera.look_at(look_target, Vector3.BACK)


func _place_marker_at_position(click_pos: Vector2):
	# Convert screen position to world position
	if not map_camera:
		return

	var camera_pos = map_camera.global_position
	var pixels_per_unit = size.y / map_camera.size

	# Calculate offset from center (inverse of drawing formula)
	var offset_x = (size.x / 2.0 - click_pos.x) / pixels_per_unit
	var offset_z = (size.y / 2.0 - click_pos.y) / pixels_per_unit

	var world_x = camera_pos.x + offset_x
	var world_z = camera_pos.z + offset_z

	# Use player's Y position or a default height
	var world_y = 0.0
	if player:
		world_y = player.global_position.y

	# Create marker with alphabetical label
	var marker = {"position": Vector3(world_x, world_y, world_z), "label": _get_marker_label(map_markers.size()), "color": marker_color}

	map_markers.append(marker)

	# Spawn 3D waypoint (async call)
	_spawn_waypoint(marker)

	print("Marker placed at: ", marker.position)

	queue_redraw()


func _spawn_waypoint(marker_data: Dictionary):
	if not waypoint_container or not waypoint_container.is_inside_tree():
		await _setup_waypoint_container()

	print("Spawning waypoint: ", marker_data)
	print("Waypoint container position: ", waypoint_container.global_position)
	print("Waypoint container path: ", waypoint_container.get_path())
	print("Container in tree: ", waypoint_container.is_inside_tree())

	var Waypoint3D = load("res://scripts/ui/map/Waypoint3D.gd")
	var waypoint = Waypoint3D.new()
	waypoint.name = "Waypoint_" + str(waypoint_nodes.size())

	# Set position BEFORE adding to scene as local position
	var target_pos = Vector3(marker_data.position.x, marker_data.position.y + 1.0, marker_data.position.z)
	waypoint.position = target_pos
	print("Setting waypoint local position to: ", target_pos)

	# Set waypoint data
	waypoint.set_waypoint_data(marker_data.label, marker_data.color)

	# Add to scene
	waypoint_container.add_child(waypoint)

	waypoint_nodes.append(waypoint)

	print("Waypoint local position: ", waypoint.position)
	print("Waypoint global position: ", waypoint.global_position)
	print("Waypoint path: ", waypoint.get_path())
	print("Total waypoints: ", waypoint_nodes.size())


func _draw_map_markers():
	if not map_camera or map_markers.is_empty():
		return

	var camera_pos = map_camera.global_position
	var pixels_per_unit = size.y / map_camera.size

	for marker in map_markers:
		var marker_pos: Vector3 = marker.position
		var marker_label: String = marker.label
		var marker_col: Color = marker.get("color", marker_color)

		# Calculate screen position
		var offset_x = marker_pos.x - camera_pos.x
		var offset_z = marker_pos.z - camera_pos.z

		var screen_x = size.x / 2.0 - offset_x * pixels_per_unit
		var screen_y = size.y / 2.0 - offset_z * pixels_per_unit

		# Only draw if visible on screen
		if screen_x >= -marker_size and screen_x <= size.x + marker_size and screen_y >= -marker_size and screen_y <= size.y + marker_size:
			var center = Vector2(screen_x, screen_y)

			# Draw marker cross
			var half_size = marker_size
			draw_line(center + Vector2(-half_size, 0), center + Vector2(half_size, 0), marker_col, 2.0)
			draw_line(center + Vector2(0, -half_size), center + Vector2(0, half_size), marker_col, 2.0)

			# Draw marker circle
			draw_circle(center, marker_size, marker_col, false, 2.0)

			# Draw label
			if current_zoom > 0.08:
				var label_pos = center + Vector2(marker_size + 5, 5)
				draw_string(ThemeDB.fallback_font, label_pos, marker_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, marker_col)


func _remove_last_marker():
	if not map_markers.is_empty():
		map_markers.pop_back()

		# Remove corresponding waypoint
		if not waypoint_nodes.is_empty():
			var waypoint = waypoint_nodes.pop_back()
			if is_instance_valid(waypoint):
				waypoint.queue_free()

		queue_redraw()


func _clear_all_markers():
	map_markers.clear()

	# Remove all waypoints
	for waypoint in waypoint_nodes:
		if is_instance_valid(waypoint):
			waypoint.queue_free()
	waypoint_nodes.clear()

	queue_redraw()


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
		var look_target = Vector3(player_pos.x, 0, player_pos.z)
		map_camera.look_at(look_target, Vector3.BACK)

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


func _get_marker_label(index: int) -> String:
	var label = ""
	var temp_index = index

	while true:
		label = char(65 + (temp_index % 26)) + label
		temp_index = int(temp_index / 26)
		if temp_index == 0:
			break
		temp_index -= 1

	return label


func open_map():
	is_map_open = true
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if player and map_camera:
		var player_pos = player.global_position
		map_camera.global_position = Vector3(player_pos.x, player_pos.y + 100, player_pos.z)
		var look_target = Vector3(player_pos.x, 0, player_pos.z)
		map_camera.look_at(look_target, Vector3.BACK)

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
