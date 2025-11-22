# ProceduralTreeSpawner.gd
# Chunk-based procedural tree spawning system for open-world environments
# Each chunk gets its own MultiMeshInstance3D that can be loaded/unloaded independently
class_name ProceduralTreeSpawner
extends Node3D

# Tree configuration
@export_group("Tree Settings")
@export var tree_scene_path: String = "res://assets/models/foliage/resinwood_tree_s.tscn"
@export var tree_density: float = 0.05  # Trees per square meter (approx)
@export var min_tree_scale: float = 0.8
@export var max_tree_scale: float = 1.4
@export var random_rotation: bool = true

# Chunk configuration
@export_group("Chunk Settings")
@export var chunk_size: float = 64.0  # Size of each chunk (larger = fewer chunks, more trees per chunk)
@export var chunk_load_distance: float = 200.0  # Distance to load chunks
@export var chunk_unload_distance: float = 250.0  # Distance to unload chunks (should be > load_distance)
@export var chunks_per_frame: int = 4  # Max chunks to load/unload per frame
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
@export var visibility_range_end: float = 200.0
@export var visibility_fade_margin: float = 20.0

# Debug settings
@export_group("Debug")
@export var debug_show_on_minimap: bool = false
@export var debug_performance: bool = false

# Internal variables
var terrain: Terrain3D = null
var tree_scene: PackedScene = null
var noise: FastNoiseLite = null
var player: Node3D = null

# Chunk management
var loaded_chunks: Dictionary = {}  # chunk_key -> ChunkData
var last_player_chunk: Vector2i = Vector2i.MAX

# Performance tracking
var perf_chunks_loaded: int = 0
var perf_chunks_unloaded: int = 0
var perf_timer: float = 0.0


# Chunk data structure
class ChunkData:
	var chunk_key: String
	var world_pos: Vector2  # World position of chunk origin
	var multimesh_instances: Array[MultiMeshInstance3D] = []
	var tree_transforms: Array[Transform3D] = []  # Cached for regeneration

	func _init(key: String, pos: Vector2):
		chunk_key = key
		world_pos = pos


func _ready():
	# Add to tree_spawner group for minimap integration
	add_to_group("tree_spawner")

	# Find terrain
	terrain = get_node_or_null("/root/TestScene/Level/Terrain3D")
	if not terrain:
		push_warning("ProceduralTreeSpawner: No Terrain3D found at /root/TestScene/Level/Terrain3D")

	# Load tree scene
	if FileAccess.file_exists(tree_scene_path):
		tree_scene = load(tree_scene_path)
		if not tree_scene:
			push_error("ProceduralTreeSpawner: Failed to load tree scene: ", tree_scene_path)
			return
	else:
		push_error("ProceduralTreeSpawner: Tree scene not found: ", tree_scene_path)
		return

	# Setup noise
	if use_noise_distribution:
		noise = FastNoiseLite.new()
		noise.seed = noise_seed
		noise.frequency = noise_scale

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

	# Performance debug
	if debug_performance:
		perf_timer += delta
		if perf_timer >= 1.0:
			if perf_chunks_loaded > 0 or perf_chunks_unloaded > 0:
				var total_trees = 0
				for chunk in loaded_chunks.values():
					total_trees += chunk.tree_transforms.size()
				print("TreeSpawner: Loaded=", perf_chunks_loaded, " Unloaded=", perf_chunks_unloaded, " Chunks=", loaded_chunks.size(), " Trees=", total_trees)
			perf_chunks_loaded = 0
			perf_chunks_unloaded = 0
			perf_timer = 0.0

	# Update chunks every frame to ensure continuous loading
	var player_pos = player.global_position
	var current_chunk = Vector2i(int(floor(player_pos.x / chunk_size)), int(floor(player_pos.z / chunk_size)))
	last_player_chunk = current_chunk
	update_chunks(player_pos)


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
	"""Generate and load a chunk of trees"""
	var chunk_key = str(chunk_x) + "_" + str(chunk_z)

	if loaded_chunks.has(chunk_key):
		return  # Already loaded

	var chunk_world_x = float(chunk_x) * chunk_size
	var chunk_world_z = float(chunk_z) * chunk_size
	var chunk_data = ChunkData.new(chunk_key, Vector2(chunk_world_x, chunk_world_z))

	# Generate tree positions for this chunk
	var trees_in_chunk = generate_trees_for_chunk(chunk_world_x, chunk_world_z)

	if debug_performance:
		print("  Chunk ", chunk_key, " generated ", trees_in_chunk.size(), " trees")

	if trees_in_chunk.size() == 0:
		return  # No trees in this chunk

	# Create MultiMesh instances (one per mesh component in tree scene)
	var temp_tree = tree_scene.instantiate()
	var mesh_nodes = get_all_mesh_instances(temp_tree)

	for mesh_node in mesh_nodes:
		var mesh = mesh_node.mesh
		if not mesh:
			continue

		# Create MultiMesh
		var multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = trees_in_chunk.size()

		# Get local transform of this mesh component
		var local_transform = mesh_node.transform

		# Calculate chunk center for positioning the MultiMeshInstance3D
		var chunk_center = Vector3(chunk_world_x + chunk_size * 0.5, 0, chunk_world_z + chunk_size * 0.5)

		# Set transforms for all trees (relative to chunk center)
		for i in range(trees_in_chunk.size()):
			var tree_transform: Transform3D = trees_in_chunk[i]
			# Make tree position relative to chunk center
			var relative_transform = tree_transform
			relative_transform.origin -= chunk_center

			var local_offset = Transform3D()
			local_offset.origin = local_transform.origin
			local_offset.basis = local_transform.basis.orthonormalized()
			var final_transform = relative_transform * local_offset
			multimesh.set_instance_transform(i, final_transform)

		# Create MultiMeshInstance3D positioned at chunk center
		var mmi = MultiMeshInstance3D.new()
		mmi.multimesh = multimesh
		mmi.position = chunk_center  # Position at chunk center for proper visibility_range
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		# Setup GPU-based visibility culling (now works per-chunk based on distance to chunk center)
		if use_visibility_range:
			mmi.visibility_range_begin = visibility_range_begin
			mmi.visibility_range_end = visibility_range_end
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.visibility_range_begin_margin = visibility_fade_margin
			mmi.visibility_range_end_margin = visibility_fade_margin

		add_child(mmi)
		chunk_data.multimesh_instances.append(mmi)

	temp_tree.queue_free()

	# Store chunk data
	chunk_data.tree_transforms = trees_in_chunk
	loaded_chunks[chunk_key] = chunk_data

	if debug_performance:
		perf_chunks_loaded += 1


