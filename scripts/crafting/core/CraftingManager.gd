# CraftingManager.gd - Simplified crafting system manager
class_name CraftingManager
extends Node

signal recipe_discovered(recipe: CraftingRecipe)
signal crafting_completed(output_item_id: String, quantity: int)
signal crafting_failed(reason: String)

# Configuration
const RECIPE_DATA_PATH = "res://data/recipes/"
const ENABLE_JSON_LOADING = true  # Set to false to use hardcoded recipes

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
	"""Load crafting recipes from JSON or hardcoded fallback"""
	if ENABLE_JSON_LOADING:
		_load_recipes_from_json()
	else:
		_load_hardcoded_recipes()


func _load_recipes_from_json():
	"""Load all recipe definitions from JSON files"""
	print("CraftingManager: Loading recipes from JSON files...")

	var json_files = ["basic_crafting.json"]

	var total_recipes = 0
	for file_name in json_files:
		var file_path = RECIPE_DATA_PATH + file_name
		var recipes_loaded = _load_recipe_json_file(file_path)
		total_recipes += recipes_loaded
		if recipes_loaded > 0:
			print("  Loaded %d recipes from %s" % [recipes_loaded, file_name])

	print("CraftingManager: Loaded %d total recipes from JSON" % total_recipes)

	# Discover all always-available recipes by default
	for recipe in all_recipes:
		if recipe.is_always_available:
			discovered_recipes.append(recipe.recipe_id)


func _load_recipe_json_file(file_path: String) -> int:
	"""Load recipes from a single JSON file"""
	print("  Attempting to load: " + file_path)
	if not FileAccess.file_exists(file_path):
		push_warning("CraftingManager: JSON file not found: " + file_path)
		return 0

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("CraftingManager: Failed to open JSON file: " + file_path)
		return 0

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_text)

	if parse_result != OK:
		push_error(
			(
				"CraftingManager: JSON parse error in %s at line %d: %s"
				% [file_path, json.get_error_line(), json.get_error_message()]
			)
		)
		return 0

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("CraftingManager: JSON root must be a dictionary in " + file_path)
		return 0

	var count = 0
	for recipe_id in data:
		if _create_recipe_from_json(recipe_id, data[recipe_id]):
			count += 1

	return count


func _create_recipe_from_json(recipe_id: String, recipe_data: Dictionary) -> bool:
	"""Create a recipe from JSON data"""
	# Validate required fields
	if not recipe_data.has("output_item_id"):
		push_error("CraftingManager: Recipe %s missing 'output_item_id' field" % recipe_id)
		return false

	# Create recipe
	var recipe = CraftingRecipe.new()
	recipe.recipe_id = recipe_id
	recipe.output_item_id = recipe_data.get("output_item_id", "")
	recipe.output_quantity = recipe_data.get("output_quantity", 1)
	recipe.is_always_available = recipe_data.get("is_always_available", false)
	recipe.is_discovered = recipe_data.get("is_discovered", false)

	# Load required materials
	if recipe_data.has("required_materials"):
		var materials = recipe_data["required_materials"]
		if typeof(materials) == TYPE_ARRAY:
			for mat_data in materials:
				if typeof(mat_data) == TYPE_DICTIONARY:
					var material = CraftingRecipe.RecipeMaterial.new()
					material.material_id = mat_data.get("material_id", "")
					material.quantity = mat_data.get("quantity", 1)
					material.consumed = mat_data.get("consumed", true)
					recipe.required_materials.append(material)

	# Refresh recipe from ItemDatabase (populates name, description, etc.)
	recipe.refresh_from_item_database()

	all_recipes.append(recipe)
	return true


func _load_hardcoded_recipes():
	"""Load hardcoded recipe definitions (legacy/fallback)"""
	print("CraftingManager: Using hardcoded recipe definitions...")
	_create_basic_recipes()


func _create_basic_recipes():
	"""Create basic crafting recipes"""
	# Wrench Recipe - data auto-populated from ItemDatabase
	var wrench = CraftingRecipe.new()
	wrench.recipe_id = "recipe_wrench"
	wrench.output_item_id = "tool_wrench"
	wrench.output_quantity = 1
	wrench.is_always_available = true

	var iron_ingot_mat = CraftingRecipe.RecipeMaterial.new()
	iron_ingot_mat.material_id = "resource_iron_ingot"
	iron_ingot_mat.quantity = 1
	wrench.required_materials.append(iron_ingot_mat)

	# Refresh display data from ItemDatabase
	wrench.refresh_from_item_database()

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


func reload_recipes():
	"""Reload all recipes from JSON files (for hot-reload)"""
	print("CraftingManager: Reloading recipes from JSON...")
	all_recipes.clear()
	discovered_recipes.clear()
	_load_recipes()
	print("CraftingManager: Reload complete!")


func refresh_recipes():
	"""Refresh all recipes to pull updated data from ItemDatabase"""
	print("CraftingManager: Refreshing recipes from ItemDatabase...")
	var refreshed_count = 0

	for recipe in all_recipes:
		recipe.refresh_from_item_database()
		refreshed_count += 1

	print("  Refreshed %d recipes" % refreshed_count)


func _complete_crafting(recipe: CraftingRecipe) -> bool:
	"""Complete the crafting process and generate output"""
	if inventory_manager and player_container:
		var output_item = ItemDatabase.create_item_instance(
			recipe.output_item_id, recipe.output_quantity
		)

		if not output_item:
			push_error(
				"CraftingManager: Failed to create item from database: " + recipe.output_item_id
			)
			return false

		player_container.add_item(output_item)
		return true
	return false
