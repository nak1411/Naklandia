# CraftingStationWindow.gd - Interactive crafting station interface
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
var overall_progress_bar: ProgressBar
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
var current_process: CraftingProcess = null

# Interaction elements
var active_interactions: Dictionary = {}
var interaction_timer: Timer


func _ready():
	super._ready()

	window_title = "Crafting Station"
	default_size = Vector2(1000, 700)
	min_window_size = Vector2(600, 400)

	_create_interaction_timer()


func _setup_window_content():
	"""Override Window_Base virtual method to setup crafting UI"""
	_setup_crafting_ui()


func _setup_crafting_ui():
	"""Set up the main crafting UI layout"""
	# Main horizontal split
	var main_split = HSplitContainer.new()
	main_split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_split.split_offset = 200
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
	_setup_output_panel(right_container)


func _setup_recipe_list_panel(parent: Control):
	"""Set up the recipe selection list"""
	recipe_list_panel = Panel.new()
	recipe_list_panel.size_flags_horizontal = Control.SIZE_FILL
	recipe_list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_list_panel.size_flags_stretch_ratio = 0.0
	recipe_list_panel.clip_contents = true
	recipe_list_panel.custom_minimum_size = Vector2(200, 0)

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.15, 0.15)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.3, 0.3)
	recipe_list_panel.add_theme_stylebox_override("panel", panel_style)
	parent.add_child(recipe_list_panel)

	# Add MarginContainer for padding
	var margin_container = MarginContainer.new()
	margin_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_left", 8)
	margin_container.add_theme_constant_override("margin_right", 8)
	margin_container.add_theme_constant_override("margin_top", 8)
	margin_container.add_theme_constant_override("margin_bottom", 8)
	margin_container.clip_contents = true  # ADDED: Clip margin container
	recipe_list_panel.add_child(margin_container)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	vbox.clip_contents = true
	margin_container.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Available Recipes"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	# Separator
	var separator = HSeparator.new()
	vbox.add_child(separator)

	# Scroll container for recipes
	recipe_scroll = ScrollContainer.new()
	recipe_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	recipe_scroll.clip_contents = true  # ADDED: Clip scroll container
	vbox.add_child(recipe_scroll)

	recipe_list = VBoxContainer.new()
	recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_list.add_theme_constant_override("separation", 2)
	recipe_scroll.add_child(recipe_list)


func _setup_recipe_info_panel(parent: VBoxContainer):
	"""Set up the recipe information display"""
	crafting_panel = Panel.new()
	crafting_panel.custom_minimum_size = Vector2(0, 300)

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.12)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.3, 0.3)
	crafting_panel.add_theme_stylebox_override("panel", panel_style)
	parent.add_child(crafting_panel)

	# Add MarginContainer for proper padding
	var margin_container = MarginContainer.new()
	margin_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_left", 8)
	margin_container.add_theme_constant_override("margin_right", 8)
	margin_container.add_theme_constant_override("margin_top", 8)
	margin_container.add_theme_constant_override("margin_bottom", 8)
	crafting_panel.add_child(margin_container)

	# ScrollContainer for the text content
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
	start_craft_button.focus_mode = Control.FOCUS_NONE
	start_craft_button.pressed.connect(_on_start_crafting_pressed)

	# Style the button to match other UI buttons
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	normal_style.border_width_left = 1
	normal_style.border_width_right = 1
	normal_style.border_width_top = 1
	normal_style.border_width_bottom = 1
	normal_style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	normal_style.content_margin_left = 8
	normal_style.content_margin_right = 8
	normal_style.content_margin_top = 8
	normal_style.content_margin_bottom = 8
	normal_style.set_corner_radius_all(0)

	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.3, 0.3, 0.3, 1.0)
	hover_style.border_width_left = 1
	hover_style.border_width_right = 1
	hover_style.border_width_top = 1
	hover_style.border_width_bottom = 1
	hover_style.border_color = Color(0.5, 0.5, 0.5, 1.0)
	hover_style.content_margin_left = 8
	hover_style.content_margin_right = 8
	hover_style.content_margin_top = 8
	hover_style.content_margin_bottom = 8
	hover_style.set_corner_radius_all(0)

	var pressed_style = StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.25, 0.25, 0.25, 1.0)
	pressed_style.border_width_left = 1
	pressed_style.border_width_right = 1
	pressed_style.border_width_top = 1
	pressed_style.border_width_bottom = 1
	pressed_style.border_color = Color(0.5, 0.5, 0.5, 1.0)
	pressed_style.content_margin_left = 8
	pressed_style.content_margin_right = 8
	pressed_style.content_margin_top = 8
	pressed_style.content_margin_bottom = 8
	pressed_style.set_corner_radius_all(0)

	var disabled_style = StyleBoxFlat.new()
	disabled_style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	disabled_style.border_width_left = 1
	disabled_style.border_width_right = 1
	disabled_style.border_width_top = 1
	disabled_style.border_width_bottom = 1
	disabled_style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	disabled_style.content_margin_left = 8
	disabled_style.content_margin_right = 8
	disabled_style.content_margin_top = 8
	disabled_style.content_margin_bottom = 8
	disabled_style.set_corner_radius_all(0)

	start_craft_button.add_theme_stylebox_override("normal", normal_style)
	start_craft_button.add_theme_stylebox_override("hover", hover_style)
	start_craft_button.add_theme_stylebox_override("pressed", pressed_style)
	start_craft_button.add_theme_stylebox_override("disabled", disabled_style)
	start_craft_button.add_theme_color_override("font_color", Color.WHITE)
	start_craft_button.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5, 1.0))

	parent.add_child(start_craft_button)


