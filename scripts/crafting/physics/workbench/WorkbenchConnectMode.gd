class_name WorkbenchConnectMode
extends RefCounted

## Manages Connect Mode (Bolt Gun) functionality for fastening items together.
##
## Allows users to:
## - Enter connect mode with 2 selected items
## - Fire rays to detect intersection points
## - Place fasteners at contact points
## - Create physics joints and visual helpers

signal fastener_placed(fastener: Fastener, item_a: PhysicalItem, item_b: PhysicalItem)
signal connect_mode_toggled(active: bool)
signal fire_line_shown()

# References
var camera: Camera3D
var viewport: SubViewport
var viewport_container: SubViewportContainer
var world: Node3D

# Connect mode state
var connect_mode_active: bool = false
var connect_mode_target_a: PhysicalItem = null
var connect_mode_target_b: PhysicalItem = null

# Visual feedback
var connect_mode_preview_line: MeshInstance3D = null
var connect_mode_fire_line: MeshInstance3D = null
var fire_line_timer: float = 0.0
const FIRE_LINE_DURATION: float = 1.0

# Settings
var connect_mode_max_bolt_length: float = 50.0
var connect_mode_max_ray_distance: float = 1000.0

# Fastener management
var fasteners_created: Array[Fastener] = []
var selected_fastener_id: String = "fastener_steel_bolt"
var available_fasteners: Array[String] = [
	"fastener_iron_nail",
	"fastener_steel_screw",
	"fastener_steel_bolt",
	"fastener_hinge",
	"fastener_ball_joint"
]


func _init(
	p_camera: Camera3D,
	p_viewport: SubViewport,
	p_viewport_container: SubViewportContainer,
	p_world: Node3D
) -> void:
	"""Initialize the connect mode controller."""
	camera = p_camera
	viewport = p_viewport
	viewport_container = p_viewport_container
	world = p_world


func enter_connect_mode(selected_items: Array[PhysicalItem]) -> bool:
	"""Enter Connect Mode with 2 selected items. Returns true if successful."""
	if selected_items.size() != 2:
		print("Connect Mode ERROR: Requires exactly 2 items selected. Currently selected: ", selected_items.size())
		return false

	connect_mode_active = true
	connect_mode_target_a = selected_items[0]
	connect_mode_target_b = selected_items[1]

	print("\n=== CONNECT MODE ACTIVATED ===")
	print("Target A: %s at %.2f,%.2f,%.2f" % [
		connect_mode_target_a.item_name,
		connect_mode_target_a.global_position.x,
		connect_mode_target_a.global_position.y,
		connect_mode_target_a.global_position.z
	])
	print("Target B: %s at %.2f,%.2f,%.2f" % [
		connect_mode_target_b.item_name,
		connect_mode_target_b.global_position.x,
		connect_mode_target_b.global_position.y,
		connect_mode_target_b.global_position.z
	])
	print("Click anywhere on visible surface to place fastener")
	print("Press Q or click button to exit")

	connect_mode_toggled.emit(true)
	return true


func exit_connect_mode() -> void:
	"""Exit Connect Mode and clean up visual elements."""
	connect_mode_active = false
	connect_mode_target_a = null
	connect_mode_target_b = null

	# Clean up preview line
	if connect_mode_preview_line:
		connect_mode_preview_line.queue_free()
		connect_mode_preview_line = null

	# Clean up fire line
	if connect_mode_fire_line:
		connect_mode_fire_line.queue_free()
		connect_mode_fire_line = null

	print("Connect Mode: Exited")
	connect_mode_toggled.emit(false)


func is_active() -> bool:
	"""Returns true if connect mode is currently active."""
	return connect_mode_active


func update_fire_line_timer(delta: float) -> void:
	"""Update the fire line timer (call in _process)."""
	if fire_line_timer > 0.0:
		fire_line_timer -= delta
		if fire_line_timer <= 0.0 and connect_mode_fire_line:
			connect_mode_fire_line.visible = false


