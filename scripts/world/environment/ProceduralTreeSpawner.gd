# ProceduralTreeSpawner.gd
# Chunk-based procedural tree spawning system for open-world environments
# Each chunk gets its own MultiMeshInstance3D that can be loaded/unloaded independently
class_name ProceduralTreeSpawner
extends Node3D

# Tree configuration
@export_group("Tree Settings")
@export var tree_scene_path: String = "res://assets/models/foliage/resinwood_tree_s.tscn"
@export var tree_density: float = 0.03  # Trees per square meter (reduced for performance)
@export var min_tree_scale: float = 0.8
@export var max_tree_scale: float = 1.4
@export var random_rotation: bool = true

# Chunk configuration
@export_group("Chunk Settings")
@export var chunk_size: float = 128.0  # Size of each chunk in meters (larger = fewer chunks, more trees per chunk)
@export var chunk_load_distance: float = 150.0  # Distance to load chunks (reduced for performance)
@export var chunk_unload_distance: float = 180.0  # Distance to unload chunks (should be > load_distance)
@export var chunks_per_frame: int = 2  # Max chunks to load/unload per frame (lower for larger chunks)
@export var follow_player: bool = true

# Terrain constraints
@export_group("Terrain Constraints")
@export var min_slope: float = 0.0
@export var max_slope: float = 0.5
@export var min_height: float = -100.0
@export var max_height: float = 100.0
@export var water_level: float = 0.0

# Noise settings for natural distribution
@export_group("Distribution Noise")
@export var use_noise_distribution: bool = false
@export var noise_threshold: float = -0.5
@export var noise_scale: float = 0.02
@export var noise_seed: int = 0

# Distribution quality settings
@export_group("Distribution Quality")
@export var min_tree_spacing: float = 2.5  # Minimum distance between trees

# GPU culling settings
@export_group("GPU Culling")
@export var use_visibility_range: bool = true  # Use GPU-based culling
@export var visibility_range_begin: float = 0.0
@export var visibility_range_end: float = 150.0  # Reduced for performance
@export var visibility_fade_margin: float = 20.0
@export var shadow_distance: float = 60.0  # Distance beyond which shadows are disabled (aggressive)
@export var use_distance_fade_shadows: bool = true  # Fade shadows based on distance

# LOD settings
@export_group("LOD Settings")
@export var use_lod: bool = true  # Enable distance-based LOD
@export var lod_distance_near: float = 50.0  # Full detail up to this distance (reduced)
@export var lod_distance_mid: float = 100.0  # Medium detail up to this distance (reduced)
@export var lod_mid_scale_factor: float = 0.4  # Keep 40% of trees at mid range
@export var lod_far_scale_factor: float = 0.15  # Keep 15% of trees at far range

# Impostor/Billboard settings (for very far trees)
@export_group("Impostor Settings")
@export var use_impostors: bool = false  # Enable billboard impostors for far trees
@export var impostor_texture: Texture2D = null  # Billboard texture (optional)
@export var impostor_distance: float = 120.0  # Distance beyond which to use impostors
@export var impostor_size: Vector2 = Vector2(4.0, 8.0)  # Billboard size (width, height)
@export var lod_fade_range: float = 20.0  # Distance over which LOD transition fades (smooth blend zone)
@export var chunk_fade_in_duration: float = 0.5  # Time in seconds for chunks to fade in when loaded

# Debug settings
@export_group("Debug")
@export var debug_show_on_minimap: bool = false
@export var debug_performance: bool = false
@export var debug_detailed_profiling: bool = false  # Detailed timing breakdown

# Internal variables
var terrain: Terrain3D = null
var tree_scene: PackedScene = null
var noise: FastNoiseLite = null
var player: Node3D = null

# Chunk management
var loaded_chunks: Dictionary = {}  # chunk_key -> ChunkData
var last_player_chunk: Vector2i = Vector2i.MAX

# MultiMesh pooling - reuse nodes instead of create/destroy
var mmi_pool: Array[MultiMeshInstance3D] = []
var cached_meshes: Array[Mesh] = []  # Cached meshes from tree scene

# Impostor system
var impostor_mesh: QuadMesh = null
var impostor_material: ShaderMaterial = null

