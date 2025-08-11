# UIManager.gd - Extended with comprehensive window management
class_name UIManager
extends Node

# Canvas layers for different UI elements
@onready var game_ui_canvas: CanvasLayer      # Layer 10 - HUD and game UI
@onready var menu_ui_canvas: CanvasLayer      # Layer 20 - Menus and overlays
@onready var inventory_canvas: CanvasLayer    # Layer 50 - Inventory window
@onready var pause_canvas: CanvasLayer        # Layer 100 - Pause menu (top layer)
@onready var ui_debugger: CanvasLayer 

# Containers within the canvas layers
@onready var hud_container: Control
@onready var menu_container: Control

# UI Elements
var crosshair_ui: CrosshairUI

# Window management properties
var active_windows: Array[Window_Base] = []
var focused_window: Window_Base = null
var window_stack: Array[Window_Base] = []  # Z-order stack
var next_tearoff_layer: int = 60  # Start tearoffs higher than inventory (50)

# Window management signals
signal window_focused(window: Window_Base)
signal window_closed(window: Window_Base)
signal layer_visibility_changed(layer_name: String, visible: bool)

func _ready():
	add_to_group("ui_manager")
	setup_canvas_layers()
	setup_ui_containers()
	setup_default_ui_elements()
	setup_ui_debugger()
	setup_window_management()

func setup_ui_debugger():
	"""Set up the UI debugger"""
	ui_debugger = CanvasLayer.new()
	ui_debugger.name = "UIDebugger"
	ui_debugger.layer = 200  # Higher than pause layer for visibility
	add_child(ui_debugger)

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
	
func setup_default_ui_elements():
	# Create and add crosshair to HUD
	crosshair_ui = CrosshairUI.new()
	crosshair_ui.name = "Crosshair"
	add_hud_element(crosshair_ui)

func setup_window_management():
	"""Initialize window management system with periodic cleanup"""
	print("UIManager: Window management initialized")
	
	# Set up a timer for periodic cleanup of invalid windows
	var cleanup_timer = Timer.new()
	cleanup_timer.wait_time = 5.0  # Clean up every 5 seconds
	cleanup_timer.timeout.connect(_cleanup_invalid_windows)
	cleanup_timer.autostart = true
	add_child(cleanup_timer)

func force_cleanup_windows():
	"""Force immediate cleanup of all invalid windows"""
	_cleanup_invalid_windows()
	_update_window_layers()

# WINDOW MANAGEMENT SYSTEM
func register_window(window: Window_Base, window_type: String = "tearoff") -> CanvasLayer:
	"""Register a window with the UI manager and return its canvas"""
	if not is_instance_valid(window) or window in active_windows:
		return window.get_meta("window_canvas", null) if is_instance_valid(window) else null
	
	active_windows.append(window)
	window_stack.append(window)
	
	# Create appropriate canvas layer
	var canvas_layer = _create_window_canvas(window, window_type)
	
	# Connect window signals with safety checks
	if is_instance_valid(window):
		# Disconnect first to avoid double connections
		if window.window_closed.is_connected(_on_managed_window_closed):
			window.window_closed.disconnect(_on_managed_window_closed)
		window.window_closed.connect(_on_managed_window_closed.bind(window))
		
		# Set up input handling for focus - connect to gui_input for all mouse events
		if not window.gui_input.is_connected(_on_window_input):
			window.gui_input.connect(_on_window_input.bind(window))
	
	# Focus the new window immediately
	focus_window(window)
	
	return canvas_layer

func _create_window_canvas(window: Window_Base, window_type: String) -> CanvasLayer:
	"""Create appropriate canvas layer for window type"""
	var canvas = CanvasLayer.new()
	canvas.name = window.name + "_Canvas"
	
	match window_type:
		"main_inventory":
			canvas.layer = 50  # Use inventory layer
			inventory_canvas.add_child(canvas)
		"tearoff":
			# FIXED: Add tearoff windows to inventory_canvas too, not scene tree
			canvas.layer = next_tearoff_layer
			next_tearoff_layer += 1
			# Use inventory_canvas instead of scene tree for consistent behavior
			inventory_canvas.add_child(canvas)
		"dialog":
			# Dialogs use the highest priority pause canvas
			canvas.layer = 100 + active_windows.size()
			pause_canvas.add_child(canvas)
	
	# Set the metadata BEFORE adding the window to canvas
	window.set_meta("window_canvas", canvas)
	window.set_meta("window_type", window_type)
	
	# Ensure window blocks input and is properly configured
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Add window to canvas
	canvas.add_child(window)
	
	print("UIManager: Created canvas %s with layer %d for window %s" % [canvas.name, canvas.layer, window.name])
	
	return canvas

