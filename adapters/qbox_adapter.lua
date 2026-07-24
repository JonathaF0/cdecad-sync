


local impl = {}


local function qbx()
    local ok, ex = pcall(function() return exports.qbx_core end)
    if not ok then return nil end
    return ex
end


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


function impl.ExtractCharacterData(player)
    if not player or not player.PlayerData then return nil end
    local pd = player.PlayerData
    local charinfo = pd.charinfo
    if not charinfo then return nil end

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


function impl.Notify(source, level, message)
    if not source or not message then return end
    TriggerClientEvent('cdecad-sync:client:notify', source, level or 'info', message)
end


function impl.RegisterLifecycleEvents()
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

    AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
        src = src or source
        if not src then return end
        local ssn
        local player = impl.GetPlayer(src)
        if player and player.PlayerData then ssn = player.PlayerData.citizenid end
        if Utils and Utils.Debug then Utils.Debug('QBox character unloaded:', src, ssn) end
        TriggerEvent('cdecad-sync:characterUnloaded', src, ssn)
    end)

    AddEventHandler('QBCore:Server:OnJobUpdate', function(src, _job)
        if not src then return end
        local ssn
        local player = impl.GetPlayer(src)
        if player and player.PlayerData then ssn = player.PlayerData.citizenid end
        if Utils and Utils.Debug then Utils.Debug('QBox job update:', src, ssn) end
        TriggerEvent('cdecad-sync:characterUpdated', src, ssn)
    end)

    RegisterNetEvent('qbx_core:server:deleteCharacter', function(citizenid)
        if not citizenid then return end
        if Utils and Utils.Debug then Utils.Debug('QBox character deleted:', citizenid) end
        TriggerEvent('cdecad-sync:characterDeleted', citizenid)
    end)
end


Adapter.register('qbox', impl)
