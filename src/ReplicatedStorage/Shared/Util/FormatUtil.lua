--!strict
local FormatUtil = {}

function FormatUtil.Number(value)
    local formatted = tostring(math.floor(value))
    while true do
        local updated, matches = formatted:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
        formatted = updated
        if matches == 0 then
            break
        end
    end
    return formatted
end

function FormatUtil.Duration(seconds)
    local totalSeconds = math.max(0, math.floor(seconds))
    local minutes = math.floor(totalSeconds / 60)
    local remainingSeconds = totalSeconds % 60
    if minutes > 0 then
        return string.format("%dm %02ds", minutes, remainingSeconds)
    end
    return string.format("%ds", remainingSeconds)
end

function FormatUtil.Reward(reward)
    if reward.Type == "Coins" then
        return string.format("%s Coins", FormatUtil.Number(reward.Amount or 0))
    elseif reward.Type == "Gems" then
        return string.format("%s Gems", FormatUtil.Number(reward.Amount or 0))
    elseif reward.Type == "LuckBoost" then
        return string.format("+%.2fx Luck (%s)", reward.Amount or 0, FormatUtil.Duration(reward.Duration or 0))
    elseif reward.Type == "Item" then
        return string.format("%sx %s", reward.Amount or 1, reward.ItemId or "Reward")
    elseif reward.Type == "AutoRoll" then
        return "Auto Roll Unlock"
    elseif reward.Type == "SkillPoints" then
        return string.format("%s Skill Points", FormatUtil.Number(reward.Amount or 0))
    elseif reward.Type == "CoinMultiplier" then
        return string.format("+%d%% Coin Rewards", math.floor((reward.Amount or 0) * 100))
    elseif reward.Type == "GemMultiplier" then
        return string.format("+%d%% Gem Rewards", math.floor((reward.Amount or 0) * 100))
    elseif reward.Type == "LuckBonus" then
        return string.format("+%.2f Luck", reward.Amount or 0)
    elseif reward.Type == "AutoRollInterval" then
        return string.format("-%.2fs Auto Roll Interval", reward.Amount or 0)
    elseif reward.Type == "CombatPower" then
        return string.format("+%s Combat Power", FormatUtil.Number(reward.Amount or 0))
    elseif reward.Type == "UnlockZone" then
        return string.format("Unlocks zone: %s", reward.ZoneId or "Unknown")
    end
    return reward.Label or reward.Type
end

return FormatUtil
