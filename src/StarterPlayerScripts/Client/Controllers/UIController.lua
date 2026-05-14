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
local AUTO_ROLL_DELAY_SECONDS = 1.5
local ROLL_DEBUG_PREFIX = "[RollDebug]"

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

local function formatUDim2(value)
    return string.format(
        "UDim2(%.3f,%d,%.3f,%d)",
        value.X.Scale,
        value.X.Offset,
        value.Y.Scale,
        value.Y.Offset
    )
end

local function formatVector2(value)
    return string.format("Vector2(%.3f,%.3f)", value.X, value.Y)
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

    if self._ui then
        for _, panelName in ipairs(UIConfig.Panels) do
            self._panels[panelName] = self:_resolvePanel(panelName)
        end
        self:_bindNavigation()
        self:_bindActions()
        self:_bindCloseButtons()
        self:_bindRewardButtons()
        self:_captureRewardsPanelLayout()
    end

    self:_setupRollingUI()
    return self
end

function UIController:_debugLog(message, ...)
    print(string.format("%s " .. message, ROLL_DEBUG_PREFIX, ...))
end

function UIController:_debugWarn(message, ...)
    warn(string.format("%s " .. message, ROLL_DEBUG_PREFIX, ...))
end

function UIController:_describeRollItem(item)
    local resolved = self:_resolveRollItem(item) or item
    if type(resolved) ~= "table" then
        return "UnknownPet(Id=?)"
    end

    local name = tostring(resolved.DisplayName or resolved.Name or "UnknownPet")
    local id = tostring(resolved.Id or "?")
    return string.format("%s(Id=%s)", name, id)
end

function UIController:_getCenterSlotIndex()
    local configured = math.floor((AnimationConfig.RollCenterSlot or 1) + 0.5)
    local slotCount = #self._rollingSlots > 0 and #self._rollingSlots or AnimationConfig.RollSlotCount
    local clamped = math.clamp(configured, 1, math.max(slotCount, 1))
    if clamped ~= configured then
        self:_debugWarn(
            "RollCenterSlot clamped from %d to %d (slotCount=%d).",
            configured,
            clamped,
            slotCount
        )
    end
    return clamped
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

    self:_debugWarn(
        "Roll item match fallback without stable IDs (left=%s right=%s).",
        self:_describeRollItem(leftResolved),
        self:_describeRollItem(rightResolved)
    )
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
        self:_debugWarn("Roll blocked/failed: remote invoke failed for %s.", tostring(remoteName))
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
            self:_debugLog("Auto-roll toggle requested.")
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
                    self:_debugLog("GUI panel closed: %s", panelName)
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

function UIController:RequestRoll(source)
    local rollSource = source or "Manual"
    if self._rollBusy then
        self:_debugWarn("Roll blocked (%s): roll already in progress.", rollSource)
        return
    end

    self:_debugLog("Roll started (%s).", rollSource)
    self._rollBusy = true

    local success, err = xpcall(function()
        local result = self:_invoke("RollRequest")
        if not result then
            self:_debugWarn("Roll failed (%s): RollRequest returned nil.", rollSource)
            self:_resetRollingUI("roll failed")
            return
        end

        if not result.Success then
            self:_debugWarn("Roll blocked/failed (%s): %s", rollSource, tostring(result.Message or "Unknown roll failure."))
            if result.Message then
                self._notifier:Show({ Kind = "Warning", Message = result.Message })
            end
            self:_resetRollingUI("roll failed")
            return
        end

        if not result.Result or not result.Result.Item then
            self:_debugWarn("Roll failed (%s): server response missing result item.", rollSource)
            self:_resetRollingUI("missing result item")
            return
        end

        self:PlayRollResult(result.Result)
    end, debug.traceback)

    if not success then
        self:_debugWarn("Roll failed (%s): %s", rollSource, tostring(err))
        self:_resetRollingUI("roll runtime error")
    end

    self._rollBusy = false
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

