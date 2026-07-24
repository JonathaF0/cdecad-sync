local function activate(name)
    Config.Framework = name
    Adapter.active   = Adapter.impls[name]
    Adapter.name     = name
    if not Adapter.active then
        print(('^1[CDECAD-SYNC] No adapter registered for framework "%s".^0'):format(name))
        return false
    end
    print(('^2[CDECAD-SYNC] Activating adapter: %s^0'):format(name))
    if Adapter.active.RegisterLifecycleEvents then
        Adapter.active.RegisterLifecycleEvents()
    end
    TriggerEvent('cdecad-sync:adapterReady', name)
    return true
end

CreateThread(function()
    if Config.Framework and Adapter.impls[Config.Framework] then
        activate(Config.Framework)
        return
    end

    local deadline = GetGameTimer() + 30000
    while GetGameTimer() < deadline do
        for name, _ in pairs(Adapter.impls) do
            local resources = ({
                esx     = { 'es_extended' },
                qbox    = { 'qbx_core' },
                qbcore  = { 'qb-core' },
                nat2k15 = { 'nat2k15', 'NAT2K15' },
                vrp     = { 'vrp' },
            })[name] or {}
            for _, r in ipairs(resources) do
                if GetResourceState(r) == 'started' then
                    activate(name)
                    return
                end
            end
        end
        Wait(1000)
    end

    print('^1[CDECAD-SYNC] No supported framework started within 30s; idling.^0')
end)
