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

# Chunk visualization
@export_group("Chunk Visualization")
@export var show_chunk_overlay: bool = false
@export var chunk_size: float = 64.0  # Should match ProceduralFoliageSpawner chunk_size
@export var unloaded_chunk_color: Color = Color(0.2, 0.2, 0.2, 0.3)
@export var loaded_chunk_color: Color = Color(0.0, 0.8, 0.2, 0.5)
@export var chunk_border_width: float = 1.0

# Debug settings
@export_group("Debug Visualization")
@export var show_tree_debug: bool = false  # Enable tree debug visualization (expensive!)
@export var tree_visible_color: Color = Color(1.0, 0.4, 0.8, 1.0)  # Pink for visible trees
@export var tree_hidden_color: Color = Color(0.6, 0.2, 0.4, 0.5)  # Dark pink for hidden trees
@export var tree_culled_color: Color = Color(0.0, 0.0, 0.0, 0.8)  # Black for frustum-culled trees
@export var tree_dot_size: float = 1.0

# Minimap texture
var minimap_image: Image
var minimap_texture: ImageTexture
var render_viewport: SubViewport
var minimap_camera: Camera3D

# References
var player: Node3D
var camera: Camera3D
var camera_pivot: Node3D
var map_manager: Node
var tree_spawner: Node  # Reference to ProceduralTreeSpawner for debug vis
var foliage_spawner: Node3D = null  # Reference to ProceduralFoliageSpawner for chunk overlay
var debug_manager: Node = null
var _debug_chunk_logged: bool = false  # Only log once


func _ready():
	custom_minimum_size = minimap_size
	clip_contents = true  # Enable clipping to prevent content from drawing outside bounds
	_setup_minimap_viewport()
	_find_player_reference()
	_find_map_manager()
	_find_tree_spawner()
	# Defer finding foliage spawner to avoid timing issues
	call_deferred("_find_foliage_spawner")
	_connect_debug_manager()


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


func _find_tree_spawner():
	var tree_spawners = get_tree().get_nodes_in_group("tree_spawner")
	if tree_spawners.size() > 0:
		tree_spawner = tree_spawners[0]
		print("Minimap: Found tree spawner: ", tree_spawner.name)
	else:
		print("Minimap: No tree spawner found in group 'tree_spawner'")


func _find_foliage_spawner():
	foliage_spawner = get_tree().get_first_node_in_group("foliage_spawner")
	if not foliage_spawner:
		print("Minimap: No foliage spawner found - chunk overlay will not work")
	else:
		print("Minimap: Found foliage spawner")


func _connect_debug_manager():
	"""Connect to DebugManager signals for debug visualization"""
	debug_manager = get_node_or_null("/root/DebugManager")
	if debug_manager:
		debug_manager.chunk_visualization_toggled.connect(_on_chunk_visualization_toggled)
		debug_manager.tree_debug_toggled.connect(_on_tree_debug_toggled)
		# Sync initial state
		show_chunk_overlay = debug_manager.get_chunk_overlay_enabled()
		show_tree_debug = debug_manager.get_tree_debug_enabled()
		print("Minimap: Connected to DebugManager, chunk overlay: ", show_chunk_overlay, ", tree debug: ", show_tree_debug)
	else:
		print("Minimap: DebugManager not found, debug toggles won't sync with settings")


func _on_chunk_visualization_toggled(enabled: bool):
	"""Called when chunk visualization is toggled from settings"""
	show_chunk_overlay = enabled
	queue_redraw()
	print("Minimap: Chunk overlay toggled from settings: ", enabled)


func _on_tree_debug_toggled(enabled: bool):
	"""Called when tree debug is toggled from settings"""
	show_tree_debug = enabled
	queue_redraw()
	print("Minimap: Tree debug toggled from settings: ", enabled)


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

	# Draw chunk overlay after 3D viewport but before other UI elements
	if show_chunk_overlay:
		_draw_chunk_overlay(center)
	elif not _debug_chunk_logged:
		print("Minimap: Chunk overlay disabled (show_chunk_overlay = false)")
		_debug_chunk_logged = true

	_draw_debug_trees(center)
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