func _setup_process_panel(parent: VBoxContainer):
	"""Set up the active crafting process display"""
	process_panel = Panel.new()
	process_panel.custom_minimum_size = Vector2(0, 200)
	process_panel.visible = false

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.15, 0.2)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.5, 0.7)
	process_panel.add_theme_stylebox_override("panel", panel_style)
	parent.add_child(process_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	process_panel.add_child(vbox)

	# Stage label
	stage_label = Label.new()
	stage_label.text = "Stage: Idle"
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(stage_label)

	# Stage progress
	var stage_progress_label = Label.new()
	stage_progress_label.text = "Stage Progress"
	stage_progress_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(stage_progress_label)

	progress_bar = ProgressBar.new()
	progress_bar.show_percentage = true
	progress_bar.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(progress_bar)

	# Overall progress
	var overall_progress_label = Label.new()
	overall_progress_label.text = "Overall Progress"
	overall_progress_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(overall_progress_label)

	overall_progress_bar = ProgressBar.new()
	overall_progress_bar.show_percentage = true
	overall_progress_bar.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(overall_progress_bar)

	# Quality indicator
	var quality_label = Label.new()
	quality_label.text = "Current Quality"
	quality_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(quality_label)

	quality_indicator = ProgressBar.new()
	quality_indicator.show_percentage = true
	quality_indicator.custom_minimum_size = Vector2(0, 25)
	quality_indicator.max_value = 2.0  # Can exceed 100% quality
	vbox.add_child(quality_indicator)

	# Stage description
	stage_description = RichTextLabel.new()
	stage_description.bbcode_enabled = true
	stage_description.fit_content = true
	stage_description.scroll_active = false
	stage_description.custom_minimum_size = Vector2(0, 60)
	vbox.add_child(stage_description)


func _setup_interaction_panel(parent: VBoxContainer):
	"""Set up the interactive crafting controls"""
	interaction_panel = Panel.new()
	interaction_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	interaction_panel.visible = false

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.18, 0.18, 0.18)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.4, 0.4, 0.4)
	interaction_panel.add_theme_stylebox_override("panel", panel_style)
	parent.add_child(interaction_panel)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	interaction_panel.add_child(scroll)

	interaction_container = VBoxContainer.new()
	interaction_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interaction_container.add_theme_constant_override("separation", 12)
	scroll.add_child(interaction_container)


