--[[
* Vana'Dial main window renderer.
*
* Layout (when all options enabled):
*
*   ┌─ Vana'Dial ─────────────────────────────────────────────┐
*   │  VT: 18:32                       LT: 01:53 AM           │
*   │ ┌──────────┐ ▶ ┌────────────────┐ ▶ ┌──────────┐       │
*   │ │ [Fire]   │   │   [Earth]      │   │  [Wind]  │       │
*   │ │  65% ↑   │   │    72% ↑       │   │  73% ↑   │       │
*   │ │[↓][weak] │   │  [↓][weak]     │   │[↓][weak] │       │
*   │ └──────────┘   └────────────────┘   └──────────┘       │
*   └─────────────────────────────────────────────────────────┘
*
* Minimalist mode collapses that to one row, with its own scale:
*   07:49  (day) 57%  >  (day) 60%      [weather]
]]--

require('common');
local bit    = require('bit');
local imgui    = require('imgui');
local imtext   = require('libs.imtext');
local colorLib = require('libs.color');

local TextureManager = require('libs.texturemanager');
local windowbg       = require('libs.windowbackground');
local Safe           = require('libs.imgui_safe');
local timers         = require('timers');
local data           = require('data');
local popups         = require('popups');

local M = {};

-- ── Constants ─────────────────────────────────────────────────────────────────

local WEATHER_POPUP_GAP = 4;
local PAST_FUTURE_ALPHA = 0.18;
local BADGE_SCALE       = 0.40;
local VT_TEXT_COLOR     = 0xFFC3AE79; -- XIUI Gold Dark — fixed for VT clock text
local ARROW_SCALE       = 0.55;
local COL_ARROW         = '>';

-- ── Textures ──────────────────────────────────────────────────────────────────

local textures          = {};
local moonPhaseTextures = {};
local todTextures       = { day=nil, night=nil, deadOfNight=nil };
local arrowRightTex     = nil;
local moonUpTex         = nil;
local moonDownTex       = nil;
local clockIconTex      = nil;
local gearIconTex       = nil;
local nextTextureRetryMs = 0;

local function TexturesReady()
    if not arrowRightTex or not moonUpTex or not moonDownTex
        or not clockIconTex or not gearIconTex
        or not todTextures.day or not todTextures.night or not todTextures.deadOfNight then
        return false;
    end
    for i = 0, 11 do
        if not textures[i] or not moonPhaseTextures[i] then return false; end
    end
    return true;
end

local function LoadTextures()
    for i = 0, 11 do
        local name = data.ELEMENT_NAMES[i];
        if name and not textures[i] then
            textures[i] = TextureManager.getFileTexture('VanaDial/elements/' .. name);
        end
    end
    for i = 0, 11 do
        if not moonPhaseTextures[i] then
            moonPhaseTextures[i] = TextureManager.getFileTexture('VanaDial/moon/phase_' .. i);
        end
    end
    if not arrowRightTex     then arrowRightTex     = TextureManager.getFileTexture('VanaDial/arrow_right');          end
    if not moonUpTex         then moonUpTex         = TextureManager.getFileTexture('VanaDial/moon_up');              end
    if not moonDownTex       then moonDownTex       = TextureManager.getFileTexture('VanaDial/moon_down');            end
    if not clockIconTex      then clockIconTex      = TextureManager.getFileTexture('VanaDial/clock_icon');           end
    if not gearIconTex       then gearIconTex       = TextureManager.getFileTexture('icons/gear');                    end
    if not todTextures.day   then todTextures.day   = TextureManager.getFileTexture('VanaDial/tod/tod_day');          end
    if not todTextures.night then todTextures.night = TextureManager.getFileTexture('VanaDial/tod/tod_night');        end
    if not todTextures.deadOfNight then
        todTextures.deadOfNight = TextureManager.getFileTexture('VanaDial/tod/tod_deadofnight');
    end
end

local function GetTexPtr(tex)
    if tex == nil then return nil; end
    return TextureManager.getTexturePtr(tex);
end

-- ── Color helpers ─────────────────────────────────────────────────────────────

local function ArgbR(c) return bit.band(bit.rshift(c, 16), 0xFF) / 255.0; end
local function ArgbG(c) return bit.band(bit.rshift(c,  8), 0xFF) / 255.0; end
local function ArgbB(c) return bit.band(c,                0xFF) / 255.0; end
local function ArgbA(c) return bit.band(bit.rshift(c, 24), 0xFF) / 255.0; end

-- Allocation-free ARGB→packed-U32 (ABGR). Avoids the {r,g,b,a} table that
-- imgui.GetColorU32(ARGBToImGui(...)) allocates on every call — this runs
-- dozens of times per frame in the draw path.
local function ToU32(argb)
    return ARGBToABGR(argb);
end

local function WithAlpha(argb, alpha)
    local a = math.floor(alpha * 255);
    return bit.bor(bit.lshift(a, 24), bit.band(argb, 0x00FFFFFF));
end

-- Background tint stores alpha in the color picker's A channel; General → Background
-- Opacity multiplies it. Previously only the slider was applied and A was discarded.
local function ResolveBackgroundOpacity(cfg, bgArgb)
    local argb = tonumber(bgArgb) or 0xFF000000;
    local fromColor = bit.band(bit.rshift(argb, 24), 0xFF) / 255.0;
    local fromSlider = tonumber(cfg.vanaTimeBackgroundOpacity);
    if fromSlider == nil then fromSlider = 0.85; end
    return math.max(0, math.min(1, fromColor * fromSlider));
end

local function LerpArgb(c1, c2, t)
    local a1 = bit.band(bit.rshift(c1, 24), 0xFF);
    local r1 = bit.band(bit.rshift(c1, 16), 0xFF);
    local g1 = bit.band(bit.rshift(c1,  8), 0xFF);
    local b1 = bit.band(c1, 0xFF);
    local a2 = bit.band(bit.rshift(c2, 24), 0xFF);
    local r2 = bit.band(bit.rshift(c2, 16), 0xFF);
    local g2 = bit.band(bit.rshift(c2,  8), 0xFF);
    local b2 = bit.band(c2, 0xFF);
    local a = math.floor(a1 + (a2 - a1) * t + 0.5);
    local r = math.floor(r1 + (r2 - r1) * t + 0.5);
    local g = math.floor(g1 + (g2 - g1) * t + 0.5);
    local b = math.floor(b1 + (b2 - b1) * t + 0.5);
    return bit.bor(bit.lshift(a, 24), bit.lshift(r, 16), bit.lshift(g, 8), b);
end

-- RGB lerp passes through unintended hues (e.g. fire orange → moon red → green).
local function LerpArgbHsv(c1, c2, t)
    t = math.max(0, math.min(1, t));
    local a1 = bit.band(bit.rshift(c1, 24), 0xFF);
    local r1 = bit.band(bit.rshift(c1, 16), 0xFF);
    local g1 = bit.band(bit.rshift(c1,  8), 0xFF);
    local b1 = bit.band(c1, 0xFF);
    local a2 = bit.band(bit.rshift(c2, 24), 0xFF);
    local r2 = bit.band(bit.rshift(c2, 16), 0xFF);
    local g2 = bit.band(bit.rshift(c2,  8), 0xFF);
    local b2 = bit.band(c2, 0xFF);
    local h1, s1, v1 = colorLib.rgbToHsv(r1 / 255, g1 / 255, b1 / 255);
    local h2, s2, v2 = colorLib.rgbToHsv(r2 / 255, g2 / 255, b2 / 255);
    local dh = h2 - h1;
    if dh > 0.5 then
        dh = dh - 1;
    elseif dh < -0.5 then
        dh = dh + 1;
    end
    local h = h1 + dh * t;
    if h < 0 then
        h = h + 1;
    elseif h >= 1 then
        h = h - 1;
    end
    local s = s1 + (s2 - s1) * t;
    local v = v1 + (v2 - v1) * t;
    local r, g, b = colorLib.hsvToRgb(h, s, v);
    r = math.floor(r * 255 + 0.5);
    g = math.floor(g * 255 + 0.5);
    b = math.floor(b * 255 + 0.5);
    local a = math.floor(a1 + (a2 - a1) * t + 0.5);
    return bit.bor(bit.lshift(a, 24), bit.lshift(r, 16), bit.lshift(g, 8), b);
end

local function GetOutlineColor(weekday)
    return 0xFF000000;
end

-- ── Per-frame allocation sinks ────────────────────────────────────────────────

local _textPos        = {0, 0};
local _moonPctMeasW   = 0;
local _moonPctFontSz  = -1;
local _mainWindowParked = false;

-- Reusable scratch tables for drawlist calls. ImGui consumes the point tables
-- synchronously within each call, so sharing two scratch points (plus constant
-- UVs) across all draws is safe and eliminates per-call {x,y} allocations.
local UV0 = {0, 0};
local UV1 = {1, 1};
local _pa = {0, 0};
local _pb = {0, 0};

local function DLRectFilled(dl, x1, y1, x2, y2, col, rounding)
    _pa[1] = x1; _pa[2] = y1; _pb[1] = x2; _pb[2] = y2;
    dl:AddRectFilled(_pa, _pb, col, rounding);
end

local function DLRect(dl, x1, y1, x2, y2, col, rounding, flags, thickness)
    _pa[1] = x1; _pa[2] = y1; _pb[1] = x2; _pb[2] = y2;
    dl:AddRect(_pa, _pb, col, rounding, flags, thickness);
end

local function DLImage(dl, tex, x1, y1, x2, y2, col)
    _pa[1] = x1; _pa[2] = y1; _pb[1] = x2; _pb[2] = y2;
    dl:AddImage(tex, _pa, _pb, UV0, UV1, col);
end

local function DLRectMultiColor(dl, x1, y1, x2, y2, c1, c2, c3, c4)
    _pa[1] = x1; _pa[2] = y1; _pb[1] = x2; _pb[2] = y2;
    dl:AddRectFilledMultiColor(_pa, _pb, c1, c2, c3, c4);
end

local function DLLine(dl, x1, y1, x2, y2, col, thickness)
    _pa[1] = x1; _pa[2] = y1; _pb[1] = x2; _pb[2] = y2;
    dl:AddLine(_pa, _pb, col, thickness);