func _draw_chunk_overlay(center: Vector2):
	"""Draw chunk grid showing loaded vs unloaded chunks on the minimap"""
	if not player or not minimap_camera or not foliage_spawner:
		if not _debug_chunk_logged:
			if not player:
				print("Minimap chunk overlay: No player")
			if not minimap_camera:
				print("Minimap chunk overlay: No minimap_camera")
			if not foliage_spawner:
				print("Minimap chunk overlay: No foliage_spawner")
			_debug_chunk_logged = true
		return

	var player_pos = player.global_position
	var pixels_per_unit = minimap_size.y / minimap_camera.size

	# Calculate visible world bounds based on minimap view
	var half_width = minimap_camera.size * (minimap_size.x / minimap_size.y) / 2.0
	var half_height = minimap_camera.size / 2.0

	var world_min_x = player_pos.x - half_width
	var world_max_x = player_pos.x + half_width
	var world_min_z = player_pos.z - half_height
	var world_max_z = player_pos.z + half_height

	# Calculate which chunks are visible
	var min_chunk_x = int(floor(world_min_x / chunk_size))
	var max_chunk_x = int(ceil(world_max_x / chunk_size))
	var min_chunk_z = int(floor(world_min_z / chunk_size))
	var max_chunk_z = int(ceil(world_max_z / chunk_size))

	# Get loaded chunks from foliage spawner
	var loaded_chunks = foliage_spawner.get("loaded_chunks")
	if not loaded_chunks:
		if not _debug_chunk_logged:
			print("Minimap chunk overlay: No loaded_chunks from foliage_spawner")
			_debug_chunk_logged = true
		return

	if not _debug_chunk_logged:
		print("Minimap chunk overlay: Drawing ", (max_chunk_x - min_chunk_x + 1) * (max_chunk_z - min_chunk_z + 1), " chunks, ", loaded_chunks.size(), " loaded")
		_debug_chunk_logged = true

	# Draw all visible chunks
	for chunk_x in range(min_chunk_x, max_chunk_x + 1):
		for chunk_z in range(min_chunk_z, max_chunk_z + 1):
			var chunk_key = str(chunk_x) + "_" + str(chunk_z)
			var is_loaded = loaded_chunks.has(chunk_key)

			# Calculate chunk bounds in world space
			var chunk_world_x = float(chunk_x) * chunk_size
			var chunk_world_z = float(chunk_z) * chunk_size

			# Calculate offset from player (who is at center)
			var offset_x1 = chunk_world_x - player_pos.x
			var offset_z1 = chunk_world_z - player_pos.z
			var offset_x2 = (chunk_world_x + chunk_size) - player_pos.x
			var offset_z2 = (chunk_world_z + chunk_size) - player_pos.z

			# Convert to screen coordinates (relative to center) - negate to flip
			var screen_x1 = center.x - offset_x1 * pixels_per_unit
			var screen_y1 = center.y - offset_z1 * pixels_per_unit
			var screen_x2 = center.x - offset_x2 * pixels_per_unit
			var screen_y2 = center.y - offset_z2 * pixels_per_unit

			var rect = Rect2(Vector2(screen_x1, screen_y1), Vector2(screen_x2 - screen_x1, screen_y2 - screen_y1))

			# Draw filled rectangle
			var fill_color = loaded_chunk_color if is_loaded else unloaded_chunk_color
			draw_rect(rect, fill_color, true)

			# Draw border
			var chunk_border_color = loaded_chunk_color if is_loaded else unloaded_chunk_color
			chunk_border_color.a = 0.8  # Make border more opaque
			draw_rect(rect, chunk_border_color, false, chunk_border_width)


func _is_point_in_frustum(point: Vector3, cam: Camera3D) -> bool:
	"""Check if a point is inside the camera's view frustum"""
	if not cam:
		return false
	var frustum = cam.get_frustum()
	for plane in frustum:
		# Godot frustum planes point inward, so positive distance = inside
		if plane.distance_to(point) > 0:
			return false
	return true


