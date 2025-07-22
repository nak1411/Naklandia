# CrosshairUI.gd - Modular crosshair component
class_name CrosshairUI
extends Control

# Crosshair settings
@export_group("Crosshair Style")
@export var crosshair_size: float = 20.0
@export var crosshair_thickness: float = 2.0
@export var crosshair_gap: float = 8.0
@export var crosshair_color: Color = Color.WHITE
@export var crosshair_outline: bool = true
@export var outline_color: Color = Color.BLACK
@export var outline_thickness: float = 1.0

@export_group("Dynamic Behavior")
@export var enable_dynamic_crosshair: bool = true
@export var movement_spread: float = 5.0
@export var jump_spread: float = 8.0
@export var crouch_reduction: float = 0.7

# Internal state
var base_gap: float
var current_spread: float = 0.0
var target_spread: float = 0.0

# References
var player_ref: CharacterBody3D

func _ready():
	# Set up the crosshair
	base_gap = crosshair_gap
	_setup_crosshair()
	
	# Find player reference
	_find_player_reference()
	
	# Make sure we're always on top
	z_index = 100

func _setup_crosshair():
	# Center the control
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	
	# Set size
	custom_minimum_size = Vector2(crosshair_size * 3, crosshair_size * 3)

func _find_player_reference():
	# Try to find player in scene
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
	if enable_dynamic_crosshair and player_ref:
		_update_dynamic_crosshair(delta)
	
	queue_redraw()

func _update_dynamic_crosshair(delta: float):
	var new_target_spread = 0.0
	
	# Check player state and velocity
	var velocity_magnitude = Vector2(player_ref.velocity.x, player_ref.velocity.z).length()
	var is_moving = velocity_magnitude > 0.1
	var is_on_floor = player_ref.is_on_floor()
	
	# Get player state if available
	var player_script = player_ref.get_script()
	if player_script and player_ref.has_method("get_current_state"):
		var player_state = player_ref.current_state
		
		# Adjust spread based on player state
		match player_state:
			0: # NORMAL
				if is_moving:
					new_target_spread = movement_spread * (velocity_magnitude / 8.0)
			1: # CROUCHING  
				new_target_spread = (movement_spread * (velocity_magnitude / 3.0)) * crouch_reduction
			2: # RUNNING
				if is_moving:
					new_target_spread = movement_spread * 1.5 * (velocity_magnitude / 10.0)
	
	# Add jump spread
	if not is_on_floor:
		new_target_spread += jump_spread
	
	# Smooth transition
	target_spread = new_target_spread
	current_spread = lerp(current_spread, target_spread, delta * 10.0)

func _draw():
	var center = size / 2
	var gap = base_gap + current_spread
	var half_size = crosshair_size / 2
	
	# Draw crosshair lines
	if crosshair_outline:
		_draw_crosshair_line(center, gap, half_size, outline_color, crosshair_thickness + outline_thickness * 2)
	
	_draw_crosshair_line(center, gap, half_size, crosshair_color, crosshair_thickness)

func _draw_crosshair_line(center: Vector2, gap: float, half_size: float, color: Color, thickness: float):
	# Horizontal line (left and right)
	draw_line(
		Vector2(center.x - gap - half_size, center.y),
		Vector2(center.x - gap, center.y),
		color, thickness
	)
	draw_line(
		Vector2(center.x + gap, center.y),
		Vector2(center.x + gap + half_size, center.y),
		color, thickness
	)
	
	# Vertical line (up and down)
	draw_line(
		Vector2(center.x, center.y - gap - half_size),
		Vector2(center.x, center.y - gap),
		color, thickness
	)
	draw_line(
		Vector2(center.x, center.y + gap),
		Vector2(center.x, center.y + gap + half_size),
		color, thickness
	)

# Public methods for customization
func set_crosshair_color(color: Color):
	crosshair_color = color

func set_crosshair_size(size: float):
	crosshair_size = size
	_setup_crosshair()

func set_dynamic_enabled(enabled: bool):
	enable_dynamic_crosshair = enabled
