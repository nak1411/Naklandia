# InventorySlotUI.gd - Individual inventory slot with new drag-and-drop system
class_name InventorySlot
extends Control

# Slot properties
@export var slot_size: Vector2 = Vector2(64, 64)
@export var border_color: Color = Color(0.2, 0.2, 0.2, 1.0)
@export var border_width: float = 0.0
@export var highlight_color: Color = Color.YELLOW
@export var selection_color: Color = Color.CYAN

# Content
var item: InventoryItem_Base
var grid_position: Vector2i
var container_id: String

# Visual components
var background_panel: Panel
var item_icon: TextureRect
var quantity_label: Label
var rarity_border: NinePatchRect
var quantity_bg: Panel

# State
var is_highlighted: bool = false
var is_selected: bool = false
var is_occupied: bool = false

# Drag and drop state
var is_dragging: bool = false
var drag_start_position: Vector2
var drag_threshold: float = 5.0
var drag_preview_created: bool = false

# Signals
signal slot_clicked(slot: InventorySlot, event: InputEvent)
signal slot_right_clicked(slot: InventorySlot, event: InputEvent)
signal item_drag_started(slot: InventorySlot, item: InventoryItem_Base)
signal item_drag_ended(slot: InventorySlot, success: bool)
signal item_dropped_on_slot(source_slot: InventorySlot, target_slot: InventorySlot)

func _init():
	custom_minimum_size = slot_size
	size = slot_size

func _ready():
	_setup_visual_components()
	_setup_signals()

func _setup_visual_components():
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Background panel
	background_panel = Panel.new()
	background_panel.name = "Background"
	background_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background_panel)
	
	# Style the background
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	style_box.border_width_left = 0
	style_box.border_width_right = 0
	style_box.border_width_top = 0
	style_box.border_width_bottom = 0
	background_panel.add_theme_stylebox_override("panel", style_box)
	
	# Create a content container with margins for spacing
	var content_container = Control.new()
	content_container.name = "ContentContainer"
	# Add margins to create visual spacing (adjust these values as needed)
	content_container.set_offsets_preset(Control.PRESET_FULL_RECT)
	content_container.position = Vector2(8, 8)  # Top-left margin
	content_container.size = slot_size - Vector2(8, 8)  # Reduce size by margin amount
	content_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content_container)
	
	# Item icon
	item_icon = TextureRect.new()
	item_icon.name = "ItemIcon"
	item_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	item_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_container.add_child(item_icon)
	
	# Quantity background panel (black background square)
	quantity_bg = Panel.new()
	quantity_bg.name = "QuantityBackground"
	quantity_bg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	quantity_bg.position = Vector2(-22, -22)
	quantity_bg.size = Vector2(22, 22)
	quantity_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quantity_bg.visible = false  # Initially hidden

	# Style the quantity background
	var quantity_bg_style = StyleBoxFlat.new()
	quantity_bg_style.bg_color = Color(0.0, 0.0, 0.0, 0.8)
	quantity_bg.add_theme_stylebox_override("panel", quantity_bg_style)
	add_child(quantity_bg)
	
	# Quantity label
	quantity_label = Label.new()
	quantity_label.name = "QuantityLabel"
	quantity_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	quantity_label.position = Vector2(-28, -22)
	quantity_label.size = Vector2(24, 20)
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	quantity_label.add_theme_font_size_override("font_size", 16)
	quantity_label.add_theme_color_override("font_color", Color.WHITE)
	quantity_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	quantity_label.add_theme_constant_override("shadow_offset_x", 1)
	quantity_label.add_theme_constant_override("shadow_offset_y", 1)
	quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(quantity_label)
	
	# Rarity border (initially hidden)
	rarity_border = NinePatchRect.new()
	rarity_border.name = "RarityBorder"
	rarity_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rarity_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rarity_border.visible = false
	add_child(rarity_border)
	
	_update_visual_state()

func _setup_signals():
	mouse_filter = Control.MOUSE_FILTER_PASS
	gui_input.connect(_on_gui_input)

# Item management
func set_item(new_item: InventoryItem_Base):
	if item and item.quantity_changed.is_connected(_on_item_quantity_changed):
		item.quantity_changed.disconnect(_on_item_quantity_changed)
	
	item = new_item
	is_occupied = item != null
	
	if item:
		item.quantity_changed.connect(_on_item_quantity_changed)
	
	_update_item_display()
	
	if visible:
		queue_redraw()
		
func _show_volume_feedback(can_drop: bool):
	"""Show visual feedback for volume constraints during drag"""
	if can_drop:
		# Green tint for valid drop
		modulate = Color(0.8, 1.2, 0.8, 1.0)
	else:
		# Red tint for invalid drop (volume exceeded)
		modulate = Color(1.2, 0.8, 0.8, 1.0)

func _clear_volume_feedback():
	"""Clear volume feedback colors"""
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	
func force_visual_refresh():
	queue_redraw()
	_update_visual_state()

func clear_item():
	set_item(null)

func get_item() -> InventoryItem_Base:
	return item

func has_item() -> bool:
	return item != null

# Visual updates
func _create_fallback_icon():
	"""Create a fallback icon when no icon texture is available"""
	var image = Image.create(64, 64, false, Image.FORMAT_RGB8)
	var type_color = item.get_type_color()
	image.fill(type_color)
	
	var texture = ImageTexture.new()
	texture.set_image(image)
	item_icon.texture = texture

