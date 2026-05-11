--!strict
local SkillTreeConfig = require(script.Parent.Parent.Config:WaitForChild("SkillTreeConfig"))

local SkillTree = {}

function SkillTree.BuildNodeMap()
    local map = {}
    for _, node in ipairs(SkillTreeConfig.Nodes) do
        map[node.Id] = node
    end
    return map
end

function SkillTree.GetNode(nodeId)
    for _, node in ipairs(SkillTreeConfig.Nodes) do
        if node.Id == nodeId then
            return node
        end
    end
    return nil
end

function SkillTree.GetCurrencyAmount(profile, currency)
    if currency == "SkillPoints" then
        return profile.Stats.SkillPoints or 0
    end
    return profile.Stats[currency] or 0
end

function SkillTree.HasRequirements(profile, node)
    local requirements = node.UnlockRequirements or {}
    if (requirements.MinimumRolls or 0) > (profile.Stats.Rolls or 0) then
        return false, string.format("Need %d rolls", requirements.MinimumRolls)
    end
    if (requirements.MinimumRebirths or 0) > (profile.Stats.Rebirths or 0) then
        return false, string.format("Need %d rebirths", requirements.MinimumRebirths)
    end

    local inventoryRequirements = requirements.RequiredItems or {}
    for itemId, amount in pairs(inventoryRequirements) do
        if (profile.Inventory[itemId] or 0) < amount then
            return false, string.format("Need %dx %s", amount, itemId)
        end
    end

    return true
end

function SkillTree.HasParents(profile, node)
    local unlockedNodes = profile.SkillTree.UnlockedNodes or {}
    for _, parentId in ipairs(node.ParentDependencies or {}) do
        if unlockedNodes[parentId] ~= true then
            return false, string.format("Requires %s", parentId)
        end
    end
    return true
end

function SkillTree.CanPurchase(profile, node)
    local unlockedNodes = profile.SkillTree.UnlockedNodes or {}
    if unlockedNodes[node.Id] == true then
        return false, "Already unlocked"
    end

    local hasRequirements, requirementMessage = SkillTree.HasRequirements(profile, node)
    if not hasRequirements then
        return false, requirementMessage
    end

    local hasParents, parentMessage = SkillTree.HasParents(profile, node)
    if not hasParents then
        return false, parentMessage
    end

    local cost = node.Cost or { Currency = "SkillPoints", Amount = 0 }
    local balance = SkillTree.GetCurrencyAmount(profile, cost.Currency)
    if balance < (cost.Amount or 0) then
        return false, string.format("Need %d %s", cost.Amount or 0, cost.Currency or "resources")
    end

    return true
end

function SkillTree.GetNodeState(profile, node)
    local unlockedNodes = profile.SkillTree.UnlockedNodes or {}
    local unlocked = unlockedNodes[node.Id] == true

    local visible = true
    local hasParents, _ = SkillTree.HasParents(profile, node)
    if not hasParents and not unlocked then
        visible = false
    end

    local canPurchase, reason = SkillTree.CanPurchase(profile, node)

    return {
        Id = node.Id,
        Name = node.Name,
        Description = node.Description,
        Category = node.Category,
        Cost = node.Cost,
        ParentDependencies = node.ParentDependencies or {},
        UnlockRequirements = node.UnlockRequirements or {},
        Rewards = node.Rewards or {},
        Gui = node.Gui or {},
        Unlocked = unlocked,
        Visible = visible,
        CanPurchase = canPurchase,
        LockedReason = canPurchase and "" or (reason or "Locked"),
    }
end

function SkillTree.GetTreeState(profile)
    local branchState = {}
    for branchId in pairs(SkillTreeConfig.Branches) do
        branchState[branchId] = {
            Id = branchId,
            UnlockedCount = 0,
            TotalCount = 0,
        }
    end

    local nodes = {}
    for _, node in ipairs(SkillTreeConfig.Nodes) do
        local nodeState = SkillTree.GetNodeState(profile, node)
        nodes[node.Id] = nodeState
        local branch = branchState[node.Category]
        if branch then
            branch.TotalCount += 1
            if nodeState.Unlocked then
                branch.UnlockedCount += 1
            end
        end
    end

    return {
        RootPanelPath = SkillTreeConfig.RootPanelPath,
        Nodes = nodes,
        Branches = branchState,
        AvailableCurrencies = {
            SkillPoints = profile.Stats.SkillPoints or 0,
            Coins = profile.Stats.Coins or 0,
            Gems = profile.Stats.Gems or 0,
        },
    }
end

return SkillTree
