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
@export var placement_distance: float = 2.0  # How far from camera to hold item
@export var placement_smoothing: float = 15.0  # How smoothly item follows cursor
@export var rotation_speed: float = 90.0  # Degrees per second when rotating
@export var max_pickup_distance: float = 5.0  # Max distance to pick up item

@export_group("References")
@export var camera_path: NodePath = NodePath("../Camera3D")  # Path to camera

# State
var camera: Camera3D = null
var held_item: PhysicalItem = null
var hovered_item: PhysicalItem = null
var rotation_offset: Vector3 = Vector3.ZERO  # Accumulated rotation

# Input state
var is_rotating: bool = false

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

	# Smoothly move item to target
	held_item.set_position_smooth(target_position, delta, placement_smoothing)

	# Apply rotation offset
	var target_basis = camera.global_transform.basis * Basis.from_euler(rotation_offset)
	held_item.set_rotation_smooth(target_basis, delta, placement_smoothing)


func pickup_item(item: PhysicalItem) -> void:
	"""Pick up a physical item."""
	if not item or held_item:
		return

	held_item = item
	held_item.grab()
	rotation_offset = Vector3.ZERO  # Reset rotation

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
