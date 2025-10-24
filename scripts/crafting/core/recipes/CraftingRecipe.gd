# CraftingRecipe.gd - Defines a crafting recipe with detailed requirements
class_name CraftingRecipe
extends Resource

# Recipe identification
@export var recipe_id: String = ""
@export var recipe_name: String = "Unknown Recipe"
@export var recipe_category: String = "General"
@export var description: String = ""
@export var icon_path: String = ""

# Recipe complexity
@export var complexity_level: int = 1  # 1-10 scale
@export var estimated_time: float = 60.0  # seconds
@export var failure_risk: float = 0.1  # 0.0 to 1.0

# Input requirements (arrays of inner class instances)
var required_materials: Array = []  # Array of RecipeMaterial
var required_tools: Array = []  # Array of RequiredTool
@export var required_station_type: String = "basic_workbench"

# Output specifications
@export var output_item_id: String = ""
@export var output_quantity: int = 1
@export var output_quality_variance: float = 0.2  # Quality can vary ±20%

# Crafting stages
var crafting_stages: Array = []  # Array of CraftingStage

# Unlocking and prerequisites
@export var required_blueprint: String = ""
@export var required_skill_level: int = 1
@export var is_repeatable: bool = true


func _init():
	if recipe_id.is_empty():
		recipe_id = "recipe_" + str(Time.get_unix_time_from_system())


func can_craft(available_materials: Dictionary, available_tools: Array) -> bool:
	"""Check if the recipe can be crafted with available resources"""
	# Check materials
	for req_mat in required_materials:
		var available = available_materials.get(req_mat.material_id, 0)
		if available < req_mat.quantity:
			return false

	# Check tools
	for req_tool in required_tools:
		if not req_tool.tool_id in available_tools:
			return false

	return true


func get_missing_materials(available_materials: Dictionary) -> Array:
	"""Get list of missing or insufficient materials"""
	var missing: Array = []

	for req_mat in required_materials:
		var available = available_materials.get(req_mat.material_id, 0)
		if available < req_mat.quantity:
			var shortage = RecipeMaterial.new()
			shortage.material_id = req_mat.material_id
			shortage.material_name = req_mat.material_name
			shortage.quantity = req_mat.quantity - available
			missing.append(shortage)

	return missing


func get_missing_tools(available_tools: Array) -> Array:
	"""Get list of missing tools"""
	var missing: Array = []

	for req_tool in required_tools:
		if not req_tool.tool_id in available_tools:
			missing.append(req_tool)

	return missing


func calculate_success_chance(player_skill: int, tool_quality: float = 1.0) -> float:
	"""Calculate the chance of successfully completing the recipe"""
	var skill_factor = clamp(float(player_skill) / float(required_skill_level), 0.5, 1.5)
	var base_success = 1.0 - failure_risk
	var modified_success = base_success * skill_factor * tool_quality
	return clamp(modified_success, 0.1, 1.0)


# Inner classes for recipe data
class RecipeMaterial:
	var material_id: String = ""
	var material_name: String = ""
	var quantity: int = 1
	var consumed: bool = true  # If false, tool is returned after crafting


class RequiredTool:
	var tool_id: String = ""
	var tool_name: String = ""
	var tool_category: String = ""
	var optional: bool = false
	var quality_impact: float = 0.1  # How much tool quality affects output


class CraftingStage:
	enum StageType { PREPARATION, ASSEMBLY, REFINEMENT, QUALITY_CHECK, FINALIZATION }

	var stage_id: String = ""
	var stage_name: String = ""
	var description: String = ""
	var duration: float = 20.0  # seconds
	var stage_type: int = StageType.ASSEMBLY
	var required_actions: Array = []  # Array of StageAction
	var success_threshold: float = 0.7  # 0.0 to 1.0
	var can_fail: bool = false


class StageAction:
	enum ActionType { BUTTON_PRESS, SLIDER_ADJUST, SEQUENCE_INPUT, TEMPERATURE_CONTROL, PRESSURE_CONTROL, TIMING_CHALLENGE }

	var action_id: String = ""
	var action_name: String = ""
	var action_type: int = ActionType.BUTTON_PRESS
	var parameter_min: float = 0.0
	var parameter_max: float = 100.0
	var optimal_value: float = 50.0
	var tolerance: float = 10.0  # ± tolerance for optimal