end

local function DLCircleFilled(dl, x, y, radius, col, segments)
    _pa[1] = x; _pa[2] = y;
    dl:AddCircleFilled(_pa, radius, col, segments);
end

-- ── Frame caches ──────────────────────────────────────────────────────────────

local vtCache    = { hour=-1, min=-1, str='', measW=0 };
local ltCache    = { osMin=-1, osHour=-1, str='', measW=0 };
local lastOsTime   = -1;
local lastFontSize = -1;
local lastVtFontSize = -1;

-- Full bright/dim cycle for new/full moon % text (and weather-test preview pulse).
local MOON_PULSE_PERIOD = 2.8;

local function NowSeconds()
    local ms = data.GetTickMs and data.GetTickMs() or nil;
    return ms and (ms / 1000) or os.clock();
end

local function GetMoonPulse(now)
    now = now or NowSeconds();
    local raw = (math.sin(now * (2 * math.pi / MOON_PULSE_PERIOD)) + 1) * 0.5;
    return math.floor(raw * 24 + 0.5) / 24;
end

-- ── Main window state ─────────────────────────────────────────────────────────

local mainWinPos  = {x=0, y=0};
local mainWinSize = {w=0, h=0};

-- Deferred day-column tooltip: set during Begin/End, drawn after End() on foreground list
local pendingDayTooltip = nil;
-- Click a day column to open today-forward week, matching the site's All days.
local weekOpen = false;

-- Preview flags: set by config/vanatime.lua while sliders are dragged
if _G.XIUI_weatherElementalPreview == nil then _G.XIUI_weatherElementalPreview = false; end
if _G.XIUI_weatherBasePreview      == nil then _G.XIUI_weatherBasePreview      = false; end
if _G.XIUI_weatherTestExpiry       == nil then _G.XIUI_weatherTestExpiry       = 0;     end

-- ── Draw helpers ──────────────────────────────────────────────────────────────

local function DrawTextWithOutline(drawList, text, x, y, textArgb, outlineArgb, fontSize)
    local font    = imtext.GetFont();
    local ow      = 1;
    local textU32 = ToU32(textArgb);
    local outU32  = ToU32(outlineArgb);
    local fs = fontSize and (fontSize + 2) or nil;
    _textPos[1] = x + ow; _textPos[2] = y + ow;
    if fs and font then
        drawList:AddText(font, fs, _textPos, outU32, text);
    else
        drawList:AddText(_textPos, outU32, text);
    end
    _textPos[1] = x; _textPos[2] = y;
    if fs and font then
        drawList:AddText(font, fs, _textPos, textU32, text);
    else
        drawList:AddText(_textPos, textU32, text);
    end
end

-- colU32 is already a packed drawlist color (callers pass ToU32(...)).
local function DrawPill(drawList, x, y, w, h, colU32, rounding)
    local r = rounding or 4;
    DLRectFilled(drawList, x, y, x + w, y + h, colU32, r);
end

-- Draw a single day column: icon + moon% + weakness badge
local function FormatLocalTime(unix)
    local lt = os.date('*t', unix);
    if not lt then return ''; end
    local h = lt.hour;
    local ampm = (h >= 12) and 'PM' or 'AM';
    local h12 = h % 12;
    if h12 == 0 then h12 = 12; end
    return string.format('%d:%02d %s', h12, lt.min, ampm);
end

local function FormatLocalClock(unix)
    local lt = os.date('*t', unix);
    if not lt then return ''; end
    return os.date('%a', unix) .. ' ' .. FormatLocalTime(unix);
end

local function FormatLead(secs)
    secs = math.max(0, math.floor(secs));
    local h = math.floor(secs / 3600);
    local m = math.floor((secs % 3600) / 60);
    local s = secs % 60;
    if h > 0 then return string.format('%dh %dm', h, m); end
    if m > 0 then return string.format('%dm %02ds', m, s); end
    return string.format('%ds', s);
end

local function DrawDayColumn(drawList, cx, cy, colWeekday, moonPercent, moonDay, alpha, iconSize, fontSize, colorConfig, showMoon, showBadge, disableIcons, timeLabel, scale)
    scale = scale or 1;
    local function S(n) return math.max(1, math.floor(n * scale)); end
    local badgeSize = math.floor(iconSize * BADGE_SCALE);

    local elemArgb = colorConfig[data.ELEM_KEYS[colWeekday]] or 0xFFFFFFFF;

    local moonPctW = (fontSize == _moonPctFontSz) and _moonPctMeasW or imtext.Measure('100%', fontSize);
    local moonArrowSlot = showMoon and (math.floor(fontSize * 0.7) + S(2)) or 0;
    local phaseIconSlot = showMoon and (math.floor(fontSize + S(2)) + S(2)) or 0;
    local moonMaxW      = showMoon and (phaseIconSlot + moonPctW + moonArrowSlot) or 0;
    local colContentW   = math.max(iconSize, moonMaxW + S(4));
    if timeLabel and timeLabel ~= '' then
        local tw = imtext.Measure(timeLabel, fontSize);
        if tw > colContentW then colContentW = tw; end
    end

    local iconY  = cy;
    local moonY  = iconY + iconSize + S(2);

    local timeExtra = (timeLabel and timeLabel ~= '') and (fontSize + S(4)) or 0;
    local colH = (showMoon
        and (iconSize + S(2) + fontSize + S(4))
        or  (iconSize + S(4))) + timeExtra;

    -- Column card: dark background + element-colored border
    local cardPad = S(4);
    local cardX   = cx - cardPad;
    local cardY   = cy - cardPad;
    local cardW   = colContentW + cardPad * 2;
    local cardH   = colH + cardPad * 2;
    DLRectFilled(drawList, cardX, cardY, cardX + cardW, cardY + cardH,
        ToU32(WithAlpha(0xFF050510, 0.70 * alpha)), S(6));
    DLRect(drawList, cardX, cardY, cardX + cardW, cardY + cardH,
        ToU32(WithAlpha(elemArgb, alpha)), S(6), nil, alpha >= 0.95 and 1.5 or 1.0);

    local iconX = cx + math.floor((colContentW - iconSize) / 2);

    if disableIcons then
        DLRectFilled(drawList, iconX, iconY, iconX + iconSize, iconY + iconSize,
            ToU32(WithAlpha(elemArgb, alpha * 0.85)), 3);
    else
        DLRectFilled(drawList, iconX, iconY, iconX + iconSize, iconY + iconSize,
            ToU32(WithAlpha(0xFF000000, alpha)), 3);
    end

    if not disableIcons then
        local iconTex = GetTexPtr(textures[colWeekday]);
        if iconTex then
            local tint = ToU32(WithAlpha(0xFFFFFFFF, alpha));
            DLImage(drawList, iconTex, iconX, iconY, iconX + iconSize, iconY + iconSize, tint);
        end
    end

    local iconBorderArgb = data.LIGHT_GROUP[colWeekday] and 0xFFF4DA97 or 0xFF6A0DAD;
    DLRect(drawList, iconX - 1, iconY - 1, iconX + iconSize + 1, iconY + iconSize + 1,
        ToU32(WithAlpha(iconBorderArgb, alpha * 0.85)), 4, nil, 1.0);

    if showMoon then
        local moonStr     = string.format('%d%%', moonPercent);
        local outlineArgb = WithAlpha(GetOutlineColor(colWeekday), alpha);
        local textArgb    = WithAlpha(elemArgb, alpha);
        local moonW, _    = imtext.Measure(moonStr, fontSize);

        local phaseIconSize = math.floor(fontSize + S(2));
        local phaseTex = GetTexPtr(moonPhaseTextures[data.GetMoonPhaseRaw(moonDay)]);

        local moonArrowSize = math.floor(fontSize * 0.7);
        local moonArrowTex  = nil;
        if moonDay > 0 and moonDay < 42 then
            moonArrowTex = GetTexPtr(moonUpTex);
        elseif moonDay > 42 then
            moonArrowTex = GetTexPtr(moonDownTex);
        end
        local arrowGap  = moonArrowTex and S(2) or 0;
        local phaseGap  = phaseTex and (phaseIconSize + S(2)) or 0;

        -- Center the entire group (phase icon + text + optional arrow) as a unit.
        -- Using only moonW would misplace the group whenever the arrow is absent (0% / 100%).
        local totalMoonRowW = phaseGap + moonW + (moonArrowTex and (moonArrowSize + arrowGap) or 0);
        local groupLeft     = cx + math.floor((colContentW - totalMoonRowW) / 2);
        local moonTextX     = groupLeft + phaseGap;

        local moonRowH  = fontSize + S(4);
        local moonBaseY = moonY + math.floor((moonRowH - fontSize) / 2);

        -- Moon pill border for New Moon (blood red) and Full Moon (moonlit blue)
        local isNewMoonPhase  = (moonDay >= 80 or moonDay <= 2);
        local isFullMoonPhase = (moonDay >= 38 and moonDay <= 44);
        if isNewMoonPhase or isFullMoonPhase then
            local pillPad   = S(4);
            local pillX = groupLeft - pillPad;
            local pillY = moonBaseY - S(3);
            local pillW = totalMoonRowW + pillPad * 2;
            local pillH = fontSize + S(6);
            if isNewMoonPhase then
                DrawPill(drawList, pillX, pillY, pillW, pillH,
                    ToU32(WithAlpha(0xFF6B0000, 0.30 * alpha)), S(4));
                DLRect(drawList, pillX, pillY, pillX + pillW, pillY + pillH,
                    ToU32(WithAlpha(0xFFCC2222, 0.85 * alpha)), S(4), nil, 1.0);
            else
                DrawPill(drawList, pillX, pillY, pillW, pillH,
                    ToU32(WithAlpha(0xFF001833, 0.35 * alpha)), S(4));
                DLRect(drawList, pillX, pillY, pillX + pillW, pillY + pillH,
                    ToU32(WithAlpha(0xFF4499FF, 0.85 * alpha)), S(4), nil, 1.0);
            end
        end

        if phaseTex then
            local phIconX = moonTextX - phaseGap;
            local phIconY = moonY + math.floor((moonRowH - phaseIconSize) / 2);
            DLImage(drawList, phaseTex, phIconX, phIconY,
                phIconX + phaseIconSize, phIconY + phaseIconSize, ToU32(WithAlpha(0xFFFFFFFF, alpha)));
        end

        -- Pulse % text: element color ↔ moon phase color (new=red, full=blue).
        if isNewMoonPhase or isFullMoonPhase then
            local baseArgb = textArgb;
            local moonArgb = WithAlpha(
                isNewMoonPhase
                    and (tonumber(colorConfig.moonNewColor)  or 0xFFFF4444)
                    or  (tonumber(colorConfig.moonFullColor) or 0xFF88CCFF),
                alpha);
            textArgb = LerpArgbHsv(baseArgb, moonArgb, GetMoonPulse());
        end

        DrawTextWithOutline(drawList, moonStr, moonTextX, moonBaseY, textArgb, outlineArgb, fontSize);

        if moonArrowTex then
            local arrowX = moonTextX + moonW + arrowGap;
            local arrowY = moonY + math.floor((moonRowH - moonArrowSize) / 2);
            DLImage(drawList, moonArrowTex, arrowX, arrowY,
                arrowX + moonArrowSize, arrowY + moonArrowSize, ToU32(WithAlpha(0xFFFFFFFF, alpha)));
        end
    end

    -- Weakness corner badge
    local weakWeekday = data.ELEMENT_DEFEATS[colWeekday];
    if showBadge ~= false and weakWeekday ~= nil then
        local cornerX = iconX + iconSize - badgeSize;
        local cornerY = iconY + iconSize - badgeSize;
        DLRectFilled(drawList, cornerX - 1, cornerY - 1, cornerX + badgeSize + 1, cornerY + badgeSize + 1,
            ToU32(WithAlpha(0xFF3B0000, alpha)), 2);
        if disableIcons then
            local weakArgb = colorConfig[data.ELEM_KEYS[weakWeekday]] or 0xFFFFFFFF;
            DLRectFilled(drawList, cornerX, cornerY, cornerX + badgeSize, cornerY + badgeSize,
                ToU32(WithAlpha(weakArgb, alpha * 0.85)), 2);
        else
            local badgeTex = GetTexPtr(textures[weakWeekday]);
            if badgeTex then
                DLImage(drawList, badgeTex, cornerX, cornerY, cornerX + badgeSize, cornerY + badgeSize,
                    ToU32(WithAlpha(0xFFFFFFFF, alpha)));
            end
        end
        DLRect(drawList, cornerX - 1, cornerY - 1, cornerX + badgeSize + 1, cornerY + badgeSize + 1,
            ToU32(WithAlpha(0xFF8B1010, alpha)), 2, nil, 1.0);
    end

    if timeExtra > 0 then
        local tw = imtext.Measure(timeLabel, fontSize);
        local tx = cx + math.floor((colContentW - tw) / 2);
        local ty = cy + colH - timeExtra;
        DrawTextWithOutline(drawList, timeLabel, tx, ty,
            WithAlpha(0xFFD5D0C8, alpha), WithAlpha(0xFF000000, alpha), fontSize);
    end

    return cardX, cardY, cardW, cardH;
