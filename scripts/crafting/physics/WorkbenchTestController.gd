extends Node

## Simple test controller for workbench window

var workbench: WorkbenchWindow = null


func _ready() -> void:
	# Get workbench reference
	workbench = get_parent().get_node("WorkbenchWindow") as WorkbenchWindow
	if workbench:
		print("TestController: Found workbench")
	else:
		print("TestController: Workbench not found!")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):  # Spacebar
		if workbench:
			workbench.visible = not workbench.visible
			print("Workbench toggled: ", workbench.visible)

			# Debug info
			if workbench.visible:
				print("Workbench should now be visible")
				print("Workbench size: ", workbench.size)
				print("Workbench position: ", workbench.position)
		else:
			print("No workbench to toggle!")