function UIController:_applyRollingTransparency(slot, alpha)
    local baseline = self._rollingTransparencyBaseline[slot]
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

    self:_debugLog("Rolling GUI reset/closed (%s).", reason or "unspecified")
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
    for _, child in ipairs(self._rollingMain.Parent:GetChildren()) do
        if child ~= self._rollingMain and child:IsA("GuiObject") and child.Name:match("^RollingSlot%d+$") then
            child:Destroy()
        end
    end
    self._rollingMain.AnchorPoint = self._rollingAnchorPoint
    self._rollingMain.Position = self._rollingFinalPosition
    self._rollingMain.Visible = false
    setPanelVisible(rollingGui, true)
    self:_debugLog(
        "Rolling main setup: anchor=%s position=%s size=%s absPos=%s absSize=%s",
        formatVector2(self._rollingMain.AnchorPoint),
        formatUDim2(self._rollingMain.Position),
        formatUDim2(self._rollingMain.Size),
        formatVector2(self._rollingMain.AbsolutePosition),
        formatVector2(self._rollingMain.AbsoluteSize)
    )
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
        self:_debugLog(
            "Rolling slot ready: idx=%d name=%s anchor=%s position=%s absPos=%s absSize=%s",
            index,
            slot.Name,
            formatVector2(slot.AnchorPoint),
            formatUDim2(slot.Position),
            formatVector2(slot.AbsolutePosition),
            formatVector2(slot.AbsoluteSize)
        )
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

function UIController:_buildRollSequence(resultItem)
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

    local centerSlotIndex = self:_getCenterSlotIndex()
    local finalIndex = previewSteps + centerSlotIndex
    sequence[finalIndex] = resolvedResultItem
    self:_debugLog(
        "Roll sequence built: slotCount=%d centerSlot=%d previewSteps=%d finalIndex=%d totalEntries=%d reward=%s",
        AnimationConfig.RollSlotCount,
        centerSlotIndex,
        previewSteps,
        finalIndex,
        totalEntries,
        self:_describeRollItem(resolvedResultItem)
    )

    return sequence, previewSteps
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
    setText(nextLabel, string.format("Next Bonus: %s Gems", FormatUtil.Number(rebirthState.NextBonusGems or 0)))
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
    self:_updateRollingLayout(snapshot)

    local shouldEnableAutoRoll = snapshot.Stats and snapshot.Stats.AutoRoll == true
    if shouldEnableAutoRoll ~= self._autoRollEnabled then
        self._autoRollEnabled = shouldEnableAutoRoll
        self._autoRollThreadToken += 1
        self:_resetRollingUI(shouldEnableAutoRoll and "auto-roll enabled" or "auto-roll disabled")
        self:_debugLog("Auto-roll %s.", shouldEnableAutoRoll and "enabled" or "disabled")
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
        self:_debugLog("Auto-roll loop started.")
        while self._autoRollEnabled and token == self._autoRollThreadToken do
            if not self._rollBusy then
                self:RequestRoll("AutoRoll")
            end
            task.wait(AUTO_ROLL_DELAY_SECONDS)
        end
        self:_debugLog("Auto-roll loop ended.")
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
    self:_updateRebirth(snapshot)
    self:_updateRewardPanel(snapshot)
    self:_updateAutoRollState(snapshot)
end

