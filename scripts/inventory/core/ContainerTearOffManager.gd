# ContainerTearOffManager.gd - Manages container tearoff functionality
class_name ContainerTearOffManager
extends RefCounted

var main_window: InventoryWindow
var tearoff_windows: Dictionary = {}  # container_id -> ContainerTearOffWindow
var drag_threshold: float = 15.0

# Drag state tracking
var drag_start_position: Vector2
var drag_start_time: float
var dragging_container_index: int = -1
var is_potential_tearoff: bool = false
var is_drag_active: bool = false  # New flag to track active drag state

func _init(window: InventoryWindow):
	main_window = window

func setup_tearoff_functionality():
	"""Setup tearoff drag detection on container list"""
	if not main_window or not main_window.content or not main_window.content.container_list:
		return
		
	var container_list = main_window.content.container_list
	
	# Connect to container list input events
	if not container_list.gui_input.is_connected(_on_container_list_input):
		container_list.gui_input.connect(_on_container_list_input)

func _on_container_list_input(event: InputEvent):
	"""Handle input on container list for tearoff detection"""
	if not event is InputEventMouseButton:
		return
		
	var mouse_event = event as InputEventMouseButton
	
	if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
		_start_potential_tearoff(mouse_event.global_position)
	elif mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
		_check_tearoff_completion(mouse_event.global_position)

func _start_potential_tearoff(position: Vector2):
	"""Start monitoring for potential tearoff"""
	var container_list = main_window.content.container_list
	if not container_list:
		return
		
	# Get container index at position
	var local_pos = position - container_list.global_position
	var item_index = container_list.get_item_at_position(local_pos, true)
	
	if item_index >= 0 and item_index < main_window.content.open_containers.size():
		drag_start_position = position
		drag_start_time = Time.get_time_dict_from_system().second
		dragging_container_index = item_index
		is_potential_tearoff = true
		is_drag_active = false
		
		# Start monitoring mouse movement
		_start_drag_monitoring()

func _start_drag_monitoring():
	"""Start monitoring mouse movement for tearoff"""
	if not main_window:
		return
		
	# Connect to process to monitor mouse movement
	if not main_window.get_tree().process_frame.is_connected(_monitor_tearoff_drag):
		main_window.get_tree().process_frame.connect(_monitor_tearoff_drag)

func _monitor_tearoff_drag():
	"""Monitor mouse movement during potential tearoff"""
	if not is_potential_tearoff:
		_stop_drag_monitoring()
		return
		
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_stop_drag_monitoring()
		return
		
	var current_position = main_window.get_global_mouse_position()
	var distance = current_position.distance_to(drag_start_position)
	
	# Once threshold exceeded, mark as active drag but don't create window yet
	if distance > drag_threshold and not is_drag_active:
		is_drag_active = true
		
		# Visual feedback - could change cursor or show drag preview
		_show_drag_feedback()

func _show_drag_feedback():
	"""Provide visual feedback that tearoff is ready"""
	# You could change the cursor or add visual feedback here
	# For now, just set the cursor to indicate dragging
	if main_window:
		main_window.mouse_default_cursor_shape = Control.CURSOR_MOVE

func _stop_drag_monitoring():
	"""Stop monitoring drag movement"""
	is_potential_tearoff = false
	is_drag_active = false
	dragging_container_index = -1
	
	# Reset cursor
	if main_window:
		main_window.mouse_default_cursor_shape = Control.CURSOR_ARROW
	
	if main_window and main_window.get_tree().process_frame.is_connected(_monitor_tearoff_drag):
		main_window.get_tree().process_frame.disconnect(_monitor_tearoff_drag)

func _check_tearoff_completion(position: Vector2):
	"""Check if tearoff should be completed on mouse release"""
	if is_drag_active:
		# Only create window on drop if we were actively dragging
		_execute_tearoff_on_drop(position)
	
	_stop_drag_monitoring()

func _execute_tearoff_on_drop(drop_position: Vector2):
	"""Execute the container tearoff when mouse is released after dragging"""
	if dragging_container_index < 0 or dragging_container_index >= main_window.content.open_containers.size():
		return
		
	var container = main_window.content.open_containers[dragging_container_index]
	if not container:
		return
		
	# Check if already torn off
	if container.container_id in tearoff_windows:
		# Focus existing window
		var existing_data = tearoff_windows[container.container_id]
		if existing_data.has("window"):
			var existing_window = existing_data["window"]
			if is_instance_valid(existing_window):
				existing_window.move_to_front()
				return
			else:
				# Clean up invalid reference
				tearoff_windows.erase(container.container_id)
	
	# Create new tearoff window at drop position
	_create_tearoff_window(container, drop_position)

