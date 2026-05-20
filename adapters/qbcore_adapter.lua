--[[
    QBCore adapter for cde-cad-sync.

    Implements the Adapter contract defined in adapters/adapter.lua against
    the qb-core framework. Only activated when Config.Framework == 'qbcore'
    (which framework_detect.lua / bootstrap.lua set based on the started
    resources).

    QBCore-specific notes:
      * Identifier of record is `citizenid` — also used as the CAD SSN.
      * `charinfo` holds firstname / lastname / birthdate / gender / phone.
      * `gender` is 0/1 (numeric) on stock QBCore, but some forks store
        'male'/'female' strings — Config.GenderMapping covers both.
      * `player_vehicles.vehicle` already stores the spawn name (string),
        not a model hash — no GetHashKey lookup needed.
]]

local impl = {}

-- Lazily resolve the core object so this file loads even if qb-core hasn't
-- started yet. bootstrap.lua only activates us once qb-core is up, but adapter
-- file registration happens at script load time.
local _QBCore
local function QB()
    if not _QBCore then
        local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok then _QBCore = core end
    end
    return _QBCore
end

-- =============================================================================
-- PLAYER LOOKUP
-- =============================================================================

function impl.GetPlayer(source)
    local core = QB()
    if not core then return nil end
    return core.Functions.GetPlayer(source)
end

