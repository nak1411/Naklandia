# InventoryWindowHeader.gd - Updated with debugging and proper integration
class_name InventoryWindowHeader
extends Control

# Signals
signal search_changed(text: String)
signal filter_changed(filter_type: int)
signal sort_requested(sort_type: InventorySortType.Type)
signal display_mode_changed(mode: InventoryDisplayMode.Mode)

# UI Components
var search_field: LineEdit
var filter_options: Panel
var sort_button: Panel
var filter_dropdown: DropDownMenu_Base
var sort_dropdown: DropDownMenu_Base
var original_header_styles: Dictionary = {}
var header_transparency_init: bool = false
var is_search_focused: bool = false
var display_mode_button: Panel
var current_display_mode: InventoryDisplayMode.Mode = InventoryDisplayMode.Mode.GRID

# References
var inventory_manager: InventoryManager
var inventory_window: Window

# State
var current_transparency: float = 1.0

# Filter dropdown data
var filter_items = ["All Items", "Weapons", "Armor", "Consumables", "Resources", "Blueprints", "Modules", "Ships", "Containers", "Ammunition", "Implants", "Skill Books"]
var current_filter_index = 0

# Sort dropdown data
var sort_items = ["By Name", "By Type", "By Value", "By Volume"]
var current_sort_index = 0


func _ready():
	custom_minimum_size.y = 30  # 16px buttons + 4px margin (2px top + 2px bottom)
	_setup_controls()
	_connect_signals()


func _setup_controls():
	var current_x = 0
	var button_height = 24  # Our target height
	var margin = 4
	var bottom_padding = 4
	var left_padding = 0
	var top_padding = 2

	# Filter "button" using Panel + Label
	filter_options = _create_label_button("All Items ▼", Vector2(100, button_height))
	filter_options.name = "FilterButton"
	filter_options.position = Vector2(current_x + left_padding, bottom_padding)
	add_child(filter_options)
	current_x += 100 + margin

	# Sort "button" using Panel + Label
	sort_button = _create_label_button("Sort ▼", Vector2(60, button_height))
	sort_button.name = "SortButton"
	sort_button.position = Vector2(current_x, bottom_padding)
	add_child(sort_button)
	current_x += 60 + margin

	# Search field
	search_field = LineEdit.new()
	search_field.name = "SearchField"
	search_field.placeholder_text = "Search..."
	search_field.size = Vector2(100, button_height)
	search_field.custom_minimum_size = Vector2(100, button_height)

	# Style the search field to match the fake buttons
	_style_search_field()

	add_child(search_field)

	# Display mode "button" using Panel + Label
	display_mode_button = _create_label_button("⊞", Vector2(button_height, button_height))
	display_mode_button.name = "DisplayModeButton"
	add_child(display_mode_button)

	# Position right-aligned elements
	_position_right_elements()

	# Create dropdown menus
	_create_dropdown_menus()


func _create_label_button(text: String, button_size: Vector2) -> Panel:
	"""Create a fake button using Panel + Label"""
	var panel = Panel.new()
	panel.size = button_size
	panel.custom_minimum_size = button_size

	# Style the panel like a button
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	normal_style.border_width_left = 1
	normal_style.border_width_right = 1
	normal_style.border_width_top = 1
	normal_style.border_width_bottom = 1
	normal_style.border_color = ColorUtilities.get_border_color()
	panel.add_theme_stylebox_override("panel", normal_style)

	# Add label for text
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 12)
	panel.add_child(label)

	# Add mouse interaction
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.mouse_entered.connect(_on_fake_button_hover.bind(panel, true))
	panel.mouse_exited.connect(_on_fake_button_hover.bind(panel, false))
	panel.gui_input.connect(_on_fake_button_input.bind(panel))

	return panel


func _on_fake_button_hover(panel: Panel, is_hovering: bool):
	var style = StyleBoxFlat.new()
	if is_hovering:
		style.bg_color = Color(0.5, 0.5, 0.5, 1.0)  # Hover color
	else:
		style.bg_color = Color(0.2, 0.2, 0.2, 1.0)  # Normal color

	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = ColorUtilities.get_border_color()
	panel.add_theme_stylebox_override("panel", style)


