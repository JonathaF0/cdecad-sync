-- Auto-detects ESX / QBCore / QBox / NAT2k15 / vRP and loads the matching
-- adapter. Override with the CDE_CAD_FRAMEWORK convar.
-- Secrets come from convars (server/secrets.lua).

Config = {}


Config.Framework = nil   -- set by shared/framework_detect.lua

-- =============================================================================
-- POSTAL CODE SETTINGS
-- =============================================================================
Config.Postal = {
    Enabled = true,
    Resource = 'nearest-postal',        -- 'nearest-postal' | 'npostal' | 'custom'
    CustomExport = 'your-postal-resource',
    CustomFunction = 'getPostal',
    IncludeIn911 = true,
    IncludeInLocation = true,
    LocationFormat = '{street}, {zone} (Postal: {postal})',
    LocationFormatNoPostal = '{street}, {zone}',
    FallbackText = nil
}

-- =============================================================================
-- SYNC SETTINGS
-- =============================================================================
Config.Sync = {
    OnCharacterLoad   = true,
    OnCharacterCreate = true,
    OnCharacterUpdate = true,
    OnCharacterDelete = true,
    SyncVehicles      = true,
    SyncVehicleStatus = true,
    LocationUpdateInterval = 30,        -- seconds, 0 = disabled
    LocationOnDutyOnly     = true,
}

-- =============================================================================
-- DISCORD ROLE INTEGRATION
-- =============================================================================
Config.Discord = {
    Enabled       = true,
    UseBadgerAPI  = true,
    ExcludedRoles = { 'Police', 'Sheriff', 'State Police', 'Fire', 'EMS', 'Dispatch' },
    ExcludedRoleIds = {},
    ForceSyncRoles  = { 'Civilian', 'Member' },
}

-- =============================================================================
-- 911 CALL SETTINGS
-- =============================================================================
Config.Calls = {
    Enabled            = true,
    Command            = '911',
    AlternateCommand   = 'call911',
    SendCoordinates    = true,
    SendPostal         = true,
    Cooldown           = 30,
    AllowAnonymous     = true,
    AnonymousCommand   = '911anon',
    NotifyOnSuccess    = true,
    NotifyOnAssignment = true,
}

-- =============================================================================
-- NPC REPORTS
-- =============================================================================
Config.NPCReports = {
    Enabled = true,
    Gunshots     = { Enabled = true,  Cooldown = 60,  Radius = 200.0 },
    VehicleTheft = { Enabled = true,  Cooldown = 120 },
    Fights       = { Enabled = true,  Cooldown = 60 },
    SpeedCamera  = { Enabled = false, SpeedLimit = 80 },
}

-- =============================================================================
-- GENDER MAPPING
-- =============================================================================
Config.GenderMapping = {
    ['m'] = 'Male', ['f'] = 'Female',
    ['male'] = 'Male', ['female'] = 'Female',
    [0] = 'Male', [1] = 'Female',
}

-- =============================================================================
-- NOTIFICATIONS
-- =============================================================================
Config.Notifications = {
    UseOxLib = true,
    Duration = 5000,
    Position = 'top-right',
}

-- =============================================================================
-- DEBUG
-- =============================================================================
Config.Debug = {
    Enabled      = false,
    LogRequests  = false,
    LogResponses = false,
}

-- =============================================================================
-- LOCALE
-- =============================================================================
Config.Locale = {
    ['911_sent']                = '911 call sent! Units have been dispatched.',
    ['911_cooldown']            = 'Please wait before making another 911 call.',
    ['911_invalid']             = 'Usage: /911 [message]',
    ['sync_success']            = 'Character synced to CAD.',
    ['sync_failed']             = 'Failed to sync character to CAD.',
    ['vehicle_registered']      = 'Vehicle registered in CAD.',
    ['vehicle_reported_stolen'] = 'Vehicle reported as stolen.',
    ['not_authorized']          = 'You are not authorized for this action.',
    ['cad_offline']             = 'CAD system is currently offline.',
}

-- =============================================================================
-- FRAMEWORK-SPECIFIC OPTIONS
-- =============================================================================
-- Only the keys for the active framework are read at runtime — the rest are
-- harmless leftovers.

-- ESX
Config.ESX = {
    MultiCharacter = {
        Enabled  = false,
        Resource = 'esx_multicharacter',   -- or 'esx_identity'
    },
    -- ESX users.identifier (license:xxx) is used as the CAD SSN by default.
    FieldMapping = {
        firstName   = 'firstName',
        lastName    = 'lastName',
        dateOfBirth = 'dateofbirth',
        gender      = 'sex',
        phone       = 'phone_number',
        ssn         = 'identifier',
    },
}

-- QBCore / QBox (same shape)
Config.QBCore = {
    -- citizenid is always the SSN for QBCore/QBox.
}

-- NAT2k15
Config.NAT2k15 = {
    FrameworkResourceName = 'nat2k15',     -- resource that exports GetCharacter
    CharacterChangePollInterval = 5000,    -- client-side ms; 0 = disabled
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

-- vRP
Config.vRP = {
    DeriveDateOfBirth     = true,
    UseRegistrationAsSSN  = false,   -- false: user_id; true: registration plate code
    SpawnSyncDelay        = 2000,    -- ms after vRP:playerSpawn before extracting identity
    IdentityTable         = 'vrp_user_identities',
    VehiclesTable         = 'vrp_user_vehicles',
    ExcludedGroups        = { 'police', 'sheriff', 'fire', 'ems' },
}
