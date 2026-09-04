--[[
* Vana'Dial - Standalone Ashita Addon
*
* Displays Vana'diel time, day element, moon phase, and zone weather.
* Includes transport and RSE timer panel.
*
* Commands:
*   /vd                   - Toggle Vana'Dial visibility
*   /vd config            - Open/close the configuration window
*   /vd ships             - Open/close airship timers section
*   /vd boats             - Open/close ferry boat timers (Selbina/Mhaura/Whitegate/Nashmau)
*   /vd boatsall          - Open/close all boat timer sub-groups
*   /vd manaclipper       - Open/close Bibiki Manaclipper timers
*   /vd barge             - Open/close Carpenters' Landing barge timers
*   /vd rse               - Open/close RSE timer section
*   /vd lunar             - Open/close lunar timer section
*   /vd sunbreezerace     - Toggle the Sunbreeze Racing event window
*   /vd reset             - Reset Vana'Dial and Sunbreeze window positions
*   /vd update            - Download latest from GitHub (then /addon reload vanadial)
*   /vd checkupdate       - Check GitHub for a newer version
]]--

addon.name    = 'vanadial';
addon.author  = 'Ferris';
addon.version = '1.4.38';
addon.desc    = "Vana'Dial — Vana'diel time, weather, moon phase and transport timers.";
addon.link    = 'https://github.com/ferrisaj87/vanadial';

require('common');
local settings = require('settings');
local imgui    = require('imgui');
local bit      = require('bit');

-- ── Bootstrap globals consumed by display.lua / popups.lua / bundled libs ─────
-- XIUI's handlers/helpers.lua exposes these as bare globals; we mirror that here
-- from our bundled color lib so windowbackground.lua, imtext.lua, etc. work.
local colorLib          = require('libs.color');
local chatprint         = require('libs.chatprint');
local updater           = require('libs.updater');
VanaDialPrint           = chatprint.Print;
local updaterReady, updaterRecovered = updater.Init(addon.version);
if not updaterReady then
    error("Vana'Dial update recovery failed; refusing to load mixed files. Restore the preserved .vdbak files and reload.");
elseif updaterRecovered then
    error("Vana'Dial recovered an interrupted update. Reload the addon to load the restored files safely.");
end
ARGBToRGBA              = colorLib.ARGBToRGBA;
RGBAToARGB              = colorLib.RGBAToARGB;
ARGBToImGui             = colorLib.ARGBToImGui;
ImGuiToARGB             = colorLib.ImGuiToARGB;
ARGBToABGR              = colorLib.ARGBToABGR;
HexToImGui              = colorLib.HexToImGui;
ImGuiToHex              = colorLib.ImGuiToHex;
HexToARGB               = colorLib.HexToARGB;
HexToU32                = colorLib.HexToU32;
ARGBToU32               = colorLib.ARGBToU32;
ColorTableToARGB        = colorLib.ColorTableToARGB;
InvalidateColorCaches   = colorLib.InvalidateColorCaches;
GetColorSetting         = colorLib.GetColorSetting;
GetGradientSetting      = colorLib.GetGradientSetting;
GetGradientTextColor    = colorLib.GetGradientTextColor;
local imtext            = require('libs.imtext');
local data              = require('data');

local function MonotonicMs()
    local ms = data.GetTickMs and data.GetTickMs() or nil;
    if ms ~= nil then return ms; end
    return math.floor(os.clock() * 1000);
end

