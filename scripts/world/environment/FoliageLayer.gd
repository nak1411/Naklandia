# FoliageLayer.gd
# Resource class for defining a single foliage layer (trees, rocks, bushes, grass, etc.)
# Multiple layers can be used in ProceduralFoliageSpawner for varied environments
class_name FoliageLayer
extends Resource

# Layer identification
@export var layer_name: String = "Trees"
@export var enabled: bool = true

# Scene/Mesh configuration
@export_group("Asset Settings")
@export var scene_path: String = ""  # Base scene (will extract LOD0 if no separate LODs)
@export var scene_path_lod1: String = ""  # Optional: Medium detail mesh (leave empty to use LOD0)
@export var scene_path_lod2: String = ""  # Optional: Low detail mesh (leave empty to use LOD1 or LOD0)
@export var density: float = 0.015  # Items per square meter
@export var min_scale: float = 0.8
@export var max_scale: float = 1.4
@export var random_rotation: bool = true
@export var align_to_terrain_normal: bool = false  # Align to surface slope

# Terrain constraints
@export_group("Terrain Constraints")
@export var min_slope: float = 0.0
@export var max_slope: float = 0.5
@export var min_height: float = -100.0
@export var max_height: float = 100.0
@export var water_level: float = 0.0

# Distribution settings
@export_group("Distribution")
@export var use_noise_distribution: bool = false
@export var noise_threshold: float = -0.5
@export var noise_scale: float = 0.02
@export var noise_seed: int = 0
@export var min_spacing: float = 2.5  # Minimum distance between items in this layer

# LOD settings (Unreal Engine-style geometry LOD)
@export_group("LOD Settings")
@export var use_geometry_lod: bool = true  # Use mesh swapping for different LOD levels
@export var lod0_distance: float = 50.0  # Distance for LOD0 (highest detail)
@export var lod1_distance: float = 100.0  # Distance for LOD1 (medium detail)
@export var lod2_distance: float = 150.0  # Distance for LOD2 (low detail)
@export var impostor_distance: float = 200.0  # Distance to switch to billboard impostors
@export var lod_transition_hysteresis: float = 5.0  # Prevent LOD flickering at boundaries

# Rendering settings
@export_group("Rendering")
@export var cast_shadows: bool = true
@export var shadow_distance: float = 50.0  # Distance beyond which shadows are disabled
@export var use_distance_fade_shadows: bool = true

# Visibility/Fade settings
@export_group("Visibility & Fade")
@export var use_custom_visibility_range: bool = false  # Override global visibility range for this layer
@export var visibility_range_end: float = 120.0  # Distance where items fade out completely
@export var visibility_fade_margin: float = 20.0  # Fade distance (smooth transition)

# Impostor settings (for distant billboards - used after LOD2)
@export_group("Impostor Settings")
@export var use_impostors: bool = false
@export var impostor_texture: Texture2D = null  # Pre-rendered billboard texture
@export var impostor_size: Vector2 = Vector2(4.0, 8.0)  # Billboard size in meters
@export var impostor_fade_margin: float = 10.0  # Fade transition distance

# Cross-layer interaction
@export_group("Layer Interactions")
@export var avoid_layers: Array[String] = []  # Layer names to avoid spawning near
@export var avoidance_distance: float = 5.0

# Interactable/Harvestable settings
@export_group("Interactable Settings")
@export var is_interactable: bool = false  # If true, spawns real nodes instead of MultiMesh
@export var interactable_distance: float = 50.0  # Distance within which to spawn real nodes
@export var foliage_type_name: String = "Bush"  # Name shown to player
@export var foliage_health: float = 100.0
@export var foliage_respawn_time: float = 300.0  # Time to respawn after harvest (0 = no respawn)
@export var harvest_items: Array[Dictionary] = []  # {item_id: String, min_amount: int, max_amount: int, chance: float}
@export var harvest_experience: int = 5

# Manual raycast collision override (for better performance and control)
@export_group("Raycast Collision Override")
@export var use_manual_collision: bool = false  # Override automatic collision detection with manual settings
@export_enum("Sphere", "Capsule") var manual_collision_shape: String = "Sphere"
@export var manual_collision_radius: float = 1.0  # Radius in meters (world space)
@export var manual_collision_height: float = 5.0  # Height for capsule (world space)
@export var manual_collision_offset: Vector3 = Vector3(0, 1.0, 0)  # Offset from base in meters (world space)
@export var manual_collision_radius_multiplier: float = 2.0  # Make interaction easier (1.0 = exact, 2.0 = 2x bigger)
@export var manual_collision_ignore_instance_scale: bool = false  # If true, collision size stays fixed regardless of instance scale

