# InteractionRaycaster.gd - Enhanced with distance tracking
extends Node

# Signals
signal interactable_detected(interactable: Interactable, distance: float)
signal interactable_lost

# Raycast settings
var raycast_distance: float = 5.0
var raycast_layer: int = 2

# References
var camera: Camera3D
var space_state: PhysicsDirectSpaceState3D
var current_interactable: Interactable
var current_distance: float = 0.0
var multimesh_converter: MultiMeshToInteractable = null


func _ready():
	_find_camera_reference()


func setup_raycaster(distance: float, layer: int):
	raycast_distance = distance
	raycast_layer = layer


func _find_camera_reference():
	var player = get_parent().get_parent()
	if player and player.has_node("CameraPivot/Camera3D"):
		camera = player.get_node("CameraPivot/Camera3D")


func update_raycast():
	if not camera:
		return

	space_state = get_viewport().world_3d.direct_space_state
	if not space_state:
		return

	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * raycast_distance)

	# Use physics raycast for ALL interactables
	var exclude_objects = []
	exclude_objects.append(get_parent().get_parent())  # Player

	# Find and exclude floor/ground objects on layer 1
	var scene_root = get_tree().current_scene
	_find_and_exclude_floors(scene_root, exclude_objects)

	# IMPORTANT: Exclude Terrain3D so it doesn't block foliage raycasts
	var terrain = get_tree().get_first_node_in_group("terrain")
	if terrain:
		exclude_objects.append(terrain)

	# First, check for physics-based interactables (chests, NPCs, etc.)
	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = 1 << (raycast_layer - 1)  # Only layer 2
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = exclude_objects

	var physics_result = space_state.intersect_ray(query)

	# Then, check for MultiMesh foliage (no physics collision, manual detection)
	var ray_direction = (to - from).normalized()
	var foliage_result = _raycast_multimesh_foliage(from, ray_direction, raycast_distance)

	# Use whichever hit is closer
	var result: Dictionary
	if physics_result.has("collider") and foliage_result.has("collider"):
		var physics_dist = from.distance_to(physics_result.position)
		var foliage_dist = from.distance_to(foliage_result.position)
		result = foliage_result if foliage_dist < physics_dist else physics_result
	elif foliage_result.has("collider"):
		result = foliage_result
	else:
		result = physics_result

	_process_raycast_result(result, from)


