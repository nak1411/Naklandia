# InteractionUI.gd - Text-only interaction prompts with proximity-based visibility
class_name InteractionUI
extends Control

# UI settings
@export_group("Interaction Prompt")
@export var prompt_text: String = "[E] {action}"
@export var prompt_color: Color = Color.WHITE
@export var crosshair_offset: Vector2 = Vector2(0, 40)  # Offset below crosshair

@export_group("Proximity Settings")
@export var text_show_distance: float = 1.5  # Distance when text appears
@export var max_interaction_distance: float = 3.0  # Maximum interaction range

@export_group("Animation")
@export var fade_duration: float = 0.2
@export var pulse_enabled: bool = true
@export var pulse_speed: float = 2.0
@export var pulse_intensity: float = 0.3

# UI nodes
var prompt_label: Label
var feedback_timer: float = 0.0
var crosshair_ref: CrosshairUI

# State tracking
var current_interactable: Interactable
var current_distance: float = 0.0
var prompt_is_visible: bool = false
var fade_tween: Tween
var pulse_time: float = 0.0

func _ready():
	setup_interaction_ui()

func setup_interaction_ui():
	# Set up control properties
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 60  # Above crosshair (which is 50)
	
	# Create prompt label only (no panel background)
	prompt_label = Label.new()
	prompt_label.name = "PromptLabel"
	prompt_label.text = ""
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.add_theme_color_override("font_color", prompt_color)
	prompt_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	prompt_label.add_theme_constant_override("shadow_offset_x", 1)
	prompt_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(prompt_label)
	
	# Find crosshair reference
	_find_crosshair_reference()
	
	# Initially hidden
	modulate.a = 0.0
	visible = false

func _find_crosshair_reference():
	await get_tree().process_frame
	
	var ui_managers = get_tree().get_nodes_in_group("ui_manager")
	if ui_managers.size() > 0:
		var ui_manager = ui_managers[0]
		if ui_manager.has_method("get_crosshair"):
			crosshair_ref = ui_manager.get_crosshair()

func _process(delta):
	# Handle feedback timer
	if feedback_timer > 0:
		feedback_timer -= delta
		if feedback_timer <= 0:
			_hide_feedback()
	
	# Handle pulse animation
	if pulse_enabled and prompt_is_visible:
		pulse_time += delta * pulse_speed
		var pulse_alpha = 1.0 + sin(pulse_time) * pulse_intensity
		if prompt_label:
			prompt_label.modulate.a = pulse_alpha
	
	# Position prompt under crosshair
	_update_prompt_position()

func _update_prompt_position():
	if not prompt_label:
		return
	
	# Get screen center (crosshair position)
	var screen_center = get_viewport().get_visible_rect().size / 2
	
	# Calculate text size for centering
	var text_size = Vector2.ZERO
	if prompt_label.text != "":
		text_size = prompt_label.get_theme_font("font").get_string_size(
			prompt_label.text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			prompt_label.get_theme_font_size("font_size")
		)
	
	# Position label under crosshair with offset
	var final_position = screen_center + crosshair_offset - (text_size / 2)
	prompt_label.position = final_position
	prompt_label.size = text_size

func show_interaction_prompt(interactable: Interactable, distance: float = 0.0):
	if not interactable:
		return
	
	# Store current interactable and distance
	current_interactable = interactable
	current_distance = distance
	
	# Set text from interactable
	var action_text = interactable.interaction_text
	var key_text = interactable.interaction_key
	prompt_label.text = "[%s] %s" % [key_text, action_text]
	
	# Only show text if close enough
	if distance <= text_show_distance:
		_fade_in()
	else:
		_fade_out()

func update_interaction_prompt(interactable: Interactable, distance: float = 0.0):
	if interactable:
		current_interactable = interactable
		current_distance = distance
		
		# Update text if it changed
		var action_text = interactable.interaction_text
		var key_text = interactable.interaction_key
		var new_text = "[%s] %s" % [key_text, action_text]
		
		if prompt_label.text != new_text:
			prompt_label.text = new_text
		
		# Show/hide based on distance
		if distance <= text_show_distance and not prompt_is_visible:
			_fade_in()
		elif distance > text_show_distance and prompt_is_visible:
			_fade_out()

func hide_interaction_prompt():
	current_interactable = null
	current_distance = 0.0
	_fade_out()

func show_interaction_feedback(message: String = "Interacted!", duration: float = 1.0):
	if prompt_label:
		prompt_label.text = message
		feedback_timer = duration
		
		# Flash effect
		var flash_tween = create_tween()
		flash_tween.tween_method(_set_label_color, Color.YELLOW, prompt_color, 0.3)

func _fade_in():
	if fade_tween:
		fade_tween.kill()
	
	visible = true
	prompt_is_visible = true
	pulse_time = 0.0
	
	fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", 1.0, fade_duration)

func _fade_out():
	if fade_tween:
		fade_tween.kill()
	
	prompt_is_visible = false
	
	fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	fade_tween.tween_callback(func(): visible = false)

func _set_label_color(color: Color):
	if prompt_label:
		prompt_label.add_theme_color_override("font_color", color)

func _hide_feedback():
	# If we still have an interactable, restore its prompt based on distance
	if current_interactable:
		var action_text = current_interactable.interaction_text
		var key_text = current_interactable.interaction_key
		prompt_label.text = "[%s] %s" % [key_text, action_text]
		
		# Only show if close enough
		if current_distance <= text_show_distance:
			_fade_in()
		else:
			_fade_out()
	else:
		hide_interaction_prompt()

# Public interface
func set_prompt_style(text_color: Color):
	prompt_color = text_color
	if prompt_label:
		prompt_label.add_theme_color_override("font_color", text_color)

func set_pulse_enabled(enabled: bool):
	pulse_enabled = enabled
	if not enabled and prompt_label:
		prompt_label.modulate.a = 1.0

func set_crosshair_offset(offset: Vector2):
	crosshair_offset = offset

func set_text_show_distance(distance: float):
	text_show_distance = distance