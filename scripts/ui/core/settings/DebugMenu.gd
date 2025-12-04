# DebugMenu.gd
class_name DebugMenu
extends Control

# Signals
signal debug_menu_closed

# UI References
var main_container: Panel
var content_container: VBoxContainer
var debug_manager: Node

# Settings controls
var settings_controls: Dictionary = {}

# Compact menu configuration
var menu_width: int = 600
var menu_height: int = 400


func _ready():
	_setup_debug_manager()
	_create_ui()
	_populate_debug_settings()


func _setup_debug_manager():
	# Get the DebugManager singleton (autoload)
	debug_manager = get_node("/root/DebugManager")
	if debug_manager:
		debug_manager.settings_changed.connect(_on_debug_setting_changed)


func _create_ui():
	# Create a background panel to center the debug window
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
	main_window.size = Vector2(menu_width, menu_height)
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
	main_container = main_window

	# Title bar
	var title_container = HBoxContainer.new()
	title_container.name = "TitleContainer"
	title_container.position = Vector2(15, 10)
	title_container.size = Vector2(menu_width - 30, 40)
	title_container.add_theme_constant_override("separation", 15)
	main_window.add_child(title_container)

	var title_label = Label.new()
	title_label.text = "Debug Settings"
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

	# Content panel
	var content_panel = Panel.new()
	content_panel.name = "ContentPanel"
	content_panel.position = Vector2(10, 60)
	content_panel.size = Vector2(menu_width - 20, menu_height - 80)

	# Styling
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.95)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.3, 0.8)
	content_panel.add_theme_stylebox_override("panel", style)
	main_window.add_child(content_panel)

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


func _populate_debug_settings():
	# Clear existing content
	for child in content_container.get_children():
		child.queue_free()

	settings_controls.clear()

	# Add debug settings title
	var title = Label.new()
	title.text = "Debug Visualization"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	title.add_theme_constant_override("margin_bottom", 10)
	content_container.add_child(title)

	# Get debug settings from DebugManager
	var debug_settings = [
		{
			"id": "show_chunk_overlay",
			"name": "Show Chunk Overlay",
			"type": "checkbox",
			"default": false,
			"description": "Display chunk grid on map and minimap"
		},
		{
			"id": "show_tree_debug",
			"name": "Show Tree Debug",
			"type": "checkbox",
			"default": false,
			"description": "Display tree positions on minimap (expensive!)"
		},
		{
			"id": "show_performance_stats",
			"name": "Show Performance Stats",
			"type": "checkbox",
			"default": false,
			"description": "Display FPS and performance metrics"
		}
	]

	# Create controls for each setting
	for setting in debug_settings:
		var control = _create_setting_control(setting)
		content_container.add_child(control)

	# Add apply/reset buttons at bottom
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
	container.custom_minimum_size.y = 35

	# Setting label
	var label = Label.new()
	label.text = setting.name
	label.custom_minimum_size.x = 200
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	container.add_child(label)

	# Setting control (checkbox for now)
	var checkbox = CheckBox.new()
	checkbox.button_pressed = debug_manager.get_current_setting(setting.id, setting.default)
	checkbox.custom_minimum_size.y = 10
	checkbox.custom_minimum_size.x = 20

	# Apply checkbox styling
	_apply_checkbox_styling(checkbox)

	checkbox.toggled.connect(_on_checkbox_toggled.bind(setting.id))
	settings_controls[setting.id] = checkbox

	container.add_child(checkbox)

	outer_container.add_child(container)

	# Add description if available
	if setting.has("description"):
		var desc_label = Label.new()
		desc_label.text = setting.description
		desc_label.add_theme_font_size_override("font_size", 11)
		desc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		outer_container.add_child(desc_label)

	# Add separator
	var separator = Panel.new()
	separator.custom_minimum_size.y = 1
	separator.modulate = Color(0.3, 0.3, 0.3, 0.5)
	var separator_style = StyleBoxFlat.new()
	separator_style.bg_color = Color(0.3, 0.3, 0.3, 0.3)
	separator.add_theme_stylebox_override("panel", separator_style)
	outer_container.add_child(separator)

	return outer_container


func _apply_checkbox_styling(checkbox: CheckBox):
	"""Apply custom styling to make checkboxes more visible"""
	# Create normal (unchecked) style
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.2, 0.2, 0.2, 0.9)
	normal_style.border_width_left = 2
	normal_style.border_width_right = 2
	normal_style.border_width_top = 2
	normal_style.border_width_bottom = 2
	normal_style.border_color = Color(0.5, 0.5, 0.5, 1.0)

	# Create checked style
	var checked_style = StyleBoxFlat.new()
	checked_style.bg_color = Color(0.3, 0.6, 0.9, 1.0)
	checked_style.border_width_left = 2
	checked_style.border_width_right = 2
	checked_style.border_width_top = 2
	checked_style.border_width_bottom = 2
	checked_style.border_color = Color(0.4, 0.7, 1.0, 1.0)

	# Create hover style
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.3, 0.3, 0.3, 0.9)
	hover_style.border_width_left = 2
	hover_style.border_width_right = 2
	hover_style.border_width_top = 2
	hover_style.border_width_bottom = 2
	hover_style.border_color = Color(0.7, 0.7, 0.7, 1.0)

	# Apply the styles
	checkbox.add_theme_stylebox_override("normal", normal_style)
	checkbox.add_theme_stylebox_override("pressed", checked_style)
	checkbox.add_theme_stylebox_override("hover", hover_style)
	checkbox.add_theme_stylebox_override("hover_pressed", checked_style)

	# Set text color
	checkbox.add_theme_color_override("font_color", Color.WHITE)
	checkbox.add_theme_color_override("font_hover_color", Color.WHITE)
	checkbox.add_theme_color_override("font_pressed_color", Color.WHITE)


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


# Signal handlers
func _on_checkbox_toggled(checked: bool, setting_id: String):
	# Update the setting in DebugManager
	if debug_manager:
		debug_manager.set_setting(setting_id, checked)


func _on_apply_pressed():
	# Apply and save debug settings
	if debug_manager:
		debug_manager.apply_all_settings()
		debug_manager.save_settings()
	print("Debug settings applied successfully")


func _on_reset_pressed():
	# Reset to defaults
	if debug_manager:
		debug_manager.reset_to_defaults()
	_refresh_controls()


func _on_back_pressed():
	debug_menu_closed.emit()
	hide()


func _on_debug_setting_changed(setting_id: String, value):
	# Update control when setting changes externally
	if setting_id in settings_controls:
		var control = settings_controls[setting_id]

		# Check if control is still valid
		if not is_instance_valid(control):
			settings_controls.erase(setting_id)
			return

		if control is CheckBox:
			control.button_pressed = value


func _refresh_controls():
	# Refresh all setting controls with current values
	for setting_id in settings_controls.keys():
		var control = settings_controls[setting_id]

		if not is_instance_valid(control):
			continue

		var value = debug_manager.get_current_setting(setting_id, false)

		if control is CheckBox:
			control.button_pressed = value


# Handle window resize to keep menu centered
func _notification(what):
	if what == NOTIFICATION_RESIZED and main_container:
		main_container.position = (get_viewport().get_visible_rect().size - main_container.size) / 2


# Public methods
func show_debug_menu():
	visible = true


func hide_debug_menu():
	visible = false
