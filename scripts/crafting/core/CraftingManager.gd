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

	# TEST RECIPE - Hybrid Charges from Noxite
	var hybrid_ammo = CraftingRecipe.new()
	hybrid_ammo.recipe_id = "recipe_hybrid_charges"
	hybrid_ammo.recipe_name = "Hybrid Charges"
	hybrid_ammo.recipe_category = "Ammunition"
	hybrid_ammo.description = "Manufacture hybrid charges using Noxite as a propellant base."
	hybrid_ammo.complexity_level = 1
	hybrid_ammo.estimated_time = 20.0
	hybrid_ammo.failure_risk = 0.05
	hybrid_ammo.output_item_id = "ammo_hybrid_charges"
	hybrid_ammo.output_quantity = 100

	# Materials - Using existing game items
	var noxite_mat = CraftingRecipe.RecipeMaterial.new()
	noxite_mat.material_id = "resource_noxite"
	noxite_mat.material_name = "Noxite"
	noxite_mat.quantity = 1
	hybrid_ammo.required_materials.append(noxite_mat)

	# Tools - Using basic workbench tools
	var basic_tool = CraftingRecipe.RequiredTool.new()
	basic_tool.tool_id = "basic_hammer"
	basic_tool.tool_name = "Basic Hammer"
	basic_tool.quality_impact = 0.05
	hybrid_ammo.required_tools.append(basic_tool)

	# Crafting stages - Keep it simple for testing
	var prep_stage = CraftingRecipe.CraftingStage.new()
	prep_stage.stage_id = "prep"
	prep_stage.stage_name = "Preparation"
	prep_stage.description = "Prepare Noxite for processing into ammunition"
	prep_stage.duration = 10.0
	prep_stage.stage_type = CraftingRecipe.CraftingStage.StageType.PREPARATION
	hybrid_ammo.crafting_stages.append(prep_stage)

	var assembly_stage = CraftingRecipe.CraftingStage.new()
	assembly_stage.stage_id = "assembly"
	assembly_stage.stage_name = "Assembly"
	assembly_stage.description = "Form charges and fill with propellant"
	assembly_stage.duration = 10.0
	assembly_stage.stage_type = CraftingRecipe.CraftingStage.StageType.ASSEMBLY
	assembly_stage.success_threshold = 0.5

	# Add simple assembly action for testing
	var assembly_action = CraftingRecipe.StageAction.new()
	assembly_action.action_id = "filling"
	assembly_action.action_name = "Propellant Fill Level"
	assembly_action.action_type = CraftingRecipe.StageAction.ActionType.SLIDER_ADJUST
	assembly_action.parameter_min = 0.0
	assembly_action.parameter_max = 100.0
	assembly_action.optimal_value = 75.0
	assembly_action.tolerance = 15.0
	assembly_stage.required_actions.append(assembly_action)

	hybrid_ammo.crafting_stages.append(assembly_stage)

	all_recipes.append(hybrid_ammo)

	# Simple component recipe
	var simple_component = CraftingRecipe.new()
	simple_component.recipe_id = "recipe_basic_component"
	simple_component.recipe_name = "Basic Component"
	simple_component.recipe_category = "Components"
	simple_component.description = "A simple mechanical component crafted from metal."
	simple_component.complexity_level = 1
	simple_component.estimated_time = 30.0
	simple_component.failure_risk = 0.1
	simple_component.output_item_id = "component_basic"
	simple_component.output_quantity = 1

	var metal_mat = CraftingRecipe.RecipeMaterial.new()
	metal_mat.material_id = "material_metal"
	metal_mat.material_name = "Metal Ingot"
	metal_mat.quantity = 2
	simple_component.required_materials.append(metal_mat)

	var hammer = CraftingRecipe.RequiredTool.new()
	hammer.tool_id = "basic_hammer"
	hammer.tool_name = "Basic Hammer"
	hammer.quality_impact = 0.1
	simple_component.required_tools.append(hammer)

	var comp_prep = CraftingRecipe.CraftingStage.new()
	comp_prep.stage_id = "prep"
	comp_prep.stage_name = "Material Preparation"
	comp_prep.description = "Prepare and measure the metal"
	comp_prep.duration = 15.0
	comp_prep.stage_type = CraftingRecipe.CraftingStage.StageType.PREPARATION
	simple_component.crafting_stages.append(comp_prep)

	var comp_forge = CraftingRecipe.CraftingStage.new()
	comp_forge.stage_id = "forge"
	comp_forge.stage_name = "Forging"
	comp_forge.description = "Shape the metal component"
	comp_forge.duration = 25.0
	comp_forge.stage_type = CraftingRecipe.CraftingStage.StageType.ASSEMBLY
	simple_component.crafting_stages.append(comp_forge)

	all_recipes.append(simple_component)

	# Advanced circuit recipe with multiple complex stages
	var circuit = CraftingRecipe.new()
	circuit.recipe_id = "recipe_circuit_board"
	circuit.recipe_name = "Advanced Circuit Board"
	circuit.recipe_category = "Electronics"
	circuit.description = "A complex circuit board requiring precision assembly and quality testing."
	circuit.complexity_level = 3
	circuit.estimated_time = 120.0
	circuit.failure_risk = 0.25
	circuit.output_item_id = "component_circuit_advanced"
	circuit.output_quantity = 1

	var silicon_mat = CraftingRecipe.RecipeMaterial.new()
	silicon_mat.material_id = "material_silicon"
	silicon_mat.material_name = "Silicon Wafer"
	silicon_mat.quantity = 1
	circuit.required_materials.append(silicon_mat)

	var conductor_mat = CraftingRecipe.RecipeMaterial.new()
	conductor_mat.material_id = "material_conductor"
	conductor_mat.material_name = "Conductive Wire"
	conductor_mat.quantity = 5
	circuit.required_materials.append(conductor_mat)

	var precision_tool = CraftingRecipe.RequiredTool.new()
	precision_tool.tool_id = "precision_laser"
	precision_tool.tool_name = "Precision Laser"
	precision_tool.quality_impact = 0.2
	circuit.required_tools.append(precision_tool)

	var circuit_prep = CraftingRecipe.CraftingStage.new()
	circuit_prep.stage_id = "prep"
	circuit_prep.stage_name = "Component Layout"
	circuit_prep.description = "Arrange and prepare components on the circuit board"
	circuit_prep.duration = 30.0
	circuit_prep.stage_type = CraftingRecipe.CraftingStage.StageType.PREPARATION
	circuit.crafting_stages.append(circuit_prep)

	var circuit_assembly = CraftingRecipe.CraftingStage.new()
	circuit_assembly.stage_id = "assembly"
	circuit_assembly.stage_name = "Precision Assembly"
	circuit_assembly.description = "Solder components with precise temperature control"
	circuit_assembly.duration = 45.0
	circuit_assembly.stage_type = CraftingRecipe.CraftingStage.StageType.ASSEMBLY
	circuit_assembly.success_threshold = 0.7

	var solder_temp = CraftingRecipe.StageAction.new()
	solder_temp.action_id = "soldering_temp"
	solder_temp.action_name = "Soldering Temperature"
	solder_temp.action_type = CraftingRecipe.StageAction.ActionType.SLIDER_ADJUST
	solder_temp.parameter_min = 0.0
	solder_temp.parameter_max = 100.0
	solder_temp.optimal_value = 65.0
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
	compound.complexity_level = 4
	compound.estimated_time = 180.0
	compound.failure_risk = 0.4
	compound.output_item_id = "fuel_advanced"
	compound.output_quantity = 10

	var chem_a = CraftingRecipe.RecipeMaterial.new()
	chem_a.material_id = "chemical_catalyst"
	chem_a.material_name = "Chemical Catalyst"
	chem_a.quantity = 2
	compound.required_materials.append(chem_a)

	var chem_b = CraftingRecipe.RecipeMaterial.new()
	chem_b.material_id = "chemical_base"
	chem_b.material_name = "Chemical Base"
	chem_b.quantity = 5
	compound.required_materials.append(chem_b)

	var heat_tool = CraftingRecipe.RequiredTool.new()
	heat_tool.tool_id = "heating_element"
	heat_tool.tool_name = "Heating Element"
	heat_tool.quality_impact = 0.15
	compound.required_tools.append(heat_tool)

	var pressure_tool = CraftingRecipe.RequiredTool.new()
	pressure_tool.tool_id = "pressure_chamber"
	pressure_tool.tool_name = "Pressure Chamber"
	pressure_tool.quality_impact = 0.15
	compound.required_tools.append(pressure_tool)

	var chem_prep = CraftingRecipe.CraftingStage.new()
	chem_prep.stage_id = "prep"
	chem_prep.stage_name = "Chemical Preparation"
	chem_prep.description = "Measure and prepare chemical components"
	chem_prep.duration = 30.0
	chem_prep.stage_type = CraftingRecipe.CraftingStage.StageType.PREPARATION
	compound.crafting_stages.append(chem_prep)

	var chem_reaction = CraftingRecipe.CraftingStage.new()
	chem_reaction.stage_id = "reaction"
	chem_reaction.stage_name = "Chemical Reaction"
	chem_reaction.description = "Carefully control temperature and pressure during the reaction"
	chem_reaction.duration = 90.0
	chem_reaction.stage_type = CraftingRecipe.CraftingStage.StageType.ASSEMBLY
	chem_reaction.success_threshold = 0.8
	chem_reaction.can_fail = true

	var temp_control = CraftingRecipe.StageAction.new()
	temp_control.action_id = "temperature"
	temp_control.action_name = "Temperature Control"
	temp_control.action_type = CraftingRecipe.StageAction.ActionType.SLIDER_ADJUST
	temp_control.parameter_min = 0.0
	temp_control.parameter_max = 100.0
	temp_control.optimal_value = 72.0
	temp_control.tolerance = 10.0
	chem_reaction.required_actions.append(temp_control)

	var pressure_control = CraftingRecipe.StageAction.new()
	pressure_control.action_id = "pressure"
	pressure_control.action_name = "Pressure Regulation"
	pressure_control.action_type = CraftingRecipe.StageAction.ActionType.SLIDER_ADJUST
	pressure_control.parameter_min = 0.0
	pressure_control.parameter_max = 100.0
	pressure_control.optimal_value = 60.0
	pressure_control.tolerance = 12.0
	chem_reaction.required_actions.append(pressure_control)

	compound.crafting_stages.append(chem_reaction)

	var chem_stabilize = CraftingRecipe.CraftingStage.new()
	chem_stabilize.stage_id = "stabilize"
	chem_stabilize.stage_name = "Stabilization"
	chem_stabilize.description = "Cool and stabilize the compound"
	chem_stabilize.duration = 40.0
	chem_stabilize.stage_type = CraftingRecipe.CraftingStage.StageType.QUALITY_CHECK
	compound.crafting_stages.append(chem_stabilize)

	var chem_package = CraftingRecipe.CraftingStage.new()
	chem_package.stage_id = "package"
	chem_package.stage_name = "Safe Packaging"
	chem_package.description = "Package the volatile compound safely"
	chem_package.duration = 20.0
	chem_package.stage_type = CraftingRecipe.CraftingStage.StageType.FINALIZATION
	compound.crafting_stages.append(chem_package)

	all_recipes.append(compound)

	# Discover all recipes by default for demo
	for recipe in all_recipes:
		discovered_recipes.append(recipe.recipe_id)


