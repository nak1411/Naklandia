# InventoryItemActions.gd - Handles all item context menus and actions
class_name InventoryItemActions
extends RefCounted

# References
var window_parent: Window
var inventory_manager: InventoryManager
var current_container: InventoryContainer

# Context menu properties
var popup_offset: Vector2 = Vector2(20, 20)

# Signals
signal container_refreshed()

func _init(parent: Window):
	window_parent = parent

func set_inventory_manager(manager: InventoryManager):
	inventory_manager = manager

func set_current_container(container: InventoryContainer):
	current_container = container

func show_item_context_menu(item: InventoryItem, slot: InventorySlotUI, position: Vector2):
	var popup = PopupMenu.new()
	
	popup.set_meta("context_item", item)
	popup.set_meta("context_slot", slot)
	
	popup.add_item("Item Information", 0)
	
	if item.quantity > 1:
		popup.add_item("Split Stack", 1)
	
	popup.add_item("Move to...", 2)
	
	match item.item_type:
		InventoryItem.ItemType.CONSUMABLE:
			popup.add_item("Use Item", 10)
		InventoryItem.ItemType.CONTAINER:
			popup.add_item("Open Container", 11)
		InventoryItem.ItemType.BLUEPRINT:
			popup.add_item("View Blueprint", 12)
	
	popup.add_separator()
	
	popup.add_item("Stack All Items", 20)
	popup.add_item("Sort Container", 21)
	
	popup.add_separator()
	
	if item.can_be_destroyed:
		popup.add_item("Destroy Item", 3)
	
	popup.add_item("Clear Container", 22)
	
	window_parent.add_child(popup)
	
	var mouse_pos = (window_parent.get_mouse_position() + Vector2(window_parent.position)) + popup_offset
	popup.position = Vector2i(mouse_pos)
	popup.show()
	
	popup.id_pressed.connect(_on_context_menu_item_selected.bind(popup))

func show_empty_area_context_menu(position: Vector2):
	var popup = PopupMenu.new()
	
	popup.set_meta("context_item", null)
	popup.set_meta("context_slot", null)
	
	popup.add_item("Stack All Items", 20)
	popup.add_item("Sort Container", 21)
	popup.add_separator()
	popup.add_item("Clear Container", 22)
	
	window_parent.add_child(popup)
	popup.position = Vector2i(position)
	popup.show()
	
	popup.id_pressed.connect(_on_context_menu_item_selected.bind(popup))

func _on_context_menu_item_selected(id: int, popup: PopupMenu):
	var item = popup.get_meta("context_item", null) as InventoryItem
	var slot = popup.get_meta("context_slot", null) as InventorySlotUI
	
	match id:
		0:  # Item Information
			show_item_details_dialog(item)
		1:  # Split Stack
			show_split_stack_dialog(item, slot)
		2:  # Move to...
			show_move_item_dialog(item, slot)
		3:  # Destroy Item
			show_destroy_item_confirmation(item, slot)
		10: # Use Item
			use_item(item, slot)
		11: # Open Container
			open_container_item(item)
		12: # View Blueprint
			view_blueprint(item)
		20: # Stack All Items
			stack_all_items()
		21: # Sort Container
			sort_container()
		22: # Clear Container
			clear_container()
	
	container_refreshed.emit()
	popup.queue_free()

func show_item_details_dialog(item: InventoryItem):
	var dialog = AcceptDialog.new()
	dialog.title = item.item_name
	dialog.size = Vector2(400, 300)
	
	var content = RichTextLabel.new()
	content.bbcode_enabled = true
	content.text = _generate_detailed_item_info(item)
	content.fit_content = true
	
	dialog.add_child(content)
	window_parent.add_child(dialog)
	dialog.popup_centered()
	
	dialog.close_requested.connect(func(): dialog.queue_free())

func _generate_detailed_item_info(item: InventoryItem) -> String:
	var text = "[center][b][font_size=16]%s[/font_size][/b][/center]\n" % item.item_name
	text += "[center][color=%s]%s[/color][/center]\n\n" % [item.get_rarity_color().to_html(), InventoryItem.ItemRarity.keys()[item.item_rarity]]
	
	text += "[b]General Information[/b]\n"
	text += "Type: %s\n" % InventoryItem.ItemType.keys()[item.item_type]
	text += "Quantity: %d\n" % item.quantity
	text += "Max Stack Size: %d\n\n" % item.max_stack_size
	
	text += "[b]Physical Properties[/b]\n"
	text += "Volume: %.3f m³ (%.3f m³ total)\n" % [item.volume, item.get_total_volume()]
	text += "Mass: %.3f kg (%.3f kg total)\n\n" % [item.mass, item.get_total_mass()]
	
	text += "[b]Economic Information[/b]\n"
	text += "Base Value: %.2f ISK\n" % item.base_value
	text += "Total Value: %.2f ISK\n\n" % item.get_total_value()
	
	if item.is_container:
		text += "[b]Container Properties[/b]\n"
		text += "Container Volume: %.2f m³\n" % item.container_volume
		text += "Container Type: %s\n\n" % InventoryItem.ContainerType.keys()[item.container_type]
	
	text += "[b]Flags[/b]\n"
	text += "Unique: %s\n" % ("Yes" if item.is_unique else "No")
	text += "Contraband: %s\n" % ("Yes" if item.is_contraband else "No")
	text += "Can be destroyed: %s\n\n" % ("Yes" if item.can_be_destroyed else "No")
	
	if not item.description.is_empty():
		text += "[b]Description[/b]\n%s" % item.description
	
	return text

