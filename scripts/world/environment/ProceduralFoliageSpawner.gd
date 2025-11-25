# ProceduralFoliageSpawner.gd
# Chunk-based procedural foliage spawning system for open-world environments
# Supports multiple foliage layers (trees, bushes, rocks, grass) via FoliageLayer resources
# Each chunk gets its own MultiMeshInstance3D per layer that can be loaded/unloaded independently
class_name ProceduralFoliageSpawner
extends Node3D

# Foliage layer configuration
@export_group("Foliage Layers")
@export var foliage_layers: Array[FoliageLayer] = []

# Chunk configuration
@export_group("Chunk Settings")
@export var chunk_size: float = 256.0  # Size of each chunk in meters (larger = fewer chunks, more items per chunk)
@export var chunk_load_distance: float = 300.0  # Distance to load chunks (must be > visibility range to prevent pop-in)
@export var chunk_unload_distance: float = 350.0  # Distance to unload chunks (should be > load_distance)
@export var chunks_per_frame: int = 2  # Max chunks to load/unload per frame (increase for smoother loading)
@export var follow_player: bool = true
@export var use_custom_aabb: bool = true  # Set custom AABB for better frustum culling

# Global visibility settings (can be overridden per layer)
@export_group("Global Visibility")
@export var global_visibility_range_begin: float = 0.0
@export var global_visibility_range_end: float = 120.0
@export var global_visibility_fade_margin: float = 20.0

# Debug settings
@export_group("Debug")
@export var debug_show_on_minimap: bool = false
@export var debug_performance: bool = false
@export var debug_detailed_profiling: bool = false  # Detailed timing breakdown

# Internal variables
var terrain: Terrain3D = null
var player: Node3D = null

# Chunk management
var loaded_chunks: Dictionary = {}  # chunk_key -> ChunkData
var last_player_chunk: Vector2i = Vector2i.MAX

# MultiMesh pooling - reuse nodes instead of create/destroy
var mmi_pool: Array[MultiMeshInstance3D] = []

# Performance tracking
var perf_chunks_loaded: int = 0
var perf_chunks_unloaded: int = 0
var perf_timer: float = 0.0

# Detailed profiling accumulators (reset every second)
var prof_terrain_query_time: float = 0.0
var prof_terrain_query_count: int = 0
var prof_spacing_check_time: float = 0.0
var prof_multimesh_creation_time: float = 0.0
var prof_transform_set_time: float = 0.0
var prof_chunk_gen_time: float = 0.0
var prof_total_frame_time: float = 0.0


# Per-layer instance data
class LayerInstanceData:
	var layer_name: String
	var multimesh_instances: Array[MultiMeshInstance3D] = []
	var item_transforms: Array[Transform3D] = []  # Cached for regeneration
	var lod_level: int = 0  # Current LOD level

	func _init(name: String):
		layer_name = name


# Chunk data structure - now holds multiple layers
class ChunkData:
	var chunk_key: String
	var world_pos: Vector2  # World position of chunk origin
	var layers: Dictionary = {}  # layer_name -> LayerInstanceData
	var load_time: float = 0.0  # Time when chunk was loaded (for fade-in effect)

	func _init(key: String, pos: Vector2, current_time: float = 0.0):
		chunk_key = key
		world_pos = pos
		load_time = current_time


func _ready():
	# Add to foliage_spawner group for minimap integration
	add_to_group("foliage_spawner")
	add_to_group("tree_spawner")  # Keep for backwards compatibility

	# Find terrain
	terrain = get_node_or_null("/root/TestScene/Level/Terrain3D")
	if not terrain:
		push_warning("ProceduralFoliageSpawner: No Terrain3D found at /root/TestScene/Level/Terrain3D")

	# Initialize all foliage layers
	var active_layers = 0
	for layer in foliage_layers:
		if layer.initialize():
			layer.cache_meshes()
			active_layers += 1
			print("  Initialized layer: ", layer.layer_name, " (", layer.cached_meshes.size(), " meshes)")
		else:
			if layer.enabled:
				push_warning("  Failed to initialize layer: ", layer.layer_name)

	if active_layers == 0:
		push_error("ProceduralFoliageSpawner: No active foliage layers!")
		return

	# Find player
	player = get_tree().get_first_node_in_group("player")
	if not player:
		push_warning("ProceduralFoliageSpawner: No player found in 'player' group")
	else:
		# Load initial chunks around player
		call_deferred("_load_initial_chunks")

	print("ProceduralFoliageSpawner: Chunk-based streaming initialized")
	print("  Active layers: ", active_layers)
	print("  Chunk size: ", chunk_size, "m")
	print("  Load distance: ", chunk_load_distance, "m")
	print("  Unload distance: ", chunk_unload_distance, "m")


