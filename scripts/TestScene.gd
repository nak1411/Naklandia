# TestScene.gd - Automatically sets up materials and testing features
extends Node3D

# UI for testing feedback
var debug_label: Label

func _ready():
	setup_materials()
	setup_debug_ui()
	print("Test Scene Ready!")
	print("Controls:")
	print("  WASD - Move")
	print("  Mouse - Look around") 
	print("  Space - Jump")
	print("  Shift - Run")
	print("  Ctrl - Crouch")
	print("  E - Interact")
	print("  Escape - Toggle mouse")

func setup_materials():
	# Create high-quality materials with PBR properties
	var materials = {
		"floor": _create_pbr_material(Color(0.7, 0.7, 0.75), 0.8, 0.1, "Concrete Floor"),
		"wall": _create_pbr_material(Color(0.5, 0.5, 0.55), 0.9, 0.0, "Stone Walls"), 
		"platform": _create_pbr_material(Color(0.2, 0.4, 0.8), 0.3, 0.8, "Metal Platform")
	}
	
	# Apply materials to level geometry
	_apply_material_to_path("Level/Floor/MeshInstance3D", materials.floor)
	_apply_material_to_path("Level/Wall1/MeshInstance3D", materials.wall)
	_apply_material_to_path("Level/Wall2/MeshInstance3D", materials.wall)
	
	# Apply materials to test objects
	_apply_material_to_path("TestObjects/Platform/MeshInstance3D", materials.platform)

func _create_pbr_material(albedo: Color, roughness: float, metallic: float, name: String) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = roughness
	material.metallic = metallic
	
	# Enhanced visual properties
	material.specular = 0.5
	material.clearcoat_enabled = metallic > 0.5
	material.clearcoat = 0.3 if metallic > 0.5 else 0.0
	
	# Add subtle normal mapping effect
	material.normal_enabled = true
	material.normal_scale = 0.5
	
	# Improve lighting response
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	
	material.resource_name = name
	return material

func _apply_material_to_path(path: String, material: StandardMaterial3D):
	var node = get_node_or_null(path)
	if node and node is MeshInstance3D:
		node.material_override = material
	else:
		print("Warning: Could not find MeshInstance3D at path: ", path)

func setup_debug_ui():
	# Create enhanced UI with crosshair
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "UI"
	add_child(canvas_layer)
	
	# Add crosshair - Create instance directly since we have the script
	var crosshair = CrosshairUI.new()
	crosshair.name = "Crosshair"
	canvas_layer.add_child(crosshair)
	
	# Debug info panel
	debug_label = Label.new()
	debug_label.text = "First Person Controller - Enhanced Test Scene\nF1: Toggle help | F2: Toggle dynamic crosshair\nESC: Toggle mouse capture"
	debug_label.position = Vector2(10, 10)
	debug_label.add_theme_color_override("font_color", Color.WHITE)
	debug_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	debug_label.add_theme_constant_override("shadow_offset_x", 2)
	debug_label.add_theme_constant_override("shadow_offset_y", 2)
	canvas_layer.add_child(debug_label)
	
	# Performance info
	var perf_label = Label.new()
	perf_label.name = "PerfLabel"
	perf_label.position = Vector2(10, get_viewport().size.y - 60)
	perf_label.add_theme_color_override("font_color", Color.YELLOW)
	perf_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	perf_label.add_theme_constant_override("shadow_offset_x", 1)
	perf_label.add_theme_constant_override("shadow_offset_y", 1)
	canvas_layer.add_child(perf_label)

func _input(event):
	# Check for F1 key press (KeyCode 4194332)
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F1:
			debug_label.visible = !debug_label.visible
			print("Debug info toggled: ", debug_label.visible)
		
		# Check for F2 key press (KeyCode 4194333)
		elif event.keycode == KEY_F2:
			var crosshair = get_node_or_null("UI/Crosshair")
			if crosshair:
				crosshair.enable_dynamic_crosshair = !crosshair.enable_dynamic_crosshair
				print("Dynamic crosshair: ", crosshair.enable_dynamic_crosshair)

# Optional: Add some simple animations or interactive elements
func _process(delta):
	# Update performance info
	var perf_label = get_node_or_null("UI/PerfLabel")
	if perf_label:
		var fps = Engine.get_frames_per_second()
		var process_time = Performance.get_monitor(Performance.TIME_PROCESS) * 1000
		perf_label.text = "FPS: %d | Frame Time: %.1fms" % [fps, process_time]
