# InventoryWindowHeader.gd - Header controls for inventory window
class_name InventoryWindowHeader
extends HBoxContainer

# UI Components
var search_field: LineEdit
var filter_options: Button  # Using Button with DropDownMenu_Base
var sort_button: Button  # Changed from MenuButton to Button
var filter_dropdown: DropDownMenu_Base
var sort_dropdown: DropDownMenu_Base

# References
var inventory_manager: InventoryManager
var inventory_window: Window

# Signals
signal search_changed(text: String)
signal filter_changed(filter_type: int)
signal sort_requested(sort_type: InventoryManager.SortType)

# State
var current_transparency: float = 1.0

# Add filter dropdown data
var filter_items = [
	"All Items", "Weapons", "Armor", "Consumables", "Resources", 
	"Blueprints", "Modules", "Ships", "Containers", "Ammunition", 
	"Implants", "Skill Books"
]
var current_filter_index = 0

# Add sort dropdown data
var sort_items = [
	"By Name", "By Type", "By Value", "By Volume", "By Rarity"
]
var current_sort_index = 0

func _ready():
	custom_minimum_size.y = 40
	_setup_controls()
	_connect_signals()
	_remove_default_outlines()
	_apply_custom_theme()
	# Force styling after everything is set up
	call_deferred("_force_button_styling")

func _setup_controls():
	# Create filter button (regular Button) - now on the left
	filter_options = Button.new()
	filter_options.text = "All Items ▼"
	filter_options.custom_minimum_size.x = 120
	filter_options.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_custom_filter_button()
	add_child(filter_options)
	
	# Sort button (regular Button) - next to filter on the left
	sort_button = Button.new()
	sort_button.text = "Sort ▼"
	sort_button.custom_minimum_size.x = 80
	sort_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_custom_sort_button()
	add_child(sort_button)
	
	# Spacer to push search field to the right
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(spacer)
	
	# Search field - now on the right side
	search_field = LineEdit.new()
	search_field.placeholder_text = "Search items..."
	search_field.custom_minimum_size.x = 150
	add_child(search_field)
	
	# Create dropdown menus but DON'T add them as children to the HBoxContainer
	# They will be added to the scene when needed
	filter_dropdown = DropDownMenu_Base.new()
	filter_dropdown.name = "FilterDropdown"
	_setup_filter_dropdown()
	
	sort_dropdown = DropDownMenu_Base.new()
	sort_dropdown.name = "SortDropdown"
	_setup_sort_dropdown()

func _setup_filter_dropdown():
	# Add all filter items to dropdown
	for i in range(filter_items.size()):
		filter_dropdown.add_menu_item("filter_" + str(i), filter_items[i])
	
	# Connect selection signal
	filter_dropdown.item_selected.connect(_on_filter_dropdown_selected)
	# Connect menu close signal to remove from scene
	filter_dropdown.tree_exiting.connect(_on_filter_dropdown_closed)

func _setup_sort_dropdown():
	# Add all sort items to dropdown
	for i in range(sort_items.size()):
		sort_dropdown.add_menu_item("sort_" + str(i), sort_items[i])
	
	# Connect selection signal
	sort_dropdown.item_selected.connect(_on_sort_dropdown_selected)
	# Connect menu close signal to remove from scene
	sort_dropdown.tree_exiting.connect(_on_sort_dropdown_closed)

func _style_custom_filter_button():
	# Make the button NOT flat so it can show styling
	filter_options.flat = false
	
	# Style the custom filter button with our desired appearance
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.4, 0.4, 0.4, 1.0)  # Much lighter
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(0.6, 0.6, 0.6, 1.0)
	# Increased inner padding for better visual spacing
	style_normal.content_margin_left = 12
	style_normal.content_margin_right = 12
	style_normal.content_margin_top = 6
	style_normal.content_margin_bottom = 6
	
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.5, 0.5, 0.5, 1.0)  # Even lighter
	style_hover.border_width_left = 1
	style_hover.border_width_right = 1
	style_hover.border_width_top = 1
	style_hover.border_width_bottom = 1
	style_hover.border_color = Color(0.7, 0.7, 0.7, 1.0)
	# Increased inner padding for better visual spacing
	style_hover.content_margin_left = 12
	style_hover.content_margin_right = 12
	style_hover.content_margin_top = 6
	style_hover.content_margin_bottom = 6
	
	filter_options.add_theme_stylebox_override("normal", style_normal)
	filter_options.add_theme_stylebox_override("hover", style_hover)
	filter_options.add_theme_stylebox_override("pressed", style_hover)
	filter_options.add_theme_stylebox_override("focus", style_normal)
	filter_options.add_theme_color_override("font_color", Color.WHITE)

