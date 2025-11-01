# ItemDatabase.gd - Master database for all game items
# This should be set as an AutoLoad singleton in Project Settings
extends Node

# Configuration
const ITEM_DATA_PATH = "res://data/items/"
const ENABLE_JSON_LOADING = true  # Set to false to use hardcoded items


# Item definition structure
class ItemDefinition:
	var item_id: String
	var name: String
	var description: String
	var item_type: ItemTypes.Type
	var volume: float
	var mass: float
	var value: float
	var icon_path: String
	var max_stack_size: int
	var model_path: String  # For future 3D model reference
	var custom_properties: Dictionary  # For item-specific data (ammo damage, fuel capacity, etc.)

	func _init(
		id: String,
		n: String,
		desc: String,
		type: ItemTypes.Type,
		vol: float,
		m: float,
		val: float,
		icon: String,
		stack: int = 999999
	):
		item_id = id
		name = n
		description = desc
		item_type = type
		volume = vol
		mass = m
		value = val
		icon_path = icon
		max_stack_size = stack
		model_path = ""
		custom_properties = {}


var items: Dictionary = {}


func _ready():
	_initialize_items()


func _input(event: InputEvent):
	"""Debug input for hot-reloading items"""
	# Press F5 to reload items from JSON (development only)
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		reload_items()
		get_viewport().set_input_as_handled()


func reload_items():
	"""Reload all items from JSON files (useful for hot-reloading during development)"""
	print("ItemDatabase: Reloading items...")
	items.clear()
	_initialize_items()
	_refresh_existing_item_instances()
	_trigger_ui_refresh()
	print("ItemDatabase: Reload complete!")


func _trigger_ui_refresh():
	"""Trigger UI refresh for inventory windows and equipment"""
	print("ItemDatabase: Triggering UI refresh...")

	# Refresh crafting recipes first (they reference items)
	_refresh_crafting_recipes()

	# Refresh inventory windows
	var inventory_integrations = get_tree().get_nodes_in_group("inventory_integration")
	for integration in inventory_integrations:
		if integration.has_method("_refresh_inventory_display"):
			integration._refresh_inventory_display()

	# Refresh equipment windows
	var equipment_windows = get_tree().get_nodes_in_group("equipment_window")
	for eq_window in equipment_windows:
		if eq_window.has_method("refresh_display"):
			eq_window.refresh_display()

	# Refresh crafting windows
	var crafting_windows = get_tree().get_nodes_in_group("crafting_window")
	for craft_window in crafting_windows:
		if craft_window.has_method("refresh_display"):
			craft_window.refresh_display()

	print("  UI refresh triggered")


func _refresh_crafting_recipes():
	"""Reload all crafting recipes from JSON (full hot-reload)"""
	var crafting_managers = get_tree().get_nodes_in_group("crafting_manager")
	for manager in crafting_managers:
		if manager.has_method("reload_recipes"):
			manager.reload_recipes()


func _refresh_existing_item_instances():
	"""Refresh all existing item instances in the game world to match updated definitions"""
	print("ItemDatabase: Refreshing existing item instances...")

	# Find all InventoryItem_Base instances in the scene tree
	var all_items = _find_all_item_instances()
	var refreshed_count = 0

	for item in all_items:
		if refresh_item_instance(item):
			refreshed_count += 1

	print("  Refreshed %d existing item instances" % refreshed_count)


func _find_all_item_instances() -> Array[InventoryItem_Base]:
	"""Find all InventoryItem_Base instances in containers"""
	var found_items: Array[InventoryItem_Base] = []

	# Find inventory manager
	var inventory_managers = get_tree().get_nodes_in_group("inventory_manager")
	if inventory_managers.size() > 0:
		var inv_manager = inventory_managers[0]
		if inv_manager.has_method("get_all_containers"):
			var containers = inv_manager.get_all_containers()
			for container in containers:
				if container and container.has_method("get_items"):
					var container_items = container.get_items()
					for item in container_items:
						if item and item is InventoryItem_Base:
							found_items.append(item)

	# Also check equipment window if it exists
	var equipment_windows = get_tree().get_nodes_in_group("equipment_window")
	for eq_window in equipment_windows:
		if eq_window.has_method("get_all_equipped_items"):
			var equipped_items = eq_window.get_all_equipped_items()
			for item in equipped_items:
				if item and item is InventoryItem_Base:
					found_items.append(item)

	return found_items


