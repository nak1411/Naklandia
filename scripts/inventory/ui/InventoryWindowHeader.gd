# InventoryWindowHeader.gd - Updated with debugging and proper integration
class_name InventoryWindowHeader
extends HBoxContainer

# UI Components
var search_field: LineEdit
var filter_options: Button
var sort_button: Button
var filter_dropdown: DropDownMenu_Base
var sort_dropdown: DropDownMenu_Base
var original_header_styles: Dictionary = {}
var header_transparency_init: bool = false
var is_search_focused: bool = false
var display_mode_button: Button
var current_display_mode: InventoryDisplayMode.Mode = InventoryDisplayMode.Mode.GRID

# References
var inventory_manager: InventoryManager
var inventory_window: Window

# Signals
signal search_changed(text: String)
signal filter_changed(filter_type: int)
signal sort_requested(sort_type: InventoryManager.SortType)
signal display_mode_changed(mode: InventoryDisplayMode.Mode)

# State
var current_transparency: float = 1.0

# Filter dropdown data
var filter_items = [
	"All Items", "Weapons", "Armor", "Consumables", "Resources", 
	"Blueprints", "Modules", "Ships", "Containers", "Ammunition", 
	"Implants", "Skill Books"
]
var current_filter_index = 0

# Sort dropdown data
var sort_items = [
	"By Name", "By Type", "By Value", "By Volume"
]
var current_sort_index = 0

func _ready():
	custom_minimum_size.y = 35  # Reduced height to not overlap title bar
	_setup_controls()
	_connect_signals()
	_remove_default_outlines()
	_apply_custom_theme()
	# Force styling after everything is set up
	call_deferred("_force_button_styling")

func _setup_controls():	
	var filter_container = MarginContainer.new()
	add_child(filter_container)
	
	filter_container.add_theme_constant_override("margin_left", 4)
	filter_container.add_theme_constant_override("margin_top", 4)
	filter_container.add_theme_constant_override("margin_right", 2)
	filter_container.add_theme_constant_override("margin_bottom", 2)
	
	# Create filter button (regular Button) - Make it more responsive
	filter_options = Button.new()
	filter_options.name = "FilterButton"
	filter_options.text = "All Items ▼"
	filter_options.custom_minimum_size.x = 100  # Reduced from 120
	filter_options.size_flags_horizontal = Control.SIZE_SHRINK_CENTER  # Allow shrinking
	filter_options.alignment = HORIZONTAL_ALIGNMENT_CENTER
	filter_options.clip_contents = true  # Prevent text overflow
	_style_custom_filter_button()
	filter_container.add_child(filter_options)
	
	var sort_container = MarginContainer.new()
	add_child(sort_container)
	
	sort_container.add_theme_constant_override("margin_left", 4)
	sort_container.add_theme_constant_override("margin_top", 4)
	sort_container.add_theme_constant_override("margin_right", 2)
	sort_container.add_theme_constant_override("margin_bottom", 2)
	
	# Sort button (regular Button) - Make it more responsive
	sort_button = Button.new()
	sort_button.name = "SortButton"
	sort_button.text = "Sort ▼"
	sort_button.custom_minimum_size.x = 60  # Reduced from 80
	sort_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER  # Allow shrinking
	sort_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	sort_button.clip_contents = true  # Prevent text overflow
	_style_custom_sort_button()
	sort_container.add_child(sort_button)
	
	# Spacer to push search field to the right
	var spacer = Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(spacer)
	
	# Search field - now on the right side, make it responsive
	var search_container = MarginContainer.new()
	add_child(search_container)
	
	search_container.add_theme_constant_override("margin_left", 4)
	search_container.add_theme_constant_override("margin_top", 4)
	search_container.add_theme_constant_override("margin_bottom", 2)
	
	search_field = LineEdit.new()
	search_field.name = "SearchField"
	search_field.placeholder_text = "Search..."  # Shorter placeholder
	search_field.custom_minimum_size.x = 100  # Reduced from 150
	search_field.size_flags_horizontal = Control.SIZE_SHRINK_CENTER  # Allow shrinking
	search_field.focus_mode = Control.FOCUS_ALL
	search_container.add_child(search_field)
	
	# Display mode toggle button - Make it more responsive
	var display_container = MarginContainer.new()
	add_child(display_container)

	display_container.add_theme_constant_override("margin_left", 4)
	display_container.add_theme_constant_override("margin_top", 4)
	display_container.add_theme_constant_override("margin_right", 2)
	display_container.add_theme_constant_override("margin_bottom", 2)

	display_mode_button = Button.new()
	display_mode_button.name = "DisplayModeButton"
	display_mode_button.text = "Grid"
	display_mode_button.custom_minimum_size.x = 45  # Reduced from 60
	display_mode_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER  # Allow shrinking
	display_mode_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	display_mode_button.clip_contents = true  # Prevent text overflow
	_style_custom_display_button()
	display_container.add_child(display_mode_button)
	
	# Create dropdown menus (don't add as children initially)
	_create_dropdown_menus()
	
func _style_custom_display_button():
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.3, 0.3, 0.3, 1.0)
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(0.6, 0.6, 0.6, 1.0)
	style_normal.content_margin_left = 12
	style_normal.content_margin_right = 12
	style_normal.content_margin_top = 6
	style_normal.content_margin_bottom = 6
	
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.5, 0.5, 0.5, 1.0)
	style_hover.border_width_left = 1
	style_hover.border_width_right = 1
	style_hover.border_width_top = 1
	style_hover.border_width_bottom = 1
	style_hover.border_color = Color(0.7, 0.7, 0.7, 1.0)
	style_hover.content_margin_left = 12
	style_hover.content_margin_right = 12
	style_hover.content_margin_top = 6
	style_hover.content_margin_bottom = 6
	
	display_mode_button.add_theme_stylebox_override("normal", style_normal)
	display_mode_button.add_theme_stylebox_override("hover", style_hover)
	display_mode_button.add_theme_stylebox_override("pressed", style_hover)
	display_mode_button.add_theme_stylebox_override("focus", style_normal)
	display_mode_button.add_theme_color_override("font_color", Color.WHITE)

