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

# Header components (same as main window)
var header: InventoryWindowHeader
var inventory_container: VBoxContainer
var content_container: Control

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
	"""Setup the torn-off container content with full functionality"""
	if not container:
		return
		
	# Get inventory manager from parent
	if parent_window:
		inventory_manager = parent_window.inventory_manager
		
	# Create main inventory container (same structure as main window)
	inventory_container = VBoxContainer.new()
	inventory_container.name = "InventoryContainer"
	inventory_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_content(inventory_container)
	
	# Create header with search, filter, sort, and display mode buttons
	header = InventoryWindowHeader.new()
	header.name = "TearoffHeader"
	inventory_container.add_child(header)
	
	# Setup mass info bar at the top (after header)
	_setup_mass_info_bar(inventory_container)
	
	# Create content area
	content_container = Control.new()
	content_container.name = "ContentContainer"
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.clip_contents = true
	inventory_container.add_child(content_container)
	
	# Setup grid display
	_setup_grid_display(content_container)
	
	# Setup list display (initially hidden)
	_setup_list_display(content_container)
	
	# Set initial display mode
	_set_display_mode(current_display_mode)
	
	# Setup item actions
	_setup_item_actions()
	
	# Connect header signals
	_connect_header_signals()
	
	# Connect to container signals
	_connect_container_signals()
	
	# Set up header with inventory manager (skip window reference for now)
	if header:
		header.set_inventory_manager(inventory_manager)
		# Note: Skipping header.set_inventory_window() as it expects native Window type
	
	# Initial display refresh
	call_deferred("_refresh_and_compact_display")

func _connect_header_signals():
	"""Connect header control signals"""
	if not header:
		return
		
	if header.has_signal("search_changed"):
		header.search_changed.connect(_on_search_changed)
	if header.has_signal("filter_changed"):
		header.filter_changed.connect(_on_filter_changed)
	if header.has_signal("sort_requested"):
		header.sort_requested.connect(_on_sort_requested)
	if header.has_signal("display_mode_changed"):
		header.display_mode_changed.connect(_on_display_mode_changed)

func _setup_mass_info_bar(parent_container: Control):
	"""Setup mass/volume info bar at the top"""
	mass_info_bar = Panel.new()
	mass_info_bar.name = "MassInfoBar"
	mass_info_bar.custom_minimum_size = Vector2(0, 24)
	mass_info_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	mass_info_bar.add_theme_stylebox_override("panel", style)
	
	# Create a margin container for padding inside the mass info bar
	var margin_container = MarginContainer.new()
	margin_container.name = "MassInfoMargin"
	margin_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_left", 8)
	margin_container.add_theme_constant_override("margin_right", 8)
	margin_container.add_theme_constant_override("margin_top", 4)
	margin_container.add_theme_constant_override("margin_bottom", 4)
	mass_info_bar.add_child(margin_container)
	
	mass_info_label = Label.new()
	mass_info_label.name = "MassInfoLabel"
	mass_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mass_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mass_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mass_info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mass_info_label.add_theme_color_override("font_color", Color.WHITE)
	mass_info_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	mass_info_label.add_theme_constant_override("shadow_offset_x", 1)
	mass_info_label.add_theme_constant_override("shadow_offset_y", 1)
	mass_info_label.add_theme_font_size_override("font_size", 12)
	mass_info_label.clip_contents = true
	mass_info_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	mass_info_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	
	margin_container.add_child(mass_info_label)
	parent_container.add_child(mass_info_bar)

