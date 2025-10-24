# CraftingStationInteractable.gd - Interactable crafting station
# Attach this to crafting station nodes in your world
# Place in: scripts/crafting/integration/CraftingStationInteractable.gd
class_name CraftingStationInteractable
extends Interactable  # Extends your existing Interactable class

@export_category("Station Properties")
@export_enum("basic_workbench", "advanced_fabricator", "chemical_station") var station_type: String = "basic_workbench"
@export var station_name: String = "Workbench"

@export_category("Requirements")
@export var require_skill: bool = false
@export var required_skill_level: int = 1
@export var require_unlock: bool = false
@export var unlock_id: String = ""

@export_category("Visual Feedback")
@export var station_busy_color: Color = Color.RED
@export var station_ready_color: Color = Color.GREEN

var is_in_use: bool = false
var current_user: Node = null


func _ready():
	super._ready()

	# Set interaction text based on station
	interaction_text = "Use " + station_name
	interaction_key = "E"
	is_repeatable = true

	# Configure interaction cooldown
	interaction_cooldown = 0.5


func _perform_interaction() -> bool:
	"""Open the crafting station when interacted with"""
	# Get player reference
	var player = get_player_reference()
	if not player:
		push_warning("CraftingStationInteractable: No player found")
		return false

	# Check if station is already in use
	if is_in_use and current_user != player:
		print("This station is currently in use")
		return false

	# Get crafting integration from player
	var crafting_integration = player.get_node_or_null("CraftingIntegration")
	if not crafting_integration:
		push_error("CraftingStationInteractable: Player has no CraftingIntegration component")
		return false

	# Check requirements
	if not _check_requirements(player, crafting_integration):
		return false

	# Mark station as in use
	is_in_use = true
	current_user = player

	# Open the crafting station
	crafting_integration.open_crafting_station(station_type, self)

	# Connect to window close signal to release station
	_connect_to_crafting_window(crafting_integration)

	return true


func _check_requirements(player: Node, crafting_integration: CraftingIntegration) -> bool:
	"""Check if player meets requirements to use this station"""
	# Check skill requirement
	if require_skill and not _check_player_skill(player):
		print("You need %s skill level %d to use this station" % [station_name, required_skill_level])
		return false

	# Check unlock requirement
	if require_unlock and not _check_player_unlock(player):
		print("This %s is locked. You need: %s" % [station_name, unlock_id])
		return false

	# Check if player can use this station type (custom logic)
	if not crafting_integration.can_use_station(station_type):
		print("You cannot use this type of station yet")
		return false

	return true


func _check_player_skill(player: Node) -> bool:
	"""Check if player has required skill level"""
	# TODO: Implement your skill system check here
	# Example: return player.skills.crafting_level >= required_skill_level
	return true  # For now, allow all


func _check_player_unlock(player: Node) -> bool:
	"""Check if player has unlocked this station"""
	# TODO: Implement your unlock system check here
	# Example: return player.unlocks.has(unlock_id)
	return true  # For now, allow all


func _connect_to_crafting_window(crafting_integration: CraftingIntegration):
	"""Connect to window closed signal to release station"""
	var crafting_window = crafting_integration.crafting_window
	if crafting_window and not crafting_window.window_closed.is_connected(_on_crafting_window_closed):
		crafting_window.window_closed.connect(_on_crafting_window_closed)


func _on_crafting_window_closed():
	"""Release station when window is closed"""
	is_in_use = false
	current_user = null
	print("Station released")


func release_station():
	"""Manually release the station"""
	is_in_use = false
	current_user = null


# VISUAL FEEDBACK


func _on_interaction_area_mouse_entered():
	"""Visual feedback when player looks at station"""
	# highlight_on_hover is inherited from parent Interactable class
	if highlight_on_hover and not is_in_use:
		_apply_highlight(true)


func _on_interaction_area_mouse_exited():
	"""Remove visual feedback"""
	# highlight_on_hover is inherited from parent Interactable class
	if highlight_on_hover:
		_apply_highlight(false)


func _apply_highlight(enabled: bool):
	"""Apply visual highlight to station - customize based on your visual setup"""
	# TODO: Implement your visual feedback here
	# Examples:
	# - Change material emission
	# - Show outline shader
	# - Display floating text
	# - Play particle effect
	pass


func get_station_status() -> String:
	"""Get current station status for UI"""
	if is_in_use:
		return "In Use"
	elif require_unlock:
		return "Locked"
	else:
		return "Available"


func get_station_info() -> Dictionary:
	"""Get station information for UI display"""
	return {
		"name": station_name,
		"type": station_type,
		"in_use": is_in_use,
		"requires_skill": require_skill,
		"required_skill_level": required_skill_level,
		"requires_unlock": require_unlock,
		"unlock_id": unlock_id
	}


# DEBUG


func _get_configuration_warnings() -> PackedStringArray:
	"""Provide helpful warnings in the editor"""
	var warnings: PackedStringArray = []

	if station_name.is_empty():
		warnings.append("Station name is not set")

	if station_type.is_empty():
		warnings.append("Station type is not set")

	if require_unlock and unlock_id.is_empty():
		warnings.append("Unlock required but unlock_id is not set")

	return warnings
