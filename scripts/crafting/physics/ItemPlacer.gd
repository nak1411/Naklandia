class_name ItemPlacer
extends Node3D

## Handles picking up, positioning, and placing PhysicalItems in the world.
##
## This component allows players to:
## - Raycast to detect physical items
## - Pick up items with mouse/controller
## - Position items in 3D space freely
## - Rotate items with keyboard/mouse
## - Drop items back into physics simulation

# Configuration
@export_group("Placement Settings")
@export var placement_distance: float = 2.0  # How far from camera to hold itemw
@export var placement_smoothing: float = 15.0  # How smoothly item follows cursor
@export var rotation_speed: float = 90.0  # Degrees per second when rotating
@export var max_pickup_distance: float = 5.0  # Max distance to pick up item

@export_group("Anti-Clipping Settings")
@export var max_force_threshold: float = 50.0  # Max force before auto-drop (N)
@export var max_penetration_depth: float = 0.5  # Max allowed penetration (m) before auto-drop - increase if items drop too easily
@export var force_check_interval: float = 0.001  # How often to check forces (seconds)

@export_group("References")
@export var camera_path: NodePath = NodePath("../Camera3D")  # Path to camera

# State
var camera: Camera3D = null
var held_item: PhysicalItem = null
var hovered_item: PhysicalItem = null
var rotation_offset: Vector3 = Vector3.ZERO  # Accumulated rotation

# Input statew
var is_rotating: bool = false

# Anti-clipping state
var force_check_timer: float = 0.0
var previous_position: Vector3 = Vector3.ZERO
var stuck_distance_accumulator: float = 0.0  # Tracks how far we're being blocked from moving

# Raycasting
var raycast_space: PhysicsDirectSpaceState3D


func _ready() -> void:
	# Get camera from node path
	if camera_path:
		camera = get_node(camera_path) as Camera3D

	if not camera:
		push_error("ItemPlacer: Camera not found at path: ", camera_path)
		return

	print("ItemPlacer ready! Camera: ", camera.name)


func _physics_process(delta: float) -> void:
	raycast_space = get_world_3d().direct_space_state

	# Update hover detection when not holding anything
	if not held_item:
		_update_hover_detection()

	# Update held item position
	if held_item:
		_update_held_item(delta)


func _input(event: InputEvent) -> void:
	# Pick up / drop item with Z key (physical grab)
	if event.is_action_pressed("physical_grab"):  # Z key
		if held_item:
			drop_item()
		elif hovered_item:
			pickup_item(hovered_item)

	# Rotation controls (only when holding item)
	if held_item:
		# Rotate with R/F keys instead of Q/E to avoid conflict
		if event.is_action_pressed("ui_text_backspace"):  # R - rotate left
			is_rotating = true
		if event.is_action_pressed("ui_text_delete"):  # F - rotate right
			is_rotating = true

		# Mouse wheel for forward/back rotation
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				rotation_offset.x += deg_to_rad(15.0)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				rotation_offset.x -= deg_to_rad(15.0)


func _process(delta: float) -> void:
	if not held_item:
		return

	# Continuous rotation while keys held (using different keys to avoid E conflict)
	# Note: Using arrow keys for now - can rebind later
	if Input.is_key_pressed(KEY_Q):
		rotation_offset.y += deg_to_rad(rotation_speed * delta)
	if Input.is_key_pressed(KEY_R):
		rotation_offset.y -= deg_to_rad(rotation_speed * delta)


func _update_hover_detection() -> void:
	"""Raycast to find physical items the player is looking at."""
	if not camera:
		return

	var from = camera.global_position
	var to = from + camera.global_transform.basis.z * -max_pickup_distance

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 4  # Layer 3 for physical items
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result = raycast_space.intersect_ray(query)

	if result:
		var collider = result.collider
		if collider is PhysicalItem and collider != held_item:
			_set_hovered_item(collider)
		else:
			_set_hovered_item(null)
	else:
		_set_hovered_item(null)


func _set_hovered_item(item: PhysicalItem) -> void:
	"""Update the currently hovered item with visual feedback."""
	if hovered_item == item:
		return

	# Clear old hover
	if hovered_item and hovered_item != held_item:
		hovered_item.show_highlight(false)

	# Set new hover
	hovered_item = item
	if hovered_item:
		hovered_item.show_highlight(true)


