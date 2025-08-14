# scripts/core/player/Player.gd
# Updated to work with the new integration system
class_name Player
extends CharacterBody3D

# New signals for integration
signal state_changed(new_state: PlayerState)

enum PlayerState { NORMAL, CROUCHING, RUNNING }

# Player state
var current_state: PlayerState = PlayerState.NORMAL
var input_enabled: bool = true

# Component references
@onready var mouse_look: MouseLook = $MouseLook
@onready var movement: PlayerMovement = $PlayerMovement
@onready var input_manager: InputManager = $InputManager
@onready var interaction_system: InteractionSystem = $InteractionSystem


func _ready():
	# Add to player group for integration system to find
	add_to_group("player")

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

	# Integration system will find and connect to us automatically


func _input(event):
	# Only handle input if enabled
	if not input_enabled:
		return

	# Handle interaction immediately on input
	if event.is_action_pressed("interact") and interaction_system:
		print("Attempting interaction")
		var success = interaction_system.attempt_interaction()
		if success:
			get_viewport().set_input_as_handled()
		return

	# Pass input to mouse look
	if mouse_look:
		mouse_look.handle_input(event)


func _physics_process(delta):
	# Only process physics if input is enabled
	if not input_enabled:
		return

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
	var new_state: PlayerState

	if crouch_pressed:
		new_state = PlayerState.CROUCHING
	elif run_pressed:
		new_state = PlayerState.RUNNING
	else:
		new_state = PlayerState.NORMAL

	if new_state != current_state:
		current_state = new_state
		state_changed.emit(current_state)


# Component signal handlers
func _on_movement_state_changed(new_state: PlayerState):
	current_state = new_state
	state_changed.emit(current_state)


func _on_interactable_found(_interactable: Interactable):
	# Handle when an interactable is found
	pass


func _on_interactable_lost():
	# Handle when interactable is lost
	pass


func _on_interaction_performed(_interactable: Interactable):
	# Handle successful interaction
	pass


# Public methods for inventory integration
func get_current_state() -> PlayerState:
	return current_state


func get_interaction_system() -> InteractionSystem:
	return interaction_system


func set_input_enabled(enabled: bool):
	"""Enable or disable player input (called by inventory system)"""
	input_enabled = enabled


# Methods for inventory integration to call
func modify_health(amount: float):
	"""Modify player health (called when using health items)"""
	# Implementation depends on your health system
	print("Player health modified by: ", amount)


func modify_stamina(amount: float):
	"""Modify player stamina (called when using stamina items)"""
	# Implementation depends on your stamina system
	print("Player stamina modified by: ", amount)


func apply_equipment_bonuses(bonuses: Dictionary):
	"""Apply equipment stat bonuses"""
	# Implementation depends on your stat system
	print("Equipment bonuses applied: ", bonuses)


func remove_equipment_bonuses(bonuses: Dictionary):
	"""Remove equipment stat bonuses"""
	# Implementation depends on your stat system
	print("Equipment bonuses removed: ", bonuses)


func update_equipment_visual(item_data: Dictionary, equipped: bool):
	"""Update visual equipment on player model"""
	# This would update 3D model attachments, clothing, etc.
	print("Equipment visual updated: ", item_data.get("name", "Unknown"), " equipped: ", equipped)
