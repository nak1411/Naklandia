# EquipmentWindow.gd - Player equipment management window
class_name EquipmentWindow
extends Window_Base

# Equipment slot types
enum EquipmentSlotType { HEAD, CHEST, LEGS, HANDS, FEET, WEAPON_PRIMARY, WEAPON_SECONDARY, ACCESSORY_1, ACCESSORY_2 }

# UI Components
var equipment_panel: Panel
var equipment_container: VBoxContainer
var equipment_slots: Dictionary = {}  # EquipmentSlotType -> EquipmentSlot

# Data
var inventory_manager: InventoryManager
var equipped_items: Dictionary = {}  # EquipmentSlotType -> InventoryItem_Base


func _ready():
	window_title = "Equipment"
	default_size = Vector2(480, 520)
	min_window_size = Vector2(400, 450)
	can_resize = true

	# Ensure we receive GUI input for drag and drop
	mouse_filter = Control.MOUSE_FILTER_PASS

	super._ready()


func _setup_window_content():
	"""Override Window_Base virtual method to setup equipment UI"""
	_setup_equipment_ui()


func _gui_input(event: InputEvent):
	"""Handle GUI input for drag and drop"""
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton

		# Check for drag operations on mouse button release
		if not mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var viewport = get_viewport()
			if viewport and viewport.has_meta("current_drag_data"):
				var drag_data = viewport.get_meta("current_drag_data")

				# Check if we're dropping on an equipment slot
				if _handle_equipment_drop(drag_data, mouse_event.global_position):
					get_viewport().set_input_as_handled()
					return


func _handle_equipment_drop(drag_data: Dictionary, drop_position: Vector2) -> bool:
	"""Handle dropping items on equipment slots"""
	print("EquipmentWindow: _handle_equipment_drop called at ", drop_position)

	var source_item = drag_data.get("item") as InventoryItem_Base
	var source_slot = drag_data.get("source_slot") as InventorySlot

	if not source_item or not source_slot:
		print("  No source item or slot")
		return false

	print("  Source item: ", source_item.item_name)

	# Check each equipment slot to see if the drop position is over it
	for slot_type in equipment_slots:
		var equipment_slot = equipment_slots[slot_type]
		if not equipment_slot or not is_instance_valid(equipment_slot):
			continue

		var slot_rect = Rect2(equipment_slot.global_position, equipment_slot.size)
		if slot_rect.has_point(drop_position):
			print("  Drop is over slot: ", equipment_slot.name)

			# Check if the item can be equipped in this slot
			if not _can_equip_in_slot(source_item, slot_type):
				print("  Item cannot be equipped in this slot type")
				return false

			# Equip the item
			print("  Equipping item!")
			_equip_item(source_item, slot_type)

			# Notify source slot of successful drop
			if source_slot.has_method("_on_external_drop_result"):
				source_slot._on_external_drop_result(true)

			# Clean up drag data
			get_viewport().remove_meta("current_drag_data")

			return true

	print("  Drop not over any equipment slot")
	return false


