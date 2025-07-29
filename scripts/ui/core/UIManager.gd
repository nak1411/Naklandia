# UIManager.gd - Fixed with proper crosshair and canvas layer management
class_name UIManager
extends Node

# Canvas layers for different UI elements
@onready var game_ui_canvas: CanvasLayer      # Layer 10 - HUD and game UI
@onready var menu_ui_canvas: CanvasLayer      # Layer 20 - Menus and overlays
@onready var inventory_canvas: CanvasLayer    # Layer 50 - Inventory window
@onready var pause_canvas: CanvasLayer        # Layer 100 - Pause menu (top layer)

# Containers within the canvas layers
@onready var hud_container: Control
@onready var menu_container: Control

# UI Elements
var crosshair_ui: CrosshairUI

func _ready():
	add_to_group("ui_manager")
	setup_canvas_layers()
	setup_ui_containers()
	setup_default_ui_elements()  # Add this to create crosshair

func setup_canvas_layers():
	# Create game UI canvas layer (HUD, health bars, etc.)
	game_ui_canvas = CanvasLayer.new()
	game_ui_canvas.name = "GameUICanvas"
	game_ui_canvas.layer = 10
	add_child(game_ui_canvas)
	
	# Create menu UI canvas layer (settings, dialogs, etc.)
	menu_ui_canvas = CanvasLayer.new()
	menu_ui_canvas.name = "MenuUICanvas"
	menu_ui_canvas.layer = 20
	add_child(menu_ui_canvas)
	
	# Create inventory canvas layer
	inventory_canvas = CanvasLayer.new()
	inventory_canvas.name = "InventoryCanvas"
	inventory_canvas.layer = 50
	add_child(inventory_canvas)
	
	# Create pause canvas layer (highest priority)
	pause_canvas = CanvasLayer.new()
	pause_canvas.name = "PauseCanvas"
	pause_canvas.layer = 100
	add_child(pause_canvas)
	
	print("UI Canvas Layers created with layers: 10, 20, 50, 100")

func setup_ui_containers():
	# Create HUD container for game UI elements
	hud_container = Control.new()
	hud_container.name = "HUDContainer"
	hud_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block input
	game_ui_canvas.add_child(hud_container)
	
	# Create menu container for overlays/menus
	menu_container = Control.new()
	menu_container.name = "MenuContainer"
	menu_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_ui_canvas.add_child(menu_container)
	
	print("UI containers created")

func setup_default_ui_elements():
	# Create and add crosshair to HUD
	crosshair_ui = CrosshairUI.new()
	crosshair_ui.name = "Crosshair"
	add_hud_element(crosshair_ui)
	
	print("Default UI elements created (crosshair)")

# Add UI elements to appropriate canvas layers
func add_hud_element(ui_element: Control):
	"""Add HUD elements like health bars, ammo counters, crosshair, etc."""
	if hud_container:
		hud_container.add_child(ui_element)
		print("Added HUD element: ", ui_element.name)

func add_menu_element(ui_element: Control):
	"""Add menu elements like settings panels, dialogs, etc."""
	if menu_container:
		menu_container.add_child(ui_element)

func add_inventory_element(ui_element: Node):
	"""Add inventory-related UI elements"""
	if inventory_canvas:
		inventory_canvas.add_child(ui_element)

func add_pause_element(ui_element: Node):
	"""Add pause menu elements (highest priority)"""
	if pause_canvas:
		pause_canvas.add_child(ui_element)

# Legacy window support (for backwards compatibility)
func add_window(window_element: Window):
	"""Add window elements to inventory canvas by default"""
	if inventory_canvas:
		inventory_canvas.add_child(window_element)

# Canvas layer visibility management
func show_menu_layer():
	if menu_ui_canvas:
		menu_ui_canvas.visible = true

func hide_menu_layer():
	if menu_ui_canvas:
		menu_ui_canvas.visible = false

func show_inventory_layer():
	if inventory_canvas:
		inventory_canvas.visible = true

func hide_inventory_layer():
	if inventory_canvas:
		inventory_canvas.visible = false

func show_pause_layer():
	if pause_canvas:
		pause_canvas.visible = true

func hide_pause_layer():
	if pause_canvas:
		pause_canvas.visible = false

# Show/hide menu overlay (legacy support)
func show_menu():
	show_menu_layer()

func hide_menu():
	hide_menu_layer()

func toggle_menu():
	if menu_ui_canvas:
		menu_ui_canvas.visible = !menu_ui_canvas.visible

# Get references for other scripts
func get_ui_canvas() -> CanvasLayer:
	"""Returns the main game UI canvas for backwards compatibility"""
	return game_ui_canvas

func get_game_ui_canvas() -> CanvasLayer:
	return game_ui_canvas

func get_menu_ui_canvas() -> CanvasLayer:
	return menu_ui_canvas

func get_inventory_canvas() -> CanvasLayer:
	return inventory_canvas

func get_pause_canvas() -> CanvasLayer:
	return pause_canvas

func get_hud_container() -> Control:
	return hud_container

func get_menu_container() -> Control:
	return menu_container

func get_crosshair() -> CrosshairUI:
	return crosshair_ui

# Utility methods for layer management
func set_layer_priority(canvas: CanvasLayer, priority: int):
	"""Dynamically adjust canvas layer priorities"""
	if canvas:
		canvas.layer = priority

func get_highest_visible_layer() -> int:
	"""Returns the highest layer number that's currently visible"""
	var highest = -1
	
	if game_ui_canvas and game_ui_canvas.visible:
		highest = max(highest, game_ui_canvas.layer)
	if menu_ui_canvas and menu_ui_canvas.visible:
		highest = max(highest, menu_ui_canvas.layer)
	if inventory_canvas and inventory_canvas.visible:
		highest = max(highest, inventory_canvas.layer)
	if pause_canvas and pause_canvas.visible:
		highest = max(highest, pause_canvas.layer)
	
	return highest

func hide_all_layers():
	"""Hide all UI layers except game UI"""
	hide_menu_layer()
	hide_inventory_layer()
	hide_pause_layer()

func is_any_overlay_visible() -> bool:
	"""Check if any overlay (non-game UI) is currently visible"""
	return (menu_ui_canvas and menu_ui_canvas.visible) or \
		   (inventory_canvas and inventory_canvas.visible) or \
		   (pause_canvas and pause_canvas.visible)