func _on_display_mode_toggled():
	match current_display_mode:
		InventoryDisplayMode.Mode.GRID:
			current_display_mode = InventoryDisplayMode.Mode.LIST
			display_mode_button.text = "List"
		InventoryDisplayMode.Mode.LIST:
			current_display_mode = InventoryDisplayMode.Mode.GRID
			display_mode_button.text = "Grid"
	
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
	# Make the button NOT flat so it can show styling
	filter_options.flat = false
	
	# Create normal style
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.9, 0.4, 0.4, 1.0)
	style_normal.border_width_left = 2
	style_normal.border_width_right = 2
	style_normal.border_width_top = 2
	style_normal.border_width_bottom = 2
	style_normal.border_color = Color(0.9, 0.6, 0.6, 1.0)
	style_normal.content_margin_left = 12
	style_normal.content_margin_right = 12
	style_normal.content_margin_top = 6
	style_normal.content_margin_bottom = 6
	
	# Create hover style
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.5, 0.5, 0.5, 1.0)
	style_hover.border_width_left = 1
	style_hover.border_width_right = 1
	style_hover.border_width_top = 1
	style_hover.border_width_bottom = 1
	style_hover.border_color = Color(0.7, 0.7, 0.7, 1.0)
	style_hover.content_margin_left = 12
	style_hover.content_margin_right = 12
	style_hover.content_margin_top = 6
	style_hover.content_margin_bottom = 6
	
	# Apply styles
	filter_options.add_theme_stylebox_override("normal", style_normal)
	filter_options.add_theme_stylebox_override("hover", style_hover)
	filter_options.add_theme_stylebox_override("pressed", style_hover)
	filter_options.add_theme_stylebox_override("focus", style_normal)
	filter_options.add_theme_color_override("font_color", Color.WHITE)

func _style_custom_sort_button():	
	# Make the button NOT flat so it can show styling
	sort_button.flat = false
	
	# Create normal style
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.4, 0.4, 0.4, 1.0)
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(0.6, 0.6, 0.6, 1.0)
	style_normal.content_margin_left = 12
	style_normal.content_margin_right = 12
	style_normal.content_margin_top = 6
	style_normal.content_margin_bottom = 6
	
	# Create hover style
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.5, 0.5, 0.5, 1.0)
	style_hover.border_width_left = 1
	style_hover.border_width_right = 1
	style_hover.border_width_top = 1
	style_hover.border_width_bottom = 1
	style_hover.border_color = Color(0.7, 0.7, 0.7, 1.0)
	style_hover.content_margin_left = 12
	style_hover.content_margin_right = 12
	style_hover.content_margin_top = 6
	style_hover.content_margin_bottom = 6
	
	# Apply styles
	sort_button.add_theme_stylebox_override("normal", style_normal)
	sort_button.add_theme_stylebox_override("hover", style_hover)
	sort_button.add_theme_stylebox_override("pressed", style_hover)
	sort_button.add_theme_stylebox_override("focus", style_normal)
	sort_button.add_theme_color_override("font_color", Color.WHITE)

func _connect_signals():	
	if search_field:
		search_field.text_changed.connect(_on_search_text_changed)
		search_field.focus_entered.connect(_on_search_focus_entered)
		search_field.focus_exited.connect(_on_search_focus_exited)
	
	if filter_options:
		filter_options.pressed.connect(_on_filter_button_pressed)
	
	if sort_button:
		sort_button.pressed.connect(_on_sort_button_pressed)
		
	if display_mode_button:
		display_mode_button.pressed.connect(_on_display_mode_toggled)
		
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
	# Remove any default focus outlines and borders from all controls
	var controls = [search_field, filter_options, sort_button]
	
	for control in controls:
		if control:
			# Remove focus and normal style overrides that might cause outlines
			control.remove_theme_stylebox_override("focus")
			control.remove_theme_stylebox_override("normal")
			control.remove_theme_stylebox_override("pressed")
			control.remove_theme_stylebox_override("hover")
			control.remove_theme_stylebox_override("disabled")
			
			# Style LineEdit specifically
			if control is LineEdit:
				var style_normal = StyleBoxFlat.new()
				style_normal.bg_color = Color(0.2, 0.2, 0.2, 0.8)
				style_normal.border_width_left = 1
				style_normal.border_width_right = 1
				style_normal.border_width_top = 1
				style_normal.border_width_bottom = 1
				style_normal.border_color = Color(0.4, 0.4, 0.4, 1.0)
				style_normal.content_margin_left = 8
				style_normal.content_margin_right = 8
				
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
	# Extract index from item_id (format: "filter_0", "filter_1", etc.)
	var index_str = item_id.replace("filter_", "")
	var index = int(index_str)
	
	if index >= 0 and index < filter_items.size():
		current_filter_index = index
		filter_options.text = filter_items[index] + " ▼"
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
	# Extract index from item_id (format: "sort_0", "sort_1", etc.)
	var index_str = item_id.replace("sort_", "")
	var index = int(index_str)
	
	if index >= 0 and index < sort_items.size():
		current_sort_index = index
		sort_button.text = sort_items[index] + " ▼"
		
		# Convert to InventoryManager.SortType
		var sort_type = index as InventoryManager.SortType
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
