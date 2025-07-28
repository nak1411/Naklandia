# InventoryWindowUI.gd - Using custom window implementation
class_name InventoryWindow
extends Window_Base

# Window properties
@export var inventory_title: String = "Inventory"
@export var min_window_size: Vector2 = Vector2(400, 300)
@export var default_size: Vector2 = Vector2(800, 600)

# UI Modules
var inventory_container: VBoxContainer
var header: InventoryWindowHeader
var content: InventoryWindowContent
var item_actions: InventoryItemActions
var inventory_integration: InventoryIntegration

# State
var inventory_manager: InventoryManager
var open_containers: Array[InventoryContainer_Base] = []
var current_container: InventoryContainer_Base
var active_context_menu: InventoryItemActions

# Window state
var is_locked: bool = false

# Signals
signal container_switched(container: InventoryContainer_Base)

func _init():
	super._init()
	set_window_title(inventory_title)
	size = Vector2i(default_size)
	min_size = Vector2i(min_window_size)
	visible = false
	position = Vector2i(1040, 410)

func _ready():
	super._ready()
	await get_tree().process_frame  # Wait for parent to be fully ready
	_setup_inventory_ui()
	_connect_inventory_signals()
	_find_inventory_manager()
	apply_custom_theme()
	visible = false

# InventoryWindow.gd - Modified _setup_inventory_ui method for left panel full height layout
# Replace the existing _setup_inventory_ui method in InventoryWindow.gd

func _setup_inventory_ui():
	# Create main horizontal container (no margins)
	var main_hsplit = HSplitContainer.new()
	main_hsplit.name = "MainHSplit"
	main_hsplit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_hsplit.split_offset = 200  # Match the container list width
	
	# Add directly to the custom window's content area
	add_content(main_hsplit)
	
	# LEFT SIDE: Container list panel (full height, small top padding)
	var left_container_panel = MarginContainer.new()
	left_container_panel.name = "LeftContainerPanel"
	left_container_panel.custom_minimum_size.x = 180
	left_container_panel.size_flags_horizontal = Control.SIZE_FILL
	left_container_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Add small top margin for padding from title bar
	left_container_panel.add_theme_constant_override("margin_top", 6)
	main_hsplit.add_child(left_container_panel)
	
	# Create the container list directly
	var container_list = ItemList.new()
	container_list.name = "ContainerList"
	container_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container_list.custom_minimum_size = Vector2(160, 200)
	container_list.auto_height = true
	container_list.allow_rmb_select = false
	container_list.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Style the container list
	var list_style = StyleBoxFlat.new()
	list_style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	list_style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	list_style.border_width_left = 1
	list_style.border_width_right = 1
	list_style.border_width_top = 1
	list_style.border_width_bottom = 1
	list_style.content_margin_left = 6
	list_style.content_margin_right = 6
	list_style.content_margin_top = 4
	list_style.content_margin_bottom = 4
	container_list.add_theme_stylebox_override("panel", list_style)
	
	left_container_panel.add_child(container_list)
	
	# RIGHT SIDE: Header + Content area (matches mass bar width)
	var right_panel = VBoxContainer.new()
	right_panel.name = "RightPanel"
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Add small margins to match the original content area
	right_panel.add_theme_constant_override("margin_left", 4)
	right_panel.add_theme_constant_override("margin_right", 4)
	right_panel.add_theme_constant_override("margin_bottom", 4)
	
	main_hsplit.add_child(right_panel)
	
	# Header with top margin (positioned over right panel only)
	var header_wrapper = MarginContainer.new()
	header_wrapper.name = "HeaderWrapper"
	header_wrapper.add_theme_constant_override("margin_top", 6)  # Space from title bar
	right_panel.add_child(header_wrapper)
	
	header = InventoryWindowHeader.new()
	header.name = "Header"
	header_wrapper.add_child(header)
	
	# Content area for mass bar + inventory grid (no additional top margin)
	content = InventoryWindowContent.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(content)
	
	# Tell content to use external container list and skip creating its own left panel
	content.set_external_container_list(container_list)
	
	# Connect the external container list to content
	container_list.item_selected.connect(_on_container_list_selected)
	
	# Create item actions module
	item_actions = InventoryItemActions.new(self)

