--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefinitions = require(Shared:WaitForChild("RemoteDefinitions"))

local RemoteService = {
    _instances = {} :: {[string]: any},
}

function RemoteService:Init()
    local folder = ReplicatedStorage:FindFirstChild(RemoteDefinitions.FolderName)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = RemoteDefinitions.FolderName
        folder.Parent = ReplicatedStorage
    end

    self._folder = folder
    for _, definition in ipairs(RemoteDefinitions.Entries) do
        local remote = folder:FindFirstChild(definition.Name)
        if not remote then
            remote = Instance.new(definition.ClassName)
            remote.Name = definition.Name
            remote.Parent = folder
        end
        self._instances[definition.Name] = remote
    end
end

function RemoteService:Get(name)
    return self._instances[name]
end

return RemoteService
