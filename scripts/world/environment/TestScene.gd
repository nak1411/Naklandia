# TestScene.gd - Updated to use UIManager
extends Node3D

@onready var ui_manager: UIManager

func _ready():
	setup_materials()
	setup_ui_manager()
	
	# Wait for everything to initialize properly
	await get_tree().create_timer(2.0).timeout
	create_test_pickup()

func create_test_pickup():
	var pickup = Area3D.new()
	pickup.name = "TestPickup"
	pickup.global_position = Vector3(2, 1.5, 0)
	pickup.collision_layer = 2
	pickup.collision_mask = 0
	
	# Add mesh
	var mesh_instance = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.5, 0.5, 0.5)
	mesh_instance.mesh = mesh
	pickup.add_child(mesh_instance)
	
	# Add collision to Area3D
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.5, 0.5, 0.5)
	collision.shape = shape
	pickup.add_child(collision)
	
	# IMPORTANT: Add RaycastTarget like TestSwitch has
	var raycast_target = StaticBody3D.new()
	raycast_target.name = "RaycastTarget"
	raycast_target.collision_layer = 2
	raycast_target.collision_mask = 0
	pickup.add_child(raycast_target)
	
	# Add collision to RaycastTarget
	var target_collision = CollisionShape3D.new()
	target_collision.shape = shape  # Same shape
	raycast_target.add_child(target_collision)
	
	# Add script
	var pickup_script = preload("res://scripts/inventory/items/PickupableItem.gd")
	pickup.set_script(pickup_script)
	
	add_child(pickup)
	print("Pickup with RaycastTarget created!")

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

func _create_pbr_material(albedo: Color, roughness: float, metallic: float, _name: String) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = roughness
	material.metallic = metallic
	material.metallic_specular = 0.5
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
