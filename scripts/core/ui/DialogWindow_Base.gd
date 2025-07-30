# DialogWindow.gd - Base dialog class that inherits from CustomWindow
class_name DialogWindow_Base
extends Window_Base

# Dialog properties
@export var dialog_title: String = "Dialog"
@export var dialog_size: Vector2 = Vector2(400, 300)
@export var is_modal: bool = true
@export var center_on_parent: bool = true

# References
var parent_window: Window

# UI Components
var dialog_content: Control
var button_container: HBoxContainer

# Signals
signal dialog_confirmed()
signal dialog_cancelled()
signal dialog_closed()

func _init(title: String = "Dialog", size: Vector2 = Vector2(400, 300)):
	super._init()
	dialog_title = title
	dialog_size = size
	
	# Configure window properties
	set_window_title(dialog_title)
	self.size = Vector2i(dialog_size)
	min_size = Vector2i(dialog_size.x - 100, dialog_size.y - 100)
	
	# Dialogs should not be resizable by default
	unresizable = true
	always_on_top = true
	
	# Remove maximize and minimize buttons for dialogs
	can_maximize = false
	can_minimize = false

func _ready():
	super._ready()
	call_deferred("_setup_dialog_content_deferred")
	
func _initialize_dialog():
	"""Initialize dialog after everything is ready"""
	# Ensure we're in the tree and parent is ready
	if not is_inside_tree():
		await tree_entered
	
	# Wait for parent initialization to complete
	await get_tree().process_frame
	
	_setup_dialog_content()
	_connect_dialog_signals()
	
func _setup_dialog_content_deferred():
	"""Setup dialog content after the window is properly in the tree"""
	# Ensure we're in the tree before proceeding
	if not is_inside_tree():
		await tree_entered
	
	_setup_dialog_content()
	_connect_dialog_signals()

func _setup_dialog_content():
	# Wait for parent content_area to be ready
	if not content_area:
		await get_tree().process_frame
	
	# Ensure we have a content area before proceeding
	if not content_area:
		push_error("DialogWindow_Base: No content_area available!")
		return
	
	# Create main content container
	dialog_content = VBoxContainer.new()
	dialog_content.name = "DialogContent"
	dialog_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog_content.add_theme_constant_override("margin_left", 15)
	dialog_content.add_theme_constant_override("margin_right", 15)
	dialog_content.add_theme_constant_override("margin_top", 15)
	dialog_content.add_theme_constant_override("margin_bottom", 15)
	dialog_content.add_theme_constant_override("separation", 10)
	
	# Add to the custom window's content area
	add_content(dialog_content)
	
	# Create button container
	button_container = HBoxContainer.new()
	button_container.name = "ButtonContainer"
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 10)
	dialog_content.add_child(button_container)

func _connect_dialog_signals():
	# Connect custom window signals
	window_closed.connect(_on_dialog_close_requested)

func _on_dialog_close_requested():
	dialog_closed.emit()
	close_dialog()

# Public interface for dialog content
func add_dialog_content(content: Control):
	"""Add content to the dialog above the button area"""
	# Ensure dialog content is ready
	if not dialog_content and is_inside_tree():
		await get_tree().process_frame
	
	if dialog_content and button_container:
		# Insert before the button container
		var button_index = dialog_content.get_children().find(button_container)
		dialog_content.add_child(content)
		if button_index >= 0:
			dialog_content.move_child(content, button_index)

func add_button(text: String, action: Callable = Callable()) -> Button:
	"""Add a button to the dialog's button container"""
	# Ensure button container is ready
	if not button_container and is_inside_tree():
		await get_tree().process_frame
	
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(80, 35)
	
	if action.is_valid():
		button.pressed.connect(action)
	
	button_container.add_child(button)
	return button

