# InventoryHUD.gd - Quick access inventory HUD for player
class_name InventoryHUD
extends Control

# HUD properties
@export var slot_count: int = 8
@export var slot_size: Vector2 = Vector2(48, 48)
@export var slot_spacing: float = 4.0
@export var show_hotkeys: bool = true

# UI components
var background_panel: Panel
var slots_container: HBoxContainer
var quick_slots: Array[InventorySlotUI] = []

# State
var inventory_manager: InventoryManager
var player_inventory: InventoryContainer
var selected_slot_index: int = 0

# Signals
signal quick_slot_used(slot_index: int, item: InventoryItem)
signal quick_slot_selected(slot_index: int)

func _ready():
	_setup_hud()
	
	# Wait a frame before finding inventory manager
	await get_tree().process_frame
	_find_inventory_manager()
	_setup_input_actions()

func _setup_hud():
	# Set HUD position (bottom center of screen)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	position.y -= 60  # Offset from bottom
	
	# Background panel
	background_panel = Panel.new()
	background_panel.name = "Background"
	add_child(background_panel)
	
	# Style background
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	style_box.border_color = Color(0.4, 0.4, 0.4, 1.0)
	style_box.border_width_left = 2
	style_box.border_width_right = 2
	style_box.border_width_top = 2
	style_box.border_width_bottom = 2
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	background_panel.add_theme_stylebox_override("panel", style_box)
	
	# Slots container
	slots_container = HBoxContainer.new()
	slots_container.name = "SlotsContainer"
	slots_container.add_theme_constant_override("separation", slot_spacing)
	background_panel.add_child(slots_container)
	
	# Create quick slots
	_create_quick_slots()
	
	# Size background to fit slots
	var total_width = slot_count * slot_size.x + (slot_count - 1) * slot_spacing + 16  # 8px padding each side
	var total_height = slot_size.y + 16  # 8px padding top/bottom
	
	custom_minimum_size = Vector2(total_width, total_height)
	background_panel.size = custom_minimum_size
	slots_container.position = Vector2(8, 8)

func _create_quick_slots():
	quick_slots.clear()
	
	for i in slot_count:
		var slot = InventorySlotUI.new()
		slot.slot_size = slot_size
		slot.set_grid_position(Vector2i(i, 0))
		
		# Connect signals
		slot.slot_clicked.connect(_on_quick_slot_clicked.bind(i))
		slot.slot_right_clicked.connect(_on_quick_slot_right_clicked.bind(i))
		
		# Add hotkey label if enabled
		if show_hotkeys:
			_add_hotkey_label(slot, i)
		
		quick_slots.append(slot)
		slots_container.add_child(slot)
	
	# Select first slot by default
	_select_slot(0)

func _add_hotkey_label(slot: InventorySlotUI, index: int):
	var hotkey_label = Label.new()
	var hotkey_text = str(index + 1) if index < 9 else "0" if index == 9 else ""
	hotkey_label.text = hotkey_text
	hotkey_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hotkey_label.position = Vector2(2, 2)
	hotkey_label.size = Vector2(12, 12)
	hotkey_label.add_theme_font_size_override("font_size", 9)
	hotkey_label.add_theme_color_override("font_color", Color.YELLOW)
	hotkey_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	hotkey_label.add_theme_constant_override("shadow_offset_x", 1)
	hotkey_label.add_theme_constant_override("shadow_offset_y", 1)
	hotkey_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(hotkey_label)

func _setup_input_actions():
	# Ensure hotkey actions exist in input map
	for i in range(10):
		var action_name = "quick_slot_%d" % i
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
			
			# Add default key bindings
			var key_event = InputEventKey.new()
			key_event.keycode = KEY_1 + i if i < 9 else KEY_0
			InputMap.action_add_event(action_name, key_event)

func _find_inventory_manager():
	var scene_root = get_tree().current_scene
	inventory_manager = _find_inventory_manager_recursive(scene_root)
	
	if inventory_manager:
		player_inventory = inventory_manager.get_player_inventory()
		_refresh_quick_slots()

func _find_inventory_manager_recursive(node: Node) -> InventoryManager:
	if node is InventoryManager:
		return node
	
	for child in node.get_children():
		var result = _find_inventory_manager_recursive(child)
		if result:
			return result
	
	return null

