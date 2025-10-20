extends Node3D

# Waypoint configuration
@export var waypoint_label: String = "Waypoint"
@export var waypoint_color: Color = Color(1.0, 0.0, 0.0, 1.0)
@export var float_height: float = 0.05
@export var max_visible_distance: float = 200.0
@export var fade_start_distance: float = 150.0

# References
var player: Node3D
var label_3d: Label3D
var marker_mesh: Sprite3D


func _ready():
	print("Waypoint3D created: ", name)
	_setup_waypoint_visuals()
	_find_player()


func _setup_waypoint_visuals():
	# Create billboard diamond sprite
	var sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.pixel_size = 0.01

	# Create diamond texture - use WHITE so modulation works correctly
	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Draw diamond shape in white
	for y in range(32):
		for x in range(32):
			var center_x = 16.0
			var center_y = 16.0
			var dx = abs(x - center_x)
			var dy = abs(y - center_y)

			# Diamond shape formula
			if (dx + dy) < 14:
				var dist = (dx + dy) / 14.0
				var alpha = 1.0 - (dist * 0.3)  # Fade from center
				# Use WHITE color - the modulate will apply the actual color
				var color = Color.WHITE
				color.a = alpha
				img.set_pixel(x, y, color)

	var texture = ImageTexture.create_from_image(img)
	sprite.texture = texture
	sprite.modulate = waypoint_color
	sprite.position.y = float_height

	marker_mesh = sprite  # Store reference

	add_child(sprite)

	# Create label
	label_3d = Label3D.new()
	label_3d.text = waypoint_label
	label_3d.pixel_size = 0.01
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.no_depth_test = true
	label_3d.modulate = waypoint_color
	label_3d.outline_size = 4
	label_3d.outline_modulate = Color(0, 0, 0, 0.9)
	label_3d.position = Vector3(0, float_height + 1.0, 0)
	label_3d.font_size = 24

	add_child(label_3d)

	# Add distance label below
	var distance_label = Label3D.new()
	distance_label.name = "DistanceLabel"
	distance_label.text = "0m"
	distance_label.pixel_size = 0.008
	distance_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	distance_label.no_depth_test = true
	distance_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	distance_label.outline_size = 4
	distance_label.outline_modulate = Color(0, 0, 0, 0.9)
	distance_label.position = Vector3(0, float_height + 0.5, 0)
	distance_label.font_size = 18

	add_child(distance_label)


func _find_player():
	var player_node = get_tree().get_first_node_in_group("player")
	if player_node:
		player = player_node


func _process(_delta):
	# Update visibility and distance based on player distance
	if player:
		var distance = global_position.distance_to(player.global_position)

		# Scale based on distance to maintain constant screen size
		var scale_factor = distance * 0.1
		scale = Vector3.ONE * scale_factor

		# Update distance label
		var distance_label = get_node_or_null("DistanceLabel")
		if distance_label:
			distance_label.text = str(int(distance)) + "m"

		# Handle visibility and fade
		if distance > max_visible_distance:
			visible = false
		else:
			visible = true

			# Fade based on distance
			var alpha = 1.0
			if distance > fade_start_distance:
				var fade_range = max_visible_distance - fade_start_distance
				var fade_amount = 1.0 - ((distance - fade_start_distance) / fade_range)
				alpha = clamp(fade_amount, 0.0, 1.0)

			# Apply alpha to all visual elements
			if label_3d:
				var label_color = waypoint_color
				label_color.a = alpha
				label_3d.modulate = label_color

			if distance_label:
				var dist_color = Color.WHITE
				dist_color.a = alpha
				distance_label.modulate = dist_color

			if marker_mesh:
				var sprite_color = waypoint_color
				sprite_color.a = alpha
				marker_mesh.modulate = sprite_color


func set_waypoint_data(label: String, color: Color):
	waypoint_label = label
	waypoint_color = color

	if label_3d:
		label_3d.text = label
		label_3d.modulate = color

	if marker_mesh:
		marker_mesh.modulate = color