-- ── Settings ──────────────────────────────────────────────────────────────────
local defaults = T{
    showVanaDial                 = true,
    vanaTimeHideOnMenuFocus      = false,
    vanaTimeHideOnChatExpanded   = false,
    vanaTimeVTElementColor       = false,
    vanaTimeShowLocalTime        = true,
    vanaTimeShowMoonPercent      = true,
    vanaTimeShowPastFuture       = true,
    vanaTimePastFutureOpacity    = 0.35,
    vanaTimePlainDayIcons        = false,
    vanaTimeShowWeaknessBadge    = true,
    vanaTimeShowWeather          = true,
    vanaTimeWeatherSide          = 'right',
    vanaTimeWeatherAlign         = 'left',
    vanaTimeWeatherCustomScale   = false,
    vanaTimeWeatherIconSize      = 28,
    vanaTimeWeatherAdjustElemental   = false,
    vanaTimeWeatherElementalIconSize = 42,
    vanaTimeWeatherHideNonElemental  = false,
    vanaTimeTodPopup             = true,
    vanaTimeTodSide              = 'left',
    vanaTimeTodAlign             = 'left',
    vanaTimeTodCustomScale       = false,
    vanaTimeTodIconSize          = 28,
    vanaTimeTodShowTimer         = true,
    vanaTimeScale                = 1.0,
    vanaTimeFontSize             = 12,
    vanaTimeFontBold             = true,  -- match XIUI default fontWeight = 'Bold'
    vanaTimeIconSize             = 28,
    vanaTimeBgScale              = 1.0,
    vanaTimeBorderScale          = 1.0,
    vanaTimeBackgroundOpacity    = 0.85,
    vanaTimeBorderOpacity        = 1.0,
    vanaTimeTooltipDirection     = 'above',
    vanaTimeShowTooltip          = true,
    vanaTimeTooltipFenrir        = true,
    vanaTimeTooltipSeleneBow     = true,
    vanaTimeShowSettingsBtn      = true,
    vanaTimeEnableTooltips       = true,
    vanaTimeTipVT                = true,
    vanaTimeTipLT                = true,
    vanaTimeTipTod               = true,
    vanaTimeTipWeather           = true,
    vanaTimeShowTimers           = true,
    vanaTimeTimerSide            = 'above',
    vanaTimeTimersFontSize       = 12,
    vanaTimeTimersAutoCloseClick = false,
    vanaTimeTimersAutoCloseIdle  = false,
    vanaTimeTimersAutoCloseIdleSec = 5,
    vanaTimeTimerSections = T{
        airships = false,
        boats    = false,
        rse      = false,
        lunar    = false,
    },
    windowPositions  = T{},
    colorCustomization = T{
        vanaTime = T{
            bgColor          = 0xFF000000,
            borderColor      = 0xFFFFFFFF,
            textColor        = 0xFFFFFFFF,
            moonFullColor    = 0xFF88CCFF,  -- moonlit blue (matches in-game full moon pulse)
            moonNewColor     = 0xFFFF4444,
            todTimerColor    = 0xFFFFFFFF,
            elementFire      = 0xFFFF4500,
            elementEarth     = 0xFFB8860B,
            elementWater     = 0xFF1E90FF,
            elementWind      = 0xFF32CD32,
            elementIce       = 0xFF87CEEB,
            elementLightning = 0xFFBF5FFF,
            elementLight     = 0xFFFFFFE0,
            elementDark      = 0xFF2A0850,
        },
    },
};

-- gConfig is read as a bare global by display.lua and popups.lua.
-- We load the settings and expose them here before requiring those modules.
-- settings.load() persists to Game/config/addons/vanadial/<Char_ServerId>/settings.lua
-- automatically (one folder per character, same scheme XIUI uses).
gConfig = settings.load(defaults);
-- appliedPositions is per-session only; reset it so saved positions are applied
-- on each load (do not persist this through settings.save).
gConfig.appliedPositions = {};

local WINDOW_KEY = 'VanaDial';

local function MigrateWindowSettings()
    local changed = false;
    if gConfig.showVanaTime ~= nil and gConfig.showVanaDial == nil then
        gConfig.showVanaDial = gConfig.showVanaTime;
        changed = true;
    end
    if not gConfig.windowPositions then
        gConfig.windowPositions = T{};
        changed = true;
    end
    if gConfig.windowPositions['VanaTime'] and not gConfig.windowPositions[WINDOW_KEY] then
        gConfig.windowPositions[WINDOW_KEY] = gConfig.windowPositions['VanaTime'];
        changed = true;
    end
    return changed;
end

-- Debounced settings persistence. Widget changes and window drags only mark
-- dirty during Present; the actual settings.save() runs on a short task so
-- serialization / file I/O / GC cannot collect D3D textures still queued in
-- this frame's ImGui draw lists (that AV is often blamed on the next addon).
local _settingsDirty      = false;
local _settingsDirtyAt    = 0;
local _allowPositionSave  = false;
local _inPresentFrame     = false;
local _saveTaskPending    = false;
local _addonAlive         = true;

local function MarkSettingsDirty()
    _settingsDirty   = true;
    _settingsDirtyAt = MonotonicMs();
end

local function FlushSettingsToDisk()
    if not gConfig then return; end
    local applied = gConfig.appliedPositions;
    gConfig.appliedPositions = nil;
    local ok, err = pcall(settings.save);
    gConfig.appliedPositions = applied or T{};
    if not ok then
        MarkSettingsDirty();
        error(err);
    end
end

-- Immediate on load/unload/commands. During Present, only queue — never write.
function SaveVanaDialSettings()
    if _inPresentFrame then
        MarkSettingsDirty();
        return;
    end
    FlushSettingsToDisk();
end