# Add this method to handle container list selection
func _on_container_list_selected(index: int):
	if content and index >= 0 and index < open_containers.size():
		content.select_container(open_containers[index])

func _connect_inventory_signals():
	# Connect custom window signals
	window_closed.connect(_on_close_requested)
	window_locked_changed.connect(_on_window_locked_changed)
	transparency_changed.connect(_on_transparency_changed)
	
	# Header signals
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
	content.update_containers(open_containers)
	
	# Auto-select first container
	if open_containers.size() > 0:
		select_container(open_containers[0])
		content.select_container_index(0)

func select_container(container: InventoryContainer_Base):
	if not container:
		return
	
	current_container = container
	content.select_container(container)
	
	# Update container list selection
	for i in range(open_containers.size()):
		if open_containers[i] == container:
			content.select_container_index(i)
			break
	
	container_switched.emit(container)

func refresh_display():
	if content:
		content.refresh_display()

func refresh_container_list():
	if not inventory_manager:
		return
	
	var containers = inventory_manager.get_accessible_containers()
	
	# Sort containers - player inventory first
	containers.sort_custom(func(a, b): 
		if a.container_id == "player_inventory":
			return true
		elif b.container_id == "player_inventory":
			return false
		return a.container_name < b.container_name
	)
	
	open_containers = containers
	content.update_containers(open_containers)

func get_current_container() -> InventoryContainer_Base:
	return current_container

func get_inventory_grid() -> InventoryGrid:
	if content:
		return content.get_inventory_grid()
	return null

# Signal handlers
func _on_close_requested():
	visible = false

func _on_window_locked_changed(locked: bool):
	is_locked = locked
	if locked:
		_add_lock_indicator()
	else:
		_remove_lock_indicator()

func _on_transparency_changed(transparency: float):
	# Apply transparency to header elements specifically
	if header and header.has_method("set_transparency"):
		header.set_transparency(transparency)
	
	# Apply transparency to content area
	if content and content.has_method("set_transparency"):
		content.set_transparency(transparency)
	
	# Apply transparency to any inventory-specific elements
	_apply_inventory_transparency(transparency)

func _apply_inventory_transparency(transparency: float):
	"""Apply transparency to inventory-specific UI elements"""
	
	# Find and apply transparency to mass info bar
	var mass_bar = get_node_or_null("MainContainer/ContentArea/MainHSplit/RightPanel/Content/MassInfoBar")
	if mass_bar:
		_apply_panel_transparency_to_node(mass_bar, transparency)
	
	# Find and apply transparency to container list
	var container_list = get_node_or_null("MainContainer/ContentArea/MainHSplit/LeftContainerPanel/ContainerList") 
	if container_list:
		_apply_itemlist_transparency_to_node(container_list, transparency)
	
	# Find and apply transparency to inventory grid background
	var grid_areas = _find_nodes_by_name_recursive(self, "InventoryGrid")
	for grid in grid_areas:
		if grid.has_method("set_transparency"):
			grid.set_transparency(transparency)

func _apply_panel_transparency_to_node(node: Control, transparency: float):
	"""Helper to apply panel transparency to a specific node"""
	if node is Panel:
		var style_box = node.get_theme_stylebox("panel")
		if style_box and style_box is StyleBoxFlat:
			var style_copy = style_box.duplicate() as StyleBoxFlat
			var current_color = style_copy.bg_color
			current_color.a = current_color.a * transparency
			style_copy.bg_color = current_color
			node.add_theme_stylebox_override("panel", style_copy)

func _apply_itemlist_transparency_to_node(node: Control, transparency: float):
	"""Helper to apply itemlist transparency to a specific node"""
	if node is ItemList:
		var style_box = node.get_theme_stylebox("panel")
		if style_box and style_box is StyleBoxFlat:
			var style_copy = style_box.duplicate() as StyleBoxFlat
			var current_color = style_copy.bg_color
			current_color.a = current_color.a * transparency
			style_copy.bg_color = current_color
			node.add_theme_stylebox_override("panel", style_copy)

func _find_nodes_by_name_recursive(node: Node, target_name: String) -> Array:
	"""Find all nodes with a specific name recursively"""
	var result = []
	
	if node.name == target_name:
		result.append(node)
	
	for child in node.get_children():
		result.append_array(_find_nodes_by_name_recursive(child, target_name))
	
	return result

