extends CharacterBody3D

## Simple player controller for testing physics crafting system.
## WASD to move, mouse to look around.

@export var move_speed: float = 5.0
@export var mouse_sensitivity: float = 0.002
@export var gravity: float = 20.0

@onready var camera: Camera3D = $Camera3D

var rotation_x: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	# Mouse look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)

		rotation_x -= event.relative.y * mouse_sensitivity
		rotation_x = clamp(rotation_x, -PI/2, PI/2)
		camera.rotation.x = rotation_x

	# Toggle mouse capture
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Get input direction
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Apply movement
	if direction:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed * delta * 5)
		velocity.z = move_toward(velocity.z, 0, move_speed * delta * 5)

	move_and_slide()
