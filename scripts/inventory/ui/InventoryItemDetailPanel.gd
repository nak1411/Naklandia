# InventoryItemDetailPanel.gd - Detail panel for selected items (Eve Online style)
class_name InventoryItemDetailPanel
extends Control

var current_item: InventoryItem_Base

var main_container: VBoxContainer
var item_header: Control
var item_icon: TextureRect
var item_title: Label
var item_subtitle: Label
var properties_container: VBoxContainer

func _ready():
	_setup_ui()

func _setup_ui():
	main_container = VBoxContainer.new()
	main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_container.add_theme_constant_override("separation", 4)
	add_child(main_container)
	
	_create_header()
	_create_properties_section()

func _create_header():
	item_header = Control.new()
	item_header.custom_minimum_size.y = 80
	main_container.add_child(item_header)
	
	# Icon
	item_icon = TextureRect.new()
	item_icon.custom_minimum_size = Vector2(64, 64)
	item_icon.position = Vector2(8, 8)
	item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_header.add_child(item_icon)
	
	# Title
	item_title = Label.new()
	item_title.position = Vector2(80, 8)
	item_title.size = Vector2(200, 24)
	item_title.add_theme_font_size_override("font_size", 16)
	item_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item_header.add_child(item_title)
	
	# Subtitle
	item_subtitle = Label.new()
	item_subtitle.position = Vector2(80, 32)
	item_subtitle.size = Vector2(200, 20)
	item_subtitle.add_theme_font_size_override("font_size", 12)
	item_subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	item_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item_header.add_child(item_subtitle)

func _create_properties_section():
	# Add separator
	var separator = HSeparator.new()
	main_container.add_child(separator)
	
	# Properties container
	properties_container = VBoxContainer.new()
	main_container.add_child(properties_container)

func display_item(item: InventoryItem_Base):
	current_item = item
	
	if not item:
		_clear_display()
		return
	
	# Update header
	item_icon.texture = item.icon
	item_title.text = item.item_name
	item_title.add_theme_color_override("font_color", item.get_rarity_color())
	item_subtitle.text = str(item.item_type).capitalize() + " • " + str(item.item_rarity).capitalize()
	
	# Update properties
	_update_properties()

func _update_properties():
	# Clear existing properties
	for child in properties_container.get_children():
		child.queue_free()
	
	if not current_item:
		return
	
	# Add item properties
	_add_property("Quantity", str(current_item.quantity))
	_add_property("Volume (each)", "%.2f m³" % current_item.volume)
	_add_property("Total Volume", "%.2f m³" % (current_item.volume * current_item.quantity))
	
	if current_item.has_method("get_item_value"):
		_add_property("Value (each)", "%.0f credits" % current_item.get_item_value())
		_add_property("Total Value", "%.0f credits" % (current_item.get_item_value() * current_item.quantity))
	
	# Add description if available
	if current_item.has_method("get_description") and current_item.get_description().length() > 0:
		_add_separator()
		_add_description(current_item.get_description())

func _add_property(name: String, value: String):
	var property_row = HBoxContainer.new()
	properties_container.add_child(property_row)
	
	var name_label = Label.new()
	name_label.text = name + ":"
	name_label.custom_minimum_size.x = 120
	name_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
	property_row.add_child(name_label)
	
	var value_label = Label.new()
	value_label.text = value
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	property_row.add_child(value_label)

func _add_separator():
	var separator = HSeparator.new()
	separator.add_theme_constant_override("separation", 8)
	properties_container.add_child(separator)

func _add_description(description: String):
	var desc_label = Label.new()
	desc_label.text = description
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	properties_container.add_child(desc_label)

func _clear_display():
	item_icon.texture = null
	item_title.text = ""
	item_subtitle.text = ""
	
	for child in properties_container.get_children():
		child.queue_free()