func _on_fake_button_input(event: InputEvent, panel: Panel):
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			# Handle click based on button name
			match panel.name:
				"FilterButton":
					_on_filter_button_pressed()
				"SortButton":
					_on_sort_button_pressed()
				"DisplayModeButton":
					_on_display_mode_toggled()


func _position_right_elements():
	"""Position search field and display button from the right edge"""
	var container_width = size.x
	var button_height = 16
	var margin = 2
	var top_padding = 4
	var right_padding = 8  # Add right padding

	# Position display button at far right (minus right padding)
	if display_mode_button:
		display_mode_button.position = Vector2(container_width - button_height - right_padding, top_padding)

	# Position search field to the left of display button
	if search_field:
		search_field.position = Vector2(container_width - button_height - 100 - margin - (right_padding + 2), top_padding)


# Override _notification to handle resizing
func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_position_right_elements()


func _style_display_mode_button():
	if not display_mode_button:
		return

	# Create normal style
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	normal_style.border_width_left = 1
	normal_style.border_width_right = 1
	normal_style.border_width_top = 1
	normal_style.border_width_bottom = 1
	normal_style.border_color = ColorUtilities.get_border_color()

	# Create hover style
	var hover_style = normal_style.duplicate()
	hover_style.bg_color = Color(0.4, 0.4, 0.4, 1.0)

	# Create pressed style
	var pressed_style = normal_style.duplicate()
	pressed_style.bg_color = Color(0.2, 0.2, 0.2, 1.0)

	display_mode_button.add_theme_stylebox_override("normal", normal_style)
	display_mode_button.add_theme_stylebox_override("hover", hover_style)
	display_mode_button.add_theme_stylebox_override("pressed", pressed_style)

	# Set font properties
	display_mode_button.add_theme_color_override("font_color", Color.WHITE)
	display_mode_button.add_theme_font_size_override("font_size", 24)


func _style_custom_display_button():
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.3, 0.3, 0.3, 1.0)
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = ColorUtilities.get_border_color()

	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.5, 0.5, 0.5, 1.0)
	style_hover.border_width_left = 1
	style_hover.border_width_right = 1
	style_hover.border_width_top = 1
	style_hover.border_width_bottom = 1
	style_hover.border_color = Color(0.7, 0.7, 0.7, 1.0)
	style_hover.content_margin_left = 12
	style_hover.content_margin_right = 12
	style_hover.content_margin_top = 0
	style_hover.content_margin_bottom = 0

	display_mode_button.add_theme_stylebox_override("normal", style_normal)
	display_mode_button.add_theme_stylebox_override("hover", style_hover)
	display_mode_button.add_theme_stylebox_override("pressed", style_hover)
	display_mode_button.add_theme_stylebox_override("focus", style_normal)
	display_mode_button.add_theme_color_override("font_color", Color.WHITE)


func _style_search_field():
	"""Style the search field to match the fake buttons"""
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = ColorUtilities.get_border_color()
	style_normal.content_margin_left = 6
	style_normal.content_margin_right = 6
	style_normal.content_margin_top = 1
	style_normal.content_margin_bottom = 1
	style_normal.set_corner_radius_all(0)  # Remove rounded corners

	var style_focus = style_normal.duplicate()
	style_focus.border_color = Color(0.6, 0.6, 0.8, 1.0)  # Slightly brighter border when focused

	search_field.add_theme_stylebox_override("normal", style_normal)
	search_field.add_theme_stylebox_override("focus", style_focus)

	# Set font color to white to match the buttons
	search_field.add_theme_color_override("font_color", Color.WHITE)
	search_field.add_theme_color_override("font_placeholder_color", Color(0.7, 0.7, 0.7, 1.0))


