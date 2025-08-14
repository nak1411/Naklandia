# scripts/inventory/shared/constants/ItemTypes.gd
class_name ItemTypes

enum Type { MISCELLANEOUS, WEAPON, ARMOR, CONSUMABLE, RESOURCE, BLUEPRINT, MODULE, SHIP, CONTAINER, AMMUNITION, IMPLANT, SKILL_BOOK }


# Helper methods for type management
static func get_type_name(type: Type) -> String:
	match type:
		Type.WEAPON:
			return "Weapon"
		Type.ARMOR:
			return "Armor"
		Type.CONSUMABLE:
			return "Consumable"
		Type.RESOURCE:
			return "Resource"
		Type.BLUEPRINT:
			return "Blueprint"
		Type.MODULE:
			return "Module"
		Type.SHIP:
			return "Ship"
		Type.CONTAINER:
			return "Container"
		Type.AMMUNITION:
			return "Ammunition"
		Type.IMPLANT:
			return "Implant"
		Type.SKILL_BOOK:
			return "Skill Book"
		_:
			return "Miscellaneous"


static func get_type_color(type: Type) -> Color:
	match type:
		Type.WEAPON:
			return Color.CRIMSON
		Type.ARMOR:
			return Color.STEEL_BLUE
		Type.CONSUMABLE:
			return Color.LIME_GREEN
		Type.RESOURCE:
			return Color.SANDY_BROWN
		Type.BLUEPRINT:
			return Color.CYAN
		Type.MODULE:
			return Color.MAGENTA
		Type.SHIP:
			return Color.GOLD
		Type.CONTAINER:
			return Color.DARK_GRAY
		Type.AMMUNITION:
			return Color.YELLOW
		Type.IMPLANT:
			return Color.PINK
		Type.SKILL_BOOK:
			return Color.LIGHT_BLUE
		_:
			return Color.WHITE