func _on_window_input(event: InputEvent, window: Window_Base):
	"""Handle window input for focus management with safety checks"""
	if not is_instance_valid(window):
		return
	
	# Handle any mouse button click to bring window to focus
	if event is InputEventMouseButton and event.pressed:
		print("UIManager: Window input detected on %s, button: %d" % [window.name, event.button_index])
		focus_window(window)
	
	# Handle any mouse button click to bring window to focus
	if event is InputEventMouseButton and event.pressed:
		print("UIManager: Window input detected on %s, button: %d" % [window.name, event.button_index])
		focus_window(window)
		# Accept the event to prevent it from propagating to windows below
		get_viewport().set_input_as_handled()

func _on_input_blocker_input(event: InputEvent, window: Window_Base):
	"""Handle input on the input blocker - prevents click-through"""
	if event is InputEventMouseButton and event.pressed:
		# Focus the window when clicking on its background area
		focus_window(window)
	# Always accept input to prevent propagation
	get_viewport().set_input_as_handled()

func focus_window(window: Window_Base):
	"""Focus a specific window and bring it to front with safety checks"""
	print("\n=== FOCUS WINDOW DEBUG ===")
	print("Attempting to focus: %s" % window.name)
	
	if not is_instance_valid(window):
		print("UIManager: Cannot focus invalid window")
		return
	
	if window == focused_window:
		print("UIManager: Window %s already focused" % window.name)
		return
	
	print("UIManager: Focusing window %s (was: %s)" % [window.name, focused_window.name if focused_window else "none"])
	
	# Clean up invalid windows first
	_cleanup_invalid_windows()
	
	# Update focus
	var old_focused = focused_window
	focused_window = window
	
	# CRITICAL: Move to top of stack - this determines layer order
	var old_position = window_stack.find(window)
	if window in window_stack:
		window_stack.erase(window)
		print("UIManager: Removed %s from stack position %d" % [window.name, old_position])
	
	window_stack.append(window)
	print("UIManager: Added %s to top of stack (position %d)" % [window.name, window_stack.size() - 1])
	
	# FIXED: Update ALL window layers based on stack position
	_update_window_layers()
	
	# Update visual focus states
	if old_focused and is_instance_valid(old_focused):
		_set_window_focus_state(old_focused, false)
	_set_window_focus_state(window, true)
	
	# Emit signal
	window_focused.emit(window)
	
	# Debug: Print current layers AFTER the update
	print("=== POST-FOCUS LAYER STATE ===")
	debug_print_all_window_info()
	print("==============================")

func _get_highest_layer_for_type(window_type: String) -> int:
	"""Get the highest layer currently used by windows of the same type"""
	var highest = 50  # Base layer
	
	for window in active_windows:
		if not is_instance_valid(window):
			continue
		
		if window.get_meta("window_type", "") == window_type:
			var canvas = window.get_meta("window_canvas", null) as CanvasLayer
			if canvas and is_instance_valid(canvas):
				highest = max(highest, canvas.layer)
	
	return highest

func _update_window_layers():
	"""Update canvas layers to maintain proper z-order based on focus order"""
	# Clean up invalid windows first
	_cleanup_invalid_windows()
	
	print("UIManager: Updating window layers for %d windows" % window_stack.size())
	
	# FIXED: Assign layers based on position in window_stack
	# Windows later in the stack (more recently focused) get higher layers
	var base_layer = 50
	
	for i in range(window_stack.size()):
		var window = window_stack[i]
		if not is_instance_valid(window):
			continue
			
		var canvas = window.get_meta("window_canvas", null) as CanvasLayer
		if canvas and is_instance_valid(canvas):
			var new_layer = base_layer + i
			print("UIManager: Setting %s canvas layer to %d (was %d) - position %d in stack" % [window.name, new_layer, canvas.layer, i])
			canvas.layer = new_layer
		else:
			print("UIManager: WARNING - No valid canvas for window %s" % window.name)
	
	# FIXED: Update next_tearoff_layer to be higher than any current tearoff
	var highest_tearoff_layer = base_layer
	for window in window_stack:
		if not is_instance_valid(window):
			continue
		var window_type = window.get_meta("window_type", "")
		if window_type == "tearoff":
			var canvas = window.get_meta("window_canvas", null) as CanvasLayer
			if canvas and is_instance_valid(canvas):
				highest_tearoff_layer = max(highest_tearoff_layer, canvas.layer)
	
	next_tearoff_layer = highest_tearoff_layer + 1
	
	print("UIManager: Layer update complete, next_tearoff_layer: %d" % next_tearoff_layer)

