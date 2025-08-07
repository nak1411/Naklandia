# scripts/inventory/shared/constants/ContainerTypes.gd
class_name ContainerTypes

enum Type {
	NONE,
	GENERAL_CARGO,
	SECURE_CONTAINER,
	HANGAR_DIVISION,
	SHIP_CARGO,
	AMMUNITION_BAY,
	FUEL_BAY,
	PLAYER_INVENTORY,
	LOOT_CONTAINER,
	TRASH_CONTAINER
}

static func get_type_name(type: Type) -> String:
	match type:
		Type.GENERAL_CARGO: return "General Cargo"
		Type.SECURE_CONTAINER: return "Secure Container"
		Type.HANGAR_DIVISION: return "Hangar Division"
		Type.SHIP_CARGO: return "Ship Cargo"
		Type.AMMUNITION_BAY: return "Ammunition Bay"
		Type.FUEL_BAY: return "Fuel Bay"
		Type.PLAYER_INVENTORY: return "Player Inventory"
		Type.LOOT_CONTAINER: return "Loot Container"
		Type.TRASH_CONTAINER: return "Trash Container"
		_: return "Unknown"

static func get_max_volume(type: Type) -> float:
	match type:
		Type.PLAYER_INVENTORY: return 100.0
		Type.GENERAL_CARGO: return 1000.0
		Type.SECURE_CONTAINER: return 50.0
		Type.SHIP_CARGO: return 5000.0
		Type.AMMUNITION_BAY: return 200.0
		Type.FUEL_BAY: return 500.0
		_: return 100.0