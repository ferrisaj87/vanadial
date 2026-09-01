--[[
* Vana'Dial Sunbreeze Racing event window.
*
* The schedule repeats every six Vana'diel hours:
*   Taking Bets        : 05:00-06:00, 11:00-12:00, 17:00-18:00, 23:00-00:00
*   Racing In Progress : 06:00-09:00, 12:00-15:00, 18:00-21:00, 00:00-03:00
*   Collect Rewards    : 09:00-11:00, 15:00-17:00, 21:00-23:00, 03:00-05:00
]]--

require('common');
local bit    = require('bit');
local imgui  = require('imgui');
local imtext = require('libs.imtext');
local data   = require('data');
local Safe   = require('libs.imgui_safe');

local M = {};

local WINDOW_KEY = 'SunbreezeRace';
local WINDOW_NAME = 'Sunbreeze Racing##standalone';

local VD_CYCLE_SEC = 6 * data.VD_HOUR_SEC;
local BETTING_SEC  = 1 * data.VD_HOUR_SEC;
local RACING_SEC   = 3 * data.VD_HOUR_SEC;
local REWARDS_SEC  = 2 * data.VD_HOUR_SEC;
local ANCHOR_SEC   = 5 * data.VD_HOUR_SEC;

local COLOR_GOLD   = { 0.957, 0.855, 0.592, 1.00 };
local COLOR_LABEL  = { 0.667, 0.667, 0.667, 1.00 };
local COLOR_WHITE  = { 1.000, 1.000, 1.000, 1.00 };
local COLOR_GREEN  = { 0.300, 0.900, 0.350, 1.00 };
local COLOR_YELLOW = { 1.000, 0.900, 0.200, 1.00 };
local COLOR_ORANGE = { 1.000, 0.500, 0.100, 1.00 };
local COLOR_RED    = { 1.000, 0.150, 0.120, 1.00 };
local COLOR_RED_DIM = { 0.550, 0.030, 0.020, 1.00 };
local COLOR_GREEN_DIM = { 0.030, 0.400, 0.080, 1.00 };
local COLOR_SECTION_BORDER = { 0.800, 0.670, 0.310, 0.85 };

local WIN_FLAGS = bit.bor(
    ImGuiWindowFlags_NoDecoration,
    ImGuiWindowFlags_AlwaysAutoResize,
    ImGuiWindowFlags_NoFocusOnAppearing,
    ImGuiWindowFlags_NoNav,
    ImGuiWindowFlags_NoDocking,
    ImGuiWindowFlags_NoSavedSettings
);

local isOpen = false;
local defaultPositionPending = true;

local function FormatCountdown(seconds)
    seconds = math.max(0, math.ceil(seconds));
    local minutes = math.floor(seconds / 60);
    local secs = seconds % 60;
    return string.format('%dm %02ds', minutes, secs);
end

local function GetScheduleState(rawTime)
    local secondsIntoCycle = (rawTime - ANCHOR_SEC) % VD_CYCLE_SEC;

    if secondsIntoCycle < BETTING_SEC then
        return 'Taking Bets', 'Racing In Progress',
            BETTING_SEC - secondsIntoCycle, BETTING_SEC;
    end

    if secondsIntoCycle < BETTING_SEC + RACING_SEC then
        return 'Racing In Progress', 'Collect Rewards',
            BETTING_SEC + RACING_SEC - secondsIntoCycle, RACING_SEC;
    end

    return 'Collect Rewards', 'Taking Bets',
        VD_CYCLE_SEC - secondsIntoCycle, REWARDS_SEC;
end

local function GetCountdownColor(remaining, duration)
    local fraction = duration > 0 and (remaining / duration) or 0;
    if fraction <= 0.05 then
        local tick = data.GetTickMs and data.GetTickMs() or nil;
        local bright = tick and (math.floor(tick / 350) % 2 == 0)
            or (math.floor(os.clock() * 3) % 2 == 0);
        if bright then
            return COLOR_RED;
        end
        return COLOR_RED_DIM;
    elseif fraction <= 0.25 then
        return COLOR_ORANGE;
    elseif fraction <= 0.50 then
        return COLOR_YELLOW;
    end
    return COLOR_GREEN;
end

local function GetCurrentTimerColor(remaining, duration)
    local fraction = duration > 0 and (remaining / duration) or 0;
    if fraction <= 0.05 then
        local tick = data.GetTickMs and data.GetTickMs() or nil;
        local bright = tick and (math.floor(tick / 350) % 2 == 0)
            or (math.floor(os.clock() * 3) % 2 == 0);
        return bright and COLOR_GREEN or COLOR_GREEN_DIM;
    elseif fraction <= 0.25 then
        return COLOR_YELLOW;
    elseif fraction <= 0.50 then
        return COLOR_ORANGE;
    end
    return COLOR_RED;
