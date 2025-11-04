# Connect Mode - Visual Fire Line & Increased Ray Distance

## Changes Made

### 1. Increased Ray Distance

**Ray Distance:**
- **Old**: 100 meters
- **New**: 500 meters (`connect_mode_max_ray_distance`)

**Max Bolt Length:**
- **Old**: 2.0 meters
- **New**: 5.0 meters (`connect_mode_max_bolt_length`)

This allows the bolt gun to detect objects much further away, solving the issue where distant objects weren't being detected.

### 2. Visual Fire Line

Added a bright orange/red laser-like line that appears when you click (fire the bolt gun).

**Features:**
- **Color**: Bright orange (Color(1.0, 0.3, 0.0))
- **Emission**: High energy (3.0x multiplier) - very bright
- **Thickness**: 2.5cm diameter (thicker than preview line)
- **Duration**: Visible for 0.5 seconds after firing
- **Always on top**: Renders over everything (no_depth_test)
- **Full length**: Shows entire ray path from camera through scene

### 3. Two Visual Lines

#### Preview Line (Yellow)
- **Purpose**: Show where you're aiming (on hover)
- **Color**: Yellow
- **Thickness**: 1.5cm
- **Visibility**: While hovering in Connect Mode
- **Length**: From camera to surface hits

#### Fire Line (Orange)
- **Purpose**: Show when bolt gun fires (on click)
- **Color**: Bright orange/red
- **Thickness**: 2.5cm (thicker, more visible)
- **Visibility**: 0.5 seconds after clicking
- **Length**: Full ray distance (500m from camera)

## Implementation Details

### New Variables

```gdscript
var connect_mode_fire_line: MeshInstance3D = null
var connect_mode_max_bolt_length: float = 5.0
var connect_mode_max_ray_distance: float = 500.0
var fire_line_timer: float = 0.0
const FIRE_LINE_DURATION: float = 0.5
```

### New Functions

#### `_create_fire_line()`
Creates the orange fire line mesh when entering Connect Mode.

```gdscript
func _create_fire_line() -> void:
    # Creates bright orange cylinder mesh
    # Emission energy: 3.0 (very bright)
    # Always visible on top
```

#### `_show_fire_line(mouse_pos)`
Displays the fire line when clicking (firing bolt gun).

```gdscript
func _show_fire_line(mouse_pos: Vector2) -> void:
    # Draws line from camera to max distance
    # Makes visible for FIRE_LINE_DURATION
    # Starts fade timer
```

### Updated Functions

#### `_process(delta)`
Added timer handling for fire line auto-hide:

```gdscript
if fire_line_timer > 0.0:
    fire_line_timer -= delta
    if fire_line_timer <= 0.0:
        connect_mode_fire_line.visible = false
```

#### `_perform_connect_mode_raycast()`
Now uses `connect_mode_max_ray_distance` (500m) instead of hardcoded 100m.

#### `_get_surface_hits_for_preview()`
Also updated to use `connect_mode_max_ray_distance`.

#### `_place_fastener_at_ray()`
Calls `_show_fire_line()` before performing raycast.

## Visual Behavior

### Normal Operation (Hover)
```
User moves mouse in Connect Mode:
  → Yellow preview line appears
  → Shows where ray hits surfaces
  → Updates in real-time
```

### Firing (Click)
```
User clicks to place fastener:
  → 🔫 Bright orange line flashes from camera
  → Shows full 500m ray path
  → Line visible for 0.5 seconds
  → Fades out automatically
  → Yellow preview line continues updating
```

### Sequence
```
1. Hover: Yellow line (surface preview)
2. Click: Orange flash (firing animation)
3. After 0.5s: Orange disappears
4. Back to: Yellow line (surface preview)
```

## Console Output

### When Firing
```
=== FIRING BOLT GUN (detecting intersection) ===
🔫 BOLT GUN FIRED - Visual ray displayed for 0.5s
Connect Mode: Found 4 intersection points along ray
  Hit 0: board_A at 1.000,0.500,0.000
  Hit 1: board_A at 1.200,0.500,0.000
  Hit 2: board_B at 1.205,0.500,0.000
  Hit 3: board_B at 1.400,0.500,0.000
✓ Fastener placed at INTERSECTION!
```

