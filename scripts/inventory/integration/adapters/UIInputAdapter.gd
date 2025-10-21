# integration/adapters/UIInputAdapter.gd
# Interface between inventory system and UI input
class_name UIInputAdapter
extends Node

var event_bus: InventoryEventBus
var connected_ui_manager: UIManager
var input_mode: String = "game"  # "game", "inventory", "menu"

var drag_in_progress: bool = false
var input_processing_enabled: bool = true


func _ready():
	name = "UIInputAdapter"


func setup_event_connections(bus: InventoryEventBus):
	"""Connect this adapter to the event bus"""
	event_bus = bus

	# Listen for UI-related events
	if event_bus:
		event_bus.inventory_opened.connect(_on_inventory_opened)
		event_bus.inventory_closed.connect(_on_inventory_closed)
		event_bus.ui_focus_changed.connect(_on_ui_focus_changed)


func connect_to_ui_manager(ui_manager: UIManager):
	"""Connect to the UI management system"""
	connected_ui_manager = ui_manager

	# Connect to UI manager signals if they exist
	if ui_manager.has_signal("layer_visibility_changed"):
		ui_manager.layer_visibility_changed.connect(_on_layer_visibility_changed)


func _input(event):
	"""Handle input events and route them appropriately"""
	if not event is InputEventKey or not input_processing_enabled:
		return

	# Check if any LineEdit (like search field) has focus
	var focused_control = get_viewport().gui_get_focus_owner()
	if focused_control is LineEdit:
		# Don't handle inventory toggle when text input is active
		return

	# Check if map is open and prevent inventory toggle
	if event.is_action_pressed("toggle_inventory"):
		# Check if map is currently open
		var map_managers = get_tree().get_nodes_in_group("map_manager")
		if map_managers.size() > 0:
			var map_manager = map_managers[0]
			if map_manager.has_method("is_map_open") and map_manager.is_map_open():
				# Map is open - don't allow inventory to open
				return
			# Alternative check if is_map_open method doesn't exist
			if map_manager.full_map and map_manager.full_map.is_map_open:
				# Map is open - don't allow inventory to open
				return

		if event_bus:
			# Check if main inventory window is currently open
			var integration = _find_inventory_integration()
			if integration and integration.is_inventory_window_open():
				# Main inventory is open - close it
				event_bus.emit_inventory_closed()
			else:
				# Main inventory is closed - open it
				event_bus.emit_inventory_opened()

		get_viewport().set_input_as_handled()


func _find_inventory_integration():
	"""Find the inventory integration node"""
	var integrations = get_tree().get_nodes_in_group("inventory_integration")
	if integrations.size() > 0:
		return integrations[0]
	return null


func _on_inventory_opened():
	"""Handle inventory opened event"""
	input_mode = "inventory"


func _on_inventory_closed():
	"""Handle inventory closed event"""
	input_mode = "game"


func _on_ui_focus_changed(_has_focus: bool):
	"""Handle UI focus changes"""
	pass


func _on_layer_visibility_changed(_layer_name: String, _visible: bool):
	"""Handle layer visibility changes from UI manager"""
	pass


func set_input_processing_enabled(enabled: bool):
	"""Enable or disable input processing"""
	input_processing_enabled = enabled


func is_drag_in_progress() -> bool:
	"""Check if a drag operation is in progress"""
	return drag_in_progress


func set_drag_in_progress(dragging: bool):
	"""Set drag in progress state"""
	drag_in_progress = dragging