func _show_rarity_border():
	rarity_border.visible = true
	var rarity_color = item.get_rarity_color()
	rarity_border.modulate = rarity_color

func _update_tooltip():
	if not item:
		tooltip_text = ""
		return
	
	var tooltip = "%s\n" % item.item_name
	tooltip += "Type: %s\n" % InventoryItem_Base.ItemType.keys()[item.item_type]
	tooltip += "Quantity: %d\n" % item.quantity
	tooltip += "Volume: %.2f m³ (%.2f m³ total)\n" % [item.volume, item.get_total_volume()]
	tooltip += "Mass: %.2f kg (%.2f kg total)\n" % [item.mass, item.get_total_mass()]
	tooltip += "Value: %.2f ISK (%.2f ISK total)\n" % [item.base_value, item.get_total_value()]
	
	if not item.description.is_empty():
		tooltip += "\n%s" % item.description
	
	tooltip_text = tooltip

# Calculate tooltip position (same position where Godot would show the tooltip)
func get_tooltip_position() -> Vector2:
	# Position the popup just to the right and slightly below the slot
	var tooltip_offset = Vector2(slot_size.x + 5, 0)
	return global_position + tooltip_offset

# Visual state management
func set_highlighted(highlighted: bool):
	is_highlighted = highlighted
	_update_visual_state()

func set_selected(selected: bool):
	is_selected = selected
	_update_visual_state()

func _update_visual_state():
	if not background_panel:
		return
	
	var style_box = background_panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	
	style_box.border_width_left = 0
	style_box.border_width_right = 0
	style_box.border_width_top = 0
	style_box.border_width_bottom = 0
	
	if is_selected:
		style_box.bg_color = selection_color.darkened(0.8)
	elif is_highlighted:
		style_box.bg_color = highlight_color.darkened(0.9)
	elif is_occupied:
		style_box.border_color = border_color.lightened(0.3)
		style_box.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	else:
		style_box.border_color = border_color
		style_box.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	
	background_panel.add_theme_stylebox_override("panel", style_box)

# New drag and drop input handling
func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				if has_item():
					is_dragging = true
					drag_preview_created = false  # Reset the flag
					drag_start_position = mouse_event.global_position
				slot_clicked.emit(self, mouse_event)
			else:
				# Mouse button released
				if is_dragging:
					_handle_drag_end(mouse_event.global_position)
					is_dragging = false
					drag_preview_created = false  # Reset the flag
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			slot_right_clicked.emit(self, mouse_event)
			get_viewport().set_input_as_handled()
	
	elif event is InputEventMouseMotion and is_dragging:
		var distance = event.global_position.distance_to(drag_start_position)
		if distance > drag_threshold and has_item() and not drag_preview_created:
			_start_drag()
			
func _update_drag_volume_feedback(mouse_position: Vector2):
	"""Update volume feedback while dragging"""
	if not has_item():
		return
	
	# Clear previous feedback first
	_clear_all_volume_feedback()
	
	# Check if mouse is over a slot in the inventory grid
	var target_slot = _find_slot_at_position(mouse_position)
	
	if target_slot and target_slot != self:
		var can_accept = target_slot._can_accept_item_volume_check(item)
		target_slot._show_volume_feedback(can_accept)

func _clear_all_volume_feedback():
	"""Clear volume feedback from all slots in the grid"""
	var grid = _get_inventory_grid()
	if not grid:
		return
	
	for y in range(grid.slots.size()):
		for x in range(grid.slots[y].size()):
			var slot = grid.slots[y][x]
			if slot and slot != self:
				slot._clear_volume_feedback()

func _start_drag():
	if not has_item() or drag_preview_created:
		return  # Already created preview or no item
	
	# Set flag to prevent multiple calls
	drag_preview_created = true
	
	# Check if shift is held for partial transfer indication
	var is_partial_transfer = Input.is_key_pressed(KEY_SHIFT) and item.quantity > 1
	
	# Create drag data for container list drops
	var drag_data = {
		"source_slot": self,
		"item": item,
		"container_id": container_id,
		"partial_transfer": is_partial_transfer,
		"success_callback": _on_external_drop_result
	}
	
	# Set the drag data globally so container list can access it
	get_viewport().set_meta("current_drag_data", drag_data)
	
	# Create drag preview
	var preview = _create_drag_preview()
	
	# Create a high-priority canvas layer for the drag preview
	var drag_canvas = CanvasLayer.new()
	drag_canvas.name = "DragCanvas"
	drag_canvas.layer = 200  # Higher than inventory (50) and pause (100)
	get_tree().root.add_child(drag_canvas)
	drag_canvas.add_child(preview)
	
	# Store reference to the canvas for cleanup
	preview.set_meta("drag_canvas", drag_canvas)
	
	# Add visual indicator for partial transfer
	if is_partial_transfer:
		_add_partial_transfer_indicator(preview)
	
	# Start following mouse
	_follow_mouse(preview)
	
	# Emit drag started signal
	item_drag_started.emit(self, item)

func _add_partial_transfer_indicator(preview: Control):
	"""Add visual indicator showing this is a partial transfer"""
	var indicator = Label.new()
	indicator.text = "½"
	indicator.position = Vector2(preview.size.x - 15, -5)
	indicator.size = Vector2(12, 12)
	indicator.add_theme_font_size_override("font_size", 10)
	indicator.add_theme_color_override("font_color", Color.YELLOW)
	indicator.add_theme_color_override("font_shadow_color", Color.BLACK)
	indicator.add_theme_constant_override("shadow_offset_x", 1)
	indicator.add_theme_constant_override("shadow_offset_y", 1)
	preview.add_child(indicator)

