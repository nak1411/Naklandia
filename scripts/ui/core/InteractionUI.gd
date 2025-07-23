# InteractionUI.gd - Handles interaction UI prompts and feedback
class_name InteractionUI
extends Control

# UI settings
@export_group("Interaction Prompt")
@export var prompt_text: String = "[E] {action}"
@export var prompt_color: Color = Color.WHITE
@export var prompt_bg_color: Color = Color(0, 0, 0, 0.7)
@export var prompt_padding: Vector2 = Vector2(16, 8)

@export_group("Animation")
@export var fade_duration: float = 0.2
@export var pulse_enabled: bool = true
@export var pulse_speed: float = 2.0
@export var pulse_intensity: float = 0.3

# UI nodes
var prompt_panel: Panel
var prompt_label: Label
var feedback_timer: float = 0.0

# Animation state
var prompt_is_visible: bool = false  # Changed from is_visible to avoid shadowing
var fade_tween: Tween
var pulse_time: float = 0.0

func _ready():
	setup_interaction_ui()

func setup_interaction_ui():
	# Set up control properties
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	
	# Create prompt panel
	prompt_panel = Panel.new()
	prompt_panel.name = "PromptPanel"
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt_panel)
	
	# Style the panel
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = prompt_bg_color
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	style_box.border_width_left = 2
	style_box.border_width_right = 2
	style_box.border_width_top = 2
	style_box.border_width_bottom = 2
	style_box.border_color = Color.WHITE.darkened(0.3)
	prompt_panel.add_theme_stylebox_override("panel", style_box)
	
	# Create prompt label
	prompt_label = Label.new()
	prompt_label.name = "PromptLabel"
	prompt_label.text = prompt_text
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.add_theme_color_override("font_color", prompt_color)
	prompt_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	prompt_label.add_theme_constant_override("shadow_offset_x", 1)
	prompt_label.add_theme_constant_override("shadow_offset_y", 1)
	prompt_panel.add_child(prompt_label)
	
	# Initially hidden
	modulate.a = 0.0
	visible = false

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

func show_interaction_prompt(interactable: Interactable):
	if not interactable:
		return
	
	# Update prompt text
	var action_text = interactable.interaction_text
	var key_text = interactable.interaction_key
	prompt_label.text = "[%s] %s" % [key_text, action_text]
	
	# Resize panel to fit text
	_resize_prompt_panel()
	
	# Show with fade animation
	_fade_in()

func hide_interaction_prompt():
	_fade_out()

func update_interaction_prompt(interactable: Interactable):
	if prompt_is_visible and interactable:
		# Update text if it changed
		var action_text = interactable.interaction_text
		var key_text = interactable.interaction_key
		var new_text = "[%s] %s" % [key_text, action_text]
		
		if prompt_label.text != new_text:
			prompt_label.text = new_text
			_resize_prompt_panel()

func show_interaction_feedback(message: String = "Interacted!", duration: float = 1.0):
	# Temporarily show feedback message
	if prompt_label:
		prompt_label.text = message
		_resize_prompt_panel()
		
		# Set timer to restore original prompt
		feedback_timer = duration
		
		# Flash effect
		var flash_tween = create_tween()
		flash_tween.tween_method(_set_panel_color, Color.WHITE, prompt_bg_color, 0.3)

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

func _resize_prompt_panel():
	if not prompt_label or not prompt_panel:
		return
	
	# Calculate required size
	var text_size = prompt_label.get_theme_font("font").get_string_size(
		prompt_label.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		prompt_label.get_theme_font_size("font_size")
	)
	
	# Set panel size with padding
	var panel_size = text_size + prompt_padding * 2
	prompt_panel.custom_minimum_size = panel_size
	prompt_panel.size = panel_size
	
	# Center the panel
	prompt_panel.position = -panel_size / 2
	
	# Position label within panel
	prompt_label.position = prompt_padding
	prompt_label.size = text_size

func _set_panel_color(color: Color):
	if prompt_panel:
		var style_box = prompt_panel.get_theme_stylebox("panel").duplicate()
		style_box.bg_color = color
		prompt_panel.add_theme_stylebox_override("panel", style_box)

func _hide_feedback():
	# This could restore the original prompt if an interactable is still targeted
	# For now, just hide the prompt
	hide_interaction_prompt()

# Public interface
func set_prompt_style(text_color: Color, bg_color: Color):
	prompt_color = text_color
	prompt_bg_color = bg_color
	
	if prompt_label:
		prompt_label.add_theme_color_override("font_color", text_color)
	
	if prompt_panel:
		_set_panel_color(bg_color)

func set_pulse_enabled(enabled: bool):
	pulse_enabled = enabled
	if not enabled and prompt_label:
		prompt_label.modulate.a = 1.0
