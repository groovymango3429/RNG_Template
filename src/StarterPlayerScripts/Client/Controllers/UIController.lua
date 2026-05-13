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
    self._rewardsPanelOriginalPosition = nil
    self._rewardsPanelOriginalAnchorPoint = nil
    self._rollingGui = nil
    self._rollingMain = nil
    self._rollingSlots = {}
    self._rollingSlotRefs = {}
    self._rollingSlotScales = {}
    self._rollingTransparencyBaseline = {}
    self._rollingFinalPosition = UIConfig.Rolling.FinalPosition
    self._rollingAnchorPoint = UIConfig.Rolling.AnchorPoint
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

function UIController:Destroy()
    self._rollAnimationToken += 1
    self:_hideRollingSlots()
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
            uiScale.Scale = 1
        end
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

function UIController:_setRollingSlotContent(slot, item)
    local refs = self._rollingSlotRefs[slot]
    if not refs then
        return
    end

    setImage(refs.Image, item and item.Icon or "")
    setText(refs.PetName, item and item.DisplayName or "")
    setText(refs.Rarity, formatOdds(item and item.DisplayOdds or ""))

    local rarityStroke = refs.RarityStroke
    if rarityStroke and rarityStroke:IsA("UIStroke") then
        rarityStroke.Color = getRarityColor(item and item.Rarity or nil)
    end
end

function UIController:_setRollingSlotState(slot, item, yScale, alpha)
    slot.AnchorPoint = self._rollingAnchorPoint
    slot.Position = UDim2.new(
        self._rollingFinalPosition.X.Scale,
        self._rollingFinalPosition.X.Offset,
        yScale,
        self._rollingFinalPosition.Y.Offset
    )
    slot.Visible = true
    self:_setRollingSlotContent(slot, item)
    self:_applyRollingTransparency(slot, alpha)

    local uiScale = self._rollingSlotScales[slot]
    if uiScale then
        uiScale.Scale = 1
    end
end

function UIController:_playWinningReveal(slot, item, token)
    self:_setRollingSlotState(slot, item, self._rollingFinalPosition.Y.Scale, 0)
    slot.Position = self._rollingFinalPosition

    local uiScale = self._rollingSlotScales[slot]
    if uiScale then
        uiScale.Scale = AnimationConfig.RollRevealStartScale

        local popTween = TweenService:Create(
            uiScale,
            TweenInfo.new(AnimationConfig.RollRevealPopDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = AnimationConfig.RollRevealPeakScale }
        )
        popTween:Play()
        popTween.Completed:Wait()

        if token ~= self._rollAnimationToken then
            return
        end

        local settleTween = TweenService:Create(
            uiScale,
            TweenInfo.new(AnimationConfig.RollRevealSettleDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
            { Scale = 1 }
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
    local endPosition = UDim2.new(
        self._rollingFinalPosition.X.Scale,
        self._rollingFinalPosition.X.Offset,
        self._rollingFinalPosition.Y.Scale + AnimationConfig.RollFadeOutOffset,
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
    local source = #self._rollTable > 0 and self._rollTable or { resultItem }
    local previewSteps = math.max(AnimationConfig.RollCycleCount * 2, AnimationConfig.RollSlotCount + AnimationConfig.RollPreviewPadding)
    local totalEntries = previewSteps + AnimationConfig.RollSlotCount + 1
    local sequence = {}

    for index = 1, totalEntries do
        sequence[index] = source[((index - 1) % #source) + 1]
    end

    local finalIndex = previewSteps + AnimationConfig.RollCenterSlot
    sequence[finalIndex] = resultItem
    for index = finalIndex + 1, totalEntries do
        sequence[index] = resultItem
    end

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

function UIController:_updateAutoRollState(snapshot)
    self:_updateRewardsPanelLayout(snapshot)

    if self._autoRollThread then
        task.cancel(self._autoRollThread)
        self._autoRollThread = nil
    end

    if snapshot.Stats and snapshot.Stats.AutoRoll then
        self._autoRollThread = task.spawn(function()
            while self._snapshot and self._snapshot.Stats and self._snapshot.Stats.AutoRoll do
                if not self._rollBusy then
                    self:RequestRoll()
                end
                task.wait(1.5)
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
        return
    end

    if not self:_ensureRollingSlots() then
        return
    end

    self:_preloadRollImages({ result.Item })

    self._rollAnimationToken += 1
    local token = self._rollAnimationToken
    local sequence, previewSteps = self:_buildRollSequence(result.Item)
    local fadeStartY = AnimationConfig.RollFadeStartY
    local fadeRange = math.max(AnimationConfig.RollFadeEndY - fadeStartY, MIN_FADE_RANGE)

    self:_hideRollingSlots()
    task.spawn(function()
        local startedAt = os.clock()
        while token == self._rollAnimationToken do
            local progress = math.clamp((os.clock() - startedAt) / AnimationConfig.RollSpinDuration, 0, 1)
            local eased = TweenService:GetValue(progress, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
            local distance = previewSteps * eased
            local wholeSteps = math.floor(distance)
            local fractionalStep = distance - wholeSteps
            local baseIndex = wholeSteps + 1

            for slotIndex, slot in ipairs(self._rollingSlots) do
                local item = sequence[baseIndex + slotIndex - 1] or result.Item
                local yScale = self._rollingFinalPosition.Y.Scale + (((slotIndex - AnimationConfig.RollCenterSlot) + fractionalStep) * AnimationConfig.RollSlotSpacing)
                local alpha = 0
                if yScale >= fadeStartY then
                    alpha = math.clamp((yScale - fadeStartY) / fadeRange, 0, 1)
                end
                self:_setRollingSlotState(slot, item, yScale, alpha)
            end

            if progress >= 1 then
                break
            end
            RunService.Heartbeat:Wait()
        end

        if token ~= self._rollAnimationToken then
            return
        end

        local winningSlot = self._rollingSlots[AnimationConfig.RollCenterSlot]
        for slotIndex, slot in ipairs(self._rollingSlots) do
            if slotIndex == AnimationConfig.RollCenterSlot then
                self:_setRollingSlotState(slot, result.Item, self._rollingFinalPosition.Y.Scale, 0)
            else
                slot.Visible = false
            end
        end

        if winningSlot then
            self:_playWinningReveal(winningSlot, result.Item, token)
        end
    end)
end

return UIController