func _setup_equipment_ui():
	"""Set up the main equipment UI layout - WoW style"""
	# Main container with padding
	var main_margin = MarginContainer.new()
	main_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_margin.add_theme_constant_override("margin_left", 20)
	main_margin.add_theme_constant_override("margin_right", 20)
	main_margin.add_theme_constant_override("margin_top", 20)
	main_margin.add_theme_constant_override("margin_bottom", 20)
	content_area.add_child(main_margin)

	# Create a grid container for WoW-style layout
	var layout_container = GridContainer.new()
	layout_container.columns = 3
	layout_container.add_theme_constant_override("h_separation", 40)
	layout_container.add_theme_constant_override("v_separation", 15)
	main_margin.add_child(layout_container)

	# LEFT COLUMN
	var left_column = VBoxContainer.new()
	left_column.add_theme_constant_override("separation", 15)
	left_column.custom_minimum_size.x = 100
	layout_container.add_child(left_column)

	_create_slot_in_column(left_column, EquipmentSlotType.HEAD, "Head")
	_create_slot_in_column(left_column, EquipmentSlotType.CHEST, "Chest")
	_create_slot_in_column(left_column, EquipmentSlotType.LEGS, "Legs")
	_create_slot_in_column(left_column, EquipmentSlotType.FEET, "Feet")

	# CENTER COLUMN (Character preview placeholder)
	var center_panel = Panel.new()
	center_panel.custom_minimum_size = Vector2(180, 400)
	layout_container.add_child(center_panel)

	# Style center panel
	var center_style = StyleBoxFlat.new()
	center_style.bg_color = Color(0.05, 0.05, 0.05, 0.5)
	center_style.border_width_left = 1
	center_style.border_width_right = 1
	center_style.border_width_top = 1
	center_style.border_width_bottom = 1
	center_style.border_color = Color(0.2, 0.2, 0.2, 0.8)
	center_panel.add_theme_stylebox_override("panel", center_style)

	# Add placeholder label
	var placeholder_label = Label.new()
	placeholder_label.text = "Character\nPreview"
	placeholder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	placeholder_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1.0))
	placeholder_label.add_theme_font_size_override("font_size", 16)
	center_panel.add_child(placeholder_label)

	# RIGHT COLUMN
	var right_column = VBoxContainer.new()
	right_column.add_theme_constant_override("separation", 15)
	right_column.custom_minimum_size.x = 100
	layout_container.add_child(right_column)

	_create_slot_in_column(right_column, EquipmentSlotType.HANDS, "Hands")
	_create_slot_in_column(right_column, EquipmentSlotType.ACCESSORY_1, "Accessory")
	_create_slot_in_column(right_column, EquipmentSlotType.ACCESSORY_2, "Accessory")

	# Add spacer to push weapons to bottom
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout_container.add_child(spacer)

	# BOTTOM WEAPONS ROW
	var weapons_container = HBoxContainer.new()
	weapons_container.add_theme_constant_override("separation", 30)
	weapons_container.alignment = BoxContainer.ALIGNMENT_CENTER
	layout_container.add_child(weapons_container)

	# Add second spacer
	var spacer2 = Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout_container.add_child(spacer2)

	# Create weapon slots horizontally
	_create_slot_in_row(weapons_container, EquipmentSlotType.WEAPON_PRIMARY, "Primary")
	_create_slot_in_row(weapons_container, EquipmentSlotType.WEAPON_SECONDARY, "Secondary")


func _configure_slot_categories(slot: EquipmentSlot, slot_type: EquipmentSlotType):
	"""Configure which item categories a slot can accept"""
	var categories: Array[String] = []

	match slot_type:
		EquipmentSlotType.HEAD:
			categories = ["head", "helmet", "hat"]
		EquipmentSlotType.CHEST:
			categories = ["chest", "armor", "torso"]
		EquipmentSlotType.LEGS:
			categories = ["legs", "pants", "leggings"]
		EquipmentSlotType.HANDS:
			categories = ["hands", "gloves", "gauntlets"]
		EquipmentSlotType.FEET:
			categories = ["feet", "boots", "shoes"]
		EquipmentSlotType.WEAPON_PRIMARY, EquipmentSlotType.WEAPON_SECONDARY:
			categories = ["weapon", "tool", "melee", "ranged"]
		EquipmentSlotType.ACCESSORY_1, EquipmentSlotType.ACCESSORY_2:
			categories = ["accessory", "ring", "amulet", "trinket"]

	slot.set_allowed_categories(categories)
	print("  Configured categories for ", slot.name, ": ", categories)


func _create_slot_in_column(column: VBoxContainer, slot_type: EquipmentSlotType, label_text: String):
	"""Create a slot with label in a vertical column"""
	print("Creating equipment slot: ", label_text)

	# Slot container
	var slot_container = VBoxContainer.new()
	slot_container.add_theme_constant_override("separation", 5)
	column.add_child(slot_container)

	# Equipment slot
	var slot = EquipmentSlot.new()
	slot.name = "EquipmentSlot_" + label_text.replace(" ", "_")
	slot.slot_size = Vector2(64, 64)
	slot.custom_minimum_size = Vector2(64, 64)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Set allowed categories based on slot type
	_configure_slot_categories(slot, slot_type)

	slot_container.add_child(slot)

	print("  Slot created: ", slot.name)
	print("  Slot size: ", slot.size, ", min_size: ", slot.custom_minimum_size)
	print("  Slot in tree: ", slot.is_inside_tree())
	print("  Slot parent: ", slot.get_parent())
	print("  Allowed categories: ", slot.get_allowed_categories())

	# Label below slot
	var label = Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	slot_container.add_child(label)

	# Store slot reference
	equipment_slots[slot_type] = slot

	# Connect slot signals
	slot.slot_clicked.connect(_on_equipment_slot_clicked.bind(slot_type))
	slot.slot_right_clicked.connect(_on_equipment_slot_right_clicked.bind(slot_type))
	slot.item_dropped_on_slot.connect(_on_item_dropped_on_equipment.bind(slot_type))

	print("  Slot fully set up for: ", label_text)