func _cleanup_invalid_windows():
	"""Remove invalid windows from tracking arrays"""
	# Clean up active_windows
	for i in range(active_windows.size() - 1, -1, -1):
		var window = active_windows[i]
		if not is_instance_valid(window):
			active_windows.remove_at(i)
	
	# Clean up window_stack
	for i in range(window_stack.size() - 1, -1, -1):
		var window = window_stack[i]
		if not is_instance_valid(window):
			window_stack.remove_at(i)
	
	# Clean up focused_window
	if focused_window and not is_instance_valid(focused_window):
		focused_window = null

func _set_window_focus_state(window: Window_Base, has_focus: bool):
	"""Update window visual focus state with safety checks"""
	if not is_instance_valid(window):
		return
		
	if has_focus:
		# Add focus styling
		window.modulate = Color(1.05, 1.05, 1.05, 1.0)  # Slightly brighter
		if window.has_method("set_edge_bloom_state"):
			window.set_edge_bloom_state(Window_Base.BloomState.ACTIVE)
	else:
		# Remove focus styling  
		window.modulate = Color(0.95, 0.95, 0.95, 1.0)  # Slightly dimmer
		if window.has_method("set_edge_bloom_state"):
			window.set_edge_bloom_state(Window_Base.BloomState.SUBTLE)

func _on_managed_window_closed(window: Window_Base):
	"""Handle managed window being closed"""
	unregister_window(window)

func unregister_window(window: Window_Base):
	"""Unregister a window from the UI manager"""
	if window not in active_windows:
		return
	
	print("UIManager: Unregistering window %s" % window.name)
	
	# Don't automatically close other windows when main inventory closes
	var window_type = window.get_meta("window_type", "")
	var is_main_inventory = (window_type == "main_inventory")
	
	active_windows.erase(window)
	window_stack.erase(window)
	
	# Clean up canvas
	var canvas = window.get_meta("window_canvas", null) as CanvasLayer
	if canvas and is_instance_valid(canvas):
		canvas.queue_free()
	
	# Update focus to remaining windows (but don't close them)
	if window == focused_window:
		focused_window = null
		# Focus the topmost remaining window
		_cleanup_invalid_windows()
		if window_stack.size() > 0:
			var next_window = window_stack[-1]
			# Only focus if it's not the main inventory closing
			if not is_main_inventory or next_window.get_meta("window_type", "") != "tearoff":
				focus_window(next_window)
	
	# Update layers
	_update_window_layers()
	
	window_closed.emit(window)
	
	print("UIManager: Window %s unregistered, %d windows remaining" % [window.name, active_windows.size()])

func _debug_print_window_layers():
	"""Debug method to print current window layers"""
	print("UIManager: Current window layers:")
	for window in window_stack:
		if is_instance_valid(window):
			var canvas = window.get_meta("window_canvas", null) as CanvasLayer
			if canvas and is_instance_valid(canvas):
				print("  %s: layer %d" % [window.name, canvas.layer])

func debug_print_all_window_info():
	"""Print detailed info about all windows and their layers"""
	print("\n=== WINDOW DEBUG INFO ===")
	print("Focused window: %s" % (focused_window.name if focused_window else "none"))
	print("Total active windows: %d" % active_windows.size())
	print("Window stack order (bottom to top):")
	
	for i in range(window_stack.size()):
		var window = window_stack[i]
		if is_instance_valid(window):
			var canvas = window.get_meta("window_canvas", null) as CanvasLayer
			var window_type = window.get_meta("window_type", "unknown")
			var layer = canvas.layer if canvas else -1
			var visible = window.visible
			var mouse_filter = _get_mouse_filter_name(window.mouse_filter)
			print("  [%d] %s (type: %s, layer: %d, visible: %s, mouse_filter: %s)" % [i, window.name, window_type, layer, visible, mouse_filter])
			
			# Check canvas parent
			if canvas:
				var canvas_parent = canvas.get_parent()
				print("      Canvas parent: %s" % (canvas_parent.name if canvas_parent else "none"))
	
	print("=========================\n")

func _get_mouse_filter_name(filter: Control.MouseFilter) -> String:
	match filter:
		Control.MOUSE_FILTER_STOP:
			return "STOP"
		Control.MOUSE_FILTER_PASS:
			return "PASS"
		Control.MOUSE_FILTER_IGNORE:
			return "IGNORE"
		_:
			return "UNKNOWN"

