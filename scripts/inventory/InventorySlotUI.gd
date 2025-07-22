# InventorySlotUI.gd - Individual inventory slot with drag-and-drop
class_name InventorySlotUI
extends Control

# Slot properties
@export var slot_size: Vector2 = Vector2(64, 64)
@export var border_color: Color = Color.GRAY
@export var border_width: float = 2.0
@export var highlight_color: Color = Color.YELLOW
@export var selection_color: Color = Color.CYAN

# Content
var item: InventoryItem
var grid_position: Vector2i
var container_id: String
var drag_data: Dictionary = {}

# Visual components
var background_panel: Panel
var item_icon: TextureRect
var quantity_label: Label
var rarity_border: NinePatchRect

# State
var is_highlighted: bool = false
var is_selected: bool = false
var is_occupied: bool = false

# Signals
signal slot_clicked(slot: InventorySlotUI, event: InputEvent)
signal slot_right_clicked(slot: InventorySlotUI, event: InputEvent)
signal drag_started(slot: InventorySlotUI, item: InventoryItem)
signal drag_ended(slot: InventorySlotUI, item: InventoryItem)
signal item_dropped(slot: InventorySlotUI, dropped_item: InventoryItem)

func _init():
	custom_minimum_size = slot_size
	size = slot_size

func _ready():
	_setup_visual_components()
	_setup_signals()

func _setup_visual_components():
	# Set mouse filter to pass input
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Background panel
	background_panel = Panel.new()
	background_panel.name = "Background"
	background_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background_panel)
	
	# Style the background
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	style_box.border_width_left = border_width
	style_box.border_width_right = border_width
	style_box.border_width_top = border_width
	style_box.border_width_bottom = border_width
	style_box.border_color = border_color
	style_box.corner_radius_top_left = 4
	style_box.corner_radius_top_right = 4
	style_box.corner_radius_bottom_left = 4
	style_box.corner_radius_bottom_right = 4
	background_panel.add_theme_stylebox_override("panel", style_box)
	
	# Item icon
	item_icon = TextureRect.new()
	item_icon.name = "ItemIcon"
	item_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	item_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(item_icon)
	
	# Quantity label
	quantity_label = Label.new()
	quantity_label.name = "QuantityLabel"
	quantity_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	quantity_label.position = Vector2(-20, -16)
	quantity_label.size = Vector2(18, 14)
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	quantity_label.add_theme_font_size_override("font_size", 10)
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
func set_item(new_item: InventoryItem):
	if item and item.quantity_changed.is_connected(_on_item_quantity_changed):
		item.quantity_changed.disconnect(_on_item_quantity_changed)
	
	item = new_item
	is_occupied = item != null
	
	if item:
		item.quantity_changed.connect(_on_item_quantity_changed)
	
	_update_item_display()
	
	if visible:
		queue_redraw()
	
func force_visual_refresh():
	# Force redraw
	queue_redraw()
	
	# Update visual state
	_update_visual_state()

func clear_item():
	set_item(null)

func get_item() -> InventoryItem:
	return item

func has_item() -> bool:
	return item != null

# Visual updates
func _update_item_display():
	if not item:
		if item_icon:
			item_icon.texture = null
			item_icon.visible = false
		if quantity_label:
			quantity_label.text = ""
			quantity_label.visible = false
		if rarity_border:
			rarity_border.visible = false
		tooltip_text = ""
		return
	
	# Set icon
	var icon_texture = item.get_icon_texture()
	if icon_texture:
		item_icon.texture = icon_texture
		item_icon.visible = true
	else:
		_create_fallback_icon()
		item_icon.visible = true
	
	# Always show quantity for any amount > 1, and ensure it's visible
	if item.quantity > 1:
		quantity_label.text = str(item.quantity)
		quantity_label.visible = true
	else:
		# Still show "1" for single items to be explicit
		quantity_label.text = "1"
		quantity_label.visible = true
	
	# Set rarity border
	if rarity_border:
		if item.item_rarity != InventoryItem.ItemRarity.COMMON:
			_show_rarity_border()
		else:
			rarity_border.visible = false
	
	# Set tooltip
	_update_tooltip()
	
	# Force visual update
	queue_redraw()

func _create_fallback_icon():
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
	
	# TODO: Set appropriate rarity border texture
	# For now, just use modulation

func _update_tooltip():
	if not item:
		tooltip_text = ""
		return
	
	var tooltip = "%s\n" % item.item_name
	tooltip += "Type: %s\n" % InventoryItem.ItemType.keys()[item.item_type]
	tooltip += "Quantity: %d\n" % item.quantity
	tooltip += "Volume: %.2f m³ (%.2f m³ total)\n" % [item.volume, item.get_total_volume()]
	tooltip += "Mass: %.2f kg (%.2f kg total)\n" % [item.mass, item.get_total_mass()]
	tooltip += "Value: %.2f ISK (%.2f ISK total)\n" % [item.base_value, item.get_total_value()]
	
	if not item.description.is_empty():
		tooltip += "\n%s" % item.description
	
	tooltip_text = tooltip

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
	
	if is_selected:
		style_box.border_color = selection_color
		style_box.bg_color = selection_color.darkened(0.8)
	elif is_highlighted:
		style_box.border_color = highlight_color
		style_box.bg_color = highlight_color.darkened(0.9)
	elif is_occupied:
		style_box.border_color = border_color.lightened(0.3)
		style_box.bg_color = Color(0.3, 0.3, 0.3, 0.9)
	else:
		style_box.border_color = border_color
		style_box.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	
	background_panel.add_theme_stylebox_override("panel", style_box)

