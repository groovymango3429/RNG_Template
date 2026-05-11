--!strict
local TableUtil = {}

function TableUtil.DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, nested in pairs(value) do
        copy[key] = TableUtil.DeepCopy(nested)
    end
    return copy
end

function TableUtil.Reconcile(source, template)
    local base = TableUtil.DeepCopy(template)
    if type(source) ~= "table" then
        return base
    end

    for key, value in pairs(source) do
        if type(value) == "table" and type(base[key]) == "table" then
            base[key] = TableUtil.Reconcile(value, base[key])
        else
            base[key] = TableUtil.DeepCopy(value)
        end
    end

    return base
end

function TableUtil.Count(map)
    local total = 0
    for _ in pairs(map) do
        total = total + 1
    end
    return total
end

return TableUtil
