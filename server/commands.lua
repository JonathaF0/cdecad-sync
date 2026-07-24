

RegisterCommand('cadsync', function(src, args)
    local target = src
    if args[1] then target = tonumber(args[1]) end
    if not target or target == 0 then return end

    if not Adapter.active or not Adapter.active.GetPlayer(target) then
        if src > 0 then
            TriggerClientEvent('cdecad-sync:client:notify', src, 'error', 'Player not found')
        else
            print('[CDECAD-SYNC] Player not found: ' .. tostring(target))
        end
        return
    end

    exports[GetCurrentResourceName()]:ForceSync(target)
    if src > 0 then
        TriggerClientEvent('cdecad-sync:client:notify', src, 'success', 'Syncing player to CAD...')
    else
        print('[CDECAD-SYNC] Syncing player ' .. target .. ' to CAD')
    end
end, true)

RegisterCommand('cadstatus', function(src)
    CDECAD_API.HealthCheck(function(online, statusCode)
        local fwBadge = Config.Framework and (' (framework: ' .. Config.Framework .. ')') or ' (no framework)'
        local message = (online and 'CAD is online' or 'CAD is offline') ..
                        ' (HTTP ' .. tostring(statusCode) .. ')' .. fwBadge
        if src > 0 then
            TriggerClientEvent('cdecad-sync:client:notify', src, online and 'success' or 'error', message)
        else
            print('[CDECAD-SYNC] ' .. message)
        end
    end)
end, true)

RegisterCommand('cadlookup', function(src, args)
    if not args[1] then
        if src > 0 then
            TriggerClientEvent('cdecad-sync:client:notify', src, 'error', 'Usage: /cadlookup [identifier or plate]')
        else
            print('[CDECAD-SYNC] Usage: /cadlookup [identifier or plate]')
        end
        return
    end

    local searchTerm = args[1]:upper()

    if #searchTerm <= 8 then
        CDECAD_API.GetVehicle(searchTerm, function(success, data)
            if success and data then
                local info = ('Vehicle: %s %s %s | Owner: %s | Stolen: %s'):format(
                    data.year or '?', data.color or '?', data.model or '?',
                    data.owner or 'Unknown', data.stolen and 'YES' or 'No')
                if src > 0 then
                    TriggerClientEvent('cdecad-sync:client:notify', src, 'info', info)
                else
                    print('[CDECAD-SYNC] ' .. info)
                end
            else
                CDECAD_API.GetCivilianBySSN(searchTerm, function(civSuccess, civData)
                    if civSuccess and civData then
                        local info = ('Civilian: %s | DOB: %s | Phone: %s'):format(
                            civData.name or 'Unknown', civData.dob or '?', civData.phone or '?')
                        if src > 0 then
                            TriggerClientEvent('cdecad-sync:client:notify', src, 'info', info)
                        else
                            print('[CDECAD-SYNC] ' .. info)
                        end
                    else
                        if src > 0 then
                            TriggerClientEvent('cdecad-sync:client:notify', src, 'error', 'No records found')
                        else
                            print('[CDECAD-SYNC] No records found for: ' .. searchTerm)
                        end
                    end
                end)
            end
        end)
    end
end, true)

TriggerEvent('chat:addSuggestion', '/cadsync',    'Sync a player to the CAD (Admin)', { { name = 'playerId', help = 'Target player id' } })
TriggerEvent('chat:addSuggestion', '/cadstatus',  'Check CAD connection status (Admin)', {})
TriggerEvent('chat:addSuggestion', '/cadlookup',  'Look up an identifier or plate in CAD (Admin)', { { name = 'term', help = 'identifier or plate' } })
