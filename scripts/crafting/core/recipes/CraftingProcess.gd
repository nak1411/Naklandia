# CraftingProcess.gd - Tracks an active crafting job
class_name CraftingProcess
extends Resource

signal stage_started(stage_index: int)
signal stage_completed(stage_index: int, quality: float)
signal stage_failed(stage_index: int)
signal process_completed(output_items: Array, final_quality: float)
signal process_cancelled
signal progress_updated(progress: float)

# Process identification
var process_id: String = ""
var recipe: CraftingRecipe = null
var start_time: float = 0.0

# Process state
var current_stage_index: int = 0
var stage_progress: float = 0.0
var overall_progress: float = 0.0
var is_active: bool = false
var is_paused: bool = false

# Quality tracking
var stage_qualities: Array[float] = []
var overall_quality: float = 1.0
var quality_modifiers: Dictionary = {}

# Materials and tools used
var consumed_materials: Dictionary = {}
var used_tools: Array[String] = []

# Crafting parameters
var current_parameters: Dictionary = {"temperature": 0.0, "pressure": 0.0, "precision": 0.0, "timing": 0.0}

# Results
var success: bool = false
var output_items: Array = []
var failure_reason: String = ""


func _init(p_recipe: CraftingRecipe = null):
	if p_recipe:
		recipe = p_recipe
		process_id = "process_" + str(Time.get_unix_time_from_system()) + "_" + str(randi() % 1000)
		start_time = Time.get_ticks_msec() / 1000.0
		_initialize_stages()


func _initialize_stages():
	"""Initialize stage quality tracking"""
	if recipe and recipe.crafting_stages:
		stage_qualities.resize(recipe.crafting_stages.size())
		for i in stage_qualities.size():
			stage_qualities[i] = 0.0


func start_process():
	"""Begin the crafting process"""
	is_active = true
	is_paused = false
	current_stage_index = 0
	if recipe.crafting_stages.size() > 0:
		stage_started.emit(current_stage_index)


func pause_process():
	"""Pause the crafting process"""
	is_paused = true


func resume_process():
	"""Resume the crafting process"""
	is_paused = false


func cancel_process():
	"""Cancel the crafting process"""
	is_active = false
	is_paused = false
	process_cancelled.emit()


func update_progress(delta: float):
	"""Update crafting progress - call this in _process()"""
	if not is_active or is_paused or not recipe:
		return

	if current_stage_index >= recipe.crafting_stages.size():
		_complete_process()
		return

	var current_stage = recipe.crafting_stages[current_stage_index]

	# Update stage progress
	stage_progress += delta / current_stage.duration
	stage_progress = clamp(stage_progress, 0.0, 1.0)

	# Calculate overall progress
	_update_overall_progress()

	progress_updated.emit(overall_progress)


func _update_overall_progress():
	"""Calculate overall progress across all stages"""
	if not recipe or recipe.crafting_stages.is_empty():
		overall_progress = 0.0
		return

	var total_duration = 0.0
	var completed_duration = 0.0

	for i in recipe.crafting_stages.size():
		var stage = recipe.crafting_stages[i]
		total_duration += stage.duration

		if i < current_stage_index:
			completed_duration += stage.duration
		elif i == current_stage_index:
			completed_duration += stage.duration * stage_progress

	overall_progress = completed_duration / total_duration if total_duration > 0 else 0.0


func complete_current_stage(quality: float = 1.0):
	"""Mark current stage as complete with quality rating"""
	if current_stage_index >= recipe.crafting_stages.size():
		return

	var current_stage = recipe.crafting_stages[current_stage_index]

	# Check if stage failed
	if quality < current_stage.success_threshold and current_stage.can_fail:
		stage_failed.emit(current_stage_index)
		_fail_process("Stage %d failed quality check" % current_stage_index)
		return

	# Set progress to 100% so progress bar shows complete
	stage_progress = 1.0  # ADD THIS LINE

	# Record stage quality
	stage_qualities[current_stage_index] = quality
	stage_completed.emit(current_stage_index, quality)

	# Move to next stage
	current_stage_index += 1
	stage_progress = 0.0

	if current_stage_index < recipe.crafting_stages.size():
		stage_started.emit(current_stage_index)
	else:
		_complete_process()


func set_parameter(param_name: String, value: float):
	"""Set a crafting parameter"""
	current_parameters[param_name] = value


func get_parameter(param_name: String) -> float:
	"""Get a crafting parameter"""
	return current_parameters.get(param_name, 0.0)


func add_quality_modifier(modifier_id: String, value: float):
	"""Add a quality modifier"""
	quality_modifiers[modifier_id] = value
	_recalculate_overall_quality()


func _recalculate_overall_quality():
	"""Recalculate overall quality from stages and modifiers"""
	# Average stage qualities
	var avg_stage_quality = 0.0
	var completed_stages = 0

	for quality in stage_qualities:
		if quality > 0.0:
			avg_stage_quality += quality
			completed_stages += 1

	if completed_stages > 0:
		avg_stage_quality /= completed_stages
	else:
		avg_stage_quality = 1.0

	# Apply modifiers
	var modifier_total = 0.0
	for modifier in quality_modifiers.values():
		modifier_total += modifier

	overall_quality = clamp(avg_stage_quality + modifier_total, 0.0, 2.0)


func _complete_process():
	"""Complete the crafting process"""
	is_active = false
	success = true

	_recalculate_overall_quality()

	# Generate output items based on recipe and quality
	_generate_output_items()

	process_completed.emit(output_items, overall_quality)


func _fail_process(reason: String):
	"""Fail the crafting process"""
	is_active = false
	success = false
	failure_reason = reason
	process_cancelled.emit()


func _generate_output_items():
	"""Generate output items based on quality"""
	# This would create actual InventoryItem_Base instances
	# For now, just store the recipe output data
	output_items.clear()

	var output_data = {"item_id": recipe.output_item_id, "quantity": recipe.output_quantity, "quality": overall_quality}

	output_items.append(output_data)


func get_current_stage() -> CraftingRecipe.CraftingStage:
	"""Get the current stage object"""
	if not recipe or current_stage_index >= recipe.crafting_stages.size():
		return null
	return recipe.crafting_stages[current_stage_index]


func get_stage_name() -> String:
	"""Get the current stage name"""
	var stage = get_current_stage()
	return stage.stage_name if stage else ""


func get_stage_description() -> String:
	"""Get the current stage description"""
	var stage = get_current_stage()
	return stage.description if stage else ""


func get_estimated_time_remaining() -> float:
	"""Get estimated time remaining for the entire process"""
	if not recipe or not is_active:
		return 0.0

	var time_remaining = 0.0

	for i in range(current_stage_index, recipe.crafting_stages.size()):
		var stage = recipe.crafting_stages[i]
		if i == current_stage_index:
			time_remaining += stage.duration * (1.0 - stage_progress)
		else:
			time_remaining += stage.duration

	return time_remaining