local function ScheduleSettingsFlush()
    if _saveTaskPending or not _settingsDirty then return; end
    _saveTaskPending = true;
    local scheduled = pcall(function()
        ashita.tasks.once(0.05, function()
            _saveTaskPending = false;
            if not _addonAlive or not gConfig then return; end
            local ok = xpcall(FlushSettingsToDisk, function(e) return tostring(e); end);
            if ok then
                _settingsDirty = false;
            else
                MarkSettingsDirty();
            end
        end);
    end);
    if not scheduled then
        _saveTaskPending = false;
    end
end

local function EnsureDefaultWindowPosition(persist)
    if not gConfig.windowPositions then
        gConfig.windowPositions = T{};
    end
    if not gConfig.windowPositions[WINDOW_KEY] then
        gConfig.windowPositions[WINDOW_KEY] = T{ x = 100, y = 100 };
        if persist then
            MarkSettingsDirty();
        end
    end
end

local _activeCharKey = nil;

local function GetSettingsCharKey()
    local ok, key = pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        if not party then return nil; end
        local name = party:GetMemberName(0);
        if not name or name == '' then return nil; end
        local id = party:GetMemberServerId(0);
        if id == nil or id == 0 then return nil; end
        return string.format('%s_%u', name, id);
    end);
    return ok and key or nil;
end

local _positionReady = false;
local RearmPositionIfInWorld;

local function OnCharacterSettingsReady(s)
    if s == nil then return; end

    local switching = gConfig ~= nil and gConfig ~= s;

    -- Flush the outgoing character's pending position before switching tables.
    if switching and _settingsDirty then
        SaveVanaDialSettings();
        _settingsDirty = false;
    end

    s.appliedPositions = nil;
    gConfig = s;

    InvalidateColorCaches();
    imtext.Reset();
    if MigrateWindowSettings() then
        SaveVanaDialSettings();
    end
    gConfig.appliedPositions = T{};
    _allowPositionSave = false;

    local key = GetSettingsCharKey();
    if key then _activeCharKey = key; end

    if switching then
        _positionReady = false;
    end
end

local function ReloadCharacterSettingsIfNeeded()
    local key = GetSettingsCharKey();
    if not key or key == _activeCharKey then return; end
    -- Ashita's settings library already switches character tables via
    -- settings.register; avoid settings.load() here — it can discard unsaved
    -- position changes still waiting on the debounce timer.
    _activeCharKey = key;
    RearmPositionIfInWorld();
end

-- Fires whenever Ashita loads/switches the per-character settings table.
settings.register('settings', 'vd_char_settings', function(s)
    OnCharacterSettingsReady(s);
end);

if MigrateWindowSettings() then
    SaveVanaDialSettings();
end

-- ── Config window state ───────────────────────────────────────────────────────
local _configOpen = false;

-- display.lua calls VanaDial_ToggleConfig when the gear icon is clicked.
VanaDial_ToggleConfig = function()
    _configOpen = not _configOpen;
end;

-- ── Window helper globals (mirror of XIUI handlers/helpers.lua) ───────────────
-- display.lua calls these as bare globals; we provide standalone equivalents.

local _baseWinFlagsCache = nil;
function GetBaseWindowFlags(lockPositions)
    if _baseWinFlagsCache == nil then
        _baseWinFlagsCache = bit.bor(
            ImGuiWindowFlags_NoDecoration,
            ImGuiWindowFlags_AlwaysAutoResize,
            ImGuiWindowFlags_NoFocusOnAppearing,
            ImGuiWindowFlags_NoNav,
            ImGuiWindowFlags_NoBackground,
            ImGuiWindowFlags_NoBringToFrontOnFocus,
            ImGuiWindowFlags_NoDocking
        );
    end
    if lockPositions then
        return bit.bor(_baseWinFlagsCache, ImGuiWindowFlags_NoMove);
    end
    return _baseWinFlagsCache;
end

function ApplyWindowPosition(windowName)
    if gConfig and gConfig.windowPositions and gConfig.windowPositions[windowName] then
        if not gConfig.appliedPositions then gConfig.appliedPositions = {}; end
        if not gConfig.appliedPositions[windowName] then
            local pos = gConfig.windowPositions[windowName];
            local x, y = tonumber(pos.x), tonumber(pos.y);
            if not x or not y or x < -32000 or y < -32000 or x > 32000 or y > 32000 then
                gConfig.windowPositions[windowName] = nil;
                MarkSettingsDirty();
                return false;
            end
            imgui.SetNextWindowPos({x, y}, ImGuiCond_Always);
            gConfig.appliedPositions[windowName] = true;
            return true;
        end
    end
    return false;
end

