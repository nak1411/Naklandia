# CleanupOldWindowSettings.gd
# One-time cleanup script to remove old window_settings.cfg
# Run this once to clean up conflicting window settings
extends Node

func _ready():
	_cleanup_old_settings()
	queue_free()

func _cleanup_old_settings():
	var old_config_path = "user://window_settings.cfg"

	if FileAccess.file_exists(old_config_path):
		print("Found old window_settings.cfg - removing to prevent conflicts with GraphicsManager...")
		DirAccess.remove_absolute(old_config_path)
		print("Old window_settings.cfg removed successfully!")
	else:
		print("No old window_settings.cfg found - all good!")