func _raycast_multimesh_foliage(ray_origin: Vector3, ray_direction: Vector3, max_distance: float) -> Dictionary:
	"""
	Manual raycast against MultiMesh foliage instances - no physics collision needed!
	Returns a raycast result dictionary compatible with _process_raycast_result
	"""
	# Find all foliage spawners
	var spawners = get_tree().get_nodes_in_group("foliage_spawner")
	if spawners.is_empty():
		return {}

	var closest_hit: Dictionary = {}
	var closest_distance: float = max_distance

	var debug_total_checks = 0
	var debug_mmis_checked = 0
	var debug_chunks_skipped = 0
	var debug_instances_culled = 0

	for spawner in spawners:
		# Check all loaded chunks
		for chunk_data in spawner.loaded_chunks.values():
			# OPTIMIZATION 1: Skip entire chunk if it's too far from ray origin
			# Calculate chunk center position (chunk_data.world_pos is the corner)
			var chunk_size = spawner.chunk_size if "chunk_size" in spawner else 256.0
			var chunk_center = Vector3(chunk_data.world_pos.x + chunk_size * 0.5, ray_origin.y, chunk_data.world_pos.y + chunk_size * 0.5)  # Use player height for Y

			# Quick distance check - skip chunk if player is too farw
			var dist_to_chunk = ray_origin.distance_to(chunk_center)
			if dist_to_chunk > max_distance + chunk_size:
				debug_chunks_skipped += 1
				continue

			# OPTIMIZATION 2: Skip chunk if it's behind the camera (not in view direction)
			var to_chunk = chunk_center - ray_origin
			var chunk_dot = to_chunk.normalized().dot(ray_direction)
			if chunk_dot < -0.5:  # Chunk is mostly behind camera
				debug_chunks_skipped += 1
				continue

			for layer_data in chunk_data.layers.values():
				for mmi in layer_data.multimesh_instances:
					if not mmi.has_meta("is_interactable_foliage"):
						continue

					var item_transforms: Array = mmi.get_meta("item_transforms", [])
					var layer: FoliageLayer = mmi.get_meta("foliage_layer", null)

					if not layer or item_transforms.is_empty():
						continue

					# OPTIMIZATION: Broad-phase culling - check if ray even goes near this MMI
					var mmi_pos = mmi.global_position
					var to_mmi = mmi_pos - ray_origin
					var mmi_projection = to_mmi.dot(ray_direction)

					# Skip if MMI is behind camera or too far
					if mmi_projection < 0 or mmi_projection > max_distance + chunk_size:
						continue

					# Check distance from ray to MMI center - skip if too far
					var closest_on_ray = ray_origin + ray_direction * clamp(mmi_projection, 0, max_distance)
					var dist_to_ray_from_mmi = mmi_pos.distance_to(closest_on_ray)
					# Use chunk size for culling, add extra margin
					if dist_to_ray_from_mmi > chunk_size:  # Full chunk size
						continue

					debug_mmis_checked += 1

					# Get collision shape radius from layer
					# The collision shape is in scene-local space, radius is typically 5.0 for bushes
					# Scene root is scaled to 0.1, so world radius = 5.0 × 0.1 = 0.5 meters
					# We use the radius directly as it's already properly scaled when cached
					var interaction_radius = 1.0  # Default fallback (1 meter)

					if layer.cached_collision_shape and layer.cached_collision_shape is SphereShape3D:
						# The cached collision shape radius is in scene-local space
						# For bushes: radius=5.0, scene_scale=0.1, so we need to divide by 10
						# to get world space (0.5 meters)
						var shape_radius = layer.cached_collision_shape.radius
						interaction_radius = shape_radius * 0.1  # Assume 0.1 scene scale for foliage

					# Use a generous multiplier for easier interaction (2x-3x)
					interaction_radius *= 3.0  # Final radius: ~1.5 meters for bushes

					# Narrow-phase: Check individual instances with aggressive culling
					for i in range(item_transforms.size()):
						var instance_pos = item_transforms[i].origin

						# OPTIMIZATION 3: Quick distance check before expensive ray test
						var dist_sq = ray_origin.distance_squared_to(instance_pos)
						var max_dist_sq = max_distance * max_distance
						if dist_sq > max_dist_sq:
							debug_instances_culled += 1
							continue

						debug_total_checks += 1

						# Simple sphere-ray intersection test
						var to_instance = instance_pos - ray_origin
						var projection = to_instance.dot(ray_direction)

						# Behind camera or too far
						if projection < 0 or projection > closest_distance:
							continue

						# Get closest point on ray to instance
						var closest_point_on_ray = ray_origin + ray_direction * projection
						var distance_to_ray = instance_pos.distance_to(closest_point_on_ray)

						if distance_to_ray < interaction_radius and projection < closest_distance:
							closest_distance = projection
							closest_hit = {"collider": mmi, "position": instance_pos, "normal": Vector3.UP, "multimesh_instance_index": i, "is_multimesh_foliage": true}

							# OPTIMIZATION 4: Early exit if we found a very close hit
							if closest_distance < 1.0:  # Within 1 meter
								return closest_hit

	# Debug output every 2 seconds (with detailed culling stats)
	if Engine.get_frames_drawn() % 120 == 0 and (debug_mmis_checked > 0 or debug_total_checks > 0 or debug_chunks_skipped > 0):
		print(
			"[FOLIAGE RAYCAST] Chunks skipped: ",
			debug_chunks_skipped,
			" | MMIs: ",
			debug_mmis_checked,
			" | Instances culled: ",
			debug_instances_culled,
			" | Ray tested: ",
			debug_total_checks,
			" | Hit: ",
			closest_hit.has("collider")
		)

	return closest_hit


