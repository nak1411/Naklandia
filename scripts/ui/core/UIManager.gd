# UIManager.gd - Extended with comprehensive window management
#REFACTOR
class_name UIManager
extends Node

# Window management signals
signal window_focused(window: Window_Base)
signal window_closed(window: Window_Base)
signal layer_visibility_changed(layer_name: String, visible: bool)

# UI Elements
var crosshair_ui: CrosshairUI
var focused_window: Window_Base = null
var active_windows: Array[Window_Base] = []
var window_stack: Array[Window_Base] = []  # Z-order stack

# Window management properties
var next_tearoff_layer: int = 60  # Start tearoffs higher than inventory (50)

# Window positioning properties
var last_window_position: Vector2 = Vector2(200, 100)  # Track last opened window position
var window_cascade_offset: Vector2 = Vector2(40, 40)  # Offset for cascade positioning
var window_initial_positions: Dictionary = {}  # Track initial positions by window type

# Canvas layers for different UI elements
@onready var game_ui_canvas: CanvasLayer  # Layer 10 - HUD and game UI
@onready var menu_ui_canvas: CanvasLayer  # Layer 20 - Menus and overlays
@onready var inventory_canvas: CanvasLayer  # Layer 50 - Inventory window
@onready var pause_canvas: CanvasLayer  # Layer 100 - Pause menu (top layer)
@onready var ui_debugger: CanvasLayer

# Containers within the canvas layers
@onready var hud_container: Control
@onready var menu_container: Control


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
	ui_debugger.layer = 250  # Higher than pause layer for visibility
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
	inventory_canvas.layer = 110
	add_child(inventory_canvas)

	# Create pause canvas layer (highest priority)
	pause_canvas = CanvasLayer.new()
	pause_canvas.name = "PauseCanvas"
	pause_canvas.layer = 200
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

	window.set_meta("window_type", window_type)

	# Apply smart positioning to prevent overlap (only if window hasn't been positioned yet)
	if window.position == Vector2(200, 100):  # Default position from Window_Base
		_apply_smart_window_position(window, window_type)

	# Create appropriate canvas layer
	var canvas_layer = _create_window_canvas(window, window_type)

	# Connect to window layout manager for auto-saving
	var layout_managers = get_tree().get_nodes_in_group("window_layout_manager")
	if layout_managers.size() > 0:
		var layout_manager = layout_managers[0]
		if layout_manager.has_method("connect_window_signals"):
			layout_manager.connect_window_signals(window)

	# Connect window signals with safety checks
	if is_instance_valid(window):
		# Disconnect first to avoid double connections
		if window.window_closed.is_connected(_on_managed_window_closed):
			window.window_closed.disconnect(_on_managed_window_closed)
		window.window_closed.connect(_on_managed_window_closed.bind(window))

	# Focus the new window immediately
	focus_window(window)

	return canvas_layer


func _create_window_canvas(window: Window_Base, window_type: String) -> CanvasLayer:
	"""Create appropriate canvas layer for window type"""
	var canvas = CanvasLayer.new()
	canvas.name = window.name + "_Canvas"

	match window_type:
		"main_inventory":
			canvas.layer = 110  # Use inventory layer
			inventory_canvas.add_child(canvas)
		"tearoff":
			# FIX: Add tearoff windows directly to scene tree with their own layer
			canvas.layer = next_tearoff_layer
			next_tearoff_layer += 1
			# Add directly to scene tree, not nested in inventory_canvas
			add_child(canvas)  # Changed from inventory_canvas.add_child(canvas)
		"dialog":
			# Dialogs use the highest priority pause canvas
			canvas.layer = 200 + active_windows.size()
			pause_canvas.add_child(canvas)
		"equipment", "crafting", "character", "workbench":
			# Persistent UI windows - add directly to UIManager with their own layers
			canvas.layer = 120 + active_windows.size()
			add_child(canvas)

	# Set the metadata BEFORE adding the window to canvas
	window.set_meta("window_canvas", canvas)
	window.set_meta("window_type", window_type)

	# Add window to canvas
	canvas.add_child(window)

	return canvas


func _on_window_input(event: InputEvent, window: Window_Base):
	"""Handle window input for focus management with safety checks"""
	if not is_instance_valid(window):
		return

	# Handle any mouse button click to bring window to focus
	if event is InputEventMouseButton and event.pressed:
		focus_window(window)


