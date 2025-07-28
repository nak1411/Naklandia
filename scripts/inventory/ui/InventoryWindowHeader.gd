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

# References
var inventory_manager: InventoryManager
var inventory_window: Window

# Signals
signal search_changed(text: String)
signal filter_changed(filter_type: int)
signal sort_requested(sort_type: InventoryManager.SortType)

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
	"By Name", "By Type", "By Value", "By Volume", "By Rarity"
]
var current_sort_index = 0

func _ready():
	print("InventoryWindowHeader _ready() starting...")
	custom_minimum_size.y = 35  # Reduced height to not overlap title bar
	_setup_controls()
	_connect_signals()
	_remove_default_outlines()
	_apply_custom_theme()
	# Force styling after everything is set up
	call_deferred("_force_button_styling")
	print("InventoryWindowHeader _ready() completed")

func _setup_controls():
	print("Setting up header controls...")
	
	# Create filter button (regular Button)
	filter_options = Button.new()
	filter_options.name = "FilterButton"
	filter_options.text = "All Items ▼"
	filter_options.custom_minimum_size.x = 120
	filter_options.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_custom_filter_button()
	add_child(filter_options)
	
	# Sort button (regular Button)
	sort_button = Button.new()
	sort_button.name = "SortButton"
	sort_button.text = "Sort ▼"
	sort_button.custom_minimum_size.x = 80
	sort_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_custom_sort_button()
	add_child(sort_button)
	
	# Spacer to push search field to the right
	var spacer = Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(spacer)
	
	# Search field - now on the right side
	search_field = LineEdit.new()
	search_field.name = "SearchField"
	search_field.placeholder_text = "Search items..."
	search_field.custom_minimum_size.x = 150
	add_child(search_field)
	
	# Right margin spacer
	var right_margin = Control.new()
	right_margin.name = "RightMargin"
	right_margin.custom_minimum_size.x = 8
	add_child(right_margin)
	
	# Create dropdown menus (don't add as children initially)
	_create_dropdown_menus()
	
	print("Header controls setup completed")

func _create_dropdown_menus():
	print("Creating dropdown menus...")
	
	# Create filter dropdown
	filter_dropdown = DropDownMenu_Base.new()
	filter_dropdown.name = "FilterDropdown"
	_setup_filter_dropdown()
	
	# Create sort dropdown
	sort_dropdown = DropDownMenu_Base.new()
	sort_dropdown.name = "SortDropdown"
	_setup_sort_dropdown()
	
	print("Dropdown menus created")

func _setup_filter_dropdown():
	print("Setting up filter dropdown with ", filter_items.size(), " items")
	
	# Add all filter items to dropdown
	for i in range(filter_items.size()):
		var item_id = "filter_" + str(i)
		filter_dropdown.add_menu_item(item_id, filter_items[i])
		print("Added filter item: ", item_id, " -> ", filter_items[i])
	
	# Connect selection signal
	if filter_dropdown.has_signal("item_selected"):
		filter_dropdown.item_selected.connect(_on_filter_dropdown_selected)
	
	# Connect menu close signal
	if filter_dropdown.has_signal("tree_exiting"):
		filter_dropdown.tree_exiting.connect(_on_filter_dropdown_closed)

func _setup_sort_dropdown():
	print("Setting up sort dropdown with ", sort_items.size(), " items")
	
	# Add all sort items to dropdown
	for i in range(sort_items.size()):
		var item_id = "sort_" + str(i)
		sort_dropdown.add_menu_item(item_id, sort_items[i])
		print("Added sort item: ", item_id, " -> ", sort_items[i])
	
	# Connect selection signal
	if sort_dropdown.has_signal("item_selected"):
		sort_dropdown.item_selected.connect(_on_sort_dropdown_selected)
	
	# Connect menu close signal
	if sort_dropdown.has_signal("tree_exiting"):
		sort_dropdown.tree_exiting.connect(_on_sort_dropdown_closed)

func _style_custom_filter_button():
	print("Styling filter button...")
	
	# Make the button NOT flat so it can show styling
	filter_options.flat = false
	
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
	filter_options.add_theme_stylebox_override("normal", style_normal)
	filter_options.add_theme_stylebox_override("hover", style_hover)
	filter_options.add_theme_stylebox_override("pressed", style_hover)
	filter_options.add_theme_stylebox_override("focus", style_normal)
	filter_options.add_theme_color_override("font_color", Color.WHITE)

func _style_custom_sort_button():
	print("Styling sort button...")
	
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
	print("Connecting header signals...")
	
	if search_field:
		search_field.text_changed.connect(_on_search_text_changed)
		print("Connected search field signal")
	
	if filter_options:
		filter_options.pressed.connect(_on_filter_button_pressed)
		print("Connected filter button signal")
	
	if sort_button:
		sort_button.pressed.connect(_on_sort_button_pressed)
		print("Connected sort button signal")

func _remove_default_outlines():
	print("Removing default outlines...")
	
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
	print("Applying custom theme...")
	
	# Create a theme for the entire header
	var header_theme = Theme.new()
	
	# Apply theme to the header container
	set_theme(header_theme)

