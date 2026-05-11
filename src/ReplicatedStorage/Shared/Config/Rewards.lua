--!strict
return {
    Daily = {
        { Type = "Coins", Amount = 50 },
        { Type = "Coins", Amount = 100 },
        { Type = "Gems", Amount = 10 },
        { Type = "Coins", Amount = 250 },
        { Type = "LuckBoost", Amount = 0.5, Duration = 900 },
        { Type = "Gems", Amount = 25 },
        { Type = "Item", ItemId = "PrismPhoenix", Amount = 1 },
    },
    Playtime = {
        { RequiredSeconds = 300, Reward = { Type = "Coins", Amount = 150 } },
        { RequiredSeconds = 900, Reward = { Type = "Gems", Amount = 15 } },
        { RequiredSeconds = 1800, Reward = { Type = "LuckBoost", Amount = 0.35, Duration = 1200 } },
        { RequiredSeconds = 2700, Reward = { Type = "Coins", Amount = 600 } },
        { RequiredSeconds = 3600, Reward = { Type = "Item", ItemId = "AuroraManta", Amount = 1 } },
    },
}
