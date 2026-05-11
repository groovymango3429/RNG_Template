--!strict
local DataStoreService = game:GetService("DataStoreService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")

local DataConfig = require(Config:WaitForChild("DataConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local TableUtil = require(Util:WaitForChild("TableUtil"))

local function buildDefaultProfile(userId: number)
    return {
        Meta = {
            -- v2 adds SkillTree, Unlocks, Modifiers, and expanded Stats fields.
            SchemaVersion = 2,
            UserId = userId,
            SaveMode = "Normal",
            LastLoadAt = 0,
            LastSaveAt = 0,
        },
        Session = {
            JobId = "",
            Heartbeat = 0,
            PlaceId = 0,
        },
        Stats = {
            Coins = EconomyConfig.StartingStats.Coins,
            Gems = EconomyConfig.StartingStats.Gems,
            Rolls = EconomyConfig.StartingStats.Rolls,
            Rebirths = EconomyConfig.StartingStats.Rebirths,
            CombatPower = EconomyConfig.StartingStats.CombatPower,
            SkillPoints = EconomyConfig.StartingStats.SkillPoints,
        },
        Settings = {
            AutoRoll = false,
        },
        Inventory = {} :: {[string]: number},
        Index = {} :: {[string]: boolean},
        Rewards = {
            Daily = {
                LastClaimDay = -1,
                CurrentDay = 1,
            },
            Playtime = {
                AccumulatedSeconds = 0,
                ClaimedSlots = {} :: {[number]: boolean},
            },
        },
        Boosts = {
            Luck = {
                Amount = 0,
                ExpiresAt = 0,
            },
        },
        Purchases = {
            Gamepasses = {} :: {[string]: boolean},
            Products = {} :: {[string]: number},
        },
        SkillTree = {
            UnlockedNodes = {} :: {[string]: boolean},
        },
        Unlocks = {
            Zones = {} :: {[string]: boolean},
        },
        Modifiers = {
            LuckBonus = 0,
            CoinMultiplier = 0,
            GemMultiplier = 0,
            AutoRollIntervalReduction = 0,
            CombatPowerBonus = 0,
        },
    }
end

type Profile = typeof(buildDefaultProfile(0))

local DataService = {
    _profiles = {} :: {[Player]: Profile},
    _dirty = {} :: {[Player]: boolean},
    _started = false,
}

function DataService:_withRetries(callback, label)
    local lastError = "Unknown error"
    for attempt = 1, DataConfig.RetryCount do
        local success, result = pcall(callback)
        if success then
            return true, result
        end
        lastError = tostring(result)
        warn(string.format("[DataService] %s attempt %d failed: %s", label, attempt, lastError))
        if attempt < DataConfig.RetryCount then
            task.wait(DataConfig.RetryDelaySeconds * attempt)
        end
    end
    return false, lastError
end

function DataService:_getKey(userId)
    return string.format("player_%d", userId)
end

function DataService:Init()
    if self._started then
        return
    end

    self._started = true
    self._store = DataStoreService:GetDataStore(DataConfig.StoreName)

    task.spawn(function()
        while self._started do
            task.wait(DataConfig.AutosaveIntervalSeconds)
            for player in pairs(self._profiles) do
                if self._dirty[player] then
                    self:SaveProfile(player, false)
                end
            end
        end
    end)
end

function DataService:LoadProfile(player)
    local key = self:_getKey(player.UserId)
    local loadedProfile
    local lockConflict = false

    local success = self:_withRetries(function()
        self._store:UpdateAsync(key, function(current)
            current = TableUtil.Reconcile(current or {}, buildDefaultProfile(player.UserId))
            local session = current.Session or {}
            local now = os.time()
            local isLocked = session.JobId ~= nil
                and session.JobId ~= ""
                and session.JobId ~= game.JobId
                and now - (session.Heartbeat or 0) < DataConfig.SessionLockSeconds

            if isLocked then
                lockConflict = true
                return nil
            end

            current.Session = {
                JobId = game.JobId,
                Heartbeat = now,
                PlaceId = game.PlaceId,
            }
            current.Meta.SaveMode = "Normal"
            current.Meta.LastLoadAt = now
            loadedProfile = current
            return current
        end)
    end, "load")

    if success and loadedProfile then
        self._profiles[player] = loadedProfile
        self._dirty[player] = false
        return loadedProfile, false
    end

    if lockConflict then
        warn(string.format("[DataService] Profile for %s is session locked. Using fallback session.", player.Name))
    else
        warn(string.format("[DataService] Falling back to temporary profile for %s.", player.Name))
    end

    local fallback = buildDefaultProfile(player.UserId)
    fallback.Meta.SaveMode = "Fallback"
    fallback.Session = {
        JobId = game.JobId,
        Heartbeat = os.time(),
        PlaceId = game.PlaceId,
    }

    self._profiles[player] = fallback
    self._dirty[player] = false
    return fallback, true
end

function DataService:GetProfile(player)
    return self._profiles[player]
end

function DataService:MarkDirty(player)
    if self._profiles[player] then
        self._dirty[player] = true
    end
end

function DataService:UpdateProfile(player, mutator)
    local profile = self._profiles[player]
    if not profile then
        return nil
    end

    mutator(profile)
    profile.Session.Heartbeat = os.time()
    self._dirty[player] = true
    return profile
end

function DataService:SaveProfile(player, releaseLock)
    local profile = self._profiles[player]
    if not profile then
        return false
    end

    if profile.Meta.SaveMode == "Fallback" then
        return false
    end

    local key = self:_getKey(player.UserId)
    local wroteProfile = false

    local success = self:_withRetries(function()
        self._store:UpdateAsync(key, function(current)
            current = current or {}
            local session = current.Session or {}
            if session.JobId ~= nil and session.JobId ~= "" and session.JobId ~= game.JobId then
                warn(string.format("[DataService] Refused save for %s because another session owns the profile.", player.Name))
                return nil
            end

            profile.Meta.LastSaveAt = os.time()
            profile.Session = {
                JobId = releaseLock and "" or game.JobId,
                Heartbeat = releaseLock and 0 or os.time(),
                PlaceId = releaseLock and 0 or game.PlaceId,
            }
            wroteProfile = true
            return profile
        end)
    end, releaseLock and "release" or "save")

    if success and wroteProfile then
        self._dirty[player] = false
        if releaseLock then
            self._profiles[player] = nil
            self._dirty[player] = nil
        end
        return true
    end

    return false
end

function DataService:ReleaseProfile(player)
    self:SaveProfile(player, true)
    self._profiles[player] = nil
    self._dirty[player] = nil
end

function DataService:Shutdown()
    self._started = false
    for player in pairs(self._profiles) do
        self:ReleaseProfile(player)
    end
end

return DataService
