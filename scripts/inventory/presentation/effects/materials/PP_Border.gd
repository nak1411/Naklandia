# EVEStylePixelPerfectBorder.gd - Enhanced border with window edge bloom
class_name EVEStylePixelPerfectBorder
extends StyleBoxFlat

var bloom_material: BloomMaterial
var edge_shader: Shader


func _init():
	_setup_eve_style()
	bloom_material = BloomMaterial.new()
	_load_edge_shader()


func _setup_eve_style():
	anti_aliasing = false
	anti_aliasing_size = 0
	bg_color = Color(0.12, 0.14, 0.18, 0.95)
	border_width_top = 1
	border_width_bottom = 1
	border_width_left = 1
	border_width_right = 1
	border_color = Color(0.3, 0.4, 0.6, 1.0)


func _load_edge_shader():
	"""Load the enhanced edge shader"""
	edge_shader = load("res://shaders/ui/pp_border.gdshader") as Shader
	if not edge_shader:
		push_error("Failed to load pp_border.gdshader")


func create_window_edge_material() -> ShaderMaterial:
	"""Create a shader material for window edge bloom"""
	if not edge_shader:
		return null

	var material = ShaderMaterial.new()
	material.shader = edge_shader

	# Set default window edge bloom parameters
	material.set_shader_parameter("enable_window_edge_bloom", true)
	material.set_shader_parameter("edge_bloom_width", 32.0)
	material.set_shader_parameter("edge_bloom_intensity", 1.5)
	material.set_shader_parameter("edge_bloom_color", Color(0.6, 0.8, 1.0, 0.4))
	material.set_shader_parameter("edge_bloom_softness", 4.0)
	material.set_shader_parameter("edge_falloff", 3.0)
	material.set_shader_parameter("edge_pulse", false)
	material.set_shader_parameter("edge_pulse_speed", 2.0)
	material.set_shader_parameter("enhanced_mode", false)

	return material


func create_enhanced_border_material() -> ShaderMaterial:
	"""Create a shader material that combines borders with bloom"""
	if not edge_shader:
		return null

	var material = ShaderMaterial.new()
	material.shader = edge_shader

	# Enable both border and bloom
	material.set_shader_parameter("enable_window_edge_bloom", true)
	material.set_shader_parameter("enhanced_mode", true)
	material.set_shader_parameter("border_color", Color(0.6, 0.8, 1.0, 1.0))
	material.set_shader_parameter("border_width", 2.0)
	material.set_shader_parameter("anti_alias", false)
	material.set_shader_parameter("edge_bloom_width", 24.0)
	material.set_shader_parameter("edge_bloom_intensity", 1.2)
	material.set_shader_parameter("edge_bloom_color", Color(0.6, 0.8, 1.0, 0.3))
	material.set_shader_parameter("bloom_border_interaction", 1.5)

	return material


# Preset methods for different window edge bloom states
func apply_subtle_edge_preset(material: ShaderMaterial):
	"""Subtle edge bloom for normal windows"""
	material.set_shader_parameter("edge_bloom_width", 24.0)
	material.set_shader_parameter("edge_bloom_intensity", 1.0)
	material.set_shader_parameter("edge_bloom_color", Color(0.5, 0.7, 0.9, 0.3))
	material.set_shader_parameter("edge_bloom_softness", 6.0)
	material.set_shader_parameter("edge_pulse", false)
	material.set_shader_parameter("edge_falloff", 4.0)


func apply_active_edge_preset(material: ShaderMaterial):
	"""Enhanced bloom for active/focused windows"""
	material.set_shader_parameter("edge_bloom_width", 40.0)
	material.set_shader_parameter("edge_bloom_intensity", 2.0)
	material.set_shader_parameter("edge_bloom_color", Color(0.75, 0.85, 1.0, 0.6))
	material.set_shader_parameter("edge_bloom_softness", 3.0)
	material.set_shader_parameter("edge_pulse", false)
	material.set_shader_parameter("edge_falloff", 2.5)


func apply_alert_edge_preset(material: ShaderMaterial):
	"""Pulsing bloom for alerts/notifications"""
	material.set_shader_parameter("edge_bloom_width", 48.0)
	material.set_shader_parameter("edge_bloom_intensity", 2.5)
	material.set_shader_parameter("edge_bloom_color", Color(1.0, 0.7, 0.3, 0.7))
	material.set_shader_parameter("edge_bloom_softness", 2.0)
	material.set_shader_parameter("edge_pulse", true)
	material.set_shader_parameter("edge_pulse_speed", 3.0)
	material.set_shader_parameter("edge_falloff", 2.0)


func apply_critical_edge_preset(material: ShaderMaterial):
	"""Intense pulsing bloom for critical alerts"""
	material.set_shader_parameter("edge_bloom_width", 56.0)
	material.set_shader_parameter("edge_bloom_intensity", 3.0)
	material.set_shader_parameter("edge_bloom_color", Color(1.0, 0.4, 0.4, 0.8))
	material.set_shader_parameter("edge_bloom_softness", 1.5)
	material.set_shader_parameter("edge_pulse", true)
	material.set_shader_parameter("edge_pulse_speed", 4.5)
	material.set_shader_parameter("edge_falloff", 1.8)
