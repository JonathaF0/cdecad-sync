-- =============================================================================
-- MUGSHOT CAPTURE
-- =============================================================================

local function CaptureMugshot()
    if GetResourceState('MugShotBase64') ~= 'started' then
        Utils.Debug('MugShotBase64 not running, skipping mugshot capture')
        return
    end

    local ok, result = pcall(function()
        return exports['MugShotBase64']:GetMugShotBase64(PlayerPedId(), true)
    end)

    if ok and result and result ~= '' then
        Utils.Debug('Mugshot captured, sending to server')
        TriggerServerEvent('cdecad-sync:server:updateMugshot', result)
    end
end

-- Schedule mugshot capture on spawn / character switch. The server fires this
-- via the adapter's lifecycle plumbing, but we also self-trigger on first load
-- so framework-less servers still get a mugshot.
AddEventHandler('playerSpawned', function()
    SetTimeout(6000, CaptureMugshot)
end)

-- =============================================================================
-- NOTIFICATIONS
-- =============================================================================

RegisterNetEvent('cdecad-sync:client:notify', function(level, message)
    if Config.Notifications.UseOxLib and lib and lib.notify then
        lib.notify({
            title       = 'CDECAD',
            description = message,
            type        = level,
            duration    = Config.Notifications.Duration,
            position    = Config.Notifications.Position,
        })
    else
        -- Fallback: GTA native notification
        SetNotificationTextEntry('STRING')
        AddTextComponentString(tostring(message))
        DrawNotification(false, true)
    end
end)

-- =============================================================================
-- POSTAL CODE
-- =============================================================================

function GetPostalCode()
    if not Config.Postal or not Config.Postal.Enabled then return nil end

    local postal
    local resource = Config.Postal.Resource or 'nearest-postal'

    if resource == 'nearest-postal' then
        local ok, r = pcall(function() return exports['nearest-postal']:getPostal() end)
        if ok then postal = r end
    elseif resource == 'npostal' then
        local ok, r = pcall(function() return exports.npostal:npostal() end)
        if ok then postal = r end
    elseif resource == 'custom' then
        local exportName = Config.Postal.CustomExport
        local funcName   = Config.Postal.CustomFunction or 'getPostal'
        if exportName then
            local ok, r = pcall(function() return exports[exportName][funcName]() end)
            if ok then postal = r end
        end
    end

    return postal and tostring(postal) or Config.Postal.FallbackText
end

-- =============================================================================
-- LOCATION HELPERS
-- =============================================================================

function GetCurrentStreetName()
    local coords = GetEntityCoords(PlayerPedId())
    local s, c = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street   = GetStreetNameFromHashKey(s)
    local crossing = GetStreetNameFromHashKey(c)
    if crossing and crossing ~= '' then
        return street .. ' & ' .. crossing
    end
    return street
end

function GetCurrentZoneName()
    local coords = GetEntityCoords(PlayerPedId())
    return GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
end

function FormatLocationString(street, zone, postal)
    local fmt
    if postal and Config.Postal.IncludeInLocation then
        fmt = Config.Postal.LocationFormat or '{street}, {zone} (Postal: {postal})'
        fmt = fmt:gsub('{postal}', postal)
    else
        fmt = Config.Postal.LocationFormatNoPostal or '{street}, {zone}'
    end
    fmt = fmt:gsub('{street}', street or 'Unknown')
    fmt = fmt:gsub('{zone}',   zone   or 'Unknown')
    return fmt
end

function GetLocationInfo()
    local coords = GetEntityCoords(PlayerPedId())
    local street = GetCurrentStreetName()
    local zone   = GetCurrentZoneName()
    local postal = GetPostalCode()

    return {
        street   = street,
        zone     = zone,
        postal   = postal,
        location = FormatLocationString(street, zone, postal),
        coords   = coords,
        x = coords.x, y = coords.y, z = coords.z,
    }
end

function GetCurrentVehicle()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh == 0 then return nil end
    return {
        vehicle = veh,
        plate   = GetVehicleNumberPlateText(veh):gsub('%s+', ''),
        model   = GetDisplayNameFromVehicleModel(GetEntityModel(veh)),
        class   = GetVehicleClass(veh),
    }
end

function Prepare911CallData(callType, anonymous)
    local loc = GetLocationInfo()
    return {
        callType  = callType,
        location  = loc.location,
        street    = loc.street,
        zone      = loc.zone,
        postal    = loc.postal,
        coords    = loc.coords,
        anonymous = anonymous or false,
    }
end

-- =============================================================================
-- EXPORTS
-- =============================================================================

exports('GetLocationInfo',     GetLocationInfo)
exports('GetCurrentVehicle',   GetCurrentVehicle)
exports('Prepare911CallData',  Prepare911CallData)
exports('GetPostalCode',       GetPostalCode)
