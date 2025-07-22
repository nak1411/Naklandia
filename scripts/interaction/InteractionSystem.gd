# InteractionSystem.gd - Clean production version
class_name InteractionSystem
extends Node

# Interaction settings
@export_group("Interaction")
@export var interaction_distance: float = 3.0
@export var interaction_layer: int = 2  # Physics layer for interactables

# Component references - using untyped variables to avoid class loading issues
var raycaster: Node
var ui: Node

# Current interaction state
var current_interactable: Interactable = null
var interaction_available: bool = false

# Signals
signal interactable_found(interactable: Interactable)
signal interactable_lost()
signal interaction_performed(interactable: Interactable)

func _ready():
	# Get component references
	raycaster = get_node("InteractionRaycaster")
	ui = get_node("InteractionUI")
	
	# Setup raycaster
	if raycaster:
		raycaster.setup_raycaster(interaction_distance, interaction_layer)
		raycaster.interactable_detected.connect(_on_interactable_detected)
		raycaster.interactable_lost.connect(_on_interactable_lost)
	
	# Setup UI
	if ui:
		ui.setup_interaction_ui()

func _process(delta):
	# Update raycaster
	if raycaster:
		raycaster.update_raycast()
	
	# Update UI
	if ui and current_interactable:
		ui.update_interaction_prompt(current_interactable)

func attempt_interaction() -> bool:
	if current_interactable and interaction_available:
		# Perform interaction
		var success = current_interactable.interact()
		if success:
			interaction_performed.emit(current_interactable)
			
			# Visual feedback
			if ui:
				ui.show_interaction_feedback()
			
			# Crosshair feedback
			_update_crosshair_interaction()
		
		return success
	
	return false

func _on_interactable_detected(interactable: Interactable):
	current_interactable = interactable
	interaction_available = true
	
	# Update UI
	if ui:
		ui.show_interaction_prompt(interactable)
	
	# Update crosshair
	_update_crosshair_interaction()
	
	# Emit signal
	interactable_found.emit(interactable)

func _on_interactable_lost():
	current_interactable = null
	interaction_available = false
	
	# Update UI
	if ui:
		ui.hide_interaction_prompt()
	
	# Update crosshair
	_update_crosshair_interaction()
	
	# Emit signal
	interactable_lost.emit()

func _update_crosshair_interaction():
	# Find crosshair and update it
	var scene_root = get_tree().current_scene
	var crosshair = _find_crosshair_recursive(scene_root)
	if crosshair and crosshair.has_method("set_interaction_state"):
		crosshair.set_interaction_state(interaction_available)

func _find_crosshair_recursive(node: Node) -> Node:
	if node.name == "Crosshair":
		return node
	
	for child in node.get_children():
		var result = _find_crosshair_recursive(child)
		if result:
			return result
	
	return null

# Public getters
func get_current_interactable() -> Interactable:
	return current_interactable

func is_interaction_available() -> bool:
	return interaction_available

func get_interaction_distance() -> float:
	return interaction_distance

func set_interaction_distance(distance: float):
	interaction_distance = distance
	if raycaster:
		raycaster.set_raycast_distance(distance)
