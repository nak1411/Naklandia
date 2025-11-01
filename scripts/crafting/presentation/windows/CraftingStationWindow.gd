# CraftingStationWindow.gd - Simple crafting window with original layout
class_name CraftingStationWindow
extends Window_Base

# UI Components
var recipe_list_panel: Panel
var recipe_list: VBoxContainer
var recipe_scroll: ScrollContainer
var top_spacer: Control
var bottom_spacer: Control
var recipe_separator: HSeparator

var crafting_panel: Panel
var recipe_info_label: RichTextLabel
var requirements_label: RichTextLabel
var recipe_name_label: RichTextLabel
var recipe_details_label: RichTextLabel
var start_craft_button: Button

var process_panel: Panel
var stage_label: Label
var progress_bar: ProgressBar
var stage_description: RichTextLabel

var interaction_panel: Panel
var interaction_container: VBoxContainer

var output_panel: Panel
var output_grid: GridContainer

# Data
var crafting_manager: CraftingManager
var available_recipes: Array[CraftingRecipe] = []
var selected_recipe: CraftingRecipe = null
var is_crafting: bool = false


func _ready():
	window_title = "Crafting"
	default_size = Vector2(1000, 700)
	min_window_size = Vector2(800, 600)

	# Add to crafting_window group for hot-reload support
	add_to_group("crafting_window")

	super._ready()


func _setup_window_content():
	"""Override Window_Base virtual method to setup crafting UI"""
	print("CraftingStationWindow: _setup_window_content called")
	_setup_crafting_ui()
	print("CraftingStationWindow: UI setup complete")


func _setup_crafting_ui():
	"""Set up the main crafting UI layout"""
	print("Setting up crafting UI...")
	# Main horizontal split
	var main_split = HSplitContainer.new()
	main_split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_split.split_offset = 200
	content_area.clip_contents = true
	content_area.add_child(main_split)

	# Left side - Recipe list
	_setup_recipe_list_panel(main_split)

	# Right side - Crafting area
	var right_container = VBoxContainer.new()
	right_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_container.add_theme_constant_override("separation", 0)
	main_split.add_child(right_container)

	_setup_recipe_info_panel(right_container)
	_setup_process_panel(right_container)
	_setup_interaction_panel(right_container)

	print("Crafting UI setup complete - recipe_info_label: %s" % str(recipe_info_label))


func _setup_recipe_list_panel(parent: Control):
	"""Set up the recipe selection list"""
	recipe_list_panel = Panel.new()
	recipe_list_panel.size_flags_horizontal = Control.SIZE_FILL
	recipe_list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_list_panel.clip_contents = true
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.1)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.3, 0.3)
	recipe_list_panel.add_theme_stylebox_override("panel", panel_style)
	parent.add_child(recipe_list_panel)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	recipe_list_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Available Recipes"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	# Separator
	var separator = HSeparator.new()
	vbox.add_child(separator)

	recipe_scroll = ScrollContainer.new()
	recipe_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	recipe_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(recipe_scroll)

	recipe_list = VBoxContainer.new()
	recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_list.add_theme_constant_override("separation", 2)
	recipe_scroll.add_child(recipe_list)


