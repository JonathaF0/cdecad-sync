
Utils = {}
_G.Utils = Utils

function Utils.Debug(...)
    if Config.Debug.Enabled then
        print('[CDECAD-SYNC]', ...)
    end
end

function Utils.FormatDate(dateStr)
    if not dateStr then return nil end
    local s = tostring(dateStr):gsub('^%s+', ''):gsub('%s+$', '')

    local a, b, y = s:match('^(%d%d?)/(%d%d?)/(%d%d%d%d)$')
    if a and b and y then
        local mo, da = tonumber(a), tonumber(b)
        if mo > 12 and da >= 1 and da <= 12 then mo, da = da, mo end
        return ('%s-%02d-%02d'):format(y, mo, da)
    end

    local yy, p2, p3 = s:match('^(%d%d%d%d)-(%d%d?)-(%d%d?)$')
    if yy and p2 and p3 then
        local mo, da = tonumber(p2), tonumber(p3)
        if mo > 12 and da >= 1 and da <= 12 then mo, da = da, mo end
        return ('%s-%02d-%02d'):format(yy, mo, da)
    end

    return s
end

function Utils.ConvertGender(gender)
    if type(gender) == 'string' then
        return Config.GenderMapping[gender:lower()] or Config.GenderMapping[gender] or 'Unknown'
    end
    if type(gender) == 'number' then
        return Config.GenderMapping[gender] or 'Unknown'
    end
    return 'Unknown'
end

function Utils.GenerateUID()
    return string.format('%x%x%x',
        math.random(0, 0xFFFF),
        math.random(0, 0xFFFF),
        os.time()
    )
end

function Utils.Sanitize(str)
    if not str then return '' end
    return tostring(str):gsub('[<>"\']', '')
end

function Utils.TableContains(tbl, value)
    if not tbl then return false end
    for _, v in ipairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

function Utils.DeepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[Utils.DeepCopy(orig_key)] = Utils.DeepCopy(orig_value)
        end
        setmetatable(copy, Utils.DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

function Utils.MergeTables(t1, t2)
    for k, v in pairs(t2) do
        if type(v) == 'table' and type(t1[k]) == 'table' then
            Utils.MergeTables(t1[k], v)
        else
            t1[k] = v
        end
    end
    return t1
end

local rateLimits = {}

function Utils.CheckRateLimit(key, cooldown)
    local now = os.time()
    if rateLimits[key] and (now - rateLimits[key]) < cooldown then
        return false, cooldown - (now - rateLimits[key])
    end
    rateLimits[key] = now
    return true
end

function Utils.GetIdentifier(source, idType)
    if not source then return nil end

    local identifiers = GetPlayerIdentifiers(source)
    for _, id in ipairs(identifiers) do
        if string.find(id, idType .. ':') then
            return id:gsub(idType .. ':', '')
        end
    end
    return nil
end

function Utils.GetDiscordId(source)
    return Utils.GetIdentifier(source, 'discord')
end

function Utils.GetLicense(source)
    return Utils.GetIdentifier(source, 'license')
end

function Utils.GetSteamId(source)
    return Utils.GetIdentifier(source, 'steam')
end

function Utils.ValidateIdentifier(identifier)
    if not identifier then return false end
    return string.len(identifier) >= 5
end

function Utils.FormatPhone(phone)
    if not phone then return nil end
    local cleaned = phone:gsub('[^0-9]', '')
    if string.len(cleaned) == 10 then
        return string.format('%s-%s-%s',
            cleaned:sub(1, 3),
            cleaned:sub(4, 6),
            cleaned:sub(7, 10)
        )
    end
    return phone
end

function Utils.GetDistance(coords1, coords2)
    if not coords1 or not coords2 then return 999999.0 end

    local x1, y1, z1 = coords1.x or coords1[1], coords1.y or coords1[2], coords1.z or coords1[3]
    local x2, y2, z2 = coords2.x or coords2[1], coords2.y or coords2[2], coords2.z or coords2[3]

    return math.sqrt(
        (x2 - x1) ^ 2 +
        (y2 - y1) ^ 2 +
        (z2 - z1) ^ 2
    )
end

return Utils
