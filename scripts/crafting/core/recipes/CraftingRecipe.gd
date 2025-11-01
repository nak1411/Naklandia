# CraftingRecipe.gd - Simplified crafting recipe for basic crafting
class_name CraftingRecipe
extends Resource

# Recipe identification
@export var recipe_id: String = ""

# Cached display data (auto-populated from ItemDatabase)
var recipe_name: String = "Unknown Recipe"
var description: String = ""
var icon_path: String = ""

# Input requirements
var required_materials: Array[RecipeMaterial] = []

# Output
@export var output_item_id: String = ""
@export var output_quantity: int = 1

# Cached output item type (auto-populated from ItemDatabase)
var output_item_type: ItemTypes.Type = ItemTypes.Type.MISCELLANEOUS

# Recipe unlocking
@export var is_discovered: bool = false
@export var is_always_available: bool = true


# Inner class for material requirements
class RecipeMaterial:
	var material_id: String = ""
	var material_name: String = ""
	var quantity: int = 1
	var consumed: bool = true


func _init():
	if recipe_id.is_empty():
		recipe_id = "recipe_" + str(Time.get_unix_time_from_system())


func refresh_from_item_database():
	"""Refresh recipe display data from ItemDatabase based on output_item_id"""
	if output_item_id.is_empty():
		return

	var item_db = _get_item_database()
	if not item_db:
		return

	var item_def = item_db.get_item(output_item_id)
	if not item_def:
		push_warning("CraftingRecipe: Output item not found in database: " + output_item_id)
		return

	# Update recipe display data from item definition
	recipe_name = item_def.name
	description = item_def.description
	icon_path = item_def.icon_path
	output_item_type = item_def.item_type

	# Refresh material names
	for mat in required_materials:
		if not mat.material_id.is_empty():
			var mat_def = item_db.get_item(mat.material_id)
			if mat_def:
				mat.material_name = mat_def.name


func _get_item_database():
	"""Get ItemDatabase singleton"""
	# Try AutoLoad first
	if Engine.has_singleton("ItemDatabase"):
		return Engine.get_singleton("ItemDatabase")

	# Try direct node path
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root.has_node("/root/ItemDatabase"):
		return tree.root.get_node("/root/ItemDatabase")

	return null


func can_craft(available_materials: Dictionary) -> bool:
	"""Check if the recipe can be crafted with available materials"""
	for req_mat in required_materials:
		var available = available_materials.get(req_mat.material_id, 0)
		if available < req_mat.quantity:
			return false
	return true


func get_missing_materials(available_materials: Dictionary) -> Array[RecipeMaterial]:
	"""Get list of missing or insufficient materials"""
	var missing: Array[RecipeMaterial] = []

	for req_mat in required_materials:
		var available = available_materials.get(req_mat.material_id, 0)
		if available < req_mat.quantity:
			var shortage = RecipeMaterial.new()
			shortage.material_id = req_mat.material_id
			shortage.material_name = req_mat.material_name
			shortage.quantity = req_mat.quantity - available
			missing.append(shortage)

	return missing


func get_materials_summary() -> String:
	"""Get a formatted string of required materials"""
	var summary = ""
	for i in range(required_materials.size()):
		var mat = required_materials[i]
		summary += "%s x%d" % [mat.material_name, mat.quantity]
		if i < required_materials.size() - 1:
			summary += ", "
	return summary
