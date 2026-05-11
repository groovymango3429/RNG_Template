--!strict
local SafeWait = {}

local function pathToString(path)
    return table.concat(path, ".")
end

function SafeWait.WaitForChild(parent, childName, timeout)
    local existing = parent:FindFirstChild(childName)
    if existing then
        return existing
    end

    local ok, result = pcall(parent.WaitForChild, parent, childName, timeout or 5)
    if ok and result then
        return result
    end

    warn(string.format("[UI] Missing child '%s' under %s", childName, parent:GetFullName()))
    return nil
end

function SafeWait.WaitForPath(root, path, timeoutPerStep)
    local current = root
    for _, childName in ipairs(path) do
        current = SafeWait.WaitForChild(current, childName, timeoutPerStep)
        if not current then
            warn(string.format("[UI] Missing required path %s from %s", pathToString(path), root:GetFullName()))
            return nil
        end
    end
    return current
end

function SafeWait.FindPath(root, path, suppressWarning)
    local current = root
    for _, childName in ipairs(path) do
        current = current and current:FindFirstChild(childName)
        if not current then
            if not suppressWarning then
                warn(string.format("[UI] Missing optional path %s from %s", pathToString(path), root:GetFullName()))
            end
            return nil
        end
    end
    return current
end

return SafeWait