# Quick slot management
func _refresh_quick_slots():
	if not player_inventory:
		return
	
	# Clear all slots first
	for slot in quick_slots:
		slot.clear_item()
	
	# Fill slots with items from player inventory
	var item_index = 0
	for item in player_inventory.items:
		if item_index >= slot_count:
			break
		
		quick_slots[item_index].set_item(item)
		item_index += 1

func _select_slot(index: int):
	if index < 0 or index >= quick_slots.size():
		return
	
	# Clear previous selection
	if selected_slot_index >= 0 and selected_slot_index < quick_slots.size():
		quick_slots[selected_slot_index].set_selected(false)
	
	# Set new selection
	selected_slot_index = index
	quick_slots[selected_slot_index].set_selected(true)
	
	quick_slot_selected.emit(selected_slot_index)

func use_selected_slot():
	if selected_slot_index >= 0 and selected_slot_index < quick_slots.size():
		var slot = quick_slots[selected_slot_index]
		if slot.has_item():
			var item = slot.get_item()
			quick_slot_used.emit(selected_slot_index, item)
			_handle_item_use(item)

func _handle_item_use(item: InventoryItem):
	match item.item_type:
		InventoryItem.ItemType.CONSUMABLE:
			_use_consumable(item)
		InventoryItem.ItemType.WEAPON:
			_equip_weapon(item)
		InventoryItem.ItemType.ARMOR:
			_equip_armor(item)
		_:
			print("Cannot use item: ", item.item_name)

func _use_consumable(item: InventoryItem):
	# TODO: Implement consumable usage
	print("Using consumable: ", item.item_name)
	
	# Remove one from stack
	if inventory_manager:
		item.remove_from_stack(1)
		if item.quantity <= 0:
			inventory_manager.remove_item_from_container(item, player_inventory.container_id)
		_refresh_quick_slots()

func _equip_weapon(item: InventoryItem):
	# TODO: Implement weapon equipping
	print("Equipping weapon: ", item.item_name)

func _equip_armor(item: InventoryItem):
	# TODO: Implement armor equipping
	print("Equipping armor: ", item.item_name)

# Input handling
func _unhandled_input(event: InputEvent):
	if not visible:
		return
	
	# Handle hotkey presses
	for i in range(10):
		var action_name = "quick_slot_%d" % i
		if Input.is_action_just_pressed(action_name):
			if i < quick_slots.size():
				if Input.is_action_pressed("ui_select"):  # Shift to select
					_select_slot(i)
				else:
					_select_slot(i)
					use_selected_slot()
			get_viewport().set_input_as_handled()
			return
	
	# Handle scroll wheel for slot selection
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed:
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_select_previous_slot()
			elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_select_next_slot()

func _select_next_slot():
	var next_index = (selected_slot_index + 1) % slot_count
	_select_slot(next_index)

func _select_previous_slot():
	var prev_index = (selected_slot_index - 1 + slot_count) % slot_count
	_select_slot(prev_index)

# Event handlers
func _on_quick_slot_clicked(slot_index: int, slot: InventorySlotUI, event: InputEvent):
	_select_slot(slot_index)
	
	var mouse_event = event as InputEventMouseButton
	if mouse_event.double_click:
		use_selected_slot()

func _on_quick_slot_right_clicked(slot_index: int, slot: InventorySlotUI, event: InputEvent):
	if slot.has_item():
		_show_quick_slot_context_menu(slot_index, slot, event.global_position)

func _show_quick_slot_context_menu(slot_index: int, slot: InventorySlotUI, position: Vector2):
	var popup = PopupMenu.new()
	
	popup.add_item("Use Item", 0)
	popup.add_separator()
	popup.add_item("Remove from Quick Slot", 1)
	popup.add_item("Item Information", 2)
	
	add_child(popup)
	popup.position = Vector2i(position)
	popup.popup()
	
	popup.id_pressed.connect(func(id: int):
		match id:
			0:  # Use Item
				_select_slot(slot_index)
				use_selected_slot()
			1:  # Remove from Quick Slot
				_remove_from_quick_slot(slot_index)
			2:  # Item Information
				_show_item_info(slot.get_item())
		popup.queue_free()
	)

