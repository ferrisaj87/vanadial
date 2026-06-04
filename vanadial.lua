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
*   /vd boats             - Open/close boat timers section (expands all sub-routes)
*   /vd rse               - Open/close RSE timer section
*   /vd lunar             - Open/close lunar timer section
*   /vd reset             - Reset window position to default
*   /vd update            - Download latest from GitHub (then /addon reload vanadial)
*   /vd checkupdate       - Check GitHub for a newer version
]]--

addon.name    = 'vanadial';
addon.author  = 'Ferris';
addon.version = '1.2.6';
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
local updater           = require('libs.updater');
updater.Init(addon.version);
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
    if gConfig.showVanaTime ~= nil and gConfig.showVanaDial == nil then
        gConfig.showVanaDial = gConfig.showVanaTime;
    end
    if not gConfig.windowPositions then gConfig.windowPositions = T{}; end
    if gConfig.windowPositions['VanaTime'] and not gConfig.windowPositions[WINDOW_KEY] then
        gConfig.windowPositions[WINDOW_KEY] = gConfig.windowPositions['VanaTime'];
    end
end

-- Debounced settings persistence. SaveWindowPosition() runs every frame while a
-- window is dragged, so we never write to disk inline — instead we flag the
-- settings dirty and flush once movement has settled (see the d3d_present
-- handler). This keeps drag positions across reloads without thrashing disk I/O.
local _settingsDirty      = false;
local _settingsDirtyAt    = 0;
local _allowPositionSave  = false;

local function MarkSettingsDirty()
    _settingsDirty   = true;
    _settingsDirtyAt = os.clock();
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

local function OnCharacterSettingsReady(s)
    if s ~= nil then
        gConfig = s;
    end
    MigrateWindowSettings();
    if not gConfig.appliedPositions then
        gConfig.appliedPositions = T{};
    else
        gConfig.appliedPositions[WINDOW_KEY] = nil;
    end
    EnsureDefaultWindowPosition(true);
end

-- Reload per-character settings once the character folder is known (Anglin pattern).
settings.register('settings', 'vd_char_settings', function(s)
    settings.unregister('settings', 'vd_char_settings');
    OnCharacterSettingsReady(s);
end);

MigrateWindowSettings();
EnsureDefaultWindowPosition(false);

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
            imgui.SetNextWindowPos({pos.x, pos.y}, ImGuiCond_Always);
            gConfig.appliedPositions[windowName] = true;
            return true;
        end
    end
    return false;
end

function SaveWindowPosition(windowName)
    if not gConfig or not _allowPositionSave then return; end
    local x, y = imgui.GetWindowPos();
    -- Ignore garbage positions during zoning / loading screens.
    if x < 1 and y < 1 then return; end
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
local imtext          = require('libs.imtext');
local TextureManager  = require('libs.texturemanager');

-- ── Module state ──────────────────────────────────────────────────────────────
local hidden             = false;
local weatherId          = 0;

-- ── In-world gate (zonename / minimap pattern) ────────────────────────────────
-- Do not draw on the title screen, character select, or while zoning.

local function IsPlayerZoning(player)
    if not player then return true; end
    if player.isZoning == true then return true; end
    local ok, zoning = pcall(function() return player:GetIsZoning(); end);
    return ok and zoning == true;
end

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

local function ShouldDrawMain()
    if hidden then return false; end
    if gConfig.showVanaDial == false then return false; end
    return IsPlayerInWorld();
end

local function BeginZoning()
    _allowPositionSave = false;
    if not gConfig.appliedPositions then gConfig.appliedPositions = T{}; end
    gConfig.appliedPositions[WINDOW_KEY] = nil;
end
local pendingWeatherRead = false;
local pendingWeatherTime = 0;

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
    local ptr = ResolveWeatherPtrOnce();
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
    pendingWeatherRead    = false;
    pendingWeatherTime    = 0;
    _weatherPtr           = nil;
    _weatherMemResolved   = false;
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
    if _pGameMenu or _gameMenuFailed then return _pGameMenu end;
    _pGameMenu = ResolveGameMenuPtr();
    if not _pGameMenu then _gameMenuFailed = true; end
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
    if _pChatExpanded or _chatExpandedFailed then return _pChatExpanded end;
    _pChatExpanded = ResolveChatExpandedPtr();
    if not _pChatExpanded then _chatExpandedFailed = true; end
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

-- ── Events ────────────────────────────────────────────────────────────────────

