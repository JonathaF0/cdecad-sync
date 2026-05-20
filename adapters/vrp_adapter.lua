--[[
    vRP framework adapter for cde-cad-sync.

    vRP doesn't use FiveM events for cross-resource calls — it exposes
    a Tunnel/Proxy RPC system. Characters are identified by an integer
    `user_id`, and identity lives in `vrp_user_identities` keyed by it.

    Implements adapters/adapter.lua's contract. Expects Config, Utils,
    VehicleUtils, Adapter to already be loaded.

    The vRP `module()` resolver is invoked LAZILY (inside getVRP()) so
    this file safely loads even when vRP isn't present.
]]

local impl = {}

-- =============================================================================
-- vRP PROXY INTERFACE (LAZY)
-- =============================================================================

local _vRP = nil
local _resolveTried = false

--- Resolve vRP's Proxy interface, caching after first success. The
--- `module()` call errors if vRP isn't running, so we pcall it and only
--- try once — bootstrap won't activate this adapter without vRP anyway.
local function getVRP()
    if _vRP then return _vRP end
    if _resolveTried then return nil end
    _resolveTried = true

    local ok, result = pcall(function()
        local Proxy = module('vrp', 'lib/Proxy')
        return Proxy.getInterface('vRP')
    end)
    if ok and result then
        _vRP = result
    else
        Utils.Debug('vRP adapter: failed to resolve vRP Proxy interface')
    end
    return _vRP
end

-- =============================================================================
-- INTERNAL HELPERS
-- =============================================================================

--- vRP RPC calls take positional-args wrapped in a table (e.g. { source }),
--- not a record. Centralize that quirk in these helpers.
local function fetchUserId(source)
    local vRP = getVRP()
    if not vRP or not source or source == 0 then return nil end
    local ok, uid = pcall(vRP.getUserId, { source })
    if ok then return uid end
    return nil
end

local function fetchIdentity(user_id)
    local vRP = getVRP()
    if not vRP or not user_id then return nil end
    local ok, identity = pcall(vRP.getUserIdentity, { user_id })
    if ok then return identity end
    return nil
end

local function fetchUserSource(user_id)
    local vRP = getVRP()
    if not vRP or not user_id then return nil end
    local ok, src = pcall(vRP.getUserSource, { user_id })
    if ok then return src end
    return nil
end

--- Build the synthetic "player" object. vRP has no first-class player
--- table, so we manufacture one with just what the shared layer needs.
local function makePlayer(source, user_id, identity)
    if not user_id then return nil end
    return {
        source   = source,
        user_id  = user_id,
        identity = identity or fetchIdentity(user_id) or {},
    }
end

--- Synthesize YYYY-MM-DD from an integer age. vRP only stores `age`, so
--- anchor to Jan 1 of (currentYear - age). nil for missing/invalid ages.
local function dobFromAge(age)
    local n = tonumber(age)
    if not n or n <= 0 or n > 150 then return nil end
    local currentYear = tonumber(os.date('%Y'))
    return string.format('%04d-01-01', currentYear - n)
end

-- =============================================================================
-- PLAYER LOOKUP
-- =============================================================================

function impl.GetPlayer(source)
    if not source or source == 0 then return nil end
    local user_id = fetchUserId(source)
    if not user_id then return nil end
    return makePlayer(source, user_id, fetchIdentity(user_id))
end

function impl.GetAllPlayers()
    local vRP = getVRP()
    if not vRP then return {} end

    local ok, users = pcall(vRP.getUsers, {})
    if not ok or type(users) ~= 'table' then return {} end

    -- getUsers returns a { [user_id] = source } map; flatten to an array.
    local out = {}
    for user_id, src in pairs(users) do
        local uid = tonumber(user_id) or user_id
        local srcNum = tonumber(src) or src
        local player = makePlayer(srcNum, uid, fetchIdentity(uid))
        if player then table.insert(out, player) end
    end
    return out
end

