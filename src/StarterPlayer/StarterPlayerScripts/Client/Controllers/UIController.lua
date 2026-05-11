--!strict
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")

local AnimationConfig = require(Config:WaitForChild("AnimationConfig"))
local DeveloperProducts = require(Config:WaitForChild("DeveloperProducts"))
local SkillTreeConfig = require(Config:WaitForChild("SkillTreeConfig"))
local FormatUtil = require(Util:WaitForChild("FormatUtil"))
local SafeWait = require(Util:WaitForChild("SafeWait"))
local Trove = require(Util:WaitForChild("Trove"))
local UIConfig = require(Config:WaitForChild("UIConfig"))

local UIController = {}
UIController.__index = UIController

local function setText(instance, text)
    if instance and instance:IsA("TextLabel") then
        instance.Text = text
    end
end

local function setFill(frame, alpha)
    if frame and frame:IsA("GuiObject") then
        frame.Size = UDim2.new(math.clamp(alpha, 0, 1), 0, frame.Size.Y.Scale, frame.Size.Y.Offset)
    end
end

local function findLabel(root, candidatePaths)
    for _, path in ipairs(candidatePaths) do
        local label = SafeWait.FindPath(root, path, true)
        if label and label:IsA("TextLabel") then
            return label
        end
    end
    return nil
end

local function getOrderedButtons(container)
    local buttons = {}
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("TextButton") or child:IsA("ImageButton") then
            table.insert(buttons, child)
        end
    end
    table.sort(buttons, function(a, b)
        if a.LayoutOrder == b.LayoutOrder then
            return a.Name < b.Name
        end
        return a.LayoutOrder < b.LayoutOrder
    end)
    return buttons
end

function UIController.new(remotes, notifier)
    local self = setmetatable({}, UIController)
    self._trove = Trove.new()
    self._remotes = remotes
    self._notifier = notifier
    self._snapshot = nil
    self._rollBusy = false
    self._autoRollThread = nil
    self._player = Players.LocalPlayer
    self._playerGui = self._player:WaitForChild("PlayerGui")
    self._ui = SafeWait.WaitForChild(self._playerGui, UIConfig.RootGui, 15)
    self._panels = {}
    self._rollTable = {}
    self._skillButtons = {}
    self._selectedSkillNodeId = nil

    if self._ui then
        for _, panelName in ipairs(UIConfig.Panels) do
            self._panels[panelName] = SafeWait.WaitForChild(self._ui, panelName, 5)
        end
        self:_bindNavigation()
        self:_bindActions()
        self:_bindCloseButtons()
        self:_bindRewardButtons()
        self:_bindSkillTreeButtons()
    end

    return self
end

function UIController:Destroy()
    self._trove:Destroy()
end

function UIController:_openPanel(panelName)
    for name, panel in pairs(self._panels) do
        if panel and (name ~= "LeftSide" and name ~= "LeftBottomBar") then
            panel.Visible = name == panelName
        end
    end
end

function UIController:_bindNavigation()
    for panelName, path in pairs(UIConfig.NavigationButtons) do
        local button = self._ui and SafeWait.FindPath(self._ui, path)
        if button and button:IsA("GuiButton") then
            self._trove:Connect(button.Activated, function()
                self:_openPanel(panelName)
            end)
        end
    end
end

function UIController:_invoke(remoteName, ...)
    local remote = self._remotes[remoteName]
    if not remote then
        return nil
    end

    local args = table.pack(...)
    local success, result = pcall(function()
        return remote:InvokeServer(table.unpack(args, 1, args.n))
    end)
    if not success then
        self._notifier:Show({ Kind = "Error", Message = string.format("Remote %s failed.", remoteName) })
        return nil
    end
    return result
end

