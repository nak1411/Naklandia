# EquipmentWindow.gd - Player equipment management window
class_name EquipmentWindow
extends Window_Base

# Equipment slot types
enum EquipmentSlotType {
	HEAD, CHEST, LEGS, HANDS, FEET, WEAPON_PRIMARY, WEAPON_SECONDARY, ACCESSORY_1, ACCESSORY_2
}

# UI Components
var equipment_panel: Panel
var equipment_container: VBoxContainer
var equipment_slots: Dictionary = {}  # EquipmentSlotType -> EquipmentSlot

# Data
var inventory_manager: InventoryManager
var equipped_items: Dictionary = {}  # EquipmentSlotType -> InventoryItem_Base

# Context menu
var equipment_context_menu: ContextMenu_Base


func _ready():
	window_title = "Equipment"
	default_size = Vector2(480, 520)
	min_window_size = Vector2(400, 450)
	can_resize = true

	# Ensure we receive GUI input for drag and drop
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Initialize styled context menu
	equipment_context_menu = ContextMenu_Base.new()
	equipment_context_menu.name = "EquipmentContextMenu"
	add_child(equipment_context_menu)

	# Connect context menu signals
	equipment_context_menu.item_selected.connect(_on_equipment_context_menu_selected)

	super._ready()


func _setup_window_content():
	"""Override Window_Base virtual method to setup equipment UI"""
	_setup_equipment_ui()


func _gui_input(event: InputEvent):
	"""Handle GUI input for drag and drop"""
	if not is_inside_tree():
		return

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