# Input handling
func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			slot_clicked.emit(self, mouse_event)
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			slot_right_clicked.emit(self, mouse_event)
			get_viewport().set_input_as_handled()

# Drag and drop
func _find_drop_target_at_position(global_pos: Vector2) -> InventorySlotUI:
	# Get the inventory grid parent
	var grid = _get_inventory_grid()
	if not grid:
		return null
	
	return grid.get_slot_at_position(global_pos)

# Add this helper method
func _get_inventory_grid() -> InventoryGridUI:
	var parent = get_parent()
	while parent:
		if parent is InventoryGridUI:
			return parent
		parent = parent.get_parent()
	return null

# Add this method to handle successful drops
func _handle_successful_drop(target_slot: InventorySlotUI):
	var grid = _get_inventory_grid()
	if not grid:
		return
	
	var source_pos = get_grid_position()
	var target_pos = target_slot.get_grid_position()
	
	# Handle stacking if possible
	if target_slot.has_item() and item.can_stack_with(target_slot.get_item()):
		var target_item = target_slot.get_item()
		var remaining = target_item.add_to_stack(item.quantity)
		
		if remaining == 0:
			# Full stack merged, remove source item
			clear_item()
		else:
			# Partial merge, update source quantity
			item.quantity = remaining
			_update_item_display()
		
		target_slot._update_item_display()
	else:
		# Swap or move items
		var target_item = target_slot.get_item()
		
		# Clear both slots first
		target_slot.clear_item()
		var source_item = item
		clear_item()
		
		# Place items in new positions
		target_slot.set_item(source_item)
		if target_item:
			set_item(target_item)
	
	# Notify the grid of the change
	grid._on_items_moved_internally()

# Drop handling
func can_accept_drop(dropped_item: InventoryItem) -> bool:
	if not dropped_item:
		return false
	
	# Can always drop on empty slots
	if not has_item():
		return true
	
	# Can stack identical items
	if item and item.can_stack_with(dropped_item):
		return item.quantity + dropped_item.quantity <= item.max_stack_size
	
	# Can swap different items
	return true
	
func _get_drag_data(position: Vector2):
	if not item:
		return null
	
	# Create drag data
	var drag_data = {
		"item": item,
		"source_slot": self,
		"source_container": container_id,
		"source_position": grid_position
	}
	
	# Create visual drag preview
	var preview = Control.new()
	preview.size = size
	
	var preview_icon = TextureRect.new()
	preview_icon.texture = item_icon.texture
	preview_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_icon.modulate.a = 0.8
	preview.add_child(preview_icon)
	
	if item.quantity > 1:
		var preview_quantity = Label.new()
		preview_quantity.text = str(item.quantity)
		preview_quantity.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		preview_quantity.position = Vector2(-20, -16)
		preview_quantity.size = Vector2(18, 14)
		preview_quantity.add_theme_color_override("font_color", Color.WHITE)
		preview_quantity.add_theme_font_size_override("font_size", 10)
		preview.add_child(preview_quantity)
	
	set_drag_preview(preview)
	
	# Emit drag started signal
	drag_started.emit(self, item)
	
	return drag_data

func _can_drop_data(position: Vector2, data) -> bool:
	if not data is Dictionary:
		return false
	
	if not data.has("item") or not data.has("source_slot"):
		return false
	
	var source_slot = data.source_slot as InventorySlotUI
	if source_slot == self:
		return false  # Can't drop on itself
	
	var dropped_item = data.item as InventoryItem
	return can_accept_drop(dropped_item)

func _drop_data(position: Vector2, data):
	if not _can_drop_data(position, data):
		return
	
	var source_slot = data.source_slot as InventorySlotUI
	var dropped_item = data.item as InventoryItem
	
	# Handle the drop based on current slot state
	if not has_item():
		# Empty slot - move item here
		source_slot.clear_item()
		set_item(dropped_item)
	elif item.can_stack_with(dropped_item):
		# Stack items
		var remaining = item.add_to_stack(dropped_item.quantity)
		if remaining == 0:
			source_slot.clear_item()
		else:
			dropped_item.quantity = remaining
			source_slot._update_item_display()
		_update_item_display()
	else:
		# Swap items
		var temp_item = item
		source_slot.clear_item()
		clear_item()
		set_item(dropped_item)
		source_slot.set_item(temp_item)
	
	# Emit signals
	item_dropped.emit(self, dropped_item)
	source_slot.drag_ended.emit(source_slot, dropped_item)
	
	# Update container
	_notify_container_of_changes()

# Add method to notify container
func _notify_container_of_changes():
	var grid = _get_inventory_grid()
	if grid and grid.container:
		# Force container to update its internal state
		grid.container.compact_items()
		grid.refresh_display()

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

# Context menu support
func show_context_menu(position: Vector2):
	if not item:
		return
	
	# TODO: Implement context menu
	# This would show options like "Split Stack", "Destroy", "Info", etc.
	pass