func refresh_item_instance(item: InventoryItem_Base) -> bool:
	"""Refresh a single item instance with current definition data"""
	if not item:
		return false

	var item_def = get_item(item.item_id)
	if not item_def:
		push_warning("ItemDatabase: Cannot refresh item %s - definition not found" % item.item_id)
		return false

	# Preserve quantity (don't overwrite)
	var original_quantity = item.quantity

	# Update all properties from definition
	item.item_name = item_def.name
	item.description = item_def.description
	item.item_type = item_def.item_type
	item.volume = item_def.volume
	item.mass = item_def.mass
	item.base_value = item_def.value
	item.icon_path = item_def.icon_path
	item.max_stack_size = item_def.max_stack_size
	item.quantity = original_quantity  # Restore quantity

	# Clear and reapply metadata
	var meta_list = item.get_meta_list()
	for meta_key in meta_list:
		item.remove_meta(meta_key)

	# Reapply custom metadata from definition
	_apply_custom_metadata(item, item_def)

	# Set equipment category if not already set
	if not item.has_meta("equipment_category"):
		_set_equipment_category(item)

	# Set model path
	if not item_def.model_path.is_empty():
		item.set_meta("model_path", item_def.model_path)

	# Set attachment metadata
	_set_attachment_metadata(item)

	print("  Refreshed item: %s -> %s" % [item.item_id, item.item_name])
	return true


func _initialize_items():
	"""Initialize all item definitions"""

	if ENABLE_JSON_LOADING:
		_load_items_from_json()
	else:
		_load_hardcoded_items()


func _load_items_from_json():
	"""Load all item definitions from JSON files"""
	print("ItemDatabase: Loading items from JSON files...")

	var json_files = [
		"tools.json",
		"ammunition.json",
		"resources.json",
		"modules.json",
		"blueprints.json",
		"miscellaneous.json"
	]

	var total_items = 0
	for file_name in json_files:
		var file_path = ITEM_DATA_PATH + file_name
		var items_loaded = _load_json_file(file_path)
		total_items += items_loaded
		if items_loaded > 0:
			print("  Loaded %d items from %s" % [items_loaded, file_name])

	print("ItemDatabase: Loaded %d total items from JSON" % total_items)


func _load_json_file(file_path: String) -> int:
	"""Load items from a single JSON file"""
	print("  Attempting to load: " + file_path)
	if not FileAccess.file_exists(file_path):
		push_warning("ItemDatabase: JSON file not found: " + file_path)
		print("  File does not exist!")
		return 0

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("ItemDatabase: Failed to open JSON file: " + file_path)
		return 0

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_text)

	if parse_result != OK:
		push_error(
			(
				"ItemDatabase: JSON parse error in %s at line %d: %s"
				% [file_path, json.get_error_line(), json.get_error_message()]
			)
		)
		return 0

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ItemDatabase: JSON root must be a dictionary in " + file_path)
		return 0

	var count = 0
	for item_id in data:
		if _create_item_from_json(item_id, data[item_id]):
			count += 1

	return count


func _create_item_from_json(item_id: String, item_data: Dictionary) -> bool:
	"""Create an item definition from JSON data"""
	# Validate required fields
	if not item_data.has("name"):
		push_error("ItemDatabase: Item %s missing 'name' field" % item_id)
		return false

	if not item_data.has("type"):
		push_error("ItemDatabase: Item %s missing 'type' field" % item_id)
		return false

	# Parse item type
	var item_type_string = item_data.get("type", "MISCELLANEOUS")
	var item_type = _parse_item_type(item_type_string)

	# Create item definition with defaults
	var item_def = ItemDefinition.new(
		item_id,
		item_data.get("name", "Unknown Item"),
		item_data.get("description", ""),
		item_type,
		item_data.get("volume", 0.1),
		item_data.get("mass", 0.1),
		item_data.get("value", 0.0),
		item_data.get("icon_path", ""),
		item_data.get("max_stack_size", 999999)
	)

	# Set optional fields
	item_def.model_path = item_data.get("model_path", "")

	# Set custom properties/metadata
	if item_data.has("metadata"):
		var metadata = item_data["metadata"]
		if typeof(metadata) == TYPE_DICTIONARY:
			item_def.custom_properties = metadata.duplicate()

	# Additional custom properties not in metadata
	if item_data.has("custom_properties"):
		var custom_props = item_data["custom_properties"]
		if typeof(custom_props) == TYPE_DICTIONARY:
			for key in custom_props:
				item_def.custom_properties[key] = custom_props[key]

	_register_item(item_def)
	return true


func _parse_item_type(item_type_string: String) -> ItemTypes.Type:
	"""Parse item type from string"""
	match item_type_string.to_upper():
		"TOOL":
			return ItemTypes.Type.TOOL
		"WEAPON":
			return ItemTypes.Type.WEAPON
		"ARMOR":
			return ItemTypes.Type.ARMOR
		"AMMUNITION":
			return ItemTypes.Type.AMMUNITION
		"RESOURCE":
			return ItemTypes.Type.RESOURCE
		"MODULE":
			return ItemTypes.Type.MODULE
		"BLUEPRINT":
			return ItemTypes.Type.BLUEPRINT
		"IMPLANT":
			return ItemTypes.Type.IMPLANT
		"CONSUMABLE":
			return ItemTypes.Type.CONSUMABLE
		"MISCELLANEOUS", _:
			return ItemTypes.Type.MISCELLANEOUS


