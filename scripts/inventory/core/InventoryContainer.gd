# InventoryContainer.gd - EVE-like container with volume constraints
class_name InventoryContainer
extends Resource

# Container properties
@export var container_id: String = ""
@export var container_name: String = "Container"
@export var max_volume: float = 100.0  # m³
@export var grid_width: int = 10
@export var grid_height: int = 10

# Container type and restrictions
@export var container_type: InventoryItem.ContainerType = InventoryItem.ContainerType.GENERAL_CARGO
@export var allowed_item_types: Array[InventoryItem.ItemType] = []
@export var is_secure: bool = false
@export var requires_docking: bool = false

# Items storage
var items: Array[InventoryItem] = []
var grid_slots: Array = []  # 2D array for grid-based positioning

# Signals
signal item_added(item: InventoryItem, position: Vector2i)
signal item_removed(item: InventoryItem, position: Vector2i)
signal container_full()
signal volume_exceeded()
signal item_moved(item: InventoryItem, from_pos: Vector2i, to_pos: Vector2i)

func _init(id: String = "", name: String = "Container", volume: float = 100.0):
	container_id = id
	container_name = name
	max_volume = volume
	
	if container_id.is_empty():
		container_id = _generate_unique_id()
	
	_initialize_grid()

func _generate_unique_id() -> String:
	return "container_" + str(Time.get_unix_time_from_system()) + "_" + str(randi() % 10000)

func _initialize_grid():
	grid_slots.clear()
	grid_slots.resize(grid_height)
	
	for y in grid_height:
		grid_slots[y] = []
		grid_slots[y].resize(grid_width)
		for x in grid_width:
			grid_slots[y][x] = null

# Volume management
func get_current_volume() -> float:
	var total_volume = 0.0
	for item in items:
		total_volume += item.get_total_volume()
	return total_volume

func get_available_volume() -> float:
	return max_volume - get_current_volume()

func get_volume_percentage() -> float:
	if max_volume <= 0:
		return 0.0
	return (get_current_volume() / max_volume) * 100.0

func has_volume_for_item(item: InventoryItem) -> bool:
	return get_available_volume() >= item.get_total_volume()

