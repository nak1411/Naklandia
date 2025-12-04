# DebugManager.gd
# Singleton autoload for managing debug settings across the game
extends Node

signal settings_changed(setting_id: String, value)
signal chunk_visualization_toggled(enabled: bool)
signal tree_debug_toggled(enabled: bool)

# Default debug settings
var default_settings: Dictionary = {
	"show_chunk_overlay": false,
	"show_tree_debug": false,
	"show_performance_stats": false,
}

# Current debug settings
var current_settings: Dictionary = {}

# Config file path
const CONFIG_PATH = "user://debug_settings.cfg"


func _ready():
	# Load saved settings or use defaults
	load_settings()


func load_settings():
	"""Load debug settings from config file"""
	var config = ConfigFile.new()
	var err = config.load(CONFIG_PATH)

	if err == OK:
		# Load each setting from config
		for setting_id in default_settings.keys():
			current_settings[setting_id] = config.get_value("debug", setting_id, default_settings[setting_id])
	else:
		# Use defaults if no config file exists
		current_settings = default_settings.duplicate()

	print("DebugManager: Loaded settings: ", current_settings)


func save_settings():
	"""Save debug settings to config file"""
	var config = ConfigFile.new()

	# Save each setting to config
	for setting_id in current_settings.keys():
		config.set_value("debug", setting_id, current_settings[setting_id])

	var err = config.save(CONFIG_PATH)
	if err == OK:
		print("DebugManager: Settings saved successfully")
	else:
		print("DebugManager: Failed to save settings, error: ", err)


func get_current_setting(setting_id: String, default_value):
	"""Get a current setting value"""
	return current_settings.get(setting_id, default_value)


func set_setting(setting_id: String, value):
	"""Set a setting value and emit appropriate signals"""
	if current_settings.get(setting_id) == value:
		return  # No change

	current_settings[setting_id] = value
	settings_changed.emit(setting_id, value)

	# Emit specific signals for certain settings
	match setting_id:
		"show_chunk_overlay":
			chunk_visualization_toggled.emit(value)
			print("DebugManager: Chunk visualization ", "enabled" if value else "disabled")
		"show_tree_debug":
			tree_debug_toggled.emit(value)
			print("DebugManager: Tree debug ", "enabled" if value else "disabled")
		"show_performance_stats":
			print("DebugManager: Performance stats ", "enabled" if value else "disabled")


func apply_all_settings():
	"""Apply all settings to their respective systems"""
	# Emit signals for each setting to update all listeners
	for setting_id in current_settings.keys():
		var value = current_settings[setting_id]

		match setting_id:
			"show_chunk_overlay":
				chunk_visualization_toggled.emit(value)
			"show_tree_debug":
				tree_debug_toggled.emit(value)


func reset_to_defaults():
	"""Reset all settings to their default values"""
	current_settings = default_settings.duplicate()

	# Emit signals for all settings
	for setting_id in current_settings.keys():
		settings_changed.emit(setting_id, current_settings[setting_id])

	apply_all_settings()
	print("DebugManager: Reset to defaults")


func get_chunk_overlay_enabled() -> bool:
	"""Quick accessor for chunk overlay setting"""
	return current_settings.get("show_chunk_overlay", false)


func get_tree_debug_enabled() -> bool:
	"""Quick accessor for tree debug setting"""
	return current_settings.get("show_tree_debug", false)


func get_performance_stats_enabled() -> bool:
	"""Quick accessor for performance stats setting"""
	return current_settings.get("show_performance_stats", false)
