--[[
* Vana'Dial — GitHub raw download updater (same pattern as Anglin).
* Fetches addon.version from main, downloads listed files over HTTPS, overwrites in place.
]]--

local M = {};

local https = require('socket.ssl.https');

local RAW_BASE = 'https://raw.githubusercontent.com/ferrisaj87/vanadial/main/';

local UPDATE_VERSION_URL = RAW_BASE .. 'vanadial.lua';

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

local _version             = '0.0.0';
local _loginCheckAt        = nil;
local _updateMessageDelay  = nil;
local _latestVersion       = nil;

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
    for line in SanitizeChat(msg):gmatch('[^\n]+') do
        print("[Vana'Dial] " .. line);
    end
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
    _loginCheckAt = os.clock() + (delaySec or 8);
end

local function CheckForUpdateQuiet()
    local remote = FetchRemoteVersion();
    if not remote or remote == '' or not _version or _version == '' then
        return;
    end

    _latestVersion = remote;

    if VersionGreater(remote, _version) then
        _updateMessageDelay = os.clock() + 2;
    end
end

function M.TickLoginCheck()
    if _updateMessageDelay and os.clock() >= _updateMessageDelay then
        PrintMsg(string.format(
            'Update available! Current: v%s  Latest: v%s  --  Type /vd update to install.',
            _version, _latestVersion or '?'));
        _updateMessageDelay = nil;
    end

    if not _loginCheckAt or os.clock() < _loginCheckAt then
        return;
    end
    _loginCheckAt = nil;
    CheckForUpdateQuiet();
end

function M.CheckAndNotify(manual)
    local remote, code = FetchRemoteVersion();

    if not remote then
        if manual then
            PrintMsg(string.format(
                'Could not reach GitHub to check for updates. (HTTP %s)',
                tostring(code)));
        end
        return;
    end

    _latestVersion = remote;

    if VersionGreater(remote, _version) then
        PrintMsg(string.format(
            'Update available: %s (installed %s). Run /vd update, then /addon reload vanadial.',
            remote, _version));
    elseif manual then
        PrintMsg(string.format('Already up to date. (v%s)', _version));
    end
end

function M.RunUpdate()
    local ok, body, code = FetchUrl(UPDATE_VERSION_URL);

    if not ok or code ~= 200 or not body then
        PrintMsg('Could not reach GitHub to check for updates.');
        return;
    end

    local remote = ParseVersionFromBody(body);
    if not remote then
        PrintMsg('Could not determine remote version.');
        return;
    end

    _latestVersion = remote;

    if not VersionGreater(remote, _version) then
        PrintMsg(string.format('Already up to date. (v%s)', _version));
        return;
    end

    local allOk = true;
    local messages = { string.format('Downloading v%s...', remote) };

    for _, f in ipairs(UPDATE_FILES) do
        local fok, fbody, fcode = FetchUrl(f.url);

        if not fok or fcode ~= 200 or not fbody or fbody == '' then
            table.insert(messages, string.format(
                'Failed to download %s (HTTP %s). Update aborted.', f.label, tostring(fcode)));
            allOk = false;
            break;
        end

        local out = io.open(f.path, 'wb');
        if not out then
            table.insert(messages, string.format(
                'Cannot write %s. Check file permissions. Update aborted.', f.label));
            allOk = false;
            break;
        end
        out:write(fbody);
        out:close();
        table.insert(messages, string.format('Updated %s.', f.label));
    end

    if allOk then
        table.insert(messages, string.format(
            'Update to v%s complete! Type: /addon reload vanadial', remote));
        _updateMessageDelay = nil;
    end

    PrintMsg(table.concat(messages, '\n'));
end

return M;
