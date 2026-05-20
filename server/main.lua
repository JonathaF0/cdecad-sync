local VehicleUtils = load(LoadResourceFile(GetCurrentResourceName(), 'shared/vehicles.lua'))()

local syncedCivilians = {}   -- ssn -> CAD civilian id
local syncedVehicles  = {}

local function adapter()
    if not Adapter.active then
        Utils.Debug('Adapter not yet active; deferring framework call.')
        return nil
    end
    return Adapter.active
end

-- =============================================================================
-- BUILD + SYNC
-- =============================================================================

local function buildCivilianPayload(source, data)
    local discordId = nil
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if id:find('discord:') then
            discordId = id:gsub('discord:', '')
            break
        end
    end

    return {
        firstName   = data.firstName,
        lastName    = data.lastName,
        dateOfBirth = Utils.FormatDate(data.dateOfBirth),
        gender      = data.gender and Utils.ConvertGender(data.gender) or 'male',
        nationality = data.nationality or 'American',
        phone       = data.phone,
        identifier  = data.identifier or data.ssn,
        ssn         = data.ssn,
        discordId   = discordId,
        height      = data.height,
    }
end

local SyncPlayerVehicles  -- forward
local function SyncCharacter(source, isNew)
    local a = adapter(); if not a then return end

    local player = a.GetPlayer(source)
    if not player then
        Utils.Debug('SyncCharacter: no player for source', source)
        return
    end

    if not CDECAD_Discord.ShouldSyncPlayer(source) then
        Utils.Debug('Player has excluded Discord role; skipping sync')
        return
    end

    local raw = a.ExtractCharacterData(player)
    if not raw or not raw.ssn then
        Utils.Debug('SyncCharacter: adapter returned no character data')
        return
    end

    local payload = buildCivilianPayload(source, raw)
    local ssn = payload.ssn

    if syncedCivilians[ssn] and not isNew then
        CDECAD_API.UpdateCivilian(ssn, payload, function(success, _, statusCode)
            if success then
                Utils.Debug('Character updated:', ssn)
                if Config.Sync.OnCharacterUpdate then
                    a.Notify(source, 'success', Config.Locale['sync_success'])
                end
                if Config.Sync.SyncVehicles then SyncPlayerVehicles(source) end
            else
                Utils.Debug('Failed to update character:', statusCode)
            end
        end)
    else
        CDECAD_API.CreateCivilian(payload, function(success, data, statusCode)
            if success and data then
                local civId = (data.civilian and data.civilian._id) or data._id or true
                syncedCivilians[ssn] = civId
                a.Notify(source, 'success', Config.Locale['sync_success'])
                if Config.Sync.SyncVehicles then SyncPlayerVehicles(source) end
            else
                Utils.Debug('Failed to create character:', statusCode)
                a.Notify(source, 'error', Config.Locale['sync_failed'])
            end
        end)
    end
end

SyncPlayerVehicles = function(source)
    local a = adapter(); if not a then return end
    local ssn = a.GetCharacterSSN(source)
    if not ssn then return end

    a.GetPlayerVehicles(source, function(list)
        if not list or #list == 0 then
            Utils.Debug('No vehicles to sync for', ssn)
            return
        end

        local payload = {}
        for _, v in ipairs(list) do
            table.insert(payload, {
                citizenid = ssn,
                plate     = v.plate,
                make      = v.make,
                model     = v.model,
                color     = v.color,
                year      = v.year,
            })
        end

        CDECAD_API.BulkSyncVehicles(ssn, payload, function(success, data, statusCode)
            if success then
                local created = (data and data.created) or 0
                local updated = (data and data.updated) or 0
                local failed  = (data and data.failed)  or 0
                Utils.Debug(('Vehicles synced for %s: %d created, %d updated, %d failed'):format(ssn, created, updated, failed))
                for _, v in ipairs(payload) do syncedVehicles[v.plate] = true end
            else
                print(('^1[CDECAD-SYNC] Vehicle sync failed for %s (HTTP %s)^0'):format(ssn, tostring(statusCode)))
            end
        end)
    end)
end

-- =============================================================================
-- UNIFIED LIFECYCLE EVENTS
-- =============================================================================