# Physical item drops
@export_group("Physical Drops")
@export var drop_physical_items: bool = false  # Spawn PhysicalItem nodes when harvested
@export var physical_item_scene_path: String = ""  # Path to PhysicalItem scene
@export var physical_drop_count_min: int = 1
@export var physical_drop_count_max: int = 3
@export var scale_affects_drops: bool = true  # Larger foliage drops more items
@export var drop_spread_radius: float = 1.5

# Runtime cache - LOD0 (highest detail)
var cached_meshes: Array[Mesh] = []
var cached_mesh_transforms: Array[Transform3D] = []  # Local transforms for each mesh
var cached_scene_root_scale: Vector3 = Vector3.ONE  # Scene root's scale (e.g., 0.1 for bushes)

# Runtime cache - LOD1 (medium detail)
var cached_meshes_lod1: Array[Mesh] = []
var cached_mesh_transforms_lod1: Array[Transform3D] = []

# Runtime cache - LOD2 (low detail)
var cached_meshes_lod2: Array[Mesh] = []
var cached_mesh_transforms_lod2: Array[Transform3D] = []

# Impostor cache
var cached_impostor_mesh: Mesh = null  # Billboard mesh for impostors

# Collision and other
var cached_collision_shape: Shape3D = null  # Collision shape from scene (if exists)
var cached_collision_transform: Transform3D = Transform3D.IDENTITY  # Transform of collision shape
var noise: FastNoiseLite = null
var scene: PackedScene = null
var scene_lod1: PackedScene = null
var scene_lod2: PackedScene = null

func initialize() -> bool:
	"""Initialize the layer - load scene and setup noise"""
	if not enabled:
		return false

	# Load LOD0 scene (required)
	if not FileAccess.file_exists(scene_path):
		push_error("FoliageLayer [", layer_name, "]: Scene not found: ", scene_path)
		return false

	scene = load(scene_path)
	if not scene:
		push_error("FoliageLayer [", layer_name, "]: Failed to load scene: ", scene_path)
		return false

	# Load LOD1 scene (optional - fallback to LOD0)
	if use_geometry_lod and scene_path_lod1 != "" and FileAccess.file_exists(scene_path_lod1):
		scene_lod1 = load(scene_path_lod1)
		if scene_lod1:
			print("FoliageLayer [", layer_name, "]: Loaded LOD1 from ", scene_path_lod1)
	else:
		scene_lod1 = scene  # Fallback to LOD0

	# Load LOD2 scene (optional - fallback to LOD1 or LOD0)
	if use_geometry_lod and scene_path_lod2 != "" and FileAccess.file_exists(scene_path_lod2):
		scene_lod2 = load(scene_path_lod2)
		if scene_lod2:
			print("FoliageLayer [", layer_name, "]: Loaded LOD2 from ", scene_path_lod2)
	else:
		scene_lod2 = scene_lod1  # Fallback to LOD1 (or LOD0)

	# Setup noise if needed
	if use_noise_distribution:
		noise = FastNoiseLite.new()
		# Combine noise_seed with layer_name hash to allow same resource with different layer names
		# to have different distributions
		var combined_seed = noise_seed + hash(layer_name)
		noise.seed = combined_seed
		noise.frequency = noise_scale

	return true

func cache_meshes() -> void:
	"""Cache meshes and their local transforms from all LOD scenes for MultiMesh usage"""
	if not scene:
		return

	print("[FoliageLayer] Caching meshes for layer '", layer_name, "'")

	# Cache LOD0 (highest detail)
	_cache_meshes_for_lod(scene, cached_meshes, cached_mesh_transforms, "LOD0")

	# Cache LOD1 (medium detail)
	if use_geometry_lod and scene_lod1:
		_cache_meshes_for_lod(scene_lod1, cached_meshes_lod1, cached_mesh_transforms_lod1, "LOD1")

	# Cache LOD2 (low detail)
	if use_geometry_lod and scene_lod2:
		_cache_meshes_for_lod(scene_lod2, cached_meshes_lod2, cached_mesh_transforms_lod2, "LOD2")

	# Cache impostor billboard if enabled
	if use_impostors and impostor_texture:
		_create_impostor_mesh()

	# Cache collision shape from LOD0 (collision always uses highest detail)
	var temp_instance = scene.instantiate()
	var collision_node = _find_collision_shape(temp_instance)
	if collision_node and collision_node.shape:
		cached_collision_shape = collision_node.shape
		cached_collision_transform = collision_node.transform
		print("  Found collision shape in scene for layer '", layer_name, "': ", cached_collision_shape.get_class())
	else:
		cached_collision_shape = null
		print("  No collision shape found in scene for layer '", layer_name, "' - will use fallback generation")

	temp_instance.queue_free()


