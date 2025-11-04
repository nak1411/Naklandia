# JointHelper.gd - A placeable joint connection point
# Can be positioned between two objects to create a joint connection
class_name JointHelper
extends PhysicalItem

## Visual helper object that can be placed to mark where joints should connect

@export var joint_type: Joint.JointType = Joint.JointType.FIXED

# Connected items (set when attached)
var attached_item_a: PhysicalItem = null
var attached_item_b: PhysicalItem = null
var is_attached_to_items: bool = false

# Visual
var material: StandardMaterial3D


func _ready() -> void:
	# Call parent's _ready() to set up PhysicalItem
	super._ready()

	# Create material based on joint type
	material = StandardMaterial3D.new()

	match joint_type:
		Joint.JointType.FIXED:
			material.albedo_color = Color(0.8, 0.2, 0.2, 0.9)  # Red
		Joint.JointType.HINGE:
			material.albedo_color = Color(0.2, 0.8, 0.2, 0.9)  # Green
		Joint.JointType.BALL_SOCKET:
			material.albedo_color = Color(0.2, 0.2, 0.8, 0.9)  # Blue
		Joint.JointType.SLIDER:
			material.albedo_color = Color(0.8, 0.8, 0.2, 0.9)  # Yellow
		Joint.JointType.SPRING:
			material.albedo_color = Color(0.8, 0.2, 0.8, 0.9)  # Magenta

	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 0.8

	# Apply material and setup cross bars
	var x_bar = get_node_or_null("XBar")
	var y_bar = get_node_or_null("YBar")
	var z_bar = get_node_or_null("ZBar")

	if x_bar:
		# Override the material_override to ensure color is applied
		x_bar.material_override = material

	if y_bar:
		# Rotate Y bar 90 degrees to point up
		y_bar.rotation_degrees = Vector3(0, 0, 90)
		# Override the material_override to ensure color is applied
		y_bar.material_override = material

	if z_bar:
		# Rotate Z bar 90 degrees to point forward
		z_bar.rotation_degrees = Vector3(0, 90, 0)
		# Override the material_override to ensure color is applied
		z_bar.material_override = material

	print("JointHelper ready: %s" % item_name)


## Attach this helper to two physical items
func attach_to_items(a: PhysicalItem, b: PhysicalItem, parent: Node3D) -> bool:
	"""Create a joint between two items at this helper's position."""
	if not a or not b:
		push_error("JointHelper: Cannot attach - invalid items")
		return false

	attached_item_a = a
	attached_item_b = b

	# Determine fastener type based on joint type
	var fastener_id = ""
	match joint_type:
		Joint.JointType.FIXED:
			fastener_id = "fastener_steel_bolt"
		Joint.JointType.HINGE:
			fastener_id = "fastener_hinge"
		Joint.JointType.BALL_SOCKET:
			fastener_id = "fastener_ball_joint"
		Joint.JointType.SLIDER:
			fastener_id = "fastener_steel_bolt"  # Use bolt for slider
		Joint.JointType.SPRING:
			fastener_id = "fastener_steel_bolt"  # Use bolt for spring

	# Create joint at helper position
	var fastener = attached_item_a.attach_with_fastener(attached_item_b, fastener_id, global_position, parent)

	if fastener:
		is_attached_to_items = true
		print("JointHelper: Attached %s to %s at %s" % [attached_item_a.item_name, attached_item_b.item_name, global_position])

		# Make the helper semi-transparent to show it's attached
		if material:
			material.albedo_color.a = 0.5

		return true

	return false


## Detach this helper from items
func detach() -> void:
	"""Remove the joint connection."""
	if not is_attached_to_items or not attached_item_a or not attached_item_b:
		return

	# Find and remove the fastener
	for fastener in attached_item_a.fasteners:
		if fastener.item_b == attached_item_b:
			attached_item_a.remove_fastener(fastener, true)
			break

	attached_item_a = null
	attached_item_b = null
	is_attached_to_items = false

	# Restore full opacity
	if material:
		material.albedo_color.a = 0.8


func get_info_text() -> String:
	"""Get display text for UI."""
	var info = "[b]%s[/b]\n" % item_name
	info += "%s\n" % item_description

	if is_attached_to_items:
		info += "\nAttached: %s <-> %s" % [attached_item_a.item_name if attached_item_a else "?", attached_item_b.item_name if attached_item_b else "?"]
	else:
		info += "\nNot attached"

	return info
