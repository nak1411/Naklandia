# Fastener.gd - Represents a fastener (nail, screw, bolt) connecting two items
# Works alongside Joint.gd to provide metadata about the connection
class_name Fastener
extends RefCounted

# Connected items
var item_a: PhysicalItem
var item_b: PhysicalItem

# Fastener properties (loaded from ItemDatabase)
var fastener_item_id: String = ""  # e.g., "fastener_steel_bolt"
var fastener_type: String = "fixed"  # nail, screw, bolt, rivet, weld
var material: String = "iron"  # Material of the fastener
var strength: float = 100.0  # Maximum force before failure
var durability: float = 1.0  # Current condition (0-1)
var removal_difficulty: float = 0.5  # How hard to remove (0-1)
var requires_tool: String = ""  # Tool ID needed to install/remove

# Connection data
var connection_point: Vector3 = Vector3.ZERO  # Point where fastener is placed (world space)
var connection_normal: Vector3 = Vector3.UP  # Surface normal at connection
var penetration_depth: float = 0.05  # How deep the fastener goes

# Associated joint
var joint: Joint = null

# Metadata
var installation_time: float = 0.0
var installed: bool = false

# Signals
signal fastener_installed(fastener: Fastener)
signal fastener_removed(fastener: Fastener)
signal fastener_failed(fastener: Fastener)


func _init(
	a: PhysicalItem,
	b: PhysicalItem,
	item_id: String = ""
):
	item_a = a
	item_b = b
	fastener_item_id = item_id

	# Load properties from ItemDatabase if available
	if not item_id.is_empty():
		_load_fastener_properties()


## Load fastener properties from ItemDatabase
func _load_fastener_properties():
	if not ItemDatabase:
		push_warning("Fastener: ItemDatabase not available")
		return

	var item_def = ItemDatabase.get_item(fastener_item_id)
	if not item_def:
		push_warning("Fastener: Item definition not found for %s" % fastener_item_id)
		return

	# Load metadata
	if item_def.custom_properties.has("fastener_type"):
		fastener_type = item_def.custom_properties.get("fastener_type", "fixed")

	if item_def.custom_properties.has("material"):
		material = item_def.custom_properties.get("material", "iron")

	if item_def.custom_properties.has("strength"):
		strength = item_def.custom_properties.get("strength", 100.0)

	if item_def.custom_properties.has("durability"):
		durability = item_def.custom_properties.get("durability", 1.0)

	if item_def.custom_properties.has("removal_difficulty"):
		removal_difficulty = item_def.custom_properties.get("removal_difficulty", 0.5)

	if item_def.custom_properties.has("requires_tool"):
		requires_tool = item_def.custom_properties.get("requires_tool", "")

	print("Fastener: Loaded properties for %s - strength: %.1f, type: %s" % [fastener_item_id, strength, fastener_type])


## Create associated joint based on fastener type
func create_joint(parent: Node3D) -> bool:
	if not item_a or not item_b:
		push_error("Fastener: Cannot create joint - items not set")
		return false

	# Determine joint type from fastener type
	var joint_type = Joint.JointType.FIXED
	var joint_properties = {}

	match fastener_type:
		"nail", "screw", "bolt", "rivet", "weld":
			joint_type = Joint.JointType.FIXED
		"joint":
			# Check for joint_properties in item metadata
			if ItemDatabase:
				var item_def = ItemDatabase.get_item(fastener_item_id)
				if item_def and item_def.custom_properties.has("joint_properties"):
					joint_properties = item_def.custom_properties.get("joint_properties", {})
					var connection_type = item_def.custom_properties.get("connection_type", "hinge")
					match connection_type:
						"hinge":
							joint_type = Joint.JointType.HINGE
						"ball_socket":
							joint_type = Joint.JointType.BALL_SOCKET
						"slider":
							joint_type = Joint.JointType.SLIDER
						"spring":
							joint_type = Joint.JointType.SPRING

	# Create joint
	joint = Joint.new(item_a, item_b, joint_type, fastener_item_id)
	joint.strength = strength
	joint.durability = durability
	joint.anchor_point_a = item_a.global_transform.inverse() * connection_point
	joint.anchor_point_b = item_b.global_transform.inverse() * connection_point

	# Apply joint properties if available
	if joint_properties.has("rotation_axis"):
		var axis_str = joint_properties.get("rotation_axis", "Y")
		match axis_str:
			"X":
				joint.axis = Vector3.RIGHT
			"Y":
				joint.axis = Vector3.UP
			"Z":
				joint.axis = Vector3.BACK
			"ALL":
				joint.axis = Vector3.ZERO

	if joint_properties.has("min_angle"):
		joint.min_limit = joint_properties.get("min_angle", -180.0)

	if joint_properties.has("max_angle"):
		joint.max_limit = joint_properties.get("max_angle", 180.0)

	if joint_properties.has("friction"):
		joint.friction = joint_properties.get("friction", 0.1)

	# Create physics joint
	if joint.create_physics_joint(parent):
		installed = true
		installation_time = Time.get_ticks_msec() / 1000.0
		fastener_installed.emit(self)
		print("Fastener: Created joint between %s and %s" % [item_a.name, item_b.name])
		return true

	return false


