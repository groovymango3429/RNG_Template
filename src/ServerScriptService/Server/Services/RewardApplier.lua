--!strict
local RewardApplier = {}

function RewardApplier.Apply(profile, reward)
    if reward.Type == "Coins" then
        profile.Stats.Coins = (profile.Stats.Coins or 0) + (reward.Amount or 0)
    elseif reward.Type == "Gems" then
        profile.Stats.Gems = (profile.Stats.Gems or 0) + (reward.Amount or 0)
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
    end
end

return RewardApplier
