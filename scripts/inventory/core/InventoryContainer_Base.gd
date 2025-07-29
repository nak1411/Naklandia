# InventoryContainer_Base.gd - EVE-like container with volume constraints
class_name InventoryContainer_Base
extends Resource

# Container properties
@export var container_id: String = ""
@export var container_name: String = "Container"
@export var max_volume: float = 100.0  # m³
@export var grid_width: int = 10
@export var grid_height: int = 10

# Container type and restrictions
@export var container_type: InventoryItem_Base.ContainerType = InventoryItem_Base.ContainerType.GENERAL_CARGO
@export var allowed_item_types: Array[InventoryItem_Base.ItemType] = []
@export var is_secure: bool = false
@export var requires_docking: bool = false

# Items storage
var items: Array[InventoryItem_Base] = []
var grid_slots: Array = []  # 2D array for grid-based positioning

# Signals
signal item_added(item: InventoryItem_Base, position: Vector2i)
signal item_removed(item: InventoryItem_Base, position: Vector2i)
signal container_full()
signal item_moved(item: InventoryItem_Base, from_pos: Vector2i, to_pos: Vector2i)

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

func has_volume_for_item(item: InventoryItem_Base) -> bool:
	return get_available_volume() >= item.get_total_volume()

# Grid management
func is_position_valid(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.y < 0:
		return false
	if pos.x >= grid_width or pos.y >= grid_height:
		return false
	return true

func is_area_free(pos: Vector2i, exclude_item: InventoryItem_Base = null) -> bool:
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
	
# Auto-compacting with stacking functionality
func compact_items():
	"""Stacks identical items first, then moves all items to eliminate gaps"""
	
	if items.is_empty():
		return
	
	# First, auto-stack all compatible items
	auto_stack_items()
	
	# Then compact to remove gaps
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

func auto_stack_items():
	"""Automatically stack identical items within this container"""
	var items_to_process = items.duplicate()
	
	for i in range(items_to_process.size()):
		var item = items_to_process[i]
		if not item in items:  # Item might have been merged already
			continue
		
		# Find stackable items after this one
		for j in range(i + 1, items_to_process.size()):
			var other_item = items_to_process[j]
			if not other_item in items:  # Item might have been merged already
				continue
			
			if item.can_stack_with(other_item):
				# Calculate how much we can stack
				var space_available = item.max_stack_size - item.quantity
				var amount_to_stack = min(other_item.quantity, space_available)
				
				if amount_to_stack > 0:
					# Add to the first item's stack
					item.quantity += amount_to_stack
					other_item.quantity -= amount_to_stack
					
					# If the second item is now empty, remove it
					if other_item.quantity <= 0:
						remove_item(other_item)

func occupy_grid_area(pos: Vector2i, item: InventoryItem_Base):
	grid_slots[pos.y][pos.x] = item

func clear_grid_area(pos: Vector2i):
	if pos.y < grid_slots.size() and pos.x < grid_slots[pos.y].size():
		grid_slots[pos.y][pos.x] = null

func get_item_position(item: InventoryItem_Base) -> Vector2i:
	for y in grid_height:
		for x in grid_width:
			if grid_slots[y] and x < grid_slots[y].size() and grid_slots[y][x] == item:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

# Item management
func can_add_item(item: InventoryItem_Base, exclude_item: InventoryItem_Base = null, position: Vector2i = Vector2i(-1, -1)) -> bool:
	if not item or not item.is_valid_item():
		return false
	
	# Check volume constraint (exclude the item being moved if specified)
	var available_volume = get_available_volume()
	if exclude_item and exclude_item in items:
		available_volume += exclude_item.get_total_volume()
	
	if item.get_total_volume() > available_volume:
		return false
	
	# Check type restrictions
	if not allowed_item_types.is_empty() and not item.item_type in allowed_item_types:
		return false
	
	# For specific position requests, check if that position is available
	if position != Vector2i(-1, -1):
		if not is_area_free(position, exclude_item):
			# Check if we can stack with item at target position
			var target_item = null
			if position.y < grid_slots.size() and position.x < grid_slots[position.y].size():
				target_item = grid_slots[position.y][position.x]
			
			if target_item and target_item != exclude_item and item.can_stack_with(target_item):
				return target_item.quantity + item.quantity <= target_item.max_stack_size
			else:
				return false
		else:
			return true  # Position is free and all other checks passed
	
	# For auto-placement, check for stacking possibility (exclude the item being moved)
	var existing_item = find_stackable_item(item)
	if existing_item and existing_item != exclude_item:
		var can_stack = existing_item.quantity + item.quantity <= existing_item.max_stack_size
		return can_stack
	
	# Check grid space for new item placement
	var free_pos = find_free_position()
	var has_space = free_pos != Vector2i(-1, -1)
	return has_space

func add_item(item: InventoryItem_Base, position: Vector2i = Vector2i(-1, -1), auto_stack: bool = true, prevent_merge: bool = false) -> bool:
	if not item:
		return false
	
	# Use the existing can_add_item method
	if not can_add_item(item, item):  # Pass the item itself as exclude_item for same-container moves
		return false
	
	# Try to stack with existing items first (unless prevent_merge is true or auto_stack is false)
	if auto_stack and not prevent_merge:
		var stackable_item = find_stackable_item(item)
		if stackable_item and stackable_item != item:  # Don't stack with itself
			var space_available = stackable_item.max_stack_size - stackable_item.quantity
			var amount_to_stack = min(item.quantity, space_available)
			
			if amount_to_stack > 0:
				stackable_item.quantity += amount_to_stack
				item.quantity -= amount_to_stack
				
				# If we stacked everything, we're done
				if item.quantity <= 0:
					item_added.emit(item, get_item_position(stackable_item))
					return true
	
	# Find placement position
	var final_position = position
	if position == Vector2i(-1, -1):
		final_position = find_free_position()
	elif not is_area_free(position, item):  # Pass the item as exclude_item
		final_position = find_free_position()
	
	if final_position == Vector2i(-1, -1):
		container_full.emit()
		return false
	
	# If this is a move within the same container, clear the old position first
	if item in items:
		var old_position = get_item_position(item)
		if old_position != Vector2i(-1, -1):
			clear_grid_area(old_position)
	else:
		# Only add to items array if it's not already there
		items.append(item)
	
	# Place item in grid
	occupy_grid_area(final_position, item)
	
	# Connect to item signals only if not already connected
	if not item.quantity_changed.is_connected(_on_item_quantity_changed):
		item.quantity_changed.connect(_on_item_quantity_changed)
	if not item.item_modified.is_connected(_on_item_modified):
		item.item_modified.connect(_on_item_modified)
	
	item_added.emit(item, final_position)
	return true

func _find_inventory_manager_recursive(node: Node):
	if node.get_script() and node.get_script().get_global_name() == "InventoryManager":
		return node
	
	for child in node.get_children():
		var result = _find_inventory_manager_recursive(child)
		if result:
			return result
	
	return null

# Auto-compact after item removal
func remove_item(item: InventoryItem_Base) -> bool:
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
	
	return true

func move_item(item: InventoryItem_Base, new_position: Vector2i) -> bool:
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
func find_stackable_item(item: InventoryItem_Base) -> InventoryItem_Base:
	for existing_item in items:
		if existing_item.can_stack_with(item):
			return existing_item
	return null

func find_items_by_type(item_type: InventoryItem_Base.ItemType) -> Array[InventoryItem_Base]:
	var filtered_items: Array[InventoryItem_Base] = []
	for item in items:
		if item.item_type == item_type:
			filtered_items.append(item)
	return filtered_items

func find_items_by_name(name: String) -> Array[InventoryItem_Base]:
	var filtered_items: Array[InventoryItem_Base] = []
	for item in items:
		if name.to_lower() in item.item_name.to_lower():
			filtered_items.append(item)
	return filtered_items

func find_item_by_id(item_id: String) -> InventoryItem_Base:
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
		"total_quantity": get_total_quantity(),
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
func _on_item_quantity_changed(_new_quantity: int):
	# Handle item quantity changes (for UI updates)
	pass

func _on_item_modified():
	# Handle item modifications (for saving/UI updates)
	pass

# Container type management
func set_container_type(new_type: InventoryItem_Base.ContainerType):
	container_type = new_type
	_update_type_restrictions()

func _update_type_restrictions():
	# Don't apply restrictions to personal inventory containers
	if container_id == "player_inventory" or container_id == "player_cargo" or container_id.begins_with("hangar_"):
		allowed_item_types.clear()  # Allow all types
		return
	
	allowed_item_types.clear()
	match container_type:
		InventoryItem_Base.ContainerType.AMMUNITION_BAY:
			allowed_item_types.append(InventoryItem_Base.ItemType.AMMUNITION)
		InventoryItem_Base.ContainerType.FUEL_BAY:
			allowed_item_types.append(InventoryItem_Base.ItemType.RESOURCE)  # Assuming fuel is a resource
		InventoryItem_Base.ContainerType.SECURE_CONTAINER:
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
	container_type = data.get("container_type") if data.has("container_type") else InventoryItem_Base.ContainerType.GENERAL_CARGO
	
	# Handle allowed_item_types array conversion
	var allowed_types_data = data.get("allowed_item_types") if data.has("allowed_item_types") else []
	allowed_item_types.clear()
	for item_type in allowed_types_data:
		if item_type is InventoryItem_Base.ItemType:
			allowed_item_types.append(item_type)
	
	is_secure = data.get("is_secure") if data.has("is_secure") else false
	requires_docking = data.get("requires_docking") if data.has("requires_docking") else false
	
	_initialize_grid()
	
	# Load items
	items.clear()
	var items_data = data.get("items") if data.has("items") else []
	for item_data in items_data:
		var item = InventoryItem_Base.new()
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