## Remove the fastener and destroy the joint
func remove(has_tool: bool = false) -> bool:
	# Check if correct tool is available
	if not requires_tool.is_empty() and not has_tool:
		push_warning("Fastener: Requires tool %s to remove" % requires_tool)
		return false

	# Check removal difficulty
	var removal_chance = 1.0 - (removal_difficulty * 0.5)
	if randf() > removal_chance:
		push_warning("Fastener: Failed to remove - try again")
		return false

	# Destroy joint
	if joint:
		joint.destroy_physics_joint()
		joint = null

	installed = false
	fastener_removed.emit(self)
	print("Fastener: Removed fastener from %s and %s" % [item_a.name, item_b.name])
	return true


## Apply force to the fastener (can cause failure)
func apply_force(force: float):
	if not installed or not joint:
		return

	# Check if force exceeds strength
	if force > strength * durability:
		# Fastener fails
		fail()
	else:
		# Degrade durability
		var damage = force / strength * 0.01
		durability -= damage
		durability = max(0.0, durability)

		if durability <= 0.0:
			fail()

		# Apply stress to joint
		if joint:
			joint.apply_stress(force)


## Fastener fails and breaks
func fail():
	print("Fastener: FAILED - %s between %s and %s" % [fastener_item_id, item_a.name, item_b.name])

	# Destroy joint
	if joint:
		joint.destroy_physics_joint()
		joint = null

	installed = false
	fastener_failed.emit(self)


## Check if player has required tool in inventory
func has_required_tool(inventory_container) -> bool:
	if requires_tool.is_empty():
		return true

	if not inventory_container:
		return false

	# Check inventory for tool
	var items = inventory_container.get_items()
	for item in items:
		if item.item_id == requires_tool:
			return true

	return false


## Get fastener info as dictionary for serialization
func to_dict() -> Dictionary:
	return {
		"item_a_path": item_a.get_path() if item_a else "",
		"item_b_path": item_b.get_path() if item_b else "",
		"fastener_item_id": fastener_item_id,
		"fastener_type": fastener_type,
		"material": material,
		"strength": strength,
		"durability": durability,
		"removal_difficulty": removal_difficulty,
		"requires_tool": requires_tool,
		"connection_point": var_to_str(connection_point),
		"connection_normal": var_to_str(connection_normal),
		"penetration_depth": penetration_depth,
		"installation_time": installation_time,
		"installed": installed
	}


## Load fastener from dictionary
static func from_dict(data: Dictionary, scene_root: Node) -> Fastener:
	# Get items from paths
	var a = scene_root.get_node(data.get("item_a_path", "")) if data.has("item_a_path") else null
	var b = scene_root.get_node(data.get("item_b_path", "")) if data.has("item_b_path") else null

	if not a or not b:
		return null

	var fastener = Fastener.new(a, b, data.get("fastener_item_id", ""))

	fastener.fastener_type = data.get("fastener_type", "fixed")
	fastener.material = data.get("material", "iron")
	fastener.strength = data.get("strength", 100.0)
	fastener.durability = data.get("durability", 1.0)
	fastener.removal_difficulty = data.get("removal_difficulty", 0.5)
	fastener.requires_tool = data.get("requires_tool", "")
	fastener.connection_point = str_to_var(data.get("connection_point", "Vector3(0, 0, 0)"))
	fastener.connection_normal = str_to_var(data.get("connection_normal", "Vector3(0, 1, 0)"))
	fastener.penetration_depth = data.get("penetration_depth", 0.05)
	fastener.installation_time = data.get("installation_time", 0.0)
	fastener.installed = data.get("installed", false)

	return fastener
