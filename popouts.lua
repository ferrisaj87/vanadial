--[[
* Vana'Dial timer pop outs.
*
* Cosmetic windows over the existing timer cache. A row pin or
* /vd popout <group> detaches that route (or group) into its own window so it
* can stay up while the main timer panel is closed. No schedule math lives here.
]]--

require('common');
local bit    = require('bit');
local imgui  = require('imgui');
local imtext = require('libs.imtext');
local Safe   = require('libs.imgui_safe');
local timers = require('timers');
local data   = require('data');

local M = {};

local WIN_FLAGS = bit.bor(
    ImGuiWindowFlags_NoDecoration,
    ImGuiWindowFlags_AlwaysAutoResize,
    ImGuiWindowFlags_NoFocusOnAppearing,
    ImGuiWindowFlags_NoNav,
    ImGuiWindowFlags_NoDocking,
    ImGuiWindowFlags_NoSavedSettings
);

-- Resizable width. Height is set from the rows, so dragging changes the width.
local POCKET_FLAGS = bit.bor(
    ImGuiWindowFlags_NoTitleBar,
    ImGuiWindowFlags_NoScrollbar,
    ImGuiWindowFlags_NoCollapse,
    ImGuiWindowFlags_NoFocusOnAppearing,
    ImGuiWindowFlags_NoNav,
    ImGuiWindowFlags_NoDocking,
    ImGuiWindowFlags_NoSavedSettings
);

local COL_GOLD      = {0.957, 0.855, 0.592, 1.0};
local COL_SEPARATOR = {0.28, 0.28, 0.28, 0.55};
local COL_OOS       = {0.85, 0.22, 0.22, 1.0};
local COL_WINDOW_BG = {0.02, 0.02, 0.03, 0.92};
local COL_BORDER    = {0.80, 0.67, 0.31, 0.90};
local COL_PILL_BG   = {0.025, 0.025, 0.030, 0.92};
local COL_NEW_MOON  = {0.95, 0.32, 0.30, 1.0};
local COL_FULL_MOON = {0.40, 0.70, 1.00, 1.0};
local COL_PIN_IDLE  = {0.76, 0.68, 0.47, 0.55};
local COL_PIN_HOT   = {0.96, 0.86, 0.55, 1.0};
local COL_PIN_FILL  = {0.80, 0.67, 0.31, 0.28};
local COL_CLOSE     = {0.78, 0.74, 0.64, 0.80};
local COL_CLOSE_HOT = {0.98, 0.90, 0.62, 1.0};
local COL_POCKET_BG = {0.11, 0.08, 0.045, 0.98};
local COL_SW_WELL   = {0.012, 0.010, 0.008, 0.96};
local COL_SW_DIM    = {0.78, 0.64, 0.40, 0.72};

local RSE_LOCATION_COLOR = {
    ['Shakrami Maze'] = {0.22, 0.80, 0.42, 1.0},
    ['Ordelle Caves'] = {0.90, 0.25, 0.30, 1.0},
    ['Gusgen Mines']  = {0.33, 0.53, 0.93, 1.0},
};

local _pa = {0, 0};
local _pb = {0, 0};

local openSet      = {};
local openOrder    = {};
local needsDefault = {};
local refreshFn    = nil;
local restoring    = false;

local pocketSet     = {};
local pocketOrder   = {};
local pocketVisible = false;
local pocketReady   = false;
local pocketPosX    = nil;
local pocketPosY    = nil;

local function NewWatch()
    return { accum = 0, running = false, mark = nil };
end

local function NewCountdown()
    return { hours = 0, minutes = 5, running = false, endsAt = 0, remain = 0, primed = true };
end

local watches     = { NewWatch() };
local countdowns  = { NewCountdown() };
local SavePocketTools;
local LoadPocketTools;

local pocketForceSize = true;
local pocketLaidOutH  = 0;
local pocketContentW  = 0;
local pocketItemRight = 0;
local pocketNaturalW  = 0;

local COMMANDS = {
    ships       = { key = 'group:airships',    label = 'Airship' },
    airships    = { key = 'group:airships',    label = 'Airship' },
    airship     = { key = 'group:airships',    label = 'Airship' },
    vtships     = { key = 'group:airships',    label = 'Airship' },
    vdships     = { key = 'group:airships',    label = 'Airship' },
    boats       = { key = 'group:boats',       label = 'Boat' },
    vtboats     = { key = 'group:boats',       label = 'Boat' },
    vdboats     = { key = 'group:boats',       label = 'Boat' },
    boatsall    = { key = 'group:boatsall',    label = 'All boat' },
    vtboatsall  = { key = 'group:boatsall',    label = 'All boat' },
    vdboatsall  = { key = 'group:boatsall',    label = 'All boat' },
    manaclipper = { key = 'group:manaclipper', label = 'Manaclipper' },
    vtmanaclipper = { key = 'group:manaclipper', label = 'Manaclipper' },
    vdmanaclipper = { key = 'group:manaclipper', label = 'Manaclipper' },
    barge       = { key = 'group:barge',       label = 'Barge' },
    vtbarge     = { key = 'group:barge',       label = 'Barge' },
    vdbarge     = { key = 'group:barge',       label = 'Barge' },
    rse         = { key = 'group:rse',         label = 'RSE' },
    vtrse       = { key = 'group:rse',         label = 'RSE' },
    vdrse       = { key = 'group:rse',         label = 'RSE' },
    lunar       = { key = 'group:lunar',       label = 'Lunar' },
    vtlunar     = { key = 'group:lunar',       label = 'Lunar' },
    vdlunar     = { key = 'group:lunar',       label = 'Lunar' },
    guilds      = { key = 'group:guilds',      label = 'Guild shop' },
    guild       = { key = 'group:guilds',      label = 'Guild shop' },
    guildshops  = { key = 'group:guilds',      label = 'Guild shop' },
    vtguilds    = { key = 'group:guilds',      label = 'Guild shop' },
    vdguilds    = { key = 'group:guilds',      label = 'Guild shop' },
};

-- ── Keys ──────────────────────────────────────────────────────────────────────

function M.AirshipKey(index)
    return 'air:' .. tostring(index);
end

function M.BoatKey(row)
    return 'boat:' .. tostring(row.city1 or '') .. '>' .. tostring(row.city2 or '')
        .. '>' .. tostring(row.city3 or '') .. '>' .. tostring(row.routeVia or '');
end

function M.RseKey(index)
    return 'rse:' .. tostring(index);
end

function M.LunarKey(phaseIdx)
    return 'lunar:' .. tostring(phaseIdx);
end

function M.GuildKey(id, place)
    local key = 'guild:' .. tostring(id);
    if place and place ~= '' then
        key = key .. ':' .. place;
    end
    return key;
end

function M.SetRefresh(fn)
    refreshFn = fn;
end

function M.IsOpen(key)
    return openSet[key] == true;
end

function M.IsAnyOpen()
    return openOrder[1] ~= nil or pocketVisible;
end

local function PosKey(key)
    return 'VdPop:' .. key;
end

local function ArmPosition(key)
    if gConfig and gConfig.appliedPositions then
        gConfig.appliedPositions[PosKey(key)] = nil;
    end
    needsDefault[key] = true;
end

local function TickMs()
    local ms = data.GetTickMs and data.GetTickMs();
    if ms then return ms; end
    return math.floor(os.clock() * 1000);
end

local function WatchMs(w)
    local ms = w.accum or 0;
    if w.running and w.mark then
        local delta = TickMs() - w.mark;
        if delta > 0 then ms = ms + delta; end
    end
    if ms < 0 then ms = 0; end
    return ms;
end

local function WatchStart(w)
    if w.running then return; end
    w.mark = TickMs();
    w.running = true;
    if SavePocketTools then SavePocketTools(); end
end

local function WatchStop(w)
    if not w.running then return; end
    w.accum = WatchMs(w);
    w.running = false;
    w.mark = nil;
    if SavePocketTools then SavePocketTools(); end
end

local function WatchReset(w)
    w.running = false;
    w.accum = 0;
    w.mark = nil;
    if SavePocketTools then SavePocketTools(); end
end

local function CdFull(c)
    return math.max(0, (c.hours or 0) * 3600 + (c.minutes or 0) * 60);
end

local function CdSeconds(c)
    if c.running and (c.endsAt or 0) > 0 then
        local left = c.endsAt - os.time();
        if left <= 0 then
            c.running = false;
            c.endsAt = 0;
            c.remain = 0;
            c.primed = true;
            return 0;
        end
        return left;
    end
    return math.max(0, c.remain or 0);
end

local function CdStart(c)
    if c.running then return; end
    local secs = CdSeconds(c);
    if c.primed ~= false or secs <= 0 then
        secs = CdFull(c);
    end
    if secs <= 0 then return; end
    c.remain = secs;
    c.endsAt = os.time() + secs;
    c.running = true;
    c.primed = false;
    if SavePocketTools then SavePocketTools(); end
end

local function CdStop(c)
    if not c.running then return; end
    c.remain = 0;
    c.running = false;
    c.endsAt = 0;
    c.primed = true;
    if SavePocketTools then SavePocketTools(); end
