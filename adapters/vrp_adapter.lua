



local impl = {}


local _vRP = nil
local _resolveTried = false

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

local function makePlayer(source, user_id, identity)
    if not user_id then return nil end
    return {
        source   = source,
        user_id  = user_id,
        identity = identity or fetchIdentity(user_id) or {},
    }
end

local function dobFromAge(age)
    local n = tonumber(age)
    if not n or n <= 0 or n > 150 then return nil end
    local currentYear = tonumber(os.date('%Y'))
    return string.format('%04d-01-01', currentYear - n)
end


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

    local out = {}
    for user_id, src in pairs(users) do
        local uid = tonumber(user_id) or user_id
        local srcNum = tonumber(src) or src
        local player = makePlayer(srcNum, uid, fetchIdentity(uid))
        if player then table.insert(out, player) end
    end
    return out
end

function impl.GetPlayerByIdentifier(identifier)
    local user_id = tonumber(identifier) or identifier
    if not user_id then return nil end
    local identity = fetchIdentity(user_id)
    if not identity then return nil end
    local src = fetchUserSource(user_id)
    return makePlayer(src, user_id, identity)
end


function impl.ExtractCharacterData(player)
    if not player or not player.user_id then return nil end

    local user_id  = player.user_id
    local identity = player.identity or fetchIdentity(user_id) or {}
    local vrpCfg   = Config.vRP or {}

    local firstName = identity.firstname or 'Unknown'
    local lastName  = identity.name or ''

    local dateOfBirth = nil
    if vrpCfg.DeriveDateOfBirth and identity.age then
        dateOfBirth = dobFromAge(identity.age)
    end

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

            local plate = identity.registration or ('USER' .. tostring(user_id))

            table.insert(list, {
                plate = plate,
                make  = make,
                model = model,
                color = 'Stock',
            })
        end

        Utils.Debug(('Found %d vehicles for user_id %s'):format(#list, tostring(user_id)))
        callback(list)
    end)
end


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


function impl.Notify(source, level, message)
    if not source or not message then return end
    TriggerClientEvent('cdecad-sync:client:notify', source, level or 'info', message)
end


local _lifecycleRegistered = false

function impl.RegisterLifecycleEvents()
    if _lifecycleRegistered then return end
    _lifecycleRegistered = true

    getVRP()

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

            local ssn
            if Config.vRP and Config.vRP.UseRegistrationAsSSN and identity.registration then
                ssn = identity.registration
            else
                ssn = tostring(user_id)
            end

            TriggerEvent('cdecad-sync:characterLoaded', src, ssn, first_spawn == true)
        end)
    end)

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


Adapter.register('vrp', impl)