AddEventHandler('cdecad-sync:characterLoaded', function(source, ssn, isNew)
    Utils.Debug('characterLoaded:', source, ssn, 'isNew=' .. tostring(isNew))
    if not Config.Sync.OnCharacterLoad then return end
    SetTimeout(2000, function() SyncCharacter(source, isNew) end)
end)

AddEventHandler('cdecad-sync:characterUnloaded', function(source, ssn)
    Utils.Debug('characterUnloaded:', source, ssn)
    if CDECAD_Discord and CDECAD_Discord.ClearCache then
        CDECAD_Discord.ClearCache(source)
    end
end)

AddEventHandler('cdecad-sync:characterUpdated', function(source, ssn)
    Utils.Debug('characterUpdated:', source, ssn)
end)

AddEventHandler('cdecad-sync:characterDeleted', function(ssn)
    Utils.Debug('characterDeleted:', ssn)
    if syncedCivilians[ssn] then
        CDECAD_API.DeleteCivilian(ssn, function(success)
            if success then syncedCivilians[ssn] = nil end
        end)
    end
end)

-- =============================================================================
-- CLIENT-TRIGGERED EVENTS (framework-agnostic)
-- =============================================================================

RegisterNetEvent('cdecad-sync:server:updateMugshot', function(mugshotBase64)
    local src = source
    local a = adapter(); if not a then return end
    local ssn = a.GetCharacterSSN(src); if not ssn then return end

    CDECAD_API.UpdateCivilian(ssn, { mugshotUrl = mugshotBase64 }, function(success, _, statusCode)
        Utils.Debug(success and 'Mugshot updated' or ('Mugshot failed: ' .. tostring(statusCode)))
    end)
end)

RegisterNetEvent('cdecad-sync:server:registerVehicle', function(vehicleData)
    local src = source
    local a = adapter(); if not a or not Config.Sync.SyncVehicles then return end
    local ssn = a.GetCharacterSSN(src); if not ssn then return end

    CDECAD_API.RegisterVehicle({
        plate   = vehicleData.plate,
        ownerId = ssn,
        make    = vehicleData.make or vehicleData.brand,
        model   = vehicleData.model,
        color   = vehicleData.color,
        year    = vehicleData.year,
    }, function(success, data)
        if success then
            syncedVehicles[vehicleData.plate] = data and data.vehicleId or true
            a.Notify(src, 'success', Config.Locale['vehicle_registered'])
        end
    end)
end)

RegisterNetEvent('cdecad-sync:server:reportStolen', function(plate, description)
    local src = source
    local a = adapter(); if not a or not Config.Sync.SyncVehicleStatus then return end

    CDECAD_API.GetVehicle(plate, function(success, vehicleData)
        if success and vehicleData then
            CDECAD_API.ReportVehicleStolen(vehicleData.id, true, description, function(stealSuccess)
                if stealSuccess then
                    a.Notify(src, 'success', Config.Locale['vehicle_reported_stolen'])
                end
            end)
        end
    end)
end)

RegisterNetEvent('cdecad-sync:server:911call', function(callData)
    local src = source
    local a = adapter()
    if not Config.Calls.Enabled then return end

    local canCall, remaining = Utils.CheckRateLimit('911_' .. src, Config.Calls.Cooldown)
    if not canCall then
        if a then a.Notify(src, 'error', Config.Locale['911_cooldown']:gsub('{time}', tostring(remaining))) end
        return
    end

    local callerName = 'Anonymous'
    if not callData.anonymous and a then
        local p = a.GetPlayer(src)
        if p then
            local d = a.ExtractCharacterData(p)
            if d then callerName = (d.firstName or '') .. ' ' .. (d.lastName or '') end
        end
    end

    CDECAD_API.Send911Call({
        callType    = callData.callType or 'Emergency Call',
        location    = callData.location or callData.street or 'Unknown',
        callerName  = callerName,
        coords      = callData.coords,
        x = callData.coords and callData.coords.x,
        y = callData.coords and callData.coords.y,
        z = callData.coords and callData.coords.z,
        postal      = callData.postal,
        description = callData.description,
        priority    = callData.priority,
        isAnonymous = callData.anonymous,
        isNPC       = false,
        reportType  = 'Player',
    }, function(success)
        if success then
            if Config.Calls.NotifyOnSuccess and a then
                a.Notify(src, 'success', Config.Locale['911_sent'])
            end
        else
            if a then a.Notify(src, 'error', Config.Locale['cad_offline']) end
        end
    end)
end)

