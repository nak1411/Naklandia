# TestScene.gd - Clean production version
extends Node3D

func _ready():
	setup_materials()
	setup_ui()

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

func setup_ui():
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "UI"
	add_child(canvas_layer)
	
	# Add crosshair
	var crosshair = CrosshairUI.new()
	crosshair.name = "Crosshair"
	canvas_layer.add_child(crosshair)
