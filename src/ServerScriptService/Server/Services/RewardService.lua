--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local RewardsConfig = require(Config:WaitForChild("Rewards"))
local RewardApplier = require(script.Parent:WaitForChild("RewardApplier"))

local RewardService = {}

local function getCurrentDayIndex(lastClaimDay, currentDay, dayCount)
    if lastClaimDay < 0 then
        return currentDay
    end

    local delta = currentDay - lastClaimDay
    if delta > 1 then
        return 1
    end

    return math.clamp(currentDay, 1, dayCount)
end

function RewardService:Init(dataService)
    self._dataService = dataService
end

function RewardService:AccumulatePlaytime(player, deltaSeconds)
    self._dataService:UpdateProfile(player, function(profile)
        profile.Rewards.Playtime.AccumulatedSeconds = (profile.Rewards.Playtime.AccumulatedSeconds or 0) + deltaSeconds
    end)
end

function RewardService:GetDailyState(player)
    local profile = self._dataService:GetProfile(player)
    if not profile then
        return nil
    end

    local currentDay = math.floor(os.time() / 86400)
    local saved = profile.Rewards.Daily
    local nextDay = getCurrentDayIndex(saved.LastClaimDay or -1, saved.CurrentDay or 1, #RewardsConfig.Daily)
    local canClaim = (saved.LastClaimDay or -1) < currentDay

    local slots = {}
    for index, reward in ipairs(RewardsConfig.Daily) do
        slots[index] = {
            Index = index,
            Reward = reward,
            Claimed = index < nextDay or (not canClaim and index == nextDay),
            Claimable = canClaim and index == nextDay,
        }
    end

    return {
        CanClaim = canClaim,
        NextIndex = nextDay,
        Slots = slots,
    }
end

function RewardService:ClaimDaily(player)
    local state = self:GetDailyState(player)
    if not state then
        return nil, "No profile loaded."
    end
    if not state.CanClaim then
        return nil, "Daily reward already claimed."
    end

    local reward = RewardsConfig.Daily[state.NextIndex]
    self._dataService:UpdateProfile(player, function(profile)
        profile.Rewards.Daily.LastClaimDay = math.floor(os.time() / 86400)
        profile.Rewards.Daily.CurrentDay = state.NextIndex >= #RewardsConfig.Daily and 1 or (state.NextIndex + 1)
        RewardApplier.Apply(profile, reward)
    end)

    return reward
end

function RewardService:GetPlaytimeState(player)
    local profile = self._dataService:GetProfile(player)
    if not profile then
        return nil
    end

    local claimed = profile.Rewards.Playtime.ClaimedSlots or {}
    local elapsed = profile.Rewards.Playtime.AccumulatedSeconds or 0
    local slots = {}

    for index, definition in ipairs(RewardsConfig.Playtime) do
        slots[index] = {
            Index = index,
            RequiredSeconds = definition.RequiredSeconds,
            Reward = definition.Reward,
            Claimed = claimed[index] == true,
            Claimable = claimed[index] ~= true and elapsed >= definition.RequiredSeconds,
            Progress = math.clamp(elapsed / definition.RequiredSeconds, 0, 1),
        }
    end

    return {
        ElapsedSeconds = elapsed,
        Slots = slots,
    }
end

function RewardService:ClaimPlaytime(player, index)
    local state = self:GetPlaytimeState(player)
    if not state then
        return nil, "No profile loaded."
    end

    local slot = state.Slots[index]
    if not slot then
        return nil, "Invalid playtime reward slot."
    end
    if slot.Claimed then
        return nil, "Playtime reward already claimed."
    end
    if not slot.Claimable then
        return nil, "More playtime is required before claiming this reward."
    end

    self._dataService:UpdateProfile(player, function(profile)
        profile.Rewards.Playtime.ClaimedSlots[index] = true
        RewardApplier.Apply(profile, slot.Reward)
    end)

    return slot.Reward
end

return RewardService
