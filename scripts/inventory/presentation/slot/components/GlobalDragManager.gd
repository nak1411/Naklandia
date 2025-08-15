# GlobalDragManager.gd - Manages drag operations across multiple windows
class_name GlobalDragManager
extends RefCounted

static var instance: GlobalDragManager = null
static var current_drag_data: Dictionary = {}
static var is_dragging: bool = false
static var drag_preview: Control = null
static var drag_canvas: CanvasLayer = null


static func get_instance() -> GlobalDragManager:
	if not instance:
		instance = GlobalDragManager.new()
	return instance


static func start_drag(data: Dictionary, preview: Control = null):
	"""Start a global drag operation"""
	current_drag_data = data
	is_dragging = true

	if preview:
		_setup_global_drag_preview(preview)


static func _setup_global_drag_preview(preview: Control):
	"""Setup a global drag preview that follows the mouse"""
	if drag_canvas:
		drag_canvas.queue_free()

	# Create a high-layer canvas for the drag preview
	drag_canvas = CanvasLayer.new()
	drag_canvas.name = "GlobalDragCanvas"
	drag_canvas.layer = 1000  # Very high layer

	# Add to scene root so it appears over all windows
	var scene_tree = Engine.get_singleton("SceneTree") as SceneTree
	if scene_tree and scene_tree.current_scene:
		scene_tree.current_scene.add_child(drag_canvas)

		# Clone the preview
		drag_preview = preview.duplicate()
		drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		drag_canvas.add_child(drag_preview)

		# Start following the mouse
		_start_mouse_follow()


static func _start_mouse_follow():
	"""Start a process to make the preview follow the mouse"""
	if not drag_canvas:
		return

	# Connect to the scene tree's process frame
	var scene_tree = Engine.get_singleton("SceneTree") as SceneTree
	if scene_tree:
		scene_tree.process_frame.connect(_update_drag_preview_position, CONNECT_ONE_SHOT)


static func _update_drag_preview_position():
	"""Update drag preview position to follow mouse"""
	if not is_dragging or not drag_preview:
		return

	# Get global mouse position
	var mouse_pos = DisplayServer.mouse_get_position()

	# Convert to local coordinates relative to the scene
	var scene_tree = Engine.get_singleton("SceneTree") as SceneTree
	if scene_tree and scene_tree.current_scene:
		var viewport = scene_tree.current_scene.get_viewport()
		if viewport:
			var local_mouse = viewport.get_screen_transform().affine_inverse() * mouse_pos
			drag_preview.global_position = local_mouse + Vector2(10, 10)  # Offset from cursor

	# Continue following if still dragging
	if is_dragging:
		scene_tree.process_frame.connect(_update_drag_preview_position, CONNECT_ONE_SHOT)


static func end_drag() -> Dictionary:
	"""End the global drag operation and return the drag data"""
	var data = current_drag_data.duplicate()

	current_drag_data.clear()
	is_dragging = false

	if drag_canvas:
		drag_canvas.queue_free()
		drag_canvas = null
	drag_preview = null

	return data


static func get_drag_data() -> Dictionary:
	"""Get current drag data"""
	return current_drag_data.duplicate()


static func is_drag_active() -> bool:
	"""Check if a drag is currently active"""
	return is_dragging
