# InventoryItemActions.gd - Handles all item context menus and actions using CustomContextMenu
class_name InventoryItemActions
extends RefCounted

# References
var window_parent: Window
var inventory_manager: InventoryManager
var current_container: InventoryContainer_Base

# Context menu system
var context_menu: ContextMenu_Base
var is_context_menu_active: bool = false

# Track open dialog windows for cleanup
var open_dialog_windows: Array[Window] = []

# Signals
signal container_refreshed()

func _init(parent: Window):
	window_parent = parent
	_setup_context_menu()

func _setup_context_menu():
	"""Initialize the custom context menu system"""
	context_menu = ContextMenu_Base.new()
	context_menu.name = "InventoryContextMenu"
	
	# Connect context menu signals
	context_menu.item_selected.connect(_on_context_item_selected)
	context_menu.menu_closed.connect(_on_context_menu_closed)
	
	# Add to window parent for proper input handling
	window_parent.add_child(context_menu)

func set_inventory_manager(manager: InventoryManager):
	inventory_manager = manager

func set_current_container(container: InventoryContainer_Base):
	current_container = container

func show_item_context_menu(item: InventoryItem_Base, slot: InventorySlot, position: Vector2):
	"""Show context menu for an inventory item"""
	if is_context_menu_active:
		_close_context_menu()
	
	# Setup the context menu for this item
	context_menu.setup_item_context_menu(item)
	
	# Show at position with context data and parent window
	var context_data = {
		"item": item,
		"slot": slot,
		"container": current_container,
		"action_type": "item"
	}
	
	context_menu.show_context_menu(position, context_data, window_parent)
	is_context_menu_active = true

func show_empty_area_context_menu(position: Vector2):
	"""Show context menu for empty inventory area"""
	if is_context_menu_active:
		_close_context_menu()
	
	# Setup empty area context menu
	context_menu.setup_empty_area_context_menu()
	
	# Show at position with context data and parent window
	var context_data = {
		"container": current_container,
		"action_type": "empty_area"
	}
	
	context_menu.show_context_menu(position, context_data, window_parent)
	is_context_menu_active = true

func show_container_context_menu(container: InventoryContainer_Base, position: Vector2):
	"""Show context menu for container management"""
	if is_context_menu_active:
		_close_context_menu()
	
	# Setup container context menu
	context_menu.setup_container_context_menu(container)
	
	# Show at position with context data and parent window
	var context_data = {
		"container": container,
		"action_type": "container"
	}
	
	context_menu.show_context_menu(position, context_data, window_parent)
	is_context_menu_active = true

func _close_context_menu():
	"""Close the active context menu"""
	if context_menu and context_menu.is_menu_visible():
		context_menu.hide_menu()
	is_context_menu_active = false

func _on_context_menu_closed():
	"""Handle context menu closure"""
	is_context_menu_active = false
	
	# Return focus to inventory window
	if window_parent and is_instance_valid(window_parent):
		window_parent.grab_focus()

func _on_context_item_selected(item_id: String, _item_data: Dictionary, context_data: Dictionary):
	"""Handle context menu item selection"""
	var action_type = context_data.get("action_type", "")
	
	match action_type:
		"item":
			_handle_item_action(item_id, context_data)
		"empty_area":
			_handle_empty_area_action(item_id, context_data)
		"container":
			_handle_container_action(item_id, context_data)
	
	# Emit refresh signal for most actions
	if not item_id.begins_with("item_info") and not item_id.begins_with("container_info"):
		container_refreshed.emit()

func _handle_item_action(action_id: String, context_data: Dictionary):
	"""Handle actions on inventory items"""
	var item = context_data.get("item") as InventoryItem_Base
	var slot = context_data.get("slot") as InventorySlot
	
	if not item:
		return
	
	match action_id:
		"item_info":
			show_item_details_dialog(item)
		"split_stack":
			show_split_stack_dialog(item, slot)
		"use_item":
			use_item(item, slot)
		"equip_item":
			equip_item(item, slot)
		"open_container":
			open_container_item(item)
		"view_blueprint":
			view_blueprint(item)
		"destroy_item":
			show_destroy_item_confirmation(item, slot)
		_:
			# Handle move actions
			if action_id.begins_with("move_to_"):
				_handle_move_item_action(action_id, item)

