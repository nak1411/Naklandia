# Connect Mode Button Implementation

## Changes Made

### UI Changes
- **Added**: "Connect Mode (Bolt Gun)" toggle button in sidebar
- **Location**: Above the "Validate Construct" button
- **Type**: Toggle button (stays pressed when active)

### Code Changes

#### 1. Scene File: `workbench_window.tscn`
Added new button node:
```gdscript
[node name="ConnectModeButton" type="Button" parent="VBoxContainer/MainContent/SidebarPanel/VBoxContainer"]
layout_mode = 2
focus_mode = 0
toggle_mode = true
text = "Connect Mode (Bolt Gun)"
```

#### 2. Script File: `WorkbenchWindow.gd`

**Added variable:**
```gdscript
var connect_mode_button: Button
```

**Added initialization:**
```gdscript
connect_mode_button = $VBoxContainer/MainContent/SidebarPanel/VBoxContainer/ConnectModeButton
```

**Added signal connection:**
```gdscript
if connect_mode_button:
    connect_mode_button.toggled.connect(_on_connect_mode_button_toggled)
```

**Added button handler:**
```gdscript
func _on_connect_mode_button_toggled(button_pressed: bool) -> void:
    if button_pressed:
        # Enter Connect Mode
        _set_transform_mode(TransformMode.CONNECT)
    else:
        # Exit Connect Mode
        if connect_mode_active:
            _exit_connect_mode()
        _set_transform_mode(TransformMode.SELECT)
```

**Updated mode entry/exit:**
- `_enter_connect_mode()`: Sets button to pressed state
- `_exit_connect_mode()`: Sets button to unpressed state
- Q key handler: Also updates button state when exiting

### Removed Keyboard Shortcut

**Removed:** C key shortcut (was conflicting with other systems)

**Before:**
```gdscript
elif event.keycode == KEY_C:
    # C enters Connect Mode (Bolt Gun)
    _set_transform_mode(TransformMode.CONNECT)
```

**After:** C key no longer does anything

### How It Works Now

#### Entering Connect Mode

**Via Button:**
1. User selects 2 objects
2. User clicks "Connect Mode (Bolt Gun)" button
3. Button becomes pressed (highlighted)
4. Connect Mode activates if validation passes
5. If validation fails (not exactly 2 items), button unpresses automatically

**Validation:**
- Must have exactly 2 items selected
- If not, button unpresses and returns to Select Mode
- Error message shown in console

#### Exiting Connect Mode

**Via Button:**
- Click the pressed "Connect Mode" button again
- Button unpresses
- Connect Mode exits
- Returns to Select Mode

**Via Q Key:**
- Press Q while in Connect Mode
- Connect Mode exits
- Button automatically unpresses
- Returns to Select Mode

**Via Mode Change:**
- Press W, E, or R to change modes
- Connect Mode exits
- Button automatically unpresses

### Button States

#### Unpressed (Normal)
- Connect Mode is inactive
- Gray/default appearance
- Can be clicked to enter Connect Mode

#### Pressed (Active)
- Connect Mode is active
- Highlighted/pressed appearance
- Can be clicked again to exit Connect Mode

#### Auto-Unpress
Button automatically unpresses when:
- Validation fails (not 2 items selected)
- Q key pressed
- Different transform mode selected (W/E/R)
- Connect Mode exits for any reason

### User Experience

#### Old Behavior (C key)
```
User: *Presses C*
Result: Enters Connect Mode (conflicts with other shortcuts)
```

#### New Behavior (Button)
```
User: *Clicks button*
Button: Highlights/stays pressed
User: *Can see mode is active*
User: *Clicks button again*
Button: Unpresses
Result: Clear visual feedback, no conflicts
```

### Benefits

1. **No Keyboard Conflicts**: Button doesn't conflict with other key bindings
2. **Visual Feedback**: Button state shows whether mode is active
3. **Discoverable**: Users can see the feature in the UI
4. **Intuitive**: Toggle behavior matches mode activation
5. **Consistent**: Matches UI patterns from other applications

### Testing

#### Test 1: Enter via Button
1. Select 2 objects
2. Click "Connect Mode" button
3. ✓ Button should highlight
4. ✓ Yellow preview line appears
5. ✓ Console shows activation message

#### Test 2: Exit via Button
1. While in Connect Mode (button pressed)
2. Click button again
3. ✓ Button should unpress
4. ✓ Preview line disappears
5. ✓ Console shows exit message

#### Test 3: Exit via Q Key
1. While in Connect Mode (button pressed)
2. Press Q key
3. ✓ Button should unpress automatically
4. ✓ Mode exits
5. ✓ Returns to Select Mode

#### Test 4: Validation Failure
1. Select 0, 1, or 3+ objects
2. Click "Connect Mode" button
3. ✓ Button should unpress immediately
4. ✓ Error message in console
5. ✓ Stays in Select Mode

#### Test 5: Mode Switch
1. Enter Connect Mode (button pressed)
2. Press W (Move mode)
3. ✓ Button should unpress automatically
4. ✓ Mode changes to Move
5. ✓ Connect Mode exits

### Location in UI

```
Sidebar (right side):
├── Parts List
├── Transform Inputs
├── [Separator]
├── Connect Mode (Bolt Gun) ← NEW BUTTON
├── Validate Construct
└── Clear All
```

### Console Output

#### Successful Activation
```
=== Connect Mode ACTIVATED ===
  Target A: wooden_board_small
  Target B: wooden_board_large
  Fastener: fastener_steel_bolt
...
```

#### Validation Failure
```
Connect Mode ERROR: Requires exactly 2 items selected. Currently selected: 1
Transform mode: Select
```

#### Exit
```
Connect Mode exited
Transform mode: Select
```

## Summary

The Connect Mode feature is now controlled via a **toggle button** instead of a keyboard shortcut. This provides:

- ✓ Better discoverability
- ✓ Visual feedback (button stays pressed)
- ✓ No keyboard conflicts
- ✓ Intuitive toggle behavior
- ✓ Auto-sync with mode state

The button is located in the sidebar above the "Validate Construct" button, making it easy to find and use.
