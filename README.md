# Roblox Generic Progression Template (Rojo)

A reskinnable Roblox template built on modular client/server/shared systems for collecting, upgrading, fighting/automation loops, rebirth progression, and monetization hooks.

This template **extends the current RNG system** (rolls, inventory, rewards, rebirth, saving) and adds a data-driven skill tree, economy modifiers, and clearer asset/config structure.

---

## 1) Rojo project setup

1. Install [Rojo](https://rojo.space/).
2. Open your place in Roblox Studio.
3. Keep your existing `StarterGui/YourUiPack!` hierarchy.
4. Run `rojo serve` from repository root.
5. Connect Studio to Rojo.
6. Replace placeholder IDs and balancing values before publishing.

`default.project.json` already maps Roblox services to `src/*` folders.

---

## 2) Folder structure

```text
src/
  ReplicatedStorage/
    Shared/
      Config/
        AnimationConfig.lua
        AssetConfig.lua
        DataConfig.lua
        DeveloperProducts.lua
        EconomyConfig.lua
        Gamepasses.lua
        ProgressionConfig.lua
        Rarities.lua
        Rewards.lua
        RollConfig.lua
        SkillTreeConfig.lua
        UIConfig.lua
      Systems/
        SkillTree.lua
      Util/
        FormatUtil.lua
        SafeWait.lua
        TableUtil.lua
        Trove.lua
        WeightedRandom.lua
      RemoteDefinitions.lua

  ServerScriptService/
    ServerBootstrap.server.lua
    Server/
      Services/
        AssetService.lua
        DataService.lua
        MonetizationService.lua
        RebirthService.lua
        RemoteService.lua
        RewardApplier.lua
        RewardService.lua
        RNGService.lua
        SkillTreeService.lua

  StarterPlayer/
    StarterPlayerScripts/
      ClientBootstrap.client.lua
      Client/
        Controllers/
          NotificationController.lua
          UIController.lua

  ServerStorage/
    Assets/
      RewardModels/
      Pets/
      Enemies/
      Items/
      RollEffects/
      Icons/
      Sounds/
      Animations/
```

---

## 3) Core systems included

- Core progression loop (roll -> collect -> upgrade -> rebirth)
- Currency system (coins, gems, skill points)
- Collection/inventory + index tracking
- Reward handling (daily, playtime, monetization, skill tree)
- Data-driven skill tree with dependencies and GUI references
- Unlock requirements/dependencies for progression and skill nodes
- Rebirth/reset system
- Save/load with session lock + fallback mode
- Gamepass and developer product hooks
- Notification and feedback hooks
- Data-driven rarity and reward tables
- Automation loop (auto-roll), plus combat-power stat hook for combat templates
- Memory cleanup helpers (`Trove`) and safe missing-reference behavior (`SafeWait`)

---

## 4) Beginner setup checklist (what to edit)

### A) Add models and assets

- Reward outcome models: `src/ServerStorage/Assets/RewardModels`
- Pet models: `src/ServerStorage/Assets/Pets`
- Enemy models: `src/ServerStorage/Assets/Enemies`
- Item models: `src/ServerStorage/Assets/Items`
- Roll effects: `src/ServerStorage/Assets/RollEffects`
- Optional icon assets: `src/ServerStorage/Assets/Icons`
- Optional sounds: `src/ServerStorage/Assets/Sounds`
- Optional animations: `src/ServerStorage/Assets/Animations`

Asset folder names are configured in `AssetConfig.lua`.

### B) Add/modify collectible outcomes

Edit `src/ReplicatedStorage/Shared/Config/RollConfig.lua`.

Each entry should keep stable keys:
- `Id` (unique save key; do not change after release)
- `DisplayName` (UI name)
- `Rarity` (must exist in `Rarities.lua`)
- `Weight` (roll weighting)
- `Zone` (must exist in `ProgressionConfig.lua`)
- `ModelName` (must match a model in `Assets/RewardModels`)
- `RewardCoins` (base coin reward)

### C) Set progression/economy values

- Discover/rebirth requirements: `ProgressionConfig.lua`
- Rebirth reset behavior + skill points + automation defaults: `EconomyConfig.lua`
- DataStore retry/autosave/session-lock settings: `DataConfig.lua`

### D) Edit reward tables

- Daily and playtime rewards: `Rewards.lua`
- Reward formats are processed in `RewardApplier.lua`

### E) Set monetization IDs

- Gamepasses and effects: `Gamepasses.lua`
- Developer products and rewards: `DeveloperProducts.lua`

### F) Add skill tree nodes and costs

- Node definitions: `SkillTreeConfig.lua`
- Skill tree logic/evaluation: `Shared/Systems/SkillTree.lua`
- Server purchase/save/state flow: `SkillTreeService.lua`

### G) Connect skill tree to existing GUI

For each node in `SkillTreeConfig.lua`, set:
- `Gui.ButtonPath` to the existing button path in `YourUiPack!`
- Optional detail label paths:
  - `Gui.NamePath`
  - `Gui.DescriptionPath`
  - `Gui.CostPath`
  - `Gui.StatusPath`

The scripts **only reference existing objects** and do not create UI.

### H) Adjust UI path mapping

Edit `UIConfig.lua` to match your exact `YourUiPack!` hierarchy.

---

## 5) Skill tree data model

Each node in `SkillTreeConfig.lua` supports:
- `Id` (unique string id)
- `Name`
- `Description`
- `Cost` (`Currency`, `Amount`)
- `UnlockRequirements` (rolls/rebirth/items)
- `ParentDependencies` (required node ids)
- `Rewards` (what is granted on unlock)
- `Category` (branch name)
- `Gui` paths for existing UI references

Current supported reward types include:
- `Coins`, `Gems`, `SkillPoints`, `Item`, `LuckBoost`
- `CoinMultiplier`, `GemMultiplier`, `LuckBonus`
- `AutoRollInterval`, `CombatPower`, `UnlockZone`, `AutoRoll`

Unlocked nodes are saved per player in profile data (`SkillTree.UnlockedNodes`).

---

## 6) Existing UI references (no UI creation in code)

Root expected path:
- `Players.LocalPlayer.PlayerGui.YourUiPack!`

Already-used panels/buttons:
- `DailyRewards`, `PlaytimeRewards`, `Rewards`, `Discover`, `Index`, `Rebirth`, `LeftSide`, `LeftBottomBar`

Skill tree panel expected (optional but recommended for full template):
- `YourUiPack!.SkillTree`
- Close button path default: `SkillTree.Header.CloseBtn`
- Navigation button path default: `LeftSide.SkillTreeBtn`
- Node button paths are configured per node in `SkillTreeConfig.lua`

If configured paths are missing, scripts warn and skip behavior safely.

---

## 7) Naming conventions (important)

- `RollConfig.Id` must stay stable forever after live release.
- `RollConfig.ModelName` must match ServerStorage model names exactly.
- `Rarity` values in roll entries must match keys in `Rarities.lua`.
- `Zone` values in roll entries must match `ProgressionConfig.DiscoverZones[].Id`.
- Skill tree `ParentDependencies` values must match other skill node `Id` values.
- Use consistent keys across config, save data, and UI binding paths.

---

## 8) Fallback + warning behavior

- Missing UI objects: handled by `SafeWait` with warnings.
- Missing asset folders/models: warned by `AssetService`.
- Missing reward fallback model: warning emitted; game avoids hard crash.
- DataStore failure/session lock: fallback profile mode allows play, but does not save.

---

## 9) Reskin workflow (pets/enemies/items themes)

1. Replace models in `ServerStorage/Assets/*` folders.
2. Rename and rebalance entries in `RollConfig.lua`.
3. Update rarity colors/order in `Rarities.lua`.
4. Update progression pacing in `ProgressionConfig.lua` and `EconomyConfig.lua`.
5. Update skill tree branches/nodes in `SkillTreeConfig.lua`.
6. Remap UI object paths in `UIConfig.lua` and node `Gui` paths.
7. Replace gamepass/product IDs in config files.

No code rewrite should be required for normal content expansion.
