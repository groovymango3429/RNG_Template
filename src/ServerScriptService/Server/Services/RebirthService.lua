--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
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
    local requiredRolls = nextStage and nextStage.RequiredRolls or profile.Stats.Rolls or 0
    local currentRolls = profile.Stats.Rolls or 0

    return {
        CurrentRebirths = rebirths,
        CurrentRolls = currentRolls,
        NextRequiredRolls = requiredRolls,
        NextBonusGems = nextStage and nextStage.BonusGems or 0,
        NextSkillPoints = EconomyConfig.Rebirth.SkillPointsPerRebirth,
        Progress = requiredRolls > 0 and math.clamp(currentRolls / requiredRolls, 0, 1) or 1,
        AtMaxStage = rebirths >= #ProgressionConfig.RebirthStages,
    }
end

function RebirthService:TryRebirth(player, skipRequirement)
    local state = self:GetState(player)
    if not state then
        return nil, "No profile loaded."
    end

    if not skipRequirement and state.CurrentRolls < state.NextRequiredRolls then
        return nil, string.format("Need %d rolls before rebirthing.", state.NextRequiredRolls)
    end

    self._dataService:UpdateProfile(player, function(profile)
        profile.Stats.Rebirths = (profile.Stats.Rebirths or 0) + 1
        profile.Stats.SkillPoints = (profile.Stats.SkillPoints or 0) + EconomyConfig.Rebirth.SkillPointsPerRebirth

        if EconomyConfig.Rebirth.ResetRolls then
            profile.Stats.Rolls = 0
        end
        if EconomyConfig.Rebirth.ResetCoins then
            profile.Stats.Coins = 0
        end
        if EconomyConfig.Rebirth.ResetCombatPower then
            profile.Stats.CombatPower = EconomyConfig.StartingStats.CombatPower
        end

        profile.Stats.Gems = (profile.Stats.Gems or 0) + state.NextBonusGems
    end)

    return self:GetState(player)
end

return RebirthService