func add_confirm_cancel_buttons(confirm_text: String = "OK", cancel_text: String = "Cancel"):
	"""Add standard confirm/cancel buttons"""
	# Ensure button container is ready
	if not button_container:
		await get_tree().process_frame
	
	var confirm_button = await add_button(confirm_text, _on_confirmed)
	var cancel_button = await add_button(cancel_text, _on_cancelled)
	
	return {"confirm": confirm_button, "cancel": cancel_button}

func _on_confirmed():
	dialog_confirmed.emit()
	close_dialog()

func _on_cancelled():
	dialog_cancelled.emit()
	close_dialog()

# Dialog management
func show_dialog(parent: Window = null):
	"""Show the dialog, optionally centering on a parent window"""
	if parent:
		parent_window = parent
		if center_on_parent:
			center_on_window(parent)
	
	popup()
	grab_focus()

func center_on_window(parent: Window):
	"""Center this dialog on the specified parent window"""
	if parent:
		var parent_center = parent.position + parent.size / 2
		position = Vector2i(parent_center - size / 2)

func close_dialog():
	"""Close the dialog and clean up"""
	visible = false
	queue_free()

# Utility methods for common dialog types
func set_dialog_text(text: String):
	"""Set the main text content of the dialog"""
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_dialog_content(label)

func create_input_field(placeholder: String = "", initial_value: String = "") -> LineEdit:
	"""Create and add an input field to the dialog"""
	var input = LineEdit.new()
	input.placeholder_text = placeholder
	input.text = initial_value
	input.custom_minimum_size.x = 200
	
	var input_container = HBoxContainer.new()
	input_container.alignment = BoxContainer.ALIGNMENT_CENTER
	input_container.add_child(input)
	
	add_dialog_content(input_container)
	return input

func create_spinbox(min_val: float, max_val: float, initial_val: float = 0, step: float = 1) -> SpinBox:
	"""Create and add a spinbox to the dialog"""
	var spinbox = SpinBox.new()
	spinbox.min_value = min_val
	spinbox.max_value = max_val
	spinbox.value = initial_val
	spinbox.step = step
	spinbox.custom_minimum_size = Vector2(150, 30)
	
	var spinbox_container = HBoxContainer.new()
	spinbox_container.alignment = BoxContainer.ALIGNMENT_CENTER
	spinbox_container.add_child(spinbox)
	
	add_dialog_content(spinbox_container)
	return spinbox

func create_rich_text_area(bbcode_text: String) -> RichTextLabel:
	"""Create and add a rich text area to the dialog"""
	var rich_text = RichTextLabel.new()
	rich_text.bbcode_enabled = true
	rich_text.text = bbcode_text
	rich_text.fit_content = true
	rich_text.custom_minimum_size.y = 150
	
	add_dialog_content(rich_text)
	return rich_text

# Input handling for modal behavior
func _input(event: InputEvent):
	if not visible or not is_modal:
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				_on_cancelled()
				get_viewport().set_input_as_handled()
			KEY_ENTER:
				# Only auto-confirm if there's a single button or explicit confirm button
				if button_container.get_child_count() == 1:
					_on_confirmed()
					get_viewport().set_input_as_handled()

# Override parent window styling for dialogs
func apply_dialog_theme():
	"""Apply dialog-specific styling"""
	# Dialogs typically have a slightly different appearance
	title_bar_color = Color(0.12, 0.12, 0.15, 1.0)
	title_bar_active_color = Color(0.15, 0.15, 0.2, 1.0)
	border_color = Color(0.5, 0.5, 0.6, 1.0)
	border_active_color = Color(0.7, 0.7, 0.9, 1.0)
	
	# Update the styling only if title_bar exists and is ready
	if title_bar and is_inside_tree():
		_update_title_bar_style()
	else:
		# Defer theme application until ready
		call_deferred("_apply_deferred_theme")

func _apply_deferred_theme():
	"""Apply theme after ensuring components are ready"""
	if title_bar and is_inside_tree():
		_update_title_bar_style()
