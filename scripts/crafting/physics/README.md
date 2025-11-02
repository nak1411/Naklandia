# Physics-Based Crafting System

A realistic, physics-driven crafting system where players build items by physically assembling components with complete freedom of placement.

## Overview

Unlike traditional recipe-based crafting, this system allows players to:
- Place parts anywhere in 3D space without snap points
- Use fasteners (screws, nails, glue) to bond parts together
- Validate constructs to determine if they function properly
- Build emergent solutions that the game analyzes for functionality

Inspired by games like *My Summer Car* and *Create mod* for Minecraft, but with full physics freedom.

---

## Phase 1: Basic Physical Item Placement ✅

**Status:** COMPLETE

### What's Implemented

#### PhysicalItem.gd
Base class for all physics-enabled craftable parts.

**Features:**
- RigidBody3D-based physics simulation
- Grabbable/releasable with physics freeze while held
- Visual highlighting when hovered/held
- Bond tracking (connections to other items)
- Cluster detection (get all connected items via BFS)
- Collision on Layer 3 (binary: 100)

**Properties:**
- `item_id`, `item_name`, `item_description` - Identification
- `item_mass` - Physical mass in kg
- `item_volume` - Volume in m³
- `is_held`, `is_bonded` - State tracking
- `bonded_items` - Array of connected PhysicalItems

**Methods:**
- `grab()` / `release()` - Pick up/drop item
- `bond_to(target)` / `unbond_from(target)` - Create/remove connections
- `get_bonded_cluster()` - Get all items in connected group
- `show_highlight(enabled)` - Visual feedback

#### ItemPlacer.gd
Player component for interacting with PhysicalItems.

**Features:**
- Raycast detection of items
- Pick up items within range
- Hold items at fixed distance from camera
- Smooth following of camera position/rotation
- Rotation controls (Q/E for Y-axis, mouse wheel for X-axis)

**Configuration:**
- `placement_distance: 2.0` - How far from camera to hold item
- `placement_smoothing: 15.0` - Follow speed
- `rotation_speed: 90.0` - Degrees/second rotation
- `max_pickup_distance: 5.0` - Max raycast range

**Controls:**
- **E** - Pick up / drop item
- **Q/E (hold)** - Rotate item left/right
- **Mouse Wheel** - Rotate forward/back

#### Test Scene
[physics_crafting_test.tscn](c:\Users\Justin\Documents\GitHub\Naklandia\scenes\crafting\physics_crafting_test.tscn)

Simple test environment with:
- Flythrough player controller (WASD + mouse look)
- 4 wooden boards to test with
- Ground plane for physics
- Instructions overlay

**How to Test:**
1. Open scene in Godot editor
2. Press F6 to run the scene
3. Use mouse to look around
4. Walk up to wooden boards
5. Press E to pick up/drop
6. Rotate with Q/E and mouse wheel

### Wooden Board Scene
[wooden_board.tscn](c:\Users\Justin\Documents\GitHub\Naklandia\scenes\crafting\wooden_board.tscn)

First physical crafting part:
- Size: 1.0m × 0.05m × 0.2m (plank shape)
- Mass: 2.0 kg
- Uses PhysicalItem script
- Simple box mesh (can be replaced with 3D model)

---

## Phase 2: Bonding System (Next)

**Status:** NOT STARTED

### Planned Features

#### Fastener Types
- **Screws** - Strong permanent bonds, requires screwdriver
- **Nails** - Quick but weaker, requires hammer
- **Glue** - Area-based bonds, requires cure time
- **Welding** - Metal-only, very strong

#### Tool Interactions
- Tools from inventory/equipment system
- Different tool animations and effects
- Skill/timing requirements for realism

#### Joint Creation
- Use Godot's `FixedJoint3D` for rigid bonds
- `PinJoint3D` for hinges (doors, lids)
- Track joint strength for degradation

#### Bond Validation
- Check proper fastener placement
- Verify material compatibility (wood/metal/plastic)
- Count fasteners in contact areas
- Spacing and penetration depth

**Deliverables:**
- `Fastener.gd` - Base class for screws/nails/glue
- `BondManager.gd` - Creates/manages joints between items
- `ToolInteraction.gd` - Handle hammer/screwdriver usage
- Fastener item scenes (screw, nail, glue)
- Updated ItemPlacer with tool mode

---

## Phase 3: Validation Engine (Future)

**Status:** NOT STARTED

### Planned Features

#### Cluster Detection
- Build graph of bonded items
- Identify discrete constructs
- Traverse connections via BFS/DFS

#### Structural Integrity
- Calculate center of mass (COM)
- Check COM is within base footprint
- Validate sufficient fasteners per joint
- Assess bond strength vs. estimated loads

#### Surface Analysis (for tables, benches, etc.)
- Detect flat planes using RANSAC/PCA
- Measure flatness deviation
- Calculate usable area
- Check height and clearance requirements

