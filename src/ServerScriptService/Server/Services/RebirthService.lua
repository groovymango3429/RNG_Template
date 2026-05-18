--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local ProgressionConfig = require(Config:WaitForChild("ProgressionConfig"))

local RebirthService = {}

function RebirthService:Init(dataService)
    self._dataService = dataService
end

function RebirthService:GetState(player)
    local profile = self._dataService:GetProfile(player)
    if not profile then
        return nil
    end

    local rebirths = profile.Stats.Rebirths or 0
    local nextStage = ProgressionConfig.RebirthStages[math.min(rebirths + 1, #ProgressionConfig.RebirthStages)]
    local requiredShards = nextStage and (nextStage.RequiredShards or nextStage.RequiredRolls) or 0
    local currentShards = profile.Stats.Shards or profile.Stats.Gems or 0
    local nextBonusShards = nextStage and (nextStage.BonusShards or nextStage.BonusGems) or 0

    return {
        CurrentRebirths = rebirths,
        CurrentShards = currentShards,
        NextRequiredShards = requiredShards,
        NextBonusShards = nextBonusShards,
        -- Legacy aliases kept to avoid breaking older clients.
        CurrentRolls = currentShards,
        NextRequiredRolls = requiredShards,
        NextBonusGems = nextBonusShards,
        Progress = requiredShards > 0 and math.clamp(currentShards / requiredShards, 0, 1) or 1,
        AtMaxStage = rebirths >= #ProgressionConfig.RebirthStages,
    }
end

function RebirthService:TryRebirth(player, skipRequirement)
    local state = self:GetState(player)
    if not state then
        return nil, "No profile loaded."
    end

    if not skipRequirement and state.CurrentShards < state.NextRequiredShards then
        return nil, string.format("Need %d shards before rebirthing.", state.NextRequiredShards)
    end

    self._dataService:UpdateProfile(player, function(profile)
        local currentRebirths = profile.Stats.Rebirths or 0
        local nextStage = ProgressionConfig.RebirthStages[math.min(currentRebirths + 1, #ProgressionConfig.RebirthStages)]
        local requiredShards = nextStage and (nextStage.RequiredShards or nextStage.RequiredRolls) or 0
        local currentShards = profile.Stats.Shards or profile.Stats.Gems or 0
        local spentShards = skipRequirement and 0 or requiredShards
        local remainingShards = math.max(0, currentShards - spentShards)

        profile.Stats.Rebirths = currentRebirths + 1
        profile.Stats.Rolls = 0
        profile.Stats.Coins = 0
        profile.Stats.Cash = 0
        profile.Stats.Shards = remainingShards
        profile.Stats.Gems = remainingShards
    end)

    return self:GetState(player)
end

return RebirthService
