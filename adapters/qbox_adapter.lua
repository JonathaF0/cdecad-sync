--[[
    QBox framework adapter.

    QBox forks QBCore but exposes a modern exports-based API plus `lib.callback`.
    Most QBox installs still fire QBCore-prefixed events for backwards
    compatibility, so we listen on those names. Character deletion is
    QBox-specific via `qbx_core:server:deleteCharacter`.

    All qbx_core access is resolved lazily so this file loads even if qbx_core
    hasn't started yet — the active impl is only invoked after bootstrap which
    runs after framework detection succeeds.
]]

local impl = {}

-- =============================================================================
-- LAZY EXPORT RESOLVERS
-- =============================================================================

local function qbx()
    -- Returns the qbx_core exports table (or nil if not yet up). Cheap to call.
    local ok, ex = pcall(function() return exports.qbx_core end)
    if not ok then return nil end
    return ex
end

-- =============================================================================
-- PLAYER LOOKUP
-- =============================================================================

function impl.GetPlayer(source)
    local ex = qbx()
    if not ex then return nil end
    local ok, player = pcall(function() return ex:GetPlayer(source) end)
    if not ok then return nil end
    return player
end

function impl.GetAllPlayers()
    local ex = qbx()
    if not ex then return {} end
    local ok, players = pcall(function() return ex:GetQBPlayers() end)
    if not ok or not players then return {} end
    return players
end

function impl.GetPlayerByIdentifier(citizenid)
    if not citizenid then return nil end
    local ex = qbx()
    if not ex then return nil end
    local ok, player = pcall(function() return ex:GetPlayerByCitizenId(citizenid) end)
    if not ok then return nil end
    return player
end

-- =============================================================================
-- IDENTITY
-- =============================================================================

function impl.ExtractCharacterData(player)
    if not player or not player.PlayerData then return nil end
    local pd = player.PlayerData
    local charinfo = pd.charinfo
    if not charinfo then return nil end

    -- Normalize gender via Config.GenderMapping. QBox stores 0/1 (int) or
    -- sometimes string keys; honor both.
    local gender = charinfo.gender
    if Config and Config.GenderMapping then
        if type(gender) == 'string' then
            gender = Config.GenderMapping[gender:lower()]
                  or Config.GenderMapping[gender]
                  or gender
        else
            gender = Config.GenderMapping[gender] or 'Unknown'
        end
    end

    -- Resolve a license identifier from PlayerData.license, falling back to
    -- the live identifier list. Useful for logs / audit context.
    local identifier = pd.license
    if not identifier and pd.source then
        identifier = impl.GetPlayerIdentifier(pd.source, 'license')
    end

    return {
        firstName    = charinfo.firstname,
        lastName     = charinfo.lastname,
        dateOfBirth  = charinfo.birthdate,
        gender       = gender,
        phone        = charinfo.phone,
        ssn          = pd.citizenid,
        identifier   = identifier,
        nationality  = charinfo.nationality or 'American',
    }
end

