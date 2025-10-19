extends Node

# Map action name
const MAP_ACTION = "toggle_map"

# References
var minimap_layer: CanvasLayer
var map_layer: CanvasLayer
var minimap: Control
var full_map: Control


func _ready():
	_setup_input_actions()
	_setup_minimap_layer()
	_setup_map_layer()


func _setup_input_actions():
	if not InputMap.has_action(MAP_ACTION):
		InputMap.add_action(MAP_ACTION)
		var event = InputEventKey.new()
		event.keycode = KEY_M
		InputMap.action_add_event(MAP_ACTION, event)


func _setup_minimap_layer():
	minimap_layer = CanvasLayer.new()
	minimap_layer.name = "MinimapLayer"
	minimap_layer.layer = 100
	add_child(minimap_layer)

	var Minimap = load("res://scripts/ui/map/Minimap.gd")
	minimap = Minimap.new()
	minimap.name = "Minimap"

	minimap.position = Vector2(get_viewport().get_visible_rect().size.x - 220, 20)

	minimap_layer.add_child(minimap)


func _setup_map_layer():
	map_layer = CanvasLayer.new()
	map_layer.name = "MapLayer"
	map_layer.layer = 99
	add_child(map_layer)

	var MapUI = load("res://scripts/ui/map/MapUI.gd")
	full_map = MapUI.new()
	full_map.name = "MapUI"
	full_map.anchor_right = 1.0
	full_map.anchor_bottom = 1.0

	map_layer.add_child(full_map)

	if full_map.has_signal("map_closed"):
		full_map.map_closed.connect(_on_map_closed)
	if full_map.has_signal("map_opened"):
		full_map.map_opened.connect(_on_map_opened)


func _input(event):
	if event.is_action_pressed(MAP_ACTION):
		toggle_map()
		get_viewport().set_input_as_handled()


func toggle_map():
	if full_map:
		full_map.toggle_map()


func open_map():
	if full_map:
		full_map.open_map()


func close_map():
	if full_map:
		full_map.close_map()


func _on_map_opened():
	if minimap:
		minimap.visible = false
	_set_player_input_enabled(false)


func _on_map_closed():
	if minimap:
		minimap.visible = true
	_set_player_input_enabled(true)


func _set_player_input_enabled(enabled: bool):
	var player_node = get_tree().get_first_node_in_group("player")
	if player_node:
		if enabled:
			player_node.set_process_mode(PROCESS_MODE_INHERIT)
		else:
			player_node.set_process_mode(PROCESS_MODE_DISABLED)


func set_minimap_visible(is_visible: bool):
	if minimap:
		minimap.visible = is_visible


func set_minimap_zoom(zoom: float):
	if minimap and minimap.has_method("set_zoom"):
		minimap.set_zoom(zoom)
