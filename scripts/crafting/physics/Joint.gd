# Joint.gd - Represents a physical connection between two items
# Handles different types of mechanical joints (fixed, hinge, ball socket, slider)
class_name Joint
extends RefCounted

# Joint types
enum JointType {
	FIXED,        # No movement - rigid connection
	HINGE,        # Rotation around single axis
	BALL_SOCKET,  # Multi-axis rotation
	SLIDER,       # Linear movement along single axis
	SPRING        # Flexible connection with spring physics
}

# Connection data
var item_a: PhysicalItem  # First connected item
var item_b: PhysicalItem  # Second connected item
var joint_type: JointType = JointType.FIXED
var fastener_item_id: String = ""  # ID of fastener used (e.g., "fastener_hinge")

# Transform data
var anchor_point_a: Vector3 = Vector3.ZERO  # Connection point on item A (local space)
var anchor_point_b: Vector3 = Vector3.ZERO  # Connection point on item B (local space)
var anchor_rotation: Vector3 = Vector3.ZERO # Joint rotation (euler angles)

# Joint properties
var axis: Vector3 = Vector3.UP  # Primary axis for hinges/sliders
var min_limit: float = -180.0   # Min angle (degrees) for hinges
var max_limit: float = 180.0    # Max angle (degrees) for hinges
var friction: float = 0.1       # Resistance to movement
var strength: float = 100.0     # How much force before breaking
var durability: float = 1.0     # Current condition (0-1)

# Physics joint reference
var physics_joint: Joint3D = null
var joint_node: Node3D = null  # Visual representation

# Signals
signal joint_broken(joint: Joint)
signal joint_stressed(joint: Joint, stress_level: float)


func _init(
	a: PhysicalItem,
	b: PhysicalItem,
	type: JointType = JointType.FIXED,
	fastener_id: String = ""
):
	item_a = a
	item_b = b
	joint_type = type
	fastener_item_id = fastener_id


## Create the actual Godot physics joint and attach it to the scene
func create_physics_joint(parent: Node3D) -> bool:
	if not item_a or not item_b:
		push_error("Joint: Cannot create physics joint - items not set")
		return false

	if not item_a.is_inside_tree() or not item_b.is_inside_tree():
		push_error("Joint: Cannot create physics joint - items not in scene tree")
		return false

	# Create joint based on type
	match joint_type:
		JointType.FIXED:
			physics_joint = _create_fixed_joint()
		JointType.HINGE:
			physics_joint = _create_hinge_joint()
		JointType.BALL_SOCKET:
			physics_joint = _create_ball_socket_joint()
		JointType.SLIDER:
			physics_joint = _create_slider_joint()
		JointType.SPRING:
			physics_joint = _create_spring_joint()

	if physics_joint:
		parent.add_child(physics_joint)
		physics_joint.set_node_a(item_a.get_path())
		physics_joint.set_node_b(item_b.get_path())

		# Create visual helper gizmo
		_create_visual_helper(parent)

		return true

	return false