func _style_custom_sort_button():
	# Make the button NOT flat so it can show styling
	sort_button.flat = false
	
	# Style the custom sort button with our desired appearance
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.4, 0.4, 0.4, 1.0)
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(0.6, 0.6, 0.6, 1.0)
	# Increased inner padding for better visual spacing
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
	# Increased inner padding for better visual spacing  
	style_hover.content_margin_left = 12
	style_hover.content_margin_right = 12
	style_hover.content_margin_top = 6
	style_hover.content_margin_bottom = 6
	
	sort_button.add_theme_stylebox_override("normal", style_normal)
	sort_button.add_theme_stylebox_override("hover", style_hover)
	sort_button.add_theme_stylebox_override("pressed", style_hover)
	sort_button.add_theme_stylebox_override("focus", style_normal)
	sort_button.add_theme_color_override("font_color", Color.WHITE)

func _connect_signals():
	search_field.text_changed.connect(_on_search_text_changed)
	filter_options.pressed.connect(_on_filter_button_pressed)
	sort_button.pressed.connect(_on_sort_button_pressed)

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
			
			# Set flat appearance for other buttons to remove borders
			if control is Button:
				control.flat = true
			
			# Remove line edit focus styling and add padding
			elif control is LineEdit:
				var style_normal = StyleBoxFlat.new()
				style_normal.bg_color = Color(0.2, 0.2, 0.2, 0.8)
				style_normal.border_width_left = 1
				style_normal.border_width_right = 1
				style_normal.border_width_top = 1
				style_normal.border_width_bottom = 1
				style_normal.border_color = Color(0.4, 0.4, 0.4, 1.0)
				
				# Add padding inside the search box
				style_normal.content_margin_left = 8
				style_normal.content_margin_right = 8
				
				control.add_theme_stylebox_override("normal", style_normal)
				control.add_theme_stylebox_override("focus", style_normal)

func _apply_custom_theme():
	# Create a theme for the entire header to ensure it takes priority
	var header_theme = Theme.new()
	
	# MenuButton styling for sort button
	var menu_style_normal = StyleBoxFlat.new()
	menu_style_normal.bg_color = Color(0.3, 0.3, 0.3, 1.0)
	menu_style_normal.border_width_left = 1
	menu_style_normal.border_width_right = 1
	menu_style_normal.border_width_top = 1
	menu_style_normal.border_width_bottom = 1
	menu_style_normal.border_color = Color(0.5, 0.5, 0.5, 1.0)
	
	var menu_style_hover = StyleBoxFlat.new()
	menu_style_hover.bg_color = Color(0.35, 0.35, 0.35, 1.0)
	menu_style_hover.border_width_left = 1
	menu_style_hover.border_width_right = 1
	menu_style_hover.border_width_top = 1
	menu_style_hover.border_width_bottom = 1
	menu_style_hover.border_color = Color(0.6, 0.6, 0.6, 1.0)
	
	header_theme.set_stylebox("normal", "MenuButton", menu_style_normal)
	header_theme.set_stylebox("hover", "MenuButton", menu_style_hover)
	header_theme.set_stylebox("pressed", "MenuButton", menu_style_hover)
	header_theme.set_stylebox("disabled", "MenuButton", menu_style_normal)
	header_theme.set_stylebox("focus", "MenuButton", menu_style_normal)
	
	# Apply theme to the header container
	set_theme(header_theme)

