--[[
    ESX framework adapter for cde-cad-sync.

    Implements the adapter contract documented in adapters/adapter.lua,
    translating ESX-specific player objects, events, and database layout
    into the unified interface the rest of cde-cad-sync consumes.

    Globals expected to already be loaded:
        Config, Utils, VehicleUtils, Adapter

    ESX is fetched lazily via exports['es_extended']:getSharedObject() so
    this file can load before es_extended; bootstrap.lua's CreateThread
    only activates the adapter once ESX is responsive.
]]

local impl = {}

-- =============================================================================
-- ESX SHARED OBJECT (LAZY)
-- =============================================================================

local _ESX = nil

--- Resolve the ESX shared object, caching after first success.
--- Safe to call from any handler — if es_extended isn't up yet the
--- pcall fails silently and the caller gets nil.
local function getESX()
    if _ESX then return _ESX end
    local ok, esx = pcall(function()
        return exports['es_extended']:getSharedObject()
    end)
    if ok and esx then
        _ESX = esx
    end
    return _ESX
end

-- =============================================================================
-- PLAYER LOOKUP
-- =============================================================================

function impl.GetPlayer(source)
    local ESX = getESX()
    if not ESX then return nil end
    return ESX.GetPlayerFromId(source)
end

function impl.GetAllPlayers()
    local ESX = getESX()
    if not ESX then return {} end
    -- GetExtendedPlayers returns the full xPlayer objects; some forks
    -- only expose GetPlayers (source list), so fall back gracefully.
    if ESX.GetExtendedPlayers then
        return ESX.GetExtendedPlayers()
    end
    local out = {}
    if ESX.GetPlayers then
        for _, src in ipairs(ESX.GetPlayers()) do
            local p = ESX.GetPlayerFromId(src)
            if p then table.insert(out, p) end
        end
    end
    return out
end

function impl.GetPlayerByIdentifier(identifier)
    local ESX = getESX()
    if not ESX or not identifier then return nil end
    if ESX.GetPlayerFromIdentifier then
        return ESX.GetPlayerFromIdentifier(identifier)
    end
    -- Fallback: scan extended players
    for _, xPlayer in pairs(impl.GetAllPlayers()) do
        if xPlayer.getIdentifier and xPlayer.getIdentifier() == identifier then
            return xPlayer
        end
    end
    return nil
end

-- =============================================================================
-- IDENTITY EXTRACTION
-- =============================================================================

--- Split a single ESX name string into first/last components.
--- esx_identity returns "First Last" via xPlayer.getName(); on multi-word
--- last names ("De La Cruz") we keep everything after the first token.
local function splitName(playerName)
    if not playerName or playerName == '' then
        return playerName or '', ''
    end
    local parts = {}
    for word in playerName:gmatch('%S+') do
        table.insert(parts, word)
    end
    if #parts >= 2 then
        return parts[1], table.concat(parts, ' ', 2)
    end
    return parts[1] or playerName, ''
end

--- Read a value from an xPlayer using a Config.ESX.FieldMapping key.
--- ESX stores most identity fields in xPlayer.get('field'); a couple of
--- known fields are also exposed via dedicated accessors.
local function readField(xPlayer, key)
    if not xPlayer or not key then return nil end
    if key == 'identifier' and xPlayer.getIdentifier then
        return xPlayer.getIdentifier()
    end
    if key == 'firstName' or key == 'firstname' then
        local n = xPlayer.get and (xPlayer.get('firstname') or xPlayer.get('firstName'))
        if n then return n end
    end
    if key == 'lastName' or key == 'lastname' then
        local n = xPlayer.get and (xPlayer.get('lastname') or xPlayer.get('lastName'))
        if n then return n end
    end
    if xPlayer.get then
        local v = xPlayer.get(key)
        if v ~= nil then return v end
    end
    -- Some forks expose fields as direct table members
    return xPlayer[key]
end

