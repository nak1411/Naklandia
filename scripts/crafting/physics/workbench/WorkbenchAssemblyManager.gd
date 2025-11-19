class_name WorkbenchAssemblyManager
extends RefCounted

## Manages assemblies in the workbench - creating, storing, and spawning assembled models.

# Signals
signal assembly_created(assembly: AssemblyData)
signal assembly_selected(assembly: AssemblyData)
signal assembly_deleted(assembly_id: String)

# Stored assemblies (in-memory for now, could be persisted)
var assemblies: Array[AssemblyData] = []

# Icon reference counting - tracks how many times each assembly icon is in use
# Key: assembly_id, Value: reference count (inventory items + spawned assemblies)
var icon_reference_counts: Dictionary = {}  # {assembly_id: int}

# Assembly save directory
const ASSEMBLY_SAVE_DIR = "user://assemblies/"
const THUMBNAIL_SAVE_DIR = "res://assets/textures/ui/icons/assemblies/"
const THUMBNAIL_SIZE = Vector2i(120, 120)  # Thumbnail resolution to match inventory icons
const ICON_REF_COUNT_FILE = "user://assemblies/icon_reference_counts.json"


func _init() -> void:
	# Ensure save directory exists
	_ensure_save_directory()
	# Load any saved assemblies
	_load_saved_assemblies()
	# Load icon reference counts
	_load_icon_reference_counts()


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
	"""Delete an assembly by its ID.
	Icon files are automatically deleted if not referenced by any inventory items or world objects."""
	for i in range(assemblies.size()):
		if assemblies[i].assembly_id == assembly_id:
			var assembly = assemblies[i]
			assemblies.remove_at(i)

			# Delete assembly .tres file
			var file_path = ASSEMBLY_SAVE_DIR + assembly_id + ".tres"
			var dir = DirAccess.open(ASSEMBLY_SAVE_DIR)
			if dir and dir.file_exists(file_path):
				dir.remove(file_path)
				print("WorkbenchAssemblyManager: Deleted assembly file: %s" % file_path)

			# Check if icon is still in use (referenced by inventory items or world objects)
			var ref_count = get_icon_reference_count(assembly_id)
			if ref_count <= 0:
				# Icon not in use - safe to delete
				_delete_assembly_icon(assembly_id)
				print("WorkbenchAssemblyManager: Icon not in use (ref count: %d), deleted icon files" % ref_count)
			else:
				# Icon still in use - keep it
				print("WorkbenchAssemblyManager: Icon still in use (ref count: %d), keeping icon files" % ref_count)

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


## Load icon reference counts from disk
func _load_icon_reference_counts() -> void:
	"""Load the icon reference counts from JSON file."""
	if not FileAccess.file_exists(ICON_REF_COUNT_FILE):
		print("WorkbenchAssemblyManager: No icon reference count file found, starting fresh")
		return

	var file = FileAccess.open(ICON_REF_COUNT_FILE, FileAccess.READ)
	if not file:
		push_warning("WorkbenchAssemblyManager: Failed to open icon reference count file")
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		push_error("WorkbenchAssemblyManager: Failed to parse icon reference counts JSON")
		return

	icon_reference_counts = json.data
	print("WorkbenchAssemblyManager: Loaded icon reference counts for %d assemblies" % icon_reference_counts.size())


## Save icon reference counts to disk
func _save_icon_reference_counts() -> void:
	"""Save the icon reference counts to JSON file."""
	var file = FileAccess.open(ICON_REF_COUNT_FILE, FileAccess.WRITE)
	if not file:
		push_error("WorkbenchAssemblyManager: Failed to save icon reference counts")
		return

	var json_string = JSON.stringify(icon_reference_counts, "\t")
	file.store_string(json_string)
	file.close()
	print("WorkbenchAssemblyManager: Saved icon reference counts")


## Increment icon reference count
func increment_icon_reference(assembly_id: String) -> void:
	"""Increment the reference count for an assembly icon."""
	if assembly_id not in icon_reference_counts:
		icon_reference_counts[assembly_id] = 0

	icon_reference_counts[assembly_id] += 1
	print("WorkbenchAssemblyManager: Icon ref count for %s: %d" % [assembly_id, icon_reference_counts[assembly_id]])
	_save_icon_reference_counts()