func _force_button_styling():
	print("Forcing button styling...")
	
	# Make sure buttons are visible
	if filter_options:
		filter_options.modulate = Color(1.0, 1.0, 1.0, 1.0)
		filter_options.queue_redraw()
	
	if sort_button:
		sort_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
		sort_button.queue_redraw()

# Signal handlers
func _on_search_text_changed(new_text: String):
	print("Search text changed: ", new_text)
	search_changed.emit(new_text)

func _on_filter_button_pressed():
	print("Filter button pressed")
	
	if not filter_dropdown:
		print("ERROR: No filter dropdown!")
		return
		
	# Show dropdown at button position
	var button_pos = filter_options.get_screen_position()
	var dropdown_pos = Vector2(button_pos.x, button_pos.y + filter_options.size.y)
	
	print("Showing filter dropdown at position: ", dropdown_pos)
	
	# Add dropdown to scene so it can access viewport
	get_viewport().add_child(filter_dropdown)
	
	# Show the menu
	if filter_dropdown.has_method("show_menu"):
		filter_dropdown.show_menu(dropdown_pos)
	else:
		print("ERROR: Filter dropdown doesn't have show_menu method!")

func _on_filter_dropdown_selected(item_id: String, item_data: Dictionary):
	print("Filter dropdown selected: ", item_id)
	
	# Extract index from item_id (format: "filter_0", "filter_1", etc.)
	var index_str = item_id.replace("filter_", "")
	var index = int(index_str)
	
	if index >= 0 and index < filter_items.size():
		current_filter_index = index
		filter_options.text = filter_items[index] + " ▼"
		print("Filter changed to: ", filter_items[index])
		filter_changed.emit(index)
	else:
		print("ERROR: Invalid filter index: ", index)

func _on_sort_button_pressed():
	print("Sort button pressed")
	
	if not sort_dropdown:
		print("ERROR: No sort dropdown!")
		return
		
	# Show dropdown at button position
	var button_pos = sort_button.get_screen_position()
	var dropdown_pos = Vector2(button_pos.x, button_pos.y + sort_button.size.y)
	
	print("Showing sort dropdown at position: ", dropdown_pos)
	
	# Add dropdown to scene so it can access viewport
	get_viewport().add_child(sort_dropdown)
	
	# Show the menu
	if sort_dropdown.has_method("show_menu"):
		sort_dropdown.show_menu(dropdown_pos)
	else:
		print("ERROR: Sort dropdown doesn't have show_menu method!")

func _on_sort_dropdown_selected(item_id: String, item_data: Dictionary):
	print("Sort dropdown selected: ", item_id)
	
	# Extract index from item_id (format: "sort_0", "sort_1", etc.)
	var index_str = item_id.replace("sort_", "")
	var index = int(index_str)
	
	if index >= 0 and index < sort_items.size():
		current_sort_index = index
		sort_button.text = sort_items[index] + " ▼"
		print("Sort changed to: ", sort_items[index])
		
		# Convert to InventoryManager.SortType
		var sort_type = index as InventoryManager.SortType
		sort_requested.emit(sort_type)
	else:
		print("ERROR: Invalid sort index: ", index)

func _on_filter_dropdown_closed():
	print("Filter dropdown closed")
	# Remove filter dropdown from scene when it closes
	if filter_dropdown and filter_dropdown.get_parent():
		filter_dropdown.get_parent().remove_child(filter_dropdown)

func _on_sort_dropdown_closed():
	print("Sort dropdown closed")
	# Remove sort dropdown from scene when it closes
	if sort_dropdown and sort_dropdown.get_parent():
		sort_dropdown.get_parent().remove_child(sort_dropdown)

# Public interface
func set_inventory_manager(manager: InventoryManager):
	print("Setting inventory manager on header: ", manager)
	inventory_manager = manager

func set_inventory_window(window: Window):
	print("Setting inventory window on header: ", window)
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
		print("Search field cleared")

# Debug method
func debug_header_state():
	print("\n=== INVENTORY HEADER DEBUG ===")
	print("search_field: ", search_field)
	print("filter_options: ", filter_options)
	print("sort_button: ", sort_button)
	print("filter_dropdown: ", filter_dropdown)
	print("sort_dropdown: ", sort_dropdown)
	print("inventory_manager: ", inventory_manager)
	print("inventory_window: ", inventory_window)
	print("current_filter_index: ", current_filter_index)
	print("current_sort_index: ", current_sort_index)
	
	if filter_options:
		print("Filter button text: ", filter_options.text)
		print("Filter button visible: ", filter_options.visible)
		print("Filter button size: ", filter_options.size)
	
	if sort_button:
		print("Sort button text: ", sort_button.text)
		print("Sort button visible: ", sort_button.visible)
		print("Sort button size: ", sort_button.size)
	
	print("=== END HEADER DEBUG ===\n")

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
	print("Storing original header styles...")
	
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
