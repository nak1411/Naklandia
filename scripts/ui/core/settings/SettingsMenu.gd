# SettingsMenu.gd
class_name SettingsMenu
extends Control

# UI References
var main_container: HSplitContainer
var category_list: VBoxContainer
var content_panel: Panel
var content_container: VBoxContainer
var graphics_manager: GraphicsManager

# Category management
var current_category: String = "graphics"
var category_buttons: Dictionary = {}

# Settings data
var settings_data: Dictionary = {}
var settings_controls: Dictionary = {}


# Categories (Eve Online style)
var categories: Array[Dictionary] = [
	{"id": "graphics", "name": "Graphics", "icon": null},
	{"id": "audio", "name": "Audio", "icon": null},
	{"id": "gameplay", "name": "Gameplay", "icon": null},
	{"id": "controls", "name": "Controls", "icon": null}
]

# Settings definitions
var graphics_settings: Array[Dictionary] = [
	{"id": "resolution", "name": "Resolution", "type": "dropdown", "options": ["1920x1080", "1600x900", "1366x768", "1280x720"], "default": "1920x1080"},
	{"id": "fullscreen", "name": "Fullscreen", "type": "checkbox", "default": true},
	{"id": "vsync", "name": "V-Sync", "type": "checkbox", "default": true},
	{"id": "quality", "name": "Graphics Quality", "type": "dropdown", "options": ["Low", "Medium", "High", "Ultra"], "default": "High"}
]

var audio_settings: Array[Dictionary] = [
	{"id": "master_volume", "name": "Master Volume", "type": "slider", "min": 0.0, "max": 1.0, "default": 0.8},
	{"id": "music_volume", "name": "Music Volume", "type": "slider", "min": 0.0, "max": 1.0, "default": 0.6},
	{"id": "sfx_volume", "name": "Sound Effects", "type": "slider", "min": 0.0, "max": 1.0, "default": 0.8}
]

var gameplay_settings: Array[Dictionary] = [
	{"id": "mouse_sensitivity", "name": "Mouse Sensitivity", "type": "slider", "min": 0.1, "max": 3.0, "default": 1.0},
	{"id": "auto_save", "name": "Auto Save", "type": "checkbox", "default": true},
	{"id": "difficulty", "name": "Difficulty", "type": "dropdown", "options": ["Easy", "Normal", "Hard"], "default": "Normal"}
]

# Signals
signal settings_changed(setting_id: String, value)
signal settings_applied()
signal settings_closed()

func _ready():
	_setup_graphics_manager()
	_load_settings()
	_create_ui()
	_populate_categories()
	_select_category("graphics")

func _create_ui():
	# Main container
	main_container = HSplitContainer.new()
	main_container.name = "MainContainer"
	main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_container.split_offset = 200
	add_child(main_container)
	
	# Left panel for categories (Eve Online style)
	var left_panel = _create_left_panel()
	main_container.add_child(left_panel)
	
	# Right panel for settings content
	var right_panel = _create_right_panel()
	main_container.add_child(right_panel)

func _create_left_panel() -> Panel:
	var panel = Panel.new()
	panel.name = "CategoryPanel"
	panel.custom_minimum_size.x = 200
	
	# Eve Online dark panel style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08, 0.95)
	style.border_width_left = 1
	style.border_width_right = 2
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.3, 0.8)
	panel.add_theme_stylebox_override("panel", style)
	
	# Category list container
	var scroll = ScrollContainer.new()
	scroll.name = "CategoryScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	
	category_list = VBoxContainer.new()
	category_list.name = "CategoryList"
	category_list.add_theme_constant_override("separation", 2)
	scroll.add_child(category_list)
	
	return panel

func _create_right_panel() -> Panel:
	content_panel = Panel.new()
	content_panel.name = "ContentPanel"
	
	# Eve Online content panel style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.95)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.3, 0.8)
	content_panel.add_theme_stylebox_override("panel", style)
	
	# Content scroll container
	var scroll = ScrollContainer.new()
	scroll.name = "ContentScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.add_theme_constant_override("margin_left", 20)
	scroll.add_theme_constant_override("margin_right", 20)
	scroll.add_theme_constant_override("margin_top", 20)
	scroll.add_theme_constant_override("margin_bottom", 20)
	content_panel.add_child(scroll)
	
	content_container = VBoxContainer.new()
	content_container.name = "ContentContainer"
	content_container.add_theme_constant_override("separation", 15)
	scroll.add_child(content_container)
	
	return content_panel

func _populate_categories():
	for category in categories:
		var button = _create_category_button(category)
		category_list.add_child(button)
		category_buttons[category.id] = button