## Create visual helper gizmo at connection point
func _create_visual_helper(parent: Node3D):
	"""Create a cross-shaped visual gizmo to show where the joint connection is."""
	joint_node = Node3D.new()
	joint_node.name = "JointHelper_%s_%s" % [item_a.name, item_b.name]

	# Create material for the helper
	var material = StandardMaterial3D.new()

	# Color based on joint type
	match joint_type:
		JointType.FIXED:
			material.albedo_color = Color(0.8, 0.2, 0.2, 0.9)  # Red for fixed
		JointType.HINGE:
			material.albedo_color = Color(0.2, 0.8, 0.2, 0.9)  # Green for hinge
		JointType.BALL_SOCKET:
			material.albedo_color = Color(0.2, 0.2, 0.8, 0.9)  # Blue for ball socket
		JointType.SLIDER:
			material.albedo_color = Color(0.8, 0.8, 0.2, 0.9)  # Yellow for slider
		JointType.SPRING:
			material.albedo_color = Color(0.8, 0.2, 0.8, 0.9)  # Magenta for spring

	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 0.5

	# Create 3 perpendicular bars (cross shape)
	var bar_size = 0.15  # 15cm total size

	# X-axis bar (red)
	var x_bar = MeshInstance3D.new()
	var x_mesh = BoxMesh.new()
	x_mesh.size = Vector3(bar_size, 0.01, 0.01)
	x_bar.mesh = x_mesh
	x_bar.set_surface_override_material(0, material)
	joint_node.add_child(x_bar)

	# Y-axis bar (green)
	var y_bar = MeshInstance3D.new()
	var y_mesh = BoxMesh.new()
	y_mesh.size = Vector3(0.01, bar_size, 0.01)
	y_bar.mesh = y_mesh
	y_bar.set_surface_override_material(0, material)
	joint_node.add_child(y_bar)

	# Z-axis bar (blue)
	var z_bar = MeshInstance3D.new()
	var z_mesh = BoxMesh.new()
	z_mesh.size = Vector3(0.01, 0.01, bar_size)
	z_bar.mesh = z_mesh
	z_bar.set_surface_override_material(0, material)
	joint_node.add_child(z_bar)

	# Center sphere
	var center = MeshInstance3D.new()
	var center_mesh = SphereMesh.new()
	center_mesh.radius = 0.02
	center_mesh.height = 0.04
	center.mesh = center_mesh
	center.set_surface_override_material(0, material)
	joint_node.add_child(center)

	parent.add_child(joint_node)

	# Position at connection point
	update_visual_helper_position()

	print("Joint: Created visual helper at %s" % joint_node.global_position)


## Create a fixed joint (no movement)
func _create_fixed_joint() -> Generic6DOFJoint3D:
	var joint = Generic6DOFJoint3D.new()
	joint.name = "FixedJoint_%s_%s" % [item_a.name, item_b.name]

	# Lock all axes
	for i in range(3):
		# Lock linear axes
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0)

		# Lock angular axes
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0)

	# Set position
	joint.global_position = item_a.global_position + item_a.global_transform.basis * anchor_point_a

	return joint


## Create a hinge joint (rotation around one axis)
func _create_hinge_joint() -> HingeJoint3D:
	var joint = HingeJoint3D.new()
	joint.name = "HingeJoint_%s_%s" % [item_a.name, item_b.name]

	# Set hinge parameters
	joint.set_param(HingeJoint3D.PARAM_BIAS, 0.3)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(max_limit))
	joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(min_limit))
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)

	# Set position and rotation
	joint.global_position = item_a.global_position + item_a.global_transform.basis * anchor_point_a

	# Align joint axis
	var transform = Transform3D()
	transform.basis = Basis.from_euler(anchor_rotation)
	joint.global_transform = transform

	return joint


## Create a ball socket joint (multi-axis rotation)
func _create_ball_socket_joint() -> ConeTwistJoint3D:
	var joint = ConeTwistJoint3D.new()
	joint.name = "BallSocketJoint_%s_%s" % [item_a.name, item_b.name]

	# Set cone twist parameters
	joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(max_limit))
	joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(max_limit))
	joint.set_param(ConeTwistJoint3D.PARAM_BIAS, 0.3)
	joint.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.8)
	joint.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 1.0)

	# Set position
	joint.global_position = item_a.global_position + item_a.global_transform.basis * anchor_point_a

	return joint


## Create a slider joint (linear movement)
func _create_slider_joint() -> Generic6DOFJoint3D:
	var joint = Generic6DOFJoint3D.new()
	joint.name = "SliderJoint_%s_%s" % [item_a.name, item_b.name]

	# Lock rotation axes
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0)

	# Allow movement along primary axis only
	if axis.abs().x > 0.5:
		# Slide along X
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, min_limit)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, max_limit)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0)
	elif axis.abs().y > 0.5:
		# Slide along Y
		joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, min_limit)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, max_limit)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0)
	else:
		# Slide along Z
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, min_limit)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, max_limit)

	# Set position
	joint.global_position = item_a.global_position + item_a.global_transform.basis * anchor_point_a

	return joint


