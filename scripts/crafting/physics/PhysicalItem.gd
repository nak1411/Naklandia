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
signal joint_created(item: PhysicalItem, joint: Joint)
signal fastener_attached(item: PhysicalItem, fastener: Fastener)

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

# Joint and fastener system
var joints: Array[Joint] = []  # Physics joints connecting this item
var fasteners: Array[Fastener] = []  # Fasteners holding connections
var connection_points: Array[Dictionary] = []  # Available connection points

# Highlighting for interaction
var outline_material: StandardMaterial3D
var original_material: Material
var mesh_instance: MeshInstance3D


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


func get_visual_center() -> Vector3:
	"""Get the center of the visual mesh in world space."""
	if mesh_instance and mesh_instance.mesh:
		var aabb = mesh_instance.mesh.get_aabb()
		var local_center = aabb.get_center()
		# Transform from mesh's local space to world space
		return mesh_instance.global_transform * local_center
	else:
		# Fallback to object position if no mesh
		return global_position


func get_info_text() -> String:
	"""Get display text for UI."""
	var info = "[b]%s[/b]\n" % item_name
	info += "%s\n" % item_description
	info += "Mass: %.2f kg\n" % item_mass
	if is_bonded:
		info += "Bonded to %d items\n" % bonded_items.size()
	if not joints.is_empty():
		info += "Joints: %d\n" % joints.size()
	if not fasteners.is_empty():
		info += "Fasteners: %d\n" % fasteners.size()
	return info


## Create a joint connection to another item using a fastener
func attach_with_fastener(
	target: PhysicalItem,
	fastener_item_id: String,
	connection_point: Vector3 = Vector3.ZERO,
	parent_node: Node3D = null
) -> Fastener:
	"""Attach this item to another using a fastener (nail, screw, bolt, hinge, etc.)."""

	if not target:
		push_error("PhysicalItem: Cannot attach - target is null")
		return null

	# Default to parent node if none provided
	if not parent_node:
		# Use the item's parent as the joint parent
		parent_node = get_parent()

	# Create fastener
	var fastener = Fastener.new(self, target, fastener_item_id)
	fastener.connection_point = connection_point if connection_point != Vector3.ZERO else global_position

	# Create joint through fastener
	if fastener.create_joint(parent_node):
		# Store fastener and joint
		fasteners.append(fastener)
		if fastener.joint:
			joints.append(fastener.joint)

		# Also add to target item
		target.fasteners.append(fastener)
		if fastener.joint:
			target.joints.append(fastener.joint)

		# Update bonding
		bond_to(target)

		# Emit signals
		fastener_attached.emit(self, fastener)
		if fastener.joint:
			joint_created.emit(self, fastener.joint)

		print("PhysicalItem: Attached %s to %s with %s" % [item_name, target.item_name, fastener_item_id])
		return fastener

	# Failed to create
	push_error("PhysicalItem: Failed to create fastener joint")
	return null


## Remove a fastener and its joint
func remove_fastener(fastener: Fastener, has_tool: bool = false) -> bool:
	"""Remove a fastener connection (requires appropriate tool)."""

	if not fastener in fasteners:
		push_warning("PhysicalItem: Fastener not found on this item")
		return false

	# Try to remove
	if fastener.remove(has_tool):
		# Remove from both items
		fasteners.erase(fastener)
		if fastener.joint:
			joints.erase(fastener.joint)

		if fastener.item_b and fastener in fastener.item_b.fasteners:
			fastener.item_b.fasteners.erase(fastener)
			if fastener.joint:
				fastener.item_b.joints.erase(fastener.joint)

		# Update bonding
		if fastener.item_b:
			unbond_from(fastener.item_b)

		print("PhysicalItem: Removed fastener from %s" % item_name)
		return true

	return false


## Get all items connected via joints
func get_jointed_items() -> Array[PhysicalItem]:
	"""Get all items connected to this one through joints."""
	var connected: Array[PhysicalItem] = []

	for joint in joints:
		if joint.item_a == self and joint.item_b:
			if joint.item_b not in connected:
				connected.append(joint.item_b)
		elif joint.item_b == self and joint.item_a:
			if joint.item_a not in connected:
				connected.append(joint.item_a)

	return connected


## Get all joints and fasteners as cluster
func get_assembly_cluster() -> Dictionary:
	"""Get all items, joints, and fasteners in the connected assembly."""
	var items: Array[PhysicalItem] = get_bonded_cluster()
	var all_joints: Array[Joint] = []
	var all_fasteners: Array[Fastener] = []

	for item in items:
		for joint in item.joints:
			if joint not in all_joints:
				all_joints.append(joint)
		for fastener in item.fasteners:
			if fastener not in all_fasteners:
				all_fasteners.append(fastener)

	return {
		"items": items,
		"joints": all_joints,
		"fasteners": all_fasteners
	}


## Load connection points from item metadata
func load_connection_points():
	"""Load connection points from ItemDatabase metadata."""
	connection_points.clear()

	if not ItemDatabase:
		return

	var item_def = ItemDatabase.get_item(item_id)
	if not item_def:
		return

	if item_def.custom_properties.has("connection_points"):
		var points = item_def.custom_properties.get("connection_points", [])
		for point_data in points:
			var point = {
				"position": Vector3.ZERO,
				"type": "surface"
			}

			if point_data.has("position"):
				var pos_array = point_data.get("position", [0, 0, 0])
				if pos_array is Array and pos_array.size() == 3:
					point.position = Vector3(pos_array[0], pos_array[1], pos_array[2])

			if point_data.has("type"):
				point.type = point_data.get("type", "surface")

			connection_points.append(point)

	print("PhysicalItem: Loaded %d connection points for %s" % [connection_points.size(), item_name])
