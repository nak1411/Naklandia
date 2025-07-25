# InventoryItemActions.gd - Handles all item context menus and actions
class_name InventoryItemActions
extends RefCounted

# References
var window_parent: Window
var inventory_manager: InventoryManager
var current_container: InventoryContainer

# Context menu properties
var popup_offset: Vector2i = Vector2i(20, 20)
var current_popup: PopupMenu
var popup_being_cleaned: bool = false

# Track open dialog windows for cleanup
var open_dialog_windows: Array[DialogWindow] = []

# Signals
signal container_refreshed()

func _init(parent: Window = null):
	if parent:
		window_parent = parent

func set_window_parent(parent: Window):
	window_parent = parent

func set_inventory_manager(manager: InventoryManager):
	inventory_manager = manager

func set_current_container(container: InventoryContainer):
	current_container = container

func show_item_context_menu(item: InventoryItem, slot: InventorySlotUI, position: Vector2):
	# Close existing popup if open
	_close_current_popup()
	
	var popup = PopupMenu.new()
	current_popup = popup
	
	# Store context information
	popup.set_meta("context_item", item)
	popup.set_meta("context_slot", slot)
	
	# Always add item information
	popup.add_item("Item Information", 0)
	
	# Add split stack option only if item quantity > 1 and max_stack_size > 1
	if item.quantity > 1 and item.max_stack_size > 1:
		popup.add_item("Split Stack", 1)
	
	# Add destroy option if item can be destroyed
	if item.can_be_destroyed:
		popup.add_separator()
		popup.add_item("Destroy Item", 3)
	
	# Add item type specific options
	match item.item_type:
		InventoryItem.ItemType.CONSUMABLE:
			popup.add_separator()
			popup.add_item("Use Item", 10)
		InventoryItem.ItemType.CONTAINER:
			popup.add_separator()
			popup.add_item("Open Container", 11)
		InventoryItem.ItemType.BLUEPRINT:
			popup.add_separator()
			popup.add_item("View Blueprint", 12)
	
	# Add to viewport for proper input handling
	window_parent.get_viewport().add_child(popup)
	
	# Connect signals first
	popup.id_pressed.connect(_on_context_menu_item_selected.bind(popup))
	popup.popup_hide.connect(_on_popup_hidden.bind(popup))
	
	# Create input blocker overlay
	_create_input_blocker()
	
	# Set the window's active context menu reference
	_setup_click_detection()
	
	# Position and show the popup relative to the window position
	popup.position = Vector2i(position) + window_parent.position + popup_offset
	popup.popup()

func _create_input_blocker():
	# First, check for and remove any existing input blockers
	var viewport = window_parent.get_viewport()
	var existing_blockers = []
	for child in viewport.get_children():
		if child.name == "InputBlocker":
			existing_blockers.append(child)
	
	if existing_blockers.size() > 0:
		for blocker in existing_blockers:
			viewport.remove_child(blocker)
			blocker.queue_free()
	
	var blocker = Control.new()
	blocker.name = "InputBlocker"
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_PASS
	blocker.z_index = 999  # Below popup but above everything else
	
	# Make it invisible but functional
	var color_rect = ColorRect.new()
	color_rect.color = Color.TRANSPARENT
	color_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color_rect.mouse_filter = Control.MOUSE_FILTER_PASS
	blocker.add_child(color_rect)
	
	# Connect input handling
	blocker.gui_input.connect(_on_blocker_input)
	
	# Add to viewport
	window_parent.get_viewport().add_child(blocker)
	current_popup.set_meta("input_blocker", blocker)

func _on_blocker_input(event: InputEvent):
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed:
			# Any click outside popup should close it
			if current_popup and is_instance_valid(current_popup):
				var popup_rect = Rect2(current_popup.position, current_popup.size)
				if not popup_rect.has_point(mouse_event.global_position):
					# For right-clicks, close but don't consume to allow new context menus
					if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
						_close_current_popup()
						# Don't accept_event() so it can reach other items
						return
					else:
						# For other clicks, close and consume
						_close_current_popup()
						window_parent.get_viewport().set_input_as_handled()
						return

