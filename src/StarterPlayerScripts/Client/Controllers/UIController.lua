--!strict
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")

local AnimationConfig = require(Config:WaitForChild("AnimationConfig"))
local DeveloperProducts = require(Config:WaitForChild("DeveloperProducts"))
local Rarities = require(Config:WaitForChild("Rarities"))
local FormatUtil = require(Util:WaitForChild("FormatUtil"))
local SafeWait = require(Util:WaitForChild("SafeWait"))
local Trove = require(Util:WaitForChild("Trove"))
local UIConfig = require(Config:WaitForChild("UIConfig"))

local UIController = {}
UIController.__index = UIController

local INVALID_ASSET_ID = "rbxassetid://0"
local MIN_FADE_RANGE = 0.01
local AUTO_ROLL_DELAY_SECONDS = 0.05
local LOCKED_INDEX_TEXT_TRANSPARENCY = 0
local LOCKED_INDEX_TEXT_STROKE_TRANSPARENCY = 0.25
local LOCKED_INDEX_TEXT_ZINDEX_OFFSET = 2
-- Runtime-generated rolling frames use this name pattern and are cleaned on setup.
local RUNTIME_ROLLING_SLOT_NAME_PATTERN = "^RollingSlot%d+$"
local INDEX_ZONE_BY_BUTTON = {
    Btn01 = "Normal",
    Btn02 = "Gold",
    Btn03 = "Diamond",
    Btn04 = "Candy",
    Btn05 = "Vulcan",
    Btn06 = "Rainbow",
}
local INVENTORY_SELECTION_COLOR = Color3.fromRGB(110, 224, 122)
local READY_BUTTON_EQUIP_COLOR = Color3.fromRGB(110, 224, 122)
local READY_BUTTON_UNEQUIP_COLOR = Color3.fromRGB(232, 90, 90)

local function setText(instance, text)
    if instance and instance:IsA("TextLabel") then
        instance.Text = text
    end
end

local function setImage(instance, image)
    if instance and instance:IsA("ImageLabel") then
        instance.Image = image
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

local function findFirstDescendantByName(root, name, className)
    if not root then
        return nil
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant.Name == name and (className == nil or descendant:IsA(className)) then
            return descendant
        end
    end

    return nil
end

local function findFirstDescendantByNameInsensitive(root, names, className)
    if not root then
        return nil
    end

    local lookup = {}
    for _, candidate in ipairs(names) do
        if type(candidate) == "string" and candidate ~= "" then
            lookup[string.lower(candidate)] = true
        end
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if (className == nil or descendant:IsA(className)) and lookup[string.lower(descendant.Name)] then
            return descendant
        end
    end

    return nil
end

local function findFirstSlotTemplate(container)
    if not container then
        return nil
    end

    for _, child in ipairs(container:GetChildren()) do
        if (child:IsA("Frame") or child:IsA("TextButton") or child:IsA("ImageButton")) and child.Name:match("^Slot%d+$") then
            return child
        end
    end

    return nil
end

local function findListSectionTemplate(root, excludedContainer)
    if not root then
        return nil, nil
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant ~= excludedContainer and (descendant:IsA("Frame") or descendant:IsA("ScrollingFrame")) then
            local hasListLayout = descendant:FindFirstChildOfClass("UIListLayout") ~= nil
            local template = findFirstSlotTemplate(descendant)
            if hasListLayout and template then
                return descendant, template
            end
        end
    end

    return nil, nil
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

local function isPanelVisible(panel)
    if panel:IsA("LayerCollector") then
        return panel.Enabled
    end
    if panel:IsA("GuiObject") then
        return panel.Visible
    end
    return false
end

local function setPanelVisible(panel, isVisible)
    if panel:IsA("LayerCollector") then
        panel.Enabled = isVisible
    elseif panel:IsA("GuiObject") then
        panel.Visible = isVisible
    end
end

local function blendTransparency(baseTransparency, alpha)
    return math.clamp(baseTransparency + ((1 - baseTransparency) * alpha), 0, 1)
end

local function getRarityOrder(rarityName)
    local rarity = rarityName and Rarities[rarityName]
    if rarity and type(rarity.Order) == "number" then
        return rarity.Order
    end
    return math.huge
end

local function getItemDisplayName(item)
    if type(item) ~= "table" then
        return ""
    end
    return tostring(item.DisplayName or item.Id or item.Name or "")
end

local function formatOdds(displayOdds)
    -- Normalize configured odds text for the rolling label, e.g. "1 in 100" -> "1/100".
    if type(displayOdds) ~= "string" or displayOdds == "" then
        return "1/?"
    end

    local trailingValue = displayOdds:match("^1%s*[Ii][Nn]%s*(.+)$")
    if trailingValue then
        return string.format("1/%s", trailingValue:gsub("%s+", ""))
    end

    local normalized = displayOdds:gsub("%s+", "")
    if normalized:match("^1/.+$") then
        return normalized
    end

    return displayOdds
end

local function getRarityColor(rarityName)
    local rarity = rarityName and Rarities[rarityName]
    return rarity and rarity.Color or Color3.fromRGB(255, 255, 255)
end

local function formatSignedStat(value)
    local amount = math.floor(tonumber(value) or 0)
    if amount > 0 then
        return string.format("+%s", FormatUtil.Number(amount))
    end
    return FormatUtil.Number(amount)
end


function UIController.new(remotes, notifier)
    local self = setmetatable({}, UIController)
    self._trove = Trove.new()
    self._remotes = remotes
    self._notifier = notifier
    self._snapshot = nil
    self._rollBusy = false
    self._autoRollThread = nil
    self._autoRollEnabled = false
    self._autoRollThreadToken = 0
    self._autoRollLoopRunning = false
    self._random = Random.new()
    self._player = Players.LocalPlayer
    self._playerGui = self._player:WaitForChild("PlayerGui")
    self._ui = SafeWait.WaitForChild(self._playerGui, UIConfig.RootGui, 15)
    self._panels = {}
    self._rollTable = {}
    self._rollTableById = {}
    self._rewardsPanelOriginalPosition = nil
    self._rewardsPanelOriginalAnchorPoint = nil
    self._rollingGui = nil
    self._rollingMain = nil
    self._rollingSlots = {}
    self._rollingSlotRefs = {}
    self._rollingSlotScales = {}
    self._rollingTransparencyBaseline = {}
    self._rollingBaseFinalPosition = UIConfig.Rolling.FinalPosition
    self._rollingBaseAnchorPoint = UIConfig.Rolling.AnchorPoint
    self._rollingFinalPosition = self._rollingBaseFinalPosition
    self._rollingAnchorPoint = self._rollingBaseAnchorPoint
    self._rollingScaleMultiplier = 1
    self._rollingSpacingMultiplier = 1
    self._rollingIsHorizontal = false
    self._rollAnimationToken = 0
    self._preloadedRollImages = {}
    self._rollButton = nil
    self._rollButtonTransparencyBaseline = nil
    self._indexSelectedZone = "Normal"
    self._indexTemplateButtons = {}
    self._indexTemplatesByRarity = {}
    self._indexFallbackTemplate = nil
    self._inventoryTemplate = nil
    self._inventorySelectedItemId = nil
    self._inventoryRefs = nil
    self._currencyRefs = nil

    if self._ui then
        for _, panelName in ipairs(UIConfig.Panels) do
            self._panels[panelName] = self:_resolvePanel(panelName)
        end
        self:_bindNavigation()
        self:_bindIndexSidebar()
        self:_bindActions()
        self:_bindCloseButtons()
        self:_bindRewardButtons()
        self:_captureRewardsPanelLayout()
        self:_setupInventoryUI()
        self:_setupCurrencyUI()
    end

    self:_setupRollingUI()
    return self
