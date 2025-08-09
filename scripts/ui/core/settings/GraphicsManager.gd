# GraphicsManager.gd - Fixed for Godot 4.4
class_name GraphicsManager
extends Node

# Graphics settings data
var current_settings: Dictionary = {}
var _applying_settings: bool = false

# Available options
var available_resolutions: Array[String] = []
var available_window_modes: Array[String] = ["Windowed", "Fullscreen", "Exclusive Fullscreen"]
var available_vsync_modes: Array[String] = ["Disabled", "Enabled", "Adaptive", "Mailbox"]
var available_quality_presets: Array[String] = ["Low", "Medium", "High", "Ultra", "Custom"]

# Quality preset configurations
var quality_presets: Dictionary = {
	"Low": {
		"msaa_3d": Viewport.MSAA_DISABLED,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED,
		"use_taa": false,
		"use_debanding": false,
		"use_occlusion_culling": false,
		"mesh_lod_threshold": 4.0,
		"shadow_atlas_size": 512,
		"directional_shadow_size": 1024,
		"sdfgi_enabled": false,
		"ssao_enabled": false,
		"ssil_enabled": false,
		"glow_enabled": false,
		"volumetric_fog_enabled": false
	},
	"Medium": {
		"msaa_3d": Viewport.MSAA_2X,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED,
		"use_taa": false,
		"use_debanding": true,
		"use_occlusion_culling": true,
		"mesh_lod_threshold": 2.0,
		"shadow_atlas_size": 1024,
		"directional_shadow_size": 2048,
		"sdfgi_enabled": false,
		"ssao_enabled": true,
		"ssil_enabled": false,
		"glow_enabled": true,
		"volumetric_fog_enabled": false
	},
	"High": {
		"msaa_3d": Viewport.MSAA_4X,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA,
		"use_taa": false,
		"use_debanding": true,
		"use_occlusion_culling": true,
		"mesh_lod_threshold": 1.0,
		"shadow_atlas_size": 2048,
		"directional_shadow_size": 4096,
		"sdfgi_enabled": true,
		"ssao_enabled": true,
		"ssil_enabled": true,
		"glow_enabled": true,
		"volumetric_fog_enabled": true
	},
	"Ultra": {
		"msaa_3d": Viewport.MSAA_8X,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA,
		"use_taa": true,
		"use_debanding": true,
		"use_occlusion_culling": true,
		"mesh_lod_threshold": 0.5,
		"shadow_atlas_size": 4096,
		"directional_shadow_size": 8192,
		"sdfgi_enabled": true,
		"ssao_enabled": true,
		"ssil_enabled": true,
		"glow_enabled": true,
		"volumetric_fog_enabled": true
	}
}

# Default settings
var default_settings: Dictionary = {
	"resolution": "1920x1080",
	"window_mode": "Windowed",
	"vsync_mode": "Enabled",
	"quality_preset": "High",
	"custom_msaa": Viewport.MSAA_4X,
	"custom_screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA,
	"custom_use_taa": false,
	"custom_use_debanding": true,
	"custom_use_occlusion_culling": true,
	"custom_mesh_lod_threshold": 1.0,
	"custom_shadow_atlas_size": 2048,
	"custom_directional_shadow_size": 4096,
	"custom_sdfgi_enabled": true,
	"custom_ssao_enabled": true,
	"custom_ssil_enabled": true,
	"custom_glow_enabled": true,
	"custom_volumetric_fog_enabled": true,
	"render_scale": 1.0,
	"max_fps": 0
}

# Signals
signal settings_applied()
signal settings_changed(setting_name: String, value)

func _ready():
	add_to_group("graphics_manager")
	_detect_available_resolutions()
	_load_settings()

func _detect_available_resolutions():
	"""Detect available screen resolutions"""
	available_resolutions.clear()
	
	# Get current screen size
	var screen_size = DisplayServer.screen_get_size()
	
	# Common 16:9 resolutions
	var common_resolutions: Array[Vector2i] = [
		Vector2i(1280, 720),
		Vector2i(1366, 768),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440),
		Vector2i(3840, 2160)
	]
	
	# Add resolutions that fit within the screen
	for res in common_resolutions:
		if res.x <= screen_size.x and res.y <= screen_size.y:
			available_resolutions.append(str(res.x) + "x" + str(res.y))
	
	# Add current screen resolution if not already included
	var current_res_string = str(screen_size.x) + "x" + str(screen_size.y)
	if not available_resolutions.has(current_res_string):
		available_resolutions.append(current_res_string)
	
	available_resolutions.sort()

func get_available_resolutions() -> Array[String]:
	return available_resolutions

func get_available_window_modes() -> Array[String]:
	return available_window_modes

func get_available_vsync_modes() -> Array[String]:
	return available_vsync_modes

func get_available_quality_presets() -> Array[String]:
	return available_quality_presets

