--[[
    NAT2k15 adapter — client companion.

    NAT2k15's GetCharacter export is CLIENT-side only. The server adapter
    can't see the active character on its own, so this script polls the
    export locally and pushes the active char id to the server whenever it
    changes. The server adapter listens on `cdecad-sync:server:characterChanged`
    and resolves the row from the DB.

    Falls back across a list of export names (different NAT2k15 builds rename
    the function). If none of them are callable, logs a single warning and
    stops polling so we don't spam the console.
]]

-- Run only when this resource is acting as the NAT2k15 adapter.
CreateThread(function()
    -- Wait for shared config to finish loading. Config.Framework is set by
    -- framework_detect.lua before bootstrap; give it a moment to settle.
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
        -- Second return value indicates whether any export was even callable.
        return nil, false
    end

    local lastSeenCharId = nil
    local warnedMissing  = false
    local missingCount   = 0
    local MISSING_LIMIT  = 6   -- ~6 polls of nothing-callable before we give up

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