func _create_category_button(category: Dictionary) -> Button:
	var button = Button.new()
	button.name = category.id + "_button"
	button.text = category.name
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 40
	
	# Eve Online button styling
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.15, 0.15, 0.15, 0.8)
	normal_style.border_width_left = 1
	normal_style.border_width_right = 1
	normal_style.border_width_top = 1
	normal_style.border_width_bottom = 1
	normal_style.border_color = Color(0.25, 0.25, 0.25, 0.8)
	
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.25, 0.25, 0.25, 0.9)
	hover_style.border_width_left = 1
	hover_style.border_width_right = 1
	hover_style.border_width_top = 1
	hover_style.border_width_bottom = 1
	hover_style.border_color = Color(0.4, 0.4, 0.4, 0.9)
	
	var pressed_style = StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.2, 0.3, 0.5, 0.9)
	pressed_style.border_width_left = 2
	pressed_style.border_width_right = 2
	pressed_style.border_width_top = 2
	pressed_style.border_width_bottom = 2
	pressed_style.border_color = Color(0.3, 0.5, 0.8, 1.0)
	
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	
	button.pressed.connect(_on_category_selected.bind(category.id))
	
	return button

func _select_category(category_id: String):
	current_category = category_id
	_update_category_buttons()
	_populate_content(category_id)

func _update_category_buttons():
	for id in category_buttons.keys():
		var button = category_buttons[id]
		if id == current_category:
			button.button_pressed = true
		else:
			button.button_pressed = false

func _populate_content(category_id: String):
	# Clear existing content
	for child in content_container.get_children():
		child.queue_free()
	
	# Add category title
	var title = Label.new()
	title.text = _get_category_name(category_id)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	content_container.add_child(title)
	
	# Add settings for this category
	var settings = _get_settings_for_category(category_id)
	for setting in settings:
		var control = _create_setting_control(setting)
		content_container.add_child(control)
	
	# Add apply/reset buttons at bottom
	_add_action_buttons()

func _create_setting_control(setting: Dictionary) -> Control:
	var container = HBoxContainer.new()
	container.name = setting.id + "_container"
	container.add_theme_constant_override("separation", 20)
	
	# Setting label
	var label = Label.new()
	label.text = setting.name
	label.custom_minimum_size.x = 200
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
	container.add_child(label)
	
	# Setting control based on type
	var control: Control
	match setting.type:
		"checkbox":
			control = _create_checkbox_control(setting)
		"slider":
			control = _create_slider_control(setting)
		"dropdown":
			control = _create_dropdown_control(setting)
		_:
			control = Label.new()
			control.text = "Unknown setting type"
	
	container.add_child(control)
	settings_controls[setting.id] = control
	
	return container

func _create_checkbox_control(setting: Dictionary) -> CheckBox:
	var checkbox = CheckBox.new()
	checkbox.button_pressed = get_setting_value(setting.id, setting.default)
	
	# Fix the signal connection - pressed state comes first from the signal
	checkbox.toggled.connect(_on_checkbox_toggled.bind(setting.id))
	
	return checkbox

func _create_slider_control(setting: Dictionary) -> HBoxContainer:
	var container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 10)
	
	var slider = HSlider.new()
	slider.min_value = setting.min
	slider.max_value = setting.max
	slider.step = 0.01
	slider.value = get_setting_value(setting.id, setting.default)
	slider.custom_minimum_size.x = 200
	
	var value_label = Label.new()
	var format = setting.get("format", "percentage")
	
	match format:
		"percentage":
			value_label.text = str(int(slider.value * 100)) + "%"
		"decimal":
			value_label.text = "%.2f" % slider.value
		_:
			value_label.text = str(slider.value)
	
	value_label.custom_minimum_size.x = 50
	value_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
	
	# Fix the signal connection - value comes first from the signal
	slider.value_changed.connect(_on_slider_value_changed.bind(setting.id, value_label, format))
	
	container.add_child(slider)
	container.add_child(value_label)
	
	return container

func _create_dropdown_control(setting: Dictionary) -> OptionButton:
	var dropdown = OptionButton.new()
	dropdown.custom_minimum_size.x = 200
	
	# Add options
	for option in setting.options:
		dropdown.add_item(option)
	
	# Set current value
	var current_value = get_setting_value(setting.id, setting.default)
	
	# Special handling for max_fps display
	var display_value = current_value
	if setting.id == "max_fps" and current_value == 0:
		display_value = "Unlimited"
	
	var index = setting.options.find(str(display_value))
	if index >= 0:
		dropdown.selected = index
	
	# Connect the signal correctly - index comes first from the signal
	if setting.id in ["resolution", "window_mode", "vsync_mode", "quality_preset"]:
		dropdown.item_selected.connect(_on_graphics_dropdown_selected.bind(setting.id, setting.options))
	else:
		dropdown.item_selected.connect(_on_regular_dropdown_selected.bind(setting.id, setting.options))
	
	return dropdown