func _convert_multimesh_direct(mmi: MultiMeshInstance3D, instance_index: int, layer: FoliageLayer, hit_position: Vector3) -> Interactable:
	"""Convert a MultiMesh instance directly to interactable (NEW SYSTEM - no collision shapes!)"""
	# Lazy-load the converter
	if not multimesh_converter:
		var converters = get_tree().get_nodes_in_group("multimesh_converter")
		if converters.size() > 0:
			multimesh_converter = converters[0]
		else:
			# Create one if it doesn't exist
			var spawners = get_tree().get_nodes_in_group("foliage_spawner")
			if spawners.size() > 0:
				multimesh_converter = MultiMeshToInteractable.new()
				multimesh_converter.add_to_group("multimesh_converter")
				spawners[0].add_child(multimesh_converter)

	if not multimesh_converter:
		return null

	# Use the converter to create/get the interactable
	return multimesh_converter.convert_to_interactable({"mmi": mmi, "instance_index": instance_index, "layer": layer, "position": hit_position})


func _find_and_exclude_floors(node: Node, exclude_list: Array):
	# Exclude any StaticBody3D that might be floor/walls
	if node is StaticBody3D and node.collision_layer == 1:
		exclude_list.append(node)

	for child in node.get_children():
		_find_and_exclude_floors(child, exclude_list)


func _process_raycast_result(result: Dictionary, ray_origin: Vector3):
	var hit_interactable: Interactable = null
	var hit_distance: float = 0.0

	# If no hit, clear current interactable (restore MMI if it was foliage)
	if not result.has("collider"):
		if current_interactable:
			current_interactable.end_hover()
			interactable_lost.emit()

			# Restore MMI for foliage
			if current_interactable is InteractableFoliage and multimesh_converter:
				var converter_active = multimesh_converter.get_active_interactable()
				if converter_active == current_interactable:
					multimesh_converter._cleanup_active_interactable(true)

			current_interactable = null
			current_distance = 0.0
		return

	if result.has("collider"):
		var collider = result.collider
		# Debug: Print what we're hitting
		# print("[RAYCAST] Hit: ", collider.get_class(), " Name: ", collider.name if collider is Node else "N/A")

		if collider is Node:
			# Check if this is manual MultiMesh foliage raycast (collision-free detection!)
			if result.has("is_multimesh_foliage") and collider is MultiMeshInstance3D:
				var mmi: MultiMeshInstance3D = collider
				var instance_index: int = result.get("multimesh_instance_index", -1)
				var layer: FoliageLayer = mmi.get_meta("foliage_layer", null)

				if instance_index >= 0 and layer:
					# Convert to interactable using MultiMeshToInteractable
					hit_interactable = _convert_multimesh_direct(mmi, instance_index, layer, result.get("position", Vector3.ZERO))
					if hit_interactable:
						hit_distance = ray_origin.distance_to(result.position)
			else:
				# Regular interactable
				hit_interactable = _find_interactable_in_hierarchy(collider)
				if hit_interactable and result.has("position"):
					hit_distance = ray_origin.distance_to(result.position)

	if hit_interactable != current_interactable:
		if current_interactable:
			current_interactable.end_hover()
			interactable_lost.emit()

			# If we're switching away from a MultiMesh-converted foliage, clean it up WITH restore
			if current_interactable is InteractableFoliage and multimesh_converter:
				var converter_active = multimesh_converter.get_active_interactable()
				if converter_active == current_interactable:
					multimesh_converter._cleanup_active_interactable(true)

		current_interactable = hit_interactable
		current_distance = hit_distance

		if current_interactable and current_interactable.can_interact():
			current_interactable.start_hover()
			interactable_detected.emit(current_interactable, hit_distance)
		else:
			current_interactable = null
			current_distance = 0.0
	elif current_interactable:
		# Update distance for existing interactable
		current_distance = hit_distance


