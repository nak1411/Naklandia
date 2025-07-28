# InventoryWindow.gd - Modified to support resizing
class_name InventoryWindow
extends Window_Base

# Window properties
@export var inventory_title: String = "Inventory"
@export var min_window_size: Vector2 = Vector2(400, 300)
@export var default_size: Vector2 = Vector2(800, 600)
@export var max_window_size: Vector2 = Vector2(1400, 1000)  # Optional max size


# UI Modules
var inventory_container: VBoxContainer
var header: InventoryWindowHeader
var content: InventoryWindowContent
var item_actions: InventoryItemActions

# Resizing properties (removed grid_component as it's accessed through hierarchy)
var auto_resize_grid: bool = true
var min_grid_size: Vector2i = Vector2i(8, 6)  # Minimum grid dimensions

# State
var inventory_manager: InventoryManager
var open_containers: Array[InventoryContainer_Base] = []
var current_container: InventoryContainer_Base
var active_context_menu: InventoryItemActions

# Window state
var is_locked: bool = false
var last_window_size: Vector2i

# Signals
signal container_switched(container: InventoryContainer_Base)
signal window_resized(new_size: Vector2i)

func _init():
	super._init()
	set_window_title(inventory_title)
	size = Vector2i(default_size)
	min_size = Vector2i(min_window_size)
	max_size = Vector2i(max_window_size)
	
	# Enable resizing
	unresizable = false
	
	visible = false
	position = Vector2i(1040, 410)
	last_window_size = size

func _ready():
	super._ready()
	await get_tree().process_frame
	_setup_inventory_ui()
	_connect_inventory_signals()
	_connect_resize_signals()
	_find_inventory_manager()
	apply_custom_theme()
	visible = false

func _connect_resize_signals():
	# Connect to window resize events
	size_changed.connect(_on_window_resized)

func _on_window_resized():
	var new_size = size
	if new_size != last_window_size:
		last_window_size = new_size
		if auto_resize_grid:
			_handle_window_resize()
			


func _handle_window_resize():
	var grid = get_inventory_grid()
	if not grid or not current_container:
		return
	
	# Calculate available space for grid
	var available_space = _calculate_available_grid_space()
	var new_grid_size = _calculate_optimal_grid_size(available_space)
	
	# Get current grid size
	var current_grid_size = Vector2i(grid.grid_width, grid.grid_height)
	
	# Only resize if different
	if new_grid_size != current_grid_size:
		_resize_grid(new_grid_size)

func _calculate_available_grid_space() -> Vector2:
	# Account for UI elements - adjust these values based on your layout
	var header_height = 40
	var margin_space = 40
	var container_list_width = 200  # Left panel width
	
	var available_width = size.x - container_list_width - margin_space
	var available_height = size.y - header_height - margin_space
	
	return Vector2(max(200, available_width), max(150, available_height))

func _calculate_optimal_grid_size(available_space: Vector2) -> Vector2i:
	var grid = get_inventory_grid()
	if not grid:
		return min_grid_size
	
	# Use default slot size if not accessible
	var slot_size = Vector2(64, 64)
	var slot_spacing = 2.0
	
	if grid.has_method("get_slot_size"):
		slot_size = grid.get_slot_size()
	elif "slot_size" in grid:
		slot_size = grid.slot_size
	
	if "slot_spacing" in grid:
		slot_spacing = grid.slot_spacing
	
	# Calculate how many slots can fit
	var slots_width = int((available_space.x + slot_spacing) / (slot_size.x + slot_spacing))
	var slots_height = int((available_space.y + slot_spacing) / (slot_size.y + slot_spacing))
	
	# Ensure minimum size
	slots_width = max(slots_width, min_grid_size.x)
	slots_height = max(slots_height, min_grid_size.y)
	
	return Vector2i(slots_width, slots_height)

func _resize_grid(new_grid_size: Vector2i):
	if not current_container:
		return
	
	# Update container dimensions
	current_container.grid_width = new_grid_size.x
	current_container.grid_height = new_grid_size.y
	
	# Get the grid and update it
	var grid = get_inventory_grid()
	if grid:
		# Update grid properties
		grid.grid_width = new_grid_size.x
		grid.grid_height = new_grid_size.y
		
		# Rebuild and refresh
		if grid.has_method("_rebuild_grid"):
			grid._rebuild_grid()
		
		# Force refresh display
		call_deferred("refresh_display")

