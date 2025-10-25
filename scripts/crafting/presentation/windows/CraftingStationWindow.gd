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
	default_size = Vector2(1200, 800)
	min_window_size = Vector2(1000, 600)

	_create_interaction_timer()


func _setup_window_content():
	"""Override Window_Base virtual method to setup crafting UI"""
	_setup_crafting_ui()


func _setup_crafting_ui():
	"""Set up the main crafting UI layout"""
	# Main horizontal split
	var main_split = HSplitContainer.new()
	main_split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_split.split_offset = -100
	content_area.add_child(main_split)

	# Left side - Recipe list
	_setup_recipe_list_panel(main_split)

	# Right side - Crafting area
	var right_container = VBoxContainer.new()
	right_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.add_child(right_container)

	_setup_recipe_info_panel(right_container)
	_setup_process_panel(right_container)
	_setup_interaction_panel(right_container)
	_setup_output_panel(right_container)


func _setup_recipe_list_panel(parent: Control):
	"""Set up the recipe selection list"""
	recipe_list_panel = Panel.new()
	recipe_list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.15, 0.15)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.3, 0.3)
	recipe_list_panel.add_theme_stylebox_override("panel", panel_style)
	parent.add_child(recipe_list_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	recipe_list_panel.add_child(vbox)

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
	vbox.add_child(recipe_scroll)

	recipe_list = VBoxContainer.new()
	recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_list.add_theme_constant_override("separation", 2)
	recipe_scroll.add_child(recipe_list)


func _setup_recipe_info_panel(parent: VBoxContainer):
	"""Set up the recipe information display"""
	crafting_panel = Panel.new()
	crafting_panel.custom_minimum_size = Vector2(0, 250)

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.12)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.3, 0.3, 0.3)
	crafting_panel.add_theme_stylebox_override("panel", panel_style)
	parent.add_child(crafting_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	crafting_panel.add_child(vbox)

	# Recipe info
	recipe_info_label = RichTextLabel.new()
	recipe_info_label.bbcode_enabled = true
	recipe_info_label.fit_content = true
	recipe_info_label.scroll_active = false
	recipe_info_label.custom_minimum_size = Vector2(0, 80)
	vbox.add_child(recipe_info_label)

	# Requirements
	requirements_label = RichTextLabel.new()
	requirements_label.bbcode_enabled = true
	requirements_label.fit_content = true
	requirements_label.scroll_active = false
	requirements_label.custom_minimum_size = Vector2(0, 100)
	vbox.add_child(requirements_label)

	# Start button
	start_craft_button = Button.new()
	start_craft_button.text = "Start Crafting"
	start_craft_button.custom_minimum_size = Vector2(0, 40)
	start_craft_button.disabled = true
	start_craft_button.pressed.connect(_on_start_crafting_pressed)
	vbox.add_child(start_craft_button)


func _setup_process_panel(parent: VBoxContainer):
	"""Set up the active crafting process display"""
	process_panel = Panel.new()
	process_panel.custom_minimum_size = Vector2(0, 200)
	process_panel.visible = false

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.15, 0.2)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
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
		recipe_button.custom_minimum_size = Vector2(0, 40)
		recipe_button.pressed.connect(_on_recipe_selected.bind(recipe))

		# Color code by complexity
		var complexity_color = _get_complexity_color(recipe.complexity_level)
		var button_style = StyleBoxFlat.new()
		button_style.bg_color = Color(0.2, 0.2, 0.2)
		button_style.border_width_left = 3
		button_style.border_color = complexity_color
		recipe_button.add_theme_stylebox_override("normal", button_style)

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

	# Requirements
	var req_text = "[b]Required Materials:[/b]\n"
	for mat in selected_recipe.required_materials:
		var has_enough = crafting_manager.check_material_availability(mat.material_id, mat.quantity)
		var color = "[color=green]" if has_enough else "[color=red]"
		req_text += "%s%s x%d[/color]\n" % [color, mat.material_name, mat.quantity]

	req_text += "\n[b]Required Tools:[/b]\n"
	for tool in selected_recipe.required_tools:
		var has_tool = crafting_manager.check_tool_availability(tool.tool_id)
		var color = "[color=green]" if has_tool else "[color=red]"
		var optional_text = " (Optional)" if tool.optional else ""
		req_text += "%s%s%s[/color]\n" % [color, tool.tool_name, optional_text]

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