func _setup_output_panel(parent: VBoxContainer):
	"""Set up the output display panel"""
	output_panel = Panel.new()
	output_panel.custom_minimum_size = Vector2(0, 150)
	output_panel.visible = false

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.2, 0.1)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.2, 0.6, 0.2)
	output_panel.add_theme_stylebox_override("panel", panel_style)
	parent.add_child(output_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	output_panel.add_child(vbox)

	var title = Label.new()
	title.text = "Crafting Complete!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	output_grid = GridContainer.new()
	output_grid.columns = 4
	output_grid.add_theme_constant_override("h_separation", 8)
	output_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(output_grid)


func _create_interaction_timer():
	"""Create timer for updating crafting progress"""
	interaction_timer = Timer.new()
	interaction_timer.wait_time = 0.1
	interaction_timer.timeout.connect(_on_interaction_timer_timeout)
	add_child(interaction_timer)


func set_crafting_manager(manager: CraftingManager):
	"""Set the crafting manager and load recipes"""
	crafting_manager = manager
	if crafting_manager:
		# Wait for UI to be fully ready in scene tree
		if not is_node_ready():
			await ready
		# Ensure all child nodes are in scene tree
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
		recipe_button.custom_minimum_size = Vector2(0, 20)
		recipe_button.focus_mode = Control.FOCUS_NONE  # Remove white focus outline
		recipe_button.pressed.connect(_on_recipe_selected.bind(recipe))

		# Color code by complexity
		var complexity_color = _get_complexity_color(recipe.complexity_level)

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
	_update_recipe_info()
	_check_can_craft()


func _update_recipe_info():
	"""Update the recipe information display"""
	# Safety check
	if not recipe_info_label or not requirements_label:
		return

	if not selected_recipe:
		recipe_info_label.text = "[center]Select a recipe to begin[/center]"
		requirements_label.text = ""
		return

	# Recipe info
	var info_text = "[b][font_size=16]%s[/font_size][/b]\n" % selected_recipe.recipe_name
	info_text += "[i]%s[/i]\n\n" % selected_recipe.description
	info_text += "Complexity: %d/10\n" % selected_recipe.complexity_level
	info_text += "Est. Time: %d seconds\n" % selected_recipe.estimated_time
	info_text += "Failure Risk: %.1f%%" % (selected_recipe.failure_risk * 100)
	recipe_info_label.text = info_text

	# Requirements with better formatting and spacing
	var req_text = "[b]Required Materials:[/b]\n\n"
	for mat in selected_recipe.required_materials:
		var has_enough = crafting_manager.check_material_availability(mat.material_id, mat.quantity)
		var color = "[color=green]" if has_enough else "[color=red]"
		req_text += "    %s• %s x%d[/color]\n" % [color, mat.material_name, mat.quantity]

	req_text += "\n[b]Required Tools:[/b]\n\n"
	for tool in selected_recipe.required_tools:
		var has_tool = crafting_manager.check_tool_availability(tool.tool_id)
		var color = "[color=green]" if has_tool else "[color=red]"
		var optional_text = " (Optional)" if tool.optional else ""
		req_text += "    %s• %s%s[/color]\n" % [color, tool.tool_name, optional_text]

	requirements_label.text = req_text


func _check_can_craft():
	"""Check if the selected recipe can be crafted"""
	if not start_craft_button:
		return

	if not selected_recipe or not crafting_manager:
		start_craft_button.disabled = true
		return

	var can_craft = crafting_manager.can_craft_recipe(selected_recipe)
	start_craft_button.disabled = not can_craft


func _on_start_crafting_pressed():
	"""Handle start crafting button press"""
	if not selected_recipe or not crafting_manager:
		return

	current_process = crafting_manager.start_crafting(selected_recipe)
	if current_process:
		_setup_process_ui()
		_connect_process_signals()
		interaction_timer.start()


func _setup_process_ui():
	"""Set up UI for active crafting process"""
	crafting_panel.visible = false
	recipe_list_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Disable during crafting
	process_panel.visible = true
	interaction_panel.visible = true

	_update_stage_display()


func _connect_process_signals():
	"""Connect signals from crafting process"""
	if not current_process:
		return

	current_process.stage_started.connect(_on_stage_started)
	current_process.stage_completed.connect(_on_stage_completed)
	current_process.stage_failed.connect(_on_stage_failed)
	current_process.process_completed.connect(_on_process_completed)
	current_process.progress_updated.connect(_on_progress_updated)


func _on_stage_started(_stage_index: int):
	"""Handle stage start"""
	_update_stage_display()
	_create_stage_interactions()


func _on_stage_completed(_stage_index: int, _quality: float):
	"""Handle stage completion"""
	_clear_interactions()


func _on_stage_failed(_stage_index: int, reason: String):
	"""Handle stage failure"""
	var failure_label = Label.new()
	failure_label.text = "Stage Failed: %s" % reason
	failure_label.add_theme_color_override("font_color", Color.RED)
	failure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_container.add_child(failure_label)


func _on_process_completed(output_items: Array):
	"""Handle process completion"""
	interaction_timer.stop()
	interaction_panel.visible = false
	process_panel.visible = false
	output_panel.visible = true

	_display_output(output_items)


func _update_stage_display():
	"""Update the stage information display"""
	if not current_process:
		return

	var current_stage = current_process.get_current_stage()
	if not current_stage:
		stage_label.text = "Stage: Complete"
		return

	stage_label.text = "Stage %d/%d: %s" % [current_process.current_stage_index + 1, current_process.recipe.crafting_stages.size(), current_stage.stage_name]

	var desc_text = "[b]%s[/b]\n" % current_stage.stage_name
	desc_text += current_stage.description
	stage_description.text = desc_text


func _create_stage_interactions():
	"""Create interaction buttons for current stage"""
	_clear_interactions()

	if not current_process:
		return

	var current_stage = current_process.get_current_stage()
	if not current_stage:
		return

	# Create buttons for each action
	if current_stage.required_actions:
		for action in current_stage.required_actions:
			_create_interaction_button(action)


func _create_interaction_button(action: CraftingRecipe.StageAction):
	"""Create a button for a stage action"""
	var button = Button.new()
	button.text = "%s" % action.action_name
	button.custom_minimum_size = Vector2(0, 50)
	button.pressed.connect(_on_interaction_pressed.bind(action, button))

	# Store button reference
	active_interactions[action] = {"button": button, "press_count": 0}

	interaction_container.add_child(button)


func _on_interaction_pressed(action: CraftingRecipe.StageAction, button: Button):
	"""Handle interaction button press"""
	if not current_process:
		return

	var interaction_data = active_interactions.get(action)
	if not interaction_data:
		return

	# Increment press count
	interaction_data["press_count"] += 1

	# Update button text
	button.text = "%s (Completed)" % action.action_name

	# Mark as complete
	button.disabled = true
	button.modulate = Color.GREEN

	# Auto-advance stage after interaction
	current_process.complete_current_stage(1.0)


func _clear_interactions():
	"""Clear all interaction buttons"""
	for child in interaction_container.get_children():
		child.queue_free()

	active_interactions.clear()


func _on_interaction_timer_timeout():
	"""Update crafting progress"""
	if current_process:
		current_process.update_progress(interaction_timer.wait_time)


func _display_output(output_items: Array):
	"""Display crafting output"""
	# Clear previous output
	for child in output_grid.get_children():
		child.queue_free()

	# Quality display
	var quality_vbox = VBoxContainer.new()
	output_grid.add_child(quality_vbox)

	var quality_label = Label.new()
	quality_label.text = "Quality"
	quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quality_vbox.add_child(quality_label)

	var quality_value = Label.new()
	quality_value.text = "%.1f%%" % (current_process.overall_quality * 100)
	quality_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quality_value.add_theme_font_size_override("font_size", 20)
	quality_value.add_theme_color_override("font_color", Color.YELLOW)

	quality_vbox.add_child(quality_value)

	# Items display
	for item_data in output_items:
		var item_panel = Panel.new()
		item_panel.custom_minimum_size = Vector2(150, 80)
		output_grid.add_child(item_panel)

		var item_vbox = VBoxContainer.new()
		item_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		item_panel.add_child(item_vbox)

		var item_label = Label.new()
		item_label.text = item_data.get("item_id", "Unknown")
		item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_vbox.add_child(item_label)

		var quantity_label = Label.new()
		quantity_label.text = "x%d" % item_data.get("quantity", 1)
		quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_vbox.add_child(quantity_label)

	# Collect button
	var collect_button = Button.new()
	collect_button.text = "Collect Items"
	collect_button.custom_minimum_size = Vector2(0, 50)
	collect_button.pressed.connect(_on_collect_output)
	output_grid.add_child(collect_button)


func _on_collect_output():
	"""Handle collecting output items"""
	if current_process and crafting_manager:
		crafting_manager.collect_crafting_output(current_process)

	_reset_crafting_ui()


func _on_progress_updated(_progress: float):
	"""Update progress bars"""
	if not current_process:
		return

	progress_bar.value = current_process.stage_progress * 100
	overall_progress_bar.value = current_process.overall_progress * 100
	quality_indicator.value = current_process.overall_quality

	# Update quality color
	if current_process.overall_quality >= 1.5:
		quality_indicator.modulate = Color.GOLD
	elif current_process.overall_quality >= 1.0:
		quality_indicator.modulate = Color.GREEN
	else:
		quality_indicator.modulate = Color.YELLOW


func _reset_crafting_ui():
	"""Reset UI to initial state"""
	current_process = null
	selected_recipe = null

	crafting_panel.visible = true
	recipe_list_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	process_panel.visible = false
	interaction_panel.visible = false
	output_panel.visible = false

	recipe_info_label.text = "[center]Select a recipe to begin[/center]"
	requirements_label.text = ""
	start_craft_button.disabled = true

	interaction_timer.stop()
