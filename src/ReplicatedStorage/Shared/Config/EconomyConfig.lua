--!strict
return {
    StartingStats = {
        Coins = 0,
        Gems = 0,
        Rolls = 0,
        Rebirths = 0,
        CombatPower = 1,
        SkillPoints = 0,
    },
    Rebirth = {
        SkillPointsPerRebirth = 1,
        ResetCoins = true,
        ResetRolls = true,
        ResetCombatPower = false,
    },
    Automation = {
        BaseAutoRollInterval = 1.5,
        MinimumAutoRollInterval = 0.3,
    },
    RewardScaling = {
        BaseCoinMultiplier = 1,
        BaseGemMultiplier = 1,
    },
}
