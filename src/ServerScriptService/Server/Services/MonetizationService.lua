--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local Gamepasses = require(Config:WaitForChild("Gamepasses"))
local DeveloperProducts = require(Config:WaitForChild("DeveloperProducts"))
local RewardApplier = require(script.Parent:WaitForChild("RewardApplier"))

local MonetizationService = {
    _started = false,
}

local function getProductKeyFromId(productId)
    for key, definition in pairs(DeveloperProducts) do
        if definition.Id == productId and productId ~= 0 then
            return key, definition
        end
    end
    return nil, nil
end

function MonetizationService:Init(dataService)
    if self._started then
        return
    end

    self._started = true
    self._dataService = dataService
    self._pushState = function() end
    self._notify = function() end

    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
        if not wasPurchased then
            return
        end

        for key, definition in pairs(Gamepasses) do
            if definition.Id == gamePassId and gamePassId ~= 0 then
                self._dataService:UpdateProfile(player, function(profile)
                    profile.Purchases.Gamepasses[key] = true
                    if key == "VIP" then
                        profile.Stats.Gems = (profile.Stats.Gems or 0) + (definition.ExtraGems or 0)
                    end
                end)
                self._pushState(player)
                self._notify(player, string.format("Purchased %s.", definition.Label), "Success")
                break
            end
        end
    end)

    MarketplaceService.ProcessReceipt = function(receiptInfo)
        return self:ProcessReceipt(receiptInfo)
    end
end

function MonetizationService:SetDispatch(pushState, notify)
    self._pushState = pushState
    self._notify = notify
end

function MonetizationService:LoadPlayer(player)
    for key, definition in pairs(Gamepasses) do
        if definition.Id ~= 0 then
            local success, ownsPass = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, definition.Id)
            if success then
                self._dataService:UpdateProfile(player, function(profile)
                    profile.Purchases.Gamepasses[key] = ownsPass
                end)
            else
                warn(string.format("[MonetizationService] Failed gamepass lookup for %s (%s)", player.Name, key))
            end
        end
    end
end

function MonetizationService:GetOwnedGamepasses(player)
    local profile = self._dataService:GetProfile(player)
    return profile and profile.Purchases.Gamepasses or {}
end

function MonetizationService:HasGamepass(player, key)
    local profile = self._dataService:GetProfile(player)
    return profile and profile.Purchases.Gamepasses[key] == true or false
end

function MonetizationService:GetLuckModifier(player)
    local modifier = 0
    if self:HasGamepass(player, "VIP") then
        modifier = modifier + (Gamepasses.VIP.ExtraLuck or 0)
    end
    if self:HasGamepass(player, "DoubleLuck") then
        modifier = modifier + ((Gamepasses.DoubleLuck.LuckMultiplier or 1) - 1)
    end
    return modifier
end

function MonetizationService:CanUseAutoRoll(player)
    return self:HasGamepass(player, "AutoRoll")
end

function MonetizationService:PromptGamepass(player, key)
    local definition = Gamepasses[key]
    if not definition then
        return false, "Unknown gamepass key."
    end
    if definition.Id == 0 then
        return false, string.format("Set an ID for %s in Gamepasses.lua first.", key)
    end

    MarketplaceService:PromptGamePassPurchase(player, definition.Id)
    return true
end

function MonetizationService:PromptDeveloperProduct(player, key)
    local definition = DeveloperProducts[key]
    if not definition then
        return false, "Unknown developer product key."
    end
    if definition.Id == 0 then
        return false, string.format("Set an ID for %s in DeveloperProducts.lua first.", key)
    end

    MarketplaceService:PromptProductPurchase(player, definition.Id)
    return true
end

function MonetizationService:ProcessReceipt(receiptInfo)
    local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
    if not player then
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end

    local key, definition = getProductKeyFromId(receiptInfo.ProductId)
    if not key or not definition then
        warn(string.format("[MonetizationService] Unhandled developer product %d", receiptInfo.ProductId))
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end

    self._dataService:UpdateProfile(player, function(profile)
        profile.Purchases.Products[key] = (profile.Purchases.Products[key] or 0) + 1
        RewardApplier.Apply(profile, definition.Reward)
    end)

    self._pushState(player)
    self._notify(player, string.format("Granted %s.", definition.Label), "Success")
    return Enum.ProductPurchaseDecision.PurchaseGranted
end

return MonetizationService
