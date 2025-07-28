# UIManager.gd - Manages all UI elements on a CanvasLayer
class_name UIManager
extends Node

@onready var ui_canvas: CanvasLayer
@onready var hud_container: Control
@onready var menu_container: Control

func _ready():
	setup_ui_canvas()
	setup_ui_containers()

func setup_ui_canvas():
	# Create main UI canvas layer
	ui_canvas = CanvasLayer.new()
	ui_canvas.name = "UICanvas"
	ui_canvas.layer = 10  # Render above game world
	add_child(ui_canvas)
	
	print("UI Canvas Layer created")

func setup_ui_containers():
	# Create HUD container for game UI elements
	hud_container = Control.new()
	hud_container.name = "HUDContainer"
	hud_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block input
	ui_canvas.add_child(hud_container)
	
	# Create menu container for overlays/menus
	menu_container = Control.new()
	menu_container.name = "MenuContainer"
	menu_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_container.visible = false  # Hidden by default
	ui_canvas.add_child(menu_container)
	
	print("UI containers created")

# Add UI elements to appropriate containers
func add_hud_element(ui_element: Control):
	if hud_container:
		hud_container.add_child(ui_element)

func add_menu_element(ui_element: Control):
	if menu_container:
		menu_container.add_child(ui_element)

# Add window elements directly to CanvasLayer
func add_window(window_element: Window):
	if ui_canvas:
		ui_canvas.add_child(window_element)

# Show/hide menu overlay
func show_menu():
	if menu_container:
		menu_container.visible = true

func hide_menu():
	if menu_container:
		menu_container.visible = false

func toggle_menu():
	if menu_container:
		menu_container.visible = !menu_container.visible

# Get references for other scripts
func get_ui_canvas() -> CanvasLayer:
	return ui_canvas

func get_hud_container() -> Control:
	return hud_container

func get_menu_container() -> Control:
	return menu_container