# LOD fade shaders
var tree_fade_shader: Shader = null
var impostor_fade_shader: Shader = null

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

# LOD statistics (for debugging)
var lod_chunks_near: int = 0
var lod_chunks_mid: int = 0
var lod_chunks_far: int = 0
var lod_impostor_chunks: int = 0
var lod_shadows_disabled: int = 0


# Chunk data structure
class ChunkData:
	var chunk_key: String
	var world_pos: Vector2  # World position of chunk origin
	var multimesh_instances: Array[MultiMeshInstance3D] = []  # 3D tree meshes
	var impostor_instances: Array[MultiMeshInstance3D] = []  # Billboard impostors (rendered simultaneously for crossfade)
	var tree_transforms: Array[Transform3D] = []  # Cached for regeneration
	var has_impostors: bool = false  # Track if chunk has impostor layer
	var load_time: float = 0.0  # Time when chunk was loaded (for fade-in effect)

	func _init(key: String, pos: Vector2, current_time: float = 0.0):
		chunk_key = key
		world_pos = pos
		# Store the current shader TIME when chunk is loaded
		load_time = current_time


func _ready():
	# Add to tree_spawner group for minimap integration
	add_to_group("tree_spawner")

	# Find terrain
	terrain = get_node_or_null("/root/TestScene/Level/Terrain3D")
	if not terrain:
		push_warning("ProceduralTreeSpawner: No Terrain3D found at /root/TestScene/Level/Terrain3D")

	# Load tree scene and cache meshes
	if FileAccess.file_exists(tree_scene_path):
		tree_scene = load(tree_scene_path)
		if not tree_scene:
			push_error("ProceduralTreeSpawner: Failed to load tree scene: ", tree_scene_path)
			return
		# Cache meshes from tree scene for reuse
		_cache_tree_meshes()
	else:
		push_error("ProceduralTreeSpawner: Tree scene not found: ", tree_scene_path)
		return

	# Setup noise
	if use_noise_distribution:
		noise = FastNoiseLite.new()
		noise.seed = noise_seed
		noise.frequency = noise_scale

	# Setup impostor system (includes fade shaders)
	if use_impostors:
		_setup_impostor_system()
	elif chunk_fade_in_duration > 0:
		# Create fade shaders even without impostors for chunk fade-in
		_create_lod_fade_shaders()

	# Find player
	player = get_tree().get_first_node_in_group("player")
	if not player:
		push_warning("ProceduralTreeSpawner: No player found in 'player' group")
	else:
		# Load initial chunks around player
		call_deferred("_load_initial_chunks")

	print("ProceduralTreeSpawner: Chunk-based streaming initialized")
	print("  Chunk size: ", chunk_size, "m")
	print("  Load distance: ", chunk_load_distance, "m")
	print("  Unload distance: ", chunk_unload_distance, "m")
	print("  GPU culling: ", use_visibility_range)
	print("  Cached meshes: ", cached_meshes.size())


func _cache_tree_meshes():
	"""Cache meshes from tree scene for reuse in pooling"""
	var temp_tree = tree_scene.instantiate()
	var mesh_nodes = get_all_mesh_instances(temp_tree)
	for mesh_node in mesh_nodes:
		if mesh_node.mesh:
			cached_meshes.append(mesh_node.mesh)
	temp_tree.queue_free()


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
	# Clear the multimesh data but keep the node
	if mmi.multimesh:
		mmi.multimesh.instance_count = 0
	mmi_pool.append(mmi)


func _get_lod_level(distance: float) -> int:
	"""Get LOD level based on distance: 0=full, 1=medium, 2=far"""
	if distance <= lod_distance_near:
		return 0  # Full detail
	if distance <= lod_distance_mid:
		return 1  # Medium detail
	return 2  # Far/low detail


