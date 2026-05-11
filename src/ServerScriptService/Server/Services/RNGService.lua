--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")

local DataConfig = require(Config:WaitForChild("DataConfig"))
local ProgressionConfig = require(Config:WaitForChild("ProgressionConfig"))
local Rarities = require(Config:WaitForChild("Rarities"))
local RollConfig = require(Config:WaitForChild("RollConfig"))
local WeightedRandom = require(Util:WaitForChild("WeightedRandom"))

local RNGService = {
    _lastRollTimestamps = {} :: {[Player]: number},
}

local function sortByRarityThenName(a, b)
    local leftRarity = Rarities[a.Rarity]
    local rightRarity = Rarities[b.Rarity]
    if leftRarity.Order == rightRarity.Order then
        return a.DisplayName < b.DisplayName
    end
    return leftRarity.Order < rightRarity.Order
end

function RNGService:Init(dataService, monetizationService)
    self._dataService = dataService
    self._monetizationService = monetizationService
    self._random = Random.new()
end

function RNGService:GetClientRollTable()
    local items = table.clone(RollConfig)
    table.sort(items, sortByRarityThenName)
    return items
end

function RNGService:GetLuckMultiplier(player)
    local profile = self._dataService:GetProfile(player)
    if not profile then
        return ProgressionConfig.BaseLuckMultiplier
    end

    local boost = profile.Boosts.Luck or { Amount = 0, ExpiresAt = 0 }
    local activeBoost = (boost.ExpiresAt or 0) > os.time() and (boost.Amount or 0) or 0
    local rebirthBonus = (profile.Stats.Rebirths or 0) * ProgressionConfig.RebirthLuckPerLevel
    local monetizationBonus = self._monetizationService:GetLuckModifier(player)

    return ProgressionConfig.BaseLuckMultiplier + rebirthBonus + monetizationBonus + activeBoost
end

function RNGService:GetDiscoverState(player)
    local profile = self._dataService:GetProfile(player)
    if not profile then
        return nil
    end

    local result = {}
    for _, zone in ipairs(ProgressionConfig.DiscoverZones) do
        local unlocked = (profile.Stats.Rolls or 0) >= zone.RequiredRolls and (profile.Stats.Rebirths or 0) >= zone.RequiredRebirths
        local rollsProgress = zone.RequiredRolls == 0 and 1 or math.clamp((profile.Stats.Rolls or 0) / zone.RequiredRolls, 0, 1)
        local rebirthProgress = zone.RequiredRebirths == 0 and 1 or math.clamp((profile.Stats.Rebirths or 0) / zone.RequiredRebirths, 0, 1)
        result[zone.Id] = {
            Unlocked = unlocked,
            RequiredRolls = zone.RequiredRolls,
            RequiredRebirths = zone.RequiredRebirths,
            Progress = math.min(rollsProgress, rebirthProgress),
        }
    end
    return result
end

function RNGService:_getEligibleItems(player)
    local discoverState = self:GetDiscoverState(player)
    local eligible = {}
    for _, item in ipairs(RollConfig) do
        local zoneState = discoverState[item.Zone]
        if zoneState and zoneState.Unlocked then
            table.insert(eligible, item)
        end
    end
    return eligible
end

function RNGService:_resolveWeight(item, luckMultiplier)
    local rarity = Rarities[item.Rarity]
    local influence = rarity and rarity.LuckInfluence or 0
    return math.max(0.05, item.Weight * (1 + ((luckMultiplier - 1) * influence)))
end

function RNGService:Roll(player)
    local profile = self._dataService:GetProfile(player)
    if not profile then
        return nil, "No profile loaded."
    end

    local now = os.clock()
    local lastRoll = self._lastRollTimestamps[player] or 0
    if now - lastRoll < DataConfig.RollCooldownSeconds then
        return nil, "Roll is on cooldown."
    end

    local eligibleItems = self:_getEligibleItems(player)
    local luckMultiplier = self:GetLuckMultiplier(player)
    local chosenItem, message = WeightedRandom.Choose(eligibleItems, function(item)
        return self:_resolveWeight(item, luckMultiplier)
    end, self._random)

    if not chosenItem then
        return nil, message or "No items are configured for the current unlock state."
    end

    self._lastRollTimestamps[player] = now
    self._dataService:UpdateProfile(player, function(activeProfile)
        activeProfile.Stats.Rolls = (activeProfile.Stats.Rolls or 0) + 1
        activeProfile.Stats.Coins = (activeProfile.Stats.Coins or 0) + (chosenItem.RewardCoins or 0)
        activeProfile.Inventory[chosenItem.Id] = (activeProfile.Inventory[chosenItem.Id] or 0) + 1
        activeProfile.Index[chosenItem.Id] = true
    end)

    return {
        Item = chosenItem,
        LuckMultiplier = luckMultiplier,
        InventoryCount = (profile.Inventory[chosenItem.Id] or 0),
    }
end

return RNGService
