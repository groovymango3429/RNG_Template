--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefinitions = require(Shared:WaitForChild("RemoteDefinitions"))

local remotesFolder = ReplicatedStorage:WaitForChild(RemoteDefinitions.FolderName)
local remotes = {}
for _, definition in ipairs(RemoteDefinitions.Entries) do
    remotes[definition.Name] = remotesFolder:WaitForChild(definition.Name)
end

local Client = script:WaitForChild("Client")
local Controllers = Client:WaitForChild("Controllers")

local NotificationController = require(Controllers:WaitForChild("NotificationController"))
local UIController = require(Controllers:WaitForChild("UIController"))

local uiController = UIController.new(remotes, NotificationController)

local initialSnapshot = remotes.RequestInitialState:InvokeServer()
uiController:ApplySnapshot(initialSnapshot)

remotes.StateUpdated.OnClientEvent:Connect(function(snapshot)
    uiController:ApplySnapshot(snapshot)
end)

remotes.RollResult.OnClientEvent:Connect(function(result)
    uiController:PlayRollResult(result)
end)

remotes.Notification.OnClientEvent:Connect(function(payload)
    NotificationController:Show(payload)
end)
