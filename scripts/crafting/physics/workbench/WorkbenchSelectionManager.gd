class_name WorkbenchSelectionManager
extends RefCounted

## Manages object selection, hover detection, and box selection for the workbench.
##
## Handles:
## - Single click selection with raycasting
## - Multi-select with Shift key
## - Box selection (drag to create selection rectangle)
## - Cluster selection (bonded items select together)

signal selection_changed(selected_items: Array[PhysicalItem])
signal hover_changed(hovered_item: PhysicalItem)
signal items_deleted(count: int)

# References
var camera: Camera3D
var viewport: SubViewport
var viewport_container: SubViewportContainer
var world: Node3D
var selection_overlay: Control

# Selection state
var selected_items: Array[PhysicalItem] = []
var hovered_item: PhysicalItem = null
var cluster_pivot_point: Vector3 = Vector3.ZERO
var cluster_pivot_active: bool = false

# Box selection
var is_box_selecting: bool = false
var box_select_start: Vector2
var box_select_end: Vector2


func _init(
	p_camera: Camera3D,
	p_viewport: SubViewport,
	p_viewport_container: SubViewportContainer,
	p_world: Node3D,
	p_selection_overlay: Control
) -> void:
	"""Initialize the selection manager."""
	camera = p_camera
	viewport = p_viewport
	viewport_container = p_viewport_container
	world = p_world
	selection_overlay = p_selection_overlay


func set_hovered_item(item: PhysicalItem) -> void:
	"""Set the currently hovered item."""
	if hovered_item != item:
		hovered_item = item
		hover_changed.emit(hovered_item)


func try_select_single(mouse_pos: Vector2, modifier_held: bool) -> void:
	"""Try to select a single item at mouse position.
	modifier_held can be shift (add) or ctrl (toggle/deselect)."""
	if not camera:
		return

	var viewport_pos = viewport_container.get_local_mouse_position()
	var from = camera.project_ray_origin(viewport_pos)
	var to = from + camera.project_ray_normal(viewport_pos) * 100.0

	var space_state = viewport.world_3d.direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 4

	var result = space_state.intersect_ray(query)

	if result and result.collider is PhysicalItem:
		var item = result.collider as PhysicalItem
		print("Raycast hit item: %s (instance: %s)" % [item.item_name, item.get_instance_id()])

		# Check if modifier is held for multi-select/deselect
		if modifier_held:
			# Toggle selection - deselect if already selected, select if not
			if item in selected_items:
				deselect_item(item)
			else:
				select_item_with_cluster(item, true)  # Add cluster to selection
		else:
			# Single select (clear others)
			clear_selection()
			select_item_with_cluster(item, false)  # Select entire cluster
	else:
		print("Raycast hit nothing")
		# Clicked empty space - deselect all only if no modifier held
		if not modifier_held:
			clear_selection()


func start_box_select(mouse_pos: Vector2) -> void:
	"""Start a box selection operation."""
	is_box_selecting = true
	box_select_start = mouse_pos
	box_select_end = mouse_pos


func update_box_select(mouse_pos: Vector2) -> void:
	"""Update the box selection end position."""
	box_select_end = mouse_pos


func finish_box_select(shift_held: bool = false, ctrl_held: bool = false) -> void:
	"""Complete the box selection and select items within the box."""
	try_box_select(shift_held, ctrl_held)
	is_box_selecting = false


func cancel_box_select() -> void:
	"""Cancel the box selection without selecting anything."""
	is_box_selecting = false