func unload_chunk(chunk_key: String):
	"""Unload a chunk and free its resources"""
	if not loaded_chunks.has(chunk_key):
		return

	var chunk_data: ChunkData = loaded_chunks[chunk_key]

	# Free all MultiMeshInstance3D nodes
	for mmi in chunk_data.multimesh_instances:
		mmi.queue_free()

	# Remove from loaded chunks
	loaded_chunks.erase(chunk_key)

	if debug_performance:
		perf_chunks_unloaded += 1


func generate_trees_for_chunk(chunk_x: float, chunk_z: float) -> Array[Transform3D]:
	"""Generate tree transforms for a chunk using random placement with minimum spacing"""
	var trees: Array[Transform3D] = []
	var placed_positions: Array[Vector2] = []

	# Create a seeded RNG for this chunk - deterministic but truly random distribution
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(int(chunk_x)) + "_" + str(int(chunk_z)))

	var chunk_area = chunk_size * chunk_size
	var target_tree_count = int(chunk_area * tree_density)
	var max_attempts = target_tree_count * 4  # Allow more attempts for better coverage
	var attempts = 0

	while trees.size() < target_tree_count and attempts < max_attempts:
		var rand_x = rng.randf()
		var rand_z = rng.randf()

		var local_x = rand_x * chunk_size + chunk_x
		var local_z = rand_z * chunk_size + chunk_z

		attempts += 1

		# Check minimum spacing against already placed trees in this chunk
		var too_close = false
		var new_pos = Vector2(local_x, local_z)
		for existing_pos in placed_positions:
			if new_pos.distance_to(existing_pos) < min_tree_spacing:
				too_close = true
				break

		if too_close:
			continue

		var spawn_data = get_spawn_pos_at(Vector3(local_x, 0, local_z), rng)
		if spawn_data:
			var tree_transform = Transform3D()
			tree_transform = tree_transform.rotated(Vector3.UP, spawn_data["rotation"])
			tree_transform = tree_transform.scaled(Vector3.ONE * spawn_data["scale"])
			tree_transform.origin = spawn_data["position"]
			trees.append(tree_transform)
			placed_positions.append(new_pos)

	return trees


func get_spawn_pos_at(pos: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	"""Check if a tree can spawn at this position and return spawn data"""
	if not terrain or not terrain.data:
		return {}

	# Get terrain height
	var height = terrain.data.get_height(pos)
	if is_nan(height):
		return {}

	# Check height constraints
	if height < min_height or height > max_height:
		return {}

	# Check water level
	if height < water_level:
		return {}

	# Check slope
	var normal = terrain.data.get_normal(pos)
	var slope = 1.0 - normal.y
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