func _handle_empty_area_action(action_id: String, _context_data: Dictionary):
	"""Handle actions on empty inventory areas"""
	match action_id:
		"stack_all":
			stack_all_items()
		"sort_container":
			sort_container()
		"clear_container":
			show_clear_container_confirmation()

func _handle_container_action(action_id: String, context_data: Dictionary):
	"""Handle container management actions"""
	var container = context_data.get("container") as InventoryContainer_Base
	
	match action_id:
		"container_info":
			show_container_details_dialog(container)
		"compact_container":
			compact_container(container)
		"sort_by_name":
			sort_container_by_type(InventoryManager.SortType.BY_NAME)
		"sort_by_type":
			sort_container_by_type(InventoryManager.SortType.BY_TYPE)
		"sort_by_value":
			sort_container_by_type(InventoryManager.SortType.BY_VALUE)
		"sort_by_volume":
			sort_container_by_type(InventoryManager.SortType.BY_VOLUME)
		"sort_by_rarity":
			sort_container_by_type(InventoryManager.SortType.BY_RARITY)
		_:
			# Handle move actions for containers
			if action_id.begins_with("move_to_"):
				_handle_move_container_items_action(action_id, container)

func _handle_move_item_action(action_id: String, item: InventoryItem_Base):
	"""Handle moving individual items between containers"""
	if not inventory_manager or not current_container:
		return
	
	var target_container_id = ""
	
	match action_id:
		"move_to_player":
			target_container_id = "player_inventory"
		"move_to_cargo":
			target_container_id = "player_cargo"
		"move_to_hangar_1":
			target_container_id = "hangar_0"
		"move_to_hangar_2":
			target_container_id = "hangar_1"
		"move_to_hangar_3":
			target_container_id = "hangar_2"
		_:
			# Parse container ID from action
			if action_id.begins_with("move_to_"):
				target_container_id = action_id.replace("move_to_", "")
	
	if not target_container_id.is_empty() and target_container_id != current_container.container_id:
		var success = inventory_manager.transfer_item(item, current_container.container_id, target_container_id)
		if not success:
			_show_transfer_failed_notification()

func _handle_move_container_items_action(action_id: String, container: InventoryContainer_Base):
	"""Handle moving all items from a container"""
	# Implementation for bulk container moves

# Dialog methods
func show_item_details_dialog(item: InventoryItem_Base):
	"""Show detailed item information dialog"""
	var dialog_window = Window.new()
	dialog_window.title = item.item_name
	dialog_window.size = Vector2i(400, 350)
	dialog_window.unresizable = true
	dialog_window.always_on_top = true
	dialog_window.set_flag(Window.FLAG_POPUP, false)
	
	# Track this dialog window
	open_dialog_windows.append(dialog_window)
	
	# Position relative to inventory window
	var inventory_center = window_parent.position + window_parent.size / 2
	dialog_window.position = Vector2i(inventory_center - dialog_window.size / 2)
	
	# Create content
	var content = RichTextLabel.new()
	content.bbcode_enabled = true
	content.text = _generate_detailed_item_info(item)
	content.fit_content = true
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("margin_left", 10)
	content.add_theme_constant_override("margin_right", 10)
	content.add_theme_constant_override("margin_top", 10)
	content.add_theme_constant_override("margin_bottom", 50)
	
	dialog_window.add_child(content)
	
	# Add to scene and show
	window_parent.get_tree().current_scene.add_child(dialog_window)
	dialog_window.popup()
	dialog_window.grab_focus()
	
	# Connect close events
	dialog_window.close_requested.connect(func():
		_safe_cleanup_dialog(dialog_window)
		if window_parent and is_instance_valid(window_parent):
			window_parent.grab_focus()
	)

