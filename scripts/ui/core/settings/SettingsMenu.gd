# SettingsMenu.gd
class_name SettingsMenu
extends Control

# UI References
var main_container: Panel  
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

# Compact settings configuration
var settings_width: int = 800
var settings_height: int = 600

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

func _setup_graphics_manager():
	graphics_manager = GraphicsManager.new()
	add_child(graphics_manager)
	graphics_manager.settings_changed.connect(_on_graphics_setting_changed)

func _create_ui():
	# Create a background panel to center the settings window
	var background = Panel.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Semi-transparent background
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0.5)
	background.add_theme_stylebox_override("panel", bg_style)
	add_child(background)
	
	# Main window container
	var main_window = Panel.new()
	main_window.name = "MainWindow"
	main_window.size = Vector2(settings_width, settings_height)
	main_window.position = (get_viewport().get_visible_rect().size - main_window.size) / 2
	
	# Window styling
	var window_style = StyleBoxFlat.new()
	window_style.bg_color = Color(0.1, 0.1, 0.1, 0.95)
	window_style.border_width_left = 2
	window_style.border_width_right = 2
	window_style.border_width_top = 2
	window_style.border_width_bottom = 2
	window_style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	window_style.shadow_color = Color(0, 0, 0, 0.6)
	window_style.shadow_size = 8
	window_style.shadow_offset = Vector2(4, 4)
	main_window.add_theme_stylebox_override("panel", window_style)
	
	add_child(main_window)
	main_container = main_window  # Update reference
	
	# Title bar
	var title_container = HBoxContainer.new()
	title_container.name = "TitleContainer"
	title_container.position = Vector2(15, 10)
	title_container.size = Vector2(settings_width - 30, 40)
	title_container.add_theme_constant_override("separation", 15)
	main_window.add_child(title_container)
	
	var title_label = Label.new()
	title_label.text = "Settings"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_container.add_child(title_label)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_container.add_child(spacer)
	
	var back_button = Button.new()
	back_button.text = "← Back"
	back_button.custom_minimum_size = Vector2(80, 35)
	back_button.add_theme_font_size_override("font_size", 14)

	# Style the back button
	var back_style = StyleBoxFlat.new()
	back_style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	back_style.border_width_left = 1
	back_style.border_width_right = 1
	back_style.border_width_top = 1
	back_style.border_width_bottom = 1
	back_style.border_color = Color(0.4, 0.4, 0.5, 1.0)
	back_style.corner_radius_top_left = 4
	back_style.corner_radius_top_right = 4
	back_style.corner_radius_bottom_left = 4
	back_style.corner_radius_bottom_right = 4
	back_button.add_theme_stylebox_override("normal", back_style)
	back_button.add_theme_color_override("font_color", Color.WHITE)

	back_button.pressed.connect(_on_back_pressed)
	title_container.add_child(back_button)
	
	# Left panel - fixed position and size
	var left_panel = _create_left_panel()
	left_panel.position = Vector2(10, 60)
	left_panel.size = Vector2(180, settings_height - 80)
	main_window.add_child(left_panel)
	
	# Right panel - fills remaining space
	var right_panel = _create_right_panel()
	right_panel.position = Vector2(200, 60)  # 10 margin + 180 width + 10 gap
	right_panel.size = Vector2(settings_width - 220, settings_height - 80)  # Remaining width
	main_window.add_child(right_panel)

func _create_left_panel() -> Panel:
	var panel = Panel.new()
	panel.name = "CategoryPanel"
	
	# Styling
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08, 0.95)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.3, 0.8)
	panel.add_theme_stylebox_override("panel", style)
	
	# Margin container for padding
	var margin_container = MarginContainer.new()
	margin_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_left", 15)
	margin_container.add_theme_constant_override("margin_right", 15)
	margin_container.add_theme_constant_override("margin_top", 15)
	margin_container.add_theme_constant_override("margin_bottom", 15)
	panel.add_child(margin_container)
	
	# Center container for buttons
	var center_container = VBoxContainer.new()
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_container.alignment = BoxContainer.ALIGNMENT_CENTER
	margin_container.add_child(center_container)
	
	# Button list
	category_list = VBoxContainer.new()
	category_list.name = "CategoryList"
	category_list.add_theme_constant_override("separation", 12)
	category_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	category_list.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center_container.add_child(category_list)
	
	return panel
	