func _on_stage_started(stage_index: int):
	"""Handle stage start"""
	_update_stage_display()
	_create_stage_interactions()


func _update_stage_display():
	"""Update the stage information display"""
	if not current_process:
		return

	var stage = current_process.get_current_stage()
	if not stage:
		return

	stage_label.text = "Stage %d/%d: %s" % [current_process.current_stage_index + 1, current_process.recipe.crafting_stages.size(), stage.stage_name]

	stage_description.text = "[center]%s[/center]" % stage.description


func _create_stage_interactions():
	"""Create interactive elements for current stage"""
	# Clear existing interactions
	for child in interaction_container.get_children():
		child.queue_free()
	active_interactions.clear()

	var stage = current_process.get_current_stage()
	if not stage or stage.required_actions.is_empty():
		# Auto-complete stage if no interactions
		var label = Label.new()
		label.text = "Processing automatically..."
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		interaction_container.add_child(label)
		return

	# Create controls for each action
	for action in stage.required_actions:
		_create_action_control(action)


func _create_action_control(action: CraftingRecipe.StageAction):
	"""Create a control for a stage action"""
	var action_panel = Panel.new()
	action_panel.custom_minimum_size = Vector2(0, 100)

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.15, 0.15)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.3, 0.3)
	action_panel.add_theme_stylebox_override("panel", panel_style)
	interaction_container.add_child(action_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	action_panel.add_child(vbox)

	# Action title
	var title = Label.new()
	title.text = action.action_name
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	match action.action_type:
		CraftingRecipe.StageAction.ActionType.BUTTON_PRESS:
			_create_button_action(vbox, action)
		CraftingRecipe.StageAction.ActionType.SLIDER_ADJUST:
			_create_slider_action(vbox, action)
		CraftingRecipe.StageAction.ActionType.TEMPERATURE_CONTROL:
			_create_temperature_control(vbox, action)
		CraftingRecipe.StageAction.ActionType.PRESSURE_CONTROL:
			_create_pressure_control(vbox, action)
		CraftingRecipe.StageAction.ActionType.TIMING_CHALLENGE:
			_create_timing_challenge(vbox, action)


func _create_button_action(parent: VBoxContainer, action: CraftingRecipe.StageAction):
	"""Create a simple button action"""
	var button = Button.new()
	button.text = "Execute Action"
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(_on_action_button_pressed.bind(action))
	parent.add_child(button)

	active_interactions[action.action_id] = {"type": "button", "completed": false}


func _create_slider_action(parent: VBoxContainer, action: CraftingRecipe.StageAction):
	"""Create a slider adjustment action"""
	var hbox = HBoxContainer.new()
	parent.add_child(hbox)

	var value_label = Label.new()
	value_label.text = "Value: %.1f" % action.optimal_value
	value_label.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(value_label)

	var slider = HSlider.new()
	slider.min_value = action.parameter_min
	slider.max_value = action.parameter_max
	slider.value = (action.parameter_min + action.parameter_max) / 2.0
	slider.step = 0.1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_slider_value_changed.bind(action, value_label))
	hbox.add_child(slider)

	# Optimal range indicator
	var optimal_label = Label.new()
	optimal_label.text = "Optimal: %.1f ± %.1f" % [action.optimal_value, action.tolerance]
	optimal_label.add_theme_font_size_override("font_size", 10)
	parent.add_child(optimal_label)

	var confirm_button = Button.new()
	confirm_button.text = "Confirm Setting"
	confirm_button.pressed.connect(_on_slider_confirmed.bind(action, slider))
	parent.add_child(confirm_button)

	active_interactions[action.action_id] = {"type": "slider", "value": slider.value, "completed": false}


