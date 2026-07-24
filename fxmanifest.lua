fx_version 'cerulean'
game 'gta5'

name 'cde-cad-sync'
description 'CDECAD framework sync (ESX / QBCore / QBox / NAT2k15 / vRP). Auto-detects.'
author 'CDECAD'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/framework_detect.lua',
    'adapters/adapter.lua',
    'shared/utils.lua',
    'shared/vehicle_names.lua',
    'shared/vehicles.lua',
}

server_scripts {
    'server/secrets.lua',
    'server/api.lua',

    'adapters/esx_adapter.lua',
    'adapters/qbcore_adapter.lua',
    'adapters/qbox_adapter.lua',
    'adapters/nat2k15_adapter.lua',
    'adapters/vrp_adapter.lua',

    'server/bootstrap.lua',
    'server/main.lua',
    'server/commands.lua',
}

client_scripts {
    'client/main.lua',
    'adapters/nat2k15_adapter_client.lua',
}

dependencies {
    'ox_lib',
}
