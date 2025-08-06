# WindowEdgeBloomMaterial.gd - Window edge bloom material with animation
class_name WindowEdgeBloomMaterial
extends ShaderMaterial

var base_intensity: float = 0.3
var current_intensity: float = 0.0

func _init():
	_setup_edge_bloom_shader()

func _setup_edge_bloom_shader():
	var edge_shader = load("res://scripts/inventory/presentation/effects/shaders/pp_border.gdshader") as Shader
	if edge_shader:
		shader = edge_shader
		_set_default_parameters()
	else:
		push_error("Failed to load pp_border.gdshader")

func _set_default_parameters():
	set_shader_parameter("enable_window_edge_bloom", true)
	set_shader_parameter("edge_bloom_width", 15.0)
	set_shader_parameter("edge_bloom_intensity", 0.0)
	set_shader_parameter("edge_bloom_color", Color(0.5, 0.8, 1.0, 1.0))
	set_shader_parameter("edge_bloom_softness", 6.0)
	set_shader_parameter("edge_falloff", 2.5)
	set_shader_parameter("spear_length", 8.0)  # Controls how gradually the spear tapers
	set_shader_parameter("show_left_edge", false)
	set_shader_parameter("show_right_edge", false)
	set_shader_parameter("show_top_edge", false)
	set_shader_parameter("show_bottom_edge", false)

func set_spear_length(length: float):
	"""Set how gradually the bloom tapers at the ends (spear effect)"""
	set_shader_parameter("spear_length", length)

func set_window_size(size: Vector2):
	set_shader_parameter("window_size", size)

func set_bloom_extend(extend: float):
	set_shader_parameter("bloom_extend", extend)

func set_intensity(intensity: float):
	current_intensity = intensity
	set_shader_parameter("edge_bloom_intensity", intensity)

func show_edge(resize_mode: Window_Base.ResizeMode):
	# Hide all edges first
	hide_all_edges()
	
	# Show the specified edge
	match resize_mode:
		Window_Base.ResizeMode.LEFT:
			set_shader_parameter("show_left_edge", true)
		Window_Base.ResizeMode.RIGHT:
			set_shader_parameter("show_right_edge", true)
		Window_Base.ResizeMode.TOP:
			set_shader_parameter("show_top_edge", true)
		Window_Base.ResizeMode.BOTTOM:
			set_shader_parameter("show_bottom_edge", true)
		Window_Base.ResizeMode.TOP_LEFT:
			set_shader_parameter("show_left_edge", true)
			set_shader_parameter("show_top_edge", true)
		Window_Base.ResizeMode.TOP_RIGHT:
			set_shader_parameter("show_right_edge", true)
			set_shader_parameter("show_top_edge", true)
		Window_Base.ResizeMode.BOTTOM_LEFT:
			set_shader_parameter("show_left_edge", true)
			set_shader_parameter("show_bottom_edge", true)
		Window_Base.ResizeMode.BOTTOM_RIGHT:
			set_shader_parameter("show_right_edge", true)
			set_shader_parameter("show_bottom_edge", true)

func hide_all_edges():
	set_shader_parameter("show_left_edge", false)
	set_shader_parameter("show_right_edge", false)
	set_shader_parameter("show_top_edge", false)
	set_shader_parameter("show_bottom_edge", false)