func _create_slot_in_row(row: HBoxContainer, slot_type: EquipmentSlotType, label_text: String):
	"""Create a slot with label in a horizontal row"""
	print("Creating equipment slot: ", label_text)

	# Slot container
	var slot_container = VBoxContainer.new()
	slot_container.add_theme_constant_override("separation", 5)
	row.add_child(slot_container)

	# Equipment slot
	var slot = EquipmentSlot.new()
	slot.name = "EquipmentSlot_" + label_text.replace(" ", "_")
	slot.slot_size = Vector2(64, 64)
	slot.custom_minimum_size = Vector2(64, 64)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Set allowed categories based on slot type
	_configure_slot_categories(slot, slot_type)

	slot_container.add_child(slot)

	print("  Slot created: ", slot.name)
	print("  Slot size: ", slot.size, ", min_size: ", slot.custom_minimum_size)
	print("  Slot in tree: ", slot.is_inside_tree())
	print("  Allowed categories: ", slot.get_allowed_categories())

	# Label below slot
	var label = Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	slot_container.add_child(label)

	# Store slot reference
	equipment_slots[slot_type] = slot

	# Connect slot signals
	slot.slot_clicked.connect(_on_equipment_slot_clicked.bind(slot_type))
	slot.slot_right_clicked.connect(_on_equipment_slot_right_clicked.bind(slot_type))
	slot.item_dropped_on_slot.connect(_on_item_dropped_on_equipment.bind(slot_type))

	print("  Slot fully set up for: ", label_text)


func _on_equipment_slot_clicked(slot: EquipmentSlot, _event: InputEvent, slot_type: EquipmentSlotType):
	"""Handle equipment slot click"""
	if slot.has_item():
		# Unequip item
		_unequip_item(slot_type)


func _on_equipment_slot_right_clicked(slot: EquipmentSlot, event: InputEvent, slot_type: EquipmentSlotType):
	"""Handle equipment slot right-click"""
	if slot.has_item():
		# Show context menu for equipped item
		_show_equipment_context_menu(slot_type, event.position)


func _on_item_dropped_on_equipment(source_slot: InventorySlot, _target_slot: EquipmentSlot, slot_type: EquipmentSlotType):
	"""Handle item dropped on equipment slot"""
	print("EquipmentWindow._on_item_dropped_on_equipment called")
	print("  Slot type: ", _get_slot_name(slot_type))

	if not source_slot.has_item():
		print("  Source slot has no item - aborting")
		return

	var item = source_slot.get_item()
	print("  Item: ", item.item_name)

	# Validate item can be equipped in this slot
	if not _can_equip_in_slot(item, slot_type):
		print("  Cannot equip ", item.item_name, " in ", _get_slot_name(slot_type))
		return

	print("  Equipping item...")
	# Equip the item
	_equip_item(item, slot_type)


func _can_equip_in_slot(item: InventoryItem_Base, slot_type: EquipmentSlotType) -> bool:
	"""Check if an item can be equipped in the specified slot"""
	print("  _can_equip_in_slot called")

	if not item:
		print("    No item provided")
		return false

	# This would check item type/category matches the slot
	# For now, simplified version
	var item_category = item.get_meta("equipment_category", "")
	print("    Item: ", item.item_name)
	print("    Item category: '", item_category, "'")
	print("    Slot type: ", _get_slot_name(slot_type))

	# TEMPORARY: Accept any item for testing if no category set
	if item_category.is_empty():
		print("    No category - ACCEPTING FOR TESTING")
		return true

	var can_equip = false
	match slot_type:
		EquipmentSlotType.HEAD:
			can_equip = item_category == "head" or item_category == "helmet"
		EquipmentSlotType.CHEST:
			can_equip = item_category == "chest" or item_category == "armor"
		EquipmentSlotType.LEGS:
			can_equip = item_category == "legs" or item_category == "pants"
		EquipmentSlotType.HANDS:
			can_equip = item_category == "hands" or item_category == "gloves"
		EquipmentSlotType.FEET:
			can_equip = item_category == "feet" or item_category == "boots"
		EquipmentSlotType.WEAPON_PRIMARY, EquipmentSlotType.WEAPON_SECONDARY:
			can_equip = item_category == "weapon" or item_category == "tool"
		EquipmentSlotType.ACCESSORY_1, EquipmentSlotType.ACCESSORY_2:
			can_equip = item_category == "accessory"

	print("    Can equip: ", can_equip)
	return can_equip