func _setup_grid_display(parent_container: Control):
	"""Setup grid display for container with preserved layout"""
	content_grid = InventoryGrid.new()
	content_grid.name = "ContainerGrid"
	content_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Configure grid properties to match main window
	content_grid.slot_size = Vector2(64, 96)
	content_grid.slot_spacing = 20
	content_grid.min_grid_width = 5
	content_grid.min_grid_height = 5
	content_grid.enable_virtual_scrolling = false  # Use traditional grid for tearoff windows
	
	parent_container.add_child(content_grid)
	
	# CRITICAL: Copy item positions from parent grid before setting container
	_copy_item_positions_from_parent()
	
	# Set container - this will preserve the copied positions
	if container:
		content_grid.set_container(container)
	
	# Connect signals
	if content_grid.has_signal("item_activated"):
		content_grid.item_activated.connect(_on_item_activated)
	if content_grid.has_signal("item_context_menu"):
		content_grid.item_context_menu.connect(_on_item_context_menu)
	if content_grid.has_signal("empty_area_context_menu"):
		content_grid.empty_area_context_menu.connect(_on_empty_area_context_menu)

func _copy_item_positions_from_parent():
	"""Copy item positions from the parent window's grid to maintain layout"""
	if not parent_window or not parent_window.content or not parent_window.content.inventory_grid:
		return
		
	var parent_grid = parent_window.content.inventory_grid
	
	# Copy the item_positions dictionary from parent grid
	if parent_grid.has_method("get_item_positions"):
		var parent_positions = parent_grid.get_item_positions()
		if content_grid.has_method("set_item_positions"):
			content_grid.set_item_positions(parent_positions)
	else:
		# Fallback: Access the item_positions member directly if available
		if parent_grid.get("item_positions"):
			var parent_positions = parent_grid.item_positions
			if content_grid.get("item_positions"):
				content_grid.item_positions = parent_positions.duplicate()
	
	# Also copy virtual_items order if using virtual scrolling
	if parent_grid.get("virtual_items") and content_grid.get("virtual_items"):
		content_grid.virtual_items = parent_grid.virtual_items.duplicate()

func _setup_list_display(parent_container: Control):
	"""Setup list display for container"""
	content_list = InventoryListView.new()
	content_list.name = "ContainerList"
	content_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_list.visible = false  # Start hidden
	parent_container.add_child(content_list)
	
	# Set container with both parameters
	if container:
		content_list.set_container(container, container.container_id)
	
	# Connect signals
	if content_list.has_signal("item_activated"):
		content_list.item_activated.connect(_on_item_activated)
	if content_list.has_signal("item_context_menu"):
		content_list.item_context_menu.connect(_on_item_context_menu)

func _setup_item_actions():
	"""Setup item actions for context menus and operations"""
	if not parent_window or not parent_window.item_actions:
		return
		
	# Share the same item actions instance from parent window
	item_actions = parent_window.item_actions
	
	# Set current container for actions
	if item_actions.has_method("set_current_container"):
		item_actions.set_current_container(container)

func _set_display_mode(mode: InventoryDisplayMode.Mode):
	"""Switch between grid and list display modes"""
	if mode == current_display_mode:
		return
		
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
	
	# Update header button if it exists
	if header and header.display_mode_button:
		var button_text = "⊞" if mode == InventoryDisplayMode.Mode.GRID else "☰"
		header.set_fake_button_text(header.display_mode_button, button_text)
	
	# Refresh current display
	call_deferred("_refresh_display")

func _connect_container_signals():
	"""Connect to container change signals"""
	if not container:
		return
		
	if container.has_signal("item_added"):
		if not container.item_added.is_connected(_on_container_item_added):
			container.item_added.connect(_on_container_item_added)
	
	if container.has_signal("item_removed"):
		if not container.item_removed.is_connected(_on_container_item_removed):
			container.item_removed.connect(_on_container_item_removed)
	
	if container.has_signal("container_changed"):
		if not container.container_changed.is_connected(_on_container_changed):
			container.container_changed.connect(_on_container_changed)

# Header signal handlers (same as main window)
func _on_search_changed(text: String):
	"""Handle search text changes from header"""
	# Apply to grid view
	if content_grid and content_grid.has_method("apply_search"):
		content_grid.apply_search(text)
	
	# Apply to list view
	if content_list and content_list.has_method("apply_search"):
		content_list.apply_search(text)

