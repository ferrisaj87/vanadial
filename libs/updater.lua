--[[
* Vana'Dial — GitHub raw download updater (same pattern as Anglin).
* Fetches addon.version from main, downloads listed files over HTTPS, overwrites in place.
]]--

local M = {};

local https = require('socket.ssl.https');
local http  = require('socket.http');
http.TIMEOUT = 15;

local RAW_BASE = 'https://raw.githubusercontent.com/ferrisaj87/vanadial/main/';

local UPDATE_VERSION_URL = RAW_BASE .. 'vanadial.lua';

-- Seconds after load before the login update notice (avoid login chat spam).
local LOGIN_CHECK_DELAY_SEC = 15;

-- All runtime Lua files shipped with the addon (relative to addons/vanadial/).
local UPDATE_RELATIVE = {
    'vanadial.lua',
    'display.lua',
    'popups.lua',
    'config.lua',
    'timers.lua',
    'data.lua',
    'libs/color.lua',
    'libs/imgui_compat.lua',
    'libs/texturemanager.lua',
    'libs/imtext.lua',
    'libs/windowbackground.lua',
    'libs/memory.lua',
    'libs/updater.lua',
};

local _version            = '0.0.0';
local _loginCheckAt        = nil;
local _loginCheckDone      = false;

local UPDATE_FILES = {};

local function BuildUpdateFiles()
    local root = AshitaCore:GetInstallPath() or '';
    local addonRoot = (root .. 'addons\\vanadial\\'):gsub('[\\/]+$', '') .. '\\';
    UPDATE_FILES = {};
    for _, rel in ipairs(UPDATE_RELATIVE) do
        local urlPath = rel:gsub('\\', '/');
        UPDATE_FILES[#UPDATE_FILES + 1] = {
            url   = RAW_BASE .. urlPath,
            path  = addonRoot .. rel:gsub('/', '\\'),
            label = rel:gsub('\\', '/'),
        };
    end
end

BuildUpdateFiles();

-- ── Version helpers ─────────────────────────────────────────────────────────────

local function ParseVersion(ver)
    local parts = {};
    for n in tostring(ver or ''):gsub('^%s*v', ''):gmatch('%d+') do
        parts[#parts + 1] = tonumber(n) or 0;
    end
    return parts;
end

local function VersionGreater(a, b)
    local pa = ParseVersion(a);
    local pb = ParseVersion(b);
    for i = 1, math.max(#pa, #pb) do
        local ai = pa[i] or 0;
        local bi = pb[i] or 0;
        if ai > bi then return true; end
        if ai < bi then return false; end
    end
    return false;
end

function M.IsNewer(remote, localVer)
    return VersionGreater(remote, localVer);
end

-- FFXI chat is not UTF-8; strip non-ASCII so glyphs do not become garbage.
local function SanitizeChat(text)
    return tostring(text or ''):gsub('[^\32-\126]', '');
end

local function PrintMsg(msg)
    print("[Vana'Dial] " .. SanitizeChat(msg));
end

local function ParseVersionFromBody(body)
    if not body then return nil; end
    local remote = body:match("addon%.version%s*=%s*'([^']+)'");
    if not remote then
        remote = body:match('addon%.version%s*=%s*"([^"]+)"');
    end
    return remote;
end

local function FetchUrl(url)
    return pcall(function()
        return https.request(url .. '?t=' .. os.time());
    end);
end

local function FetchRemoteVersion()
    local ok, body, code = FetchUrl(UPDATE_VERSION_URL);
    if not ok or code ~= 200 or not body then
        return nil, code;
    end
    return ParseVersionFromBody(body), 200;
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.Init(version)
    _version = version or _version;
end

function M.GetVersion()
    return _version;
end

function M.ScheduleLoginCheck(delaySec)
    _loginCheckAt   = os.clock() + (delaySec or LOGIN_CHECK_DELAY_SEC);
    _loginCheckDone = false;
end

function M.TickLoginCheck()
    if _loginCheckDone or not _loginCheckAt or os.clock() < _loginCheckAt then
        return;
    end
    _loginCheckDone = true;
    _loginCheckAt = nil;

    local ok = pcall(function()
        local remote = FetchRemoteVersion();
        if remote and remote ~= '' and _version and _version ~= ''
            and VersionGreater(remote, _version) then
            PrintMsg('There is an update available.');
        end
    end);
    if not ok then
        -- Silent on login; user can run /vd checkupdate manually.
    end
end

function M.CheckAndNotify(manual)
    local remote, code = FetchRemoteVersion();

    if not remote then
        if manual then
            PrintMsg('Could not check for updates. Try again later.');
        end
        return;
    end

    if VersionGreater(remote, _version) then
        PrintMsg('There is an update available.');
    elseif manual then
        PrintMsg('Already up to date.');
    end
end

function M.RunUpdate()
    local ok, body, code = FetchUrl(UPDATE_VERSION_URL);

    if not ok or code ~= 200 or not body then
        PrintMsg('Could not check for updates. Try again later.');
        return;
    end

    local remote = ParseVersionFromBody(body);
    if not remote then
        PrintMsg('Could not check for updates. Try again later.');
        return;
    end

    if not VersionGreater(remote, _version) then
        PrintMsg('Already up to date.');
        return;
    end

    PrintMsg('Updating Vana''Dial....');

    local allOk = true;

    for _, f in ipairs(UPDATE_FILES) do
        local fok, fbody, fcode = FetchUrl(f.url);

        if not fok or fcode ~= 200 or not fbody or fbody == '' then
            allOk = false;
            break;
        end

        local out = io.open(f.path, 'wb');
        if not out then
            allOk = false;
            break;
        end
        out:write(fbody);
        out:close();
    end

    if allOk then
        PrintMsg('Addon has been successfully updated, use /addon reload vanadial to reload newest version.');
    else
        PrintMsg('Update failed. Try again or download from GitHub.');
    end
end

return M;