## Create a spring joint (flexible connection)
func _create_spring_joint() -> Generic6DOFJoint3D:
	var joint = Generic6DOFJoint3D.new()
	joint.name = "SpringJoint_%s_%s" % [item_a.name, item_b.name]

	# Enable springs on all linear axes
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING, true)

	# Set spring parameters
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, strength * 10.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, strength * 10.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, strength * 10.0)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING, friction * 5.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING, friction * 5.0)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING, friction * 5.0)

	# Set position
	joint.global_position = item_a.global_position + item_a.global_transform.basis * anchor_point_a

	return joint


## Remove the physics joint from the scene
func destroy_physics_joint():
	if physics_joint and is_instance_valid(physics_joint):
		if physics_joint.is_inside_tree():
			physics_joint.get_parent().remove_child(physics_joint)
		physics_joint.queue_free()
		physics_joint = null

	if joint_node and is_instance_valid(joint_node):
		if joint_node.is_inside_tree():
			joint_node.get_parent().remove_child(joint_node)
		joint_node.queue_free()
		joint_node = null


## Apply stress to the joint (can cause degradation or breaking)
func apply_stress(force: float):
	var stress_level = force / strength

	if stress_level > 1.0:
		# Joint breaks
		durability = 0.0
		joint_broken.emit(self)
		destroy_physics_joint()
	else:
		# Degrade durability
		durability -= stress_level * 0.01
		durability = max(0.0, durability)
		joint_stressed.emit(self, stress_level)

		if durability <= 0.0:
			joint_broken.emit(self)
			destroy_physics_joint()


## Update the visual helper position to follow the connected objects
func update_visual_helper_position() -> void:
	"""Update the joint visual helper to stay at the connection point as objects move."""
	if not joint_node or not item_a or not item_b:
		return

	# Calculate connection point from item A's anchor in world space
	var connection_pos = item_a.global_transform * anchor_point_a

	# Update visual helper position
	joint_node.global_position = connection_pos


## Get joint info as dictionary for serialization
func to_dict() -> Dictionary:
	return {
		"item_a_path": item_a.get_path() if item_a else "",
		"item_b_path": item_b.get_path() if item_b else "",
		"joint_type": joint_type,
		"fastener_item_id": fastener_item_id,
		"anchor_point_a": var_to_str(anchor_point_a),
		"anchor_point_b": var_to_str(anchor_point_b),
		"anchor_rotation": var_to_str(anchor_rotation),
		"axis": var_to_str(axis),
		"min_limit": min_limit,
		"max_limit": max_limit,
		"friction": friction,
		"strength": strength,
		"durability": durability
	}


## Load joint from dictionary
static func from_dict(data: Dictionary, scene_root: Node) -> Joint:
	# Get items from paths
	var a = scene_root.get_node(data.get("item_a_path", "")) if data.has("item_a_path") else null
	var b = scene_root.get_node(data.get("item_b_path", "")) if data.has("item_b_path") else null

	if not a or not b:
		return null

	var joint = Joint.new(a, b, data.get("joint_type", JointType.FIXED), data.get("fastener_item_id", ""))

	joint.anchor_point_a = str_to_var(data.get("anchor_point_a", "Vector3(0, 0, 0)"))
	joint.anchor_point_b = str_to_var(data.get("anchor_point_b", "Vector3(0, 0, 0)"))
	joint.anchor_rotation = str_to_var(data.get("anchor_rotation", "Vector3(0, 0, 0)"))
	joint.axis = str_to_var(data.get("axis", "Vector3(0, 1, 0)"))
	joint.min_limit = data.get("min_limit", -180.0)
	joint.max_limit = data.get("max_limit", 180.0)
	joint.friction = data.get("friction", 0.1)
	joint.strength = data.get("strength", 100.0)
	joint.durability = data.get("durability", 1.0)

	return joint