func _find_interactable_in_hierarchy(node: Node) -> Interactable:
	if node is Interactable:
		return node

	var parent = node.get_parent()
	var depth = 0
	while parent and depth < 3:
		if parent is Interactable:
			return parent
		parent = parent.get_parent()
		depth += 1

	return null


# Public interface
func set_raycast_distance(distance: float):
	raycast_distance = distance


func set_raycast_layer(layer: int):
	raycast_layer = layer


func get_current_interactable() -> Interactable:
	return current_interactable


func get_current_distance() -> float:
	return current_distance


func force_clear_interactable():
	if current_interactable:
		current_interactable.end_hover()
		current_interactable = null
		current_distance = 0.0
		interactable_lost.emit()


func _convert_multimesh_to_interactable(raycast_result: Dictionary, foliage_area: Area3D) -> Interactable:
	"""Convert a MultiMesh instance to an interactable foliage node on-hover"""
	# Lazy-load the converter
	if not multimesh_converter:
		var converters = get_tree().get_nodes_in_group("multimesh_converter")
		if converters.size() > 0:
			multimesh_converter = converters[0]
		else:
			# Create one if it doesn't exist
			var spawners = get_tree().get_nodes_in_group("foliage_spawner")
			if spawners.size() > 0:
				multimesh_converter = MultiMeshToInteractable.new()
				multimesh_converter.add_to_group("multimesh_converter")
				spawners[0].add_child(multimesh_converter)

	if not multimesh_converter:
		return null

	# Get the MMI that was hit
	var mmi = foliage_area.get_parent() as MultiMeshInstance3D
	if not mmi:
		return null

	var hit_position = raycast_result.get("position", Vector3.ZERO)

	# Check if this is the NEW optimized broad collision system
	if foliage_area.has_meta("item_transforms"):
		# NEW SYSTEM: Manual nearest-instance search
		var item_transforms: Array[Transform3D] = foliage_area.get_meta("item_transforms", [])
		var foliage_layer: FoliageLayer = foliage_area.get_meta("foliage_layer", null)

		if not foliage_layer or item_transforms.is_empty():
			return null

		# Find the closest instance to the raycast hit position
		var nearest_index = -1
		var nearest_distance = 999999.0
		var interaction_radius = 3.0  # Max distance to consider an instance "hit" (increased for better detection)

		for i in range(item_transforms.size()):
			var instance_world_pos = item_transforms[i].origin
			var distance = hit_position.distance_to(instance_world_pos)
			if distance < nearest_distance and distance < interaction_radius:
				nearest_distance = distance
				nearest_index = i

		if nearest_index < 0:
			return null

		# Use the converter to create/get the interactable
		return multimesh_converter.convert_to_interactable({"mmi": mmi, "instance_index": nearest_index, "layer": foliage_layer, "position": hit_position})

	# OLD SYSTEM: Per-instance collision shapes (deprecated, but keep for compatibility)
	var collision_shape: CollisionShape3D = null
	var closest_distance = 999999.0

	# Find the closest collision shape to the hit position
	for child in foliage_area.get_children():
		if child is CollisionShape3D:
			var child_global_pos = foliage_area.global_position + child.position
			var distance = hit_position.distance_to(child_global_pos)
			if distance < closest_distance:
				closest_distance = distance
				collision_shape = child

	if not collision_shape:
		return null

	# Get metadata
	var instance_index = collision_shape.get_meta("multimesh_instance_index", -1)
	var layer: FoliageLayer = collision_shape.get_meta("foliage_layer", null)

	if instance_index < 0 or not layer:
		return null

	# Use the converter to create/get the interactable
	return multimesh_converter.convert_to_interactable({"mmi": mmi, "instance_index": instance_index, "layer": layer, "position": raycast_result.get("position", Vector3.ZERO)})
