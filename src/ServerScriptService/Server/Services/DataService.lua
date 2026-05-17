--!strict
local DataStoreService = game:GetService("DataStoreService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")

local DataConfig = require(Config:WaitForChild("DataConfig"))
local TableUtil = require(Util:WaitForChild("TableUtil"))
local CURRENT_SCHEMA_VERSION = 2

local function normalizeInventory(inventory)
    local normalized = {}
    if type(inventory) ~= "table" then
        return normalized
    end

    for itemId, amount in pairs(inventory) do
        if type(itemId) == "string" and type(amount) == "number" then
            local roundedAmount = math.max(0, math.floor(amount))
            if roundedAmount > 0 then
                normalized[itemId] = roundedAmount
            end
        end
    end

    return normalized
end

local function migrateProfile(profile)
    local schemaVersion = tonumber(profile and profile.Meta and profile.Meta.SchemaVersion) or 0
    if schemaVersion < CURRENT_SCHEMA_VERSION then
        local inventory = normalizeInventory(profile.Inventory)
        local equippedIds = {}

        if type(profile.EquippedItemIds) == "table" then
            for _, itemId in ipairs(profile.EquippedItemIds) do
                if type(itemId) == "string" and itemId ~= "" then
                    table.insert(equippedIds, itemId)
                end
            end
        elseif type(profile.EquippedItemId) == "string" and profile.EquippedItemId ~= "" then
            table.insert(equippedIds, profile.EquippedItemId)
        end

        for _, itemId in ipairs(equippedIds) do
            local amount = inventory[itemId]
            if type(amount) == "number" and amount > 0 then
                amount -= 1
                if amount > 0 then
                    inventory[itemId] = amount
                else
                    inventory[itemId] = nil
                end
            end
        end

        profile.Inventory = inventory
    else
        profile.Inventory = normalizeInventory(profile.Inventory)
    end

    if type(profile.Stats) ~= "table" then
        profile.Stats = {}
    end

    local stats = profile.Stats
    local coins = tonumber(stats.Coins) or tonumber(stats.Cash) or 0
    local shards = tonumber(stats.Shards) or tonumber(stats.Gems) or 0

    stats.Coins = math.max(0, math.floor(coins))
    stats.Cash = stats.Coins
    stats.Shards = math.max(0, math.floor(shards))
    stats.Gems = stats.Shards
    stats.Rolls = math.max(0, math.floor(tonumber(stats.Rolls) or 0))
    stats.Rebirths = math.max(0, math.floor(tonumber(stats.Rebirths) or 0))

    profile.Meta.SchemaVersion = CURRENT_SCHEMA_VERSION
    return profile
end

local function buildDefaultProfile(userId: number)
    return {
        Meta = {
            SchemaVersion = CURRENT_SCHEMA_VERSION,
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
            Coins = 0,
            Cash = 0,
            Gems = 0,
            Shards = 0,
            Rolls = 0,
            Rebirths = 0,
        },
        Settings = {
            AutoRoll = false,
        },
        Inventory = {} :: {[string]: number},
        EquippedItemId = nil :: string?,
        EquippedItemIds = {} :: {string},
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
            current = migrateProfile(current)
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
