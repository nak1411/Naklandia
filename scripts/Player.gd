# Player.gd - Main first-person controller with interaction support
# Coordinates all player components
class_name Player
extends CharacterBody3D

# Component references
@onready var mouse_look: MouseLook = $MouseLook
@onready var movement: PlayerMovement = $PlayerMovement
@onready var input_manager: InputManager = $InputManager
@onready var interaction_system: InteractionSystem = $InteractionSystem
@onready var inventory_integration: InventoryIntegration = $InventoryIntegration

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
	
	# Connect interaction system signals
	if interaction_system:
		interaction_system.interactable_found.connect(_on_interactable_found)
		interaction_system.interactable_lost.connect(_on_interactable_lost)
		interaction_system.interaction_performed.connect(_on_interaction_performed)

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
	var interact_pressed = input_manager.is_interact_pressed()
	
	# Handle interaction
	if interact_pressed and interaction_system:
		var success = interaction_system.attempt_interaction()
		if success:
			# Consume the interact input buffer
			input_manager.consume_interact_buffer()
	
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

# Component signal handlers
func _on_movement_state_changed(new_state: PlayerState):
	current_state = new_state

func _on_interactable_found(interactable: Interactable):
	# Handle when an interactable is found
	pass

func _on_interactable_lost():
	# Handle when interactable is lost
	pass

func _on_interaction_performed(interactable: Interactable):
	# Handle successful interaction
	pass

# Public method for crosshair to access state
func get_current_state() -> PlayerState:
	return current_state

# Public method to get interaction system
func get_interaction_system() -> InteractionSystem:
	return interaction_system
