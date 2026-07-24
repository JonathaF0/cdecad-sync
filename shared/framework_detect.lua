local FRAMEWORK_RESOURCES = {
    esx     = { 'es_extended' },
    qbox    = { 'qbx_core' },
    qbcore  = { 'qb-core' },
    nat2k15 = { 'nat2k15', 'NAT2K15' },
    vrp     = { 'vrp' },
}

local DETECTION_ORDER = { 'qbox', 'qbcore', 'esx', 'nat2k15', 'vrp' }

local function isStarted(name)
    return GetResourceState(name) == 'started' or GetResourceState(name) == 'starting'
end

local function autodetect()
    if IsDuplicityVersion() then
        local override = GetConvar('CDE_CAD_FRAMEWORK', '')
        if override ~= '' then
            override = override:lower()
            if FRAMEWORK_RESOURCES[override] then
                return override, 'convar'
            end
            print('^3[CDECAD-SYNC] CDE_CAD_FRAMEWORK="' .. override .. '" unknown; auto-detecting.^0')
        end
    end

    for _, fw in ipairs(DETECTION_ORDER) do
        for _, resName in ipairs(FRAMEWORK_RESOURCES[fw]) do
            if isStarted(resName) then return fw, resName end
        end
    end
    return nil, nil
end

local framework, sourceHint = autodetect()
Config.Framework = framework

if IsDuplicityVersion() then
    if framework then
        print(('^2[CDECAD-SYNC] Framework: %s (%s)^0'):format(framework, sourceHint))
    else
        print('^1[CDECAD-SYNC] No supported framework found; idling. (es_extended, qb-core, qbx_core, nat2k15, vrp)^0')
    end
end