function impl.GetPlayerIdentifier(source, idType)
    if not source or not idType then return nil end
    local prefix = tostring(idType) .. ':'
    local ids = GetPlayerIdentifiers(source) or {}
    for _, id in ipairs(ids) do
        if string.sub(id, 1, #prefix) == prefix then
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

-- =============================================================================
-- VEHICLES
-- =============================================================================

function impl.GetPlayerVehicles(source, callback)
    callback = callback or function() end
    local player = impl.GetPlayer(source)
    if not player or not player.PlayerData then
        callback({})
        return
    end

    local citizenid = player.PlayerData.citizenid
    if not citizenid then
        callback({})
        return
    end

    if Utils and Utils.Debug then Utils.Debug('Querying vehicles for:', citizenid) end

    -- QBox uses the QBCore-compatible player_vehicles schema: plate / vehicle
    -- (spawn name) / mods (json). Color lives inside mods.color1.
    local ok = pcall(function()
        exports.oxmysql:execute(
            'SELECT plate, vehicle, mods FROM player_vehicles WHERE citizenid = ?',
            { citizenid },
            function(rows)
                if not rows or #rows == 0 then
                    callback({})
                    return
                end

                local list = {}
                for _, v in ipairs(rows) do
                    local spawnName = v.vehicle or 'Unknown'
                    local make, model = 'Unknown', spawnName
                    if VehicleUtils and VehicleUtils.ResolveMakeModel then
                        make, model = VehicleUtils.ResolveMakeModel(spawnName)
                    end

                    local color = 'Unknown'
                    if v.mods then
                        local okDecode, mods = pcall(json.decode, v.mods)
                        if okDecode and mods and VehicleUtils and VehicleUtils.ResolveColor then
                            color = VehicleUtils.ResolveColor(mods.color1)
                        end
                    end

                    list[#list + 1] = {
                        plate = v.plate,
                        make  = make,
                        model = model,
                        color = color,
                        -- year omitted; player_vehicles has no year column.
                    }
                end
                callback(list)
            end
        )
    end)

    if not ok then
        if Utils and Utils.Debug then Utils.Debug('oxmysql query failed for vehicles') end
        callback({})
    end
end

-- =============================================================================
-- JOB / ON-DUTY
-- =============================================================================

function impl.GetPlayerJob(source)
    local player = impl.GetPlayer(source)
    if not player or not player.PlayerData or not player.PlayerData.job then
        return nil
    end
    local job = player.PlayerData.job
    return {
        name  = job.name,
        grade = (job.grade and job.grade.level) or 0,
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

function impl.RegisterLifecycleEvents()
    -- Character loaded. QBox fires the legacy QBCore event name for compat.
    -- We listen on both the networked and non-networked variants because
    -- some QBox versions only fire one of them.
    local function onLoaded()
        local src = source
        if not src or src == 0 then return end
        local player = impl.GetPlayer(src)
        if not player or not player.PlayerData then return end
        local ssn = player.PlayerData.citizenid
        if Utils and Utils.Debug then Utils.Debug('QBox character loaded:', src, ssn) end
        TriggerEvent('cdecad-sync:characterLoaded', src, ssn, false)
    end
    RegisterNetEvent('QBCore:Server:OnPlayerLoaded', onLoaded)
    AddEventHandler('QBCore:Server:OnPlayerLoaded', onLoaded)

    -- Character unloaded. QBCore-style handler receives `source` as an arg
    -- (since the event is fired from server -> server, the magic `source`
    -- global isn't reliable).
    AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
        src = src or source
        if not src then return end
        local ssn
        local player = impl.GetPlayer(src)
        if player and player.PlayerData then ssn = player.PlayerData.citizenid end
        if Utils and Utils.Debug then Utils.Debug('QBox character unloaded:', src, ssn) end
        TriggerEvent('cdecad-sync:characterUnloaded', src, ssn)
    end)

    -- Job updates. Signature: (source, job).
    AddEventHandler('QBCore:Server:OnJobUpdate', function(src, _job)
        if not src then return end
        local ssn
        local player = impl.GetPlayer(src)
        if player and player.PlayerData then ssn = player.PlayerData.citizenid end
        if Utils and Utils.Debug then Utils.Debug('QBox job update:', src, ssn) end
        TriggerEvent('cdecad-sync:characterUpdated', src, ssn)
    end)

    -- Character deletion (QBox-specific event; QBCore has no direct equivalent).
    RegisterNetEvent('qbx_core:server:deleteCharacter', function(citizenid)
        if not citizenid then return end
        if Utils and Utils.Debug then Utils.Debug('QBox character deleted:', citizenid) end
        TriggerEvent('cdecad-sync:characterDeleted', citizenid)
    end)
end

-- =============================================================================
-- REGISTER
-- =============================================================================

Adapter.register('qbox', impl)