func _add_action_buttons():
	var separator = HSeparator.new()
	separator.add_theme_constant_override("separation", 20)
	content_container.add_child(separator)
	
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 20)
	content_container.add_child(button_container)
	
	# Apply button
	var apply_button = Button.new()
	apply_button.text = "Apply"
	apply_button.custom_minimum_size = Vector2(100, 35)
	apply_button.pressed.connect(_on_apply_pressed)
	button_container.add_child(apply_button)
	
	# Reset button
	var reset_button = Button.new()
	reset_button.text = "Reset to Defaults"
	reset_button.custom_minimum_size = Vector2(150, 35)
	reset_button.pressed.connect(_on_reset_pressed)
	button_container.add_child(reset_button)
	
	# Close button
	var close_button = Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(100, 35)
	close_button.pressed.connect(_on_close_pressed)
	button_container.add_child(close_button)

func _get_category_name(category_id: String) -> String:
	for category in categories:
		if category.id == category_id:
			return category.name
	return "Unknown"

func _get_graphics_settings() -> Array[Dictionary]:
	if not graphics_manager:
		return []
	
	return [
		{
			"id": "resolution",
			"name": "Resolution",
			"type": "dropdown",
			"options": graphics_manager.get_available_resolutions(),
			"default": "1920x1080"
		},
		{
			"id": "window_mode",
			"name": "Window Mode",
			"type": "dropdown",
			"options": graphics_manager.get_available_window_modes(),
			"default": "Windowed"
		},
		{
			"id": "vsync_mode",
			"name": "V-Sync Mode",
			"type": "dropdown",
			"options": graphics_manager.get_available_vsync_modes(),
			"default": "Enabled"
		},
		{
			"id": "quality_preset",
			"name": "Quality Preset",
			"type": "dropdown",
			"options": graphics_manager.get_available_quality_presets(),
			"default": "High"
		},
		{
			"id": "render_scale",
			"name": "Render Scale",
			"type": "slider",
			"min": 0.25,
			"max": 2.0,
			"default": 1.0,
			"format": "percentage"
		},
		{
			"id": "max_fps",
			"name": "Max FPS",
			"type": "dropdown",
			"options": ["Unlimited", "30", "60", "75", "90", "120", "144", "165", "240"],
			"default": "Unlimited"
		}
	]

func _get_settings_for_category(category_id: String) -> Array:
	match category_id:
		"graphics":
			return _get_graphics_settings()
		"audio":
			return audio_settings
		"gameplay":
			return gameplay_settings
		"controls":
			return []
		_:
			return []

func _setup_graphics_manager():
	"""Setup graphics manager"""
	graphics_manager = GraphicsManager.new()
	graphics_manager.name = "GraphicsManager"
	add_child(graphics_manager)
	
	# Connect signals
	graphics_manager.settings_changed.connect(_on_graphics_setting_changed)
	graphics_manager.settings_applied.connect(_on_graphics_settings_applied)

# Signal handlers
func _on_category_selected(category_id: String):
	_select_category(category_id)

func _on_setting_changed(setting_id: String, value):
	settings_data[setting_id] = value
	settings_changed.emit(setting_id, value)

func _on_slider_value_changed(value: float, setting_id: String, label: Label, format: String):
	set_setting_value(setting_id, value)
	
	match format:
		"percentage":
			label.text = str(int(value * 100)) + "%"
		"decimal":
			label.text = "%.2f" % value
		_:
			label.text = str(value)
	
	settings_changed.emit(setting_id, value)

func _on_dropdown_changed(setting_id: String, options: Array, index: int):
	# Convert index to the actual option value
	if index >= 0 and index < options.size():
		var value = options[index]
		
		# Special handling for max_fps
		if setting_id == "max_fps":
			if value == "Unlimited":
				value = 0
			else:
				value = int(value)
		
		set_setting_value(setting_id, value)
		settings_changed.emit(setting_id, value)
	else:
		push_error("Invalid dropdown index: " + str(index) + " for setting: " + setting_id)

func _on_apply_pressed():
	if graphics_manager:
		graphics_manager.apply_all_settings()
		graphics_manager.save_settings()
	
	_save_settings()
	_apply_audio_settings()
	_apply_gameplay_settings()
	
	settings_applied.emit()

func _on_checkbox_toggled(pressed: bool, setting_id: String):
	set_setting_value(setting_id, pressed)
	settings_changed.emit(setting_id, pressed)

func _apply_audio_settings():
	"""Apply audio settings"""
	var master_volume = settings_data.get("master_volume", 0.8)
	var music_volume = settings_data.get("music_volume", 0.6)
	var sfx_volume = settings_data.get("sfx_volume", 0.8)
	
	# Apply audio settings to your audio buses
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(master_volume))
	if AudioServer.get_bus_index("Music") >= 0:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(music_volume))
	if AudioServer.get_bus_index("SFX") >= 0:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(sfx_volume))