func apply_resolution(resolution: String, force_apply: bool = false):
	"""Apply resolution setting"""
	var parts = resolution.split("x")
	if parts.size() != 2:
		push_error("Invalid resolution format: " + resolution)
		return
	
	current_settings["resolution"] = resolution
	
	# Only apply immediately if forced or if we're in a safe state
	if force_apply:
		var width = int(parts[0])
		var height = int(parts[1])
		var new_size = Vector2i(width, height)
		
		var current_mode = DisplayServer.window_get_mode()
		if current_mode == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_size(new_size)
			
			# Center on primary screen
			var primary_screen = DisplayServer.get_primary_screen()
			var screen_size = DisplayServer.screen_get_size(primary_screen)
			var screen_position = DisplayServer.screen_get_position(primary_screen)
			var window_pos = screen_position + (screen_size - new_size) / 2
			DisplayServer.window_set_position(window_pos)
	
	settings_changed.emit("resolution", resolution)

func apply_window_mode(mode: String):
	"""Apply window mode setting"""
	match mode:
		"Windowed":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		"Fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"Exclusive Fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	
	current_settings["window_mode"] = mode
	settings_changed.emit("window_mode", mode)

func apply_vsync_mode(mode: String):
	"""Apply VSync setting"""
	match mode:
		"Disabled":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		"Enabled":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		"Adaptive":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
		"Mailbox":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX)
	
	current_settings["vsync_mode"] = mode
	settings_changed.emit("vsync_mode", mode)

func apply_quality_preset(preset: String):
	"""Apply quality preset"""
	if preset == "Custom":
		# Use custom settings
		_apply_custom_quality_settings()
	else:
		# Apply preset
		if quality_presets.has(preset):
			var preset_data = quality_presets[preset]
			_apply_quality_settings(preset_data)
	
	current_settings["quality_preset"] = preset
	settings_changed.emit("quality_preset", preset)

func apply_render_scale(scale: float):
	"""Apply render scale (resolution scaling)"""
	scale = clamp(scale, 0.25, 2.0)
	
	var viewport = get_viewport()
	if viewport:
		viewport.set_scaling_3d_scale(scale)
	
	current_settings["render_scale"] = scale
	settings_changed.emit("render_scale", scale)

func apply_max_fps(fps: int):
	"""Apply FPS limit"""
	if fps <= 0:
		Engine.max_fps = 0  # Unlimited
	else:
		Engine.max_fps = fps
	
	current_settings["max_fps"] = fps
	settings_changed.emit("max_fps", fps)

func _apply_quality_settings(settings: Dictionary):
	"""Apply quality settings to the rendering server and viewport"""
	var viewport = get_viewport()
	if not viewport:
		return
	
	# MSAA
	if settings.has("msaa_3d"):
		viewport.set_msaa_3d(settings["msaa_3d"])
	
	# Screen Space AA
	if settings.has("screen_space_aa"):
		viewport.set_screen_space_aa(settings["screen_space_aa"])
	
	# TAA
	if settings.has("use_taa"):
		viewport.set_use_taa(settings["use_taa"])
	
	# Debanding
	if settings.has("use_debanding"):
		viewport.set_use_debanding(settings["use_debanding"])
	
	# Occlusion culling
	if settings.has("use_occlusion_culling"):
		viewport.set_use_occlusion_culling(settings["use_occlusion_culling"])
	
	# Mesh LOD threshold
	if settings.has("mesh_lod_threshold"):
		viewport.set_mesh_lod_threshold(settings["mesh_lod_threshold"])
	
	# Shadow atlas settings
	if settings.has("shadow_atlas_size"):
		RenderingServer.viewport_set_positional_shadow_atlas_size(
			viewport.get_viewport_rid(), 
			settings["shadow_atlas_size"], 
			true
		)
	
	# Environment settings
	var world_env = _find_world_environment()
	if world_env and world_env.environment:
		var env = world_env.environment
		
		if settings.has("sdfgi_enabled"):
			env.sdfgi_enabled = settings["sdfgi_enabled"]
		
		if settings.has("ssao_enabled"):
			env.ssao_enabled = settings["ssao_enabled"]
		
		if settings.has("ssil_enabled"):
			env.ssil_enabled = settings["ssil_enabled"]
		
		if settings.has("glow_enabled"):
			env.glow_enabled = settings["glow_enabled"]
		
		if settings.has("volumetric_fog_enabled"):
			env.volumetric_fog_enabled = settings["volumetric_fog_enabled"]
	
	# Apply directional shadow size
	if settings.has("directional_shadow_size"):
		_apply_directional_shadow_size(settings["directional_shadow_size"])

func _apply_directional_shadow_size(size: int):
	"""Apply directional shadow size to all DirectionalLight3D nodes"""
	var scene_root = get_tree().current_scene
	var lights = _find_all_directional_lights(scene_root)
	
	for light in lights:
		var dir_light = light as DirectionalLight3D
		if dir_light:
			dir_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS

func _find_all_directional_lights(node: Node) -> Array[Node]:
	"""Find all DirectionalLight3D nodes"""
	var lights: Array[Node] = []
	
	if node.get_class() == "DirectionalLight3D":
		lights.append(node)
	
	for child in node.get_children():
		lights.append_array(_find_all_directional_lights(child))
	
	return lights

