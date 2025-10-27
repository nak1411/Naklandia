# CraftingRecipe.gd - Simplified crafting recipe for basic crafting
class_name CraftingRecipe
extends Resource

# Recipe identification
@export var recipe_id: String = ""
@export var recipe_name: String = "Unknown Recipe"
@export var description: String = ""
@export var icon_path: String = ""

# Input requirements
var required_materials: Array[RecipeMaterial] = []

# Output
@export var output_item_id: String = ""
@export var output_quantity: int = 1
@export var output_item_type: ItemTypes.Type = ItemTypes.Type.MISCELLANEOUS

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