RegisterNetEvent('cdecad-sync:server:npcReport', function(reportData)
    if not Config.NPCReports.Enabled then return end

    local locationKey = ('npc_%s_%d_%d'):format(
        reportData.reportType,
        math.floor((reportData.coords and reportData.coords.x or 0) / 100),
        math.floor((reportData.coords and reportData.coords.y or 0) / 100))

    local cooldown = (Config.NPCReports[reportData.reportType] and Config.NPCReports[reportData.reportType].Cooldown) or 60
    if not Utils.CheckRateLimit(locationKey, cooldown) then return end

    CDECAD_API.Send911Call({
        callType    = reportData.callType or 'Suspicious Activity',
        location    = reportData.location or reportData.street or 'Unknown',
        callerName  = 'Anonymous Witness',
        coords      = reportData.coords,
        x = reportData.coords and reportData.coords.x,
        y = reportData.coords and reportData.coords.y,
        z = reportData.coords and reportData.coords.z,
        postal      = reportData.postal,
        isAnonymous = true,
        isNPC       = true,
        reportType  = reportData.reportType or 'NPC',
    }, function(success)
        if success then Utils.Debug('NPC report sent:', reportData.reportType) end
    end)
end)

-- =============================================================================
-- LOOKUPS (callback exports for MDT / tablet)
-- =============================================================================

lib.callback.register('cdecad-sync:server:lookupCivilian', function(_, identifier)
    local result, done = nil, false
    CDECAD_API.GetCivilianBySSN(identifier, function(success, data)
        result = success and data or nil
        done = true
    end)
    while not done do Wait(10) end
    return result
end)

lib.callback.register('cdecad-sync:server:lookupVehicle', function(_, plate)
    local result, done = nil, false
    CDECAD_API.GetVehicle(plate, function(success, data)
        result = success and data or nil
        done = true
    end)
    while not done do Wait(10) end
    return result
end)

-- =============================================================================
-- EXPORTS
-- =============================================================================

exports('SyncCharacter', function(source)
    SyncCharacter(source, false)
    return true
end)

exports('Send911Call', function(callData)
    CDECAD_API.Send911Call(callData, function(success)
        Utils.Debug('Export Send911Call result:', success)
    end)
end)

exports('GetSyncedCivilianId', function(ssn)
    return syncedCivilians[ssn]
end)

exports('ForceSync', function(source)
    SyncCharacter(source, true)
    return true
end)

exports('GetActiveFramework', function()
    return Config.Framework
end)

-- =============================================================================
-- STARTUP
-- =============================================================================

AddEventHandler('cdecad-sync:adapterReady', function(name)
    print(('[CDECAD-SYNC] Adapter ready: %s'):format(name))

    CDECAD_API.HealthCheck(function(online, statusCode)
        if online then
            print('[CDECAD-SYNC] Connected to CDECAD API')
        else
            print('^3[CDECAD-SYNC] Unable to reach CDECAD API (status ' .. tostring(statusCode) .. ')^0')
        end
    end)

    if Config.Sync.OnCharacterLoad and Adapter.active.GetAllPlayers then
        SetTimeout(5000, function()
            for _, p in pairs(Adapter.active.GetAllPlayers() or {}) do
                local src = p.source or (p.PlayerData and p.PlayerData.source) or p
                if type(src) == 'number' then
                    SyncCharacter(src, false)
                end
            end
        end)
    end
end)

if not Config.API_KEY or Config.API_KEY == '' then
    print('^1[CDECAD-SYNC] CDE_CAD_API_KEY is not set — every CAD request will 401. See server/secrets.lua.^0')
end
if not Config.API_URL or Config.API_URL == '' then
    print('^1[CDECAD-SYNC] CDE_CAD_API_URL is not set — CAD requests have no target.^0')
end
