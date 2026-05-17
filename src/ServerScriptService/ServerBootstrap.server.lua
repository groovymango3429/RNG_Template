--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local DeveloperProducts = require(Config:WaitForChild("DeveloperProducts"))
local Rarities = require(Config:WaitForChild("Rarities"))
local RollConfig = require(Config:WaitForChild("RollConfig"))
local UIConfig = require(Config:WaitForChild("UIConfig"))

local ServerFolder = script.Parent:WaitForChild("Server")
local Services = ServerFolder:WaitForChild("Services")

local DataService = require(Services:WaitForChild("DataService"))
local MonetizationService = require(Services:WaitForChild("MonetizationService"))
local RNGService = require(Services:WaitForChild("RNGService"))
local RebirthService = require(Services:WaitForChild("RebirthService"))
local RemoteService = require(Services:WaitForChild("RemoteService"))
local RewardService = require(Services:WaitForChild("RewardService"))

local rollLookup = {}
for _, item in ipairs(RollConfig) do
    if item and item.Id then
        rollLookup[item.Id] = item
    end
end

local function compareItemsForEquip(leftItem, rightItem)
    local leftRarity = leftItem and Rarities[leftItem.Rarity]
    local rightRarity = rightItem and Rarities[rightItem.Rarity]
    local leftOrder = leftRarity and leftRarity.Order or 0
    local rightOrder = rightRarity and rightRarity.Order or 0
    if leftOrder ~= rightOrder then
        return leftOrder > rightOrder
    end

    local leftCoins = leftItem and leftItem.RewardCoins or 0
    local rightCoins = rightItem and rightItem.RewardCoins or 0
    if leftCoins ~= rightCoins then
        return leftCoins > rightCoins
    end

    local leftName = tostring(leftItem and (leftItem.DisplayName or leftItem.Id) or "")
    local rightName = tostring(rightItem and (rightItem.DisplayName or rightItem.Id) or "")
    return leftName < rightName
end

local function resolveBestOwnedItemId(profile)
    local bestId = nil
    local bestItem = nil
    local inventory = profile and profile.Inventory
    if type(inventory) ~= "table" then
        return nil
    end

    for itemId, amount in pairs(inventory) do
        if type(itemId) == "string" and type(amount) == "number" and amount > 0 then
            local candidate = rollLookup[itemId]
            if candidate and (not bestItem or compareItemsForEquip(candidate, bestItem)) then
                bestItem = candidate
                bestId = itemId
            end
        end
    end
    return bestId
end

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
        EquippedItemId = profile.EquippedItemId,
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

RemoteService:Get("RequestEquipItem").OnServerInvoke = function(player, itemId)
    if type(itemId) ~= "string" or itemId == "" then
        return { Success = false, Message = "Invalid item." }
    end

    local item = rollLookup[itemId]
    if not item then
        return { Success = false, Message = "Item not found." }
    end

    local didEquip = false
    local profile = DataService:UpdateProfile(player, function(activeProfile)
        local owned = (activeProfile.Inventory and activeProfile.Inventory[itemId]) or 0
        if owned <= 0 then
            return
        end
        activeProfile.EquippedItemId = itemId
        didEquip = true
    end)

    if not profile then
        return { Success = false, Message = "Profile not loaded." }
    end

    if not didEquip then
        return { Success = false, Message = "You do not own this item." }
    end

    pushState(player)
    return { Success = true, EquippedItemId = profile.EquippedItemId }
end

RemoteService:Get("RequestEquipBestItem").OnServerInvoke = function(player)
    local equippedBestId = nil
    local profile = DataService:UpdateProfile(player, function(activeProfile)
        local bestId = resolveBestOwnedItemId(activeProfile)
        if bestId then
            activeProfile.EquippedItemId = bestId
            equippedBestId = bestId
        end
    end)

    if not profile then
        return { Success = false, Message = "Profile not loaded." }
    end

    if type(equippedBestId) ~= "string" or equippedBestId == "" then
        return { Success = false, Message = "No item available to equip." }
    end

    local ownedCount = (profile.Inventory and profile.Inventory[equippedBestId]) or 0
    if ownedCount <= 0 then
        return { Success = false, Message = "No item available to equip." }
    end

    pushState(player)
    return { Success = true, EquippedItemId = equippedBestId }
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
