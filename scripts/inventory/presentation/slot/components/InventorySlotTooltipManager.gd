# InventorySlotTooltipManager.gd - Manages tooltip functionality for inventory slots
class_name InventorySlotTooltipManager
extends RefCounted

# References
var slot: InventorySlot
var tooltip: PanelContainer
var tooltip_label: RichTextLabel

# State
var is_showing_tooltip: bool = false
var tooltip_timer: float = 0.0
var tooltip_delay: float = 0.2

func _init(inventory_slot: InventorySlot):
	slot = inventory_slot

func setup_tooltip():
	"""Initialize the tooltip system"""
	var inventory_window = _find_inventory_window()
	if not inventory_window:
		return
	
	# Create tooltip panel
	tooltip = PanelContainer.new()
	tooltip.name = "ItemTooltip"
	tooltip.visible = false
	tooltip.z_index = 1000
	
	# Style the tooltip panel
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.1, 0.1, 0.1, 0.75)
	style_box.border_width_left = 1
	style_box.border_width_right = 1
	style_box.border_width_top = 1
	style_box.border_width_bottom = 1
	style_box.border_color = Color(0.5, 0.5, 0.5, 1.0)
	style_box.content_margin_left = 8
	style_box.content_margin_right = 8
	style_box.content_margin_top = 6
	style_box.content_margin_bottom = 6
	tooltip.add_theme_stylebox_override("panel", style_box)
	
	# Create tooltip label
	tooltip_label = RichTextLabel.new()
	tooltip_label.bbcode_enabled = true
	tooltip_label.fit_content = true
	tooltip_label.add_theme_font_size_override("normal_font_size", 12)
	tooltip_label.custom_minimum_size = Vector2(200, 0)
	tooltip.add_child(tooltip_label)
	
	# Add to inventory window
	inventory_window.add_child(tooltip)

func process_tooltip_timer(delta: float):
	"""Process tooltip delay timer"""
	if tooltip_timer > 0:
		tooltip_timer -= delta
		if tooltip_timer <= 0 and slot.get_item() and not is_showing_tooltip:
			show_tooltip()

func show_tooltip():
	"""Show the tooltip"""
	var item = slot.get_item()
	if not item or is_showing_tooltip or not tooltip:
		return
	
	# Update tooltip content
	tooltip_label.text = _get_tooltip_text(item)
	
	# Position below the slot
	var tooltip_pos = slot.global_position + Vector2(((slot.slot_size.x / 2) + slot.slot_padding / 2) - (tooltip.size.x / 2), slot.slot_size.y + 5)
	tooltip.position = tooltip_pos
	tooltip.visible = true
	is_showing_tooltip = true

func hide_tooltip():
	"""Hide the tooltip"""
	if tooltip and tooltip.visible:
		tooltip.visible = false
	is_showing_tooltip = false
	tooltip_timer = 0.0

func start_tooltip_timer():
	"""Start the tooltip delay timer"""
	var item = slot.get_item()
	if item:
		tooltip_timer = tooltip_delay

func _get_tooltip_text(item: InventoryItem_Base) -> String:
	"""Generate tooltip text for an item"""
	if not item:
		return ""
	
	var tooltip_text = "[b]%s[/b]\n" % item.item_name
	tooltip_text += "Type: %s\n" % InventoryItem_Base.ItemType.keys()[item.item_type]
	tooltip_text += "Quantity: %d\n" % item.quantity
	tooltip_text += "Volume: %.2f m³ (%.2f m³ total)\n" % [item.volume, item.get_total_volume()]
	tooltip_text += "Mass: %.2f t (%.2f t total)\n" % [item.mass, item.get_total_mass()]
	tooltip_text += "Value: %.2f cr (%.2f cr total)" % [item.base_value, item.get_total_value()]
	
	if not item.description.is_empty():
		tooltip_text += "\n\n[i]%s[/i]" % item.description
	
	return tooltip_text

func _find_inventory_window() -> Control:
	"""Find the inventory window in the scene hierarchy"""
	var current = slot.get_parent()
	while current:
		if current.get_script() and current.get_script().get_global_name() == "InventoryWindow":
			return current
		current = current.get_parent()
	return null

func cleanup():
	"""Clean up tooltip components"""
	if tooltip and is_instance_valid(tooltip):
		tooltip.queue_free()
	tooltip = null
	tooltip_label = null