class_name TransformGizmo
extends Node3D

## Visual transform gizmo for manipulating objects in 3D space.
## Displays colored arrows/circles/boxes for Move/Rotate/Scale modes.

enum GizmoMode { MOVE, ROTATE, SCALE }

var current_mode: GizmoMode = GizmoMode.MOVE
var gizmo_size: float = 1.5

# Visual components
var move_gizmo: Node3D
var rotate_gizmo: Node3D
var scale_gizmo: Node3D

# Materials
var material_x: StandardMaterial3D  # Red
var material_y: StandardMaterial3D  # Green
var material_z: StandardMaterial3D  # Blue
var material_highlight: StandardMaterial3D  # Yellow

# Interaction
var hovered_axis: Vector3 = Vector3.ZERO  # Currently hovered axis/plane
var is_dragging: bool = false
var drag_axis: String = ""

# Move gizmo node references for highlighting
var arrow_x_node: Node3D = null
var arrow_y_node: Node3D = null
var arrow_z_node: Node3D = null
var plane_xy_node: MeshInstance3D = null
var plane_xz_node: MeshInstance3D = null
var plane_yz_node: MeshInstance3D = null

# Rotate gizmo node references
var circle_x_node: MeshInstance3D = null
var circle_y_node: MeshInstance3D = null
var circle_z_node: MeshInstance3D = null

# Scale gizmo node references
var scale_x_node: Node3D = null
var scale_y_node: Node3D = null
var scale_z_node: Node3D = null
var scale_center_node: MeshInstance3D = null


func _ready() -> void:
	_create_materials()
	_create_move_gizmo()
	_create_rotate_gizmo()
	_create_scale_gizmo()

	# Start with move mode
	set_mode(GizmoMode.MOVE)


func _create_materials() -> void:
	"""Create colored materials for gizmo axes."""
	material_x = StandardMaterial3D.new()
	material_x.albedo_color = Color(1, 0, 0, 1)  # Red for X
	material_x.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_x.no_depth_test = true  # Always render on top
	material_x.disable_receive_shadows = true

	material_y = StandardMaterial3D.new()
	material_y.albedo_color = Color(0, 1, 0, 1)  # Green for Y
	material_y.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_y.no_depth_test = true  # Always render on top
	material_y.disable_receive_shadows = true

	material_z = StandardMaterial3D.new()
	material_z.albedo_color = Color(0, 0, 1, 1)  # Blue for Z
	material_z.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_z.no_depth_test = true  # Always render on top
	material_z.disable_receive_shadows = true

	material_highlight = StandardMaterial3D.new()
	material_highlight.albedo_color = Color(1, 1, 0, 1)  # Yellow for highlight
	material_highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_highlight.no_depth_test = true  # Always render on top
	material_highlight.disable_receive_shadows = true


func _create_move_gizmo() -> void:
	"""Create move gizmo (3 arrows + 3 plane handles)."""
	# Remove old gizmo if it exists
	if move_gizmo:
		move_gizmo.queue_free()

	move_gizmo = Node3D.new()
	move_gizmo.name = "MoveGizmo"
	add_child(move_gizmo)

	# X axis (Red arrow pointing right)
	arrow_x_node = _create_arrow(Vector3.RIGHT, material_x)
	arrow_x_node.name = "ArrowX"
	move_gizmo.add_child(arrow_x_node)

	# Y axis (Green arrow pointing up)
	arrow_y_node = _create_arrow(Vector3.UP, material_y)
	arrow_y_node.name = "ArrowY"
	move_gizmo.add_child(arrow_y_node)

	# Z axis (Blue arrow pointing back)
	arrow_z_node = _create_arrow(Vector3.BACK, material_z)
	arrow_z_node.name = "ArrowZ"
	move_gizmo.add_child(arrow_z_node)

	# Plane handles (small colored squares at axis intersections)
	# XY plane (Red+Green = Yellow)
	plane_xy_node = _create_plane_handle(Vector3.RIGHT, Vector3.UP, Color(1, 1, 0, 0.5))
	plane_xy_node.name = "PlaneXY"
	move_gizmo.add_child(plane_xy_node)

	# XZ plane (Red+Blue = Magenta)
	plane_xz_node = _create_plane_handle(Vector3.RIGHT, Vector3.BACK, Color(1, 0, 1, 0.5))
	plane_xz_node.name = "PlaneXZ"
	move_gizmo.add_child(plane_xz_node)

	# YZ plane (Green+Blue = Cyan)
	plane_yz_node = _create_plane_handle(Vector3.UP, Vector3.BACK, Color(0, 1, 1, 0.5))
	plane_yz_node.name = "PlaneYZ"
	move_gizmo.add_child(plane_yz_node)


