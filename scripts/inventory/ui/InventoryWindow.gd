# InventoryWindow.gd - Inventory-specific window implementation
class_name InventoryWindow
extends Window_Base

# Inventory-specific properties
var inventory_manager: InventoryManager
var inventory_container: VBoxContainer
var header: InventoryWindowHeader
var content: InventoryWindowContent
var item_actions: InventoryItemActions

# Inventory-specific state
var open_containers: Array[InventoryContainer_Base] = []
var current_container: InventoryContainer_Base

# Inventory-specific signals
signal container_switched(container: InventoryContainer_Base)

func _init():
	super._init()
	
	# Set inventory-specific defaults
	window_title = "Inventory"
	default_size = Vector2(800, 600)
	min_window_size = Vector2(400, 300)
	max_window_size = Vector2(1400, 1000)

func _setup_window_content():
	"""Override base method to add inventory-specific content"""
	print("Setting up inventory window content...")
	
	# Call the original content setup method
	_setup_content()

func _setup_content():
	"""Setup inventory-specific content"""
	# Create main inventory container
	inventory_container = VBoxContainer.new()
	inventory_container.name = "InventoryContainer"
	inventory_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_content(inventory_container)
	
	# Create the header (search, filter, sort)
	header = InventoryWindowHeader.new()
	header.name = "InventoryHeader"
	inventory_container.add_child(header)
	
	# Connect header signals
	if header:
		if header.has_signal("search_changed"):
			header.search_changed.connect(_on_search_changed)
		if header.has_signal("filter_changed"):
			header.filter_changed.connect(_on_filter_changed)
		if header.has_signal("sort_requested"):
			header.sort_requested.connect(_on_sort_requested)
		if header.has_signal("display_mode_changed"):
			header.display_mode_changed.connect(_on_display_mode_changed)

func _on_display_mode_changed(mode: InventoryDisplayMode.Mode):
	if content and content.has_method("set_display_mode"):
		content.set_display_mode(mode)
	
func _on_container_list_item_selected(index: int):
	"""Handle container list selection"""
	print("Container list item selected: ", index)
	
	if index >= 0 and index < open_containers.size():
		var selected_container = open_containers[index]
		print("Switching to container: ", selected_container.container_name)
		
		# Update current container
		current_container = selected_container
		
		# Set container on content
		if content and content.has_method("select_container"):
			content.select_container(selected_container)
		
		# Update item actions
		if item_actions and item_actions.has_method("set_current_container"):
			item_actions.set_current_container(selected_container)
		
		# Emit signal
		container_switched.emit(selected_container)
		
		print("Container switch complete!")

func _setup_inventory_content():
	"""Initialize inventory-specific UI components"""
	# Create main inventory container
	inventory_container = VBoxContainer.new()
	inventory_container.name = "InventoryContainer"
	inventory_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_content(inventory_container)
	
	# Create header
	header = InventoryWindowHeader.new()
	header.name = "InventoryHeader"
	inventory_container.add_child(header)
	
	# Create content
	content = InventoryWindowContent.new()
	content.name = "InventoryContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_container.add_child(content)
	
	# Connect signals
	if header:
		if header.has_signal("container_selected"):
			header.container_selected.connect(_on_container_selected_from_header)
		if header.has_signal("search_text_changed"):
			header.search_text_changed.connect(_on_search_text_changed_from_header)
	
	if content:
		if content.has_signal("container_selected"):
			content.container_selected.connect(_on_container_selected_from_content)
		if content.has_signal("item_activated"):
			content.item_activated.connect(_on_item_activated_from_content)
		if content.has_signal("item_context_menu"):
			content.item_context_menu.connect(_on_item_context_menu_from_content)
		
		# Connect window resize to trigger grid reflow
		window_resized.connect(_on_window_resized_for_grid)
	
	# Initialize content with inventory manager if available
	if inventory_manager:
		_initialize_inventory_content()
	
	_setup_item_actions()

func _setup_options_dropdown():
	"""Setup the options dropdown for inventory-specific actions"""
	options_dropdown = DropDownMenu_Base.new()
	options_dropdown.name = "OptionsDropdown"
	
	# Add inventory-specific options
	_update_options_dropdown_text()
	
	# Connect dropdown signals
	if options_dropdown.has_signal("item_selected"):
		options_dropdown.item_selected.connect(_on_options_dropdown_selected)
	if options_dropdown.has_signal("menu_closed"):
		options_dropdown.menu_closed.connect(_on_options_dropdown_closed)

func _setup_item_actions():
	"""Initialize the item actions handler for context menus"""
	var scene_window = get_viewport()
	if scene_window is Window:
		item_actions = InventoryItemActions.new(scene_window)
	else:
		var parent_window = _find_parent_window()
		if parent_window:
			item_actions = InventoryItemActions.new(parent_window)
		else:
			push_error("Could not find parent window for InventoryItemActions")
			return
	
	# Set the inventory manager on item_actions
	if inventory_manager:
		item_actions.set_inventory_manager(inventory_manager)
	
	# Connect to inventory manager updates
	if item_actions.has_signal("container_refreshed"):
		item_actions.container_refreshed.connect(_on_container_refreshed)

