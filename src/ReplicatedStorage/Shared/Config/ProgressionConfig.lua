--!strict
return {
    BaseLuckMultiplier = 1,
    RebirthLuckPerLevel = 1.89,
    DiscoverZones = {
        { Id = "Normal", RequiredRolls = 0, RequiredRebirths = 0 },
        { Id = "Candy", RequiredRolls = 15, RequiredRebirths = 0 },
        { Id = "Gold", RequiredRolls = 40, RequiredRebirths = 0 },
        { Id = "Diamond", RequiredRolls = 85, RequiredRebirths = 1 },
        { Id = "Rainbow", RequiredRolls = 150, RequiredRebirths = 2 },
        { Id = "Vulcan", RequiredRolls = 225, RequiredRebirths = 3 },
    },
    RebirthStages = {
        { RequiredRolls = 25, BonusGems = 10 },
        { RequiredRolls = 75, BonusGems = 25 },
        { RequiredRolls = 150, BonusGems = 40 },
        { RequiredRolls = 275, BonusGems = 60 },
        { RequiredRolls = 450, BonusGems = 100 },
    },
}
