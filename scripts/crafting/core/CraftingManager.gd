# CraftingManager.gd - Manages crafting recipes and processes
class_name CraftingManager
extends Node

signal recipe_discovered(recipe: CraftingRecipe)
signal crafting_started(process: CraftingProcess)
signal crafting_completed(process: CraftingProcess)
signal crafting_failed(process: CraftingProcess)

# Managers
var inventory_manager: InventoryManager
var player_container: InventoryContainer_Base

# Recipe data
var all_recipes: Array[CraftingRecipe] = []
var discovered_recipes: Array[String] = []  # Recipe IDs
var active_processes: Array[CraftingProcess] = []

# Crafting stations
var active_station_type: String = "basic_workbench"
var available_tools: Array[String] = []


func _ready():
	add_to_group("crafting_manager")
	_load_recipes()


func set_inventory_manager(manager: InventoryManager):
	"""Set the inventory manager reference"""
	inventory_manager = manager
	if inventory_manager:
		player_container = inventory_manager.get_player_inventory()


func set_active_station(station_type: String):
	"""Set the currently active crafting station"""
	active_station_type = station_type
	_update_available_tools()


func _update_available_tools():
	"""Update available tools based on station and inventory"""
	available_tools.clear()

	# Get tools from inventory
	if player_container:
		for item in player_container.items:
			if item.item_type == ItemTypes.Type.TOOL:
				available_tools.append(item.item_id)

	# Add station-specific tools
	match active_station_type:
		"basic_workbench":
			available_tools.append("basic_hammer")
			available_tools.append("basic_screwdriver")
		"advanced_fabricator":
			available_tools.append("precision_laser")
			available_tools.append("molecular_assembler")
			available_tools.append("quality_scanner")
		"chemical_station":
			available_tools.append("heating_element")
			available_tools.append("cooling_system")
			available_tools.append("pressure_chamber")


func _load_recipes():
	"""Load crafting recipes - in production this would load from files"""
	# Create example recipes
	_create_example_recipes()


