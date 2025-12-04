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
@export var scene_path: String = ""
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

# LOD settings
@export_group("LOD Settings")
@export var use_lod: bool = true
@export var lod_distance_near: float = 50.0
@export var lod_distance_mid: float = 90.0
@export var lod_mid_scale_factor: float = 0.40
@export var lod_far_scale_factor: float = 0.15

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

# Impostor settings (for distant billboards)
@export_group("Impostor Settings")
@export var use_impostors: bool = false
@export var impostor_texture: Texture2D = null
@export var impostor_distance: float = 150.0
@export var impostor_size: Vector2 = Vector2(4.0, 8.0)

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

# Runtime cache
var cached_meshes: Array[Mesh] = []
var cached_mesh_transforms: Array[Transform3D] = []  # Local transforms for each mesh
var cached_scene_root_scale: Vector3 = Vector3.ONE  # Scene root's scale (e.g., 0.1 for bushes)
var cached_collision_shape: Shape3D = null  # Collision shape from scene (if exists)
var cached_collision_transform: Transform3D = Transform3D.IDENTITY  # Transform of collision shape
var noise: FastNoiseLite = null
var scene: PackedScene = null

func initialize() -> bool:
	"""Initialize the layer - load scene and setup noise"""
	if not enabled:
		return false

	# Load scene
	if not FileAccess.file_exists(scene_path):
		push_error("FoliageLayer [", layer_name, "]: Scene not found: ", scene_path)
		return false

	scene = load(scene_path)
	if not scene:
		push_error("FoliageLayer [", layer_name, "]: Failed to load scene: ", scene_path)
		return false

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
	"""Cache meshes and their local transforms from the scene for MultiMesh usage"""
	if not scene:
		return

	cached_meshes.clear()
	cached_mesh_transforms.clear()
	var temp_instance = scene.instantiate()

	# Cache the scene root's scale (e.g., bush01_s.tscn has scale=0.1)
	cached_scene_root_scale = temp_instance.scale if temp_instance is Node3D else Vector3.ONE

	# Cache meshes and their transforms relative to the scene root
	var mesh_nodes = _get_all_mesh_instances(temp_instance)
	print("[FoliageLayer] Caching ", mesh_nodes.size(), " meshes for layer '", layer_name, "'")
	for i in range(mesh_nodes.size()):
		var mesh_node = mesh_nodes[i]
		if mesh_node.mesh:
			cached_meshes.append(mesh_node.mesh)
			# Get the mesh's transform by walking up the hierarchy to the scene root
			# This avoids using affine_inverse which can cause scale inversions
			var relative_transform = _get_transform_relative_to_ancestor(mesh_node, temp_instance)
			print("[FoliageLayer]   Mesh ", i, " (", mesh_node.name, "): local_transform=", mesh_node.transform, " | relative_transform=", relative_transform)
			cached_mesh_transforms.append(relative_transform)

	# Cache collision shape if it exists in the scene
	var collision_node = _find_collision_shape(temp_instance)
	if collision_node and collision_node.shape:
		cached_collision_shape = collision_node.shape
		cached_collision_transform = collision_node.transform
		print("  Found collision shape in scene for layer '", layer_name, "': ", cached_collision_shape.get_class())
	else:
		cached_collision_shape = null
		print("  No collision shape found in scene for layer '", layer_name, "' - will use fallback generation")

	temp_instance.queue_free()

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