function SaveWindowPosition(windowName)
    if not gConfig or not _allowPositionSave then return; end
    local x, y = imgui.GetWindowPos();
    -- Allow monitors left/above the primary display while rejecting corrupt data.
    if type(x) ~= 'number' or type(y) ~= 'number' then return; end
    if x < -32000 or y < -32000 or x > 32000 or y > 32000 then return; end
    if not gConfig.windowPositions then gConfig.windowPositions = T{}; end
    local saved = gConfig.windowPositions[windowName];
    if not saved then
        gConfig.windowPositions[windowName] = T{ x = x, y = y };
        MarkSettingsDirty();
    elseif saved.x ~= x or saved.y ~= y then
        saved.x = x; saved.y = y;
        MarkSettingsDirty();
    end
end

-- ── ImGui compatibility shims ─────────────────────────────────────────────────
-- Patches missing constants (ImGuiWindowFlags_NoDocking, ImGuiCol_Tab*, etc.)
-- that exist on Ashita 4.3 but not on the main branch, or vice-versa.
-- Must run before any module that builds window-flag constants at load time.
require('libs.imgui_compat');

-- ── Load Vana'Dial modules ────────────────────────────────────────────────────
-- Loaded AFTER gConfig and globals are set so they can read gConfig at
-- module-load time (some constants reference gConfig at the file scope).
local display         = require('display');
local popups          = require('popups');
local config          = require('config');
local sunbreeze       = require('sunbreeze');
local TextureManager  = require('libs.texturemanager');

-- ── Module state ──────────────────────────────────────────────────────────────
local hidden             = false;
local weatherId          = 0;
local _wasInWorldDraw    = false;
local _inWorldReady          = false;

-- A failing PRESENT component is paused before retrying so one bad frame cannot
-- repeatedly corrupt state, flood chat, or take down later addons.
local _presentFailures = {};
local PRESENT_RETRY_MS = { 1000, 5000, 15000, 60000 };

local function Traceback(err)
    if debug and debug.traceback then
        return debug.traceback(tostring(err), 2);
    end
    return tostring(err);
end

local function RunPresentComponent(name, fn)
    local now = MonotonicMs();
    local state = _presentFailures[name];
    if state and now < (state.retryAt or 0) then
        return false;
    end

    local ok, err = xpcall(fn, Traceback);
    if ok then
        _presentFailures[name] = nil;
        return true;
    end

    state = state or { attempts = 0, retryAt = 0, lastLogAt = -60000 };
    state.attempts = math.min(state.attempts + 1, #PRESENT_RETRY_MS);
    state.retryAt = now + PRESENT_RETRY_MS[state.attempts];
    _presentFailures[name] = state;

    if now - state.lastLogAt >= 30000 then
        state.lastLogAt = now;
        pcall(VanaDialPrint, string.format(
            '%s failed; retrying in %.0fs: %s',
            name, PRESENT_RETRY_MS[state.attempts] / 1000, tostring(err)));
    end
    return false;
end

-- ── In-world gate (zonename / minimap pattern) ────────────────────────────────
-- Do not draw on the title screen, character select, or while zoning.

local function IsPlayerZoning(player)
    if not player then return true; end
    if player.isZoning == true then return true; end
    local ok, zoning = pcall(function() return player:GetIsZoning(); end);
    return ok and zoning == true;
end

-- Per-present-frame cache: avoid duplicate memory reads and throttle menu/chat scans.
local _presentTick      = -1;
local _presentInWorld   = false;
local _presentMenuOpen  = false;
local _presentChatOpen  = false;
local _menuChatTick      = -1;
local _inWorldTick       = -1;
local MENU_CHAT_INTERVAL_MS = 120; -- menu name chain is heavier than chat-expanded byte read
local IN_WORLD_INTERVAL_MS  = 150; -- party/entity probe; zone-in lags slightly at most this long

local function IsPlayerInWorld()
    local ok, ready = pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        if not party then return false; end

        local zoneId = party:GetMemberZone(0);
        if zoneId == nil or zoneId == 0 then return false; end

        local player = AshitaCore:GetMemoryManager():GetPlayer();
        if not player or IsPlayerZoning(player) then return false; end

        local entIndex = party:GetMemberTargetIndex(0);
        if entIndex == nil or entIndex == 0 then return false; end

        local entity = AshitaCore:GetMemoryManager():GetEntity();
        if not entity then return false; end

        local name = entity:GetName(entIndex);
        if not name or name == '' then return false; end

        return true;
    end);
    return ok and ready;
end

IsPlayerZoningNow = function()
    local ok, zoning = pcall(function()
        local player = AshitaCore:GetMemoryManager():GetPlayer();
        if not player then return false; end
        return IsPlayerZoning(player);
    end);
    return ok and zoning;
