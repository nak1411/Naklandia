# scripts/inventory/shared/utilities/InventoryMath.gd
class_name InventoryMath

# Volume and mass calculations
static func calculate_total_volume(items: Array[InventoryItem_Base]) -> float:
	var total: float = 0.0
	for item in items:
		if item:
			total += item.get_total_volume()
	return total

static func calculate_total_mass(items: Array[InventoryItem_Base]) -> float:
	var total: float = 0.0
	for item in items:
		if item:
			total += item.get_total_mass()
	return total

static func calculate_stack_efficiency(item: InventoryItem_Base) -> float:
	if not item or item.max_stack_size <= 1:
		return 1.0
	return float(item.quantity) / float(item.max_stack_size)

# Grid calculations
static func calculate_grid_size(container_volume: float, slot_size: float = 1.0) -> Vector2i:
	var slots_needed = ceili(container_volume / slot_size)
	var width = mini(10, slots_needed)  # Max 10 wide
	var height = ceili(float(slots_needed) / float(width))
	return Vector2i(width, height)

static func position_to_index(position: Vector2i, grid_width: int) -> int:
	return position.y * grid_width + position.x

static func index_to_position(index: int, grid_width: int) -> Vector2i:
	return Vector2i(index % grid_width, index / grid_width)

# Value calculations
static func format_currency(value: float) -> String:
	var parts = str(value).split(".")
	if parts.size() < 2:
		parts.append("00")
	elif parts[1].length() == 1:
		parts[1] += "0"
	
	var dollars = parts[0]
	var cents = parts[1].substr(0, 2)
	
	# Add commas
	var result = ""
	var count = 0
	for i in range(dollars.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = dollars[i] + result
		count += 1
	
	if cents != "00":
		return result + "." + cents + " cr "
	else:
		return result + " cr "