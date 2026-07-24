


CreateThread(function()
    local deadline = GetGameTimer() + 15000
    while (not Config or Config.Framework == nil) and GetGameTimer() < deadline do
        Wait(250)
    end

    if not Config or Config.Framework ~= 'nat2k15' then
        return
    end

    local nat      = Config.NAT2k15 or {}
    local interval = tonumber(nat.CharacterChangePollInterval) or 0
    if interval <= 0 then
        if Utils and Utils.Debug then
            Utils.Debug('nat2k15 client adapter: poll disabled (CharacterChangePollInterval <= 0)')
        end
        return
    end

    local configuredResource = nat.FrameworkResourceName or 'nat2k15'
    local resourceNames      = { configuredResource, 'nat2k15', 'NAT2K15', 'NAT2k15' }
    local exportNames        = { 'GetCharacter', 'GetPlayerData', 'GetActiveCharacter' }

    local function ReadActiveCharId()
        for _, resourceName in ipairs(resourceNames) do
            if GetResourceState(resourceName) == 'started' then
                for _, exportName in ipairs(exportNames) do
                    local ok, result = pcall(function()
                        return exports[resourceName][exportName](exports[resourceName])
                    end)
                    if ok and type(result) == 'table' then
                        local id = result.id or result.charId or result.characterId or result.character_id
                        if id then return tonumber(id), true end
                    elseif ok and type(result) == 'number' then
                        return result, true
                    end
                end
            end
        end
        return nil, false
    end

    local lastSeenCharId = nil
    local warnedMissing  = false
    local missingCount   = 0
    local MISSING_LIMIT  = 6

    if Utils and Utils.Debug then
        Utils.Debug(('nat2k15 client adapter: polling every %dms'):format(interval))
    end

    while true do
        Wait(interval)

        local charId, exportAvailable = ReadActiveCharId()

        if not exportAvailable then
            missingCount = missingCount + 1
            if missingCount >= MISSING_LIMIT then
                if not warnedMissing then
                    print('^3[CDECAD-SYNC] nat2k15 client adapter: no GetCharacter export found on resource "'
                        .. tostring(configuredResource) .. '". Stopping poll. ' ..
                        'Set Config.NAT2k15.FrameworkResourceName to your build\'s resource name.^0')
                    warnedMissing = true
                end
                return
            end
        else
            missingCount = 0
        end

        if charId and charId ~= lastSeenCharId then
            if Utils and Utils.Debug then
                Utils.Debug(('nat2k15 client poll: char changed %s -> %s')
                    :format(tostring(lastSeenCharId), tostring(charId)))
            end
            lastSeenCharId = charId
            TriggerServerEvent('cdecad-sync:server:characterChanged', charId)
        elseif not charId and lastSeenCharId ~= nil then
            if Utils and Utils.Debug then
                Utils.Debug('nat2k15 client poll: active character cleared')
            end
            lastSeenCharId = nil
            TriggerServerEvent('cdecad-sync:server:characterChanged', nil)
        end
    end
end)
