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
	header.container_changed.connect(_on_header_container_changed)
	header.search_changed.connect(_on_search_changed)
	header.filter_changed.connect(_on_filter_changed)
	header.sort_requested.connect(_on_sort_requested)
	
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
	
	# Update modules
	header.update_containers(open_containers)
	content.update_containers(open_containers)
	
	# Select player inventory first
	if not open_containers.is_empty():
		_switch_to_container(open_containers[0])
		header.select_container_index(0)
		content.select_container_index(0)

func _switch_to_container(container: InventoryContainer):
	var current_container = content.get_current_container()
	if current_container == container:
		return
	
	# Compact the container before displaying
	if container and container.get_item_count() > 0:
		container.compact_items()
	
	content.select_container(container)
	item_actions.set_current_container(container)
	
	container_switched.emit(container)

# Event handlers
func _on_close_requested():
	_close_window()

func _close_window():
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	window_closed.emit()

func _on_header_container_changed(container: InventoryContainer):
	_switch_to_container(container)
	var index = open_containers.find(container)
	if index != -1:
		content.select_container_index(index)

func _on_content_container_selected(container: InventoryContainer):
	_switch_to_container(container)
	var index = open_containers.find(container)
	if index != -1:
		header.select_container_index(index)

func _on_search_changed(text: String):
	# TODO: Implement search filtering
	pass

func _on_filter_changed(filter_type: int):
	# TODO: Implement item filtering
	pass

func _on_sort_requested(sort_type: InventoryManager.SortType):
	var current_container = content.get_current_container()
	if inventory_manager and current_container:
		inventory_manager.sort_container(current_container.container_id, sort_type)

func _on_item_activated(item: InventoryItem, slot: InventorySlotUI):
	item_actions.show_item_details_dialog(item)

func _on_item_context_menu(item: InventoryItem, slot: InventorySlotUI, position: Vector2):
	item_actions.show_item_context_menu(item, slot, position)

func _on_container_refreshed():
	refresh_display()
	refresh_container_list()

# Public interface
func refresh_display():
	content.refresh_display()

func refresh_container_list():
	if not inventory_manager:
		return
	
	# Update container text for each container
	for i in range(open_containers.size()):
		var container = open_containers[i]
		
		var total_qty = container.get_total_quantity()
		var unique_items = container.get_item_count()
		
		var container_text = ""
		if unique_items > 1:
			container_text = "%s (%d items, %d types)" % [container.container_name, total_qty, unique_items]
		else:
			container_text = "%s (%d items)" % [container.container_name, total_qty]
	
	# Update modules with refreshed container info
	header.update_containers(open_containers)
	content.update_containers(open_containers)

func toggle_visibility():
	if visible:
		hide()
	else:
		show()
		grab_focus()

func bring_to_front():
	grab_focus()

# Keyboard input
func _input(event: InputEvent):
	if not visible:
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_I, KEY_ESCAPE:
				_close_window()
				get_viewport().set_input_as_handled()
			KEY_F5, KEY_F9:
				refresh_display()
				get_viewport().set_input_as_handled()
			KEY_HOME:
				position = Vector2i(1040, 410)
				get_viewport().set_input_as_handled()

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
