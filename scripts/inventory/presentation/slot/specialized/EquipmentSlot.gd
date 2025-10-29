# EquipmentSlot.gd - Equipment-specific slot extending InventorySlot
class_name EquipmentSlot
extends InventorySlot

# Equipment-specific properties
@export var equipment_slot_type: String = ""  # e.g., "head", "chest", "weapon"
@export var allowed_categories: Array[String] = []  # What item categories can go here

# Visual customization for equipment slots
var slot_type_label: Label


func _ready():
	# Set equipment container ID before parent initialization
	container_id = "equipment"
	add_to_group("equipment_slots")

	# Adjust slot size for equipment (square slots) BEFORE parent init
	slot_size = Vector2(64, 64)
	custom_minimum_size = slot_size
	size = slot_size

	# Call parent ready to set up components
	super._ready()

	# Setup equipment visuals after parent is complete
	if is_node_ready():
		_setup_equipment_visual()
	else:
		await ready
		_setup_equipment_visual()


func set_item(new_item: InventoryItem_Base):
	"""Override to maintain visible background and hide name/quantity"""
	super.set_item(new_item)
	_ensure_background_visible()

	# Hide item name label
	if visuals and visuals.item_name_label:
		visuals.item_name_label.visible = false

	# Hide quantity display in equipment slots
	if visuals:
		if visuals.quantity_label:
			visuals.quantity_label.visible = false
		if visuals.quantity_bg:
			visuals.quantity_bg.visible = false


func update_item_display():
	"""Override to prevent item name from showing in equipment slots"""
	if visuals:
		visuals.update_item_display()
		# CRITICAL: Always hide item name in equipment slots
		if visuals.item_name_label:
			visuals.item_name_label.visible = false


func clear_item():
	"""Override to maintain visible background and hide name"""
	super.clear_item()
	_ensure_background_visible()

	# CRITICAL: Force hide item name label after parent updates
	if visuals and visuals.item_name_label:
		visuals.item_name_label.visible = false


func _mouse_enter():
	"""Debug: Mouse entered this slot"""
	print("Mouse entered EquipmentSlot: ", name)


func _mouse_exit():
	"""Debug: Mouse exited this slot"""
	print("Mouse exited EquipmentSlot: ", name)


func can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	"""Check if we can accept dropped data"""
	print("EquipmentSlot.can_drop_data called on ", name)

	if not data:
		print("  No data provided")
		return false

	var source_item = data.get("item") as InventoryItem_Base
	if not source_item:
		print("  No source item in data")
		return false

	print("  Source item: ", source_item.item_name)
	print("  Item metadata: ", source_item.get_meta_list())
	print("  Item equipment_category: ", source_item.get_meta("equipment_category", "NONE"))

	# Check if this equipment slot can accept the item
	var can_accept = can_accept_item(source_item)
	print("  Can accept: ", can_accept)
	return can_accept


func drop_data(_at_position: Vector2, data: Variant):
	"""Handle dropped data"""
	print("EquipmentSlot.drop_data called on ", name)

	if not data:
		print("  No data provided")
		return

	var source_item = data.get("item") as InventoryItem_Base
	var source_slot = data.get("source_slot") as InventorySlot
	var source_row = data.get("source_row")  # ListRowManager

	print("  Source item: ", source_item.item_name if source_item else "NONE")
	print("  Source slot: ", source_slot.name if source_slot else "NONE")
	print("  Source row: ", source_row.name if source_row else "NONE")

	if not source_item:
		print("  Missing item - aborting")
		return

	# Handle drops from InventorySlot
	if source_slot:
		print("  Emitting item_dropped_on_slot signal for slot")
		item_dropped_on_slot.emit(source_slot, self)
		return

	# Handle drops from ListRowManager (list view)
	if source_row:
		print("  Handling drop from list row")
		_handle_list_row_drop(source_item, source_row)
		return

	print("  No valid source - aborting")


func _handle_list_row_drop(source_item: InventoryItem_Base, _source_row):
	"""Handle dropping an item from a list view row"""
	print("  _handle_list_row_drop called for item: ", source_item.item_name)

	# Find the equipment window to properly equip the item
	var equipment_window = _find_equipment_window()
	if not equipment_window:
		print("  ERROR: Could not find equipment window")
		return

	# Find which slot type this is
	var slot_type = _find_equipment_slot_type(equipment_window)
	if slot_type == null:
		print("  ERROR: Could not determine slot type")
		return

	print("  Equipping item in slot type: ", slot_type)

	# Equip the item through the equipment window
	equipment_window._equip_item(source_item, slot_type)

	print("  Item equipped successfully")


func _find_equipment_window():
	"""Find the EquipmentWindow in the scene tree"""
	var current = get_parent()
	while current:
		if current.get_script() and current.get_script().get_global_name() == "EquipmentWindow":
			return current
		current = current.get_parent()
	return null


func _find_equipment_slot_type(equipment_window):
	"""Find which slot type this equipment slot is"""
	for slot_type in equipment_window.equipment_slots:
		if equipment_window.equipment_slots[slot_type] == self:
			return slot_type
	return null


