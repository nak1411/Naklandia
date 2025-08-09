# AudioManager.gd
class_name AudioManager
extends Node

# Audio bus names (these should match your audio buses in the Audio tab)
const MASTER_BUS = "Master"
const MUSIC_BUS = "Music"
const SFX_BUS = "SFX"

# Current settings
var current_settings: Dictionary = {}

# Default settings
var default_settings: Dictionary = {
	"master_volume": 0.8,
	"music_volume": 0.6,
	"sfx_volume": 0.8
}

# Signals
signal settings_applied()
signal settings_changed(setting_name: String, value)

func _ready():
	add_to_group("audio_manager")

	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus(1)
		AudioServer.set_bus_name(1, "SFX")
	
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus(2) 
		AudioServer.set_bus_name(2, "Music")
		
	_load_settings()

func apply_master_volume(volume: float):
	"""Apply master volume setting"""
	volume = clamp(volume, 0.0, 1.0)
	var db = linear_to_db(volume)
	if volume == 0.0:
		db = -80.0  # Mute
	
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MASTER_BUS), db)
	current_settings["master_volume"] = volume
	settings_changed.emit("master_volume", volume)

func apply_music_volume(volume: float):
	"""Apply music volume setting"""
	volume = clamp(volume, 0.0, 1.0)
	var db = linear_to_db(volume)
	if volume == 0.0:
		db = -80.0  # Mute
	
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MUSIC_BUS), db)
	current_settings["music_volume"] = volume
	settings_changed.emit("music_volume", volume)

func apply_sfx_volume(volume: float):
	"""Apply SFX volume setting"""
	volume = clamp(volume, 0.0, 1.0)
	var db = linear_to_db(volume)
	if volume == 0.0:
		db = -80.0  # Mute
	
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX_BUS), db)
	current_settings["sfx_volume"] = volume
	settings_changed.emit("sfx_volume", volume)

func apply_all_settings():
	"""Apply all current audio settings"""
	apply_master_volume(current_settings.get("master_volume", default_settings["master_volume"]))
	apply_music_volume(current_settings.get("music_volume", default_settings["music_volume"]))
	apply_sfx_volume(current_settings.get("sfx_volume", default_settings["sfx_volume"]))
	settings_applied.emit()

func get_current_setting(setting_name: String, default_value = null):
	"""Get current setting value"""
	return current_settings.get(setting_name, default_value)

func _load_settings():
	"""Load audio settings from file"""
	var config = ConfigFile.new()
	var err = config.load("user://audio_settings.cfg")
	
	if err == OK:
		for key in default_settings.keys():
			current_settings[key] = config.get_value("audio", key, default_settings[key])
	else:
		current_settings = default_settings.duplicate()
	
	apply_all_settings()

func save_settings():
	"""Save audio settings to file"""
	var config = ConfigFile.new()
	
	for key in current_settings.keys():
		config.set_value("audio", key, current_settings[key])
	
	config.save("user://audio_settings.cfg")

func reset_to_defaults():
	"""Reset all settings to defaults"""
	current_settings = default_settings.duplicate()
	apply_all_settings()

func play_sound_at_position(sound_name: String, position: Vector3):
	"""Play a sound effect at a specific position"""
	# You can expand this based on your audio system needs
	print("Playing sound: ", sound_name, " at position: ", position)