func _create_temperature_control(parent: VBoxContainer, action: CraftingRecipe.StageAction):
	"""Create a temperature control interface"""
	var hbox = HBoxContainer.new()
	parent.add_child(hbox)

	var decrease_button = Button.new()
	decrease_button.text = "-"
	decrease_button.custom_minimum_size = Vector2(40, 40)
	hbox.add_child(decrease_button)

	var temp_label = Label.new()
	temp_label.text = "Temperature: %.1f°C" % action.optimal_value
	temp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	temp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(temp_label)

	var increase_button = Button.new()
	increase_button.text = "+"
	increase_button.custom_minimum_size = Vector2(40, 40)
	hbox.add_child(increase_button)

	var current_temp = action.optimal_value

	decrease_button.pressed.connect(
		func():
			current_temp = max(action.parameter_min, current_temp - 5.0)
			temp_label.text = "Temperature: %.1f°C" % current_temp
			_update_temp_color(temp_label, current_temp, action)
			active_interactions[action.action_id]["value"] = current_temp
	)

	increase_button.pressed.connect(
		func():
			current_temp = min(action.parameter_max, current_temp + 5.0)
			temp_label.text = "Temperature: %.1f°C" % current_temp
			_update_temp_color(temp_label, current_temp, action)
			active_interactions[action.action_id]["value"] = current_temp
	)

	var stabilize_button = Button.new()
	stabilize_button.text = "Stabilize Temperature"
	stabilize_button.pressed.connect(_on_temperature_stabilized.bind(action, current_temp))
	parent.add_child(stabilize_button)

	active_interactions[action.action_id] = {"type": "temperature", "value": current_temp, "completed": false}


func _update_temp_color(label: Label, temp: float, action: CraftingRecipe.StageAction):
	"""Update label color based on temperature accuracy"""
	var diff = abs(temp - action.optimal_value)
	if diff <= action.tolerance:
		label.add_theme_color_override("font_color", Color.GREEN)
	elif diff <= action.tolerance * 2:
		label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		label.add_theme_color_override("font_color", Color.RED)


func _create_pressure_control(parent: VBoxContainer, action: CraftingRecipe.StageAction):
	"""Create a pressure control interface"""
	var progress = ProgressBar.new()
	progress.min_value = action.parameter_min
	progress.max_value = action.parameter_max
	progress.value = action.optimal_value
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(0, 30)
	parent.add_child(progress)

	var pressure_label = Label.new()
	pressure_label.text = "Pressure: %.2f bar (Target: %.2f ± %.2f)" % [action.optimal_value, action.optimal_value, action.tolerance]
	pressure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(pressure_label)

	var button_box = HBoxContainer.new()
	button_box.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(button_box)

	var vent_button = Button.new()
	vent_button.text = "Vent Pressure"
	button_box.add_child(vent_button)

	var increase_button = Button.new()
	increase_button.text = "Increase Pressure"
	button_box.add_child(increase_button)

	var confirm_button = Button.new()
	confirm_button.text = "Confirm Pressure"
	confirm_button.disabled = true
	button_box.add_child(confirm_button)

	var current_pressure = action.optimal_value

	vent_button.pressed.connect(
		func():
			current_pressure = max(action.parameter_min, current_pressure - 0.5)
			progress.value = current_pressure
			pressure_label.text = "Pressure: %.2f bar (Target: %.2f ± %.2f)" % [current_pressure, action.optimal_value, action.tolerance]
			var in_range = abs(current_pressure - action.optimal_value) <= action.tolerance
			confirm_button.disabled = not in_range
			active_interactions[action.action_id]["value"] = current_pressure
	)

	increase_button.pressed.connect(
		func():
			current_pressure = min(action.parameter_max, current_pressure + 0.5)
			progress.value = current_pressure
			pressure_label.text = "Pressure: %.2f bar (Target: %.2f ± %.2f)" % [current_pressure, action.optimal_value, action.tolerance]
			var in_range = abs(current_pressure - action.optimal_value) <= action.tolerance
			confirm_button.disabled = not in_range
			active_interactions[action.action_id]["value"] = current_pressure
	)

	confirm_button.pressed.connect(_on_pressure_confirmed.bind(action, current_pressure))

	active_interactions[action.action_id] = {"type": "pressure", "value": current_pressure, "completed": false}


