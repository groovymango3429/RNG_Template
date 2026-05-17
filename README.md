# Roblox RNG Template

A Rojo-ready Roblox RNG template built around modular Luau services, reliable profile saving, existing Studio UI, and easy configuration.

## Quick start
1. Install [Rojo](https://rojo.space/).
2. Open the experience in Roblox Studio.
3. Keep your existing `StarterGui/YourUiPack!` hierarchy in Studio.
4. Run `rojo serve` from the repository root and connect Studio.
5. Update the placeholder IDs, assets, and balance values before publishing.

## Project layout
- `/default.project.json` - Rojo project file.
- `/src/ReplicatedStorage/Shared` - shared config, utility, and remote definitions.
- `/src/ServerScriptService/Server` - server services for data, rolling, rewards, rebirths, and purchases.
- `/src/StarterPlayer/StarterPlayerScripts` - client bootstrap and UI logic.
- `/src/ServerStorage/Assets` - place reward models, pets, and roll effects here.
- `/src/Workspace`, `/src/Lighting`, `/src/SoundService`, `/src/TextChatService`, `/src/Teams` - service folders ready for Studio content.

## Customization guide
### Where to change roll chances
Edit `src/ReplicatedStorage/Shared/Config/RollConfig.lua`.
- Each entry uses a `Weight` value for weighted rolling.
- Higher weights make outcomes more common.
- `DisplayOdds` is the text shown to players.
- `Zone` decides which Discover card and unlock requirements apply.

### Where to add new models
Add models to `src/ServerStorage/Assets/RewardModels`.
- Model names must match `ModelName` in `RollConfig.lua` exactly.
- If you want client-visible preview assets, mirror lightweight display assets under `ReplicatedStorage` later.

### Where to add gamepass IDs
Edit `src/ReplicatedStorage/Shared/Config/Gamepasses.lua`.
- Replace each placeholder `Id = 0` with the correct Roblox gamepass ID.
- The server checks ownership and applies multipliers automatically.

### Where to add developer product IDs
Edit `src/ReplicatedStorage/Shared/Config/DeveloperProducts.lua`.
- Replace each placeholder `Id = 0` with your developer product ID.
- Rewards are granted through `ProcessReceipt`.

### Where to change UI text
Use your existing Studio UI for visual text defaults, then adjust script-driven text in:
- `src/ReplicatedStorage/Shared/Config/UIConfig.lua`
- `src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.lua`

### Where to change reward tables
Edit `src/ReplicatedStorage/Shared/Config/Rewards.lua`.
- Daily rewards live in `Rewards.Daily`.
- Playtime rewards live in `Rewards.Playtime`.
- Starter rewards can be added through reward application logic if desired.

### Where to change animations, sounds, and icons
Edit:
- `src/ReplicatedStorage/Shared/Config/AnimationConfig.lua`
- `src/ReplicatedStorage/Shared/Config/RollConfig.lua`
- `src/ReplicatedStorage/Assets/PreloadManifest.lua`
- `src/ServerStorage/Assets/RollEffects`
- `src/SoundService/README.md`

### Where to add new rarities or new roll outcomes
- Add rarities in `src/ReplicatedStorage/Shared/Config/Rarities.lua`.
- Add outcomes in `src/ReplicatedStorage/Shared/Config/RollConfig.lua`.
- Add matching index slots in Studio if you want more visible entries than the current template provides.

### Where to configure data saving settings
Edit `src/ReplicatedStorage/Shared/Config/DataConfig.lua`.
- Store name
- retry counts
- retry delays
- autosave interval
- session lock timeout

## Asset and naming conventions
- `RollConfig.ModelName` must match the model stored in `ServerStorage/Assets/RewardModels`.
- `RollConfig.Id` should stay unique and stable once you ship.
- Use the same key in configs, saved inventory, and UI mapping to avoid broken references.
- Placeholder icons, sounds, and animation IDs are expected to be replaced with your own asset IDs.

## Existing UI reference guide
The scripts do **not** create any UI. They only reference your existing hierarchy under:
- `Players.LocalPlayer.PlayerGui:WaitForChild("YourUiPack!")`

Top-level objects expected under `YourUiPack!`:
- `DailyRewards` - panel for the 7-day login reward track.
- `PlaytimeRewards` - panel for timed reward claims.
- `Rewards` - roll result panel plus monetization shortcut button.
- `Discover` - progression cards for zone unlock progress.
- `Index` - collection book showing discovered outcomes.
- `Rebirth` - rebirth progress and purchase shortcuts.
- `LeftSide` - main navigation buttons.
- `LeftBottomBar` - rolling and quick action buttons.
- `InvUI` - inventory/equip panel (resolved from `PlayerGui.InvUI`).

### Exact paths used by the client scripts
#### Required root panel access
- `Players.LocalPlayer.PlayerGui:WaitForChild("YourUiPack!")`
- `Players.LocalPlayer.PlayerGui:WaitForChild("Rolling")`
- `ui:WaitForChild("DailyRewards")`
- `ui:WaitForChild("Index")`
- `ui:WaitForChild("Rebirth")`
- `ui:WaitForChild("Rewards")`
- `ui:WaitForChild("Discover")`
- `ui:WaitForChild("PlaytimeRewards")`
- `ui:WaitForChild("LeftSide")`
- `ui:WaitForChild("LeftBottomBar")`

#### Navigation buttons expected
- `YourUiPack!.LeftSide.ReadyBtn` - opens `DailyRewards`.
- `YourUiPack!.LeftSide.ShopBtn` - opens `ItemShopUI` inside `PlayerGui.Shop`.
- `YourUiPack!.LeftSide.BackpackBtn` - opens `PlayerGui.InvUI`.
- `YourUiPack!.LeftSide.IndexBtn` - opens `Index`.
- `YourUiPack!.LeftSide.RebirthBtn` - opens `Rebirth`.
- `YourUiPack!.LeftBottomBar.IconBtn01` - performs a roll.
- `YourUiPack!.LeftBottomBar.IconBtn02` - toggles auto-roll.
- `YourUiPack!.LeftBottomBar.IconBtn03` - opens `Discover`.
- `YourUiPack!.LeftBottomBar.IconBtn04` - prompts the configured luck developer product.
- `YourUiPack!.LeftBottomBar.IconBtn05` - opens `PlaytimeRewards`.

#### Other UI objects used
- `Rolling.Main.ImageLabel` - roll result pet image used by the roulette animation.
- `Rolling.Main.PetName` - roll result pet name text.
- `Rolling.Main.Rarity` - roll result odds text.
- `Rolling.Main.Rarity.UIStroke` - dynamically recolored to the rolled pet rarity color.
- `DailyRewards.Header.CloseBtn` - closes the daily reward panel.
- `DailyRewards.Content.Slot01` through `Slot07` - claimable daily reward buttons.
- `PlaytimeRewards.Header.CloseBtn` - closes the playtime panel.
- `PlaytimeRewards.Content.Main.Rewards` - contains the timed reward buttons used in order.
- `Rewards.Header.CloseBtn` - closes the roll result panel.
- `Rewards.Content.WatchBtn` - prompts the configured ad/luck developer product.
- `Discover.Normal`, `Discover.Candy`, `Discover.Gold`, `Discover.Diamond`, `Discover.Rainbow`, `Discover.Vulcan` - progression cards updated by scripts.
- `Index.Main.Header.CloseBtn` - closes the index panel.
- `Index.Main.Content` - holds prebuilt item slots; scripts update existing buttons in order.
- `Rebirth.Header.CloseBtn` - closes the rebirth panel.
- `Rebirth.Content.Btns.RebirthBtn` - attempts a rebirth.
- `Rebirth.Content.Btns.SkipRebirthBtn` - prompts the configured skip rebirth developer product.
- `InvUI.HolderFrame.Inv.Header.CloseBtn` - closes inventory.
- `InvUI.HolderFrame.Inv.Content.Slots1` - receives runtime inventory slots cloned from `Slot1`.
- `InvUI.HolderFrame.Frame.ReadyButton` - equips the currently selected inventory item.
- `InvUI.HolderFrame.Inv.EquipBest.EquipBest` - equips the best owned inventory item.

If any of these objects are missing, the scripts warn clearly and skip that behavior instead of creating replacements.

## Notes
- This template uses a Trove-style cleanup helper for connections and temporary resources.
- Fallback profiles allow play even when DataStore loading fails, but fallback sessions do not save.
- Review all placeholder IDs before publishing.