func _create_example_recipes():
	"""Create example crafting recipes for demonstration"""

	# Simple component recipe
	var simple_component = CraftingRecipe.new()
	simple_component.recipe_id = "recipe_basic_component"
	simple_component.recipe_name = "Basic Component"
	simple_component.recipe_category = "Components"
	simple_component.description = "A simple mechanical component crafted from metal."
	simple_component.complexity_level = 2
	simple_component.estimated_time = 30.0
	simple_component.failure_risk = 0.05
	simple_component.output_item_id = "basic_component"
	simple_component.output_quantity = 1

	# Materials
	var metal_mat = CraftingRecipe.RecipeMaterial.new()
	metal_mat.material_id = "metal_plate"
	metal_mat.material_name = "Metal Plate"
	metal_mat.quantity = 2
	simple_component.required_materials.append(metal_mat)

	var screw_mat = CraftingRecipe.RecipeMaterial.new()
	screw_mat.material_id = "screw"
	screw_mat.material_name = "Screw"
	screw_mat.quantity = 4
	simple_component.required_materials.append(screw_mat)

	# Tools
	var hammer_tool = CraftingRecipe.RequiredTool.new()
	hammer_tool.tool_id = "basic_hammer"
	hammer_tool.tool_name = "Hammer"
	hammer_tool.quality_impact = 0.1
	simple_component.required_tools.append(hammer_tool)

	# Crafting stages
	var prep_stage = CraftingRecipe.CraftingStage.new()
	prep_stage.stage_id = "prep"
	prep_stage.stage_name = "Preparation"
	prep_stage.description = "Prepare materials and inspect quality"
	prep_stage.duration = 10.0
	prep_stage.stage_type = CraftingRecipe.CraftingStage.StageType.PREPARATION
	simple_component.crafting_stages.append(prep_stage)

	var assembly_stage = CraftingRecipe.CraftingStage.new()
	assembly_stage.stage_id = "assembly"
	assembly_stage.stage_name = "Assembly"
	assembly_stage.description = "Assemble the component parts"
	assembly_stage.duration = 15.0
	assembly_stage.stage_type = CraftingRecipe.CraftingStage.StageType.ASSEMBLY
	assembly_stage.success_threshold = 0.6

	# Add assembly action
	var assemble_action = CraftingRecipe.StageAction.new()
	assemble_action.action_id = "assemble"
	assemble_action.action_name = "Apply Pressure"
	assemble_action.action_type = CraftingRecipe.StageAction.ActionType.SLIDER_ADJUST
	assemble_action.parameter_min = 0.0
	assemble_action.parameter_max = 100.0
	assemble_action.optimal_value = 65.0
	assemble_action.tolerance = 10.0
	assembly_stage.required_actions.append(assemble_action)

	simple_component.crafting_stages.append(assembly_stage)

	var finish_stage = CraftingRecipe.CraftingStage.new()
	finish_stage.stage_id = "finish"
	finish_stage.stage_name = "Finishing"
	finish_stage.description = "Polish and inspect the completed component"
	finish_stage.duration = 5.0
	finish_stage.stage_type = CraftingRecipe.CraftingStage.StageType.FINALIZATION
	simple_component.crafting_stages.append(finish_stage)

	all_recipes.append(simple_component)

	# Advanced electronic circuit recipe
	var circuit = CraftingRecipe.new()
	circuit.recipe_id = "recipe_circuit_board"
	circuit.recipe_name = "Circuit Board"
	circuit.recipe_category = "Electronics"
	circuit.description = "An advanced electronic circuit board requiring precision assembly."
	circuit.complexity_level = 6
	circuit.estimated_time = 90.0
	circuit.failure_risk = 0.25
	circuit.output_item_id = "circuit_board"
	circuit.output_quantity = 1

	# Materials
	var pcb_mat = CraftingRecipe.RecipeMaterial.new()
	pcb_mat.material_id = "pcb_blank"
	pcb_mat.material_name = "PCB Blank"
	pcb_mat.quantity = 1
	circuit.required_materials.append(pcb_mat)

	var component_mat = CraftingRecipe.RecipeMaterial.new()
	component_mat.material_id = "electronic_component"
	component_mat.material_name = "Electronic Components"
	component_mat.quantity = 10
	circuit.required_materials.append(component_mat)

	var solder_mat = CraftingRecipe.RecipeMaterial.new()
	solder_mat.material_id = "solder"
	solder_mat.material_name = "Solder"
	solder_mat.quantity = 5
	circuit.required_materials.append(solder_mat)

	# Tools
	var precision_tool = CraftingRecipe.RequiredTool.new()
	precision_tool.tool_id = "precision_laser"
	precision_tool.tool_name = "Precision Laser"
	precision_tool.quality_impact = 0.3
	circuit.required_tools.append(precision_tool)

	var scanner_tool = CraftingRecipe.RequiredTool.new()
	scanner_tool.tool_id = "quality_scanner"
	scanner_tool.tool_name = "Quality Scanner"
	scanner_tool.optional = true
	scanner_tool.quality_impact = 0.2
	circuit.required_tools.append(scanner_tool)

	# Stages
	var circuit_prep = CraftingRecipe.CraftingStage.new()
	circuit_prep.stage_id = "prep"
	circuit_prep.stage_name = "PCB Preparation"
	circuit_prep.description = "Clean and prepare the PCB surface"
	circuit_prep.duration = 15.0
	circuit_prep.stage_type = CraftingRecipe.CraftingStage.StageType.PREPARATION

	var temp_action = CraftingRecipe.StageAction.new()
	temp_action.action_id = "preheat"
	temp_action.action_name = "Preheat PCB"
	temp_action.action_type = CraftingRecipe.StageAction.ActionType.TEMPERATURE_CONTROL
	temp_action.parameter_min = 50.0
	temp_action.parameter_max = 150.0
	temp_action.optimal_value = 85.0
	temp_action.tolerance = 10.0
	circuit_prep.required_actions.append(temp_action)

	circuit.crafting_stages.append(circuit_prep)

	var circuit_assembly = CraftingRecipe.CraftingStage.new()
	circuit_assembly.stage_id = "assembly"
	circuit_assembly.stage_name = "Component Assembly"
	circuit_assembly.description = "Precisely place and solder electronic components"
	circuit_assembly.duration = 45.0
	circuit_assembly.stage_type = CraftingRecipe.CraftingStage.StageType.ASSEMBLY
	circuit_assembly.success_threshold = 0.7
	circuit_assembly.can_fail = true

	var precision_action = CraftingRecipe.StageAction.new()
	precision_action.action_id = "placement"
	precision_action.action_name = "Component Placement Precision"
	precision_action.action_type = CraftingRecipe.StageAction.ActionType.SLIDER_ADJUST
	precision_action.parameter_min = 0.0
	precision_action.parameter_max = 100.0
	precision_action.optimal_value = 90.0
	precision_action.tolerance = 5.0
	circuit_assembly.required_actions.append(precision_action)

	var solder_temp = CraftingRecipe.StageAction.new()
	solder_temp.action_id = "solder_temp"
	solder_temp.action_name = "Solder Temperature"
	solder_temp.action_type = CraftingRecipe.StageAction.ActionType.TEMPERATURE_CONTROL
	solder_temp.parameter_min = 180.0
	solder_temp.parameter_max = 350.0
	solder_temp.optimal_value = 260.0
	solder_temp.tolerance = 15.0
	circuit_assembly.required_actions.append(solder_temp)

	circuit.crafting_stages.append(circuit_assembly)

	var circuit_test = CraftingRecipe.CraftingStage.new()
	circuit_test.stage_id = "test"
	circuit_test.stage_name = "Quality Testing"
	circuit_test.description = "Test circuit functionality and quality"
	circuit_test.duration = 20.0
	circuit_test.stage_type = CraftingRecipe.CraftingStage.StageType.QUALITY_CHECK
	circuit_test.can_fail = true

	var timing_test = CraftingRecipe.StageAction.new()
	timing_test.action_id = "test_timing"
	timing_test.action_name = "Power-On Timing"
	timing_test.action_type = CraftingRecipe.StageAction.ActionType.TIMING_CHALLENGE
	timing_test.parameter_min = 0.0
	timing_test.parameter_max = 100.0
	timing_test.optimal_value = 50.0
	timing_test.tolerance = 15.0
	circuit_test.required_actions.append(timing_test)

	circuit.crafting_stages.append(circuit_test)

	var circuit_finish = CraftingRecipe.CraftingStage.new()
	circuit_finish.stage_id = "finish"
	circuit_finish.stage_name = "Final Inspection"
	circuit_finish.description = "Inspect and package the circuit board"
	circuit_finish.duration = 10.0
	circuit_finish.stage_type = CraftingRecipe.CraftingStage.StageType.FINALIZATION
	circuit.crafting_stages.append(circuit_finish)

	all_recipes.append(circuit)

	# Chemical compound recipe
	var compound = CraftingRecipe.new()
	compound.recipe_id = "recipe_fuel_compound"
	compound.recipe_name = "Advanced Fuel Compound"
	compound.recipe_category = "Chemistry"
	compound.description = "A volatile fuel compound requiring precise temperature and pressure control."
	compound.complexity_level = 8
	compound.estimated_time = 120.0
	compound.failure_risk = 0.35
	compound.output_item_id = "fuel_compound"
	compound.output_quantity = 10

	# Materials
	var base_chem = CraftingRecipe.RecipeMaterial.new()
	base_chem.material_id = "base_chemical"
	base_chem.material_name = "Base Chemical"
	base_chem.quantity = 50
	compound.required_materials.append(base_chem)

	var catalyst = CraftingRecipe.RecipeMaterial.new()
	catalyst.material_id = "catalyst"
	catalyst.material_name = "Catalyst"
	catalyst.quantity = 5
	compound.required_materials.append(catalyst)

	var stabilizer = CraftingRecipe.RecipeMaterial.new()
	stabilizer.material_id = "stabilizer"
	stabilizer.material_name = "Stabilizer"
	stabilizer.quantity = 10
	compound.required_materials.append(stabilizer)

	# Tools
	var heating = CraftingRecipe.RequiredTool.new()
	heating.tool_id = "heating_element"
	heating.tool_name = "Heating Element"
	heating.quality_impact = 0.2
	compound.required_tools.append(heating)

	var pressure = CraftingRecipe.RequiredTool.new()
	pressure.tool_id = "pressure_chamber"
	pressure.tool_name = "Pressure Chamber"
	pressure.quality_impact = 0.25
	compound.required_tools.append(pressure)

	# Stages
	var mix_stage = CraftingRecipe.CraftingStage.new()
	mix_stage.stage_id = "mixing"
	mix_stage.stage_name = "Chemical Mixing"
	mix_stage.description = "Mix base chemicals in precise ratios"
	mix_stage.duration = 30.0
	mix_stage.stage_type = CraftingRecipe.CraftingStage.StageType.PREPARATION

	var mix_ratio = CraftingRecipe.StageAction.new()
	mix_ratio.action_id = "mix_ratio"
	mix_ratio.action_name = "Mixing Ratio"
	mix_ratio.action_type = CraftingRecipe.StageAction.ActionType.SLIDER_ADJUST
	mix_ratio.parameter_min = 0.0
	mix_ratio.parameter_max = 100.0
	mix_ratio.optimal_value = 75.0
	mix_ratio.tolerance = 8.0
	mix_stage.required_actions.append(mix_ratio)

	compound.crafting_stages.append(mix_stage)

	var reaction_stage = CraftingRecipe.CraftingStage.new()
	reaction_stage.stage_id = "reaction"
	reaction_stage.stage_name = "Chemical Reaction"
	reaction_stage.description = "Heat and pressurize the mixture to initiate reaction"
	reaction_stage.duration = 60.0
	reaction_stage.stage_type = CraftingRecipe.CraftingStage.StageType.ASSEMBLY
	reaction_stage.success_threshold = 0.75
	reaction_stage.can_fail = true

	var heat_control = CraftingRecipe.StageAction.new()
	heat_control.action_id = "heat"
	heat_control.action_name = "Reaction Temperature"
	heat_control.action_type = CraftingRecipe.StageAction.ActionType.TEMPERATURE_CONTROL
	heat_control.parameter_min = 100.0
	heat_control.parameter_max = 500.0
	heat_control.optimal_value = 320.0
	heat_control.tolerance = 25.0
	reaction_stage.required_actions.append(heat_control)

	var pressure_control = CraftingRecipe.StageAction.new()
	pressure_control.action_id = "pressure"
	pressure_control.action_name = "Reaction Pressure"
	pressure_control.action_type = CraftingRecipe.StageAction.ActionType.PRESSURE_CONTROL
	pressure_control.parameter_min = 1.0
	pressure_control.parameter_max = 10.0
	pressure_control.optimal_value = 6.5
	pressure_control.tolerance = 0.8
	reaction_stage.required_actions.append(pressure_control)

	compound.crafting_stages.append(reaction_stage)

	var refine_stage = CraftingRecipe.CraftingStage.new()
	refine_stage.stage_id = "refinement"
	refine_stage.stage_name = "Compound Refinement"
	refine_stage.description = "Cool and stabilize the fuel compound"
	refine_stage.duration = 20.0
	refine_stage.stage_type = CraftingRecipe.CraftingStage.StageType.REFINEMENT

	var cool_control = CraftingRecipe.StageAction.new()
	cool_control.action_id = "cooling"
	cool_control.action_name = "Cooling Rate"
	cool_control.action_type = CraftingRecipe.StageAction.ActionType.TEMPERATURE_CONTROL
	cool_control.parameter_min = 20.0
	cool_control.parameter_max = 200.0
	cool_control.optimal_value = 45.0
	cool_control.tolerance = 12.0
	refine_stage.required_actions.append(cool_control)

	compound.crafting_stages.append(refine_stage)

	var stabilize_stage = CraftingRecipe.CraftingStage.new()
	stabilize_stage.stage_id = "stabilization"
	stabilize_stage.stage_name = "Final Stabilization"
	stabilize_stage.description = "Add stabilizer and finalize the compound"
	stabilize_stage.duration = 10.0
	stabilize_stage.stage_type = CraftingRecipe.CraftingStage.StageType.FINALIZATION
	compound.crafting_stages.append(stabilize_stage)

	all_recipes.append(compound)

	# Discover all recipes by default for demo
	for recipe in all_recipes:
		discovered_recipes.append(recipe.recipe_id)