func _get_pooled_mmi() -> MultiMeshInstance3D:
	"""Get a MultiMeshInstance3D from pool or create new one"""
	var result_mmi: MultiMeshInstance3D
	if mmi_pool.size() > 0:
		result_mmi = mmi_pool.pop_back()
		result_mmi.visible = true
	else:
		# Create new if pool is empty
		result_mmi = MultiMeshInstance3D.new()
		result_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(result_mmi)
	return result_mmi


func _return_to_pool(mmi: MultiMeshInstance3D):
	"""Return a MultiMeshInstance3D to the pool for reuse"""
	mmi.visible = false
	mmi.position = Vector3.ZERO
	mmi.material_override = null
	# Clear the multimesh data but keep the node
	if mmi.multimesh:
		mmi.multimesh.instance_count = 0
	mmi_pool.append(mmi)


func _get_lod_level(distance: float, layer: FoliageLayer) -> int:
	"""Get LOD level based on distance: 0=full, 1=medium, 2=far"""
	if not layer.use_lod:
		return 0

	if distance <= layer.lod_distance_near:
		return 0  # Full detail
	if distance <= layer.lod_distance_mid:
		return 1  # Medium detail
	return 2  # Far/low detail


func _apply_lod_to_items(items: Array[Transform3D], lod_level: int, layer: FoliageLayer) -> Array[Transform3D]:
	"""Reduce item count for distant chunks based on LOD level."""
	if lod_level == 0 or items.size() == 0 or not layer.use_lod:
		return items

	var keep_ratio: float
	if lod_level == 1:
		keep_ratio = layer.lod_mid_scale_factor
	else:
		keep_ratio = layer.lod_far_scale_factor

	var items_to_keep = max(1, int(items.size() * keep_ratio))
	var result: Array[Transform3D] = []

	# Use deterministic selection (every Nth item) for consistent appearance
	var step = float(items.size()) / float(items_to_keep)
	var index: float = 0.0
	while result.size() < items_to_keep and int(index) < items.size():
		result.append(items[int(index)])
		index += step

	return result


func _create_shader_fade_material(layer: FoliageLayer, mesh: Mesh, _chunk_load_time: float) -> ShaderMaterial:
	"""Create a shader material with distance-based fading for a layer"""
	var fade_shader = Shader.new()
	fade_shader.code = """
shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_texture = true;
uniform float fade_start = 100.0;
uniform float fade_end = 120.0;

varying float vertex_distance;

// Hash function for dithering
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vertex_distance = length(world_pos - INV_VIEW_MATRIX[3].xyz);
}

void fragment() {
	vec4 color;
	if (use_texture) {
		color = texture(albedo_texture, UV) * albedo_color;
	} else {
		color = albedo_color;
	}

	// Calculate distance-based fade
	float fade_range = fade_end - fade_start;
	float distance_fade = 1.0 - clamp((vertex_distance - fade_start) / fade_range, 0.0, 1.0);

	// Use dithering for fade to maintain proper depth sorting
	float dither = hash(FRAGCOORD.xy);
	if (dither > distance_fade) {
		discard;
	}

	ALBEDO = color.rgb;

	// Still need alpha for texture cutout (leaves, etc)
	if (color.a < 0.5) {
		discard;
	}
}
"""

	var fade_mat = ShaderMaterial.new()
	fade_mat.shader = fade_shader

	# Use layer-specific visibility settings
	var fade_start = global_visibility_range_end - layer.visibility_fade_margin
	var fade_end = global_visibility_range_end

	if layer.use_custom_visibility_range:
		fade_start = layer.visibility_range_end - layer.visibility_fade_margin
		fade_end = layer.visibility_range_end

	fade_mat.set_shader_parameter("fade_start", fade_start)
	fade_mat.set_shader_parameter("fade_end", fade_end)

	# Copy texture from original mesh material if available
	if mesh.surface_get_material(0) is StandardMaterial3D:
		var orig_mat = mesh.surface_get_material(0) as StandardMaterial3D
		if orig_mat.albedo_texture:
			fade_mat.set_shader_parameter("albedo_texture", orig_mat.albedo_texture)
			fade_mat.set_shader_parameter("use_texture", true)
		fade_mat.set_shader_parameter("albedo_color", orig_mat.albedo_color)

	return fade_mat