func show_container_details_dialog(container: InventoryContainer_Base):
	"""Show detailed container information dialog"""
	var dialog_window = Window.new()
	dialog_window.title = container.container_name
	dialog_window.size = Vector2i(350, 250)
	dialog_window.unresizable = true
	dialog_window.always_on_top = true
	dialog_window.set_flag(Window.FLAG_POPUP, false)
	
	# Track this dialog window
	open_dialog_windows.append(dialog_window)
	
	# Position relative to inventory window
	var inventory_center = window_parent.position + window_parent.size / 2
	dialog_window.position = Vector2i(inventory_center - dialog_window.size / 2)
	
	# Create content
	var content = RichTextLabel.new()
	content.bbcode_enabled = true
	content.text = _generate_detailed_container_info(container)
	content.fit_content = true
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("margin_left", 10)
	content.add_theme_constant_override("margin_right", 10)
	content.add_theme_constant_override("margin_top", 10)
	content.add_theme_constant_override("margin_bottom", 50)
	
	dialog_window.add_child(content)
	
	# Add to scene and show
	window_parent.get_tree().current_scene.add_child(dialog_window)
	dialog_window.popup()
	dialog_window.grab_focus()
	
	# Connect close events
	dialog_window.close_requested.connect(func():
		_safe_cleanup_dialog(dialog_window)
		if window_parent and is_instance_valid(window_parent):
			window_parent.grab_focus()
	)

func show_split_stack_dialog(item: InventoryItem_Base, _slot: InventorySlot):
	"""Show split stack dialog using DialogWindow_Base"""
	# Prevent auto-stacking while dialog is open
	var original_auto_stack = inventory_manager.auto_stack
	inventory_manager.auto_stack = false
	
	# Create dialog using the base class
	var dialog_window = DialogWindow_Base.new("Split Stack", Vector2(300, 180))
	dialog_window.center_on_parent = true
	dialog_window.title_bar_active_color = Color(0.1, 0.1, 0.1, 1.0)
	dialog_window.border_active_color = Color(0.1, 0.1, 0.1, 1.0)
	
	# Track this dialog window
	open_dialog_windows.append(dialog_window)
	
	# Add to scene FIRST so it gets properly initialized
	window_parent.get_tree().current_scene.add_child(dialog_window)
	
	# Wait for dialog to be fully ready
	if not dialog_window.is_node_ready():
		await dialog_window.ready
	
	# Wait one more frame to ensure all components are initialized
	await dialog_window.get_tree().process_frame
	
	# Now add content - check if dialog_content exists
	if not dialog_window.dialog_content:
		push_error("Dialog content not initialized!")
		return
	
	# Create the split stack content
	var label = Label.new()
	label.text = "Split %s (Current: %d)" % [item.item_name, item.quantity]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog_window.add_dialog_content(label)
	
	# Create spinbox using the dialog's helper method
	var spinbox = dialog_window.create_spinbox(1, item.quantity - 1, min(1, item.quantity - 1))
	
	# Add buttons
	var split_button = await dialog_window.add_button("Split")
	var cancel_button = await dialog_window.add_button("Cancel")
	
	# Connect button events
	split_button.pressed.connect(func():
		var split_amount = int(spinbox.value)
		inventory_manager.auto_stack = original_auto_stack
		_perform_split(item, split_amount, original_auto_stack)
		dialog_window.close_dialog()
		if window_parent and is_instance_valid(window_parent):
			window_parent.grab_focus()
	)
	
	cancel_button.pressed.connect(func():
		inventory_manager.auto_stack = original_auto_stack
		dialog_window.close_dialog()
		if window_parent and is_instance_valid(window_parent):
			window_parent.grab_focus()
	)
	
	# Connect close event
	dialog_window.dialog_closed.connect(func():
		inventory_manager.auto_stack = original_auto_stack
		_safe_cleanup_dialog(dialog_window)
		if window_parent and is_instance_valid(window_parent):
			window_parent.grab_focus()
	)
	
	# Show the dialog
	dialog_window.show_dialog(window_parent)

