# TextGlowMaterial.gd - Material for text glow effects
class_name TextGlowMaterial
extends ShaderMaterial

func _init():
	_setup_text_glow_shader()

func _setup_text_glow_shader():
	var glow_shader = load("res://scripts/inventory/presentation/effects/shaders/text_glow.gdshader") as Shader
	if glow_shader:
		shader = glow_shader
		
		# Set default parameters
		set_shader_parameter("glow_strength", 1.5)
		set_shader_parameter("glow_color", Color(0.6, 0.8, 1.0, 0.8))
		set_shader_parameter("glow_size", 3.0)
		set_shader_parameter("enable_pulse", false)
		set_shader_parameter("pulse_speed", 2.0)
	else:
		push_error("Failed to load text_glow.gdshader")

func apply_eve_preset():
	"""Apply EVE-style glow settings"""
	set_shader_parameter("glow_strength", 50.0)
	set_shader_parameter("glow_color", Color(0.5, 0.7, 1.0, 0.9))
	set_shader_parameter("glow_size", 50.0)
	set_shader_parameter("enable_pulse", false)

func apply_close_button_preset():
	"""Apply red glow for close button"""
	set_shader_parameter("glow_strength", 1.8)
	set_shader_parameter("glow_color", Color(1.0, 0.4, 0.4, 0.8))
	set_shader_parameter("glow_size", 3.5)
	set_shader_parameter("enable_pulse", false)

func apply_hover_preset():
	"""Apply bright hover glow"""
	set_shader_parameter("glow_strength", 2.5)
	set_shader_parameter("glow_color", Color(0.8, 0.9, 1.0, 1.0))
	set_shader_parameter("glow_size", 5.0)
	set_shader_parameter("enable_pulse", true)
	set_shader_parameter("pulse_speed", 3.0)

func apply_subtle_preset():
	"""Apply subtle background glow"""
	set_shader_parameter("glow_strength", 1.0)
	set_shader_parameter("glow_color", Color(0.4, 0.6, 0.8, 0.6))
	set_shader_parameter("glow_size", 2.0)
	set_shader_parameter("enable_pulse", false)