func show_split_stack_dialog(item: InventoryItem, slot: InventorySlotUI):
	var dialog = AcceptDialog.new()
	dialog.title = "Split Stack"
	dialog.size = Vector2(300, 150)
	
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	var label = Label.new()
	label.text = "Split %s (Current: %d)" % [item.item_name, item.quantity]
	vbox.add_child(label)
	
	var spinbox = SpinBox.new()
	spinbox.min_value = 1
	spinbox.max_value = item.quantity - 1
	spinbox.value = 1
	vbox.add_child(spinbox)
	
	var button_container = HBoxContainer.new()
	vbox.add_child(button_container)
	
	var split_button = Button.new()
	split_button.text = "Split"
	button_container.add_child(split_button)
	
	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	button_container.add_child(cancel_button)
	
	window_parent.add_child(dialog)
	dialog.popup_centered()
	
	split_button.pressed.connect(func():
		var split_amount = int(spinbox.value)
		if inventory_manager:
			var new_item = item.split_stack(split_amount)
			if new_item:
				inventory_manager.add_item_to_container(new_item, current_container.container_id)
		dialog.queue_free()
	)
	
	cancel_button.pressed.connect(func(): dialog.queue_free())

func show_move_item_dialog(item: InventoryItem, slot: InventorySlotUI):
	var dialog = AcceptDialog.new()
	dialog.title = "Move Item"
	dialog.size = Vector2(350, 200)
	
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	var label = Label.new()
	label.text = "Move %s to:" % item.item_name
	vbox.add_child(label)
	
	var container_list = ItemList.new()
	container_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(container_list)
	
	if inventory_manager:
		var containers = inventory_manager.get_accessible_containers()
		for container in containers:
			if container != current_container:
				container_list.add_item(container.container_name)
	
	var button_container = HBoxContainer.new()
	vbox.add_child(button_container)
	
	var move_button = Button.new()
	move_button.text = "Move"
	button_container.add_child(move_button)
	
	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	button_container.add_child(cancel_button)
	
	window_parent.add_child(dialog)
	dialog.popup_centered()
	
	move_button.pressed.connect(func():
		var selected_index = container_list.get_selected_items()
		if not selected_index.is_empty() and inventory_manager:
			var containers = inventory_manager.get_accessible_containers()
			var target_container_index = 0
			for i in range(containers.size()):
				if containers[i] != current_container:
					if target_container_index == selected_index[0]:
						inventory_manager.transfer_item(item, current_container.container_id, containers[i].container_id)
						break
					target_container_index += 1
		dialog.queue_free()
	)
	
	cancel_button.pressed.connect(func(): dialog.queue_free())

func show_destroy_item_confirmation(item: InventoryItem, slot: InventorySlotUI):
	var dialog = ConfirmationDialog.new()
	dialog.title = "Destroy Item"
	dialog.dialog_text = "Are you sure you want to destroy %s? This action cannot be undone." % item.item_name
	
	window_parent.add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func():
		if inventory_manager:
			inventory_manager.remove_item_from_container(item, current_container.container_id)
			await window_parent.get_tree().process_frame
			container_refreshed.emit()
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func(): dialog.queue_free())

func use_item(item: InventoryItem, slot: InventorySlotUI):
	print("Using item: ", item.item_name)

func open_container_item(item: InventoryItem):
	print("Opening container: ", item.item_name)

func view_blueprint(item: InventoryItem):
	print("Viewing blueprint: ", item.item_name)

func stack_all_items():
	if inventory_manager and current_container:
		inventory_manager.auto_stack_container(current_container.container_id)

func sort_container():
	if inventory_manager and current_container:
		inventory_manager.sort_container(current_container.container_id, InventoryManager.SortType.BY_NAME)

func clear_container():
	if not current_container:
		return
	
	var dialog = ConfirmationDialog.new()
	dialog.title = "Clear Container"
	dialog.dialog_text = "Are you sure you want to clear all items from %s? This action cannot be undone." % current_container.container_name
	
	window_parent.add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func():
		if current_container:
			current_container.clear()
			container_refreshed.emit()
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func(): dialog.queue_free())
