# Workbench Window - Modular Architecture

This folder contains the refactored, modular version of the WorkbenchWindow system.

## Structure

The original monolithic `WorkbenchWindow.gd` (3,441 lines) has been split into 7 specialized modules:

### Core Modules

1. **WorkbenchUndoRedo.gd** (~200 lines)
   - Manages undo/redo operations
   - Tracks transform history (move, rotate, scale)
   - Max 10 operations in history
   - Emits signals for UI updates

2. **WorkbenchCameraController.gd** (~250 lines)
   - Handles all camera movement (orbit, pan, zoom)
   - Blender/Maya-style controls (Alt + Mouse)
   - Frame selection functionality (F key)
   - Automatic floor collision prevention

3. **WorkbenchSelectionManager.gd** (~450 lines)
   - Single/multi-select with raycasting
   - Box selection with rectangle drawing
   - Cluster selection for bonded items
   - Delete operations with fastener cleanup

4. **WorkbenchGizmoController.gd** (~800 lines)
   - Transform gizmo interactions (move, rotate, scale)
   - Precise drag operations
   - Snap to grid and angle snapping
   - Fine control with modifier keys (Shift, Ctrl, X)
   - Transform statistics display

5. **WorkbenchConnectMode.gd** (~400 lines)
   - Fastener/bolt gun system
   - Raycast detection for intersection points
   - Joint creation and visual helpers
   - Fire line visual feedback

6. **WorkbenchUIManager.gd** (~500 lines)
   - All UI panels and controls
   - Part list and category filtering
   - Transform input spinboxes
   - Viewport settings dialog
   - Fastener selection dialog

### Main Orchestrator

7. **WorkbenchWindow_Refactored.gd** (~700 lines)
   - Main window class that coordinates all modules
   - Handles input events and delegates to managers
   - Signal routing between modules
   - Scene tree node references

## Migration Guide

### To Use the Refactored Version:

1. **Backup the original:**
   ```bash
   cp ../WorkbenchWindow.gd ../WorkbenchWindow_OLD.gd
   ```

2. **Option A - Test first (Recommended):**
   - Keep both versions
   - Test `WorkbenchWindow_Refactored.gd` thoroughly
   - Once verified, rename to `WorkbenchWindow.gd`

3. **Option B - Direct replacement:**
   - Replace `../WorkbenchWindow.gd` with `WorkbenchWindow_Refactored.gd`
   - Rename to `WorkbenchWindow.gd`

### Important Notes:

- All 7 files must be in the same directory for class references to work
- Godot will auto-detect the `class_name` declarations
- No changes needed to scene files (`.tscn`)
- All original functionality is preserved

## Benefits

### Maintainability
- Each module handles a single responsibility
- Easier to locate and fix bugs
- Clear separation of concerns

### Testability
- Each module can be tested independently
- Mocking is simpler for unit tests
- Isolated debugging

### Reusability
- Camera controller can be used in other 3D editors
- Selection manager is reusable for other tools
- Gizmo controller is project-agnostic

### Scalability
- Easy to extend individual systems
- Add new features without affecting other modules
- Reduced merge conflicts in team development

## Architecture Diagram

```
WorkbenchWindow_Refactored.gd (Main Orchestrator)
├── WorkbenchCameraController.gd
│   └── Handles: Camera movement, orbit, pan, zoom, framing
│
├── WorkbenchSelectionManager.gd
│   └── Handles: Selection, box select, cluster selection, delete
│
├── WorkbenchGizmoController.gd
│   └── Handles: Gizmo transforms, drag operations, snapping
│
├── WorkbenchConnectMode.gd
│   └── Handles: Fastener placement, bolt gun, joint creation
│
├── WorkbenchUndoRedo.gd
│   └── Handles: Undo/redo operations, history management
│
└── WorkbenchUIManager.gd
    └── Handles: UI panels, buttons, dialogs, part list
```

## Signal Flow

Each module emits signals that the main orchestrator listens to:

- **SelectionManager** → `selection_changed(items)` → Main → Updates gizmo & UI
- **GizmoController** → `transform_updated(op, val, axis)` → Main → Updates stats label
- **CameraController** → `camera_moved(pos, rot)` → Main → (optional listeners)
- **ConnectMode** → `fastener_placed(fastener, a, b)` → Main → Updates UI
- **UndoRedo** → `history_changed(undo, redo)` → Main → Updates menu states

## File Sizes

| File | Lines | Purpose |
|------|-------|---------|
| WorkbenchUndoRedo.gd | ~200 | Undo/redo system |
| WorkbenchCameraController.gd | ~250 | Camera controls |
| WorkbenchSelectionManager.gd | ~450 | Selection system |
| WorkbenchUIManager.gd | ~500 | UI management |
| WorkbenchConnectMode.gd | ~400 | Fastener system |
| WorkbenchGizmoController.gd | ~800 | Transform gizmos |
| WorkbenchWindow_Refactored.gd | ~700 | Main orchestrator |
| **TOTAL** | **~3,300** | (vs 3,441 original) |

## Testing Checklist

After migration, verify:

- [ ] Camera controls (Alt + LMB/MMB/RMB)
- [ ] Object selection (click, Shift+click, box select)
- [ ] Transform gizmos (Q/W/E/R modes)
- [ ] Gizmo operations (move, rotate, scale)
- [ ] Snap to grid (X key)
- [ ] Fine mode (Shift during drag)
- [ ] Snap angles (Ctrl during drag)
- [ ] Connect mode / bolt gun
- [ ] Fastener placement
- [ ] Undo/redo (Ctrl+Z, Ctrl+Shift+Z)
- [ ] Part spawning
- [ ] Context menus (right-click)
- [ ] Transform input spinboxes
- [ ] Viewport settings dialog
- [ ] Delete objects (Delete key)
- [ ] Duplicate objects (Ctrl+D)
- [ ] Select all (Ctrl+A)
- [ ] Frame selection (F key)

## Future Enhancements

Potential improvements now that the code is modular:

1. **Add more transform tools** - Just extend GizmoController
2. **Multiple camera presets** - Add to CameraController
3. **Selection filters** - Extend SelectionManager
4. **Custom fastener types** - Expand ConnectMode
5. **Advanced undo/redo** - Enhance UndoRedo with branching

## Maintenance

When adding features:

1. Identify which module the feature belongs to
2. Add functionality to that specific module
3. Expose via signals if main window needs to react
4. Update this README with changes

## Support

If you encounter issues:

1. Check which module the issue relates to
2. Debug that specific module in isolation
3. Verify signal connections in main window
4. Check console for print statements (each module logs activity)

---

**Last Updated:** November 4, 2024
**Refactored By:** Claude (Anthropic AI)
**Original Author:** Justin (Naklandia Project)
