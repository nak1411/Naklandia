class_name AssemblyData
extends Resource

## Represents a saved assembly from the workbench that can be spawned as a single item.
##
## An assembly stores all the parts, their transforms, connections, and fasteners
## so the assembled model can be recreated as a unified PhysicalItem.

# Assembly identification
@export var assembly_id: String = ""
@export var assembly_name: String = "New Assembly"
@export var assembly_description: String = ""
@export var creation_date: String = ""

# Assembly properties
@export var total_mass: float = 0.0
@export var total_volume: float = 0.0
@export var assembly_value: float = 0.0

# Part data - stores all parts and their relative transforms
@export var parts: Array[Dictionary] = []  # [{scene_path: String, transform: Transform3D, item_id: String}]

# Connection data - stores fasteners between parts
@export var fasteners: Array[Dictionary] = []  # [{item_a_index: int, item_b_index: int, fastener_id: String, connection_point: Vector3}]

# Visual representation
@export var icon_path: String = ""
@export var preview_texture: Texture2D = null

# Bounding box for the assembly
var bounds_min: Vector3 = Vector3.ZERO
var bounds_max: Vector3 = Vector3.ZERO


func _init() -> void:
	assembly_id = _generate_assembly_id()
	creation_date = Time.get_datetime_string_from_system()


## Generate a unique assembly ID
func _generate_assembly_id() -> String:
	return "assembly_%d_%d" % [Time.get_ticks_msec(), randi()]


## Create AssemblyData from a collection of PhysicalItems in the workbench
static func from_physical_items(items: Array[PhysicalItem], name: String = "") -> AssemblyData:
	"""Create an assembly from a list of PhysicalItems with their current transforms."""
	if items.is_empty():
		push_error("AssemblyData: Cannot create assembly from empty items array")
		return null

	var assembly = AssemblyData.new()
	assembly.assembly_name = name if not name.is_empty() else "Assembly_%d" % Time.get_ticks_msec()

	# Calculate center of mass / pivot point
	var center_point = Vector3.ZERO
	for item in items:
		# Check if item is still valid (not freed)
		if not is_instance_valid(item):
			push_error("AssemblyData: Item is no longer valid (freed)")
			return null
		center_point += item.global_position
	center_point /= items.size()

	# Store each part with its transform relative to center point
	for item in items:
		# Check if item is still valid (not freed)
		if not is_instance_valid(item):
			push_error("AssemblyData: Item is no longer valid (freed)")
			return null
		var part_data = {
			"scene_path": item.scene_file_path,
			"item_id": item.item_id,
			"item_name": item.item_name,
			"transform": _make_relative_transform(item.global_transform, center_point),
			"mass": item.item_mass,
			"volume": item.item_volume,
		}
		assembly.parts.append(part_data)

		# Accumulate totals
		assembly.total_mass += item.item_mass
		assembly.total_volume += item.item_volume

	# Store fastener connections
	var processed_fasteners: Array[Fastener] = []
	for i in range(items.size()):
		var item = items[i]
		for fastener in item.fasteners:
			# Skip if already processed
			if fastener in processed_fasteners:
				continue
			processed_fasteners.append(fastener)

			# Find indices of connected items
			var item_a_index = items.find(fastener.item_a)
			var item_b_index = items.find(fastener.item_b)

			if item_a_index >= 0 and item_b_index >= 0:
				var fastener_data = {
					"item_a_index": item_a_index,
					"item_b_index": item_b_index,
					"fastener_id": fastener.fastener_item_id,
					"connection_point": fastener.connection_point - center_point,  # Relative to center
				}
				assembly.fasteners.append(fastener_data)

	# Calculate bounds
	assembly._calculate_bounds()

	# Estimate value (could be sum of parts, or have crafting bonus)
	assembly.assembly_value = assembly.total_mass * 10.0  # Simple value calculation

	print("AssemblyData: Created assembly '%s' with %d parts and %d fasteners" % [assembly.assembly_name, assembly.parts.size(), assembly.fasteners.size()])

	return assembly


## Make a transform relative to a center point
static func _make_relative_transform(world_transform: Transform3D, center_point: Vector3) -> Transform3D:
	"""Convert a world transform to be relative to a center point."""
	var relative_transform = Transform3D()
	relative_transform.basis = world_transform.basis  # Keep rotation as-is
	relative_transform.origin = world_transform.origin - center_point  # Make position relative
	return relative_transform


## Calculate the bounding box of the assembly
func _calculate_bounds() -> void:
	"""Calculate the min/max bounds of all parts in the assembly."""
	if parts.is_empty():
		return

	# Initialize with first part's position
	var first_pos = parts[0].transform.origin
	bounds_min = first_pos
	bounds_max = first_pos

	# Expand bounds to include all parts
	for part in parts:
		var pos = part.transform.origin
		bounds_min.x = min(bounds_min.x, pos.x)
		bounds_min.y = min(bounds_min.y, pos.y)
		bounds_min.z = min(bounds_min.z, pos.z)
		bounds_max.x = max(bounds_max.x, pos.x)
		bounds_max.y = max(bounds_max.y, pos.y)
		bounds_max.z = max(bounds_max.z, pos.z)