func _apply_lod_to_trees(trees: Array[Transform3D], lod_level: int) -> Array[Transform3D]:
	"""Reduce tree count for distant chunks based on LOD level.
	LOD 1 (medium): Keep 60% of trees
	LOD 2 (far): Keep 30% of trees"""
	if lod_level == 0 or trees.size() == 0:
		return trees

	var keep_ratio: float
	if lod_level == 1:
		keep_ratio = lod_mid_scale_factor
	else:
		keep_ratio = lod_far_scale_factor

	var trees_to_keep = max(1, int(trees.size() * keep_ratio))
	var result: Array[Transform3D] = []

	# Use deterministic selection (every Nth tree) for consistent appearance
	var step = float(trees.size()) / float(trees_to_keep)
	var index: float = 0.0
	while result.size() < trees_to_keep and int(index) < trees.size():
		result.append(trees[int(index)])
		index += step

	return result


func _setup_impostor_system():
	"""Setup the impostor/billboard rendering system for far trees with distance-based fading"""
	# Create billboard quad mesh
	impostor_mesh = QuadMesh.new()
	impostor_mesh.size = impostor_size
	impostor_mesh.orientation = PlaneMesh.FACE_Z  # Face forward for billboard

	# Create impostor fade shader for smooth LOD transitions
	_create_lod_fade_shaders()

	# Create billboard shader material with distance fade
	impostor_material = ShaderMaterial.new()
	impostor_material.shader = impostor_fade_shader
	impostor_material.set_shader_parameter("fade_start", impostor_distance - lod_fade_range)
	impostor_material.set_shader_parameter("fade_end", impostor_distance)

	# Apply texture if provided
	if impostor_texture:
		impostor_material.set_shader_parameter("albedo_texture", impostor_texture)
		impostor_material.set_shader_parameter("use_texture", true)
	else:
		impostor_material.set_shader_parameter("albedo_color", Color(0.2, 0.4, 0.15, 1.0))
		impostor_material.set_shader_parameter("use_texture", false)

	print("  Impostor system: Enabled (distance: ", impostor_distance, "m, fade range: ", lod_fade_range, "m)")


func _create_lod_fade_shaders():
	"""Create shaders for smooth LOD fading based on camera distance.
	Uses alpha_hash dithering for proper depth testing (no sorting issues).
	Also supports chunk fade-in when loaded.

	IMPORTANT: The fade curves overlap to prevent gaps during transitions.
	- 3D trees stay at full opacity until fade_end, then fade out
	- Impostors start fading in at fade_start, reaching full opacity at fade_end
	- Both are visible in the overlap zone for smooth handoff"""
	# Shader for impostors (billboards) - fades IN at distance
	impostor_fade_shader = Shader.new()
	impostor_fade_shader.code = """
shader_type spatial;
render_mode depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(0.2, 0.4, 0.15, 1.0);
uniform bool use_texture = false;
uniform float fade_start = 100.0;
uniform float fade_end = 120.0;
uniform float chunk_load_time = 0.0;
uniform float chunk_fade_duration = 0.5;

varying float vertex_distance;

// Hash function for dithering
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	// Billboard: make quad face camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);

	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vertex_distance = length(world_pos - INV_VIEW_MATRIX[3].xyz);
}

void fragment() {
	vec4 color;
	if (use_texture) {
		color = texture(albedo_texture, UV);
	} else {
		color = albedo_color;
	}

	// Alpha scissor for texture edges
	if (color.a < 0.5) {
		discard;
	}

	// Calculate distance-based fade for impostors
	// Impostors should be fully visible beyond fade_end, and fade OUT as we get closer
	// This ensures overlap: trees fade out from midpoint->fade_end, impostors fade out from fade_end->fade_start
	// At any distance in the transition zone, at least one is substantially visible

	float fade_range = fade_end - fade_start;
	float midpoint = fade_start + fade_range * 0.5;

	// Impostors: fully visible beyond midpoint, fade out as we approach fade_start
	// This creates overlap with trees which stay visible until midpoint
	float distance_fade;
	if (vertex_distance >= midpoint) {
		distance_fade = 1.0;  // Fully visible beyond midpoint
	} else {
		// Fade out from midpoint down to fade_start
		distance_fade = clamp((vertex_distance - fade_start) / (midpoint - fade_start), 0.0, 1.0);
	}

	// Quick chunk load fade-in for impostors (faster than 3D trees)
	float time_since_load = TIME - chunk_load_time;
	float load_fade = clamp(time_since_load / (chunk_fade_duration * 0.3), 0.0, 1.0); // 30% of normal duration

	// Combine distance fade with quick load fade
	float final_fade = distance_fade * load_fade;

	// Use dithering for fade to maintain proper depth sorting
	float dither = hash(FRAGCOORD.xy);
	if (dither > final_fade) {
		discard;
	}

	ALBEDO = color.rgb;
}
"""

	# Shader for 3D tree models - fades OUT at distance
	tree_fade_shader = Shader.new()
	tree_fade_shader.code = """
shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_texture = true;
uniform float fade_start = 100.0;
uniform float fade_end = 120.0;
uniform float chunk_load_time = 0.0;
uniform float chunk_fade_duration = 0.5;

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

	// Calculate distance-based fade - trees fade OUT as distance increases
	// Use extended range: trees stay fully visible until midpoint, then fade out
	// This creates overlap with impostors which start fading in at fade_start
	float fade_range = fade_end - fade_start;
	float midpoint = fade_start + fade_range * 0.5;

	// Trees: fully visible until midpoint, then fade to 0 at fade_end
	float distance_fade = 1.0 - clamp((vertex_distance - midpoint) / (fade_end - midpoint), 0.0, 1.0);

	// Calculate chunk load fade-in
	float time_since_load = TIME - chunk_load_time;
	float load_fade = clamp(time_since_load / chunk_fade_duration, 0.0, 1.0);

	// Combine both fades
	float final_fade = distance_fade * load_fade;

	// Use dithering for fade to maintain proper depth sorting
	float dither = hash(FRAGCOORD.xy);
	if (dither > final_fade) {
		discard;
	}

	ALBEDO = color.rgb;

	// Still need alpha for texture cutout (leaves, etc)
	if (color.a < 0.5) {
		discard;
	}
}
"""


