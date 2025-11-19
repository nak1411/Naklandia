class_name PhysicalItem
extends RigidBody3D

## A physics-enabled craftable item that can be placed, moved, and bonded to other items.
##
## This is the base class for all physical crafting parts (boards, screws, nails, etc.)
## Players can pick these up, position them freely, and connect them together.

# Signals
signal item_grabbed(item: PhysicalItem)
signal item_released(item: PhysicalItem)
signal item_bonded(item: PhysicalItem, target: PhysicalItem)

# Item identification
@export var item_id: String = ""
@export var item_name: String = "Physical Item"
@export_multiline var item_description: String = ""

# Physical properties
@export_group("Physical Properties")
@export var item_mass: float = 1.0  # kg
@export var item_volume: float = 0.001  # m³ (default 1 liter)

# Inventory properties
@export_group("Inventory")
@export var can_pickup_to_inventory: bool = true
@export var pickup_quantity: int = 1
@export var icon_path: String = ""
@export var item_value: float = 10.0
@export var max_stack_size: int = 99

# Visual properties
@export_group("Visuals")
@export var mesh_path: String = ""
@export var material_path: String = ""

# Interaction state
var is_held: bool = false
var is_bonded: bool = false
var bonded_items: Array[PhysicalItem] = []

# Highlighting for interaction
var outline_material: StandardMaterial3D
var original_material: Material
var mesh_instance: MeshInstance3D

# Interactable system
var interactable_area: Area3D = null


func _ready() -> void:
	# Set up physics properties
	mass = item_mass

	# Set up collision layer/mask
	# Layer 3 for physical crafting items
	collision_layer = 4  # Binary: 100 (layer 3)
	collision_mask = 1 | 4  # Collide with world (layer 1) and other items (layer 3)

	# Find mesh instance for highlighting
	_find_mesh_instance()

	# Create outline material for when item is hoverable/selected
	_setup_outline_material()

	# Set up interactable area for inventory pickup (E key)
	if can_pickup_to_inventory:
		call_deferred("_setup_interactable_area")


func _find_mesh_instance() -> void:
	"""Recursively find the first MeshInstance3D child."""
	for child in get_children():
		if child is MeshInstance3D:
			mesh_instance = child
			if mesh_instance.get_surface_override_material_count() > 0:
				original_material = mesh_instance.get_surface_override_material(0)
			else:
				original_material = mesh_instance.mesh.surface_get_material(0) if mesh_instance.mesh else null
			break


func _setup_outline_material() -> void:
	"""Create a material for highlighting this item when interactable."""
	outline_material = StandardMaterial3D.new()
	outline_material.albedo_color = Color(0.3, 0.7, 1.0, 1.0)  # Light blue
	outline_material.emission_enabled = true
	outline_material.emission = Color(0.2, 0.5, 0.8, 1.0)
	outline_material.emission_energy_multiplier = 0.5


func grab() -> void:
	"""Called when player picks up this item."""
	if is_held:
		return

	is_held = true
	freeze = true  # Disable physics while held
	show_highlight(true)
	item_grabbed.emit(self)


func release() -> void:
	"""Called when player releases this item."""
	if not is_held:
		return

	is_held = false
	freeze = false  # Re-enable physics
	show_highlight(false)
	item_released.emit(self)


func show_highlight(enabled: bool) -> void:
	"""Show/hide the highlight outline."""
	if not mesh_instance:
		return

	if enabled:
		mesh_instance.set_surface_override_material(0, outline_material)
	else:
		mesh_instance.set_surface_override_material(0, original_material)


func bond_to(target: PhysicalItem) -> void:
	"""Create a bond connection to another physical item."""
	if target in bonded_items:
		return

	bonded_items.append(target)
	if self not in target.bonded_items:
		target.bonded_items.append(self)

	is_bonded = true
	item_bonded.emit(self, target)


func unbond_from(target: PhysicalItem) -> void:
	"""Remove a bond connection from another physical item."""
	if target in bonded_items:
		bonded_items.erase(target)

	if self in target.bonded_items:
		target.bonded_items.erase(self)

	if bonded_items.is_empty():
		is_bonded = false


func get_bonded_cluster() -> Array[PhysicalItem]:
	"""Get all items connected to this one through bonds (BFS traversal)."""
	var cluster: Array[PhysicalItem] = []
	var visited: Dictionary = {}
	var queue: Array[PhysicalItem] = [self]

	while not queue.is_empty():
		var current = queue.pop_front()
		if current in visited:
			continue

		visited[current] = true
		cluster.append(current)

		for bonded in current.bonded_items:
			if bonded not in visited:
				queue.append(bonded)

	return cluster


func set_position_smooth(target_pos: Vector3, delta: float, speed: float = 10.0) -> void:
	"""Smoothly move item to target position (for held items)."""
	if is_held:
		global_position = global_position.lerp(target_pos, delta * speed)


func set_rotation_smooth(target_basis: Basis, delta: float, speed: float = 10.0) -> void:
	"""Smoothly rotate item to target rotation (for held items)."""
	if is_held:
		global_transform.basis = global_transform.basis.slerp(target_basis, delta * speed)