func _create_arrow(direction: Vector3, material: StandardMaterial3D) -> Node3D:
	"""Create a single arrow mesh for an axis (shaft + cone tip)."""
	var arrow_node = Node3D.new()

	# Shaft (cylinder) - thicker for easier clicking
	var shaft = MeshInstance3D.new()
	var shaft_mesh = CylinderMesh.new()
	shaft_mesh.top_radius = 0.01 * gizmo_size  # Much thicker
	shaft_mesh.bottom_radius = 0.01 * gizmo_size
	shaft_mesh.height = 0.8 * gizmo_size
	shaft.mesh = shaft_mesh
	shaft.material_override = material

	# Position shaft along axis - starting from center, extending outward
	# Shaft center is at 0.4 (half of 0.8 height from origin)
	shaft.position = direction * 0.4 * gizmo_size

	# Rotate to align with direction
	if direction == Vector3.RIGHT:
		shaft.rotation.z = -PI / 2
	elif direction == Vector3.FORWARD:
		shaft.rotation.x = PI / 2
	elif direction == Vector3.BACK:
		shaft.rotation.x = -PI / 2
	# UP is default orientation for cylinder

	arrow_node.add_child(shaft)

	# Cone tip
	var tip = MeshInstance3D.new()
	var tip_mesh = CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.03 * gizmo_size  # Wide base for visibility
	tip_mesh.height = 0.15 * gizmo_size
	tip.mesh = tip_mesh
	tip.material_override = material

	# Position tip at end of shaft
	# Shaft ends at 0.8, tip center is at 0.8 + 0.075 (half of tip height)
	tip.position = direction * 0.875 * gizmo_size

	# Rotate to align with direction
	if direction == Vector3.RIGHT:
		tip.rotation.z = -PI / 2
	elif direction == Vector3.FORWARD:
		tip.rotation.x = PI / 2
	elif direction == Vector3.BACK:
		tip.rotation.x = PI / 2  # Same as FORWARD, pointing along the axis

	arrow_node.add_child(tip)

	return arrow_node


func _create_plane_handle(axis1: Vector3, axis2: Vector3, color: Color) -> MeshInstance3D:
	"""Create a plane handle (small quad) for 2-axis dragging."""
	var plane = MeshInstance3D.new()

	# Create a small quad mesh
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(0.2, 0.2) * gizmo_size
	plane.mesh = quad_mesh

	# Create semi-transparent material
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from both sides
	mat.no_depth_test = true  # Always render on top
	mat.disable_receive_shadows = true
	plane.material_override = mat

	# Position at the intersection of the two axes
	plane.position = (axis1 + axis2) * 0.15 * gizmo_size

	# Orient the plane to face the right direction
	# The quad faces -Z by default, so we need to rotate it
	if axis1 == Vector3.RIGHT and axis2 == Vector3.UP:
		# XY plane - no rotation needed (faces Z)
		pass
	elif axis1 == Vector3.RIGHT and axis2 == Vector3.BACK:
		# XZ plane - rotate 90 degrees around X
		plane.rotation.x = PI / 2
	elif axis1 == Vector3.UP and axis2 == Vector3.BACK:
		# YZ plane - rotate 90 degrees around Y
		plane.rotation.y = PI / 2

	return plane


