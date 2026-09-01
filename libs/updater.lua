--[[
* Vana'Dial resilient GitHub updater.
*
* Work is scheduled outside d3d_present. Every file is fetched from one pinned
* Git commit, syntax-checked, and staged before installation. A transaction
* journal and verified backups allow automatic recovery after write failure or
* interruption.
]]--

local M = {};

local https     = require('socket.ssl.https');
local http      = require('socket.http');
local ltn12     = require('ltn12');
local chatprint = require('libs.chatprint');
http.TIMEOUT = 8;

local REPO_API = 'https://api.github.com/repos/ferrisaj87/vanadial/commits/main';
local RAW_ROOT = 'https://raw.githubusercontent.com/ferrisaj87/vanadial/';
local RETRY_DELAYS = { 2, 5, 15 };

local UPDATE_RELATIVE = {
    'vanadial.lua',
    'display.lua',
    'popups.lua',
    'config.lua',
    'timers.lua',
    'sunbreeze.lua',
    'data.lua',
    'libs/color.lua',
    'libs/imgui_compat.lua',
    'libs/imgui_safe.lua',
    'libs/texturemanager.lua',
    'libs/imtext.lua',
    'libs/windowbackground.lua',
    'libs/memory.lua',
    'libs/chatprint.lua',
    'libs/updater.lua',
};

local _version = '0.0.0';
local _loginCheckDone = false;
local _checkActive = false;
local _updateJob = nil;
local _generation = 0;
local _addonRoot = nil;
local _journalPath = nil;
local UPDATE_FILES = {};
local FILES_BY_RELATIVE = {};

local function PrintMsg(msg)
    pcall(chatprint.Print, msg);
end

local function Traceback(err)
    if debug and debug.traceback then
        return debug.traceback(tostring(err), 2);
    end
    return tostring(err);
end

local function Schedule(delay, fn)
    local ok, err = pcall(function()
        ashita.tasks.once(delay or 0, function()
            local runOk, runErr = xpcall(fn, Traceback);
            if not runOk then
                _checkActive = false;
                _updateJob = nil;
                PrintMsg('Updater stopped safely: ' .. tostring(runErr));
            end
        end);
    end);
    if not ok then
        PrintMsg('Could not schedule updater work: ' .. tostring(err));
    end
    return ok;
end

