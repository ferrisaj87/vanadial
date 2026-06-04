--[[
* Vana'Dial - GitHub release check and git pull updater.
* Uses PowerShell for GitHub API (Windows / Horizon XI). Update requires a git clone.
]]--

local M = {};

local REPO_SLUG  = 'ferrisaj87/vanadial';
local API_URL    = 'https://api.github.com/repos/' .. REPO_SLUG .. '/releases/latest';
local REPO_URL   = 'https://github.com/' .. REPO_SLUG;

local _version       = '0.0.0';
local _loginCheckAt  = nil;
local _checkInFlight = false;

-- ── Version helpers ─────────────────────────────────────────────────────────────

local function ParseVersion(ver)
    ver = tostring(ver or ''):gsub('^%s*v', ''):gsub('%s+$', '');
    local parts = T{};
    for n in ver:gmatch('%d+') do
        parts[#parts + 1] = tonumber(n) or 0;
    end
    return parts;
end

local function CompareVersions(a, b)
    local pa = ParseVersion(a);
    local pb = ParseVersion(b);
    local n  = math.max(#pa, #pb);
    for i = 1, n do
        local va = pa[i] or 0;
        local vb = pb[i] or 0;
        if va < vb then return -1; end
        if va > vb then return 1; end
    end
    return 0;
end

function M.IsNewer(remote, localVer)
    return CompareVersions(remote, localVer) > 0;
end

-- ── Paths / shell ─────────────────────────────────────────────────────────────

local function GetAddonDir()
    local root = AshitaCore:GetInstallPath() or '';
    return (root .. 'addons\\vanadial'):gsub('[\\/]+$', '');
end

-- Trailing backslash before a closing " breaks cmd/git on Windows (\" escapes the quote).
local function QuoteCmdPath(path)
    path = path:gsub('[\\/]+$', ''):gsub('"', '');
    return '"' .. path .. '"';
end

-- FFXI chat is not UTF-8; strip non-ASCII so glyphs do not become garbage.
local function SanitizeChat(text)
    return tostring(text or ''):gsub('[^\32-\126]', '');
end

local function ShellCapture(cmd)
    local f = io.popen(cmd, 'r');
    if not f then return nil; end
    local out = f:read('*a') or '';
    f:close();
    return out;
end

local function HasGitInstall()
    local dir = GetAddonDir();
    local head = io.open(dir .. '\\.git\\HEAD', 'r');
    if head then
        head:close();
        return true;
    end
    return false;
end

-- ── GitHub API ────────────────────────────────────────────────────────────────

local function FetchLatestReleaseTag()
    local ps = string.format(
        [[powershell -NoProfile -Command "(Invoke-RestMethod -Uri '%s' -Headers @{ 'User-Agent' = 'VanaDial-Ashita' }).tag_name"]],
        API_URL:gsub("'", "''")
    );
    local out = ShellCapture(ps);
    if not out then return nil; end
    out = out:gsub('[\r\n]+', ''):gsub('^%s+', ''):gsub('%s+$', '');
    if out == '' then return nil; end
    return out;
end

local function PrintMsg(msg)
    print("[Vana'Dial] " .. SanitizeChat(msg));
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

function M.TickLoginCheck()
    if not _loginCheckAt or os.clock() < _loginCheckAt then
        return;
    end
    _loginCheckAt = nil;
    M.CheckAndNotify(false);
end

function M.CheckAndNotify(manual)
    if _checkInFlight then return; end
    _checkInFlight = true;

    local latest = FetchLatestReleaseTag();
    _checkInFlight = false;

    if not latest then
        if manual then
            PrintMsg('Could not reach GitHub to check for updates. Try again later.');
        end
        return;
    end

    if M.IsNewer(latest, _version) then
        PrintMsg(string.format(
            'Update available: %s (installed %s). Run /vd update, then /addon reload vanadial.',
            latest, _version));
    elseif manual then
        PrintMsg(string.format('Up to date (%s). Latest release: %s.', _version, latest));
    end
end

function M.RunUpdate()
    if not HasGitInstall() then
        PrintMsg('This folder is not a git clone. Install or update from:');
        PrintMsg(REPO_URL);
        return;
    end

    PrintMsg('Checking for updates...');
    M.CheckAndNotify(true);

    local dir = GetAddonDir();
    local cmd = 'git -C ' .. QuoteCmdPath(dir) .. ' pull --ff-only 2>&1';
    local out = ShellCapture(cmd);
    if not out then
        PrintMsg('git pull failed (is git installed and on PATH?).');
        return;
    end

    out = out:gsub('[\r\n]+', '\n'):gsub('\n+$', '');
    for line in out:gmatch('[^\n]+') do
        PrintMsg(line);
    end

    if out:find('Already up to date', 1, true)
        or out:find('Already up%-to%-date', 1, true) then
        -- message already printed
    elseif out:find('Updating', 1, true) or out:find('Fast%-forward', 1, true) then
        PrintMsg('Update complete. Run /addon reload vanadial to apply.');
    else
        PrintMsg('If files changed, run /addon reload vanadial to apply.');
    end
end

return M;