end



function UIController:_getCenterSlotIndex()
    local configured = math.round(AnimationConfig.RollCenterSlot or 1)
    local slotCount = AnimationConfig.RollSlotCount
    local clamped = math.clamp(configured, 1, math.max(slotCount, 1))
    return clamped
end

function UIController:_clearStaleRollingSlots()
    if not self._rollingMain or not self._rollingMain.Parent then
        return
    end

    for _, child in ipairs(self._rollingMain.Parent:GetChildren()) do
        if child ~= self._rollingMain
            and child:IsA("GuiObject")
            and child.Name:match(RUNTIME_ROLLING_SLOT_NAME_PATTERN)
            and child:GetAttribute("RuntimeRollingSlot") == true
        then
            child:Destroy()
        end
    end
end

function UIController:_rollItemsMatch(leftItem, rightItem)
    local leftResolved = self:_resolveRollItem(leftItem) or leftItem
    local rightResolved = self:_resolveRollItem(rightItem) or rightItem
    if type(leftResolved) ~= "table" or type(rightResolved) ~= "table" then
        return false
    end

    local leftId = leftResolved.Id
    local rightId = rightResolved.Id
    if leftId ~= nil and rightId ~= nil then
        return leftId == rightId
    end

    return false
end

function UIController:Destroy()
    self._rollBusy = false
    self._autoRollEnabled = false
    self._autoRollThreadToken += 1
    self._rollAnimationToken += 1
    self:_resetRollingUI("controller destroy")
    self._trove:Destroy()
end

function UIController:_openPanel(panelName)
    local targetPanel = self._panels[panelName]
    if not targetPanel then
        warn(string.format("[UI] Missing panel '%s' for navigation.", panelName))
        return
    end

    local isCurrentlyOpen = isPanelVisible(targetPanel)
    for name, panel in pairs(self._panels) do
        if panel and (name ~= "LeftSide" and name ~= "LeftBottomBar") then
            local shouldBeVisible = not isCurrentlyOpen and name == panelName
            setPanelVisible(panel, shouldBeVisible)
        end
    end
end

function UIController:_resolvePanel(panelName)
    local panel = self._ui and self._ui:FindFirstChild(panelName)
    if panel then
        return panel
    end

    local externalPath = UIConfig.ExternalPanels and UIConfig.ExternalPanels[panelName]
    if externalPath then
        return SafeWait.FindPath(self._playerGui, externalPath, true)
    end

    return self._ui and SafeWait.WaitForChild(self._ui, panelName, 5)
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

