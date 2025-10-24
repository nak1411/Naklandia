# CraftingConstants.gd - Constants and enums for crafting system
# Place in: scripts/crafting/shared/constants/CraftingConstants.gd
class_name CraftingConstants
extends RefCounted

# Station Types
enum StationType { BASIC_WORKBENCH, ADVANCED_FABRICATOR, CHEMICAL_STATION, ELECTRONICS_LAB, FORGE, ASSEMBLY_LINE }

# Station Type Names
const STATION_TYPE_NAMES = {
	StationType.BASIC_WORKBENCH: "basic_workbench",
	StationType.ADVANCED_FABRICATOR: "advanced_fabricator",
	StationType.CHEMICAL_STATION: "chemical_station",
	StationType.ELECTRONICS_LAB: "electronics_lab",
	StationType.FORGE: "forge",
	StationType.ASSEMBLY_LINE: "assembly_line"
}

# Station Display Names
const STATION_DISPLAY_NAMES = {
	StationType.BASIC_WORKBENCH: "Basic Workbench",
	StationType.ADVANCED_FABRICATOR: "Advanced Fabricator",
	StationType.CHEMICAL_STATION: "Chemical Laboratory",
	StationType.ELECTRONICS_LAB: "Electronics Laboratory",
	StationType.FORGE: "Forge",
	StationType.ASSEMBLY_LINE: "Assembly Line"
}

# Recipe Categories
enum RecipeCategory { COMPONENTS, ELECTRONICS, CHEMISTRY, WEAPONS, ARMOR, TOOLS, CONSUMABLES, SHIP_PARTS, MODULES, MISC }

const CATEGORY_NAMES = {
	RecipeCategory.COMPONENTS: "Components",
	RecipeCategory.ELECTRONICS: "Electronics",
	RecipeCategory.CHEMISTRY: "Chemistry",
	RecipeCategory.WEAPONS: "Weapons",
	RecipeCategory.ARMOR: "Armor",
	RecipeCategory.TOOLS: "Tools",
	RecipeCategory.CONSUMABLES: "Consumables",
	RecipeCategory.SHIP_PARTS: "Ship Parts",
	RecipeCategory.MODULES: "Modules",
	RecipeCategory.MISC: "Miscellaneous"
}

# Crafting Stage Types
enum StageType { PREPARATION, ASSEMBLY, REFINEMENT, QUALITY_CHECK, FINALIZATION }

# Action Types for Interactive Crafting
enum ActionType { BUTTON_PRESS, SLIDER_ADJUST, SEQUENCE_INPUT, TEMPERATURE_CONTROL, PRESSURE_CONTROL, TIMING_CHALLENGE }

# Quality Grades
enum QualityGrade { FAILED, POOR, ACCEPTABLE, GOOD, HIGH, EXCELLENT, PERFECT }  # < 0.5  # 0.5 - 0.7  # 0.7 - 0.9  # 0.9 - 1.1  # 1.1 - 1.3  # 1.3 - 1.5  # 1.5 - 2.0

# Quality Thresholds
const QUALITY_THRESHOLDS = {
	QualityGrade.FAILED: 0.0, QualityGrade.POOR: 0.5, QualityGrade.ACCEPTABLE: 0.7, QualityGrade.GOOD: 0.9, QualityGrade.HIGH: 1.1, QualityGrade.EXCELLENT: 1.3, QualityGrade.PERFECT: 1.5
}

# Quality Colors
const QUALITY_COLORS = {
	QualityGrade.FAILED: Color.DARK_RED,
	QualityGrade.POOR: Color.ORANGE_RED,
	QualityGrade.ACCEPTABLE: Color.YELLOW,
	QualityGrade.GOOD: Color.WHITE,
	QualityGrade.HIGH: Color.GREEN,
	QualityGrade.EXCELLENT: Color.CYAN,
	QualityGrade.PERFECT: Color.GOLD
}

# Quality Names
const QUALITY_NAMES = {
	QualityGrade.FAILED: "Failed",
	QualityGrade.POOR: "Poor",
	QualityGrade.ACCEPTABLE: "Acceptable",
	QualityGrade.GOOD: "Good",
	QualityGrade.HIGH: "High Quality",
	QualityGrade.EXCELLENT: "Excellent",
	QualityGrade.PERFECT: "Masterwork"
}