func _find_parent_window() -> Window:
	"""Find the parent window in the scene tree"""
	var current = get_parent()
	while current:
		if current is Window:
			return current
		current = current.get_parent()
	return null

func _initialize_inventory_content():
	"""Initialize the inventory content with the inventory manager"""
	print("Initializing inventory content with manager...")
	
	if not content or not inventory_manager:
		print("Missing content or inventory_manager")
		return
	
	# Set inventory manager on content
	if content.has_method("set_inventory_manager"):
		content.set_inventory_manager(inventory_manager)
		print("Set inventory manager on content")
	
	# Get all accessible containers, not just player inventory
	var all_containers = inventory_manager.get_accessible_containers()
	print("Found ", all_containers.size(), " containers")
	
	if all_containers.size() > 0:
		open_containers.clear()
		open_containers.append_array(all_containers)
		
		# Set player inventory as default if available, otherwise use first container
		var default_container = null
		for container in all_containers:
			if container.container_id == "player_inventory":
				default_container = container
				break
		
		if not default_container:
			default_container = all_containers[0]
		
		print("Using default container: ", default_container.container_name)
		
		# IMPORTANT: Set the current container first
		current_container = default_container
		
		# Set current container on item_actions too
		if item_actions and item_actions.has_method("set_current_container"):
			item_actions.set_current_container(current_container)
			print("Set current container on item_actions")
		
		# Update containers list in content with ALL containers
		if content.has_method("update_containers"):
			content.update_containers(all_containers)
			print("Updated containers list in content")
		
		# Then select it in the content
		if content.has_method("select_container"):
			content.select_container(default_container)
			print("Selected default container in content")
			
		# Select the default container in the list
		var default_index = 0
		for i in range(all_containers.size()):
			if all_containers[i] == current_container:
				default_index = i
				break
		
		if content.has_method("select_container_index"):
			content.select_container_index(default_index)
			print("Selected container index: ", default_index)
	
	# Force a refresh of the display
	if content.has_method("refresh_display"):
		content.refresh_display()
		print("Refreshed content display")
	
	print("Inventory content initialization complete!")

func _update_options_dropdown_text():
	"""Update options dropdown with inventory-specific options"""
	if not options_dropdown:
		return
	
	var options = [
		"Sort by Name",
		"Sort by Type", 
		"Sort by Rarity",
		"Sort by Quantity",
		"---",
		"Auto-Stack Items",
		"Show Item Details",
		"---",
		"Export Inventory",
		"Import Inventory"
	]
	
	if options_dropdown.has_method("set_items"):
		options_dropdown.set_items(options)

# Signal handlers for inventory-specific events
func _on_container_selected_from_header(container: InventoryContainer_Base):
	_switch_container(container)

func _on_container_selected_from_content(container: InventoryContainer_Base):
	_switch_container(container)

func _on_search_text_changed_from_header(search_text: String):
	if content and content.has_method("filter_items"):
		content.filter_items(search_text)

func _on_item_activated_from_content(item: InventoryItem_Base, slot: InventorySlot):
	if item_actions and item_actions.has_method("handle_item_activation"):
		item_actions.handle_item_activation(item, slot)

func _on_item_context_menu_from_content(item: InventoryItem_Base, slot: InventorySlot, global_position: Vector2):
	if item_actions and item_actions.has_method("show_item_context_menu"):
		item_actions.show_item_context_menu(item, slot, global_position)

func _on_window_resized_for_grid(_new_size: Vector2i):
	"""Handle window resize for inventory grid"""
	if content and content.inventory_grid and content.inventory_grid.has_method("handle_window_resize"):
		content.inventory_grid.handle_window_resize()

func _on_options_dropdown_selected(index: int):
	"""Handle options dropdown selection"""
	# Implement inventory-specific option handling
	pass

func _on_options_dropdown_closed():
	"""Handle options dropdown close"""
	pass

func _on_container_refreshed():
	"""Handle container refresh from item actions"""
	if content and content.has_method("refresh_display"):
		content.refresh_display()

func _switch_container(container: InventoryContainer_Base):
	"""Switch to a different inventory container"""
	current_container = container
	container_switched.emit(container)
	
	if content and content.has_method("display_container"):
		content.display_container(container)

# Override base class close behavior
func _on_window_closed():
	"""Override from Window_Base - handle inventory window close"""
	# Find the inventory integration and close properly
	var integration = _find_inventory_integration(get_tree().current_scene)
	if integration:
		# Call the integration's close method to restore player input
		integration.is_inventory_open = false
		integration._set_player_input_enabled(true)
		
		# Restore mouse mode if not paused
		if not integration._is_pause_menu_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
		# Save position
		integration._save_window_position()
		
		# Emit the signal
		integration.inventory_toggled.emit(false)
	else:
		# Fallback if integration not found
		_reenable_player_input_fallback()

