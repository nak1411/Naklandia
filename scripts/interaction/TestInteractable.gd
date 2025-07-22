# TestInteractable.gd - Example interactable object for testing
extends Interactable

@export var activation_message: String = "Switch activated!"
@export var is_activated: bool = false

func _ready():
	super._ready()
	interaction_text = "Activate Switch"
	interaction_key = "E"
	is_repeatable = true
	interaction_cooldown = 1.0

func _perform_interaction() -> bool:
	# Toggle the switch state
	is_activated = !is_activated
	
	# Update interaction text
	interaction_text = "Deactivate Switch" if is_activated else "Activate Switch"
	
	# Visual feedback
	_update_visual_state()
	
	# Print feedback
	var state_text = "ON" if is_activated else "OFF"
	print("%s - Switch is now %s" % [activation_message, state_text])
	
	return true

func _update_visual_state():
	# Change material color based on state
	var mesh_instances = _get_all_mesh_instances()
	for mesh_instance in mesh_instances:
		if mesh_instance.material_override:
			var material = mesh_instance.material_override as StandardMaterial3D
			if material:
				if is_activated:
					material.emission = Color.GREEN
					material.emission_energy = 0.5
				else:
					material.emission = Color.RED
					material.emission_energy = 0.2
