# TestScene.gd - Updated to spawn different item types
extends Node3D

@onready var ui_manager: UIManager


func _ready():
	setup_materials()
	setup_ui_manager()

	# Wait for everything to initialize properly
	await get_tree().process_frame
	_load_window_position()

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
	ammo.global_position = position


func spawn_module_pickup(position: Vector3):
	# Create module programmatically
	var module = ModulePickup.new()
	module.name = "Gauss Turret"
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
	module.global_position = position


func spawn_resource_pickup(position: Vector3):
	var resource = ResourcePickup.new()
	resource.name = "Noxite"
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
	resource.global_position = position


func spawn_blueprint_pickup(position: Vector3):
	var blueprint = BlueprintPickup.new()
	blueprint.name = "Hybrid Charge Blueprint"
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
	blueprint.global_position = position


# Rest of your existing methods...
func setup_materials():
	pass


func setup_ui_manager():
	ui_manager = UIManager.new()


func _save_window_position():
	var config = ConfigFile.new()

	var window_pos = DisplayServer.window_get_position()
	var window_size = DisplayServer.window_get_size()
	var window_mode = DisplayServer.window_get_mode()

	config.set_value("window", "position_x", window_pos.x)
	config.set_value("window", "position_y", window_pos.y)
	config.set_value("window", "size_x", window_size.x)
	config.set_value("window", "size_y", window_size.y)
	config.set_value("window", "mode", window_mode)

	config.save("user://window_settings.cfg")


func _load_window_position():
	var config = ConfigFile.new()
	if config.load("user://window_settings.cfg") != OK:
		return

	var pos_x = config.get_value("window", "position_x", -1)
	var pos_y = config.get_value("window", "position_y", -1)
	var size_x = config.get_value("window", "size_x", -1)
	var size_y = config.get_value("window", "size_y", -1)
	var mode = config.get_value("window", "mode", DisplayServer.WINDOW_MODE_WINDOWED)

	# Apply window mode
	if mode != DisplayServer.window_get_mode():
		DisplayServer.window_set_mode(mode)

	# Apply position if valid and within screen bounds
	if pos_x >= 0 and pos_y >= 0:
		var screen_count = DisplayServer.get_screen_count()
		var valid_position = false

		for screen_id in screen_count:
			var screen_rect = Rect2(DisplayServer.screen_get_position(screen_id), DisplayServer.screen_get_size(screen_id))
			if screen_rect.has_point(Vector2i(pos_x, pos_y)):
				valid_position = true
				break

		if valid_position:
			DisplayServer.window_set_position(Vector2i(pos_x, pos_y))

	# Apply size if valid
	if size_x > 0 and size_y > 0:
		DisplayServer.window_set_size(Vector2i(size_x, size_y))


func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_window_position()
		get_tree().quit()
