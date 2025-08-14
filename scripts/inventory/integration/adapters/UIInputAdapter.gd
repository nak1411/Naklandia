# integration/adapters/UIInputAdapter.gd
# Interface between inventory system and UI input
class_name UIInputAdapter
extends Node

var event_bus: InventoryEventBus
var connected_ui_manager: UIManager
var input_mode: String = "game" # "game", "inventory", "menu"

var drag_in_progress: bool = false
var input_processing_enabled: bool = true

func _ready():
	name = "UIInputAdapter"

func setup_event_connections(bus: InventoryEventBus):
	"""Connect this adapter to the event bus"""
	event_bus = bus
	
	# Listen for UI-related events
	if event_bus:
		event_bus.inventory_opened.connect(_on_inventory_opened)
		event_bus.inventory_closed.connect(_on_inventory_closed)
		event_bus.ui_focus_changed.connect(_on_ui_focus_changed)

func connect_to_ui_manager(ui_manager: UIManager):
	"""Connect to the UI management system"""
	connected_ui_manager = ui_manager
	
	# Connect to UI manager signals if they exist
	if ui_manager.has_signal("layer_visibility_changed"):
		ui_manager.layer_visibility_changed.connect(_on_layer_visibility_changed)

func _input(event):
	"""Handle input events and route them appropriately"""
	if not event is InputEventKey:
		return
	
	# Check if any LineEdit (like search field) has focus
	var focused_control = get_viewport().gui_get_focus_owner()
	if focused_control is LineEdit:
		# Don't handle inventory toggle when text input is active
		return
		
	# ONLY handle inventory toggle - remove the interact fallback
	if event.is_action_pressed("toggle_inventory"):
		if event_bus:
			if input_mode == "game":
				event_bus.emit_inventory_opened()
			else:
				event_bus.emit_inventory_closed()
		get_viewport().set_input_as_handled()

# Input mode management
func set_input_mode(mode: String):
	"""Set the current input mode"""
	if input_mode != mode:
		var old_mode = input_mode
		input_mode = mode
		
		if event_bus:
			event_bus.emit_signal("ui_input_mode_changed", mode)
		
		_handle_input_mode_change(old_mode, mode)

func _handle_input_mode_change(old_mode: String, new_mode: String):
	"""Handle input mode transitions"""
	match new_mode:
		"inventory":
			_enable_inventory_input()
		"game":
			_enable_game_input()
		"menu":
			_enable_menu_input()

func _enable_inventory_input():
	"""Configure input for inventory mode"""
	# Set mouse mode for inventory interaction
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Disable game input actions
	if connected_ui_manager:
		var crosshair = connected_ui_manager.get_crosshair()
		if crosshair:
			crosshair.set_visible(false)

func _enable_game_input():
	"""Configure input for game mode"""
	# Set mouse mode for game interaction
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Enable game input actions
	if connected_ui_manager:
		var crosshair = connected_ui_manager.get_crosshair()
		if crosshair:
			crosshair.set_visible(true)

func _enable_menu_input():
	"""Configure input for menu mode"""
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# Event handlers
func _on_inventory_opened():
	"""Handle inventory opening"""
	set_input_mode("inventory")
	
	# Show inventory UI layer
	if connected_ui_manager:
		connected_ui_manager.show_inventory_layer()

func _on_inventory_closed():
	"""Handle inventory closing - but check if other UI windows are still open"""
	# Check if there are any UI windows still open before switching to game mode
	var should_switch_to_game = true
	
	if connected_ui_manager and connected_ui_manager.has_method("get_all_windows"):
		var remaining_windows = connected_ui_manager.get_all_windows()
		# Filter out any invalid windows and check for main inventory
		var valid_windows = remaining_windows.filter(func(w): return is_instance_valid(w) and w.visible)
		
		# CRITICAL FIX: Always check if main inventory is actually closed
		var main_inventory_open = false
		for window in valid_windows:
			var window_type = window.get_meta("window_type", "")
			if window_type == "main_inventory":
				main_inventory_open = true
				break
		
		# Only stay in inventory mode if main inventory is actually open
		if main_inventory_open:
			should_switch_to_game = false
			print("UIInputAdapter: Main inventory still open - staying in inventory mode")
		elif valid_windows.size() > 0:
			# Tearoff windows only - check if we should stay in inventory mode
			var has_tearoffs = valid_windows.any(func(w): return w.get_meta("window_type", "") == "tearoff")
			if has_tearoffs:
				should_switch_to_game = false
				print("UIInputAdapter: Tearoff windows open - staying in inventory mode")
	
	if should_switch_to_game:
		print("UIInputAdapter: Switching to game input mode - no main inventory open")
		set_input_mode("game")
	else:
		print("UIInputAdapter: Staying in inventory input mode")
	
	# Hide inventory UI layer (this is safe even if tearoffs are open)
	if connected_ui_manager:
		connected_ui_manager.hide_inventory_layer()

func _on_ui_focus_changed(has_focus: bool):
	"""Handle UI focus changes"""
	if event_bus:
		# Emit focus state to other systems
		event_bus.emit_ui_focus_changed(has_focus)

func _on_layer_visibility_changed(layer_name: String, visible: bool):
	"""Handle UI layer visibility changes"""
	if event_bus:
		# Fix: Use a method call instead of emitting a non-existent signal
		if event_bus.has_method("emit_ui_layer_changed"):
			event_bus.emit_ui_layer_changed(layer_name, visible)
		else:
			# Just print for debugging if the method doesn't exist
			print("UIInputAdapter: Layer %s visibility changed to %s" % [layer_name, visible])

func set_drag_in_progress(dragging: bool):
	"""Enable/disable input processing during drag operations"""
	drag_in_progress = dragging

func set_input_processing_enabled(enabled: bool):
	"""Enable/disable input processing"""
	input_processing_enabled = enabled
	set_process_unhandled_input(enabled)

# Public interface
func get_input_mode() -> String:
	"""Get current input mode"""
	return input_mode

func is_ui_input_active() -> bool:
	"""Check if UI input is currently active"""
	return input_mode != "game"