# InventoryWindowUI.gd - Refactored modular inventory window
class_name InventoryWindowUI
extends Window

# Window properties
@export var window_title: String = "Inventory"
@export var min_window_size: Vector2 = Vector2(400, 300)
@export var default_size: Vector2 = Vector2(800, 600)

# UI Modules
var main_container: VBoxContainer
var header: InventoryWindowHeader
var content: InventoryWindowContent
var item_actions: InventoryItemActions

# State
var inventory_manager: InventoryManager
var open_containers: Array[InventoryContainer] = []
var current_container: InventoryContainer
var active_context_menu: InventoryItemActions

# Window state
var is_locked: bool = false
var window_transparency: float = 1.0

# Signals
signal window_closed()
signal container_switched(container: InventoryContainer)

func _init():
	title = window_title
	size = default_size
	min_size = min_window_size
	
	set_flag(Window.FLAG_RESIZE_DISABLED, false)
	set_flag(Window.FLAG_BORDERLESS, false)
	
	visible = false
	position = Vector2i(1040, 410)

func _ready():
	_setup_ui()
	_connect_signals()
	_find_inventory_manager()
	apply_custom_theme()
	visible = false

func _setup_ui():
	main_container = VBoxContainer.new()
	main_container.name = "MainContainer"
	main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_container)
	
	# Create header module
	header = InventoryWindowHeader.new()
	header.name = "Header"
	main_container.add_child(header)
	
	# Create content module
	content = InventoryWindowContent.new()
	content.name = "Content"
	main_container.add_child(content)
	
	# Create item actions module
	item_actions = InventoryItemActions.new(self)

func _connect_signals():
	close_requested.connect(_on_close_requested)
	
	# Header signals
	header.search_changed.connect(_on_search_changed)
	header.filter_changed.connect(_on_filter_changed)
	header.sort_requested.connect(_on_sort_requested)
	header.transparency_changed.connect(_on_transparency_changed)
	header.lock_toggled.connect(_on_lock_toggled)
	
	# Content signals
	content.container_selected.connect(_on_content_container_selected)
	content.item_activated.connect(_on_item_activated)
	content.item_context_menu.connect(_on_item_context_menu)
	
	# Item actions signals
	item_actions.container_refreshed.connect(_on_container_refreshed)

func _find_inventory_manager():
	var scene_root = get_tree().current_scene
	inventory_manager = _find_inventory_manager_recursive(scene_root)
	
	if inventory_manager:
		header.set_inventory_manager(inventory_manager)
		header.set_inventory_window(self)
		content.set_inventory_manager(inventory_manager)
		item_actions.set_inventory_manager(inventory_manager)
		_populate_container_list()

func _find_inventory_manager_recursive(node: Node) -> InventoryManager:
	if node is InventoryManager:
		return node
	
	for child in node.get_children():
		var result = _find_inventory_manager_recursive(child)
		if result:
			return result
	
	return null

# Container management
func _populate_container_list():
	if not inventory_manager:
		return
	
	open_containers.clear()
	
	var containers = inventory_manager.get_accessible_containers()
	
	# Compact all containers before displaying
	for container in containers:
		if container.get_item_count() > 0:
			container.compact_items()
	
	# Sort containers - player inventory first
	containers.sort_custom(func(a, b): 
		if a.container_id == "player_inventory":
			return true
		elif b.container_id == "player_inventory":
			return false
		return a.container_name < b.container_name
	)
	
	open_containers = containers
	
	# Update content module only
	content.update_containers(open_containers)
	
	# Select player inventory first
	if not open_containers.is_empty():
		_switch_to_container(open_containers[0])
		content.select_container_index(0)

func _switch_to_container(container: InventoryContainer):
	if current_container == container:
		return
	
	current_container = container
	
	# Compact the container before displaying
	if container and container.get_item_count() > 0:
		container.compact_items()
	
	content.select_container(container)
	item_actions.set_current_container(container)
	
	container_switched.emit(container)

# Window behavior overrides
var locked_position: Vector2i

func _notification(what: int):
	# Handle window events if needed
	pass

# Event handlers
func _on_close_requested():
	_close_window()

func _close_window():
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	window_closed.emit()

func _on_content_container_selected(container: InventoryContainer):
	_switch_to_container(container)

func _on_search_changed(text: String):
	# TODO: Implement search filtering
	pass

func _on_filter_changed(filter_type: int):
	# TODO: Implement item filtering
	pass

func _on_sort_requested(sort_type: InventoryManager.SortType):
	if inventory_manager and current_container:
		inventory_manager.sort_container(current_container.container_id, sort_type)

func _on_transparency_changed(value: float):
	window_transparency = value
	if main_container:
		main_container.modulate.a = value

