# InventoryContainerLogic.gd - Business logic for container operations
class_name InventoryContainerLogic
extends RefCounted

# Static utility methods for container operations
static func auto_stack_items(container: InventoryContainer_Base) -> int:
	"""Auto-stack compatible items in a container. Returns number of stacks created."""
	if not container:
		return 0
	
	var stacks_created = 0
	var processed_items = []
	
	for item in container.items:
		if item in processed_items:
			continue
		
		# Find all compatible items
		var compatible_items = []
		for other_item in container.items:
			if other_item != item and item.can_stack_with(other_item) and not other_item in processed_items:
				compatible_items.append(other_item)
		
		if compatible_items.size() > 0:
			# Merge compatible items into the first item
			for compatible_item in compatible_items:
				var space_available = item.max_stack_size - item.quantity
				var amount_to_merge = min(compatible_item.quantity, space_available)
				
				if amount_to_merge > 0:
					item.quantity += amount_to_merge
					compatible_item.quantity -= amount_to_merge
					
					if compatible_item.quantity <= 0:
						container.remove_item(compatible_item)
						processed_items.append(compatible_item)
					
					stacks_created += 1
					
					if item.quantity >= item.max_stack_size:
						break
		
		processed_items.append(item)
	
	return stacks_created

static func sort_items_by_type(container: InventoryContainer_Base, sort_type: InventorySortType.Type):
	"""Sort container items by specified type"""
	if not container:
		return
	
	match sort_type:
		InventorySortType.Type.BY_NAME:
			sort_items_by_name(container)
		InventorySortType.Type.BY_TYPE:
			container.items.sort_custom(func(a, b): return a.item_type < b.item_type)
		InventorySortType.Type.BY_VALUE:
			sort_items_by_value(container)
		InventorySortType.Type.BY_VOLUME:
			container.items.sort_custom(func(a, b): return a.get_total_volume() > b.get_total_volume())

static func sort_items_by_name(container: InventoryContainer_Base):
	"""Sort container items by name"""
	if not container:
		return
	
	container.items.sort_custom(func(a, b): return a.item_name.naturalnocasecmp_to(b.item_name) < 0)

static func sort_items_by_value(container: InventoryContainer_Base):
	"""Sort container items by value (highest first)"""
	if not container:
		return
	
	container.items.sort_custom(func(a, b): return a.get_total_value() > b.get_total_value())

static func compact_items(container: InventoryContainer_Base):
	"""Remove gaps in item positioning"""
	if not container:
		return
	
	# For volume-based containers, this is handled by the UI layer
	# Just ensure items array is clean
	container.items = container.items.filter(func(item): return item != null and item.is_valid_item())

static func calculate_total_value(container: InventoryContainer_Base) -> float:
	"""Calculate total value of all items in container"""
	if not container:
		return 0.0
	
	var total_value = 0.0
	for item in container.items:
		if item and item.is_valid_item():
			total_value += item.get_total_value()
	
	return total_value

static func calculate_total_mass(container: InventoryContainer_Base) -> float:
	"""Calculate total mass of all items in container"""
	if not container:
		return 0.0
	
	var total_mass = 0.0
	for item in container.items:
		if item and item.is_valid_item():
			total_mass += item.get_total_mass()
	
	return total_mass

static func find_items_by_type(container: InventoryContainer_Base, item_type: InventoryItem_Base.ItemType) -> Array[InventoryItem_Base]:
	"""Find all items of a specific type"""
	var found_items: Array[InventoryItem_Base] = []
	
	if not container:
		return found_items
	
	for item in container.items:
		if item and item.item_type == item_type:
			found_items.append(item)
	
	return found_items

static func find_item_by_id(container: InventoryContainer_Base, item_id: String) -> InventoryItem_Base:
	"""Find first item with specific ID"""
	if not container:
		return null
	
	for item in container.items:
		if item and item.item_id == item_id:
			return item
	
	return null