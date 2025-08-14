# ContainerView.gd - Independent view of container data that extends InventoryContainer_Base
class_name ContainerView
extends InventoryContainer_Base

# Add missing signal
signal container_changed

# References
var source_container: InventoryContainer_Base
var view_id: String

# View-specific state (independent from source container)
var view_items: Array[InventoryItem_Base] = []
var search_filter: String = ""
var type_filter: ItemTypes.Type = ItemTypes.Type.MISCELLANEOUS  # Use MISCELLANEOUS as "no filter"
var sort_type: InventorySortType.Type = InventorySortType.Type.BY_NAME
var sort_ascending: bool = true


func _init(container: InventoryContainer_Base, id: String = ""):
	# Initialize base class with source container's properties
	var view_container_id = id if id != "" else "view_" + str(Time.get_time_dict_from_system().unix)
	super._init(view_container_id, container.container_name + " (View)", container.max_volume)

	source_container = container
	view_id = view_container_id

	# Copy properties from source container
	container_type = container.container_type
	grid_width = container.grid_width
	grid_height = container.grid_height
	requires_docking = container.requires_docking
	is_secure = container.is_secure

	# Connect to source container for live updates
	if source_container:
		source_container.item_added.connect(_on_source_item_added)
		source_container.item_removed.connect(_on_source_item_removed)
		source_container.item_moved.connect(_on_source_item_moved)

	# Initial population
	_refresh_view()


func _ready():
	# Override the base items array with our view_items
	items = view_items


# View management
func _refresh_view():
	"""Rebuild the view from source container with current filters/sorting"""
	view_items.clear()

	if not source_container:
		items = view_items  # Sync with base class
		return

	# Apply filters
	for item in source_container.items:
		if _passes_filters(item):
			view_items.append(item)

	# Apply sorting
	_apply_current_sort()

	# Sync with base class items array
	items = view_items


func _passes_filters(item: InventoryItem_Base) -> bool:
	"""Check if item passes current view filters"""
	# Search filter
	if search_filter != "" and not item.item_name.to_lower().contains(search_filter.to_lower()):
		return false

	# Type filter (MISCELLANEOUS means no filter)
	if type_filter != ItemTypes.Type.MISCELLANEOUS and item.item_type != type_filter:
		return false

	return true


func _apply_current_sort():
	"""Apply current sort settings to view_items"""
	match sort_type:
		InventorySortType.Type.BY_NAME:
			view_items.sort_custom(func(a, b): return a.item_name.naturalnocasecmp_to(b.item_name) < 0 if sort_ascending else a.item_name.naturalnocasecmp_to(b.item_name) > 0)
		InventorySortType.Type.BY_TYPE:
			view_items.sort_custom(func(a, b): return a.item_type < b.item_type if sort_ascending else a.item_type > b.item_type)
		InventorySortType.Type.BY_VALUE:
			view_items.sort_custom(func(a, b): return a.get_total_value() > b.get_total_value() if sort_ascending else a.get_total_value() < b.get_total_value())
		InventorySortType.Type.BY_VOLUME:
			view_items.sort_custom(func(a, b): return a.get_total_volume() > b.get_total_volume() if sort_ascending else a.get_total_volume() < b.get_total_volume())


# Source container event handlers
func _on_source_item_added(item: InventoryItem_Base, position: Vector2i):
	"""Handle item added to source container"""
	# Always refresh the entire view to ensure consistency
	_refresh_view()

	# Only emit our signal if the item passes filters
	if _passes_filters(item):
		item_added.emit(item, position)


func _on_source_item_removed(item: InventoryItem_Base, position: Vector2i):
	"""Handle item removed from source container"""
	var was_in_view = item in view_items

	# Always refresh the entire view to ensure consistency
	_refresh_view()

	# Only emit our signal if the item was visible in this view
	if was_in_view:
		item_removed.emit(item, position)


func _on_source_item_moved(item: InventoryItem_Base, old_position: Vector2i, new_position: Vector2i):
	"""Handle item moved in source container"""
	# Refresh view in case filters changed item visibility
	_refresh_view()

	# Only emit if item is visible in this view
	if item in view_items:
		item_moved.emit(item, old_position, new_position)


# Public interface for view control
func set_search_filter(filter: String):
	"""Set search filter and refresh view"""
	search_filter = filter
	_refresh_view()
	container_changed.emit()


func set_type_filter(filter: ItemTypes.Type):
	"""Set type filter and refresh view"""
	type_filter = filter
	_refresh_view()
	container_changed.emit()


func set_sort(type: InventorySortType.Type, ascending: bool = true):
	"""Set sort type and refresh view"""
	sort_type = type
	sort_ascending = ascending
	_apply_current_sort()
	items = view_items  # Sync with base class
	container_changed.emit()


# Override volume calculations to use view_items
func get_used_volume() -> float:
	var total = 0.0
	for item in view_items:
		total += item.get_total_volume()
	return total


func get_current_volume() -> float:
	return get_used_volume()


func get_item_count() -> int:
	return view_items.size()


func get_total_quantity() -> int:
	var total = 0
	for item in view_items:
		total += item.quantity
	return total


# Delegate modification methods to source container
func add_item(item: InventoryItem_Base, position: Vector2i = Vector2i(-1, -1), auto_stack: bool = true) -> bool:
	return source_container.add_item(item, position, auto_stack) if source_container else false


func remove_item(item: InventoryItem_Base) -> bool:
	return source_container.remove_item(item) if source_container else false


func clear():
	if source_container:
		source_container.clear()


# Override has_volume_for_item to delegate to source
func has_volume_for_item(item: InventoryItem_Base) -> bool:
	return source_container.has_volume_for_item(item) if source_container else false


# Delegate other methods to source container
func find_stackable_item(item: InventoryItem_Base) -> InventoryItem_Base:
	return source_container.find_stackable_item(item) if source_container else null


func find_items_by_type(item_type: ItemTypes.Type) -> Array[InventoryItem_Base]:
	return source_container.find_items_by_type(item_type) if source_container else []


func find_items_by_name(name: String) -> Array[InventoryItem_Base]:
	return source_container.find_items_by_name(name) if source_container else []


func find_item_by_id(item_id: String) -> InventoryItem_Base:
	return source_container.find_item_by_id(item_id) if source_container else null


func force_refresh():
	"""Force a complete refresh of the view - useful for external synchronization"""
	_refresh_view()
	container_changed.emit()


func cleanup():
	"""Clean up view"""
	if source_container:
		if source_container.item_added.is_connected(_on_source_item_added):
			source_container.item_added.disconnect(_on_source_item_added)
		if source_container.item_removed.is_connected(_on_source_item_removed):
			source_container.item_removed.disconnect(_on_source_item_removed)
		if source_container.item_moved.is_connected(_on_source_item_moved):
			source_container.item_moved.disconnect(_on_source_item_moved)

	view_items.clear()
	source_container = null