func _load_initial_chunks():
	"""Load chunks around player on startup"""
	if not player:
		print("ProceduralFoliageSpawner: Cannot load initial chunks - no player found")
		return

	var player_pos = player.global_position
	print("ProceduralFoliageSpawner: Loading initial chunks around player at ", player_pos)
	last_player_chunk = Vector2i(int(floor(player_pos.x / chunk_size)), int(floor(player_pos.z / chunk_size)))
	update_chunks(player_pos)
	print("ProceduralFoliageSpawner: Loaded initial chunks. Total chunks loaded: ", loaded_chunks.size())


func _process(delta):
	if not player or not follow_player:
		return

	var frame_start = Time.get_ticks_usec()

	# Performance debug
	if debug_performance or debug_detailed_profiling:
		perf_timer += delta
		if perf_timer >= 1.0:
			var total_items = 0
			for chunk in loaded_chunks.values():
				for layer_data in chunk.layers.values():
					total_items += layer_data.item_transforms.size()

			if debug_performance and (perf_chunks_loaded > 0 or perf_chunks_unloaded > 0):
				print("FoliageSpawner: Loaded=", perf_chunks_loaded, " Unloaded=", perf_chunks_unloaded, " Chunks=", loaded_chunks.size(), " Items=", total_items)

			# Detailed profiling output
			if debug_detailed_profiling:
				print("=== FOLIAGE SPAWNER PROFILING (last 1s) ===")
				print("  Chunks loaded: ", perf_chunks_loaded, " | Unloaded: ", perf_chunks_unloaded)
				print("  Total chunks: ", loaded_chunks.size(), " | Total items: ", total_items)
				print("  --- Timing Breakdown ---")
				print("  Terrain queries: ", "%.2f" % (prof_terrain_query_time * 1000), "ms (", prof_terrain_query_count, " queries)")
				if prof_terrain_query_count > 0:
					print("    Avg per query: ", "%.4f" % ((prof_terrain_query_time / prof_terrain_query_count) * 1000), "ms")
				print("  Spacing checks: ", "%.2f" % (prof_spacing_check_time * 1000), "ms")
				print("  Chunk generation: ", "%.2f" % (prof_chunk_gen_time * 1000), "ms")
				print("  MultiMesh creation: ", "%.2f" % (prof_multimesh_creation_time * 1000), "ms")
				print("  Transform setting: ", "%.2f" % (prof_transform_set_time * 1000), "ms")
				print("  Total frame time: ", "%.2f" % (prof_total_frame_time * 1000), "ms")
				print("========================================")

			# Reset counters
			perf_chunks_loaded = 0
			perf_chunks_unloaded = 0
			perf_timer = 0.0
			prof_terrain_query_time = 0.0
			prof_terrain_query_count = 0
			prof_spacing_check_time = 0.0
			prof_multimesh_creation_time = 0.0
			prof_transform_set_time = 0.0
			prof_chunk_gen_time = 0.0
			prof_total_frame_time = 0.0

	# Update chunks every frame to ensure continuous loading
	var player_pos = player.global_position
	var current_chunk = Vector2i(int(floor(player_pos.x / chunk_size)), int(floor(player_pos.z / chunk_size)))
	last_player_chunk = current_chunk
	update_chunks(player_pos)

	if debug_detailed_profiling:
		prof_total_frame_time += float(Time.get_ticks_usec() - frame_start) / 1000000.0


