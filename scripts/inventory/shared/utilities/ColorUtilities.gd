# scripts/inventory/shared/utilities/ColorUtilities.gd
class_name ColorUtilities

static var rarity_colors = {"common": Color.WHITE, "uncommon": Color.LIME_GREEN, "rare": Color.CYAN, "epic": Color.MAGENTA, "legendary": Color.GOLD, "artifact": Color.ORANGE_RED}

static var state_colors = {
	"normal": Color.WHITE,
	"highlighted": Color.YELLOW,
	"selected": Color.CYAN,
	"dragging": Color(1.0, 1.0, 1.0, 0.5),
	"drop_valid": Color.LIME_GREEN,
	"drop_invalid": Color.CRIMSON,
	"disabled": Color.GRAY
}

static var border_color = Color(0.3, 0.3, 0.3, 1.0)


# Get color for item type
static func get_type_color(item_type: ItemTypes.Type) -> Color:
	return ItemTypes.get_type_color(item_type)


# Get color for item rarity
static func get_rarity_color(rarity: String) -> Color:
	return rarity_colors.get(rarity.to_lower(), Color.WHITE)


# Get UI state color
static func get_state_color(state: String) -> Color:
	return state_colors.get(state.to_lower(), Color.WHITE)


# Get UI border color
static func get_border_color() -> Color:
	return border_color


# Color manipulation utilities
static func lighten_color(color: Color, factor: float) -> Color:
	return Color(mini(color.r + factor, 1.0), mini(color.g + factor, 1.0), mini(color.b + factor, 1.0), color.a)


static func darken_color(color: Color, factor: float) -> Color:
	return Color(maxi(color.r - factor, 0.0), maxi(color.g - factor, 0.0), maxi(color.b - factor, 0.0), color.a)


static func with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)
