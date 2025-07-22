# Player.gd - Main first-person controller
# Coordinates all player components
class_name Player
extends CharacterBody3D

# Component references
@onready var mouse_look: MouseLook = $MouseLook
@onready var movement: PlayerMovement = $PlayerMovement
@onready var input_manager: InputManager = $InputManager

# Player state
var current_state: PlayerState = PlayerState.NORMAL

enum PlayerState {
	NORMAL,
	CROUCHING,
	RUNNING
}

func _ready():
	# Initialize components
	_setup_components()

func _setup_components():
	# Connect component signals if needed
	if movement:
		movement.state_changed.connect(_on_movement_state_changed)

func _input(event):
	# Pass input to mouse look
	if mouse_look:
		mouse_look.handle_input(event)

func _physics_process(delta):
	# Get input from input manager
	var input_vector = input_manager.get_movement_input()
	var jump_pressed = input_manager.is_jump_pressed()
	var run_pressed = input_manager.is_run_pressed()
	var crouch_pressed = input_manager.is_crouch_pressed()
	
	# Update movement state
	_update_player_state(run_pressed, crouch_pressed)
	
	# Handle movement
	if movement:
		movement.handle_movement(self, input_vector, jump_pressed, current_state, delta)
	
	# Apply movement
	move_and_slide()

func _update_player_state(run_pressed: bool, crouch_pressed: bool):
	if crouch_pressed:
		current_state = PlayerState.CROUCHING
	elif run_pressed:
		current_state = PlayerState.RUNNING
	else:
		current_state = PlayerState.NORMAL

func _on_movement_state_changed(new_state: PlayerState):
	current_state = new_state

# Public method for crosshair to access state
func get_current_state() -> PlayerState:
	return current_state