func _on_input_blocker_input(event: InputEvent, window: Window_Base):
	"""Handle input on the input blocker - prevents click-through"""
	if event is InputEventMouseButton and event.pressed:
		# Focus the window when clicking on its background area
		focus_window(window)


func focus_window(window: Window_Base):
	"""Focus a specific window and bring it to front with safety checks"""
	if not is_instance_valid(window):
		return

	if window == focused_window:
		return

	# Clean up invalid windows first
	_cleanup_invalid_windows()

	# Update focus
	var old_focused = focused_window
	focused_window = window

	# Move to top of stack - this determines layer order
	if window in window_stack:
		window_stack.erase(window)

	window_stack.append(window)

	# Update ALL window layers based on stack position
	_update_window_layers()

	# Update visual focus states
	if old_focused and is_instance_valid(old_focused):
		_set_window_focus_state(old_focused, false)
	_set_window_focus_state(window, true)

	# Emit signal
	window_focused.emit(window)


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

	# FIXED: Assign layers based on position in window_stack
	# Windows later in the stack (more recently focused) get higher layers
	var base_layer = 120

	for i in range(window_stack.size()):
		var window = window_stack[i]
		if not is_instance_valid(window):
			continue

		var canvas = window.get_meta("window_canvas", null) as CanvasLayer
		if canvas and is_instance_valid(canvas):
			var new_layer = base_layer + i
			canvas.layer = new_layer

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


func _apply_smart_window_position(window: Window_Base, window_type: String):
	"""Apply smart positioning to prevent window overlap"""
	# Get viewport size for bounds checking
	var viewport = get_viewport()
	if not viewport:
		return

	var screen_size = viewport.get_visible_rect().size

	# Define different starting positions for different window types
	var type_offsets = {
		"main_inventory": Vector2(100, 80),
		"equipment": Vector2(150, 120),
		"crafting": Vector2(200, 160),
		"workbench": Vector2(250, 200),
		"character": Vector2(300, 240),
		"tearoff": Vector2(350, 280),
		"dialog": Vector2(400, 320)
	}

	# Get the base position for this window type
	var base_position = type_offsets.get(window_type, Vector2(200, 100))

	# Check if this is the first window of this type
	if not window_initial_positions.has(window_type):
		# First window of this type - use base position
		window_initial_positions[window_type] = base_position
		window.position = base_position
		last_window_position = base_position
	else:
		# Not the first window - check for overlap with existing windows
		var new_position = _find_non_overlapping_position(window, base_position, screen_size)
		window.position = new_position
		last_window_position = new_position


func _find_non_overlapping_position(new_window: Window_Base, preferred_position: Vector2, screen_size: Vector2) -> Vector2:
	"""Find a position that doesn't overlap with existing windows"""
	var test_position = preferred_position
	var max_attempts = 20  # Prevent infinite loops
	var attempts = 0

	# Try cascade positions
	while attempts < max_attempts:
		var overlaps = false

		# Check if this position overlaps with any existing window
		for existing_window in active_windows:
			if not is_instance_valid(existing_window):
				continue
			if existing_window == new_window:
				continue
			if not existing_window.visible:
				continue

			# Check for overlap
			var existing_rect = Rect2(existing_window.position, existing_window.size)
			var new_rect = Rect2(test_position, new_window.size)

			if existing_rect.intersects(new_rect):
				overlaps = true
				break

		# If no overlap, use this position
		if not overlaps:
			return test_position

		# Try next cascade position
		test_position += window_cascade_offset

		# If we've cascaded too far off screen, reset to a different area
		if test_position.x + new_window.size.x > screen_size.x - 50 or test_position.y + new_window.size.y > screen_size.y - 50:
			# Try a different quadrant
			if attempts < 5:
				test_position = Vector2(screen_size.x * 0.3, 100)
			elif attempts < 10:
				test_position = Vector2(100, screen_size.y * 0.3)
			elif attempts < 15:
				test_position = Vector2(screen_size.x * 0.5, screen_size.y * 0.3)
			else:
				# Last resort - just use preferred position
				return preferred_position

		attempts += 1

	# If we couldn't find a non-overlapping position, return the preferred position
	return preferred_position


