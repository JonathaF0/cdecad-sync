
Config = {}

Config.Framework = nil

Config.Sync = {
    OnCharacterLoad   = true,
    OnCharacterCreate = true,
    OnCharacterUpdate = true,
    OnCharacterDelete = true,
    SyncVehicles      = true,
    SyncVehicleStatus = true,
}

Config.Notifications = {
    UseOxLib = true,
    Duration = 5000,
    Position = 'top-right',
}

Config.Debug = {
    Enabled      = false,
    LogRequests  = false,
    LogResponses = false,
}

Config.GenderMapping = {
    ['m'] = 'Male', ['f'] = 'Female',
    ['male'] = 'Male', ['female'] = 'Female',
    [0] = 'Male', [1] = 'Female',
}

Config.Locale = {
    ['sync_success']       = 'Character synced to CAD.',
    ['sync_failed']        = 'Failed to sync character to CAD.',
    ['vehicle_registered'] = 'Vehicle registered in CAD.',
}


Config.ESX = {
    MultiCharacter = {
        Enabled  = false,
        Resource = 'esx_multicharacter',
    },
    FieldMapping = {
        firstName   = 'firstName',
        lastName    = 'lastName',
        dateOfBirth = 'dateofbirth',
        gender      = 'sex',
        phone       = 'phone_number',
        ssn         = 'identifier',
    },
}

Config.QBCore = {}

Config.NAT2k15 = {
    FrameworkResourceName = 'nat2k15',
    CharacterChangePollInterval = 5000,
    Database = {
        CharactersTable = 'characters',
        Columns = {
            Id        = 'id',
            Discord   = 'discord',
            FirstName = 'first_name',
            LastName  = 'last_name',
            Dob       = 'dob',
            Gender    = 'gender',
            Dept      = 'dept',
        },
    },
    Events = {
        CharacterLoaded   = { 'nat2k15:server:charLoaded', 'nat2k15:characterLoaded', 'nat2k15:CharacterLoaded' },
        CharacterUnloaded = { 'nat2k15:server:charUnloaded', 'nat2k15:characterUnloaded' },
    },
}

Config.vRP = {
    DeriveDateOfBirth     = true,
    UseRegistrationAsSSN  = false,
    SpawnSyncDelay        = 2000,
    IdentityTable         = 'vrp_user_identities',
    VehiclesTable         = 'vrp_user_vehicles',
    ExcludedGroups        = { 'police', 'sheriff', 'fire', 'ems' },
}