func _cache_meshes_for_lod(lod_scene: PackedScene, mesh_array: Array[Mesh], transform_array: Array[Transform3D], lod_name: String) -> void:
	"""Cache meshes for a specific LOD level"""
	mesh_array.clear()
	transform_array.clear()

	var temp_instance = lod_scene.instantiate()

	# Cache the scene root's scale (e.g., bush01_s.tscn has scale=0.1)
	if lod_name == "LOD0":
		cached_scene_root_scale = temp_instance.scale if temp_instance is Node3D else Vector3.ONE

	# Cache meshes and their transforms relative to the scene root
	var mesh_nodes = _get_all_mesh_instances(temp_instance)
	print("  [", lod_name, "] Caching ", mesh_nodes.size(), " meshes")
	for i in range(mesh_nodes.size()):
		var mesh_node = mesh_nodes[i]
		if mesh_node.mesh:
			mesh_array.append(mesh_node.mesh)
			# Get the mesh's transform by walking up the hierarchy to the scene root
			var relative_transform = _get_transform_relative_to_ancestor(mesh_node, temp_instance)
			transform_array.append(relative_transform)

	temp_instance.queue_free()


func _create_impostor_mesh() -> void:
	"""Create a billboard quad mesh for impostors"""
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = impostor_size

	# Create material with impostor texture
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = impostor_texture
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from both sides
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED  # Always face camera
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # No lighting for billboards

	quad_mesh.material = mat
	cached_impostor_mesh = quad_mesh
	print("  Created impostor billboard mesh (", impostor_size, ")")

func _find_collision_shape(node: Node) -> CollisionShape3D:
	"""Recursively find the first CollisionShape3D node"""
	if node is CollisionShape3D:
		return node

	for child in node.get_children():
		var result = _find_collision_shape(child)
		if result:
			return result

	return null

func _get_all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	"""Recursively find all MeshInstance3D nodes"""
	var meshes: Array[MeshInstance3D] = []

	if node is MeshInstance3D:
		meshes.append(node)

	for child in node.get_children():
		meshes.append_array(_get_all_mesh_instances(child))

	return meshes

func _get_transform_relative_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	"""Get a node's transform relative to an ancestor by walking up the hierarchy"""
	var result = Transform3D.IDENTITY
	var current = node

	# Walk up the hierarchy, accumulating transforms
	while current != ancestor and current != null:
		result = current.transform * result
		current = current.get_parent() as Node3D

		# Safety check - if we reach the root without finding ancestor, something is wrong
		if current == null:
			push_error("Node is not a descendant of the given ancestor")
			return Transform3D.IDENTITY

	return result


func get_meshes_for_lod(lod_level: int) -> Array[Mesh]:
	"""Get the appropriate mesh array for a given LOD level"""
	if not use_geometry_lod:
		return cached_meshes

	match lod_level:
		0:
			return cached_meshes
		1:
			return cached_meshes_lod1 if cached_meshes_lod1.size() > 0 else cached_meshes
		2:
			return cached_meshes_lod2 if cached_meshes_lod2.size() > 0 else (cached_meshes_lod1 if cached_meshes_lod1.size() > 0 else cached_meshes)
		3:  # Impostor
			if cached_impostor_mesh:
				var impostor_array: Array[Mesh] = [cached_impostor_mesh]
				return impostor_array
			return cached_meshes_lod2 if cached_meshes_lod2.size() > 0 else cached_meshes
		_:
			return cached_meshes


func get_mesh_transforms_for_lod(lod_level: int) -> Array[Transform3D]:
	"""Get the appropriate transform array for a given LOD level"""
	if not use_geometry_lod:
		return cached_mesh_transforms

	match lod_level:
		0:
			return cached_mesh_transforms
		1:
			return cached_mesh_transforms_lod1 if cached_mesh_transforms_lod1.size() > 0 else cached_mesh_transforms
		2:
			return cached_mesh_transforms_lod2 if cached_mesh_transforms_lod2.size() > 0 else (cached_mesh_transforms_lod1 if cached_mesh_transforms_lod1.size() > 0 else cached_mesh_transforms)
		3:  # Impostor - identity transform for billboards
			if cached_impostor_mesh:
				var identity_array: Array[Transform3D] = [Transform3D.IDENTITY]
				return identity_array
			return cached_mesh_transforms_lod2 if cached_mesh_transforms_lod2.size() > 0 else cached_mesh_transforms
		_:
			return cached_mesh_transforms


func validate_spawn_position(pos: Vector3, terrain: Terrain3D) -> Dictionary:
	"""Check if this position is valid for spawning this layer's items.
	Returns {valid: bool, height: float}"""
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

	return {"valid": true, "height": height, "normal": normal}