func _apply_gameplay_settings():
	"""Apply gameplay settings"""
	# Add gameplay setting applications here as needed
	var mouse_sensitivity = settings_data.get("mouse_sensitivity", 1.0)
	# Apply mouse sensitivity to your player controller, etc.

func _on_reset_pressed():
	if graphics_manager:
		graphics_manager.reset_to_defaults()
	
	_reset_to_defaults()
	_refresh_controls()

func _on_close_pressed():
	settings_closed.emit()

func _on_graphics_setting_changed(setting_name: String, value):
	print("Graphics setting changed: ", setting_name, " = ", value)

func _on_graphics_settings_applied():
	print("Graphics settings applied!")

func _on_graphics_dropdown_changed(setting_id: String, options: Array, index: int):
	"""Handle graphics dropdown changes - store but don't apply immediately"""
	if index >= 0 and index < options.size():
		var value = options[index]
		
		# Special handling for max_fps
		if setting_id == "max_fps":
			if value == "Unlimited":
				value = 0
			else:
				value = int(value)
		
		# Only store in settings data, don't call graphics manager functions
		if graphics_manager:
			graphics_manager.current_settings[setting_id] = value
		
		print("Graphics setting queued: ", setting_id, " = ", value)

func _on_graphics_dropdown_selected(index: int, setting_id: String, options: Array):
	"""Handle graphics dropdown changes - store but don't apply immediately"""
	if index >= 0 and index < options.size():
		var value = options[index]
		
		# Special handling for max_fps
		if setting_id == "max_fps":
			if value == "Unlimited":
				value = 0
			else:
				value = int(value)
		
		# Only store in settings data, don't call graphics manager functions
		if graphics_manager:
			graphics_manager.current_settings[setting_id] = value

func _on_regular_dropdown_selected(index: int, setting_id: String, options: Array):
	"""Handle regular dropdown changes"""
	if index >= 0 and index < options.size():
		var value = options[index]
		
		# Special handling for max_fps
		if setting_id == "max_fps":
			if value == "Unlimited":
				value = 0
			else:
				value = int(value)
		
		set_setting_value(setting_id, value)
		settings_changed.emit(setting_id, value)

# Settings persistence
func _save_settings():
	var config = ConfigFile.new()
	
	# Only save NON-graphics settings (audio and gameplay)
	for setting in audio_settings:
		if settings_data.has(setting.id):
			config.set_value("audio", setting.id, settings_data[setting.id])
	
	for setting in gameplay_settings:
		if settings_data.has(setting.id):
			config.set_value("gameplay", setting.id, settings_data[setting.id])
	
	# Don't save graphics settings here - GraphicsManager handles those
	config.save("user://settings.cfg")

func _load_settings():
	# Load from user://settings.cfg but ONLY for audio/gameplay
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	
	if err == OK:
		# Only load audio and gameplay settings
		for setting in audio_settings + gameplay_settings:
			settings_data[setting.id] = config.get_value("audio", setting.id, setting.default)
			if not settings_data.has(setting.id):
				settings_data[setting.id] = config.get_value("gameplay", setting.id, setting.default)

func _reset_to_defaults():
	settings_data.clear()
	
	# Reset to defaults
	for setting in graphics_settings + audio_settings + gameplay_settings:
		settings_data[setting.id] = setting.default

func _refresh_controls():
	# Refresh all setting controls with current values
	for setting_id in settings_controls.keys():
		var control = settings_controls[setting_id]
		var value = settings_data.get(setting_id, null)
		
		if value != null:
			if control is CheckBox:
				control.button_pressed = value
			elif control is HSlider:
				control.value = value
			elif control is OptionButton:
				# Find the option and select it
				for i in control.get_item_count():
					if control.get_item_text(i) == str(value):
						control.selected = i
						break

# Public methods
func show_settings():
	visible = true

func hide_settings():
	visible = false

func get_setting_value(setting_id: String, default_value):
	"""Get setting value from graphics manager or settings data"""
	if graphics_manager and setting_id in ["resolution", "window_mode", "vsync_mode", "quality_preset", "render_scale", "max_fps"]:
		return graphics_manager.get_current_setting(setting_id, default_value)
	else:
		return settings_data.get(setting_id, default_value)

func set_setting_value(setting_id: String, value):
	"""Set setting value in graphics manager or settings data"""
	if graphics_manager and setting_id in ["resolution", "window_mode", "vsync_mode", "quality_preset", "render_scale", "max_fps"]:
		graphics_manager.current_settings[setting_id] = value
	else:
		settings_data[setting_id] = value