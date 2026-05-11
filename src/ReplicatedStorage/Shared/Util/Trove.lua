--!strict
local Trove = {}
Trove.__index = Trove

local function cleanupTask(task)
    local taskType = typeof(task)
    if taskType == "RBXScriptConnection" then
        task:Disconnect()
    elseif taskType == "Instance" then
        task:Destroy()
    elseif taskType == "function" then
        task()
    elseif type(task) == "table" then
        if typeof(task.Destroy) == "function" then
            task:Destroy()
        elseif typeof(task.Clean) == "function" then
            task:Clean()
        elseif typeof(task.Disconnect) == "function" then
            task:Disconnect()
        end
    end
end

function Trove.new()
    return setmetatable({ _tasks = {} }, Trove)
end

function Trove:Add(task)
    table.insert(self._tasks, task)
    return task
end

function Trove:Connect(signal, callback)
    local connection = signal:Connect(callback)
    self:Add(connection)
    return connection
end

function Trove:Clean()
    for index = #self._tasks, 1, -1 do
        cleanupTask(self._tasks[index])
        self._tasks[index] = nil
    end
end

function Trove:Destroy()
    self:Clean()
end

return Trove
