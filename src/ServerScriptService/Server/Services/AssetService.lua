--!strict
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")

local AssetConfig = require(Config:WaitForChild("AssetConfig"))
local RollConfig = require(Config:WaitForChild("RollConfig"))
local SafeWait = require(Util:WaitForChild("SafeWait"))

local AssetService = {}

function AssetService:Init()
    local assetsRoot = SafeWait.FindPath(ServerStorage, { "Assets" })
    if not assetsRoot then
        warn("[AssetService] ServerStorage/Assets is missing. Using fallback behavior for all model references.")
        self._assetsRoot = nil
        return
    end

    self._assetsRoot = assetsRoot
    for folderName, folderPath in pairs(AssetConfig.Folders) do
        local folder = SafeWait.FindPath(ServerStorage, folderPath, true)
        if not folder then
            warn(string.format("[AssetService] Missing asset folder for %s at %s.", folderName, table.concat(folderPath, "/")))
        end
    end

    local rewardFolder = SafeWait.FindPath(ServerStorage, AssetConfig.Folders.RewardModels, true)
    for _, item in ipairs(RollConfig) do
        if rewardFolder and not rewardFolder:FindFirstChild(item.ModelName) then
            warn(string.format("[AssetService] Missing reward model '%s' for RollConfig id '%s'.", item.ModelName, item.Id))
        end
    end
end

function AssetService:ResolveRewardModel(modelName)
    local rewardFolder = SafeWait.FindPath(ServerStorage, AssetConfig.Folders.RewardModels, true)
    if rewardFolder then
        local model = rewardFolder:FindFirstChild(modelName)
        if model then
            return model
        end

        local fallback = rewardFolder:FindFirstChild(AssetConfig.FallbackModelName)
        if fallback then
            warn(string.format("[AssetService] Using fallback reward model for missing model '%s'.", modelName))
            return fallback
        end
    end

    warn(string.format("[AssetService] Missing model '%s' and fallback '%s'.", modelName, AssetConfig.FallbackModelName))
    return nil
end

return AssetService
