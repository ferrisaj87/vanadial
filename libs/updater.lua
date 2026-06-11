--[[
* Vana'Dial — GitHub raw download updater (same pattern as Anglin).
* Fetches addon.version from main, downloads listed files over HTTPS, overwrites in place.
]]--

local M = {};

local https     = require('socket.ssl.https');
local http      = require('socket.http');
local chatprint = require('libs.chatprint');
http.TIMEOUT = 15;

local RAW_BASE = 'https://raw.githubusercontent.com/ferrisaj87/vanadial/main/';

local UPDATE_VERSION_URL = RAW_BASE .. 'vanadial.lua';

-- Login update check runs after the HorizonXI welcome line in chat (see vanadial.lua text_in).

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
    'libs/chatprint.lua',
    'libs/updater.lua',
};

local _version             = '0.0.0';
local _loginCheckDone      = false;
local _loginCheckPending   = false;
local _loginCheckAt        = nil;
local LOGIN_CHECK_DELAY_SEC = 0.25;

-- Incremental download state (one HTTPS fetch per packet_in tick).
local _updateJob = nil;
local _updateTickAt = -1;

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

local function PrintMsg(msg)
    chatprint.Print(msg);
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

local function NotifyVersionStatus(remote)
    if not remote or remote == '' then
        PrintMsg(string.format("Vana'Dial v%s — could not check GitHub for updates.", _version or '?'));
        return;
    end
    if _version and _version ~= '' and VersionGreater(remote, _version) then
        PrintMsg(string.format(
            "A new version of Vana'Dial is available (v%s)! /vd update to get the latest version!",
            remote));
    else
        PrintMsg(string.format("Vana'Dial v%s is up to date!", _version or '?'));
    end
end

-- Armed by the HorizonXI welcome chat line only (see vanadial.lua text_in).
function M.OnWelcomeChat()
    _loginCheckDone    = false;
    _loginCheckPending = true;
    _loginCheckAt      = os.clock() + LOGIN_CHECK_DELAY_SEC;
end

function M.TickLoginCheck()
    if _loginCheckDone or not _loginCheckPending then
        return;
    end
    if _loginCheckAt and os.clock() < _loginCheckAt then
        return;
    end
    _loginCheckDone    = true;
    _loginCheckPending = false;
    _loginCheckAt      = nil;

    pcall(function()
        NotifyVersionStatus(FetchRemoteVersion());
    end);
end

function M.CheckAndNotify(manual)
    local remote, code = FetchRemoteVersion();

    if not remote then
        if manual then
            PrintMsg('Could not check for updates. Try again later.');
        end
        return;
    end

    if manual then
        NotifyVersionStatus(remote);
    end
end

function M.IsUpdateInProgress()
    return _updateJob ~= nil;
end

function M.RunUpdate()
    if _updateJob then
        PrintMsg('Update already in progress.');
        return;
    end
    _updateJob = { phase = 'check' };
    PrintMsg('Checking for updates...');
end

local function FinishUpdateJob(success)
    _updateJob = nil;
    _updateTickAt = -1;
    if success then
        PrintMsg('Addon has been successfully updated, use /addon reload vanadial to reload newest version.');
    else
        PrintMsg('Update failed. Try again or download from GitHub.');
    end
end

function M.TickUpdate()
    if not _updateJob then return; end

    -- Present + packet_in both call this; at most one step per frame time.
    local now = os.clock();
    if now == _updateTickAt then return; end
    _updateTickAt = now;

    local job = _updateJob;

    if job.phase == 'check' then
        local ok, body, code = FetchUrl(UPDATE_VERSION_URL);
        if not ok or code ~= 200 or not body then
            FinishUpdateJob(false);
            return;
        end

        local remote = ParseVersionFromBody(body);
        if not remote then
            FinishUpdateJob(false);
            return;
        end

        if not VersionGreater(remote, _version) then
            _updateJob = nil;
            _updateTickAt = -1;
            PrintMsg(string.format("Vana'Dial v%s is up to date!", _version or '?'));
            return;
        end

        job.phase  = 'download';
        job.index  = 1;
        job.total  = #UPDATE_FILES;
        job.remote = remote;
        PrintMsg("Updating Vana'Dial....");
        return;
    end

    if job.phase == 'download' then
        local i = job.index;
        local f = UPDATE_FILES[i];
        if not f then
            FinishUpdateJob(true);
            return;
        end

        local fok, fbody, fcode = FetchUrl(f.url);
        if not fok or fcode ~= 200 or not fbody or fbody == '' then
            FinishUpdateJob(false);
            return;
        end

        local out = io.open(f.path, 'wb');
        if not out then
            FinishUpdateJob(false);
            return;
        end
        out:write(fbody);
        out:close();

        job.index = i + 1;
        -- Light progress so long downloads do not look frozen.
        if (i % 3) == 1 or i == job.total then
            PrintMsg(string.format('Downloading %d/%d...', i, job.total));
        end
    end
end

return M;