func _create_drag_preview() -> Control:
	var preview = Control.new()
	preview.name = "DragPreview"
	
	# Make the preview smaller - adjust scale factor as needed
	var scale_factor = 0.8  # 80% of original size
	preview.size = size * scale_factor
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Copy visual elements
	var preview_bg = Panel.new()
	preview_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_bg.add_theme_stylebox_override("panel", background_panel.get_theme_stylebox("panel"))
	preview_bg.modulate.a = 0.8
	preview.add_child(preview_bg)
	
	var preview_icon = TextureRect.new()
	preview_icon.texture = item_icon.texture
	preview_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_icon.modulate.a = 0.9
	preview.add_child(preview_icon)
	
	var preview_quantity = Label.new()
	preview_quantity.text = str(item.quantity)
	preview_quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	preview_quantity.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	# Scale position relative to the smaller preview size
	preview_quantity.position = Vector2(preview.size.x - 28 * scale_factor, preview.size.y - 26 * scale_factor)
	preview_quantity.size = Vector2(24 * scale_factor, 20 * scale_factor)
	preview_quantity.add_theme_color_override("font_color", Color.WHITE)
	preview_quantity.add_theme_color_override("font_shadow_color", Color.BLACK)
	preview_quantity.add_theme_constant_override("shadow_offset_x", 1)
	preview_quantity.add_theme_constant_override("shadow_offset_y", 1)
	# Scale font size as well
	preview_quantity.add_theme_font_size_override("font_size", int(18 * scale_factor))
	preview.add_child(preview_quantity)
	
	return preview

func _follow_mouse(preview: Control):
	# Store reference and start immediate positioning
	preview.set_meta("source_slot", self)
	_update_preview_position(preview)
	
	# Create a timer to update position continuously
	var timer = Timer.new()
	timer.wait_time = 0.016  # ~60 FPS
	timer.timeout.connect(_update_preview_position.bind(preview))
	add_child(timer)
	timer.start()
	
	# Store timer reference to clean it up later
	preview.set_meta("position_timer", timer)

func _update_preview_position(preview: Control):
	if not is_instance_valid(preview) or not is_dragging:
		# Clean up the timer if dragging stopped
		var timer = preview.get_meta("position_timer", null)
		if timer and is_instance_valid(timer):
			timer.stop()
			timer.queue_free()
		return
	
	# Check if this preview belongs to this slot
	var source_slot = preview.get_meta("source_slot", null)
	if source_slot != self:
		return
	
	var mouse_pos = get_global_mouse_position()
	preview.global_position = mouse_pos - preview.size / 2

func _handle_drag_end(end_position: Vector2):
	print("=== DRAG END ===")
	_cleanup_all_drag_previews()
	
	var drop_successful = false
	
	# Find target slot
	var target_slot = _find_slot_at_position(end_position)
	
	if target_slot and target_slot != self:
		drop_successful = _attempt_drop_on_slot(target_slot)
	else:
		drop_successful = _attempt_drop_on_container_list(end_position)
	
	# Clear drag data from viewport
	if get_viewport().has_meta("current_drag_data"):
		get_viewport().remove_meta("current_drag_data")
	
	# Ensure container highlights are cleared
	var content = _find_inventory_content()
	if content:
		content._clear_all_container_highlights()
	
	# Emit drag ended signal
	item_drag_ended.emit(self, drop_successful)
	
	# Reset dragging state
	is_dragging = false
	drag_preview_created = false
	