--- For vRP the identifier IS the user_id. Accept number or numeric string.
function impl.GetPlayerByIdentifier(identifier)
    local user_id = tonumber(identifier) or identifier
    if not user_id then return nil end
    local identity = fetchIdentity(user_id)
    if not identity then return nil end
    local src = fetchUserSource(user_id)
    return makePlayer(src, user_id, identity)
end

-- =============================================================================
-- IDENTITY EXTRACTION
-- =============================================================================

function impl.ExtractCharacterData(player)
    if not player or not player.user_id then return nil end

    local user_id  = player.user_id
    local identity = player.identity or fetchIdentity(user_id) or {}
    local vrpCfg   = Config.vRP or {}

    -- vRP stores firstname in `firstname` and surname in `name`.
    local firstName = identity.firstname or 'Unknown'
    local lastName  = identity.name or ''

    -- vRP has no DoB column. When DeriveDateOfBirth is set, fabricate
    -- Jan 1 of the year implied by `age`; otherwise leave nil.
    local dateOfBirth = nil
    if vrpCfg.DeriveDateOfBirth and identity.age then
        dateOfBirth = dobFromAge(identity.age)
    end

    -- vRP has no gender column by default. Identity addons may inject
    -- `sex`/`gender`; normalize via the shared mapping, default Unknown.
    local rawGender = identity.sex or identity.gender
    local gender = 'Unknown'
    if rawGender ~= nil then
        if type(rawGender) == 'string' then
            gender = Config.GenderMapping[rawGender:lower()]
                or Config.GenderMapping[rawGender]
                or 'Unknown'
        else
            gender = Config.GenderMapping[rawGender] or 'Unknown'
        end
    end

    -- SSN: integer user_id (default) or `registration` plate code if
    -- the operator prefers human-readable IDs.
    local ssn
    if vrpCfg.UseRegistrationAsSSN and identity.registration then
        ssn = identity.registration
    else
        ssn = tostring(user_id)
    end

    return {
        firstName   = firstName,
        lastName    = lastName,
        dateOfBirth = dateOfBirth,
        gender      = gender,
        phone       = identity.phone,
        ssn         = ssn,
        identifier  = tostring(user_id),
        nationality = 'American',
    }
end

