# PlayerInventorySetup.gd - Simple script to add inventory to existing player
extends Node

var inventory_integration: InventoryIntegration
var setup_complete: bool = false

func _ready():
	# Wait for the scene to be fully ready
	await get_tree().process_frame
	_setup_inventory()

func _setup_inventory():
	print("Setting up inventory system...")
	
	# Create and add inventory integration
	inventory_integration = InventoryIntegration.new()
	inventory_integration.name = "InventoryIntegration"
	get_parent().add_child(inventory_integration)
	
	# Wait for inventory to initialize
	await get_tree().process_frame
	setup_complete = true
	
	print("Inventory system initialized. Press I to open inventory!")

func _unhandled_input(event: InputEvent):
	# Backup input handling in case the integration doesn't catch it
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_I:
			print("I key pressed")
			if setup_complete and inventory_integration:
				inventory_integration.toggle_inventory()
			else:
				print("Inventory not ready yet!")
			get_viewport().set_input_as_handled()