func show_empty_area_context_menu(position: Vector2):
	# Close existing popup if open
	_close_current_popup()
	
	var popup = PopupMenu.new()
	current_popup = popup
	
	popup.set_meta("context_item", null)
	popup.set_meta("context_slot", null)
	
	popup.add_item("Stack All Items", 20)
	popup.add_item("Sort Container", 21)
	popup.add_separator()
	popup.add_item("Clear Container", 22)
	
	window_parent.add_child(popup)
	
	# Connect signals
	popup.id_pressed.connect(_on_context_menu_item_selected.bind(popup))
	popup.popup_hide.connect(_on_popup_hidden.bind(popup))
	
	# Set the window's active context menu reference
	_setup_click_detection()
	
	popup.show()
	
	# Return focus to the inventory window immediately
	window_parent.grab_focus()

func _setup_click_detection():
	# Set a flag that the window can check
	if window_parent and window_parent.has_method("_set_context_menu_active"):
		window_parent._set_context_menu_active(self)

func _cleanup_input_connections():
	if window_parent and window_parent.has_method("_clear_context_menu_active"):
		window_parent._clear_context_menu_active()

func handle_window_input(event: InputEvent) -> bool:
	"""Called by the window to check if input should close the popup"""
	if not current_popup or not is_instance_valid(current_popup):
		# No popup active, clear the reference and don't handle
		_cleanup_input_connections()
		return false
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed:
			# Check if click is outside the popup
			var popup_rect = Rect2(current_popup.position, current_popup.size)
			var click_pos = mouse_event.global_position
			
			if not popup_rect.has_point(click_pos):
				# Click is outside popup - close it
				_close_current_popup()
				
				# For right-clicks, don't consume the event so new context menus can appear
				if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
					return false  # Don't consume the event
				else:
					return true   # Consume other clicks
	
	return false

func _close_current_popup():
	if popup_being_cleaned:
		return
	
	# First, clean up ANY input blockers in the viewport
	var viewport = window_parent.get_viewport()
	var blockers_found = 0
	var all_children = viewport.get_children()
	
	for child in all_children:
		if child.name == "InputBlocker":
			if child.is_inside_tree():
				viewport.remove_child(child)
			child.queue_free()
			blockers_found += 1
	
	if current_popup and is_instance_valid(current_popup):
		popup_being_cleaned = true
		
		current_popup.hide()
		if current_popup.is_inside_tree():
			current_popup.get_parent().remove_child(current_popup)
		current_popup.queue_free()
		current_popup = null
		popup_being_cleaned = false
	
	# Verify cleanup worked
	var remaining_blockers = 0
	for child in viewport.get_children():
		if child.name == "InputBlocker":
			remaining_blockers += 1

func _on_popup_hidden(popup: PopupMenu):
	if popup_being_cleaned:
		return
	
	# Only clear current_popup if this is the popup that was hidden
	if popup == current_popup:
		current_popup = null
		
		# IMPORTANT: Also clean up input blockers when popup hides automatically
		var viewport = window_parent.get_viewport()
		var blockers_found = 0
		for child in viewport.get_children():
			if child.name == "InputBlocker":
				if child.is_inside_tree():
					viewport.remove_child(child)
				child.queue_free()
				blockers_found += 1
	
	# Clean up the popup if it's still valid and not already being cleaned
	if popup and is_instance_valid(popup) and not popup_being_cleaned:
		popup_being_cleaned = true
		popup.queue_free()
		popup_being_cleaned = false
	
	# Ensure window keeps focus
	if window_parent:
		window_parent.grab_focus()

func _on_context_menu_item_selected(id: int, popup: PopupMenu):
	var item = popup.get_meta("context_item", null) as InventoryItem
	var slot = popup.get_meta("context_slot", null) as InventorySlotUI
	
	match id:
		0:  # Item Information
			show_item_details_dialog(item)
		1:  # Split Stack
			show_split_stack_dialog(item, slot)
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
	_close_current_popup()

func show_item_details_dialog(item: InventoryItem):
	# Create a new dialog window
	var dialog_window = DialogWindow.new(item.item_name, Vector2(400, 300))
	
	# Track this dialog window
	open_dialog_windows.append(dialog_window)
	
	# Add to scene first
	window_parent.get_tree().current_scene.add_child(dialog_window)
	
	# Wait for full initialization - multiple frames to ensure CustomWindow is ready
	await dialog_window.get_tree().process_frame
	await dialog_window.get_tree().process_frame
	
	# Apply theme after everything is initialized
	dialog_window.apply_dialog_theme()
	
	# Create rich text content
	var rich_text = dialog_window.create_rich_text_area(_generate_detailed_item_info(item))
	
	# Add close button
	await dialog_window.add_button("Close", func():
		_cleanup_dialog_window(dialog_window)
		window_parent.grab_focus()
	)
	
	# Show dialog
	dialog_window.show_dialog(window_parent)
	
	# Connect close events
	dialog_window.dialog_closed.connect(func():
		_cleanup_dialog_window(dialog_window)
		window_parent.grab_focus()
	)