func try_box_select(shift_held: bool = false, ctrl_held: bool = false) -> void:
	"""Select all items within the box selection area."""
	if not camera or not world:
		return

	# Create selection rectangle (normalize in case user dragged backwards)
	var rect_min = Vector2(min(box_select_start.x, box_select_end.x), min(box_select_start.y, box_select_end.y))
	var rect_max = Vector2(max(box_select_start.x, box_select_end.x), max(box_select_start.y, box_select_end.y))
	var selection_rect = Rect2(rect_min, rect_max - rect_min)

	# Check if box is too small (probably just a click)
	if selection_rect.size.length() < 5.0:
		# Treat as single click selection
		try_select_single(box_select_start, shift_held or ctrl_held)
		return

	# Find all PhysicalItems in the world and test with raycasting for accuracy
	var space_state = viewport.world_3d.direct_space_state
	var items_to_select: Array[PhysicalItem] = []

	for child in world.get_children():
		if child is PhysicalItem:
			var item = child as PhysicalItem

			# Get the item's AABB (bounding box) in local space
			var aabb: AABB

			# For JointHelper, use a small AABB around the cross shape (15cm bars)
			if item is JointHelper:
				aabb = AABB(Vector3(-0.075, -0.075, -0.075), Vector3(0.15, 0.15, 0.15))
			elif item.has_node("MeshInstance3D"):
				var mesh_instance = item.get_node("MeshInstance3D") as MeshInstance3D
				if mesh_instance and mesh_instance.mesh:
					aabb = mesh_instance.get_aabb()
			else:
				# Fallback: use a small box around the origin
				aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1))

			# Transform the 8 corners of the AABB to world space
			var item_transform = item.global_transform
			var corners = [
				item_transform * (aabb.position),
				item_transform * (aabb.position + Vector3(aabb.size.x, 0, 0)),
				item_transform * (aabb.position + Vector3(0, aabb.size.y, 0)),
				item_transform * (aabb.position + Vector3(0, 0, aabb.size.z)),
				item_transform * (aabb.position + Vector3(aabb.size.x, aabb.size.y, 0)),
				item_transform * (aabb.position + Vector3(aabb.size.x, 0, aabb.size.z)),
				item_transform * (aabb.position + Vector3(0, aabb.size.y, aabb.size.z)),
				item_transform * (aabb.position + aabb.size)
			]

			# Check visibility: only select if object is in front of camera
			var is_in_front = false
			for corner in corners:
				var to_corner = corner - camera.global_position
				var forward = -camera.global_transform.basis.z
				if to_corner.dot(forward) > 0:
					is_in_front = true
					break

			if not is_in_front:
				continue

			# Project all corners to screen space
			var screen_corners: Array[Vector2] = []
			for corner in corners:
				screen_corners.append(camera.unproject_position(corner))

			# Create screen-space bounding rect for the item
			var screen_min = Vector2(INF, INF)
			var screen_max = Vector2(-INF, -INF)
			for screen_pos in screen_corners:
				screen_min.x = min(screen_min.x, screen_pos.x)
				screen_min.y = min(screen_min.y, screen_pos.y)
				screen_max.x = max(screen_max.x, screen_pos.x)
				screen_max.y = max(screen_max.y, screen_pos.y)
			var item_screen_rect = Rect2(screen_min, screen_max - screen_min)

			# Check if rectangles intersect (crossing mode - any overlap counts)
			if selection_rect.intersects(item_screen_rect, true):
				# Generate multiple test points across the overlap area for raycasting
				# This ensures we detect objects even if only part of them overlaps
				var overlap_rect = selection_rect.intersection(item_screen_rect)

				if not overlap_rect.has_area():
					continue

				var test_points: Array[Vector2] = []

				# Sample points in a grid across the overlap area
				# Use 3x3 grid for better coverage
				var grid_size = 3
				for i in range(grid_size):
					for j in range(grid_size):
						var x = overlap_rect.position.x + (overlap_rect.size.x * i / float(grid_size - 1) if grid_size > 1 else 0)
						var y = overlap_rect.position.y + (overlap_rect.size.y * j / float(grid_size - 1) if grid_size > 1 else 0)
						test_points.append(Vector2(x, y))

				# Also add the center point
				test_points.append(overlap_rect.position + overlap_rect.size * 0.5)

				# Raycast test - if any test point hits this object, include it
				var is_visible = false
				for test_point in test_points:
					var from = camera.project_ray_origin(test_point)
					var to = from + camera.project_ray_normal(test_point) * 100.0

					var query = PhysicsRayQueryParameters3D.create(from, to)
					query.collision_mask = 4

					var result = space_state.intersect_ray(query)
					if result and result.collider == item:
						is_visible = true
						break

				if is_visible:
					items_to_select.append(item)

	# Update selection
	if items_to_select.size() > 0:
		# Build a set of all unique clusters/items to select
		# This prevents selecting the same cluster multiple times
		var clusters_to_select: Array[Array] = []
		var processed_items: Array[PhysicalItem] = []

		for item in items_to_select:
			# Skip if already processed as part of another cluster
			if item in processed_items:
				continue

			# Get the cluster for this item
			var cluster = item.get_bonded_cluster()

			# Mark all items in this cluster as processed
			for cluster_item in cluster:
				if cluster_item not in processed_items:
					processed_items.append(cluster_item)

			# Add the cluster to our list
			clusters_to_select.append(cluster)

		# Ctrl = deselect mode
		if ctrl_held:
			for cluster in clusters_to_select:
				for item in cluster:
					deselect_item(item)
			print("Box deselected ", clusters_to_select.size(), " cluster(s)")
		# Shift = add to selection, Normal = replace selection
		else:
			if not shift_held:
				clear_selection()

			# Select all items from all clusters
			var total_selected = 0
			for cluster in clusters_to_select:
				for item in cluster:
					if item not in selected_items:
						selected_items.append(item)
						item.show_highlight(true)
						total_selected += 1

			# Determine if we should use cluster pivot
			# Only use cluster pivot if we selected exactly ONE cluster with multiple items
			if clusters_to_select.size() == 1 and clusters_to_select[0].size() > 1:
				var cluster = clusters_to_select[0]
				# Calculate cluster pivot point (average of all fastener connection points)
				var connection_points: Array[Vector3] = []
				for cluster_item in cluster:
					for fastener in cluster_item.fasteners:
						if fastener.joint and fastener.joint.joint_node:
							connection_points.append(fastener.joint.joint_node.global_position)

				if connection_points.size() > 0:
					cluster_pivot_point = Vector3.ZERO
					for point in connection_points:
						cluster_pivot_point += point
					cluster_pivot_point /= connection_points.size()
					cluster_pivot_active = true
					print("Box selected 1 cluster (%d items) - pivot active" % cluster.size())
				else:
					cluster_pivot_active = false
					print("Box selected 1 cluster (%d items) - no pivot (no joints)" % cluster.size())
			else:
				# Multiple clusters or single items - no cluster pivot
				cluster_pivot_active = false
				print("Box selected %d cluster(s) with %d total items" % [clusters_to_select.size(), total_selected])

			selection_changed.emit(selected_items)
	else:
		# No items selected - clear selection only if neither shift nor ctrl is held
		if not shift_held and not ctrl_held:
			clear_selection()


