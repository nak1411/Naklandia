# ItemSpawner.gd
extends Node3D
class_name ItemSpawner

enum SpawnMode { RANDOM, DESIGNATED }

@export var spawn_mode: SpawnMode = SpawnMode.RANDOM
@export var spawn_interval: float = 5.0
@export var auto_spawn: bool = false
@export var max_spawned_items: int = -1  # -1 for unlimited

# For designated spawning
@export var designated_item_types: Array[String] = []

# For random spawning
@export var random_item_pool: Array[String] = ["AmmoPickup", "ModulePickup", "ResourcePickup", "BlueprintPickup"]

# Spawn positioning
@export var spawn_radius: float = 5.0
@export var spawn_height: float = 1.5

var spawned_items: Array[Node3D] = []
var spawn_timer: Timer

func _ready():
	if auto_spawn:
		setup_spawn_timer()

func setup_spawn_timer():
	spawn_timer = Timer.new()
	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	spawn_timer.autostart = true
	add_child(spawn_timer)

func _on_spawn_timer_timeout():
	if can_spawn():
		spawn_item()

func can_spawn() -> bool:
	return max_spawned_items == -1 or spawned_items.size() < max_spawned_items

func spawn_item(custom_position: Vector3 = Vector3.ZERO) -> Node3D:
	if not can_spawn():
		return null
	
	var item_type: String
	if spawn_mode == SpawnMode.DESIGNATED:
		item_type = get_designated_item_type()
	else:
		item_type = get_random_item_type()
	
	if item_type.is_empty():
		return null
	
	var position = custom_position if custom_position != Vector3.ZERO else get_spawn_position()
	var spawned_item = create_item(item_type, position)
	
	if spawned_item:
		spawned_items.append(spawned_item)
		# Connect to cleanup when item is freed
		if spawned_item.tree_exiting:
			spawned_item.tree_exiting.connect(_on_item_cleanup.bind(spawned_item))
	
	return spawned_item

func get_designated_item_type() -> String:
	if designated_item_types.is_empty():
		return ""
	return designated_item_types[randi() % designated_item_types.size()]

func get_random_item_type() -> String:
	if random_item_pool.is_empty():
		return ""
	return random_item_pool[randi() % random_item_pool.size()]

func get_spawn_position() -> Vector3:
	var angle = randf() * TAU
	var distance = randf() * spawn_radius
	var x = cos(angle) * distance
	var z = sin(angle) * distance
	return global_position + Vector3(x, spawn_height, z)

func create_item(item_type: String, position: Vector3) -> Node3D:
	var item: Node3D
	
	match item_type:
		"AmmoPickup":
			item = create_ammo_pickup(position)
		"ModulePickup":
			item = create_module_pickup(position)
		"ResourcePickup":
			item = create_resource_pickup(position)
		"BlueprintPickup":
			item = create_blueprint_pickup(position)
		_:
			print("Unknown item type: ", item_type)
			return null
	
	get_tree().current_scene.add_child(item)
	return item

func create_ammo_pickup(position: Vector3) -> AmmoPickup:
	var ammo = AmmoPickup.new()
	ammo.name = "Hybrid Charges"
	ammo.position = position
	ammo.collision_layer = 2
	ammo.collision_mask = 0
	
	# Add mesh and collision
	var mesh_instance = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.3, 0.3, 0.8)
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
	
	return ammo

func create_module_pickup(position: Vector3) -> ModulePickup:
	var module = ModulePickup.new()
	module.name = "Gauss Turret"
	module.position = position
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
	
	return module

func create_resource_pickup(position: Vector3) -> ResourcePickup:
	var resource = ResourcePickup.new()
	resource.name = "Noxite"
	resource.position = position
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
	
	return resource

func create_blueprint_pickup(position: Vector3) -> BlueprintPickup:
	var blueprint = BlueprintPickup.new()
	blueprint.name = "Hybrid Charge Blueprint"
	blueprint.position = position
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
	
	return blueprint

func _on_item_cleanup(item: Node3D):
	if item in spawned_items:
		spawned_items.erase(item)

# Public interface
func spawn_item_at_position(position: Vector3) -> Node3D:
	return spawn_item(position)

func clear_all_spawned_items():
	for item in spawned_items:
		if is_instance_valid(item):
			item.queue_free()
	spawned_items.clear()

func set_spawn_mode(mode: SpawnMode):
	spawn_mode = mode

func add_designated_item_type(item_type: String):
	if item_type not in designated_item_types:
		designated_item_types.append(item_type)

func remove_designated_item_type(item_type: String):
	designated_item_types.erase(item_type)

func set_random_item_pool(pool: Array[String]):
	random_item_pool = pool