func _attempt_drop_on_container_list(end_position: Vector2) -> bool:
	print("=== CONTAINER LIST DROP DEBUG ===")
	
	var content = _find_inventory_content()
	if not content:
		print("ERROR: No inventory content found")
		return false
	
	var container_list = content.container_list
	if not container_list:
		print("ERROR: No container list found")
		return false
	
	var container_rect = Rect2(container_list.global_position, container_list.size)
	
	if not container_rect.has_point(end_position):
		print("Drop position not in container list bounds")
		return false
	
	var local_pos = end_position - container_list.global_position
	var item_index = container_list.get_item_at_position(local_pos, true)
	
	if item_index == -1 or item_index >= content.open_containers.size():
		print("ERROR: Invalid item index: ", item_index)
		return false
	
	var target_container = content.open_containers[item_index]
	
	if target_container.container_id == container_id:
		print("Same container - skipping")
		return false
	
	var inventory_manager = _get_inventory_manager()
	if not inventory_manager:
		print("ERROR: No inventory manager")
		return false
	
	print("Target container: ", target_container.container_name)
	print("Source item: ", item.item_name, " (qty: ", item.quantity, ")")
	print("Item volume per unit: ", item.volume)
	print("Total item volume: ", item.get_total_volume())
	print("Target container current volume: ", target_container.get_current_volume())
	print("Target container max volume: ", target_container.max_volume)
	print("Target container available volume: ", target_container.get_available_volume())
	
	# Get source container
	var source_container = inventory_manager.get_container(container_id)
	if not source_container:
		print("ERROR: Source container not found")
		return false
	
	# Check if there's an existing stackable item in the target container
	var existing_item = target_container.find_stackable_item(item)
	
	if existing_item:
		print("Found existing stackable item with quantity: ", existing_item.quantity)
		
		# Since we removed stack size limits, we can add all items to the existing stack
		# But we still need to check volume constraints
		var volume_needed = item.get_total_volume()
		var available_volume = target_container.get_available_volume()
		
		if volume_needed <= available_volume:
			# Can transfer all items to existing stack
			print("Stacking all ", item.quantity, " items with existing stack")
			
			existing_item.quantity += item.quantity
			existing_item.quantity_changed.emit(existing_item.quantity)
			
			# Remove source item completely
			source_container.remove_item(item)
			clear_item()
			
			if content.has_method("refresh_display"):
				content.refresh_display()
			
			print("Full stacking SUCCESS")
			return true
		else:
			# Can only transfer some items due to volume constraints
			var max_transferable = int(available_volume / item.volume) if item.volume > 0 else item.quantity
			
			if max_transferable > 0:
				print("Partial stacking: ", max_transferable, " items")
				
				existing_item.quantity += max_transferable
				existing_item.quantity_changed.emit(existing_item.quantity)
				
				item.quantity -= max_transferable
				item.quantity_changed.emit(item.quantity)
				
				refresh_display()
				_show_transfer_feedback(max_transferable, item.quantity)
				
				if content.has_method("refresh_display"):
					content.refresh_display()
				
				print("Partial stacking SUCCESS")
				return true
			else:
				print("No volume available for stacking")
				_show_volume_error("Container is full")
				return false
	else:
		print("No existing stackable item found, creating new stack")
		
		# No existing stack, create new item as before
		var available_volume = target_container.get_available_volume()
		
		if available_volume <= 0:
			print("No volume available")
			_show_volume_error("Container is full")
			return false
		
		var max_transferable = item.quantity  # Default to all items
		
		if item.volume > 0:
			max_transferable = int(available_volume / item.volume)
			max_transferable = min(max_transferable, item.quantity)
		
		if max_transferable <= 0:
			print("Cannot fit any items")
			_show_volume_error("Container is full")
			return false
		
		print("Creating new stack with ", max_transferable, " items")
		
		# Create transfer item with the calculated quantity
		var transfer_item = InventoryItem_Base.new()
		transfer_item.item_id = item.item_id
		transfer_item.item_name = item.item_name
		transfer_item.description = item.description
		transfer_item.icon_path = item.icon_path
		transfer_item.volume = item.volume
		transfer_item.mass = item.mass
		transfer_item.quantity = max_transferable
		transfer_item.max_stack_size = 999999  # No stack limit
		transfer_item.item_type = item.item_type
		transfer_item.item_rarity = item.item_rarity
		transfer_item.is_contraband = item.is_contraband
		transfer_item.base_value = item.base_value
		transfer_item.can_be_destroyed = item.can_be_destroyed
		transfer_item.is_unique = item.is_unique
		transfer_item.is_container = item.is_container
		transfer_item.container_volume = item.container_volume
		transfer_item.container_type = item.container_type
		
		print("Transfer item volume: ", transfer_item.get_total_volume())
		print("Available volume before transfer: ", target_container.get_available_volume())
		
		# Add to target container
		if target_container.add_item(transfer_item, Vector2i(-1, -1), false):
			# Reduce source quantity
			item.quantity -= max_transferable
			
			print("New stack transfer successful. Transferred: ", max_transferable)
			print("Target container volume after: ", target_container.get_current_volume(), "/", target_container.max_volume)
			
			# Handle source item cleanup
			if item.quantity <= 0:
				source_container.remove_item(item)
				clear_item()
			else:
				refresh_display()
				_show_transfer_feedback(max_transferable, item.quantity)
			
			if content.has_method("refresh_display"):
				content.refresh_display()
			
			return true
		else:
			print("Failed to add item to target container")
			_show_volume_error("Transfer failed")
			return false
	
func _cleanup_all_drag_previews():
	"""Clean up any existing drag previews in the scene"""
	
	# Clean up any drag canvas nodes
	var root = get_tree().root
	var drag_canvases = []
	
	# Find all DragCanvas nodes
	for child in root.get_children():
		if child.name == "DragCanvas":
			drag_canvases.append(child)
	
	# Clean them up
	for canvas in drag_canvases:
		if is_instance_valid(canvas):
			canvas.queue_free()
	
	# Also clean up any loose DragPreview nodes
	var drag_previews = []
	
	# Check viewport for DragPreview
	var viewport_preview = get_viewport().get_node_or_null("DragPreview")
	if viewport_preview:
		drag_previews.append(viewport_preview)
	
	# Check root for DragPreview
	var root_preview = root.get_node_or_null("DragPreview")
	if root_preview:
		drag_previews.append(root_preview)
	
	# Clean up previews and their timers
	for preview in drag_previews:
		if is_instance_valid(preview):
			var timer = preview.get_meta("position_timer", null)
			if timer and is_instance_valid(timer):
				timer.stop()
				timer.queue_free()
			preview.queue_free()
	
	# Clean up any orphaned timers on this slot
	for child in get_children():
		if child is Timer and child.name.begins_with("@Timer"):
			child.stop()
			child.queue_free()

func _on_external_drop_result(success: bool):
	"""Called when an external drop (like container list) completes"""
	if success:
		clear_item()