local function BuildUpdateFiles()
    local root = AshitaCore:GetInstallPath() or '';
    _addonRoot = (root .. 'addons\\vanadial\\'):gsub('[\\/]+$', '') .. '\\';
    _journalPath = _addonRoot .. '.vd-update-journal';
    UPDATE_FILES = {};
    FILES_BY_RELATIVE = {};
    for _, rel in ipairs(UPDATE_RELATIVE) do
        local entry = {
            relative = rel,
            path = _addonRoot .. rel:gsub('/', '\\'),
        };
        UPDATE_FILES[#UPDATE_FILES + 1] = entry;
        FILES_BY_RELATIVE[rel] = entry;
    end
end

local function ParseVersion(ver)
    local parts = {};
    for n in tostring(ver or ''):gsub('^%s*v', ''):gmatch('%d+') do
        parts[#parts + 1] = tonumber(n) or 0;
    end
    return parts;
end

local function VersionGreater(a, b)
    local pa, pb = ParseVersion(a), ParseVersion(b);
    for i = 1, math.max(#pa, #pb) do
        local ai, bi = pa[i] or 0, pb[i] or 0;
        if ai > bi then return true; end
        if ai < bi then return false; end
    end
    return false;
end

local function ParseVersionFromBody(body)
    if not body then return nil; end
    return body:match("addon%.version%s*=%s*'([^']+)'")
        or body:match('addon%.version%s*=%s*"([^"]+)"');
end

local function ReadFile(path)
    local f = io.open(path, 'rb');
    if not f then return nil; end
    local ok, body = pcall(function() return f:read('*a'); end);
    pcall(function() f:close(); end);
    return ok and body or nil;
end

local function WriteFile(path, body)
    local f, openErr = io.open(path, 'wb');
    if not f then return false, openErr; end
    local writeOk, writeErr = pcall(function()
        f:write(body);
        f:flush();
    end);
    local closeOk, closeErr = pcall(function() f:close(); end);
    if not writeOk then return false, writeErr; end
    if not closeOk then return false, closeErr; end
    if ReadFile(path) ~= body then return false, 'verification failed'; end
    return true;
end

local function RemoveFile(path)
    local existing = ReadFile(path);
    if existing == nil then return true; end
    local ok = pcall(os.remove, path);
    return ok and ReadFile(path) == nil;
end

local function CleanupArtifacts(removeBackups)
    for _, f in ipairs(UPDATE_FILES) do
        RemoveFile(f.path .. '.vdtmp');
        if removeBackups then RemoveFile(f.path .. '.vdbak'); end
    end
end

local function FetchUrl(url)
    local chunks = {};
    local ok, result, code = pcall(function()
        return https.request({
            url = url .. (url:find('?', 1, true) and '&' or '?') .. 't=' .. os.time(),
            method = 'GET',
            headers = {
                ['User-Agent'] = 'VanaDial-Ashita-Updater',
                ['Accept'] = 'application/vnd.github+json',
            },
            sink = ltn12.sink.table(chunks),
        });
    end);
    local body = table.concat(chunks);
    if not ok or not result or tonumber(code) ~= 200 or body == '' then
        return nil, code;
    end
    if body:find('<!DOCTYPE', 1, true) or body:find('<html', 1, true) then
        return nil, 'invalid response';
    end
    return body, 200;
end

local function RetryFetch(url, attempt, callback)
    local body, code = FetchUrl(url);
    if body then
        callback(body);
        return;
    end
    if attempt <= #RETRY_DELAYS then
        local delay = RETRY_DELAYS[attempt];
        if Schedule(delay, function() RetryFetch(url, attempt + 1, callback); end) then
            return;
        end
        code = 'retry scheduling failed';
    end
    callback(nil, code);
end

local function ValidateLua(relative, body)
    if type(body) ~= 'string' or body == '' then return false, 'empty file'; end
    if relative:sub(-4) == '.lua' then
        local chunk, err = loadstring(body, '@' .. relative);
        if not chunk then return false, err; end
    end
    return true;
end

local function GetLocalVersion()
    local body = UPDATE_FILES[1] and ReadFile(UPDATE_FILES[1].path) or nil;
    return ParseVersionFromBody(body) or _version;
end

local function ParseJournal(body)
    local entries = {};
    for line in tostring(body or ''):gmatch('[^\r\n]+') do
        local originalFlag, relative = line:match('^([01])|(.+)$');
        local file = relative and FILES_BY_RELATIVE[relative] or nil;
        if not file then return nil, 'invalid journal entry'; end
        entries[#entries + 1] = {
            file = file,
            hadOriginal = originalFlag == '1',
        };
    end
    if #entries ~= #UPDATE_FILES then return nil, 'incomplete journal'; end
    return entries;
end

local function RestoreEntries(entries)
    local restored = true;
    for _, entry in ipairs(entries) do
        local path = entry.file.path;
        if entry.hadOriginal then
            local backup = ReadFile(path .. '.vdbak');
            local ok = backup ~= nil and WriteFile(path, backup);
            if not ok then restored = false; end
        elseif not RemoveFile(path) then
            restored = false;
        end
    end
    return restored;
end

local function RecoverInterruptedTransaction()
    local body = ReadFile(_journalPath);
    if not body then
        CleanupArtifacts(true);
        return true, false;
    end
    local entries = ParseJournal(body);
    if not entries or not RestoreEntries(entries) then
        PrintMsg('Update recovery needs attention; backups were preserved.');
        return false, false;
    end
    if not RemoveFile(_journalPath) then
        PrintMsg('Update files were restored, but the recovery journal could not be removed; backups were preserved.');
        return false, false;
    end
    CleanupArtifacts(true);
    PrintMsg('Recovered the previous Vana\'Dial version after an interrupted update.');
    return true, true;
end

local function FinishUpdate(success, message, preserveRecovery)
    if not preserveRecovery then
        if ReadFile(_journalPath) ~= nil and not RemoveFile(_journalPath) then
            preserveRecovery = true;
            success = false;
            message = 'Could not finalize the update journal; backups were preserved for recovery.';
        else
            CleanupArtifacts(true);
        end
    end
    _updateJob = nil;
    if message then PrintMsg(message); end
    if success then
        PrintMsg('Update installed safely. Use /addon reload vanadial to load it.');
    end
end

local function AbortCommit(job, message)
    local restored = RestoreEntries(job.entries);
    if restored then
        FinishUpdate(false, message .. ' Previous files were restored.', false);
    else
        FinishUpdate(false, message .. ' Automatic recovery was incomplete; backups were preserved.', true);
    end
end

local function CommitStaged(job)
    job.entries = {};
    local journalLines = {};

    -- Back up every original before changing any live file.
    for _, f in ipairs(UPDATE_FILES) do
        local original = ReadFile(f.path);
        local hadOriginal = original ~= nil;
        if hadOriginal then
            local ok, err = WriteFile(f.path .. '.vdbak', original);
            if not ok then
                FinishUpdate(false, 'Update aborted while creating backups: ' .. tostring(err), false);
                return;
            end
        end
        job.entries[#job.entries + 1] = { file = f, hadOriginal = hadOriginal };
        journalLines[#journalLines + 1] = (hadOriginal and '1|' or '0|') .. f.relative;
    end

    local journalOk, journalErr = WriteFile(_journalPath, table.concat(journalLines, '\n'));
    if not journalOk then
        FinishUpdate(false, 'Update aborted before commit: ' .. tostring(journalErr), false);
        return;
    end

    -- Install the entrypoint last so it cannot advertise the new version before
    -- all supporting modules are present.
    local order = {};
    for i = 2, #UPDATE_FILES do order[#order + 1] = UPDATE_FILES[i]; end
    order[#order + 1] = UPDATE_FILES[1];

    for _, f in ipairs(order) do
        local staged = ReadFile(f.path .. '.vdtmp');
        if not staged then
            AbortCommit(job, 'A staged file disappeared during commit.');
            return;
        end
        local ok, err = WriteFile(f.path, staged);
        if not ok then
            AbortCommit(job, 'Update write failed: ' .. tostring(err));
            return;
        end
    end

    FinishUpdate(true, nil, false);
end

local function DownloadNext(job)
    if _updateJob ~= job or job.generation ~= _generation then return; end
    local f = UPDATE_FILES[job.index];
    if not f then
        CommitStaged(job);
        return;
    end

    local url = RAW_ROOT .. job.commit .. '/' .. f.relative:gsub('\\', '/');
    RetryFetch(url, 1, function(body)
        if _updateJob ~= job then return; end
        if not body then
            FinishUpdate(false, 'Download failed after retries; the installed version was not changed.', false);
            return;
        end
        local valid, validationErr = ValidateLua(f.relative, body);
        if not valid then
            FinishUpdate(false, 'Downloaded file failed validation: ' .. tostring(validationErr), false);
            return;
        end
        local written, writeErr = WriteFile(f.path .. '.vdtmp', body);
        if not written then
            FinishUpdate(false, 'Could not stage update: ' .. tostring(writeErr), false);
            return;
        end
        job.index = job.index + 1;
        if (job.index % 3) == 0 or job.index > #UPDATE_FILES then
            PrintMsg(string.format('Staged %d/%d files...', job.index - 1, #UPDATE_FILES));
        end
        if not Schedule(0.05, function() DownloadNext(job); end) then
            FinishUpdate(false, 'Could not schedule the next download; installed files were not changed.', false);
        end
    end);
end

local function ResolveRemote(callback)
    RetryFetch(REPO_API, 1, function(apiBody)
        local commit = apiBody and apiBody:match('"sha"%s*:%s*"([0-9a-fA-F]+)"') or nil;
        if not commit or #commit ~= 40 then
            callback(nil, nil, 'could not pin remote commit');
            return;
        end
        local versionUrl = RAW_ROOT .. commit .. '/vanadial.lua';
        RetryFetch(versionUrl, 1, function(versionBody, code)
            if not versionBody then
                callback(nil, nil, code);
                return;
            end
            local valid, err = ValidateLua('vanadial.lua', versionBody);
            if not valid then
                callback(nil, nil, err);
                return;
            end
            callback(commit, ParseVersionFromBody(versionBody));
        end);
    end);
end

local function BeginUpdate()
    ResolveRemote(function(commit, remote)
        local job = _updateJob;
        if not job then return; end
        local localVer = GetLocalVersion();
        if not commit or not remote then
            FinishUpdate(false, 'Could not resolve a consistent remote release after retries.', false);
            return;
        end
        if not VersionGreater(remote, localVer) then
            FinishUpdate(false, string.format("Vana'Dial v%s is up to date!", localVer or '?'), false);
            return;
        end
        job.commit = commit;
        job.remote = remote;
        DownloadNext(job);
    end);
end

local function BeginVersionCheck(manual)
    ResolveRemote(function(_, remote)
        _checkActive = false;
        local localVer = GetLocalVersion();
        if not remote then
            if manual then PrintMsg('Could not check for updates after retries.'); end
        elseif VersionGreater(remote, localVer) then
            PrintMsg(string.format(
                "A new version of Vana'Dial is available (v%s)! /vd update to install it.",
                remote));
        elseif manual then
            PrintMsg(string.format("Vana'Dial v%s is up to date!", localVer or '?'));
        end
    end);
end

-- v1.4.30 and older updaters do not know about newly added runtime files.
-- After they replace the existing manifest, the new updater repairs only those
-- missing files during addon load, before vanadial.lua requires them. This work
-- never runs from PRESENT; a failed repair aborts loading and can be retried by
-- reloading the addon later.
local function EnsureRuntimeFiles()
    local missing = {};
    for _, f in ipairs(UPDATE_FILES) do
        if ReadFile(f.path) == nil then
            missing[#missing + 1] = f;
        end
    end
    if #missing == 0 then return true; end

    PrintMsg(string.format('Repairing %d missing runtime file(s)...', #missing));
    local apiBody, apiErr = FetchUrl(REPO_API);
    local commit = apiBody and apiBody:match('"sha"%s*:%s*"([0-9a-fA-F]+)"') or nil;
    if not commit or #commit ~= 40 then
        return false, apiErr or 'could not pin repair commit';
    end

    for _, f in ipairs(missing) do
        local url = RAW_ROOT .. commit .. '/' .. f.relative:gsub('\\', '/');
        local body, fetchErr = FetchUrl(url);
        if not body then return false, fetchErr or ('could not fetch ' .. f.relative); end
        local valid, validationErr = ValidateLua(f.relative, body);
        if not valid then return false, validationErr; end
        local written, writeErr = WriteFile(f.path, body);
        if not written then return false, writeErr; end
    end
    PrintMsg('Missing runtime files repaired.');
    return true;
end

function M.Init(version)
    _version = version or _version;
    BuildUpdateFiles();
    local recoveredOk, recovered = RecoverInterruptedTransaction();
    if not recoveredOk or recovered then
        return recoveredOk, recovered;
    end
    local runtimeOk, runtimeErr = EnsureRuntimeFiles();
    if not runtimeOk then
        PrintMsg('Runtime repair failed; reload later to retry: ' .. tostring(runtimeErr));
        return false, false;
    end
    return true, false;
end

function M.GetVersion()
    return _version;
end

function M.IsNewer(remote, localVer)
    return VersionGreater(remote, localVer);
end

function M.OnWelcomeChat()
    if _loginCheckDone or _checkActive or _updateJob then return; end
    _loginCheckDone = true;
    _checkActive = true;
    if not Schedule(0.25, function() BeginVersionCheck(false); end) then
        _checkActive = false;
    end
end

function M.CheckAndNotify(manual)
    if _checkActive or _updateJob then
        if manual then PrintMsg('An update operation is already running.'); end
        return;
    end
    _checkActive = true;
    if not Schedule(0, function() BeginVersionCheck(manual == true); end) then
        _checkActive = false;
    end
end

function M.IsUpdateInProgress()
    return _updateJob ~= nil;
end

function M.RunUpdate()
    if _updateJob or _checkActive then
        PrintMsg('An update operation is already running.');
        return;
    end
    if not RecoverInterruptedTransaction() then
        PrintMsg('Update cannot start until recovery succeeds.');
        return;
    end
    _generation = _generation + 1;
    _updateJob = {
        generation = _generation,
        index = 1,
        commit = nil,
        entries = {},
    };
    CleanupArtifacts(true);
    PrintMsg('Checking and staging a consistent update...');
    if not Schedule(0, BeginUpdate) then
        _updateJob = nil;
    end
end

function M.Cancel()
    _generation = _generation + 1;
    if not ReadFile(_journalPath) then CleanupArtifacts(true); end
    _updateJob = nil;
    _checkActive = false;
end

-- Compatibility no-ops for callers from older mixed-version installs.
function M.TickUpdate() end
function M.TickLoginCheck() end

return M;