func _calculate_lod_stats():
	"""Calculate LOD statistics from currently loaded chunks"""
	lod_chunks_near = 0
	lod_chunks_mid = 0
	lod_chunks_far = 0
	lod_impostor_chunks = 0
	lod_shadows_disabled = 0

	if not player:
		return

	var player_pos = player.global_position

	for chunk_data in loaded_chunks.values():
		var chunk_center = Vector3(
			chunk_data.world_pos.x + chunk_size * 0.5,
			0,
			chunk_data.world_pos.y + chunk_size * 0.5
		)
		var dist = chunk_center.distance_to(player_pos)

		# Count LOD levels
		if dist <= lod_distance_near:
			lod_chunks_near += 1
		elif dist <= lod_distance_mid:
			lod_chunks_mid += 1
		else:
			lod_chunks_far += 1

		# Count impostors
		if use_impostors and dist > impostor_distance:
			lod_impostor_chunks += 1

		# Count shadows disabled
		if use_distance_fade_shadows and dist > shadow_distance:
			lod_shadows_disabled += 1


func _load_initial_chunks():
	"""Load chunks around player on startup"""
	if not player:
		print("ProceduralTreeSpawner: Cannot load initial chunks - no player found")
		return

	var player_pos = player.global_position
	print("ProceduralTreeSpawner: Loading initial chunks around player at ", player_pos)
	last_player_chunk = Vector2i(int(floor(player_pos.x / chunk_size)), int(floor(player_pos.z / chunk_size)))
	update_chunks(player_pos)
	print("ProceduralTreeSpawner: Loaded initial chunks. Total chunks loaded: ", loaded_chunks.size())