function UIController:_bindActions()
    local rollButton = self._ui and SafeWait.FindPath(self._ui, UIConfig.ActionButtons.Roll)
    if rollButton and rollButton:IsA("GuiButton") then
        self._trove:Connect(rollButton.Activated, function()
            self:RequestRoll()
        end)
    end

    local autoRollButton = self._ui and SafeWait.FindPath(self._ui, UIConfig.ActionButtons.AutoRoll)
    if autoRollButton and autoRollButton:IsA("GuiButton") then
        self._trove:Connect(autoRollButton.Activated, function()
            local result = self:_invoke("ToggleAutoRoll")
            if result and not result.Success and result.Message then
                self._notifier:Show({ Kind = "Warning", Message = result.Message })
            end
        end)
    end

    local luckProductButton = self._ui and SafeWait.FindPath(self._ui, UIConfig.ActionButtons.LuckProduct)
    if luckProductButton and luckProductButton:IsA("GuiButton") then
        self._trove:Connect(luckProductButton.Activated, function()
            self:_invoke("PromptDeveloperProductPurchase", UIConfig.FeaturedProductKey)
        end)
    end

    local rewardsWatch = self._ui and SafeWait.FindPath(self._ui, UIConfig.ActionButtons.RewardsWatch)
    if rewardsWatch and rewardsWatch:IsA("GuiButton") then
        self._trove:Connect(rewardsWatch.Activated, function()
            self:_invoke("PromptDeveloperProductPurchase", UIConfig.FeaturedProductKey)
        end)
    end

    local rebirthButton = self._ui and SafeWait.FindPath(self._ui, UIConfig.ActionButtons.Rebirth)
    if rebirthButton and rebirthButton:IsA("GuiButton") then
        self._trove:Connect(rebirthButton.Activated, function()
            local result = self:_invoke("RequestRebirth")
            if result and not result.Success and result.Message then
                self._notifier:Show({ Kind = "Warning", Message = result.Message })
            end
        end)
    end

    local skipRebirth = self._ui and SafeWait.FindPath(self._ui, UIConfig.ActionButtons.SkipRebirth)
    if skipRebirth and skipRebirth:IsA("GuiButton") then
        self._trove:Connect(skipRebirth.Activated, function()
            self:_invoke("PromptDeveloperProductPurchase", UIConfig.RebirthSkipProductKey)
        end)
    end
end

function UIController:_bindCloseButtons()
    for panelName, path in pairs(UIConfig.CloseButtons) do
        local button = self._ui and SafeWait.FindPath(self._ui, path)
        if button and button:IsA("GuiButton") then
            self._trove:Connect(button.Activated, function()
                local panel = self._panels[panelName]
                if panel then
                    panel.Visible = false
                end
            end)
        end
    end
end

function UIController:_bindRewardButtons()
    local dailyContent = self._panels.DailyRewards and SafeWait.FindPath(self._panels.DailyRewards, { "Content" })
    if dailyContent then
        for index, button in ipairs(getOrderedButtons(dailyContent)) do
            self._trove:Connect(button.Activated, function()
                local dailyState = self._snapshot and self._snapshot.Rewards and self._snapshot.Rewards.Daily
                local slot = dailyState and dailyState.Slots[index]
                if slot and slot.Claimable then
                    local result = self:_invoke("ClaimDailyReward")
                    if result and not result.Success and result.Message then
                        self._notifier:Show({ Kind = "Warning", Message = result.Message })
                    end
                end
            end)
        end
    end

    local playtimeContent = self._panels.PlaytimeRewards and SafeWait.FindPath(self._panels.PlaytimeRewards, { "Content", "Main", "Rewards" })
    if playtimeContent then
        for index, button in ipairs(getOrderedButtons(playtimeContent)) do
            self._trove:Connect(button.Activated, function()
                local playtimeState = self._snapshot and self._snapshot.Rewards and self._snapshot.Rewards.Playtime
                local slot = playtimeState and playtimeState.Slots[index]
                if slot and slot.Claimable then
                    local result = self:_invoke("ClaimPlaytimeReward", index)
                    if result and not result.Success and result.Message then
                        self._notifier:Show({ Kind = "Warning", Message = result.Message })
                    end
                end
            end)
        end
    end
end

