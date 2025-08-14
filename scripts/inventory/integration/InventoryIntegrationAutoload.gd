# integration/InventoryIntegrationAutoload.gd
# Autoload script to set up inventory integration
extends Node

var integration_system: InventoryIntegration


func _ready():
	# Wait for the scene to be ready
	await get_tree().process_frame

	# Create the integration system
	integration_system = InventoryIntegration.new()
	integration_system.name = "InventoryIntegration"

	# Add to current scene
	get_tree().current_scene.add_child(integration_system)


func get_integration_system() -> InventoryIntegration:
	return integration_system
