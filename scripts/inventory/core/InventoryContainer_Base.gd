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
	# In volume-based system, we don't maintain a fixed grid internally
	# The grid is managed by the UI layer
	grid_slots.clear()
	# Keep grid_slots as an empty array - UI will handle positioning

# Volume management
func get_current_volume() -> float:
	var total_volume = 0.0
	var processed_items = {}  # Track processed items to prevent duplicates
	
	for item in items:
		# Safety check for null items
		if not item:
			continue
		
		# Safety check for invalid item data
		if not item.has_method("get_total_volume"):
			continue
		
		# Create a unique key for this item instance
		var item_key = str(item.get_instance_id())
		
		# Skip if we've already processed this exact item instance
		if processed_items.has(item_key):
			continue
		
		processed_items[item_key] = true
		
		# Safe volume calculation with bounds checking
		var item_volume = 0.0
		var item_quantity = max(0, item.quantity)  # Ensure non-negative
		var item_unit_volume = max(0.0, item.volume)  # Ensure non-negative
		
		# Prevent overflow with reasonable limits
		if item_quantity > 0 and item_unit_volume > 0:
			if item_quantity > 1000000 or item_unit_volume > 1000000:
				item_volume = min(item_quantity * item_unit_volume, 1000000.0)  # Cap at 1M
			else:
				item_volume = item_quantity * item_unit_volume
		
		total_volume += item_volume
		
		# Safety check for runaway volume calculation
		if total_volume > 1000000.0:  # 1 million m³ is unreasonably large
			break
	
	return total_volume
	
func can_accept_any_quantity(item: InventoryItem_Base) -> bool:
	"""Check if we can accept at least some quantity of an item (for UI highlighting)"""
	if not item or not item.is_valid_item():
		return false
	
	# Check type restrictions first
	if not allowed_item_types.is_empty() and not item.item_type in allowed_item_types:
		return false
	
	var available_volume = get_available_volume()
	
	# If no volume available at all
	if available_volume <= 0.0:
		return false
	
	# If item has no volume, we can accept it
	if item.volume <= 0.0:
		return true
	
	# Check if we can fit at least one unit
	if available_volume >= item.volume:
		return true
	
	# Check if we can stack with existing items
	var existing_item = find_stackable_item(item)
	if existing_item:
		var stack_space = existing_item.max_stack_size - existing_item.quantity
		return stack_space > 0
	
	return false

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
	# In volume-based system, any position is potentially valid
	# The actual constraint is volume, not grid position
	return pos.x >= 0 and pos.y >= 0

func is_area_free(_pos: Vector2i, _exclude_item: InventoryItem_Base = null) -> bool:
	# Let the UI grid handle position conflicts
	# For the container, we only care about volume
	return get_available_volume() > 0

func find_free_position() -> Vector2i:
	# In volume-based system, this is handled by the grid UI
	# Return a placeholder position
	return Vector2i(0, 0)
	
# Auto-compacting with stacking functionality
func compact_items():
	"""Stacks identical items first - positioning is handled by UI"""
	
	if items.is_empty():
		return
	
	# Only auto-stack - don't handle positioning here
	auto_stack_items()
	
	# Signal that items have been reorganized
	for item in items:
		item_moved.emit(item, Vector2i(-1, -1), Vector2i(-1, -1))

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

func occupy_grid_area(_pos: Vector2i, _item: InventoryItem_Base):
	# Volume-based system doesn't track grid positions in the container
	# This is handled by the UI layer
	pass

func clear_grid_area(_pos: Vector2i):
	# Volume-based system doesn't track grid positions in the container
	# This is handled by the UI layer
	pass

func get_item_position(_item: InventoryItem_Base) -> Vector2i:
	# Return invalid position - let UI manage positioning
	return Vector2i(-1, -1)

func can_accept_any_quantity_for_ui(item: InventoryItem_Base) -> bool:
	"""Check if we can accept at least some quantity of an item (specifically for UI highlighting)"""
	if not item or not item.is_valid_item():
		return false
	
	# Check type restrictions first
	if not allowed_item_types.is_empty() and not item.item_type in allowed_item_types:
		return false
	
	var available_volume = get_available_volume()
	
	# If container is completely full
	if available_volume <= 0.0:
		return false
	
	# If item has no volume, we can accept it
	if item.volume <= 0.0:
		return true
	
	# Check if we can fit at least one unit by volume
	if available_volume >= item.volume:
		return true
	
	return false

# Item management
func can_add_item(item: InventoryItem_Base, exclude_item: InventoryItem_Base = null) -> bool:
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
	
	# Only volume and type matter now
	return true

# Replace the add_item method to work with dynamic positioning
func add_item(item: InventoryItem_Base, _position: Vector2i = Vector2i(-1, -1), auto_stack: bool = true) -> bool:
	
	if not can_add_item(item):
		return false
	
	# Try to stack with existing item first (only if auto_stack is enabled)
	if auto_stack:
		var existing_item = find_stackable_item(item)
		if existing_item:
			var space_available = existing_item.max_stack_size - existing_item.quantity
			var amount_to_stack = min(item.quantity, space_available)
			
			if amount_to_stack > 0:
				existing_item.quantity += amount_to_stack
				item.quantity -= amount_to_stack
				
				# If we stacked everything, we're done
				if item.quantity <= 0:
					item_added.emit(item, get_item_position(existing_item))
					return true

	# For volume-based system, position is managed by the grid
	# We just add the item and let the grid handle positioning
	items.append(item)
	
	# Connect to item signals
	if not item.quantity_changed.is_connected(_on_item_quantity_changed):
		item.quantity_changed.connect(_on_item_quantity_changed)
	if not item.item_modified.is_connected(_on_item_modified):
		item.item_modified.connect(_on_item_modified)
	
	# The grid will handle positioning, so we emit with an invalid position
	# The grid will assign a proper position
	item_added.emit(item, Vector2i(-1, -1))
	return true
	
func assign_dynamic_position(item: InventoryItem_Base, _position: Vector2i):
	"""Assign a position to an item for grid display purposes"""
	if item in items:
		# This is now just for display - the actual constraint is volume
		# The grid system will track positions visually
		pass

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
	
	# In volume-based system, "moving" an item doesn't change its container validity
	# Just emit the signal for UI updates
	item_moved.emit(item, Vector2i(-1, -1), new_position)
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