function UIController:_bindSkillTreeButtons()
    for _, node in ipairs(SkillTreeConfig.Nodes) do
        local buttonPath = node.Gui and node.Gui.ButtonPath
        if buttonPath then
            local button = SafeWait.FindPath(self._ui, buttonPath, true)
            if button and button:IsA("GuiButton") then
                self._skillButtons[node.Id] = button
                self._trove:Connect(button.Activated, function()
                    self._selectedSkillNodeId = node.Id
                    local result = self:_invoke("PurchaseSkillTreeNode", node.Id)
                    if result and not result.Success and result.Message then
                        self._notifier:Show({ Kind = "Warning", Message = result.Message })
                    end
                end)
            end
        end
    end
end

function UIController:RequestRoll()
    if self._rollBusy then
        return
    end
    self._rollBusy = true
    local result = self:_invoke("RollRequest")
    if result and not result.Success and result.Message then
        self._notifier:Show({ Kind = "Warning", Message = result.Message })
    end
    self._rollBusy = false
end

function UIController:_updateDailyRewards(dailyState)
    local content = self._panels.DailyRewards and SafeWait.FindPath(self._panels.DailyRewards, { "Content" })
    if not content or not dailyState then
        return
    end

    local buttons = getOrderedButtons(content)
    for index, button in ipairs(buttons) do
        local slotState = dailyState.Slots[index]
        if slotState then
            local headerLabel = findLabel(button, {
                { "Header", "Label01", "Main" },
                { "Header", "Label01" },
                { "Label01", "Main" },
            })
            local contentLabel = findLabel(button, {
                { "Content", "Label01" },
                { "Content", "Label01", "Main" },
                { "Label02" },
            })
            setText(headerLabel, string.format("Day %d", index))
            setText(contentLabel, FormatUtil.Reward(slotState.Reward))
            button.AutoButtonColor = slotState.Claimable
        end
    end
end

function UIController:_updatePlaytimeRewards(playtimeState)
    local rewardsFrame = self._panels.PlaytimeRewards and SafeWait.FindPath(self._panels.PlaytimeRewards, { "Content", "Main", "Rewards" })
    if not rewardsFrame or not playtimeState then
        return
    end

    local buttons = getOrderedButtons(rewardsFrame)
    for index, button in ipairs(buttons) do
        local slotState = playtimeState.Slots[index]
        if slotState then
            local title = findLabel(button, {
                { "Label01", "Main" },
                { "Label01", "Dropshadow" },
            })
            local rewardLabel = findLabel(button, {
                { "Label02", "Main" },
                { "Label02", "Dropshadow" },
            })
            setText(title, FormatUtil.Duration(slotState.RequiredSeconds))
            setText(rewardLabel, FormatUtil.Reward(slotState.Reward))
            button.AutoButtonColor = slotState.Claimable
        end
    end
end

function UIController:_updateDiscover(discoverState)
    local discover = self._panels.Discover
    if not discover or not discoverState then
        return
    end

    for _, zoneName in ipairs(UIConfig.DiscoverOrder) do
        local zoneFrame = SafeWait.FindPath(discover, { zoneName })
        local zoneState = discoverState[zoneName]
        if zoneFrame and zoneState then
            local label = findLabel(zoneFrame, {
                { "Label01", "Main" },
                { "Label01", "Dropshadow" },
            })
            local fill = SafeWait.FindPath(zoneFrame, { "Bar", "Fill" })
            setFill(fill, zoneState.Progress)
            if label then
                if zoneState.Unlocked then
                    label.Text = string.format("%s Unlocked", zoneName)
                else
                    label.Text = string.format("%s / %s rolls", FormatUtil.Number(self._snapshot.Stats.Rolls or 0), FormatUtil.Number(zoneState.RequiredRolls))
                end
            end
        end
    end
end

function UIController:_updateIndex(snapshot)
    local content = self._panels.Index and SafeWait.FindPath(self._panels.Index, { "Main", "Content" })
    if not content then
        return
    end

    local slots = getOrderedButtons(content)
    local rollTable = snapshot.RollTable or {}

    for index, button in ipairs(slots) do
        local item = rollTable[index]
        if item then
            local nameLabel = findLabel(button, {
                { "Label01", "BrainrotName" },
                { "Label01", "Main" },
            })
            local owned = snapshot.Index and snapshot.Index[item.Id] == true
            setText(nameLabel, owned and item.DisplayName or "???")
            button.AutoButtonColor = owned
        end
    end
