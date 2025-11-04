# Connect Mode (Bolt Gun) - How It Works

## Two Different Behaviors

Connect Mode has **two separate raycast behaviors** depending on whether you're hovering or clicking:

### 1. PREVIEW (Mouse Hover) - Visual Feedback Only

**Purpose**: Show you where your cursor is aiming

**What it does**:
- Simple raycast from camera through cursor
- Shows yellow line to where ray hits object **surfaces**
- This is just visual feedback - NOT where the fastener will be placed
- Updates in real-time as you move the mouse

**Implementation**: `_get_surface_hits_for_preview()`
- First raycast hits object A surface → Shows line to that point
- If ray continues and hits object B surface → Extends line to B's surface
- Yellow line indicates "I'm aiming here"

### 2. PLACEMENT (Left Click) - Actual Fastener Creation

**Purpose**: Place fastener at the actual intersection/contact point between objects

**What it does**:
- Fires ray **THROUGH** both objects (multiple raycasts)
- Detects ALL intersection points (entry/exit on both objects)
- Finds the **closest pair** between objects (their actual contact point)
- Places fastener at that intersection

**Implementation**: `_perform_connect_mode_raycast()`
- Multiple sequential raycasts along the ray
- Captures entry AND exit points for both objects
- Finds closest pair: `exit_A` and `entry_B` (or vice versa)
- This is where objects actually touch/connect

## Visual Example

```
Scenario: Two overlapping boards (A and B)

        Camera
           |
           | Ray
           ↓
    ┌──────────────┐  ← Object A (front surface)
    │   Board A    │
    │      ┌───────┼─────┐  ← Intersection/Contact area
    │      │   ////│/////│     (This is where fastener should go!)
    └──────┼───────┘     │
           │   Board B   │
           └─────────────┘

PREVIEW Mode (hover):
  Yellow line: Camera → Front of A
  (Simple visual feedback)

PLACEMENT Mode (click):
  1. Ray enters A (front surface)
  2. Ray exits A  ← Point A (near contact)
  3. Ray enters B ← Point B (near contact)
  4. Ray exits B (back surface)

  Finds closest pair (2 & 3) → Fastener placed at intersection!
```

## Why Two Behaviors?

### Preview needs to be fast and simple
- Updates every frame on mouse move
- Just needs to show "I'm aiming here"
- Single/double raycast is sufficient
- Low CPU overhead

### Placement needs to be accurate
- Only runs on click (once)
- Must find the actual contact point
- Multiple raycasts to capture all intersections
- Find closest pair algorithm
- Higher CPU cost, but only when placing

## Console Output Examples

### Preview (hovering, no output)
```
(Silent - just updates yellow line position)
```

### Placement (clicking)
```
=== FIRING BOLT GUN (detecting intersection) ===
Connect Mode: Found 4 intersection points along ray
  Hit 0: board_A at 1.000,0.500,0.000  ← Entry into A
  Hit 1: board_A at 1.200,0.500,0.000  ← Exit from A (near contact)
  Hit 2: board_B at 1.205,0.500,0.000  ← Entry into B (near contact)
  Hit 3: board_B at 1.400,0.500,0.000  ← Exit from B
Connect Mode: Best intersection - A: 1.200,0.500,0.000  B: 1.205,0.500,0.000  Distance: 0.005m
Fastener: Loaded properties for fastener_steel_bolt - strength: 200.0, type: fixed
Fastener: Created joint between board_A and board_B
✓ Fastener placed at INTERSECTION! Distance: 0.005m, Type: fastener_steel_bolt
✓ Connected board_A to board_B at their contact point
  Connection point: 1.202, 0.500, 0.000
```

## Key Features

### Preview System
- **Fast**: Single/double raycast
- **Visual**: Shows aiming direction
- **Real-time**: Updates on mouse move
- **Non-blocking**: No console spam

### Placement System
- **Accurate**: Multiple raycasts with `hit_from_inside = true`
- **Smart**: Finds actual contact point via closest-pair algorithm
- **Verbose**: Console output shows exactly what's detected
- **Validated**: Checks distance, object matching, etc.

## Edge Cases Handled

### Preview
1. **Ray misses objects**: Line hidden
2. **Ray hits only one**: Short indicator line shown
3. **Ray hits both**: Line extends through both

### Placement
1. **Ray hits only one object**: Error message
2. **Objects too far apart**: Distance validation
3. **Objects overlapping**: Detects and reports
4. **Ray hits wrong objects**: Validates targets
5. **Multiple hits on same object**: Filters correctly

## Technical Details

### Preview Raycast
```gdscript
func _get_surface_hits_for_preview(mouse_pos):
    1. Camera → Ray → First object surface hit
    2. Continue ray → Second object surface hit (optional)
    3. Show line between hit points
    Return: visual feedback only
```

### Placement Raycast
```gdscript
func _perform_connect_mode_raycast(mouse_pos):
    1. Fire ray from camera
    2. Loop: Collect ALL intersection points
       - hit_from_inside = true (detect exits too)
       - Move ray origin past each hit
       - Continue until no more hits
    3. Filter hits by target objects (A and B)
    4. Find closest pair between A's hits and B's hits
    5. Validate distance and placement
    6. Return intersection points
```

## User Experience

### What the user sees:
1. **Select 2 objects** → Press C
2. **Move mouse** → Yellow line appears showing aim
3. **Adjust angle** → Line updates in real-time
4. **Left-click** → Brief calculation
5. **Red cross appears** → Fastener placed at contact point
6. **Console confirms** → Exact placement details

### What happens behind the scenes:
- **Hover**: Fast preview updates (every frame)
- **Click**: Comprehensive intersection detection (once per click)
- **Result**: Fastener placed exactly where objects touch

## Benefits of This Approach

1. **Intuitive**: Preview shows where you're aiming
2. **Accurate**: Placement finds actual intersection
3. **Fast**: Preview doesn't lag despite real-time updates
4. **Precise**: Multi-raycast ensures correct placement
5. **Debuggable**: Console shows all detection details
6. **Flexible**: Works with any object orientation/overlap

## Troubleshooting

### "Preview line shows but fastener doesn't place"
- Preview just shows surface aiming
- Placement requires ray to pass through **both** objects' collision volumes
- Try different angle where ray penetrates both objects

### "Fastener not at expected location"
- Check console output for detected intersection points
- System finds **closest** pair between objects
- This might not be the first surface hit you see in preview

### "Preview line looks wrong"
- Preview shows simple surface hits (by design)
- This is NOT where fastener will be placed
- Click to see actual placement at intersection

## Summary

**Preview = "Where am I aiming?"** (simple, fast, visual feedback)

**Placement = "Where do these objects actually touch?"** (accurate, thorough, intersection detection)

This two-tier approach gives you responsive visual feedback while ensuring accurate fastener placement at the actual contact points between objects.