func _draw_debug_trees(center: Vector2):
	"""Draw tree positions as colored dots for debugging culling and rendering"""
	if not show_tree_debug:
		return

	if not tree_spawner:
		# Try to find it again if we don't have it yet
		_find_tree_spawner()
		if not tree_spawner:
			return

	if not player or not minimap_camera:
		return

	# Check if tree spawner has debug mode enabled
	if not tree_spawner.has_method("is_debug_mode_enabled"):
		print("Minimap Debug: Tree spawner doesn't have is_debug_mode_enabled method")
		return

	if not tree_spawner.is_debug_mode_enabled():
		print("Minimap Debug: Tree spawner debug mode is disabled. Enable 'Debug Show On Minimap' on the ProceduralTreeSpawner node")
		return

	var player_pos = player.global_position
	var pixels_per_unit = minimap_size.y / minimap_camera.size

	# OPTIMIZATION: Only get trees within minimap view radius
	var view_radius = minimap_camera.size  # Camera size = view radius in world units
	var all_tree_positions: Array[Vector3] = []

	# Use optimized spatial query if available, otherwise fall back to all trees
	if tree_spawner.has_method("get_nearby_tree_positions"):
		all_tree_positions = tree_spawner.get_nearby_tree_positions(player_pos, view_radius)
	elif tree_spawner.has_method("get_all_tree_positions"):
		all_tree_positions = tree_spawner.get_all_tree_positions()

	# Get visible trees to differentiate colors
	var visible_tree_positions: Array[Vector3] = []
	if tree_spawner.has_method("get_visible_tree_positions"):
		visible_tree_positions = tree_spawner.get_visible_tree_positions()

	# Count trees by state for debugging
	var count_loaded = 0
	var count_in_frustum = 0
	var count_culled = 0

	# Create a set of visible positions for quick lookup
	var visible_set = {}
	for tree_pos in visible_tree_positions:
		var key = str(snappedf(tree_pos.x, 0.01)) + "_" + str(snappedf(tree_pos.z, 0.01))
		visible_set[key] = true

	# Draw all trees
	for tree_pos in all_tree_positions:
		# Calculate offset from player (who is at center)
		var offset_x = tree_pos.x - player_pos.x
		var offset_z = tree_pos.z - player_pos.z

		# Convert to screen coordinates (relative to center) - negate to flip
		var screen_offset_x = -offset_x * pixels_per_unit
		var screen_offset_z = -offset_z * pixels_per_unit

		var tree_screen_pos = center + Vector2(screen_offset_x, screen_offset_z)

		# Only draw if within minimap bounds (with small padding)
		if tree_screen_pos.x < -5 or tree_screen_pos.x > minimap_size.x + 5:
			continue
		if tree_screen_pos.y < -5 or tree_screen_pos.y > minimap_size.y + 5:
			continue

		# Determine color based on visibility and frustum culling
		var key = str(snappedf(tree_pos.x, 0.01)) + "_" + str(snappedf(tree_pos.z, 0.01))
		var tree_color: Color

		if not visible_set.has(key):
			# Tree is not loaded (not in visible_tree_positions from spawner)
			tree_color = tree_hidden_color  # Dark pink
		elif camera and _is_point_in_frustum(tree_pos, camera):
			# Tree is loaded AND in camera frustum
			tree_color = tree_visible_color  # Pink
			count_in_frustum += 1
		else:
			# Tree is loaded but frustum-culled
			tree_color = tree_culled_color  # Black
			count_culled += 1

		if visible_set.has(key):
			count_loaded += 1

		# Draw the tree dot
		draw_circle(tree_screen_pos, tree_dot_size, tree_color)

	# Debug output (only print once per second to avoid spam)
	var time = Time.get_ticks_msec() / 1000.0
	if int(time) != int(time - get_process_delta_time()):
		print("Minimap Trees: Loaded=", count_loaded, " InFrustum=", count_in_frustum, " Culled=", count_culled, " Total=", all_tree_positions.size())
		if camera:
			print("  Camera pos: ", camera.global_position, " rot: ", camera.global_rotation_degrees)
			print("  Camera FOV: ", camera.fov if camera.projection == Camera3D.PROJECTION_PERSPECTIVE else "N/A (orthogonal)")
			var frustum = camera.get_frustum()
			print("  Frustum planes: ", frustum.size())
			# Test a tree position if we have any
			if all_tree_positions.size() > 0:
				var test_tree = all_tree_positions[0]
				print("  Test tree pos: ", test_tree)
				var in_frustum = _is_point_in_frustum(test_tree, camera)
				print("  Test tree in frustum: ", in_frustum)
				for i in range(frustum.size()):
					var dist = frustum[i].distance_to(test_tree)
					print("    Plane ", i, " distance: ", dist, " (negative = outside)")
		else:
			print("  Camera is null!")


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
		var marker_label: String = marker.label
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

		# Draw label in center of marker with outline for visibility
		var font_size = 10
		var string_size = ThemeDB.fallback_font.get_string_size(marker_label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var label_pos = Vector2(marker_screen_pos.x - string_size.x / 2.0, marker_screen_pos.y + 4)

		# Draw outline
		for offset in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_string(ThemeDB.fallback_font, label_pos + offset, marker_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)

		# Draw label
		draw_string(ThemeDB.fallback_font, label_pos, marker_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


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
