class_name WorkbenchAssemblyManager
extends RefCounted

## Manages assemblies in the workbench - creating, storing, and spawning assembled models.

# Signals
signal assembly_created(assembly: AssemblyData)
signal assembly_selected(assembly: AssemblyData)
signal assembly_deleted(assembly_id: String)

# Stored assemblies (in-memory for now, could be persisted)
var assemblies: Array[AssemblyData] = []

# Assembly save directory
const ASSEMBLY_SAVE_DIR = "user://assemblies/"


func _init() -> void:
	# Ensure save directory exists
	_ensure_save_directory()
	# Load any saved assemblies
	_load_saved_assemblies()


## Ensure the assembly save directory exists
func _ensure_save_directory() -> void:
	"""Create the assembly save directory if it doesn't exist."""
	var dir = DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("assemblies"):
			dir.make_dir("assemblies")
			print("WorkbenchAssemblyManager: Created assemblies directory")


## Create a new assembly from selected items in the workbench
func create_assembly_from_items(items: Array[PhysicalItem], assembly_name: String = "") -> AssemblyData:
	"""Create a new assembly from a collection of PhysicalItems."""
	if items.is_empty():
		push_warning("WorkbenchAssemblyManager: Cannot create assembly from empty items array")
		return null

	# Generate default name if not provided
	if assembly_name.is_empty():
		assembly_name = "Assembly %d" % (assemblies.size() + 1)

	# Create assembly data
	var assembly = AssemblyData.from_physical_items(items, assembly_name)
	if not assembly:
		push_error("WorkbenchAssemblyManager: Failed to create assembly data")
		return null

	# Add to list
	assemblies.append(assembly)

	# Save to file
	var save_path = ASSEMBLY_SAVE_DIR + assembly.assembly_id + ".tres"
	assembly.save_to_file(save_path)

	# Emit signal
	assembly_created.emit(assembly)

	print("WorkbenchAssemblyManager: Created assembly '%s' with %d parts" % [assembly_name, items.size()])

	return assembly


## Get all assemblies
func get_all_assemblies() -> Array[AssemblyData]:
	"""Get all stored assemblies."""
	return assemblies.duplicate()


## Get assembly by ID
func get_assembly(assembly_id: String) -> AssemblyData:
	"""Get a specific assembly by its ID."""
	for assembly in assemblies:
		if assembly.assembly_id == assembly_id:
			return assembly
	return null


## Delete an assembly
func delete_assembly(assembly_id: String) -> bool:
	"""Delete an assembly by its ID."""
	for i in range(assemblies.size()):
		if assemblies[i].assembly_id == assembly_id:
			var assembly = assemblies[i]
			assemblies.remove_at(i)

			# Delete file
			var file_path = ASSEMBLY_SAVE_DIR + assembly_id + ".tres"
			var dir = DirAccess.open(ASSEMBLY_SAVE_DIR)
			if dir and dir.file_exists(file_path):
				dir.remove(file_path)

			assembly_deleted.emit(assembly_id)
			print("WorkbenchAssemblyManager: Deleted assembly '%s'" % assembly.assembly_name)
			return true

	return false


## Rename an assembly
func rename_assembly(assembly_id: String, new_name: String) -> bool:
	"""Rename an existing assembly."""
	var assembly = get_assembly(assembly_id)
	if not assembly:
		return false

	assembly.assembly_name = new_name

	# Re-save
	var save_path = ASSEMBLY_SAVE_DIR + assembly_id + ".tres"
	assembly.save_to_file(save_path)

	print("WorkbenchAssemblyManager: Renamed assembly to '%s'" % new_name)
	return true


## Load all saved assemblies from disk
func _load_saved_assemblies() -> void:
	"""Load all assembly files from the save directory."""
	var dir = DirAccess.open(ASSEMBLY_SAVE_DIR)
	if not dir:
		print("WorkbenchAssemblyManager: No assemblies directory found")
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var full_path = ASSEMBLY_SAVE_DIR + file_name
			var assembly = AssemblyData.load_from_file(full_path)
			if assembly:
				assemblies.append(assembly)
				print("WorkbenchAssemblyManager: Loaded assembly '%s'" % assembly.assembly_name)

		file_name = dir.get_next()

	dir.list_dir_end()

	print("WorkbenchAssemblyManager: Loaded %d assemblies" % assemblies.size())


## Spawn an assembly into the world as PhysicalItems
func spawn_assembly(assembly_id: String, parent: Node3D, spawn_position: Vector3 = Vector3.ZERO, enable_physics: bool = true) -> Array[PhysicalItem]:
	"""Spawn an assembly at the given position."""
	var assembly = get_assembly(assembly_id)
	if not assembly:
		push_error("WorkbenchAssemblyManager: Assembly not found: %s" % assembly_id)
		return []

	return await assembly.spawn_assembly(parent, spawn_position, enable_physics)


## Convert an assembly into a single InventoryItem
func convert_assembly_to_inventory_item(assembly: AssemblyData) -> InventoryItem_Base:
	"""Convert an assembly into an InventoryItem_Base for adding to inventory."""
	if not assembly:
		return null

	var item = InventoryItem_Base.new()
	item.item_id = "assembly_" + assembly.assembly_id
	item.item_type = ItemTypes.Type.RESOURCE  # Or could be ASSEMBLY type
	item.item_name = assembly.assembly_name
	item.description = assembly.assembly_description if not assembly.assembly_description.is_empty() else "A custom-built assembly"
	item.volume = assembly.total_volume
	item.mass = assembly.total_mass
	item.base_value = assembly.assembly_value
	item.quantity = 1
	item.max_stack_size = 1  # Assemblies don't stack
	item.icon_path = assembly.icon_path

	# Store assembly reference in metadata
	item.set_meta("assembly_id", assembly.assembly_id)
	item.set_meta("is_assembly", true)

	return item


## Spawn an assembly from an inventory item into the world
func spawn_assembly_from_inventory_item(item: InventoryItem_Base, parent: Node3D, spawn_position: Vector3 = Vector3.ZERO, enable_physics: bool = true) -> Array[PhysicalItem]:
	"""Spawn an assembly from an inventory item that has assembly metadata."""
	if not item:
		push_error("WorkbenchAssemblyManager: Invalid item")
		return []

	# Check if this is an assembly item
	if not item.has_meta("is_assembly") or not item.get_meta("is_assembly"):
		push_warning("WorkbenchAssemblyManager: Item is not an assembly")
		return []

	# Get assembly ID
	var assembly_id = item.get_meta("assembly_id", "")
	if assembly_id.is_empty():
		push_error("WorkbenchAssemblyManager: Item has no assembly_id")
		return []

	# Spawn the assembly with physics enabled (since it's being placed in the world)
	return await spawn_assembly(assembly_id, parent, spawn_position, enable_physics)


## Export assembly stats for debugging
func get_assembly_stats() -> Dictionary:
	"""Get statistics about all assemblies."""
	var total_parts = 0
	var total_fasteners = 0
	var total_mass = 0.0

	for assembly in assemblies:
		total_parts += assembly.parts.size()
		total_fasteners += assembly.fasteners.size()
		total_mass += assembly.total_mass

	return {
		"total_assemblies": assemblies.size(),
		"total_parts": total_parts,
		"total_fasteners": total_fasteners,
		"total_mass": total_mass,
	}