func _setup_recipe_info_panel(parent: VBoxContainer):
	"""Set up the recipe information display"""
	crafting_panel = Panel.new()
	crafting_panel.custom_minimum_size = Vector2(0, 120)
	crafting_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	crafting_panel.clip_contents = true
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.12)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.3, 0.3)
	crafting_panel.add_theme_stylebox_override("panel", panel_style)
	parent.add_child(crafting_panel)

	var margin_container = MarginContainer.new()
	margin_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_left", 8)
	margin_container.add_theme_constant_override("margin_right", 8)
	margin_container.add_theme_constant_override("margin_top", 8)
	margin_container.add_theme_constant_override("margin_bottom", 8)
	crafting_panel.add_child(margin_container)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	margin_container.add_child(scroll)

	var scroll_vbox = VBoxContainer.new()
	scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_vbox.custom_minimum_size = Vector2(0, 400)
	scroll_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(scroll_vbox)

	top_spacer = Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_vbox.add_child(top_spacer)

	# Recipe name header
	recipe_name_label = RichTextLabel.new()
	recipe_name_label.bbcode_enabled = true
	recipe_name_label.fit_content = true
	recipe_name_label.scroll_active = false
	recipe_name_label.visible = false
	scroll_vbox.add_child(recipe_name_label)

	# Separator under recipe name
	recipe_separator = HSeparator.new()
	recipe_separator.visible = false
	scroll_vbox.add_child(recipe_separator)

	# Recipe details (description and output)
	recipe_details_label = RichTextLabel.new()
	recipe_details_label.bbcode_enabled = true
	recipe_details_label.fit_content = true
	recipe_details_label.scroll_active = false
	recipe_details_label.visible = false
	scroll_vbox.add_child(recipe_details_label)

	# Recipe info (placeholder text only)
	recipe_info_label = RichTextLabel.new()
	recipe_info_label.bbcode_enabled = true
	recipe_info_label.fit_content = true
	recipe_info_label.scroll_active = false
	recipe_info_label.text = "[center]Select a recipe to begin crafting[/center]"
	scroll_vbox.add_child(recipe_info_label)

	# Bottom spacer for vertical centering
	bottom_spacer = Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_vbox.add_child(bottom_spacer)

	# Requirements
	requirements_label = RichTextLabel.new()
	requirements_label.bbcode_enabled = true
	requirements_label.fit_content = true
	requirements_label.scroll_active = false
	scroll_vbox.add_child(requirements_label)

	# Start button - SEPARATE, underneath the panel
	start_craft_button = Button.new()
	start_craft_button.text = "Start Crafting"
	start_craft_button.custom_minimum_size = Vector2(200, 40)
	start_craft_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_craft_button.disabled = true
	start_craft_button.focus_mode = Control.FOCUS_NONE  # Remove white focus outline
	start_craft_button.pressed.connect(_on_start_craft_pressed)

	# Flat button styling
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.25, 0.5, 0.25)
	normal.set_corner_radius_all(0)
	start_craft_button.add_theme_stylebox_override("normal", normal)

	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(0.3, 0.6, 0.3)
	hover.set_corner_radius_all(0)
	start_craft_button.add_theme_stylebox_override("hover", hover)

	var pressed = StyleBoxFlat.new()
	pressed.bg_color = Color(0.2, 0.4, 0.2)
	pressed.set_corner_radius_all(0)
	start_craft_button.add_theme_stylebox_override("pressed", pressed)

	var disabled = StyleBoxFlat.new()
	disabled.bg_color = Color(0.2, 0.2, 0.2)
	disabled.set_corner_radius_all(0)
	start_craft_button.add_theme_stylebox_override("disabled", disabled)

	start_craft_button.add_theme_color_override("font_color", Color.WHITE)
	start_craft_button.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5, 1.0))

	var button_margin = MarginContainer.new()
	button_margin.add_theme_constant_override("margin_bottom", 12)
	button_margin.add_theme_constant_override("margin_top", 12)
	button_margin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(button_margin)
	button_margin.add_child(start_craft_button)


func _setup_process_panel(parent: VBoxContainer):
	"""Set up the crafting process display"""
	process_panel = Panel.new()
	process_panel.custom_minimum_size = Vector2(0, 80)
	process_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	process_panel.visible = false
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.12)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.3, 0.3)
	process_panel.add_theme_stylebox_override("panel", panel_style)
	parent.add_child(process_panel)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	process_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Stage label
	stage_label = Label.new()
	stage_label.text = "Crafting..."
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(stage_label)

	# Separator
	var separator = HSeparator.new()
	vbox.add_child(separator)

	# Progress bar
	progress_bar = ProgressBar.new()
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(progress_bar)


func _setup_interaction_panel(parent: VBoxContainer):
	"""Set up the interaction panel"""
	interaction_panel = Panel.new()
	interaction_panel.custom_minimum_size = Vector2(0, 100)
	interaction_panel.visible = false
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.12)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.3, 0.3)
	interaction_panel.add_theme_stylebox_override("panel", panel_style)
	parent.add_child(interaction_panel)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	interaction_panel.add_child(margin)

	interaction_container = VBoxContainer.new()
	interaction_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interaction_container.add_theme_constant_override("separation", 8)
	margin.add_child(interaction_container)


func set_crafting_manager(manager: CraftingManager):
	"""Set the crafting manager and load recipes"""
	crafting_manager = manager
	if crafting_manager:
		if not is_node_ready():
			await ready
		await get_tree().process_frame
		_load_available_recipes()


func _load_available_recipes():
	"""Load and display available recipes"""
	if not crafting_manager:
		return

	available_recipes = crafting_manager.get_available_recipes()

	# If a recipe is currently selected, update the reference to the refreshed version
	if selected_recipe:
		var recipe_id = selected_recipe.recipe_id
		for recipe in available_recipes:
			if recipe.recipe_id == recipe_id:
				selected_recipe = recipe
				break

	_populate_recipe_list()