func _update_held_item(delta: float) -> void:
	"""Update position and rotation of held item to follow camera."""
	if not held_item or not camera:
		return

	# Calculate target position in front of camera
	var camera_forward = -camera.global_transform.basis.z
	var target_position = camera.global_position + camera_forward * placement_distance

	# Check for collisions and adjust position if needed
	var adjusted_position = _check_collision_and_adjust(held_item, target_position)

	# Track force/penetration for anti-clipping
	var blocked_distance = target_position.distance_to(adjusted_position)

	# Check if item is being forced into geometry
	if _check_should_auto_drop(delta, target_position, adjusted_position, blocked_distance):
		print("ItemPlacer: Auto-dropping item due to excessive force/penetration")
		drop_item()
		return

	# Smoothly move item to target
	held_item.set_position_smooth(adjusted_position, delta, placement_smoothing)

	# Apply rotation offset
	var target_basis = camera.global_transform.basis * Basis.from_euler(rotation_offset)
	held_item.set_rotation_smooth(target_basis, delta, placement_smoothing)

	# CRITICAL: After smooth movement, validate the actual position
	# This catches cases where fast movement causes the lerp to skip through walls
	var final_position = _validate_current_position(held_item)
	if final_position != held_item.global_position:
		held_item.global_position = final_position


func pickup_item(item: PhysicalItem) -> void:
	"""Pick up a physical item."""
	if not item or held_item:
		return

	held_item = item
	held_item.grab()
	rotation_offset = Vector3.ZERO  # Reset rotation

	# Reset anti-clipping state
	stuck_distance_accumulator = 0.0
	force_check_timer = 0.0
	previous_position = item.global_position

	print("Picked up: %s" % item.item_name)


func drop_item() -> void:
	"""Drop the currently held item."""
	if not held_item:
		return

	held_item.release()
	print("Dropped: %s" % held_item.item_name)
	held_item = null
	rotation_offset = Vector3.ZERO


func spawn_item(item_scene: PackedScene, spawn_position: Vector3) -> PhysicalItem:
	"""Spawn a new physical item at the given position."""
	if not item_scene:
		push_error("ItemPlacer: Invalid item scene")
		return null

	var item = item_scene.instantiate() as PhysicalItem
	if not item:
		push_error("ItemPlacer: Scene is not a PhysicalItem")
		return null

	get_tree().root.add_child(item)
	item.global_position = spawn_position
	return item


func get_hovered_item() -> PhysicalItem:
	"""Get the currently hovered item (if any)."""
	return hovered_item


func get_held_item() -> PhysicalItem:
	"""Get the currently held item (if any)."""
	return held_item


func is_holding_item() -> bool:
	"""Check if player is currently holding an item."""
	return held_item != null


func _check_collision_and_adjust(item: PhysicalItem, target_position: Vector3) -> Vector3:
	"""Check for collisions between current position and target, prevent clipping."""
	if not raycast_space or not item:
		return target_position

	var current_pos = item.global_position
	var movement = target_position - current_pos
	var movement_distance = movement.length()

	# Skip if movement is negligible
	if movement_distance < 0.001:
		return target_position

	# Get the item's collision shape
	var collision_shape: CollisionShape3D = null
	for child in item.get_children():
		if child is CollisionShape3D:
			collision_shape = child
			break

	# If no collision shape, use raycast fallback
	if not collision_shape or not collision_shape.shape:
		return _raycast_collision_check(item, target_position)

	# Use shape cast for accurate collision detection
	var shape_cast = PhysicsShapeQueryParameters3D.new()
	shape_cast.shape = collision_shape.shape
	shape_cast.transform = Transform3D(item.global_transform.basis, target_position)

	# Apply local transform offset from collision shape
	if collision_shape.transform != Transform3D.IDENTITY:
		var offset_transform = Transform3D(collision_shape.transform.basis, collision_shape.transform.origin)
		shape_cast.transform = shape_cast.transform * offset_transform

	# Check collision with world (layer 1) and other items (layer 3)
	shape_cast.collision_mask = 1 | 4
	shape_cast.exclude = [item.get_rid()]  # Exclude the held item itself

	var collision_results = raycast_space.intersect_shape(shape_cast, 4)

	# If no collision, target position is safe
	if collision_results.is_empty():
		return target_position

	# Collision detected - find safe position by moving back along the movement path
	var safe_position = current_pos
	var movement_dir = movement.normalized()

	# Binary search to find the furthest safe position
	var min_distance = 0.0
	var max_distance = movement_distance
	var iterations = 0
	var max_iterations = 8

	while iterations < max_iterations and (max_distance - min_distance) > 0.01:
		iterations += 1
		var test_distance = (min_distance + max_distance) / 2.0
		var test_position = current_pos + movement_dir * test_distance

		# Test this position
		shape_cast.transform = Transform3D(item.global_transform.basis, test_position)
		if collision_shape.transform != Transform3D.IDENTITY:
			var offset_transform = Transform3D(collision_shape.transform.basis, collision_shape.transform.origin)
			shape_cast.transform = shape_cast.transform * offset_transform

		collision_results = raycast_space.intersect_shape(shape_cast, 1)

		if collision_results.is_empty():
			# No collision at this distance, can go further
			min_distance = test_distance
			safe_position = test_position
		else:
			# Collision found, need to go closer
			max_distance = test_distance

	return safe_position


