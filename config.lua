--[[
* Vana'Dial - Standalone Configuration Window
*
* Draws a self-contained ImGui settings window.
* Called from vanadial.lua each frame when _configOpen is true.
]]--

require('common');
local settings = require('settings');
local imgui    = require('imgui');

local M = {};

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function Tip(text)
    if imgui.IsItemHovered() then
        imgui.BeginTooltip();
        imgui.PushTextWrapPos(imgui.GetFontSize() * 28);
        imgui.TextUnformatted(text);
        imgui.PopTextWrapPos();
        imgui.EndTooltip();
    end
end

-- Checkbox bound to gConfig[key]. Returns true when value changed.
local function CB(label, key)
    local v = T{ gConfig[key] == true };
    if imgui.Checkbox(label, v) then
        gConfig[key] = v[1];
        settings.save();
        return true;
    end
    return false;
end

-- SliderFloat bound to gConfig[key].
local function SF(label, key, vmin, vmax, fmt, reset)
    local v = T{ tonumber(gConfig[key]) or reset };
    if imgui.SliderFloat(label, v, vmin, vmax, fmt or '%.2f') then
        gConfig[key] = v[1];
        settings.save();
    end
    if imgui.IsItemHovered() and imgui.IsMouseDoubleClicked(1) then
        gConfig[key] = reset;
        settings.save();
    end
end

-- SliderInt bound to gConfig[key].
local function SI(label, key, vmin, vmax, reset)
    local v = T{ math.floor(tonumber(gConfig[key]) or reset) };
    if imgui.SliderInt(label, v, vmin, vmax) then
        gConfig[key] = v[1];
        settings.save();
    end
    if imgui.IsItemHovered() and imgui.IsMouseDoubleClicked(1) then
        gConfig[key] = reset;
        settings.save();
    end
end

-- Combo widths (match XIUI config/vanatime.lua).
local COMBO_WIDTH_SIDE  = 90;
local COMBO_WIDTH_ALIGN = 72;
local COMBO_WIDTH_DIR   = 90;

-- String enum via BeginCombo/Selectable (Ashita's imgui.Combo table form renders
-- invisible list text and stretches to the full content width).
local function Combo(label, key, labels, values, default, width)
    local current = gConfig[key] or default;
    local currentLabel = labels[1];
    for i, v in ipairs(values) do
        if v == current then
            currentLabel = labels[i];
            break;
        end
    end

    imgui.SetNextItemWidth(width or COMBO_WIDTH_SIDE);
    if imgui.BeginCombo(label, currentLabel) then
        for i, itemLabel in ipairs(labels) do
            local itemValue = values[i];
            local isSelected = (itemValue == current);
            if imgui.Selectable(itemLabel, isSelected) then
                gConfig[key] = itemValue;
                settings.save();
            end
            if isSelected then
                imgui.SetItemDefaultFocus();
            end
        end
        imgui.EndCombo();
    end
end

-- ARGB <-> ImGui float[4] conversion helpers.
local function ArgbToFloat4(argb)
    local a = bit.band(bit.rshift(argb, 24), 0xFF) / 255.0;
    local r = bit.band(bit.rshift(argb, 16), 0xFF) / 255.0;
    local g = bit.band(bit.rshift(argb,  8), 0xFF) / 255.0;
    local b = bit.band(argb, 0xFF)                 / 255.0;
    return T{ r, g, b, a };
end

local function Float4ToArgb(f)
    local a = math.floor(math.min(math.max(f[4], 0), 1) * 255 + 0.5);
    local r = math.floor(math.min(math.max(f[1], 0), 1) * 255 + 0.5);
    local g = math.floor(math.min(math.max(f[2], 0), 1) * 255 + 0.5);
    local b = math.floor(math.min(math.max(f[3], 0), 1) * 255 + 0.5);
    return bit.bor(
        bit.lshift(a, 24),
        bit.lshift(r, 16),
        bit.lshift(g,  8),
        b
    );
end

local function ColorPicker(label, colorCfg, key, tip)
    local f = ArgbToFloat4(tonumber(colorCfg[key]) or 0xFFFFFFFF);
    if imgui.ColorEdit4(label, f, ImGuiColorEditFlags_AlphaBar) then
        colorCfg[key] = Float4ToArgb(f);
        settings.save();
    end
    if tip then Tip(tip); end