func _create_right_panel() -> Panel:
	content_panel = Panel.new()
	content_panel.name = "ContentPanel"
	
	# Styling
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.95)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.3, 0.8)
	content_panel.add_theme_stylebox_override("panel", style)
	
	# Margin container for padding
	var margin_container = MarginContainer.new()
	margin_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_left", 20)
	margin_container.add_theme_constant_override("margin_right", 20)
	margin_container.add_theme_constant_override("margin_top", 15)
	margin_container.add_theme_constant_override("margin_bottom", 20)
	content_panel.add_child(margin_container)
	
	# Scroll container
	var scroll = ScrollContainer.new()
	scroll.name = "ContentScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_container.add_child(scroll)
	
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
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER  # Center the text
	button.custom_minimum_size.y = 45  # Taller buttons
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # Full width
	
	# Much more visible button styling
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.2, 0.2, 0.25, 0.95)  # Lighter background
	normal_style.border_width_left = 2
	normal_style.border_width_right = 2
	normal_style.border_width_top = 2
	normal_style.border_width_bottom = 2
	normal_style.border_color = Color(0.4, 0.4, 0.5, 1.0)  # More visible border
	normal_style.corner_radius_top_left = 6
	normal_style.corner_radius_top_right = 6
	normal_style.corner_radius_bottom_left = 6
	normal_style.corner_radius_bottom_right = 6
	normal_style.content_margin_left = 15
	normal_style.content_margin_right = 15
	normal_style.content_margin_top = 10
	normal_style.content_margin_bottom = 10
	
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.3, 0.35, 0.4, 1.0)  # Bright hover
	hover_style.border_width_left = 2
	hover_style.border_width_right = 2
	hover_style.border_width_top = 2
	hover_style.border_width_bottom = 2
	hover_style.border_color = Color(0.5, 0.6, 0.7, 1.0)
	hover_style.corner_radius_top_left = 6
	hover_style.corner_radius_top_right = 6
	hover_style.corner_radius_bottom_left = 6
	hover_style.corner_radius_bottom_right = 6
	hover_style.content_margin_left = 15
	hover_style.content_margin_right = 15
	hover_style.content_margin_top = 10
	hover_style.content_margin_bottom = 10
	
	var pressed_style = StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.3, 0.5, 0.8, 1.0)  # Bright selected color
	pressed_style.border_width_left = 3
	pressed_style.border_width_right = 3
	pressed_style.border_width_top = 3
	pressed_style.border_width_bottom = 3
	pressed_style.border_color = Color(0.4, 0.7, 1.0, 1.0)  # Bright blue border
	pressed_style.corner_radius_top_left = 6
	pressed_style.corner_radius_top_right = 6
	pressed_style.corner_radius_bottom_left = 6
	pressed_style.corner_radius_bottom_right = 6
	pressed_style.content_margin_left = 15
	pressed_style.content_margin_right = 15
	pressed_style.content_margin_top = 10
	pressed_style.content_margin_bottom = 10
	
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("focus", pressed_style)  # Same as pressed for focus
	
	# Better text styling
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 14)
	
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
	
	# Add category title with padding
	var title = Label.new()
	title.text = _get_category_name(category_id)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	title.add_theme_constant_override("margin_bottom", 10)
	content_container.add_child(title)
	
	# Add settings for this category
	var settings = _get_settings_for_category(category_id)
	for setting in settings:
		var control = _create_setting_control(setting)
		content_container.add_child(control)
	
	# Add apply/reset buttons at bottom with extra spacing
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 20
	content_container.add_child(spacer)
	
	_add_action_buttons()

func _create_setting_control(setting: Dictionary) -> Control:
	var outer_container = VBoxContainer.new()
	outer_container.name = setting.id + "_outer_container"
	outer_container.add_theme_constant_override("separation", 8)
	
	# Create main setting container
	var container = HBoxContainer.new()
	container.name = setting.id + "_container"
	container.add_theme_constant_override("separation", 25)
	container.custom_minimum_size.y = 35  # Ensure minimum height for padding
	
	# Setting label with padding
	var label = Label.new()
	label.text = setting.name
	label.custom_minimum_size.x = 200
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
	
	outer_container.add_child(container)
	
	# Add subtle separator between settings
	var separator = Panel.new()
	separator.custom_minimum_size.y = 1
	separator.modulate = Color(0.3, 0.3, 0.3, 0.5)
	var separator_style = StyleBoxFlat.new()
	separator_style.bg_color = Color(0.3, 0.3, 0.3, 0.3)
	separator.add_theme_stylebox_override("panel", separator_style)
	outer_container.add_child(separator)
	
	return outer_container

func _create_checkbox_control(setting: Dictionary) -> CheckBox:
	var checkbox = CheckBox.new()
	checkbox.button_pressed = get_setting_value(setting.id, setting.default)
	checkbox.custom_minimum_size.y = 30
	checkbox.toggled.connect(_on_checkbox_toggled.bind(setting.id))
	return checkbox

func _create_slider_control(setting: Dictionary) -> HBoxContainer:
	var container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 15)
	
	var slider = HSlider.new()
	slider.min_value = setting.min
	slider.max_value = setting.max
	slider.step = 0.01
	slider.value = get_setting_value(setting.id, setting.default)
	slider.custom_minimum_size.x = 220
	slider.custom_minimum_size.y = 30
	
	var value_label = Label.new()
	var format = setting.get("format", "percentage")
	
	match format:
		"percentage":
			value_label.text = str(int(slider.value * 100)) + "%"
		"decimal":
			value_label.text = "%.2f" % slider.value
		_:
			value_label.text = str(slider.value)
	
	value_label.custom_minimum_size.x = 60
	value_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	slider.value_changed.connect(_on_slider_changed.bind(setting.id, value_label, format))
	
	container.add_child(slider)
	container.add_child(value_label)
	
	return container

