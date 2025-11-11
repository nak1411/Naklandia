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
	"""Create an assembly prefab from a list of PhysicalItems - like CAD grouping."""
	if items.is_empty():
		push_error("AssemblyData: Cannot create assembly from empty items array")
		return null

	var assembly = AssemblyData.new()
	assembly.assembly_name = name if not name.is_empty() else "Assembly_%d" % Time.get_ticks_msec()

	# Calculate the bounding box center as the assembly pivot
	var min_pos = Vector3(INF, INF, INF)
	var max_pos = Vector3(-INF, -INF, -INF)

	# Find bounding box of all items
	for item in items:
		if not is_instance_valid(item):
			push_error("AssemblyData: Item is no longer valid (freed)")
			return null

		var pos = item.global_position
		min_pos.x = min(min_pos.x, pos.x)
		min_pos.y = min(min_pos.y, pos.y)
		min_pos.z = min(min_pos.z, pos.z)
		max_pos.x = max(max_pos.x, pos.x)
		max_pos.y = max(max_pos.y, pos.y)
		max_pos.z = max(max_pos.z, pos.z)

	# Use bounding box center as assembly origin
	var assembly_origin = (min_pos + max_pos) / 2.0
	print("AssemblyData: Assembly origin at %s (bbox center)" % assembly_origin)

	# Store each part with its transform relative to assembly origin
	var part_count = 0
	for item in items:
		if not is_instance_valid(item):
			continue

		# Store the item's world transform relative to assembly origin
		# This is SIMPLE: just subtract the origin from position, keep rotation as-is
		var local_position = item.global_position - assembly_origin
		var local_rotation = item.global_rotation  # Keep exact rotation

		print("AssemblyData SAVE: '%s' world_pos=%s world_rot_deg=%s" % [item.item_name, item.global_position, item.global_rotation_degrees])
		print("AssemblyData SAVE: '%s' local_pos=%s local_rot_deg=%s" % [item.item_name, local_position, local_rotation * 180.0 / PI])

		var part_data = {
			"scene_path": item.scene_file_path,
			"item_id": item.item_id,
			"item_name": item.item_name,
			"local_position": local_position,
			"local_rotation": local_rotation,  # Store as euler angles (radians)
			"local_scale": item.scale,
			"mass": item.item_mass,
			"volume": item.item_volume,
		}
		assembly.parts.append(part_data)
		part_count += 1

		# Accumulate totals
		assembly.total_mass += item.item_mass
		assembly.total_volume += item.item_volume

	if part_count == 0:
		push_error("AssemblyData: No valid parts found to save")
		return null

	# Calculate bounds
	assembly._calculate_bounds()

	# Estimate value
	assembly.assembly_value = assembly.total_mass * 10.0

	print("AssemblyData: Created assembly '%s' with %d parts (simplified - no fasteners)" % [assembly.assembly_name, assembly.parts.size()])

	return assembly


## Calculate the bounding box of the assembly
func _calculate_bounds() -> void:
	"""Calculate the min/max bounds of all parts in the assembly."""
	if parts.is_empty():
		return

	# Get first part's position (handle both new and old format)
	var first_pos = Vector3.ZERO
	if parts[0].has("local_position"):
		first_pos = parts[0].local_position
	elif parts[0].has("transform"):
		first_pos = parts[0].transform.origin

	bounds_min = first_pos
	bounds_max = first_pos

	# Expand bounds to include all parts
	for part in parts:
		var pos = Vector3.ZERO
		if part.has("local_position"):
			pos = part.local_position
		elif part.has("transform"):
			pos = part.transform.origin

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
	"""Instantiate the assembly prefab at a given position - simple and clean like CAD.

	Args:
		parent: The parent node to spawn items under
		spawn_position: World position to spawn at (assembly origin goes here)
		enable_physics: If true, enable physics simulation
		enable_selection: If true, enable selection layer (only applies when enable_physics=false)
	"""
	var spawned_items: Array[PhysicalItem] = []

	print("AssemblyData LOAD: Spawning assembly '%s' at world position %s" % [assembly_name, spawn_position])

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

		# SIMPLE: Add the local position to spawn position, apply local rotation
		# Handle both new format (local_position/local_rotation) and old format (transform)
		var local_pos = Vector3.ZERO
		var local_rot = Vector3.ZERO
		var local_scale = Vector3.ONE

		if part_data.has("local_position"):
			# New simplified format
			local_pos = part_data.local_position
			local_rot = part_data.local_rotation
			if part_data.has("local_scale"):
				local_scale = part_data.local_scale
		elif part_data.has("transform"):
			# Old format - convert
			var transform = part_data.transform as Transform3D
			local_pos = transform.origin
			local_rot = transform.basis.get_euler()
			local_scale = transform.basis.get_scale()

		# Apply world transform
		# Position: simple offset from spawn position
		var world_pos = spawn_position + local_pos

		# Rotation: use the exact rotation (no transformation needed)
		var world_rot = local_rot

		print("AssemblyData LOAD: '%s' local_pos=%s local_rot_deg=%s" % [part_data.item_name, local_pos, local_rot * 180.0 / PI])
		print("AssemblyData LOAD: '%s' world_pos=%s world_rot_deg=%s" % [part_data.item_name, world_pos, world_rot * 180.0 / PI])

		# Set transform BEFORE adding to tree
		item.position = world_pos
		item.rotation = world_rot
		item.scale = local_scale
		item.freeze = true  # Freeze immediately

		# Now add to tree
		parent.add_child(item)

		spawned_items.append(item)

	# Wait for items to be in tree and _ready() to complete
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame

	# Configure collision layers
	for item in spawned_items:
		if item is PhysicalItem:
			item.freeze = not enable_physics

			if not enable_physics:
				if enable_selection:
					item.collision_layer = 4  # Selectable in workbench
				else:
					item.collision_layer = 0  # Preview only
				item.collision_mask = 0

	print("AssemblyData: Spawned assembly '%s' with %d items (simplified - no fasteners)" % [assembly_name, spawned_items.size()])
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