end

-- ── Day column tooltip (weekday name + moon phase + optional Fenrir/Selene) ───

local function DayColumnTooltipsEnabled()
    if not gConfig or gConfig.vanaTimeEnableTooltips == false then return false; end
    if gConfig.vanaTimeShowTooltip == false then return false; end
    return true;
end

local function DrawDayColumnTooltip(drawList, cardX, cardY, cardW, cardH, colWeekday, moonDay, moonPercent, startUnix, delta)
    imgui.SetCursorScreenPos({cardX, cardY});
    local clicked = imgui.InvisibleButton('##vdDay' .. tostring(delta), {cardW, cardH});
    local hovered = imgui.IsItemHovered()
        or imgui.IsMouseHoveringRect({cardX, cardY}, {cardX + cardW, cardY + cardH});
    if clicked then weekOpen = not weekOpen; end
    if not hovered then return; end
    DLRect(drawList, cardX, cardY, cardX + cardW, cardY + cardH,
        ToU32(0xCCFFFFFF), 6, nil, 2.0);
    if DayColumnTooltipsEnabled() then
        pendingDayTooltip = {colWeekday, moonDay, moonPercent, startUnix};
    end
end

-- Draw via a real ImGui window (Begin/End). Do NOT use GetForegroundDrawList +
-- imtext.Draw after imgui.End — that races the renderer and causes
-- EXCEPTION_ACCESS_VIOLATION (random addon blamed on the next event).
local TIP_WIN_FLAGS = bit.bor(
    ImGuiWindowFlags_NoDecoration,
    ImGuiWindowFlags_AlwaysAutoResize,
    ImGuiWindowFlags_NoInputs,
    ImGuiWindowFlags_NoFocusOnAppearing,
    ImGuiWindowFlags_NoNav,
    ImGuiWindowFlags_NoSavedSettings,
    ImGuiWindowFlags_NoMove,
    ImGuiWindowFlags_NoDocking
);

local COL_TIP_GOLD   = {0.957, 0.855, 0.592, 1.0};
local COL_TIP_HEADER = {0.796, 0.667, 0.313, 1.0};
local COL_TIP_LABEL  = {0.667, 0.667, 0.667, 1.0};

local function DrawDayColumnTooltipWindow()
    if not pendingDayTooltip then return; end
    local colWeekday, moonDay, moonPercent, startUnix = pendingDayTooltip[1], pendingDayTooltip[2], pendingDayTooltip[3], pendingDayTooltip[4];
    pendingDayTooltip = nil;

    if not DayColumnTooltipsEnabled() then return; end

    local showFenrir = gConfig.vanaTimeTooltipFenrir ~= false;
    local showSelene = gConfig.vanaTimeTooltipSeleneBow ~= false;

    local phaseIdx  = data.GetMoonPhaseRaw(moonDay);
    local phaseName = data.PHASE_NAMES[phaseIdx] or '?';
    local dayName   = data.GetWeekdayName(colWeekday);

    local direction = (gConfig and gConfig.vanaTimeTooltipDirection) or 'above';
    local anchorX   = mainWinPos.x + mainWinSize.w * 0.5;
    local anchorY   = (direction == 'below')
        and (mainWinPos.y + mainWinSize.h + 4)
        or  (mainWinPos.y - 4);
    local pivotY    = (direction == 'below') and 0.0 or 1.0;

    local ok, err = Safe.Run(function(scope)
    imgui.SetNextWindowBgAlpha(0.92);
    imgui.SetNextWindowPos({anchorX, anchorY}, ImGuiCond_Always, {0.5, pivotY});
    scope:PushStyleVar(ImGuiStyleVar_WindowRounding, 4.0);
    scope:PushStyleVar(ImGuiStyleVar_WindowPadding, {8, 8});

    local visible = scope:BeginWindow("##VanaDialDayTip", true, TIP_WIN_FLAGS);
    if visible then
        imgui.TextColored(COL_TIP_GOLD, dayName);
        imgui.Text(string.format('%s  (%d%%)', phaseName, moonPercent));
        if startUnix then
            local remain = startUnix - data.GetUnixTime();
            if remain > 0 then
                imgui.Text('Starts ' .. FormatLocalClock(startUnix) .. ' in ' .. FormatLead(remain));
            else
                imgui.Text('Started ' .. FormatLocalClock(startUnix));
            end
        end

        if showFenrir then
            local lc = data.LUNAR_CRY[phaseIdx];
            local eh = data.ECLIPTIC_HOWL[phaseIdx];
            local eg = data.ECLIPTIC_GROWL[phaseIdx];
            if lc and eh and eg then
                imgui.Separator();
                imgui.TextColored(COL_TIP_HEADER, 'Fenrir Pacts');
                imgui.TextColored(COL_TIP_LABEL, 'Lunar Cry');
                imgui.SameLine(0, 8);
                imgui.Text(string.format('Acc %+d   Eva %+d', lc[1], lc[2]));
                imgui.TextColored(COL_TIP_LABEL, 'Ecliptic Howl');
                imgui.SameLine(0, 8);
                imgui.Text(string.format('Acc %+d   Eva %+d', eh[1], eh[2]));
                imgui.TextColored(COL_TIP_LABEL, 'Ecliptic Growl');
                imgui.SameLine(0, 8);
                imgui.Text(string.format('STR/DEX/VIT %+d   AGI/INT/MND/CHR %+d', eg[1], eg[2]));
            end
        end

        if showSelene then
            local sb = data.SELENE_BOW[phaseIdx];
            if sb then
                if showFenrir then imgui.Separator(); end
                imgui.TextColored(COL_TIP_HEADER, "Selene's Bow");
                imgui.TextColored(COL_TIP_LABEL, 'Rng Acc / Atk');
                imgui.SameLine(0, 8);
                imgui.Text(string.format('%+d RAcc   %+d RAtk', sb[1], sb[2]));
            end
        end
    end
    end);
    if not ok then error(err); end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.Initialize()
    LoadTextures();
    -- Share texture tables and position state with popups via a context table.
    -- Tables are references — LoadTextures and DrawWindow update them in-place.
    popups.Initialize({
        mainWinPos        = mainWinPos,
        mainWinSize       = mainWinSize,
        textures          = textures,
        moonPhaseTextures = moonPhaseTextures,
        todTextures       = todTextures,
        GetTexPtr         = GetTexPtr,
    });
end

function M.EnsureTextures()
    if TexturesReady() then return true; end
    local now = data.GetTickMs and data.GetTickMs() or 0;
    if now < nextTextureRetryMs then return false; end
    nextTextureRetryMs = now + 1000;
    LoadTextures();
    return TexturesReady();
end

function M.Reset()
    vtCache    = { hour=-1, min=-1, str='', measW=0 };
    ltCache    = { osMin=-1, osHour=-1, str='', measW=0 };
    lastOsTime  = -1;
    lastFontSize = -1;
    _mainWindowParked = false;
    windowbg.ClearTintCache();
    imtext.Reset();
end

