# Item Database - JSON Definition System

This directory contains JSON files that define all items in the game. Items are automatically loaded by the `ItemDatabase` singleton when the game starts.

## File Structure

Items are organized by category:
- `tools.json` - Tools and equipment
- `ammunition.json` - Ammunition types
- `resources.json` - Raw materials and resources
- `modules.json` - Ship/vehicle modules
- `blueprints.json` - Crafting blueprints
- `miscellaneous.json` - Other items

## Item Definition Format

Each item is defined with the following structure:

```json
{
  "item_id": {
    "name": "Display Name",
    "description": "Item description text",
    "type": "ITEM_TYPE",
    "volume": 0.1,
    "mass": 0.1,
    "value": 100.0,
    "icon_path": "res://path/to/icon.png",
    "max_stack_size": 999999,
    "model_path": "res://path/to/model.glb",
    "metadata": {
      "custom_key": "custom_value"
    }
  }
}
```

### Required Fields

- **name** (String): Display name shown in UI
- **type** (String): Item type - one of:
  - `TOOL`
  - `WEAPON`
  - `ARMOR`
  - `AMMUNITION`
  - `RESOURCE`
  - `MODULE`
  - `BLUEPRINT`
  - `IMPLANT`
  - `CONSUMABLE`
  - `MISCELLANEOUS`

### Optional Fields

- **description** (String): Item description (default: "")
- **volume** (Float): Item volume in cubic meters (default: 0.1)
- **mass** (Float): Item mass in kg (default: 0.1)
- **value** (Float): Base value/price (default: 0.0)
- **icon_path** (String): Path to icon texture (default: "")
- **max_stack_size** (Int): Maximum stack size (default: 999999)
- **model_path** (String): Path to 3D model file (default: "")

### Metadata

The `metadata` object contains custom properties specific to the item type:

#### Equipment Items (Tools, Weapons, Armor)
```json
"metadata": {
  "is_equippable": true,
  "equipment_category": "tool",
  "equipment_socket": "hand_tool"
}
```

Equipment categories:
- **weapon** - Primary/secondary weapon slots
- **tool** - Hand tool slots
- **head**, **chest**, **legs**, **hands**, **feet** - Armor slots
- **accessory** - Accessory/implant slots

#### Other Metadata Examples
```json
"metadata": {
  "damage": 50,
  "fire_rate": 2.5,
  "ammo_type": "hybrid_charges"
}
```

## Adding New Items

1. Open the appropriate JSON file (or create a new one)
2. Add your item definition with a unique `item_id` as the key
3. Fill in required and optional fields
4. Add any custom metadata needed for game systems
5. Save the file - changes will be loaded on next game start

## Example: Adding a New Tool

```json
{
  "tool_hammer": {
    "name": "Hammer",
    "description": "A heavy hammer for construction work.",
    "type": "TOOL",
    "volume": 0.08,
    "mass": 0.5,
    "value": 75.0,
    "icon_path": "res://assets/textures/ui/icons/hammer.png",
    "model_path": "res://assets/models/tools/hammer.glb",
    "metadata": {
      "is_equippable": true,
      "equipment_category": "tool",
      "equipment_socket": "hand_tool"
    }
  }
}
```

## Validation

The ItemDatabase performs the following validations:
- File must be valid JSON
- Root must be a dictionary/object
- Each item must have `name` and `type` fields
- Item type must be valid
- Numeric values must be valid numbers

Errors and warnings are logged to the console on startup.

## Fallback System

If JSON loading fails or is disabled, the system falls back to hardcoded item definitions in `ItemDatabase.gd`. You can toggle this with the `ENABLE_JSON_LOADING` constant.

## Hot Reloading

**Press F5 in-game** to hot-reload all items and recipes!

When you press F5:
1. JSON files are reloaded from disk
2. All existing items in inventories/equipment are updated
3. All crafting recipes are refreshed
4. All UI windows are refreshed to show changes

This means you can:
- Edit item names, descriptions, stats
- See changes on items you already own
- Update crafting recipes automatically
- No need to restart the game or drop/pickup items