func _apply_custom_quality_settings():
	"""Apply custom quality settings"""
	var custom_settings: Dictionary = {}
	
	# Build custom settings from stored values
	for key in default_settings.keys():
		if key.begins_with("custom_"):
			var setting_key = key.substr(7)  # Remove "custom_" prefix
			custom_settings[setting_key] = current_settings.get(key, default_settings[key])
	
	_apply_quality_settings(custom_settings)

func _find_world_environment() -> WorldEnvironment:
	"""Find WorldEnvironment node in the scene"""
	var scene_root = get_tree().current_scene
	var found = _find_node_by_class_name(scene_root, "WorldEnvironment")
	return found as WorldEnvironment

func _find_node_by_type_recursive(node: Node, node_class: String) -> Node:
	"""Recursively find a node of specific type"""
	if node.get_class() == node_class:
		return node
	
	for child in node.get_children():
		var result = _find_node_by_type_recursive(child, node_class)
		if result:
			return result
	
	return null

func _find_nodes_by_type_recursive(node: Node, node_class: String) -> Array[Node]:
	"""Recursively find all nodes of specific type"""
	var found_nodes: Array[Node] = []
	
	if node.get_class() == node_class:
		found_nodes.append(node)
	
	for child in node.get_children():
		var child_results = _find_nodes_by_type_recursive(child, node_class)
		found_nodes.append_array(child_results)
	
	return found_nodes

func _find_nodes_by_class_recursive(node: Node, node_class: String) -> Array[Node]:
	var found_nodes: Array[Node] = []
	if node.get_class() == node_class:
		found_nodes.append(node)
	for child in node.get_children():
		var child_results = _find_nodes_by_class_recursive(child, node_class)
		found_nodes.append_array(child_results)
	return found_nodes

func _find_node_by_class_name(node: Node, node_class: String) -> Node:
	"""Recursively find a node of specific class"""
	if node.get_class() == node_class:
		return node
	
	for child in node.get_children():
		var result = _find_node_by_class_name(child, node_class)
		if result:
			return result
	
	return null

func get_current_setting(setting_name: String, default_value = null):
	"""Get current setting value"""
	return current_settings.get(setting_name, default_value)

func set_custom_setting(setting_name: String, value):
	"""Set a custom quality setting"""
	var custom_key = "custom_" + setting_name
	current_settings[custom_key] = value
	
	# If we're using custom preset, apply immediately
	if current_settings.get("quality_preset", "") == "Custom":
		_apply_custom_quality_settings()

func _load_settings():
	"""Load graphics settings from file"""
	var config = ConfigFile.new()
	var err = config.load("user://graphics_settings.cfg")
	
	if err == OK:
		for key in default_settings.keys():
			current_settings[key] = config.get_value("graphics", key, default_settings[key])
	else:
		# Use defaults
		current_settings = default_settings.duplicate()
	
	# Apply loaded settings
	apply_all_settings()

func save_settings():
	"""Save graphics settings to file"""
	var config = ConfigFile.new()
	
	for key in current_settings.keys():
		config.set_value("graphics", key, current_settings[key])
	
	config.save("user://graphics_settings.cfg")

func apply_all_settings():
	"""Apply all current settings"""
	if _applying_settings:
		return
	
	_applying_settings = true
	
	# Apply non-display settings first
	apply_vsync_mode(current_settings.get("vsync_mode", default_settings["vsync_mode"]))
	apply_quality_preset(current_settings.get("quality_preset", default_settings["quality_preset"]))
	apply_render_scale(current_settings.get("render_scale", default_settings["render_scale"]))
	apply_max_fps(current_settings.get("max_fps", default_settings["max_fps"]))
	
	# Handle display settings with force apply
	var target_mode = current_settings.get("window_mode", default_settings["window_mode"])
	var target_resolution = current_settings.get("resolution", default_settings["resolution"])
	
	# Apply window mode first
	apply_window_mode(target_mode)
	
	# Force apply resolution
	apply_resolution(target_resolution, true)  # Add force_apply = true here
	
	_applying_settings = false
	settings_applied.emit()

func reset_to_defaults():
	"""Reset all settings to defaults"""
	current_settings = default_settings.duplicate()
	apply_all_settings()

func get_performance_info() -> Dictionary:
	"""Get current performance information"""
	return {
		"fps": Engine.get_frames_per_second(),
		"frame_time": Performance.get_monitor(Performance.TIME_PROCESS),
		"render_time": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),
		"memory_usage": Performance.get_monitor(Performance.MEMORY_STATIC),
		"video_memory": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	}

func get_current_graphics_info() -> Dictionary:
	"""Get current graphics configuration info"""
	var viewport = get_viewport()
	var info = {}
	
	if viewport:
		info["current_resolution"] = str(DisplayServer.window_get_size().x) + "x" + str(DisplayServer.window_get_size().y)
		info["window_mode"] = DisplayServer.window_get_mode()
		info["vsync_mode"] = DisplayServer.window_get_vsync_mode()
		info["msaa_3d"] = viewport.get_msaa_3d()
		info["screen_space_aa"] = viewport.get_screen_space_aa()
		info["use_taa"] = viewport.get_use_taa()
		info["render_scale"] = viewport.get_scaling_3d_scale()
	
	return info