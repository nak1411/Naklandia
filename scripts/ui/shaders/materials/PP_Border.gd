# EVEStylePixelPerfectBorder.gd - Enhanced border with bloom
class_name EVEStylePixelPerfectBorder
extends StyleBoxFlat

var bloom_material: EVEBloomMaterial

func _init():
	_setup_eve_style()
	bloom_material = EVEBloomMaterial.new()

func _setup_eve_style():
	anti_aliasing = false
	anti_aliasing_size = 0
	bg_color = Color(0.12, 0.14, 0.18, 0.95)
	border_width_top = 1
	border_width_bottom = 1
	border_width_left = 1
	border_width_right = 1
	border_color = Color(0.3, 0.4, 0.6, 1.0)