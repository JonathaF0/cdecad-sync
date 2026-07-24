Adapter = Adapter or { impls = {}, active = nil, name = nil }
_G.Adapter = Adapter

function Adapter.register(name, impl)
    Adapter.impls[name] = impl
    if Config and Config.Framework == name then
        Adapter.active = impl
        Adapter.name   = name
    end
end







