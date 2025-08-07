# scripts/inventory/shared/interfaces/IInventoryRenderer.gd
class_name IInventoryRenderer

# Renderer interface definition
# All inventory display systems should implement these methods

# Display operations
func refresh_display():
	push_error("IInventoryRenderer.refresh_display() not implemented")

func set_container(container: InventoryContainer_Base):
	push_error("IInventoryRenderer.set_container() not implemented")

func clear_display():
	push_error("IInventoryRenderer.clear_display() not implemented")

# Interaction handling
func handle_item_drop(item: InventoryItem_Base, position: Vector2) -> bool:
	push_error("IInventoryRenderer.handle_item_drop() not implemented")
	return false

func handle_item_selection(item: InventoryItem_Base):
	push_error("IInventoryRenderer.handle_item_selection() not implemented")

# Visual feedback
func show_drop_preview(position: Vector2, item: InventoryItem_Base):
	push_error("IInventoryRenderer.show_drop_preview() not implemented")

func hide_drop_preview():
	push_error("IInventoryRenderer.hide_drop_preview() not implemented")