function UIController:PlayRollResult(result)
    if not result or not result.Item then
        self:_debugWarn("Roll failed: PlayRollResult called without a valid item.")
        self:_resetRollingUI("invalid play result")
        return
    end

    if not self:_ensureRollingSlots() then
        self:_debugWarn("Roll blocked: rolling slots are unavailable.")
        self:_resetRollingUI("rolling slots unavailable")
        return
    end

    local resolvedResultItem = self:_resolveRollItem(result.Item) or result.Item
    self:_debugLog("Reward pet selected: %s", self:_describeRollItem(resolvedResultItem))
    self:_preloadRollImages({ resolvedResultItem })

    self._rollAnimationToken += 1
    local token = self._rollAnimationToken
    local sequence, previewSteps = self:_buildRollSequence(resolvedResultItem)
    local centerSlotIndex = self:_getCenterSlotIndex()
    local centerSequenceIndex = previewSteps + centerSlotIndex
    local middleSequenceItem = sequence[centerSequenceIndex] or resolvedResultItem
    if not self:_rollItemsMatch(middleSequenceItem, resolvedResultItem) then
        self:_debugWarn(
            "ERROR: animation middle pet (%s) does not match rewarded pet (%s).",
            self:_describeRollItem(middleSequenceItem),
            self:_describeRollItem(resolvedResultItem)
        )
        sequence[centerSequenceIndex] = resolvedResultItem
        middleSequenceItem = resolvedResultItem
    end
    self:_debugLog("Middle animation pet: %s", self:_describeRollItem(middleSequenceItem))
    self:_debugLog(
        "Middle/reward match: %s",
        self:_rollItemsMatch(middleSequenceItem, resolvedResultItem) and "YES" or "NO"
    )
    local fadeStartDistance = AnimationConfig.RollFadeStartDistance
    local fadeRange = math.max(AnimationConfig.RollFadeEndDistance - fadeStartDistance, MIN_FADE_RANGE)
    local slotSpacingPixels = self:_getRollingSlotSpacingPixels()
    local maxAutoRollPositionOffset = self:_getAutoRollMaxYOffsetPixels()
    self:_debugLog(
        "Roll animation config: slotCount=%d centerSlot=%d slotSpacing=%.2f padding=%d horizontal=%s basePos=%s",
        AnimationConfig.RollSlotCount,
        centerSlotIndex,
        slotSpacingPixels,
        AnimationConfig.RollSlotPaddingPixels,
        tostring(self._rollingIsHorizontal),
        formatUDim2(self._rollingFinalPosition)
    )

    self:_hideRollingSlots()
    local startedAt = os.clock()
    local lastLoggedWholeSteps = -1
    while token == self._rollAnimationToken do
        local progress = math.clamp((os.clock() - startedAt) / AnimationConfig.RollSpinDuration, 0, 1)
        local eased = TweenService:GetValue(progress, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        local distance = previewSteps * eased
        local wholeSteps = math.floor(distance)
        local fractionalStep = distance - wholeSteps
        local baseIndex = wholeSteps + 1
        local shouldLogStep = wholeSteps ~= lastLoggedWholeSteps
        local slotSnapshots = shouldLogStep and {} or nil

        for slotIndex, slot in ipairs(self._rollingSlots) do
            local item = sequence[baseIndex + slotIndex - 1] or resolvedResultItem
            local slotDistanceFromCenter = math.abs((slotIndex - centerSlotIndex) + fractionalStep)
            local positionOffset = ((slotIndex - centerSlotIndex) + fractionalStep) * slotSpacingPixels
            positionOffset = math.min(positionOffset, maxAutoRollPositionOffset)
            local alpha = 0
            if slotDistanceFromCenter >= fadeStartDistance then
                alpha = math.clamp((slotDistanceFromCenter - fadeStartDistance) / fadeRange, 0, 1)
            end
            if slotSnapshots then
                table.insert(
                    slotSnapshots,
                    string.format(
                        "#%d:%s@offset=%.2f,a=%.2f,pos=%s",
                        slotIndex,
                        self:_describeRollItem(item),
                        positionOffset,
                        alpha,
                        formatVector2(slot.AbsolutePosition)
                    )
                )
            end
            self:_setRollingSlotState(slot, item, positionOffset, alpha)
        end
        if slotSnapshots then
            self:_debugLog(
                "Spin step=%d progress=%.3f baseIndex=%d centerSeqIndex=%d slots={%s}",
                wholeSteps,
                progress,
                baseIndex,
                centerSequenceIndex,
                table.concat(slotSnapshots, " | ")
            )
        end
        lastLoggedWholeSteps = wholeSteps

        if progress >= 1 then
            break
        end
        RunService.Heartbeat:Wait()
    end

    if token ~= self._rollAnimationToken then
        self:_resetRollingUI("roll animation interrupted before reveal")
        return
    end

    local winningSlot = self._rollingSlots[centerSlotIndex]
    for slotIndex, slot in ipairs(self._rollingSlots) do
        if slotIndex == centerSlotIndex then
            self:_setRollingSlotState(slot, resolvedResultItem, 0, 0)
        else
            slot.Visible = false
        end
    end
    self:_debugLog(
        "Winning slot reveal: centerSlot=%d reward=%s winningSlotAbsPos=%s",
        centerSlotIndex,
        self:_describeRollItem(resolvedResultItem),
        winningSlot and formatVector2(winningSlot.AbsolutePosition) or "nil"
    )

    if winningSlot then
        self:_playWinningReveal(winningSlot, resolvedResultItem, token)
    end

    if token ~= self._rollAnimationToken then
        self:_resetRollingUI("roll animation interrupted after reveal")
        return
    end

    self:_debugLog("Roll animation ended.")
    self:_resetRollingUI("roll animation completed")
end

return UIController