func _save_inventory_state():
	"""Save inventory-specific state"""
	# Implement inventory state saving if needed
	pass

# Public interface methods for inventory management
func set_inventory_manager(manager: InventoryManager):
	inventory_manager = manager
	
	# Set up item actions now that we have inventory manager
	if not item_actions:
		_setup_item_actions()
	
	# Also set/update it on item_actions if it exists
	if item_actions and item_actions.has_method("set_inventory_manager"):
		item_actions.set_inventory_manager(inventory_manager)
	
	# Initialize content with inventory manager
	if manager:
		_initialize_inventory_content()

func get_current_container() -> InventoryContainer_Base:
	return current_container
	
func show_window():
	"""Show inventory window with grid layout fix"""
	super.show_window()
	move_to_front()
	_fix_initial_grid_layout()

# Lock visual implementation
func _update_lock_visual():
	"""Update lock indicator visibility"""
	if not lock_indicator:
		_setup_lock_indicator()
	
	if is_locked:
		lock_indicator.visible = true
		# Position it to the left of the options button
		if options_button:
			var options_x = options_button.position.x
			lock_indicator.position = Vector2(options_x - 28, (title_bar_height - 24) / 2)
	else:
		lock_indicator.visible = false

func _setup_lock_indicator():
	"""Create lock indicator icon"""
	if lock_indicator:
		return
		
	lock_indicator = Label.new()
	lock_indicator.name = "LockIndicator"
	lock_indicator.text = "🔒"
	lock_indicator.add_theme_font_size_override("font_size", 16)
	lock_indicator.add_theme_color_override("font_color", Color.YELLOW)
	lock_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock_indicator.size = Vector2(24, 24)
	lock_indicator.visible = false
	title_bar.add_child(lock_indicator)

# Options dropdown methods
func _show_transparency_dialog():
	"""Show transparency adjustment dialog"""
	var dialog = AcceptDialog.new()
	dialog.title = "Window Transparency"
	dialog.size = Vector2i(300, 150)
	
	var vbox = VBoxContainer.new()
	var label = Label.new()
	label.text = "Adjust window transparency:"
	vbox.add_child(label)
	
	var slider = HSlider.new()
	slider.min_value = 0.3
	slider.max_value = 1.0
	slider.step = 0.1
	slider.value = modulate.a
	slider.custom_minimum_size.x = 250
	vbox.add_child(slider)
	
	dialog.add_child(vbox)
	slider.value_changed.connect(func(value): modulate.a = value)
	
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())

func _toggle_window_lock():
	"""Toggle window lock state"""
	set_window_locked(!is_locked)
	_update_options_dropdown_text()

# Grid layout fix
func _fix_initial_grid_layout():
	"""Fix the initial grid layout after window is shown"""
	await get_tree().process_frame
	
	if content and content.inventory_grid and content.current_container:
		content.inventory_grid._initialize_with_proper_size()

# Inventory-specific helpers
func get_inventory_grid():
	"""Get reference to the inventory grid"""
	if content and content.has_method("get_inventory_grid"):
		return content.get_inventory_grid()
	return null

func update_mass_info():
	"""Update the mass info bar - delegate to content"""
	if content and content.has_method("update_mass_info"):
		content.update_mass_info()

# Helper methods for player input management
func _find_inventory_integration(node: Node) -> InventoryIntegration:
	if node is InventoryIntegration:
		return node
	
	for child in node.get_children():
		var result = _find_inventory_integration(child)
		if result:
			return result
	return null

func _reenable_player_input_fallback():
	"""Fallback method to re-enable player input"""
	var scene_root = get_tree().current_scene
	var player_node = _find_node_by_name_recursive(scene_root, "Player")
	
	if player_node:
		player_node.process_mode = Node.PROCESS_MODE_INHERIT
	
	var input_managers = get_tree().get_nodes_in_group("input_managers")
	for input_manager in input_managers:
		input_manager.process_mode = Node.PROCESS_MODE_INHERIT
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _find_node_by_name_recursive(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	
	for child in node.get_children():
		var result = _find_node_by_name_recursive(child, target_name)
		if result:
			return result
	return null
	
# Header signal handlers
func _on_search_changed(text: String):
	"""Handle search text changes from header"""
	if not content:
		return
	
	# Get the inventory grid to apply the search
	var grid = get_inventory_grid()
	if grid and grid.has_method("apply_search"):
		grid.apply_search(text)

func _on_filter_changed(filter_type: int):
	"""Handle filter changes from header"""
	if not content:
		return
	
	# Get the inventory grid to apply the filter
	var grid = get_inventory_grid()
	if grid and grid.has_method("apply_filter"):
		grid.apply_filter(filter_type)

func _on_sort_requested(sort_type):
	"""Handle sort requests from header"""
	if not inventory_manager or not current_container:
		return
	
	# Call the sort function on the inventory manager
	inventory_manager.sort_container(current_container.container_id, sort_type)
