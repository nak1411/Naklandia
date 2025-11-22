# PerformanceCounter.gd
# Displays FPS, UPS, and custom performance metrics
class_name PerformanceCounter
extends Control

# Settings
@export_group("Display Settings")
@export var update_interval: float = 0.5  # How often to update the display (seconds)
@export var font_size: int = 12
@export var background_color: Color = Color(0.0, 0.0, 0.0, 0.7)
@export var text_color: Color = Color(0.0, 1.0, 0.0, 1.0)
@export var warning_color: Color = Color(1.0, 0.8, 0.0, 1.0)  # Yellow for performance warnings
@export var critical_color: Color = Color(1.0, 0.0, 0.0, 1.0)  # Red for critical performance
@export var padding: float = 8.0

@export_group("Performance Thresholds")
@export var fps_warning_threshold: float = 45.0  # Show yellow below this
@export var fps_critical_threshold: float = 30.0  # Show red below this
@export var show_tree_stats: bool = true  # Show tree spawner statistics

# Internal variables
var update_timer: float = 0.0
var frame_count: int = 0
var physics_frame_count: int = 0
var last_fps: float = 0.0
var last_ups: float = 0.0
var tree_spawner: Node = null

# Performance history for smoothing
var fps_history: Array[float] = []
var ups_history: Array[float] = []
var history_size: int = 10

func _ready():
	# Position in top-left corner
	anchor_left = 0.0
	anchor_top = 0.0
	offset_left = 10.0
	offset_top = 80.0  # Below compass
	custom_minimum_size = Vector2(200, 100)

	# Find tree spawner for stats
	if show_tree_stats:
		call_deferred("_find_tree_spawner")

func _find_tree_spawner():
	var spawners = get_tree().get_nodes_in_group("tree_spawner")
	if spawners.size() > 0:
		tree_spawner = spawners[0]
		print("PerformanceCounter: Found tree spawner for stats")

func _process(delta):
	frame_count += 1
	update_timer += delta

	if update_timer >= update_interval:
		# Calculate FPS and UPS
		last_fps = frame_count / update_timer
		last_ups = physics_frame_count / update_timer

		# Add to history for smoothing
		fps_history.append(last_fps)
		ups_history.append(last_ups)
		if fps_history.size() > history_size:
			fps_history.pop_front()
		if ups_history.size() > history_size:
			ups_history.pop_front()

		# Reset counters
		frame_count = 0
		physics_frame_count = 0
		update_timer = 0.0

		queue_redraw()

func _physics_process(_delta):
	physics_frame_count += 1

func _get_average(array: Array[float]) -> float:
	if array.is_empty():
		return 0.0
	var sum = 0.0
	for value in array:
		sum += value
	return sum / array.size()