func _populate_recipe_list():
	"""Populate the recipe list UI"""
	# Safety check - ensure UI is ready
	if not recipe_list or not is_instance_valid(recipe_list):
		push_warning("CraftingStationWindow: recipe_list not ready, deferring populate")
		return

	# Clear existing
	for child in recipe_list.get_children():
		child.queue_free()

	# Add recipe buttons
	for recipe in available_recipes:
		var recipe_button = Button.new()
		recipe_button.text = ""  # Clear text, we'll use custom layout
		recipe_button.custom_minimum_size = Vector2(0, 40)
		recipe_button.focus_mode = Control.FOCUS_NONE
		recipe_button.pressed.connect(_on_recipe_selected.bind(recipe))

		# Color code by material availability
		var availability_color = _get_material_availability_color(recipe)

		# Create custom layout with icon and label - centered vertically
		var hbox = HBoxContainer.new()
		hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_theme_constant_override("separation", 8)
		hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
		recipe_button.add_child(hbox)

		# Add small spacer for padding from left border
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(4, 0)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(spacer)

		# Add icon - get from ItemDatabase using output_item_id
		var icon_rect = TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(32, 32)
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Look up item in database to get icon path
		var item_database = get_node_or_null("/root/ItemDatabase")
		if item_database and not recipe.output_item_id.is_empty():
			var item_def = item_database.get_item(recipe.output_item_id)
			if item_def and not item_def.icon_path.is_empty():
				if ResourceLoader.exists(item_def.icon_path):
					var icon_texture = load(item_def.icon_path)
					if icon_texture:
						icon_rect.texture = icon_texture

		hbox.add_child(icon_rect)

		# Add label
		var label = Label.new()
		label.text = recipe.recipe_name
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(label)

		# Normal style - matches container list
		var normal_style = StyleBoxFlat.new()
		normal_style.bg_color = Color(0.12, 0.12, 0.12, 1.0)  # Dark background like container list
		normal_style.border_width_left = 3  # Keep left border for complexity color
		normal_style.border_color = availability_color
		normal_style.content_margin_left = 8
		normal_style.content_margin_right = 8
		normal_style.content_margin_top = 8
		normal_style.content_margin_bottom = 8
		normal_style.set_corner_radius_all(0)  # No rounded corners
		recipe_button.add_theme_stylebox_override("normal", normal_style)

		# Hover style - lighter background
		var hover_style = StyleBoxFlat.new()
		hover_style.bg_color = Color(0.25, 0.25, 0.25, 1.0)  # Lighter on hover
		hover_style.border_width_left = 3
		hover_style.border_color = availability_color
		hover_style.content_margin_left = 8
		hover_style.content_margin_right = 8
		hover_style.content_margin_top = 8
		hover_style.content_margin_bottom = 8
		hover_style.set_corner_radius_all(0)
		recipe_button.add_theme_stylebox_override("hover", hover_style)

		# Pressed/Selected style - even lighter
		var pressed_style = StyleBoxFlat.new()
		pressed_style.bg_color = Color(0.3, 0.35, 0.4, 1.0)  # Selected color
		pressed_style.border_width_left = 3
		pressed_style.border_color = availability_color
		pressed_style.content_margin_left = 8
		pressed_style.content_margin_right = 8
		pressed_style.content_margin_top = 8
		pressed_style.content_margin_bottom = 8
		pressed_style.set_corner_radius_all(0)
		recipe_button.add_theme_stylebox_override("pressed", pressed_style)

		# Font color
		recipe_button.add_theme_color_override("font_color", Color.WHITE)

		recipe_list.add_child(recipe_button)


func _get_material_availability_color(recipe: CraftingRecipe) -> Color:
	"""Get color based on material availability"""
	var available_materials = _get_available_materials()
	var has_count = 0
	var total_count = recipe.required_materials.size()

	if total_count == 0:
		return Color.GREEN

	for req_mat in recipe.required_materials:
		var available = available_materials.get(req_mat.material_id, 0)
		if available >= req_mat.quantity:
			has_count += 1

	if has_count == total_count:
		return Color.GREEN  # Has all materials
	if has_count > 0:
		return Color.YELLOW  # Has some materials
	return Color.RED  # Has no materials


func _on_recipe_selected(recipe: CraftingRecipe):
	"""Handle recipe selection"""
	selected_recipe = recipe
	is_crafting = false
	_update_recipe_display()