func _create_timing_challenge(parent: VBoxContainer, action: CraftingRecipe.StageAction):
	"""Create a timing challenge action"""
	var progress = ProgressBar.new()
	progress.max_value = 100
	progress.value = 0
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(0, 40)
	parent.add_child(progress)

	var instruction_label = Label.new()
	instruction_label.text = "Press the button when the bar is in the green zone!"
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(instruction_label)

	var action_button = Button.new()
	action_button.text = "STOP!"
	action_button.custom_minimum_size = Vector2(0, 50)
	parent.add_child(action_button)

	active_interactions[action.action_id] = {"type": "timing", "progress": 0.0, "direction": 1, "completed": false, "progress_bar": progress}

	action_button.pressed.connect(_on_timing_button_pressed.bind(action))


func _on_action_button_pressed(action: CraftingRecipe.StageAction):
	"""Handle button action press"""
	if not active_interactions.has(action.action_id):
		return

	active_interactions[action.action_id]["completed"] = true
	_check_all_actions_complete()


func _on_slider_value_changed(value: float, action: CraftingRecipe.StageAction, label: Label):
	"""Handle slider value change"""
	label.text = "Value: %.1f" % value
	if active_interactions.has(action.action_id):
		active_interactions[action.action_id]["value"] = value


func _on_slider_confirmed(action: CraftingRecipe.StageAction, slider: HSlider):
	"""Handle slider confirmation"""
	if not active_interactions.has(action.action_id):
		return

	var value = slider.value
	var quality = _calculate_action_quality(value, action)

	active_interactions[action.action_id]["completed"] = true
	active_interactions[action.action_id]["quality"] = quality

	current_process.add_quality_modifier(action.action_id, quality - 1.0)

	_check_all_actions_complete()


func _on_temperature_stabilized(action: CraftingRecipe.StageAction, temp: float):
	"""Handle temperature stabilization"""
	if not active_interactions.has(action.action_id):
		return

	var quality = _calculate_action_quality(temp, action)

	active_interactions[action.action_id]["completed"] = true
	active_interactions[action.action_id]["quality"] = quality

	current_process.add_quality_modifier(action.action_id, quality - 1.0)

	_check_all_actions_complete()


func _on_pressure_confirmed(action: CraftingRecipe.StageAction, pressure: float):
	"""Handle pressure confirmation"""
	if not active_interactions.has(action.action_id):
		return

	var quality = _calculate_action_quality(pressure, action)

	active_interactions[action.action_id]["completed"] = true
	active_interactions[action.action_id]["quality"] = quality

	current_process.add_quality_modifier(action.action_id, quality - 1.0)

	_check_all_actions_complete()


func _on_timing_button_pressed(action: CraftingRecipe.StageAction):
	"""Handle timing challenge button press"""
	if not active_interactions.has(action.action_id):
		return

	var data = active_interactions[action.action_id]
	var progress_value = data["progress"]

	# Green zone is around optimal value
	var optimal_normalized = (action.optimal_value - action.parameter_min) / (action.parameter_max - action.parameter_min) * 100.0
	var tolerance_normalized = (action.tolerance / (action.parameter_max - action.parameter_min)) * 100.0

	var quality = 0.0
	var diff = abs(progress_value - optimal_normalized)

	if diff <= tolerance_normalized:
		quality = 1.5  # Perfect timing
	elif diff <= tolerance_normalized * 2:
		quality = 1.0  # Good timing
	else:
		quality = 0.5  # Poor timing

	data["completed"] = true
	data["quality"] = quality

	current_process.add_quality_modifier(action.action_id, quality - 1.0)

	_check_all_actions_complete()


