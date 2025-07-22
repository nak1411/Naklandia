# TestInteractable.gd - Safe debug version
extends Interactable

@export var activation_message: String = "Switch activated!"
@export var is_activated: bool = false

func _ready():
	print("=== TEST SWITCH SETUP ===")
	print("Switch name: ", name)
	print("Switch position: ", global_position)
	
	# Call parent _ready
	super._ready()
	
	# Configure interaction
	interaction_text = "Activate Switch"
	interaction_key = "E"
	is_repeatable = true
	interaction_cooldown = 1.0
	
	print("Collision layer: ", collision_layer)
	print("Collision mask: ", collision_mask)
	print("Area3D monitoring: ", monitoring)
	print("Area3D monitorable: ", monitorable)
	
	# Check collision shape
	var collision_shape = get_node_or_null("CollisionShape3D")
	if collision_shape:
		print("CollisionShape3D found: ", collision_shape.shape)
	else:
		print("WARNING: No CollisionShape3D found!")
	
	# Check mesh
	var mesh_instance = get_node_or_null("MeshInstance3D")
	if mesh_instance:
		print("MeshInstance3D found with mesh: ", mesh_instance.mesh)
	else:
		print("WARNING: No MeshInstance3D found!")

func _perform_interaction() -> bool:
	print("=== SWITCH ACTIVATED ===")
	
	# Toggle state
	is_activated = !is_activated
	interaction_text = "Deactivate Switch" if is_activated else "Activate Switch"
	
	# Visual feedback
	_update_visual_state()
	
	var state_text = "ON" if is_activated else "OFF"
	print("Switch is now: ", state_text)
	
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

func start_hover():
	print("HOVER START: ", name)
	super.start_hover()

func end_hover():
	print("HOVER END: ", name)
	super.end_hover()

func can_interact() -> bool:
	var result = super.can_interact()
	print("Can interact: ", result)
	return result
