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

	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = 1 << (raycast_layer - 1)  # Only layer 2
	query.collide_with_areas = true  # IMPORTANT: Allow raycasts to hit Area3D nodes
	query.collide_with_bodies = true
	query.exclude = exclude_objects

	var result = space_state.intersect_ray(query)
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

	for spawner in spawners:
		# Check all loaded chunks
		for chunk_data in spawner.loaded_chunks.values():
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
					if mmi_projection < 0 or mmi_projection > max_distance + 256:
						continue

					# Check distance from ray to MMI center - skip if too far
					var closest_on_ray = ray_origin + ray_direction * clamp(mmi_projection, 0, max_distance)
					var dist_to_ray_from_mmi = mmi_pos.distance_to(closest_on_ray)
					if dist_to_ray_from_mmi > 128:  # Half chunk size
						continue

					# CRITICAL OPTIMIZATION: Skip instances for dense foliage to reduce CPU load
					var check_step = 1
					if item_transforms.size() > 1000:
						check_step = 5  # Only check every 5th instance (20%) for very dense layers
					elif item_transforms.size() > 500:
						check_step = 3  # Check every 3rd instance (33%) for dense layers

					# Narrow-phase: Check individual instances
					for i in range(0, item_transforms.size(), check_step):
						var instance_pos = item_transforms[i].origin

						# Simple sphere-ray intersection test
						var to_instance = instance_pos - ray_origin
						var projection = to_instance.dot(ray_direction)

						# Behind camera or too far
						if projection < 0 or projection > closest_distance:
							continue

						# Get closest point on ray to instance
						var closest_point_on_ray = ray_origin + ray_direction * projection
						var distance_to_ray = instance_pos.distance_to(closest_point_on_ray)

						# Use a generous interaction radius (accounting for bush size and skip step)
						var interaction_radius = 1.5 * item_transforms[i].basis.get_scale().x
						if check_step > 1:
							interaction_radius *= check_step * 0.5  # Widen radius when skipping instances

						if distance_to_ray < interaction_radius and projection < closest_distance:
							closest_distance = projection
							closest_hit = {
								"collider": mmi,
								"position": instance_pos,
								"normal": Vector3.UP,
								"multimesh_instance_index": i,
								"is_multimesh_foliage": true
							}

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
	return multimesh_converter.convert_to_interactable({
		"mmi": mmi,
		"instance_index": instance_index,
		"layer": layer,
		"position": hit_position
	})


func _find_and_exclude_floors(node: Node, exclude_list: Array):
	# Exclude any StaticBody3D that might be floor/walls
	if node is StaticBody3D and node.collision_layer == 1:
		exclude_list.append(node)

	for child in node.get_children():
		_find_and_exclude_floors(child, exclude_list)


func _process_raycast_result(result: Dictionary, ray_origin: Vector3):
	var hit_interactable: Interactable = null
	var hit_distance: float = 0.0

	if result.has("collider"):
		var collider = result.collider
		# Debug: Print what we're hitting
		# print("[RAYCAST] Hit: ", collider.get_class(), " Name: ", collider.name if collider is Node else "N/A")

		if collider is Node:
			# Check if this is manual MultiMesh foliage raycast (NEW SYSTEM - no physics!)
			if result.has("is_multimesh_foliage") and collider is MultiMeshInstance3D:
				var mmi: MultiMeshInstance3D = collider
				var instance_index: int = result.get("multimesh_instance_index", -1)
				var layer: FoliageLayer = mmi.get_meta("foliage_layer", null)

				if instance_index >= 0 and layer:
					# Convert to interactable using MultiMeshToInteractable
					hit_interactable = _convert_multimesh_direct(mmi, instance_index, layer, result.get("position", Vector3.ZERO))
					if hit_interactable:
						hit_distance = ray_origin.distance_to(result.position)
			# Check if this is OLD SYSTEM MultiMesh foliage collision (using Area3D)
			elif collider is Area3D and collider.name == "FoliageCollision" and collider.get_parent() is MultiMeshInstance3D:
				# This is MultiMesh foliage - convert to interactable on-hover
				hit_interactable = _convert_multimesh_to_interactable(result, collider)
				if hit_interactable and result.has("position"):
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
		var interaction_radius = 1.5  # Max distance to consider an instance "hit"

		for i in range(item_transforms.size()):
			var instance_world_pos = item_transforms[i].origin
			var distance = hit_position.distance_to(instance_world_pos)
			if distance < nearest_distance and distance < interaction_radius:
				nearest_distance = distance
				nearest_index = i

		if nearest_index < 0:
			return null

		# Use the converter to create/get the interactable
		return multimesh_converter.convert_to_interactable({
			"mmi": mmi,
			"instance_index": nearest_index,
			"layer": foliage_layer,
			"position": hit_position
		})

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
	return multimesh_converter.convert_to_interactable({
		"mmi": mmi,
		"instance_index": instance_index,
		"layer": layer,
		"position": raycast_result.get("position", Vector3.ZERO)
	})