end

function UIController:_updateRebirth(snapshot)
    local rebirthState = snapshot.Progression and snapshot.Progression.Rebirth
    local rebirthPanel = self._panels.Rebirth
    if not rebirthPanel or not rebirthState then
        return
    end

    local currentLabel = findLabel(rebirthPanel, {
        { "Content", "RebirthStage", "Current", "Label01", "Main" },
        { "Content", "RebirthStage", "Current", "Main", "Label01", "Main" },
    })
    local nextLabel = findLabel(rebirthPanel, {
        { "Content", "RebirthStage", "Next", "Label01", "Main" },
        { "Content", "RebirthStage", "Next", "Main", "Label01", "Main" },
    })
    local progressLabel = findLabel(rebirthPanel, {
        { "Content", "Progress", "Label02", "Main" },
        { "Content", "Label01", "Main" },
    })
    local fill = SafeWait.FindPath(rebirthPanel, { "Content", "Progress", "Bar", "Fill" })

    setText(currentLabel, string.format("Rebirths: %s", FormatUtil.Number(rebirthState.CurrentRebirths or 0)))
    setText(nextLabel, string.format("Next Bonus: %s Gems | +%s SP", FormatUtil.Number(rebirthState.NextBonusGems or 0), FormatUtil.Number(rebirthState.NextSkillPoints or 0)))
    setText(progressLabel, string.format("%s / %s rolls", FormatUtil.Number(rebirthState.CurrentRolls or 0), FormatUtil.Number(rebirthState.NextRequiredRolls or 0)))
    setFill(fill, rebirthState.Progress or 0)
end

function UIController:_updateRewardPanel(snapshot)
    local rewardsPanel = self._panels.Rewards
    if not rewardsPanel then
        return
    end

    local titleLabel = findLabel(rewardsPanel, {
        { "Content", "Label01", "Main" },
        { "Header", "Label01", "Main" },
    })
    local subLabel = findLabel(rewardsPanel, {
        { "Content", "Label02", "Main" },
        { "Content", "AltLabel02", "Main" },
    })
    local watchButtonLabel = findLabel(rewardsPanel, {
        { "Content", "WatchBtn", "Label01", "Main" },
    })

    setText(titleLabel, string.format("Coins: %s", FormatUtil.Number(snapshot.Stats.Coins or 0)))
    setText(subLabel, string.format("Gems: %s", FormatUtil.Number(snapshot.Stats.Gems or 0)))
    local featuredProduct = DeveloperProducts[UIConfig.FeaturedProductKey]
    if featuredProduct then
        setText(watchButtonLabel, featuredProduct.Label)
    end
end