func _process(delta):
	if not player or not follow_player:
		return

	var frame_start = Time.get_ticks_usec()

	# Performance debug
	if debug_performance or debug_detailed_profiling:
		perf_timer += delta
		if perf_timer >= 1.0:
			var total_trees = 0
			for chunk in loaded_chunks.values():
				total_trees += chunk.tree_transforms.size()

			if debug_performance and (perf_chunks_loaded > 0 or perf_chunks_unloaded > 0):
				print("TreeSpawner: Loaded=", perf_chunks_loaded, " Unloaded=", perf_chunks_unloaded, " Chunks=", loaded_chunks.size(), " Trees=", total_trees)

			# Detailed profiling output
			if debug_detailed_profiling:
				# Calculate LOD stats from loaded chunks
				_calculate_lod_stats()

				print("=== TREE SPAWNER PROFILING (last 1s) ===")
				print("  Chunks loaded: ", perf_chunks_loaded, " | Unloaded: ", perf_chunks_unloaded)
				print("  Total chunks: ", loaded_chunks.size(), " | Total trees: ", total_trees)
				print("  --- LOD Breakdown ---")
				print("  LOD Near (full): ", lod_chunks_near, " chunks")
				print("  LOD Mid (", int(lod_mid_scale_factor * 100), "%): ", lod_chunks_mid, " chunks")
				print("  LOD Far (", int(lod_far_scale_factor * 100), "%): ", lod_chunks_far, " chunks")
				print("  Impostors: ", lod_impostor_chunks, " chunks")
				print("  Shadows disabled: ", lod_shadows_disabled, " chunks")
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
	# Note: No need to refresh chunks for impostor transitions anymore
	# Both 3D trees and impostors are always rendered, and shaders handle crossfade automatically