end

RearmPositionIfInWorld = function()
    if not IsPlayerInWorld() or IsPlayerZoningNow() or not GetSettingsCharKey() then return; end
    EnsureDefaultWindowPosition(false);
    if gConfig then gConfig.appliedPositions = T{}; end
    _positionReady = true;
end

local function BeginZoning()
    _allowPositionSave = false;
    _positionReady = false;
end
-- ── Weather (packet 0x057 primary; memory fallback on zone-in only) ───────────
-- Incoming 0x057 carries weather ID at byte offset 0x08. Reading memory on every
-- 0x057 was re-scanning FFXiMain.dll when the pointer was wrong, causing ~1s hitches.
local WEATHER_SIG         = '66A1????????663D????72';
local WEATHER_PKT_OFF     = 9;   -- Lua 1-based index for packet byte 0x08
local _weatherPtr         = nil;
local _weatherMemResolved = false; -- true after one resolve attempt (success or fail)

-- Horizon XI uses FFXiMain.dll only; avoid the fallback scan of all modules (very slow).
local function memory_find_compat(pattern, offset, scan)
    local result = ashita.memory.find('FFXiMain.dll', 0, pattern, offset, scan);
    if result ~= nil and result ~= 0 then return result end;
    return nil;
end

local function ResolveWeatherPtrOnce()
    if _weatherMemResolved then return _weatherPtr end;
    _weatherMemResolved = true;

    local ok, result = pcall(function()
        local base = memory_find_compat(WEATHER_SIG, 0, 0);
        if not base or base == 0 then return nil end;
        local ptr = ashita.memory.read_uint32(base + 0x02);
        if not ptr or ptr == 0 then return nil end;
        return ptr;
    end);
    if ok and type(result) == 'number' and result ~= 0 then
        _weatherPtr = result;
    end
    return _weatherPtr;
end

local function ReadWeatherFromMemory()
    local ptr = _weatherPtr;
    if not ptr then return nil end;
    local ok, w = pcall(function() return ashita.memory.read_uint8(ptr); end);
    if ok and type(w) == 'number' and w >= 0 and w <= 19 then
        return w;
    end
    return nil;
end

local function ReadWeatherFromPacket(data)
    if type(data) ~= 'string' or #data < WEATHER_PKT_OFF then return nil end;
    local w = data:byte(WEATHER_PKT_OFF);
    if w and w >= 0 and w <= 19 then return w; end;
    return nil;
end

local function ResetWeatherState()
    weatherId             = 0;
end

-- ── Game menu detection (for "Hide When Menu Open") ───────────────────────────
-- Mirrors XIUI's core/gamestate.lua. Resolves a pointer into FFXiMain.dll that
-- exposes the currently focused menu's name, then treats the module as hidden
-- while a "real" menu (inventory, map, etc.) is open. Combat/chat sub-menus are
-- ignored so the clock doesn't vanish every time you open the action menu.
-- Signature courtesy of Velyn (same one XIUI uses).
local _pGameMenu       = nil;
local _gameMenuFailed  = false;

local function ResolveGameMenuPtr()
    local ok, result = pcall(function()
        return ashita.memory.find('FFXiMain.dll', 0, '8B480C85C974??8B510885D274??3B05', 16, 0);
    end);
    if ok and type(result) == 'number' and result ~= 0 then return result end;
    return nil;
end

local function EnsureGameMenuPtr()
    return _pGameMenu;
end

local function GetMenuName()
    if not EnsureGameMenuPtr() then return ''; end
    local ok, name = pcall(function()
        local subPointer = ashita.memory.read_uint32(_pGameMenu);
        if subPointer == 0 then return ''; end
        local subValue = ashita.memory.read_uint32(subPointer);
        if subValue == 0 then return ''; end
        local menuHeader = ashita.memory.read_uint32(subValue + 4);
        if menuHeader == 0 then return ''; end
        local menuName = ashita.memory.read_string(menuHeader + 0x46, 16);
        return string.gsub(menuName, '\x00', '');
    end);
    if ok and type(name) == 'string' then return name; end
    return '';
end

-- Menus that should NOT trigger hide (chat input, combat sub-menus, etc.).
local IGNORED_MENUS = {
    inline   = true,  -- chat box / text input
    playermo = true,  -- player menu (self-target/engage)
    chatctrl = true,  -- chat mode select
    magselec = true,  -- magic side menu
    magic    = true,  -- magic / trust menu
    abiselec = true,  -- abilities side menu
    ability  = true,  -- JA, WS, pet commands
};

