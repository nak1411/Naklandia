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
	# Hybrid Charges Recipe
	var wrench = CraftingRecipe.new()
	wrench.recipe_id = "recipe_wrench"
	wrench.recipe_name = "Wrench"
	wrench.description = "Creates a wrench used for contructing items and structures."
	wrench.output_item_id = "wrench"
	wrench.output_quantity = 1
	wrench.output_item_type = ItemTypes.Type.TOOL
	wrench.is_always_available = true

	var noxite_mat = CraftingRecipe.RecipeMaterial.new()
	noxite_mat.material_id = "resource_noxite"
	noxite_mat.material_name = "Noxite"
	noxite_mat.quantity = 1
	wrench.required_materials.append(noxite_mat)

	all_recipes.append(wrench)

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

	# Save inventory after successful crafting
	if inventory_manager:
		inventory_manager.save_inventory()

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


func _complete_crafting(recipe: CraftingRecipe) -> bool:
	"""Complete the crafting process and generate output"""
	if inventory_manager and player_container:
		var output_item = ItemDatabase.create_item_instance(recipe.output_item_id, recipe.output_quantity)

		if not output_item:
			push_error("CraftingManager: Failed to create item from database: " + recipe.output_item_id)
			return false

		player_container.add_item(output_item)
		return true
	return false