func get_available_recipes() -> Array[CraftingRecipe]:
	"""Get all discovered recipes that can be crafted at current station"""
	var available: Array[CraftingRecipe] = []

	for recipe in all_recipes:
		if recipe.recipe_id in discovered_recipes:
			# Check if station supports this recipe
			if _station_supports_recipe(recipe):
				available.append(recipe)

	return available


func _station_supports_recipe(recipe: CraftingRecipe) -> bool:
	"""Check if current station can craft this recipe"""
	# For now, advanced_fabricator can do everything, others are limited
	match active_station_type:
		"advanced_fabricator":
			return true
		"basic_workbench":
			return recipe.complexity_level <= 5
		"chemical_station":
			return recipe.recipe_category == "Chemistry"
		_:
			return false


func can_craft_recipe(recipe: CraftingRecipe) -> bool:
	"""Check if recipe can be crafted with current resources"""
	if not player_container:
		return false

	# Check materials
	for req_mat in recipe.required_materials:
		if not check_material_availability(req_mat.material_id, req_mat.quantity):
			return false

	# Check required tools
	for req_tool in recipe.required_tools:
		if not req_tool.optional and not check_tool_availability(req_tool.tool_id):
			return false

	return true


func check_material_availability(material_id: String, required_quantity: int) -> bool:
	"""Check if enough material is available"""
	if not player_container:
		return false

	var available = 0
	for item in player_container.items:
		if item.item_id == material_id:
			available += item.quantity

	return available >= required_quantity