func _create_torus_circle(axis: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	"""Create a torus circle for rotation visualization with depth-aware rendering."""
	var torus = MeshInstance3D.new()
	var torus_mesh = TorusMesh.new()
	torus_mesh.inner_radius = 0.69 * gizmo_size
	torus_mesh.outer_radius = 0.71 * gizmo_size  # Thin torus (0.02 thickness)
	torus_mesh.rings = 64  # Very smooth circle
	torus_mesh.ring_segments = 6  # Thin profile
	torus.mesh = torus_mesh

	# Create a depth-aware material for rotation circles
	# This allows proper visual feedback about which circle is in front
	var depth_material = StandardMaterial3D.new()
	depth_material.albedo_color = material.albedo_color
	depth_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	depth_material.disable_receive_shadows = true

	# Enable depth testing for rotation circles to show proper occlusion
	# but disable depth writing so they don't occlude each other completely
	depth_material.no_depth_test = false  # Enable depth test
	depth_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED  # But don't write depth

	# Add slight transparency to show overlapping circles
	depth_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	depth_material.albedo_color.a = 0.9  # Slightly transparent

	# Render hint for better blending
	depth_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	depth_material.cull_mode = BaseMaterial3D.CULL_BACK  # Cull back faces for cleaner look

	torus.material_override = depth_material

	# Rotate the torus to align with the axis
	# Torus default: lies in XZ plane (circle around Y axis)
	if axis == Vector3.RIGHT:
		# X axis - circle should be in YZ plane (rotate around X)
		torus.rotation.z = PI / 2
	elif axis == Vector3.UP:
		# Y axis - circle should be in XZ plane (rotate around Y)
		pass  # Default orientation is correct
	elif axis == Vector3.BACK:
		# Z axis - circle should be in XY plane (rotate around Z)
		torus.rotation.x = PI / 2

	return torus


func _create_scale_handle(direction: Vector3, material: StandardMaterial3D) -> Node3D:
	"""Create a scale handle (line + box at end)."""
	var handle_node = Node3D.new()

	# Line/shaft (thin cylinder) - extends from center outward
	var shaft = MeshInstance3D.new()
	var shaft_mesh = CylinderMesh.new()
	shaft_mesh.top_radius = 0.008 * gizmo_size
	shaft_mesh.bottom_radius = 0.008 * gizmo_size
	shaft_mesh.height = 0.7 * gizmo_size
	shaft.mesh = shaft_mesh
	shaft.material_override = material

	# Position shaft so it starts at center (0,0,0)
	# Shaft center is at half its height from origin
	shaft.position = direction * 0.35 * gizmo_size

	# Rotate to align with direction
	if direction == Vector3.RIGHT:
		shaft.rotation.z = -PI / 2
	elif direction == Vector3.FORWARD:
		shaft.rotation.x = PI / 2
	elif direction == Vector3.BACK:
		shaft.rotation.x = -PI / 2
	# UP is default orientation for cylinder

	handle_node.add_child(shaft)

	# Box at end
	var box = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3.ONE * 0.05 * gizmo_size
	box.mesh = box_mesh
	box.material_override = material

	# Position box at end of shaft (at 0.7 from center)
	box.position = direction * 0.7 * gizmo_size

	handle_node.add_child(box)

	return handle_node


func _create_rotate_gizmo() -> void:
	"""Create rotate gizmo (3 torus circles for each axis)."""
	# Remove old gizmo if it exists
	if rotate_gizmo:
		rotate_gizmo.queue_free()

	rotate_gizmo = Node3D.new()
	rotate_gizmo.name = "RotateGizmo"
	add_child(rotate_gizmo)

	# X axis circle (Red, rotates around X)
	circle_x_node = _create_torus_circle(Vector3.RIGHT, material_x)
	circle_x_node.name = "CircleX"
	rotate_gizmo.add_child(circle_x_node)

	# Y axis circle (Green, rotates around Y)
	circle_y_node = _create_torus_circle(Vector3.UP, material_y)
	circle_y_node.name = "CircleY"
	rotate_gizmo.add_child(circle_y_node)

	# Z axis circle (Blue, rotates around Z)
	circle_z_node = _create_torus_circle(Vector3.BACK, material_z)
	circle_z_node.name = "CircleZ"
	rotate_gizmo.add_child(circle_z_node)

	rotate_gizmo.visible = false


func _create_scale_gizmo() -> void:
	"""Create scale gizmo (3 lines with boxes at ends)."""
	# Remove old gizmo if it exists
	if scale_gizmo:
		scale_gizmo.queue_free()

	scale_gizmo = Node3D.new()
	scale_gizmo.name = "ScaleGizmo"
	add_child(scale_gizmo)

	# X axis (Red line + box)
	scale_x_node = _create_scale_handle(Vector3.RIGHT, material_x)
	scale_x_node.name = "ScaleX"
	scale_gizmo.add_child(scale_x_node)

	# Y axis (Green line + box)
	scale_y_node = _create_scale_handle(Vector3.UP, material_y)
	scale_y_node.name = "ScaleY"
	scale_gizmo.add_child(scale_y_node)

	# Z axis (Blue line + box)
	scale_z_node = _create_scale_handle(Vector3.BACK, material_z)
	scale_z_node.name = "ScaleZ"
	scale_gizmo.add_child(scale_z_node)

	# Center box for uniform scaling
	scale_center_node = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3.ONE * 0.08 * gizmo_size
	scale_center_node.mesh = box_mesh
	var white_mat = StandardMaterial3D.new()
	white_mat.albedo_color = Color(1, 1, 1, 1)
	white_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white_mat.no_depth_test = true
	white_mat.disable_receive_shadows = true
	scale_center_node.material_override = white_mat
	scale_center_node.name = "CenterBox"
	scale_gizmo.add_child(scale_center_node)

	scale_gizmo.visible = false


func set_mode(mode: GizmoMode) -> void:
	"""Switch between Move/Rotate/Scale modes."""
	current_mode = mode

	# Hide all gizmos
	if move_gizmo:
		move_gizmo.visible = false
	if rotate_gizmo:
		rotate_gizmo.visible = false
	if scale_gizmo:
		scale_gizmo.visible = false

	# Show active gizmo
	match mode:
		GizmoMode.MOVE:
			if move_gizmo:
				move_gizmo.visible = true
		GizmoMode.ROTATE:
			if rotate_gizmo:
				rotate_gizmo.visible = true
		GizmoMode.SCALE:
			if scale_gizmo:
				scale_gizmo.visible = true


func set_target_position(pos: Vector3) -> void:
	"""Position the gizmo at the target object."""
	global_position = pos


func update_scale_for_camera(camera_pos: Vector3) -> void:
	"""Keep gizmo at a fixed screen size regardless of camera distance."""
	# Scale proportionally to distance to maintain constant screen size
	var distance = global_position.distance_to(camera_pos)
	# This multiplier keeps the gizmo at a fixed viewport size
	var target_scale = distance * 0.05
	scale = Vector3.ONE * target_scale


func set_hover(axis: Vector3) -> void:
	"""Highlight the hovered axis/plane."""
	if hovered_axis == axis:
		return  # Already set

	# Clear previous highlight
	_clear_highlight()

	hovered_axis = axis

	# Apply highlight based on current mode and axis
	if current_mode == GizmoMode.MOVE:
		# Move gizmo highlighting
		if axis == Vector3.RIGHT:
			_highlight_arrow(arrow_x_node)
		elif axis == Vector3.UP:
			_highlight_arrow(arrow_y_node)
		elif axis == Vector3.BACK:
			_highlight_arrow(arrow_z_node)
		elif axis == Vector3(1, 1, 0):  # XY plane
			_highlight_plane(plane_xy_node)
		elif axis == Vector3(1, 0, -1):  # XZ plane
			_highlight_plane(plane_xz_node)
		elif axis == Vector3(0, 1, -1):  # YZ plane
			_highlight_plane(plane_yz_node)

	elif current_mode == GizmoMode.ROTATE:
		# Rotate gizmo highlighting
		if axis == Vector3.RIGHT:
			_highlight_mesh(circle_x_node)
		elif axis == Vector3.UP:
			_highlight_mesh(circle_y_node)
		elif axis == Vector3.BACK:
			_highlight_mesh(circle_z_node)

	elif current_mode == GizmoMode.SCALE:
		# Scale gizmo highlighting
		if axis == Vector3.RIGHT:
			_highlight_scale_handle(scale_x_node)
		elif axis == Vector3.UP:
			_highlight_scale_handle(scale_y_node)
		elif axis == Vector3.BACK:
			_highlight_scale_handle(scale_z_node)
		elif axis == Vector3(1, 1, 1):  # Uniform scale (center box)
			_highlight_mesh(scale_center_node)


func _highlight_arrow(arrow: Node3D) -> void:
	"""Apply highlight material to an arrow."""
	if not arrow:
		return
	for child in arrow.get_children():
		if child is MeshInstance3D:
			child.material_override = material_highlight


func _highlight_plane(plane: MeshInstance3D) -> void:
	"""Apply brighter highlight to a plane."""
	if not plane:
		return
	var bright_mat = StandardMaterial3D.new()
	bright_mat.albedo_color = Color(1, 1, 0, 0.8)  # Brighter yellow
	bright_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bright_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bright_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bright_mat.no_depth_test = true
	bright_mat.disable_receive_shadows = true
	plane.material_override = bright_mat


func _highlight_mesh(mesh: MeshInstance3D) -> void:
	"""Apply highlight material to a single mesh (for circles and center box)."""
	if not mesh:
		return

	# For rotation circles, create a depth-aware highlight material
	if mesh.get_parent() == rotate_gizmo:
		var highlight_mat = StandardMaterial3D.new()
		highlight_mat.albedo_color = Color(1, 1, 0, 1)  # Bright yellow
		highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		highlight_mat.disable_receive_shadows = true

		# Match the depth settings from rotation circles
		highlight_mat.no_depth_test = false
		highlight_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		highlight_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		highlight_mat.cull_mode = BaseMaterial3D.CULL_BACK

		mesh.material_override = highlight_mat
	else:
		# For other meshes, use the standard highlight material
		mesh.material_override = material_highlight


func _highlight_scale_handle(handle: Node3D) -> void:
	"""Apply highlight material to a scale handle (line + box)."""
	if not handle:
		return
	for child in handle.get_children():
		if child is MeshInstance3D:
			child.material_override = material_highlight


func _clear_highlight() -> void:
	"""Clear all highlights and restore original materials."""
	# Restore move gizmo materials
	if arrow_x_node:
		_restore_arrow_material(arrow_x_node, material_x)
	if arrow_y_node:
		_restore_arrow_material(arrow_y_node, material_y)
	if arrow_z_node:
		_restore_arrow_material(arrow_z_node, material_z)

	if plane_xy_node:
		_restore_plane_material(plane_xy_node, Color(1, 1, 0, 0.5))
	if plane_xz_node:
		_restore_plane_material(plane_xz_node, Color(1, 0, 1, 0.5))
	if plane_yz_node:
		_restore_plane_material(plane_yz_node, Color(0, 1, 1, 0.5))

	# Restore rotate gizmo materials with depth-aware rendering
	if circle_x_node:
		_restore_rotation_circle_material(circle_x_node, material_x)
	if circle_y_node:
		_restore_rotation_circle_material(circle_y_node, material_y)
	if circle_z_node:
		_restore_rotation_circle_material(circle_z_node, material_z)

	# Restore scale gizmo materials
	if scale_x_node:
		_restore_arrow_material(scale_x_node, material_x)
	if scale_y_node:
		_restore_arrow_material(scale_y_node, material_y)
	if scale_z_node:
		_restore_arrow_material(scale_z_node, material_z)
	if scale_center_node:
		var white_mat = StandardMaterial3D.new()
		white_mat.albedo_color = Color(1, 1, 1, 1)
		white_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		white_mat.no_depth_test = true
		white_mat.disable_receive_shadows = true
		scale_center_node.material_override = white_mat


func _restore_arrow_material(arrow: Node3D, original_mat: StandardMaterial3D) -> void:
	"""Restore original material to an arrow."""
	if not arrow:
		return
	for child in arrow.get_children():
		if child is MeshInstance3D:
			child.material_override = original_mat


func _restore_plane_material(plane: MeshInstance3D, original_color: Color) -> void:
	"""Restore original material to a plane."""
	if not plane:
		return
	var mat = StandardMaterial3D.new()
	mat.albedo_color = original_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.disable_receive_shadows = true
	plane.material_override = mat


func _restore_rotation_circle_material(circle: MeshInstance3D, base_material: StandardMaterial3D) -> void:
	"""Restore original depth-aware material to a rotation circle."""
	if not circle:
		return

	var depth_material = StandardMaterial3D.new()
	depth_material.albedo_color = base_material.albedo_color
	depth_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	depth_material.disable_receive_shadows = true

	# Restore depth-aware settings
	depth_material.no_depth_test = false
	depth_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	depth_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	depth_material.albedo_color.a = 0.9
	depth_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	depth_material.cull_mode = BaseMaterial3D.CULL_BACK

	circle.material_override = depth_material