func _calculate_action_quality(value: float, action: CraftingRecipe.StageAction) -> float:
	"""Calculate quality based on how close value is to optimal"""
	var diff = abs(value - action.optimal_value)

	if diff <= action.tolerance:
		return 1.5  # Perfect
	elif diff <= action.tolerance * 2:
		return 1.0  # Good
	elif diff <= action.tolerance * 3:
		return 0.75  # Acceptable
	else:
		return 0.5  # Poor


func _check_all_actions_complete():
	"""Check if all stage actions are complete"""
	for data in active_interactions.values():
		if not data["completed"]:
			return

	# All actions complete - finish stage
	var avg_quality = 1.0
	var quality_count = 0

	for data in active_interactions.values():
		if data.has("quality"):
			avg_quality += data["quality"]
			quality_count += 1

	if quality_count > 0:
		avg_quality /= quality_count

	current_process.complete_current_stage(avg_quality)


func _on_interaction_timer_timeout():
	"""Update crafting progress each tick"""
	if not current_process or not current_process.is_active:
		return

	# Update timing challenges
	for action_id in active_interactions:
		var data = active_interactions[action_id]
		if data["type"] == "timing" and not data["completed"]:
			data["progress"] += data["direction"] * 2.0
			if data["progress"] >= 100.0 or data["progress"] <= 0.0:
				data["direction"] *= -1
			data["progress"] = clamp(data["progress"], 0.0, 100.0)
			data["progress_bar"].value = data["progress"]

	# Update process
	current_process.update_progress(interaction_timer.wait_time)


func _on_stage_completed(stage_index: int, quality: float):
	"""Handle stage completion"""
	# Clear interactions for next stage
	for child in interaction_container.get_children():
		child.queue_free()
	active_interactions.clear()


func _on_stage_failed(stage_index: int):
	"""Handle stage failure"""
	interaction_timer.stop()
	process_panel.visible = false
	interaction_panel.visible = false

	# Show failure message
	var dialog = AcceptDialog.new()
	dialog.dialog_text = "Crafting failed at stage %d!\n%s" % [stage_index + 1, current_process.failure_reason]
	dialog.title = "Crafting Failed"
	add_child(dialog)
	dialog.popup_centered()

	_reset_crafting_ui()


func _on_process_completed(output_items: Array, final_quality: float):
	"""Handle process completion"""
	interaction_timer.stop()
	process_panel.visible = false
	interaction_panel.visible = false
	output_panel.visible = true

	_display_output(output_items, final_quality)


func _display_output(output_items: Array, final_quality: float):
	"""Display crafting output"""
	# Clear output grid
	for child in output_grid.get_children():
		child.queue_free()

	# Quality display
	var quality_panel = Panel.new()
	quality_panel.custom_minimum_size = Vector2(200, 80)
	output_grid.add_child(quality_panel)

	var quality_vbox = VBoxContainer.new()
	quality_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	quality_panel.add_child(quality_vbox)

	var quality_label = Label.new()
	quality_label.text = "Final Quality"
	quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quality_vbox.add_child(quality_label)

	var quality_value = Label.new()
	quality_value.text = "%.1f%%" % (final_quality * 100)
	quality_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quality_value.add_theme_font_size_override("font_size", 24)

	if final_quality >= 1.5:
		quality_value.add_theme_color_override("font_color", Color.GOLD)
	elif final_quality >= 1.0:
		quality_value.add_theme_color_override("font_color", Color.GREEN)
	else:
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


func _on_progress_updated(progress: float):
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
