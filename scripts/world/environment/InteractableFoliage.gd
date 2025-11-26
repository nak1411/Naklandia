# InteractableFoliage.gd
# Harvestable foliage node (bushes, rocks, etc.) that can be interacted with
class_name InteractableFoliage
extends Interactable

# Foliage properties
@export_group("Foliage Settings")
@export var foliage_type: String = "Bush"  # Bush, Rock, etc.
@export var health: float = 100.0
@export var max_health: float = 100.0
@export var respawn_time: float = 300.0  # Time in seconds to respawn (0 = no respawn)
@export var auto_destroy_on_harvest: bool = true

# Harvest rewards
@export_group("Harvest Rewards")
@export var harvest_items: Array[Dictionary] = []  # {item_id: String, min_amount: int, max_amount: int, chance: float}
@export var harvest_experience: int = 5

# Visual feedback
@export_group("Harvest Visuals")
@export var damage_shake_intensity: float = 0.1
@export var harvest_particle_scene: PackedScene = null

# Internal state
var is_destroyed: bool = false
var respawn_timer: float = 0.0
var original_position: Vector3
var original_rotation: Vector3
var original_scale: Vector3
var visual_node: Node3D = null


func _ready():
	# DON'T call super._ready() yet - we need to set layer first

	# Setup Area3D properties BEFORE super._ready() which sets up the interaction system
	set_collision_layer_value(2, true)  # Layer 2 for interactions
	set_collision_layer_value(1, false) # Not on layer 1
	set_collision_mask(0)  # Don't collide with anything

	# NOW call super to setup interaction system
	super._ready()

	# Store original transform
	original_position = global_position
	original_rotation = rotation
	original_scale = scale

	# Set default interaction text
	if interaction_text == "Interact":
		interaction_text = "Harvest " + foliage_type

	# Find the visual node (usually first child with mesh)
	for child in get_children():
		if child is MeshInstance3D or child is Node3D:
			visual_node = child
			break

	# Debug: Verify setup (deferred to ensure collision shape is added)
	call_deferred("_debug_verify_setup")


func _debug_verify_setup():
	"""Debug function to verify the foliage is set up correctly"""
	print("[InteractableFoliage] Created: ", foliage_type, " at ", global_position)
	print("  Collision layer: ", collision_layer, " (should include layer 2)")
	print("  Has CollisionShape: ", get_node_or_null("CollisionShape3D") != null)
	var collision_shape = get_node_or_null("CollisionShape3D")
	if collision_shape and collision_shape.shape:
		print("  Collision shape type: ", collision_shape.shape.get_class())
		if collision_shape.shape is SphereShape3D:
			print("  Sphere radius: ", collision_shape.shape.radius)


func _process(delta):
	super._process(delta)

	# Handle respawn timer
	if is_destroyed and respawn_time > 0:
		respawn_timer -= delta
		if respawn_timer <= 0:
			respawn()


func interact() -> bool:
	"""Override interact to harvest the foliage"""
	if not super.interact():
		return false

	if is_destroyed:
		return false

	harvest()
	return true


func harvest():
	"""Harvest this foliage and give rewards"""
	if is_destroyed:
		return

	# Apply damage/harvest
	take_damage(max_health)

	# Give rewards to player
	var player = get_player_reference()
	if player:
		_give_harvest_rewards(player)

	# Visual feedback
	_play_harvest_effects()

	# Destroy or hide
	if auto_destroy_on_harvest:
		destroy()
	else:
		is_destroyed = true
		respawn_timer = respawn_time
		hide_visual()


func take_damage(damage: float):
	"""Apply damage to the foliage"""
	if is_destroyed:
		return

	health -= damage

	# Shake effect
	if visual_node and damage_shake_intensity > 0:
		_apply_damage_shake()

	if health <= 0:
		health = 0
		if not auto_destroy_on_harvest:
			is_destroyed = true
			respawn_timer = respawn_time


func destroy():
	"""Completely destroy this foliage node"""
	is_destroyed = true

	# Play effects
	_play_harvest_effects()

	# Queue for deletion or hide
	if respawn_time > 0:
		hide_visual()
		respawn_timer = respawn_time
	else:
		queue_free()


func respawn():
	"""Respawn the foliage after being harvested"""
	is_destroyed = false
	health = max_health
	respawn_timer = 0.0
	show_visual()


func hide_visual():
	"""Hide the visual representation"""
	if visual_node:
		visual_node.visible = false

	# Disable interaction
	set_enabled(false)


func show_visual():
	"""Show the visual representation"""
	if visual_node:
		visual_node.visible = true

	# Enable interaction
	set_enabled(true)


func _give_harvest_rewards(player: Node):
	"""Give harvest rewards to the player"""
	if not player:
		return

	# Check if player has inventory
	var inventory_integration = _find_player_inventory(player)
	if not inventory_integration:
		print("InteractableFoliage: Player has no inventory system")
		return

	# Give items from harvest_items list
	for reward_data in harvest_items:
		var item_id = reward_data.get("item_id", "")
		var min_amount = reward_data.get("min_amount", 1)
		var max_amount = reward_data.get("max_amount", 1)
		var chance = reward_data.get("chance", 1.0)

		# Roll for chance
		if randf() > chance:
			continue

		# Calculate random amount
		var amount = randi_range(min_amount, max_amount)

		# Try to add to inventory
		if inventory_integration.has_method("add_item_by_id"):
			inventory_integration.add_item_by_id(item_id, amount)
			print("Harvested ", amount, "x ", item_id, " from ", foliage_type)


func _find_player_inventory(player: Node) -> Node:
	"""Find the player's inventory integration"""
	# Try to find InventoryIntegration on player
	var integration = player.get_node_or_null("InventoryIntegration")
	if integration:
		return integration

	# Try global search
	var integrations = get_tree().get_nodes_in_group("inventory_integration")
	if integrations.size() > 0:
		return integrations[0]

	return null


func _play_harvest_effects():
	"""Play particle effects and sounds when harvested"""
	if harvest_particle_scene:
		var particles = harvest_particle_scene.instantiate()
		get_parent().add_child(particles)
		particles.global_position = global_position

		# Auto-cleanup particles after a delay
		if particles is GPUParticles3D:
			particles.emitting = true
			await get_tree().create_timer(particles.lifetime * 2).timeout
			particles.queue_free()


func _apply_damage_shake():
	"""Apply a shake effect when damaged"""
	if not visual_node:
		return

	# Create a simple shake tween
	var tween = create_tween()
	tween.set_parallel(true)

	# Shake position
	var shake_offset = Vector3(
		randf_range(-damage_shake_intensity, damage_shake_intensity),
		0,
		randf_range(-damage_shake_intensity, damage_shake_intensity)
	)

	tween.tween_property(visual_node, "position", shake_offset, 0.05)
	tween.tween_property(visual_node, "position", Vector3.ZERO, 0.1).set_delay(0.05)


func set_foliage_data(data: Dictionary):
	"""Set foliage properties from a dictionary (useful for procedural spawning)"""
	if data.has("foliage_type"):
		foliage_type = data["foliage_type"]
	if data.has("health"):
		health = data["health"]
		max_health = data["health"]
	if data.has("respawn_time"):
		respawn_time = data["respawn_time"]
	if data.has("harvest_items"):
		harvest_items = data["harvest_items"]
	if data.has("harvest_experience"):
		harvest_experience = data["harvest_experience"]

	# Update interaction text
	interaction_text = "Harvest " + foliage_type