func get_all_recipes() -> Array[CraftingRecipe]:
	"""Get all available recipes"""
	return all_recipes


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


func get_recipes_by_category(category: String) -> Array[CraftingRecipe]:
	"""Get recipes filtered by category"""
	var filtered: Array[CraftingRecipe] = []
	for recipe in all_recipes:
		if recipe.recipe_category == category:
			filtered.append(recipe)
	return filtered


func get_craftable_recipes() -> Array[CraftingRecipe]:
	"""Get recipes that can currently be crafted"""
	if not player_container:
		return []

	var available_materials: Dictionary = {}
	for item in player_container.items:
		available_materials[item.item_id] = item.quantity

	var craftable: Array[CraftingRecipe] = []
	for recipe in all_recipes:
		if recipe.can_craft(available_materials, available_tools):
			craftable.append(recipe)

	return craftable


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
	"""Begin crafting a recipe"""
	if not recipe:
		return null

	# Consume materials
	if not _consume_materials(recipe):
		push_warning("Failed to consume materials")
		return null

	# Create process
	var process = CraftingProcess.new(recipe)
	process.used_tools = available_tools.duplicate()
	active_processes.append(process)

	# Start the process
	process.start_process()
	crafting_started.emit(process)

	return process


func _consume_materials(recipe: CraftingRecipe) -> bool:
	"""Consume materials required for crafting"""
	if not player_container or not inventory_manager:
		return false

	# Track items to remove
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
			return false

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


