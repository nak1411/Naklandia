# InventoryItem.gd - Core item class with EVE-like properties
class_name InventoryItem
extends Resource

# Basic item properties
@export var item_id: String = ""
@export var item_name: String = "Unknown Item"
@export var description: String = ""
@export var icon_path: String = ""

# Physical properties (EVE-like)
@export var volume: float = 1.0  # m³
@export var mass: float = 1.0    # kg
@export var quantity: int = 1
@export var max_stack_size: int = 1

# Item type and rarity
@export var item_type: ItemType = ItemType.MISCELLANEOUS
@export var item_rarity: ItemRarity = ItemRarity.COMMON
@export var is_contraband: bool = false

# Value and meta properties
@export var base_value: float = 0.0
@export var can_be_destroyed: bool = true
@export var is_unique: bool = false

# Container properties (if this item is a container)
@export var is_container: bool = false
@export var container_volume: float = 0.0
@export var container_type: ContainerType = ContainerType.NONE

enum ItemType {
	MISCELLANEOUS,
	WEAPON,
	ARMOR,
	CONSUMABLE,
	RESOURCE,
	BLUEPRINT,
	MODULE,
	SHIP,
	CONTAINER,
	AMMUNITION,
	IMPLANT,
	SKILL_BOOK
}

enum ItemRarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY,
	ARTIFACT
}

enum ContainerType {
	NONE,
	GENERAL_CARGO,
	SECURE_CONTAINER,
	HANGAR_DIVISION,
	SHIP_CARGO,
	AMMUNITION_BAY,
	FUEL_BAY
}

# Signals
signal quantity_changed(new_quantity: int)
signal item_modified()

func _init(id: String = "", name: String = "Unknown Item"):
	if not id.is_empty():
		item_id = id
	else:
		item_id = _generate_unique_id()
	
	if not name.is_empty():
		item_name = name

func _generate_unique_id() -> String:
	return "item_" + str(Time.get_unix_time_from_system()) + "_" + str(randi() % 10000)

# Volume and mass calculations
func get_total_volume() -> float:
	return volume * quantity

func get_total_mass() -> float:
	return mass * quantity

func get_total_value() -> float:
	return base_value * quantity

# Stack management
func can_stack_with(other_item: InventoryItem) -> bool:
	if not other_item:
		return false
	
	var can_stack = (item_id == other_item.item_id and 
			quantity < max_stack_size and 
			other_item.quantity < other_item.max_stack_size and
			not is_unique and not other_item.is_unique)
	
	return can_stack

func add_to_stack(amount: int) -> int:
	var space_available = max_stack_size - quantity
	var amount_to_add = min(amount, space_available)
	
	if amount_to_add > 0:
		quantity += amount_to_add
		quantity_changed.emit(quantity)
		item_modified.emit()
	
	return amount - amount_to_add  # Return remaining amount that couldn't be added

func remove_from_stack(amount: int) -> int:
	var amount_to_remove = min(amount, quantity)
	quantity -= amount_to_remove
	
	if quantity <= 0:
		quantity = 0
	
	quantity_changed.emit(quantity)
	item_modified.emit()
	
	return amount_to_remove

func split_stack(split_amount: int) -> InventoryItem:
	if split_amount >= quantity or split_amount <= 0:
		return null
	
	# Create new item with split amount
	var new_item = duplicate()
	new_item.quantity = split_amount
	# Keep the same ID so items can still stack together
	
	# Reduce current stack
	quantity -= split_amount
	quantity_changed.emit(quantity)
	item_modified.emit()
	
	return new_item

# Rarity color coding (EVE-like)
func get_rarity_color() -> Color:
	match item_rarity:
		ItemRarity.COMMON:
			return Color.WHITE
		ItemRarity.UNCOMMON:
			return Color.GREEN
		ItemRarity.RARE:
			return Color.BLUE
		ItemRarity.EPIC:
			return Color.PURPLE
		ItemRarity.LEGENDARY:
			return Color.ORANGE
		ItemRarity.ARTIFACT:
			return Color.RED
		_:
			return Color.WHITE

# Type color coding
func get_type_color() -> Color:
	match item_type:
		ItemType.WEAPON:
			return Color.CRIMSON
		ItemType.ARMOR:
			return Color.STEEL_BLUE
		ItemType.CONSUMABLE:
			return Color.LIME_GREEN
		ItemType.RESOURCE:
			return Color.SANDY_BROWN
		ItemType.BLUEPRINT:
			return Color.CYAN
		ItemType.MODULE:
			return Color.MAGENTA
		ItemType.SHIP:
			return Color.GOLD
		ItemType.CONTAINER:
			return Color.DARK_GRAY
		ItemType.AMMUNITION:
			return Color.YELLOW
		ItemType.IMPLANT:
			return Color.PINK
		ItemType.SKILL_BOOK:
			return Color.LIGHT_BLUE
		_:
			return Color.WHITE

# Icon management
func get_icon_texture() -> Texture2D:
	if icon_path.is_empty():
		return null
	
	return load(icon_path) as Texture2D

func has_icon() -> bool:
	return not icon_path.is_empty()

# Validation
func is_valid_item() -> bool:
	return not item_name.is_empty() and volume > 0 and mass >= 0 and quantity > 0

# Serialization helpers
func to_dict() -> Dictionary:
	return {
		"item_id": item_id,
		"item_name": item_name,
		"description": description,
		"icon_path": icon_path,
		"volume": volume,
		"mass": mass,
		"quantity": quantity,
		"max_stack_size": max_stack_size,
		"item_type": item_type,
		"item_rarity": item_rarity,
		"is_contraband": is_contraband,
		"base_value": base_value,
		"can_be_destroyed": can_be_destroyed,
		"is_unique": is_unique,
		"is_container": is_container,
		"container_volume": container_volume,
		"container_type": container_type
	}

func from_dict(data: Dictionary):
	item_id = data.get("item_id") if data.has("item_id") else ""
	item_name = data.get("item_name") if data.has("item_name") else "Unknown Item"
	description = data.get("description") if data.has("description") else ""
	icon_path = data.get("icon_path") if data.has("icon_path") else ""
	volume = data.get("volume") if data.has("volume") else 1.0
	mass = data.get("mass") if data.has("mass") else 1.0
	quantity = data.get("quantity") if data.has("quantity") else 1
	max_stack_size = data.get("max_stack_size") if data.has("max_stack_size") else 1
	item_type = data.get("item_type") if data.has("item_type") else ItemType.MISCELLANEOUS
	item_rarity = data.get("item_rarity") if data.has("item_rarity") else ItemRarity.COMMON
	is_contraband = data.get("is_contraband") if data.has("is_contraband") else false
	base_value = data.get("base_value") if data.has("base_value") else 0.0
	can_be_destroyed = data.get("can_be_destroyed") if data.has("can_be_destroyed") else true
	is_unique = data.get("is_unique") if data.has("is_unique") else false
	is_container = data.get("is_container") if data.has("is_container") else false
	container_volume = data.get("container_volume") if data.has("container_volume") else 0.0
	container_type = data.get("container_type") if data.has("container_type") else ContainerType.NONE

# Debug
func get_debug_string() -> String:
	return "%s (ID: %s) - Qty: %d, Vol: %.2fm³, Mass: %.2fkg" % [item_name, item_id, quantity, volume, mass]