func update_chunks(player_pos: Vector3):
	"""Load nearby chunks and unload distant chunks"""
	var load_radius = int(ceil(chunk_load_distance / chunk_size))
	var unload_distance_sq = chunk_unload_distance * chunk_unload_distance

	var player_chunk_x = int(floor(player_pos.x / chunk_size))
	var player_chunk_z = int(floor(player_pos.z / chunk_size))

	# Find chunks to load
	var chunks_to_load: Array[Vector2i] = []
	for x in range(-load_radius, load_radius + 1):
		for z in range(-load_radius, load_radius + 1):
			var chunk_x = player_chunk_x + x
			var chunk_z = player_chunk_z + z
			var chunk_key = str(chunk_x) + "_" + str(chunk_z)

			# Skip if already loaded
			if loaded_chunks.has(chunk_key):
				continue

			# Check circular distance
			var chunk_center = Vector3(chunk_x * chunk_size + chunk_size * 0.5, 0, chunk_z * chunk_size + chunk_size * 0.5)
			var dist_sq = player_pos.distance_squared_to(chunk_center)
			if dist_sq <= chunk_load_distance * chunk_load_distance:
				chunks_to_load.append(Vector2i(chunk_x, chunk_z))

	# Sort by distance (load closest first)
	chunks_to_load.sort_custom(
		func(a, b):
			var pos_a = Vector3(a.x * chunk_size + chunk_size * 0.5, 0, a.y * chunk_size + chunk_size * 0.5)
			var pos_b = Vector3(b.x * chunk_size + chunk_size * 0.5, 0, b.y * chunk_size + chunk_size * 0.5)
			return player_pos.distance_squared_to(pos_a) < player_pos.distance_squared_to(pos_b)
	)

	# Load chunks (limited per frame)
	var loaded_this_frame = 0
	for chunk_coord in chunks_to_load:
		if loaded_this_frame >= chunks_per_frame:
			break
		load_chunk(chunk_coord.x, chunk_coord.y)
		loaded_this_frame += 1

	# Find chunks to unload
	var chunks_to_unload: Array[String] = []
	for chunk_key in loaded_chunks.keys():
		var chunk_data: ChunkData = loaded_chunks[chunk_key]
		var chunk_center = Vector3(chunk_data.world_pos.x + chunk_size * 0.5, 0, chunk_data.world_pos.y + chunk_size * 0.5)
		var dist_sq = player_pos.distance_squared_to(chunk_center)
		if dist_sq > unload_distance_sq:
			chunks_to_unload.append(chunk_key)

	# Unload chunks (limited per frame)
	var unloaded_this_frame = 0
	for chunk_key in chunks_to_unload:
		if unloaded_this_frame >= chunks_per_frame:
			break
		unload_chunk(chunk_key)
		unloaded_this_frame += 1


