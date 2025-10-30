class_name EquipmentSocket
extends Node3D

## Represents an attachment point for equippable items
## The Node3D's transform in the scene defines where items will appear
## Simply place these nodes in the scene tree and position them in the editor

@export var socket_name: String = "default_socket"
@export var socket_category: String = "weapon"  ## weapon, tool, armor_head, armor_chest, etc.
@export var enabled: bool = true

func _ready():
	# Note: We don't set visible = false because that would hide children too
	# The socket itself is just a transform marker with no mesh, so it's already invisible
	pass

## Get the world transform where items should be attached
func get_attachment_transform() -> Transform3D:
	return global_transform

## Get the local transform relative to parent
func get_local_attachment_transform() -> Transform3D:
	return transform
