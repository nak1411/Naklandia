class_name PhysicalItem
extends RigidBody3D

## A physics-enabled craftable item that can be placed, moved, and bonded to other items.
##
## This is the base class for all physical crafting parts (boards, screws, nails, etc.)
## Players can pick these up, position them freely, and connect them together.

# Item identification
@export var item_id: String = ""
@export var item_name: String = "Physical Item"
@export_multiline var item_description: String = ""

# Physical properties
@export_group("Physical Properties")
@export var item_mass: float = 1.0  # kg
@export var item_volume: float = 0.001  # m³ (default 1 liter)

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

# Signals
signal item_grabbed(item: PhysicalItem)
signal item_released(item: PhysicalItem)
signal item_bonded(item: PhysicalItem, target: PhysicalItem)


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


func get_info_text() -> String:
	"""Get display text for UI."""
	var info = "[b]%s[/b]\n" % item_name
	info += "%s\n" % item_description
	info += "Mass: %.2f kg\n" % item_mass
	if is_bonded:
		info += "Bonded to %d items" % bonded_items.size()
	return info