func _load_hardcoded_items():
	"""Load hardcoded item definitions (legacy/fallback)"""
	print("ItemDatabase: Using hardcoded item definitions...")
	push_warning(
		"ItemDatabase: Hardcoded items are deprecated. Please enable JSON loading or add items to JSON files."
	)

	# Note: Hardcoded items have been removed. All items should be defined in JSON files.
	# If you need fallback items, add them here temporarily.


func _register_item(item_def: ItemDefinition):
	"""Register an item definition in the database"""
	items[item_def.item_id] = item_def


func get_item(item_id: String) -> ItemDefinition:
	"""Get item definition by ID"""
	if items.has(item_id):
		return items[item_id]

	push_warning("ItemDatabase: Item not found: " + item_id)
	return null


func has_item(item_id: String) -> bool:
	"""Check if item exists in database"""
	return items.has(item_id)


func get_all_items() -> Array[ItemDefinition]:
	"""Get all item definitions"""
	var all_items: Array[ItemDefinition] = []
	for item_def in items.values():
		all_items.append(item_def)
	return all_items


func get_items_by_type(item_type: ItemTypes.Type) -> Array[ItemDefinition]:
	"""Get all items of a specific type"""
	var filtered_items: Array[ItemDefinition] = []
	for item_def in items.values():
		if item_def.item_type == item_type:
			filtered_items.append(item_def)
	return filtered_items


func create_item_instance(item_id: String, quantity: int = 1) -> InventoryItem_Base:
	"""Create a new InventoryItem_Base instance from database definition"""
	var item_def = get_item(item_id)
	if not item_def:
		return null

	var item = InventoryItem_Base.new()
	item.item_id = item_def.item_id
	item.item_name = item_def.name
	item.description = item_def.description
	item.item_type = item_def.item_type
	item.volume = item_def.volume
	item.mass = item_def.mass
	item.base_value = item_def.value
	item.icon_path = item_def.icon_path
	item.max_stack_size = item_def.max_stack_size
	item.quantity = quantity

	# Apply custom properties/metadata from item definition
	_apply_custom_metadata(item, item_def)

	# CRITICAL: Set equipment_category metadata (if not already set by JSON)
	if not item.has_meta("equipment_category"):
		_set_equipment_category(item)

	# Set model path if available (from JSON or hardcoded)
	if not item_def.model_path.is_empty():
		item.set_meta("model_path", item_def.model_path)

	# Set item-specific attachment transforms and metadata (legacy support)
	_set_attachment_metadata(item)

	# Debug: Verify metadata was set
	if item.has_meta("model_path"):
		print(
			"ItemDatabase: Created ",
			item.item_id,
			" with model_path: ",
			item.get_meta("model_path")
		)

	return item


func _apply_custom_metadata(item: InventoryItem_Base, item_def: ItemDefinition):
	"""Apply custom metadata from item definition to item instance"""
	for key in item_def.custom_properties:
		var value = item_def.custom_properties[key]
		item.set_meta(key, value)


func _set_equipment_category(item: InventoryItem_Base):
	"""Set equipment_category metadata based on item type"""
	match item.item_type:
		ItemTypes.Type.WEAPON:
			item.set_meta("is_equippable", true)
			item.set_meta("equipment_category", "weapon")
		ItemTypes.Type.TOOL:
			item.set_meta("is_equippable", true)
			item.set_meta("equipment_category", "tool")
		ItemTypes.Type.ARMOR:
			item.set_meta("is_equippable", true)
			# Determine specific armor slot based on item name/properties
			# For now, default to chest, but this should be more specific
			item.set_meta("equipment_category", "chest")
		ItemTypes.Type.AMMUNITION:
			# Ammunition is NOT equippable - it's consumed
			item.set_meta("is_equippable", false)
		ItemTypes.Type.IMPLANT:
			item.set_meta("is_equippable", true)
			item.set_meta("equipment_category", "accessory")
		_:
			# All other types are NOT equippable
			item.set_meta("is_equippable", false)


func _set_attachment_metadata(item: InventoryItem_Base):
	"""Set 3D model attachment metadata for specific items"""
	match item.item_id:
		"tool_wrench":
			# Ensure model path is set
			item.set_meta("model_path", "res://assets/models/equippable/old_wrench.glb")
			item.set_meta("equipment_socket", "hand_tool")
