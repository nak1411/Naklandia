# CraftingManager.gd - Simplified crafting system manager
class_name CraftingManager
extends Node

signal recipe_discovered(recipe: CraftingRecipe)
signal crafting_completed(output_item_id: String, quantity: int)
signal crafting_failed(reason: String)

# Managers
var inventory_manager: InventoryManager
var player_container: InventoryContainer_Base

# Recipe data
var all_recipes: Array[CraftingRecipe] = []
var discovered_recipes: Array[String] = []


func _ready():
	add_to_group("crafting_manager")
	_load_recipes()


func set_inventory_manager(manager: InventoryManager):
	"""Set the inventory manager reference"""
	inventory_manager = manager
	if inventory_manager:
		player_container = inventory_manager.get_player_inventory()


func _load_recipes():
	"""Load crafting recipes - in production this would load from files"""
	_create_basic_recipes()


func _create_basic_recipes():
	"""Create basic crafting recipes"""
	# Simple Tool Recipe
	var simple_tool = CraftingRecipe.new()
	simple_tool.recipe_id = "recipe_hybrid_charges"
	simple_tool.recipe_name = "Simple Tool"
	simple_tool.description = "A basic tool crafted from metal plates and screws"
	simple_tool.output_item_id = "ammo_hybrid_charges"
	simple_tool.output_quantity = 100
	simple_tool.output_item_type = ItemTypes.Type.AMMUNITION
	simple_tool.is_always_available = true

	var metal_mat = CraftingRecipe.RecipeMaterial.new()
	metal_mat.material_id = "metal_plate"
	metal_mat.material_name = "Metal Plate"
	metal_mat.quantity = 0
	simple_tool.required_materials.append(metal_mat)

	var screw_mat = CraftingRecipe.RecipeMaterial.new()
	screw_mat.material_id = "screw"
	screw_mat.material_name = "Screw"
	screw_mat.quantity = 0
	simple_tool.required_materials.append(screw_mat)

	all_recipes.append(simple_tool)

	# Basic Component Recipe
	var basic_component = CraftingRecipe.new()
	basic_component.recipe_id = "recipe_basic_component"
	basic_component.recipe_name = "Basic Component"
	basic_component.description = "A simple component made from raw materials"
	basic_component.output_item_id = "basic_component"
	basic_component.output_quantity = 1
	basic_component.is_always_available = true

	var metal_mat2 = CraftingRecipe.RecipeMaterial.new()
	metal_mat2.material_id = "metal_plate"
	metal_mat2.material_name = "Metal Plate"
	metal_mat2.quantity = 1
	basic_component.required_materials.append(metal_mat2)

	all_recipes.append(basic_component)

	# Repair Kit Recipe
	var repair_kit = CraftingRecipe.new()
	repair_kit.recipe_id = "recipe_repair_kit"
	repair_kit.recipe_name = "Repair Kit"
	repair_kit.description = "Emergency repair kit for quick fixes"
	repair_kit.output_item_id = "repair_kit"
	repair_kit.output_quantity = 1
	repair_kit.is_always_available = true

	var metal_mat3 = CraftingRecipe.RecipeMaterial.new()
	metal_mat3.material_id = "metal_plate"
	metal_mat3.material_name = "Metal Plate"
	metal_mat3.quantity = 3
	repair_kit.required_materials.append(metal_mat3)

	var component_mat = CraftingRecipe.RecipeMaterial.new()
	component_mat.material_id = "basic_component"
	component_mat.material_name = "Basic Component"
	component_mat.quantity = 2
	repair_kit.required_materials.append(component_mat)

	all_recipes.append(repair_kit)

	# Discover all always-available recipes by default
	for recipe in all_recipes:
		if recipe.is_always_available:
			discovered_recipes.append(recipe.recipe_id)


func get_available_recipes() -> Array[CraftingRecipe]:
	"""Get all discovered recipes"""
	var available: Array[CraftingRecipe] = []

	for recipe in all_recipes:
		if recipe.recipe_id in discovered_recipes or recipe.is_always_available:
			available.append(recipe)

	return available


func can_craft_recipe(recipe: CraftingRecipe) -> bool:
	"""Check if recipe can be crafted with current resources"""
	if not player_container:
		return false

	var available_materials = _get_available_materials()
	return recipe.can_craft(available_materials)


func _get_available_materials() -> Dictionary:
	"""Get dictionary of available materials from player inventory"""
	var materials: Dictionary = {}

	if not player_container:
		return materials

	for item in player_container.items:
		materials[item.item_id] = materials.get(item.item_id, 0) + item.quantity

	return materials


func craft_recipe(recipe: CraftingRecipe) -> bool:
	"""Attempt to craft a recipe"""
	if not can_craft_recipe(recipe):
		crafting_failed.emit("Missing required materials")
		return false

	# Consume materials
	if not _consume_materials(recipe):
		crafting_failed.emit("Failed to consume materials")
		return false

	# Add output to inventory
	if not _complete_crafting(recipe):
		crafting_failed.emit("Inventory full")
		# Try to restore materials
		_restore_materials(recipe)
		return false

	crafting_completed.emit(recipe.output_item_id, recipe.output_quantity)
	return true


func _consume_materials(recipe: CraftingRecipe) -> bool:
	"""Consume materials required for crafting"""
	if not player_container or not inventory_manager:
		return false

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


func _restore_materials(_recipe: CraftingRecipe):
	"""Restore materials if crafting fails after consumption"""
	# TODO: Implement material restoration if needed


func discover_recipe(recipe_id: String):
	"""Discover a new recipe"""
	if recipe_id not in discovered_recipes:
		discovered_recipes.append(recipe_id)

		var recipe = _get_recipe_by_id(recipe_id)
		if recipe:
			recipe_discovered.emit(recipe)


func _get_recipe_by_id(recipe_id: String) -> CraftingRecipe:
	"""Get a recipe by ID"""
	for recipe in all_recipes:
		if recipe.recipe_id == recipe_id:
			return recipe
	return null


func add_recipe(recipe: CraftingRecipe):
	"""Add a custom recipe to the crafting system"""
	all_recipes.append(recipe)
	if recipe.is_always_available:
		discovered_recipes.append(recipe.recipe_id)


func _complete_crafting(recipe: CraftingRecipe):
	"""Complete the crafting process and generate output"""
	# Generate output item
	if inventory_manager and player_container:
		var output_item = InventoryItem_Base.new()
		output_item.item_id = recipe.output_item_id
		output_item.item_name = recipe.recipe_name
		output_item.quantity = recipe.output_quantity
		output_item.item_type = recipe.output_item_type
		output_item.volume = 0.025
		output_item.mass = 0.01
		output_item.base_value = 10.0
		output_item.max_stack_size = 999999
		player_container.add_item(output_item)