function UIController:_updateSkillTree(snapshot)
    local tree = snapshot.SkillTree
    if not tree then
        return
    end

    local selectedNodeState = nil
    local selectedNodeConfig = nil

    for _, nodeConfig in ipairs(SkillTreeConfig.Nodes) do
        local nodeState = tree.Nodes[nodeConfig.Id]
        local button = self._skillButtons[nodeConfig.Id]
        if button and nodeState then
            button.Visible = nodeState.Visible
            button.AutoButtonColor = nodeState.CanPurchase
            button.Active = nodeState.Unlocked or nodeState.CanPurchase

            local title = findLabel(button, {
                { "Label01", "Main" },
                { "Title", "Main" },
            })
            local status = findLabel(button, {
                { "Label02", "Main" },
                { "Status", "Main" },
            })
            setText(title, nodeState.Name)
            if nodeState.Unlocked then
                setText(status, "Unlocked")
            elseif nodeState.CanPurchase then
                setText(status, "Available")
            else
                setText(status, nodeState.LockedReason)
            end
        end

        if self._selectedSkillNodeId == nodeConfig.Id then
            selectedNodeState = nodeState
            selectedNodeConfig = nodeConfig
        end
    end

    if not selectedNodeState then
        for _, nodeConfig in ipairs(SkillTreeConfig.Nodes) do
            local nodeState = tree.Nodes[nodeConfig.Id]
            if nodeState and nodeState.Visible then
                self._selectedSkillNodeId = nodeConfig.Id
                selectedNodeState = nodeState
                selectedNodeConfig = nodeConfig
                break
            end
        end
    end

    if selectedNodeState and selectedNodeConfig then
        local detailGui = SkillTreeConfig.DetailGui or {}
        local gui = selectedNodeConfig.Gui or {}
        local namePath = gui.NamePath or detailGui.NamePath
        local descriptionPath = gui.DescriptionPath or detailGui.DescriptionPath
        local costPath = gui.CostPath or detailGui.CostPath
        local statusPath = gui.StatusPath or detailGui.StatusPath

        local nameLabel = namePath and SafeWait.FindPath(self._ui, namePath, true)
        local descriptionLabel = descriptionPath and SafeWait.FindPath(self._ui, descriptionPath, true)
        local costLabel = costPath and SafeWait.FindPath(self._ui, costPath, true)
        local statusLabel = statusPath and SafeWait.FindPath(self._ui, statusPath, true)

        setText(nameLabel, selectedNodeState.Name)
        setText(descriptionLabel, selectedNodeState.Description)
        if selectedNodeState.Cost then
            setText(costLabel, string.format("Cost: %s %s", FormatUtil.Number(selectedNodeState.Cost.Amount or 0), selectedNodeState.Cost.Currency or ""))
        end

        if selectedNodeState.Unlocked then
            setText(statusLabel, "Unlocked")
        elseif selectedNodeState.CanPurchase then
            setText(statusLabel, "Click node to unlock")
        else
            setText(statusLabel, selectedNodeState.LockedReason)
        end
    end
end

function UIController:_updateAutoRollState(snapshot)
    if self._autoRollThread then
        task.cancel(self._autoRollThread)
        self._autoRollThread = nil
    end

    local interval = snapshot.Stats and snapshot.Stats.AutoRollInterval or 1.5
    if snapshot.Stats and snapshot.Stats.AutoRoll then
        self._autoRollThread = task.spawn(function()
            while self._snapshot and self._snapshot.Stats and self._snapshot.Stats.AutoRoll do
                if not self._rollBusy then
                    self:RequestRoll()
                end
                task.wait(interval)
            end
        end)
    end
end

function UIController:ApplySnapshot(snapshot)
    if not snapshot then
        return
    end

    self._snapshot = snapshot
    self._rollTable = snapshot.RollTable or self._rollTable
    self:_updateDailyRewards(snapshot.Rewards and snapshot.Rewards.Daily)
    self:_updatePlaytimeRewards(snapshot.Rewards and snapshot.Rewards.Playtime)
    self:_updateDiscover(snapshot.Progression and snapshot.Progression.Discover)
    self:_updateIndex(snapshot)
    self:_updateRebirth(snapshot)
    self:_updateRewardPanel(snapshot)
    self:_updateSkillTree(snapshot)
    self:_updateAutoRollState(snapshot)
end

function UIController:PlayRollResult(result)
    if not result or not self._panels.Rewards then
        return
    end

    self:_openPanel("Rewards")
    local nameLabel = findLabel(self._panels.Rewards, {
        { "Content", "Label01", "Main" },
        { "Header", "Label01", "Main" },
    })
    local rarityLabel = findLabel(self._panels.Rewards, {
        { "Content", "Label02", "Main" },
        { "Content", "AltLabel02", "Main" },
    })

    task.spawn(function()
        for index = 1, AnimationConfig.RollCycleCount do
            local preview = self._rollTable[((index - 1) % math.max(#self._rollTable, 1)) + 1]
            if preview then
                setText(nameLabel, preview.DisplayName)
                setText(rarityLabel, preview.Rarity)
            end
            task.wait(AnimationConfig.RollCycleDelay)
        end

        setText(nameLabel, result.Item.DisplayName)
        setText(rarityLabel, string.format("%s • %s", result.Item.Rarity, result.Item.DisplayOdds or "Weighted"))
    end)
end

return UIController