## Get the size of the assembly bounding box
func get_bounds_size() -> Vector3:
	"""Get the size of the assembly's bounding box."""
	return bounds_max - bounds_min


## Spawn the assembly as a collection of PhysicalItems in the world
func spawn_assembly(parent: Node3D, spawn_position: Vector3 = Vector3.ZERO, enable_physics: bool = true, enable_selection: bool = true) -> Array[PhysicalItem]:
	"""Instantiate the assembly at a given position, recreating all parts and connections.

	Args:
		parent: The parent node to spawn items under
		spawn_position: World position to spawn at
		enable_physics: If true, enable physics simulation
		enable_selection: If true, enable selection layer (only applies when enable_physics=false)
	"""
	var spawned_items: Array[PhysicalItem] = []

	# Spawn all parts
	for part_data in parts:
		var scene_path = part_data.scene_path
		var scene = load(scene_path) as PackedScene
		if not scene:
			push_error("AssemblyData: Failed to load part scene: %s" % scene_path)
			continue

		var item = scene.instantiate() as PhysicalItem
		if not item:
			push_error("AssemblyData: Failed to instantiate part: %s" % scene_path)
			continue

		parent.add_child(item)

		# Apply transform (relative to spawn position)
		var world_transform = part_data.transform
		world_transform.origin += spawn_position
		item.global_transform = world_transform

		spawned_items.append(item)

	# Wait for items to be in tree and _ready() to complete before setting collision layers
	# This is crucial because PhysicalItem._ready() sets collision_layer=4 by default
	await parent.get_tree().process_frame

	# Wait one more frame to be absolutely sure _ready() completed
	await parent.get_tree().process_frame

	# Now configure collision layers AFTER _ready() has been called
	for item in spawned_items:
		if item is PhysicalItem:
			# Control physics based on parameter
			item.freeze = not enable_physics
			# In workbench mode, configure collision layers based on selection parameter
			if not enable_physics:
				if enable_selection:
					item.collision_layer = 4  # Keep layer 3 (binary: 100) for workbench selection
					print("AssemblyData: Set item '%s' collision_layer to 4 (selectable)" % item.item_name)
				else:
					item.collision_layer = 0  # No selection layer (preview only)
					print("AssemblyData: Set item '%s' collision_layer to 0 (NOT selectable)" % item.item_name)
				item.collision_mask = 0  # Don't collide with anything
			# Verify the setting stuck
			if not enable_physics:
				print("AssemblyData: Verified item '%s' has collision_layer=%d" % [item.item_name, item.collision_layer])

	# Recreate fastener connections
	for fastener_data in fasteners:
		var item_a_index = fastener_data.item_a_index
		var item_b_index = fastener_data.item_b_index
		var fastener_id = fastener_data.fastener_id
		var connection_point = fastener_data.connection_point + spawn_position

		if item_a_index < spawned_items.size() and item_b_index < spawned_items.size():
			var item_a = spawned_items[item_a_index]
			var item_b = spawned_items[item_b_index]

			# Create fastener connection
			item_a.attach_with_fastener(item_b, fastener_id, connection_point, parent)

	print("AssemblyData: Spawned assembly '%s' with %d items" % [assembly_name, spawned_items.size()])
	return spawned_items


## Get a summary string for display
func get_summary() -> String:
	"""Get a display string with assembly info."""
	var summary = "[b]%s[/b]\n" % assembly_name
	if not assembly_description.is_empty():
		summary += "%s\n" % assembly_description
	summary += "\n"
	summary += "Parts: %d\n" % parts.size()
	summary += "Fasteners: %d\n" % fasteners.size()
	summary += "Mass: %.2f kg\n" % total_mass
	summary += "Volume: %.3f m³\n" % total_volume
	summary += "Value: %.2f\n" % assembly_value
	summary += "\nCreated: %s" % creation_date
	return summary


## Save assembly to a resource file
func save_to_file(path: String) -> bool:
	"""Save this assembly to a .tres resource file."""
	var result = ResourceSaver.save(self, path)
	if result == OK:
		print("AssemblyData: Saved assembly to %s" % path)
		return true
	else:
		push_error("AssemblyData: Failed to save assembly to %s (error code: %d)" % [path, result])
		return false


## Load assembly from a resource file
static func load_from_file(path: String) -> AssemblyData:
	"""Load an assembly from a .tres resource file."""
	var assembly = load(path) as AssemblyData
	if assembly:
		print("AssemblyData: Loaded assembly '%s' from %s" % [assembly.assembly_name, path])
		return assembly
	else:
		push_error("AssemblyData: Failed to load assembly from %s" % path)
		return null