func place_fastener_at_ray(mouse_pos: Vector2) -> void:
	"""
	Place a fastener at the INTERSECTION between two objects.
	This fires a ray through both objects and finds their contact point.
	"""
	print("\n=== FIRING BOLT GUN (detecting intersection) ===")

	# Show visual fire line
	_show_fire_line(mouse_pos)

	var result = _perform_raycast(mouse_pos)

	if not result["success"]:
		print("❌ Cannot place fastener: ", result["error_message"])
		return

	var hit_point_a = result["hit_point_a"]
	var hit_point_b = result["hit_point_b"]
	var hit_item_a = result["hit_item_a"]
	var hit_item_b = result["hit_item_b"]
	var distance = result["distance"]
	var ray_direction = result["ray_direction"]

	# Calculate connection point (midpoint between hits)
	var connection_point = (hit_point_a + hit_point_b) / 2.0

	# Create fastener
	var fastener = Fastener.new(hit_item_a, hit_item_b, selected_fastener_id)
	fastener.connection_point = connection_point
	fastener.connection_normal = ray_direction
	fastener.penetration_depth = distance

	# Create joint
	if fastener.create_joint(world):
		fasteners_created.append(fastener)

		# Add fastener to both items' fastener arrays (for cluster tracking)
		hit_item_a.fasteners.append(fastener)
		hit_item_b.fasteners.append(fastener)

		# Add joint to both items' joint arrays
		if fastener.joint:
			hit_item_a.joints.append(fastener.joint)
			hit_item_b.joints.append(fastener.joint)

		# Bond the items together for cluster selection
		hit_item_a.bond_to(hit_item_b)

		print("✓ Fastener placed at INTERSECTION! Distance: %.3fm, Type: %s" % [distance, selected_fastener_id])
		print("✓ Connected %s to %s at their contact point" % [hit_item_a.item_name, hit_item_b.item_name])
		print("  Connection point: %.3f, %.3f, %.3f" % [connection_point.x, connection_point.y, connection_point.z])
		print("✓ Items bonded - they will now select and move as a cluster")

		fastener_placed.emit(fastener, hit_item_a, hit_item_b)
	else:
		print("❌ Failed to create joint for fastener")


func attach_selected_items_with_fastener(selected_items: Array[PhysicalItem], fastener_id: String) -> int:
	"""
	Attach all selected items together using the specified fastener.
	Returns the number of items successfully attached.
	"""
	print("_attach_selected_items_with_fastener called")
	print("  Selected items: %d" % selected_items.size())
	print("  Fastener: %s" % fastener_id)

	if selected_items.size() < 2:
		print("ERROR: Need at least 2 items selected to attach")
		return 0

	# Get the first item as the base
	var base_item = selected_items[0]
	print("  Base item: %s" % base_item.item_name)

	# Attach all other items to the base
	var attached_count = 0
	for i in range(1, selected_items.size()):
		var target_item = selected_items[i]
		print("  Attempting to attach: %s" % target_item.item_name)

		# Calculate midpoint between items for connection point
		var connection_point = (base_item.global_position + target_item.global_position) / 2.0
		print("    Connection point: %s" % connection_point)

		# Attach using PhysicalItem's method
		var fastener = base_item.attach_with_fastener(target_item, fastener_id, connection_point, world)

		if fastener:
			fasteners_created.append(fastener)
			attached_count += 1
			print("    SUCCESS: Attached %s to %s with %s" % [target_item.item_name, base_item.item_name, fastener_id])
			fastener_placed.emit(fastener, base_item, target_item)
		else:
			print("    FAILED: Could not attach %s to %s" % [target_item.item_name, base_item.item_name])

	if attached_count > 0:
		print("RESULT: Successfully attached %d items with %s" % [attached_count, fastener_id])
	else:
		print("RESULT: Failed to attach any items")

	return attached_count


func set_selected_fastener(fastener_id: String) -> void:
	"""Set the currently selected fastener type."""
	if fastener_id in available_fasteners:
		selected_fastener_id = fastener_id
		print("Selected fastener: %s" % selected_fastener_id)


func get_fastener_display_name(fastener_id: String) -> String:
	"""Get display name for fastener from ItemDatabase."""
	if not ItemDatabase:
		return fastener_id

	var item_def = ItemDatabase.get_item(fastener_id)
	if item_def:
		return item_def.name

	return fastener_id


func get_available_fasteners() -> Array[String]:
	"""Get the list of available fastener IDs."""
	return available_fasteners


