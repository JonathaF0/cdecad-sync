
local API = {}

local requestQueue = {}
local isProcessing = false
local lastRequestTime = 0
local MIN_REQUEST_INTERVAL = 100

local function MakeRequest(method, endpoint, data, callback)
    local url = Config.API_URL .. endpoint

    local headers = {
        ['Content-Type'] = 'application/json',
        ['x-api-key'] = Config.API_KEY
    }

    if Config.Debug.LogRequests then
        print('[CDECAD-API] ' .. method .. ' ' .. url)
        if data then
            print('[CDECAD-API] Body: ' .. json.encode(data))
        end
    end

    local requestCallback = function(statusCode, responseText, responseHeaders)
        local success = statusCode >= 200 and statusCode < 300

        if Config.Debug.LogResponses then
            print('[CDECAD-API] Response ' .. tostring(statusCode) .. ': ' .. tostring(responseText))
        elseif not success then
            print(('^1[CDECAD-API] %s %s → %d %s^7'):format(
                method, endpoint, statusCode, tostring(responseText):sub(1, 200)
            ))
        end

        local responseData = nil
        if responseText and responseText ~= '' then
            local ok, decoded = pcall(json.decode, responseText)
            if ok then
                responseData = decoded
            end
        end

        if callback then
            callback(success, responseData, statusCode)
        end
    end

    if method == 'GET' then
        PerformHttpRequest(url, requestCallback, 'GET', '', headers)
    else
        local body = data and json.encode(data) or ''
        PerformHttpRequest(url, requestCallback, method, body, headers)
    end
end

local function QueueRequest(method, endpoint, data, callback)
    table.insert(requestQueue, {
        method = method,
        endpoint = endpoint,
        data = data,
        callback = callback
    })

    if not isProcessing then
        ProcessQueue()
    end
end

function ProcessQueue()
    if #requestQueue == 0 then
        isProcessing = false
        return
    end

    isProcessing = true
    local now = GetGameTimer()
    local waitTime = MIN_REQUEST_INTERVAL - (now - lastRequestTime)

    if waitTime > 0 then
        SetTimeout(waitTime, ProcessQueue)
        return
    end

    local request = table.remove(requestQueue, 1)
    lastRequestTime = GetGameTimer()

    MakeRequest(request.method, request.endpoint, request.data, function(success, data, statusCode)
        if request.callback then
            request.callback(success, data, statusCode)
        end
        ProcessQueue()
    end)
end


function API.CreateCivilian(civilianData, callback)
    Utils.Debug('Creating civilian:', civilianData.firstName, civilianData.lastName)

    local payload = {
        firstName = civilianData.firstName,
        lastName = civilianData.lastName,
        dateOfBirth = civilianData.dateOfBirth,
        gender = civilianData.gender,
        nationality = civilianData.nationality or 'American',
        phone = civilianData.phone,
        ssn = civilianData.ssn or civilianData.identifier,
        communityId = Config.COMMUNITY_ID,
        discordId = civilianData.discordId,
        race = civilianData.race,
        hairColor = civilianData.hairColor,
        eyeColor = civilianData.eyeColor,
        height = civilianData.height,
        weight = civilianData.weight,
        address = civilianData.address,
        mugshotUrl = civilianData.mugshotUrl,
        placeOfBirth = civilianData.placeOfBirth
    }

    QueueRequest('POST', '/civilian/fivem-sync-character', payload, callback)
end

function API.UpdateCivilian(civilianId, updateData, callback)
    Utils.Debug('Updating civilian:', civilianId)
    updateData.communityId = Config.COMMUNITY_ID
    QueueRequest('PUT', '/civilian/fivem-update-character/' .. civilianId, updateData, callback)
end

function API.GetCivilian(civilianId, callback)
    MakeRequest('GET', '/civilian/' .. civilianId, nil, callback)
end

function API.GetCivilianBySSN(ssn, callback)
    MakeRequest('GET', '/civilian/fivem-civilian/' .. ssn .. '?communityId=' .. Config.COMMUNITY_ID, nil, callback)
end

function API.DeleteCivilian(identifier, callback)
    Utils.Debug('Deleting civilian:', identifier)
    QueueRequest('DELETE', '/civilian/fivem-delete-character/' .. identifier .. '?communityId=' .. Config.COMMUNITY_ID, nil, callback)
end


function API.RegisterVehicle(vehicleData, callback)
    Utils.Debug('Registering vehicle:', vehicleData.plate)

    local payload = {
        plate = vehicleData.plate,
        ownerId = vehicleData.ownerId,
        communityId = Config.COMMUNITY_ID,
        make = vehicleData.make or 'Unknown',
        model = vehicleData.model,
        color = vehicleData.color or 'Unknown',
        year = vehicleData.year or os.date('%Y')
    }

    QueueRequest('POST', '/civilian/fivem-register-vehicle', payload, callback)
end

function API.GetVehicle(plate, callback)
    local encodedPlate = plate:gsub(' ', '%%20')
    MakeRequest('GET', '/civilian/fivem-vehicle/' .. encodedPlate .. '?communityId=' .. Config.COMMUNITY_ID, nil, callback)
end

function API.BulkSyncVehicles(identifier, vehicles, callback)
    Utils.Debug('Bulk syncing ' .. #vehicles .. ' vehicles for:', identifier)

    local payload = {
        communityId = Config.COMMUNITY_ID,
        ownerId = identifier,
        vehicles = vehicles
    }

    QueueRequest('POST', '/civilian/fivem-sync-vehicles', payload, callback)
end

function API.ForceSyncAllCharacters(characters, callback)
    Utils.Debug('Force syncing ' .. #characters .. ' characters to CAD')

    local payload = {
        communityId = Config.COMMUNITY_ID,
        characters = characters
    }

    MakeRequest('POST', '/civilian/fivem-force-sync-characters', payload, callback)
end

function API.ForceSyncAllVehicles(vehicles, callback)
    Utils.Debug('Force syncing ' .. #vehicles .. ' vehicles to CAD')

    local payload = {
        communityId = Config.COMMUNITY_ID,
        vehicles = vehicles
    }

    MakeRequest('POST', '/civilian/fivem-force-sync-vehicles', payload, callback)
end



function API.HealthCheck(callback)
    PerformHttpRequest(Config.API_URL:gsub('/api', ''), function(statusCode, responseText, responseHeaders)
        local online = statusCode and statusCode >= 200 and statusCode < 500
        if callback then
            callback(online, statusCode)
        end
    end, 'GET', '', {})
end

_G.CDECAD_API = API

return API
