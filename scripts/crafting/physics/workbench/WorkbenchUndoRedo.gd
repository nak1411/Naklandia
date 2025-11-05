class_name WorkbenchUndoRedo
extends RefCounted

## Manages undo/redo operations for the workbench.
##
## Tracks transform operations (move, rotate, scale) and allows
## reverting or reapplying changes with Ctrl+Z and Ctrl+Shift+Z.

signal operation_recorded(operation_type: String)
signal undo_performed()
signal redo_performed()
signal history_changed(undo_count: int, redo_count: int)

const MAX_UNDO_OPERATIONS: int = 10

var undo_history: Array = []  # Array of command dictionaries
var redo_history: Array = []  # Array of command dictionaries for redo


func record_transform(
	operation_type: String,
	items: Array,
	initial_values: Dictionary,
	final_values: Dictionary
) -> void:
	"""
	Record a transform operation for undo/redo.

	Args:
		operation_type: Type of operation ("move", "rotate", "scale")
		items: Array of items that were transformed
		initial_values: Dictionary mapping items to their initial values
		final_values: Dictionary mapping items to their final values
	"""
	if items.is_empty() or initial_values.is_empty():
		return

	var command = {
		"type": operation_type,
		"items": items.duplicate(),
		"old_values": initial_values.duplicate(true),
		"new_values": final_values.duplicate(true)
	}

	# Only record if values actually changed
	var has_changes = false
	for item in command["old_values"].keys():
		if command["old_values"][item] != command["new_values"][item]:
			has_changes = true
			break

	if has_changes:
		# Add to history
		undo_history.append(command)

		# Clear redo history when a new operation is recorded
		redo_history.clear()

		# Limit history size to MAX_UNDO_OPERATIONS
		if undo_history.size() > MAX_UNDO_OPERATIONS:
			undo_history.pop_front()

		print("Recorded undo: ", command["type"], " (", undo_history.size(), "/", MAX_UNDO_OPERATIONS, " operations)")
		operation_recorded.emit(operation_type)
		history_changed.emit(undo_history.size(), redo_history.size())


func undo() -> bool:
	"""
	Undo the last transform operation.
	Returns true if successful, false otherwise.
	"""
	if undo_history.is_empty():
		print("Nothing to undo")
		return false

	var command = undo_history.pop_back()
	print("Undoing operation: ", command["type"], " affecting ", command["items"].size(), " items")

	# Verify all items still exist
	if not _verify_items_exist(command["items"]):
		print("Cannot undo: some items no longer exist")
		return false

	print("Items verified, applying transform...")
	# Apply the old values
	_apply_transform(command["type"], command["old_values"])

	# Add to redo history
	redo_history.append(command)

	# Limit redo history size
	if redo_history.size() > MAX_UNDO_OPERATIONS:
		redo_history.pop_front()

	print("Undo completed (", undo_history.size(), " undo | ", redo_history.size(), " redo)")
	undo_performed.emit()
	history_changed.emit(undo_history.size(), redo_history.size())
	return true


func redo() -> bool:
	"""
	Redo the last undone operation.
	Returns true if successful, false otherwise.
	"""
	if redo_history.is_empty():
		print("Nothing to redo")
		return false

	var command = redo_history.pop_back()

	# Verify all items still exist
	if not _verify_items_exist(command["items"]):
		print("Cannot redo: some items no longer exist")
		return false

	# Apply the new values (the ones that were undone)
	_apply_transform(command["type"], command["new_values"])

	# Add back to undo history
	undo_history.append(command)

	# Limit undo history size
	if undo_history.size() > MAX_UNDO_OPERATIONS:
		undo_history.pop_front()

	print("Redo completed (", undo_history.size(), " undo | ", redo_history.size(), " redo)")
	redo_performed.emit()
	history_changed.emit(undo_history.size(), redo_history.size())
	return true


func clear_history() -> void:
	"""Clear all undo and redo history."""
	undo_history.clear()
	redo_history.clear()
	history_changed.emit(0, 0)
	print("Undo/Redo history cleared")


func has_undo() -> bool:
	"""Returns true if there are operations to undo."""
	return not undo_history.is_empty()


func has_redo() -> bool:
	"""Returns true if there are operations to redo."""
	return not redo_history.is_empty()


func get_undo_count() -> int:
	"""Returns the number of operations that can be undone."""
	return undo_history.size()


func get_redo_count() -> int:
	"""Returns the number of operations that can be redone."""
	return redo_history.size()


# Private helper methods

func _verify_items_exist(items: Array) -> bool:
	"""Verify that all items in the array still exist and are valid."""
	for item in items:
		if not is_instance_valid(item) or not item.is_inside_tree():
			return false
	return true


func _apply_transform(operation_type: String, values: Dictionary) -> void:
	"""Apply transform values to items based on operation type."""
	print("_apply_transform called with type: '", operation_type, "' and ", values.size(), " values")
	match operation_type:
		"move":
			for item in values.keys():
				if is_instance_valid(item):
					item.global_position = values[item]
			print("Applied move operation to ", values.size(), " items")

		"rotate":
			for item in values.keys():
				if is_instance_valid(item):
					var old_basis = item.basis
					item.basis = values[item]
					print("  Item rotation: ", item.rotation_degrees, " (basis changed: ", old_basis != item.basis, ")")
			print("Applied rotate operation to ", values.size(), " items")

		"scale":
			for item in values.keys():
				if is_instance_valid(item):
					item.scale = values[item]
			print("Applied scale operation to ", values.size(), " items")