local function IsGameMenuOpen()
    local menuName = GetMenuName():gsub('%s+$', '');
    if menuName == '' then return false; end
    local shortName = menuName:match('^menu%s+(.+)') or menuName;
    return not IGNORED_MENUS[shortName];
end

-- ── Chat log expanded (for "Hide When Chat Log Expanded") ─────────────────────
-- Same FFXiMain.dll signature as minimapcontrol / minimapmon. Detects the large
-- scrollback window only — not the inline chat input used while typing.
local _pChatExpanded      = nil;
local _chatExpandedFailed = false;

local function ResolveChatExpandedPtr()
    local ok, result = pcall(function()
        return ashita.memory.find('FFXiMain.dll', 0, '83EC??B9????????E8????????0FBF4C24??84C0', 0x04, 0);
    end);
    if ok and type(result) == 'number' and result ~= 0 then return result end;
    return nil;
end

local function EnsureChatExpandedPtr()
    return _pChatExpanded;
end

local function IsChatExpanded()
    if not EnsureChatExpandedPtr() then return false; end
    local ok, expanded = pcall(function()
        local ptr = ashita.memory.read_uint32(_pChatExpanded);
        if ptr == 0 then return false; end
        return ashita.memory.read_uint8(ptr + 0xF1) ~= 0;
    end);
    if ok then return expanded; end
    return false;
end

-- Signature scans never run from PRESENT. They are resolved during load or a
-- delayed Ashita task after zoning; failures are nonfatal and retried later.
local function ResolveClientPointers()
    if not _weatherPtr then
        _weatherMemResolved = false;
        ResolveWeatherPtrOnce();
    end
    if not _pGameMenu then
        _gameMenuFailed = false;
        _pGameMenu = ResolveGameMenuPtr();
        _gameMenuFailed = _pGameMenu == nil;
    end
    if not _pChatExpanded then
        _chatExpandedFailed = false;
        _pChatExpanded = ResolveChatExpandedPtr();
        _chatExpandedFailed = _pChatExpanded == nil;
    end
    return _weatherPtr ~= nil and _pGameMenu ~= nil and _pChatExpanded ~= nil;
end

local _pointerResolveGeneration = 0;
local function SchedulePointerResolve(initialDelay)
    _pointerResolveGeneration = _pointerResolveGeneration + 1;
    local generation = _pointerResolveGeneration;

    local function scheduleAttempt(delay, attempt)
        local scheduled = pcall(function()
            ashita.tasks.once(delay, function()
                if generation ~= _pointerResolveGeneration then return; end
                local ok, complete = xpcall(ResolveClientPointers, Traceback);
                if ok and _weatherPtr then
                    local w = ReadWeatherFromMemory();
                    if w ~= nil then weatherId = w; end
                end
                if (not ok or not complete) and attempt < 4 then
                    scheduleAttempt(math.min(5 * attempt, 30), attempt + 1);
                end
            end);
        end);
        return scheduled;
    end

    scheduleAttempt(initialDelay or 0, 1);
end

-- Must be defined AFTER IsGameMenuOpen / IsChatExpanded (Lua resolves locals at compile time).
local function RefreshPresentCache()
    local t = MonotonicMs();
    if t == _presentTick then return; end
    _presentTick = t;

    if _inWorldTick < 0 or (t - _inWorldTick) >= IN_WORLD_INTERVAL_MS then
        _inWorldTick  = t;
        local ready   = IsPlayerInWorld();
        _inWorldReady = ready;
        _presentInWorld = ready;
        if ready and not IsPlayerZoningNow() then
            ReloadCharacterSettingsIfNeeded();
        end
    end

    local needMenu = gConfig.vanaTimeHideOnMenuFocus == true;
    local needChat = gConfig.vanaTimeHideOnChatExpanded == true;
    if needMenu then
        if _menuChatTick < 0 or (t - _menuChatTick) >= MENU_CHAT_INTERVAL_MS then
            _menuChatTick = t;
            _presentMenuOpen = IsGameMenuOpen();
        end
    else
        _presentMenuOpen = false;
    end
    if needChat then
        _presentChatOpen = IsChatExpanded();
    else
        _presentChatOpen = false;
    end
end

local function ShouldDrawMain()
    if hidden then return false; end
    if gConfig.showVanaDial == false then return false; end
    if not _positionReady then return false; end
    if IsPlayerZoningNow() then return false; end
    if not _presentInWorld then return false; end
    if not GetSettingsCharKey() then return false; end
    return true;
end

local function ShouldHideMainWindow()
    if hidden then return false; end
    if gConfig.showVanaDial == false then return false; end
    return true;
end

-- ── Events ────────────────────────────────────────────────────────────────────