func _remove_from_quick_slot(slot_index: int):
	# TODO: Implement quick slot management
	# For now, just clear the slot display
	if slot_index >= 0 and slot_index < quick_slots.size():
		quick_slots[slot_index].clear_item()

func _show_item_info(item: InventoryItem):
	# Create simple info tooltip
	var tooltip = AcceptDialog.new()
	tooltip.title = item.item_name
	tooltip.dialog_text = "Type: %s\nQuantity: %d\nValue: %.2f ISK" % [
		InventoryItem.ItemType.keys()[item.item_type],
		item.quantity,
		item.get_total_value()
	]
	
	add_child(tooltip)
	tooltip.popup_centered()
	tooltip.confirmed.connect(func(): tooltip.queue_free())

# Public interface
func set_slot_count(count: int):
	slot_count = count
	_create_quick_slots()

func set_slot_size(size: Vector2):
	slot_size = size
	for slot in quick_slots:
		slot.slot_size = size

func add_item_to_quick_slot(item: InventoryItem, slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= quick_slots.size():
		return false
	
	quick_slots[slot_index].set_item(item)
	return true

func remove_item_from_quick_slot(slot_index: int):
	if slot_index >= 0 and slot_index < quick_slots.size():
		quick_slots[slot_index].clear_item()

func get_quick_slot_item(slot_index: int) -> InventoryItem:
	if slot_index >= 0 and slot_index < quick_slots.size():
		return quick_slots[slot_index].get_item()
	return null

func get_selected_slot_index() -> int:
	return selected_slot_index

func get_selected_item() -> InventoryItem:
	return get_quick_slot_item(selected_slot_index)

# Visual updates
func set_hud_opacity(opacity: float):
	modulate.a = clamp(opacity, 0.0, 1.0)

func show_hud():
	visible = true

func hide_hud():
	visible = false

func toggle_hud():
	visible = not visible

# Animation effects
func animate_slot_use(slot_index: int):
	if slot_index >= 0 and slot_index < quick_slots.size():
		var slot = quick_slots[slot_index]
		var tween = create_tween()
		tween.tween_property(slot, "scale", Vector2(1.2, 1.2), 0.1)
		tween.tween_property(slot, "scale", Vector2(1.0, 1.0), 0.1)

func animate_item_pickup(item: InventoryItem):
	# Create a temporary item icon that flies to the HUD
	var pickup_icon = TextureRect.new()
	pickup_icon.texture = item.get_icon_texture()
	pickup_icon.size = Vector2(32, 32)
	pickup_icon.position = get_global_mouse_position()
	
	get_viewport().add_child(pickup_icon)
	
	var tween = create_tween()
	tween.parallel().tween_property(pickup_icon, "global_position", global_position + Vector2(slot_size.x * 0.5, slot_size.y * 0.5), 0.5)
	tween.parallel().tween_property(pickup_icon, "scale", Vector2(0.5, 0.5), 0.5)
	tween.parallel().tween_property(pickup_icon, "modulate:a", 0.0, 0.5)
	
	tween.tween_callback(func():
		pickup_icon.queue_free()
		_refresh_quick_slots()
	)

# Save/Load quick slot configuration
func save_quick_slot_config() -> Dictionary:
	var config = {
		"selected_slot": selected_slot_index,
		"slot_items": []
	}
	
	for i in quick_slots.size():
		var item = quick_slots[i].get_item()
		if item:
			config.slot_items.append({
				"slot_index": i,
				"item_id": item.item_id
			})
		else:
			config.slot_items.append(null)
	
	return config

func load_quick_slot_config(config: Dictionary):
	selected_slot_index = config.get("selected_slot") if config.has("selected_slot") else 0
	var slot_items = config.get("slot_items") if config.has("slot_items") else []
	
	for i in range(min(slot_items.size(), quick_slots.size())):
		var slot_data = slot_items[i]
		if slot_data and "item_id" in slot_data:
			# Find item in player inventory
			if player_inventory:
				var item = player_inventory.find_item_by_id(slot_data.item_id)
				if item:
					quick_slots[i].set_item(item)
	
	_select_slot(selected_slot_index)