# Grid management
func is_position_valid(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.y < 0:
		return false
	if pos.x >= grid_width or pos.y >= grid_height:
		return false
	return true

func is_area_free(pos: Vector2i, exclude_item: InventoryItem = null) -> bool:
	if not is_position_valid(pos):
		return false
	
	var slot_item = grid_slots[pos.y][pos.x]
	return slot_item == null or slot_item == exclude_item

func find_free_position() -> Vector2i:
	for y in range(grid_height):
		for x in range(grid_width):
			var pos = Vector2i(x, y)
			if is_area_free(pos):
				return pos
	
	return Vector2i(-1, -1)
	
# Auto-compacting functionality
# Add this debug version of compact_items to InventoryContainer.gd:

func compact_items():
	"""Moves all items to eliminate gaps, placing them sequentially from top-left"""
	
	if items.is_empty():
		return
	
	for i in range(items.size()):
		var item = items[i]
		var old_pos = get_item_position(item)
	
	# Store items temporarily
	var items_to_place = items.duplicate()
	
	# Clear the grid
	_initialize_grid()
	items.clear()
	
	# Re-add items in sequence, filling from top-left
	for item in items_to_place:
		var free_pos = find_free_position()
		if free_pos != Vector2i(-1, -1):
			occupy_grid_area(free_pos, item)
			items.append(item)

func occupy_grid_area(pos: Vector2i, item: InventoryItem):
	grid_slots[pos.y][pos.x] = item

func clear_grid_area(pos: Vector2i):
	if pos.y < grid_slots.size() and pos.x < grid_slots[pos.y].size():
		grid_slots[pos.y][pos.x] = null

func get_item_position(item: InventoryItem) -> Vector2i:
	for y in grid_height:
		for x in grid_width:
			if grid_slots[y] and x < grid_slots[y].size() and grid_slots[y][x] == item:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

# Item management
func can_add_item(item: InventoryItem) -> bool:
	if not item or not item.is_valid_item():
		return false
	
	# Check volume constraint
	if not has_volume_for_item(item):
		return false
	
	# Check type restrictions
	if not allowed_item_types.is_empty() and not item.item_type in allowed_item_types:
		return false
	
	# Check for stacking possibility
	var existing_item = find_stackable_item(item)
	if existing_item:
		return existing_item.quantity + item.quantity <= existing_item.max_stack_size
	
	# Check grid space
	var free_pos = find_free_position()
	return free_pos != Vector2i(-1, -1)

func add_item(item: InventoryItem, position: Vector2i = Vector2i(-1, -1)) -> bool:
	if not can_add_item(item):
		return false
	
	# Try to stack with existing item first
	var existing_item = find_stackable_item(item)
	if existing_item:
		var remaining = existing_item.add_to_stack(item.quantity)
		if remaining > 0:
			item.quantity = remaining
		else:
			item_added.emit(item, get_item_position(existing_item))
			return true
	
	# Find placement position
	var final_position = position
	if position == Vector2i(-1, -1):
		final_position = find_free_position()
	elif not is_area_free(position):
		final_position = find_free_position()
	
	if final_position == Vector2i(-1, -1):
		container_full.emit()
		return false
	
	# Place item in grid
	occupy_grid_area(final_position, item)
	items.append(item)
	
	# Connect to item signals
	item.quantity_changed.connect(_on_item_quantity_changed)
	item.item_modified.connect(_on_item_modified)
	
	item_added.emit(item, final_position)
	return true

# Auto-compact after item removal
func remove_item(item: InventoryItem) -> bool:
	if not item in items:
		return false
	
	var position = get_item_position(item)
	clear_grid_area(position)
	items.erase(item)
	
	# Disconnect signals safely
	if item.quantity_changed.is_connected(_on_item_quantity_changed):
		item.quantity_changed.disconnect(_on_item_quantity_changed)
	if item.item_modified.is_connected(_on_item_modified):
		item.item_modified.disconnect(_on_item_modified)
	
	item_removed.emit(item, position)
	
	# DON'T auto-compact after removal - let items stay where they are
	# compact_items()  <-- REMOVE THIS LINE
	
	return true

func move_item(item: InventoryItem, new_position: Vector2i) -> bool:
	if not item in items:
		return false
	
	var old_position = get_item_position(item)
	
	if not is_area_free(new_position, item):
		return false
	
	# Clear old position and set new position
	clear_grid_area(old_position)
	occupy_grid_area(new_position, item)
	
	item_moved.emit(item, old_position, new_position)
	return true

# Search and filtering
func find_stackable_item(item: InventoryItem) -> InventoryItem:
	for existing_item in items:
		if existing_item.can_stack_with(item):
			return existing_item
	return null

func find_items_by_type(item_type: InventoryItem.ItemType) -> Array[InventoryItem]:
	var filtered_items: Array[InventoryItem] = []
	for item in items:
		if item.item_type == item_type:
			filtered_items.append(item)
	return filtered_items

func find_items_by_name(name: String) -> Array[InventoryItem]:
	var filtered_items: Array[InventoryItem] = []
	for item in items:
		if name.to_lower() in item.item_name.to_lower():
			filtered_items.append(item)
	return filtered_items

func find_item_by_id(item_id: String) -> InventoryItem:
	for item in items:
		if item.item_id == item_id:
			return item
	return null

# Container statistics
func get_item_count() -> int:
	return items.size()
	
func get_total_quantity() -> int:
	"""Returns the total quantity of all items (sum of all item quantities)"""
	var total_quantity = 0
	for item in items:
		total_quantity += item.quantity
	return total_quantity

# Update get_container_info to include total quantity
func get_container_info() -> Dictionary:
	return {
		"name": container_name,
		"id": container_id,
		"volume_used": get_current_volume(),
		"volume_max": max_volume,
		"volume_percentage": get_volume_percentage(),
		"item_count": get_item_count(),
		"total_quantity": get_total_quantity(),  # Add this line
		"total_mass": get_total_mass(),
		"total_value": get_total_value(),
		"is_secure": is_secure
	}

func get_total_mass() -> float:
	var total_mass = 0.0
	for item in items:
		total_mass += item.get_total_mass()
	return total_mass

func get_total_value() -> float:
	var total_value = 0.0
	for item in items:
		total_value += item.get_total_value()
	return total_value

# Signal handlers
func _on_item_quantity_changed(new_quantity: int):
	# Handle item quantity changes (for UI updates)
	pass

func _on_item_modified():
	# Handle item modifications (for saving/UI updates)
	pass

# Container type management
func set_container_type(new_type: InventoryItem.ContainerType):
	container_type = new_type
	_update_type_restrictions()

func _update_type_restrictions():
	allowed_item_types.clear()
	match container_type:
		InventoryItem.ContainerType.AMMUNITION_BAY:
			allowed_item_types.append(InventoryItem.ItemType.AMMUNITION)
		InventoryItem.ContainerType.FUEL_BAY:
			allowed_item_types.append(InventoryItem.ItemType.RESOURCE)  # Assuming fuel is a resource
		InventoryItem.ContainerType.SECURE_CONTAINER:
			is_secure = true
		_:
			pass  # Allow all types - keep array empty

# Serialization
func to_dict() -> Dictionary:
	var items_data = []
	for item in items:
		var item_data = item.to_dict()
		item_data["grid_position"] = get_item_position(item)
		items_data.append(item_data)
	
	return {
		"container_id": container_id,
		"container_name": container_name,
		"max_volume": max_volume,
		"grid_width": grid_width,
		"grid_height": grid_height,
		"container_type": container_type,
		"allowed_item_types": allowed_item_types,
		"is_secure": is_secure,
		"requires_docking": requires_docking,
		"items": items_data
	}

func from_dict(data: Dictionary):
	container_id = data.get("container_id") if data.has("container_id") else ""
	container_name = data.get("container_name") if data.has("container_name") else "Container"
	max_volume = data.get("max_volume") if data.has("max_volume") else 100.0
	grid_width = data.get("grid_width") if data.has("grid_width") else 10
	grid_height = data.get("grid_height") if data.has("grid_height") else 10
	container_type = data.get("container_type") if data.has("container_type") else InventoryItem.ContainerType.GENERAL_CARGO
	
	# Handle allowed_item_types array conversion
	var allowed_types_data = data.get("allowed_item_types") if data.has("allowed_item_types") else []
	allowed_item_types.clear()
	for item_type in allowed_types_data:
		if item_type is InventoryItem.ItemType:
			allowed_item_types.append(item_type)
	
	is_secure = data.get("is_secure") if data.has("is_secure") else false
	requires_docking = data.get("requires_docking") if data.has("requires_docking") else false
	
	_initialize_grid()
	
	# Load items
	items.clear()
	var items_data = data.get("items") if data.has("items") else []
	for item_data in items_data:
		var item = InventoryItem.new()
		item.from_dict(item_data)
		var grid_pos_data = item_data.get("grid_position") if item_data.has("grid_position") else Vector2i(-1, -1)
		var grid_pos = Vector2i(-1, -1)
		if grid_pos_data is Vector2i:
			grid_pos = grid_pos_data
		elif grid_pos_data is Vector2:
			grid_pos = Vector2i(int(grid_pos_data.x), int(grid_pos_data.y))
		add_item(item, grid_pos)

# Clear all items
func clear():
	for item in items.duplicate():
		remove_item(item)
	_initialize_grid()

# Debug
func get_debug_string() -> String:
	return "%s - Items: %d, Volume: %.1f/%.1f m³ (%.1f%%)" % [
		container_name, get_item_count(), get_current_volume(), 
		max_volume, get_volume_percentage()
	]