ashita.events.register('load', 'vd_load', function()
    -- Load all fonts NOW, during the load event (outside any d3d_present frame).
    -- imgui.AddFontFromFileTTF mutates the font atlas; doing it mid-frame on the
    -- Ashita main lineage causes EXCEPTION_ACCESS_VIOLATION. Prewarm the clock
    -- font plus the event window's italic font before any PRESENT callback.
    imtext.PrewarmFonts({'Tahoma'});
    imtext.PrewarmItalicFonts({'Arial'});
    display.Initialize();
    local pointersOk, complete = xpcall(ResolveClientPointers, Traceback);
    local w = pointersOk and ReadWeatherFromMemory() or nil;
    if w ~= nil then weatherId = w; end
    if not pointersOk or not complete then SchedulePointerResolve(5); end
    _positionReady = false;
    _wasInWorldDraw = false;
    _presentTick = -1;
    _inWorldTick = -1;
    RearmPositionIfInWorld();
end);

ashita.events.register('text_in', 'vd_welcome', function(e)
    if e.injected or e.blocked then return; end
    local msg = e.message or e.message_modified or '';
    if msg:find('<<< Welcome to', 1, true)
        or msg:find('Welcome to HorizonXI', 1, true) then
        updater.OnWelcomeChat();
    end
end);

ashita.events.register('unload', 'vd_unload', function()
    _pointerResolveGeneration = _pointerResolveGeneration + 1;
    updater.Cancel();
    ResetWeatherState();
    _weatherPtr = nil;
    _weatherMemResolved = false;
    _pGameMenu = nil;
    _gameMenuFailed = false;
    _pChatExpanded = nil;
    _chatExpandedFailed = false;
    display.Cleanup();
    -- Flush any pending window-position changes so a drag right before unload
    -- (or reload) is never lost.
    SaveVanaDialSettings();
    _addonAlive = false;
end);

local function PresentFrame()
    RunPresentComponent('Texture release', TextureManager.FlushPendingReleases);
    if not RunPresentComponent('Present cache', RefreshPresentCache) then return; end

    local inWorldDraw = _presentInWorld and not IsPlayerZoningNow() and GetSettingsCharKey() ~= nil;

    -- Apply the logged-in character's saved position once when entering the world.
    if inWorldDraw and not _wasInWorldDraw then
        EnsureDefaultWindowPosition(true);
        if gConfig then gConfig.appliedPositions = T{}; end
        _positionReady = true;
    elseif not inWorldDraw then
        _positionReady = false;
    end
    _wasInWorldDraw = inWorldDraw;

    if inWorldDraw then
        _allowPositionSave = true;
        RunPresentComponent('Texture acquisition', display.EnsureTextures);
    else
        _allowPositionSave = false;
    end

    if not ShouldDrawMain() and ShouldHideMainWindow() then
        RunPresentComponent('Main window hide', display.HideMainWindow);
    end

    if ShouldDrawMain() then
        local menuHidden = _presentMenuOpen;
        local chatHidden = _presentChatOpen;

        if not menuHidden and not chatHidden then
            RunPresentComponent('Main window draw', function()
                display.DrawWindow(weatherId);
            end);
        elseif ShouldHideMainWindow() then
            RunPresentComponent('Main window hide', display.HideMainWindow);
        end
    end

    -- Sunbreeze Racing is toggled independently from the main Vana'Dial window,
    -- but follows the same in-world and menu/chat visibility gates.
    if inWorldDraw and sunbreeze.IsOpen()
        and not _presentMenuOpen and not _presentChatOpen then
        RunPresentComponent('Sunbreeze window draw', sunbreeze.Draw);
    end

    if _configOpen then
        RunPresentComponent('Config window draw', function()
            config.Draw(_configOpen, function(open)
                if _configOpen and not open then
                    -- Request an immediate retryable save after this frame.
                    if _settingsDirty then
                        _settingsDirtyAt = MonotonicMs() - 800;
                    end
                end
                _configOpen = open;
            end);
        end);
    end

end

local _lastPresentFatalLog = -60000;
ashita.events.register('d3d_present', 'vd_present', function()
    _inPresentFrame = true;
    local ok, err = xpcall(PresentFrame, Traceback);
    _inPresentFrame = false;
    if not ok then
        local now = MonotonicMs();
        if now - _lastPresentFatalLog >= 30000 then
            _lastPresentFatalLog = now;
            pcall(VanaDialPrint, 'PRESENT contained an unexpected error: ' .. tostring(err));
        end
    end
    -- Flush off the Present thread after widgets have settled. settings.save
    -- serializes the whole table and writes disk; doing that inside ImGui
    -- (especially while dragging sliders/colors) triggers GC that can free
    -- another addon's D3D textures still in this frame's draw list.
    if _settingsDirty and (MonotonicMs() - _settingsDirtyAt) > 750 then
        ScheduleSettingsFlush();
    end
end);