func _on_filter_changed(filter_type: int):
	"""Handle filter changes from header"""
	# Apply to grid view
	if content_grid and content_grid.has_method("apply_filter"):
		content_grid.apply_filter(filter_type)
	
	# Apply to list view
	if content_list and content_list.has_method("apply_filter"):
		content_list.apply_filter(filter_type)

func _on_sort_requested(sort_type: InventorySortType.Type):
	"""Handle sort requests from header"""
	if not inventory_manager or not container:
		return
		
	# Sort the container
	inventory_manager.sort_container(container.container_id, sort_type)
	
	# Force refresh after sort
	await get_tree().process_frame  # Wait for sort to complete
	_refresh_display()

func _on_display_mode_changed(mode: InventoryDisplayMode.Mode):
	"""Handle display mode changes from header"""
	_set_display_mode(mode)
	call_deferred("_refresh_and_compact_display")

# Container signal handlers
func _on_container_item_added(item: InventoryItem_Base, _position: Vector2i = Vector2i(-1, -1)):
	"""Handle item added to container"""
	_refresh_display()
	_update_mass_info()

func _on_container_item_removed(item: InventoryItem_Base, _position: Vector2i = Vector2i(-1, -1)):
	"""Handle item removed from container"""
	_refresh_display()
	_update_mass_info()

func _on_container_changed(_item: InventoryItem_Base = null, _position: Vector2i = Vector2i(-1, -1)):
	"""Handle general container changes"""
	_refresh_display()
	_update_mass_info()

# Content signal handlers
func _on_item_activated(item: InventoryItem_Base, slot: InventorySlot):
	"""Handle item activation"""
	if item_actions and item_actions.has_method("handle_item_activation"):
		item_actions.handle_item_activation(item, slot)

func _on_item_context_menu(item: InventoryItem_Base, slot: InventorySlot, position: Vector2):
	"""Handle item context menu"""
	if item_actions and item_actions.has_method("show_item_context_menu"):
		item_actions.show_item_context_menu(item, slot, position)

func _on_empty_area_context_menu(position: Vector2):
	"""Handle empty area context menu"""
	if item_actions and item_actions.has_method("show_empty_area_context_menu"):
		item_actions.show_empty_area_context_menu(position)

# Display management
func _refresh_display():
	"""Refresh the current display mode"""
	if not container:
		return
		
	match current_display_mode:
		InventoryDisplayMode.Mode.GRID:
			if content_grid and content_grid.visible:
				content_grid.refresh_display()
		InventoryDisplayMode.Mode.LIST:
			if content_list and content_list.visible:
				content_list.refresh_display()
	
	_update_mass_info()

func _refresh_and_compact_display():
	"""Refresh display and trigger compacting for tearoff window"""
	_refresh_display()
	
	# Trigger compact refresh on grid to reorganize items
	if content_grid and content_grid.has_method("trigger_compact_refresh"):
		content_grid.trigger_compact_refresh()
	elif content_grid and content_grid.has_method("_trigger_compact_refresh"):
		content_grid._trigger_compact_refresh()

func _update_mass_info():
	"""Update mass/volume information display"""
	if not mass_info_label or not container:
		return
		
	var used_volume = container.get_used_volume()
	var max_volume = container.max_volume
	var item_count = container.get_item_count()
	
	var volume_text = "%.1f / %.1f m³" % [used_volume, max_volume]
	var count_text = "%d items" % item_count
	
	mass_info_label.text = "%s | %s" % [volume_text, count_text]

# Public interface
func get_container() -> InventoryContainer_Base:
	"""Get the container this window represents"""
	return container

func reattach_to_parent():
	"""Reattach this container to the parent window"""
	window_reattached.emit(container)
	hide_window()
	queue_free()

# Override Window_Base methods for proper cleanup
func hide_window():
	"""Override to ensure proper cleanup"""
	super.hide_window()

func _on_window_closed():
	"""Override the Window_Base virtual method for close handling"""
	# Emit reattach signal when window is closed
	reattach_to_parent()