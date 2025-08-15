# InventorySlotTooltipManager.gd - Fixed to prevent multiple tooltips
class_name InventorySlotTooltipManager
extends RefCounted

@export var tooltip_fade_duration: float = 0.15

# References
var slot: InventorySlot
var tooltip: PanelContainer
var tooltip_label: RichTextLabel

# Animation properties

var tooltip_tween: Tween

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
	"""Show the tooltip with fade in animation"""
	var item = slot.get_item()
	if not item or is_showing_tooltip or not tooltip:
		return

	# Kill any existing tween first
	if tooltip_tween:
		tooltip_tween.kill()
		tooltip_tween = null

	# Mark as showing immediately to prevent multiple calls
	is_showing_tooltip = true

	# Update tooltip content
	tooltip_label.text = _get_tooltip_text(item)

	# Get the inventory window to use as reference
	var inventory_window = _find_inventory_window()
	if not inventory_window:
		is_showing_tooltip = false
		return

	# Convert slot's global position to inventory window's local space
	var slot_global_pos = slot.global_position
	var window_global_pos = inventory_window.global_position
	var slot_local_to_window = slot_global_pos - window_global_pos

	# Calculate tooltip position below the slot
	var tooltip_pos = slot_local_to_window + Vector2((slot.slot_size.x - tooltip.size.x) / 2, slot.slot_size.y + 5)  # Center horizontally  # Position below with 5px gap

	# Ensure tooltip stays within window bounds
	var window_rect = Rect2(Vector2.ZERO, inventory_window.size)
	var tooltip_rect = Rect2(tooltip_pos, tooltip.size)

	# Adjust horizontal position if tooltip goes outside window
	if tooltip_rect.position.x < 0:
		tooltip_pos.x = 0
	elif tooltip_rect.end.x > window_rect.size.x:
		tooltip_pos.x = window_rect.size.x - tooltip.size.x

	# Adjust vertical position if tooltip goes outside window
	if tooltip_rect.end.y > window_rect.size.y:
		# Position above the slot instead
		tooltip_pos.y = slot_local_to_window.y - tooltip.size.y - 5

	# Ensure tooltip doesn't go above window top
	if tooltip_pos.y < 0:
		tooltip_pos.y = slot_local_to_window.y + slot.slot_size.y + 5

	tooltip.position = tooltip_pos
	tooltip.visible = true

	# Start fully transparent and fade in
	tooltip.modulate.a = 0.0
	tooltip_tween = slot.create_tween()
	tooltip_tween.tween_property(tooltip, "modulate:a", 1.0, tooltip_fade_duration)


func hide_tooltip():
	"""Hide the tooltip with fade out animation"""
	# Always reset the timer when hiding
	tooltip_timer = 0.0

	if not tooltip or not is_showing_tooltip:
		return

	# Kill any existing tween first
	if tooltip_tween:
		tooltip_tween.kill()
		tooltip_tween = null

	# Fade out and then hide
	tooltip_tween = slot.create_tween()
	tooltip_tween.tween_property(tooltip, "modulate:a", 0.0, tooltip_fade_duration)
	tooltip_tween.tween_callback(
		func():
			if tooltip:
				tooltip.visible = false
			is_showing_tooltip = false
	)


func start_tooltip_timer():
	"""Start the tooltip delay timer"""
	var item = slot.get_item()
	if item and not is_showing_tooltip:
		tooltip_timer = tooltip_delay
	else:
		tooltip_timer = 0.0


func _get_tooltip_text(item: InventoryItem_Base) -> String:
	"""Generate tooltip text for an item"""
	if not item:
		return ""

	var tooltip_text = "[b]%s[/b]\n" % item.item_name
	tooltip_text += "Type: %s\n" % ItemTypes.Type.keys()[item.item_type]
	tooltip_text += "Quantity: %d\n" % item.quantity
	tooltip_text += "Volume: %.2f m³ (%.2f m³ total)\n" % [item.volume, item.get_total_volume()]
	tooltip_text += "Mass: %.2f t (%.2f t total)\n" % [item.mass, item.get_total_mass()]
	tooltip_text += "Value: %.2f cr (%.2f cr total)" % [item.base_value, item.get_total_value()]

	if not item.description.is_empty():
		tooltip_text += "\n\n[i]%s[/i]" % item.description

	return tooltip_text


func _find_inventory_window() -> Control:
	"""Find the inventory window in the scene hierarchy"""
	var current = slot.get_parent()  # or row.get_parent() for ListRowTooltipManager
	while current:
		if current.get_script():
			var script_name = current.get_script().get_global_name()
			if script_name == "InventoryWindow" or script_name == "ContainerTearOffWindow":
				return current
		current = current.get_parent()
	return null


func cleanup():
	"""Clean up tooltip components"""
	# Clear timer and state first
	tooltip_timer = 0.0
	is_showing_tooltip = false

	# Kill any running tween
	if tooltip_tween:
		tooltip_tween.kill()
		tooltip_tween = null

	# Clean up tooltip
	if tooltip and is_instance_valid(tooltip):
		tooltip.queue_free()
	tooltip = null
	tooltip_label = null