function impl.GetPlayerIdentifier(source, idType)
    if not source or not idType then return nil end
    local prefix = idType .. ':'
    for _, id in ipairs(GetPlayerIdentifiers(source) or {}) do
        if id:sub(1, #prefix) == prefix then
            return id
        end
    end
    return nil
end

function impl.GetCharacterSSN(source)
    local user_id = fetchUserId(source)
    if not user_id then return nil end

    local vrpCfg = Config.vRP or {}
    if vrpCfg.UseRegistrationAsSSN then
        local identity = fetchIdentity(user_id)
        if identity and identity.registration then
            return identity.registration
        end
    end
    return tostring(user_id)
end

-- =============================================================================
-- VEHICLES
-- =============================================================================

--- Pull owned vehicles from `vrp_user_vehicles`. Rows are (user_id, vehicle)
--- where `vehicle` is the spawn name; plates aren't persisted per-vehicle
--- in the default schema — vRP derives them from the user's registration
--- at spawn time. We mirror cde-cad-vrp and use registration as the plate.
function impl.GetPlayerVehicles(source, callback)
    callback = callback or function() end

    local user_id = fetchUserId(source)
    if not user_id then
        callback({})
        return
    end

    local identity = fetchIdentity(user_id) or {}
    local table_name = (Config.vRP and Config.vRP.VehiclesTable) or 'vrp_user_vehicles'
    local query = ('SELECT vehicle FROM %s WHERE user_id = ?'):format(table_name)

    Utils.Debug('GetPlayerVehicles for user_id:', user_id)

    exports.oxmysql:execute(query, { user_id }, function(rows)
        if not rows or #rows == 0 then
            Utils.Debug('No vehicles for user_id:', user_id)
            callback({})
            return
        end

        local list = {}
        for _, row in ipairs(rows) do
            local spawnName = row.vehicle or 'Unknown'
            local make, model = VehicleUtils.ResolveMakeModel(spawnName)

            -- vRP doesn't store per-vehicle plates; use registration as a
            -- stable placeholder so CAD can match against plate scans.
            local plate = identity.registration or ('USER' .. tostring(user_id))

            table.insert(list, {
                plate = plate,
                make  = make,
                model = model,
                color = 'Stock',
                -- year omitted; backend renders as "—" when unknown.
            })
        end

        Utils.Debug(('Found %d vehicles for user_id %s'):format(#list, tostring(user_id)))
        callback(list)
    end)
end

-- =============================================================================
-- JOB / DUTY
-- =============================================================================

--- vRP has no "job" — only additive permission groups. Approximate the
--- ESX/QBCore job object by returning the first ExcludedGroup the player
--- belongs to (LEO/Fire/EMS as "primary job"). Civilians get nil.
function impl.GetPlayerJob(source)
    local vRP = getVRP()
    local user_id = fetchUserId(source)
    if not vRP or not user_id then return nil end

    local groups = (Config.vRP and Config.vRP.ExcludedGroups) or {}
    for _, group in ipairs(groups) do
        local ok, has = pcall(vRP.hasGroup, { user_id, group })
        if ok and has then
            return { name = group, grade = 0 }
        end
    end
    return nil
end

--- "On duty" here means "should we sync this character to the civilian
--- CAD?". Returns FALSE for excluded-group members (LEO/Fire/EMS), who
--- are tracked separately in the LEO CAD.
function impl.IsOnDuty(source)
    local vRP = getVRP()
    local user_id = fetchUserId(source)
    if not vRP or not user_id then return true end

    local groups = (Config.vRP and Config.vRP.ExcludedGroups) or {}
    for _, group in ipairs(groups) do
        local ok, has = pcall(vRP.hasGroup, { user_id, group })
        if ok and has then
            return false
        end
    end
    return true
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

local _lifecycleRegistered = false

function impl.RegisterLifecycleEvents()
    if _lifecycleRegistered then return end
    _lifecycleRegistered = true

    -- Warm the Proxy interface; safe to fail since events will retry.
    getVRP()

    -- vRP:playerSpawn fires (user_id, source, first_spawn). The identity
    -- row may still be settling on first_spawn=true, so delay per
    -- Config.vRP.SpawnSyncDelay (ms) before extracting.
    AddEventHandler('vRP:playerSpawn', function(user_id, src, first_spawn)
        Utils.Debug('vRP:playerSpawn user_id=' .. tostring(user_id) ..
            ' source=' .. tostring(src) .. ' first_spawn=' .. tostring(first_spawn))

        if not user_id then return end

        local delay = (Config.vRP and Config.vRP.SpawnSyncDelay) or 2000
        SetTimeout(delay, function()
            local identity = fetchIdentity(user_id)
            if not identity then
                Utils.Debug('vRP:playerSpawn: no identity for user_id ' .. tostring(user_id))
                return
            end

            -- Mirror ExtractCharacterData's SSN logic for the event payload.
            local ssn
            if Config.vRP and Config.vRP.UseRegistrationAsSSN and identity.registration then
                ssn = identity.registration
            else
                ssn = tostring(user_id)
            end

            TriggerEvent('cdecad-sync:characterLoaded', src, ssn, first_spawn == true)
        end)
    end)

    -- vRP:playerLeave fires (user_id, source). source may already be 0
    -- and identity may have been cleared; pass what we have.
    AddEventHandler('vRP:playerLeave', function(user_id, src)
        Utils.Debug('vRP:playerLeave user_id=' .. tostring(user_id))
        if not user_id then return end

        local identity = fetchIdentity(user_id)
        local ssn
        if identity and Config.vRP and Config.vRP.UseRegistrationAsSSN and identity.registration then
            ssn = identity.registration
        else
            ssn = tostring(user_id)
        end

        TriggerEvent('cdecad-sync:characterUnloaded', src, ssn)
    end)

    Utils.Debug('vRP adapter lifecycle events registered')
end

-- =============================================================================
-- REGISTER
-- =============================================================================

Adapter.register('vrp', impl)
