
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

AddEventHandler('playerSpawned', function()
    SetTimeout(6000, CaptureMugshot)
end)


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
        SetNotificationTextEntry('STRING')
        AddTextComponentString(tostring(message))
        DrawNotification(false, true)
    end
end)
