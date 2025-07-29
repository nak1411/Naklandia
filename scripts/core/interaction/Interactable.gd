# Interactable.gd - Base class for all interactable objects
class_name Interactable
extends Area3D

# Interactable properties
@export_group("Interaction")
@export var interaction_text: String = "Interact"
@export var interaction_key: String = "E"
@export var is_enabled: bool = true
@export var is_repeatable: bool = true
@export var interaction_cooldown: float = 0.0

@export_group("Visual Feedback")
@export var highlight_on_hover: bool = true
@export var highlight_color: Color = Color.YELLOW
@export var outline_enabled: bool = false

# Internal state
var has_been_used: bool = false
var cooldown_timer: float = 0.0
var original_materials: Array[Material] = []
var is_highlighted: bool = false

# Signals
signal interacted(player: Node)
signal interaction_enabled()
signal interaction_disabled()
signal hover_started()
signal hover_ended()

func _ready():
	# Setup Area3D properties
	set_collision_layer(2)  # Interaction layer
	set_collision_mask(0)   # Don't collide with anything
	
	# Store original materials for highlighting
	_store_original_materials()
	
	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(delta):
	# Handle cooldown
	if cooldown_timer > 0:
		cooldown_timer -= delta
		if cooldown_timer <= 0:
			_enable_interaction()

# Main interaction method - override in derived classes
func interact() -> bool:
	if not can_interact():
		return false
	
	# Perform interaction
	var success = _perform_interaction()
	
	if success:
		# Handle post-interaction state
		_handle_interaction_performed()
		
		# Emit signal
		interacted.emit(get_player_reference())
	
	return success

# Override this method in derived classes
func _perform_interaction() -> bool:
	print("Interacting with: ", name)
	return true

func can_interact() -> bool:
	return is_enabled and cooldown_timer <= 0 and (is_repeatable or not has_been_used)

func _handle_interaction_performed():
	has_been_used = true
	
	# Start cooldown if specified
	if interaction_cooldown > 0:
		cooldown_timer = interaction_cooldown
		_disable_interaction()

func _enable_interaction():
	is_enabled = true
	interaction_enabled.emit()

func _disable_interaction():
	is_enabled = false
	interaction_disabled.emit()

# Visual feedback methods
func start_hover():
	if not is_highlighted and highlight_on_hover:
		is_highlighted = true
		_apply_highlight()
		hover_started.emit()

func end_hover():
	if is_highlighted:
		is_highlighted = false
		_remove_highlight()
		hover_ended.emit()

func _apply_highlight():
	if highlight_on_hover:
		var mesh_instances = _get_all_mesh_instances()
		for mesh_instance in mesh_instances:
			if mesh_instance.material_override:
				var material = mesh_instance.material_override.duplicate()
				if material is StandardMaterial3D:
					material.emission = highlight_color
					material.emission_energy = 0.3
			else:
				var highlight_material = StandardMaterial3D.new()
				highlight_material.albedo_color = highlight_color
				highlight_material.emission = highlight_color
				highlight_material.emission_energy = 0.5
				mesh_instance.material_overlay = highlight_material

func _remove_highlight():
	var mesh_instances = _get_all_mesh_instances()
	for mesh_instance in mesh_instances:
		mesh_instance.material_overlay = null
		# Restore original material if we modified material_override
		var index = mesh_instances.find(mesh_instance)
		if index < original_materials.size() and original_materials[index]:
			mesh_instance.material_override = original_materials[index]

func _store_original_materials():
	var mesh_instances = _get_all_mesh_instances()
	original_materials.clear()
	for mesh_instance in mesh_instances:
		original_materials.append(mesh_instance.material_override)

func _get_all_mesh_instances() -> Array[MeshInstance3D]:
	var mesh_instances: Array[MeshInstance3D] = []
	_find_mesh_instances_recursive(self, mesh_instances)
	return mesh_instances

func _find_mesh_instances_recursive(node: Node, mesh_list: Array[MeshInstance3D]):
	if node is MeshInstance3D:
		mesh_list.append(node)
	
	for child in node.get_children():
		_find_mesh_instances_recursive(child, mesh_list)

# Utility methods
func get_player_reference() -> Node:
	# Try to find player in scene
	var scene_root = get_tree().current_scene
	return _find_player_recursive(scene_root)

func _find_player_recursive(node: Node) -> Node:
	if node.get_script() and node.get_script().get_global_name() == "Player":
		return node
	
	for child in node.get_children():
		var result = _find_player_recursive(child)
		if result:
			return result
	
	return null

# Event handlers
func _on_body_entered(_body):
	# Optional: Handle when player enters area
	pass

func _on_body_exited(_body):
	# Optional: Handle when player exits area
	pass

# Public interface
func set_interaction_text(text: String):
	interaction_text = text

func set_enabled(enabled: bool):
	is_enabled = enabled
	if enabled:
		interaction_enabled.emit()
	else:
		interaction_disabled.emit()

func reset_interaction():
	has_been_used = false
	cooldown_timer = 0.0
	_enable_interaction()
