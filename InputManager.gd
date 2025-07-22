# InputManager.gd - Centralized input handling
class_name InputManager
extends Node

# Input action names (define these in Input Map)
const MOVE_FORWARD = "move_forward"
const MOVE_BACKWARD = "move_backward"
const MOVE_LEFT = "move_left"
const MOVE_RIGHT = "move_right"
const JUMP = "jump"
const RUN = "run"
const CROUCH = "crouch"
const TOGGLE_MOUSE = "toggle_mouse"

# Input buffering for better responsiveness
var jump_buffer_time: float = 0.1
var jump_buffer_timer: float = 0.0

func _ready():
	# Verify input actions exist
	_verify_input_actions()

func _process(delta):
	# Update input buffers
	_update_input_buffers(delta)
	
	# Handle toggle inputs
	_handle_toggle_inputs()

func get_movement_input() -> Vector2:
	var input_vector = Vector2.ZERO
	
	# Get movement input
	if Input.is_action_pressed(MOVE_FORWARD):
		input_vector.y += 1
	if Input.is_action_pressed(MOVE_BACKWARD):
		input_vector.y -= 1
	if Input.is_action_pressed(MOVE_LEFT):
		input_vector.x -= 1
	if Input.is_action_pressed(MOVE_RIGHT):
		input_vector.x += 1
	
	# Normalize diagonal movement
	return input_vector.normalized() if input_vector.length() > 1 else input_vector

func is_jump_pressed() -> bool:
	# Check for fresh jump input or buffered jump
	return Input.is_action_just_pressed(JUMP) or jump_buffer_timer > 0

func is_run_pressed() -> bool:
	return Input.is_action_pressed(RUN)

func is_crouch_pressed() -> bool:
	return Input.is_action_pressed(CROUCH)

func _update_input_buffers(delta: float):
	# Update jump buffer
	if Input.is_action_just_pressed(JUMP):
		jump_buffer_timer = jump_buffer_time
	elif jump_buffer_timer > 0:
		jump_buffer_timer -= delta
		if jump_buffer_timer <= 0:
			jump_buffer_timer = 0

func _handle_toggle_inputs():
	# Toggle mouse capture
	if Input.is_action_just_pressed(TOGGLE_MOUSE):
		var mouse_look = get_parent().get_node("MouseLook") as MouseLook
		if mouse_look:
			mouse_look.toggle_mouse_capture()

func _verify_input_actions():
	# Check if all required actions exist in the Input Map
	var required_actions = [
		MOVE_FORWARD, MOVE_BACKWARD, MOVE_LEFT, MOVE_RIGHT,
		JUMP, RUN, CROUCH, TOGGLE_MOUSE
	]
	
	for action in required_actions:
		if not InputMap.has_action(action):
			print("Warning: Input action '%s' not found in Input Map!" % action)

# Utility function to consume jump buffer (call when jump is used)
func consume_jump_buffer():
	jump_buffer_timer = 0