func load_chunk(chunk_x: int, chunk_z: int):
	"""Generate and load a chunk of trees with smooth LOD crossfade support"""
	var chunk_key = str(chunk_x) + "_" + str(chunk_z)

	if loaded_chunks.has(chunk_key):
		return  # Already loaded

	var chunk_world_x = float(chunk_x) * chunk_size
	var chunk_world_z = float(chunk_z) * chunk_size
	var chunk_load_time = Time.get_ticks_msec() / 1000.0
	var chunk_data = ChunkData.new(chunk_key, Vector2(chunk_world_x, chunk_world_z), chunk_load_time)

	# Generate tree positions for this chunk
	var gen_start = Time.get_ticks_usec()
	var trees_in_chunk = generate_trees_for_chunk(chunk_world_x, chunk_world_z)
	if debug_detailed_profiling:
		prof_chunk_gen_time += float(Time.get_ticks_usec() - gen_start) / 1000000.0

	if debug_performance:
		print("  Chunk ", chunk_key, " generated ", trees_in_chunk.size(), " trees")

	if trees_in_chunk.size() == 0:
		return  # No trees in this chunk

	# Create MultiMesh instances using cached meshes and pooled nodes
	var mm_start = Time.get_ticks_usec()
	var chunk_center = Vector3(chunk_world_x + chunk_size * 0.5, 0, chunk_world_z + chunk_size * 0.5)

	# Calculate chunk distance to determine LOD level
	var player_pos = player.global_position if player else Vector3.ZERO
	var chunk_distance = chunk_center.distance_to(player_pos)
	var lod_level = _get_lod_level(chunk_distance)

	# For LOD, we might skip some trees at distance or reduce detail
	var trees_to_render = trees_in_chunk
	if use_lod and lod_level > 0:
		trees_to_render = _apply_lod_to_trees(trees_in_chunk, lod_level)

	if trees_to_render.size() == 0:
		return

	# === CREATE 3D TREE MESHES ===
	# Always create 3D trees - they will fade out at impostor_distance via shader
	for mesh in cached_meshes:
		var multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = trees_to_render.size()

		if debug_detailed_profiling:
			prof_multimesh_creation_time += float(Time.get_ticks_usec() - mm_start) / 1000000.0

		# Set transforms for all trees (relative to chunk center)
		var transform_start = Time.get_ticks_usec()
		for i in range(trees_to_render.size()):
			var tree_transform: Transform3D = trees_to_render[i]
			var relative_transform = tree_transform
			relative_transform.origin -= chunk_center
			multimesh.set_instance_transform(i, relative_transform)
		if debug_detailed_profiling:
			prof_transform_set_time += float(Time.get_ticks_usec() - transform_start) / 1000000.0

		var mmi = _get_pooled_mmi()
		mmi.multimesh = multimesh
		mmi.position = chunk_center

		# Apply fade shader for smooth LOD transition and chunk fade-in
		if use_impostors and tree_fade_shader:
			var fade_mat = ShaderMaterial.new()
			fade_mat.shader = tree_fade_shader
			fade_mat.set_shader_parameter("fade_start", impostor_distance - lod_fade_range)
			fade_mat.set_shader_parameter("fade_end", impostor_distance)
			fade_mat.set_shader_parameter("chunk_load_time", chunk_data.load_time)
			fade_mat.set_shader_parameter("chunk_fade_duration", chunk_fade_in_duration)
			# Copy texture from original mesh material if available
			if mesh.surface_get_material(0) is StandardMaterial3D:
				var orig_mat = mesh.surface_get_material(0) as StandardMaterial3D
				if orig_mat.albedo_texture:
					fade_mat.set_shader_parameter("albedo_texture", orig_mat.albedo_texture)
					fade_mat.set_shader_parameter("use_texture", true)
				fade_mat.set_shader_parameter("albedo_color", orig_mat.albedo_color)
			mmi.material_override = fade_mat
		elif chunk_fade_in_duration > 0 and tree_fade_shader:
			# Even without impostors, apply fade-in shader for chunk loading
			var fade_mat = ShaderMaterial.new()
			fade_mat.shader = tree_fade_shader
			fade_mat.set_shader_parameter("fade_start", 99999.0)  # Disable distance fade
			fade_mat.set_shader_parameter("fade_end", 99999.0)
			fade_mat.set_shader_parameter("chunk_load_time", chunk_data.load_time)
			fade_mat.set_shader_parameter("chunk_fade_duration", chunk_fade_in_duration)
			if mesh.surface_get_material(0) is StandardMaterial3D:
				var orig_mat = mesh.surface_get_material(0) as StandardMaterial3D
				if orig_mat.albedo_texture:
					fade_mat.set_shader_parameter("albedo_texture", orig_mat.albedo_texture)
					fade_mat.set_shader_parameter("use_texture", true)
				fade_mat.set_shader_parameter("albedo_color", orig_mat.albedo_color)
			mmi.material_override = fade_mat
		else:
			mmi.material_override = null

		# Setup GPU-based visibility culling
		if use_visibility_range:
			mmi.visibility_range_begin = visibility_range_begin
			# Extend visibility range to include fade zone
			mmi.visibility_range_end = visibility_range_end if not use_impostors else impostor_distance + lod_fade_range
			if chunk_data.multimesh_instances.size() == 0:
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			else:
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DEPENDENCIES
			mmi.visibility_range_begin_margin = visibility_fade_margin
			mmi.visibility_range_end_margin = visibility_fade_margin

		# Optimize shadow rendering based on distance
		if use_distance_fade_shadows:
			if chunk_distance > shadow_distance:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			else:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		chunk_data.multimesh_instances.append(mmi)
		mm_start = Time.get_ticks_usec()

	# === CREATE IMPOSTOR BILLBOARDS (if enabled) ===
	# Impostors are always rendered and fade IN at impostor_distance via shader
	if use_impostors and impostor_mesh and impostor_material:
		var impostor_multimesh = MultiMesh.new()
		impostor_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		impostor_multimesh.mesh = impostor_mesh
		impostor_multimesh.instance_count = trees_to_render.size()

		# Set transforms - adjust Y position to center billboard at tree height
		for i in range(trees_to_render.size()):
			var tree_transform: Transform3D = trees_to_render[i]
			var relative_transform = tree_transform
			relative_transform.origin -= chunk_center
			# Offset billboard up by half its height so it sits on ground
			relative_transform.origin.y += impostor_size.y * 0.5 * tree_transform.basis.get_scale().y
			impostor_multimesh.set_instance_transform(i, relative_transform)

		var impostor_mmi = _get_pooled_mmi()
		impostor_mmi.multimesh = impostor_multimesh
		impostor_mmi.position = chunk_center

		# Create per-chunk impostor material with fade-in timing
		var chunk_impostor_mat = impostor_material.duplicate() as ShaderMaterial
		chunk_impostor_mat.set_shader_parameter("chunk_load_time", chunk_data.load_time)
		chunk_impostor_mat.set_shader_parameter("chunk_fade_duration", chunk_fade_in_duration)
		impostor_mmi.material_override = chunk_impostor_mat
		impostor_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # Impostors don't cast shadows

		# Setup visibility range for impostors - visible from fade start to unload distance
		if use_visibility_range:
			impostor_mmi.visibility_range_begin = impostor_distance - lod_fade_range
			impostor_mmi.visibility_range_end = chunk_unload_distance
			impostor_mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			impostor_mmi.visibility_range_begin_margin = lod_fade_range
			impostor_mmi.visibility_range_end_margin = visibility_fade_margin

		chunk_data.impostor_instances.append(impostor_mmi)
		chunk_data.has_impostors = true

	# Store chunk data (keep full transforms for potential LOD updates)
	chunk_data.tree_transforms = trees_in_chunk
	loaded_chunks[chunk_key] = chunk_data

	if debug_performance or debug_detailed_profiling:
		perf_chunks_loaded += 1


