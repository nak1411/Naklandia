# MouseLook.gd - Handles mouse look and camera rotation
class_name MouseLook
extends Node

# Camera references
@onready var camera_pivot: Node3D = get_parent().get_node("CameraPivot")
@onready var camera: Camera3D = camera_pivot.get_node("Camera3D")

# Mouse sensitivity settings
@export var mouse_sensitivity: float = 0.003
@export var vertical_look_limit: float = 90.0

# Internal rotation values
var mouse_delta: Vector2 = Vector2.ZERO
var vertical_rotation: float = 0.0

func _ready():
	# Capture mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

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

func set_mouse_sensitivity(new_sensitivity: float):
	mouse_sensitivity = new_sensitivity

func toggle_mouse_capture():
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
