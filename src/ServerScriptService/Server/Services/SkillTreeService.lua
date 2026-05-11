--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Systems = Shared:WaitForChild("Systems")

local SkillTree = require(Systems:WaitForChild("SkillTree"))

local SkillTreeService = {}

function SkillTreeService:Init(dataService, rewardApplier)
    self._dataService = dataService
    self._rewardApplier = rewardApplier
end

function SkillTreeService:GetState(player)
    local profile = self._dataService:GetProfile(player)
    if not profile then
        return nil
    end
    return SkillTree.GetTreeState(profile)
end

function SkillTreeService:PurchaseNode(player, nodeId)
    local profile = self._dataService:GetProfile(player)
    if not profile then
        return nil, "No profile loaded."
    end

    local node = SkillTree.GetNode(nodeId)
    if not node then
        return nil, "Unknown skill tree node."
    end

    local canPurchase, message = SkillTree.CanPurchase(profile, node)
    if not canPurchase then
        return nil, message
    end

    self._dataService:UpdateProfile(player, function(activeProfile)
        local cost = node.Cost or { Currency = "SkillPoints", Amount = 0 }
        activeProfile.Stats[cost.Currency] = (activeProfile.Stats[cost.Currency] or 0) - (cost.Amount or 0)
        activeProfile.SkillTree.UnlockedNodes[node.Id] = true

        for _, reward in ipairs(node.Rewards or {}) do
            self._rewardApplier.Apply(activeProfile, reward)
        end
    end)

    return self:GetState(player)
end

return SkillTreeService