func unload_chunk(chunk_key: String):
	"""Unload a chunk and return its resources to pool"""
	if not loaded_chunks.has(chunk_key):
		return

	var chunk_data: ChunkData = loaded_chunks[chunk_key]

	# Return all MultiMeshInstance3D nodes to pool for reuse
	for mmi in chunk_data.multimesh_instances:
		_return_to_pool(mmi)

	# Return impostor instances to pool as well
	for mmi in chunk_data.impostor_instances:
		_return_to_pool(mmi)

	# Remove from loaded chunks
	loaded_chunks.erase(chunk_key)

	if debug_performance or debug_detailed_profiling:
		perf_chunks_unloaded += 1


func generate_trees_for_chunk(chunk_x: float, chunk_z: float) -> Array[Transform3D]:
	"""Generate tree transforms for a chunk using random placement with minimum spacing.
	Uses a two-pass approach for better performance:
	1. Generate candidate positions with spacing checks (cheap)
	2. Batch validate terrain constraints (expensive but batched)"""
	var trees: Array[Transform3D] = []
	var placed_positions: Array[Vector2] = []

	# Create a seeded RNG for this chunk - deterministic but truly random distribution
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(int(chunk_x)) + "_" + str(int(chunk_z)))

	var chunk_area = chunk_size * chunk_size
	var target_tree_count = int(chunk_area * tree_density)
	var max_attempts = target_tree_count * 4  # Allow more attempts for better coverage
	var attempts = 0

	# Pass 1: Generate candidate positions with spacing checks
	var candidates: Array[Dictionary] = []  # {pos: Vector3, scale: float, rotation: float}
	var candidate_positions: Array[Vector2] = []

	while candidates.size() < target_tree_count and attempts < max_attempts:
		var rand_x = rng.randf()
		var rand_z = rng.randf()

		var local_x = rand_x * chunk_size + chunk_x
		var local_z = rand_z * chunk_size + chunk_z

		attempts += 1

		# Check minimum spacing against already placed candidates
		var spacing_start = Time.get_ticks_usec()
		var too_close = false
		var new_pos = Vector2(local_x, local_z)
		for existing_pos in candidate_positions:
			if new_pos.distance_to(existing_pos) < min_tree_spacing:
				too_close = true
				break
		if debug_detailed_profiling:
			prof_spacing_check_time += float(Time.get_ticks_usec() - spacing_start) / 1000000.0

		if too_close:
			continue

		# Pre-generate random values for this candidate
		var tree_scale = rng.randf_range(min_tree_scale, max_tree_scale)
		var tree_rotation = rng.randf() * TAU if random_rotation else 0.0

		candidates.append({
			"pos": Vector3(local_x, 0, local_z),
			"scale": tree_scale,
			"rotation": tree_rotation
		})
		candidate_positions.append(new_pos)

	# Pass 2: Batch validate terrain constraints
	var query_start = Time.get_ticks_usec()
	for candidate in candidates:
		var pos: Vector3 = candidate["pos"]
		var spawn_result = validate_spawn_position(pos)
		if spawn_result["valid"]:
			var tree_transform = Transform3D()
			tree_transform = tree_transform.rotated(Vector3.UP, candidate["rotation"])
			tree_transform = tree_transform.scaled(Vector3.ONE * candidate["scale"])
			tree_transform.origin = Vector3(pos.x, spawn_result["height"], pos.z)
			trees.append(tree_transform)
			placed_positions.append(Vector2(pos.x, pos.z))

	if debug_detailed_profiling:
		prof_terrain_query_time += float(Time.get_ticks_usec() - query_start) / 1000000.0
		prof_terrain_query_count += candidates.size() * 2  # height + normal per candidate

	return trees


