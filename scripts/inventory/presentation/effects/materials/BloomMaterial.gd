# EVEBloomMaterial.gd - EVE Online bloom material
class_name BloomMaterial
extends ShaderMaterial

func _init():
	_setup_eve_bloom_shader()

func _setup_eve_bloom_shader():
	# Load the bloom shader
	var bloom_shader = load("res://scripts/inventory/presentation/effects/shaders/bloom_glow.gdshader") as Shader
	if bloom_shader:
		shader = bloom_shader
		
		# Set EVE-style default parameters
		set_shader_parameter("bloom_intensity", 2.0)
		set_shader_parameter("bloom_threshold", 0.2)
		set_shader_parameter("bloom_radius", 0.8)
		set_shader_parameter("glow_color", Color(0.9, 0.8, 1.0, 0.6))
		set_shader_parameter("edge_softness", 1.2)
		set_shader_parameter("pulse_speed", 1.5)
		set_shader_parameter("enable_pulse", false)
	else:
		push_error("Failed to load bloom_glow.gdshader - check file path")

func apply_slot_hover_preset():
	"""Enhanced preset for inventory slot hover with smooth falloff"""
	set_shader_parameter("bloom_intensity", 12.0)
	set_shader_parameter("inner_radius", 0.8)
	set_shader_parameter("outer_radius", 0.42)
	set_shader_parameter("glow_color", Color(0.75, 0.85, 1.0, 0.8))
	set_shader_parameter("enable_pulse", false)
	set_shader_parameter("falloff_power", 0.6)  # Smooth but defined falloff
	set_shader_parameter("edge_softness", 0.2)  # Very soft edges

func apply_selection_preset():
	"""Enhanced preset for selected slots with stronger, pulsing bloom"""
	set_shader_parameter("bloom_intensity", 3.0)
	set_shader_parameter("inner_radius", 0.1)
	set_shader_parameter("outer_radius", 0.65)
	set_shader_parameter("glow_color", Color(0.8, 0.9, 1.0, 0.9))
	set_shader_parameter("enable_pulse", true)
	set_shader_parameter("pulse_speed", 1.8)
	set_shader_parameter("falloff_power", 2.5)  # Slightly sharper for selection
	set_shader_parameter("edge_softness", 1.0)

func apply_subtle_preset():
	"""Very subtle bloom for background slots"""
	set_shader_parameter("bloom_intensity", 1.5)
	set_shader_parameter("inner_radius", 0.15)
	set_shader_parameter("outer_radius", 0.45)
	set_shader_parameter("glow_color", Color(0.5, 0.7, 0.9, 0.6))
	set_shader_parameter("enable_pulse", false)
	set_shader_parameter("falloff_power", 3.5)  # Very soft falloff
	set_shader_parameter("edge_softness", 1.2)

func apply_intense_preset():
	"""Intense bloom for special states (rare items, etc.)"""
	set_shader_parameter("bloom_intensity", 3.5)
	set_shader_parameter("inner_radius", 0.08)
	set_shader_parameter("outer_radius", 0.7)
	set_shader_parameter("glow_color", Color(0.9, 0.95, 1.0, 1.0))
	set_shader_parameter("enable_pulse", true)
	set_shader_parameter("pulse_speed", 2.5)
	set_shader_parameter("falloff_power", 2.2)
	set_shader_parameter("edge_softness", 0.7)

func set_slot_aspect_ratio(width: float, height: float):
	"""Set the aspect ratio to match slot dimensions"""
	var aspect = Vector2(width / height, 1.0)
	set_shader_parameter("slot_aspect", aspect)