func show_destroy_item_confirmation(item: InventoryItem_Base, _slot: InventorySlot):
	"""Show confirmation dialog for item destruction"""
	var dialog_window = Window.new()
	dialog_window.title = "Destroy Item"
	dialog_window.size = Vector2i(350, 120)
	dialog_window.unresizable = true
	dialog_window.always_on_top = true
	dialog_window.set_flag(Window.FLAG_POPUP, false)
	
	# Track this dialog window
	open_dialog_windows.append(dialog_window)
	
	# Position relative to inventory window
	var inventory_center = window_parent.position + window_parent.size / 2
	dialog_window.position = Vector2i(inventory_center - dialog_window.size / 2)
	
	# Create content container
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("margin_left", 10)
	vbox.add_theme_constant_override("margin_right", 10)
	vbox.add_theme_constant_override("margin_top", 10)
	vbox.add_theme_constant_override("margin_bottom", 10)
	
	var label = Label.new()
	label.text = "Are you sure you want to destroy %s?\nThis action cannot be undone." % item.item_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(label)
	
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_container)
	
	var confirm_button = Button.new()
	confirm_button.text = "Destroy"
	confirm_button.custom_minimum_size = Vector2(80, 30)
	button_container.add_child(confirm_button)
	
	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(80, 30)
	button_container.add_child(cancel_button)
	
	dialog_window.add_child(vbox)
	
	# Add to scene and show
	window_parent.get_tree().current_scene.add_child(dialog_window)
	dialog_window.popup()
	dialog_window.grab_focus()
	
	# Connect button events
	confirm_button.pressed.connect(func():
		if inventory_manager:
			inventory_manager.remove_item_from_container(item, current_container.container_id)
			await window_parent.get_tree().process_frame
			container_refreshed.emit()
		_safe_cleanup_dialog(dialog_window)
		if window_parent and is_instance_valid(window_parent):
			window_parent.grab_focus()
	)
	
	cancel_button.pressed.connect(func():
		_safe_cleanup_dialog(dialog_window)
		if window_parent and is_instance_valid(window_parent):
			window_parent.grab_focus()
	)
	
	dialog_window.close_requested.connect(func():
		_safe_cleanup_dialog(dialog_window)
		if window_parent and is_instance_valid(window_parent):
			window_parent.grab_focus()
	)

func show_clear_container_confirmation():
	"""Show confirmation dialog for clearing container"""
	if not current_container:
		return
	
	var dialog_window = Window.new()
	dialog_window.title = "Clear Container"
	dialog_window.size = Vector2i(350, 120)
	dialog_window.unresizable = true
	dialog_window.always_on_top = true
	dialog_window.set_flag(Window.FLAG_POPUP, false)
	
	# Track this dialog window
	open_dialog_windows.append(dialog_window)
	
	# Position relative to inventory window
	var inventory_center = window_parent.position + window_parent.size / 2
	dialog_window.position = Vector2i(inventory_center - dialog_window.size / 2)
	
	# Create content container
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("margin_left", 10)
	vbox.add_theme_constant_override("margin_right", 10)
	vbox.add_theme_constant_override("margin_top", 10)
	vbox.add_theme_constant_override("margin_bottom", 10)
	
	var label = Label.new()
	label.text = "Are you sure you want to clear all items from %s?\nThis action cannot be undone." % current_container.container_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(label)
	
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_container)
	
	var confirm_button = Button.new()
	confirm_button.text = "Clear"
	confirm_button.custom_minimum_size = Vector2(80, 30)
	button_container.add_child(confirm_button)
	
	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(80, 30)
	button_container.add_child(cancel_button)
	
	dialog_window.add_child(vbox)
	
	# Add to scene and show
	window_parent.get_tree().current_scene.add_child(dialog_window)
	dialog_window.popup()
	dialog_window.grab_focus()
	
	# Connect button events
	confirm_button.pressed.connect(func():
		if current_container:
			current_container.clear()
			container_refreshed.emit()
		_safe_cleanup_dialog(dialog_window)
		if window_parent and is_instance_valid(window_parent):
			window_parent.grab_focus()
	)
	
	cancel_button.pressed.connect(func():
		_safe_cleanup_dialog(dialog_window)
		if window_parent and is_instance_valid(window_parent):
			window_parent.grab_focus()
	)
	
	dialog_window.close_requested.connect(func():
		_safe_cleanup_dialog(dialog_window)
		if window_parent and is_instance_valid(window_parent):
			window_parent.grab_focus()
	)

# Item action implementations
func use_item(item: InventoryItem_Base, _slot: InventorySlot):
	"""Use an item (consume, activate, etc.)"""
	print("Using item: ", item.item_name)
	# TODO: Implement item usage logic

func equip_item(item: InventoryItem_Base, _slot: InventorySlot):
	"""Equip an item (weapons, armor, modules)"""
	print("Equipping item: ", item.item_name)
	# TODO: Implement equipment logic