func validate_spawn_position(pos: Vector3) -> Dictionary:
	"""Validate if a position can spawn a tree. Returns {valid: bool, height: float}"""
	if not terrain or not terrain.data:
		return {"valid": false, "height": 0.0}

	# Get terrain height
	var height = terrain.data.get_height(pos)
	if is_nan(height):
		return {"valid": false, "height": 0.0}

	# Check height constraints
	if height < min_height or height > max_height:
		return {"valid": false, "height": 0.0}

	# Check water level
	if height < water_level:
		return {"valid": false, "height": 0.0}

	# Check slope
	var normal = terrain.data.get_normal(pos)
	var slope = 1.0 - normal.y
	if slope < min_slope or slope > max_slope:
		return {"valid": false, "height": 0.0}

	# Check noise distribution
	if use_noise_distribution and noise:
		var noise_value = noise.get_noise_2d(pos.x, pos.z)
		if noise_value < noise_threshold:
			return {"valid": false, "height": 0.0}

	return {"valid": true, "height": height}


func get_spawn_pos_at(pos: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	"""Check if a tree can spawn at this position and return spawn data"""
	if not terrain or not terrain.data:
		return {}

	var query_start = Time.get_ticks_usec()

	# Get terrain height
	var height = terrain.data.get_height(pos)
	if is_nan(height):
		if debug_detailed_profiling:
			prof_terrain_query_time += float(Time.get_ticks_usec() - query_start) / 1000000.0
			prof_terrain_query_count += 1
		return {}

	# Check height constraints
	if height < min_height or height > max_height:
		if debug_detailed_profiling:
			prof_terrain_query_time += float(Time.get_ticks_usec() - query_start) / 1000000.0
			prof_terrain_query_count += 1
		return {}

	# Check water level
	if height < water_level:
		if debug_detailed_profiling:
			prof_terrain_query_time += float(Time.get_ticks_usec() - query_start) / 1000000.0
			prof_terrain_query_count += 1
		return {}

	# Check slope
	var normal = terrain.data.get_normal(pos)
	var slope = 1.0 - normal.y

	if debug_detailed_profiling:
		prof_terrain_query_time += float(Time.get_ticks_usec() - query_start) / 1000000.0
		prof_terrain_query_count += 2  # height + normal queries

	if slope < min_slope or slope > max_slope:
		return {}

	# Check noise distribution
	if use_noise_distribution and noise:
		var noise_value = noise.get_noise_2d(pos.x, pos.z)
		if noise_value < noise_threshold:
			return {}

	# Generate random scale and rotation using the chunk's RNG
	var tree_scale = rng.randf_range(min_tree_scale, max_tree_scale)
	var tree_rotation = rng.randf() * TAU if random_rotation else 0.0

	return {"position": Vector3(pos.x, height, pos.z), "rotation": tree_rotation, "scale": tree_scale}


func get_seeded_random(seed_string: String, offset: int) -> float:
	"""Generate deterministic random number from string seed"""
	var hash_val = hash(seed_string + str(offset))
	return float(hash_val % 10000) / 10000.0


func get_all_tree_positions() -> Array[Vector3]:
	"""Get all tree positions (for minimap)"""
	var positions: Array[Vector3] = []
	for chunk_data in loaded_chunks.values():
		for tree_trans in chunk_data.tree_transforms:
			positions.append(tree_trans.origin)
	return positions


func get_visible_tree_positions() -> Array[Vector3]:
	"""Get positions of visible trees (for minimap)"""
	# With GPU culling, we consider all loaded trees as potentially visible
	return get_all_tree_positions()


func is_debug_mode_enabled() -> bool:
	return debug_show_on_minimap


func get_all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	"""Recursively find all MeshInstance3D nodes"""
	var meshes: Array[MeshInstance3D] = []

	if node is MeshInstance3D:
		meshes.append(node)

	for child in node.get_children():
		meshes.append_array(get_all_mesh_instances(child))

	return meshes