function impl.ExtractCharacterData(player)
    if not player then return nil end

    local mapping = (Config.ESX and Config.ESX.FieldMapping) or {}

    -- Identifier — used as SSN by default, and as the log key
    local identifier = (player.getIdentifier and player:getIdentifier())
        or readField(player, mapping.ssn or 'identifier')

    -- Names: prefer mapped fields, fall back to xPlayer.getName() split
    local firstName = readField(player, mapping.firstName)
    local lastName  = readField(player, mapping.lastName)
    if (not firstName or firstName == '') and player.getName then
        local fn, ln = splitName(player.getName())
        firstName = firstName ~= '' and firstName or fn
        lastName  = (lastName and lastName ~= '') and lastName or ln
    end

    -- DOB — normalize via Utils.FormatDate (handles MM/DD/YYYY → YYYY-MM-DD)
    local dob = readField(player, mapping.dateOfBirth or 'dateofbirth')
    local dateOfBirth = Utils.FormatDate(dob)

    -- Gender — ESX stores 'm'/'f'; normalize via Config.GenderMapping
    local rawSex = readField(player, mapping.gender or 'sex')
    local gender = 'Unknown'
    if rawSex ~= nil then
        if type(rawSex) == 'string' then
            gender = Config.GenderMapping[rawSex:lower()]
                or Config.GenderMapping[rawSex]
                or 'Unknown'
        else
            gender = Config.GenderMapping[rawSex] or 'Unknown'
        end
    end

    -- Phone (optional — many ESX setups don't populate this)
    local phone = readField(player, mapping.phone or 'phone_number')

    local ssn = identifier
    if mapping.ssn and mapping.ssn ~= 'identifier' then
        ssn = readField(player, mapping.ssn) or identifier
    end

    return {
        firstName   = firstName or '',
        lastName    = lastName or '',
        dateOfBirth = dateOfBirth,
        gender      = gender,
        phone       = phone,
        ssn         = ssn,
        identifier  = identifier,
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
    local xPlayer = impl.GetPlayer(source)
    if not xPlayer then return nil end
    if xPlayer.getIdentifier then
        return xPlayer.getIdentifier()
    end
    return nil
end

-- =============================================================================
-- VEHICLES
-- =============================================================================

--- Pull a player's owned vehicles from the ESX `owned_vehicles` table.
--- The original cde-cad-esx used oxmysql's exports.oxmysql:execute API,
--- so we match that here (NOT the older MySQL-Async wrapper).
function impl.GetPlayerVehicles(source, callback)
    callback = callback or function() end
    local xPlayer = impl.GetPlayer(source)
    if not xPlayer or not xPlayer.getIdentifier then
        callback({})
        return
    end

    local identifier = xPlayer.getIdentifier()
    Utils.Debug('GetPlayerVehicles for:', identifier)

    exports.oxmysql:execute(
        'SELECT plate, vehicle FROM owned_vehicles WHERE owner = ?',
        { identifier },
        function(rows)
            if not rows or #rows == 0 then
                Utils.Debug('No vehicles for:', identifier)
                callback({})
                return
            end

            local list = {}
            for _, row in ipairs(rows) do
                local spawnName, colorRaw

                if row.vehicle then
                    local ok, props = pcall(json.decode, row.vehicle)
                    if ok and props then
                        if props.model then
                            -- ESX persists `model` as a joaat hash int.
                            -- Reverse-lookup to a spawn name; if it's not
                            -- in our table, stringify the hash so the row
                            -- still has something traceable.
                            spawnName = VehicleUtils.ResolveSpawnNameByHash(props.model)
                                or tostring(props.model)
                        end
                        colorRaw = props.color1 or props.colorPrimary
                    end
                end

                local make, model = VehicleUtils.ResolveMakeModel(spawnName or 'Unknown')
                local color = VehicleUtils.ResolveColor(colorRaw)

                -- year is intentionally omitted: ESX doesn't track a
                -- real registration year, and the backend renders the
                -- missing value as "—" rather than fabricating one.
                table.insert(list, {
                    plate = row.plate,
                    make  = make,
                    model = model,
                    color = color,
                })
            end

            Utils.Debug(('Found %d vehicles for %s'):format(#list, identifier))
            callback(list)
        end
    )
end

-- =============================================================================
-- JOB / DUTY
-- =============================================================================

function impl.GetPlayerJob(source)
    local xPlayer = impl.GetPlayer(source)
    if not xPlayer or not xPlayer.job then return nil end
    return {
        name  = xPlayer.job.name,
        grade = xPlayer.job.grade,
    }
end

--- ESX has no built-in on-duty toggle (esx_service is a separate addon
--- with its own state). We return true here and let the shared LEO/Fire/
--- EMS filtering logic (excluded jobs + excluded Discord roles) handle
--- whether a player should be treated as on-duty for sync purposes.
function impl.IsOnDuty(source)
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

--- Resolve the (source, xPlayer, isNew) tuple from esx:playerLoaded.
--- Modern ESX fires it as (source, xPlayer, isNew); some legacy forks
--- still fire (xPlayer, isNew). Detect at runtime so this adapter works
--- on either without forcing the operator to pick an ESX version.
local function resolvePlayerLoadedArgs(a, b, c)
    -- (source, xPlayer, isNew)
    if type(a) == 'number' then
        return a, b, c == true
    end
    -- (xPlayer, isNew) — fork shape
    if type(a) == 'table' then
        local src = a.source or (a.getSource and a:getSource()) or source
        return src, a, b == true
    end
    -- Unknown shape — fall back to FX's `source` global if available
    return source, b, c == true
end

local _lifecycleRegistered = false

function impl.RegisterLifecycleEvents()
    if _lifecycleRegistered then return end
    _lifecycleRegistered = true

    -- Player selected/loaded a character ---------------------------------
    local function onPlayerLoaded(a, b, c)
        local src, xPlayer, isNew = resolvePlayerLoadedArgs(a, b, c)
        Utils.Debug('esx:playerLoaded -> source:', src, 'isNew:', isNew)

        local player = xPlayer or impl.GetPlayer(src)
        if not player then
            Utils.Debug('esx:playerLoaded: could not resolve player for', src)
            return
        end

        local ssn = (player.getIdentifier and player:getIdentifier()) or impl.GetCharacterSSN(src)
        if not ssn then
            Utils.Debug('esx:playerLoaded: no identifier for', src)
            return
        end

        -- Small delay: lets esx_identity / metadata writes settle before
        -- the shared sync code reads via ExtractCharacterData.
        SetTimeout(2000, function()
            TriggerEvent('cdecad-sync:characterLoaded', src, ssn, isNew == true)
        end)
    end

    RegisterNetEvent('esx:playerLoaded', onPlayerLoaded)
    -- Also AddEventHandler so internal TriggerEvent calls (from a
    -- multichar resource on the server side) fire the same path.
    AddEventHandler('esx:playerLoaded', onPlayerLoaded)

    -- Job change ---------------------------------------------------------
    RegisterNetEvent('esx:setJob', function(playerId, job, lastJob)
        Utils.Debug('esx:setJob ->', playerId, job and job.name)
        local ssn = impl.GetCharacterSSN(playerId)
        if ssn then
            TriggerEvent('cdecad-sync:characterUpdated', playerId, ssn)
        end
    end)

    -- Player dropped -----------------------------------------------------
    AddEventHandler('esx:playerDropped', function(playerId, reason)
        Utils.Debug('esx:playerDropped ->', playerId, reason)
        local ssn = impl.GetCharacterSSN(playerId)
        -- Note: by the time esx:playerDropped fires, GetPlayerFromId may
        -- already be nil; the shared layer should tolerate ssn=nil here.
        TriggerEvent('cdecad-sync:characterUnloaded', playerId, ssn)
    end)

    -- Multicharacter hook ------------------------------------------------
    -- esx_multicharacter fires its own events on character switch; only
    -- wire them when the operator has explicitly enabled multichar in
    -- Config.ESX.MultiCharacter.
    if Config.ESX and Config.ESX.MultiCharacter and Config.ESX.MultiCharacter.Enabled then
        local mcResource = Config.ESX.MultiCharacter.Resource or 'esx_multicharacter'
        Utils.Debug('Wiring multichar events for:', mcResource)

        -- Common multichar event names across the major forks. We register
        -- all of them; only the one your resource actually fires will hit.
        local events = {
            'esx_multicharacter:CharacterChosen',
            'esx_multicharacter:characterSelected',
            'esx_identity:setPlayerData',
            'esx:characterLoaded',
        }
        for _, ev in ipairs(events) do
            RegisterNetEvent(ev)
            AddEventHandler(ev, function(...)
                local src = source
                Utils.Debug('multichar event:', ev, 'src:', src)
                local ssn = impl.GetCharacterSSN(src)
                if ssn then
                    -- Treat as a fresh character load — isNew=false because
                    -- multichar resources don't reliably distinguish
                    -- first-time creation from a returning selection.
                    TriggerEvent('cdecad-sync:characterLoaded', src, ssn, false)
                end
            end)
        end
    end

    Utils.Debug('ESX adapter lifecycle events registered')
end

-- =============================================================================
-- REGISTER
-- =============================================================================

Adapter.register('esx', impl)
