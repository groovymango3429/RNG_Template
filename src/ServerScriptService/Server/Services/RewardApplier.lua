--!strict
local RewardApplier = {}

local function getMultiplier(baseValue)
    return math.max(baseValue or 1, 0)
end

function RewardApplier.Apply(profile, reward)
    if reward.Type == "Coins" then
        local scale = getMultiplier(1 + (profile.Modifiers.CoinMultiplier or 0))
        local amount = math.floor((reward.Amount or 0) * scale)
        profile.Stats.Coins = (profile.Stats.Coins or 0) + amount
    elseif reward.Type == "Gems" then
        local scale = getMultiplier(1 + (profile.Modifiers.GemMultiplier or 0))
        local amount = math.floor((reward.Amount or 0) * scale)
        profile.Stats.Gems = (profile.Stats.Gems or 0) + amount
    elseif reward.Type == "LuckBoost" then
        local boost = profile.Boosts.Luck or { Amount = 0, ExpiresAt = 0 }
        boost.Amount = math.max(boost.Amount or 0, reward.Amount or 0)
        boost.ExpiresAt = math.max(boost.ExpiresAt or 0, os.time() + (reward.Duration or 0))
        profile.Boosts.Luck = boost
    elseif reward.Type == "Item" then
        local itemId = reward.ItemId
        if itemId then
            profile.Inventory[itemId] = (profile.Inventory[itemId] or 0) + (reward.Amount or 1)
            profile.Index[itemId] = true
        end
    elseif reward.Type == "AutoRoll" then
        profile.Settings.AutoRoll = true
    elseif reward.Type == "SkillPoints" then
        profile.Stats.SkillPoints = (profile.Stats.SkillPoints or 0) + (reward.Amount or 0)
    elseif reward.Type == "CoinMultiplier" then
        profile.Modifiers.CoinMultiplier = (profile.Modifiers.CoinMultiplier or 0) + (reward.Amount or 0)
    elseif reward.Type == "GemMultiplier" then
        profile.Modifiers.GemMultiplier = (profile.Modifiers.GemMultiplier or 0) + (reward.Amount or 0)
    elseif reward.Type == "LuckBonus" then
        profile.Modifiers.LuckBonus = (profile.Modifiers.LuckBonus or 0) + (reward.Amount or 0)
    elseif reward.Type == "AutoRollInterval" then
        profile.Modifiers.AutoRollIntervalReduction = (profile.Modifiers.AutoRollIntervalReduction or 0) + (reward.Amount or 0)
    elseif reward.Type == "CombatPower" then
        local amount = reward.Amount or 0
        profile.Modifiers.CombatPowerBonus = (profile.Modifiers.CombatPowerBonus or 0) + amount
        profile.Stats.CombatPower = (profile.Stats.CombatPower or 0) + amount
    elseif reward.Type == "UnlockZone" then
        if reward.ZoneId then
            profile.Unlocks.Zones[reward.ZoneId] = true
        end
    else
        warn(string.format("[RewardApplier] Unknown reward type '%s'.", tostring(reward.Type)))
    end
end

return RewardApplier
