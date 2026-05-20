Adapter = Adapter or { impls = {}, active = nil, name = nil }
_G.Adapter = Adapter

function Adapter.register(name, impl)
    Adapter.impls[name] = impl
    if Config and Config.Framework == name then
        Adapter.active = impl
        Adapter.name   = name
    end
end

--[[
    Contract every adapter must implement:

    impl.GetPlayer(source)                  -> player | nil
    impl.GetAllPlayers()                    -> array of players
    impl.GetPlayerByIdentifier(identifier)  -> player | nil

    impl.ExtractCharacterData(player) -> {
        firstName, lastName, dateOfBirth, gender, phone, ssn,
        identifier (discord/license string for logs), nationality
    } | nil

    impl.GetPlayerIdentifier(source, type)  -- type ∈ {'license','discord','steam','ip','fivem'}
    impl.GetCharacterSSN(source)            -> string | nil  -- stable per-character id

    impl.GetPlayerVehicles(source, callback) -- async; callback({ {plate, make, model, color, year?}, ... })

    impl.GetPlayerJob(source) -> { name, grade } | nil
    impl.IsOnDuty(source)     -> boolean

    impl.RegisterLifecycleEvents()
        Translate the framework's native events into the unified ones:
          cdecad-sync:characterLoaded(source, ssn, isNew)
          cdecad-sync:characterUnloaded(source, ssn)
          cdecad-sync:characterUpdated(source, ssn)
          cdecad-sync:characterDeleted(ssn)

    impl.Notify(source, level, message)  -- level: 'success'|'error'|'info'
--]]
