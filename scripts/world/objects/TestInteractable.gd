# TestInteractable.gd - Clean production version
extends Interactable

@export var activation_message: String = "Switch activated!"
@export var is_activated: bool = false

func _ready():
	# Call parent _ready
	super._ready()
	
	# Configure interaction
	interaction_text = "Activate Switch"
	interaction_key = "E"
	is_repeatable = true
	interaction_cooldown = 1.0

func _perform_interaction() -> bool:
	# Toggle state
	is_activated = !is_activated
	interaction_text = "Deactivate Switch" if is_activated else "Activate Switch"
	
	# Visual feedback
	_update_visual_state()
	
	return true

func _update_visual_state():
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
