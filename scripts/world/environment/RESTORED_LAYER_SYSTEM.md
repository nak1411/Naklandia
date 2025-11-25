# ProceduralFoliageSpawner - Layer System Restored

## What Happened
I accidentally ran `git checkout` which reverted the refactored ProceduralFoliageSpawner.gd back to the old ProceduralTreeSpawner version. I've now recreated the complete multi-layer system.

## Current System

### Files
- **[FoliageLayer.gd](FoliageLayer.gd)** - Resource class for defining individual foliage layers (trees, bushes, rocks, etc.)
- **[ProceduralFoliageSpawner.gd](ProceduralFoliageSpawner.gd)** - Main spawner supporting multiple foliage layers

### Key Features

1. **Multi-Layer Architecture**
   - `@export var foliage_layers: Array[FoliageLayer] = []`
   - Each layer has independent settings for density, LOD, rendering, visibility
   - Layers processed in a single chunk system (no redundant calculations)

2. **Per-Layer Shader-Based Visibility Fading** ✅
   - Uses shader distance calculation (per-vertex, works correctly with MultiMesh)
   - NOT using GPU visibility range (which measures from chunk center and causes fade bugs)
   - Layer setting: `use_custom_visibility_range = true`
   - Layer setting: `visibility_range_end` - distance where items fade out
   - Layer setting: `visibility_fade_margin` - fade transition distance

3. **Architecture**
   ```gdscript
   class LayerInstanceData:
       var layer_name: String
       var multimesh_instances: Array[MultiMeshInstance3D]
       var transforms: Array[Transform3D]

   class ChunkData:
       var chunk_key: String
       var world_pos: Vector2
       var layers: Dictionary = {}  # layer_name -> LayerInstanceData
   ```

## How to Configure Per-Layer Fading

### Bushes Layer
Open your bushes FoliageLayer resource:
- `Use Custom Visibility Range` = **true**
- `Visibility Range End` = **80.0** (bushes invisible beyond 80m)
- `Visibility Fade Margin` = **20.0** (fade from 60m to 80m)

### Trees Layer
Open your trees FoliageLayer resource:
- `Use Custom Visibility Range` = **true**
- `Visibility Range End` = **150.0** (trees invisible beyond 150m)
- `Visibility Fade Margin` = **30.0** (fade from 120m to 150m)

## Result
- Trees will stay visible longer and fade at 120-150m
- Bushes will fade sooner at 60-80m
- All done with smooth shader-based fading (no pop-in/out)
- GPU efficient (dithered alpha for proper depth testing)

## Important Notes
- **DO NOT enable GPU Visibility Range** on the ProceduralFoliageSpawner node
- GPU visibility range doesn't work with MultiMesh (fades entire chunks, not individual items)
- Shader-based fading is the correct solution for per-item distance fading
