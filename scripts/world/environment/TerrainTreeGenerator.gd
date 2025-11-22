# TerrainTreeGenerator.gd
# Editor tool for generating trees on terrain
@tool
extends EditorScript

func _run():
	var scene_root = get_scene()
	if not scene_root:
		print("No scene loaded!")
		return

	# Find the tree spawner in the scene
	var spawner = find_tree_spawner(scene_root)
	if not spawner:
		print("No ProceduralTreeSpawner found in scene!")
		return

	# Trigger tree generation
	print("Starting procedural tree generation...")
	spawner.generate_trees()
	print("Tree generation initiated!")

func find_tree_spawner(node: Node) -> Node:
	if node.get_script() and node.get_script().get_global_name() == "ProceduralTreeSpawner":
		return node

	for child in node.get_children():
		var result = find_tree_spawner(child)
		if result:
			return result

	return null