func set_fake_button_text(panel: Panel, text: String):
	"""Helper function to set text on fake button panels"""
	var label = panel.get_child(0) as Label
	if label:
		label.text = text


func _on_display_mode_toggled():
	match current_display_mode:
		InventoryDisplayMode.Mode.GRID:
			current_display_mode = InventoryDisplayMode.Mode.LIST
			set_fake_button_text(display_mode_button, "☰")  # Changed
		InventoryDisplayMode.Mode.LIST:
			current_display_mode = InventoryDisplayMode.Mode.GRID
			set_fake_button_text(display_mode_button, "⊞")  # Changed

	display_mode_changed.emit(current_display_mode)


func _create_dropdown_menus():
	# Create filter dropdown
	filter_dropdown = DropDownMenu_Base.new()
	filter_dropdown.name = "FilterDropdown"
	_setup_filter_dropdown()

	# Create sort dropdown
	sort_dropdown = DropDownMenu_Base.new()
	sort_dropdown.name = "SortDropdown"
	_setup_sort_dropdown()


func _setup_filter_dropdown():
	# Add all filter items to dropdown
	for i in range(filter_items.size()):
		var item_id = "filter_" + str(i)
		filter_dropdown.add_menu_item(item_id, filter_items[i])

	# Connect selection signal
	if filter_dropdown.has_signal("item_selected"):
		filter_dropdown.item_selected.connect(_on_filter_dropdown_selected)

	# Connect menu close signal
	if filter_dropdown.has_signal("tree_exiting"):
		filter_dropdown.tree_exiting.connect(_on_filter_dropdown_closed)


func _setup_sort_dropdown():
	# Add all sort items to dropdown
	for i in range(sort_items.size()):
		var item_id = "sort_" + str(i)
		sort_dropdown.add_menu_item(item_id, sort_items[i])

	# Connect selection signal
	if sort_dropdown.has_signal("item_selected"):
		sort_dropdown.item_selected.connect(_on_sort_dropdown_selected)

	# Connect menu close signal
	if sort_dropdown.has_signal("tree_exiting"):
		sort_dropdown.tree_exiting.connect(_on_sort_dropdown_closed)


func _style_custom_filter_button():
	filter_options.flat = false
	filter_options.focus_mode = Control.FOCUS_NONE

	# Create normal style with reduced padding
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	normal_style.border_width_left = 1
	normal_style.border_width_right = 1
	normal_style.border_width_top = 1
	normal_style.border_width_bottom = 1
	normal_style.border_color = ColorUtilities.get_border_color()
	# Reduce content margins to make button shorter
	normal_style.content_margin_left = 8
	normal_style.content_margin_right = 8
	normal_style.content_margin_top = 2  # Reduced from 6 to 2
	normal_style.content_margin_bottom = 2  # Reduced from 6 to 2

	# Create hover style
	var hover_style = normal_style.duplicate()
	hover_style.bg_color = Color(0.5, 0.5, 0.5, 1.0)

	# Create pressed style
	var pressed_style = normal_style.duplicate()
	pressed_style.bg_color = Color(0.3, 0.3, 0.3, 1.0)

	filter_options.add_theme_stylebox_override("normal", normal_style)
	filter_options.add_theme_stylebox_override("hover", hover_style)
	filter_options.add_theme_stylebox_override("pressed", pressed_style)

	filter_options.add_theme_color_override("font_color", Color.WHITE)
	filter_options.add_theme_font_size_override("font_size", 12)


func _style_custom_sort_button():
	sort_button.focus_mode = Control.FOCUS_NONE
	sort_button.flat = false

	# Create normal style with reduced padding
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = ColorUtilities.get_border_color()
	# Reduce content margins to make button shorter
	style_normal.content_margin_left = 8
	style_normal.content_margin_right = 8
	style_normal.content_margin_top = 2  # Reduced from 6 to 2
	style_normal.content_margin_bottom = 2  # Reduced from 6 to 2
	style_normal.set_corner_radius_all(0)

	# Create hover style
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.5, 0.5, 0.5, 1.0)

	# Create pressed style
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = Color(0.3, 0.3, 0.3, 1.0)

	sort_button.add_theme_stylebox_override("normal", style_normal)
	sort_button.add_theme_stylebox_override("hover", style_hover)
	sort_button.add_theme_stylebox_override("pressed", style_pressed)

	sort_button.add_theme_color_override("font_color", Color.WHITE)
	sort_button.add_theme_font_size_override("font_size", 12)


