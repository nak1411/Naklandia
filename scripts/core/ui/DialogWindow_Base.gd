# DialogWindow_Base.gd - Updated to use the new Control-based system
class_name DialogWindow_Base
extends Window_Base

# Dialog properties
@export var dialog_title: String = "Dialog"
@export var dialog_size: Vector2 = Vector2(400, 300)
@export var is_modal: bool = true

# UI Components
var dialog_content: VBoxContainer
var button_container: HBoxContainer

# Signals
signal dialog_confirmed()
signal dialog_cancelled()
signal dialog_closed()

func _init(title: String = "Dialog", size: Vector2 = Vector2(400, 300)):
	super._init()
	
	# Set dialog-specific properties
	dialog_title = title
	dialog_size = size
	window_title = dialog_title
	default_size = dialog_size
	min_window_size = Vector2(dialog_size.x - 100, dialog_size.y - 100)
	
	# Dialogs should not be resizable by default
	can_resize = false
	can_maximize = false
	can_minimize = false

func _setup_window_content():
	"""Override base method to add dialog-specific content"""
	_setup_dialog_content()
	_connect_dialog_signals()

func _setup_dialog_content():
	# Create main content container
	dialog_content = VBoxContainer.new()
	dialog_content.name = "DialogContent"
	dialog_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog_content.add_theme_constant_override("margin_left", 15)
	dialog_content.add_theme_constant_override("margin_right", 15)
	dialog_content.add_theme_constant_override("margin_top", 15)
	dialog_content.add_theme_constant_override("margin_bottom", 15)
	dialog_content.add_theme_constant_override("separation", 10)
	
	# Add to the content area
	add_content(dialog_content)
	
	# Create button container
	button_container = HBoxContainer.new()
	button_container.name = "ButtonContainer"
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 10)
	dialog_content.add_child(button_container)

func _connect_dialog_signals():
	# Connect window signals to dialog signals
	window_closed.connect(_on_dialog_close_requested)

func _on_dialog_close_requested():
	dialog_closed.emit()
	close_dialog()

# Dialog-specific methods
func add_dialog_content(content: Control):
	"""Add content to the dialog above the button area"""
	if dialog_content and button_container:
		# Insert before the button container
		var button_index = dialog_content.get_children().find(button_container)
		dialog_content.add_child(content)
		if button_index >= 0:
			dialog_content.move_child(content, button_index)

func add_button(text: String, action: Callable = Callable()) -> Button:
	"""Add a button to the dialog's button container"""
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(80, 35)
	
	if action.is_valid():
		button.pressed.connect(action)
	
	button_container.add_child(button)
	return button

func add_confirm_cancel_buttons(confirm_text: String = "OK", cancel_text: String = "Cancel"):
	"""Add standard confirm/cancel buttons"""
	var confirm_button = add_button(confirm_text, _on_confirmed)
	var cancel_button = add_button(cancel_text, _on_cancelled)
	
	return {"confirm": confirm_button, "cancel": cancel_button}

func _on_confirmed():
	dialog_confirmed.emit()
	close_dialog()

func _on_cancelled():
	dialog_cancelled.emit()
	close_dialog()

func show_dialog(parent: Window = null):
	"""Show the dialog, optionally centering on a parent window"""
	if parent:
		center_on_window(parent)
	else:
		center_on_viewport()
	
	visible = true
	
func center_on_window(parent: Window):
	"""Center this dialog on the specified parent window"""
	if parent:
		var parent_center = parent.position + parent.size / 2
		position = parent_center - size / 2
		
		# Ensure dialog stays on screen
		var viewport = get_viewport()
		if viewport:
			var screen_size = viewport.get_visible_rect().size
			position.x = clamp(position.x, 0, screen_size.x - size.x)
			position.y = clamp(position.y, 0, screen_size.y - size.y)
	else:
		center_on_viewport()

func close_dialog():
	"""Close the dialog"""
	visible = false
	queue_free()

func center_on_viewport():
	"""Center dialog on the viewport"""
	var viewport = get_viewport()
	if viewport:
		var screen_size = viewport.get_visible_rect().size
		position = (screen_size - size) / 2