ashita.events.register('load', 'vd_load', function()
    -- Load all fonts NOW, during the load event (outside any d3d_present frame).
    -- imgui.AddFontFromFileTTF mutates the font atlas; doing it mid-frame on the
    -- Ashita main lineage causes EXCEPTION_ACCESS_VIOLATION. Vana'Dial only uses
    -- Tahoma, so prewarm just that family (regular + bold).
    imtext.PrewarmFonts({'Tahoma'});
    display.Initialize();
    local w = ReadWeatherFromMemory();
    if w ~= nil then weatherId = w; end
    updater.ScheduleLoginCheck(15);
end);

ashita.events.register('unload', 'vd_unload', function()
    ResetWeatherState();
    _pGameMenu = nil;
    _gameMenuFailed = false;
    _pChatExpanded = nil;
    _chatExpandedFailed = false;
    display.Cleanup();
    -- Flush any pending window-position changes so a drag right before unload
    -- (or reload) is never lost.
    settings.save();
end);

ashita.events.register('d3d_present', 'vd_present', function()
    TextureManager.FlushPendingReleases();
    updater.TickLoginCheck();

    if IsPlayerInWorld() then
        _allowPositionSave = true;
    end

    if ShouldDrawMain() then
        -- Hide the clock + popups while a game menu or expanded chat log is open.
        -- The config window (below) is intentionally NOT gated so it stays usable.
        local menuHidden = gConfig.vanaTimeHideOnMenuFocus and IsGameMenuOpen();
        local chatHidden = gConfig.vanaTimeHideOnChatExpanded and IsChatExpanded();

        if not menuHidden and not chatHidden then
            -- Deferred weather re-read after zone-in.
            if pendingWeatherRead and os.time() >= pendingWeatherTime then
                pendingWeatherRead = false;
                local w = ReadWeatherFromMemory();
                if w ~= nil then weatherId = w; end
            end

            display.DrawWindow(weatherId);
        end
    end

    if _configOpen then
        config.Draw(_configOpen, function(open) _configOpen = open; end);
    end

    -- Debounced persistence: write the dragged window position to disk ~0.75s
    -- after the last movement, so positions survive reload without saving on
    -- every frame of a drag.
    if _settingsDirty and (os.clock() - _settingsDirtyAt) > 0.75 then
        _settingsDirty = false;
        settings.save();
    end
end);

ashita.events.register('zone_change', 'vd_zone_change', function()
    BeginZoning();
end);

ashita.events.register('packet_in', 'vd_packet', function(e)
    if e.id == 0x000A then
        BeginZoning();
        ResetWeatherState();
        _pGameMenu = nil;
        _gameMenuFailed = false;
        _pChatExpanded = nil;
        _chatExpandedFailed = false;
        pendingWeatherRead = true;
        pendingWeatherTime = os.time() + 2;
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
            print("[Vana'Dial] Hidden.");
        else
            print("[Vana'Dial] Shown.");
        end

    elseif sub == 'config' then
        _configOpen = not _configOpen;

    elseif sub == 'ships' or sub == 'vtships' then
        hidden = false;
        popups.OpenTimersSection('vdships');

    elseif sub == 'boats' or sub == 'vtboats' then
        hidden = false;
        popups.OpenTimersSection('vdboats');

    elseif sub == 'rse' or sub == 'vtrse' then
        hidden = false;
        popups.OpenTimersSection('vdrse');

    elseif sub == 'lunar' or sub == 'vtlunar' then
        hidden = false;
        popups.OpenTimersSection('vdlunar');

    elseif sub == 'reset' then
        if not gConfig.windowPositions then gConfig.windowPositions = T{}; end
        gConfig.windowPositions[WINDOW_KEY] = T{ x = 100, y = 100 };
        gConfig.appliedPositions = {};
        settings.save();
        print("[Vana'Dial] Position reset to (100, 100).");

    elseif sub == 'update' then
        updater.RunUpdate();

    elseif sub == 'checkupdate' or sub == 'check' then
        updater.CheckAndNotify(true);

    else
        print("[Vana'Dial] Commands:");
        print('  /vd               - Toggle visibility');
        print('  /vd config        - Open config window');
        print('  /vd ships         - Toggle airship timers (vtships ok)');
        print('  /vd boats         - Toggle boat timers (vtboats ok)');
        print('  /vd rse           - Toggle RSE timers (vtrse ok)');
        print('  /vd lunar         - Toggle lunar timers (vtlunar ok)');
        print('  /vd reset         - Reset window position');
        print('  /vd update        - Download latest from GitHub');
        print('  /vd checkupdate   - Check GitHub for updates');
        print('  /vanadial         - Alias for /vd');
    end
end);
