# ContainerTearOffManager.gd - Manages container tearoff functionality
class_name ContainerTearOffManager
extends RefCounted

var main_window: InventoryWindow
var tearoff_windows: Dictionary = {}  # container_id -> ContainerTearOffWindow
var drag_threshold: float = 15.0

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

var drag_start_position: Vector2
var drag_start_time: float
var dragging_container_index: int = -1
var is_potential_tearoff: bool = false

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
	
	if distance > drag_threshold:
		_execute_tearoff()
		_stop_drag_monitoring()

func _stop_drag_monitoring():
	"""Stop monitoring drag movement"""
	is_potential_tearoff = false
	dragging_container_index = -1
	
	if main_window and main_window.get_tree().process_frame.is_connected(_monitor_tearoff_drag):
		main_window.get_tree().process_frame.disconnect(_monitor_tearoff_drag)

func _check_tearoff_completion(position: Vector2):
	"""Check if tearoff should be completed on mouse release"""
	_stop_drag_monitoring()

func _execute_tearoff():
	"""Execute the container tearoff"""
	if dragging_container_index < 0 or dragging_container_index >= main_window.content.open_containers.size():
		return
		
	var container = main_window.content.open_containers[dragging_container_index]
	if not container:
		return
		
	# Check if already torn off
	if container.container_id in tearoff_windows:
		# Focus existing window
		var existing_window = tearoff_windows[container.container_id]
		if is_instance_valid(existing_window):
			existing_window.move_to_front()
			return
		else:
			# Clean up invalid reference
			tearoff_windows.erase(container.container_id)
	
	# Create new tearoff window
	_create_tearoff_window(container)

func _create_tearoff_window(container: InventoryContainer_Base):
	"""Create a new tearoff window for the container"""
	var tearoff_window = ContainerTearOffWindow.new(container, main_window)
	
	# Create a high-priority canvas layer for the tearoff window
	var tearoff_canvas = CanvasLayer.new()
	tearoff_canvas.name = "TearoffWindowLayer"
	tearoff_canvas.layer = 100  # Higher than inventory canvas layer (50)
	main_window.get_tree().current_scene.add_child(tearoff_canvas)
	tearoff_canvas.add_child(tearoff_window)
	
	# Position near mouse
	var mouse_pos = main_window.get_global_mouse_position()
	tearoff_window.position = mouse_pos - Vector2(100, 50)
	
	# Ensure it's on screen
	_ensure_window_on_screen(tearoff_window)
	
	# Show the window and bring it to the front
	tearoff_window.show_window()
	tearoff_window.move_to_front()
	tearoff_window.grab_focus()
	
	# Transfer any active drag state to the new window
	_transfer_active_drag_to_window(tearoff_window)
	
	# Store reference (store both window and its canvas)
	tearoff_windows[container.container_id] = {
		"window": tearoff_window,
		"canvas": tearoff_canvas
	}
	
	# Connect to reattach signal
	tearoff_window.window_reattached.connect(_on_window_reattached)
	tearoff_window.window_closed.connect(_on_tearoff_window_closed.bind(container.container_id))
	
	# Remove container from main window list (but keep it accessible)
	_hide_container_from_main_list(container)
	
	# Emit torn off signal
	tearoff_window.window_torn_off.emit(container, tearoff_window)

func _transfer_active_drag_to_window(tearoff_window: ContainerTearOffWindow):
	"""Transfer any active drag operations to the new tearoff window"""
	var viewport = main_window.get_viewport()
	if not viewport:
		return
	
	# Check for active drag data
	if viewport.has_meta("current_drag_data"):
		var drag_data = viewport.get_meta("current_drag_data")
		
		# Force the viewport to recognize the new window as the input target
		tearoff_window.grab_focus()
		
		# Create a synthetic mouse motion event to continue the drag in the new window
		var current_mouse_pos = tearoff_window.get_global_mouse_position()
		var synthetic_event = InputEventMouseMotion.new()
		synthetic_event.global_position = current_mouse_pos
		synthetic_event.position = tearoff_window.to_local(current_mouse_pos)
		
		# Send the event to the new window
		tearoff_window._gui_input(synthetic_event)

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
	tearoff_windows.erase(container_id)

# Public interface
func is_container_torn_off(container: InventoryContainer_Base) -> bool:
	"""Check if a container is currently torn off"""
	return container.container_id in tearoff_windows

func get_tearoff_window(container: InventoryContainer_Base) -> ContainerTearOffWindow:
	"""Get the tearoff window for a container"""
	return tearoff_windows.get(container.container_id)

func close_all_tearoff_windows():
	"""Close all tearoff windows"""
	for window in tearoff_windows.values():
		if is_instance_valid(window):
			window.hide_window()
			window.queue_free()
	tearoff_windows.clear()

func cleanup():
	"""Cleanup tearoff manager"""
	close_all_tearoff_windows()
	_stop_drag_monitoring()