func _find_inventory_content():
	"""Find the InventoryWindowContent in the scene tree"""
	var current = get_parent()
	while current:
		if current.get_script() and current.get_script().get_global_name() == "InventoryWindowContent":
			return current
		current = current.get_parent()
	return null

func _find_slot_at_position(global_pos: Vector2) -> InventorySlot:
	var grid = _get_inventory_grid()
	if not grid:
		return null
	
	# Check all slots in the grid for the one under the mouse
	for y in range(grid.slots.size()):
		for x in range(grid.slots[y].size()):
			var slot = grid.slots[y][x]
			if slot and slot != self and is_instance_valid(slot):
				var slot_rect = Rect2(slot.global_position, slot.size)
				# Add small margin for easier dropping
				slot_rect = slot_rect.grow(2)
				if slot_rect.has_point(global_pos):
					return slot
	
	return null

func _attempt_drop_on_slot(target_slot: InventorySlot) -> bool:
	if not target_slot or not has_item():
		return false
	
	var inventory_manager = _get_inventory_manager()
	if not inventory_manager:
		return false
	
	# Same container - use existing logic
	if target_slot.container_id == container_id:
		return _handle_same_container_drop(target_slot)
	
	# Different containers - check volume-based partial transfer
	var target_container = inventory_manager.get_container(target_slot.container_id)
	if not target_container:
		return false
	
	# Calculate how much can be transferred based on available volume
	var available_volume = target_container.get_available_volume()
	var item_volume_per_unit = item.volume
	
	if item_volume_per_unit <= 0:
		# If item has no volume, transfer entire stack
		if target_slot.has_item():
			return _handle_occupied_slot_drop(target_slot)
		else:
			var success = inventory_manager.transfer_item(item, container_id, target_slot.container_id)
			if success:
				clear_item()
			return success
	
	# Calculate maximum transferable quantity based on volume
	var max_transferable_by_volume = int(available_volume / item_volume_per_unit)
	
	if max_transferable_by_volume <= 0:
		_show_volume_error("Target container is full")
		return false
	
	# Check if target slot has an item for potential stacking
	if target_slot.has_item():
		var target_item = target_slot.get_item()
		
		# If items can stack, check stacking constraints
		if item.can_stack_with(target_item):
			var stack_space = target_item.max_stack_size - target_item.quantity
			var transferable_quantity = min(max_transferable_by_volume, min(item.quantity, stack_space))
			
			if transferable_quantity <= 0:
				_show_volume_error("Target stack is full")
				return false
			
			# Perform the partial stack transfer
			var success = inventory_manager.transfer_item(item, container_id, target_slot.container_id, target_slot.grid_position, transferable_quantity)
			
			if success:
				if item.quantity <= 0:
					clear_item()
				else:
					refresh_display()
					_show_transfer_feedback(transferable_quantity, item.quantity)
				
				# Refresh target container display
				var target_grid = target_slot._get_inventory_grid()
				if target_grid:
					target_grid.refresh_display()
				
				return true
			
			return false
		else:
			# Items can't stack - try to swap if both fit in each other's containers
			var source_container = inventory_manager.get_container(container_id)
			if source_container and source_container.has_volume_for_item(target_item):
				return _handle_item_swap(target_slot, target_item, inventory_manager)
			else:
				_show_volume_error("Cannot swap - insufficient volume")
				return false
	else:
		# Target slot is empty
		var transferable_quantity = min(max_transferable_by_volume, item.quantity)
		
		if transferable_quantity >= item.quantity:
			# Can transfer entire stack
			var success = inventory_manager.transfer_item(item, container_id, target_slot.container_id)
			if success:
				clear_item()
				# Refresh target container display
				var target_grid = target_slot._get_inventory_grid()
				if target_grid:
					target_grid.refresh_display()
			return success
		else:
			# Partial transfer needed
			var success = inventory_manager.transfer_item(item, container_id, target_slot.container_id, target_slot.grid_position, transferable_quantity)
			
			if success:
				refresh_display()
				_show_transfer_feedback(transferable_quantity, item.quantity)
				
				# Refresh target container display
				var target_grid = target_slot._get_inventory_grid()
				if target_grid:
					target_grid.refresh_display()
				
				return true
			
			return false

func _handle_same_container_drop(target_slot: InventorySlot) -> bool:
	"""Handle dropping on a slot within the same container"""
	if target_slot.has_item():
		return _handle_stack_or_swap(target_slot, _get_inventory_manager())
	else:
		return _handle_move_to_empty(target_slot, _get_inventory_manager())

func _handle_occupied_slot_drop(target_slot: InventorySlot) -> bool:
	"""Handle dropping on a slot that already has an item"""
	var target_item = target_slot.get_item()
	
	# Try stacking if items are compatible
	if item.can_stack_with(target_item):
		return _handle_stack_merge(target_slot, target_item)
	else:
		# Different items - try to swap
		var inventory_manager = _get_inventory_manager()
		return _handle_item_swap(target_slot, target_item, inventory_manager)

func refresh_display():
	"""Refresh the visual display of this slot"""
	_update_item_display()
	
	# Also refresh the parent grid if available
	var grid = _get_inventory_grid()
	if grid and grid.has_method("refresh_display"):
		# Use call_deferred to prevent recursion issues
		grid.call_deferred("refresh_display")