func get_created_fasteners() -> Array[Fastener]:
	"""Get all fasteners created in this session."""
	return fasteners_created


func clear_fasteners() -> void:
	"""Clear the list of created fasteners."""
	fasteners_created.clear()


# Private helper methods

func _perform_raycast(mouse_pos: Vector2) -> Dictionary:
	"""
	Perform raycast to find intersection between two objects.
	Returns success dict with hit points or error message.
	"""
	if not camera or not connect_mode_target_a or not connect_mode_target_b:
		return {"success": false, "error_message": "Invalid state"}

	var viewport_pos = viewport_container.get_local_mouse_position()
	var ray_origin = camera.project_ray_origin(viewport_pos)
	var ray_direction = camera.project_ray_normal(viewport_pos)
	var ray_length = connect_mode_max_ray_distance

	print("\nRaycast setup:")
	print("  Origin: %.2f, %.2f, %.2f" % [ray_origin.x, ray_origin.y, ray_origin.z])
	print("  Direction: %.2f, %.2f, %.2f" % [ray_direction.x, ray_direction.y, ray_direction.z])
	print("  Max distance: %.2f" % ray_length)

	var space_state = viewport.world_3d.direct_space_state

	# Collect all hits along the ray by doing multiple raycasts
	var all_hits = []
	var current_origin = ray_origin
	var remaining_length = ray_length
	var max_iterations = 20  # Safety limit

	for i in range(max_iterations):
		var ray_query = PhysicsRayQueryParameters3D.create(current_origin, current_origin + ray_direction * remaining_length)
		ray_query.collision_mask = 4
		ray_query.collide_with_bodies = true
		ray_query.hit_from_inside = true

		var result = space_state.intersect_ray(ray_query)

		if not result or not result.collider:
			break  # No more hits

		all_hits.append(result)

		# Move past this hit point
		var distance_to_hit = current_origin.distance_to(result.position)
		current_origin = result.position + ray_direction * 0.01  # 1cm past
		remaining_length -= (distance_to_hit + 0.01)

		if remaining_length <= 0:
			break

	# Debug output
	print("Connect Mode: Found %d total intersection points along ray" % all_hits.size())
	if all_hits.size() > 0:
		for i in range(all_hits.size()):
			var hit = all_hits[i]
			if hit.collider is PhysicalItem:
				var target_label = ""
				if hit.collider == connect_mode_target_a:
					target_label = " [TARGET A]"
				elif hit.collider == connect_mode_target_b:
					target_label = " [TARGET B]"

				print("  Hit %d: %s%s at %.3f,%.3f,%.3f" % [i, hit.collider.item_name, target_label, hit.position.x, hit.position.y, hit.position.z])
	else:
		print("  ⚠️ NO HITS DETECTED!")

	# Find where ray transitions from one target to the other
	var exit_point: Vector3
	var entry_point: Vector3
	var first_object: PhysicalItem
	var second_object: PhysicalItem
	var found_transition = false

	print("Analyzing hit sequence to find object transition...")

	for i in range(all_hits.size() - 1):
		var current_hit = all_hits[i]
		var next_hit = all_hits[i + 1]

		var current_obj = current_hit.collider
		var next_obj = next_hit.collider

		var current_is_target = current_obj == connect_mode_target_a or current_obj == connect_mode_target_b
		var next_is_target = next_obj == connect_mode_target_a or next_obj == connect_mode_target_b

		if current_is_target and next_is_target and current_obj != next_obj:
			# Found it! Ray exits current object and enters next object
			exit_point = current_hit.position
			entry_point = next_hit.position
			first_object = current_obj
			second_object = next_obj
			found_transition = true

			print("✓ Found transition from %s to %s" % [first_object.item_name, second_object.item_name])
			print("  Exit point: %.3f,%.3f,%.3f" % [exit_point.x, exit_point.y, exit_point.z])
			print("  Entry point: %.3f,%.3f,%.3f" % [entry_point.x, entry_point.y, entry_point.z])
			break

	if not found_transition:
		# Check if we at least hit both objects
		var hit_target_a = false
		var hit_target_b = false
		for hit in all_hits:
			if hit.collider == connect_mode_target_a:
				hit_target_a = true
			if hit.collider == connect_mode_target_b:
				hit_target_b = true

		if not hit_target_a:
			return {"success": false, "error_message": "Ray didn't hit %s" % connect_mode_target_a.item_name}
		if not hit_target_b:
			return {"success": false, "error_message": "Ray didn't hit %s" % connect_mode_target_b.item_name}

		return {"success": false, "error_message": "Ray hit both objects but not consecutively"}

	# Calculate distance between exit and entry points
	var distance = exit_point.distance_to(entry_point)

	# Check if distance exceeds max bolt length
	if distance > connect_mode_max_bolt_length:
		return {"success": false, "error_message": "Distance too large (%.2fm > %.2fm max)" % [distance, connect_mode_max_bolt_length]}

	print("✓ Fastener placement:")
	print("  Exit from: %s at %.3f,%.3f,%.3f" % [first_object.item_name, exit_point.x, exit_point.y, exit_point.z])
	print("  Entry to: %s at %.3f,%.3f,%.3f" % [second_object.item_name, entry_point.x, entry_point.y, entry_point.z])
	print("  Distance: %.3fm" % distance)

	# Success!
	return {
		"success": true,
		"hit_point_a": exit_point,
		"hit_point_b": entry_point,
		"hit_item_a": first_object,
		"hit_item_b": second_object,
		"distance": distance,
		"ray_direction": ray_direction
	}