func _check_should_auto_drop(delta: float, _target_position: Vector3, _adjusted_position: Vector3, blocked_distance: float) -> bool:
	"""Check if item should be auto-dropped due to excessive force or penetration."""
	if not held_item:
		return false

	# Method 1: Accumulate how much distance we're being blocked
	# Only accumulate if SIGNIFICANTLY blocked (not just normal collision prevention)
	# This prevents normal wall contact from triggering auto-drop
	if blocked_distance > 0.1:  # Increased threshold - only care about big pushes
		# Only accumulate a portion of the blocked distance per frame to be less aggressive
		stuck_distance_accumulator += blocked_distance * delta * 2.0  # Accumulate slowly over time
	else:
		# Not blocked significantly, decay the accumulator rapidly
		stuck_distance_accumulator = max(0.0, stuck_distance_accumulator - delta * 2.0)

	# If accumulated blocked distance exceeds threshold, drop the item
	if stuck_distance_accumulator > max_penetration_depth:
		print("ItemPlacer: Stuck accumulator exceeded: %.2f / %.2f" % [stuck_distance_accumulator, max_penetration_depth])
		return true

	# Method 2: Check for penetration using shape queries (this is the main protection)
	force_check_timer += delta
	if force_check_timer >= force_check_interval:
		force_check_timer = 0.0

		if _check_item_penetration(held_item):
			print("ItemPlacer: Deep penetration detected")
			return true

	return false


func _check_item_penetration(item: PhysicalItem) -> bool:
	"""Check if the item is penetrating geometry beyond allowed threshold."""
	if not raycast_space or not item:
		return false

	# Get the item's collision shape
	var collision_shape: CollisionShape3D = null
	for child in item.get_children():
		if child is CollisionShape3D:
			collision_shape = child
			break

	if not collision_shape or not collision_shape.shape:
		return false

	# Check current position for penetration
	var shape_cast = PhysicsShapeQueryParameters3D.new()
	shape_cast.shape = collision_shape.shape
	shape_cast.transform = Transform3D(item.global_transform.basis, item.global_position)

	# Apply local transform offset from collision shape
	if collision_shape.transform != Transform3D.IDENTITY:
		var offset_transform = Transform3D(collision_shape.transform.basis, collision_shape.transform.origin)
		shape_cast.transform = shape_cast.transform * offset_transform

	# Check collision with world (layer 1) only - we care about walls/floors
	shape_cast.collision_mask = 1
	shape_cast.exclude = [item.get_rid()]
	shape_cast.margin = 0.1  # Larger margin to only detect significant penetration

	var collision_results = raycast_space.intersect_shape(shape_cast, 10)

	# If no collision even with margin, we're definitely not penetrating
	if collision_results.is_empty():
		return false

	# We're colliding even with the margin - this means we're penetrating
	# Use a different approach: shrink the shape and see if it still collides
	# If a shrunken shape doesn't collide, penetration is shallow
	# If a shrunken shape still collides, penetration is deep

	# Only check for VERY deep penetration using shape cast at reduced size
	var shape_scale = 0.5  # Shrink shape to 50% - if still colliding, very deep penetration

	# For box/sphere shapes, we can check with a smaller version
	if collision_shape.shape is BoxShape3D:
		var smaller_shape = BoxShape3D.new()
		var original_box = collision_shape.shape as BoxShape3D
		smaller_shape.size = original_box.size * shape_scale

		shape_cast.shape = smaller_shape
		shape_cast.transform = Transform3D(item.global_transform.basis, item.global_position)
		if collision_shape.transform != Transform3D.IDENTITY:
			var offset_transform = Transform3D(collision_shape.transform.basis, collision_shape.transform.origin)
			shape_cast.transform = shape_cast.transform * offset_transform

		shape_cast.margin = 0.0
		var shrunk_results = raycast_space.intersect_shape(shape_cast, 1)

		if not shrunk_results.is_empty():
			# Even at 50% size we're still colliding - DEEP penetration
			print("ItemPlacer: Deep penetration detected (shape at 50%% still colliding)")
			return true
	elif collision_shape.shape is SphereShape3D:
		var smaller_shape = SphereShape3D.new()
		var original_sphere = collision_shape.shape as SphereShape3D
		smaller_shape.radius = original_sphere.radius * shape_scale

		shape_cast.shape = smaller_shape
		shape_cast.transform = Transform3D(item.global_transform.basis, item.global_position)
		if collision_shape.transform != Transform3D.IDENTITY:
			var offset_transform = Transform3D(collision_shape.transform.basis, collision_shape.transform.origin)
			shape_cast.transform = shape_cast.transform * offset_transform

		shape_cast.margin = 0.0
		var shrunk_results = raycast_space.intersect_shape(shape_cast, 1)

		if not shrunk_results.is_empty():
			# Even at 50% size we're still colliding - DEEP penetration
			print("ItemPlacer: Deep penetration detected (sphere at 50%% still colliding)")
			return true

	# Not deeply penetrating
	return false