func _update_recipe_display():
	"""Update the recipe information display"""
	# Safety check - ensure UI is ready
	if not recipe_info_label or not is_instance_valid(recipe_info_label):
		push_warning("CraftingStationWindow: UI not ready for display update")
		return

	if not requirements_label or not is_instance_valid(requirements_label):
		push_warning("CraftingStationWindow: Requirements label not ready")
		return

	if not selected_recipe:
		recipe_info_label.text = "[center]Select a recipe to begin crafting[/center]"
		recipe_info_label.visible = true
		recipe_name_label.visible = false
		recipe_details_label.visible = false
		requirements_label.text = ""
		requirements_label.visible = false
		recipe_separator.visible = false
		top_spacer.visible = true
		bottom_spacer.visible = true
		if start_craft_button:
			start_craft_button.disabled = true
		_hide_process_and_output_panels()
		return

	# Display recipe info
	top_spacer.visible = false
	bottom_spacer.visible = false
	requirements_label.visible = true
	recipe_separator.visible = true
	recipe_info_label.visible = false
	recipe_name_label.visible = true
	recipe_details_label.visible = true
	recipe_name_label.text = (
		"[center][font_size=24][b]%s[/b][/font_size][/center]" % selected_recipe.recipe_name
	)

	var details_text = "[color=gray]%s[/color]\n\n" % selected_recipe.description
	details_text += (
		"[b]Output:[/b] %s x%d" % [selected_recipe.recipe_name, selected_recipe.output_quantity]
	)
	recipe_details_label.text = details_text

	# Display requirements
	var can_craft = crafting_manager.can_craft_recipe(selected_recipe)
	var req_text = "[b]Required Materials:[/b]\n\n"

	var available_materials = _get_available_materials()

	for req_mat in selected_recipe.required_materials:
		var available = available_materials.get(req_mat.material_id, 0)
		var has_enough = available >= req_mat.quantity
		var color = "green" if has_enough else "red"
		req_text += (
			"[color=%s]• %s: %d/%d[/color]\n"
			% [color, req_mat.material_name, available, req_mat.quantity]
		)

	requirements_label.text = req_text
	requirements_label.visible = true
	if start_craft_button:
		start_craft_button.disabled = not can_craft


func _get_available_materials() -> Dictionary:
	"""Get dictionary of available materials"""
	var materials: Dictionary = {}

	if not crafting_manager or not crafting_manager.player_container:
		return materials

	for item in crafting_manager.player_container.items:
		materials[item.item_id] = materials.get(item.item_id, 0) + item.quantity

	return materials


func _on_start_craft_pressed():
	"""Handle start craft button press"""
	if not selected_recipe or not crafting_manager:
		return

	# Show process panel with animation
	is_crafting = true
	_show_crafting_process()

	# Simulate instant crafting with brief animation
	await _animate_crafting()

	# Actually craft
	var success = crafting_manager.craft_recipe(selected_recipe)

	if success:
		_show_crafting_complete()
	else:
		_show_crafting_failed()


func _show_crafting_process():
	"""Show the crafting process panel"""
	crafting_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recipe_list_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	process_panel.visible = true
	start_craft_button.visible = false
	stage_label.text = "Crafting %s..." % selected_recipe.recipe_name
	progress_bar.value = 0


func _animate_crafting():
	"""Animate the crafting process"""
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(progress_bar, "value", 100, 5.5)
	await tween.finished


func _show_crafting_complete():
	"""Show crafting complete notification and return to crafting screen"""
	# Hide process panel
	process_panel.visible = false

	# Show notification
	_show_crafted_notification()

	# Reset to allow more crafting
	_reset_crafting_ui()


func _show_crafted_notification():
	"""Display notification for crafted item"""
	var message = "Crafted: %s" % [selected_recipe.recipe_name]
	NotificationManager.show_item_crafted(message, selected_recipe.output_quantity)


func _show_crafting_failed():
	"""Show crafting failed message"""
	process_panel.visible = false
	stage_label.text = "Crafting Failed!"
	push_warning("Crafting failed")
	_reset_crafting_ui()


func _reset_crafting_ui():
	"""Reset UI to initial state"""
	is_crafting = false

	_hide_process_and_output_panels()

	crafting_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	recipe_list_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	start_craft_button.visible = true

	# Refresh display to update material counts and recipe list colors
	if selected_recipe:
		refresh_display()


func _hide_process_and_output_panels():
	"""Hide process and output panels"""
	process_panel.visible = false
	interaction_panel.visible = false
	start_craft_button.visible = true


func refresh_display():
	"""Refresh the entire display (useful after inventory changes)"""
	# Only refresh if UI is ready
	if is_node_ready() and recipe_info_label and is_instance_valid(recipe_info_label):
		if not is_crafting:
			# Reload recipes from manager (in case they were updated via hot-reload)
			_load_available_recipes()
			_update_recipe_display()
	else:
		push_warning("CraftingStationWindow: Cannot refresh - UI not ready")