func _connect_signals():
	if search_field:
		search_field.text_changed.connect(_on_search_text_changed)
		search_field.focus_entered.connect(_on_search_focus_entered)
		search_field.focus_exited.connect(_on_search_focus_exited)


func _on_search_focus_entered():
	is_search_focused = true


func _on_search_focus_exited():
	is_search_focused = false


func clear_search_focus():
	if search_field and search_field.has_focus():
		search_field.release_focus()
		# Also clear the search text if desired
		#search_field.text = ""
		#search_changed.emit("")


func _on_search_field_input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		# Consume all key input when search field is focused
		get_viewport().set_input_as_handled()

		# Handle special keys
		if event.keycode == KEY_ESCAPE:
			# Clear search and lose focus
			search_field.text = ""
			search_field.release_focus()
			search_changed.emit("")


func _input(event: InputEvent):
	if not is_search_focused:
		return

	if event is InputEventKey and event.pressed:
		pass


func _remove_default_outlines():
	var controls = [search_field, filter_options, sort_button]

	for control in controls:
		if control:
			# Remove focus and normal style overrides that might cause outlines
			control.remove_theme_stylebox_override("focus")
			control.remove_theme_stylebox_override("normal")
			control.remove_theme_stylebox_override("pressed")
			control.remove_theme_stylebox_override("hover")
			control.remove_theme_stylebox_override("disabled")

			# Style LineEdit specifically with reduced padding
			if control is LineEdit:
				var style_normal = StyleBoxFlat.new()
				style_normal.bg_color = Color(0.2, 0.2, 0.2, 0.8)
				style_normal.border_width_left = 1
				style_normal.border_width_right = 1
				style_normal.border_width_top = 1
				style_normal.border_width_bottom = 1
				style_normal.border_color = ColorUtilities.get_border_color()
				# Reduce content margins for shorter height
				style_normal.content_margin_left = 6
				style_normal.content_margin_right = 6
				style_normal.content_margin_top = 2  # Reduced padding
				style_normal.content_margin_bottom = 2  # Reduced padding

				control.add_theme_stylebox_override("normal", style_normal)
				control.add_theme_stylebox_override("focus", style_normal)


func _apply_custom_theme():
	# Create a theme for the entire header
	var header_theme = Theme.new()

	# Apply theme to the header container
	set_theme(header_theme)


func _force_button_styling():
	# Make sure buttons are visible
	if filter_options:
		filter_options.modulate = Color(1.0, 1.0, 1.0, 1.0)
		filter_options.queue_redraw()

	if sort_button:
		sort_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
		sort_button.queue_redraw()


# Signal handlers
func _on_search_text_changed(new_text: String):
	search_changed.emit(new_text)


func _on_filter_button_pressed():
	if not filter_dropdown:
		return

	# Show dropdown at button position
	var button_pos = filter_options.get_screen_position()
	var dropdown_pos = Vector2(button_pos.x, button_pos.y + filter_options.size.y)

	# Only add dropdown to scene if it's not already there
	if not filter_dropdown.get_parent():
		get_viewport().add_child(filter_dropdown)

	# Show the menu
	if filter_dropdown.has_method("show_menu"):
		filter_dropdown.show_menu(dropdown_pos)


func _on_filter_dropdown_selected(item_id: String, _item_data: Dictionary):
	var index_str = item_id.replace("filter_", "")
	var index = int(index_str)

	if index >= 0 and index < filter_items.size():
		current_filter_index = index
		set_fake_button_text(filter_options, filter_items[index] + " ▼")
		filter_changed.emit(index)


