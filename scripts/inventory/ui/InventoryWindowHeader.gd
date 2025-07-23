# InventoryWindowHeader.gd - Header controls for inventory window
class_name InventoryWindowHeader
extends HBoxContainer

# UI Components
var container_selector: OptionButton
var search_field: LineEdit
var filter_options: OptionButton
var sort_button: MenuButton

# References
var inventory_manager: InventoryManager
var open_containers: Array[InventoryContainer] = []

# Signals
signal container_changed(container: InventoryContainer)
signal search_changed(text: String)
signal filter_changed(filter_type: int)
signal sort_requested(sort_type: InventoryManager.SortType)

func _ready():
	custom_minimum_size.y = 40
	_setup_controls()
	_connect_signals()

func _setup_controls():
	# Add spacing
	var left_spacer = Control.new()
	left_spacer.custom_minimum_size.x = 8
	add_child(left_spacer)
	
	# Container selector
	container_selector = OptionButton.new()
	container_selector.custom_minimum_size.x = 150
	container_selector.selected = -1
	add_child(container_selector)
	
	# Search field
	search_field = LineEdit.new()
	search_field.placeholder_text = "Search items..."
	search_field.custom_minimum_size.x = 120
	add_child(search_field)
	
	# Filter options
	filter_options = OptionButton.new()
	_populate_filter_options()
	filter_options.custom_minimum_size.x = 100
	add_child(filter_options)
	
	# Sort button
	sort_button = MenuButton.new()
	sort_button.text = "Sort"
	_populate_sort_menu()
	add_child(sort_button)
	
	# Right spacer
	var right_spacer = Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right_spacer)

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
	container_selector.item_selected.connect(_on_container_selector_changed)
	search_field.text_changed.connect(_on_search_text_changed)
	filter_options.item_selected.connect(_on_filter_changed)
	sort_button.get_popup().id_pressed.connect(_on_sort_selected)

func _on_container_selector_changed(index: int):
	if index >= 0 and index < open_containers.size():
		container_changed.emit(open_containers[index])

func _on_search_text_changed(new_text: String):
	search_changed.emit(new_text)

func _on_filter_changed(index: int):
	filter_changed.emit(index)

func _on_sort_selected(id: int):
	var sort_type = id as InventoryManager.SortType
	sort_requested.emit(sort_type)

# Public interface
func set_inventory_manager(manager: InventoryManager):
	inventory_manager = manager

func update_containers(containers: Array[InventoryContainer]):
	open_containers = containers
	
	for container in containers:
		var total_qty = container.get_total_quantity()
		var unique_items = container.get_item_count()
		
		var container_text = container.container_name

func select_container_index(index: int):
	if index >= 0 and index < open_containers.size():
		container_selector.selected = index

func get_selected_container_index() -> int:
	return container_selector.selected

func get_search_text() -> String:
	return search_field.text

func get_filter_index() -> int:
	return filter_options.selected
