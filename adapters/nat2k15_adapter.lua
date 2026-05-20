--[[
    NAT2k15 framework adapter.

    NAT2k15 is the trickiest framework we support:
      * It doesn't have a single agreed-upon server-side character-load event,
        so we listen to every common variant defined in
        Config.NAT2k15.Events.CharacterLoaded / .CharacterUnloaded.
      * It doesn't expose a server-side "player" Lua object — character data
        lives entirely in MySQL and must be fetched by id.
      * Its GetCharacter export is CLIENT-side only, so the companion client
        adapter polls it and pushes the active character id to the server
        whenever it changes (nat2k15_adapter_client.lua).

    The "synthetic player" we return is a plain table:
        { source = src, ssn = charDbId, raw = <row from characters table> }
    `raw` is the row most recently observed for that source; consumers should
    treat it as opaque and read it via ExtractCharacterData() so the column
    mapping stays in one place.
]]

local impl = {}

-- =============================================================================
-- INTERNAL STATE
-- =============================================================================
-- activeChars[source] = { ssn = <charDbId number>, raw = <characters row> }
-- Populated by the lifecycle events below and consumed by every Get* method.
local activeChars = {}

-- =============================================================================
-- DB HELPERS
-- =============================================================================

-- Fetch a characters row by primary key. Synchronous wrapper around
-- oxmysql:execute via a flag-flip loop — only used inside the adapter, never
-- on a hot path.
local function FetchCharacterByIdSync(charDbId)
    local cfg = Config.NAT2k15 and Config.NAT2k15.Database
    if not cfg or not charDbId then return nil end

    local tbl = cfg.CharactersTable or 'characters'
    local col = cfg.Columns or {}
    local idCol = col.Id or 'id'

    local done, row = false, nil
    exports.oxmysql:execute(
        string.format('SELECT * FROM `%s` WHERE `%s` = ? LIMIT 1', tbl, idCol),
        { charDbId },
        function(rows)
            row  = rows and rows[1] or nil
            done = true
        end
    )

    -- Bounded wait — bail after ~2s rather than hanging the caller forever.
    local deadline = GetGameTimer() + 2000
    while not done and GetGameTimer() < deadline do Wait(5) end
    return row
end

-- Async variant used by GetPlayerByIdentifier.
local function FetchCharacterByIdAsync(charDbId, cb)
    local cfg = Config.NAT2k15 and Config.NAT2k15.Database
    if not cfg or not charDbId then cb(nil); return end

    local tbl   = cfg.CharactersTable or 'characters'
    local col   = cfg.Columns or {}
    local idCol = col.Id or 'id'

    exports.oxmysql:execute(
        string.format('SELECT * FROM `%s` WHERE `%s` = ? LIMIT 1', tbl, idCol),
        { charDbId },
        function(rows) cb(rows and rows[1] or nil) end
    )
end

-- Pull a char id out of whatever shape an event handed us.
local function ParseEventCharId(eventArg)
    if type(eventArg) == 'number' then
        return eventArg
    elseif type(eventArg) == 'string' then
        return tonumber(eventArg)
    elseif type(eventArg) == 'table' then
        return tonumber(eventArg.id or eventArg.charId or eventArg.characterId or eventArg.character_id)
    end
    return nil
end

-- =============================================================================
-- PLAYER LOOKUP
-- =============================================================================

function impl.GetPlayer(source)
    if not source then return nil end
    local entry = activeChars[source]
    if not entry then return nil end
    return {
        source = source,
        ssn    = entry.ssn,
        raw    = entry.raw,
    }
end