func debug_window_click_test(window: Window_Base):
	"""Debug what happens when a window should receive a click"""
	print("\n=== CLICK TEST for %s ===" % window.name)
	var canvas = window.get_meta("window_canvas", null) as CanvasLayer
	print("Window visible: %s" % window.visible)
	print("Window mouse_filter: %s" % _get_mouse_filter_name(window.mouse_filter))
	print("Canvas layer: %d" % (canvas.layer if canvas else -1))
	print("Canvas parent: %s" % (canvas.get_parent().name if canvas and canvas.get_parent() else "none"))
	print("Window in active_windows: %s" % (window in active_windows))
	print("Window in window_stack: %s" % (window in window_stack))
	print("Window stack position: %d" % (window_stack.find(window) if window in window_stack else -1))
	print("Is focused: %s" % (window == focused_window))
	print("========================\n")

# PUBLIC WINDOW MANAGEMENT INTERFACE
func get_focused_window() -> Window_Base:
	return focused_window

func get_all_windows() -> Array[Window_Base]:
	return active_windows.duplicate()

func close_all_windows():
	"""Close all managed windows except main inventory"""
	print("UIManager: Closing all non-inventory windows")
	for window in active_windows.duplicate():
		if is_instance_valid(window):
			var window_type = window.get_meta("window_type", "")
			if window_type != "main_inventory":
				print("UIManager: Closing window %s (type: %s)" % [window.name, window_type])
				window.hide_window()

func close_windows_by_type(window_type: String):
	"""Close all windows of a specific type"""
	print("UIManager: Closing all windows of type: %s" % window_type)
	var windows_to_close = get_windows_by_type(window_type)
	for window in windows_to_close:
		if is_instance_valid(window):
			print("UIManager: Closing window %s" % window.name)
			window.hide_window()

func close_all_windows_including_main():
	"""Close ALL managed windows including main inventory"""
	print("UIManager: Closing ALL windows")
	for window in active_windows.duplicate():
		if is_instance_valid(window):
			print("UIManager: Closing window %s" % window.name)
			window.hide_window()

func bring_window_to_front(window: Window_Base):
	"""Bring specific window to front"""
	focus_window(window)

# WINDOW TYPE-SPECIFIC METHODS
func add_tearoff_window(window: Window_Base) -> CanvasLayer:
	"""Add a tearoff window with proper layering"""
	return register_window(window, "tearoff")

func add_dialog_window(window: Window_Base) -> CanvasLayer:
	"""Add a dialog window with highest priority"""
	return register_window(window, "dialog")

func add_main_inventory_window(window: Window_Base) -> CanvasLayer:
	"""Add the main inventory window"""
	return register_window(window, "main_inventory")

# WINDOW MANAGEMENT UTILITIES
func get_window_count_by_type(window_type: String) -> int:
	"""Get count of windows by type with safety checks"""
	var count = 0
	_cleanup_invalid_windows()
	
	for window in active_windows:
		if not is_instance_valid(window):
			continue
		var w_type = window.get_meta("window_type", "")
		if w_type == window_type:
			count += 1
	return count

func get_windows_by_type(window_type: String) -> Array[Window_Base]:
	"""Get all windows of a specific type with safety checks"""
	var windows: Array[Window_Base] = []
	_cleanup_invalid_windows()
	
	for window in active_windows:
		if not is_instance_valid(window):
			continue
		var w_type = window.get_meta("window_type", "")
		if w_type == window_type:
			windows.append(window)
	return windows

# ORIGINAL UI ELEMENT METHODS
func add_hud_element(ui_element: Control):
	"""Add HUD elements like health bars, ammo counters, crosshair, etc."""
	if hud_container:
		hud_container.add_child(ui_element)

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

# CANVAS LAYER VISIBILITY MANAGEMENT
func show_menu_layer():
	if menu_ui_canvas:
		menu_ui_canvas.visible = true
		layer_visibility_changed.emit("menu", true)

func hide_menu_layer():
	if menu_ui_canvas:
		menu_ui_canvas.visible = false
		layer_visibility_changed.emit("menu", false)

func show_inventory_layer():
	if inventory_canvas:
		inventory_canvas.visible = true
		layer_visibility_changed.emit("inventory", true)

func hide_inventory_layer():
	if inventory_canvas:
		inventory_canvas.visible = false
		layer_visibility_changed.emit("inventory", false)

func show_pause_layer():
	if pause_canvas:
		pause_canvas.visible = true
		layer_visibility_changed.emit("pause", true)

func hide_pause_layer():
	if pause_canvas:
		pause_canvas.visible = false
		layer_visibility_changed.emit("pause", false)

# Show/hide menu overlay (legacy support)
func show_menu():
	show_menu_layer()

func hide_menu():
	hide_menu_layer()

func toggle_menu():
	if menu_ui_canvas:
		menu_ui_canvas.visible = !menu_ui_canvas.visible

# GET CANVAS REFERENCES
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

# UTILITY METHODS FOR LAYER MANAGEMENT
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