# ContainerTearOffWindow.gd - Detached window for individual containers
class_name ContainerTearOffWindow
extends Window_Base

# References
var inventory_manager: InventoryManager
var container: InventoryContainer_Base
var parent_window: InventoryWindow
var content_grid: InventoryGrid
var content_list: InventoryListView
var mass_info_bar: Panel
var mass_info_label: Label
var current_display_mode: InventoryDisplayMode.Mode = InventoryDisplayMode.Mode.GRID
var item_actions: InventoryItemActions

# Signals
signal window_torn_off(container: InventoryContainer_Base, window: ContainerTearOffWindow)
signal window_reattached(container: InventoryContainer_Base)

func _init(tear_container: InventoryContainer_Base, parent_inv_window: InventoryWindow):
	super._init()
	
	container = tear_container
	parent_window = parent_inv_window
	
	if container:
		window_title = container.container_name
	else:
		window_title = "Container"
		
	default_size = Vector2(600, 500)
	min_window_size = Vector2(400, 300)
	max_window_size = Vector2(1200, 800)

func _setup_window_content():
	"""Override base method to add tearoff-specific content"""
	_setup_tearoff_content()

func _setup_tearoff_content():
	"""Setup the torn-off container content"""
	if not container:
		return
		
	# Get inventory manager from parent
	if parent_window:
		inventory_manager = parent_window.inventory_manager
		
	# Create main container
	var main_vbox = VBoxContainer.new()
	main_vbox.name = "MainContainer"
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_content(main_vbox)
	
	# Setup mass info bar
	_setup_mass_info_bar(main_vbox)
	
	# Create content area
	var content_container = Control.new()
	content_container.name = "ContentContainer"
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.clip_contents = true
	main_vbox.add_child(content_container)
	
	# Setup grid display
	_setup_grid_display(content_container)
	
	# Setup list display (initially hidden)
	_setup_list_display(content_container)
	
	# Set initial display mode
	_set_display_mode(current_display_mode)
	
	# Setup item actions
	_setup_item_actions()
	
	# Connect to container signals
	_connect_container_signals()
	
	# Initial display refresh
	call_deferred("_refresh_display")

func _setup_mass_info_bar(parent_container: Control):
	"""Setup mass/volume info bar"""
	mass_info_bar = Panel.new()
	mass_info_bar.name = "MassInfoBar"
	mass_info_bar.custom_minimum_size = Vector2(0, 30)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	style.border_width_top = 1
	mass_info_bar.add_theme_stylebox_override("panel", style)
	
	mass_info_label = Label.new()
	mass_info_label.name = "MassInfoLabel"
	mass_info_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mass_info_label.add_theme_constant_override("margin_left", 8)
	mass_info_label.add_theme_constant_override("margin_right", 8)
	mass_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mass_info_label.add_theme_font_size_override("font_size", 11)
	mass_info_bar.add_child(mass_info_label)
	
	parent_container.add_child(mass_info_bar)

func _setup_grid_display(parent_container: Control):
	"""Setup grid display for container"""
	content_grid = InventoryGrid.new()
	content_grid.name = "ContainerGrid"
	content_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Configure grid properties using the available export variables
	content_grid.slot_size = Vector2(64, 96)
	content_grid.slot_spacing = 20
	content_grid.min_grid_width = 5
	content_grid.min_grid_height = 5
	content_grid.enable_virtual_scrolling = false  # Use traditional grid for tearoff windows
	
	parent_container.add_child(content_grid)
	
	# Set container
	if container:
		content_grid.set_container(container)
	
	# Connect signals
	if content_grid.has_signal("item_activated"):
		content_grid.item_activated.connect(_on_item_activated)
	if content_grid.has_signal("item_context_menu"):
		content_grid.item_context_menu.connect(_on_item_context_menu)
	if content_grid.has_signal("empty_area_context_menu"):
		content_grid.empty_area_context_menu.connect(_on_empty_area_context_menu)

func _setup_list_display(parent_container: Control):
	"""Setup list display for container"""
	content_list = InventoryListView.new()
	content_list.name = "ContainerList"
	content_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_list.visible = false
	
	parent_container.add_child(content_list)
	
	# Set container with correct parameters: container and container_id
	if container:
		content_list.set_container(container, container.container_id)
	
	# Connect signals with correct signatures
	if content_list.has_signal("item_selected"):
		content_list.item_selected.connect(_on_list_item_selected)
	if content_list.has_signal("item_context_menu"):
		content_list.item_context_menu.connect(_on_list_item_context_menu)
	if content_list.has_signal("empty_area_context_menu"):
		content_list.empty_area_context_menu.connect(_on_empty_area_context_menu)

func _setup_item_actions():
	"""Setup item actions for context menus"""
	if not parent_window:
		return
		
	# Use parent window's item actions but set our container
	item_actions = parent_window.item_actions
	if item_actions and container:
		item_actions.set_current_container(container)
		
	# Set item actions on displays
	if content_grid and item_actions:
		content_grid.set_item_actions(item_actions)

func _connect_container_signals():
	"""Connect to container change signals"""
	if not container:
		return
		
	# Connect container signals
	if container.has_signal("item_added") and not container.item_added.is_connected(_on_container_changed):
		container.item_added.connect(_on_container_changed)
	if container.has_signal("item_removed") and not container.item_removed.is_connected(_on_container_changed):
		container.item_removed.connect(_on_container_changed)
	if container.has_signal("item_moved") and not container.item_moved.is_connected(_on_container_changed):
		container.item_moved.connect(_on_container_changed)