func _draw():
	var rect = Rect2(Vector2.ZERO, size)

	# Draw background
	draw_rect(rect, background_color, true)
	draw_rect(rect, Color(0.3, 0.3, 0.3, 1.0), false, 1.0)

	# Prepare text
	var y_offset = padding
	var line_height = font_size + 4

	# Calculate smoothed values
	var avg_fps = _get_average(fps_history)
	var avg_ups = _get_average(ups_history)

	# Determine FPS color
	var fps_color = text_color
	if avg_fps < fps_critical_threshold:
		fps_color = critical_color
	elif avg_fps < fps_warning_threshold:
		fps_color = warning_color

	# Draw FPS
	var fps_text = "FPS: " + str(int(avg_fps))
	draw_string(ThemeDB.fallback_font, Vector2(padding, y_offset + font_size), fps_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fps_color)
	y_offset += line_height

	# Draw UPS
	var ups_text = "UPS: " + str(int(avg_ups))
	draw_string(ThemeDB.fallback_font, Vector2(padding, y_offset + font_size), ups_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	y_offset += line_height

	# Draw engine FPS for comparison
	var engine_fps = Engine.get_frames_per_second()
	var engine_fps_text = "Engine FPS: " + str(engine_fps)
	draw_string(ThemeDB.fallback_font, Vector2(padding, y_offset + font_size), engine_fps_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.7, 0.7, 0.7, 1.0))
	y_offset += line_height

	# Draw frame time
	var frame_time = 1000.0 / max(avg_fps, 1.0)
	var frame_time_text = "Frame: " + str(snapped(frame_time, 0.01)) + "ms"
	var frame_time_color = text_color
	if frame_time > 33.33:  # > 30 FPS
		frame_time_color = critical_color
	elif frame_time > 22.22:  # > 45 FPS
		frame_time_color = warning_color
	draw_string(ThemeDB.fallback_font, Vector2(padding, y_offset + font_size), frame_time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, frame_time_color)
	y_offset += line_height

	# Draw tree stats if enabled
	if show_tree_stats and tree_spawner:
		y_offset += 4  # Extra spacing

		# Draw separator line
		draw_line(Vector2(padding, y_offset), Vector2(size.x - padding, y_offset), Color(0.5, 0.5, 0.5, 1.0), 1.0)
		y_offset += 6

		# Get tree spawner stats
		var visible_trees = 0
		var total_trees = 0
		var is_spawning = false
		var spawn_queue_size = 0

		if tree_spawner.has_method("get_tree_count"):
			visible_trees = tree_spawner.get_tree_count()

		if "tree_registry" in tree_spawner:
			total_trees = tree_spawner.tree_registry.size()

		if "is_spawning" in tree_spawner:
			is_spawning = tree_spawner.is_spawning

		if "spawn_queue" in tree_spawner:
			spawn_queue_size = tree_spawner.spawn_queue.size()

		# Draw tree stats
		var trees_text = "Trees: " + str(visible_trees) + " / " + str(total_trees)
		draw_string(ThemeDB.fallback_font, Vector2(padding, y_offset + font_size), trees_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
		y_offset += line_height

		# Draw spawn queue if active
		if is_spawning or spawn_queue_size > 0:
			var queue_text = "Queue: " + str(spawn_queue_size)
			var queue_color = warning_color if is_spawning else text_color
			draw_string(ThemeDB.fallback_font, Vector2(padding, y_offset + font_size), queue_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, queue_color)
			y_offset += line_height

		# Draw culled trees count
		var culled_trees = total_trees - visible_trees
		if culled_trees > 0:
			var culled_text = "Culled: " + str(culled_trees)
			draw_string(ThemeDB.fallback_font, Vector2(padding, y_offset + font_size), culled_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.7, 0.7, 0.7, 1.0))
			y_offset += line_height

		# Draw memory usage estimate
		var memory_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / 1024.0 / 1024.0
		var memory_text = "Mem: " + str(snapped(memory_mb, 0.1)) + " MB"
		draw_string(ThemeDB.fallback_font, Vector2(padding, y_offset + font_size), memory_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.7, 0.7, 0.7, 1.0))
		y_offset += line_height

		# Draw additional performance metrics
		y_offset += 4
		draw_line(Vector2(padding, y_offset), Vector2(size.x - padding, y_offset), Color(0.5, 0.5, 0.5, 1.0), 1.0)
		y_offset += 6

		# Nodes in scene
		var nodes_processed = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		var nodes_text = "Nodes: " + str(nodes_processed)
		draw_string(ThemeDB.fallback_font, Vector2(padding, y_offset + font_size), nodes_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.7, 0.7, 0.7, 1.0))
		y_offset += line_height

		# Physics objects
		var physics_bodies = Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)
		var physics_text = "Physics: " + str(physics_bodies)
		draw_string(ThemeDB.fallback_font, Vector2(padding, y_offset + font_size), physics_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.7, 0.7, 0.7, 1.0))
		y_offset += line_height

	# Update size to fit content
	custom_minimum_size.y = y_offset + padding