func _on_lock_toggled(locked: bool):
	is_locked = locked
	
	# Store current size and position to maintain consistency
	var current_size = size
	var current_pos = position
	
	# Update window flags based on lock state
	if is_locked:
		# Store current position
		locked_position = current_pos
		# Disable resizing and dragging
		set_flag(Window.FLAG_RESIZE_DISABLED, true)
		# Start position monitoring to snap back if moved
		_start_position_monitoring()
	else:
		# Stop monitoring and re-enable resizing
		_stop_position_monitoring()
		set_flag(Window.FLAG_RESIZE_DISABLED, false)

func _start_position_monitoring():
	# Use a high-frequency timer to immediately snap back position
	var timer = Timer.new()
	timer.name = "PositionLockTimer"
	timer.wait_time = 0.016  # ~60 FPS for smooth snapping
	timer.timeout.connect(_enforce_position_lock)
	add_child(timer)
	timer.start()

func _stop_position_monitoring():
	var timer = get_node_or_null("PositionLockTimer")
	if timer:
		timer.queue_free()

func _enforce_position_lock():
	if is_locked and position != locked_position:
		# Immediately snap back to locked position
		position = locked_position

func _create_fake_titlebar():
	# Just add a visual indicator without trying to block dragging
	var fake_titlebar = Panel.new()
	fake_titlebar.name = "FakeTitlebar"
	fake_titlebar.custom_minimum_size.y = 4
	fake_titlebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Style as a simple yellow bar indicator
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color.YELLOW
	fake_titlebar.add_theme_stylebox_override("panel", style_box)
	
	# Insert at the top of main container
	main_container.add_child(fake_titlebar)
	main_container.move_child(fake_titlebar, 0)

func _remove_fake_titlebar():
	# Remove visual indicator
	var fake_titlebar = main_container.get_node_or_null("FakeTitlebar")
	if fake_titlebar:
		fake_titlebar.queue_free()

func _on_item_activated(item: InventoryItem, slot: InventorySlotUI):
	item_actions.show_item_details_dialog(item)

func _on_item_context_menu(item: InventoryItem, slot: InventorySlotUI, position: Vector2):
	item_actions.show_item_context_menu(item, slot, position)

func _on_container_refreshed():
	refresh_display()
	refresh_container_list()

func _show_empty_area_context_menu(global_pos: Vector2):
	if item_actions:
		item_actions.show_empty_area_context_menu(global_pos)

func _set_context_menu_active(handler: InventoryItemActions):
	active_context_menu = handler

func _clear_context_menu_active():
	active_context_menu = null

func _unhandled_input(event: InputEvent):
	# Handle context menu cleanup only if no other UI handled the input
	if active_context_menu and event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed:
			# Check if we have a valid popup
			if active_context_menu.current_popup and is_instance_valid(active_context_menu.current_popup):
				var popup = active_context_menu.current_popup
				var popup_rect = Rect2(popup.position, popup.size)
				var click_pos = mouse_event.global_position
				
				if not popup_rect.has_point(click_pos):
					# Click is outside popup - close it and clear reference
					active_context_menu._close_current_popup()
					active_context_menu = null
			else:
				# No valid popup but we have a reference - close everything and clear it
				active_context_menu._close_current_popup()
				active_context_menu = null
	
	# Handle window-specific keyboard shortcuts only when visible
	if visible and event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_I, KEY_ESCAPE:
				_close_window()
				get_viewport().set_input_as_handled()
			KEY_F5, KEY_F9:
				refresh_display()
				get_viewport().set_input_as_handled()
			KEY_HOME:
				if not is_locked:
					position = Vector2i(1040, 410)
				get_viewport().set_input_as_handled()

# Public interface
func refresh_display():
	content.refresh_display()

func refresh_container_list():
	if not inventory_manager:
		return
	
	# Update content module with refreshed container info
	content.update_containers(open_containers)

func toggle_visibility():
	if visible:
		hide()
	else:
		show()
		grab_focus()

func bring_to_front():
	grab_focus()

func set_transparency(value: float):
	window_transparency = value
	if main_container:
		main_container.modulate.a = value
	if header:
		header.set_transparency(value)

func get_transparency() -> float:
	return window_transparency

func set_window_locked(locked: bool):
	is_locked = locked
	if header:
		header.set_window_locked(locked)
	_on_lock_toggled(locked)

func is_window_locked() -> bool:
	return is_locked

func _exit_tree():
	_stop_position_monitoring()

# Theme and styling
func apply_custom_theme():
	var theme = Theme.new()
	
	var itemlist_style = StyleBoxFlat.new()
	itemlist_style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	itemlist_style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	itemlist_style.border_width_left = 1
	itemlist_style.border_width_right = 1
	itemlist_style.border_width_top = 1
	itemlist_style.border_width_bottom = 1
	itemlist_style.content_margin_left = 8
	itemlist_style.content_margin_right = 8
	itemlist_style.content_margin_top = 4
	itemlist_style.content_margin_bottom = 4
	
	set_theme(theme)
