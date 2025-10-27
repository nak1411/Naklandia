extends Node

signal notification_shown(message: String, type: String)
signal notification_hidden

const NOTIFICATION_PANEL = preload("res://scenes/ui/notification_panel.tscn")

const MAX_NOTIFICATIONS = 5
const NOTIFICATION_SPACING = 10

var notification_container: VBoxContainer
var canvas_layer: CanvasLayer
var active_notifications: Array = []


func _ready():
	_setup_ui()


func _setup_ui():
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100
	add_child(canvas_layer)

	notification_container = VBoxContainer.new()
	notification_container.name = "NotificationContainer"
	notification_container.anchor_left = 0.0
	notification_container.anchor_right = 0.0
	notification_container.anchor_top = 0.0
	notification_container.anchor_bottom = 0.0
	notification_container.offset_left = 20
	notification_container.offset_right = 320
	notification_container.offset_top = 20
	notification_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	notification_container.add_theme_constant_override("separation", NOTIFICATION_SPACING)
	canvas_layer.add_child(notification_container)


func show_notification(message: String, notification_type: String = "info", duration: float = 3.0):
	if active_notifications.size() >= MAX_NOTIFICATIONS:
		_remove_oldest_notification()

	var notification_panel = NOTIFICATION_PANEL.instantiate()
	notification_container.add_child(notification_panel)
	active_notifications.append(notification_panel)

	notification_panel.setup(message, notification_type, duration)
	notification_panel.notification_finished.connect(_on_notification_finished.bind(notification_panel))

	notification_shown.emit(message, notification_type)


func show_item_pickup(item_name: String, quantity: int = 1):
	var message = "%s x%d" % [item_name, quantity] if quantity > 1 else item_name
	show_notification(message, "item", 2.5)


func show_item_crafted(item_name: String, quantity: int = 1):
	var message = "%s x%d" % [item_name, quantity] if quantity > 1 else item_name
	show_notification(message, "crafted", 2.5)


func show_success(message: String, duration: float = 2.5):
	show_notification(message, "success", duration)


func show_warning(message: String, duration: float = 3.0):
	show_notification(message, "warning", duration)


func show_error(message: String, duration: float = 3.5):
	show_notification(message, "error", duration)


func show_info(message: String, duration: float = 2.5):
	show_notification(message, "info", duration)


func _remove_oldest_notification():
	if active_notifications.is_empty():
		return

	var oldest = active_notifications[0]
	if is_instance_valid(oldest):
		oldest.force_close()


func _on_notification_finished(notification_panel: Control):
	if notification_panel in active_notifications:
		active_notifications.erase(notification_panel)

	if is_instance_valid(notification_panel):
		notification_panel.queue_free()

	notification_hidden.emit()