# Complexity Colors
const COMPLEXITY_COLORS = {1: Color.GREEN, 2: Color.GREEN, 3: Color.YELLOW, 4: Color.YELLOW, 5: Color.YELLOW, 6: Color.ORANGE, 7: Color.ORANGE, 8: Color.ORANGE, 9: Color.RED, 10: Color.RED}

# Tool Categories
enum ToolCategory { HAND_TOOL, PRECISION_TOOL, POWER_TOOL, MEASURING_TOOL, CHEMICAL_EQUIPMENT, ELECTRONICS_EQUIPMENT, FABRICATION_EQUIPMENT }

# Tool Quality Tiers
enum ToolQuality { BASIC, STANDARD, ADVANCED, PROFESSIONAL, INDUSTRIAL }

const TOOL_QUALITY_MODIFIERS = {ToolQuality.BASIC: 0.8, ToolQuality.STANDARD: 1.0, ToolQuality.ADVANCED: 1.15, ToolQuality.PROFESSIONAL: 1.3, ToolQuality.INDUSTRIAL: 1.5}

# Default crafting parameters
const DEFAULT_CRAFTING_TICK_RATE = 0.1  # Update 10 times per second
const DEFAULT_INTERACTION_COOLDOWN = 0.5
const DEFAULT_AUTO_COLLECT_DELAY = 2.0

# UI Constants
const MIN_WINDOW_SIZE = Vector2(1000, 600)
const DEFAULT_WINDOW_SIZE = Vector2(1200, 800)
const MAX_WINDOW_SIZE = Vector2(1600, 1000)

# Progress bar colors
const PROGRESS_BAR_COLOR = Color(0.2, 0.6, 0.8)
const QUALITY_BAR_LOW_COLOR = Color.ORANGE_RED
const QUALITY_BAR_MID_COLOR = Color.YELLOW
const QUALITY_BAR_HIGH_COLOR = Color.GREEN
const QUALITY_BAR_PERFECT_COLOR = Color.GOLD

# Helper Functions


static func get_quality_grade(quality: float) -> QualityGrade:
	"""Get quality grade from quality value"""
	if quality < QUALITY_THRESHOLDS[QualityGrade.POOR]:
		return QualityGrade.FAILED
	elif quality < QUALITY_THRESHOLDS[QualityGrade.ACCEPTABLE]:
		return QualityGrade.POOR
	elif quality < QUALITY_THRESHOLDS[QualityGrade.GOOD]:
		return QualityGrade.ACCEPTABLE
	elif quality < QUALITY_THRESHOLDS[QualityGrade.HIGH]:
		return QualityGrade.GOOD
	elif quality < QUALITY_THRESHOLDS[QualityGrade.EXCELLENT]:
		return QualityGrade.HIGH
	elif quality < QUALITY_THRESHOLDS[QualityGrade.PERFECT]:
		return QualityGrade.EXCELLENT
	else:
		return QualityGrade.PERFECT


static func get_quality_color(quality: float) -> Color:
	"""Get color for quality value"""
	var grade = get_quality_grade(quality)
	return QUALITY_COLORS[grade]


static func get_quality_name(quality: float) -> String:
	"""Get name for quality value"""
	var grade = get_quality_grade(quality)
	return QUALITY_NAMES[grade]


static func get_complexity_color(complexity: int) -> Color:
	"""Get color for complexity level"""
	complexity = clampi(complexity, 1, 10)
	return COMPLEXITY_COLORS.get(complexity, Color.WHITE)


static func get_station_type_string(station_type: StationType) -> String:
	"""Get string ID for station type"""
	return STATION_TYPE_NAMES.get(station_type, "basic_workbench")


static func get_station_display_name(station_type: StationType) -> String:
	"""Get display name for station type"""
	return STATION_DISPLAY_NAMES.get(station_type, "Unknown Station")


static func get_category_name(category: RecipeCategory) -> String:
	"""Get display name for recipe category"""
	return CATEGORY_NAMES.get(category, "Miscellaneous")


static func format_time(seconds: float) -> String:
	"""Format time in seconds to readable string"""
	if seconds < 60:
		return "%ds" % int(seconds)
	else:
		var minutes = int(seconds / 60)
		var remaining_seconds = int(seconds) % 60
		return "%dm %ds" % [minutes, remaining_seconds]


static func format_quality_percent(quality: float) -> String:
	"""Format quality as percentage"""
	return "%.1f%%" % (quality * 100.0)