func _on_search_changed(text: String):
	# TODO: Implement search functionality
	pass

func _on_filter_changed(filter_type: int):
	# TODO: Implement filter functionality
	pass

func _on_sort_requested(sort_type: InventoryManager.SortType):
	if inventory_manager and current_container:
		inventory_manager.sort_container(current_container.container_id, sort_type)
		refresh_display()

func _on_content_container_selected(container: InventoryContainer_Base):
	select_container(container)

func _add_lock_indicator():
	# Find the right panel or content area to add the lock indicator to
	var target_container = _find_lock_indicator_parent()
	
	if not target_container:
		print("Warning: Could not find suitable parent for lock indicator")
		return
	
	var lock_indicator = Panel.new()
	lock_indicator.name = "LockIndicator"
	lock_indicator.custom_minimum_size.y = 25
	lock_indicator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var lock_label = Label.new()
	lock_label.text = "🔒 WINDOW LOCKED"
	lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lock_label.add_theme_color_override("font_color", Color.BLACK)
	lock_label.add_theme_font_size_override("font_size", 12)
	lock_indicator.add_child(lock_label)
	
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color.YELLOW
	lock_indicator.add_theme_stylebox_override("panel", style_box)
	
	# Add to the appropriate container
	target_container.add_child(lock_indicator)
	target_container.move_child(lock_indicator, 0)

func _find_lock_indicator_parent() -> Control:
	"""Find the best container to add the lock indicator to"""
	
	# Try to find RightPanel first (from the new UI structure)
	var right_panel = get_node_or_null("MainContainer/ContentArea/MainHSplit/RightPanel")
	if right_panel:
		return right_panel
	
	# Try to find the content area
	var content_area = get_node_or_null("MainContainer/ContentArea") 
	if content_area:
		return content_area
	
	# Try to find any VBoxContainer that could work
	var main_container = get_node_or_null("MainContainer")
	if main_container:
		var vboxes = _find_nodes_by_type(main_container, VBoxContainer)
		if vboxes.size() > 0:
			return vboxes[0]
	
	# Last resort - use the main container itself
	return get_node_or_null("MainContainer")

func _find_nodes_by_type(parent: Node, type) -> Array:
	"""Recursively find all nodes of a specific type"""
	var result = []
	
	if parent.get_class() == type.get_class():
		result.append(parent)
	
	for child in parent.get_children():
		result.append_array(_find_nodes_by_type(child, type))
	
	return result

func _remove_lock_indicator():
	# Look for lock indicator in multiple possible locations
	var locations_to_check = [
		"MainContainer/ContentArea/MainHSplit/RightPanel/LockIndicator",
		"MainContainer/ContentArea/LockIndicator", 
		"MainContainer/LockIndicator"
	]
	
	for location in locations_to_check:
		var lock_indicator = get_node_or_null(location)
		if lock_indicator:
			lock_indicator.queue_free()
			return
	
	# If not found in expected locations, search recursively
	var main_container = get_node_or_null("MainContainer")
	if main_container:
		var lock_indicator = _find_lock_indicator_recursive(main_container)
		if lock_indicator:
			lock_indicator.queue_free()

func _find_lock_indicator_recursive(node: Node) -> Node:
	"""Recursively find the lock indicator"""
	if node.name == "LockIndicator":
		return node
	
	for child in node.get_children():
		var result = _find_lock_indicator_recursive(child)
		if result:
			return result
	
	return null

func _on_item_activated(item: InventoryItem_Base, slot: InventorySlot):
	item_actions.show_item_details_dialog(item)

func _on_item_context_menu(item: InventoryItem_Base, slot: InventorySlot, position: Vector2):
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
	
	# Handle window-specific keyboard shortcuts
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_I:
				# Toggle inventory (close when pressing I while window is open)
				if visible and inventory_integration:
					inventory_integration.close_from_window()
					get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if visible:
					if inventory_integration:
						inventory_integration.close_from_window()
					else:
						visible = false
					get_viewport().set_input_as_handled()
			KEY_F5:
				refresh_display()
				get_viewport().set_input_as_handled()

# Theme management
func apply_custom_theme():
	# Apply any custom theming to the inventory window
	pass
	
func set_inventory_integration(integration: InventoryIntegration):
	inventory_integration = integration