func _force_button_styling():
	# Force the filter button to be visible by using modulate
	filter_options.modulate = Color(0.8, 0.8, 0.8, 1.0)  # Make it 50% brighter
	
	# Also force a background color override WITH PROPER PADDING
	filter_options.add_theme_color_override("font_color", Color.DARK_GRAY)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color.WHITE * 0.4  # 40% white
	bg_style.border_width_left = 1
	bg_style.border_width_right = 1
	bg_style.border_width_top = 1
	bg_style.border_width_bottom = 1
	bg_style.border_color = Color.WHITE * 0.6
	# ADD THE INNER PADDING HERE - this was missing!
	bg_style.content_margin_left = 12
	bg_style.content_margin_right = 12
	bg_style.content_margin_top = 6
	bg_style.content_margin_bottom = 6
	
	filter_options.add_theme_stylebox_override("normal", bg_style)
	filter_options.add_theme_stylebox_override("hover", bg_style)
	filter_options.add_theme_stylebox_override("pressed", bg_style)
	filter_options.add_theme_stylebox_override("focus", bg_style)
	
	# Make sure it's not flat
	filter_options.flat = false
	
	# Force redraw
	filter_options.queue_redraw()
	
	# Also style the sort button the same way WITH PROPER PADDING
	sort_button.modulate = Color(1.5, 1.5, 1.5, 1.0)
	sort_button.add_theme_color_override("font_color", Color.WHITE)
	var sort_bg_style = StyleBoxFlat.new()
	sort_bg_style.bg_color = Color.WHITE * 0.4  # 40% white
	sort_bg_style.border_width_left = 1
	sort_bg_style.border_width_right = 1
	sort_bg_style.border_width_top = 1
	sort_bg_style.border_width_bottom = 1
	sort_bg_style.border_color = Color.WHITE * 0.6
	# ADD THE INNER PADDING HERE TOO - this was missing!
	sort_bg_style.content_margin_left = 12
	sort_bg_style.content_margin_right = 12
	sort_bg_style.content_margin_top = 6
	sort_bg_style.content_margin_bottom = 6
	
	sort_button.add_theme_stylebox_override("normal", sort_bg_style)
	sort_button.add_theme_stylebox_override("hover", sort_bg_style)
	sort_button.add_theme_stylebox_override("pressed", sort_bg_style)
	sort_button.add_theme_stylebox_override("focus", sort_bg_style)
	sort_button.flat = false
	sort_button.queue_redraw()

func _on_search_text_changed(new_text: String):
	search_changed.emit(new_text)

func _on_filter_button_pressed():
	# Show dropdown at button position
	var button_pos = filter_options.get_screen_position()
	var dropdown_pos = Vector2(button_pos.x, button_pos.y + filter_options.size.y)
	
	# Temporarily add dropdown to scene so it can access viewport
	get_viewport().add_child(filter_dropdown)
	filter_dropdown.show_menu(dropdown_pos)

func _on_filter_dropdown_selected(item_id: String, item_data: Dictionary):
	# Extract index from item_id (format: "filter_0", "filter_1", etc.)
	var index_str = item_id.replace("filter_", "")
	var index = int(index_str)
	
	if index >= 0 and index < filter_items.size():
		current_filter_index = index
		filter_options.text = filter_items[index] + " ▼"
		filter_changed.emit(index)

func _on_sort_button_pressed():
	# Show dropdown at button position
	var button_pos = sort_button.get_screen_position()
	var dropdown_pos = Vector2(button_pos.x, button_pos.y + sort_button.size.y)
	
	# Temporarily add dropdown to scene so it can access viewport
	get_viewport().add_child(sort_dropdown)
	sort_dropdown.show_menu(dropdown_pos)

func _on_sort_dropdown_selected(item_id: String, item_data: Dictionary):
	# Extract index from item_id (format: "sort_0", "sort_1", etc.)
	var index_str = item_id.replace("sort_", "")
	var index = int(index_str)
	
	if index >= 0 and index < sort_items.size():
		current_sort_index = index
		sort_button.text = sort_items[index] + " ▼"
		var sort_type = index as InventoryManager.SortType
		sort_requested.emit(sort_type)

func _on_filter_dropdown_closed():
	# Remove filter dropdown from scene when it closes
	if filter_dropdown and filter_dropdown.get_parent():
		filter_dropdown.get_parent().remove_child(filter_dropdown)

func _on_sort_dropdown_closed():
	# Remove sort dropdown from scene when it closes
	if sort_dropdown and sort_dropdown.get_parent():
		sort_dropdown.get_parent().remove_child(sort_dropdown)

func _on_sort_selected(id: int):
	# No longer needed since we're using DropDownMenu_Base
	pass

# Public interface
func set_inventory_manager(manager: InventoryManager):
	inventory_manager = manager

func set_inventory_window(window: Window):
	inventory_window = window

func get_search_text() -> String:
	return search_field.text

func get_filter_index() -> int:
	return current_filter_index

func clear_search():
	search_field.text = ""

func set_transparency(transparency: float):
	current_transparency = transparency
	modulate.a = transparency
