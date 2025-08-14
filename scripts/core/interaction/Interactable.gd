# Interactable.gd - Using proper outline material resource
class_name Interactable
extends Area3D

# Signals
signal interacted(player: Node)
signal interaction_enabled
signal interaction_disabled
signal hover_started
signal hover_ended

# Interactable properties
@export_group("Interaction")
@export var interaction_text: String = "Interact"
@export var interaction_key: String = "E"
@export var is_enabled: bool = true
@export var is_repeatable: bool = true
@export var interaction_cooldown: float = 0.0

@export_group("Visual Feedback")
@export var highlight_on_hover: bool = true
@export var outline_enabled: bool = true
@export var outline_material: ShaderMaterial
@export var outline_color: Color = Color.YELLOW
@export var outline_width: float = 0.01
@export var outline_pulse: bool = false
@export var pulse_speed: float = 2.0

# Internal state
var has_been_used: bool = false
var cooldown_timer: float = 0.0
var is_highlighted: bool = false
var outline_nodes: Array[MeshInstance3D] = []
var original_meshes: Array[MeshInstance3D] = []
var pulse_timer: float = 0.0


func _ready():
	# Setup Area3D properties
	set_collision_layer(2)  # Interaction layer
	set_collision_mask(0)  # Don't collide with anything

	# Load default outline material if none assigned
	if not outline_material:
		outline_material = load("res://assets/materials/OutlineMaterial.tres")

	# Setup outline system
	if outline_enabled and outline_material:
		_setup_outline_system()

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta):
	# Handle cooldown
	if cooldown_timer > 0:
		cooldown_timer -= delta
		if cooldown_timer <= 0:
			_enable_interaction()

	# Handle outline pulsing
	if outline_pulse and is_highlighted and outline_material:
		pulse_timer += delta
		var pulse_factor = (sin(pulse_timer * pulse_speed) + 1.0) * 0.5
		var current_color = outline_color
		current_color.a = outline_color.a * (0.5 + pulse_factor * 0.5)
		outline_material.set_shader_parameter("outline_color", current_color)


func _setup_outline_system():
	original_meshes = _get_all_mesh_instances()
	outline_nodes.clear()

	for mesh_instance in original_meshes:
		_create_outline_node(mesh_instance)


func _create_outline_node(mesh_instance: MeshInstance3D):
	# Create outline duplicate
	var outline_node = MeshInstance3D.new()
	outline_node.name = mesh_instance.name + "_Outline"
	outline_node.mesh = mesh_instance.mesh
	outline_node.skeleton = mesh_instance.skeleton
	outline_node.material_override = outline_material.duplicate()
	outline_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outline_node.visible = false

	# Set shader parameters
	var material = outline_node.material_override as ShaderMaterial
	material.set_shader_parameter("outline_color", outline_color)
	material.set_shader_parameter("outline_width", outline_width)

	# Add to scene tree
	mesh_instance.add_child(outline_node)
	outline_nodes.append(outline_node)


func start_hover():
	if not is_highlighted and highlight_on_hover:
		is_highlighted = true
		_show_outline()
		hover_started.emit()


func end_hover():
	if is_highlighted:
		is_highlighted = false
		_hide_outline()
		hover_ended.emit()


func _show_outline():
	if outline_enabled:
		for outline_node in outline_nodes:
			if outline_node and is_instance_valid(outline_node):
				outline_node.visible = true

		if outline_pulse:
			pulse_timer = 0.0


func _hide_outline():
	for outline_node in outline_nodes:
		if outline_node and is_instance_valid(outline_node):
			outline_node.visible = false


# Public methods for customizing outline
func set_outline_color(color: Color):
	outline_color = color
	for outline_node in outline_nodes:
		if outline_node and is_instance_valid(outline_node):
			var material = outline_node.material_override as ShaderMaterial
			if material:
				material.set_shader_parameter("outline_color", color)


func set_outline_width(width: float):
	outline_width = width
	for outline_node in outline_nodes:
		if outline_node and is_instance_valid(outline_node):
			var material = outline_node.material_override as ShaderMaterial
			if material:
				material.set_shader_parameter("outline_width", width)


func set_outline_pulse(enable: bool, speed: float = 2.0):
	outline_pulse = enable
	pulse_speed = speed


# Cleanup
func _exit_tree():
	for outline_node in outline_nodes:
		if outline_node and is_instance_valid(outline_node):
			outline_node.queue_free()
	outline_nodes.clear()


# Main interaction method - override in derived classes
func interact() -> bool:
	if not can_interact():
		return false

	var success = _perform_interaction()

	if success:
		_handle_interaction_performed()
		interacted.emit(get_player_reference())

	return success


func _perform_interaction() -> bool:
	print("Interacting with: ", name)
	return true


func can_interact() -> bool:
	return is_enabled and cooldown_timer <= 0 and (is_repeatable or not has_been_used)


func _handle_interaction_performed():
	has_been_used = true

	if interaction_cooldown > 0:
		cooldown_timer = interaction_cooldown
		_disable_interaction()


func _enable_interaction():
	is_enabled = true
	interaction_enabled.emit()


func _disable_interaction():
	is_enabled = false
	interaction_disabled.emit()


func _get_all_mesh_instances() -> Array[MeshInstance3D]:
	var mesh_instances: Array[MeshInstance3D] = []
	_find_mesh_instances_recursive(self, mesh_instances)
	return mesh_instances


func _find_mesh_instances_recursive(node: Node, mesh_list: Array[MeshInstance3D]):
	if node is MeshInstance3D:
		mesh_list.append(node)

	for child in node.get_children():
		_find_mesh_instances_recursive(child, mesh_list)


func get_player_reference() -> Node:
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


func _on_body_entered(_body):
	pass


func _on_body_exited(_body):
	pass


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
