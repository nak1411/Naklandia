# CrosshairUI.gd - Single dot crosshair with proximity-based opacity
class_name CrosshairUI
extends Control

# Crosshair settings
@export_group("Crosshair Style")
@export var dot_radius: float = 1.0
@export var dot_color: Color = Color.WHITE
@export var dot_outline: bool = true
@export var outline_color: Color = Color.BLACK
@export var outline_thickness: float = 1.0

@export_group("Interaction Behavior")
@export var max_interaction_distance: float = 2.0
@export var min_opacity: float = 0.0  # Hidden when no interactable
@export var max_opacity: float = 1.0  # Full opacity when very close

# Internal state
var current_opacity: float = 0.0
var target_opacity: float = 0.0
var current_distance: float = 0.0
var has_interactable: bool = false

# References
var player_ref: CharacterBody3D


func _ready():
	_setup_crosshair()
	_find_player_reference()
	z_index = 50


func _setup_crosshair():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_size(get_viewport().get_visible_rect().size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Start hidden
	modulate.a = 0.0


func _find_player_reference():
	var scene_root = get_tree().current_scene
	player_ref = _find_node_by_class(scene_root, CharacterBody3D)


func _find_node_by_class(node: Node, target_class) -> Node:
	if node.get_script() and node.get_script().get_global_name() == "Player":
		return node

	for child in node.get_children():
		var result = _find_node_by_class(child, target_class)
		if result:
			return result

	return null


func _process(delta):
	# Smooth opacity transition
	current_opacity = lerp(current_opacity, target_opacity, delta * 10.0)
	modulate.a = current_opacity

	queue_redraw()


func _draw():
	var screen_center = size / 2

	# Only draw if we have some opacity
	if current_opacity > 0.01:
		# Draw outline first if enabled
		if dot_outline:
			draw_circle(screen_center, dot_radius + outline_thickness, outline_color)

		# Draw main dot
		var dot_color_with_alpha = dot_color
		dot_color_with_alpha.a = current_opacity
		draw_circle(screen_center, dot_radius, dot_color_with_alpha)


func set_interaction_state(can_interact: bool, distance: float = 0.0):
	has_interactable = can_interact
	current_distance = distance

	if can_interact:
		# Calculate opacity based on distance (closer = more opaque)
		var normalized_distance = clamp(distance / max_interaction_distance, 0.0, 1.0)
		# Invert so closer objects give higher opacity
		var proximity_factor = 1.0 - normalized_distance
		target_opacity = lerp(min_opacity, max_opacity, proximity_factor)
	else:
		target_opacity = min_opacity


# Legacy method for backward compatibility
func set_interaction_state_simple(can_interact: bool):
	set_interaction_state(can_interact, current_distance)


func set_dot_size(new_radius: float):
	dot_radius = new_radius


func set_dot_color(new_color: Color):
	dot_color = new_color
