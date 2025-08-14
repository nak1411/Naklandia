# UIDebuggerAutoload.gd
extends Node

var ui_debugger: UIDebugger


func _ready():
	# Wait for the scene to be ready
	await get_tree().process_frame

	# Create the UI debugger
	ui_debugger = UIDebugger.new()
	ui_debugger.name = "UIDebugger"

	# Add to the root so it persists across scene changes
	get_tree().root.add_child(ui_debugger)

	print("UIDebugger autoload ready! Press F3 or ` to toggle")


func get_debugger() -> UIDebugger:
	return ui_debugger
