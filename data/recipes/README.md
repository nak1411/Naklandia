# Crafting Recipes - JSON Definition System

This directory contains JSON files that define all crafting recipes in the game. Recipes are automatically loaded by the `CraftingManager` when the game starts.

## File Structure

Recipes are organized by category:
- `basic_crafting.json` - Basic crafting recipes

## Recipe Definition Format

Each recipe is defined with the following structure:

```json
{
  "recipe_id": {
    "output_item_id": "item_id_from_database",
    "output_quantity": 1,
    "is_always_available": true,
    "is_discovered": false,
    "required_materials": [
      {
        "material_id": "resource_item_id",
        "quantity": 1,
        "consumed": true
      }
    ]
  }
}
```

### Required Fields

- **output_item_id** (String): The item ID from ItemDatabase that this recipe produces
  - Must match an item_id in one of the item JSON files

### Optional Fields

- **output_quantity** (Int): How many items are produced (default: 1)
- **is_always_available** (Boolean): Recipe available from start (default: false)
- **is_discovered** (Boolean): Recipe already discovered (default: false)
- **required_materials** (Array): List of materials needed

### Material Definition

Each material in `required_materials` has:

- **material_id** (String): Item ID from ItemDatabase (required)
- **quantity** (Int): How many needed (default: 1)
- **consumed** (Boolean): Whether material is consumed (default: true)

## Auto-Population from ItemDatabase

The recipe system automatically pulls display data from ItemDatabase:

- ✅ `recipe_name` - Comes from output item's name
- ✅ `description` - Comes from output item's description
- ✅ `icon_path` - Comes from output item's icon
- ✅ `output_item_type` - Comes from output item's type
- ✅ `material_name` - Comes from each material's name

This means you **only** need to specify IDs and quantities - all display data stays in sync!

## Example: Simple Recipe

```json
{
  "recipe_wrench": {
    "output_item_id": "tool_wrench",
    "output_quantity": 1,
    "is_always_available": true,
    "required_materials": [
      {
        "material_id": "resource_iron_ingot",
        "quantity": 1,
        "consumed": true
      }
    ]
  }
}
```

This creates a recipe that:
- Produces 1 Wrench (name/description from `tool_wrench` in items)
- Requires 1 Iron Ingot (name from `resource_iron_ingot` in items)
- Available from game start
- Consumes the iron ingot when crafted

## Example: Complex Recipe

```json
{
  "recipe_advanced_tool": {
    "output_item_id": "tool_advanced_wrench",
    "output_quantity": 1,
    "is_always_available": false,
    "required_materials": [
      {
        "material_id": "tool_wrench",
        "quantity": 1,
        "consumed": false
      },
      {
        "material_id": "resource_steel_round_bar",
        "quantity": 2,
        "consumed": true
      },
      {
        "material_id": "resource_copper_ingot",
        "quantity": 1,
        "consumed": true
      }
    ]
  }
}
```

This recipe:
- Produces 1 Advanced Wrench
- Needs to be discovered (not always available)
- Requires a basic wrench (not consumed - acts as a tool)
- Requires 2 steel bars and 1 copper ingot (consumed)

## Adding New Recipes

1. Open the appropriate JSON file (or create a new category file)
2. Add your recipe with a unique `recipe_id` as the key
3. Set the `output_item_id` (must exist in ItemDatabase)
4. Add required materials with their IDs and quantities
5. Save the file
6. Restart the game or press **F5** to hot-reload

## Hot Reloading

**Press F5 in-game** to reload recipes without restarting!

When you press F5:
- Recipe JSON files are reloaded
- Recipes refresh their data from ItemDatabase
- Crafting windows update automatically

## Validation

The CraftingManager performs validation:
- Recipe must have `output_item_id`
- Output item must exist in ItemDatabase
- Material items should exist in ItemDatabase (warnings shown)
- JSON must be valid format

Errors and warnings are logged to console on startup.

## Fallback System

If JSON loading fails or is disabled (`ENABLE_JSON_LOADING = false` in CraftingManager), the system falls back to hardcoded recipes in `CraftingManager._create_basic_recipes()`.