func load_chunk(chunk_x: int, chunk_z: int):
	"""Generate and load a chunk with all foliage layers"""
	var chunk_key = str(chunk_x) + "_" + str(chunk_z)

	if loaded_chunks.has(chunk_key):
		return  # Already loaded

	var chunk_world_x = float(chunk_x) * chunk_size
	var chunk_world_z = float(chunk_z) * chunk_size
	var chunk_load_time = Time.get_ticks_msec() / 1000.0
	var chunk_data = ChunkData.new(chunk_key, Vector2(chunk_world_x, chunk_world_z), chunk_load_time)

	var chunk_center = Vector3(chunk_world_x + chunk_size * 0.5, 0, chunk_world_z + chunk_size * 0.5)
	var player_pos = player.global_position if player else Vector3.ZERO
	var chunk_distance = chunk_center.distance_to(player_pos)

	var has_any_items = false

	# Generate foliage for each layer
	for layer in foliage_layers:
		if not layer.enabled:
			continue

		# Generate items for this layer
		var gen_start = Time.get_ticks_usec()
		var items_in_chunk = generate_items_for_layer(chunk_world_x, chunk_world_z, layer)
		if debug_detailed_profiling:
			prof_chunk_gen_time += float(Time.get_ticks_usec() - gen_start) / 1000000.0

		if items_in_chunk.size() == 0:
			continue

		has_any_items = true

		# Calculate LOD level for this layer
		var lod_level = _get_lod_level(chunk_distance, layer)

		# Apply LOD
		var items_to_render = items_in_chunk
		if layer.use_lod and lod_level > 0:
			items_to_render = _apply_lod_to_items(items_in_chunk, lod_level, layer)

		if items_to_render.size() == 0:
			continue

		# Create layer instance data
		var layer_data = LayerInstanceData.new(layer.layer_name)
		layer_data.item_transforms = items_in_chunk
		layer_data.lod_level = lod_level

		# Create MultiMesh instances for this layer
		var mm_start = Time.get_ticks_usec()
		for mesh in layer.cached_meshes:
			var multimesh = MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = mesh
			multimesh.instance_count = items_to_render.size()

			if debug_detailed_profiling:
				prof_multimesh_creation_time += float(Time.get_ticks_usec() - mm_start) / 1000000.0

			# Set transforms for all items (relative to chunk center)
			var transform_start = Time.get_ticks_usec()
			for i in range(items_to_render.size()):
				var item_transform: Transform3D = items_to_render[i]
				var relative_transform = item_transform
				relative_transform.origin -= chunk_center
				multimesh.set_instance_transform(i, relative_transform)
			if debug_detailed_profiling:
				prof_transform_set_time += float(Time.get_ticks_usec() - transform_start) / 1000000.0

			var mmi = _get_pooled_mmi()
			mmi.multimesh = multimesh
			mmi.position = chunk_center

			# Set custom AABB for proper frustum culling
			if use_custom_aabb:
				var aabb = AABB(
					Vector3(-chunk_size * 0.5, -10, -chunk_size * 0.5),
					Vector3(chunk_size, 50, chunk_size)
				)
				mmi.custom_aabb = aabb

			# Apply shader-based distance fading if layer uses custom visibility range
			if layer.use_custom_visibility_range:
				var fade_mat = _create_shader_fade_material(layer, mesh, chunk_load_time)
				mmi.material_override = fade_mat
			else:
				mmi.material_override = null

			# Setup visibility range (NOT GPU-based, just for hard culling)
			# Shader handles the fading
			var vis_range_end = global_visibility_range_end
			if layer.use_custom_visibility_range:
				vis_range_end = layer.visibility_range_end

			mmi.visibility_range_begin = global_visibility_range_begin
			mmi.visibility_range_end = vis_range_end
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

			# Shadow settings
			if layer.cast_shadows:
				if layer.use_distance_fade_shadows and chunk_distance > layer.shadow_distance:
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				else:
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			else:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

			layer_data.multimesh_instances.append(mmi)
			mm_start = Time.get_ticks_usec()

		chunk_data.layers[layer.layer_name] = layer_data

	if has_any_items:
		loaded_chunks[chunk_key] = chunk_data
		if debug_performance or debug_detailed_profiling:
			perf_chunks_loaded += 1


func unload_chunk(chunk_key: String):
	"""Unload a chunk and return its resources to pool"""
	if not loaded_chunks.has(chunk_key):
		return

	var chunk_data: ChunkData = loaded_chunks[chunk_key]

	# Return all MultiMeshInstance3D nodes to pool for all layers
	for layer_data in chunk_data.layers.values():
		for mmi in layer_data.multimesh_instances:
			_return_to_pool(mmi)

	# Remove from loaded chunks
	loaded_chunks.erase(chunk_key)

	if debug_performance or debug_detailed_profiling:
		perf_chunks_unloaded += 1