## Decrement icon reference count
func decrement_icon_reference(assembly_id: String) -> void:
	"""Decrement the reference count for an assembly icon."""
	if assembly_id not in icon_reference_counts:
		push_warning("WorkbenchAssemblyManager: Attempted to decrement non-existent reference count for %s" % assembly_id)
		return

	icon_reference_counts[assembly_id] -= 1
	print("WorkbenchAssemblyManager: Icon ref count for %s: %d" % [assembly_id, icon_reference_counts[assembly_id]])

	# Check if reference count reached zero
	if icon_reference_counts[assembly_id] <= 0:
		icon_reference_counts.erase(assembly_id)

		# Check if the assembly itself still exists
		var assembly_exists = get_assembly(assembly_id) != null

		# If assembly doesn't exist and ref count is 0, the icon is orphaned - delete it
		if not assembly_exists:
			_delete_assembly_icon(assembly_id)
			print("WorkbenchAssemblyManager: Assembly deleted and ref count = 0, deleted orphaned icon for %s" % assembly_id)

	_save_icon_reference_counts()


## Get icon reference count
func get_icon_reference_count(assembly_id: String) -> int:
	"""Get the current reference count for an assembly icon."""
	return icon_reference_counts.get(assembly_id, 0)


## Spawn an assembly into the world as PhysicalItems
func spawn_assembly(assembly_id: String, parent: Node3D, spawn_position: Vector3 = Vector3.ZERO, enable_physics: bool = true, enable_selection: bool = true) -> Array[PhysicalItem]:
	"""Spawn an assembly at the given position.

	Args:
		assembly_id: ID of the assembly to spawn
		parent: Parent node to spawn under
		spawn_position: World position to spawn at
		enable_physics: If true, enable physics simulation
		enable_selection: If true, enable selection layer (only applies when enable_physics=false)
	"""
	var assembly = get_assembly(assembly_id)
	if not assembly:
		push_error("WorkbenchAssemblyManager: Assembly not found: %s" % assembly_id)
		return []

	return await assembly.spawn_assembly(parent, spawn_position, enable_physics, enable_selection)


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

	# Embed the icon texture directly in the item (instead of using a file path)
	# This way the icon persists even if the assembly is deleted
	if assembly.preview_texture != null:
		# Assembly already has loaded texture - use it directly
		item.icon_texture = assembly.preview_texture
		print("WorkbenchAssemblyManager: Using existing preview texture for inventory item")
	elif not assembly.icon_path.is_empty():
		# Load the texture from path and embed it
		var texture = load_thumbnail(assembly.icon_path)
		if texture:
			item.icon_texture = texture
			print("WorkbenchAssemblyManager: Loaded and embedded texture from %s" % assembly.icon_path)
		else:
			print("WorkbenchAssemblyManager: WARNING - Failed to load texture for assembly")
	else:
		print("WorkbenchAssemblyManager: WARNING - Assembly has no icon")

	# Store assembly reference in metadata
	item.set_meta("assembly_id", assembly.assembly_id)
	item.set_meta("is_assembly", true)

	# Increment icon reference count (inventory item now uses this icon)
	increment_icon_reference(assembly.assembly_id)

	return item


## Notify that an assembly item was removed from inventory
func on_assembly_item_removed(item: InventoryItem_Base) -> void:
	"""Call this when an assembly inventory item is destroyed/consumed.
	Decrements the icon reference count."""
	if not item:
		return

	# Check if this is an assembly item
	if not item.has_meta("is_assembly") or not item.get_meta("is_assembly"):
		return

	# Get assembly ID
	var assembly_id = item.get_meta("assembly_id", "")
	if assembly_id.is_empty():
		return

	# Decrement icon reference count
	decrement_icon_reference(assembly_id)
	print("WorkbenchAssemblyManager: Assembly item removed, decremented icon reference for %s" % assembly_id)


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
	var total_mass = 0.0

	for assembly in assemblies:
		total_parts += assembly.parts.size()
		total_mass += assembly.total_mass

	return {
		"total_assemblies": assemblies.size(),
		"total_parts": total_parts,
		"total_mass": total_mass,
	}


## Generate a thumbnail from a captured viewport image
func generate_thumbnail_from_image(image: Image, assembly_id: String) -> String:
	"""Generate and save a thumbnail image for an assembly.
	Returns the path to the saved thumbnail, or empty string on failure."""
	if not image:
		push_error("WorkbenchAssemblyManager: No image provided for thumbnail generation")
		return ""

	# Resize image to thumbnail size
	var thumbnail = image.duplicate()
	thumbnail.resize(THUMBNAIL_SIZE.x, THUMBNAIL_SIZE.y, Image.INTERPOLATE_LANCZOS)

	# Save as PNG to res:// path (convert to absolute path for saving)
	var thumbnail_filename = assembly_id + ".png"
	var thumbnail_path = THUMBNAIL_SAVE_DIR + thumbnail_filename
	var absolute_path = ProjectSettings.globalize_path(thumbnail_path)

	var error = thumbnail.save_png(absolute_path)
	if error != OK:
		push_error("WorkbenchAssemblyManager: Failed to save thumbnail to %s (error: %d)" % [absolute_path, error])
		return ""

	print("WorkbenchAssemblyManager: Saved thumbnail to %s" % thumbnail_path)
	return thumbnail_path