func open_container_item(item: InventoryItem_Base):
	"""Open a container item"""
	print("Opening container: ", item.item_name)
	# TODO: Implement container opening logic

func view_blueprint(item: InventoryItem_Base):
	"""View blueprint details"""
	print("Viewing blueprint: ", item.item_name)
	# TODO: Implement blueprint viewer

# Container action implementations
func stack_all_items():
	"""Stack all compatible items in current container"""
	if inventory_manager and current_container:
		inventory_manager.auto_stack_container(current_container.container_id)

func sort_container():
	"""Sort current container by name"""
	if inventory_manager and current_container:
		inventory_manager.sort_container(current_container.container_id, InventoryManager.SortType.BY_NAME)

func sort_container_by_type(sort_type: InventoryManager.SortType):
	"""Sort current container by specified type"""
	if inventory_manager and current_container:
		inventory_manager.sort_container(current_container.container_id, sort_type)

func compact_container(container: InventoryContainer_Base):
	"""Compact a container to remove gaps"""
	if container:
		container.compact_items()

# Helper methods
func _generate_detailed_item_info(item: InventoryItem_Base) -> String:
	"""Generate detailed item information text"""
	var text = "[center][b][font_size=16]%s[/font_size][/b][/center]\n" % item.item_name
	text += "[center][color=%s]%s[/color][/center]\n\n" % [item.get_rarity_color().to_html(), InventoryItem_Base.ItemRarity.keys()[item.item_rarity]]
	
	text += "[b]General Information[/b]\n"
	text += "Type: %s\n" % InventoryItem_Base.ItemType.keys()[item.item_type]
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
		text += "Container Type: %s\n\n" % InventoryItem_Base.ContainerType.keys()[item.container_type]
	
	text += "[b]Flags[/b]\n"
	text += "Unique: %s\n" % ("Yes" if item.is_unique else "No")
	text += "Contraband: %s\n" % ("Yes" if item.is_contraband else "No")
	text += "Can be destroyed: %s\n\n" % ("Yes" if item.can_be_destroyed else "No")
	
	if not item.description.is_empty():
		text += "[b]Description[/b]\n%s" % item.description
	
	return text

func _generate_detailed_container_info(container: InventoryContainer_Base) -> String:
	"""Generate detailed container information text"""
	var info = container.get_container_info()
	
	var text = "[center][b][font_size=16]%s[/font_size][/b][/center]\n\n" % container.container_name
	
	text += "[b]Container Properties[/b]\n"
	text += "Container ID: %s\n" % container.container_id
	text += "Container Type: %s\n" % InventoryItem_Base.ContainerType.keys()[container.container_type]
	text += "Grid Size: %d × %d\n\n" % [container.grid_width, container.grid_height]
	
	text += "[b]Capacity Information[/b]\n"
	text += "Volume Used: %.2f m³\n" % info.volume_used
	text += "Volume Available: %.2f m³\n" % (info.volume_max - info.volume_used)
	text += "Volume Total: %.2f m³\n" % info.volume_max
	text += "Volume Usage: %.1f%%\n\n" % info.volume_percentage
	
	text += "[b]Content Statistics[/b]\n"
	text += "Item Types: %d\n" % info.item_count
	text += "Total Items: %d\n" % info.total_quantity
	text += "Total Mass: %.2f kg\n" % info.total_mass
	text += "Total Value: %.2f ISK\n\n" % info.total_value
	
	text += "[b]Security & Access[/b]\n"
	text += "Secure Container: %s\n" % ("Yes" if container.is_secure else "No")
	text += "Requires Docking: %s\n" % ("Yes" if container.requires_docking else "No")
	
	return text

