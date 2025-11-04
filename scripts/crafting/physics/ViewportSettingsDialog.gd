class_name ViewportSettingsDialog
extends DialogWindow_Base

## Dialog for configuring viewport settings like grid size, gizmo scale, and background color

signal settings_changed(grid_size: float, gizmo_scale: float, background_color: Color)

# UI Controls
var grid_size_spinbox: SpinBox
var gizmo_scale_spinbox: SpinBox
var background_color_picker: ColorPickerButton

# Current settings
var current_grid_size: float = 1.0
var current_gizmo_scale: float = 1.5
var current_background_color: Color = Color(0.2, 0.2, 0.25, 1.0)


func _init(grid_size: float = 1.0, gizmo_scale: float = 1.5, bg_color: Color = Color(0.2, 0.2, 0.25, 1.0)):
	super._init("Viewport Settings", Vector2(400, 280))

	current_grid_size = grid_size
	current_gizmo_scale = gizmo_scale
	current_background_color = bg_color


func _ready():
	super._ready()

	# Disable focus-related visual effects
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Wait for dialog content to be ready
	if not is_node_ready():
		await ready

	_setup_window_content()

	# Wait one more frame to ensure all components are initialized
	await get_tree().process_frame

	if not dialog_content:
		push_error("ViewportSettingsDialog: Dialog content not initialized!")
		return

	_build_settings_ui()


func _build_settings_ui():
	"""Build the settings UI controls"""

	# Create main content container with proper spacing
	var content_container = VBoxContainer.new()
	content_container.add_theme_constant_override("separation", 15)

	# Grid Size Setting
	var grid_size_container = _create_setting_row("Grid Size:", current_grid_size, 0.1, 10.0, 0.1)
	grid_size_spinbox = grid_size_container.get_node("SpinBox") as SpinBox
	content_container.add_child(grid_size_container)

	# Gizmo Scale Setting
	var gizmo_scale_container = _create_setting_row("Gizmo Scale:", current_gizmo_scale, 0.5, 5.0, 0.1)
	gizmo_scale_spinbox = gizmo_scale_container.get_node("SpinBox") as SpinBox
	content_container.add_child(gizmo_scale_container)

	# Background Color Setting
	var color_container = HBoxContainer.new()
	color_container.add_theme_constant_override("separation", 10)

	var color_label = Label.new()
	color_label.text = "Background Color:"
	color_label.custom_minimum_size = Vector2(150, 0)
	color_container.add_child(color_label)

	background_color_picker = ColorPickerButton.new()
	background_color_picker.color = current_background_color
	background_color_picker.custom_minimum_size = Vector2(100, 30)
	background_color_picker.edit_alpha = true
	color_container.add_child(background_color_picker)

	content_container.add_child(color_container)

	# Add spacer to push buttons to bottom
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	content_container.add_child(spacer)

	# Add content to dialog
	add_dialog_content(content_container)

	# Add Apply, Close, and Cancel buttons
	var apply_button = add_button("Apply", _on_apply_pressed)
	apply_button.custom_minimum_size = Vector2(80, 35)
	apply_button.focus_mode = Control.FOCUS_NONE

	var close_apply_button = add_button("Close", _on_close_pressed)
	close_apply_button.custom_minimum_size = Vector2(80, 35)
	close_apply_button.focus_mode = Control.FOCUS_NONE

	var cancel_button = add_button("Cancel", _on_cancel_pressed)
	cancel_button.custom_minimum_size = Vector2(80, 35)
	cancel_button.focus_mode = Control.FOCUS_NONE


func _create_setting_row(label_text: String, default_value: float, min_val: float, max_val: float, step_val: float) -> HBoxContainer:
	"""Create a setting row with label and spinbox"""
	var container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 10)

	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(150, 0)
	container.add_child(label)

	var spinbox = SpinBox.new()
	spinbox.name = "SpinBox"
	spinbox.min_value = min_val
	spinbox.max_value = max_val
	spinbox.step = step_val
	spinbox.value = default_value
	spinbox.custom_minimum_size = Vector2(120, 30)
	spinbox.alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(spinbox)

	return container


func _on_apply_pressed():
	"""Apply the settings without closing the dialog"""
	var new_grid_size = grid_size_spinbox.value if grid_size_spinbox else current_grid_size
	var new_gizmo_scale = gizmo_scale_spinbox.value if gizmo_scale_spinbox else current_gizmo_scale
	var new_bg_color = background_color_picker.color if background_color_picker else current_background_color

	print("ViewportSettingsDialog: Apply button pressed, emitting settings_changed")

	# Emit the settings changed signal
	settings_changed.emit(new_grid_size, new_gizmo_scale, new_bg_color)

	# Update current settings to reflect the applied values
	current_grid_size = new_grid_size
	current_gizmo_scale = new_gizmo_scale
	current_background_color = new_bg_color


func _on_close_pressed():
	"""Apply the settings and close the dialog"""
	var new_grid_size = grid_size_spinbox.value if grid_size_spinbox else current_grid_size
	var new_gizmo_scale = gizmo_scale_spinbox.value if gizmo_scale_spinbox else current_gizmo_scale
	var new_bg_color = background_color_picker.color if background_color_picker else current_background_color

	print("ViewportSettingsDialog: Close button pressed, applying settings and closing")

	# Emit the settings changed signal
	settings_changed.emit(new_grid_size, new_gizmo_scale, new_bg_color)

	# Emit the dialog closed signal
	dialog_closed.emit()

	# Defer the close to ensure signal handlers complete
	call_deferred("close_dialog")


func _on_cancel_pressed():
	"""Close the dialog without applying changes"""
	print("ViewportSettingsDialog: Cancel button pressed, emitting dialog_cancelled")
	# Emit cancelled signal (dialog_cancelled is from DialogWindow_Base)
	dialog_cancelled.emit()
	# Defer the close to ensure signal handlers complete
	call_deferred("close_dialog")
