# WorkbenchWindow_Base.gd - Assembly Workbench window using Window_Base system
class_name WorkbenchWindow_Base
extends Window_Base

# Reference to the workbench content (the original WorkbenchWindow as content)
var workbench_content: WorkbenchWindow = null

# Signals
signal workbench_validated(success: bool, report: Dictionary)


func _ready():
	print("WorkbenchWindow_Base: _ready() called")
	window_title = "Assembly Workbench"
	default_size = Vector2(1200, 800)
	min_window_size = Vector2(1000, 800)
	max_window_size = Vector2(1920, 1080)

	super._ready()
	print("WorkbenchWindow_Base: super._ready() completed")


func _setup_window_content():
	"""Override Window_Base virtual method to setup workbench content"""
	print("WorkbenchWindow_Base: _setup_window_content called")

	# Load the workbench content scene
	var workbench_scene = load("res://scenes/crafting/workbench_window.tscn") as PackedScene
	if not workbench_scene:
		push_error("WorkbenchWindow_Base: Failed to load workbench_window.tscn")
		return

	# Instantiate the workbench content
	workbench_content = workbench_scene.instantiate() as WorkbenchWindow
	if not workbench_content:
		push_error("WorkbenchWindow_Base: Failed to instantiate WorkbenchWindow")
		return

	# Remove the title bar from the workbench content since Window_Base provides one
	if workbench_content.has_node("VBoxContainer/TitleBar"):
		workbench_content.get_node("VBoxContainer/TitleBar").queue_free()

	# Make the workbench content fill the content area
	workbench_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Add to content area
	content_area.add_child(workbench_content)

	# Connect signals
	if workbench_content.has_signal("item_validated"):
		workbench_content.item_validated.connect(_on_workbench_validated)
	if workbench_content.has_signal("workbench_closed"):
		workbench_content.workbench_closed.connect(_on_workbench_content_closed)

	print("WorkbenchWindow_Base: Workbench content added successfully")


func _on_workbench_validated(success: bool, report: Dictionary):
	"""Relay validation signal"""
	workbench_validated.emit(success, report)


func _on_workbench_content_closed():
	"""Handle workbench content requesting to close"""
	# Disable input on workbench content first
	if workbench_content and workbench_content.has_method("_on_window_hidden"):
		workbench_content._on_window_hidden()
	# Close the window
	hide_window()


func _on_window_closed():
	"""Override to cleanup workbench content"""
	if workbench_content:
		# Clear the workbench when closing
		workbench_content.clear_workbench()
		# Disable input on the workbench content when window closes (AFTER clearing)
		if workbench_content.has_method("_on_window_hidden"):
			workbench_content._on_window_hidden()


func hide_window():
	"""Override hide_window to properly disable workbench input"""
	# Disable input on workbench content BEFORE hiding
	if workbench_content:
		# Explicitly hide the workbench content
		workbench_content.visible = false
		if workbench_content.has_method("_on_window_hidden"):
			workbench_content._on_window_hidden()
	# Call parent hide
	super.hide_window()


func show_window():
	"""Override show_window to properly enable workbench input"""
	# Call parent show
	super.show_window()
	# Re-enable input on workbench content AFTER showing
	if workbench_content:
		# Explicitly show the workbench content
		workbench_content.visible = true
		if workbench_content.has_method("_on_window_shown"):
			workbench_content._on_window_shown()


# Public API for accessing workbench functionality


func spawn_part(scene_path: String) -> PhysicalItem:
	"""Spawn a part in the workbench"""
	if workbench_content:
		return workbench_content.spawn_part(scene_path)
	return null


func clear_workbench() -> void:
	"""Clear all items from workbench"""
	if workbench_content:
		workbench_content.clear_workbench()


func get_all_items() -> Array[PhysicalItem]:
	"""Get all items in the workbench"""
	if workbench_content:
		return workbench_content.get_all_items()
	return []


func get_selected_items() -> Array[PhysicalItem]:
	"""Get currently selected items"""
	if workbench_content:
		return workbench_content.selected_items
	return []