func _disconnect_container_signals():
	"""Disconnect from container signals"""
	if not container:
		return
		
	if container.has_signal("item_added") and container.item_added.is_connected(_on_container_changed):
		container.item_added.disconnect(_on_container_changed)
	if container.has_signal("item_removed") and container.item_removed.is_connected(_on_container_changed):
		container.item_removed.disconnect(_on_container_changed)
	if container.has_signal("item_moved") and container.item_moved.is_connected(_on_container_changed):
		container.item_moved.disconnect(_on_container_changed)

func _gui_input(event: InputEvent):
	"""Handle input events for the tearoff window"""
	# If we have content displays, forward mouse events to them
	if event is InputEventMouseMotion:
		var motion_event = event as InputEventMouseMotion
		
		# Forward to the currently visible display
		match current_display_mode:
			InventoryDisplayMode.Mode.GRID:
				if content_grid and content_grid.visible:
					content_grid._gui_input(motion_event)
			InventoryDisplayMode.Mode.LIST:
				if content_list and content_list.visible:
					content_list._gui_input(motion_event)

func _set_display_mode(mode: InventoryDisplayMode.Mode):
	"""Set the display mode for this window"""
	current_display_mode = mode
	
	match mode:
		InventoryDisplayMode.Mode.GRID:
			if content_grid:
				content_grid.visible = true
			if content_list:
				content_list.visible = false
		InventoryDisplayMode.Mode.LIST:
			if content_grid:
				content_grid.visible = false
			if content_list:
				content_list.visible = true

func set_display_mode(mode: InventoryDisplayMode.Mode):
	"""Public method to change display mode"""
	_set_display_mode(mode)
	_refresh_display()

func _refresh_display():
	"""Refresh the current display"""
	if not container:
		return
		
	match current_display_mode:
		InventoryDisplayMode.Mode.GRID:
			if content_grid:
				content_grid.refresh_display()
		InventoryDisplayMode.Mode.LIST:
			if content_list:
				content_list.refresh_display()
	
	_update_mass_info()

func _update_mass_info():
	"""Update mass/volume information"""
	if not container or not mass_info_label:
		if mass_info_label:
			mass_info_label.text = "No container"
		return
	
	var info = container.get_container_info()
	
	var text = "Items: %d (%d types)  |  " % [info.total_quantity, info.item_count]
	text += "Volume: %.1f/%.1f m³ (%.1f%%)  |  " % [info.volume_used, info.volume_max, info.volume_percentage]
	text += "Mass: %.1f t  |  " % info.total_mass
	text += "Value: " + _format_currency(info.total_value)
	
	mass_info_label.text = text
	
	if info.volume_percentage > 90:
		mass_info_label.add_theme_color_override("font_color", Color.RED)
	elif info.volume_percentage > 75:
		mass_info_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		mass_info_label.add_theme_color_override("font_color", Color.WHITE)

func _format_currency(value: float) -> String:
	"""Format currency value"""
	if value >= 1000000:
		return "%.1fM ISK" % (value / 1000000.0)
	elif value >= 1000:
		return "%.1fK ISK" % (value / 1000.0)
	else:
		return "%.0f ISK" % value

# Signal handlers
func _on_container_changed(_item: InventoryItem_Base = null, _slot_position: Vector2i = Vector2i.ZERO):
	"""Handle container changes"""
	call_deferred("_refresh_display")

func _on_item_activated(item: InventoryItem_Base, slot: InventorySlot):
	"""Handle item activation"""
	if item_actions:
		item_actions.handle_item_activated(item, slot)

func _on_item_context_menu(item: InventoryItem_Base, slot: InventorySlot, position: Vector2):
	"""Handle item context menu"""
	if item_actions:
		item_actions.show_item_context_menu(item, slot, position)

func _on_empty_area_context_menu(position: Vector2):
	"""Handle empty area context menu"""
	if item_actions:
		item_actions.show_empty_area_context_menu(position)

# List view specific signal handlers
func _on_list_item_selected(item: InventoryItem_Base):
	"""Handle item selection from list view"""
	# Create a dummy slot for compatibility with grid-style handlers
	var dummy_slot = InventorySlot.new()
	dummy_slot.set_item(item)
	if container:
		dummy_slot.set_container_id(container.container_id)
	
	_on_item_activated(item, dummy_slot)

func _on_list_item_context_menu(item: InventoryItem_Base, position: Vector2):
	"""Handle item context menu from list view"""
	# Create a dummy slot for compatibility with grid-style handlers
	var dummy_slot = InventorySlot.new()
	dummy_slot.set_item(item)
	if container:
		dummy_slot.set_container_id(container.container_id)
	
	_on_item_context_menu(item, dummy_slot, position)

# Override close behavior
func _on_window_closed():
	"""Handle window close - reattach container to main window"""
	_disconnect_container_signals()
	
	# Emit reattach signal
	window_reattached.emit(container)
	
	# Call parent cleanup
	super._on_window_closed()

# Public interface
func get_container() -> InventoryContainer_Base:
	return container

func reattach_to_main_window():
	"""Reattach this container to the main window"""
	_on_window_closed()