func _on_sort_button_pressed():
	if not sort_dropdown:
		return

	# Show dropdown at button position
	var button_pos = sort_button.get_screen_position()
	var dropdown_pos = Vector2(button_pos.x, button_pos.y + sort_button.size.y)

	# Only add dropdown to scene if it's not already there
	if not sort_dropdown.get_parent():
		get_viewport().add_child(sort_dropdown)

	# Show the menu
	if sort_dropdown.has_method("show_menu"):
		sort_dropdown.show_menu(dropdown_pos)


func _on_sort_dropdown_selected(item_id: String, _item_data: Dictionary):
	var index_str = item_id.replace("sort_", "")
	var index = int(index_str)

	if index >= 0 and index < sort_items.size():
		current_sort_index = index
		set_fake_button_text(sort_button, sort_items[index] + " ▼")

		var sort_type = index as InventorySortType.Type
		sort_requested.emit(sort_type)


func _on_filter_dropdown_closed():
	# Remove filter dropdown from scene when it closes
	if filter_dropdown and filter_dropdown.get_parent():
		filter_dropdown.get_parent().remove_child.call_deferred(filter_dropdown)


func _on_sort_dropdown_closed():
	# Remove sort dropdown from scene when it closes
	if sort_dropdown and sort_dropdown.get_parent():
		sort_dropdown.get_parent().remove_child.call_deferred(sort_dropdown)


# Public interface
func set_inventory_manager(manager: InventoryManager):
	inventory_manager = manager


func set_inventory_window(window: Window):
	inventory_window = window


func get_search_text() -> String:
	if search_field:
		return search_field.text
	return ""


func get_filter_index() -> int:
	return current_filter_index


func clear_search():
	if search_field:
		search_field.text = ""


# Transparency handling
func set_transparency(transparency: float):
	current_transparency = transparency

	# Store originals on first call
	if not header_transparency_init:
		_store_original_header_styles()
		header_transparency_init = true

	# Apply base modulate
	modulate.a = transparency

	# Apply transparency to buttons using stored originals
	_apply_transparency_from_originals(transparency)


func _store_original_header_styles():
	if filter_options:
		var style = filter_options.get_theme_stylebox("normal")
		if style and style is StyleBoxFlat:
			original_header_styles["filter_normal"] = style.duplicate()

	if sort_button:
		var style = sort_button.get_theme_stylebox("normal")
		if style and style is StyleBoxFlat:
			original_header_styles["sort_normal"] = style.duplicate()

	if search_field:
		var style = search_field.get_theme_stylebox("normal")
		if style and style is StyleBoxFlat:
			original_header_styles["search_normal"] = style.duplicate()


func _apply_transparency_from_originals(transparency: float):
	# Apply to filter button
	if filter_options and original_header_styles.has("filter_normal"):
		var original = original_header_styles["filter_normal"] as StyleBoxFlat
		var new_style = original.duplicate() as StyleBoxFlat
		var orig_color = original.bg_color
		new_style.bg_color = Color(orig_color.r, orig_color.g, orig_color.b, orig_color.a * transparency)
		filter_options.add_theme_stylebox_override("normal", new_style)

	# Apply to sort button
	if sort_button and original_header_styles.has("sort_normal"):
		var original = original_header_styles["sort_normal"] as StyleBoxFlat
		var new_style = original.duplicate() as StyleBoxFlat
		var orig_color = original.bg_color
		new_style.bg_color = Color(orig_color.r, orig_color.g, orig_color.b, orig_color.a * transparency)
		sort_button.add_theme_stylebox_override("normal", new_style)

	# Apply to search field
	if search_field and original_header_styles.has("search_normal"):
		var original = original_header_styles["search_normal"] as StyleBoxFlat
		var new_style = original.duplicate() as StyleBoxFlat
		var orig_color = original.bg_color
		new_style.bg_color = Color(orig_color.r, orig_color.g, orig_color.b, orig_color.a * transparency)
		search_field.add_theme_stylebox_override("normal", new_style)
