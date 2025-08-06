# TestScene.gd - Updated to spawn different item types
extends Node3D

@onready var ui_manager: UIManager

func _ready():
	setup_materials()
	setup_ui_manager()
	
	# Wait for everything to initialize properly
	await get_tree().create_timer(2.0).timeout
	create_test_items()

func create_test_items():
	# Spawn different item types
	spawn_ammo_pickup(Vector3(2, 1.5, 0))
	spawn_module_pickup(Vector3(4, 1.5, 0))
	spawn_resource_pickup(Vector3(6, 1.5, 0))
	spawn_blueprint_pickup(Vector3(8, 1.5, 0))

func spawn_ammo_pickup(position: Vector3):
	# Create ammo programmatically - SAME as others
	var ammo = AmmoPickup.new()
	ammo.name = "Hybrid Charges"
	ammo.global_position = position
	ammo.collision_layer = 2
	ammo.collision_mask = 0
	
	# Add mesh and collision
	var mesh_instance = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.3, 0.3, 0.8)  # Ammo-like shape
	mesh_instance.mesh = mesh
	ammo.add_child(mesh_instance)
	
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.3, 0.3, 0.8)
	collision.shape = shape
	ammo.add_child(collision)
	
	# Add raycast target
	var raycast_target = StaticBody3D.new()
	raycast_target.name = "RaycastTarget"
	raycast_target.collision_layer = 2
	raycast_target.collision_mask = 0
	ammo.add_child(raycast_target)
	
	var target_collision = CollisionShape3D.new()
	target_collision.shape = shape
	raycast_target.add_child(target_collision)
	
	add_child(ammo)

func spawn_module_pickup(position: Vector3):
	# Create module programmatically
	var module = ModulePickup.new()
	module.name = "Gauss Turret"
	module.global_position = position
	module.collision_layer = 2
	module.collision_mask = 0
	module.module_name = "Gauss Turret"
	
	# Add mesh and collision
	var mesh_instance = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.8, 0.3, 0.8)
	mesh_instance.mesh = mesh
	module.add_child(mesh_instance)

	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.8, 0.3, 0.8)
	collision.shape = shape
	module.add_child(collision)

	# Add raycast target
	var raycast_target = StaticBody3D.new()
	raycast_target.name = "RaycastTarget"
	raycast_target.collision_layer = 2
	raycast_target.collision_mask = 0
	module.add_child(raycast_target)

	var target_collision = CollisionShape3D.new()
	target_collision.shape = shape
	raycast_target.add_child(target_collision)
	
	add_child(module)

func spawn_resource_pickup(position: Vector3):
	var resource = ResourcePickup.new()
	resource.name = "Noxite"
	resource.global_position = position
	resource.collision_layer = 2
	resource.collision_mask = 0
	resource.resource_name = "Noxite"
	resource.resource_quantity = 500
	
	# Add mesh and collision
	var mesh_instance = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = 0.3
	mesh_instance.mesh = mesh
	resource.add_child(mesh_instance)

	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.3
	collision.shape = shape
	resource.add_child(collision)

	# Add raycast target
	var raycast_target = StaticBody3D.new()
	raycast_target.name = "RaycastTarget"
	raycast_target.collision_layer = 2
	raycast_target.collision_mask = 0
	resource.add_child(raycast_target)
	
	var target_collision = CollisionShape3D.new()
	target_collision.shape = shape
	raycast_target.add_child(target_collision)
	
	add_child(resource)

func spawn_blueprint_pickup(position: Vector3):
	var blueprint = BlueprintPickup.new()
	blueprint.name = "Hybrid Charge Blueprint"
	blueprint.global_position = position
	blueprint.collision_layer = 2
	blueprint.collision_mask = 0
	blueprint.blueprint_name = "Hybrid Charge Blueprint"
	
	# Add mesh and collision
	var mesh_instance = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = 0.4
	mesh_instance.mesh = mesh
	blueprint.add_child(mesh_instance)

	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.4
	collision.shape = shape
	blueprint.add_child(collision)

	# Add raycast target
	var raycast_target = StaticBody3D.new()
	raycast_target.name = "RaycastTarget"
	raycast_target.collision_layer = 2
	raycast_target.collision_mask = 0
	blueprint.add_child(raycast_target)

	var target_collision = CollisionShape3D.new()
	target_collision.shape = shape
	raycast_target.add_child(target_collision)
	
	add_child(blueprint)

# Rest of your existing methods...
func setup_materials():
	pass

func setup_ui_manager():
	ui_manager = UIManager.new()