func _equip_item(item: InventoryItem_Base, slot_type: EquipmentSlotType):
	"""Equip an item in the specified slot"""
	# If slot already has item, unequip it first
	if slot_type in equipped_items and equipped_items[slot_type]:
		_unequip_item(slot_type)

	# Equip new item
	equipped_items[slot_type] = item
	equipment_slots[slot_type].set_item(item)

	# Notify player adapter
	_notify_item_equipped(item)

	print("Equipped ", item.item_name, " in ", _get_slot_name(slot_type))


func _unequip_item(slot_type: EquipmentSlotType):
	"""Unequip an item from the specified slot"""
	if not slot_type in equipped_items:
		return

	var item = equipped_items[slot_type]
	if not item:
		return

	# Remove from slot
	equipment_slots[slot_type].clear_item()
	equipped_items.erase(slot_type)

	# Notify player adapter
	_notify_item_unequipped(item)

	# Return item to inventory would be handled here

	print("Unequipped ", item.item_name, " from ", _get_slot_name(slot_type))


func _show_equipment_context_menu(slot_type: EquipmentSlotType, menu_position: Vector2):
	"""Show context menu for equipped item"""
	var item = equipped_items.get(slot_type)
	if not item:
		return

	# Create simple popup menu
	var popup = PopupMenu.new()
	popup.add_item("Unequip")
	popup.add_item("Inspect")
	popup.position = menu_position
	add_child(popup)

	popup.id_pressed.connect(
		func(id):
			match id:
				0:  # Unequip
					_unequip_item(slot_type)
				1:  # Inspect
					_inspect_item(item)
			popup.queue_free()
	)

	popup.popup()


func _inspect_item(_item: InventoryItem_Base):
	"""Show detailed item information"""
	# This would open an item detail dialog
	return


func _notify_item_equipped(_item: InventoryItem_Base):
	"""Notify systems that an item was equipped"""
	# This would notify player adapter, stats system, etc.
	return


func _notify_item_unequipped(_item: InventoryItem_Base):
	"""Notify systems that an item was unequipped"""
	# This would notify player adapter, stats system, etc.
	return


func _get_slot_name(slot_type: EquipmentSlotType) -> String:
	"""Get display name for a slot type"""
	match slot_type:
		EquipmentSlotType.HEAD:
			return "Head"
		EquipmentSlotType.CHEST:
			return "Chest"
		EquipmentSlotType.LEGS:
			return "Legs"
		EquipmentSlotType.HANDS:
			return "Hands"
		EquipmentSlotType.FEET:
			return "Feet"
		EquipmentSlotType.WEAPON_PRIMARY:
			return "Primary Weapon"
		EquipmentSlotType.WEAPON_SECONDARY:
			return "Secondary Weapon"
		EquipmentSlotType.ACCESSORY_1:
			return "Accessory 1"
		EquipmentSlotType.ACCESSORY_2:
			return "Accessory 2"
	return "Unknown"


# Public interface
func set_inventory_manager(manager: InventoryManager):
	"""Set the inventory manager reference"""
	inventory_manager = manager


func get_equipped_item(slot_type: EquipmentSlotType) -> InventoryItem_Base:
	"""Get the item equipped in a specific slot"""
	return equipped_items.get(slot_type)


func get_all_equipped_items() -> Array[InventoryItem_Base]:
	"""Get all currently equipped items"""
	var items: Array[InventoryItem_Base] = []
	for item in equipped_items.values():
		if item:
			items.append(item)
	return items


func clear_all_equipment():
	"""Unequip all items"""
	for slot_type in equipped_items.keys():
		_unequip_item(slot_type)


func refresh_display():
	"""Refresh the equipment display"""
	for slot_type in equipment_slots:
		var slot = equipment_slots[slot_type]
		if slot_type in equipped_items:
			slot.set_item(equipped_items[slot_type])
		else:
			slot.clear_item()
