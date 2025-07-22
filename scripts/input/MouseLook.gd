# MouseLook.gd - Handles mouse look and camera rotation with dynamic height
class_name MouseLook
extends Node

# Camera references
@onready var camera_pivot: Node3D = get_parent().get_node("CameraPivot")
@onready var camera: Camera3D = camera_pivot.get_node("Camera3D")

# Mouse sensitivity settings
@export var mouse_sensitivity: float = 0.003
@export var vertical_look_limit: float = 90.0

# Camera height settings
@export_group("Camera Heights")
@export var standing_height: float = 1.7
@export var crouching_height: float = 1.0
@export var height_transition_speed: float = 8.0

# Internal rotation values
var mouse_delta: Vector2 = Vector2.ZERO
var vertical_rotation: float = 0.0

# Camera height state
var current_camera_height: float
var target_camera_height: float

# Player reference
var player_ref: CharacterBody3D

func _ready():
	# Capture mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Initialize camera height
	current_camera_height = standing_height
	target_camera_height = standing_height
	
	# Get player reference
	player_ref = get_parent()
	
	# Set initial camera position
	_update_camera_position()

func _process(delta):
	# Update camera height based on player state
	_update_camera_height(delta)

func handle_input(event: InputEvent):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		mouse_delta = event.relative * mouse_sensitivity
		_apply_mouse_look()

func _apply_mouse_look():
	if not camera_pivot or not camera:
		return
	
	# Horizontal rotation (Y-axis) - rotate the player body
	get_parent().rotate_y(-mouse_delta.x)
	
	# Vertical rotation (X-axis) - rotate the camera pivot
	vertical_rotation += -mouse_delta.y
	vertical_rotation = clamp(vertical_rotation, -deg_to_rad(vertical_look_limit), deg_to_rad(vertical_look_limit))
	
	camera_pivot.rotation.x = vertical_rotation

func _update_camera_height(delta: float):
	# Get current player state
	if player_ref and player_ref.has_method("get_current_state"):
		var player_state = player_ref.get_current_state()
		
		# Set target height based on state
		match player_state:
			0: # NORMAL or RUNNING
				target_camera_height = standing_height
			1: # CROUCHING
				target_camera_height = crouching_height
			2: # RUNNING
				target_camera_height = standing_height
	
	# Smoothly transition camera height
	if abs(current_camera_height - target_camera_height) > 0.01:
		current_camera_height = move_toward(current_camera_height, target_camera_height, height_transition_speed * delta)
		_update_camera_position()

func _update_camera_position():
	if camera_pivot:
		camera_pivot.position.y = current_camera_height
	
	# Keep camera at pivot center
	if camera:
		camera.position = Vector3.ZERO

func set_mouse_sensitivity(new_sensitivity: float):
	mouse_sensitivity = new_sensitivity

func toggle_mouse_capture():
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# Public methods for external height control
func set_camera_heights(standing: float, crouching: float):
	standing_height = standing
	crouching_height = crouching

func set_height_transition_speed(speed: float):
	height_transition_speed = speed

func get_current_camera_height() -> float:
	return current_camera_height
