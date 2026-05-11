--!strict
local WeightedRandom = {}

function WeightedRandom.Choose(items, weightResolver, randomObject)
    local totalWeight = 0
    local resolvedWeights = table.create(#items)

    for index, item in ipairs(items) do
        local weight = math.max(0, weightResolver(item))
        resolvedWeights[index] = weight
        totalWeight = totalWeight + weight
    end

    if totalWeight <= 0 then
        return nil, "No weighted entries were available."
    end

    local rng = randomObject or Random.new()
    local roll = rng:NextNumber(0, totalWeight)
    local cursor = 0

    for index, item in ipairs(items) do
        cursor = cursor + resolvedWeights[index]
        if roll <= cursor then
            return item
        end
    end

    return items[#items]
end

return WeightedRandom