-- Drop this addon's cached D3D textures after a device reset / zone. COM
-- release is deferred until the next present so this frame's draw list can
-- finish. Do not TextureManager.clear() — if this manager is shared with
-- XIUI, a full clear drops every XIUI texture mid-session.
function M.InvalidateTextures()
    TextureManager.evictKeyPrefix('file_VanaDial/');
    TextureManager.evictKeyPrefix('file_backgrounds/');
    TextureManager.evictKey('file_icons/gear');
    windowbg.ClearTintCache();
    for k in pairs(textures)          do textures[k]          = nil; end
    for k in pairs(moonPhaseTextures) do moonPhaseTextures[k] = nil; end
    todTextures.day         = nil;
    todTextures.night       = nil;
    todTextures.deadOfNight = nil;
    arrowRightTex     = nil;
    moonUpTex         = nil;
    moonDownTex       = nil;
    clockIconTex      = nil;
    gearIconTex       = nil;
    nextTextureRetryMs = 0;
end

function M.Cleanup()
    M.InvalidateTextures();
    imtext.Reset();
    _mainWindowParked = false;
    popups.SetTimersOpen(false);
end

function M.HideMainWindow()
    -- Park off-screen first; never move the visible window to (0,0) during transitions.
    imgui.SetNextWindowPos({-10000, -10000}, ImGuiCond_Always);
    imgui.SetNextWindowSize({1, 1}, ImGuiCond_Always);
    local flags = bit.bor(
        GetBaseWindowFlags(true),
        ImGuiWindowFlags_NoInputs,
        ImGuiWindowFlags_NoBackground
    );
    local ok, err = Safe.Run(function(scope)
        scope:BeginWindow("Vana'Dial##standalone", true, flags);
    end);
    if not ok then error(err); end
    -- Clear once per hide stretch so the next draw re-applies saved position.
    if not _mainWindowParked then
        _mainWindowParked = true;
        if gConfig and gConfig.appliedPositions then
            gConfig.appliedPositions['VanaDial'] = nil;
        end
    end
end

function M.StageMainWindowPosition()
    local cfg = gConfig;
    if not cfg then return false; end
    if not cfg.windowPositions then cfg.windowPositions = T{}; end
    if not cfg.windowPositions['VanaDial'] then
        cfg.windowPositions['VanaDial'] = T{ x = 100, y = 100 };
    end
    local pos = cfg.windowPositions['VanaDial'];
    imgui.SetNextWindowPos({pos.x, pos.y}, ImGuiCond_Always);
    imgui.SetNextWindowSize({1, 1}, ImGuiCond_Always);
    local flags = bit.bor(
        GetBaseWindowFlags(true),
        ImGuiWindowFlags_NoInputs,
        ImGuiWindowFlags_NoBackground
    );
    local ok, err = Safe.Run(function(scope)
        scope:BeginWindow("Vana'Dial##standalone", true, flags);
    end);
    if not ok then error(err); end
    if not cfg.appliedPositions then cfg.appliedPositions = T{}; end
    cfg.appliedPositions['VanaDial'] = true;
    return true;
end

-- ── Minimalist bar ────────────────────────────────────────────────────────────

local MOON_WAX_COLOR   = 0xFF3DDC6A;
local MOON_WANE_COLOR  = 0xFFFF5050;
local MINIMAL_DELAY_DEFAULT = 5;
-- After the scale slider is released, keep the compact bar up this long
-- so the new size can be seen before the full window returns.
local SCALE_PREVIEW_HOLD = 2.0;
-- Stay hovered while a button is held or a popup covers the window, so a
-- click on the timer or settings icon can finish.
local MINIMAL_HOVER_FLAGS = bit.bor(
    rawget(_G, 'ImGuiHoveredFlags_AllowWhenBlockedByPopup') or 32,
    rawget(_G, 'ImGuiHoveredFlags_AllowWhenBlockedByActiveItem') or 128
);

local minimalExpanded   = false;
local minimalLatched    = false;
local minimalSawDrag    = false;
local minimalLeftAt     = nil;
local minimalLastInteract = 0;
local minimalScalePreviewUntil = 0;
local minimalScaleWasExpanded = false;
local expandAnchorBottom = nil;
local lastExpandContentH = nil;

local minimalFontCache = { size = -1, pctW = 0 };
local minimalTimeCache = { key = '', size = -1, w = 0, str = '' };

local function ConfigIsOpen()
    return VanaDial_IsConfigOpen and VanaDial_IsConfigOpen();
end

local function MinimalShowFull(cfg)
    if cfg.vanaTimeMinimalist ~= true then return true; end
    if NowSeconds() < minimalScalePreviewUntil then return false; end
    return minimalExpanded;
end

VanaDial_PreviewMinimalScale = function()
    local now = NowSeconds();
    if minimalScalePreviewUntil <= now then
        minimalScaleWasExpanded = minimalExpanded;
    end
    minimalExpanded = false;
    minimalLatched = true;
    minimalScalePreviewUntil = now + SCALE_PREVIEW_HOLD;
end;

local function IsNewMoonPhase(moonDay)
    return moonDay >= 80 or moonDay <= 2;
end

local function IsFullMoonPhase(moonDay)
    return moonDay >= 38 and moonDay <= 44;
end

local function MoonPercentArgb(moonDay, colorCfg)
    local base;
    if moonDay > 0 and moonDay < 42 then
        base = MOON_WAX_COLOR;
    elseif moonDay > 42 then
        base = MOON_WANE_COLOR;
    elseif IsNewMoonPhase(moonDay) then
        base = tonumber(colorCfg.moonNewColor) or 0xFFFF4444;
    else
        base = tonumber(colorCfg.moonFullColor) or 0xFF88CCFF;
    end
    if IsNewMoonPhase(moonDay) or IsFullMoonPhase(moonDay) then
        base = LerpArgbHsv(base, 0xFFFFFFFF, GetMoonPulse());
    end
    return base;
end

local function MoonTip(moonDay, pct)
    local phase = data.PHASE_NAMES[data.GetMoonPhaseRaw(moonDay)] or 'Moon';
    local trend = '';
    if moonDay > 0 and moonDay < 42 then
        trend = '  ·  Waxing';
    elseif moonDay > 42 then
        trend = '  ·  Waning';
    end
    return string.format('%s  (%d%%)%s', phase, pct, trend);
end

local function MinimalReturnDelay(cfg)
    local delay = tonumber(cfg.vanaTimeMinimalDelay);
    if delay == nil then delay = MINIMAL_DELAY_DEFAULT; end
    if delay < 0 then delay = 0; end
    if delay > 60 then delay = 60; end
    return delay;
end

local function UpdateMinimalMode(cfg, hovered)
    if cfg.vanaTimeMinimalist ~= true then
        minimalExpanded = false;
        minimalLatched = false;
        minimalSawDrag = false;
        minimalLeftAt = nil;
        return;
    end

    local now = NowSeconds();
    if minimalScalePreviewUntil > 0 then
        if now < minimalScalePreviewUntil then
            minimalExpanded = false;
            return;
        end
        minimalExpanded = minimalScaleWasExpanded;
        minimalLastInteract = now;
        minimalLatched = false;
        minimalScalePreviewUntil = 0;
    end

    local sawDrag = minimalSawDrag;
    if imgui.IsMouseDragging(0, 4.0) then
        sawDrag = true;
        minimalSawDrag = true;
    end

    local clicked = false;
    if imgui.IsMouseReleased(0) then
        clicked = hovered and not sawDrag;
        minimalSawDrag = false;
    end

    -- Settings stay put: a visible bar keeps previewing its scale, and an
    -- already-open full window does not snap shut while the cursor is in config.
    local delay = MinimalReturnDelay(cfg);

    if ConfigIsOpen() then
        minimalLeftAt = nil;
        if minimalExpanded then
            minimalLastInteract = now;
        end
        return;
    end

    if not hovered then
        -- Mouse-down still belongs to the timer/settings button. Collapsing
        -- here destroys that button before the click can register.
        if minimalExpanded and imgui.IsMouseDown(0) then
            minimalLastInteract = now;
            minimalLeftAt = nil;
            return;
        end
        -- Brief gap between the clock and the timers panel.
        if minimalExpanded and popups.IsTimersOpen() and (now - minimalLastInteract) <= 0.4 then
            return;
        end
        if minimalExpanded then
            if minimalLeftAt == nil then
                minimalLeftAt = now;
            end
            if (now - minimalLeftAt) < delay then
                return;
            end
        end
        minimalExpanded = false;
        minimalLatched = false;
        minimalLeftAt = nil;
        return;
    end

    minimalLeftAt = nil;

    local moved = clicked or sawDrag;
    local io = imgui.GetIO();
    if io then
        local delta = io.MouseDelta;
        if delta and ((delta.x or 0) ~= 0 or (delta.y or 0) ~= 0) then
            moved = true;
        end
        if (io.MouseWheel or 0) ~= 0 or (io.MouseWheelH or 0) ~= 0 then
            moved = true;
        end
    end
    if moved then
        minimalLastInteract = now;
    end

    local mode = cfg.vanaTimeMinimalExpand or 'hover';
    if minimalLatched then
        if clicked then
            minimalLatched = false;
            minimalExpanded = true;
            minimalLastInteract = now;
        end
        return;
    end

    if not minimalExpanded then
        if mode == 'hover' or (mode == 'click' and clicked) then
            minimalExpanded = true;
            minimalLastInteract = now;
        end
        return;
    end

    if delay > 0 and (now - minimalLastInteract) > delay then
        minimalExpanded = false;
        minimalLatched = true;
    end
end

local function ResolveBarWeather(cfg, weatherId)
    if cfg.vanaTimeShowWeather == false then
        _G.XIUI_weatherTestExpiry = 0;
        return nil, 1;
    end
    local testId, testAlpha = nil, 1;
    if cfg.vanaTimeWeatherHideNonElemental then
        if NowSeconds() < (_G.XIUI_weatherTestExpiry or 0) then
            testId = 4;
            testAlpha = 0.35 + 0.65 * GetMoonPulse();
        end
    else
        _G.XIUI_weatherTestExpiry = 0;
    end
    local id = testId or weatherId;
    local enabled = ((weatherId or -1) >= 0
        and not (cfg.vanaTimeWeatherHideNonElemental and weatherId < 4))
        or testId ~= nil;
    if not enabled or id == nil or data.WEATHER_TO_ELEMENT[id] == nil then
        return nil, 1;
    end
    return id, testId and testAlpha or 1;