end

local SIDE_LABELS  = T{'Right', 'Left', 'Above', 'Below'};
local SIDE_VALUES  = T{'right', 'left',  'above', 'below'};
local ALIGN_LABELS = T{'Left', 'Right'};
local ALIGN_VALUES = T{'left', 'right'};
local DIR_LABELS   = T{'Above', 'Below'};
local DIR_VALUES   = T{'above', 'below'};

-- Chat commands (shown on the Commands tab; keep in sync with vanadial.lua).
local VD_COMMANDS = {
    { '/vd',        "Toggle Vana'Dial visibility (show or hide the clock)." },
    { '/vanadial',  'Alias for /vd.' },
    { '/vd config', 'Open or close this settings window.' },
    { '/vd ships',  'Open the timers popup with Airships expanded. Other timer sections are collapsed. Run again to close the popup.' },
    { '/vd boats',  'Open the timers popup with Boats expanded (including all sub-routes). Other sections are collapsed. Run again to close the popup.' },
    { '/vd rse',    'Open the timers popup with RSE expanded. Other sections are collapsed. Run again to close the popup.' },
    { '/vd lunar',  'Open the timers popup with Lunar Phases expanded. Other sections are collapsed. Run again to close the popup.' },
    { '/vd reset',  "Reset the main Vana'Dial window position to the default (100, 100)." },
    { '/vd update', 'Pull the latest version from GitHub (requires a git clone). Reload with /addon reload vanadial after.' },
    { '/vd checkupdate', 'Check GitHub for a newer release without downloading.' },
};

-- ── Theme ───────────────────────────────────────────────────────────────────
-- The config window must NOT inherit the global ImGui style (which on this
-- client is a low-contrast red/black theme that makes text unreadable and combo
-- dropdowns blend into the background). We push a self-contained dark + gold
-- theme around the whole window so it renders identically regardless of whatever
-- global style another addon installed. Built once at module load; the ImGuiCol_*
-- constants are guaranteed present because vanadial.lua requires imgui_compat
-- before this file.
local GOLD       = {0.78, 0.69, 0.46, 1.00};
local GOLD_HOVER = {0.90, 0.81, 0.57, 1.00};
local WHITE      = {0.92, 0.92, 0.93, 1.00};

local THEME_COLORS = {
    { ImGuiCol_WindowBg,            {0.06, 0.07, 0.10, 0.98} },
    { ImGuiCol_ChildBg,             {0.00, 0.00, 0.00, 0.00} },
    { ImGuiCol_PopupBg,             {0.08, 0.09, 0.13, 0.99} },
    { ImGuiCol_Border,              {0.30, 0.33, 0.40, 0.85} },
    { ImGuiCol_Text,                WHITE },
    { ImGuiCol_TextDisabled,        {0.60, 0.61, 0.66, 1.00} },
    { ImGuiCol_FrameBg,             {0.13, 0.15, 0.20, 1.00} },
    { ImGuiCol_FrameBgHovered,      {0.19, 0.22, 0.28, 1.00} },
    { ImGuiCol_FrameBgActive,       {0.24, 0.27, 0.34, 1.00} },
    { ImGuiCol_TitleBg,             {0.08, 0.09, 0.13, 1.00} },
    { ImGuiCol_TitleBgActive,       {0.15, 0.17, 0.22, 1.00} },
    { ImGuiCol_TitleBgCollapsed,    {0.08, 0.09, 0.13, 0.80} },
    { ImGuiCol_Header,              {0.20, 0.23, 0.30, 1.00} },
    { ImGuiCol_HeaderHovered,       {0.28, 0.31, 0.39, 1.00} },
    { ImGuiCol_HeaderActive,        {0.33, 0.36, 0.44, 1.00} },
    { ImGuiCol_Button,              {0.18, 0.21, 0.27, 1.00} },
    { ImGuiCol_ButtonHovered,       {0.27, 0.30, 0.38, 1.00} },
    { ImGuiCol_ButtonActive,        {0.34, 0.37, 0.46, 1.00} },
    { ImGuiCol_CheckMark,           GOLD },
    { ImGuiCol_SliderGrab,          GOLD },
    { ImGuiCol_SliderGrabActive,    GOLD_HOVER },
    { ImGuiCol_Tab,                 {0.12, 0.14, 0.19, 1.00} },
    { ImGuiCol_TabHovered,          {0.30, 0.27, 0.18, 1.00} },
    { ImGuiCol_TabActive,           {0.26, 0.24, 0.16, 1.00} },
    { ImGuiCol_TabUnfocused,        {0.10, 0.11, 0.15, 1.00} },
    { ImGuiCol_TabUnfocusedActive,  {0.17, 0.18, 0.16, 1.00} },
    { ImGuiCol_Separator,           {0.30, 0.33, 0.40, 0.55} },
    { ImGuiCol_ScrollbarBg,         {0.05, 0.06, 0.09, 0.50} },
    { ImGuiCol_ScrollbarGrab,       {0.24, 0.27, 0.33, 1.00} },
    { ImGuiCol_ScrollbarGrabHovered,{0.30, 0.33, 0.40, 1.00} },
};

