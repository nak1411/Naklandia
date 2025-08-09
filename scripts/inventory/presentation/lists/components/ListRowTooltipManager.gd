# ListRowTooltipManager.gd - Tooltip manager for list rows with debug
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
	print("ListRowTooltipManager created for row")

func setup_tooltip():
	"""Initialize the tooltip system"""
	print("Setting up tooltip...")
	var inventory_canvas_layer = _find_inventory_canvas_layer()
	if not inventory_canvas_layer:
		print("ERROR: Could not find inventory canvas layer")
		return
	
	print("Found canvas layer: ", inventory_canvas_layer.name)
	
	# Create tooltip panel
	tooltip = PanelContainer.new()
	tooltip.name = "ItemTooltip"
	tooltip.visible = false
	tooltip.z_index = 1000
	
	# Style the tooltip panel
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.1, 0.1, 0.1, 0.95)
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
	
	# Add to inventory canvas layer
	inventory_canvas_layer.add_child(tooltip)
	print("Tooltip setup complete")

func process_tooltip_timer(delta: float):
	"""Process tooltip delay timer"""
	if tooltip_timer > 0:
		tooltip_timer -= delta
		if tooltip_timer <= 0 and row.item and not is_showing_tooltip:
			print("Timer expired, showing tooltip")
			show_tooltip()

func show_tooltip():
	"""Show the tooltip with fade in animation"""
	var item = row.item
	if not item or is_showing_tooltip or not tooltip:
		print("Cannot show tooltip - item:", item, " showing:", is_showing_tooltip, " tooltip:", tooltip)
		return
	
	print("Showing tooltip for item: ", item.item_name)
	
	# Kill any existing tween first
	if tooltip_tween:
		tooltip_tween.kill()
		tooltip_tween = null
	
	# Mark as showing immediately to prevent multiple calls
	is_showing_tooltip = true
	
	# Update tooltip content
	tooltip_label.text = _get_tooltip_text(item)
	
	# Wait for tooltip to calculate its size
	await row.get_tree().process_frame
	
	# Get the inventory canvas layer for proper coordinate space
	var inventory_canvas_layer = _find_inventory_canvas_layer()
	if not inventory_canvas_layer:
		print("ERROR: Canvas layer not found during show")
		is_showing_tooltip = false
		return
	
	# Convert row's global position to canvas layer's local space
	var row_global_pos = row.global_position
	var canvas_global_pos = inventory_canvas_layer.global_position
	var row_local_to_canvas = row_global_pos - canvas_global_pos
	
	# Calculate tooltip position - centered horizontally, positioned below the row
	var tooltip_pos = row_local_to_canvas + Vector2(
		(row.size.x - tooltip.size.x) / 2,  # Center horizontally with the row
		row.size.y + 5  # Position below the row with 5px gap
	)
	
	print("Tooltip position: ", tooltip_pos)
	print("Row size: ", row.size)
	print("Tooltip size: ", tooltip.size)
	
	tooltip.position = tooltip_pos
	tooltip.visible = true
	
	# Start fully transparent and fade in
	tooltip.modulate.a = 0.0
	tooltip_tween = row.create_tween()
	tooltip_tween.tween_property(tooltip, "modulate:a", 1.0, tooltip_fade_duration)
	
	print("Tooltip should now be visible")

func hide_tooltip():
	"""Hide the tooltip with fade out animation"""
	print("Hiding tooltip")
	# Always reset the timer when hiding
	tooltip_timer = 0.0
	
	if not tooltip or not is_showing_tooltip:
		return
	
	# Kill any existing tween first
	if tooltip_tween:
		tooltip_tween.kill()
		tooltip_tween = null
	
	# Fade out and then hide
	tooltip_tween = row.create_tween()
	tooltip_tween.tween_property(tooltip, "modulate:a", 0.0, tooltip_fade_duration)
	tooltip_tween.tween_callback(func(): 
		if tooltip:
			tooltip.visible = false
		is_showing_tooltip = false
	)

func start_tooltip_timer():
	"""Start the tooltip delay timer"""
	var item = row.item
	if item and not is_showing_tooltip:
		tooltip_timer = tooltip_delay
		print("Started tooltip timer for: ", item.item_name)
	else:
		tooltip_timer = 0.0

func _get_tooltip_text(item: InventoryItem_Base) -> String:
	"""Generate tooltip text for an item"""
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

func _find_inventory_canvas_layer() -> CanvasLayer:
	"""Find the inventory canvas layer in the scene"""
	# Look for InventoryLayer in the scene
	var scene_root = row.get_tree().current_scene
	var inventory_layer = scene_root.get_node_or_null("InventoryLayer")
	if inventory_layer and inventory_layer is CanvasLayer:
		return inventory_layer
	
	# Alternative approach: traverse up from the row to find the CanvasLayer
	var current = row.get_parent()
	while current:
		if current is CanvasLayer:
			return current
		current = current.get_parent()
	
	print("Could not find canvas layer")
	return null

func cleanup():
	"""Clean up tooltip components"""
	print("Cleaning up tooltip")
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