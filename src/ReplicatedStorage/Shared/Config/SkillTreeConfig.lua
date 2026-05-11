--!strict
return {
    RootPanelPath = { "SkillTree" },
    DetailGui = {
        NamePath = { "SkillTree", "Content", "Details", "NodeName" },
        DescriptionPath = { "SkillTree", "Content", "Details", "NodeDescription" },
        CostPath = { "SkillTree", "Content", "Details", "NodeCost" },
        StatusPath = { "SkillTree", "Content", "Details", "NodeStatus" },
    },
    Branches = {
        Economy = { Label = "Economy" },
        Automation = { Label = "Automation" },
        Combat = { Label = "Combat" },
    },
    Nodes = {
        {
            Id = "eco_coin_boost_1",
            Name = "Coin Magnet I",
            Description = "Increase all coin rewards by 15%.",
            Category = "Economy",
            Cost = { Currency = "SkillPoints", Amount = 1 },
            UnlockRequirements = {
                MinimumRolls = 10,
            },
            ParentDependencies = {},
            Rewards = {
                { Type = "CoinMultiplier", Amount = 0.15 },
            },
            Gui = {
                ButtonPath = { "SkillTree", "Content", "Economy", "Node_CoinMagnet1" },
            },
        },
        {
            Id = "eco_gem_boost_1",
            Name = "Gem Cache I",
            Description = "Increase gem rewards from all systems by 10%.",
            Category = "Economy",
            Cost = { Currency = "SkillPoints", Amount = 1 },
            UnlockRequirements = {
                MinimumRebirths = 1,
            },
            ParentDependencies = {},
            Rewards = {
                { Type = "GemMultiplier", Amount = 0.1 },
            },
            Gui = {
                ButtonPath = { "SkillTree", "Content", "Economy", "Node_GemCache1" },
            },
        },
        {
            Id = "auto_efficiency_1",
            Name = "Automation Relay",
            Description = "Reduce auto roll interval by 0.2 seconds.",
            Category = "Automation",
            Cost = { Currency = "SkillPoints", Amount = 2 },
            UnlockRequirements = {
                MinimumRebirths = 1,
            },
            ParentDependencies = {},
            Rewards = {
                { Type = "AutoRollInterval", Amount = 0.2 },
            },
            Gui = {
                ButtonPath = { "SkillTree", "Content", "Automation", "Node_Relay1" },
            },
        },
        {
            Id = "auto_zone_unlock",
            Name = "Explorer Permit",
            Description = "Unlock one progression zone early.",
            Category = "Automation",
            Cost = { Currency = "SkillPoints", Amount = 2 },
            UnlockRequirements = {
                MinimumRolls = 50,
            },
            ParentDependencies = { "auto_efficiency_1" },
            Rewards = {
                { Type = "UnlockZone", ZoneId = "Diamond" },
            },
            Gui = {
                ButtonPath = { "SkillTree", "Content", "Automation", "Node_ExplorerPermit" },
            },
        },
        {
            Id = "combat_power_1",
            Name = "Battle Drills",
            Description = "Increase combat/automation power by +3.",
            Category = "Combat",
            Cost = { Currency = "SkillPoints", Amount = 1 },
            UnlockRequirements = {
                MinimumRolls = 20,
            },
            ParentDependencies = {},
            Rewards = {
                { Type = "CombatPower", Amount = 3 },
            },
            Gui = {
                ButtonPath = { "SkillTree", "Content", "Combat", "Node_BattleDrills1" },
            },
        },
        {
            Id = "combat_luck_1",
            Name = "Precision Core",
            Description = "Increase global luck by +0.2.",
            Category = "Combat",
            Cost = { Currency = "SkillPoints", Amount = 2 },
            UnlockRequirements = {
                MinimumRebirths = 2,
            },
            ParentDependencies = { "combat_power_1" },
            Rewards = {
                { Type = "LuckBonus", Amount = 0.2 },
            },
            Gui = {
                ButtonPath = { "SkillTree", "Content", "Combat", "Node_PrecisionCore1" },
            },
        },
    },
}
