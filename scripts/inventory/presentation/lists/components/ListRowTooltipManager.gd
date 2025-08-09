# ListRowTooltipManager.gd - Exact copy of slot tooltip pattern
class_name ListRowTooltipManager
extends RefCounted

# References
var row: ListRowManager
var tooltip: PanelContainer
var tooltip_label: RichTextLabel

# Animation properties
@export var tooltip_fade_duration: float = 0.15
var tooltip_tween: Tween

# State
var is_showing_tooltip: bool = false
var tooltip_timer: float = 0.0
var tooltip_delay: float = 0.2

func _init(list_row: ListRowManager):
	row = list_row

func setup_tooltip():
	"""Initialize the tooltip system - exact copy of slot version"""
	var inventory_window = _find_inventory_window()
	if not inventory_window:
		print("ListRowTooltipManager: Could not find inventory window")
		return
	
	print("ListRowTooltipManager: Found inventory window: ", inventory_window.name)
	
	# Create tooltip panel - exact copy
	tooltip = PanelContainer.new()
	tooltip.name = "ItemTooltip"
	tooltip.visible = false
	tooltip.z_index = 1000
	
	# Style the tooltip panel - exact copy
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
	
	# Create tooltip label - exact copy
	tooltip_label = RichTextLabel.new()
	tooltip_label.bbcode_enabled = true
	tooltip_label.fit_content = true
	tooltip_label.add_theme_font_size_override("normal_font_size", 12)
	tooltip_label.custom_minimum_size = Vector2(200, 0)
	tooltip.add_child(tooltip_label)
	
	# Add to inventory window - exact copy
	inventory_window.add_child(tooltip)
	print("ListRowTooltipManager: Tooltip added to inventory window")

func process_tooltip_timer(delta: float):
	"""Process tooltip delay timer - exact copy"""
	if tooltip_timer > 0:
		tooltip_timer -= delta
		if tooltip_timer <= 0 and row.item and not is_showing_tooltip:
			show_tooltip()

func show_tooltip():
	"""Show the tooltip - exact copy of slot logic"""
	var item = row.item
	if not item or is_showing_tooltip or not tooltip:
		print("ListRowTooltipManager: Cannot show - item: ", item, " showing: ", is_showing_tooltip, " tooltip: ", tooltip)
		return
	
	print("ListRowTooltipManager: Showing tooltip for: ", item.item_name)
	
	# Kill any existing tween first - exact copy
	if tooltip_tween:
		tooltip_tween.kill()
		tooltip_tween = null
	
	# Mark as showing immediately to prevent multiple calls - exact copy
	is_showing_tooltip = true
	
	# Update tooltip content - exact copy
	tooltip_label.text = _get_tooltip_text(item)
	
	# Get the inventory window to use as reference - exact copy
	var inventory_window = _find_inventory_window()
	if not inventory_window:
		is_showing_tooltip = false
		return
	
	# Convert row's global position to inventory window's local space - SAME as slot logic
	var row_global_pos = row.global_position
	var window_global_pos = inventory_window.global_position
	var row_local_to_window = row_global_pos - window_global_pos
	
	# Calculate tooltip position below the row - adapted from slot logic
	var tooltip_pos = row_local_to_window + Vector2(
		(row.size.x - tooltip.size.x) / 2,  # Center horizontally with the row
		row.size.y + 5  # Position below with 5px gap
	)
	
	# Ensure tooltip stays within window bounds - exact copy of slot logic
	var window_rect = Rect2(Vector2.ZERO, inventory_window.size)
	var tooltip_rect = Rect2(tooltip_pos, tooltip.size)
	
	# Adjust horizontal position if tooltip goes outside window - exact copy
	if tooltip_rect.position.x < 0:
		tooltip_pos.x = 0
	elif tooltip_rect.end.x > window_rect.size.x:
		tooltip_pos.x = window_rect.size.x - tooltip.size.x
	
	# Adjust vertical position if tooltip goes outside window - exact copy
	if tooltip_rect.end.y > window_rect.size.y:
		# Position above the row instead
		tooltip_pos.y = row_local_to_window.y - tooltip.size.y - 5
	
	# Ensure tooltip doesn't go above window top - exact copy
	if tooltip_pos.y < 0:
		tooltip_pos.y = row_local_to_window.y + row.size.y + 5
	
	tooltip.position = tooltip_pos
	tooltip.visible = true
	print("ListRowTooltipManager: Tooltip positioned at: ", tooltip_pos)
	
	# Start fully transparent and fade in - exact copy
	tooltip.modulate.a = 0.0
	tooltip_tween = row.create_tween()
	tooltip_tween.tween_property(tooltip, "modulate:a", 1.0, tooltip_fade_duration)

func hide_tooltip():
	"""Hide the tooltip - exact copy"""
	# Always reset the timer when hiding
	tooltip_timer = 0.0
	
	if not tooltip or not is_showing_tooltip:
		return
	
	# Kill any existing tween first - exact copy
	if tooltip_tween:
		tooltip_tween.kill()
		tooltip_tween = null
	
	# Fade out and then hide - exact copy
	tooltip_tween = row.create_tween()
	tooltip_tween.tween_property(tooltip, "modulate:a", 0.0, tooltip_fade_duration)
	tooltip_tween.tween_callback(func(): 
		if tooltip:
			tooltip.visible = false
		is_showing_tooltip = false
	)

func start_tooltip_timer():
	"""Start the tooltip delay timer - exact copy"""
	var item = row.item
	if item and not is_showing_tooltip:
		tooltip_timer = tooltip_delay
		print("ListRowTooltipManager: Timer started for: ", item.item_name)
	else:
		tooltip_timer = 0.0

func _get_tooltip_text(item: InventoryItem_Base) -> String:
	"""Generate tooltip text - exact copy of slot version"""
	if not item:
		return ""
	
	var tooltip_text = "[b]%s[/b]\n" % item.item_name

	var type_name = ItemTypes.get_type_name(item.item_type)

	tooltip_text += "Type: %s\n" % type_name
	tooltip_text += "Quantity: %d\n" % item.quantity
	tooltip_text += "Volume: %.2f m³ (%.2f m³ total)\n" % [item.volume, item.get_total_volume()]
	tooltip_text += "Mass: %.2f t (%.2f t total)\n" % [item.mass, item.get_total_mass()]
	tooltip_text += "Value: %.2f cr (%.2f cr total)" % [item.base_value, item.get_total_value()]
	
	if not item.description.is_empty():
		tooltip_text += "\n\n[i]%s[/i]" % item.description
	
	return tooltip_text

func _find_inventory_window() -> Control:
	"""Find the inventory window - exact copy of slot version"""
	var current = row.get_parent()
	while current:
		if current.get_script() and current.get_script().get_global_name() == "InventoryWindow":
			return current
		current = current.get_parent()
	return null

func cleanup():
	"""Clean up tooltip components - exact copy"""
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