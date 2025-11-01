# ItemDatabase.gd - Master database for all game items
# This should be set as an AutoLoad singleton in Project Settings
extends Node


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


func _initialize_items():
	"""Initialize all item definitions"""

	# TOOLS
	var wrench_def = ItemDefinition.new(
		"tool_wrench",
		"Wrench",
		"Durable hand tool used for assembly, maintenance, and machine calibration.",
		ItemTypes.Type.TOOL,
		0.05,
		0.1,
		50.0,
		"res://assets/textures/ui/icons/wrench_slot.png"
	)
	wrench_def.model_path = "res://assets/models/equippable/old_wrench.glb"
	_register_item(wrench_def)

	# AMMUNITION
	_register_item(
		ItemDefinition.new(
			"ammo_hybrid_charges",
			"Hybrid Charges",
			"Standard ammunition for hybrid weapon systems.",
			ItemTypes.Type.AMMUNITION,
			0.025,
			0.01,
			1000.0,
			"res://assets/textures/ui/icons/ammo.png"
		)
	)

	# RESOURCES
	_register_item(
		ItemDefinition.new(
			"resource_noxite",
			"Noxite",
			"A liquid that can be used as a fuel source.",
			ItemTypes.Type.RESOURCE,
			0.125,
			0.1,
			10.0,
			"res://assets/textures/ui/icons/resource.png"
		)
	)
	_register_item(
		(
			ItemDefinition
			. new(
				"resource_iron_ore",
				"Iron Ore",
				"Unrefined metallic mineral used in industrial production. Smelted to produce iron, the base metal for machinery, structures, and tools.",
				ItemTypes.Type.RESOURCE,
				0.125,
				0.1,
				10.0,
				"res://assets/textures/ui/icons/iron_ore_slot.png"
			)
		)
	)
	_register_item(
		(
			ItemDefinition
			. new(
				"resource_copper_ore",
				"Copper Ore",
				"Unrefined mineral containing traces of copper. Processed through smelting to produce copper ingots for electrical and mechanical applications.",
				ItemTypes.Type.RESOURCE,
				0.125,
				0.1,
				10.0,
				"res://assets/textures/ui/icons/copper_ore_slot.png"
			)
		)
	)
	_register_item(
		(
			ItemDefinition
			. new(
				"resource_iron_ingot",
				"Iron Ingot",
				"Refined from raw iron ore. A durable, versatile metal used in construction, machinery, and component fabrication.",
				ItemTypes.Type.RESOURCE,
				0.125,
				0.1,
				10.0,
				"res://assets/textures/ui/icons/iron_ingot_slot.png"
			)
		)
	)
	_register_item(
		(
			ItemDefinition
			. new(
				"resource_steel_round_bar",
				"Steel Round Bar",
				"Alloyed and forged from iron and carbon into cylindrical form. Used in high-strength frameworks, shafts, hardware, and assemblies.",
				ItemTypes.Type.RESOURCE,
				0.125,
				0.1,
				10.0,
				"res://assets/textures/ui/icons/steel_round_bar_slot.png"
			)
		)
	)
	_register_item(
		(
			ItemDefinition
			. new(
				"resource_copper_ingot",
				"Copper Ingot",
				"Refined from copper ore. A highly conductive metal used in wiring, electronics, and precision components.",
				ItemTypes.Type.RESOURCE,
				0.125,
				0.1,
				10.0,
				"res://assets/textures/ui/icons/copper_ingot_slot.png"
			)
		)
	)
	_register_item(
		(
			ItemDefinition
			. new(
				"resource_resinwood_log",
				"Resinwood Log",
				"A tough, fibrous log streaked with pale blue resin veins. Light yet strong, it’s prized for building and crafting durable structures.",
				ItemTypes.Type.RESOURCE,
				0.125,
				0.1,
				10.0,
				"res://assets/textures/ui/icons/resinwood_log_slot.png"
			)
		)
	)

	# MODULES
	_register_item(
		ItemDefinition.new(
			"module_gauss_turret",
			"Gauss Turret",
			"Turret firing a high velocity solid charge.",
			ItemTypes.Type.MODULE,
			3.62,
			0.125,
			50000.0,
			"res://assets/textures/ui/icons/module.png"
		)
	)

	# BLUEPRINTS
	_register_item(
		ItemDefinition.new(
			"blueprint_hybrid_charges",
			"Hybrid Charge Blueprint",
			"Blueprint for manufacturing Hybrid Charges.",
			ItemTypes.Type.BLUEPRINT,
			0.015,
			0.01,
			100000.0,
			"res://assets/textures/ui/icons/blueprint.png"
		)
	)

	# CRAFTED ITEMS
	_register_item(
		ItemDefinition.new(
			"basic_component",
			"Basic Component",
			"A simple component made from raw materials.",
			ItemTypes.Type.MISCELLANEOUS,
			0.05,
			0.1,
			50.0,
			"res://assets/textures/ui/icons/resource.png"
		)
	)

	_register_item(
		ItemDefinition.new(
			"repair_kit",
			"Repair Kit",
			"Emergency repair kit for quick fixes.",
			ItemTypes.Type.MISCELLANEOUS,
			0.15,
			0.5,
			500.0,
			"res://assets/textures/ui/icons/resource.png"
		)
	)


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

	# CRITICAL: Set equipment_category metadata
	_set_equipment_category(item)

	# Set model path if available
	if not item_def.model_path.is_empty():
		item.set_meta("model_path", item_def.model_path)

	# Set item-specific attachment transforms and metadata
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