func update_process(process: CraftingProcess, delta: float):
	"""Update a crafting process"""
	if not process or not process.is_active or process.is_paused:
		return

	var recipe = process.recipe
	if not recipe or process.current_stage_index >= recipe.crafting_stages.size():
		return

	var current_stage = recipe.crafting_stages[process.current_stage_index]

	# CRITICAL FIX: Check if stage has required actions that need player input
	var has_required_actions = current_stage.required_actions and not current_stage.required_actions.is_empty()

	# Only progress stages WITHOUT required actions
	# Stages with required actions are completely paused until player interacts
	if not has_required_actions:
		# Update progress
		process.stage_progress += delta / current_stage.duration
		process.progress_updated.emit(process.stage_progress)

		# Check if stage completed
		if process.stage_progress >= 1.0:
			_complete_stage(process)
	# If stage has required actions, do nothing - wait for player to click the button


func _complete_stage(process: CraftingProcess):
	"""Complete the current crafting stage"""
	var recipe = process.recipe
	var current_stage = recipe.crafting_stages[process.current_stage_index]

	# Calculate stage quality based on actions
	var stage_quality = _calculate_stage_quality(process, current_stage)
	process.stage_qualities[process.current_stage_index] = stage_quality

	process.stage_completed.emit(process.current_stage_index, stage_quality)

	# Move to next stage or complete
	process.current_stage_index += 1
	process.stage_progress = 0.0

	if process.current_stage_index >= recipe.crafting_stages.size():
		_complete_crafting(process)
	else:
		process.stage_started.emit(process.current_stage_index)