## Benefits

### 1. Increased Detection Range
- Can now detect objects up to 500m away
- Bolt length increased to 5m (was 2m)
- Solves issue with distant objects not being detected

### 2. Visual Feedback
- Clear indication when bolt gun fires
- Shows exact ray path through scene
- Helps understand what the raycast is doing
- Looks cool and satisfying

### 3. Debug Aid
- Fire line shows if ray is aimed correctly
- Can see if ray passes through both objects
- Visual confirmation of firing action

## Color Coding

| Line | Color | Purpose | When Visible |
|------|-------|---------|-------------|
| **Preview** | Yellow | Aiming feedback | Hovering |
| **Fire** | Orange | Firing animation | 0.5s after click |

## Material Properties

### Preview Line
```gdscript
albedo_color: Yellow (1, 1, 0)
emission: Yellow, 2.0x energy
thickness: 1.5cm
no_depth_test: true (always visible)
```

### Fire Line
```gdscript
albedo_color: Orange (1, 0.3, 0)
emission: Orange-red (1, 0.5, 0), 3.0x energy
thickness: 2.5cm (thicker)
no_depth_test: true (always visible)
```

## Timer System

The fire line uses a simple countdown timer:

```gdscript
# On click:
fire_line_timer = 0.5  # Start at 0.5 seconds

# Every frame (_process):
fire_line_timer -= delta
if fire_line_timer <= 0.0:
    hide fire line
```

## Configuration

Easy to customize via constants:

```gdscript
# Adjust fire line duration
const FIRE_LINE_DURATION: float = 0.5  # seconds

# Adjust distances
var connect_mode_max_ray_distance: float = 500.0  # max raycast
var connect_mode_max_bolt_length: float = 5.0     # max fastener
```

## Testing

### Test 1: Fire Line Appears
1. Enter Connect Mode (2 objects selected)
2. Click anywhere in viewport
3. ✓ Bright orange line should flash from camera
4. ✓ Line extends far into distance
5. ✓ Line disappears after 0.5 seconds

### Test 2: Fire Line Shows Ray Path
1. Position camera at different angles
2. Click to fire
3. ✓ Orange line shows exact ray direction
4. ✓ Line goes through objects if aimed correctly
5. ✓ Can see the full 500m path

### Test 3: Both Lines Work Together
1. Hover (yellow preview appears)
2. Click (orange fire flashes)
3. ✓ Both lines visible briefly
4. ✓ Orange fades after 0.5s
5. ✓ Yellow continues showing

### Test 4: Increased Distance Detection
1. Place objects far apart (>100m)
2. Enter Connect Mode
3. Click to fire
4. ✓ Should now detect objects (old: would fail)
5. ✓ Console shows hits detected

### Test 5: Rapid Fire
1. Click multiple times quickly
2. ✓ Each click resets the 0.5s timer
3. ✓ Line stays visible as long as clicking
4. ✓ Fades 0.5s after last click

## Performance

- Fire line only visible 0.5s at a time
- Preview line always visible (in Connect Mode)
- Both use simple cylinder meshes (low poly)
- No depth test = slight GPU cost but negligible
- Timer check in _process is very cheap

## Future Enhancements

Potential improvements:

1. **Fade Animation**: Gradually fade fire line instead of instant hide
2. **Trail Effect**: Leave multiple fading lines for rapid fire
3. **Hit Markers**: Show spheres at intersection points
4. **Color Coding**: Green if hit both objects, red if miss
5. **Sound Effect**: "Pew pew" when firing
6. **Particles**: Sparks at hit points
7. **Recoil Animation**: Camera shake on fire

## Summary

The Connect Mode now has:
- ✅ **500m ray distance** (was 100m) - detects distant objects
- ✅ **5m max bolt length** (was 2m) - allows larger gaps
- ✅ **Visual fire line** - bright orange ray when clicking
- ✅ **0.5 second duration** - line auto-hides
- ✅ **Full ray visualization** - shows entire 500m path

This makes the bolt gun more functional (increased range) and more satisfying to use (visual feedback)!