end

local function CenterText(text, color)
    local available = imgui.GetContentRegionAvail();
    local textWidth = imgui.CalcTextSize(text);
    if available > textWidth then
        imgui.SetCursorPosX(imgui.GetCursorPosX() + (available - textWidth) * 0.5);
    end
    if color then
        imgui.TextColored(color, text);
    else
        imgui.Text(text);
    end
end

function M.Toggle()
    isOpen = not isOpen;
    if isOpen then
        defaultPositionPending = true;
    end
    return isOpen;
end

function M.IsOpen()
    return isOpen;
end

function M.ResetPosition()
    if not gConfig then return; end
    if not gConfig.windowPositions then gConfig.windowPositions = T{}; end
    gConfig.windowPositions[WINDOW_KEY] = T{ x = 450, y = 100 };
    if not gConfig.appliedPositions then gConfig.appliedPositions = T{}; end
    gConfig.appliedPositions[WINDOW_KEY] = nil;
    defaultPositionPending = true;
end

function M.Draw()
    if not isOpen or not gConfig then return; end

    local cfg = gConfig;
    local scale = math.max(0.5, math.min(4.0, tonumber(cfg.vanaTimeScale) or 1.0));
    local baseFontSize = math.max(8, math.min(48, tonumber(cfg.vanaTimeFontSize) or 12));
    local fontSize = math.floor(baseFontSize * scale);
    local paddingX = math.floor(12 * scale);
    local paddingY = math.floor(10 * scale);
    local minWidth = math.floor(210 * scale);

    imtext.SetConfig('Tahoma', cfg.vanaTimeFontBold ~= false, 1);

    local ok, err = Safe.Run(function(scope)
        scope:PushStyleVar(ImGuiStyleVar_WindowRounding, 8 * scale);
        scope:PushStyleVar(ImGuiStyleVar_WindowPadding, { paddingX, paddingY });
        scope:PushStyleVar(ImGuiStyleVar_WindowMinSize, { minWidth, 0 });
        scope:PushStyleColor(ImGuiCol_WindowBg, { 0.02, 0.02, 0.03, 0.92 });
        scope:PushStyleColor(ImGuiCol_Border, { 0.80, 0.67, 0.31, 0.90 });

        local applied = ApplyWindowPosition(WINDOW_KEY);
        if not applied and defaultPositionPending then
            imgui.SetNextWindowPos({ 450, 100 }, ImGuiCond_Once);
        end
        defaultPositionPending = false;

        local font = imtext.GetFont();
        if font then
            scope:PushFont(font, fontSize);
        end

        local visible = scope:BeginWindow(WINDOW_NAME, true, WIN_FLAGS);
        if visible then
            SaveWindowPosition(WINDOW_KEY);

            local status, nextStatus, remaining, duration =
                GetScheduleState(data.GetRawTime());
            local nextTimerColor = GetCountdownColor(remaining, duration);
            local currentTimerColor = GetCurrentTimerColor(remaining, duration);
            local timerText = FormatCountdown(remaining);

            CenterText('Sunbreeze Racing', COLOR_GOLD);
            imgui.Separator();

            local sectionX, sectionY = imgui.GetCursorScreenPos();
            local sectionWidth = imgui.GetContentRegionAvail();
            imgui.Dummy({ 0, math.max(2, math.floor(3 * scale)) });
            CenterText('Current', COLOR_LABEL);
            CenterText(status, COLOR_WHITE);
            CenterText(timerText, currentTimerColor);
            imgui.Dummy({ 0, math.max(2, math.floor(3 * scale)) });
            local _, sectionBottom = imgui.GetCursorScreenPos();
            imgui.GetWindowDrawList():AddRect(
                { sectionX, sectionY },
                { sectionX + sectionWidth, sectionBottom },
                imgui.GetColorU32(COLOR_SECTION_BORDER),
                5 * scale, nil, math.max(1, scale));

            imgui.Spacing();

            local italicMark = scope:Mark();
            local italicFont = imtext.GetItalicFont('Arial');
            if italicFont then scope:PushFont(italicFont, fontSize); end
            CenterText('Next: ' .. nextStatus, COLOR_LABEL);
            CenterText(timerText, nextTimerColor);
            scope:CloseTo(italicMark);
        end
    end);

    if not ok then
        error(err);
    end
end

-- Exposed for schedule verification without changing the shared clock module.
M.GetScheduleState = GetScheduleState;

return M;
