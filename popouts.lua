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

local M = {};

local WIN_FLAGS = bit.bor(
    ImGuiWindowFlags_NoDecoration,
    ImGuiWindowFlags_AlwaysAutoResize,
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
    return openOrder[1] ~= nil;
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
end

function M.RestoreSaved()
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
end

function M.ToggleCommand(name)
    name = name and name:lower() or '';
    if name == 'close' or name == 'off' or name == 'hide' or name == 'none' then
        local any = openOrder[1] ~= nil;
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
end

-- ── Row chrome (mirrors the timer panel, without the pin) ────────────────────

local function CloseSize()
    return math.max(12, math.floor(imgui.GetTextLineHeight()));
end

local function DrawPill(id, text, color)
    text = text or '--';
    color = color or timers.colorDimGrey;
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
    dl:AddRect(_pa, _pb, imgui.GetColorU32(color), rounding, nil, 1.0);
    _pa[1] = x + (pillW - textW) * 0.5;
    _pa[2] = y + (pillH - textH) * 0.5;
    dl:AddText(_pa, imgui.GetColorU32(color), text);
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
    if row.isAwaiting then return 'AWAITING', timers.colorAwaiting; end
    if row.isBoarding then return 'BOARDING', timers.colorBoarding; end
    if row.isDocking then return 'DOCKING', timers.colorDocking; end
    if row.isTransit then return 'IN-TRANSIT', timers.colorGoldDark; end
    return nil, nil;
end

local function AlignRight(width)
    local avail = imgui.GetContentRegionAvail();
    if type(avail) == 'number' and avail > width then
        imgui.SetCursorPosX(imgui.GetCursorPosX() + (avail - width));
    end
end

local function CloseButton(id, size)
    local x, y = imgui.GetCursorScreenPos();
    local clicked = imgui.InvisibleButton('##vdPopX_' .. id, {size, size});
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
        imgui.SetTooltip('Close');
    end
    return clicked;
end

local function PlaceClose(id)
    local size = CloseSize();
    imgui.SameLine(0, 8);
    AlignRight(size);
    return CloseButton(id, size);
end

local function DrawRouteLine(row, id, withClose)
    local cdColor = (row.isEmpty or not row.cdColor) and timers.colorDimGrey or row.cdColor;
    DrawPill(id, row.countdownStr, cdColor);
    imgui.SameLine(0, 8);
    DrawCities(row);
    local status, statusCol = StatusOf(row);
    if status then
        imgui.SameLine(0, 8);
        imgui.TextColored(statusCol, status);
    end
    if withClose then
        return PlaceClose(id);
    end
    return false;
end

local function DrawDivider(scope)
    local mark = scope:Mark();
    scope:PushStyleColor(ImGuiCol_Separator, COL_SEPARATOR);
    imgui.Separator();
    scope:CloseTo(mark);
end

local function DrawAirshipBlock(scope, row, index, withClose)
    local closed = DrawRouteLine(row, 'pair_' .. index, withClose);
    if row.sub and (row.sub.city1 or row.sub.label) then
        local mark = scope:Mark();
        scope:Indent(16);
        DrawRouteLine(row.sub, 'pair_sub_' .. index, false);
        scope:CloseTo(mark);
    end
    return closed;
end

local function DrawRseLine(e, id, withClose)
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
        return PlaceClose(id);
    end
    return false;
end

local function LunarNameColor(e)
    if e.phaseIdx == 0 then return COL_NEW_MOON; end
    if e.phaseIdx == 6 then return COL_FULL_MOON; end
    if e.isCurrent then return timers.colorGoldDark; end
    return timers.colorGoldMuted;
end

local function DrawLunarLine(e, id, withClose)
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
        return PlaceClose(id);
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

local function DrawGuildLocation(e, hol, id, center, reserve)
    local muted = hol.onHoliday == true;
    local nameColor = muted and timers.colorDimGrey or (e.nameColor or timers.colorGold);
    local placeColor = muted and timers.colorDimGrey or (hol.placeColor or nameColor);
    local label = e.shortName or e.name or '';
    if center then
        local avail = imgui.GetContentRegionAvail();
        local groupW = GuildLineWidth(e, hol);
        if type(avail) ~= 'number' then avail = groupW + (reserve or 0); end
        local inner = math.max(groupW, avail - (reserve or 0));
        local shift = (inner - groupW) * 0.5;
        if shift > 0 then
            imgui.SetCursorPosX(imgui.GetCursorPosX() + shift);
        end
    end
    imgui.TextColored(nameColor, label);
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

local function DrawGuildLine(scope, e, id, withClose, onlyIndex)
    local closed = false;
    local count = e.holidayCount or 0;
    local closeSize = withClose and CloseSize() or 0;
    local placedClose = false;
    for h = 1, count do
        if not onlyIndex or h == onlyIndex then
            local reserve = 0;
            if withClose and not placedClose then
                local avail = imgui.GetContentRegionAvail();
                if type(avail) ~= 'number' then avail = closeSize; end
                local cursorX = imgui.GetCursorPosX();
                local cursorY = imgui.GetCursorPosY();
                local sx, sy = imgui.GetCursorScreenPos();
                imgui.SetCursorScreenPos({sx + math.max(0, avail - closeSize), sy});
                closed = CloseButton('card_' .. id, closeSize);
                imgui.SetCursorPos({cursorX, cursorY});
                reserve = closeSize + 8;
                placedClose = true;
            end
            DrawGuildLocation(e, e.holidays[h], id .. '_' .. h, true, reserve);
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

    local scale = math.max(0.5, math.min(4.0, tonumber(cfg.vanaTimeScale) or 1.0));
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

function M.Draw()
    if not gConfig or openOrder[1] == nil then return; end
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
end

-- Pin drawn at the right edge of a timer-panel row.
function M.PinButton(id, key)
    local size = CloseSize();
    imgui.SameLine(0, 8);
    AlignRight(size);
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
