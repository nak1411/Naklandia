# InventorySlot.gd - Simplified main slot class using component system
class_name InventorySlot
extends Control

# Core properties
@export var slot_size: Vector2 = Vector2(96, 96)
var item: InventoryItem_Base
var grid_position: Vector2i
var container_id: String
var slot_padding: int = 8

# Component systems
var visuals: InventorySlotVisualManager
var drag_handler: InventorySlotDragHandler
var tooltip_manager: InventorySlotTooltipManager

# State (simplified)
var is_highlighted: bool = false
var is_selected: bool = false
var is_hovered: bool = false

# Signals
signal slot_clicked(slot: InventorySlot, event: InputEvent)
signal slot_right_clicked(slot: InventorySlot, event: InputEvent)
signal item_drag_started(slot: InventorySlot, item: InventoryItem_Base)
signal item_drag_ended(slot: InventorySlot, success: bool)

func _init():
	custom_minimum_size = slot_size
	size = slot_size

func _ready():
	_setup_components()
	_connect_signals()

func _setup_components():
	"""Initialize all component systems"""
	visuals = InventorySlotVisualManager.new(self)
	drag_handler = InventorySlotDragHandler.new(self)
	tooltip_manager = InventorySlotTooltipManager.new(self)
	
	visuals.setup_visual_components()
	tooltip_manager.setup_tooltip()
	
	# Connect drag handler signals
	drag_handler.drag_started.connect(_on_drag_started)
	drag_handler.drag_ended.connect(_on_drag_ended)

func _connect_signals():
	"""Connect internal signals"""
	mouse_filter = Control.MOUSE_FILTER_PASS
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _process(delta):
	"""Process component updates"""
	tooltip_manager.process_tooltip_timer(delta)

func _on_gui_input(event: InputEvent):
	"""Handle input events - delegate to appropriate handlers"""
	if drag_handler.should_handle_input(event):
		if event is InputEventMouseButton:
			drag_handler.handle_mouse_button(event)
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				slot_clicked.emit(self, event)
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				slot_right_clicked.emit(self, event)
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion:
			drag_handler.handle_mouse_motion(event)
	else:
		# Handle non-drag inputs
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				slot_clicked.emit(self, event)
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				slot_right_clicked.emit(self, event)
				get_viewport().set_input_as_handled()

func _on_mouse_entered():
	"""Handle mouse enter"""
	is_hovered = true
	tooltip_manager.start_tooltip_timer()

func _on_mouse_exited():
	"""Handle mouse exit"""
	is_hovered = false
	tooltip_manager.hide_tooltip()

func _on_drag_started(source_slot: InventorySlot, drag_item: InventoryItem_Base):
	"""Handle drag started"""
	item_drag_started.emit(source_slot, drag_item)

func _on_drag_ended(source_slot: InventorySlot, success: bool):
	"""Handle drag ended"""
	item_drag_ended.emit(source_slot, success)

# Public API (simplified)
func set_item(new_item: InventoryItem_Base):
	"""Set the item for this slot"""
	item = new_item
	visuals.update_item_display()

func clear_item():
	"""Clear the item from this slot"""
	item = null
	visuals.update_item_display()

func get_item() -> InventoryItem_Base:
	return item

func has_item() -> bool:
	return item != null

func set_highlighted(highlighted: bool):
	"""Set highlight state"""
	is_highlighted = highlighted
	visuals.update_visual_state(is_highlighted, is_selected, has_item())

func set_selected(selected: bool):
	"""Set selection state"""
	is_selected = selected
	visuals.update_visual_state(is_highlighted, is_selected, has_item())

func set_grid_position(pos: Vector2i):
	"""Set grid position"""
	grid_position = pos

func set_container_id(id: String):
	"""Set container ID"""
	container_id = id

func force_visual_refresh():
	"""Force a complete visual refresh"""
	visuals.force_visual_refresh()

func cleanup():
	"""Clean up all components"""
	if visuals:
		visuals.cleanup()
	if drag_handler:
		drag_handler.cleanup()
	if tooltip_manager:
		tooltip_manager.cleanup()

func _exit_tree():
	"""Clean up when slot is removed"""
	cleanup()

# Legacy methods for compatibility with existing code
func _attempt_drop_on_slot(target_slot: InventorySlot) -> bool:
	"""Legacy method - delegate to existing implementation"""
	# This would contain the existing drop logic
	# Keep this for now to maintain compatibility
	pass

func _attempt_drop_on_container_list(end_position: Vector2) -> bool:
	"""Legacy method - delegate to existing implementation"""
	# This would contain the existing container list drop logic
	# Keep this for now to maintain compatibility
	pass