func _update_item_display():
	"""Update the visual representation of the item in this slot"""
	if not item:
		# Clear display
		if item_icon:
			item_icon.texture = null
		if quantity_label:
			quantity_label.text = ""
			quantity_label.visible = false
		if quantity_bg:
			quantity_bg.visible = false
		if rarity_border:
			rarity_border.visible = false
		is_occupied = false
		return
	
	# Update icon using the correct method
	if item_icon:
		var icon_texture = item.get_icon_texture()
		if icon_texture:
			item_icon.texture = icon_texture
		else:
			_create_fallback_icon()
	
	# Update quantity - ALWAYS show quantity, even for single items
	if quantity_label:
		quantity_label.text = str(item.quantity)
		quantity_label.visible = true
	
	# Show quantity background when item is present
	if quantity_bg:
		quantity_bg.visible = true
	
	# Update rarity border if available
	if rarity_border and item.item_rarity != InventoryItem_Base.ItemRarity.COMMON:
		var rarity_color = item.get_rarity_color()
		rarity_border.modulate = rarity_color
		rarity_border.visible = true
	elif rarity_border:
		rarity_border.visible = false
	
	is_occupied = true

# Also add this helper method for volume-based partial transfers
func _calculate_transferable_quantity(target_container: InventoryContainer_Base) -> int:
	"""Calculate how many items can be transferred based on volume"""
	if not target_container or not item:
		return 0
	
	var available_volume = target_container.get_available_volume()
	var item_volume_per_unit = item.volume
	
	if item_volume_per_unit <= 0:
		# If item has no volume, transfer entire stack
		return item.quantity
	
	var max_by_volume = int(available_volume / item_volume_per_unit)
	var result = min(item.quantity, max_by_volume)
	
	print("Final transferable quantity: ", result)
	return result
	
func _show_transfer_feedback(transferred: int, remaining: int):
	"""Show visual feedback for partial transfer"""
	var feedback_label = Label.new()
	feedback_label.text = "Moved %d\n%d left" % [transferred, remaining]
	feedback_label.add_theme_font_size_override("font_size", 10)
	feedback_label.add_theme_color_override("font_color", Color.GREEN)
	feedback_label.position = Vector2(size.x + 5, 0)
	add_child(feedback_label)
	
	# Create timer for delay
	var timer = Timer.new()
	timer.wait_time = 1.5
	timer.one_shot = true
	add_child(timer)
	
	# Store references for the callback
	var label_ref = feedback_label
	var timer_ref = timer
	
	timer.timeout.connect(func():
		if is_instance_valid(label_ref):
			var tween = create_tween()
			tween.tween_property(label_ref, "modulate:a", 0.0, 0.5)
			tween.tween_callback(func():
				if is_instance_valid(label_ref):
					label_ref.queue_free()
				if is_instance_valid(timer_ref):
					timer_ref.queue_free()
			)
		else:
			# If label is already freed, just free the timer
			if is_instance_valid(timer_ref):
				timer_ref.queue_free()
	)
	
	timer.start()

func _show_volume_error(message: String):
	"""Show error message for volume constraints above the inventory window"""
	
	# Find the inventory window content to position the error above it
	var inventory_content = _find_inventory_content()
	if not inventory_content:
		# Fallback to showing next to slot if we can't find the window
		_show_error_next_to_slot(message)
		return
	
	# Create a high-priority CanvasLayer for the error message
	var error_canvas = CanvasLayer.new()
	error_canvas.name = "ErrorCanvas"
	error_canvas.layer = 300  # Higher than inventory (50) and pause (100) and drag (200)
	get_tree().root.add_child(error_canvas)
	
	# Create error panel
	var error_panel = Panel.new()
	error_panel.name = "VolumeErrorPanel"
	
	# Style the error panel
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.8, 0.2, 0.2, 0.9)  # Red background
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color.RED
	error_panel.add_theme_stylebox_override("panel", panel_style)
	
	# Create error label
	var error_label = Label.new()
	error_label.text = message
	error_label.add_theme_font_size_override("font_size", 14)
	error_label.add_theme_color_override("font_color", Color.WHITE)
	error_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	error_label.add_theme_constant_override("shadow_offset_x", 1)
	error_label.add_theme_constant_override("shadow_offset_y", 1)
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# Calculate size needed for the text
	var text_size = error_label.get_theme_font("font").get_string_size(
		message,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14
	)
	
	# Set panel and label sizes with padding
	var padding = Vector2(20, 10)
	var panel_size = text_size + padding * 2
	error_panel.size = panel_size
	error_label.size = panel_size
	
	error_panel.add_child(error_label)
	error_canvas.add_child(error_panel)
	
	# Position above the inventory window
	var inventory_rect = Rect2(inventory_content.global_position, inventory_content.size)
	var error_pos = Vector2(
		inventory_rect.position.x + (inventory_rect.size.x - panel_size.x) / 2,  # Center horizontally
		inventory_rect.position.y - panel_size.y - 10  # Position above with 10px gap
	)
	
	error_panel.position = error_pos  # Use position instead of global_position for CanvasLayer
	
	# Animate in
	error_panel.modulate.a = 0.0
	var fade_in_tween = create_tween()
	fade_in_tween.tween_property(error_panel, "modulate:a", 1.0, 0.2)
	
	# Create timer for delay
	var timer = Timer.new()
	timer.wait_time = 2.0  # Show for 2 seconds
	timer.one_shot = true
	error_canvas.add_child(timer)
	
	# Store references for the callback
	var canvas_ref = error_canvas
	var panel_ref = error_panel
	var timer_ref = timer
	
	timer.timeout.connect(func():
		if is_instance_valid(panel_ref):
			var fade_out_tween = create_tween()
			fade_out_tween.tween_property(panel_ref, "modulate:a", 0.0, 0.5)
			fade_out_tween.tween_callback(func():
				if is_instance_valid(canvas_ref):
					canvas_ref.queue_free()  # This will free the entire canvas and its children
				elif is_instance_valid(timer_ref):
					timer_ref.queue_free()
			)
		else:
			# If panel is already freed, just free the canvas
			if is_instance_valid(canvas_ref):
				canvas_ref.queue_free()
			elif is_instance_valid(timer_ref):
				timer_ref.queue_free()
	)
	
	timer.start()
	