end

-- Compact bar: HH:MM, today dot, moon %, arrow, tomorrow dot, moon %, weather.
-- Returns content width and height (window padding is applied by the caller).
local function DrawMinimalBar(drawList, cx0, cy0, cfg, colorCfg, vtHour, vtMin, weekday, moonDay, weatherId, scale, colPad)
    local function S(n) return math.max(1, math.floor(n * scale)); end
    local fontSize = math.max(8, math.floor(13 * scale));
    local gap = S(5);
    local weatherGap = math.max(S(22), math.floor(fontSize * 1.8));
    local contentH = fontSize + 4;
    local dotR = math.max(3, math.floor(fontSize * 0.30));
    local arrowH = math.max(7, math.floor(contentH * 0.62));
    local arrowW = math.max(7, math.floor(arrowH * 0.85));

    local timeKey = vtHour * 60 + vtMin;
    if minimalTimeCache.key ~= timeKey or minimalTimeCache.size ~= fontSize then
        minimalTimeCache.key = timeKey;
        minimalTimeCache.size = fontSize;
        minimalTimeCache.str = string.format('%02d:%02d', vtHour, vtMin);
        minimalTimeCache.w = imtext.Measure(minimalTimeCache.str, fontSize);
    end
    if minimalFontCache.size ~= fontSize then
        minimalFontCache.size = fontSize;
        minimalFontCache.pctW = imtext.Measure('100%', fontSize);
    end
    local timeW = minimalTimeCache.w;
    local pctW = minimalFontCache.pctW;
    local dotD = dotR * 2;

    local wxId, wxAlpha = ResolveBarWeather(cfg, weatherId);
    local wxTex, wxDouble = nil, false;
    local wxIcon = contentH;
    local wxW = 0;
    if wxId ~= nil then
        wxTex = GetTexPtr(textures[data.WEATHER_TO_ELEMENT[wxId]]);
        wxDouble = (wxId % 2 ~= 0) and wxId >= 5;
        if wxTex then
            wxW = wxIcon + (wxDouble and (S(2) + wxIcon) or 0);
        end
    end

    local contentW = timeW + gap + dotD + gap + pctW + gap + arrowW + gap + dotD + gap + pctW;
    if wxTex then
        contentW = contentW + weatherGap + wxW;
    end

    local bgPad = colPad or 8;
    local bgX, bgY = cx0 - bgPad, cy0 - bgPad;
    local bgW, bgH = contentW + bgPad * 2, contentH + bgPad * 2;
    local bgRgb = colorCfg.bgColor or 0xFF000000;
    local bgOpacity = ResolveBackgroundOpacity(cfg, bgRgb);
    local opaqueU32 = ToU32(WithAlpha(bgRgb, bgOpacity));
    local transpU32 = ToU32(WithAlpha(bgRgb, 0.0));
    local midX = bgX + bgW / 2;
    DLRectMultiColor(drawList, bgX, bgY, midX, bgY + bgH, transpU32, opaqueU32, opaqueU32, transpU32);
    DLRectMultiColor(drawList, midX, bgY, bgX + bgW, bgY + bgH, opaqueU32, transpU32, transpU32, opaqueU32);
    windowbg.Draw(drawList, cx0, cy0, contentW, contentH, {
        theme = 'Window1', bgScale = 0, bgOpacity = 0,
        borderScale = cfg.vanaTimeBorderScale or 1.0,
        borderOpacity = cfg.vanaTimeBorderOpacity or 1.0,
        bgColor = 0x00000000, borderColor = colorCfg.borderColor or 0xFFFFFFFF,
        padding = bgPad });

    local todayArgb = colorCfg[data.ELEM_KEYS[weekday]] or 0xFFFFFFFF;
    local textY = cy0 + math.floor((contentH - fontSize) / 2);
    local timeColor = cfg.vanaTimeVTElementColor and todayArgb or (tonumber(colorCfg.vtClockColor) or VT_TEXT_COLOR);
    local tips = cfg.vanaTimeEnableTooltips ~= false;

    local function Tip(x, y, w, h, text)
        if not tips or not text then return; end
        if imgui.IsMouseHoveringRect({ x, y }, { x + w, y + h }) then
            imgui.SetTooltip(text);
        end
    end

    local x = cx0;
    DrawTextWithOutline(drawList, minimalTimeCache.str, x, textY, timeColor, 0xFF000000, fontSize);
    if cfg.vanaTimeTipVT ~= false then
        Tip(x, cy0, timeW, contentH, "Vana'diel Time");
    end
    x = x + timeW + gap;

    local function DrawDot(wd, atX, alpha)
        local argb = colorCfg[data.ELEM_KEYS[wd]] or 0xFFFFFFFF;
        local ring = 0xCC000000;
        if alpha then
            argb = WithAlpha(argb, alpha);
            ring = WithAlpha(0xFF000000, 0.8 * alpha);
        end
        local cx = atX + dotR;
        local cy = cy0 + contentH * 0.5;
        DLCircleFilled(drawList, cx, cy, dotR + 1, ToU32(ring), 16);
        DLCircleFilled(drawList, cx, cy, dotR, ToU32(argb), 16);
        Tip(atX, cy0, dotD, contentH, data.GetWeekdayName(wd));
    end

    local function DrawPct(md, atX, alpha)
        local pct = data.CalcMoonPercent(md);
        local label = string.format('%d%%', pct);
        local col = MoonPercentArgb(md, colorCfg);
        local outline = 0xFF000000;
        if alpha then
            col = WithAlpha(col, alpha);
            outline = WithAlpha(outline, alpha);
        end
        DrawTextWithOutline(drawList, label, atX, textY, col, outline, fontSize);
        Tip(atX, cy0, pctW, contentH, MoonTip(md, pct));
    end

    DrawDot(weekday, x);
    x = x + dotD + gap;
    DrawPct(moonDay, x);
    x = x + pctW + gap;

    local arrY = cy0 + math.floor((contentH - arrowH) / 2);
    local arrTex = GetTexPtr(arrowRightTex);
    if arrTex then
        DLImage(drawList, arrTex, x, arrY, x + arrowW, arrY + arrowH, ToU32(0xC0FFFFFF));
    else
        DrawTextWithOutline(drawList, COL_ARROW, x, textY, 0xFFFFFFFF, 0xFF000000, fontSize);
    end
    x = x + arrowW + gap;

    local nextWeekday = (weekday + 1) % 8;
    local nextMoon = (moonDay + 1) % data.VD_MOON_DAYS;
    DrawDot(nextWeekday, x, 0.55);
    x = x + dotD + gap;
    DrawPct(nextMoon, x, 0.55);

    if wxTex then
        x = x + pctW + weatherGap;
        local iy = cy0 + math.floor((contentH - wxIcon) / 2);
        local tint = ToU32(WithAlpha(0xFFFFFFFF, wxAlpha));
        DLImage(drawList, wxTex, x, iy, x + wxIcon, iy + wxIcon, tint);
        if wxDouble then
            local x2 = x + wxIcon + S(2);
            DLImage(drawList, wxTex, x2, iy, x2 + wxIcon, iy + wxIcon, tint);
        end
        if cfg.vanaTimeTipWeather ~= false then
            Tip(x, cy0, wxW, contentH, data.WEATHER_NAMES[wxId] or 'Weather');
        end
    end

    return contentW, contentH;
end

-- ── DrawWindow ────────────────────────────────────────────────────────────────

