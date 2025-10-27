# CraftingStationWindow.gd - Simple crafting window with original layout
class_name CraftingStationWindow
extends Window_Base

# UI Components
var recipe_list_panel: Panel
var recipe_list: VBoxContainer
var recipe_scroll: ScrollContainer

var crafting_panel: Panel
var recipe_info_label: RichTextLabel
var requirements_label: RichTextLabel
var start_craft_button: Button

var process_panel: Panel
var stage_label: Label
var progress_bar: ProgressBar
var quality_indicator: ProgressBar
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
	right_container.add_theme_constant_override("separation", 12)
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
	scroll_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(scroll_vbox)

	# Recipe info
	recipe_info_label = RichTextLabel.new()
	recipe_info_label.bbcode_enabled = true
	recipe_info_label.fit_content = true
	recipe_info_label.scroll_active = false
	recipe_info_label.text = "[center]Select a recipe to begin crafting[/center]"
	scroll_vbox.add_child(recipe_info_label)

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

	parent.add_child(start_craft_button)


func _setup_process_panel(parent: VBoxContainer):
	"""Set up the crafting process display"""
	process_panel = Panel.new()
	process_panel.custom_minimum_size = Vector2(0, 100)
	process_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
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

	# Progress bar
	progress_bar = ProgressBar.new()
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(progress_bar)

	# Quality indicator
	var quality_label = Label.new()
	quality_label.text = "Quality"
	quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(quality_label)

	quality_indicator = ProgressBar.new()
	quality_indicator.show_percentage = false
	quality_indicator.custom_minimum_size = Vector2(0, 16)
	quality_indicator.value = 100
	vbox.add_child(quality_indicator)


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
		recipe_button.text = recipe.recipe_name
		recipe_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		recipe_button.custom_minimum_size = Vector2(0, 40)  # FIXED: was 20, now 40 to fit padding
		recipe_button.focus_mode = Control.FOCUS_NONE  # Remove white focus outline
		recipe_button.pressed.connect(_on_recipe_selected.bind(recipe))

		# Color code by complexity - safely get complexity_level
		var complexity_level = 1
		if "complexity_level" in recipe:
			complexity_level = recipe.complexity_level
		var complexity_color = _get_complexity_color(complexity_level)

		# Normal style - matches container list
		var normal_style = StyleBoxFlat.new()
		normal_style.bg_color = Color(0.12, 0.12, 0.12, 1.0)  # Dark background like container list
		normal_style.border_width_left = 3  # Keep left border for complexity color
		normal_style.border_color = complexity_color
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
		hover_style.border_color = complexity_color
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
		pressed_style.border_color = complexity_color
		pressed_style.content_margin_left = 8
		pressed_style.content_margin_right = 8
		pressed_style.content_margin_top = 8
		pressed_style.content_margin_bottom = 8
		pressed_style.set_corner_radius_all(0)
		recipe_button.add_theme_stylebox_override("pressed", pressed_style)

		# Font color
		recipe_button.add_theme_color_override("font_color", Color.WHITE)

		recipe_list.add_child(recipe_button)


func _get_complexity_color(level: int) -> Color:
	"""Get color for complexity level"""
	match level:
		1, 2:
			return Color.GREEN
		3, 4, 5:
			return Color.YELLOW
		6, 7, 8:
			return Color.ORANGE
		_:
			return Color.RED


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
		requirements_label.text = ""
		if start_craft_button:
			start_craft_button.disabled = true
		_hide_process_and_output_panels()
		return

	# Display recipe info
	var info_text = "[center][font_size=24][b]%s[/b][/font_size][/center]\n\n" % selected_recipe.recipe_name
	info_text += "[color=gray]%s[/color]\n\n" % selected_recipe.description
	info_text += "[b]Output:[/b] %s x%d" % [selected_recipe.recipe_name, selected_recipe.output_quantity]
	recipe_info_label.text = info_text

	# Display requirements
	var can_craft = crafting_manager.can_craft_recipe(selected_recipe)
	var req_text = "[b]Required Materials:[/b]\n\n"

	var available_materials = _get_available_materials()

	for req_mat in selected_recipe.required_materials:
		var available = available_materials.get(req_mat.material_id, 0)
		var has_enough = available >= req_mat.quantity
		var color = "green" if has_enough else "red"
		req_text += "[color=%s]• %s: %d/%d[/color]\n" % [color, req_mat.material_name, available, req_mat.quantity]

	requirements_label.text = req_text
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
	stage_label.text = "Crafting %s..." % selected_recipe.recipe_name
	progress_bar.value = 0
	quality_indicator.value = 100


func _animate_crafting():
	"""Animate the crafting process"""
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(progress_bar, "value", 100, 2.5)
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

	# Refresh display to update material counts
	if selected_recipe:
		_update_recipe_display()


func _hide_process_and_output_panels():
	"""Hide process and output panels"""
	process_panel.visible = false
	interaction_panel.visible = false


func refresh_display():
	"""Refresh the entire display (useful after inventory changes)"""
	# Only refresh if UI is ready
	if is_node_ready() and recipe_info_label and is_instance_valid(recipe_info_label):
		if not is_crafting:
			_update_recipe_display()
	else:
		push_warning("CraftingStationWindow: Cannot refresh - UI not ready")