func _validate_current_position(item: PhysicalItem) -> Vector3:
	"""Validate that the item's current position is not penetrating geometry.
	If it is, pull it back to a safe position."""
	if not raycast_space or not item:
		return item.global_position

	# Get the item's collision shape
	var collision_shape: CollisionShape3D = null
	for child in item.get_children():
		if child is CollisionShape3D:
			collision_shape = child
			break

	if not collision_shape or not collision_shape.shape:
		return item.global_position

	# Check if current position is penetrating
	var shape_cast = PhysicsShapeQueryParameters3D.new()
	shape_cast.shape = collision_shape.shape
	shape_cast.transform = Transform3D(item.global_transform.basis, item.global_position)

	# Apply local transform offset from collision shape
	if collision_shape.transform != Transform3D.IDENTITY:
		var offset_transform = Transform3D(collision_shape.transform.basis, collision_shape.transform.origin)
		shape_cast.transform = shape_cast.transform * offset_transform

	shape_cast.collision_mask = 1  # World geometry only
	shape_cast.exclude = [item.get_rid()]
	shape_cast.margin = 0.01  # Very small margin

	var collision_results = raycast_space.intersect_shape(shape_cast, 1)

	# No collision - position is safe
	if collision_results.is_empty():
		return item.global_position

	# We're colliding - need to find a safe position
	# Move towards the camera until we're no longer colliding
	var camera_to_item = item.global_position - camera.global_position
	var direction = camera_to_item.normalized()
	var max_pullback = 2.0  # Maximum distance to pull back
	var step_size = 0.05
	var steps = int(max_pullback / step_size)

	for i in range(steps):
		var pullback_distance = (i + 1) * step_size
		var test_position = item.global_position - direction * pullback_distance

		shape_cast.transform = Transform3D(item.global_transform.basis, test_position)
		if collision_shape.transform != Transform3D.IDENTITY:
			var offset_transform = Transform3D(collision_shape.transform.basis, collision_shape.transform.origin)
			shape_cast.transform = shape_cast.transform * offset_transform

		var test_results = raycast_space.intersect_shape(shape_cast, 1)

		if test_results.is_empty():
			# Found a safe position
			return test_position

	# If we couldn't find a safe position, drop the item
	print("ItemPlacer: Could not find safe position, dropping item")
	call_deferred("drop_item")
	return item.global_position


func _raycast_collision_check(item: PhysicalItem, target_position: Vector3) -> Vector3:
	"""Fallback collision check using raycasts from multiple points on the object."""
	if not raycast_space:
		return target_position

	var current_pos = item.global_position
	var movement = target_position - current_pos
	var movement_distance = movement.length()

	if movement_distance < 0.001:
		return target_position

	var movement_dir = movement.normalized()

	# Test multiple rays from the object's bounds
	var test_points = [
		Vector3.ZERO,  # Center
		Vector3(0.1, 0, 0),  # Right
		Vector3(-0.1, 0, 0),  # Left
		Vector3(0, -0.1, 0),  # Down (most important for floor)
		Vector3(0, 0.1, 0),  # Up
		Vector3(0, 0, 0.1),  # Forward
		Vector3(0, 0, -0.1),  # Back
	]

	var min_safe_distance = movement_distance
	var hit_something = false

	for offset in test_points:
		var ray_start = current_pos + offset
		var ray_end = target_position + offset

		var ray_query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		ray_query.collision_mask = 1 | 4  # World and items
		ray_query.exclude = [item.get_rid()]

		var result = raycast_space.intersect_ray(ray_query)

		if result:
			hit_something = true
			var hit_distance = current_pos.distance_to(result.position)

			# Add small margin to prevent clipping
			var safe_distance = max(0, hit_distance - 0.05)
			min_safe_distance = min(min_safe_distance, safe_distance)

	if hit_something:
		# Move only as far as safe, along the movement direction
		return current_pos + movement_dir * min_safe_distance

	return target_position
