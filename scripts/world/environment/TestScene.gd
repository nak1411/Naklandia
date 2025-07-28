# TestScene.gd - Updated to use UIManager
extends Node3D

@onready var ui_manager: UIManager

func _ready():
	setup_materials()
	setup_ui_manager()  # Use UIManager instead of direct CanvasLayer

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

func setup_ui_manager():
	# Create UI Manager
	ui_manager = UIManager.new()
	ui_manager.name = "UIManager"
	add_child(ui_manager)
	
	# Wait for UI Manager to be ready
	await ui_manager.ready
	
	# Add crosshair to HUD
	var crosshair = CrosshairUI.new()
	crosshair.name = "Crosshair"
	ui_manager.add_hud_element(crosshair)
	
	print("UIManager setup complete with crosshair")

func create_sample_menu():
	# Example sample menu - you can remove this later
	var sample_label = Label.new()
	sample_label.text = "Sample Menu (Press ESC to hide)"
	sample_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ui_manager.add_menu_element(sample_label)