func check_tool_availability(tool_id: String) -> bool:
	"""Check if tool is available"""
	return tool_id in available_tools


func start_crafting(recipe: CraftingRecipe) -> CraftingProcess:
	"""Start a new crafting process"""
	if not can_craft_recipe(recipe):
		return null

	# Consume materials
	if not _consume_materials(recipe):
		return null

	# Create process
	var process = CraftingProcess.new(recipe)
	process.start_process()

	active_processes.append(process)
	crafting_started.emit(process)

	return process


func _consume_materials(recipe: CraftingRecipe) -> bool:
	"""Consume materials for crafting"""
	if not player_container or not inventory_manager:
		return false

	# Track consumed items
	var to_remove: Array[Dictionary] = []

	for req_mat in recipe.required_materials:
		if not req_mat.consumed:
			continue

		var remaining = req_mat.quantity

		for item in player_container.items:
			if item.item_id == req_mat.material_id and remaining > 0:
				var consume_amount = min(item.quantity, remaining)
				to_remove.append({"item": item, "amount": consume_amount})
				remaining -= consume_amount

		if remaining > 0:
			return false  # Not enough materials

	# Actually remove items
	for removal in to_remove:
		var item = removal["item"]
		var amount = removal["amount"]

		if amount >= item.quantity:
			player_container.remove_item(item)
		else:
			item.quantity -= amount
			item.quantity_changed.emit(item.quantity)

	return true