func _perform_split(item: InventoryItem_Base, split_amount: int, original_auto_stack: bool):
	"""Perform the item stack split operation"""
	
	if not inventory_manager or not current_container or not item:
		inventory_manager.auto_stack = original_auto_stack
		return
	
	if split_amount <= 0 or split_amount >= item.quantity:
		inventory_manager.auto_stack = original_auto_stack
		return
	
	# Create the new item
	var new_item = InventoryItem_Base.new()
	new_item.item_id = item.item_id
	new_item.item_name = item.item_name
	new_item.description = item.description
	new_item.icon_path = item.icon_path
	new_item.volume = item.volume
	new_item.mass = item.mass
	new_item.quantity = split_amount
	new_item.max_stack_size = item.max_stack_size
	new_item.item_type = item.item_type
	new_item.item_rarity = item.item_rarity
	new_item.is_contraband = item.is_contraband
	new_item.base_value = item.base_value
	new_item.can_be_destroyed = item.can_be_destroyed
	new_item.is_unique = item.is_unique
	new_item.is_container = item.is_container
	new_item.container_volume = item.container_volume
	new_item.container_type = item.container_type
	
	# Check volume
	var temp_original_quantity = item.quantity
	item.quantity -= split_amount
	var can_add = current_container.has_volume_for_item(new_item)
	item.quantity = temp_original_quantity
	
	if not can_add:
		inventory_manager.auto_stack = original_auto_stack
		return
	
	# CRITICAL: Temporarily disable auto-stacking to prevent merging
	var temp_auto_stack = inventory_manager.auto_stack
	inventory_manager.auto_stack = false
	
	# Perform the split
	item.quantity -= split_amount
	current_container.items.append(new_item)
	
	# Connect signals for the new item
	if not new_item.quantity_changed.is_connected(current_container._on_item_quantity_changed):
		new_item.quantity_changed.connect(current_container._on_item_quantity_changed)
	if not new_item.item_modified.is_connected(current_container._on_item_modified):
		new_item.item_modified.connect(current_container._on_item_modified)
	
	# Emit signals with auto-stack disabled
	current_container.item_added.emit(new_item, Vector2i(-1, -1))
	item.quantity_changed.emit(item.quantity)
	
	# Restore auto-stack setting
	inventory_manager.auto_stack = temp_auto_stack

func _show_transfer_failed_notification():
	"""Show notification when item transfer fails"""

func _safe_cleanup_dialog(dialog_window: Window):
	"""Safely clean up a dialog window with proper validity checks"""
	if not dialog_window:
		return
	
	# Remove from tracking array immediately
	if dialog_window in open_dialog_windows:
		open_dialog_windows.erase(dialog_window)
	
	# Disconnect all signals first to prevent input handling on destroyed nodes
	if is_instance_valid(dialog_window):
		# Disconnect window signals
		if dialog_window.close_requested.is_connected(_safe_cleanup_dialog):
			dialog_window.close_requested.disconnect(_safe_cleanup_dialog)
		
		# Remove from scene tree first to stop input processing
		if dialog_window.get_parent():
			dialog_window.get_parent().remove_child(dialog_window)
		
		# Then queue for deletion
		if not dialog_window.is_queued_for_deletion():
			dialog_window.queue_free()

func close_all_dialogs():
	"""Close all open dialog windows - called when inventory is closed"""
	# Create a copy of the array to avoid modification during iteration
	var dialogs_to_close = open_dialog_windows.duplicate()
	open_dialog_windows.clear()
	
	for dialog_window in dialogs_to_close:
		if dialog_window and is_instance_valid(dialog_window):
			# Disconnect signals first
			if dialog_window.close_requested.is_connected(_safe_cleanup_dialog):
				dialog_window.close_requested.disconnect(_safe_cleanup_dialog)
			
			# Remove from tree first
			if dialog_window.get_parent():
				dialog_window.get_parent().remove_child(dialog_window)
			
			# Then queue for deletion
			if not dialog_window.is_queued_for_deletion():
				dialog_window.queue_free()

# Public interface for compatibility
func has_action_method(method_name: String) -> bool:
	"""Compatibility method for external calls"""
	match method_name:
		"close_all_dialogs":
			return true
		"show_item_context_menu":
			return true
		"show_empty_area_context_menu":
			return true
		_:
			return false

func is_context_menu_visible() -> bool:
	"""Check if context menu is currently visible"""
	return is_context_menu_active and context_menu and context_menu.is_menu_visible()

func get_context_menu() -> ContextMenu_Base:
	"""Get reference to the context menu for external use"""
	return context_menu

# Cleanup methods
func cleanup():
	"""Clean up all resources when the actions handler is destroyed"""
	_close_context_menu()
	close_all_dialogs()
	
	if context_menu and is_instance_valid(context_menu):
		context_menu.queue_free()
		context_menu = null