func _create_tearoff_window(container: InventoryContainer_Base, drop_position: Vector2 = Vector2.ZERO):
	"""Create a new tearoff window for the container"""
	var tearoff_window = ContainerTearOffWindow.new(container, main_window)
		
	# Position the window first
	var position_for_window: Vector2
	if drop_position != Vector2.ZERO:
		position_for_window = drop_position - Vector2(100, 50)
	else:
		var mouse_pos = main_window.get_global_mouse_position()
		position_for_window = mouse_pos - Vector2(100, 50)
	
	tearoff_window.position = position_for_window
	
	# Try to use UIManager first
	var ui_managers = main_window.get_tree().get_nodes_in_group("ui_manager")
	var ui_manager: UIManager = null
	if ui_managers.size() > 0:
		ui_manager = ui_managers[0]
		print("ContainerTearOffManager: Found UIManager")
	else:
		print("ContainerTearOffManager: No UIManager found")
	
	if ui_manager and ui_manager.has_method("add_tearoff_window"):
		print("ContainerTearOffManager: Using UIManager for tearoff window")
		# Let UIManager handle canvas creation and layering
		var canvas = ui_manager.add_tearoff_window(tearoff_window)
		print("ContainerTearOffManager: UIManager returned canvas with layer %d" % (canvas.layer if canvas else -1))
	else:
		print("ContainerTearOffManager: Falling back to manual canvas creation")
		# Fallback to old method
		var tearoff_canvas = CanvasLayer.new()
		tearoff_canvas.name = "TearoffWindowLayer"
		tearoff_canvas.layer = 100
		main_window.get_tree().current_scene.add_child(tearoff_canvas)
		tearoff_canvas.add_child(tearoff_window)
		print("ContainerTearOffManager: Created manual canvas with layer %d" % tearoff_canvas.layer)
	
	# Ensure it's on screen
	_ensure_window_on_screen(tearoff_window)
	
	# Show the window
	tearoff_window.show_window()
	print("ContainerTearOffManager: Showed tearoff window")
	
	# Store reference
	tearoff_windows[container.container_id] = {
		"window": tearoff_window,
		"ui_manager": ui_manager
	}
	
	# Connect signals
	tearoff_window.window_reattached.connect(_on_window_reattached)
	tearoff_window.window_closed.connect(_on_tearoff_window_closed.bind(container.container_id))
	
	print("ContainerTearOffManager: Tearoff window creation complete")

func _ensure_window_on_screen(window: ContainerTearOffWindow):
	"""Ensure tearoff window is positioned on screen"""
	var viewport = main_window.get_viewport()
	if not viewport:
		return
		
	var screen_size = viewport.get_visible_rect().size
	var window_size = window.size
	
	# Clamp position to screen bounds
	window.position.x = clampf(window.position.x, 0, screen_size.x - window_size.x)
	window.position.y = clampf(window.position.y, 0, screen_size.y - window_size.y)

func _hide_container_from_main_list(container: InventoryContainer_Base):
	"""Hide container from main window list while torn off"""
	if not main_window.content or not main_window.content.container_list:
		return
		
	# Find and remove from open containers display
	var container_index = main_window.content.open_containers.find(container)
	if container_index >= 0:
		var container_list = main_window.content.container_list
		
		# Store original item data for restoration
		var item_text = container_list.get_item_text(container_index)
		var item_icon = container_list.get_item_icon(container_index)
		
		# Mark as torn off (change appearance)
		container_list.set_item_text(container_index, item_text + " (Detached)")
		container_list.set_item_disabled(container_index, true)
		container_list.set_item_custom_fg_color(container_index, Color.GRAY)

func _restore_container_to_main_list(container: InventoryContainer_Base):
	"""Restore container to main window list"""
	if not main_window.content or not main_window.content.container_list:
		return
		
	var container_index = main_window.content.open_containers.find(container)
	if container_index >= 0:
		var container_list = main_window.content.container_list
		
		# Restore normal appearance
		container_list.set_item_text(container_index, container.container_name)
		container_list.set_item_disabled(container_index, false)
		container_list.set_item_custom_fg_color(container_index, Color.WHITE)

func detach_from_main_window():
	"""Detach tearoff windows from main window so they can exist independently"""
	
	# Stop drag monitoring since main window is closing
	_stop_drag_monitoring()
	
	# Clear our reference to main window to prevent tearoff windows from trying to reattach
	for tearoff_data in tearoff_windows.values():
		if tearoff_data.has("window") and is_instance_valid(tearoff_data["window"]):
			var tearoff_window = tearoff_data["window"]
			# Clear the parent window reference so reattach becomes impossible
			tearoff_window.parent_window = null
	
	# Don't close the windows - just clear our references
	main_window = null

func _on_window_reattached(container: InventoryContainer_Base):
	"""Handle container reattachment"""
	if not container:
		return
		
	# Remove from tearoff windows
	tearoff_windows.erase(container.container_id)
	
	# Restore to main list
	_restore_container_to_main_list(container)
	
	# Select the reattached container in main window
	if main_window.content:
		var container_index = main_window.content.open_containers.find(container)
		if container_index >= 0:
			main_window.content.container_list.select(container_index)
			main_window.content._on_container_list_selected(container_index)

func _on_tearoff_window_closed(container_id: String):
	"""Handle tearoff window being closed"""
	var tearoff_data = tearoff_windows.get(container_id)
	if tearoff_data:
		# Clean up canvas layer
		if tearoff_data.has("canvas") and is_instance_valid(tearoff_data["canvas"]):
			tearoff_data["canvas"].queue_free()
		tearoff_windows.erase(container_id)

# Public interface
func is_container_torn_off(container: InventoryContainer_Base) -> bool:
	"""Check if a container is currently torn off"""
	return container.container_id in tearoff_windows

func get_tearoff_window(container: InventoryContainer_Base) -> ContainerTearOffWindow:
	"""Get the tearoff window for a container"""
	var tearoff_data = tearoff_windows.get(container.container_id)
	if tearoff_data and tearoff_data.has("window"):
		return tearoff_data["window"]
	return null

func close_all_tearoff_windows():
	"""Close all tearoff windows"""
	for tearoff_data in tearoff_windows.values():
		if tearoff_data.has("window") and is_instance_valid(tearoff_data["window"]):
			tearoff_data["window"].hide_window()
			tearoff_data["window"].queue_free()
		if tearoff_data.has("canvas") and is_instance_valid(tearoff_data["canvas"]):
			tearoff_data["canvas"].queue_free()
	tearoff_windows.clear()

func cleanup():
	"""Cleanup tearoff manager"""
	close_all_tearoff_windows()
	_stop_drag_monitoring()