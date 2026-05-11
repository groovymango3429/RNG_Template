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
    end
    return reward.Label or reward.Type
end

return FormatUtil
