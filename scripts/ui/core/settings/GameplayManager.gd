# GameplayManager.gd
class_name GameplayManager
extends Node

# Current settings
var current_settings: Dictionary = {}

# Default settings
var default_settings: Dictionary = {
	"mouse_sensitivity": 1.0,
	"auto_save": true,
	"difficulty": "Normal"
}

# Available options
var available_difficulties: Array[String] = ["Easy", "Normal", "Hard", "Expert"]

# Signals
signal settings_applied()
signal settings_changed(setting_name: String, value)

func _ready():
	add_to_group("gameplay_manager")
	_load_settings()

func apply_mouse_sensitivity(sensitivity: float):
	"""Apply mouse sensitivity setting"""
	sensitivity = clamp(sensitivity, 0.1, 5.0)
	current_settings["mouse_sensitivity"] = sensitivity
	
	# Apply to player's mouse look if available
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_mouse_sensitivity"):
		player.set_mouse_sensitivity(sensitivity)
	
	settings_changed.emit("mouse_sensitivity", sensitivity)

func apply_auto_save(enabled: bool):
	"""Apply auto save setting"""
	current_settings["auto_save"] = enabled
	
	# Apply to save system if available
	var save_manager = get_tree().get_first_node_in_group("save_manager")
	if save_manager and save_manager.has_method("set_auto_save_enabled"):
		save_manager.set_auto_save_enabled(enabled)
	
	settings_changed.emit("auto_save", enabled)

func apply_difficulty(difficulty: String):
	"""Apply difficulty setting"""
	if difficulty in available_difficulties:
		current_settings["difficulty"] = difficulty
		
		# Apply to game systems if available
		var game_manager = get_tree().get_first_node_in_group("game_manager")
		if game_manager and game_manager.has_method("set_difficulty"):
			game_manager.set_difficulty(difficulty)
		
		settings_changed.emit("difficulty", difficulty)

func apply_all_settings():
	"""Apply all current gameplay settings"""
	apply_mouse_sensitivity(current_settings.get("mouse_sensitivity", default_settings["mouse_sensitivity"]))
	apply_auto_save(current_settings.get("auto_save", default_settings["auto_save"]))
	apply_difficulty(current_settings.get("difficulty", default_settings["difficulty"]))
	settings_applied.emit()

func get_current_setting(setting_name: String, default_value = null):
	"""Get current setting value"""
	return current_settings.get(setting_name, default_value)

func get_available_difficulties() -> Array[String]:
	return available_difficulties

func _load_settings():
	"""Load gameplay settings from file"""
	var config = ConfigFile.new()
	var err = config.load("user://gameplay_settings.cfg")
	
	if err == OK:
		for key in default_settings.keys():
			current_settings[key] = config.get_value("gameplay", key, default_settings[key])
	else:
		current_settings = default_settings.duplicate()
	
	apply_all_settings()

func save_settings():
	"""Save gameplay settings to file"""
	var config = ConfigFile.new()
	
	for key in current_settings.keys():
		config.set_value("gameplay", key, current_settings[key])
	
	config.save("user://gameplay_settings.cfg")

func reset_to_defaults():
	"""Reset all settings to defaults"""
	current_settings = default_settings.duplicate()
	apply_all_settings()