function impl.GetAllPlayers()
    local result = {}
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        if src then
            local p = impl.GetPlayer(src)
            if p then result[#result + 1] = p end
        end
    end
    return result
end

function impl.GetPlayerByIdentifier(charDbId)
    local id = tonumber(charDbId)
    if not id then return nil end

    local row = FetchCharacterByIdSync(id)
    if not row then return nil end

    return {
        source = nil,         -- offline lookup; caller shouldn't assume a session
        ssn    = id,
        raw    = row,
    }
end

-- =============================================================================
-- IDENTITY
-- =============================================================================

function impl.ExtractCharacterData(player)
    if not player or not player.raw then return nil end

    local col = (Config.NAT2k15 and Config.NAT2k15.Database and Config.NAT2k15.Database.Columns) or {}
    local row = player.raw

    local function read(key, fallback)
        local c = col[key]
        if not c then return fallback end
        local v = row[c]
        if v == nil then return fallback end
        return v
    end

    local idVal = read('Id')
    local identifier
    if player.source then
        identifier = impl.GetPlayerIdentifier(player.source, 'discord')
                  or impl.GetPlayerIdentifier(player.source, 'license')
    end
    if not identifier and col.Discord and row[col.Discord] then
        identifier = 'discord:' .. tostring(row[col.Discord])
    end

    return {
        firstName   = read('FirstName'),
        lastName    = read('LastName'),
        dateOfBirth = Utils.FormatDate(read('Dob')),
        gender      = Utils.ConvertGender(read('Gender')),
        phone       = nil,                  -- NAT2k15 default schema has no phone column
        ssn         = idVal and tostring(idVal) or nil,
        identifier  = identifier,
        nationality = 'American',
    }
end

function impl.GetPlayerIdentifier(source, idType)
    if not source or not idType then return nil end
    local prefix = tostring(idType) .. ':'
    for i = 0, GetNumPlayerIdentifiers(source) - 1 do
        local ident = GetPlayerIdentifier(source, i)
        if ident and ident:sub(1, #prefix) == prefix then
            return ident
        end
    end
    return nil
end

function impl.GetCharacterSSN(source)
    local entry = activeChars[source]
    if not entry or not entry.ssn then return nil end
    return tostring(entry.ssn)
end

-- =============================================================================
-- VEHICLES
-- =============================================================================
-- NAT2k15's default schema doesn't ship a player-owned-vehicles table, so we
-- can't enumerate them server-side. Callers should fall back to the /regveh
-- workflow (player explicitly registers the vehicle they're in).
function impl.GetPlayerVehicles(source, callback)
    if callback then callback({}) end
end

-- =============================================================================
-- JOB / ON-DUTY
-- =============================================================================

function impl.GetPlayerJob(source)
    local entry = activeChars[source]
    if not entry or not entry.raw then return nil end

    local col = (Config.NAT2k15 and Config.NAT2k15.Database and Config.NAT2k15.Database.Columns) or {}
    local deptCol = col.Dept
    if not deptCol then return nil end

    local dept = entry.raw[deptCol]
    if not dept or dept == '' then return nil end

    return { name = tostring(dept), grade = 0 }
end

-- NAT2k15 has no on-duty concept at the framework level, so location syncing
-- is effectively disabled for this adapter.
function impl.IsOnDuty(source)
    return false
end

-- =============================================================================
-- NOTIFICATIONS
-- =============================================================================

function impl.Notify(source, level, message)
    if not source then return end
    TriggerClientEvent('cdecad-sync:client:notify', source, level, message)
end

-- =============================================================================
-- LIFECYCLE
-- =============================================================================

local function emitLoaded(src, charId, row)
    activeChars[src] = { ssn = charId, raw = row }
    Utils.Debug(('nat2k15: characterLoaded src=%s charId=%s'):format(tostring(src), tostring(charId)))
    TriggerEvent('cdecad-sync:characterLoaded', src, tostring(charId), false)
end

local function emitUnloaded(src)
    local entry = activeChars[src]
    if not entry then return end
    local ssn = entry.ssn
    activeChars[src] = nil
    Utils.Debug(('nat2k15: characterUnloaded src=%s charId=%s'):format(tostring(src), tostring(ssn)))
    TriggerEvent('cdecad-sync:characterUnloaded', src, ssn and tostring(ssn) or nil)
end

-- Resolve, cache and emit a load given whatever id we have.
local function resolveAndLoad(src, charId)
    if not src or src == 0 then return end
    if not charId then return end

    -- Avoid redundant fires for the same character on the same source.
    local existing = activeChars[src]
    if existing and existing.ssn == charId and existing.raw then
        return
    end

    FetchCharacterByIdAsync(charId, function(row)
        if not row then
            Utils.Debug(('nat2k15: no row found for charId=%s'):format(tostring(charId)))
            return
        end
        emitLoaded(src, charId, row)
    end)
end

function impl.RegisterLifecycleEvents()
    local nat = Config.NAT2k15 or {}
    local events = nat.Events or {}

    -- --- Load events ------------------------------------------------------
    local loadNames = events.CharacterLoaded or {}
    local seenLoad  = {}
    for _, name in ipairs(loadNames) do
        if name and not seenLoad[name] then
            seenLoad[name] = true
            RegisterNetEvent(name)
            AddEventHandler(name, function(eventArg)
                local src = source
                if not src or src == 0 then return end
                local charId = ParseEventCharId(eventArg)
                Utils.Debug(('nat2k15 event %s src=%s arg=%s'):format(name, tostring(src), tostring(charId)))
                if charId then
                    resolveAndLoad(src, charId)
                else
                    -- No id in the event payload — wait for the client poll
                    -- to push one via cdecad-sync:server:characterChanged.
                    Utils.Debug('nat2k15: load event with no id; awaiting client push')
                end
            end)
        end
    end

    -- --- Unload events ----------------------------------------------------
    local unloadNames = events.CharacterUnloaded or {}
    local seenUnload  = {}
    for _, name in ipairs(unloadNames) do
        if name and not seenUnload[name] then
            seenUnload[name] = true
            RegisterNetEvent(name)
            AddEventHandler(name, function(eventArg)
                local src = source
                if (not src or src == 0) and type(eventArg) == 'number' then
                    src = eventArg
                end
                if not src or src == 0 then return end
                emitUnloaded(src)
            end)
        end
    end

    -- --- Client-side push fallback ---------------------------------------
    -- The client polls NAT2k15's client-only GetCharacter export and pushes
    -- the active char id here whenever it changes. This is the only path
    -- that works on NAT2k15 builds that don't fire any server-side event.
    RegisterNetEvent('cdecad-sync:server:characterChanged', function(charId)
        local src = source
        if not src or src == 0 then return end

        if charId == nil then
            emitUnloaded(src)
            return
        end

        local id = tonumber(charId)
        if not id then return end

        local existing = activeChars[src]
        if existing and existing.ssn == id then return end

        -- If we had a different char loaded, fire unload first so consumers
        -- see a clean switch.
        if existing and existing.ssn and existing.ssn ~= id then
            emitUnloaded(src)
        end

        resolveAndLoad(src, id)
    end)

    -- --- Drop cleanup -----------------------------------------------------
    AddEventHandler('playerDropped', function()
        local src = source
        if not src then return end
        if activeChars[src] then
            emitUnloaded(src)
        end
        activeChars[src] = nil
    end)

    Utils.Debug('nat2k15 adapter: lifecycle events registered')
end

-- =============================================================================
-- REGISTER
-- =============================================================================
Adapter.register('nat2k15', impl)