func collect_crafting_output(process: CraftingProcess):
	"""Collect the output from a completed crafting process"""
	if not process.success or not inventory_manager or not player_container:
		return

	# Create output items and add to inventory
	for output_data in process.output_items:
		var item = InventoryItem_Base.new()
		item.item_id = output_data.get("item_id", "unknown")
		item.item_name = output_data.get("item_id", "Unknown Item").capitalize()
		item.quantity = output_data.get("quantity", 1)

		# Adjust item properties based on quality
		var quality = output_data.get("quality", 1.0)
		if quality > 1.0:
			item.item_name += " (High Quality)"
			item.base_value *= quality

		# Try to add to inventory
		if not inventory_manager.add_item_to_container(item, player_container.container_id):
			# Drop on ground if inventory full
			print("Inventory full! Item dropped.")

	# Remove from active processes
	active_processes.erase(process)
	crafting_completed.emit(process)


func discover_recipe(recipe_id: String):
	"""Discover a new recipe"""
	if not recipe_id in discovered_recipes:
		discovered_recipes.append(recipe_id)

		var recipe = _get_recipe_by_id(recipe_id)
		if recipe:
			recipe_discovered.emit(recipe)


func _get_recipe_by_id(recipe_id: String) -> CraftingRecipe:
	"""Get recipe by ID"""
	for recipe in all_recipes:
		if recipe.recipe_id == recipe_id:
			return recipe
	return null


func add_recipe(recipe: CraftingRecipe):
	"""Add a new recipe to the system"""
	if not recipe in all_recipes:
		all_recipes.append(recipe)


func get_recipe_by_id(recipe_id: String) -> CraftingRecipe:
	"""Public method to get recipe by ID"""
	return _get_recipe_by_id(recipe_id)


func get_all_recipes() -> Array[CraftingRecipe]:
	"""Get all recipes (discovered or not)"""
	return all_recipes


func is_recipe_discovered(recipe_id: String) -> bool:
	"""Check if recipe is discovered"""
	return recipe_id in discovered_recipes
