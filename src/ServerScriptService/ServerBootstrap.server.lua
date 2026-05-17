--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local DeveloperProducts = require(Config:WaitForChild("DeveloperProducts"))
local UIConfig = require(Config:WaitForChild("UIConfig"))

local ServerFolder = script.Parent:WaitForChild("Server")
local Services = ServerFolder:WaitForChild("Services")

local DataService = require(Services:WaitForChild("DataService"))
local MonetizationService = require(Services:WaitForChild("MonetizationService"))
local RNGService = require(Services:WaitForChild("RNGService"))
local RebirthService = require(Services:WaitForChild("RebirthService"))
local RemoteService = require(Services:WaitForChild("RemoteService"))
local RewardService = require(Services:WaitForChild("RewardService"))

RemoteService:Init()
DataService:Init()
RewardService:Init(DataService)
MonetizationService:Init(DataService)
RebirthService:Init(DataService)
RNGService:Init(DataService, MonetizationService)

local function notify(player, message, kind)
    RemoteService:Get("Notification"):FireClient(player, {
        Message = message,
        Kind = kind or "Info",
    })
end

local function buildSnapshot(player)
    local profile = DataService:GetProfile(player)
    if not profile then
        return nil
    end

    return {
        Meta = {
            SaveMode = profile.Meta.SaveMode,
        },
        Stats = {
            Coins = profile.Stats.Coins,
            Gems = profile.Stats.Gems,
            Rolls = profile.Stats.Rolls,
            Rebirths = profile.Stats.Rebirths,
            LuckMultiplier = RNGService:GetLuckMultiplier(player),
            AutoRoll = profile.Settings.AutoRoll,
        },
        Inventory = profile.Inventory,
        Index = profile.Index,
        Rewards = {
            Daily = RewardService:GetDailyState(player),
            Playtime = RewardService:GetPlaytimeState(player),
        },
        Progression = {
            Discover = RNGService:GetDiscoverState(player),
            Rebirth = RebirthService:GetState(player),
        },
        Monetization = {
            Gamepasses = MonetizationService:GetOwnedGamepasses(player),
        },
        RollTable = RNGService:GetClientRollTable(),
    }
end

local function pushState(player)
    RemoteService:Get("StateUpdated"):FireClient(player, buildSnapshot(player))
end

MonetizationService:SetDispatch(pushState, notify)

local function onPlayerAdded(player)
    local profile, isFallback = DataService:LoadProfile(player)
    if profile then
        profile.Settings.AutoRoll = false
        if profile.Meta.SaveMode ~= "Fallback" then
            DataService:MarkDirty(player)
        end
    end
    MonetizationService:LoadPlayer(player)
    pushState(player)

    if isFallback then
        notify(player, "DataStore fallback mode enabled. Progress will not save for this session.", "Warning")
    else
        notify(player, "Profile loaded.", "Success")
    end
end

local function onPlayerRemoving(player)
    DataService:ReleaseProfile(player)
end

for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

task.spawn(function()
    while true do
        task.wait(30)
        for _, player in ipairs(Players:GetPlayers()) do
            if DataService:GetProfile(player) then
                RewardService:AccumulatePlaytime(player, 30)
                pushState(player)
            end
        end
    end
end)

RemoteService:Get("RequestInitialState").OnServerInvoke = function(player)
    return buildSnapshot(player)
end

RemoteService:Get("RollRequest").OnServerInvoke = function(player)
    local result, message = RNGService:Roll(player)
    if not result then
        return {
            Success = false,
            Message = message,
        }
    end

    pushState(player)
    notify(player, string.format("You rolled %s!", result.Item.DisplayName), "Success")

    return {
        Success = true,
        Result = result,
    }
end

RemoteService:Get("ToggleAutoRoll").OnServerInvoke = function(player)
    local profile = DataService:UpdateProfile(player, function(activeProfile)
        activeProfile.Settings.AutoRoll = not activeProfile.Settings.AutoRoll
    end)

    pushState(player)
    return {
        Success = true,
        Enabled = profile and profile.Settings.AutoRoll or false,
    }
end

RemoteService:Get("ClaimDailyReward").OnServerInvoke = function(player)
    local reward, message = RewardService:ClaimDaily(player)
    if not reward then
        return { Success = false, Message = message }
    end
    pushState(player)
    notify(player, "Daily reward claimed.", "Success")
    return { Success = true, Reward = reward }
end

RemoteService:Get("ClaimPlaytimeReward").OnServerInvoke = function(player, index)
    local reward, message = RewardService:ClaimPlaytime(player, index)
    if not reward then
        return { Success = false, Message = message }
    end
    pushState(player)
    notify(player, "Playtime reward claimed.", "Success")
    return { Success = true, Reward = reward }
end

RemoteService:Get("RequestRebirth").OnServerInvoke = function(player)
    local state, message = RebirthService:TryRebirth(player, false)
    if not state then
        return { Success = false, Message = message }
    end
    pushState(player)
    notify(player, "Rebirth complete.", "Success")
    return { Success = true, State = state }
end

RemoteService:Get("PromptGamepassPurchase").OnServerInvoke = function(player, key)
    local success, message = MonetizationService:PromptGamepass(player, key)
    return { Success = success, Message = message }
end

RemoteService:Get("PromptDeveloperProductPurchase").OnServerInvoke = function(player, key)
    local success, message = MonetizationService:PromptDeveloperProduct(player, key)
    return { Success = success, Message = message }
end

game:BindToClose(function()
    for _, player in ipairs(Players:GetPlayers()) do
        DataService:ReleaseProfile(player)
    end
    DataService:Shutdown()
end)
