# ConsumeTracker

A comprehensive WoW 1.12.1 addon that combines consumable tracking with a customizable action bar. Track your consumables across inventory, bank, and mail, then add them to a quick-access bar with intelligent buff detection.

## Features

### 🎯 Consumable Tracking
- Track consumables across inventory, bank, and mail
- Categorized display (Elixirs, Flasks, Food, Potions, etc.)
- Color-coded counts (red/orange/yellow/green)
- Real-time updates when items change

### 🎮 Action Bar
- Customizable action bar for quick consumable access
- Drag-and-drop reordering
- Click to use consumables
- Visual indicators:
  - **Grayed out**: Buff already active or item on cooldown
  - **Desaturated**: Out of stock
  - **Normal**: Ready to use
- Cooldown spiral overlay
- Item count display
- Keybind support

### 🔍 Buff Detection
- Automatically detects active consumable buffs
- Grays out buttons when buff is active (prevents accidental reuse)
- Tracks cooldowns for instant-use items (potions, bandages)
- Buff replacement warnings (configurable)
- Shift+Click to override and force use

### ⚙️ Configuration
- Enable/disable buff detection
- Enable/disable buff replacement warnings
- Adjustable action bar scale (0.5x - 2.0x)
- Movable action bar (Ctrl+Drag)
- Minimap icon for easy access

## Installation

1. Download the addon
2. Extract the `ConsumeTracker` folder to your `World of Warcraft/Interface/AddOns/` directory
3. Restart WoW or type `/reload` if already in-game
4. The addon will load automatically

## Usage

### Basic Commands
- `/ct` or `/consumetracker` - Show help
- `/ct show` - Show tracker window
- `/ct hide` - Hide tracker window
- `/ct config` - Open settings
- `/ct reset` - Clear action bar

### Minimap Icon
- **Left-click**: Toggle tracker window
- **Right-click**: Open settings
- **Drag**: Move icon around minimap

### Adding Consumables
1. Click the minimap icon or type `/ct show`
2. Browse the categorized list of consumables
3. Click "Add" next to items you want on your action bar
4. Items appear on the action bar immediately

### Using the Action Bar
- **Click**: Use the consumable (if available and not grayed out)
- **Shift+Click**: Force use (bypasses buff detection and warnings)
- **Ctrl+Drag**: Move the entire action bar
- **Drag buttons**: Reorder consumables on the bar
- **Hover**: View tooltip

### Buff Detection
When you use a consumable that provides a buff:
1. The button grays out immediately on click
2. The addon verifies the buff is active
3. The button stays grayed while the buff is active
4. When the buff expires, the button returns to normal

For instant-use items (potions, bandages):
- The button grays out during the cooldown period
- Returns to normal when cooldown expires

### Buff Replacement Warnings
If you try to use a consumable that would replace an existing buff (e.g., switching between Battle Elixirs):
- A warning dialog appears showing which buff will be replaced
- Click "Yes" to confirm or "No" to cancel
- Hold Shift to bypass the warning
- Can be disabled in settings

## Tips

- Hold **Ctrl** and drag the action bar to reposition it
- Hold **Shift** and click to override buff detection
- Drag consumable buttons to reorder them
- Use `/ct config` to adjust scale and settings
- The action bar persists across sessions

## Supported Consumables

### Battle Elixirs
- Elixir of the Mongoose, Greater Agility, Brute Force, Giants, etc.

### Guardian Elixirs
- Elixir of the Sages, Greater Arcane Elixir, Superior Defense, etc.

### Flasks
- Flask of Supreme Power, Titans, Distilled Wisdom, Chromatic Resistance

### Food Buffs
- Grilled Squid, Nightfin Soup, Poached Sunscale Salmon, etc.

### Potions
- Major Healing/Mana Potions, Combat Potions, etc.

### Runes
- Demonic Rune, Dark Rune

### Bandages
- Heavy Runecloth Bandage, Runecloth Bandage, etc.

### Weapon Buffs
- Brilliant Wizard Oil, Dense Sharpening Stone, etc.

## Known Limitations

- Scrolls and stacking consumables are not tracked
- Some consumables may not have accurate buff detection if their buff name differs from the item name
- World buffs are displayed for reference but cannot be used via the addon

## Troubleshooting

**Action bar not showing:**
- Type `/ct show` or click the minimap icon
- Check that you've added items to the bar via the tracker window

**Buttons not graying out:**
- Ensure buff detection is enabled in settings (`/ct config`)
- Some consumables don't provide detectable buffs (this is normal)

**Items not appearing in tracker:**
- The addon only shows items from the database
- Custom or non-standard consumables may not be included

**Position reset after reload:**
- The position should save automatically
- If issues persist, try `/ct config` and use "Reset Bar Position"

## Credits

Created by Nicholas Knight

Inspired by:
- **ConsumesManager** by Horyoshi (logicsec)
- **ConsumeBar** by Fastbond

## Version History

### v1.0.0 (Initial Release)
- Consumable tracking across inventory, bank, and mail
- Customizable action bar with drag-drop
- Buff detection and cooldown tracking
- Buff replacement warnings
- Minimap icon
- Configuration UI
- Slash commands

## License

This addon is free to use and modify for personal use.
