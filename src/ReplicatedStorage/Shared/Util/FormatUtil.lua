--!strict
local FormatUtil = {}
local SCALE_FACTOR_BY_DECIMALS = {
    [0] = 1,
    [1] = 10,
    [2] = 100,
}

function FormatUtil.Number(value)
    local numeric = tonumber(value) or 0
    local isNegative = numeric < 0
    local absolute = math.floor(math.abs(numeric))

    if absolute < 1000 then
        return (isNegative and "-" or "") .. tostring(absolute)
    end

    local suffixes = {
        { 1e12, "T" },
        { 1e9, "B" },
        { 1e6, "M" },
        { 1e3, "K" },
    }

    for _, entry in ipairs(suffixes) do
        local threshold = entry[1]
        local suffix = entry[2]
        if absolute >= threshold then
            local scaled = absolute / threshold
            local decimals = (scaled >= 100 and 0) or (scaled >= 10 and 1) or 2
            local scaleFactor = SCALE_FACTOR_BY_DECIMALS[decimals] or 1
            scaled = math.floor(scaled * scaleFactor) / scaleFactor
            local formatString = "%." .. tostring(decimals) .. "f"
            local compact = string.format(formatString, scaled)
            if compact:find("%.") then
                compact = compact:gsub("0+$", ""):gsub("%.$", "")
            end
            return (isNegative and "-" or "") .. compact .. suffix
        end
    end

    return (isNegative and "-" or "") .. tostring(absolute)
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
        return string.format("%s Cash", FormatUtil.Number(reward.Amount or 0))
    elseif reward.Type == "Gems" then
        return string.format("%s Shards", FormatUtil.Number(reward.Amount or 0))
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