func show_split_stack_dialog(item: InventoryItem, slot: InventorySlotUI):
	# Check if inventory manager is available
	if not inventory_manager:
		print("Error: Inventory manager not available")
		return
	
	# Prevent auto-stacking while dialog is open
	var original_auto_stack = inventory_manager.auto_stack
	inventory_manager.auto_stack = false
	
	# Create a new dialog window
	var dialog_window = DialogWindow.new("Split Stack", Vector2(300, 180))
	
	# Track this dialog window
	open_dialog_windows.append(dialog_window)
	
	# Add to scene first
	window_parent.get_tree().current_scene.add_child(dialog_window)
	
	# Wait for full initialization - multiple frames to ensure CustomWindow is ready
	await dialog_window.get_tree().process_frame
	await dialog_window.get_tree().process_frame
	
	# Apply theme after everything is initialized
	dialog_window.apply_dialog_theme()
	
	# Add dialog text - clarify what the split does
	dialog_window.set_dialog_text("Split %s (Current: %d)\nHow many to take out of this stack?" % [item.item_name, item.quantity])
	
	# Create spinbox for quantity selection - this represents how many to TAKE OUT
	var spinbox = dialog_window.create_spinbox(1, item.quantity - 1, 1)
	
	# Add buttons
	var buttons = await dialog_window.add_confirm_cancel_buttons("Split", "Cancel")
	
	# Connect button events
	buttons.confirm.pressed.connect(func():
		if inventory_manager:
			var split_amount = int(spinbox.value)
			inventory_manager.auto_stack = original_auto_stack
			_perform_split(item, split_amount, original_auto_stack)
		_cleanup_dialog_window(dialog_window)
		window_parent.grab_focus()
	)
	
	buttons.cancel.pressed.connect(func():
		if inventory_manager:
			inventory_manager.auto_stack = original_auto_stack
		_cleanup_dialog_window(dialog_window)
		window_parent.grab_focus()
	)
	
	# Show dialog
	dialog_window.show_dialog(window_parent)
	
	# Connect dialog events - but DON'T duplicate the split action
	dialog_window.dialog_cancelled.connect(func():
		if inventory_manager:
			inventory_manager.auto_stack = original_auto_stack
	)
	
	dialog_window.dialog_closed.connect(func():
		if inventory_manager:
			inventory_manager.auto_stack = original_auto_stack
		_cleanup_dialog_window(dialog_window)
		window_parent.grab_focus()
	)

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

func _perform_split(item: InventoryItem, split_amount: int, original_auto_stack: bool):
	if not inventory_manager or not current_container or not item:
		if inventory_manager:
			inventory_manager.auto_stack = original_auto_stack
		return
	
	# Debug output
	print("DEBUG: Starting split - Original quantity: %d, Split amount: %d" % [item.quantity, split_amount])
	
	# Validate split amount - should be less than total quantity
	if split_amount <= 0 or split_amount >= item.quantity:
		if inventory_manager:
			inventory_manager.auto_stack = original_auto_stack
		print("DEBUG: Invalid split amount")
		return
	
	# Store original quantity for rollback
	var original_quantity = item.quantity
	
	# Find a free position for the new item BEFORE modifying anything
	var free_position = current_container.find_free_position()
	
	if free_position == Vector2i(-1, -1):
		# No free space - can't split
		if inventory_manager:
			inventory_manager.auto_stack = original_auto_stack
		print("DEBUG: No free space for split")
		return
	
	print("DEBUG: Found free position: %s" % free_position)
	
	# Create the new item with the split amount
	var new_item = InventoryItem.new()
	new_item.item_id = item.item_id
	new_item.item_name = item.item_name
	new_item.description = item.description
	new_item.icon_path = item.icon_path
	new_item.volume = item.volume
	new_item.mass = item.mass
	new_item.quantity = split_amount  # This is the amount being split OFF
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
	
	print("DEBUG: Created new item with quantity: %d" % new_item.quantity)
	
	# Reduce the original item's quantity by the split amount
	item.quantity -= split_amount
	print("DEBUG: Reduced original item quantity to: %d" % item.quantity)
	
	# Add the new item to container with auto_stack explicitly disabled
	var success = current_container.add_item(new_item, free_position, false)
	
	if not success:
		# Failed to add - restore original quantity
		print("DEBUG: Failed to add new item, restoring original quantity")
		item.quantity = original_quantity
		# Emit quantity changed signal to update the original slot
		item.quantity_changed.emit(item.quantity)
	else:
		print("DEBUG: Successfully added new item. Total items in container: %d" % current_container.get_item_count())
		# Success - emit signals to update UI but avoid auto-stacking
		item.quantity_changed.emit(item.quantity)
		# Don't emit container_refreshed as it might trigger unwanted behavior
	
	# Always restore auto-stack setting
	if inventory_manager:
		inventory_manager.auto_stack = original_auto_stack