func generate_items_for_layer(chunk_x: float, chunk_z: float, layer: FoliageLayer) -> Array[Transform3D]:
	"""Generate item transforms for a layer in a chunk using spatial hashing for O(1) spacing checks"""
	var items: Array[Transform3D] = []

	# Create a seeded RNG for this chunk and layer - deterministic but truly random distribution
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(int(chunk_x)) + "_" + str(int(chunk_z)) + "_" + layer.layer_name)

	var chunk_area = chunk_size * chunk_size
	var target_item_count = int(chunk_area * layer.density)
	var max_attempts = target_item_count * 4
	var attempts = 0

	# Spatial hash grid for O(1) spacing checks
	var cell_size = layer.min_spacing
	var grid: Dictionary = {}  # Vector2i -> Array[Vector2]

	# Pass 1: Generate candidate positions with spatial hash spacing checks
	var candidates: Array[Dictionary] = []

	while candidates.size() < target_item_count and attempts < max_attempts:
		var rand_x = rng.randf()
		var rand_z = rng.randf()

		var local_x = rand_x * chunk_size + chunk_x
		var local_z = rand_z * chunk_size + chunk_z

		attempts += 1

		# Spatial hash check
		var spacing_start = Time.get_ticks_usec()
		var new_pos = Vector2(local_x, local_z)
		var cell = Vector2i(int(floor(local_x / cell_size)), int(floor(local_z / cell_size)))

		var too_close = false
		# Check 3x3 grid of cells around this position
		for dx in range(-1, 2):
			if too_close:
				break
			for dz in range(-1, 2):
				if too_close:
					break
				var check_cell = Vector2i(cell.x + dx, cell.y + dz)
				if grid.has(check_cell):
					for existing_pos in grid[check_cell]:
						if new_pos.distance_squared_to(existing_pos) < layer.min_spacing * layer.min_spacing:
							too_close = true
							break

		if debug_detailed_profiling:
			prof_spacing_check_time += float(Time.get_ticks_usec() - spacing_start) / 1000000.0

		if too_close:
			continue

		# Add to spatial hash grid
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(new_pos)

		# Pre-generate random values for this candidate
		var item_scale = rng.randf_range(layer.min_scale, layer.max_scale)
		var item_rotation = rng.randf() * TAU if layer.random_rotation else 0.0

		candidates.append({
			"pos": Vector3(local_x, 0, local_z),
			"scale": item_scale,
			"rotation": item_rotation
		})

	# Pass 2: Batch validate terrain constraints
	var query_start = Time.get_ticks_usec()
	for candidate in candidates:
		var pos: Vector3 = candidate["pos"]
		var spawn_result = layer.validate_spawn_position(pos, terrain)
		if spawn_result["valid"]:
			var item_transform = Transform3D()

			# Align to terrain normal if requested
			if layer.align_to_terrain_normal and spawn_result.has("normal"):
				var normal: Vector3 = spawn_result["normal"]
				var up = Vector3.UP
				var right = up.cross(normal).normalized()
				var forward = normal.cross(right).normalized()
				item_transform.basis = Basis(right, normal, forward)
				item_transform = item_transform.rotated(normal, candidate["rotation"])
			else:
				item_transform = item_transform.rotated(Vector3.UP, candidate["rotation"])

			item_transform = item_transform.scaled(Vector3.ONE * candidate["scale"])
			item_transform.origin = Vector3(pos.x, spawn_result["height"], pos.z)
			items.append(item_transform)

	if debug_detailed_profiling:
		prof_terrain_query_time += float(Time.get_ticks_usec() - query_start) / 1000000.0
		prof_terrain_query_count += candidates.size() * 2  # height + normal per candidate

	return items


func get_all_item_positions() -> Array[Vector3]:
	"""Get all item positions from all layers (for minimap)"""
	var positions: Array[Vector3] = []
	for chunk_data in loaded_chunks.values():
		for layer_data in chunk_data.layers.values():
			for item_trans in layer_data.item_transforms:
				positions.append(item_trans.origin)
	return positions


func get_visible_item_positions() -> Array[Vector3]:
	"""Get positions of visible items (for minimap)"""
	return get_all_item_positions()


# Backwards compatibility methods
func get_all_tree_positions() -> Array[Vector3]:
	"""Get all tree positions (for minimap) - backwards compatibility"""
	return get_all_item_positions()


func get_visible_tree_positions() -> Array[Vector3]:
	"""Get positions of visible trees (for minimap) - backwards compatibility"""
	return get_visible_item_positions()


func is_debug_mode_enabled() -> bool:
	return debug_show_on_minimap