#### Validation Report
- Generate pass/fail for each check
- Grade quality (A/B/C)
- Identify specific problems with locations

**Deliverables:**
- `ConstructValidator.gd` - Main validation orchestrator
- `ClusterDetector.gd` - Connected component analysis
- `SurfaceAnalyzer.gd` - Plane fitting and area calculation
- `StabilityChecker.gd` - COM and balance checks
- Validation report data structure

---

## Phase 4: UI Feedback (Future)

**Status:** NOT STARTED

### Planned Features

#### Validation Report Overlay
- Show validation results in readable format
- Pass/fail status with color coding
- Specific measurements and requirements
- Suggestions for fixes

#### Visual Heatmaps
- Red zones - missing fasteners
- Yellow - stability warnings
- Green - validated surfaces
- Ghost outlines of detected features

#### In-World Indicators
- COM projection (yellow dot on ground)
- Detected surface highlights
- Fastener sufficiency markers
- Edge clearance zones

**Deliverables:**
- `ValidationReportUI.gd` - Report window
- `ValidationHeatmap.gd` - 3D overlay renderer
- Shader for highlighting problem areas
- Integration with existing UI system

---

## Phase 5: Integration (Future)

**Status:** NOT STARTED

### Planned Features

#### Functional Components
- `CraftingSurface` - Attach to validated tables
- `Storage` - For validated chests/containers
- `Workbench` - For validated tool benches
- Grade affects functionality (speed/quality)

#### Runtime Behavior
- Degradation over time/use
- Damage from impacts
- Auto-deregister when broken
- Repair mechanics

#### Inventory Integration
- Spawn parts from inventory
- Tools from equipment system
- Register built items as usable stations
- Disassemble to recover materials

**Deliverables:**
- Functional component scripts
- Integration with CraftingManager
- Integration with InventoryEventBus
- Degradation and repair system
- JSON schemas for part definitions

---

## Architecture

### Collision Layers
- **Layer 1 (1)** - World geometry, terrain
- **Layer 2 (2)** - Player character
- **Layer 3 (4)** - Physical crafting items

### Dependencies
- Godot 4.4+ physics engine
- Existing inventory system (future integration)
- Existing equipment system (for tools)
- UI system for validation feedback

### File Structure
```
scripts/crafting/physics/
├── PhysicalItem.gd          ✅ Base class for parts
├── ItemPlacer.gd            ✅ Player interaction
├── TestPlayerController.gd  ✅ Test scene controller
├── Fastener.gd              ⏳ Screws/nails/glue
├── BondManager.gd           ⏳ Joint creation
└── README.md                ✅ This file

scripts/crafting/validation/
├── ConstructValidator.gd    ⏳ Main validator
├── ClusterDetector.gd       ⏳ Graph traversal
├── SurfaceAnalyzer.gd       ⏳ Plane detection
└── StabilityChecker.gd      ⏳ COM calculations

scenes/crafting/
├── physics_crafting_test.tscn  ✅ Test environment
├── wooden_board.tscn           ✅ Sample part
└── [more parts]                ⏳ Screws, nails, etc.
```

---

## Testing

### Current Test Scene
**File:** `scenes/crafting/physics_crafting_test.tscn`

**Controls:**
- **Mouse** - Look around
- **WASD** - Move
- **E** - Pick up / Drop item
- **Q/E** - Rotate left/right
- **Mouse Wheel** - Rotate forward/back
- **ESC** - Toggle mouse capture

**What to Test:**
1. Item detection (boards highlight when looked at)
2. Pickup (E on highlighted board)
3. Smooth following (item follows camera)
4. Rotation (Q/E and wheel)
5. Drop (E while holding)
6. Physics (dropped items fall and collide)

### Next Phase Testing
When Phase 2 is complete:
- Test screw placement between boards
- Test bond creation with tools
- Test construct stability
- Test fastener requirements

---

## Known Limitations (Phase 1)

- No actual bonding yet (just tracking)
- No tool interactions
- No validation of constructs
- Test player controller is basic (no main game integration)
- Wooden board mesh is placeholder (box)
- No sound effects
- No particles/VFX

These will be addressed in future phases.

---

## Future Enhancements

- VR support (motion controls for tools)
- Destructible bonds (break under stress)
- Material deformation (wood splitting, metal bending)
- Temperature effects (glue curing, welding heat)
- Precision measurement tools (level, measuring tape)
- Blueprint system (save/load designs)
- Multiplayer construction collaboration

---

## Credits

System designed based on concept document: [CraftingIdea.txt](c:\Users\Justin\Desktop\CraftingIdea.txt)

Inspired by:
- *My Summer Car* - Detailed assembly mechanics
- *Create mod (Minecraft)* - Free-form validation
- *Hardspace: Shipbreaker* - Physics-based deconstruction
- *Teardown* - Physics destruction