function impl.GetAllPlayers()
    local core = QB()
    if not core then return {} end
    local sources = core.Functions.GetPlayers() or {}
    local players = {}
    for _, src in ipairs(sources) do
        local p = core.Functions.GetPlayer(src)
        if p then players[#players + 1] = p end
    end
    return players
end

function impl.GetPlayerByIdentifier(citizenid)
    local core = QB()
    if not core then return nil end
    return core.Functions.GetPlayerByCitizenId(citizenid)
end

-- =============================================================================
-- IDENTITY
-- =============================================================================

function impl.GetPlayerIdentifier(source, idType)
    if not source or not idType then return nil end
    local ids = GetPlayerIdentifiers(source) or {}
    local prefix = idType .. ':'
    for _, id in ipairs(ids) do
        if id:sub(1, #prefix) == prefix then
            return id
        end
    end
    return nil
end

function impl.GetCharacterSSN(source)
    local player = impl.GetPlayer(source)
    if not player or not player.PlayerData then return nil end
    return player.PlayerData.citizenid
end

function impl.ExtractCharacterData(player)
    if not player or not player.PlayerData then return nil end
    local pd = player.PlayerData
    local charinfo = pd.charinfo or {}

    -- Normalize gender. QBCore stock = 0/1; some forks = 'male'/'female'.
    local rawGender = charinfo.gender
    local gender = Config.GenderMapping and Config.GenderMapping[rawGender]
    if not gender and type(rawGender) == 'string' then
        gender = Config.GenderMapping and Config.GenderMapping[rawGender:lower()]
    end
    gender = gender or 'Male'

    -- Best-effort log identifier: prefer discord, fall back to license.
    local logIdent = impl.GetPlayerIdentifier(pd.source, 'discord')
        or impl.GetPlayerIdentifier(pd.source, 'license')

    return {
        firstName   = charinfo.firstname,
        lastName    = charinfo.lastname,
        dateOfBirth = charinfo.birthdate,
        gender      = gender,
        phone       = charinfo.phone,
        ssn         = pd.citizenid,
        identifier  = logIdent,
        nationality = charinfo.nationality or 'American',
    }
end

-- =============================================================================
-- VEHICLES
-- =============================================================================

function impl.GetPlayerVehicles(source, callback)
    local player = impl.GetPlayer(source)
    if not player or not player.PlayerData then
        if callback then callback({}) end
        return
    end

    local citizenid = player.PlayerData.citizenid
    Utils.Debug('[qbcore_adapter] Fetching vehicles for citizenid:', citizenid)

    exports.oxmysql:execute(
        'SELECT plate, vehicle, mods FROM player_vehicles WHERE citizenid = ?',
        { citizenid },
        function(rows)
            if not rows or #rows == 0 then
                Utils.Debug('[qbcore_adapter] No vehicles for:', citizenid)
                if callback then callback({}) end
                return
            end

            local list = {}
            for _, row in ipairs(rows) do
                local spawnName = row.vehicle or 'Unknown'
                local make, model = VehicleUtils.ResolveMakeModel(spawnName)

                local color = 'Unknown'
                if row.mods then
                    local ok, mods = pcall(json.decode, row.mods)
                    if ok and mods then
                        color = VehicleUtils.ResolveColor(mods.color1) or 'Unknown'
                    end
                end

                list[#list + 1] = {
                    plate = row.plate,
                    make  = make,
                    model = model,
                    color = color,
                    -- year intentionally omitted — QBCore doesn't track a
                    -- registration year; the backend will render '—'.
                }
            end

            if callback then callback(list) end
        end
    )
end

-- =============================================================================
-- JOB / DUTY
-- =============================================================================

function impl.GetPlayerJob(source)
    local player = impl.GetPlayer(source)
    if not player or not player.PlayerData or not player.PlayerData.job then
        return nil
    end
    local job = player.PlayerData.job
    return {
        name  = job.name,
        grade = job.grade and job.grade.level or 0,
    }
end

function impl.IsOnDuty(source)
    local player = impl.GetPlayer(source)
    if not player or not player.PlayerData or not player.PlayerData.job then
        return false
    end
    return player.PlayerData.job.onduty == true
end

-- =============================================================================
-- NOTIFICATIONS
-- =============================================================================

function impl.Notify(source, level, message)
    if not source or not message then return end
    TriggerClientEvent('cdecad-sync:client:notify', source, level or 'info', message)
end

-- =============================================================================
-- LIFECYCLE EVENT WIRING
-- =============================================================================
--
-- Translate QBCore's native events into the framework-agnostic
-- `cdecad-sync:character*` events that server/main.lua listens for.

function impl.RegisterLifecycleEvents()
    Utils.Debug('[qbcore_adapter] Registering lifecycle events')

    -- Character loaded (player selected character / spawned).
    AddEventHandler('QBCore:Server:OnPlayerLoaded', function()
        local src = source
        -- Small delay matches the original cde-cad-qbcore behaviour: charinfo
        -- and metadata aren't always fully populated the instant this fires.
        SetTimeout(2000, function()
            local player = impl.GetPlayer(src)
            if not player or not player.PlayerData then
                Utils.Debug('[qbcore_adapter] OnPlayerLoaded: player not found for', src)
                return
            end
            local ssn = player.PlayerData.citizenid
            Utils.Debug('[qbcore_adapter] characterLoaded ->', src, ssn)
            TriggerEvent('cdecad-sync:characterLoaded', src, ssn, false)
        end)
    end)

    -- Character unloaded (logout, character switch, disconnect).
    AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
        local player = impl.GetPlayer(src)
        local ssn = player and player.PlayerData and player.PlayerData.citizenid
        Utils.Debug('[qbcore_adapter] characterUnloaded ->', src, ssn)
        TriggerEvent('cdecad-sync:characterUnloaded', src, ssn)
    end)

    -- Job updated — propagate so the backend can refresh the unit/job tags
    -- on the civilian record.
    AddEventHandler('QBCore:Server:OnJobUpdate', function(src, _job)
        local player = impl.GetPlayer(src)
        local ssn = player and player.PlayerData and player.PlayerData.citizenid
        if not ssn then return end
        Utils.Debug('[qbcore_adapter] characterUpdated (job) ->', src, ssn)
        TriggerEvent('cdecad-sync:characterUpdated', src, ssn)
    end)

    -- Optional event — only on newer QBCore builds. Wrapping in pcall is
    -- harmless: AddEventHandler always succeeds, the handler just never
    -- fires on builds that don't emit it.
    AddEventHandler('QBCore:Server:OnPlayerLogout', function(src)
        local player = impl.GetPlayer(src)
        local ssn = player and player.PlayerData and player.PlayerData.citizenid
        Utils.Debug('[qbcore_adapter] characterUnloaded (logout) ->', src, ssn)
        TriggerEvent('cdecad-sync:characterUnloaded', src, ssn)
    end)
end

-- =============================================================================
-- REGISTRATION
-- =============================================================================

Adapter.register('qbcore', impl)
