# TestScene.gd - Auto debug version that runs on startup
extends Node3D

var debug_label: Label

func _ready():
	setup_materials()
	setup_debug_ui()
	
	# Auto-run debug after scene is fully loaded
	call_deferred("_auto_debug_everything")
	
	print("=== SCENE LOADED ===")

func _auto_debug_everything():
	print("\n" + "=".repeat(50))
	print("AUTOMATIC DEBUG REPORT")
	print("=".repeat(50))
	
	# Check player
	var player = get_node_or_null("Player")
	if player:
		print("✓ Player found at: ", player.global_position)
		
		var camera = player.get_node_or_null("CameraPivot/Camera3D")
		if camera:
			print("✓ Camera found at: ", camera.global_position)
			print("  Camera forward: ", -camera.global_transform.basis.z)
		else:
			print("✗ Camera NOT found")
	else:
		print("✗ Player NOT found")
	
	# Check TestSwitch
	var test_switch = get_node_or_null("TestSwitch")
	if test_switch:
		print("✓ TestSwitch found at: ", test_switch.global_position)
		print("  Type: ", test_switch.get_class())
		print("  Collision layer: ", test_switch.collision_layer)
		print("  Script attached: ", test_switch.get_script() != null)
		
		# Check collision shape
		var collision_shape = test_switch.get_node_or_null("CollisionShape3D")
		if collision_shape:
			print("  ✓ CollisionShape3D: ", collision_shape.shape)
			print("  Disabled: ", collision_shape.disabled)
		else:
			print("  ✗ No CollisionShape3D found!")
		
		# Check mesh
		var mesh_instance = test_switch.get_node_or_null("MeshInstance3D")
		if mesh_instance:
			print("  ✓ MeshInstance3D: ", mesh_instance.mesh)
		else:
			print("  ✗ No MeshInstance3D found!")
		
		# Distance check
		if player:
			var distance = player.global_position.distance_to(test_switch.global_position)
			print("  Distance from player: ", distance)
			
			if distance > 5.0:
				print("  ⚠ WARNING: Switch is farther than interaction distance (5.0)!")
			
			# Check if in front of camera
			var camera = player.get_node_or_null("CameraPivot/Camera3D")
			if camera:
				var to_switch = (test_switch.global_position - camera.global_position).normalized()
				var camera_forward = -camera.global_transform.basis.z.normalized()
				var dot_product = camera_forward.dot(to_switch)
				print("  Switch visibility (dot product): ", dot_product)
				if dot_product > 0.5:
					print("  ✓ Switch should be visible ahead")
				else:
					print("  ⚠ Switch is behind or to the side")
	else:
		print("✗ TestSwitch NOT found!")
		print("Available scene children:")
		for child in get_children():
			print("  - ", child.name, " (", child.get_class(), ")")
	
	# Check interaction system
	if player:
		var interaction_system = player.get_node_or_null("InteractionSystem")
		if interaction_system:
			print("✓ InteractionSystem found")
			
			var raycaster = interaction_system.get_node_or_null("InteractionRaycaster")
			if raycaster:
				print("  ✓ InteractionRaycaster found")
				print("  Current interactable: ", raycaster.get_current_interactable())
			else:
				print("  ✗ InteractionRaycaster NOT found")
		else:
			print("✗ InteractionSystem NOT found")
	
	print("=".repeat(50))
	print("DEBUG REPORT COMPLETE")
	print("=".repeat(50))

func setup_materials():
	var materials = {
		"floor": _create_pbr_material(Color(0.7, 0.7, 0.75), 0.8, 0.1, "Concrete Floor"),
		"wall": _create_pbr_material(Color(0.5, 0.5, 0.55), 0.9, 0.0, "Stone Walls"), 
		"platform": _create_pbr_material(Color(0.2, 0.4, 0.8), 0.3, 0.8, "Metal Platform")
	}
	
	_apply_material_to_path("Level/Floor/MeshInstance3D", materials.floor)
	_apply_material_to_path("Level/Wall1/MeshInstance3D", materials.wall)
	_apply_material_to_path("Level/Wall2/MeshInstance3D", materials.wall)
	_apply_material_to_path("TestObjects/Platform/MeshInstance3D", materials.platform)

func _create_pbr_material(albedo: Color, roughness: float, metallic: float, name: String) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = roughness
	material.metallic = metallic
	material.specular = 0.5
	material.clearcoat_enabled = metallic > 0.5
	material.clearcoat = 0.3 if metallic > 0.5 else 0.0
	material.normal_enabled = true
	material.normal_scale = 0.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	material.resource_name = name
	return material

func _apply_material_to_path(path: String, material: StandardMaterial3D):
	var node = get_node_or_null(path)
	if node and node is MeshInstance3D:
		node.material_override = material

func setup_debug_ui():
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "UI"
	add_child(canvas_layer)
	
	# Add crosshair
	var crosshair = CrosshairUI.new()
	crosshair.name = "Crosshair"
	canvas_layer.add_child(crosshair)
	
	# Debug label
	debug_label = Label.new()
	debug_label.text = "Debug info will show in console on startup"
	debug_label.position = Vector2(10, 10)
	debug_label.add_theme_color_override("font_color", Color.WHITE)
	debug_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	debug_label.add_theme_constant_override("shadow_offset_x", 2)
	debug_label.add_theme_constant_override("shadow_offset_y", 2)
	canvas_layer.add_child(debug_label)
