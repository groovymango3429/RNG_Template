--!strict
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefinitions = require(Shared:WaitForChild("RemoteDefinitions"))
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")

local UIConfig = require(Config:WaitForChild("UIConfig"))
local SafeWait = require(Util:WaitForChild("SafeWait"))

local function isPreloadable(instance)
    return instance:IsA("ImageLabel")
        or instance:IsA("ImageButton")
        or instance:IsA("Decal")
        or instance:IsA("Texture")
        or instance:IsA("MeshPart")
        or instance:IsA("Sound")
        or instance:IsA("Animation")
end

local function collectPreloadTargets(root, targets, seen)
    if isPreloadable(root) and not seen[root] then
        seen[root] = true
        table.insert(targets, root)
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if isPreloadable(descendant) and not seen[descendant] then
            seen[descendant] = true
            table.insert(targets, descendant)
        end
    end
end

local function setGuiEnabled(guiRoot, isEnabled)
    if guiRoot:IsA("LayerCollector") then
        guiRoot.Enabled = isEnabled
    elseif guiRoot:IsA("GuiObject") then
        guiRoot.Visible = isEnabled
    end
end

local function fadeOutLoadingScreen(loadingGui)
    if not loadingGui then
        return
    end

    local fadeDuration = UIConfig.Loading.FadeDuration
    local tweenInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local processed = {}

    local function addTween(instance, properties)
        local tween = TweenService:Create(instance, tweenInfo, properties)
        tween:Play()
    end

    local function process(instance)
        if processed[instance] then
            return
        end
        processed[instance] = true

        if instance:IsA("CanvasGroup") then
            addTween(instance, { GroupTransparency = 1 })
        elseif instance:IsA("GuiObject") then
            if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
                addTween(instance, { BackgroundTransparency = 1, ImageTransparency = 1 })
            elseif instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
                addTween(instance, { BackgroundTransparency = 1, TextTransparency = 1 })
            else
                addTween(instance, { BackgroundTransparency = 1 })
            end
        elseif instance:IsA("UIStroke") then
            addTween(instance, { Transparency = 1 })
        end
    end

    process(loadingGui)
    for _, descendant in ipairs(loadingGui:GetDescendants()) do
        process(descendant)
    end

    task.wait(fadeDuration)
    setGuiEnabled(loadingGui, false)
end

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local mainGui = SafeWait.WaitForChild(playerGui, UIConfig.RootGui, 15)
local loadingGui = playerGui:FindFirstChild(UIConfig.Loading.ScreenGuiName)

if mainGui then
    setGuiEnabled(mainGui, false)
end

if loadingGui then
    setGuiEnabled(loadingGui, true)
end

local preloadTargets = {}
local seenTargets = {}
local assetsFolder = ReplicatedStorage:FindFirstChild(UIConfig.Loading.PreloadAssetsFolder)

if assetsFolder then
    collectPreloadTargets(assetsFolder, preloadTargets, seenTargets)
else
    warn(string.format("[Loading] Missing ReplicatedStorage.%s folder for preloads.", UIConfig.Loading.PreloadAssetsFolder))
end

if mainGui then
    collectPreloadTargets(mainGui, preloadTargets, seenTargets)
end

if loadingGui then
    collectPreloadTargets(loadingGui, preloadTargets, seenTargets)
end

if #preloadTargets > 0 then
    local ok, err = pcall(function()
        ContentProvider:PreloadAsync(preloadTargets)
    end)
    if not ok then
        warn(string.format("[Loading] PreloadAsync failed: %s", tostring(err)))
    end
end

local remotesFolder = ReplicatedStorage:WaitForChild(RemoteDefinitions.FolderName)
local remotes = {}
for _, definition in ipairs(RemoteDefinitions.Entries) do
    remotes[definition.Name] = remotesFolder:WaitForChild(definition.Name)
end

local Client = script.Parent:WaitForChild("Client")
local Controllers = Client:WaitForChild("Controllers")

local NotificationController = require(Controllers:WaitForChild("NotificationController"))
local UIController = require(Controllers:WaitForChild("UIController"))

local uiController = UIController.new(remotes, NotificationController)

local initialSnapshot = remotes.RequestInitialState:InvokeServer()
uiController:ApplySnapshot(initialSnapshot)

if mainGui then
    setGuiEnabled(mainGui, true)
end

fadeOutLoadingScreen(loadingGui)

remotes.StateUpdated.OnClientEvent:Connect(function(snapshot)
    uiController:ApplySnapshot(snapshot)
end)

remotes.RollResult.OnClientEvent:Connect(function(result)
    uiController:PlayRollResult(result)
end)

remotes.Notification.OnClientEvent:Connect(function(payload)
    NotificationController:Show(payload)
end)