func show_destroy_item_confirmation(item: InventoryItem, slot: InventorySlotUI):
	# Create a new dialog window
	var dialog_window = DialogWindow.new("Destroy Item", Vector2(350, 120))
	
	# Track this dialog window
	open_dialog_windows.append(dialog_window)
	
	# Add to scene first
	window_parent.get_tree().current_scene.add_child(dialog_window)
	
	# Wait for full initialization - multiple frames to ensure CustomWindow is ready
	await dialog_window.get_tree().process_frame
	await dialog_window.get_tree().process_frame
	
	# Apply theme after everything is initialized
	dialog_window.apply_dialog_theme()
	
	# Add confirmation text
	dialog_window.set_dialog_text("Are you sure you want to destroy %s?\nThis action cannot be undone." % item.item_name)
	
	# Add buttons
	var buttons = await dialog_window.add_confirm_cancel_buttons("Destroy", "Cancel")
	
	# Connect button events
	buttons.confirm.pressed.connect(func():
		if inventory_manager:
			inventory_manager.remove_item_from_container(item, current_container.container_id)
			await window_parent.get_tree().process_frame
			container_refreshed.emit()
		_cleanup_dialog_window(dialog_window)
		window_parent.grab_focus()
	)
	
	buttons.cancel.pressed.connect(func():
		_cleanup_dialog_window(dialog_window)
		window_parent.grab_focus()
	)
	
	# Show dialog
	dialog_window.show_dialog(window_parent)
	
	# Connect dialog events
	dialog_window.dialog_confirmed.connect(func():
		if inventory_manager:
			inventory_manager.remove_item_from_container(item, current_container.container_id)
			await window_parent.get_tree().process_frame
			container_refreshed.emit()
	)
	
	dialog_window.dialog_closed.connect(func():
		_cleanup_dialog_window(dialog_window)
		window_parent.grab_focus()
	)

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
	
	# Create a new dialog window
	var dialog_window = DialogWindow.new("Clear Container", Vector2(350, 120))
	
	# Track this dialog window
	open_dialog_windows.append(dialog_window)
	
	# Add to scene first
	window_parent.get_tree().current_scene.add_child(dialog_window)
	
	# Wait for full initialization - multiple frames to ensure CustomWindow is ready
	await dialog_window.get_tree().process_frame
	await dialog_window.get_tree().process_frame
	
	# Apply theme after everything is initialized
	dialog_window.apply_dialog_theme()
	
	# Add confirmation text
	dialog_window.set_dialog_text("Are you sure you want to clear all items from %s?\nThis action cannot be undone." % current_container.container_name)
	
	# Add buttons
	var buttons = await dialog_window.add_confirm_cancel_buttons("Clear", "Cancel")
	
	# Connect button events
	buttons.confirm.pressed.connect(func():
		if current_container:
			current_container.clear()
			container_refreshed.emit()
		_cleanup_dialog_window(dialog_window)
		window_parent.grab_focus()
	)
	
	buttons.cancel.pressed.connect(func():
		_cleanup_dialog_window(dialog_window)
		window_parent.grab_focus()
	)
	
	# Show dialog
	dialog_window.show_dialog(window_parent)
	
	# Connect dialog events
	dialog_window.dialog_confirmed.connect(func():
		if current_container:
			current_container.clear()
			container_refreshed.emit()
	)
	
	dialog_window.dialog_closed.connect(func():
		_cleanup_dialog_window(dialog_window)
		window_parent.grab_focus()
	)

# Dialog window management
func _cleanup_dialog_window(dialog_window: DialogWindow):
	"""Clean up a single dialog window and remove it from tracking"""
	open_dialog_windows.erase(dialog_window)
	if is_instance_valid(dialog_window):
		dialog_window.queue_free()

func close_all_dialogs():
	"""Close all open dialog windows - called when inventory is closed"""
	for dialog_window in open_dialog_windows.duplicate():
		if is_instance_valid(dialog_window):
			dialog_window.queue_free()
	open_dialog_windows.clear()