function UIController:_bindIndexSidebar()
    local indexPanel = self._panels.Index
    if not indexPanel then
        return
    end

    local sidebar = SafeWait.FindPath(indexPanel, { "Sidebar" })
    if not sidebar then
        return
    end

    for buttonName, zoneName in pairs(INDEX_ZONE_BY_BUTTON) do
        local button = SafeWait.FindPath(sidebar, { buttonName }, true)
        if button and button:IsA("GuiButton") then
            self._trove:Connect(button.Activated, function()
                self._indexSelectedZone = zoneName
                if self._snapshot then
                    self:_updateIndex(self._snapshot)
                end
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
        self._rollButton = rollButton
        self._rollButtonTransparencyBaseline = self:_captureTransparencyBaseline(rollButton)
        self:_setRollButtonBusyVisual(self._rollBusy)
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
        local panel = self._panels[panelName]
        local button = self._ui and SafeWait.FindPath(self._ui, path, true)
        if not button and panel then
            button = SafeWait.FindPath(panel, path, true)
        end
        if button and button:IsA("GuiButton") then
            local panelToClose = panel
            self._trove:Connect(button.Activated, function()
                if panelToClose then
                    setPanelVisible(panelToClose, false)
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

function UIController:_ensureInventorySlotStroke(slot)
    local stroke = slot:FindFirstChild("SelectedStroke")
    if not stroke or not stroke:IsA("UIStroke") then
        stroke = Instance.new("UIStroke")
        stroke.Name = "SelectedStroke"
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Thickness = 2
        stroke.Transparency = 1
        stroke.Parent = slot
    end

    local corner = slot:FindFirstChild("SelectedCorner")
    if not corner or not corner:IsA("UICorner") then
        corner = Instance.new("UICorner")
        corner.Name = "SelectedCorner"
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = slot
    end

    stroke.Color = INVENTORY_SELECTION_COLOR
    return stroke
end

function UIController:_updateReadyButtonStyle(isEquipped)
    local refs = self._inventoryRefs
    if not refs then
        return
    end

    local actionColor = isEquipped and READY_BUTTON_UNEQUIP_COLOR or READY_BUTTON_EQUIP_COLOR
    if refs.ReadyButton and refs.ReadyButton:IsA("GuiObject") then
        refs.ReadyButton.BackgroundColor3 = actionColor
    end
    if refs.ReadyButtonBG and refs.ReadyButtonBG:IsA("GuiObject") then
        refs.ReadyButtonBG.BackgroundColor3 = actionColor
    end

    if refs.ReadyButton then
        for _, descendant in ipairs(refs.ReadyButton:GetDescendants()) do
            if descendant:IsA("TextLabel") then
                descendant.TextStrokeColor3 = actionColor
            elseif descendant:IsA("UIStroke") then
                descendant.Color = actionColor
            end
        end
    end
end

function UIController:_setupInventoryUI()
    local inventoryPanel = self._panels.InvUI
    if not inventoryPanel then
        return
    end

    local slotsFrame = SafeWait.FindPath(inventoryPanel, { "HolderFrame", "Inv", "Content", "Slots1" }, true)
    local slotTemplate = slotsFrame and SafeWait.FindPath(slotsFrame, { "Slot1" }, true)
    if slotTemplate and (slotTemplate:IsA("TextButton") or slotTemplate:IsA("ImageButton")) then
        self._inventoryTemplate = slotTemplate
        self._inventoryTemplate.Visible = false
    end

    local equippedFrame, equippedTemplate = findListSectionTemplate(inventoryPanel, slotsFrame)
    if equippedTemplate and (equippedTemplate:IsA("Frame") or equippedTemplate:IsA("TextButton") or equippedTemplate:IsA("ImageButton")) then
        self._equippedTemplate = equippedTemplate
        self._equippedTemplate.Visible = false
    end

    self._inventoryRefs = {
        Panel = inventoryPanel,
        Slots = slotsFrame,
        EquippedSection = equippedFrame,
        YouLabel = SafeWait.FindPath(inventoryPanel, { "HolderFrame", "Inv", "You" }, true),
        EquipBest = SafeWait.FindPath(inventoryPanel, { "HolderFrame", "Inv", "EquipBest", "EquipBest" }, true),
        ReadyButton = SafeWait.FindPath(inventoryPanel, { "HolderFrame", "Frame", "ReadyButton" }, true),
        ReadyLabel = SafeWait.FindPath(inventoryPanel, { "HolderFrame", "Frame", "ReadyButton", "Equip" }, true),
        ReadyButtonBG = SafeWait.FindPath(inventoryPanel, { "HolderFrame", "Frame", "ReadyButton", "BG" }, true)
            or findFirstDescendantByName(SafeWait.FindPath(inventoryPanel, { "HolderFrame", "Frame", "ReadyButton" }, true), "BG", "GuiObject"),
        DetailItem = SafeWait.FindPath(inventoryPanel, { "HolderFrame", "Frame", "Item" }, true),
        DetailName = SafeWait.FindPath(inventoryPanel, { "HolderFrame", "Frame", "Label02", "ItemName" }, true),
        DetailRarity = SafeWait.FindPath(inventoryPanel, { "HolderFrame", "Frame", "Label01", "Rearity" }, true)
            or SafeWait.FindPath(inventoryPanel, { "HolderFrame", "Frame", "Label01", "Rarity" }, true),
        DetailAmount = SafeWait.FindPath(inventoryPanel, { "HolderFrame", "Frame", "AmountText" }, true),
        DetailDamage = SafeWait.FindPath(inventoryPanel, { "HolderFrame", "Frame", "Information", "DamageFrame", "Damage" }, true),
        DetailHealth = SafeWait.FindPath(inventoryPanel, { "HolderFrame", "Frame", "Information", "HealthFrame", "Health" }, true),
    }

    local equipBestButton = self._inventoryRefs.EquipBest
    if equipBestButton and equipBestButton:IsA("GuiButton") then
        self._trove:Connect(equipBestButton.Activated, function()
            local result = self:_invoke("RequestEquipBestItem")
            if result and not result.Success and result.Message then
                self._notifier:Show({ Kind = "Warning", Message = result.Message })
            end
        end)
    end

    local readyButton = self._inventoryRefs.ReadyButton
    if readyButton and readyButton:IsA("GuiButton") then
        self._trove:Connect(readyButton.Activated, function()
            if not self._inventorySelectedItemId then
                return
            end
            local result = self:_invoke("RequestEquipItem", self._inventorySelectedItemId)
            if result and not result.Success and result.Message then
                self._notifier:Show({ Kind = "Warning", Message = result.Message })
            end
        end)
    end
end

function UIController:_setupCurrencyUI()
    local roots = { self._ui, self._playerGui }
    local cashContainer = nil
    local shardContainer = nil

    for _, root in ipairs(roots) do
        if not cashContainer then
            cashContainer = findFirstDescendantByNameInsensitive(root, { "CashGui", "CashUI", "Cash" }, "GuiObject")
        end
        if not shardContainer then
            shardContainer = findFirstDescendantByNameInsensitive(root, { "ShardGui", "ShardsGui", "ShardUI", "Shard", "Shards" }, "GuiObject")
        end
    end

    local function resolveValueLabel(container)
        if not container then
            return nil
        end

        local label = findLabel(container, {
            { "Label01", "Main" },
            { "Label02", "Main" },
            { "Amount" },
            { "Value" },
            { "Text" },
            { "Main" },
        })
        if label then
            return label
        end

        return findFirstDescendantByNameInsensitive(container, { "Main", "Amount", "Value", "Text", "Label01", "Label02" }, "TextLabel")
    end

    self._currencyRefs = {
        CashLabel = resolveValueLabel(cashContainer),
        ShardLabel = resolveValueLabel(shardContainer),
    }
end

function UIController:_updateInventoryDetail(entry, equippedItemLookup)
    local refs = self._inventoryRefs
    if not refs then
        return
    end

    local item = entry and entry.Item
    local isEquipped = entry and equippedItemLookup and equippedItemLookup[entry.Id] == true
    local availableCount = entry and entry.Count or 0

    setImage(refs.DetailItem, item and item.Icon or "")
    setText(refs.DetailName, item and getItemDisplayName(item) or "No Item")
    setText(refs.DetailRarity, item and tostring(item.Rarity or "") or "")
    setText(refs.DetailAmount, string.format("x%s", FormatUtil.Number(availableCount)))
    setText(refs.DetailDamage, formatSignedStat(item and (item.Damage or item.RewardCoins or 0) or 0))
    setText(refs.DetailHealth, formatSignedStat(item and (item.Health or item.RewardHealth or 0) or 0))
    if refs.DetailRarity and refs.DetailRarity:IsA("TextLabel") then
        refs.DetailRarity.TextColor3 = getRarityColor(item and item.Rarity or nil)
    end

    if refs.ReadyLabel and refs.ReadyLabel:IsA("TextLabel") then
        if not entry then
            refs.ReadyLabel.Text = "Equip"
        elseif isEquipped then
            refs.ReadyLabel.Text = "Unequip"
        else
            refs.ReadyLabel.Text = "Equip"
        end
    end

    self:_updateReadyButtonStyle(isEquipped == true)
end

function UIController:_updateInventory(snapshot)
    local refs = self._inventoryRefs
    local slotsFrame = refs and refs.Slots
    local slotTemplate = self._inventoryTemplate
    if not refs or not slotsFrame or not slotTemplate then
        return
    end

    local equippedItemIds = snapshot.EquippedItemIds
    if type(equippedItemIds) ~= "table" then
        equippedItemIds = {}
        if type(snapshot.EquippedItemId) == "string" and snapshot.EquippedItemId ~= "" then
            table.insert(equippedItemIds, snapshot.EquippedItemId)
        end
    end
    local equippedItemLookup = {}
    local equippedItemCounts = {}
    for _, equippedId in ipairs(equippedItemIds) do
        equippedItemLookup[equippedId] = true
        equippedItemCounts[equippedId] = (equippedItemCounts[equippedId] or 0) + 1
    end
    local inventoryState = snapshot.Inventory or {}
    local entriesById = {}
    for itemId, amount in pairs(inventoryState) do
        if type(itemId) == "string" and type(amount) == "number" and amount > 0 then
            local resolvedItem = self:_resolveRollItem({ Id = itemId })
            if resolvedItem then
                entriesById[itemId] = {
                    Id = itemId,
                    Count = amount,
                    EquippedCount = equippedItemCounts[itemId] or 0,
                    Item = resolvedItem,
                }
            end
        end
    end

    for itemId, equippedCount in pairs(equippedItemCounts) do
        if not entriesById[itemId] then
            local resolvedItem = self:_resolveRollItem({ Id = itemId })
            if resolvedItem then
                entriesById[itemId] = {
                    Id = itemId,
                    Count = 0,
                    EquippedCount = equippedCount,
                    Item = resolvedItem,
                }
            end
        elseif entriesById[itemId] then
            entriesById[itemId].EquippedCount = equippedCount
        end
    end

    local function compareEntries(left, right)
        local leftOrder = getRarityOrder(left.Item and left.Item.Rarity)
        local rightOrder = getRarityOrder(right.Item and right.Item.Rarity)
        if leftOrder ~= rightOrder then
            return leftOrder > rightOrder
        end
        if left.Count ~= right.Count then
            return left.Count > right.Count
        end
        return getItemDisplayName(left.Item) < getItemDisplayName(right.Item)
    end

    local entries = {}
    for _, entry in pairs(entriesById) do
        if entry.Count > 0 then
            table.insert(entries, entry)
        end
    end
    table.sort(entries, compareEntries)

    local equippedEntries = {}
    for _, entry in pairs(entriesById) do
        for slotIndex = 1, entry.EquippedCount or 0 do
            table.insert(equippedEntries, {
                Id = entry.Id,
                Count = entry.Count,
                EquippedCount = entry.EquippedCount,
                Item = entry.Item,
                SlotIndex = slotIndex,
            })
        end
    end
    table.sort(equippedEntries, compareEntries)

    local runtimeSlotsToDestroy = {}
    for _, child in ipairs(slotsFrame:GetChildren()) do
        if (child:IsA("TextButton") or child:IsA("ImageButton")) and child:GetAttribute("RuntimeInventorySlot") == true then
            table.insert(runtimeSlotsToDestroy, child)
        end
    end
    for _, runtimeSlot in ipairs(runtimeSlotsToDestroy) do
        runtimeSlot:Destroy()
    end

    local equippedSection = refs.EquippedSection
    local equippedTemplate = self._equippedTemplate
    if equippedSection and equippedTemplate then
        local runtimeEquippedToDestroy = {}
        for _, child in ipairs(equippedSection:GetChildren()) do
            if (child:IsA("Frame") or child:IsA("TextButton") or child:IsA("ImageButton")) and child:GetAttribute("RuntimeEquippedSlot") == true then
                table.insert(runtimeEquippedToDestroy, child)
            end
        end
        for _, runtimeSlot in ipairs(runtimeEquippedToDestroy) do
            runtimeSlot:Destroy()
        end
    end

    local selectedId = self._inventorySelectedItemId
    local selectedEntry = nil
    local firstEntry = entries[1]
    local firstEquippedEntry = equippedEntries[1]
    if not selectedId then
        if firstEntry then
            selectedId = firstEntry.Id
        elseif firstEquippedEntry then
            selectedId = firstEquippedEntry.Id
        end
    end

    for index, entry in ipairs(entries) do
        local slot = slotTemplate:Clone()
        slot.Name = string.format("RuntimeInventorySlot_%02d", index)
        slot:SetAttribute("RuntimeInventorySlot", true)
        slot.Visible = true
        slot.LayoutOrder = index
        slot.Parent = slotsFrame

        local nameLabel = findLabel(slot, {
            { "Label02", "ItemName" },
            { "Label02", "Main" },
        })
        local amountLabel = findLabel(slot, {
            { "AmountText" },
            { "Amount" },
            { "Stock" },
        })
        local rarityLabel = findLabel(slot, {
            { "Label01", "Rearity" },
            { "Label01", "Rarity" },
            { "Label01", "Main" },
        })
        local itemImage = SafeWait.FindPath(slot, { "Item" }, true)
        setText(nameLabel, getItemDisplayName(entry.Item))
        setText(amountLabel, string.format("x%s", FormatUtil.Number(entry.Count)))
        setText(rarityLabel, tostring(entry.Item.Rarity or ""))
        setImage(itemImage, tostring(entry.Item.Icon or ""))

        if rarityLabel and rarityLabel:IsA("TextLabel") then
            rarityLabel.TextColor3 = getRarityColor(entry.Item.Rarity)
        end

        local equippedStroke = self:_ensureInventorySlotStroke(slot)
        equippedStroke.Transparency = entry.Id == selectedId and 0 or 1

        self._trove:Connect(slot.Activated, function()
            self._inventorySelectedItemId = entry.Id
            if self._snapshot then
                self:_updateInventory(self._snapshot)
            else
                self:_updateInventoryDetail(entry, equippedItemLookup)
            end
        end)

        if entry.Id == selectedId then
            selectedEntry = entry
        end
    end

    if equippedSection and equippedTemplate then
        for index, entry in ipairs(equippedEntries) do
            local slot = equippedTemplate:Clone()
            slot.Name = string.format("RuntimeEquippedSlot_%02d", index)
            slot:SetAttribute("RuntimeEquippedSlot", true)
            slot.Visible = true
            slot.LayoutOrder = index
            slot.Parent = equippedSection

            local nameLabel = findLabel(slot, {
                { "Label02", "ItemName" },
                { "Label02", "Main" },
            })
            local amountLabel = findLabel(slot, {
                { "AmountText" },
                { "Amount" },
                { "Stock" },
            })
            local rarityLabel = findLabel(slot, {
                { "Label01", "Rearity" },
                { "Label01", "Rarity" },
                { "Label01", "Main" },
            })
            local itemImage = SafeWait.FindPath(slot, { "Item" }, true)
            setText(nameLabel, getItemDisplayName(entry.Item))
            setText(amountLabel, "")
            setText(rarityLabel, tostring(entry.Item.Rarity or ""))
            setImage(itemImage, tostring(entry.Item.Icon or ""))

            if rarityLabel and rarityLabel:IsA("TextLabel") then
                rarityLabel.TextColor3 = getRarityColor(entry.Item.Rarity)
            end

            local equippedStroke = self:_ensureInventorySlotStroke(slot)
            equippedStroke.Transparency = 1

            if slot:IsA("GuiButton") then
                self._trove:Connect(slot.Activated, function()
                    self._inventorySelectedItemId = entry.Id
                    if self._snapshot then
                        self:_updateInventory(self._snapshot)
                    else
                        self:_updateInventoryDetail(entry, equippedItemLookup)
                    end
                end)
            elseif slot:IsA("GuiObject") then
                self._trove:Connect(slot.InputBegan, function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        self._inventorySelectedItemId = entry.Id
                        if self._snapshot then
                            self:_updateInventory(self._snapshot)
                        else
                            self:_updateInventoryDetail(entry, equippedItemLookup)
                        end
                    end
                end)
            end

            if not selectedEntry and entry.Id == selectedId then
                selectedEntry = entriesById[entry.Id] or entry
            end
        end
    end

    self._inventorySelectedItemId = selectedEntry and selectedEntry.Id or nil
    self:_updateInventoryDetail(selectedEntry, equippedItemLookup)

    if refs.YouLabel and refs.YouLabel:IsA("TextLabel") then
        refs.YouLabel.Text = "Backpack"
    end
end

function UIController:RequestRoll(source)
    local rollSource = source or "Manual"
    if self._rollBusy then
        return
    end

    self:_setRollBusy(true)

    local success, err = xpcall(function()
        local result = self:_invoke("RollRequest")
        if not result then
            self:_resetRollingUI("roll failed")
            return
        end

        if not result.Success then
            if result.Message then
                self._notifier:Show({ Kind = "Warning", Message = result.Message })
            end
            self:_resetRollingUI("roll failed")
            return
        end

        if not result.Result or not result.Result.Item then
            self:_resetRollingUI("missing result item")
            return
        end

        self:PlayRollResult(result.Result)
    end, debug.traceback)

    if not success then
        self:_resetRollingUI("roll runtime error")
    end

    self:_setRollBusy(false)
    if self._snapshot then
        self:_updateAutoRollState(self._snapshot)
    end
end

function UIController:_captureTransparencyBaseline(root)
    local baseline = {} :: {[Instance]: {[string]: number}}

    local function capture(instance)
        local entry = {} :: {[string]: number}
        if instance:IsA("GuiObject") then
            entry.BackgroundTransparency = instance.BackgroundTransparency
        end
        if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
            entry.ImageTransparency = instance.ImageTransparency
        end
        if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
            entry.TextTransparency = instance.TextTransparency
            entry.TextStrokeTransparency = instance.TextStrokeTransparency
        end
        if instance:IsA("UIStroke") then
            entry.Transparency = instance.Transparency
        end
        if next(entry) then
            baseline[instance] = entry
        end
    end

    capture(root)
    for _, descendant in ipairs(root:GetDescendants()) do
        capture(descendant)
    end

    return baseline
end

function UIController:_applyTransparencyBaseline(baseline, alpha)
    if not baseline then
        return
    end

    for instance, values in pairs(baseline) do
        if instance.Parent then
            if instance:IsA("GuiObject") and values.BackgroundTransparency ~= nil then
                instance.BackgroundTransparency = blendTransparency(values.BackgroundTransparency, alpha)
            end
            if (instance:IsA("ImageLabel") or instance:IsA("ImageButton")) and values.ImageTransparency ~= nil then
                instance.ImageTransparency = blendTransparency(values.ImageTransparency, alpha)
            end
            if (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")) and values.TextTransparency ~= nil then
                instance.TextTransparency = blendTransparency(values.TextTransparency, alpha)
                instance.TextStrokeTransparency = blendTransparency(values.TextStrokeTransparency or 1, alpha)
            end
            if instance:IsA("UIStroke") and values.Transparency ~= nil then
                instance.Transparency = blendTransparency(values.Transparency, alpha)
            end
        end
    end
end

function UIController:_applyRollingTransparency(slot, alpha)
    self:_applyTransparencyBaseline(self._rollingTransparencyBaseline[slot], alpha)
end

function UIController:_setRollButtonBusyVisual(isBusy)
    local rollButton = self._rollButton
    if not rollButton then
        return
    end

    rollButton.Active = not isBusy
    rollButton.AutoButtonColor = not isBusy
    self:_applyTransparencyBaseline(self._rollButtonTransparencyBaseline, isBusy and 0.35 or 0)
end

function UIController:_setRollBusy(isBusy)
    if self._rollBusy == isBusy then
        return
    end
    self._rollBusy = isBusy
    self:_setRollButtonBusyVisual(isBusy)
end

function UIController:_ensureIndexTemplates(content)
    if self._indexFallbackTemplate then
        return
    end

    self._indexTemplateButtons = getOrderedButtons(content)
    for _, template in ipairs(self._indexTemplateButtons) do
        template.Visible = false
        template.AutoButtonColor = false
        local rarityKey = string.lower(template.Name)
        self._indexTemplatesByRarity[rarityKey] = template
        if not self._indexFallbackTemplate then
            self._indexFallbackTemplate = template
        end
    end
end

function UIController:_hideRollingSlots()
    for _, slot in ipairs(self._rollingSlots) do
        slot.Visible = false
        local uiScale = self._rollingSlotScales[slot]
        if uiScale then
            uiScale.Scale = self._rollingScaleMultiplier
        end
    end
end

function UIController:_resetRollingUI(reason)
    self:_hideRollingSlots()

    for _, slot in ipairs(self._rollingSlots) do
        slot.AnchorPoint = self._rollingAnchorPoint
        slot.Position = self._rollingFinalPosition
        self:_applyRollingTransparency(slot, 0)
    end
end

function UIController:_setupRollingUI()
    local rollingGui = SafeWait.WaitForChild(self._playerGui, UIConfig.Rolling.ScreenGuiName, 15)
    if not rollingGui then
        return
    end

    self._rollingGui = rollingGui
    local rollingMain = SafeWait.FindPath(rollingGui, UIConfig.Rolling.MainPath)
    if not rollingMain or not rollingMain:IsA("GuiObject") then
        warn(string.format("[UI] Missing rolling main at %s.%s", rollingGui:GetFullName(), table.concat(UIConfig.Rolling.MainPath, ".")))
        return
    end

    self._rollingMain = rollingMain
    self:_clearStaleRollingSlots()
    self._rollingMain.AnchorPoint = self._rollingAnchorPoint
    self._rollingMain.Position = self._rollingFinalPosition
    self._rollingMain.Visible = false
    setPanelVisible(rollingGui, true)
    self:_ensureRollingSlots()
end

function UIController:_ensureRollingSlots()
    if not self._rollingMain then
        return false
    end

    if #self._rollingSlots > 0 then
        return true
    end

    for index = 1, AnimationConfig.RollSlotCount do
        local slot = index == 1 and self._rollingMain or self._rollingMain:Clone()
        slot.Name = string.format("RollingSlot%02d", index)
        slot:SetAttribute("RuntimeRollingSlot", index > 1)
        slot.AnchorPoint = self._rollingAnchorPoint
        slot.Position = self._rollingFinalPosition
        slot.Visible = false
        if index > 1 then
            slot.Parent = self._rollingMain.Parent
        end

        local slotScale = slot:FindFirstChildOfClass("UIScale")
        if not slotScale then
            slotScale = Instance.new("UIScale")
            slotScale.Parent = slot
        end
        slotScale.Scale = 1

        self._rollingSlots[index] = slot
        self._rollingSlotScales[slot] = slotScale
        self._rollingSlotRefs[slot] = {
            Image = SafeWait.FindPath(slot, UIConfig.Rolling.ImagePath, true),
            PetName = SafeWait.FindPath(slot, UIConfig.Rolling.PetNamePath, true),
            Rarity = SafeWait.FindPath(slot, UIConfig.Rolling.RarityPath, true),
            RarityStroke = SafeWait.FindPath(slot, UIConfig.Rolling.RarityStrokePath, true),
        }
        self._rollingTransparencyBaseline[slot] = self:_captureTransparencyBaseline(slot)
    end

    return true
end

function UIController:_refreshRollLookup()
    self._rollTableById = {}
    for _, item in ipairs(self._rollTable) do
        if item and item.Id then
            self._rollTableById[item.Id] = item
        end
    end
end

function UIController:_resolveRollItem(item)
    if type(item) ~= "table" then
        return item
    end

    local mapped = item.Id and self._rollTableById[item.Id]
    if not mapped then
        return item
    end

    local resolved = table.clone(mapped)
    for key, value in pairs(item) do
        resolved[key] = value
    end

    local resolvedIcon = resolved.Icon
    if type(resolvedIcon) ~= "string" or resolvedIcon == "" or resolvedIcon == INVALID_ASSET_ID then
        resolved.Icon = mapped.Icon
    end

    if not resolved.DisplayOdds or resolved.DisplayOdds == "" then
        resolved.DisplayOdds = mapped.DisplayOdds
    end
    if not resolved.DisplayName or resolved.DisplayName == "" then
        resolved.DisplayName = mapped.DisplayName
    end
    if not resolved.Rarity or resolved.Rarity == "" then
        resolved.Rarity = mapped.Rarity
    end

    return resolved
end

function UIController:_getRollingSlotSpacingPixels()
    local baseSlot = self._rollingSlots[1] or self._rollingMain
    if not baseSlot or not baseSlot:IsA("GuiObject") then
        return 120 + AnimationConfig.RollSlotPaddingPixels
    end

    if self._rollingIsHorizontal then
        local slotWidth = baseSlot.AbsoluteSize.X
        if slotWidth <= 0 then
            local viewportWidth = self._rollingGui and self._rollingGui.AbsoluteSize.X or 0
            slotWidth = (baseSlot.Size.X.Scale * viewportWidth) + baseSlot.Size.X.Offset
        end
        if slotWidth <= 0 then
            slotWidth = 120
        end
        return (slotWidth + AnimationConfig.RollSlotPaddingPixels) * self._rollingSpacingMultiplier
    end

    local slotHeight = baseSlot.AbsoluteSize.Y
    if slotHeight <= 0 then
        local viewportHeight = self._rollingGui and self._rollingGui.AbsoluteSize.Y or 0
        slotHeight = (baseSlot.Size.Y.Scale * viewportHeight) + baseSlot.Size.Y.Offset
    end
    if slotHeight <= 0 then
        slotHeight = 120
    end

    return (slotHeight + AnimationConfig.RollSlotPaddingPixels) * self._rollingSpacingMultiplier
end

function UIController:_getAutoRollMaxYOffsetPixels()
    if not self._autoRollEnabled then
        return math.huge
    end

    if self._rollingIsHorizontal then
        return math.huge
    end

    local maxYScale = UIConfig.AutoRoll and UIConfig.AutoRoll.MaxAnimationYScale
    if type(maxYScale) ~= "number" then
        return math.huge
    end

    local rollingGui = self._rollingGui
    if not rollingGui then
        return math.huge
    end

    local viewportHeight = rollingGui.AbsoluteSize.Y
    if viewportHeight <= 0 then
        return math.huge
    end

    local basePositionPixels = (self._rollingFinalPosition.Y.Scale * viewportHeight) + self._rollingFinalPosition.Y.Offset
    local maxPositionPixels = maxYScale * viewportHeight
    return math.max(0, maxPositionPixels - basePositionPixels)
end

function UIController:_setRollingSlotContent(slot, item)
    local refs = self._rollingSlotRefs[slot]
    if not refs then
        return
    end

    local resolvedItem = self:_resolveRollItem(item)
    setImage(refs.Image, resolvedItem and resolvedItem.Icon or "")
    setText(refs.PetName, resolvedItem and resolvedItem.DisplayName or "")
    setText(refs.Rarity, formatOdds(resolvedItem and resolvedItem.DisplayOdds or ""))

    local rarityStroke = refs.RarityStroke
    if rarityStroke and rarityStroke:IsA("UIStroke") then
        rarityStroke.Color = getRarityColor(resolvedItem and resolvedItem.Rarity or nil)
    end
end

function UIController:_setRollingSlotState(slot, item, positionOffset, alpha)
    slot.AnchorPoint = self._rollingAnchorPoint
    if self._rollingIsHorizontal then
        slot.Position = UDim2.new(
            self._rollingFinalPosition.X.Scale,
            self._rollingFinalPosition.X.Offset + math.floor(positionOffset),
            self._rollingFinalPosition.Y.Scale,
            self._rollingFinalPosition.Y.Offset
        )
    else
        slot.Position = UDim2.new(
            self._rollingFinalPosition.X.Scale,
            self._rollingFinalPosition.X.Offset,
            self._rollingFinalPosition.Y.Scale,
            self._rollingFinalPosition.Y.Offset + math.floor(positionOffset)
        )
    end
    slot.Visible = true
    self:_setRollingSlotContent(slot, item)
    self:_applyRollingTransparency(slot, alpha)

    local uiScale = self._rollingSlotScales[slot]
    if uiScale then
        uiScale.Scale = self._rollingScaleMultiplier
    end
end

function UIController:_playWinningReveal(slot, item, token)
    self:_setRollingSlotState(slot, item, 0, 0)
    slot.Position = self._rollingFinalPosition

    local uiScale = self._rollingSlotScales[slot]
    if uiScale then
        uiScale.Scale = AnimationConfig.RollRevealStartScale * self._rollingScaleMultiplier

        local popTween = TweenService:Create(
            uiScale,
            TweenInfo.new(AnimationConfig.RollRevealPopDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = AnimationConfig.RollRevealPeakScale * self._rollingScaleMultiplier }
        )
        popTween:Play()
        popTween.Completed:Wait()

        if token ~= self._rollAnimationToken then
            return
        end

        local settleTween = TweenService:Create(
            uiScale,
            TweenInfo.new(AnimationConfig.RollRevealSettleDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
            { Scale = self._rollingScaleMultiplier }
        )
        settleTween:Play()
        settleTween.Completed:Wait()
    end

    if token ~= self._rollAnimationToken then
        return
    end

    task.wait(AnimationConfig.ResultHoldSeconds)
    if token ~= self._rollAnimationToken then
        return
    end

    local fadeDuration = AnimationConfig.RollFadeOutDuration
    local fadeOutScaleOffset = self._autoRollEnabled and 0 or AnimationConfig.RollFadeOutOffset
    local endPosition = UDim2.new(
        self._rollingFinalPosition.X.Scale,
        self._rollingFinalPosition.X.Offset,
        self._rollingFinalPosition.Y.Scale + fadeOutScaleOffset,
        self._rollingFinalPosition.Y.Offset
    )
    local movementTween = TweenService:Create(
        slot,
        TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = endPosition }
    )
    movementTween:Play()

    local fadeStartedAt = os.clock()
    while token == self._rollAnimationToken do
        local progress = math.clamp((os.clock() - fadeStartedAt) / fadeDuration, 0, 1)
        self:_applyRollingTransparency(slot, progress)
        if progress >= 1 then
            break
        end
        RunService.Heartbeat:Wait()
    end

    if token ~= self._rollAnimationToken then
        return
    end
    slot.Visible = false
end

function UIController:_buildRollSequence(resultItem, centerSlotIndex)
    local resolvedResultItem = self:_resolveRollItem(resultItem) or resultItem
    local source = {}
    for _, entry in ipairs(self._rollTable) do
        local resolvedEntry = self:_resolveRollItem(entry)
        if resolvedEntry then
            table.insert(source, resolvedEntry)
        end
    end
    if #source == 0 then
        source = { resolvedResultItem }
    end

    local previewSteps = math.max(
        AnimationConfig.RollCycleCount * AnimationConfig.RollCycleMultiplier,
        AnimationConfig.RollSlotCount + AnimationConfig.RollPreviewPadding
    )
    local totalEntries = previewSteps + AnimationConfig.RollSlotCount + 1
    local sequence = {}
    local previousId = nil

    for index = 1, totalEntries do
        local candidateIndex = self._random:NextInteger(1, #source)
        if #source > 1 and previousId ~= nil then
            local chosen = source[candidateIndex]
            if chosen and chosen.Id == previousId then
                local startIndex = candidateIndex
                repeat
                    candidateIndex = (candidateIndex % #source) + 1
                    chosen = source[candidateIndex]
                until candidateIndex == startIndex or (chosen and chosen.Id ~= previousId)
            end
        end
        local candidate = source[candidateIndex]
        sequence[index] = candidate
        previousId = candidate and candidate.Id or nil
    end

    local finalIndex = previewSteps + centerSlotIndex
    sequence[finalIndex] = resolvedResultItem

    -- Also place the reward two steps earlier so the slot arriving at center
    -- during the deceleration phase (slot centerSlotIndex-1) shows the correct pet.
    local arrivingIndex = finalIndex - 2
    if arrivingIndex >= 1 then
        sequence[arrivingIndex] = resolvedResultItem
    end

    return sequence, previewSteps, finalIndex
end

function UIController:_preloadRollImages(items)
    local targets = {}
    for _, item in ipairs(items) do
        local icon = item and item.Icon
        if type(icon) == "string" and icon ~= "" and icon ~= INVALID_ASSET_ID and not self._preloadedRollImages[icon] then
            self._preloadedRollImages[icon] = true
            table.insert(targets, icon)
        end
    end

    if #targets == 0 then
        return
    end

    local success, err = pcall(function()
        ContentProvider:PreloadAsync(targets)
    end)
    if not success then
        warn(string.format("[UI] Failed to preload roll images: %s", tostring(err)))
        for _, icon in ipairs(targets) do
            self._preloadedRollImages[icon] = nil
        end
    end
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

    self:_ensureIndexTemplates(content)

    local runtimeSlotsToDestroy = {}
    for _, child in ipairs(content:GetChildren()) do
        if (child:IsA("TextButton") or child:IsA("ImageButton")) and child:GetAttribute("RuntimeIndexSlot") == true then
            table.insert(runtimeSlotsToDestroy, child)
        end
    end
    for _, runtimeSlot in ipairs(runtimeSlotsToDestroy) do
        runtimeSlot:Destroy()
    end

    local rollTable = snapshot.RollTable or {}
    local filtered = {}
    for _, item in ipairs(rollTable) do
        local zoneName = item and item.Zone
        if item and (self._indexSelectedZone == nil or zoneName == self._indexSelectedZone) then
            table.insert(filtered, item)
        end
    end

    table.sort(filtered, function(a, b)
        local rarityOrderA = getRarityOrder(a.Rarity)
        local rarityOrderB = getRarityOrder(b.Rarity)
        if rarityOrderA == rarityOrderB then
            local nameA = getItemDisplayName(a)
            local nameB = getItemDisplayName(b)
            if nameA == nameB then
                local idA = a.Id
                local idB = b.Id
                if type(idA) == "number" and type(idB) == "number" then
                    return idA < idB
                end
                return tostring(idA or "") < tostring(idB or "")
            end
            return nameA < nameB
        end
        return rarityOrderA < rarityOrderB
    end)

    for index, item in ipairs(filtered) do
        local rarityKey = string.lower(tostring(item.Rarity or ""))
        local template = self._indexTemplatesByRarity[rarityKey] or self._indexFallbackTemplate
        if template then
            local button = template:Clone()
            button.Name = string.format("RuntimeIndexItem_%02d", index)
            button:SetAttribute("RuntimeIndexSlot", true)
            button.LayoutOrder = index
            button.Visible = true
            button.Parent = content

            local nameLabel = findLabel(button, {
                { "Label01", "BrainrotName" },
                { "Label01", "Main" },
            })
            local owned = snapshot.Index and snapshot.Index[item.Id] == true
            setText(nameLabel, owned and getItemDisplayName(item) or "???")
            if nameLabel and not owned then
                nameLabel.TextTransparency = LOCKED_INDEX_TEXT_TRANSPARENCY
                nameLabel.TextStrokeTransparency = LOCKED_INDEX_TEXT_STROKE_TRANSPARENCY
                nameLabel.ZIndex = math.max(nameLabel.ZIndex, button.ZIndex + LOCKED_INDEX_TEXT_ZINDEX_OFFSET)
            end
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

    local currentShards = rebirthState.CurrentShards or rebirthState.CurrentRolls or 0
    local requiredShards = rebirthState.NextRequiredShards or rebirthState.NextRequiredRolls or 0
    local nextBonusShards = rebirthState.NextBonusShards or rebirthState.NextBonusGems or 0
    setText(currentLabel, string.format("Rebirths: %s", FormatUtil.Number(rebirthState.CurrentRebirths or 0)))
    setText(nextLabel, string.format("Next Bonus: %s Shards", FormatUtil.Number(nextBonusShards)))
    setText(progressLabel, string.format("%s / %s shards", FormatUtil.Number(currentShards), FormatUtil.Number(requiredShards)))
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

    local cash = snapshot.Stats.Cash or snapshot.Stats.Coins or 0
    local shards = snapshot.Stats.Shards or snapshot.Stats.Gems or 0
    setText(titleLabel, string.format("Cash: %s", FormatUtil.Number(cash)))
    setText(subLabel, string.format("Shards: %s", FormatUtil.Number(shards)))
    local featuredProduct = DeveloperProducts[UIConfig.FeaturedProductKey]
    if featuredProduct then
        setText(watchButtonLabel, featuredProduct.Label)
    end
end

function UIController:_updateCurrencyUI(snapshot)
    local refs = self._currencyRefs
    if not refs then
        return
    end

    local cash = snapshot.Stats.Cash or snapshot.Stats.Coins or 0
    local shards = snapshot.Stats.Shards or snapshot.Stats.Gems or 0

    if refs.CashLabel and refs.CashLabel:IsA("TextLabel") then
        refs.CashLabel.Text = FormatUtil.Number(cash)
    end

    if refs.ShardLabel and refs.ShardLabel:IsA("TextLabel") then
        refs.ShardLabel.Text = FormatUtil.Number(shards)
    end
end

function UIController:_captureRewardsPanelLayout()
    local rewardsPanel = self._panels.Rewards
    if not rewardsPanel or not rewardsPanel:IsA("GuiObject") then
        return
    end

    self._rewardsPanelOriginalPosition = rewardsPanel.Position
    self._rewardsPanelOriginalAnchorPoint = rewardsPanel.AnchorPoint
end

function UIController:_updateRewardsPanelLayout(snapshot)
    local rewardsPanel = self._panels.Rewards
    if not rewardsPanel or not rewardsPanel:IsA("GuiObject") then
        return
    end

    local isAutoRollEnabled = snapshot.Stats and snapshot.Stats.AutoRoll == true
    if isAutoRollEnabled then
        rewardsPanel.AnchorPoint = UIConfig.AutoRoll.RollPanelTopAnchorPoint
        rewardsPanel.Position = UIConfig.AutoRoll.RollPanelTopPosition
        return
    end

    if self._rewardsPanelOriginalAnchorPoint then
        rewardsPanel.AnchorPoint = self._rewardsPanelOriginalAnchorPoint
    end
    if self._rewardsPanelOriginalPosition then
        rewardsPanel.Position = self._rewardsPanelOriginalPosition
    end
end

function UIController:_updateRollingLayout(snapshot)
    if not self._rollingMain then
        return
    end

    local isAutoRollEnabled = snapshot.Stats and snapshot.Stats.AutoRoll == true
    if isAutoRollEnabled then
        self._rollingAnchorPoint = UIConfig.AutoRoll.RollingPanelTopAnchorPoint or self._rollingBaseAnchorPoint
        self._rollingFinalPosition = UIConfig.AutoRoll.RollingPanelTopPosition or self._rollingBaseFinalPosition
        self._rollingScaleMultiplier = UIConfig.AutoRoll.RollingScale or 1
        self._rollingSpacingMultiplier = UIConfig.AutoRoll.RollingSpacingScale or 1
        self._rollingIsHorizontal = UIConfig.AutoRoll.IsHorizontal == true
    else
        self._rollingAnchorPoint = self._rollingBaseAnchorPoint
        self._rollingFinalPosition = self._rollingBaseFinalPosition
        self._rollingScaleMultiplier = 1
        self._rollingSpacingMultiplier = 1
        self._rollingIsHorizontal = false
    end
end

function UIController:_updateAutoRollState(snapshot)
    self:_updateRewardsPanelLayout(snapshot)
    if not self._rollBusy then
        self:_updateRollingLayout(snapshot)
    end

    local shouldEnableAutoRoll = snapshot.Stats and snapshot.Stats.AutoRoll == true
    if shouldEnableAutoRoll ~= self._autoRollEnabled then
        self._autoRollEnabled = shouldEnableAutoRoll
        self._autoRollThreadToken += 1
        if not self._rollBusy then
            self:_resetRollingUI(shouldEnableAutoRoll and "auto-roll enabled" or "auto-roll disabled")
        end
    end

    if self._rollBusy then
        return
    end

    if not self._autoRollEnabled then
        return
    end

    if self._autoRollLoopRunning then
        return
    end

    local token = self._autoRollThreadToken
    self._autoRollLoopRunning = true
    self._autoRollThread = task.spawn(function()
        while self._autoRollEnabled and token == self._autoRollThreadToken do
            if not self._rollBusy then
                self:RequestRoll("AutoRoll")
            end
            task.wait(AUTO_ROLL_DELAY_SECONDS)
        end
        self._autoRollLoopRunning = false
        self._autoRollThread = nil
    end)
end

function UIController:ApplySnapshot(snapshot)
    if not snapshot then
        return
    end

    self._snapshot = snapshot
    self._rollTable = snapshot.RollTable or self._rollTable
    self:_refreshRollLookup()
    self:_preloadRollImages(self._rollTable)
    self:_updateDailyRewards(snapshot.Rewards and snapshot.Rewards.Daily)
    self:_updatePlaytimeRewards(snapshot.Rewards and snapshot.Rewards.Playtime)
    self:_updateDiscover(snapshot.Progression and snapshot.Progression.Discover)
    self:_updateIndex(snapshot)
    self:_updateInventory(snapshot)
    self:_updateRebirth(snapshot)
    self:_updateRewardPanel(snapshot)
    self:_updateCurrencyUI(snapshot)
    self:_updateAutoRollState(snapshot)
end

function UIController:PlayRollResult(result)
    if not result or not result.Item then
        self:_resetRollingUI("invalid play result")
        return
    end

    if not self:_ensureRollingSlots() then
        self:_resetRollingUI("rolling slots unavailable")
        return
    end

    local resolvedResultItem = self:_resolveRollItem(result.Item) or result.Item
    self:_preloadRollImages({ resolvedResultItem })

    self._rollAnimationToken += 1
    local token = self._rollAnimationToken
    local centerSlotIndex = self:_getCenterSlotIndex()
    local sequence, previewSteps, centerSequenceIndex = self:_buildRollSequence(resolvedResultItem, centerSlotIndex)
    -- With the current UI layout, slot 2 is the visual center even though RollCenterSlot remains 3.
    local winningSlotIndex = math.clamp(centerSlotIndex - 1, 1, #self._rollingSlots)
    local rewardSequenceIndex = math.max(centerSequenceIndex - 2, 1)
    sequence[rewardSequenceIndex] = resolvedResultItem
    local fadeStartDistance = AnimationConfig.RollFadeStartDistance
    local fadeRange = math.max(AnimationConfig.RollFadeEndDistance - fadeStartDistance, MIN_FADE_RANGE)
    local slotSpacingPixels = self:_getRollingSlotSpacingPixels()
    local maxAutoRollPositionOffset = self:_getAutoRollMaxYOffsetPixels()

    self:_hideRollingSlots()
    local startedAt = os.clock()
    while token == self._rollAnimationToken do
        local progress = math.clamp((os.clock() - startedAt) / AnimationConfig.RollSpinDuration, 0, 1)
        local eased = TweenService:GetValue(progress, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        local distance = previewSteps * eased
        local wholeSteps = math.floor(distance)
        local fractionalStep = distance - wholeSteps
        local baseIndex = wholeSteps + 1

        for slotIndex, slot in ipairs(self._rollingSlots) do
            local item = sequence[baseIndex + slotIndex - 1] or resolvedResultItem
            local slotDistanceFromCenter = math.abs((slotIndex - centerSlotIndex) + fractionalStep)
            local positionOffset = ((slotIndex - centerSlotIndex) + fractionalStep) * slotSpacingPixels
            positionOffset = math.min(positionOffset, maxAutoRollPositionOffset)
            local alpha = 0
            if slotDistanceFromCenter >= fadeStartDistance then
                alpha = math.clamp((slotDistanceFromCenter - fadeStartDistance) / fadeRange, 0, 1)
            end
            self:_setRollingSlotState(slot, item, positionOffset, alpha)
        end

        if progress >= 1 then
            break
        end
        RunService.Heartbeat:Wait()
    end

    if token ~= self._rollAnimationToken then
        self:_resetRollingUI("roll animation interrupted before reveal")
        return
    end

    local finalBaseIndex = previewSteps + 1
    -- Keep slot 4 different from the rewarded pet for the final snapped frame.
    -- With the current layout this corresponds to winningSlotIndex + 2.
    local slotFourIndex = math.min(winningSlotIndex + 2, #self._rollingSlots)
    for slotIndex, slot in ipairs(self._rollingSlots) do
        local finalItem = sequence[finalBaseIndex + slotIndex - 1] or resolvedResultItem
        if slotIndex == winningSlotIndex then
            finalItem = resolvedResultItem
        elseif slotIndex == slotFourIndex and self:_rollItemsMatch(finalItem, resolvedResultItem) then
            for _, fallbackItem in ipairs(self._rollTable) do
                local resolvedFallback = self:_resolveRollItem(fallbackItem)
                if resolvedFallback and not self:_rollItemsMatch(resolvedFallback, resolvedResultItem) then
                    finalItem = resolvedFallback
                    break
                end
            end
        end
        local slotDistanceFromCenter = math.abs(slotIndex - centerSlotIndex)
        local positionOffset = (slotIndex - centerSlotIndex) * slotSpacingPixels
        local alpha = 0
        if slotDistanceFromCenter >= fadeStartDistance then
            alpha = math.clamp((slotDistanceFromCenter - fadeStartDistance) / fadeRange, 0, 1)
        end
        self:_setRollingSlotState(slot, finalItem, positionOffset, alpha)
    end

    local winningSlot = self._rollingSlots[winningSlotIndex]
    for slotIndex, slot in ipairs(self._rollingSlots) do
        if slotIndex == winningSlotIndex then
            self:_setRollingSlotState(slot, resolvedResultItem, 0, 0)
        else
            slot.Visible = false
        end
    end

    if winningSlot then
        local refs = self._rollingSlotRefs[winningSlot]
        local petNameText = ""
        local imageText = ""
        if refs then
            if refs.PetName and refs.PetName:IsA("TextLabel") then
                petNameText = refs.PetName.Text
            end
            if refs.Image and refs.Image:IsA("ImageLabel") then
                imageText = refs.Image.Image
            end
        end
        local expectedName = tostring(resolvedResultItem.DisplayName or resolvedResultItem.Name or "")
        local expectedImage = tostring(resolvedResultItem.Icon or "")
        warn(string.format(
            "[RollSlot2Check] slot=%d petText='%s' expectedPet='%s' image='%s' expectedImage='%s' petMatch=%s imageMatch=%s",
            winningSlotIndex,
            petNameText,
            expectedName,
            imageText,
            expectedImage,
            tostring(petNameText == expectedName),
            tostring(imageText == expectedImage)
        ))
    end

    if winningSlot then
        self:_playWinningReveal(winningSlot, resolvedResultItem, token)
    end

    if token ~= self._rollAnimationToken then
        self:_resetRollingUI("roll animation interrupted after reveal")
        return
    end

    self:_resetRollingUI("roll animation completed")
end

return UIController
