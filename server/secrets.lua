local function getConvar(name, default)
    local v = GetConvar(name, '')
    if v == nil or v == '' then return default end
    return v
end

local baseUrl = getConvar('CDE_CAD_API_URL', ''):gsub('/$', '')
if baseUrl ~= '' and not baseUrl:find('/api$') then
    Config.API_URL = baseUrl .. '/api'
else
    Config.API_URL = baseUrl
end

Config.API_KEY      = getConvar('CDE_CAD_API_KEY', '')
Config.COMMUNITY_ID = getConvar('CDE_CAD_COMMUNITY_ID', '')

if Config.API_KEY == ''      then print('^1[CDECAD-SYNC] CDE_CAD_API_KEY is not set.^0') end
if Config.COMMUNITY_ID == '' then print('^1[CDECAD-SYNC] CDE_CAD_COMMUNITY_ID is not set.^0') end
