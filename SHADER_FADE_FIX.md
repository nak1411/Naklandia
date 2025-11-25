# Shader-Based Per-Layer Fading Fix

## Problem
GPU visibility range (`use_visibility_range`) doesn't work correctly with MultiMesh because Godot measures distance from the **MultiMeshInstance3D node position** (chunk center), not from individual trees/bushes. This causes all items in a chunk to fade together based on chunk center distance.

## Solution
Use shader-based fading instead, which calculates distance per-vertex in the shader.

## Code Change Needed

In `ProceduralFoliageSpawner.gd`, around line 623-651, replace the shader application code with:

```gdscript
# Apply fade shader if needed (shader-based distance fading works per-vertex, unlike GPU visibility range)
if tree_fade_shader and (layer.use_impostors or chunk_fade_in_duration > 0 or layer.use_custom_visibility_range):
	var fade_mat = ShaderMaterial.new()
	fade_mat.shader = tree_fade_shader

	# Determine fade distances - use per-layer settings if available
	var fade_end: float
	var fade_start: float
	if layer.use_impostors:
		fade_end = layer.impostor_distance
		fade_start = layer.impostor_distance - lod_fade_range
	elif layer.use_custom_visibility_range:
		fade_end = layer.visibility_range_end
		fade_start = layer.visibility_range_end - layer.visibility_fade_margin
	else:
		fade_end = visibility_range_end
		fade_start = visibility_range_end - lod_fade_range

	fade_mat.set_shader_parameter("fade_start", fade_start)
	fade_mat.set_shader_parameter("fade_end", fade_end)
	fade_mat.set_shader_parameter("chunk_load_time", chunk_data.load_time)
	fade_mat.set_shader_parameter("chunk_fade_duration", chunk_fade_in_duration)

	if mesh.surface_get_material(0) is StandardMaterial3D:
		var orig_mat = mesh.surface_get_material(0) as StandardMaterial3D
		if orig_mat.albedo_texture:
			fade_mat.set_shader_parameter("albedo_texture", orig_mat.albedo_texture)
			fade_mat.set_shader_parameter("use_texture", true)
		fade_mat.set_shader_parameter("albedo_color", orig_mat.albedo_color)
	mmi.material_override = fade_mat

	if debug_performance:
		print("    [", layer.layer_name, "] Shader fade: start=", fade_start, " end=", fade_end)
```

This replaces the old `if layer.use_impostors... elif chunk_fade_in_duration...` block.

## Configuration Steps

1. **Disable GPU Visibility Range** (it doesn't work well with MultiMesh):
   - ProceduralFoliageSpawner → GPU Culling → `Use Visibility Range` = **false**

2. **Enable Shader Fading**:
   - ProceduralFoliageSpawner → GPU Culling → `Chunk Fade In Duration` = **0.5** (or any value > 0)

3. **Configure Per-Layer Fade Distances**:

   **Bushes Layer**:
   - `Use Custom Visibility Range` = **true**
   - `Visibility Range End` = **80.0**
   - `Visibility Fade Margin` = **20.0**

   **Trees Layer**:
   - `Use Custom Visibility Range` = **true**
   - `Visibility Range End` = **150.0**
   - `Visibility Fade Margin` = **30.0**

## How It Works

- **Shader fading** calculates distance from camera to each vertex (per-tree/bush)
- **GPU visibility range** calculates distance from camera to the MMI node (per-chunk)
- Shader fading provides accurate per-item fading
- Items fade out smoothly from `(end - margin)` to `end` distance