end

local function CdReset(c)
    c.running = false;
    c.endsAt = 0;
    c.remain = 0;
    c.primed = true;
    if SavePocketTools then SavePocketTools(); end
end

local function ToolsHoldWindow()
    for i = 1, #watches do
        local w = watches[i];
        if w.running or WatchMs(w) > 0 then return true; end
    end
    for i = 1, #countdowns do
        local c = countdowns[i];
        if c.running or c.primed == false then return true; end
    end
    return false;
end

SavePocketTools = function()
    if restoring or not gConfig then return; end
    local savedW = T{};
    for i = 1, #watches do
        local w = watches[i];
        savedW[i] = T{ accum = WatchMs(w), running = w.running == true };
    end
    gConfig.pocketWatches = savedW;
    local savedC = T{};
    for i = 1, #countdowns do
        local c = countdowns[i];
        savedC[i] = T{
            hours = c.hours or 0,
            minutes = c.minutes or 0,
            running = c.running == true,
            endsAt = c.running and (c.endsAt or 0) or 0,
            remain = CdSeconds(c),
            primed = c.primed ~= false,
        };
    end
    gConfig.pocketCountdowns = savedC;
    if SaveVanaDialSettings then SaveVanaDialSettings(); end
end

LoadPocketTools = function()
    watches = {};
    local savedW = gConfig and gConfig.pocketWatches;
    if type(savedW) == 'table' then
        local n = 0;
        for k, v in pairs(savedW) do
            local i = tonumber(k);
            if i and i > n then n = i; end
            if i and type(v) == 'table' then
                local w = NewWatch();
                w.accum = math.max(0, tonumber(v.accum) or 0);
                w.running = v.running == true;
                if w.running then w.mark = TickMs(); end
                watches[i] = w;
            end
        end
        local compact = {};
        for i = 1, n do
            if watches[i] then compact[#compact + 1] = watches[i]; end
        end
        watches = compact;
    end
    if watches[1] == nil then watches[1] = NewWatch(); end

    countdowns = {};
    local savedC = gConfig and gConfig.pocketCountdowns;
    if type(savedC) == 'table' then
        local n = 0;
        local indexed = {};
        for k, v in pairs(savedC) do
            local i = tonumber(k);
            if i and type(v) == 'table' then
                if i > n then n = i; end
                local c = NewCountdown();
                c.hours = math.max(0, math.min(99, math.floor(tonumber(v.hours) or 0)));
                c.minutes = math.max(0, math.min(59, math.floor(tonumber(v.minutes) or 0)));
                c.running = v.running == true;
                c.endsAt = tonumber(v.endsAt) or 0;
                c.remain = math.max(0, tonumber(v.remain) or 0);
                c.primed = v.primed ~= false;
                if c.running and (c.endsAt <= 0 or c.endsAt <= os.time()) then
                    c.running = false;
                    c.endsAt = 0;
                    c.remain = 0;
                end
                if not c.running then
                    c.primed = true;
                    c.remain = 0;
                end
                indexed[i] = c;
            end
        end
        for i = 1, n do
            if indexed[i] then countdowns[#countdowns + 1] = indexed[i]; end
        end
    end
    if countdowns[1] == nil then countdowns[1] = NewCountdown(); end
end

local function FormatStopwatch(ms)
    local cs = math.floor(ms / 10) % 100;
    local totalSec = math.floor(ms / 1000);
    local ss = totalSec % 60;
    local mm = math.floor(totalSec / 60);
    local main = (mm > 99) and string.format('%d:%02d', mm, ss) or string.format('%02d:%02d', mm, ss);
    return main, string.format('%02d', cs);
end

local function PersistPocket()
    if restoring or not gConfig then return; end
    local list = T{};
    for i = 1, #pocketOrder do
        list[i] = pocketOrder[i];
    end
    gConfig.pocketKeys = list;
    gConfig.pocketOpen = pocketVisible;
    if SavePocketTools then SavePocketTools(); end
    if SaveVanaDialSettings then SaveVanaDialSettings(); end
end

local function PocketHasTimers()
    return pocketOrder[1] ~= nil;
end

local function PocketKeepWindow()
    return PocketHasTimers() or ToolsHoldWindow();
end

local function PocketShow()
    if pocketVisible then return; end
    pocketVisible = true;
    if not (gConfig and gConfig.windowPositions and gConfig.windowPositions[PosKey('pocket')]) then
        ArmPosition('pocket');
    end
    PersistPocket();
end

local function PocketHide()
    if not pocketVisible then return; end
    pocketVisible = false;
    PersistPocket();
end

local function PocketAdd(key)
    if type(key) ~= 'string' or key == '' then return; end
    if not pocketSet[key] then
        pocketSet[key] = true;
        pocketOrder[#pocketOrder + 1] = key;
    end
    pocketVisible = true;
    if not (gConfig and gConfig.windowPositions and gConfig.windowPositions[PosKey('pocket')]) then
        ArmPosition('pocket');
    end
    PersistPocket();
end

local function PocketRemove(key)
    if not pocketSet[key] then return; end
    pocketSet[key] = nil;
    for i, existing in ipairs(pocketOrder) do
        if existing == key then
            table.remove(pocketOrder, i);
            break;
        end
    end
    if not PocketKeepWindow() then
        pocketVisible = false;
    end
    PersistPocket();
end

function M.PocketClick(key)
    if pocketSet[key] and pocketVisible then
        PocketRemove(key);
        return;
    end
    if pocketSet[key] then
        PocketShow();
        return;
    end
    PocketAdd(key);
end

local function PersistOpen()
    if restoring or not gConfig then return; end
    local list = T{};
    for i = 1, #openOrder do
        list[i] = openOrder[i];
    end
    gConfig.popoutsOpen = list;
    if SaveVanaDialSettings then SaveVanaDialSettings(); end
end

local function SetOpen(key, open)
    if open then
        if openSet[key] then return true; end
        openSet[key] = true;
        openOrder[#openOrder + 1] = key;
        ArmPosition(key);
        PersistOpen();
        return true;
    end
    if not openSet[key] then return false; end
    openSet[key] = nil;
    needsDefault[key] = nil;
    for i, existing in ipairs(openOrder) do
        if existing == key then
            table.remove(openOrder, i);
            break;
        end
    end
    PersistOpen();
    return false;
end

function M.Toggle(key)
    if openSet[key] then
        SetOpen(key, false);
        return false;
    end
    SetOpen(key, true);
    return true;
end

function M.CloseAll()
    for i = #openOrder, 1, -1 do
        local key = openOrder[i];
        openSet[key] = nil;
        needsDefault[key] = nil;
        openOrder[i] = nil;
    end
    PersistOpen();
    if pocketVisible then
        PocketHide();
    end
end

local function RememberPocketPosition()
    local positions = gConfig and gConfig.windowPositions;
    local pos = positions and positions['VdPop:pocket'];
    if not pos then return; end
    local x, y = tonumber(pos.x), tonumber(pos.y);
    if x and y then
        pocketPosX, pocketPosY = x, y;
    end
end

local function EnsurePocketPosition()
    if not gConfig or not pocketPosX or not pocketPosY then return; end
    if not gConfig.windowPositions then gConfig.windowPositions = T{}; end
    if not gConfig.windowPositions['VdPop:pocket'] then
        gConfig.windowPositions['VdPop:pocket'] = T{ x = pocketPosX, y = pocketPosY };
    end
    if gConfig.appliedPositions then
        gConfig.appliedPositions['VdPop:pocket'] = nil;
    end
end

local function NotePocketPosition()
    local x, y = imgui.GetWindowPos();
    if type(x) ~= 'number' or type(y) ~= 'number' then return; end
    if x < -32000 or y < -32000 or x > 32000 or y > 32000 then return; end
    pocketPosX, pocketPosY = x, y;
end

local function ReadPocketKeys(saved)
    local indexed = {};
    local n = 0;
    if type(saved) ~= 'table' then return indexed; end
    for k, value in pairs(saved) do
        local i = tonumber(k);
        if i and i >= 1 and type(value) == 'string' and value ~= '' then
            indexed[i] = value;
            if i > n then n = i; end
        end
    end
    local list = {};
    local seen = {};
    for i = 1, n do
        local key = indexed[i];
        if key and not seen[key] then
            seen[key] = true;
            list[#list + 1] = key;
        end
    end
    return list;
end

function M.RestoreSaved(sameCharacter)
    restoring = true;
    for i = #openOrder, 1, -1 do
        local key = openOrder[i];
        openSet[key] = nil;
        needsDefault[key] = nil;
        openOrder[i] = nil;
    end
    local saved = gConfig and gConfig.popoutsOpen;
    if type(saved) == 'table' then
        for _, key in ipairs(saved) do
            if type(key) == 'string' and key ~= '' and not openSet[key] then
                openSet[key] = true;
                openOrder[#openOrder + 1] = key;
                ArmPosition(key);
            end
        end
    end
    restoring = false;

    local savedPocket = ReadPocketKeys(gConfig and gConfig.pocketKeys);
    local savedOpen = gConfig and gConfig.pocketOpen == true;
    -- Same character, or a zone where the character isn't known yet: a settings
    -- reload can arrive without the pocket. Keep the open window and its timers.
    -- A confirmed character change loads that character's own list.
    if pocketReady and sameCharacter ~= false and not (savedPocket[1] or savedOpen)
        and (pocketOrder[1] ~= nil or pocketVisible) then
        if sameCharacter == true then
            RememberPocketPosition();
            EnsurePocketPosition();
            PersistPocket();
        end
        return;
    end

    pocketSet = {};
    pocketOrder = {};
    for i = 1, #savedPocket do
        local key = savedPocket[i];
        if not pocketSet[key] then
            pocketSet[key] = true;
            pocketOrder[#pocketOrder + 1] = key;
        end
    end
    pocketVisible = gConfig and gConfig.pocketOpen == true;
    RememberPocketPosition();
    if pocketVisible then
        EnsurePocketPosition();
    end
    if LoadPocketTools then LoadPocketTools(); end
    pocketReady = true;
end

function M.ToggleCommand(name)
    name = name and name:lower() or '';
    if name == 'close' or name == 'off' or name == 'hide' or name == 'none' then
        local any = openOrder[1] ~= nil or pocketVisible;
        M.CloseAll();
        if any then return 'Timer pop outs closed.'; end
        return 'No timer pop outs were open.';
    end
    local spec = COMMANDS[name];
    if not spec then return nil; end
    if M.Toggle(spec.key) then
        return spec.label .. ' pop out shown.';
    end
    return spec.label .. ' pop out hidden.';
end

function M.ResetPositions()
    if gConfig and gConfig.windowPositions then
        local drop = {};
        for name in pairs(gConfig.windowPositions) do
            if type(name) == 'string' and name:sub(1, 6) == 'VdPop:' then
                drop[#drop + 1] = name;
            end
        end
        for _, name in ipairs(drop) do
            gConfig.windowPositions[name] = nil;
            if gConfig.appliedPositions then
                gConfig.appliedPositions[name] = nil;
            end
        end
    end
    for _, key in ipairs(openOrder) do
        needsDefault[key] = true;
    end
    needsDefault['pocket'] = true;
end

-- ── Row chrome (mirrors the timer panel, without the pin) ────────────────────

local function CloseSize()
    return math.max(12, math.floor(imgui.GetTextLineHeight()));
end

local function DrawPill(id, text, color, urgent)
    text = text or '--';
    local textColor = color or timers.colorDimGrey;
    local borderColor = timers.FlashColor(textColor, urgent);
    local textW = imgui.CalcTextSize(text);
    local textH = imgui.GetTextLineHeight();
    local minTextW = imgui.CalcTextSize('00m 00s');
    local padX, padY = 7, 3;
    local pillW = math.max(textW, minTextW) + padX * 2;
    local pillH = textH + padY * 2;
    local x, y = imgui.GetCursorScreenPos();

    imgui.InvisibleButton('##vdPopPill_' .. id, {pillW, pillH});

    local dl = imgui.GetWindowDrawList();
    local rounding = pillH * 0.45;
    _pa[1] = x; _pa[2] = y; _pb[1] = x + pillW; _pb[2] = y + pillH;
    dl:AddRectFilled(_pa, _pb, imgui.GetColorU32(COL_PILL_BG), rounding);
    dl:AddRect(_pa, _pb, imgui.GetColorU32(borderColor), rounding, nil, 1.0);
    _pa[1] = x + (pillW - textW) * 0.5;
    _pa[2] = y + (pillH - textH) * 0.5;
    dl:AddText(_pa, imgui.GetColorU32(textColor), text);
end

local function DrawCities(row)
    if row.city1 then
        imgui.TextColored(row.city1Color or timers.colorGold, row.city1);
        if row.city2 and row.city2 ~= '' then
            imgui.SameLine(0, 4);
            imgui.TextColored(timers.colorGoldDark, row.arrow or '>');
            imgui.SameLine(0, 4);
            imgui.TextColored(row.city2Color or timers.colorGold, row.city2);
        end
        if row.city3 and row.city3 ~= '' then
            imgui.SameLine(0, 4);
            imgui.TextColored(timers.colorGoldDark, '>');
            imgui.SameLine(0, 4);
            imgui.TextColored(row.city3Color or timers.colorGold, row.city3);
        end
        if row.routeVia and row.routeVia ~= '' then
            imgui.SameLine(0, 6);
            imgui.TextColored(timers.colorDimGrey, row.routeVia);
        end
    else
        imgui.TextColored(timers.colorGoldDark, row.label or '');
    end
end

local function StatusOf(row)
    if row.isOOS then return 'Out of Service', COL_OOS; end
    if row.isServicedSoon then return 'Serviced Soon', timers.colorServicedSoon; end
    if row.isAwaiting then return 'AWAITING', row.cdColor or timers.colorAwaiting; end
    if row.isBoarding then return 'BOARDING', row.cdColor or timers.colorBoarding; end
    if row.isDocking then return 'DOCKING', row.cdColor or timers.colorDocking; end
    if row.isTransit then return 'IN-TRANSIT', row.cdColor or timers.colorGoldDark; end
    return nil, nil;
end

local function AlignRight(width)
    local avail = imgui.GetContentRegionAvail();
    if type(avail) == 'number' and avail > width then
        imgui.SetCursorPosX(imgui.GetCursorPosX() + (avail - width));
    end
end

local function DrawGearIcon(x, y, size, hot)
    local dl = imgui.GetWindowDrawList();
    local u = imgui.GetColorU32(hot and COL_CLOSE_HOT or COL_CLOSE);
    local cx, cy = x + size * 0.5, y + size * 0.5;
    local r = size * 0.26;
    _pa[1] = cx; _pa[2] = cy;
    dl:AddCircle(_pa, r, u, 12, 1.15);
    dl:AddCircleFilled(_pa, math.max(1.2, r * 0.38), u, 8);
    for i = 0, 5 do
        local a = (i / 6) * math.pi * 2;
        local inner, outer = r * 0.85, r * 1.7;
        _pa[1] = cx + math.cos(a) * inner; _pa[2] = cy + math.sin(a) * inner;
        _pb[1] = cx + math.cos(a) * outer; _pb[2] = cy + math.sin(a) * outer;
        dl:AddLine(_pa, _pb, u, 1.35);
    end
end

local function GearButton(id, scaleKey)
    local size = CloseSize();
    local x, y = imgui.GetCursorScreenPos();
    local clicked = imgui.InvisibleButton('##vdPopGear_' .. tostring(id), { size, size });
    local hovered = imgui.IsItemHovered();
    DrawGearIcon(x, y, size, hovered);
    if hovered then
        imgui.SetTooltip('Pocket scale');
    end
    if clicked and VanaDial_OpenPopoutScale then
        VanaDial_OpenPopoutScale(scaleKey);
    end
    return clicked;
end

local function NoteItemRight()
    local x = imgui.GetItemRectMax();
    if type(x) == 'table' then
        x = x[1] or x.x;
    elseif type(x) == 'userdata' then
        x = x.x;
    end
    if type(x) == 'number' and x > pocketItemRight then
        pocketItemRight = x;
    end
end

-- Natural row width, before a row is centered or pinned to the window edge.
local function NoteNatural(w)
    if type(w) == 'number' and w > pocketNaturalW then
        pocketNaturalW = w;
    end
end

local function CloseButton(id, size, tip)
    local x, y = imgui.GetCursorScreenPos();
    local clicked = imgui.InvisibleButton('##vdPopX_' .. id, {size, size});
    NoteItemRight();
    local hovered = imgui.IsItemHovered();
    local col = hovered and COL_CLOSE_HOT or COL_CLOSE;
    local u = imgui.GetColorU32(col);
    local dl = imgui.GetWindowDrawList();
    local m = math.max(3, math.floor(size * 0.28));
    _pa[1] = x + m; _pa[2] = y + m; _pb[1] = x + size - m; _pb[2] = y + size - m;
    dl:AddLine(_pa, _pb, u, 1.25);
    _pa[1] = x + size - m; _pa[2] = y + m; _pb[1] = x + m; _pb[2] = y + size - m;
    dl:AddLine(_pa, _pb, u, 1.25);
    if hovered then
        imgui.SetTooltip(tip or 'Close');
    end
    return clicked;
end

local function PlaceClose(id, tip)
    local size = CloseSize();
    imgui.SameLine(0, 8);
    return CloseButton(id, size, tip);
end

local function DrawRouteLine(row, id, withClose, closeTip)
    local cdColor = (row.isEmpty or not row.cdColor) and timers.colorDimGrey or row.cdColor;
    DrawPill(id, row.countdownStr, cdColor, row.urgent);
    imgui.SameLine(0, 8);
    DrawCities(row);
    local status, statusCol = StatusOf(row);
    if status then
        imgui.SameLine(0, 8);
        imgui.TextColored(statusCol, status);
    end
    if withClose then
        return PlaceClose(id, closeTip);
    end
    return false;
end

local function DrawDivider(scope)
    local mark = scope:Mark();
    scope:PushStyleColor(ImGuiCol_Separator, COL_SEPARATOR);
    imgui.Separator();
    scope:CloseTo(mark);
end

local function DrawAirshipBlock(scope, row, index, withClose, closeTip)
    local closed = DrawRouteLine(row, 'pair_' .. index, withClose, closeTip);
    if row.sub and (row.sub.city1 or row.sub.label) then
        local mark = scope:Mark();
        scope:Indent(16);
        DrawRouteLine(row.sub, 'pair_sub_' .. index, false);
        scope:CloseTo(mark);
    end
    return closed;
end

local function DrawRseLine(e, id, withClose, closeTip)
    local pillColor = e.isCurrent and timers.colorSoon or timers.colorWaiting;
    local nameColor = e.isCurrent and timers.colorGoldDark or timers.colorGoldMuted;
    DrawPill(id, e.countdownStr, pillColor);
    imgui.SameLine(0, 8);
    imgui.TextColored(nameColor, e.slotName or '');
    imgui.SameLine(0, 5);
    imgui.TextColored(timers.colorDimGrey, '@');
    imgui.SameLine(0, 4);
    imgui.TextColored(RSE_LOCATION_COLOR[e.location] or timers.colorDimGrey, e.location or '');
    if e.dateStr and e.dateStr ~= '' then
        imgui.SameLine(0, 8);
        imgui.TextColored(timers.colorDimGrey, e.dateStr);
    end
    if withClose then
        return PlaceClose(id, closeTip);
    end
    return false;
end

local function LunarNameColor(e)
    if e.phaseIdx == 0 then return COL_NEW_MOON; end
    if e.phaseIdx == 6 then return COL_FULL_MOON; end
    if e.isCurrent then return timers.colorGoldDark; end
    return timers.colorGoldMuted;
end

local function DrawLunarLine(e, id, withClose, closeTip)
    local pillColor = e.isCurrent and timers.colorSoon or timers.colorWaiting;
    DrawPill(id, e.countdownStr, pillColor);
    imgui.SameLine(0, 8);
    imgui.TextColored(LunarNameColor(e), e.phaseName or '');
    if e.isCurrent then
        imgui.SameLine(0, 8);
        imgui.TextColored(timers.colorDimGrey, 'ends');
    end
    if e.dateStr and e.dateStr ~= '' then
        imgui.SameLine(0, 4);
        imgui.TextColored(timers.colorGrey, e.dateStr);
    end
    if withClose then
        return PlaceClose(id, closeTip);
    end
    return false;
end

local function PillSize(text)
    local textW = imgui.CalcTextSize(text or '--');
    local textH = imgui.GetTextLineHeight();
    local minTextW = imgui.CalcTextSize('00m 00s');
    return math.max(textW, minTextW) + 14, textH + 6;
end

local function CenterCursor(itemW)
    local avail = imgui.GetContentRegionAvail();
    if type(avail) == 'number' and avail > itemW then
        imgui.SetCursorPosX(imgui.GetCursorPosX() + (avail - itemW) * 0.5);
    end
end

local function CenterText(text, color)
    CenterCursor(imgui.CalcTextSize(text));
    imgui.TextColored(color, text);
end

local function CenterPill(id, text, color)
    local pillW = PillSize(text);
    CenterCursor(pillW);
    DrawPill(id, text, color);
end

local function GuildLineWidth(e, hol)
    local label = e.shortName or e.name or '';
    local place = hol.place or '';
    local groupW = imgui.CalcTextSize(label);
    if place ~= '' then
        groupW = groupW + 4 + imgui.CalcTextSize('-') + 4 + imgui.CalcTextSize(place);
    end
    return groupW + 8 + PillSize(hol.pillText or '');
end

local function HolidayLineWidth(hol)
    local width = 12 + imgui.CalcTextSize('Holidays:') + 6 + imgui.CalcTextSize(hol.name or '');
    if hol.countdownStr and hol.countdownStr ~= '' then
        width = width + 8 + PillSize(hol.countdownStr);
    end
    return width;
end

local function DrawGuildLocation(e, hol, id)
    local muted = hol.onHoliday == true;
    local nameColor = muted and timers.colorDimGrey or (e.nameColor or timers.colorGold);
    local placeColor = muted and timers.colorDimGrey or (hol.placeColor or nameColor);
    imgui.TextColored(nameColor, e.shortName or e.name or '');
    if hol.place and hol.place ~= '' then
        imgui.SameLine(0, 4);
        imgui.TextColored(timers.colorDimGrey, '-');
        imgui.SameLine(0, 4);
        imgui.TextColored(placeColor, hol.place);
    end
    imgui.SameLine(0, 8);
    DrawPill(id, hol.pillText or '', hol.statusColor or timers.colorDimGrey);
    imgui.Indent(12);
    imgui.TextColored(muted and timers.colorDimGrey or timers.colorTeal, 'Holidays:');
    imgui.SameLine(0, 6);
    imgui.TextColored(muted and timers.colorDimGrey or timers.DayColor(hol.colorKey), hol.name or '');
    if hol.countdownStr and hol.countdownStr ~= '' then
        imgui.SameLine(0, 8);
        DrawPill(id .. '_h', hol.countdownStr, hol.cdColor or timers.colorDocking);
    end
    imgui.Unindent(12);
end

local function DrawGuildLine(scope, e, id, withClose, onlyIndex, closeTip)
    local closed = false;
    local count = e.holidayCount or 0;
    local closeSize = withClose and CloseSize() or 0;
    local placedClose = false;
    for h = 1, count do
        if not onlyIndex or h == onlyIndex then
            local hol = e.holidays[h];
            if withClose and not placedClose then
                local nameW = GuildLineWidth(e, hol);
                local contentW = math.max(nameW + closeSize + 8, HolidayLineWidth(hol));
                local cursorX = imgui.GetCursorPosX();
                local cursorY = imgui.GetCursorPosY();
                imgui.SetCursorPosX(cursorX + contentW - closeSize);
                closed = CloseButton('card_' .. id, closeSize, closeTip);
                imgui.SetCursorPos({cursorX, cursorY});
                placedClose = true;
            end
            DrawGuildLocation(e, hol, id .. '_' .. h);
        end
    end
    return closed;
end

local function TrimLabel(text)
    return (tostring(text or ''):gsub('%s+$', ''));
end

local function DrawBoatGroup(scope, headerLabel, showHeaders)
    local on = false;
    local needDiv = false;
    local any = false;
    for i, entry in ipairs(timers.boats) do
        if entry.isHeader then
            local match = (headerLabel == nil) or (entry.label == headerLabel);
            on = match;
            if match and showHeaders then
                if needDiv then DrawDivider(scope); end
                imgui.TextColored(COL_GOLD, TrimLabel(entry.label));
                needDiv = false;
                any = true;
            end
        elseif on and entry.city1 then
            if needDiv then DrawDivider(scope); end
            DrawRouteLine(entry, 'gboat_' .. i, false);
            needDiv = true;
            any = true;
        end
    end
    if not any then
        imgui.TextColored(timers.colorDimGrey, '--');
    end
end

local function FindBoat(key)
    for _, entry in ipairs(timers.boats) do
        if not entry.isHeader and entry.city1 and M.BoatKey(entry) == key then
            return entry;
        end
    end
    return nil;
end

local function FindGuild(key)
    local id, place = key:match('^guild:([^:]+):(.+)$');
    if not id then
        id = key:match('^guild:(.+)$');
    end
    if not id then return nil, nil; end
    for _, entry in ipairs(timers.guilds) do
        if entry.id == id then
            if not place or place == '' then return entry, nil; end
            local count = entry.holidayCount or 0;
            for h = 1, count do
                local hol = entry.holidays[h];
                if hol and hol.place == place then
                    return entry, h;
                end
            end
            return nil, nil;
        end
    end
    return nil, nil;
end

local function FindLunar(phaseIdx)
    for _, entry in ipairs(timers.lunar) do
        if entry.phaseIdx == phaseIdx and entry.phaseName then
            return entry;
        end
    end
    return nil;
end

local function DrawTitle(scope, text, key)
    imgui.TextColored(COL_GOLD, text);
    local closed = PlaceClose('title_' .. key);
    if not closed then
        DrawDivider(scope);
    end
    return closed;
end

local function DrawBody(scope, key)
    if key == 'group:airships' then
        if DrawTitle(scope, 'Airships', key) then return true; end
        for i, entry in ipairs(timers.airships) do
            if i > 1 then DrawDivider(scope); end
            DrawAirshipBlock(scope, entry, i, false);
        end
        return false;
    end
    if key == 'group:boats' then
        if DrawTitle(scope, 'Boats', key) then return true; end
        DrawBoatGroup(scope, timers.BOAT_GROUP.FERRIES, false);
        return false;
    end
    if key == 'group:boatsall' then
        if DrawTitle(scope, 'All Boats', key) then return true; end
        DrawBoatGroup(scope, nil, true);
        return false;
    end
    if key == 'group:manaclipper' then
        if DrawTitle(scope, 'Manaclipper', key) then return true; end
        DrawBoatGroup(scope, timers.BOAT_GROUP.MANACLIPPER, false);
        return false;
    end
    if key == 'group:barge' then
        if DrawTitle(scope, 'Barge', key) then return true; end
        DrawBoatGroup(scope, timers.BOAT_GROUP.BARGE, false);
        return false;
    end
    if key == 'group:rse' then
        if DrawTitle(scope, 'RSE', key) then return true; end
        for i, entry in ipairs(timers.rse) do
            if not entry.slotName then break; end
            if i > 1 then DrawDivider(scope); end
            DrawRseLine(entry, 'grse_' .. i, false);
        end
        return false;
    end
    if key == 'group:lunar' then
        if DrawTitle(scope, 'Lunar Phases', key) then return true; end
        for i, entry in ipairs(timers.lunar) do
            if not entry.phaseName or entry.phaseName == '' then break; end
            if i > 1 then DrawDivider(scope); end
            DrawLunarLine(entry, 'glun_' .. i, false);
        end
        return false;
    end
    if key == 'group:guilds' then
        if DrawTitle(scope, 'Guild Shops', key) then return true; end
        local shown = 0;
        for i, entry in ipairs(timers.guilds) do
            if not entry.name then break; end
            if timers.GuildShown(entry.id) then
                if shown > 0 then DrawDivider(scope); end
                DrawGuildLine(scope, entry, 'gguild_' .. i, false);
                shown = shown + 1;
            end
        end
        if shown == 0 then
            imgui.TextColored(timers.colorDimGrey, 'No shops selected');
        end
        return false;
    end

    local airIndex = key:match('^air:(%d+)$');
    if airIndex then
        local row = timers.airships[tonumber(airIndex)];
        if not row then
            imgui.TextColored(timers.colorDimGrey, '--');
            return PlaceClose(key);
        end
        return DrawAirshipBlock(scope, row, airIndex, true);
    end
    if key:sub(1, 5) == 'boat:' then
        local row = FindBoat(key);
        if not row then
            imgui.TextColored(timers.colorDimGrey, '--');
            return PlaceClose(key);
        end
        return DrawRouteLine(row, 'oneboat', true);
    end
    local rseIndex = key:match('^rse:(%d+)$');
    if rseIndex then
        local row = timers.rse[tonumber(rseIndex)];
        if not row or not row.slotName then
            imgui.TextColored(timers.colorDimGrey, '--');
            return PlaceClose(key);
        end
        return DrawRseLine(row, 'onerse', true);
    end
    local phaseIdx = key:match('^lunar:(%d+)$');
    if phaseIdx then
        local row = FindLunar(tonumber(phaseIdx));
        if not row then
            imgui.TextColored(timers.colorDimGrey, '--');
            return PlaceClose(key);
        end
        return DrawLunarLine(row, 'onelunar', true);
    end
    if key:sub(1, 6) == 'guild:' then
        local row, holIndex = FindGuild(key);
        if not row then
            imgui.TextColored(timers.colorDimGrey, '--');
            return PlaceClose(key);
        end
        return DrawGuildLine(scope, row, 'oneguild', true, holIndex);
    end
    imgui.TextColored(timers.colorDimGrey, '--');
    return PlaceClose(key);
end

-- One pocket row. The close control removes that timer from the pocket.
local function DrawPocketEntry(scope, key)
    local tip = 'Remove';
    local airIndex = key:match('^air:(%d+)$');
    if airIndex then
        local row = timers.airships[tonumber(airIndex)];
        if not row then
            imgui.TextColored(timers.colorDimGrey, '--');
            return PlaceClose('pocket_' .. key, tip);
        end
        return DrawAirshipBlock(scope, row, 'p' .. airIndex, true, tip);
    end
    if key:sub(1, 5) == 'boat:' then
        local row = FindBoat(key);
        if not row then
            imgui.TextColored(timers.colorDimGrey, '--');
            return PlaceClose('pocket_' .. key, tip);
        end
        return DrawRouteLine(row, 'pboat_' .. key, true, tip);
    end
    local rseIndex = key:match('^rse:(%d+)$');
    if rseIndex then
        local row = timers.rse[tonumber(rseIndex)];
        if not row or not row.slotName then
            imgui.TextColored(timers.colorDimGrey, '--');
            return PlaceClose('pocket_' .. key, tip);
        end
        return DrawRseLine(row, 'prse_' .. rseIndex, true, tip);
    end
    local phaseIdx = key:match('^lunar:(%d+)$');
    if phaseIdx then
        local row = FindLunar(tonumber(phaseIdx));
        if not row then
            imgui.TextColored(timers.colorDimGrey, '--');
            return PlaceClose('pocket_' .. key, tip);
        end
        return DrawLunarLine(row, 'plunar_' .. phaseIdx, true, tip);
    end
    if key:sub(1, 6) == 'guild:' then
        local row, holIndex = FindGuild(key);
        if not row then
            imgui.TextColored(timers.colorDimGrey, '--');
            return PlaceClose('pocket_' .. key, tip);
        end
        return DrawGuildLine(scope, row, 'pguild_' .. key, true, holIndex, tip);
    end
    imgui.TextColored(timers.colorDimGrey, '--');
    return PlaceClose('pocket_' .. key, tip);
end

local WATCH_COLORS = {
    { 0.94, 0.82, 0.48 },
    { 0.93, 0.55, 0.32 },
    { 0.86, 0.70, 0.36 },
    { 0.78, 0.48, 0.36 },
};

local COUNTDOWN_COLORS = {
    { 0.42, 0.78, 0.74 },
    { 0.48, 0.66, 0.90 },
    { 0.52, 0.76, 0.48 },
    { 0.70, 0.56, 0.86 },
};

local function TextWidth(text)
    local w = imgui.CalcTextSize(text or '');
    if type(w) == 'table' then w = w[1] or w.x; end
    if type(w) == 'userdata' then w = w.x; end
    return tonumber(w) or 0;
end

local function ToolAccent(list, index)
    return list[((index - 1) % #list) + 1];
end

local function Rgba(rgb, alpha)
    return { rgb[1], rgb[2], rgb[3], alpha };
end

local function Bright(rgb)
    return {
        math.min(1, rgb[1] * 0.35 + 0.65),
        math.min(1, rgb[2] * 0.35 + 0.65),
        math.min(1, rgb[3] * 0.35 + 0.65),
        1,
    };
end

local function SwChip(id, label, width, height, quiet, accent)
    local rgb = accent or { 0.80, 0.67, 0.31 };
    local x, y = imgui.GetCursorScreenPos();
    local clicked = imgui.InvisibleButton(id, { width, height });
    local hot = imgui.IsItemHovered();
    local dl = imgui.GetWindowDrawList();
    local fill = hot and { rgb[1] * 0.28, rgb[2] * 0.22, rgb[3] * 0.16, 0.96 }
        or { rgb[1] * 0.08, rgb[2] * 0.06, rgb[3] * 0.05, 0.94 };
    local border = hot and Bright(rgb) or (quiet and Rgba(rgb, 0.34) or Rgba(rgb, 0.85));
    local text = hot and Bright(rgb) or (quiet and Rgba(rgb, 0.60) or Rgba(rgb, 1));
    _pa[1] = x; _pa[2] = y; _pb[1] = x + width; _pb[2] = y + height;
    dl:AddRectFilled(_pa, _pb, imgui.GetColorU32(fill), height * 0.5);
    dl:AddRect(_pa, _pb, imgui.GetColorU32(border), height * 0.5, nil, 1.0);
    local tw = TextWidth(label);
    local th = imgui.GetTextLineHeight();
    _pa[1] = x + (width - tw) * 0.5;
    _pa[2] = y + (height - th) * 0.5;
    dl:AddText(_pa, imgui.GetColorU32(text), label);
    return clicked;
end

local function FormatHMS(secs)
    secs = math.max(0, math.floor(secs));
    local h = math.floor(secs / 3600);
    local m = math.floor(secs / 60) % 60;
    local s = secs % 60;
    if h > 99 then
        return string.format('%d:%02d:%02d', h, m, s);
    end
    return string.format('%02d:%02d:%02d', h, m, s);
end

local toolOp = nil;

local function QueueTool(op)
    if toolOp == nil then toolOp = op; end
end

local function DrawTimeWell(id, main, frac, running, height, accent)
    local rgb = accent or { 0.80, 0.67, 0.31 };
    local lineH = imgui.GetTextLineHeight();
    local mainW = TextWidth(main);
    local colonW = frac and TextWidth(':') or 0;
    local fracW = frac and TextWidth(frac) or 0;
    local wellW = math.floor(10 + mainW + colonW + fracW + 10);
    local x, y = imgui.GetCursorScreenPos();
    imgui.InvisibleButton(id, { wellW, height });
    local dl = imgui.GetWindowDrawList();
    local pulse = 0.45;
    if running then
        pulse = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(TickMs() / 140));
    end
    local border = running and Rgba(rgb, 0.40 + 0.60 * pulse) or Rgba(rgb, 0.85);
    _pa[1] = x; _pa[2] = y; _pb[1] = x + wellW; _pb[2] = y + height;
    dl:AddRectFilled(_pa, _pb, imgui.GetColorU32({ rgb[1] * 0.10, rgb[2] * 0.08, rgb[3] * 0.06, 0.96 }), height * 0.5);
    dl:AddRect(_pa, _pb, imgui.GetColorU32(border), height * 0.5, nil, 1.0);
    local textX = x + 10;
    local textY = y + (height - lineH) * 0.5;
    _pa[1] = textX; _pa[2] = textY;
    dl:AddText(_pa, imgui.GetColorU32(Rgba(rgb, 1)), main);
    if frac then
        _pa[1] = textX + mainW; _pa[2] = textY;
        dl:AddText(_pa, imgui.GetColorU32(Rgba(rgb, 0.55)), ':');
        _pa[1] = textX + mainW + colonW; _pa[2] = textY;
        dl:AddText(_pa, imgui.GetColorU32(Rgba(rgb, 0.72)), frac);
    end
    return wellW;
end

local function ChipWidth(label, scale)
    return math.max(math.floor(36 * scale), TextWidth(label) + 14);
end

local function DrawEndChips(kind, index, count, btnH, gap, accent)
    local sq = btnH;
    if count > 1 then
        imgui.SameLine(0, gap);
        if SwChip('##vd' .. kind .. 'X' .. index, 'x', sq, btnH, true, accent) then
            QueueTool({ kind = kind, op = 'del', index = index });
        end
    end
    if index == count then
        imgui.SameLine(0, gap);
        if SwChip('##vd' .. kind .. 'Plus' .. index, '+', sq, btnH, true, accent) then
            QueueTool({ kind = kind, op = 'add' });
        end
    end
end

local function UnitFieldWidth(sample, unit)
    return math.floor(8 + TextWidth(sample) + 4 + TextWidth(unit) + 8);
end

-- Same pill as the stopwatch, with the unit drawn inside the field.
local function DrawUnitField(id, valueRef, maxv, sample, unit, height, accent)
    local rgb = accent or { 0.80, 0.67, 0.31 };
    local width = UnitFieldWidth(sample, unit);
    local padY = math.max(1, (height - imgui.GetTextLineHeight()) * 0.5);
    imgui.PushStyleColor(ImGuiCol_FrameBg, { rgb[1] * 0.10, rgb[2] * 0.08, rgb[3] * 0.06, 0.96 });
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, { rgb[1] * 0.18, rgb[2] * 0.14, rgb[3] * 0.10, 0.98 });
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, { rgb[1] * 0.24, rgb[2] * 0.18, rgb[3] * 0.12, 1.0 });
    imgui.PushStyleColor(ImGuiCol_Border, Rgba(rgb, 0.85));
    imgui.PushStyleColor(ImGuiCol_Text, Rgba(rgb, 1));
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, height * 0.5);
    imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1.0);
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 8, padY });
    imgui.SetNextItemWidth(width);
    local changed = imgui.InputInt(id, valueRef, 0, 0);
    for _ = 1, 3 do imgui.PopStyleVar(1); end
    for _ = 1, 5 do imgui.PopStyleColor(1); end
    if changed then
        local n = math.floor(tonumber(valueRef[1]) or 0);
        if n < 0 then n = 0; end
        if n > maxv then n = maxv; end
        valueRef[1] = n;
    end
    local x, y = imgui.GetItemRectMin();
    if type(x) == 'table' then y = x[2] or x.y; x = x[1] or x.x; end
    if type(x) == 'number' then
        local unitW = TextWidth(unit);
        _pa[1] = x + width - unitW - 7;
        _pa[2] = (type(y) == 'number' and y or 0) + padY;
        imgui.GetWindowDrawList():AddText(_pa, imgui.GetColorU32(Rgba(rgb, 0.62)), unit);
    end
    return width, changed == true;
end

local function DrawWatchRow(scale, index)
    local w = watches[index];
    local elapsed = WatchMs(w);
    local running = w.running == true;
    local main, frac = FormatStopwatch(elapsed);
    local lineH = imgui.GetTextLineHeight();
    local btnH = lineH + 4;
    local gap = 4;
    local actions;
    if running then
        actions = { { 'Reset', function() WatchReset(w); end }, { 'Stop', function() WatchStop(w); end } };
    elseif elapsed > 0 then
        actions = { { 'Start', function() WatchStart(w); end }, { 'Reset', function() WatchReset(w); end } };
    else
        actions = { { 'Start', function() WatchStart(w); end } };
    end
    local accent = ToolAccent(WATCH_COLORS, index);
    local btnW = ChipWidth('Start', scale);
    for i = 1, #actions do
        btnW = math.max(btnW, ChipWidth(actions[i][1], scale));
    end
    DrawTimeWell('##vdSwWell' .. index, main, frac, running, btnH, accent);
    for i = 1, #actions do
        imgui.SameLine(0, gap);
        if SwChip('##vdSw' .. index .. actions[i][1], actions[i][1], btnW, btnH, false, accent) then
            actions[i][2]();
        end
    end
    DrawEndChips('watch', index, #watches, btnH, gap, accent);
end

local function DrawCountdownRow(scale, index)
    local c = countdowns[index];
    local secs = CdSeconds(c);
    local running = c.running == true;
    -- Idle countdown is the hours/minutes fields. The clock only shows while it is running.
    local showInputs = not running;
    local accent = ToolAccent(COUNTDOWN_COLORS, index);
    local lineH = imgui.GetTextLineHeight();
    local btnH = lineH + 4;
    local gap = 4;
    local btnW = ChipWidth('Start', scale);
    btnW = math.max(btnW, ChipWidth('Reset', scale));
    btnW = math.max(btnW, ChipWidth('Stop', scale));
    if showInputs then
        local hv = T{ c.hours or 0 };
        local _, hourChanged = DrawUnitField('##vdCdH' .. index, hv, 99, '99', 'h', btnH, accent);
        if hourChanged then
            c.hours = hv[1];
            if SavePocketTools then SavePocketTools(); end
        end
        imgui.SameLine(0, gap);
        local mv = T{ c.minutes or 0 };
        local _, minChanged = DrawUnitField('##vdCdM' .. index, mv, 59, '59', 'm', btnH, accent);
        if minChanged then
            c.minutes = mv[1];
            if SavePocketTools then SavePocketTools(); end
        end
        imgui.SameLine(0, gap);
        if SwChip('##vdCdStart' .. index, 'Start', btnW, btnH, false, accent) then
            CdStart(c);
        end
    else
        local clock = FormatHMS(secs);
        DrawTimeWell('##vdCdWell' .. index, clock, nil, true, btnH, accent);
        imgui.SameLine(0, gap);
        if SwChip('##vdCdStop' .. index, 'Stop', btnW, btnH, false, accent) then CdStop(c); end
        imgui.SameLine(0, gap);
        if SwChip('##vdCdReset' .. index, 'Reset', btnW, btnH, false, accent) then CdReset(c); end
    end
    DrawEndChips('cd', index, #countdowns, btnH, gap, accent);
end

local function ApplyToolOp()
    if not toolOp then return; end
    local op = toolOp;
    toolOp = nil;
    if op.op == 'add' and op.kind == 'watch' then
        watches[#watches + 1] = NewWatch();
    elseif op.op == 'add' and op.kind == 'cd' then
        countdowns[#countdowns + 1] = NewCountdown();
    elseif op.op == 'del' and op.kind == 'watch' and #watches > 1 then
        table.remove(watches, op.index);
    elseif op.op == 'del' and op.kind == 'cd' and #countdowns > 1 then
        table.remove(countdowns, op.index);
    else
        return;
    end
    pocketForceSize = true;
    if SavePocketTools then SavePocketTools(); end
end

local function ButtonWidth(scale)
    local btnW = ChipWidth('Start', scale);
    btnW = math.max(btnW, ChipWidth('Reset', scale));
    btnW = math.max(btnW, ChipWidth('Stop', scale));
    return btnW;
end

local function WatchRowWidth(scale, index, btnH, gap)
    local entry = watches[index];
    local elapsed = WatchMs(entry);
    local actions = (entry.running == true or elapsed > 0) and 2 or 1;
    local main, frac = FormatStopwatch(elapsed);
    local width = math.floor(10 + TextWidth(main) + TextWidth(':') + TextWidth(frac) + 10);
    width = width + actions * (gap + ButtonWidth(scale));
    if #watches > 1 then width = width + gap + btnH; end
    if index == #watches then width = width + gap + btnH; end
    return width;
end

local function CountdownRowWidth(scale, index, btnH, gap)
    local c = countdowns[index];
    local running = c.running == true;
    local btnW = ButtonWidth(scale);
    local width;
    if not running then
        width = UnitFieldWidth('99', 'h') + gap + UnitFieldWidth('59', 'm') + gap + btnW;
    else
        width = math.floor(10 + TextWidth(FormatHMS(CdSeconds(c))) + 10) + 2 * (gap + btnW);
    end
    if #countdowns > 1 then width = width + gap + btnH; end
    if index == #countdowns then width = width + gap + btnH; end
    return width;
end

local function DrawPocketTools(scope, scale, font, fontSize)
    if font then scope:PushFont(font, fontSize); end
    local lineH = imgui.GetTextLineHeight();
    local btnH = lineH + 4;
    local gap = 4;
    local colGap = math.max(12, math.floor(16 * scale));
    local watchCol = 0;
    for i = 1, #watches do
        watchCol = math.max(watchCol, WatchRowWidth(scale, i, btnH, gap));
    end
    local cdCol = 0;
    for i = 1, #countdowns do
        cdCol = math.max(cdCol, CountdownRowWidth(scale, i, btnH, gap));
    end
    NoteNatural(watchCol + colGap + cdCol);
    local rowH = btnH + 4;
    local rows = math.max(#watches, #countdowns);
    local blockH = 6 + rows * (rowH + 2) + 4;
    local originX, originY = imgui.GetCursorScreenPos();
    local winX, winY = imgui.GetWindowPos();
    local winW, winH = imgui.GetWindowSize();
    if type(winW) ~= 'number' or winW < 8 then winW = 220; end
    local bottom = originY + blockH;
    if type(winY) == 'number' and type(winH) == 'number' and winH > 8 then
        bottom = winY + winH;
    end
    local dl = imgui.GetWindowDrawList();
    -- The window clip stops at the padding, which left a strip of the normal background.
    dl:PushClipRect({ winX - 2, originY }, { winX + winW + 2, bottom + 2 }, false);
    _pa[1] = winX; _pa[2] = originY;
    _pb[1] = winX + winW; _pb[2] = bottom;
    dl:AddRectFilled(_pa, _pb, imgui.GetColorU32(COL_POCKET_BG), 8 * scale, ImDrawFlags_RoundCornersBottom);
    dl:PopClipRect();
    _pa[1] = winX + 8; _pa[2] = originY; _pb[1] = winX + winW - 8; _pb[2] = originY;
    dl:AddLine(_pa, _pb, imgui.GetColorU32({ 0.80, 0.67, 0.31, 0.55 }), 1.0);

    local rowX, rowY = imgui.GetCursorScreenPos();
    for i = 1, rows do
        local startX = imgui.GetCursorPosX();
        if watches[i] then
            DrawWatchRow(scale, i);
        end
        if countdowns[i] then
            if watches[i] then
                imgui.SameLine(startX + watchCol + colGap, 0);
            else
                imgui.SetCursorPosX(startX + watchCol + colGap);
            end
            DrawCountdownRow(scale, i);
        end
    end
    local _, rowBottom = imgui.GetCursorScreenPos();
    if type(rowX) == 'number' and type(rowY) == 'number' and type(rowBottom) == 'number' and rowBottom > rowY + 4 then
        local divX = rowX + watchCol + colGap * 0.5;
        _pa[1] = divX; _pa[2] = rowY;
        _pb[1] = divX; _pb[2] = bottom - 1;
        dl:AddLine(_pa, _pb, imgui.GetColorU32({ 0.80, 0.67, 0.31, 0.45 }), 1.0);
    end

    ApplyToolOp();
end

function M.OpenKeys()
    if not pocketVisible then return openOrder; end
    local list = { 'pocket' };
    for i = 1, #openOrder do
        list[#list + 1] = openOrder[i];
    end
    return list;
end

local POP_GROUP_LABELS = {
    ['group:airships']    = 'Airships',
    ['group:boats']       = 'Boats',
    ['group:boatsall']    = 'All Boats',
    ['group:manaclipper'] = 'Manaclipper',
    ['group:barge']       = 'Barge',
    ['group:rse']         = 'RSE',
    ['group:lunar']       = 'Lunar Phases',
    ['group:guilds']      = 'Guild Shops',
};

local LUNAR_PHASE_NAMES = {
    [0]  = 'New Moon',
    [1]  = 'Waxing Crescent',
    [2]  = 'Waxing Crescent',
    [3]  = 'First Quarter',
    [4]  = 'Waxing Gibbous',
    [5]  = 'Waxing Gibbous',
    [6]  = 'Full Moon',
    [7]  = 'Waning Gibbous',
    [8]  = 'Waning Gibbous',
    [9]  = 'Last Quarter',
    [10] = 'Waning Crescent',
    [11] = 'Waning Crescent',
};

local function RouteLabel(city1, city2, city3)
    local label = city1 or '';
    if city2 and city2 ~= '' then label = label .. ' > ' .. city2; end
    if city3 and city3 ~= '' then label = label .. ' > ' .. city3; end
    if label == '' then return nil; end
    return label;
end

function M.Label(key)
    if key == 'pocket' then return 'Pocket'; end
    local grouped = POP_GROUP_LABELS[key];
    if grouped then return grouped; end
    local airIndex = key:match('^air:(%d+)$');
    if airIndex then
        local row = timers.airships[tonumber(airIndex)];
        local label = row and (RouteLabel(row.city1, row.city2) or row.label);
        return label or ('Airship ' .. airIndex);
    end
    if key:sub(1, 5) == 'boat:' then
        local c1, rest = key:sub(6):match('^([^>]*)>(.*)$');
        local c2, rest2 = rest and rest:match('^([^>]*)>(.*)$');
        local c3 = rest2 and rest2:match('^([^>]*)');
        return RouteLabel(c1, c2, c3) or 'Boat';
    end
    local rseIndex = key:match('^rse:(%d+)$');
    if rseIndex then
        local row = timers.rse[tonumber(rseIndex)];
        if row and row.slotName and row.slotName ~= '' then
            if row.location and row.location ~= '' then
                return row.slotName .. ' @ ' .. row.location;
            end
            return row.slotName;
        end
        return 'RSE ' .. rseIndex;
    end
    local phaseIdx = tonumber(key:match('^lunar:(%d+)$'));
    if phaseIdx then
        local row = FindLunar(phaseIdx);
        local name = (row and row.phaseName ~= '' and row.phaseName) or LUNAR_PHASE_NAMES[phaseIdx];
        if name then
            if row and row.dateStr and row.dateStr ~= '' then
                return name .. '  ' .. row.dateStr;
            end
            return name;
        end
        return 'Lunar ' .. phaseIdx;
    end
    local guildId, place = key:match('^guild:([^:]+):(.+)$');
    if not guildId then guildId = key:match('^guild:(.+)$'); end
    if guildId then
        local name = guildId:gsub('^%l', string.upper);
        if place and place ~= '' then return name .. ' - ' .. place; end
        return name;
    end
    return key;
end

local function ClampScale(value, fallback)
    local s = tonumber(value);
    if not s then s = fallback; end
    if s < 0.5 then return 0.5; end
    if s > 4.0 then return 4.0; end
    return s;
end

local function WindowScale(cfg, key)
    local scales = cfg.popoutScales;
    local custom = scales and tonumber(scales[key]);
    if custom then return ClampScale(custom, 1.0); end
    return ClampScale(cfg.vanaTimeScale, 1.0);
end

local function DefaultPos(key)
    local h = 0;
    for i = 1, #key do
        h = (h * 33 + key:byte(i)) % 997;
    end
    return 500 + (h % 5) * 28, 120 + (h % 7) * 36;
end

local function DrawOne(key)
    local cfg = gConfig;
    if not cfg then return false; end

    local scale = WindowScale(cfg, key);
    local baseFont = math.max(8, math.min(48, tonumber(cfg.vanaTimeTimersFontSize) or 12));
    local fontSize = math.floor(baseFont * scale);
    local isGuildCard = key:sub(1, 6) == 'guild:';

    local closed = false;
    local ok, err = Safe.Run(function(scope)
        scope:PushStyleVar(ImGuiStyleVar_WindowRounding, (isGuildCard and 16 or 8) * scale);
        scope:PushStyleVar(ImGuiStyleVar_WindowPadding, {
            math.floor((isGuildCard and 12 or 10) * scale),
            math.floor((isGuildCard and 10 or 6) * scale),
        });
        scope:PushStyleVar(ImGuiStyleVar_ItemSpacing, { math.floor(6 * scale), math.max(2, math.floor(3 * scale)) });
        if not isGuildCard then
            scope:PushStyleVar(ImGuiStyleVar_WindowMinSize, { math.floor(120 * scale), 0 });
        end
        scope:PushStyleColor(ImGuiCol_WindowBg, COL_WINDOW_BG);
        scope:PushStyleColor(ImGuiCol_Border, COL_BORDER);

        local posKey = PosKey(key);
        local applied = ApplyWindowPosition(posKey);
        if not applied and needsDefault[key] then
            local x, y = DefaultPos(key);
            imgui.SetNextWindowPos({x, y}, ImGuiCond_Always);
        end
        needsDefault[key] = nil;

        local font = imtext.GetFont();
        if font then
            scope:PushFont(font, fontSize);
        end

        local flags = WIN_FLAGS;
        local visible = scope:BeginWindow("Vana'Dial Pop##" .. key, true, flags);
        if visible then
            SaveWindowPosition(posKey);
            closed = DrawBody(scope, key);
        end
    end);
    if not ok then error(err); end
    return closed;
end

local function DrawPocket()
    local cfg = gConfig;
    if not cfg then return false, {}; end

    local scale = WindowScale(cfg, 'pocket');
    local baseFont = math.max(8, math.min(48, tonumber(cfg.vanaTimeTimersFontSize) or 12));
    local fontSize = math.floor(baseFont * scale);
    local hide = false;
    local removed = {};

    local ok, err = Safe.Run(function(scope)
        scope:PushStyleVar(ImGuiStyleVar_WindowRounding, 8 * scale);
        -- No bottom padding. The timer band paints to the border; a top dummy keeps the header inset.
        scope:PushStyleVar(ImGuiStyleVar_WindowPadding, {
            math.floor(8 * scale),
            0,
        });
        scope:PushStyleVar(ImGuiStyleVar_ItemSpacing, { math.floor(6 * scale), math.max(2, math.floor(3 * scale)) });
        scope:PushStyleVar(ImGuiStyleVar_WindowMinSize, { math.floor(140 * scale), 0 });
        scope:PushStyleColor(ImGuiCol_WindowBg, COL_WINDOW_BG);
        scope:PushStyleColor(ImGuiCol_Border, COL_BORDER);

        pocketItemRight = 0;
        pocketNaturalW = 0;
        local width = pocketContentW > 0 and pocketContentW or math.floor(220 * scale);
        local height = pocketLaidOutH > 0 and pocketLaidOutH or math.floor(64 * scale);
        imgui.SetNextWindowSizeConstraints({ math.floor(80 * scale), 0 }, { 2800, 2000 });
        if not imgui.IsMouseDragging(0) then
            imgui.SetNextWindowSize({ width, height }, ImGuiCond_Always);
        end

        local posKey = PosKey('pocket');
        local hadSaved = gConfig.windowPositions and gConfig.windowPositions[posKey] ~= nil;
        local placeDefault = (not hadSaved) and needsDefault['pocket'] == true;
        ApplyWindowPosition(posKey);
        if placeDefault then
            local x, y = DefaultPos('pocket');
            imgui.SetNextWindowPos({x, y}, ImGuiCond_Always);
        end
        needsDefault['pocket'] = nil;

        local font = imtext.GetFont();
        if font then
            scope:PushFont(font, fontSize);
        end

        local visible = scope:BeginWindow("Vana'Dial Pocket##vd", true, POCKET_FLAGS);
        if not visible then return; end
        if hadSaved or placeDefault then
            SaveWindowPosition(posKey);
            NotePocketPosition();
        end

        imgui.Dummy({ 1, math.floor(6 * scale) });
        local size = CloseSize();
        local titleW = imgui.CalcTextSize('Pocket');
        if type(titleW) == 'table' then titleW = titleW[1] or titleW.x; end
        if type(titleW) ~= 'number' then titleW = 48; end
        NoteNatural(titleW + 8 + size * 2 + 2);
        imgui.TextColored(COL_GOLD, 'Pocket');
        imgui.SameLine(0, 8);
        AlignRight(size * 2 + 2);
        GearButton('pocket', 'pocket');
        imgui.SameLine(0, 2);
        if CloseButton('pocket_win', size, 'Close') then
            hide = true;
        end
        -- The header buttons sit on the window's right edge, so they are not content.
        pocketItemRight = 0;

        if pocketOrder[1] ~= nil then
            DrawDivider(scope);
            for i, key in ipairs(pocketOrder) do
                if i > 1 then DrawDivider(scope); end
                if DrawPocketEntry(scope, key) then
                    removed[#removed + 1] = key;
                end
                NoteItemRight();
            end
        end

        imgui.Dummy({ 1, math.max(3, math.floor(4 * scale)) });
        local toolFont = math.max(8, math.floor(fontSize * 0.85));
        DrawPocketTools(scope, scale, font, toolFont);

        local winX = imgui.GetWindowPos();
        if type(winX) == 'table' then winX = winX[1] or winX.x; end
        local pad = math.floor(8 * scale);
        local fromItems = 0;
        if type(winX) == 'number' and pocketItemRight > winX + pad then
            fromItems = pocketItemRight - winX - pad;
        end
        local content = math.max(fromItems, pocketNaturalW);
        pocketContentW = math.ceil(content + pad * 2);
        -- Cursor sits one item-spacing below the last control. Keep only a small inset.
        local spacingY = math.max(2, math.floor(3 * scale));
        local bottomPad = math.max(3, math.floor(4 * scale));
        pocketLaidOutH = math.max(bottomPad, imgui.GetCursorPosY() - spacingY + bottomPad);
    end);
    if not ok then error(err); end
    return hide, removed;
end

function M.Draw()
    if not gConfig or (openOrder[1] == nil and not pocketVisible) then return; end
    if refreshFn then refreshFn(); end
    imtext.SetConfig('Tahoma', gConfig.vanaTimeFontBold ~= false, 1);

    local pendingClose = {};
    local count = #openOrder;
    for i = 1, count do
        local key = openOrder[i];
        if key and DrawOne(key) then
            pendingClose[#pendingClose + 1] = key;
        end
    end
    for _, key in ipairs(pendingClose) do
        SetOpen(key, false);
    end

    if pocketVisible then
        local hide, removed = DrawPocket();
        for _, key in ipairs(removed or {}) do
            PocketRemove(key);
        end
        if hide then
            PocketHide();
        end
    end
end

local function DrawPocketGlyph(x, y, size, hot, active)
    local dl = imgui.GetWindowDrawList();
    local col = (hot or active) and COL_PIN_HOT or COL_PIN_IDLE;
    local u = imgui.GetColorU32(col);
    if active then
        _pa[1] = x + 1; _pa[2] = y + 1; _pb[1] = x + size - 1; _pb[2] = y + size - 1;
        dl:AddRectFilled(_pa, _pb, imgui.GetColorU32(COL_PIN_FILL), 2);
    end
    local m = math.max(2, math.floor(size * 0.16));
    _pa[1] = x + m; _pa[2] = y + size * 0.34;
    _pb[1] = x + size - m; _pb[2] = y + size - m;
    dl:AddRect(_pa, _pb, u, 2, nil, 1.1);
    _pa[1] = x + m; _pa[2] = y + size * 0.46;
    _pb[1] = x + size - m; _pb[2] = y + size * 0.46;
    dl:AddLine(_pa, _pb, u, 1.1);
end

-- Pocket glyph, then the pin, at the right edge of a timer-panel row.
function M.PinButton(id, key)
    local size = CloseSize();
    local gap = 2;
    imgui.SameLine(0, 6);
    AlignRight(size * 2 + gap);

    local px, py = imgui.GetCursorScreenPos();
    local pocketClicked = imgui.InvisibleButton('##vdPocket_' .. tostring(id), {size, size});
    local pocketHovered = imgui.IsItemHovered();
    local inPocket = pocketSet[key] == true;
    DrawPocketGlyph(px, py, size, pocketHovered, inPocket);
    if pocketHovered then
        local tip = 'Add to pocket';
        if inPocket and pocketVisible then
            tip = 'Remove from pocket';
        elseif inPocket then
            tip = 'Show pocket';
        end
        imgui.SetTooltip(tip);
    end
    if pocketClicked then
        M.PocketClick(key);
    end

    imgui.SameLine(0, gap);
    local x, y = imgui.GetCursorScreenPos();
    local clicked = imgui.InvisibleButton('##vdPin_' .. tostring(id), {size, size});
    local hovered = imgui.IsItemHovered();
    local active = openSet[key] == true;
    local col = (hovered or active) and COL_PIN_HOT or COL_PIN_IDLE;
    local dl = imgui.GetWindowDrawList();
    if active then
        _pa[1] = x; _pa[2] = y; _pb[1] = x + size; _pb[2] = y + size;
        dl:AddRectFilled(_pa, _pb, imgui.GetColorU32(COL_PIN_FILL), 2);
    end
    local u = imgui.GetColorU32(col);
    local boxL, boxT = x + 1, y + 4;
    local boxR, boxB = x + size - 6, y + size - 1;
    _pa[1] = boxL; _pa[2] = boxT; _pb[1] = boxR; _pb[2] = boxB;
    dl:AddRect(_pa, _pb, u, 1.5, nil, 1.0);
    local ax, ay = x + size - 2, y + 2;
    _pa[1] = x + size * 0.40; _pa[2] = y + size * 0.58; _pb[1] = ax; _pb[2] = ay;
    dl:AddLine(_pa, _pb, u, 1.15);
    _pa[1] = ax - 4; _pa[2] = ay; _pb[1] = ax; _pb[2] = ay;
    dl:AddLine(_pa, _pb, u, 1.15);
    _pa[1] = ax; _pa[2] = ay; _pb[1] = ax; _pb[2] = ay + 4;
    dl:AddLine(_pa, _pb, u, 1.15);
    if hovered then
        imgui.SetTooltip(active and 'Close pop out' or 'Pop out');
    end
    if clicked then
        M.Toggle(key);
    end
end

return M;