func _show_fire_line(mouse_pos: Vector2) -> void:
	"""
	Show a visual fire line from camera through the scene when firing the bolt gun.
	The line stays visible for FIRE_LINE_DURATION seconds.
	"""
	if not camera:
		print("WARNING: No camera for fire line")
		return

	# Create fire line if it doesn't exist yet
	if not connect_mode_fire_line:
		print("Creating fire line on demand...")
		_create_fire_line()

	if not connect_mode_fire_line:
		print("ERROR: Failed to create fire line!")
		return

	var viewport_pos = viewport_container.get_local_mouse_position()
	var ray_origin = camera.project_ray_origin(viewport_pos)
	var ray_direction = camera.project_ray_normal(viewport_pos)
	var ray_end = ray_origin + ray_direction * connect_mode_max_ray_distance

	_update_line_mesh(connect_mode_fire_line, ray_origin, ray_end)
	connect_mode_fire_line.visible = true
	fire_line_timer = FIRE_LINE_DURATION

	print("Fire line: Drawing from %.2f,%.2f,%.2f to %.2f,%.2f,%.2f" % [
		ray_origin.x, ray_origin.y, ray_origin.z,
		ray_end.x, ray_end.y, ray_end.z
	])
	print("🔫 BOLT GUN FIRED - Visual ray displayed for %.1fs" % FIRE_LINE_DURATION)

	fire_line_shown.emit()


func _create_fire_line() -> void:
	"""Create the fire line visual (bright orange)."""
	connect_mode_fire_line = MeshInstance3D.new()
	connect_mode_fire_line.name = "ConnectModeFireLine"

	var mesh = CylinderMesh.new()
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 1
	mesh.top_radius = 0.005  # 5mm radius
	mesh.bottom_radius = 0.005

	connect_mode_fire_line.mesh = mesh

	# Bright orange material with emission
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.4, 0.0, 0.9)  # Bright orange
	material.emission_enabled = true
	material.emission = Color(1.0, 0.5, 0.0)
	material.emission_energy_multiplier = 1.5
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true  # Always visible

	connect_mode_fire_line.set_surface_override_material(0, material)
	connect_mode_fire_line.visible = false

	world.add_child(connect_mode_fire_line)
	print("Connect Mode: Created fire line visual (bright orange)")


func _update_line_mesh(line: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	"""Update a line mesh to connect two points."""
	if not line:
		return

	var midpoint = (start + end) / 2.0
	var direction = end - start
	var distance = direction.length()

	# Position at midpoint
	line.global_position = midpoint

	# Scale to match distance
	var mesh = line.mesh as CylinderMesh
	if mesh:
		mesh.height = distance

	# Rotate to point from start to end
	if distance > 0.001:
		var up = direction.normalized()
		line.look_at(end, Vector3.UP)
		line.rotate_object_local(Vector3.RIGHT, PI / 2)  # Cylinder aligns with Y, we want it along direction