## Load a thumbnail as a Texture2D
func load_thumbnail(icon_path: String) -> Texture2D:
	"""Load a thumbnail image as a Texture2D."""
	if icon_path.is_empty():
		return null

	# Convert any path to absolute for loading
	var absolute_path = ProjectSettings.globalize_path(icon_path)

	# Check if file exists
	if not FileAccess.file_exists(absolute_path):
		push_warning("WorkbenchAssemblyManager: Thumbnail file not found: %s" % absolute_path)
		return null

	# Load image directly from file (works for both res:// and user:// paths at runtime)
	var image = Image.load_from_file(absolute_path)
	if not image:
		push_error("WorkbenchAssemblyManager: Failed to load thumbnail image: %s" % absolute_path)
		return null

	return ImageTexture.create_from_image(image)


## Delete assembly icon/thumbnail files
func _delete_assembly_icon(assembly_id: String) -> void:
	"""Delete the thumbnail PNG and import files for an assembly."""
	var thumbnail_filename = assembly_id + ".png"
	var thumbnail_path = THUMBNAIL_SAVE_DIR + thumbnail_filename
	var import_path = thumbnail_path + ".import"

	# Convert to absolute paths
	var absolute_thumbnail_path = ProjectSettings.globalize_path(thumbnail_path)
	var absolute_import_path = ProjectSettings.globalize_path(import_path)

	# Delete the .png file
	if FileAccess.file_exists(absolute_thumbnail_path):
		var dir = DirAccess.open(ProjectSettings.globalize_path(THUMBNAIL_SAVE_DIR))
		if dir:
			var error = dir.remove(absolute_thumbnail_path)
			if error == OK:
				print("WorkbenchAssemblyManager: Deleted thumbnail file: %s" % thumbnail_path)
			else:
				push_warning("WorkbenchAssemblyManager: Failed to delete thumbnail file: %s (error: %d)" % [thumbnail_path, error])
	else:
		print("WorkbenchAssemblyManager: Thumbnail file not found (skipping): %s" % thumbnail_path)

	# Delete the .png.import file
	if FileAccess.file_exists(absolute_import_path):
		var dir = DirAccess.open(ProjectSettings.globalize_path(THUMBNAIL_SAVE_DIR))
		if dir:
			var error = dir.remove(absolute_import_path)
			if error == OK:
				print("WorkbenchAssemblyManager: Deleted import file: %s" % import_path)
			else:
				push_warning("WorkbenchAssemblyManager: Failed to delete import file: %s (error: %d)" % [import_path, error])
	else:
		print("WorkbenchAssemblyManager: Import file not found (skipping): %s" % import_path)


## Clean up orphaned assembly icon files
func cleanup_orphaned_icons() -> int:
	"""Delete icon files that don't have a corresponding assembly.
	Returns the number of orphaned files deleted."""
	var deleted_count = 0

	# Get list of valid assembly IDs
	var valid_ids: Array[String] = []
	for assembly in assemblies:
		valid_ids.append(assembly.assembly_id)

	# Scan the thumbnail directory
	var absolute_dir_path = ProjectSettings.globalize_path(THUMBNAIL_SAVE_DIR)
	var dir = DirAccess.open(absolute_dir_path)
	if not dir:
		push_warning("WorkbenchAssemblyManager: Cannot access thumbnail directory: %s" % THUMBNAIL_SAVE_DIR)
		return 0

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.begins_with("assembly_") and file_name.ends_with(".png"):
			# Extract assembly ID from filename (e.g., "assembly_12345_67890.png" -> "assembly_12345_67890")
			var assembly_id = file_name.trim_suffix(".png")

			# Check if this assembly ID exists
			if assembly_id not in valid_ids:
				# Orphaned icon - delete it and its .import file
				var full_path = absolute_dir_path + "/" + file_name
				var import_path = full_path + ".import"

				# Delete .png file
				var error = dir.remove(full_path)
				if error == OK:
					print("WorkbenchAssemblyManager: Deleted orphaned icon: %s" % file_name)
					deleted_count += 1
				else:
					push_warning("WorkbenchAssemblyManager: Failed to delete orphaned icon: %s (error: %d)" % [file_name, error])

				# Delete .import file if it exists
				if FileAccess.file_exists(import_path):
					error = dir.remove(import_path)
					if error == OK:
						print("WorkbenchAssemblyManager: Deleted orphaned import: %s.import" % file_name)
					else:
						push_warning("WorkbenchAssemblyManager: Failed to delete orphaned import: %s.import (error: %d)" % [file_name, error])

		file_name = dir.get_next()

	dir.list_dir_end()

	if deleted_count > 0:
		print("WorkbenchAssemblyManager: Cleaned up %d orphaned icon file(s)" % deleted_count)

	return deleted_count