func select_item(item: PhysicalItem, add_to_selection: bool) -> void:
	"""Select an item."""
	if not add_to_selection:
		clear_selection()

	if item not in selected_items:
		selected_items.append(item)
		item.show_highlight(true)
		print("Selected: ", item.item_name, " (", selected_items.size(), " total)")

	selection_changed.emit(selected_items)


func select_item_with_cluster(item: PhysicalItem, add_to_selection: bool) -> void:
	"""Select an item and its entire bonded cluster."""
	if not add_to_selection:
		clear_selection()

	# Get the entire bonded cluster
	var cluster = item.get_bonded_cluster()

	if cluster.size() > 1:
		print("Selecting bonded cluster of %d items" % cluster.size())

		# Calculate cluster pivot point (average of all fastener connection points)
		var connection_points: Array[Vector3] = []
		for cluster_item in cluster:
			for fastener in cluster_item.fasteners:
				if fastener.joint and fastener.joint.joint_node:
					connection_points.append(fastener.joint.joint_node.global_position)

		if connection_points.size() > 0:
			cluster_pivot_point = Vector3.ZERO
			for point in connection_points:
				cluster_pivot_point += point
			cluster_pivot_point /= connection_points.size()
			cluster_pivot_active = true
			print("✓ Cluster pivot set to: %.3f, %.3f, %.3f (from %d joints)" % [cluster_pivot_point.x, cluster_pivot_point.y, cluster_pivot_point.z, connection_points.size()])
		else:
			print("⚠️ No joints found for cluster pivot - using default center")
			cluster_pivot_active = false
	else:
		cluster_pivot_active = false

	# Select all items in cluster
	for cluster_item in cluster:
		if cluster_item not in selected_items:
			selected_items.append(cluster_item)
			cluster_item.show_highlight(true)

	print("Selected: %s and cluster (total: %d items)" % [item.item_name, cluster.size()])
	selection_changed.emit(selected_items)