func _unhandled_input(event: InputEvent):
	"""Handle unhandled input"""
	if not is_inside_tree():
		return

	if (
		event is InputEventMouseButton
		and not event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		print("EquipmentWindow _unhandled_input called at: ", event.global_position)

		var viewport = get_viewport()
		if viewport and viewport.has_meta("current_drag_data"):
			var drag_data = viewport.get_meta("current_drag_data")
			var source_slot = drag_data.get("source_slot")

			# Check if this is a drag from our equipment slots
			if source_slot and source_slot.container_id == "equipment":
				print("EquipmentWindow: Detected equipment drag release")

				# Check if dropping over inventory window
				var inventory_window = _find_inventory_window()
				if inventory_window:
					var inv_rect = Rect2(inventory_window.global_position, inventory_window.size)
					if inv_rect.has_point(event.global_position):
						print("  Release is over inventory window, letting it handle the drop")
						# Don't set as handled - let the slot's drag handler process this
						return

		var my_rect = Rect2(global_position, size)
		if my_rect.has_point(event.global_position):
			print("EquipmentWindow would handle this input")


func _find_inventory_window():
	"""Find the inventory window"""
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("inventory_window")


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

			# CRITICAL: Check if dropping same item on itself
			var currently_equipped = equipped_items.get(slot_type)
			if currently_equipped and currently_equipped == source_item:
				print("  Same item already equipped in this slot - cancelling drag")

				# Notify source slot that the drop failed so it can restore the item
				if source_slot.has_method("_on_external_drop_result"):
					source_slot._on_external_drop_result(false)

				# Force refresh the source container/grid display
				_force_refresh_inventory_display()

				# Clean up drag data
				if is_inside_tree():
					get_viewport().remove_meta("current_drag_data")

				return false

			# Check if the item can be equipped in this slot
			if not _can_equip_in_slot(source_item, slot_type):
				print("  Item cannot be equipped in this slot type - cancelling drag")

				# Notify source slot that the drop failed so it can restore the item
				if source_slot.has_method("_on_external_drop_result"):
					source_slot._on_external_drop_result(false)

				# Force refresh the source container/grid display
				_force_refresh_inventory_display()

				# Clean up drag data
				if is_inside_tree():
					get_viewport().remove_meta("current_drag_data")

				return false

			# Handle swapping if slot is already occupied
			var item_to_swap = null
			if currently_equipped:
				print("  Slot already has item: ", currently_equipped.item_name, " - will swap")
				item_to_swap = currently_equipped

			# Equip the new item
			print("  Equipping item!")
			_equip_item(source_item, slot_type)

			# If swapping, put the old item in the source location
			if item_to_swap:
				print("  Placing swapped item back in source")
				# Put the old equipped item where the new item came from
				source_slot.set_item(item_to_swap)

				# Update the source container
				if source_slot.container_id != "equipment":
					var source_container = inventory_manager.get_container(source_slot.container_id)
					if source_container:
						# Remove the new item and add the old item
						source_container.remove_item(source_item)
						source_container.add_item(item_to_swap)

			# Notify source slot of successful drop
			if source_slot.has_method("_on_external_drop_result"):
				source_slot._on_external_drop_result(true)

			# Clean up drag data
			if is_inside_tree():
				get_viewport().remove_meta("current_drag_data")

			return true

	print("  Drop not over any equipment slot - cancelling drag")

	# Notify source slot that the drop failed so it can restore the item
	if source_slot.has_method("_on_external_drop_result"):
		source_slot._on_external_drop_result(false)

	# Force refresh the source container/grid display
	_force_refresh_inventory_display()

	# Clean up drag data
	if is_inside_tree():
		get_viewport().remove_meta("current_drag_data")

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


func _create_slot_in_column(
	column: VBoxContainer, slot_type: EquipmentSlotType, label_text: String
):
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

	# Defer drag_handler signal connection to ensure slot is fully ready
	call_deferred("_connect_drag_handler_signals", slot, slot_type)

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

	# Defer drag_handler signal connection to ensure slot is fully ready
	call_deferred("_connect_drag_handler_signals", slot, slot_type)

	print("  Slot fully set up for: ", label_text)


func _connect_drag_handler_signals(slot: EquipmentSlot, slot_type: EquipmentSlotType):
	"""Deferred method to connect drag handler signals after slot is fully ready"""
	if not slot or not is_instance_valid(slot):
		return

	if slot.drag_handler:
		slot.drag_handler.item_dropped_on_slot.connect(
			func(source, target):
				print("SIGNAL FIRED: item_dropped_on_slot")
				print("  source: ", source.name if source else "NULL")
				print("  target: ", target.name if target else "NULL")
				print("  source == slot: ", source == slot)
				print("  target.container_id: ", target.container_id if target else "NULL")
				if source == slot and target.container_id != "equipment":
					print("  Calling _on_equipment_item_dragged_to_inventory")
					_on_equipment_item_dragged_to_inventory(slot, target, slot_type)
				else:
					print("  NOT calling _on_equipment_item_dragged_to_inventory")
		)


func _on_equipment_slot_clicked(
	_slot: EquipmentSlot, _event: InputEvent, _slot_type: EquipmentSlotType
):
	"""Handle equipment slot click"""
	# DON'T unequip on left click - that interferes with dragging
	# Unequip only happens via:
	# 1. Right-click context menu
	# 2. Dragging to inventory
	# 3. Dedicated unequip button
	return


func _on_equipment_slot_right_clicked(
	slot: EquipmentSlot, event: InputEvent, slot_type: EquipmentSlotType
):
	"""Handle equipment slot right-click"""
	if slot.has_item():
		# Show context menu for equipped item - use global_position for proper positioning
		if event is InputEventMouseButton:
			_show_equipment_context_menu(slot_type, event.global_position)
		else:
			_show_equipment_context_menu(slot_type, event.position)


func _on_item_dropped_on_equipment(
	source_slot: InventorySlot, _target_slot: EquipmentSlot, slot_type: EquipmentSlotType
):
	"""Handle item dropped on equipment slot"""
	print("EquipmentWindow._on_item_dropped_on_equipment called")
	print("  Slot type: ", _get_slot_name(slot_type))

	if not source_slot.has_item():
		print("  Source slot has no item - aborting")
		return

	var item = source_slot.get_item()
	print("  Item: ", item.item_name)

	# CRITICAL: Check if dropping same item on itself
	var currently_equipped = equipped_items.get(slot_type)
	if currently_equipped and currently_equipped == item:
		print("  Same item already equipped in this slot - cancelling drop")
		# Restore source slot
		if source_slot.has_method("_on_external_drop_result"):
			source_slot._on_external_drop_result(false)
		return

	# Validate item can be equipped in this slot
	if not _can_equip_in_slot(item, slot_type):
		print("  Cannot equip ", item.item_name, " in ", _get_slot_name(slot_type))
		return

	print("  Equipping item...")

	# Handle swapping if slot is already occupied
	var item_to_swap = null
	if currently_equipped:
		print("  Slot already has item: ", currently_equipped.item_name, " - swapping")
		item_to_swap = currently_equipped

	# Equip the new item
	_equip_item(item, slot_type)

	# If swapping, put the old item in the source location
	if item_to_swap:
		print("  Placing swapped item back in source")
		# Put the old equipped item where the new item came from
		source_slot.set_item(item_to_swap)

		# Update the source container
		if inventory_manager and source_slot.container_id != "equipment":
			var source_container = inventory_manager.get_container(source_slot.container_id)
			if source_container:
				# Remove the new item and add the old item
				source_container.remove_item(item)
				source_container.add_item(item_to_swap)
	else:
		# No swap - just remove from source
		# CRITICAL: Remove the item from the source slot
		source_slot.clear_item()

		# Make the source slot visually disappear immediately
		source_slot.modulate.a = 0.0
		source_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Trigger refresh of the source container
		if inventory_manager:
			var source_container = inventory_manager.get_container(source_slot.container_id)
			if source_container:
				source_container.remove_item(item)

	# Clean up drag state on source slot
	if source_slot.drag_handler:
		source_slot.drag_handler.is_dragging = false
		source_slot.drag_handler.drag_preview_created = false

	# Ensure equipment slot visual is correct
	_target_slot._ensure_background_visible()

	print("  Item equipped successfully")


func _on_equipment_item_dragged_to_inventory(
	equipment_slot: EquipmentSlot, target_slot: InventorySlot, slot_type: EquipmentSlotType
):
	"""Handle dragging equipped item back to inventory"""
	print("EquipmentWindow: _on_equipment_item_dragged_to_inventory called!")
	print("  Equipment slot: ", equipment_slot.name)
	print("  Target slot: ", target_slot.name if target_slot else "NULL")
	print("  Target container_id: ", target_slot.container_id if target_slot else "NULL")

	if not equipment_slot.has_item():
		print("  Equipment slot has no item!")
		return

	var item = equipment_slot.get_item()
	print("  Item to unequip: ", item.item_name)

	# Check if the target slot can accept the item
	if target_slot.has_item():
		var target_item = target_slot.get_item()
		if not item.can_stack_with(target_item):
			print("  Cannot drop on occupied slot")
			return

	# Check if inventory has space
	if not inventory_manager:
		print("  No inventory manager!")
		return

	var target_container = inventory_manager.get_container(target_slot.container_id)
	if not target_container:
		print("  No target container!")
		return

	if not target_container.can_add_item(item):
		print("  Inventory doesn't have space")
		return

	# Unequip the item
	print("  Calling _unequip_item...")
	_unequip_item(slot_type)

	# Add to inventory container
	if not target_container.add_item(item):
		print("  ERROR: Failed to add item to container!")
		return

	# Update the slot visually
	target_slot.set_item(item)

	print("  Item unequipped and moved to inventory successfully")


func _can_equip_in_slot(item: InventoryItem_Base, slot_type: EquipmentSlotType) -> bool:
	"""Check if an item can be equipped in the specified slot"""
	print("  _can_equip_in_slot called")

	if not item:
		print("    No item provided")
		return false

	# Block materials/resources from being equipped
	if item.item_type == ItemTypes.Type.RESOURCE:
		print("    Item is a RESOURCE - materials cannot be equipped")
		return false

	# Get the item's equipment category
	var item_category = item.get_meta("equipment_category", "")

	# FALLBACK: Infer category from item type if not set
	if item_category.is_empty():
		match item.item_type:
			ItemTypes.Type.TOOL:
				item_category = "tool"
			ItemTypes.Type.WEAPON:
				item_category = "weapon"
			ItemTypes.Type.ARMOR:
				item_category = "chest"  # Default armor to chest
			_:
				# Not a valid equipment type
				print("    Item has no valid equipment category - REJECTING")
				return false

	print("    Item: ", item.item_name)
	print("    Item category: '", item_category, "'")
	print("    Slot type: ", _get_slot_name(slot_type))

	var can_equip = false
	match slot_type:
		EquipmentSlotType.HEAD:
			can_equip = item_category in ["head", "helmet", "hat"]
		EquipmentSlotType.CHEST:
			can_equip = item_category in ["chest", "armor", "torso"]
		EquipmentSlotType.LEGS:
			can_equip = item_category in ["legs", "pants", "leggings"]
		EquipmentSlotType.HANDS:
			can_equip = item_category in ["hands", "gloves", "gauntlets"]
		EquipmentSlotType.FEET:
			can_equip = item_category in ["feet", "boots", "shoes"]
		EquipmentSlotType.WEAPON_PRIMARY, EquipmentSlotType.WEAPON_SECONDARY:
			can_equip = item_category in ["weapon", "tool", "melee", "ranged"]
		EquipmentSlotType.ACCESSORY_1, EquipmentSlotType.ACCESSORY_2:
			can_equip = item_category in ["accessory", "ring", "amulet", "trinket"]

	print("    Can equip: ", can_equip)
	return can_equip


func _equip_item(item: InventoryItem_Base, slot_type: EquipmentSlotType):
	"""Equip an item in the specified slot"""
	# CRITICAL: Check if this item is already equipped in another slot
	for existing_slot_type in equipped_items:
		if equipped_items[existing_slot_type] == item:
			print(
				"WARNING: Item ",
				item.item_name,
				" is already equipped in ",
				_get_slot_name(existing_slot_type)
			)
			print("  Unequipping from ", _get_slot_name(existing_slot_type), " first")
			_unequip_item(existing_slot_type)
			break

	# If slot already has item, unequip it first
	if slot_type in equipped_items and equipped_items[slot_type]:
		_unequip_item(slot_type)

	# Equip new item
	equipped_items[slot_type] = item
	equipment_slots[slot_type].set_item(item)

	# Notify player adapter
	_notify_item_equipped(item, slot_type)

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
	_notify_item_unequipped(item, slot_type)

	# Return item to inventory would be handled here

	print("Unequipped ", item.item_name, " from ", _get_slot_name(slot_type))


func _show_equipment_context_menu(slot_type: EquipmentSlotType, click_position: Vector2):
	"""Show context menu for equipped item with same styling as inventory items"""
	var item = equipped_items.get(slot_type)
	if not item:
		return

	var equipment_slot = equipment_slots.get(slot_type)
	if not equipment_slot:
		return

	# Clear previous items and add equipment-specific options
	equipment_context_menu.clear_items()
	equipment_context_menu.add_menu_item("unequip", "Unequip")
	equipment_context_menu.add_menu_item("inspect", "Inspect")
	equipment_context_menu.add_separator()
	equipment_context_menu.add_menu_item("destroy", "Destroy")

	# Show the context menu with equipment context data
	var context_data = {
		"item": item, "slot": equipment_slot, "slot_type": slot_type, "action_type": "equipment"
	}

	# Pass null for parent_window since we're using DisplayServer positioning
	equipment_context_menu.show_context_menu(click_position, context_data, null)


func _on_equipment_context_menu_selected(
	item_id: String, _item_data: Dictionary, context_data: Dictionary
):
	"""Handle equipment context menu selection"""
	var slot_type = context_data.get("slot_type")
	var item = context_data.get("item")

	match item_id:
		"unequip":
			if slot_type != null and item:
				_unequip_to_inventory(slot_type, item)
		"inspect":
			if item:
				_inspect_item(item)
		"destroy":
			if slot_type != null and item:
				_destroy_equipped_item(slot_type, item)


func _unequip_to_inventory(slot_type: EquipmentSlotType, item: InventoryItem_Base):
	"""Unequip an item and return it to the player's inventory"""
	if not inventory_manager:
		push_error("EquipmentWindow: Cannot unequip - no inventory manager")
		return

	# Get the player inventory container
	var player_inventory = inventory_manager.get_container("player_inventory")
	if not player_inventory:
		push_error("EquipmentWindow: Cannot unequip - player inventory not found")
		return

	# Check if inventory has space
	if not player_inventory.can_add_item(item):
		push_error("EquipmentWindow: Cannot unequip - inventory is full")
		# TODO: Show user feedback that inventory is full
		return

	# Unequip the item (removes from equipment slot)
	_unequip_item(slot_type)

	# Add to player inventory
	if player_inventory.add_item(item):
		print("EquipmentWindow: Unequipped ", item.item_name, " and added to inventory")
	else:
		push_error("EquipmentWindow: Failed to add unequipped item to inventory")
		# Item is now lost! This shouldn't happen since we checked can_add_item


func _destroy_equipped_item(slot_type: EquipmentSlotType, item: InventoryItem_Base):
	"""Destroy an equipped item permanently"""
	# Unequip the item first
	_unequip_item(slot_type)

	# Item is now removed from equipment and will be garbage collected
	print("EquipmentWindow: Destroyed equipped item: ", item.item_name)


func _inspect_item(_item: InventoryItem_Base):
	"""Show detailed item information"""
	# This would open an item detail dialog
	return


func _notify_item_equipped(item: InventoryItem_Base, slot_type: EquipmentSlotType):
	"""Notify systems that an item was equipped"""
	if not is_inside_tree():
		return

	# Notify player to update 3D visual
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("update_equipment_visual"):
		player.update_equipment_visual(item, slot_type, true)

	# Defer auto-save to next frame so inventory changes complete first
	call_deferred("_auto_save_equipment")


func _notify_item_unequipped(item: InventoryItem_Base, slot_type: EquipmentSlotType):
	"""Notify systems that an item was unequipped"""
	if not is_inside_tree():
		return

	# Notify player to update 3D visual
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("update_equipment_visual"):
		player.update_equipment_visual(item, slot_type, false)

	# Defer auto-save to next frame so inventory changes complete first
	call_deferred("_auto_save_equipment")


func _auto_save_equipment():
	"""Auto-save equipment state whenever items are equipped/unequipped"""
	if not inventory_manager:
		return

	if not inventory_manager.save_system:
		return

	# Save the entire inventory (including equipment)
	inventory_manager.save_system.save_inventory()
	print("EquipmentWindow: Auto-saved equipment state")


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


func _force_refresh_inventory_display():
	"""Force refresh the inventory display when a drag operation is cancelled"""
	if not is_inside_tree():
		return

	# Find the inventory integration to trigger a refresh
	var integration_nodes = get_tree().get_nodes_in_group("inventory_integration")
	if integration_nodes.size() > 0:
		var integration = integration_nodes[0]
		if integration.has_method("_refresh_inventory_display"):
			integration._refresh_inventory_display()


# Save/Load Equipment State
func to_dict() -> Dictionary:
	"""Serialize equipment state to dictionary"""
	var data = {"equipped_items": {}}

	# Serialize each equipped item
	for slot_type in equipped_items:
		var item = equipped_items[slot_type]
		if item and item.has_method("to_dict"):
			# Store both slot type (as int) and item data
			data.equipped_items[str(slot_type)] = item.to_dict()

	return data


func from_dict(data: Dictionary):
	"""Deserialize equipment state from dictionary"""
	# Clear current equipment
	clear_all_equipment()

	# Load equipped items
	var equipped_data = data.get("equipped_items", {})
	for slot_type_str in equipped_data:
		var slot_type = int(slot_type_str)
		var item_data = equipped_data[slot_type_str]

		# Reconstruct the item
		var item = _reconstruct_item_from_dict(item_data)
		if item:
			# Equip the item
			equipped_items[slot_type] = item
			if slot_type in equipment_slots:
				equipment_slots[slot_type].set_item(item)

			# Notify visual system when loading from save
			_notify_item_equipped(item, slot_type)

	print("EquipmentWindow: Loaded ", equipped_data.size(), " equipped items")


func _reconstruct_item_from_dict(item_data: Dictionary) -> InventoryItem_Base:
	"""Reconstruct an item from serialized data"""
	var item_id = item_data.get("item_id", "")

	if item_id.is_empty():
		push_error("EquipmentWindow: Item data missing item_id!")
		return null

	# Try to get the item database
	var item_database = null

	# Try AutoLoad singleton first (most likely)
	if has_node("/root/ItemDatabase"):
		item_database = get_node("/root/ItemDatabase")

	# Try group lookup as fallback
	if not item_database and is_inside_tree():
		var databases = get_tree().get_nodes_in_group("item_database")
		if not databases.is_empty():
			item_database = databases[0]

	if not item_database:
		push_error("EquipmentWindow: Could not find ItemDatabase (tried AutoLoad and groups)")
		return null

	# Create item instance from item_id
	var item = item_database.create_item_instance(item_id)
	if not item:
		push_error("EquipmentWindow: Failed to create item with id: ", item_id)
		return null

	# Restore item data (quantity, etc.)
	if item.has_method("from_dict"):
		item.from_dict(item_data)

	return item