local THEME_VARS = {
    { ImGuiStyleVar_WindowRounding, 6.0 },
    { ImGuiStyleVar_FrameRounding,  4.0 },
    { ImGuiStyleVar_TabRounding,    4.0 },
    { ImGuiStyleVar_WindowPadding,  {12, 12} },
    { ImGuiStyleVar_ItemSpacing,    {8, 6} },
    { ImGuiStyleVar_FramePadding,   {7, 4} },
};

local _pushedColors = 0;
local _pushedVars   = 0;

local function PushTheme()
    _pushedColors = 0;
    for _, c in ipairs(THEME_COLORS) do
        if c[1] ~= nil then
            imgui.PushStyleColor(c[1], c[2]);
            _pushedColors = _pushedColors + 1;
        end
    end
    _pushedVars = 0;
    for _, v in ipairs(THEME_VARS) do
        if v[1] ~= nil then
            imgui.PushStyleVar(v[1], v[2]);
            _pushedVars = _pushedVars + 1;
        end
    end
end

local function PopTheme()
    if _pushedVars   > 0 then imgui.PopStyleVar(_pushedVars);     end
    if _pushedColors > 0 then imgui.PopStyleColor(_pushedColors); end
    _pushedVars   = 0;
    _pushedColors = 0;
end

-- ── Draw ──────────────────────────────────────────────────────────────────────