func _show_error_next_to_slot(message: String):
	"""Fallback method to show error next to slot if inventory window not found"""
	var error_label = Label.new()
	error_label.text = message
	error_label.add_theme_font_size_override("font_size", 10)
	error_label.add_theme_color_override("font_color", Color.RED)
	error_label.position = Vector2(size.x + 5, 0)
	add_child(error_label)
	
	# Create timer for delay
	var timer = Timer.new()
	timer.wait_time = 1.5
	timer.one_shot = true
	add_child(timer)
	
	# Store references for the callback
	var label_ref = error_label
	var timer_ref = timer
	
	timer.timeout.connect(func():
		if is_instance_valid(label_ref):
			var tween = create_tween()
			tween.tween_property(label_ref, "modulate:a", 0.0, 0.5)
			tween.tween_callback(func():
				if is_instance_valid(label_ref):
					label_ref.queue_free()
				if is_instance_valid(timer_ref):
					timer_ref.queue_free()
			)
		else:
			# If label is already freed, just free the timer
			if is_instance_valid(timer_ref):
				timer_ref.queue_free()
	)
	
	timer.start()

# Update _can_accept_item_volume_check method in InventorySlot.gd
func _can_accept_item_volume_check(incoming_item: InventoryItem_Base) -> bool:
	"""Check if this slot can accept an item based on volume constraints"""
	var inventory_manager = _get_inventory_manager()
	if not inventory_manager:
		return false
	
	var target_container = inventory_manager.get_container(container_id)
	if not target_container:
		return false
	
	# Get the source container of the incoming item
	var drag_data = get_viewport().get_meta("current_drag_data", null)
	var source_container_id = ""
	if drag_data:
		source_container_id = drag_data.get("container_id", "")
	
	# If this is a same-container operation, volume constraints don't apply
	# since we're just moving items around, not adding new volume
	if container_id == source_container_id:
		# If slot is empty, we can always accept
		if not has_item():
			return true
		
		# If slot has same item type, we can merge
		if item.item_id == incoming_item.item_id:
			return true
		
		# Different item types - we can swap within same container
		return true
	
	# Different containers - check volume constraints
	# If slot is empty, check if container has volume
	if not has_item():
		return target_container.get_available_volume() >= incoming_item.volume
	
	# If slot has same item type, check if we can merge
	if item.item_id == incoming_item.item_id:
		var total_quantity = item.quantity + incoming_item.quantity
		var required_volume = total_quantity * item.volume
		var current_volume = target_container.get_current_volume()
		var container_volume_without_this_item = current_volume - (item.quantity * item.volume)
		
		return (container_volume_without_this_item + required_volume) <= target_container.max_volume
	
	# Different item types - would need to swap, check if source container can accept current item
	if source_container_id.is_empty():
		return false
	
	var source_container = inventory_manager.get_container(source_container_id)
	if not source_container:
		return false
	
	return source_container.get_available_volume() >= item.volume
		
func _handle_stack_or_swap(target_slot: InventorySlot, inventory_manager: InventoryManager) -> bool:
	"""Handle stacking or swapping with target slot that has an item"""
	var target_item = target_slot.get_item()
	
	# Try stacking if items are compatible
	if item.can_stack_with(target_item):
		return _handle_stack_merge(target_slot, target_item)
	else:
		# Swap items if they can't stack
		return _handle_item_swap(target_slot, target_item, inventory_manager)

func _show_split_stack_dialog():
	"""Show split stack dialog using the existing item actions system"""
	var item_actions = _find_item_actions()
	if item_actions and item_actions.has_method("show_split_stack_dialog"):
		item_actions.show_split_stack_dialog(item, self)

func _find_item_actions():
	"""Find the InventoryItemActions instance in the scene"""
	var current = get_parent()
	while current:
		if current.get_script() and current.get_script().get_global_name() == "InventoryWindowUI":
			return current.item_actions
		current = current.get_parent()
	return null

