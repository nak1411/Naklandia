# PlayerMovement.gd - Handles all player movement mechanics
class_name PlayerMovement
extends Node

# Signals
@warning_ignore("unused_signal")
signal state_changed(new_state)

# Movement settings
@export_group("Movement")
@export var walk_speed: float = 5.0
@export var run_speed: float = 8.0
@export var crouch_speed: float = 2.5
@export var acceleration: float = 10.0
@export var friction: float = 10.0

@export_group("Jumping")
@export var jump_velocity: float = 8.0
@export var gravity: float = 20.0
@export var fall_multiplier: float = 2.0

@export_group("Crouching")
@export var crouch_height: float = 0.5
@export var normal_height: float = 1.0
@export var crouch_transition_speed: float = 8.0

# Internal state
var current_height: float
var target_height: float

# Component references
@onready var collision_shape: CollisionShape3D = get_parent().get_node("CollisionShape3D")
@onready var mesh_instance: MeshInstance3D = get_parent().get_node("MeshInstance3D")


func _ready():
	# Initialize heights
	current_height = normal_height
	target_height = normal_height
	_update_collision_height()


func handle_movement(player: CharacterBody3D, input_vector: Vector2, jump_pressed: bool, state: Player.PlayerState, delta: float):
	# Handle gravity and jumping
	_handle_vertical_movement(player, jump_pressed, delta)

	# Handle horizontal movement
	_handle_horizontal_movement(player, input_vector, state, delta)

	# Handle crouching
	_handle_crouching(state, delta)


func _handle_vertical_movement(player: CharacterBody3D, jump_pressed: bool, delta: float):
	# Add gravity
	if not player.is_on_floor():
		# Apply stronger gravity when falling for better feel
		var gravity_multiplier = fall_multiplier if player.velocity.y < 0 else 1.0
		player.velocity.y -= gravity * gravity_multiplier * delta

	# Handle jumping
	if jump_pressed and player.is_on_floor():
		player.velocity.y = jump_velocity


func _handle_horizontal_movement(player: CharacterBody3D, input_vector: Vector2, state: Player.PlayerState, delta: float):
	# Get the forward and right directions
	var forward = -player.global_transform.basis.z.normalized()
	var right = player.global_transform.basis.x.normalized()

	# Calculate movement direction
	var movement_direction = (forward * input_vector.y + right * input_vector.x).normalized()

	# Get current speed based on state
	var current_speed = _get_speed_for_state(state)

	# Apply movement
	if movement_direction.length() > 0:
		# Accelerate
		var target_velocity = movement_direction * current_speed
		player.velocity.x = move_toward(player.velocity.x, target_velocity.x, acceleration * delta)
		player.velocity.z = move_toward(player.velocity.z, target_velocity.z, acceleration * delta)
	else:
		# Apply friction
		player.velocity.x = move_toward(player.velocity.x, 0, friction * delta)
		player.velocity.z = move_toward(player.velocity.z, 0, friction * delta)


func _handle_crouching(state: Player.PlayerState, delta: float):
	# Set target height based on state
	target_height = crouch_height if state == Player.PlayerState.CROUCHING else normal_height

	# Smoothly transition height
	if current_height != target_height:
		current_height = move_toward(current_height, target_height, crouch_transition_speed * delta)
		_update_collision_height()


func _get_speed_for_state(state: Player.PlayerState) -> float:
	match state:
		Player.PlayerState.RUNNING:
			return run_speed
		Player.PlayerState.CROUCHING:
			return crouch_speed
		_:
			return walk_speed


func _update_collision_height():
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var capsule = collision_shape.shape as CapsuleShape3D
		capsule.height = current_height * 2.0  # Capsule height is total height

		# Adjust collision shape position
		collision_shape.position.y = current_height

	# Update mesh if it exists
	if mesh_instance and mesh_instance.mesh is CapsuleMesh:
		var capsule_mesh = mesh_instance.mesh as CapsuleMesh
		capsule_mesh.height = current_height * 2.0

		# Adjust mesh position
		mesh_instance.position.y = current_height