-- @param openFlag bool - whether the window is currently open
-- @param setOpen  fn(bool) - callback to update open state
function M.Draw(openFlag, setOpen)
    PushTheme();
    imgui.SetNextWindowSize(T{520, 600}, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSizeConstraints(T{420, 300}, T{900, 1200});
    local open = T{ openFlag };
    -- Never call imgui.End() when Begin returns false — that corrupts ImGui's stack
    -- and can crash the client when the window is closed or collapsed.
    if imgui.Begin("Vana'Dial Settings##standalone", open, ImGuiWindowFlags_None) then

    local colorCfg = gConfig.colorCustomization and gConfig.colorCustomization.vanaTime;

    -- Per-frame weather preview reset (mirrors config/vanatime.lua behaviour).
    _G.XIUI_weatherElementalPreview = false;
    _G.XIUI_weatherBasePreview      = false;

    if imgui.BeginTabBar('##vt_cfg_tabs') then

        -- ── General tab ───────────────────────────────────────────────────────
        if imgui.BeginTabItem('General') then

            CB('Enabled', 'showVanaDial');
            CB('Hide When Menu Open', 'vanaTimeHideOnMenuFocus');
            Tip('Hide this module when a game menu is open (equipment, map, etc.).');
            imgui.Indent(16);
            CB('Hide When Chat Log Expanded', 'vanaTimeHideOnChatExpanded');
            Tip("Hide when the chat scrollback window is expanded. Does not hide while typing in chat.");
            imgui.Unindent(16);
            CB('Display Settings Button', 'vanaTimeShowSettingsBtn');
            Tip("Show a gear icon on the Vana'Dial module that opens these settings directly.");

            imgui.Spacing(); imgui.Separator(); imgui.Spacing();

            -- Scaling & Layout
            if imgui.CollapsingHeader('Scaling & Layout##vt', ImGuiTreeNodeFlags_DefaultOpen) then
                imgui.Indent(12);
                SF('Scale##vt',     'vanaTimeScale',    0.5, 2.0, '%.2f', 1.0);
                Tip("Global scale for the entire Vana'Dial window. Double right-click to reset.");
                SI('Font Size##vt', 'vanaTimeFontSize',  8, 24, 12);
                Tip("Font size for clock and moon phase text. Double right-click to reset.");
                CB('Bold Font##vt', 'vanaTimeFontBold');
                Tip('Use Tahoma Bold for clock text (matches XIUI default fontWeight). Turn off if your XIUI global font is Normal.');
                SI('Icon Size##vt', 'vanaTimeIconSize',  16, 64, 28);
                Tip("Size of element day icons in pixels. Double right-click to reset.");
                imgui.Unindent(12);
            end

            imgui.Spacing();

            -- Display Options
            if imgui.CollapsingHeader('Display Options##vt', ImGuiTreeNodeFlags_DefaultOpen) then
                imgui.Indent(12);
                CB('VT Time matches Element Color', 'vanaTimeVTElementColor');
                Tip("Tint the Vana'diel Time clock text with the current day's element color.");
                CB('Show Local Time (LT)', 'vanaTimeShowLocalTime');
                imgui.SameLine(0, 16);
                CB('Show Moon Phase %', 'vanaTimeShowMoonPercent');
                Tip('Show moon phase percentage and waxing/waning arrow under each day icon.');
                CB('Show Past / Future Days', 'vanaTimeShowPastFuture');
                Tip('Show yesterday and tomorrow columns at reduced opacity on either side of today.');
                if gConfig.vanaTimeShowPastFuture ~= false then
                    imgui.Indent(16);
                    SF('Past / Future Opacity', 'vanaTimePastFutureOpacity', 0.0, 1.0, '%.2f', 0.35);
                    Tip('Opacity of past and future day columns. Double right-click to reset.');
                    imgui.Unindent(16);
                end
                CB('Plain Day Icons (no element texture)', 'vanaTimePlainDayIcons');
                Tip('Replace the elemental icon with a solid fill of the element color.');
                CB('Show Weakness Badge', 'vanaTimeShowWeaknessBadge');
                Tip('Show the elemental weakness icon as a small badge in the corner of each day icon.');
                imgui.Unindent(12);
            end

            imgui.Spacing();

            -- Background
            if imgui.CollapsingHeader('Background##vt', 0) then
                imgui.Indent(12);
                SF('Background Opacity##vt', 'vanaTimeBackgroundOpacity', 0.0, 1.0, '%.2f', 0.85);
                Tip('Multiplies Background Tint transparency on the main bar and TOD/Weather popups. Double right-click to reset.');
                SF('Border Opacity##vt', 'vanaTimeBorderOpacity', 0.0, 1.0, '%.2f', 1.0);
                Tip('Opacity of window borders. Double right-click to reset.');
                imgui.Unindent(12);
            end

            imgui.EndTabItem();
        end

        -- ── Panels tab ────────────────────────────────────────────────────────
        if imgui.BeginTabItem('Panels') then

            -- Time of Day
            if imgui.CollapsingHeader('Time of Day Tab##vt', ImGuiTreeNodeFlags_DefaultOpen) then
                imgui.Indent(12);
                CB('Enable TOD Tab', 'vanaTimeTodPopup');
                Tip('Show the time-of-day icon (Day / Night / Dead of Night) in a floating tab.');
                if gConfig.vanaTimeTodPopup ~= false then
                    imgui.Indent(16);
                    imgui.Text('Side:');
                    imgui.SameLine(0, 8);
                    Combo('##vanaTimeTodSide', 'vanaTimeTodSide', SIDE_LABELS, SIDE_VALUES, 'left', COMBO_WIDTH_SIDE);
                    local todSide = gConfig.vanaTimeTodSide or 'left';
                    if todSide == 'above' or todSide == 'below' then
                        imgui.SameLine(0, 4);
                        Combo('Align##tod', 'vanaTimeTodAlign', ALIGN_LABELS, ALIGN_VALUES, 'left', COMBO_WIDTH_ALIGN);
                        Tip('Horizontal alignment when TOD tab is placed above or below.');
                    end
                    CB('Individual Scaling##tod', 'vanaTimeTodCustomScale');
                    Tip('Use a separate icon size for the TOD tab.');
                    if gConfig.vanaTimeTodCustomScale then
                        imgui.Indent(16);
                        SI('Icon Size##todIcon', 'vanaTimeTodIconSize', 16, 64, 28);
                        Tip('Size of the TOD icon in pixels. Double right-click to reset.');
                        imgui.Unindent(16);
                    end
                    CB('Show Timer', 'vanaTimeTodShowTimer');
                    Tip('Display a countdown to the next Day / Night / Dead of Night transition.');
                    imgui.Unindent(16);
                end
                imgui.Unindent(12);
            end

            imgui.Spacing();

            -- Weather
            if imgui.CollapsingHeader('Weather Tab##vt', ImGuiTreeNodeFlags_DefaultOpen) then
                imgui.Indent(12);
                local hideNonElem = gConfig.vanaTimeWeatherHideNonElemental == true;
                CB('Enable Weather Tab', 'vanaTimeShowWeather');
                Tip('Show a floating tab with the current zone weather icon.');
                if hideNonElem and gConfig.vanaTimeShowWeather ~= false then
                    imgui.SameLine(0, 8);
                    if imgui.Button('Test Placement##wx') then
                        _G.XIUI_weatherTestExpiry = os.clock() + 30;
                    end
                    Tip('Temporarily shows a blinking weather icon for 30s so you can\nposition the tab without waiting for elemental weather.');
                end
                if gConfig.vanaTimeShowWeather ~= false then
                    imgui.Indent(16);
                    imgui.Text('Side:');
                    imgui.SameLine(0, 8);
                    Combo('##vanaTimeWeatherSide', 'vanaTimeWeatherSide', SIDE_LABELS, SIDE_VALUES, 'right', COMBO_WIDTH_SIDE);
                    local wxSide = gConfig.vanaTimeWeatherSide or 'right';
                    if wxSide == 'above' or wxSide == 'below' then
                        imgui.SameLine(0, 4);
                        Combo('Align##wx', 'vanaTimeWeatherAlign', ALIGN_LABELS, ALIGN_VALUES, 'left', COMBO_WIDTH_ALIGN);
                    end
                    CB('Hide Non-Elemental Weather##wx', 'vanaTimeWeatherHideNonElemental');
                    Tip('Hide the Weather tab during Clear, Sunny, Cloudy, and Fog.');
                    if not hideNonElem then
                        CB('Adjust Size for Elemental Weather##wx', 'vanaTimeWeatherAdjustElemental');
                        Tip('Elemental weather icons display larger than basic weather.');
                    end
                    CB('Individual Scaling##wx', 'vanaTimeWeatherCustomScale');
                    Tip('Use a separate icon size for the Weather tab.');
                    if gConfig.vanaTimeWeatherCustomScale then
                        imgui.Indent(16);
                        if not hideNonElem then
                            local baseLbl = (not hideNonElem and gConfig.vanaTimeWeatherAdjustElemental)
                                and 'Non-Elemental Icon Size##wxIcon'
                                or  'Icon Size##wxIcon';
                            local v = T{ math.floor(tonumber(gConfig.vanaTimeWeatherIconSize) or 28) };
                            if imgui.SliderInt(baseLbl, v, 16, 64) then
                                gConfig.vanaTimeWeatherIconSize = v[1];
                                settings.save();
                            end
                            if imgui.IsItemActive() then _G.XIUI_weatherBasePreview = true; end
                            Tip('Size of non-elemental weather icons. Double right-click to reset.');
                            if imgui.IsItemHovered() and imgui.IsMouseDoubleClicked(1) then
                                gConfig.vanaTimeWeatherIconSize = 28;
                                settings.save();
                            end
                        end
                        if (not hideNonElem and gConfig.vanaTimeWeatherAdjustElemental) or hideNonElem then
                            local elemLbl = hideNonElem
                                and 'Icon Size##wxElemOnly'
                                or  'Elemental Icon Size##wxElem';
                            local v = T{ math.floor(tonumber(gConfig.vanaTimeWeatherElementalIconSize) or 42) };
                            if imgui.SliderInt(elemLbl, v, 16, 64) then
                                gConfig.vanaTimeWeatherElementalIconSize = v[1];
                                settings.save();
                            end
                            if imgui.IsItemActive() then _G.XIUI_weatherElementalPreview = true; end
                            Tip('Size of elemental weather icons. Double right-click to reset.');
                            if imgui.IsItemHovered() and imgui.IsMouseDoubleClicked(1) then
                                gConfig.vanaTimeWeatherElementalIconSize = 42;
                                settings.save();
                            end
                        end
                        imgui.Unindent(16);
                    end
                    imgui.Unindent(16);
                end
                imgui.Unindent(12);
            end

            imgui.Spacing();

            -- Timers
            if imgui.CollapsingHeader('Timers Panel##vt', ImGuiTreeNodeFlags_DefaultOpen) then
                imgui.Indent(12);
                CB('Enable Timers', 'vanaTimeShowTimers');
                Tip('Show a clock icon that opens the transport and RSE timer panel.');
                if gConfig.vanaTimeShowTimers ~= false then
                    imgui.Indent(16);
                    imgui.Text('Side:');
                    imgui.SameLine(0, 8);
                    Combo('##vanaTimeTimerSide', 'vanaTimeTimerSide', DIR_LABELS, DIR_VALUES, 'above', COMBO_WIDTH_DIR);
                    SI('Timers Font Size##vt', 'vanaTimeTimersFontSize', 8, 24, 12);
                    Tip('Font size inside the timers panel. Double right-click to reset.');
                    imgui.Spacing();
                    CB('Auto-Close on Outside Click', 'vanaTimeTimersAutoCloseClick');
                    Tip('Automatically close the Timers panel when you click anywhere outside of it.');
                    CB('Auto-Close on Inactivity', 'vanaTimeTimersAutoCloseIdle');
                    Tip('Automatically close the Timers panel after a period of no interaction.');
                    if gConfig.vanaTimeTimersAutoCloseIdle then
                        imgui.Indent(16);
                        SI('Idle Seconds##vt_timers', 'vanaTimeTimersAutoCloseIdleSec', 1, 60, 5);
                        Tip('Seconds of inactivity before the Timers panel closes. Double right-click to reset.');
                        imgui.Unindent(16);
                    end
                    imgui.Unindent(16);
                end
                imgui.Unindent(12);
            end

            imgui.EndTabItem();
        end

        -- ── Tooltips tab ──────────────────────────────────────────────────────
        if imgui.BeginTabItem('Tooltips') then
            CB('Enable Tooltips', 'vanaTimeEnableTooltips');
            Tip("Master toggle for all hover tooltips in the Vana'Dial module.");
            if gConfig.vanaTimeEnableTooltips ~= false then
                imgui.Indent(12);
                CB('VT Clock##tipvt',   'vanaTimeTipVT');
                imgui.SameLine(0, 8);
                CB('LT Clock##tiplt',   'vanaTimeTipLT');
                imgui.SameLine(0, 8);
                CB('TOD Tab##tiptod',   'vanaTimeTipTod');
                imgui.SameLine(0, 8);
                CB('Weather Tab##tipwx','vanaTimeTipWeather');
                imgui.Spacing();
                CB('Fenrir Details##vt', 'vanaTimeTooltipFenrir');
                Tip('Show Lunar Cry, Ecliptic Howl, and Ecliptic Growl values when hovering a day column.');
                imgui.SameLine(0, 8);
                CB("Selene's Bow##vt", 'vanaTimeTooltipSeleneBow');
                Tip("Show Selene's Bow Ranged Accuracy / Ranged Attack values when hovering a day column.");
                if gConfig.vanaTimeTooltipFenrir or gConfig.vanaTimeTooltipSeleneBow then
                    imgui.Indent(16);
                    imgui.Text('Tooltip direction:');
                    imgui.SameLine(0, 8);
                    Combo('##vanaTimeTooltipDirection', 'vanaTimeTooltipDirection',
                        DIR_LABELS, DIR_VALUES, 'above', COMBO_WIDTH_DIR);
                    Tip("Whether the day column tooltip appears above or below the Vana'Dial window.");
                    imgui.Unindent(16);
                end
                imgui.Unindent(12);
            end
            imgui.EndTabItem();
        end

        -- ── Colors tab ────────────────────────────────────────────────────────
        if imgui.BeginTabItem('Colors') then
            if not colorCfg then
                imgui.TextDisabled('Color config not available.');
            else
                -- Background
                if imgui.CollapsingHeader('Background Colors##vt', ImGuiTreeNodeFlags_DefaultOpen) then
                    imgui.Indent(12);
                    ColorPicker('Background Tint##vt', colorCfg, 'bgColor',
                        "Tint for the main Vana'Dial bar and TOD/Weather popups. Use the A slider in the picker for transparency.");
                    ColorPicker('Border Color##vt', colorCfg, 'borderColor',
                        'Color of window borders.');
                    imgui.Unindent(12);
                end
                imgui.Spacing();
                -- Text
                if imgui.CollapsingHeader('Text Colors##vt', ImGuiTreeNodeFlags_DefaultOpen) then
                    imgui.Indent(12);
                    ColorPicker('General Text / LT Clock##vt', colorCfg, 'textColor',
                        'Color for local time clock and other non-element text.');
                    ColorPicker('TOD Timer Text##vt', colorCfg, 'todTimerColor',
                        'Color for the TOD countdown timer text.');
                    imgui.Unindent(12);
                end
                imgui.Spacing();
                -- Moon glow
                if imgui.CollapsingHeader('Moon Glow##vt', ImGuiTreeNodeFlags_DefaultOpen) then
                    imgui.Indent(12);
                    imgui.TextDisabled('Tint shown behind the moon% text on Full / New Moon.');
                    imgui.Spacing();
                    ColorPicker('Full Moon Glow##vt', colorCfg, 'moonFullColor',
                        'Glow shown behind moon percent on a Full Moon.');
                    ColorPicker('New Moon Glow##vt', colorCfg, 'moonNewColor',
                        'Glow shown behind moon percent on a New Moon.');
                    imgui.Unindent(12);
                end
                imgui.Spacing();
                -- Elements
                if imgui.CollapsingHeader('Element Colors##vt', 0) then
                    imgui.Indent(12);
                    imgui.TextDisabled('These color the VT clock text and day column pill backgrounds.');
                    imgui.TextDisabled('Light group (Fire/Wind/Lightning/Light): black outline + white pill.');
                    imgui.TextDisabled('Dark group  (Ice/Water/Earth/Dark):      white outline + dark pill.');
                    imgui.Spacing();
                    ColorPicker('Fire (Firesday)##vt',          colorCfg, 'elementFire');
                    ColorPicker('Earth (Earthsday)##vt',        colorCfg, 'elementEarth');
                    ColorPicker('Water (Watersday)##vt',        colorCfg, 'elementWater');
                    ColorPicker('Wind (Windsday)##vt',          colorCfg, 'elementWind');
                    ColorPicker('Ice (Iceday)##vt',             colorCfg, 'elementIce');
                    ColorPicker('Lightning (Lightningday)##vt', colorCfg, 'elementLightning');
                    ColorPicker('Light (Lightsday)##vt',        colorCfg, 'elementLight');
                    ColorPicker('Dark (Darksday)##vt',          colorCfg, 'elementDark');
                    imgui.Unindent(12);
                end
            end
            imgui.EndTabItem();
        end

        -- ── Commands tab ──────────────────────────────────────────────────────
        if imgui.BeginTabItem('Commands') then
            imgui.TextWrapped('/vanadial is an alias for /vd. Unknown subcommands print the same list to chat.');
            imgui.Spacing();
            imgui.Separator();
            imgui.Spacing();

            for _, entry in ipairs(VD_COMMANDS) do
                imgui.TextColored(GOLD, entry[1]);
                imgui.Indent(16);
                imgui.TextWrapped(entry[2]);
                imgui.Unindent(16);
                imgui.Spacing();
            end

            imgui.EndTabItem();
        end

        imgui.EndTabBar();
    end

    imgui.End();
    end

    PopTheme();
    if not open[1] then
        setOpen(false);
    end
end

return M;
