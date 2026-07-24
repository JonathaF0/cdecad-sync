



local impl = {}


local _ESX = nil

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


function impl.GetPlayer(source)
    local ESX = getESX()
    if not ESX then return nil end
    return ESX.GetPlayerFromId(source)
end

function impl.GetAllPlayers()
    local ESX = getESX()
    if not ESX then return {} end
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
    for _, xPlayer in pairs(impl.GetAllPlayers()) do
        if xPlayer.getIdentifier and xPlayer.getIdentifier() == identifier then
            return xPlayer
        end
    end
    return nil
end


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
    return xPlayer[key]
end

function impl.ExtractCharacterData(player)
    if not player then return nil end

    local mapping = (Config.ESX and Config.ESX.FieldMapping) or {}

    local identifier = (player.getIdentifier and player:getIdentifier())
        or readField(player, mapping.ssn or 'identifier')

    local firstName = readField(player, mapping.firstName)
    local lastName  = readField(player, mapping.lastName)
    if (not firstName or firstName == '') and player.getName then
        local fn, ln = splitName(player.getName())
        firstName = firstName ~= '' and firstName or fn
        lastName  = (lastName and lastName ~= '') and lastName or ln
    end

    local dob = readField(player, mapping.dateOfBirth or 'dateofbirth')
    local dateOfBirth = Utils.FormatDate(dob)

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
                            spawnName = VehicleUtils.ResolveSpawnNameByHash(props.model)
                                or tostring(props.model)
                        end
                        colorRaw = props.color1 or props.colorPrimary
                    end
                end

                local make, model = VehicleUtils.ResolveMakeModel(spawnName or 'Unknown')
                local color = VehicleUtils.ResolveColor(colorRaw)

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


function impl.GetPlayerJob(source)
    local xPlayer = impl.GetPlayer(source)
    if not xPlayer or not xPlayer.job then return nil end
    return {
        name  = xPlayer.job.name,
        grade = xPlayer.job.grade,
    }
end

function impl.IsOnDuty(source)
    return true
end


function impl.Notify(source, level, message)
    if not source or not message then return end
    TriggerClientEvent('cdecad-sync:client:notify', source, level or 'info', message)
end


local function resolvePlayerLoadedArgs(a, b, c)
    if type(a) == 'number' then
        return a, b, c == true
    end
    if type(a) == 'table' then
        local src = a.source or (a.getSource and a:getSource()) or source
        return src, a, b == true
    end
    return source, b, c == true
end

local _lifecycleRegistered = false

function impl.RegisterLifecycleEvents()
    if _lifecycleRegistered then return end
    _lifecycleRegistered = true

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

        SetTimeout(2000, function()
            TriggerEvent('cdecad-sync:characterLoaded', src, ssn, isNew == true)
        end)
    end

    RegisterNetEvent('esx:playerLoaded', onPlayerLoaded)
    AddEventHandler('esx:playerLoaded', onPlayerLoaded)

    RegisterNetEvent('esx:setJob', function(playerId, job, lastJob)
        Utils.Debug('esx:setJob ->', playerId, job and job.name)
        local ssn = impl.GetCharacterSSN(playerId)
        if ssn then
            TriggerEvent('cdecad-sync:characterUpdated', playerId, ssn)
        end
    end)

    AddEventHandler('esx:playerDropped', function(playerId, reason)
        Utils.Debug('esx:playerDropped ->', playerId, reason)
        local ssn = impl.GetCharacterSSN(playerId)
        TriggerEvent('cdecad-sync:characterUnloaded', playerId, ssn)
    end)

    if Config.ESX and Config.ESX.MultiCharacter and Config.ESX.MultiCharacter.Enabled then
        local mcResource = Config.ESX.MultiCharacter.Resource or 'esx_multicharacter'
        Utils.Debug('Wiring multichar events for:', mcResource)

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
                    TriggerEvent('cdecad-sync:characterLoaded', src, ssn, false)
                end
            end)
        end
    end

    Utils.Debug('ESX adapter lifecycle events registered')
end


Adapter.register('esx', impl)