ashita.events.register('zone_change', 'vd_zone_change', function()
    BeginZoning();
    TextureManager.ResetD3D8Device();
    SchedulePointerResolve(2);
end);

ashita.events.register('packet_in', 'vd_packet', function(e)
    if e.id == 0x000A then
        BeginZoning();
        ResetWeatherState();
        TextureManager.ResetD3D8Device();
        SchedulePointerResolve(2);
        return;
    end
    if e.id == 0x057 then
        local w = ReadWeatherFromPacket(e.data);
        if w ~= nil then
            weatherId = w;
        end
    end
end);

ashita.events.register('command', 'vd_command', function(e)
    local args = e.command:args();
    if #args == 0 then return; end

    local cmd = args[1]:lower();
    if cmd ~= '/vd' and cmd ~= '/vanadial' then return; end

    e.blocked = true;

    local sub = args[2] and args[2]:lower() or '';

    if sub == '' then
        hidden = not hidden;
        if hidden then
            VanaDialPrint('Hidden.');
        else
            VanaDialPrint('Shown.');
        end

    elseif sub == 'config' then
        _configOpen = not _configOpen;

    elseif sub == 'ships' or sub == 'vtships' then
        hidden = false;
        popups.OpenTimersSection('vdships');

    elseif sub == 'boats' or sub == 'vtboats' then
        hidden = false;
        popups.OpenTimersSection('vdboats');

    elseif sub == 'boatsall' or sub == 'vtboatsall' then
        hidden = false;
        popups.OpenTimersSection('vdboatsall');

    elseif sub == 'manaclipper' or sub == 'vtmanaclipper' then
        hidden = false;
        popups.OpenTimersSection('vdmanaclipper');

    elseif sub == 'barge' or sub == 'vtbarge' then
        hidden = false;
        popups.OpenTimersSection('vdbarge');

    elseif sub == 'rse' or sub == 'vtrse' then
        hidden = false;
        popups.OpenTimersSection('vdrse');

    elseif sub == 'lunar' or sub == 'vtlunar' then
        hidden = false;
        popups.OpenTimersSection('vdlunar');

    elseif sub == 'sunbreezerace' then
        local opened = sunbreeze.Toggle();
        VanaDialPrint(opened and 'Sunbreeze Racing window shown.'
            or 'Sunbreeze Racing window hidden.');

    elseif sub == 'show' then
        hidden = false;
        _wasInWorldDraw = false;
        RearmPositionIfInWorld();
        VanaDialPrint("Vana'Dial visibility reset.");

    elseif sub == 'reset' then
        if not gConfig.windowPositions then gConfig.windowPositions = T{}; end
        gConfig.windowPositions[WINDOW_KEY] = T{ x = 100, y = 100 };
        gConfig.appliedPositions = {};
        sunbreeze.ResetPosition();
        SaveVanaDialSettings();
        VanaDialPrint("Vana'Dial and Sunbreeze Racing positions reset.");

    elseif sub == 'update' then
        updater.RunUpdate();

    elseif sub == 'checkupdate' or sub == 'check' then
        updater.CheckAndNotify(true);

    else
        VanaDialPrint('Commands:');
        VanaDialPrint('  /vd               - Toggle visibility');
        VanaDialPrint('  /vd config        - Open config window');
        VanaDialPrint('  /vd ships         - Toggle airship timers (vtships ok)');
        VanaDialPrint('  /vd boats         - Toggle ferry boat timers (vtboats ok)');
        VanaDialPrint('  /vd boatsall      - Toggle all boat timer groups (vtboatsall ok)');
        VanaDialPrint('  /vd manaclipper   - Toggle Bibiki Manaclipper timers');
        VanaDialPrint('  /vd barge         - Toggle Carpenters\' Landing barge timers');
        VanaDialPrint('  /vd rse           - Toggle RSE timers (vtrse ok)');
        VanaDialPrint('  /vd lunar         - Toggle lunar timers (vtlunar ok)');
        VanaDialPrint('  /vd sunbreezerace - Toggle Sunbreeze Racing window');
        VanaDialPrint('  /vd reset         - Reset both standalone window positions');
        VanaDialPrint('  /vd update        - Download latest from GitHub');
        VanaDialPrint('  /vd checkupdate   - Check GitHub for updates');
        VanaDialPrint('  /vanadial         - Alias for /vd');
    end
end);