func _get_all_container_items() -> Array[InventoryItem_Base]:
	if not current_container:
		return []
	
	var items: Array[InventoryItem_Base] = []
	if current_container.has_method("get_all_items"):
		items = current_container.get_all_items()
	
	return items

# Toggle auto-resize functionality
func set_auto_resize_enabled(enabled: bool):
	auto_resize_grid = enabled

func get_auto_resize_grid() -> bool:
	return auto_resize_grid

# Lock/unlock window resizing
func set_window_locked(locked: bool):
	unresizable = locked

func get_window_locked() -> bool:
	return is_locked

# Manual grid resize methods
func resize_to_fit_content():
	if not current_container:
		return
	
	# Find maximum item positions
	var max_x = min_grid_size.x
	var max_y = min_grid_size.y
	
	for item in current_container.items:
		var pos = current_container.get_item_position(item)
		if pos != Vector2i(-1, -1):
			max_x = max(max_x, pos.x + 1)
			max_y = max(max_y, pos.y + 1)
	
	# Add padding
	max_x += 2
	max_y += 2
	
	_resize_grid(Vector2i(max_x, max_y))

func resize_grid_manually(new_size: Vector2i):
	new_size.x = max(new_size.x, min_grid_size.x)
	new_size.y = max(new_size.y, min_grid_size.y)
	_resize_grid(new_size)

# Override the existing _setup_inventory_ui method
func _setup_inventory_ui():
	# Create main horizontal container (no margins)
	var main_hsplit = HSplitContainer.new()
	main_hsplit.name = "MainHSplit"
	main_hsplit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_hsplit.split_offset = 200
	
	# Make the split container resizable
	main_hsplit.dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	
	add_content(main_hsplit)
	
	# LEFT SIDE: Container list panel
	var left_container_panel = MarginContainer.new()
	left_container_panel.name = "LeftContainerPanel"
	left_container_panel.custom_minimum_size.x = 180
	left_container_panel.size_flags_horizontal = Control.SIZE_FILL
	left_container_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_container_panel.add_theme_constant_override("margin_top", 6)
	main_hsplit.add_child(left_container_panel)
	
	# Container list
	var container_list = ItemList.new()
	container_list.name = "ContainerList"
	container_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_container_panel.add_child(container_list)
	
	# RIGHT SIDE: Main inventory content with proper resizing
	var right_content_panel = VBoxContainer.new()
	right_content_panel.name = "RightContentPanel"
	right_content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hsplit.add_child(right_content_panel)
	
	# Create scrollable container for the grid
	var scroll_container = ScrollContainer.new()
	scroll_container.name = "GridScrollContainer"
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	right_content_panel.add_child(scroll_container)
	
	# Create the inventory grid (this replaces the old grid_component)
	var inventory_grid = InventoryGrid.new()
	inventory_grid.name = "InventoryGrid"
	inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(inventory_grid)
	
	# Connect grid signals
	if inventory_grid.has_signal("item_selected"):
		inventory_grid.item_selected.connect(_on_item_selected)
	if inventory_grid.has_signal("item_activated"):
		inventory_grid.item_activated.connect(_on_item_activated)
	if inventory_grid.has_signal("item_context_menu"):
		inventory_grid.item_context_menu.connect(_on_item_context_menu)

# Placeholder signal handlers (implement based on your existing code)
func _on_item_selected(item: InventoryItem_Base, slot):
	pass

func _on_item_activated(item: InventoryItem_Base, slot):
	pass

func _on_item_context_menu(item: InventoryItem_Base, slot, position: Vector2):
	pass

# Add methods to find inventory manager and get grid (implement based on your existing code)
func _find_inventory_manager():
	# Your existing implementation
	pass

func _connect_inventory_signals():
	# Your existing implementation
	pass

func apply_custom_theme():
	# Your existing implementation
	pass

func add_content(node: Node):
	# This should match your Window_Base implementation
	pass

# Helper method to get the inventory grid from existing hierarchy
func get_inventory_grid() -> InventoryGrid:
	# This should match your existing implementation in InventoryWindow
	if content:
		return content.get_inventory_grid()
	return null