func deselect_item(item: PhysicalItem) -> void:
	"""Deselect a specific item."""
	if item in selected_items:
		selected_items.erase(item)
		item.show_highlight(false)
		print("Deselected: ", item.item_name)
	selection_changed.emit(selected_items)


func clear_selection() -> void:
	"""Clear all selected items."""
	for item in selected_items:
		item.show_highlight(false)
	selected_items.clear()
	cluster_pivot_active = false
	selection_changed.emit(selected_items)


func select_all_items() -> void:
	"""Select all PhysicalItem objects in the world."""
	clear_selection()

	# Find all PhysicalItems in the world
	for child in world.get_children():
		if child is PhysicalItem:
			var item = child as PhysicalItem
			select_item(item, true)

	print("Selected all items (", selected_items.size(), " object(s))")


func delete_selected_items() -> void:
	"""Delete all currently selected items."""
	if selected_items.is_empty():
		return

	var count = selected_items.size()
	var fasteners_to_remove: Array[Fastener] = []

	# Collect all fasteners connected to the items being deleted
	for item in selected_items:
		if is_instance_valid(item):
			for fastener in item.fasteners:
				if fastener not in fasteners_to_remove:
					fasteners_to_remove.append(fastener)
					print("Marking fastener for deletion: %s <-> %s" % [fastener.item_a.item_name if fastener.item_a else "?", fastener.item_b.item_name if fastener.item_b else "?"])

	# Remove and destroy all fasteners
	for fastener in fasteners_to_remove:
		# Remove joint visual helper
		if fastener.joint and fastener.joint.joint_node:
			fastener.joint.joint_node.queue_free()
			print("  Deleted joint visual helper")

		# Destroy physics joint
		if fastener.joint:
			fastener.joint.destroy_physics_joint()

	# Remove all selected items from the scene
	for item in selected_items:
		if is_instance_valid(item):
			item.queue_free()

	# Clear selection array
	selected_items.clear()
	cluster_pivot_active = false

	print("Deleted %d object(s) and %d fastener(s)" % [count, fasteners_to_remove.size()])
	items_deleted.emit(count)
	selection_changed.emit(selected_items)


func update_cluster_pivot() -> void:
	"""Recalculate cluster pivot point based on current fastener positions."""
	if not cluster_pivot_active or selected_items.is_empty():
		return

	# Recalculate pivot from all fastener connection points in selected cluster
	var connection_points: Array[Vector3] = []
	for item in selected_items:
		for fastener in item.fasteners:
			if fastener.joint and fastener.joint.joint_node:
				connection_points.append(fastener.joint.joint_node.global_position)

	if connection_points.size() > 0:
		cluster_pivot_point = Vector3.ZERO
		for point in connection_points:
			cluster_pivot_point += point
		cluster_pivot_point /= connection_points.size()


func draw_selection_box(overlay: Control) -> void:
	"""Draw the box selection rectangle on the overlay."""
	if is_box_selecting:
		# Normalize rectangle to handle backwards dragging
		var rect_min = Vector2(min(box_select_start.x, box_select_end.x), min(box_select_start.y, box_select_end.y))
		var rect_size = Vector2(abs(box_select_end.x - box_select_start.x), abs(box_select_end.y - box_select_start.y))
		var rect = Rect2(rect_min, rect_size)

		overlay.draw_rect(rect, Color(0.3, 0.6, 1.0, 0.2), true)  # Fill
		overlay.draw_rect(rect, Color(0.5, 0.8, 1.0, 0.8), false, 2.0)  # Border


func get_selected_items() -> Array[PhysicalItem]:
	"""Get the currently selected items."""
	return selected_items


func has_selection() -> bool:
	"""Returns true if any items are selected."""
	return not selected_items.is_empty()


func get_selection_count() -> int:
	"""Returns the number of selected items."""
	return selected_items.size()