func _create_dropdown_control(setting: Dictionary) -> OptionButton:
	var dropdown = OptionButton.new()
	dropdown.custom_minimum_size.x = 220
	dropdown.custom_minimum_size.y = 35
	
	# Add padding to dropdown style
	var dropdown_style = StyleBoxFlat.new()
	dropdown_style.content_margin_left = 8
	dropdown_style.content_margin_right = 8
	dropdown_style.content_margin_top = 6
	dropdown_style.content_margin_bottom = 6
	dropdown.add_theme_stylebox_override("normal", dropdown_style)
	
	for option in setting.options:
		dropdown.add_item(option)
	
	var current_value = get_setting_value(setting.id, setting.default)
	for i in range(dropdown.get_item_count()):
		if dropdown.get_item_text(i) == str(current_value):
			dropdown.selected = i
			break
	
	dropdown.item_selected.connect(_on_dropdown_selected.bind(setting.id))
	
	return dropdown

func _add_action_buttons():
	var button_container = HBoxContainer.new()
	button_container.name = "ActionButtons"
	button_container.add_theme_constant_override("separation", 15)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_container.add_child(spacer)
	
	var apply_button = Button.new()
	apply_button.text = "Apply"
	apply_button.custom_minimum_size = Vector2(90, 40)
	apply_button.pressed.connect(_on_apply_pressed)
	button_container.add_child(apply_button)
	
	var reset_button = Button.new()
	reset_button.text = "Reset" 
	reset_button.custom_minimum_size = Vector2(90, 40)
	reset_button.pressed.connect(_on_reset_pressed)
	button_container.add_child(reset_button)
	
	content_container.add_child(button_container)

func _get_category_name(category_id: String) -> String:
	for category in categories:
		if category.id == category_id:
			return category.name
	return "Unknown"

func _get_settings_for_category(category_id: String) -> Array[Dictionary]:
	match category_id:
		"graphics":
			return graphics_settings
		"audio":
			return audio_settings
		"gameplay":
			return gameplay_settings
		"controls":
			return []  # Add controls settings if needed
		_:
			return []

# Signal handlers
func _on_category_selected(category_id: String):
	_select_category(category_id)

func _on_checkbox_toggled(checked: bool, setting_id: String):
	set_setting_value(setting_id, checked)
	settings_changed.emit(setting_id, checked)

func _on_slider_changed(value: float, setting_id: String, value_label: Label, format: String):
	match format:
		"percentage":
			value_label.text = str(int(value * 100)) + "%"
		"decimal":
			value_label.text = "%.2f" % value
		_:
			value_label.text = str(value)
	
	set_setting_value(setting_id, value)
	settings_changed.emit(setting_id, value)

func _on_dropdown_selected(index: int, setting_id: String):
	var dropdown = settings_controls[setting_id]
	var value = dropdown.get_item_text(index)
	
	# Handle special cases for graphics settings
	if setting_id == "max_fps":
		if value == "Unlimited":
			value = 0
		else:
			value = int(value)
	
	set_setting_value(setting_id, value)
	settings_changed.emit(setting_id, value)

func _on_apply_pressed():
	_save_settings()
	settings_applied.emit()

func _on_reset_pressed():
	_reset_to_defaults()
	_refresh_controls()

func _on_close_pressed():
	settings_closed.emit()
	hide()

func _on_back_pressed():
	settings_closed.emit()
	hide()

func _on_graphics_setting_changed(setting_id: String, value):
	# Handle graphics manager setting changes
	if setting_id in settings_controls:
		var control = settings_controls[setting_id]
		if control is CheckBox:
			control.button_pressed = value
		elif control is HSlider:
			control.value = value
		elif control is OptionButton:
			for i in control.get_item_count():
				if control.get_item_text(i) == str(value):
					control.selected = i
					break

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
	
	# Graphics settings are handled by GraphicsManager
	config.save("user://settings.cfg")

func _load_settings():
	# Load from user://settings.cfg but ONLY for audio/gameplay
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	
	if err == OK:
		# Only load audio and gameplay settings
		for setting in audio_settings + gameplay_settings:
			var section = "audio" if setting in audio_settings else "gameplay"
			settings_data[setting.id] = config.get_value(section, setting.id, setting.default)
	else:
		# Initialize with defaults if no config file
		for setting in audio_settings + gameplay_settings:
			settings_data[setting.id] = setting.default

func _reset_to_defaults():
	settings_data.clear()
	
	# Reset to defaults
	for setting in graphics_settings + audio_settings + gameplay_settings:
		settings_data[setting.id] = setting.default
	
	# Reset graphics manager if available
	if graphics_manager:
		graphics_manager.reset_to_defaults()

func _refresh_controls():
	# Refresh all setting controls with current values
	for setting_id in settings_controls.keys():
		var control = settings_controls[setting_id]
		var value = get_setting_value(setting_id, null)
		
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

# Handle window resize to keep settings centered
func _notification(what):
	if what == NOTIFICATION_RESIZED and main_container:
		main_container.position = (get_viewport().get_visible_rect().size - main_container.size) / 2

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