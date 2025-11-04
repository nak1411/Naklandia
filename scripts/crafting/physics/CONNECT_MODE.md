# Connect Mode (Bolt Gun) Feature

## Overview

Connect Mode is a "bolt gun" style fastener placement system that allows you to quickly connect two PhysicalItems by firing bolts through them at precise raycast intersections.

## How It Works

### Activation

1. **Select exactly 2 objects** in the WorkbenchWindow
2. Press **C** key or click the Connect Mode button to enter Connect Mode
3. The system validates you have exactly 2 items selected - if not, it reverts to Select Mode

### Usage

Once in Connect Mode:

1. **Move your mouse** over the 3D viewport
2. A **yellow preview line** shows where the bolt will be placed (if valid)
3. **Left-click** to place a fastener at that location
4. The ray must pass through **both** selected objects
5. **Continue clicking** to place multiple fasteners rapidly
6. Press **Q** to exit Connect Mode

### Controls

- **C**: Enter Connect Mode (requires 2 selected items)
- **Q**: Exit Connect Mode
- **Left Mouse**: Place fastener where ray intersects both objects
- **Mouse Move**: Update preview line
- **Alt + Mouse**: Standard camera controls still work

## Technical Details

### Ray Intersection Logic

The system performs two sequential raycasts:

1. **First Raycast**: From camera through mouse cursor, hits the first object
2. **Second Raycast**: Continues from just past the first hit, hits the second object

### Validation

The system checks:

- ✓ Ray hits one of the two selected objects first
- ✓ Ray hits the other selected object second (not the same one)
- ✓ Distance between hit points is within max bolt length (default: 2.0m)
- ✓ Both objects are PhysicalItem instances

### Edge Cases Handled

#### Case 1: Ray only hits one object
**Result**: Preview hidden, error message: "Ray didn't pass through second object"
**Solution**: Angle your view so the ray passes through both objects

#### Case 2: Ray hits same object twice
**Result**: Error message: "Ray hit the same object twice"
**Solution**: Reposition objects or change camera angle

#### Case 3: Gap too large
**Result**: Error message: "Distance too large (X.XXm > 2.00m max)"
**Solution**: Move objects closer together, or adjust `connect_mode_max_bolt_length`

#### Case 4: Ray hits wrong object
**Result**: Error message: "Ray hit object that isn't selected (ObjectName)"
**Solution**: Remove obstructing objects or select them instead

### Visual Feedback

#### Preview Line
- **Color**: Bright yellow with emission
- **Thickness**: 1cm diameter cylinder
- **Visibility**: Only shown when raycast is valid
- **Real-time**: Updates on every mouse move

#### Joint Visualization
Once placed, fasteners create physical joints with visual helpers:
- **Red cross**: Fixed joints (bolts, screws, nails)
- **Green cross**: Hinge joints
- **Blue cross**: Ball socket joints

## Implementation Details

### Key Functions

- `_enter_connect_mode()`: Validates selection and activates mode
- `_exit_connect_mode()`: Deactivates mode and hides preview
- `_perform_connect_mode_raycast()`: Dual-raycast logic with validation
- `_update_connect_mode_preview()`: Real-time preview line update
- `_place_fastener_at_ray()`: Creates Fastener and Joint at intersection
- `_handle_connect_mode_input()`: Input handling for Connect Mode

### State Variables

```gdscript
var connect_mode_active: bool = false
var connect_mode_target_a: PhysicalItem = null
var connect_mode_target_b: PhysicalItem = null
var connect_mode_preview_line: MeshInstance3D = null
var connect_mode_max_bolt_length: float = 2.0
var fasteners_created: Array[Fastener] = []
```

### Integration

Connect Mode is integrated into:
- Transform Mode enum (added `CONNECT`)
- Main `_input()` event handler (priority handling)
- Mode button system (connect_button)
- Keyboard shortcuts (C key)

## Usage Examples

### Example 1: Simple Board Connection

```
1. Place two wooden boards overlapping
2. Select both boards (Click first, Shift+Click second)
3. Press C to enter Connect Mode
4. Click through the overlapping area
5. Multiple bolts placed rapidly
6. Press Q when done
```

### Example 2: Table Leg to Tabletop

```
1. Position table leg under tabletop corner
2. Select both items
3. Press C for Connect Mode
4. Click through the leg-to-top connection point
5. Repeat at other corners with different leg pairs
6. Q to exit
```

### Example 3: Pattern Placement

```
1. Select two boards in a T-joint
2. Press C for Connect Mode
3. Click evenly spaced points along the joint line
4. Creates a row of bolts in seconds
5. Q to exit
```

## Benefits

### Speed
- No need to manually position fasteners
- Click-to-place workflow
- Rapid repeat placement
- Visual feedback immediate

### Accuracy
- Ray-based placement ensures perfect alignment
- Fasteners always connect both objects correctly
- Preview shows exact placement before committing

### Intuitive
- Feels like using a real bolt gun
- Natural camera-to-target aiming
- Real-time feedback
- Simple controls

## Future Enhancements

### Possible Improvements

1. **Pattern Mode**: Auto-place evenly spaced fasteners
   - Define start/end points
   - Set spacing distance
   - One-click placement

2. **Fastener Selection in Mode**: Switch fastener types without exiting
   - 1-5 keys for different fastener types
   - Visual indicator of selected type

3. **Angle Constraints**: Warn if fastener angle is too shallow
   - Minimum angle validation
   - Color-coded preview (green/yellow/red)

4. **Multi-Object Support**: Connect more than 2 objects
   - First click selects object A
   - Second click selects object B
   - Dynamic target switching

5. **Strength Visualization**: Show joint stress
   - Color-coded joint helpers
   - Real-time stress display
   - Warning before failure

## Troubleshooting

### Preview line doesn't appear
- Check that both objects are selected
- Verify mouse is over viewport
- Ensure ray passes through both objects
- Check objects aren't too far apart

### Can't place fastener
- Verify you're in Connect Mode (C key)
- Check console for specific error message
- Ensure ray hits both selected objects
- Objects might be too far apart

### Fastener placed in wrong location
- Preview line shows exact placement
- If no preview, ray isn't hitting both objects
- Adjust camera angle for better alignment

## Code Location

**File**: `scripts/crafting/physics/WorkbenchWindow.gd`

**Section**: Lines 2926-3199 (CONNECT MODE implementation)

**Related Classes**:
- `Fastener.gd`: Fastener data and joint creation
- `Joint.gd`: Physics joint implementation
- `PhysicalItem.gd`: Base class for connectable objects