function M.DrawWindow(weatherId)
    local cfg = gConfig;
    if not cfg then return; end

    _mainWindowParked = false;
    pendingDayTooltip = nil;
    popups.ResetAttachedHover();

    -- Draw after other modules may have called imtext.SetConfigFromSettings
    -- (Tahoma Bold @ 20px by default). Standalone has its own imtext instance, so we must
    -- select the same font here; otherwise GetFont() falls back to ImGui's built-in font,
    -- which looks thinner and more jagged than XIUI's clock text.
    local clockBold = cfg.vanaTimeFontBold ~= false;
    imtext.SetConfig('Tahoma', clockBold, 1);

    local colorCfg = (cfg.colorCustomization or {}).vanaTime or {};
    local scale    = math.max(0.5, math.min(4.0, cfg.vanaTimeScale    or 1.0));
    local function ClampFont(n, fallback)
        return math.max(8, math.min(48, math.floor(tonumber(n) or fallback)));
    end
    local vtFontBase   = ClampFont(cfg.vanaTimeFontSize, 12);
    local textFontBase = ClampFont(cfg.vanaTimeTextFontSize or cfg.vanaTimeFontSize, 12);
    -- VD clock uses its own size. Local time, moon %, and day labels use the other size.
    local vtFontSize = math.floor(vtFontBase * scale);
    local fontSize   = math.floor(textFontBase * scale);
    local iconSize = math.floor(math.max(16, math.min(128, cfg.vanaTimeIconSize  or 28)) * scale);
    local rounding = 12.0;
    local minimalScale = math.max(0.5, math.min(4.0, tonumber(cfg.vanaTimeMinimalScale) or 1.0));
    local showFull = MinimalShowFull(cfg);

    -- ── Game data (pure Lua — no FFI) ────────────────────────────────────────
    local rawTime       = data.GetRawTime();
    local weekday       = math.floor(rawTime / data.VD_DAY_SEC) % 8;
    local vtDay         = math.floor(rawTime / data.VD_DAY_SEC);
    local vtHour        = math.floor(rawTime % data.VD_DAY_SEC / data.VD_HOUR_SEC);
    local vtMin         = math.floor(rawTime % data.VD_HOUR_SEC / data.VD_MIN_F);
    local vtMinuteOfDay = vtHour * 60 + vtMin;
    local moonDay       = (math.floor(rawTime / data.VD_DAY_SEC) + data.VD_MOON_OFFSET) % data.VD_MOON_DAYS;
    local moonPct       = data.CalcMoonPercent(moonDay);

    -- ── Time string caches ───────────────────────────────────────────────────
    if vtHour ~= vtCache.hour or vtMin ~= vtCache.min then
        vtCache.hour  = vtHour;
        vtCache.min   = vtMin;
        vtCache.str   = string.format('VT: %02d:%02d', vtHour, vtMin);
        vtCache.measW = 0;
    end
    local vtStr = vtCache.str;

    local ltStr = '';
    if cfg.vanaTimeShowLocalTime ~= false then
        local now = os.time();
        if now ~= lastOsTime then
            lastOsTime = now;
            local lt   = os.date('*t', now);
            local h    = lt.hour;
            local m    = lt.min;
            local ampm = h >= 12 and 'PM' or 'AM';
            local h12  = h % 12;
            if h12 == 0 then h12 = 12; end
            if h ~= ltCache.osHour or m ~= ltCache.osMin then
                ltCache.osHour = h;
                ltCache.osMin  = m;
                ltCache.str    = string.format('LT: %02d:%02d %s', h12, m, ampm);
                ltCache.measW  = 0;
            end
        end
        ltStr = ltCache.str;
    end

    -- ── Column layout geometry ───────────────────────────────────────────────
    local colPad = 8;
    if not showFull then
        colPad = math.max(2, math.floor(4 * minimalScale));
        rounding = math.max(4, 6 * minimalScale);
    end

    -- Hoisted here: also used after imgui.End for timer/weather/TOD popups.
    local showGear   = cfg.vanaTimeShowSettingsBtn ~= false;
    local showTimers = cfg.vanaTimeShowTimers ~= false;

    if vtFontSize ~= lastVtFontSize then
        lastVtFontSize = vtFontSize;
        vtCache.measW  = 0;
    end
    if fontSize ~= lastFontSize then
        lastFontSize   = fontSize;
        ltCache.measW  = 0;
        _moonPctFontSz = -1;
    end
    if vtCache.measW == 0 then
        vtCache.measW = imtext.Measure(vtCache.str, vtFontSize);
    end
    if ltStr ~= '' and ltCache.measW == 0 then
        ltCache.measW = imtext.Measure(ltCache.str, fontSize);
    end
    if _moonPctFontSz ~= fontSize then
        _moonPctFontSz = fontSize;
        _moonPctMeasW  = imtext.Measure('100%', fontSize);
    end

    -- ── Window open ──────────────────────────────────────────────────────────
    local windowFlags = GetBaseWindowFlags(cfg.lockPositions);
    local mainHoveredThisFrame = false;

    local ok, err = Safe.Run(function(scope)
    scope:PushStyleVar(ImGuiStyleVar_WindowRounding, rounding);
    scope:PushStyleVar(ImGuiStyleVar_WindowPadding, {colPad, colPad});

    ApplyWindowPosition('VanaDial');

    local visible = scope:BeginWindow("Vana'Dial##standalone", true, windowFlags);
    if visible then
        SaveWindowPosition('VanaDial');

        local wx, wy = imgui.GetWindowPos();
        local ww, wh = imgui.GetWindowSize();
        mainWinPos.x  = wx;
        mainWinPos.y  = wy;
        mainWinSize.w = ww;
        mainWinSize.h = wh;

        local elemArgb    = colorCfg[data.ELEM_KEYS[weekday]] or 0xFFFFFFFF;
        local outlineArgb = GetOutlineColor(weekday);
        local vtTextColor = cfg.vanaTimeVTElementColor and elemArgb or (tonumber(colorCfg.vtClockColor) or VT_TEXT_COLOR);

        local laidOutContentH = 0;
        if not showFull then
            local barX, barY = imgui.GetCursorScreenPos();
            local barW, barH = DrawMinimalBar(imgui.GetWindowDrawList(), barX, barY,
                cfg, colorCfg, vtHour, vtMin, weekday, moonDay, weatherId, minimalScale, colPad);
            laidOutContentH = barH;
            imgui.Dummy({ barW, barH });
        else
        local dayScale = weekOpen and 0.75 or 1;
        local function S(n) return math.max(1, math.floor(n * dayScale)); end
        local dayIconSize = math.floor(iconSize * dayScale);
        local dayFontSize = math.floor(fontSize * dayScale);
        if dayIconSize < 1 then dayIconSize = 1; end
        if dayFontSize < 1 then dayFontSize = 1; end
        local dayMoonPctW = (dayFontSize == _moonPctFontSz) and _moonPctMeasW or imtext.Measure('100%', dayFontSize);

        local CARD_PAD      = S(4);
        local SEP_GAP       = S(4);
        local sepArrowW     = math.max(1, math.floor(dayIconSize * 0.5));

        local showPastFuture  = cfg.vanaTimeShowPastFuture ~= false;
        local showMoon        = cfg.vanaTimeShowMoonPercent ~= false;
        local showBadge       = cfg.vanaTimeShowWeaknessBadge ~= false;
        local plainDayIcons   = cfg.vanaTimePlainDayIcons == true;
        local pastFutureAlpha = cfg.vanaTimePastFutureOpacity or PAST_FUTURE_ALPHA;

        local moonArrowSlot = showMoon and (math.floor(dayFontSize * 0.7) + S(2)) or 0;
        local phaseIconSlot = showMoon and (math.floor(dayFontSize + S(2)) + S(2)) or 0;
        local moonMaxW      = showMoon and (phaseIconSlot + dayMoonPctW + moonArrowSlot) or 0;
        local colContentW   = math.max(dayIconSize, moonMaxW + S(4));
        local cardW         = colContentW + CARD_PAD * 2;
        local weekGap       = S(6);
        local WEEK_COLS     = 4;
        if weekOpen then
            local timeW = imtext.Measure('12:45 PM', dayFontSize);
            if timeW > colContentW then
                colContentW = timeW;
                cardW = colContentW + CARD_PAD * 2;
            end
        end
        local sepSpan       = SEP_GAP * 2 + sepArrowW;
        local cardAreaW     = weekOpen
            and (WEEK_COLS * cardW + (WEEK_COLS - 1) * sepSpan)
            or  (showPastFuture
                and (cardW * 3 + SEP_GAP * 4 + sepArrowW * 2)
                or  cardW);

        local ltBelowColumns = (not showPastFuture) and (ltStr ~= '');
        local clockH = vtFontSize + 4;
        local ltRowH = fontSize + 4;
        if ltStr ~= '' and not ltBelowColumns then
            clockH = math.max(vtFontSize, fontSize) + 4;
        end
        local iconColH = showMoon and (dayIconSize + S(2) + dayFontSize + S(4)) or (dayIconSize + S(4));
        local singleColH = iconColH;
        if weekOpen then singleColH = singleColH + dayFontSize + S(4); end
        local colH     = weekOpen and (singleColH * 2 + weekGap + CARD_PAD * 4) or singleColH;
        local contentW = cardAreaW;
        local vtMeasW  = vtCache.measW;
        local ltMeasW  = ltStr ~= '' and ltCache.measW or 0;

        local totalH = clockH + colH + colPad;
        if ltBelowColumns then
            totalH = totalH + ltRowH + 2;
        end

        -- Size the clock row from the slots the layout actually uses, so a
        -- larger VD font widens the window and a smaller one does not leave
        -- a stuck width behind.
        local inlineTodW = (not cfg.vanaTimeTodPopup) and (vtFontSize + 3) or 0;
        local numIcons = (showTimers and 1 or 0) + (showGear and 1 or 0);
        local iconSpan = numIcons > 0 and (numIcons * ltRowH + (numIcons - 1) * 2) or 0;
        local vtZone = vtMeasW + inlineTodW + 8;
        local ltZone = (ltStr ~= '' and (ltMeasW + 8)) or 0;
        local clockNeed = vtZone;
        local sideBySide = (ltStr ~= '') and (not ltBelowColumns);
        if weekOpen or (showTimers and sideBySide) then
            local slot = math.max(vtZone, ltZone, iconSpan + 8);
            clockNeed = slot * 3;
        elseif sideBySide then
            clockNeed = math.max(vtZone, ltZone) * 2;
            if showGear then clockNeed = clockNeed + ltRowH + 4; end
        elseif iconSpan > 0 then
            clockNeed = math.max(math.ceil(vtZone * 1.5), (iconSpan + 8) * 3);
        end
        if ltBelowColumns and ltZone > clockNeed then
            clockNeed = ltZone;
        end
        if contentW < clockNeed then contentW = clockNeed; end

        local cx0, cy0 = imgui.GetCursorScreenPos();
        local drawList = imgui.GetWindowDrawList();

        -- ── Window background ────────────────────────────────────────────────
        local bgPad  = colPad;
        local bgX    = cx0 - bgPad;
        local bgY    = cy0 - bgPad;
        local bgW    = contentW + bgPad * 2;
        local bgH    = totalH  + bgPad * 2;
        local bgRgb     = colorCfg.bgColor or 0xFF000000;
        local bgOpacity = ResolveBackgroundOpacity(cfg, bgRgb);

        local bgTheme     = 'Plain';
        local borderTheme = 'Window1';

        if bgTheme:match('^Window%d+$') then
            windowbg.Draw(drawList, cx0, cy0, contentW, totalH, {
                theme=bgTheme, bgScale=cfg.vanaTimeBgScale or 1.0,
                bgOpacity=bgOpacity, borderScale=0, borderOpacity=0,
                bgColor=bgRgb, borderColor=0x00000000, padding=colPad });
        elseif bgTheme ~= '-None-' then
            local opaqueU32 = ToU32(WithAlpha(bgRgb, bgOpacity));
            local transpU32 = ToU32(WithAlpha(bgRgb, 0.0));
            local midX      = bgX + bgW / 2;
            DLRectMultiColor(drawList, bgX,bgY, midX,bgY+bgH, transpU32,opaqueU32,opaqueU32,transpU32);
            DLRectMultiColor(drawList, midX,bgY, bgX+bgW,bgY+bgH, opaqueU32,transpU32,transpU32,opaqueU32);
        end

        if borderTheme:match('^Window%d+$') then
            windowbg.Draw(drawList, cx0, cy0, contentW, totalH, {
                theme=borderTheme, bgScale=0, bgOpacity=0,
                borderScale=cfg.vanaTimeBorderScale or 1.0,
                borderOpacity=cfg.vanaTimeBorderOpacity or 1.0,
                bgColor=0x00000000, borderColor=colorCfg.borderColor or 0xFFFFFFFF,
                padding=colPad });
        elseif borderTheme == 'Plain' then
            local borderArgb = WithAlpha(colorCfg.borderColor or 0xFFFFFFFF, cfg.vanaTimeBorderOpacity or 1.0);
            DLRect(drawList, bgX,bgY, bgX+bgW,bgY+bgH, ToU32(borderArgb), rounding, nil, 1.0);
        end

        laidOutContentH = totalH;
        imgui.Dummy({contentW, totalH});

        -- ── Clock row ────────────────────────────────────────────────────────
        local clockY = cy0;
        local vtTextY = clockY + math.floor((clockH - 4 - vtFontSize) / 2);
        local ltTextY = clockY + math.floor((clockH - 4 - fontSize) / 2);

        do
            local gY   = clockY - 2;
            local gH   = clockH + 4;
            local gX1  = cx0 - 4;
            local gX2  = cx0 + contentW + 4;
            local midX = (gX1 + gX2) / 2;
            local glow   = ToU32(WithAlpha(elemArgb, 0.28));
            local transp = ToU32(WithAlpha(elemArgb, 0.0));
            DLRectMultiColor(drawList, gX1,gY, midX,gY+gH, transp,glow,glow,transp);
            DLRectMultiColor(drawList, midX,gY, gX2,gY+gH, glow,transp,transp,glow);
        end

        local iconSzClock = ltRowH;

        -- TOD icon (inline in clock row — only when popup is disabled)
        local todTexRaw =
            (vtHour >= 20 or vtHour < 4)     and todTextures.deadOfNight
            or (vtHour >= 6 and vtHour < 18) and todTextures.day
            or todTextures.night;
        local todIconTex = GetTexPtr(todTexRaw);

        local function DrawTodIcon(vtX)
            if not todIconTex then return end;
            if cfg.vanaTimeTodPopup then return end;
            local todSz = vtFontSize;
            local tx = vtX + vtMeasW + 3;
            local ty = vtTextY;
            DLImage(drawList, todIconTex, tx,ty, tx+todSz,ty+todSz, ToU32(0xEEFFFFFF));
            if cfg.vanaTimeEnableTooltips ~= false and cfg.vanaTimeTipTod ~= false
                and imgui.IsMouseHoveringRect({tx, ty}, {tx + todSz, ty + todSz}) then
                imgui.SetTooltip('Time of Day: ' .. (data.GetTodName(vtHour) or ''));
            end
        end

        local function DrawClockTooltips(vtX, ltX, ltClockY)
            if cfg.vanaTimeEnableTooltips == false then return end;
            local ltY = ltClockY or clockY;
            if imgui.IsMouseHoveringRect({vtX,clockY},{vtX+vtMeasW,clockY+clockH}) then
                if cfg.vanaTimeTipVT ~= false then imgui.SetTooltip("Vana'diel Time"); end
            elseif ltX and ltMeasW > 0
                and imgui.IsMouseHoveringRect({ltX,ltY},{ltX+ltMeasW,ltY+clockH}) then
                if cfg.vanaTimeTipLT ~= false then imgui.SetTooltip('Local Time'); end
            end
        end

        local function DrawGearIcon(gx, gy, isz)
            local gearTex = GetTexPtr(gearIconTex);
            local gc2x, gc2y = gx + isz * 0.5, gy + isz * 0.5;
            DLCircleFilled(drawList, gc2x,gc2y, isz*0.65, ToU32(bit.bor(bit.lshift(0x55,24),0x000000)), 24);
            if gearTex then
                DLImage(drawList, gearTex, gx,gy, gx+isz,gy+isz, ToU32(0xCCC3AE79));
            end
            imgui.SetCursorScreenPos({gx, gy});
            if imgui.InvisibleButton('##vdGear', {isz, isz}) then
                if VanaDial_ToggleConfig then VanaDial_ToggleConfig(); end
            end
            if imgui.IsItemHovered() then
                DLCircleFilled(drawList, gc2x,gc2y, isz*0.65, ToU32(0x30FFFFFF), 24);
                if cfg.vanaTimeEnableTooltips ~= false then imgui.SetTooltip("Vana'Dial Settings"); end
            end
        end

        if showTimers then
            local iconTex = GetTexPtr(clockIconTex);

            -- Determine layout based on what's shown
            local function PlaceClockIcon(icX, icY, isz)
                local icxFinal = icX;
                if showGear then
                    icxFinal = icX - math.floor((isz + 2) / 2);
                end
                local cx2, cy2 = icxFinal + isz * 0.5, icY + isz * 0.5;
                local glowAlpha = popups.IsTimersOpen() and 0xAA or 0x66;
                DLCircleFilled(drawList, cx2,cy2, isz*0.65, ToU32(bit.bor(bit.lshift(glowAlpha,24),0x000000)), 24);
                if iconTex then
                    DLImage(drawList, iconTex, icxFinal,icY, icxFinal+isz,icY+isz, ToU32(0xCCFFFFFF));
                end
                imgui.SetCursorScreenPos({icxFinal, icY});
                if imgui.InvisibleButton('##vdTimerClk', {isz, isz}) then
                    local wasOpen = popups.IsTimersOpen();
                    popups.SetTimersOpen(not wasOpen);
                    if not wasOpen then popups.MarkTimersOpenedByUserClick(); end
                end
                if imgui.IsItemHovered() then
                    DLCircleFilled(drawList, cx2,cy2, isz*0.65, ToU32(0x30FFFFFF), 24);
                end
                if showGear then
                    DrawGearIcon(icxFinal + isz + 2, icY, isz);
                end
            end

            if ltBelowColumns then
                local twoThird = math.floor(contentW * 2 / 3);
                local vtX  = cx0 + math.floor((twoThird - vtMeasW) / 2);
                local icX  = cx0 + twoThird + math.floor(((contentW - twoThird) - iconSzClock) / 2);
                local icY  = clockY + math.floor((clockH - iconSzClock) / 2);
                DrawTextWithOutline(drawList, vtStr, vtX, vtTextY, vtTextColor, outlineArgb, vtFontSize);
                DrawTodIcon(vtX);
                PlaceClockIcon(icX, icY, iconSzClock);
                DrawClockTooltips(vtX, nil);
            elseif ltStr ~= '' then
                local third = math.floor(contentW / 3);
                local vtX  = cx0 + math.floor((third - vtMeasW) / 2);
                local icX  = cx0 + third + math.floor((third - iconSzClock) / 2);
                local icY  = clockY + math.floor((clockH - iconSzClock) / 2);
                local ltX  = cx0 + third * 2 + math.floor((third - ltMeasW) / 2);
                DrawTextWithOutline(drawList, vtStr, vtX, vtTextY, vtTextColor, outlineArgb, vtFontSize);
                DrawTodIcon(vtX);
                DrawTextWithOutline(drawList, ltStr, ltX, ltTextY, colorCfg.textColor or 0xFFFFFFFF, outlineArgb, fontSize);
                PlaceClockIcon(icX, icY, iconSzClock);
                DrawClockTooltips(vtX, ltX);
            else
                local twoThird = math.floor(contentW * 2 / 3);
                local vtX  = cx0 + math.floor((twoThird - vtMeasW) / 2);
                local icX  = cx0 + twoThird + math.floor(((contentW - twoThird) - iconSzClock) / 2);
                local icY  = clockY + math.floor((clockH - iconSzClock) / 2);
                DrawTextWithOutline(drawList, vtStr, vtX, vtTextY, vtTextColor, outlineArgb, vtFontSize);
                DrawTodIcon(vtX);
                PlaceClockIcon(icX, icY, iconSzClock);
                DrawClockTooltips(vtX, nil);
            end
        elseif ltBelowColumns then
            local twoThird = showGear and math.floor(contentW * 2 / 3) or contentW;
            local vtX = cx0 + math.floor((twoThird - vtMeasW) / 2);
            DrawTextWithOutline(drawList, vtStr, vtX, vtTextY, vtTextColor, outlineArgb, vtFontSize);
            DrawTodIcon(vtX);
            DrawClockTooltips(vtX, nil);
            if showGear then
                local gx = cx0 + twoThird + math.floor(((contentW - twoThird) - iconSzClock) / 2);
                local gy = clockY + math.floor((clockH - iconSzClock) / 2);
                DrawGearIcon(gx, gy, iconSzClock);
            end
        elseif ltStr ~= '' then
            local halfW = contentW / 2;
            local vtX   = cx0 + math.floor((halfW - vtMeasW) / 2);
            local ltX   = cx0 + halfW + math.floor((halfW - ltMeasW) / 2);
            DrawTextWithOutline(drawList, vtStr, vtX, vtTextY, vtTextColor, outlineArgb, vtFontSize);
            DrawTodIcon(vtX);
            DrawTextWithOutline(drawList, ltStr, ltX, ltTextY, colorCfg.textColor or 0xFFFFFFFF, outlineArgb, fontSize);
            DrawClockTooltips(vtX, ltX);
            if showGear then
                DrawGearIcon(cx0 + contentW - iconSzClock, clockY + math.floor((clockH - iconSzClock) / 2), iconSzClock);
            end
        else
            local twoThird = showGear and math.floor(contentW * 2 / 3) or contentW;
            local vtX = cx0 + math.floor((twoThird - vtMeasW) / 2);
            DrawTextWithOutline(drawList, vtStr, vtX, vtTextY, vtTextColor, outlineArgb, vtFontSize);
            DrawTodIcon(vtX);
            DrawClockTooltips(vtX, nil);
            if showGear then
                local gx = cx0 + twoThird + math.floor(((contentW - twoThird) - iconSzClock) / 2);
                local gy = clockY + math.floor((clockH - iconSzClock) / 2);
                DrawGearIcon(gx, gy, iconSzClock);
            end
        end

        -- ── Day columns ──────────────────────────────────────────────────────
        local colY   = cy0 + clockH + colPad;
        local cardX0 = cx0;
        local unixNow = data.GetUnixTime();
        local dayRem  = rawTime % data.VD_DAY_SEC;
        local function DayStart(delta)
            return unixNow - dayRem + delta * data.VD_DAY_SEC;
        end
        local function Wrap(n, m)
            return (n % m + m) % m;
        end
        local function DayTimeLabel(delta)
            if delta == 0 then return nil; end
            return FormatLocalTime(DayStart(delta));
        end
        local function DrawSepArrow(ax, rowY)
            local arrImgH = math.floor(iconColH * 0.75);
            local arrY = rowY + math.floor((iconColH - arrImgH) / 2);
            local arrTex = GetTexPtr(arrowRightTex);
            if arrTex then
                DLImage(drawList, arrTex, ax, arrY, ax + sepArrowW, arrY + arrImgH, ToU32(0xC0FFFFFF));
            else
                DrawTextWithOutline(drawList, COL_ARROW, ax, rowY + math.floor((iconColH - dayFontSize) / 2),
                    0xFFFFFFFF, 0xFF000000, dayFontSize);
            end
        end
        local function PaintDay(delta, x, y, alpha, withTime)
            local wd = Wrap(weekday + delta, 8);
            local md = Wrap(moonDay + delta, data.VD_MOON_DAYS);
            local pct = data.CalcMoonPercent(md);
            local startAt = DayStart(delta);
            local label = withTime and DayTimeLabel(delta) or nil;
            local dcx, dcy, dcw, dch = DrawDayColumn(drawList, x, y, wd,
                pct, md, alpha,
                dayIconSize, dayFontSize, colorCfg, showMoon, showBadge, plainDayIcons, label, dayScale);
            DrawDayColumnTooltip(drawList, dcx, dcy, dcw, dch, wd, md, pct, startAt, delta);
        end

        if weekOpen then
            local rowPitch = singleColH + CARD_PAD * 2 + weekGap;
            local colPitch = cardW + SEP_GAP * 2 + sepArrowW;
            for i = 0, 7 do
                local col = i % WEEK_COLS;
                local row = math.floor(i / WEEK_COLS);
                local x = cardX0 + CARD_PAD + col * colPitch;
                local y = colY + row * rowPitch;
                PaintDay(i, x, y, 1.0, true);
                if col < WEEK_COLS - 1 then
                    DrawSepArrow(x + colContentW + CARD_PAD + SEP_GAP, y);
                end
            end
        elseif showPastFuture then
            local pastX = cardX0 + CARD_PAD;
            PaintDay(-1, pastX, colY, pastFutureAlpha, false);

            local arr1X = pastX + colContentW + CARD_PAD + SEP_GAP;
            DrawSepArrow(arr1X, colY);

            local curX = arr1X + sepArrowW + SEP_GAP + CARD_PAD;
            PaintDay(0, curX, colY, 1.0, false);

            local arr2X = curX + colContentW + CARD_PAD + SEP_GAP;
            DrawSepArrow(arr2X, colY);

            local futX = arr2X + sepArrowW + SEP_GAP + CARD_PAD;
            PaintDay(1, futX, colY, pastFutureAlpha, false);
        else
            local cardOffX = math.floor((contentW - cardW) / 2);
            PaintDay(0, cardX0 + cardOffX + CARD_PAD, colY, 1.0, false);
        end

        -- LT below day columns when past/future is hidden
        if ltBelowColumns and ltStr ~= '' then
            local ltY = colY + colH + 2;
            local ltX = cx0 + math.floor((contentW - ltMeasW) / 2);
            DrawTextWithOutline(drawList, ltStr, ltX, ltY, colorCfg.textColor or 0xFFFFFFFF, outlineArgb, fontSize);
            if cfg.vanaTimeEnableTooltips ~= false and cfg.vanaTimeTipLT ~= false then
                if imgui.IsMouseHoveringRect({ltX,ltY},{ltX+ltMeasW,ltY+ltRowH}) then
                    imgui.SetTooltip('Local Time');
                end
            end
        end
        end -- showFull

        -- Upward expand keeps the bar's bottom edge fixed, so the full window
        -- grows above it. A drag while the height is steady updates that edge.
        local expandUp = cfg.vanaTimeMinimalist == true
            and (cfg.vanaTimeMinimalExpandDir or 'down') == 'up';
        if expandUp and laidOutContentH > 0 then
            local x, y = imgui.GetWindowPos();
            local winH = laidOutContentH + colPad * 2;
            if expandAnchorBottom ~= nil and lastExpandContentH ~= nil
                and lastExpandContentH ~= laidOutContentH then
                local newY = expandAnchorBottom - winH;
                imgui.SetWindowPos({ x, newY }, ImGuiCond_Always);
                y = newY;
                mainWinPos.x = x;
                mainWinPos.y = y;
                mainWinSize.h = winH;
            end
            expandAnchorBottom = y + winH;
            lastExpandContentH = laidOutContentH;
        else
            expandAnchorBottom = nil;
            lastExpandContentH = nil;
        end

        mainHoveredThisFrame = imgui.IsWindowHovered(MINIMAL_HOVER_FLAGS);
    end -- visible
    end);
    if not ok then
        error(err);
    end

    DrawDayColumnTooltipWindow();

    if showFull then
    -- ── Popup stacking offsets ────────────────────────────────────────────────
    local todEnabled    = cfg.vanaTimeTodPopup == true;

    local weatherTestId    = nil;
    local weatherTestAlpha = 1.0;
    if cfg.vanaTimeShowWeather ~= false and cfg.vanaTimeWeatherHideNonElemental then
        if NowSeconds() < (_G.XIUI_weatherTestExpiry or 0) then
            weatherTestId    = 4;  -- Hot Spell / Fire (first elemental in HorizonXI ordering)
            weatherTestAlpha = 0.35 + 0.65 * GetMoonPulse();
        end
    else
        _G.XIUI_weatherTestExpiry = 0;
    end

    local weatherEnabled = (cfg.vanaTimeShowWeather ~= false
        and weatherId >= 0
        and not (cfg.vanaTimeWeatherHideNonElemental and weatherId < 4))
        or (weatherTestId ~= nil);
    local todSide    = cfg.vanaTimeTodSide     or 'left';
    local weatherSide = cfg.vanaTimeWeatherSide or 'right';
    local sameSide   = todEnabled and weatherEnabled and (todSide == weatherSide);

    local weatherOffX, weatherOffY = 0, 0;
    local todAlignForce, weatherAlignForce = nil, nil;
    if sameSide then
        local _, cachedTodH = popups.GetCachedTodSize();
        if todSide == 'left' or todSide == 'right' then
            weatherOffY = cachedTodH + WEATHER_POPUP_GAP;
        else
            local todAlign     = cfg.vanaTimeTodAlign     or 'left';
            local weatherAlign = cfg.vanaTimeWeatherAlign or 'left';
            if todAlign == weatherAlign then
                local cachedTodW, _ = popups.GetCachedTodSize();
                todAlignForce = todAlign;
                if todAlign == 'right' then
                    weatherAlignForce = 'right';
                    weatherOffX = -(cachedTodW + WEATHER_POPUP_GAP);
                else
                    weatherAlignForce = 'left';
                    weatherOffX = cachedTodW + WEATHER_POPUP_GAP;
                end
            end
        end
    end

    -- Per-popup icon sizes
    local todIconSize;
    if cfg.vanaTimeTodCustomScale then
        todIconSize = math.floor(math.max(16, math.min(128, cfg.vanaTimeTodIconSize or 28)) * scale);
    else
        todIconSize = iconSize;
    end

    -- Nil follows the main window scale. A stored value sizes only the zone weather tab.
    local weatherScale = scale;
    local weatherScaleSetting = tonumber(cfg.vanaTimeWeatherScale);
    if weatherScaleSetting then
        weatherScale = math.max(0.5, math.min(4.0, weatherScaleSetting));
    end

    local weatherBaseSize;
    if cfg.vanaTimeWeatherCustomScale then
        weatherBaseSize = math.floor(math.max(16, math.min(128, cfg.vanaTimeWeatherIconSize or 28)) * weatherScale);
    else
        weatherBaseSize = math.floor(math.max(16, math.min(128, cfg.vanaTimeIconSize or 28)) * weatherScale);
    end
    local effectiveWeatherId = weatherTestId or weatherId;
    local useElementalSize = cfg.vanaTimeWeatherAdjustElemental == true
        or cfg.vanaTimeWeatherHideNonElemental == true;
    local weatherIconSize = weatherBaseSize;
    if useElementalSize then
        local isElemental   = weatherEnabled and effectiveWeatherId >= 4;
        local previewElem   = _G.XIUI_weatherElementalPreview == true;
        local previewBase   = _G.XIUI_weatherBasePreview == true;
        if previewBase then
            weatherIconSize = weatherBaseSize;
        elseif isElemental or previewElem then
            if cfg.vanaTimeWeatherCustomScale then
                weatherIconSize = math.floor(math.max(16, math.min(128, cfg.vanaTimeWeatherElementalIconSize or 42)) * weatherScale);
            else
                weatherIconSize = math.min(math.floor(weatherBaseSize * 1.5), math.floor(128 * weatherScale));
            end
        end
    end

    if todEnabled then
        popups.DrawTodPopup(vtHour, vtMinuteOfDay, todIconSize, colorCfg, rounding, todAlignForce);
    end
    if weatherEnabled then
        popups.DrawWeatherPopup(weatherTestId or weatherId, fontSize, weatherIconSize,
            colorCfg, rounding, weatherOffX, weatherOffY, weatherAlignForce, weatherTestAlpha);
    end

    if showTimers and popups.IsTimersOpen() then
        local timersFontSize = math.floor(math.max(8, math.min(48, cfg.vanaTimeTimersFontSize or 12)) * scale);
        popups.DrawTimersPopup(timersFontSize, colorCfg, rounding);
    end
    end -- showFull

    local hovered = mainHoveredThisFrame or popups.AttachedHovered();
    UpdateMinimalMode(cfg, hovered);
end

return M;
