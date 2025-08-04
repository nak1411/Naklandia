# EVEBloomMaterial.gd - EVE Online bloom material
class_name EVEBloomMaterial
extends ShaderMaterial

func _init():
	_setup_eve_bloom_shader()

func _setup_eve_bloom_shader():
	# Load the bloom shader
	var bloom_shader = load("res://shaders/ui/eve_bloom_glow.gdshader") as Shader
	if bloom_shader:
		shader = bloom_shader
		
		# Set EVE-style default parameters
		set_shader_parameter("bloom_intensity", 2.5)
		set_shader_parameter("bloom_threshold", 0.3)
		set_shader_parameter("bloom_radius", 1.8)
		set_shader_parameter("glow_color", Color(0.6, 0.8, 1.0, 0.9))
		set_shader_parameter("edge_softness", 1.2)
		set_shader_parameter("pulse_speed", 1.5)
		set_shader_parameter("enable_pulse", true)

func apply_slot_hover_preset():
	set_shader_parameter("bloom_intensity", 3.0)
	set_shader_parameter("bloom_radius", 2.2)
	set_shader_parameter("glow_color", Color(0.6, 0.8, 1.0, 0.8))
	set_shader_parameter("enable_pulse", false)

func apply_selection_preset():
	set_shader_parameter("bloom_intensity", 4.0)
	set_shader_parameter("bloom_radius", 2.5)
	set_shader_parameter("glow_color", Color(0.8, 0.9, 1.0, 1.0))
	set_shader_parameter("enable_pulse", true)
	set_shader_parameter("pulse_speed", 2.0)