func _calculate_stage_quality(process: CraftingProcess, stage: CraftingRecipe.CraftingStage) -> float:
	"""Calculate quality for completed stage"""
	if stage.required_actions.is_empty():
		return 1.0

	var total_quality = 0.0
	for action in stage.required_actions:
		var param_value = process.current_parameters.get(action.action_id, action.optimal_value)
		var deviation = abs(param_value - action.optimal_value)
		var quality = 1.0 - (deviation / action.tolerance)
		total_quality += clamp(quality, 0.0, 1.0)

	return total_quality / stage.required_actions.size()


func _complete_crafting(process: CraftingProcess):
	"""Complete the crafting process and generate output"""
	# Calculate overall quality
	var total_quality = 0.0
	for quality in process.stage_qualities:
		total_quality += quality
	process.overall_quality = total_quality / process.stage_qualities.size()

	process.success = true

	print("✓ Crafting completed: ", process.recipe.recipe_name, " x", process.recipe.output_quantity)
	print("  Quality: %.1f%%" % (process.overall_quality * 100))

	# Generate output items as Dictionary (will be converted to actual items when collected)
	if process.output_items.is_empty():
		var output_data = {"item_id": process.recipe.output_item_id, "quantity": process.recipe.output_quantity, "quality": process.overall_quality}
		process.output_items.append(output_data)

	# Emit completion signal (items will be added when player clicks collect)
	process.process_completed.emit(process.output_items, process.overall_quality)
	crafting_completed.emit(process)


func collect_crafting_output(process: CraftingProcess):
	"""Clean up after collecting crafted items and add them to inventory"""
	if not process:
		return

	# Add items to inventory now
	if inventory_manager and player_container and process.output_items.size() > 0:
		for output_item in process.output_items:
			# Check if it's already an InventoryItem_Base or if it's a Dictionary
			if output_item is InventoryItem_Base:
				# Already a proper item object
				var added = player_container.add_item(output_item)
				if added:
					print("✓ Collected: ", output_item.item_name, " x", output_item.quantity)
				else:
					push_warning("Failed to add item to inventory - container full?")
			elif output_item is Dictionary:
				# Need to create actual item from dictionary
				var item = InventoryItem_Base.new()
				item.item_id = output_item.get("item_id", "")
				item.item_name = process.recipe.recipe_name
				item.quantity = output_item.get("quantity", 1)
				item.item_type = ItemTypes.Type.AMMUNITION
				item.volume = 0.025
				item.mass = 0.01
				item.base_value = 10.0
				item.max_stack_size = 999999

				var added = player_container.add_item(item)
				if added:
					print("✓ Collected: ", item.item_name, " x", item.quantity)
				else:
					push_warning("Failed to add item to inventory - container full?")

	# Remove from active processes
	if process in active_processes:
		active_processes.erase(process)


func cancel_process(process: CraftingProcess):
	"""Cancel an active crafting process"""
	if process in active_processes:
		process.cancel_process()
		active_processes.erase(process)
		crafting_failed.emit(process)


func get_active_processes() -> Array[CraftingProcess]:
	"""Get all active crafting processes"""
	return active_processes