func get_visual_center() -> Vector3:
	"""Get the center of the visual mesh in world space."""
	if mesh_instance and mesh_instance.mesh:
		var aabb = mesh_instance.mesh.get_aabb()
		var local_center = aabb.get_center()
		# Transform from mesh's local space to world space
		return mesh_instance.global_transform * local_center

	# Fallback to object position if no mesh
	return global_position


func get_info_text() -> String:
	"""Get display text for UI."""
	var info = "[b]%s[/b]\n" % item_name
	info += "%s\n" % item_description
	info += "Mass: %.2f kg\n" % item_mass
	if is_bonded:
		info += "Bonded to %d items\n" % bonded_items.size()
	return info


## Set up interactable area for E key inventory pickup
func _setup_interactable_area():
	"""Create an Area3D child that acts as an Interactable for inventory pickup."""
	# Ensure we're in the tree before setting up
	if not is_inside_tree():
		push_warning("PhysicalItem: Tried to setup interactable area before being in tree. Deferring...")
		call_deferred("_setup_interactable_area")
		return

	print("PhysicalItem: Setting up interactable area for ", item_name)

	# Create Area3D for interaction detection (Layer 2)
	interactable_area = Area3D.new()
	interactable_area.name = "InteractableArea"
	interactable_area.collision_layer = 2  # Layer 2 for interactables
	interactable_area.collision_mask = 0  # Don't collide with anything

	# Set script BEFORE adding to tree
	var interactable_script = load("res://scripts/inventory/core/items/specialized/PhysicalItemInteractable.gd")
	if interactable_script:
		interactable_area.set_script(interactable_script)
	else:
		push_error("PhysicalItem: Could not load PhysicalItemInteractable script!")
		return

	# Copy collision shapes from RigidBody3D to Area3D BEFORE adding to tree
	for child in get_children():
		if child is CollisionShape3D and child.get_parent() == self:
			var area_collision = CollisionShape3D.new()
			area_collision.shape = child.shape
			area_collision.transform = child.transform
			interactable_area.add_child(area_collision)

	# Set the physical_item reference BEFORE adding to tree
	if interactable_area.has_method("set"):
		interactable_area.set("physical_item", self)

	# Add to tree LAST (this will trigger _ready)
	add_child(interactable_area)


## Handle inventory pickup
func pickup_to_inventory(player: Node) -> bool:
	"""Pick up this item to the player's inventory."""
	if not can_pickup_to_inventory:
		return false

	# Get inventory integration from player
	var inventory_integration = player.get_node_or_null("InventoryIntegration")
	if not inventory_integration:
		push_warning("PhysicalItem: Player doesn't have InventoryIntegration")
		return false

	var inventory_manager = inventory_integration.inventory_manager
	if not inventory_manager:
		push_warning("PhysicalItem: No inventory manager found")
		return false

	var player_inventory = inventory_manager.get_player_inventory()
	if not player_inventory:
		push_warning("PhysicalItem: No player inventory found")
		return false

	# Create inventory item from PhysicalItem properties
	var item_data = _create_inventory_item_data()
	if not item_data:
		return false

	# Check if can add
	if not player_inventory.can_add_item(item_data):
		NotificationManager.show_warning("Inventory is full!")
		return false

	# Add to inventory
	var success = player_inventory.add_item(item_data)

	if success:
		NotificationManager.show_item_pickup(item_name, pickup_quantity)

		# Update inventory window if open
		if inventory_integration.is_inventory_window_open():
			var inventory_window = inventory_integration.get_inventory_window()
			if inventory_window and inventory_window.content:
				inventory_window.content.refresh_display()

		# Remove from world
		queue_free()
		return true

	NotificationManager.show_error("Failed to pick up item")
	return false


## Create inventory item data from PhysicalItem properties
func _create_inventory_item_data() -> InventoryItem_Base:
	"""Convert PhysicalItem properties to InventoryItem_Base."""
	var item_database = get_node_or_null("/root/ItemDatabase")

	# Try to get from database first
	if item_database and not item_id.is_empty():
		var item_def = item_database.get_item(item_id)
		if item_def:
			var item_data = InventoryItem_Base.new()
			item_data.item_id = item_def.item_id
			item_data.item_type = item_def.item_type
			item_data.item_name = item_def.name
			item_data.description = item_def.description
			item_data.volume = item_def.volume
			item_data.mass = item_def.mass
			item_data.base_value = item_def.value
			item_data.quantity = pickup_quantity
			item_data.max_stack_size = item_def.max_stack_size
			item_data.icon_path = item_def.icon_path
			return item_data

	# Fallback: create from PhysicalItem properties
	var item_data = InventoryItem_Base.new()
	item_data.item_id = item_id if not item_id.is_empty() else "physical_item_" + str(get_instance_id())
	item_data.item_type = ItemTypes.Type.RESOURCE  # Default to resource
	item_data.item_name = item_name
	item_data.description = item_description
	item_data.volume = item_volume
	item_data.mass = item_mass
	item_data.base_value = item_value
	item_data.quantity = pickup_quantity
	item_data.max_stack_size = max_stack_size
	item_data.icon_path = icon_path
	return item_data