func _setup_equipment_visual():
	"""Setup equipment-specific visual elements"""
	visible = true
	modulate = Color(1, 1, 1, 1)
	z_index = 10
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Hide item name label
	if visuals and visuals.item_name_label:
		visuals.item_name_label.visible = false
		visuals.item_name_label.hide()
		visuals.item_name_label.position = Vector2(-1000, -1000)

	# Hide quantity display
	if visuals:
		if visuals.quantity_label:
			visuals.quantity_label.visible = false
			visuals.quantity_label.hide()
		if visuals.quantity_bg:
			visuals.quantity_bg.visible = false
			visuals.quantity_bg.hide()

	# Adjust icon to fill the slot
	if visuals and visuals.item_icon:
		visuals.item_icon.position = Vector2(2, 2)
		visuals.item_icon.size = Vector2(60, 60)

	_ensure_background_visible()
	queue_redraw()


func can_accept_item(check_item: InventoryItem_Base) -> bool:
	"""Check if this equipment slot can accept the given item"""
	print("  can_accept_item called")

	if not check_item:
		print("    No item provided")
		return false

	# If no allowed categories set, accept any item
	if allowed_categories.is_empty():
		print("    No category restrictions - accepting all items")
		return true

	# Check if item's category matches any allowed category
	var item_category = check_item.get_meta("equipment_category", "")
	print("    Item category: '", item_category, "'")
	print("    Allowed categories: ", allowed_categories)

	# TEMPORARY: If item has no category, accept it anyway for testing
	if item_category.is_empty():
		print("    Item has no equipment_category - ACCEPTING FOR TESTING")
		return true

	var is_allowed = item_category in allowed_categories
	print("    Is allowed: ", is_allowed)
	return is_allowed


func set_equipment_type(type: String):
	"""Set the equipment slot type"""
	equipment_slot_type = type


func get_equipment_type() -> String:
	"""Get the equipment slot type"""
	return equipment_slot_type


func set_allowed_categories(categories: Array[String]):
	"""Set which item categories can be equipped in this slot"""
	allowed_categories = categories


func get_allowed_categories() -> Array[String]:
	"""Get the allowed item categories"""
	return allowed_categories


func _on_drag_started(source_slot: InventorySlot, dragged_item: InventoryItem_Base):
	"""Override to prevent equipment slot from becoming transparent during drag"""
	# DON'T call super - we don't want any behavior that might hide/fade the item

	# Keep the equipment slot fully visible during drag
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Make sure item visual stays visible
	if visuals and visuals.item_icon:
		visuals.item_icon.modulate.a = 1.0

	# Emit the signal for other systems
	item_drag_started.emit(source_slot, dragged_item)


func _on_drag_ended(source_slot: InventorySlot, success: bool):
	"""Override to restore equipment slot visuals after drag"""
	super._on_drag_ended(source_slot, success)
	# Force restore equipment slot background
	call_deferred("_ensure_background_visible")


func set_highlighted(highlighted: bool):
	"""Override to maintain visible background"""
	is_highlighted = highlighted
	_ensure_background_visible()

	# Update outline without changing background
	if visuals and visuals.outline_overlay:
		if highlighted and has_item():
			visuals._show_outline()
		else:
			visuals._hide_outline()


func set_selected(selected: bool):
	"""Override to maintain visible background"""
	super.set_selected(selected)
	_ensure_background_visible()


func _ensure_background_visible():
	"""Force the background to always be visible for equipment slots"""
	if not visuals or not visuals.background_panel:
		return

	visuals.background_panel.visible = true

	# Create fresh style box each time to prevent modifications
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	style_box.border_width_left = 2
	style_box.border_width_right = 2
	style_box.border_width_top = 2
	style_box.border_width_bottom = 2
	style_box.border_color = Color(0.4, 0.4, 0.4, 1.0)
	style_box.corner_radius_top_left = 4
	style_box.corner_radius_top_right = 4
	style_box.corner_radius_bottom_left = 4
	style_box.corner_radius_bottom_right = 4

	visuals.background_panel.add_theme_stylebox_override("panel", style_box)


# Equipment-specific helper methods
func get_equipped_stats() -> Dictionary:
	"""Get the stats provided by the equipped item"""
	if not item:
		return {}

	if item.has_method("get_stats"):
		return item.get_stats()

	return {}


func get_item_bonuses() -> Dictionary:
	"""Get bonuses provided by the equipped item"""
	if not item:
		return {}

	if item.has_method("get_bonuses"):
		return item.get_bonuses()

	# Fallback to metadata
	return item.get_meta("bonuses", {})


func is_equipment_damaged() -> bool:
	"""Check if equipped item is damaged"""
	if not item:
		return false

	if item.has_method("get_durability"):
		var durability = item.get_durability()
		var max_durability = item.get_max_durability()
		return durability < max_durability

	return false


func get_equipment_durability_percent() -> float:
	"""Get equipment durability as percentage"""
	if not item:
		return 0.0

	if item.has_method("get_durability"):
		var durability = item.get_durability()
		var max_durability = item.get_max_durability()
		if max_durability > 0:
			return (durability / max_durability) * 100.0

	return 100.0
