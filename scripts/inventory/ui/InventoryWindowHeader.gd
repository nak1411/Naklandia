# InventoryWindowHeader.gd - Header controls for inventory window
class_name InventoryWindowHeader
extends HBoxContainer

# UI Components
var search_field: LineEdit
var filter_options: OptionButton
var sort_button: MenuButton
var transparency_button: Button
var lock_button: Button

# Transparency controls
var transparency_popup: PopupPanel
var transparency_slider: HSlider
var transparency_label: Label

# References
var inventory_manager: InventoryManager
var inventory_window: Window

# Signals
signal search_changed(text: String)
signal filter_changed(filter_type: int)
signal sort_requested(sort_type: InventoryManager.SortType)
signal transparency_changed(value: float)
signal lock_toggled(is_locked: bool)

# State
var is_window_locked: bool = false
var current_transparency: float = 1.0

func _ready():
	custom_minimum_size.y = 40
	_setup_controls()
	_connect_signals()

func _setup_controls():
	# Add spacing
	var left_spacer = Control.new()
	left_spacer.custom_minimum_size.x = 8
	add_child(left_spacer)
	
	# Search field
	search_field = LineEdit.new()
	search_field.placeholder_text = "Search items..."
	search_field.custom_minimum_size.x = 150
	add_child(search_field)
	
	# Filter options
	filter_options = OptionButton.new()
	_populate_filter_options()
	filter_options.custom_minimum_size.x = 120
	add_child(filter_options)
	
	# Sort button
	sort_button = MenuButton.new()
	sort_button.text = "Sort"
	_populate_sort_menu()
	add_child(sort_button)
	
	# Transparency button
	transparency_button = Button.new()
	transparency_button.text = "🔍"  # Use transparency icon
	transparency_button.tooltip_text = "Adjust window transparency"
	transparency_button.custom_minimum_size.x = 32
	add_child(transparency_button)
	
	# Lock button
	lock_button = Button.new()
	lock_button.text = "🔓"  # Unlocked icon
	lock_button.tooltip_text = "Lock/unlock window position"
	lock_button.custom_minimum_size.x = 32
	add_child(lock_button)
	
	# Right spacer
	var right_spacer = Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right_spacer)
	
	_setup_transparency_popup()

func _setup_transparency_popup():
	transparency_popup = PopupPanel.new()
	transparency_popup.name = "TransparencyPopup"
	add_child(transparency_popup)
	
	var popup_container = VBoxContainer.new()
	popup_container.custom_minimum_size = Vector2(200, 80)
	popup_container.add_theme_constant_override("separation", 8)
	transparency_popup.add_child(popup_container)
	
	# Label
	transparency_label = Label.new()
	transparency_label.text = "Transparency: 100%"
	transparency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_container.add_child(transparency_label)
	
	# Slider
	transparency_slider = HSlider.new()
	transparency_slider.min_value = 0.1
	transparency_slider.max_value = 1.0
	transparency_slider.step = 0.01
	transparency_slider.value = 1.0
	transparency_slider.custom_minimum_size.x = 180
	popup_container.add_child(transparency_slider)
	
	# Buttons container
	var button_container = HBoxContainer.new()
	button_container.add_theme_constant_override("separation", 4)
	popup_container.add_child(button_container)
	
	var reset_button = Button.new()
	reset_button.text = "Reset"
	reset_button.custom_minimum_size.x = 60
	button_container.add_child(reset_button)
	
	var close_button = Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size.x = 60
	button_container.add_child(close_button)
	
	# Connect popup signals
	transparency_slider.value_changed.connect(_on_transparency_slider_changed)
	reset_button.pressed.connect(_on_transparency_reset)
	close_button.pressed.connect(_on_transparency_popup_close)

func _populate_filter_options():
	filter_options.add_item("All Items")
	filter_options.add_item("Weapons")
	filter_options.add_item("Armor")
	filter_options.add_item("Consumables")
	filter_options.add_item("Resources")
	filter_options.add_item("Blueprints")
	filter_options.add_item("Modules")
	filter_options.add_item("Ships")
	filter_options.add_item("Containers")
	filter_options.add_item("Ammunition")
	filter_options.add_item("Implants")
	filter_options.add_item("Skill Books")

func _populate_sort_menu():
	var sort_popup = sort_button.get_popup()
	sort_popup.add_item("By Name")
	sort_popup.add_item("By Type")
	sort_popup.add_item("By Value")
	sort_popup.add_item("By Volume")
	sort_popup.add_item("By Rarity")

func _connect_signals():
	search_field.text_changed.connect(_on_search_text_changed)
	filter_options.item_selected.connect(_on_filter_changed)
	sort_button.get_popup().id_pressed.connect(_on_sort_selected)
	transparency_button.pressed.connect(_on_transparency_button_pressed)
	lock_button.pressed.connect(_on_lock_button_pressed)

func _on_search_text_changed(new_text: String):
	search_changed.emit(new_text)

func _on_filter_changed(index: int):
	filter_changed.emit(index)

func _on_sort_selected(id: int):
	var sort_type = id as InventoryManager.SortType
	sort_requested.emit(sort_type)

func _on_transparency_button_pressed():
	if transparency_popup.visible:
		transparency_popup.hide()
	else:
		# Position popup below the button
		var button_rect = transparency_button.get_global_rect()
		transparency_popup.position = Vector2(
			button_rect.position.x - 90,  # Center under button
			button_rect.position.y + button_rect.size.y + 5
		)
		transparency_popup.popup()

func _on_lock_button_pressed():
	is_window_locked = not is_window_locked
	_update_lock_button_appearance()
	lock_toggled.emit(is_window_locked)

func _on_transparency_slider_changed(value: float):
	current_transparency = value
	transparency_label.text = "Transparency: %d%%" % int(value * 100)
	transparency_changed.emit(value)

func _on_transparency_reset():
	transparency_slider.value = 1.0
	_on_transparency_slider_changed(1.0)

func _on_transparency_popup_close():
	transparency_popup.hide()

func _update_lock_button_appearance():
	if is_window_locked:
		lock_button.text = "🔒"  # Locked icon
		lock_button.tooltip_text = "Window is locked - click to unlock"
		lock_button.modulate = Color.YELLOW
	else:
		lock_button.text = "🔓"  # Unlocked icon
		lock_button.tooltip_text = "Window is unlocked - click to lock"
		lock_button.modulate = Color.WHITE

# Public interface
func set_inventory_manager(manager: InventoryManager):
	inventory_manager = manager

func set_inventory_window(window: Window):
	inventory_window = window

func get_search_text() -> String:
	return search_field.text

func get_filter_index() -> int:
	return filter_options.selected

func set_transparency(value: float):
	current_transparency = value
	transparency_slider.value = value
	transparency_label.text = "Transparency: %d%%" % int(value * 100)

func get_transparency() -> float:
	return current_transparency

func set_window_locked(locked: bool):
	is_window_locked = locked
	_update_lock_button_appearance()

func is_locked() -> bool:
	return is_window_locked
