# Connect Mode Testing Guide

## Quick Start Test

### Step 1: Open WorkbenchWindow
1. Run your game/scene
2. Open the WorkbenchWindow (3D assembly view)
3. You should see the viewport with grid and any spawned parts

### Step 2: Spawn Two Objects
1. In the parts list (sidebar), select a part (e.g., "small_wooden_board")
2. Click "Add Object" to spawn it
3. Repeat to spawn a second object
4. Use Move mode (W key) to position them so they overlap or touch

### Step 3: Select Both Objects
1. Press Q to enter Select mode
2. Click on the first object (it should highlight)
3. Hold SHIFT and click on the second object
4. Both objects should now be selected

### Step 4: Enter Connect Mode
1. Press **C** key
2. Console should show:
   ```
   === Connect Mode ACTIVATED ===
     Target A: [object name]
     Target B: [object name]
     Fastener: fastener_steel_bolt
   ```

### Step 5: Place Fasteners
1. Move your mouse over the viewport
2. **Yellow preview line should appear** where the ray intersects both objects
3. If you don't see it, check console for errors (ray may not be hitting both objects)
4. Left-click to place a fastener
5. You should see a red cross (joint helper) at the connection point
6. Keep clicking to place multiple fasteners

### Step 6: Exit Connect Mode
1. Press **Q** to exit
2. Objects should now be physically connected
3. You can test by moving one - the other should follow

## Troubleshooting

### "No yellow preview line appears"

**Possible causes:**
1. **Ray not passing through both objects**
   - Try rotating the camera (Alt+Left Mouse)
   - Position objects so they overlap more
   - Aim through the overlapping area

2. **Objects too far apart**
   - Default max bolt length is 2.0m
   - Move objects closer together

3. **Check console output**
   - Look for: "Connect Mode: Found X intersection points"
   - If 0 intersections, ray isn't hitting anything
   - If < 2 different objects, reposition view

**Debug output to look for:**
```
Connect Mode: Found 4 intersection points along ray
  Hit 0: wooden_board_small at 1.000,0.500,0.000
  Hit 1: wooden_board_small at 1.200,0.500,0.000
  Hit 2: wooden_board_large at 1.210,0.500,0.000
  Hit 3: wooden_board_large at 1.400,0.500,0.000
Connect Mode: Best intersection - A: 1.200,0.500,0.000  B: 1.210,0.500,0.000  Distance: 0.010m
```

### "Preview line in wrong place"

The new algorithm finds the **closest pair of intersection points** between the two objects. This should be at or near where they touch/overlap.

- Entry point on object A (where ray enters/exits A near B)
- Entry point on object B (where ray enters/exits B near A)
- Midpoint = fastener placement

### "Error: Ray didn't hit [object name]"

Your viewing angle doesn't pass through that object. Try:
1. Orbit camera to different angle
2. Ensure object is visible and not behind another
3. Aim through the overlapping region

### "Error: Distance too large (X.XXm > 2.00m max)"

Objects are too far apart at that intersection point. Solutions:
1. Move objects closer together
2. Click at a different intersection angle
3. Increase `connect_mode_max_bolt_length` in code (line 165)

### "Error: Objects are overlapping at this point (0.0000m)"

The intersection points are exactly coincident (same position). This usually means:
1. Objects are deeply intersecting at that exact spot
2. Try a slightly different angle/position

## Expected Console Output

### Successful placement:
```
Connect Mode: Found 4 intersection points along ray
  Hit 0: board_A at 1.000,0.500,0.000
  Hit 1: board_A at 1.200,0.500,0.000
  Hit 2: board_B at 1.205,0.500,0.000
  Hit 3: board_B at 1.400,0.500,0.000
Connect Mode: Best intersection - A: 1.200,0.500,0.000  B: 1.205,0.500,0.000  Distance: 0.005m
Fastener: Loaded properties for fastener_steel_bolt - strength: 200.0, type: fixed
Fastener: Created joint between board_A and board_B
Fastener placed! Distance: 0.005m, Type: fastener_steel_bolt
Connected board_A to board_B
```

## Testing Scenarios

### Scenario 1: T-Joint (Perpendicular Boards)
1. Spawn 2 boards
2. Rotate one 90 degrees (E key for rotate mode)
3. Position them in a T shape
4. Select both, press C
5. Click along the joint line multiple times
6. Should create a row of bolts

### Scenario 2: Corner Joint
1. Spawn 2 boards
2. Position at 90-degree angle (corner)
3. Select both, press C
4. Click through the corner
5. Bolt should appear at the edge intersection

### Scenario 3: Overlapping Flat Surfaces
1. Spawn 2 boards
2. Stack them flat (one on top of other)
3. Select both, press C
4. Click through the stack
5. Should work if there's a small gap between them

### Scenario 4: Table Assembly
1. Spawn 4 table legs + 1 tabletop
2. Position legs under corners
3. For each leg:
   - Select leg + tabletop
   - Press C
   - Click through connection point
   - Press Q
4. Repeat for all 4 legs
5. Table should be fully assembled

## Visual Indicators

### Yellow Preview Line
- **Visible**: Ray passes through both objects successfully
- **Not visible**: Ray doesn't intersect properly
- **Thickness**: 1.5cm diameter (should be easy to see)
- **Brightness**: Emissive yellow, always on top (no_depth_test)

### Joint Helpers (after placement)
- **Red cross**: Fixed joint (bolt/screw/nail)
- **Green cross**: Hinge joint
- **Blue cross**: Ball socket joint
- **Size**: 15cm cross shape at connection point

## Performance Notes

- Maximum 20 raycast iterations per preview update
- Preview updates on every mouse move (in Connect Mode)
- Console output can be verbose - this is intentional for debugging
- Each fastener creates a physics joint (lightweight)

## Known Limitations

1. **Requires collision geometry**: Objects must have proper collision shapes
2. **Physics layer 3**: Objects must be on layer 3 (PhysicalItem default)
3. **Two objects only**: Can't connect 3+ objects simultaneously (yet)
4. **No undo**: Fastener placement can't be undone (delete and recreate)
5. **Gap sensitivity**: Very small gaps (<1mm) may cause "overlapping" error

## Tips for Best Results

1. **Use Alt+Left Mouse** to orbit and find good angles
2. **Zoom in** (Alt+Right Mouse) for precision placement
3. **Multiple angles**: Place fasteners from different directions for strength
4. **Spacing**: Leave 10-20cm between bolts for realistic assembly
5. **Check console**: Debug output shows exactly what's being detected
