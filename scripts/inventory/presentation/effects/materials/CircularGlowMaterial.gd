# CircularGlowMaterial.gd - Material for circular button glow effects
class_name CircularGlowMaterial
extends ShaderMaterial

func _init():
	_setup_circular_glow_shader()

func _setup_circular_glow_shader():
	# Load the circular glow shader
	var glow_shader = load("res://scripts/inventory/presentation/effects/shaders/circular_glow.gdshader") as Shader
	if glow_shader:
		shader = glow_shader
		
		# Set default parameters for button hover
		set_shader_parameter("glow_radius", 0.8)
		set_shader_parameter("glow_intensity", 1.5)
		set_shader_parameter("glow_color", Color(0.6, 0.8, 1.0, 0.6))
		set_shader_parameter("inner_radius", 0.2)
		set_shader_parameter("softness", 0.4)
		set_shader_parameter("enable_pulse", false)
		set_shader_parameter("pulse_speed", 2.0)
	else:
		push_error("Failed to load circular_glow.gdshader - check file path")

func apply_button_hover_preset(button_type: String = "normal"):
	"""Apply sunburst preset for button hover effects"""
	if button_type == "close":
		set_shader_parameter("glow_color", Color(1.0, 0.4, 0.4, 0.6))
		set_shader_parameter("glow_intensity", 1.2)
		set_shader_parameter("glow_radius", 1.4)  # Larger radius for more spread
		set_shader_parameter("inner_radius", 0.02)  # Very small inner hole
		set_shader_parameter("falloff_power", 4.0)  # Strong falloff for sunburst
		set_shader_parameter("softness", 1.2)  # Very soft edges
	else:
		set_shader_parameter("glow_color", Color(0.5, 0.7, 1.0, 0.5))
		set_shader_parameter("glow_intensity", 1.0)
		set_shader_parameter("glow_radius", 1.3)  # Larger radius
		set_shader_parameter("inner_radius", 0.03)  # Very small inner hole
		set_shader_parameter("falloff_power", 3.8)  # Strong falloff
		set_shader_parameter("softness", 1.0)  # Soft edges

func apply_sunburst_preset():
	"""Apply a dramatic sunburst effect"""
	set_shader_parameter("glow_intensity", 0.8)
	set_shader_parameter("glow_radius", 1.6)  # Very large radius
	set_shader_parameter("inner_radius", 0.01)  # Tiny inner hole
	set_shader_parameter("falloff_power", 5.0)  # Very strong falloff
	set_shader_parameter("softness", 1.5)  # Maximum softness

func apply_subtle_sunburst():
	"""Apply a very subtle sunburst effect"""
	set_shader_parameter("glow_intensity", 0.6)
	set_shader_parameter("glow_radius", 1.2)
	set_shader_parameter("inner_radius", 0.05)
	set_shader_parameter("falloff_power", 4.5)
	set_shader_parameter("softness", 1.8)