func _handle_stack_merge(target_slot: InventorySlot, target_item: InventoryItem_Base) -> bool:
	
	var space_available = target_item.max_stack_size - target_item.quantity
	var amount_to_transfer = min(item.quantity, space_available)
	
	if amount_to_transfer <= 0:
		return false
	
	# Direct stacking without using transfer system for same container
	if container_id == target_slot.container_id:
		# Update quantities directly
		target_item.quantity += amount_to_transfer
		item.quantity -= amount_to_transfer
		
		
		# Update displays
		target_slot._update_item_display()
		
		if item.quantity <= 0:
			# Source item fully consumed
			var source_container = _get_inventory_manager().get_container(container_id)
			if source_container:
				source_container.remove_item(item)
			clear_item()
		else:
			_update_item_display()
		
		return true
	else:
		# Different container stacking - use transfer system
		var inventory_manager = _get_inventory_manager()
		if not inventory_manager:
			return false
		
		# Use the inventory manager's transfer system for different containers
		var success = inventory_manager.transfer_item(item, container_id, target_slot.container_id, target_slot.grid_position, amount_to_transfer)
		
		if success:
			# Update displays - the transfer system handles the logic
			if item.quantity <= 0:
				# Source item fully consumed
				clear_item()
			else:
				_update_item_display()
			
			# Update target display
			target_slot._update_item_display()
			
			return true
		
		return false

func _handle_item_swap(target_slot: InventorySlot, target_item: InventoryItem_Base, inventory_manager: InventoryManager) -> bool:
	var source_container = inventory_manager.get_container(container_id)
	var target_container = inventory_manager.get_container(target_slot.container_id)
	
	# Store items and positions temporarily
	var temp_source_item = item
	var temp_target_item = target_item
	var source_pos = grid_position
	var target_pos = target_slot.grid_position
	
	# For same container swaps, use move_item which is more reliable
	if source_container == target_container:
		# Clear the grid positions manually first
		source_container.clear_grid_area(source_pos)
		source_container.clear_grid_area(target_pos)
		
		# Place items at swapped positions
		source_container.occupy_grid_area(target_pos, temp_source_item)
		source_container.occupy_grid_area(source_pos, temp_target_item)
		
		# Update visual slots immediately
		clear_item()
		target_slot.clear_item()
		target_slot.set_item(temp_source_item)
		set_item(temp_target_item)
		
		# Emit move signals instead of add/remove to avoid refresh_display
		source_container.item_moved.emit(temp_source_item, source_pos, target_pos)
		source_container.item_moved.emit(temp_target_item, target_pos, source_pos)
		
		return true
	else:
		# Different containers - use the existing logic but without signals
		var source_success = source_container.remove_item(temp_source_item)
		var target_success = target_container.remove_item(temp_target_item)
		
		if not source_success or not target_success:
			return false
		
		# Clear visual slots
		clear_item()
		target_slot.clear_item()
		
		# Add to new containers at specific positions
		target_container.occupy_grid_area(target_pos, temp_source_item)
		source_container.occupy_grid_area(source_pos, temp_target_item)
		target_container.items.append(temp_source_item)
		source_container.items.append(temp_target_item)
		
		# Reconnect signals
		temp_source_item.quantity_changed.connect(target_container._on_item_quantity_changed)
		temp_source_item.item_modified.connect(target_container._on_item_modified)
		temp_target_item.quantity_changed.connect(source_container._on_item_quantity_changed)
		temp_target_item.item_modified.connect(source_container._on_item_modified)
		
		# Update visual slots
		target_slot.set_item(temp_source_item)
		set_item(temp_target_item)
		
		# Only emit item_added signals for cross-container moves
		target_container.item_added.emit(temp_source_item, target_pos)
		source_container.item_added.emit(temp_target_item, source_pos)
		
		return true

func _handle_move_to_empty(target_slot: InventorySlot, inventory_manager: InventoryManager) -> bool:
	var source_container = inventory_manager.get_container(container_id)
	var target_container = inventory_manager.get_container(target_slot.container_id)
	
	if not source_container or not target_container:
		return false
	
	# Store the item reference before removing it
	var temp_item = item
	
	# For same container moves, just update the visual position
	if source_container == target_container:
		# No volume check needed for same container - just move the item visually
		clear_item()
		target_slot.set_item(temp_item)
		# Emit move signal for any listeners
		source_container.item_moved.emit(temp_item, grid_position, target_slot.grid_position)
		return true
	
	# For different containers, check volume constraints
	if not target_container.has_volume_for_item(item):
		return false
	
	# Remove from source and add to target
	var source_success = source_container.remove_item(temp_item)
	if not source_success:
		return false
	
	# Clear the source slot visually
	clear_item()
	
	# Add to target container - let it handle volume validation
	var target_success = target_container.add_item(temp_item, target_slot.grid_position, false)
	if not target_success:
		# Restore to source if target add failed
		source_container.add_item(temp_item, grid_position, false)
		set_item(temp_item)
		return false
	
	# Set the target slot visually
	target_slot.set_item(temp_item)
	
	return true

# Helper methods
func _get_inventory_grid() -> InventoryGrid:
	var parent = get_parent()
	while parent:
		if parent is InventoryGrid:
			return parent
		parent = parent.get_parent()
	return null

func _get_inventory_manager() -> InventoryManager:
	var scene_root = get_tree().current_scene
	return _find_inventory_manager_recursive(scene_root)

func _find_inventory_manager_recursive(node: Node) -> InventoryManager:
	if node is InventoryManager:
		return node
	
	for child in node.get_children():
		var result = _find_inventory_manager_recursive(child)
		if result:
			return result
	
	return null

# Signal handlers
func _on_item_quantity_changed(new_quantity: int):
	_update_item_display()
	
	if new_quantity <= 0:
		clear_item()

# Public interface
func set_grid_position(pos: Vector2i):
	grid_position = pos

func get_grid_position() -> Vector2i:
	return grid_position

func set_container_id(id: String):
	container_id = id

func get_container_id() -> String:
	return container_id
