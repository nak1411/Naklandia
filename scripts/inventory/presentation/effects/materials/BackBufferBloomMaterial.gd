# BackBufferBloomMaterial.gd - Material for true bloom effects using BackBufferCopy
class_name BackBufferBloomMaterial
extends ShaderMaterial


func _init():
	_setup_backbuffer_bloom_shader()


func _setup_backbuffer_bloom_shader():
	var bloom_shader = load("res://scripts/inventory/presentation/effects/shaders/backbuffer_bloom.gdshader") as Shader
	if bloom_shader:
		shader = bloom_shader

		# Set default parameters
		set_shader_parameter("bloom_intensity", 2.0)
		set_shader_parameter("bloom_color", Color(0.6, 0.8, 1.0, 1.0))
		set_shader_parameter("bloom_threshold", 0.4)
		set_shader_parameter("blur_radius", 6.0)
		set_shader_parameter("bloom_spread", 1.5)
		set_shader_parameter("enable_pulse", false)
		set_shader_parameter("pulse_speed", 2.0)
	else:
		push_error("Failed to load backbuffer_bloom.gdshader")


func apply_button_bloom_preset(button_type: String = "normal"):
	"""Apply bloom preset for title bar buttons"""
	if button_type == "close":
		set_shader_parameter("bloom_color", Color(1.0, 0.4, 0.4, 1.0))
		set_shader_parameter("bloom_intensity", 2.5)
		set_shader_parameter("bloom_threshold", 0.3)
		set_shader_parameter("blur_radius", 8.0)
		set_shader_parameter("bloom_spread", 2.0)
	else:
		set_shader_parameter("bloom_color", Color(0.5, 0.7, 1.0, 1.0))
		set_shader_parameter("bloom_intensity", 2.0)
		set_shader_parameter("bloom_threshold", 0.4)
		set_shader_parameter("blur_radius", 6.0)
		set_shader_parameter("bloom_spread", 1.5)


func apply_intense_bloom():
	"""Apply intense bloom for hover effects"""
	set_shader_parameter("bloom_intensity", 3.5)
	set_shader_parameter("bloom_threshold", 0.2)
	set_shader_parameter("blur_radius", 10.0)
	set_shader_parameter("bloom_spread", 2.5)
	set_shader_parameter("enable_pulse", true)
	set_shader_parameter("pulse_speed", 3.0)


func apply_subtle_bloom():
	"""Apply subtle bloom for normal state"""
	set_shader_parameter("bloom_intensity", 1.5)
	set_shader_parameter("bloom_threshold", 0.5)
	set_shader_parameter("blur_radius", 4.0)
	set_shader_parameter("bloom_spread", 1.0)
	set_shader_parameter("enable_pulse", false)