func _set_window_focus_state(window: Window_Base, has_focus: bool):
	"""Update window visual focus state with safety checks"""
	if not is_instance_valid(window):
		return

	# Don't change visual state if window is being resized
	if window.is_resizing:
		return

	# Preserve the current alpha (transparency) value
	var current_alpha = window.modulate.a

	if has_focus:
		# Add focus styling while preserving transparency
		window.modulate = Color(1.25, 1.25, 1.25, current_alpha)  # Keep alpha
		if window.has_method("set_edge_bloom_state"):
			window.set_edge_bloom_state(Window_Base.BloomState.ACTIVE)
	else:
		# Remove focus styling while preserving transparency
		window.modulate = Color(0.95, 0.95, 0.95, current_alpha)  # Keep alpha
		if window.has_method("set_edge_bloom_state"):
			window.set_edge_bloom_state(Window_Base.BloomState.SUBTLE)


func _on_managed_window_closed(window: Window_Base):
	"""Handle managed window being closed"""
	var window_name = "invalid"
	if is_instance_valid(window):
		window_name = window.name
	print("[UIManager] _on_managed_window_closed called for: ", window_name)
	unregister_window(window)


func unregister_window(window: Window_Base):
	"""Unregister a window from the UI manager"""
	var window_name = "invalid"
	if is_instance_valid(window):
		window_name = window.name
	print("[UIManager] unregister_window called for: ", window_name)

	var layout_managers = get_tree().get_nodes_in_group("window_layout_manager")
	if layout_managers.size() > 0:
		var layout_manager = layout_managers[0]
		if layout_manager.has_method("disconnect_window_signals"):
			layout_manager.disconnect_window_signals(window)

	if window not in active_windows:
		print("[UIManager] Window not in active_windows list - returning early")
		return

	var window_type = window.get_meta("window_type", "")
	var is_main_inventory = window_type == "main_inventory"
	var is_persistent = window_type in ["main_inventory", "equipment", "crafting", "character"]
	print("[UIManager] Unregistering window type: ", window_type, " persistent:", is_persistent)

	# For persistent windows, DON'T remove from active_windows - just remove from stack
	# This allows them to be tracked even when hidden
	if not is_persistent:
		active_windows.erase(window)

	window_stack.erase(window)

	# DON'T free the canvas for persistent windows (equipment, crafting, character)
	# These windows should be reused when reopened to preserve their state
	# Only free canvas for tearoff and dialog windows that are meant to be temporary
	var should_free_canvas = window_type in ["tearoff", "dialog"]

	if should_free_canvas:
		# Clean up canvas for temporary windows
		var canvas = window.get_meta("window_canvas", null) as CanvasLayer
		if canvas and is_instance_valid(canvas):
			canvas.queue_free()
	# For persistent windows (main_inventory, equipment, crafting), keep the canvas and window alive

	# CRITICAL FIX: If main inventory closes, don't close tearoff windows
	if is_main_inventory:
		# Keep tearoff windows open and independent
		# Just remove focus without closing tearoffs
		if window == focused_window:
			focused_window = null
			# Focus a tearoff window if available
			_cleanup_invalid_windows()
			var tearoff_windows = active_windows.filter(func(w): return w.get_meta("window_type", "") == "tearoff")
			if tearoff_windows.size() > 0:
				focus_window(tearoff_windows[0])
	else:
		# Normal window closing behavior for non-inventory windows
		if window == focused_window:
			focused_window = null
			_cleanup_invalid_windows()
			if window_stack.size() > 0:
				focus_window(window_stack[-1])

	# Update layers
	_update_window_layers()

	window_closed.emit(window)


# PUBLIC WINDOW MANAGEMENT INTERFACE
func get_focused_window() -> Window_Base:
	return focused_window


func get_all_windows() -> Array[Window_Base]:
	return active_windows.duplicate()


func close_all_windows():
	"""Close all managed windows except main inventory"""
	for window in active_windows.duplicate():
		if is_instance_valid(window):
			var window_type = window.get_meta("window_type", "")
			if window_type != "main_inventory":
				window.hide_window()


func close_windows_by_type(window_type: String):
	"""Close all windows of a specific type"""
	var windows_to_close = get_windows_by_type(window_type)
	for window in windows_to_close:
		if is_instance_valid(window):
			window.hide_window()


func close_all_windows_including_main():
	"""Close ALL managed windows including main inventory"""
	for window in active_windows.duplicate():
		if is_instance_valid(window):
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
	return (menu_ui_canvas and menu_ui_canvas.visible) or (inventory_canvas and inventory_canvas.visible) or (pause_canvas and pause_canvas.visible)
