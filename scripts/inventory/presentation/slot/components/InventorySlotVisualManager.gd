# InventorySlotVisualManager.gd - Manages all visual aspects of inventory slots
class_name InventorySlotVisualManager
extends RefCounted

# References
var slot: InventorySlot
var background_panel: Panel
var item_icon: TextureRect
var quantity_label: Label
var item_name_label: Label
var quantity_bg: Panel
var label_canvas: CanvasLayer
var is_slot_positioned: bool = false

# Visual properties
var slot_size: Vector2
var border_color: Color = Color(0.2, 0.2, 0.2, 1.0)
var highlight_color: Color = Color.YELLOW
var selection_color: Color = Color.CYAN

func _init(inventory_slot: InventorySlot):
	slot = inventory_slot
	slot_size = inventory_slot.slot_size

func setup_visual_components():
	"""Set up all visual components for the slot"""
	if not slot:
		push_error("SlotVisualManager: slot reference is null!")
		return
	
	_create_background_panel()
	_create_content_container()
	_create_item_display_components()
	
	# Verify all components were created
	if not item_icon:
		push_error("SlotVisualManager: Failed to create item_icon!")
	if not quantity_label:
		push_error("SlotVisualManager: Failed to create quantity_label!")
	if not quantity_bg:
		push_error("SlotVisualManager: Failed to create quantity_bg!")
	if not item_name_label:
		push_error("SlotVisualManager: Failed to create item_name_label!")

func _create_background_panel():
	"""Create and style the background panel"""
	background_panel = Panel.new()
	background_panel.name = "Background"
	background_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(background_panel)
	
	# Style the background to match grid background
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.1, 0.1, 0.1, 0.0)
	style_box.border_width_left = 0
	style_box.border_width_right = 0
	style_box.border_width_top = 0
	style_box.border_width_bottom = 0
	background_panel.add_theme_stylebox_override("panel", style_box)
	
func _create_content_container():
	"""Create content container with separate areas for icon and name"""
	var content_container = Control.new()
	content_container.name = "ContentContainer"
	content_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(content_container)
	
	# Item icon takes the top square area (64x64)
	item_icon = TextureRect.new()
	item_icon.name = "ItemIcon"
	item_icon.position = Vector2(0, 0)
	item_icon.size = Vector2(64, 64)  # Square icon area
	item_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_container.add_child(item_icon)

func _create_item_display_components():
	"""Create quantity display components and item name label"""
	# Quantity background panel - positioned over the icon area
	quantity_bg = Panel.new()
	quantity_bg.name = "QuantityBackground"
	quantity_bg.size = Vector2(10, 10)
	quantity_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quantity_bg.visible = false

	var quantity_bg_style = StyleBoxFlat.new()
	quantity_bg_style.bg_color = Color(0.0, 0.0, 0.0, 0.8)
	quantity_bg.add_theme_stylebox_override("panel", quantity_bg_style)
	slot.add_child(quantity_bg)
	
	# Quantity label - positioned in bottom right of icon area
	quantity_label = Label.new()
	quantity_label.name = "QuantityLabel"
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quantity_label.add_theme_font_size_override("font_size", 12)
	quantity_label.add_theme_color_override("font_color", Color.WHITE)
	quantity_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	quantity_label.add_theme_constant_override("shadow_offset_x", 1)
	quantity_label.add_theme_constant_override("shadow_offset_y", 1)
	quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quantity_bg.add_child(quantity_label)
	
	# Item name label - positioned in the bottom area (64x32)
	item_name_label = Label.new()
	item_name_label.name = "ItemNameLabel"
	item_name_label.position = Vector2(2, 68)  # Start below icon area with small margin
	item_name_label.size = Vector2(60, 30)     # Use remaining slot area with margins
	item_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_name_label.add_theme_font_size_override("font_size", 12)  # Bigger font size
	item_name_label.add_theme_color_override("font_color", Color.WHITE)
	item_name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	item_name_label.add_theme_constant_override("shadow_offset_x", 1)
	item_name_label.add_theme_constant_override("shadow_offset_y", 1)
	item_name_label.visible = false

	# Enable text wrapping and clipping for the name area
	item_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item_name_label.clip_contents = true

	slot.add_child(item_name_label)

func update_item_display():
	"""Update the visual display for the current item"""
	# Lazy initialization check
	if not item_icon:
		setup_visual_components()
	
	var item = slot.get_item()
	
	if not item:
		_clear_item_display()
		return
	
	# Now we should have components
	if not item_icon:
		push_error("SlotVisualManager: item_icon still null after setup!")
		return
	
	# Update item icon
	var icon_texture = item.get_icon_texture()
	if icon_texture:
		item_icon.texture = icon_texture
	else:
		_create_fallback_icon(item)
	
	# Ensure quantity components exist before updating
	if not quantity_label or not quantity_bg:
		push_warning("SlotVisualManager: quantity components not initialized")
		return
	
	# Update quantity display with auto-scaling
	if item.quantity > 0:
		quantity_label.text = str(item.quantity)
		_auto_scale_quantity_label()
		quantity_label.visible = true
		quantity_bg.visible = true
	else:
		quantity_label.visible = false
		quantity_bg.visible = false

	# Update item name label - just like quantity label
	if item_name_label:
		if item.item_name:
			item_name_label.text = item.item_name
			item_name_label.visible = true
		else:
			item_name_label.visible = false

func _auto_scale_quantity_label():
	"""Resize background to fit quantity text at fixed font size"""
	if not quantity_label or not quantity_bg:
		return
	
	var item = slot.get_item()
	if not item:
		return
	
	var font = quantity_label.get_theme_font("font")
	if not font:
		font = ThemeDB.fallback_font
	
	var font_size = 12
	var text = str(item.quantity)
	
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var padding = 6
	var needed_width = max(10, text_size.x + padding)
	
	# Position quantity in bottom right of icon area (not full slot)
	quantity_bg.size = Vector2(needed_width, 14)
	quantity_bg.position = Vector2(
		64 - needed_width,  # Right edge of icon area
		64 - 14             # Bottom edge of icon area
	)
	
	quantity_label.size = quantity_bg.size
	quantity_label.position = Vector2.ZERO

func _clear_item_display():
	"""Clear all item-related visuals"""
	if item_icon:
		item_icon.texture = null
	if quantity_label:
		quantity_label.visible = false
	if quantity_bg:
		quantity_bg.visible = false
	if item_name_label:
		item_name_label.visible = false

func _create_fallback_icon(item: InventoryItem_Base):
	"""Create a fallback icon when no icon texture is available"""
	var image = Image.create(64, 96, false, Image.FORMAT_RGB8)
	var type_color = item.get_type_color()
	image.fill(type_color)
	
	var texture = ImageTexture.new()
	texture.set_image(image)
	item_icon.texture = texture

func update_visual_state(is_highlighted: bool, is_selected: bool, is_occupied: bool):
	"""Update visual state based on slot status"""
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
		style_box.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	else:
		style_box.border_color = border_color
		style_box.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	
	background_panel.add_theme_stylebox_override("panel", style_box)

func force_visual_refresh():
	"""Force a complete visual refresh"""
	slot.queue_redraw()
	update_item_display()

func cleanup():
	"""Clean up visual components"""
	background_panel = null
	item_icon = null
	quantity_label = null
	quantity_bg = null
	item_name_label = null