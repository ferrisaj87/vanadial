--[[
* ImGui Compatibility Layer for Ashita v4beta
*
* This module provides compatibility between the current Ashita v4beta (main)
* and the upcoming Ashita 4.3 (2025_q3_update branch) which has breaking ImGui changes.
*
* Set _XIUI_USE_ASHITA_4_3 = true in XIUI.lua to enable 4.3 mode.
*
* Changes in 4.3:
*   - BeginChild: cflags default changed, now needs explicit ImGuiChildFlags_Borders
*   - PushStyleColor: idx param no longer optional, nil check needed
*   - ImGuiCol_Tab* constants renamed (TabActive -> TabSelected, etc.)
*   - ImDrawCornerFlags renamed to ImDrawFlags_RoundCorners*
*   - BeginDisabled/EndDisabled: exists in 4.3 (ImGui 1.85+), polyfilled for main
*   - SetWindowFontScale: removed in ImGui 1.92 (Ashita 3.0). Do NOT emulate it
*     with a process-global PushFont stack — that leaks into later addons and
*     crashes Present (often blamed on equipmon/mobdb/checker).
]]--

local imgui = require('imgui');

-- Auto-detect Ashita 4.3 vs main branch based on ImGui constants
-- 4.3 has ImGuiChildFlags_Borders constant, main branch does not
-- Manual override via _XIUI_USE_ASHITA_4_3 global is still supported
local use43 = rawget(_G, '_XIUI_USE_ASHITA_4_3');
if use43 == nil then
    -- Auto-detect: ImGuiChildFlags_Borders exists only in 4.3
    use43 = (ImGuiChildFlags_Borders ~= nil);
end

-- ImDrawCornerFlags -> ImDrawFlags_RoundCorners* aliases
-- 4.3 uses ImDrawFlags_RoundCorners* (new naming), main uses ImDrawCornerFlags_* (old naming)
-- Create aliases so code can use ImDrawCornerFlags_* consistently on both branches
if ImDrawFlags_RoundCornersAll ~= nil then
    -- 4.3 branch: new names exist, create old name aliases pointing to new names
    ImDrawCornerFlags_None = ImDrawFlags_RoundCornersNone;
    ImDrawCornerFlags_TopLeft = ImDrawFlags_RoundCornersTopLeft;
    ImDrawCornerFlags_TopRight = ImDrawFlags_RoundCornersTopRight;
    ImDrawCornerFlags_BotLeft = ImDrawFlags_RoundCornersBottomLeft;
    ImDrawCornerFlags_BotRight = ImDrawFlags_RoundCornersBottomRight;
    ImDrawCornerFlags_Top = ImDrawFlags_RoundCornersTop;
    ImDrawCornerFlags_Bot = ImDrawFlags_RoundCornersBottom;
    ImDrawCornerFlags_Left = ImDrawFlags_RoundCornersLeft;
    ImDrawCornerFlags_Right = ImDrawFlags_RoundCornersRight;
    ImDrawCornerFlags_All = ImDrawFlags_RoundCornersAll;
end
-- On main branch: ImDrawCornerFlags_* already exist natively, no aliases needed

if use43 then
    -- Running on 4.3 branch - add backwards compatibility aliases for old constant names
    -- These were renamed in ImGui 1.90+
    -- Always set fallbacks first, then override with actual values if they exist
    ImGuiCol_Tab = ImGuiCol_Tab or ImGuiCol_Header or 0;
    ImGuiCol_TabHovered = ImGuiCol_TabHovered or ImGuiCol_HeaderHovered or 0;
    ImGuiCol_TabActive = ImGuiCol_HeaderActive or 0;  -- Will be overwritten below if TabSelected exists
    ImGuiCol_TabUnfocused = ImGuiCol_Header or 0;     -- Will be overwritten below if TabDimmed exists
    ImGuiCol_TabUnfocusedActive = ImGuiCol_HeaderActive or 0;  -- Will be overwritten below if TabDimmedSelected exists

    if ImGuiCol_TabSelected ~= nil then
        ImGuiCol_TabActive = ImGuiCol_TabSelected;
        ImGuiCol_TabUnfocused = ImGuiCol_TabDimmed;
        ImGuiCol_TabUnfocusedActive = ImGuiCol_TabDimmedSelected;
    end

else
    -- Running on MAIN branch - apply compatibility shims for 4.3-style code

    -- ImGuiWindowFlags_NoDocking doesn't exist on main branch (added in 4.3)
    -- Define as 0 so bit.bor() calls don't fail
    if ImGuiWindowFlags_NoDocking == nil then
        ImGuiWindowFlags_NoDocking = 0;
    end

    -- Tab color constants may not exist on older main branch versions
    -- Provide fallbacks to prevent nil idx in PushStyleColor which causes push/pop imbalance
    -- We use existing similar constants as fallbacks so styling still works reasonably
    if ImGuiCol_Tab == nil then
        ImGuiCol_Tab = ImGuiCol_Header or 0;
    end
    if ImGuiCol_TabHovered == nil then
        ImGuiCol_TabHovered = ImGuiCol_HeaderHovered or 0;
    end
    if ImGuiCol_TabActive == nil then
        ImGuiCol_TabActive = ImGuiCol_HeaderActive or 0;
    end
    if ImGuiCol_TabUnfocused == nil then
        ImGuiCol_TabUnfocused = ImGuiCol_Header or 0;
    end
    if ImGuiCol_TabUnfocusedActive == nil then
        ImGuiCol_TabUnfocusedActive = ImGuiCol_HeaderActive or 0;
    end

    -- BeginDisabled/EndDisabled shim for main branch
    -- These functions exist in ImGui 1.85+ (4.3) but not in older versions
    -- Always push/pop to maintain stack balance (matches native ImGui behavior)
    if imgui.BeginDisabled == nil then
        imgui.BeginDisabled = function(disabled)
            if disabled == false then
                -- Push with no visual effect to maintain stack balance
                imgui.PushStyleVar(ImGuiStyleVar_Alpha, imgui.GetStyle().Alpha);
            else
                -- Default: apply 50% alpha for disabled appearance
                imgui.PushStyleVar(ImGuiStyleVar_Alpha, imgui.GetStyle().Alpha * 0.5);
            end
        end
        imgui.EndDisabled = function()
            imgui.PopStyleVar();
        end
    end

    -- PushStyleColor wrapper removed - all constants now guaranteed to exist via fallbacks above
    -- This ensures push/pop counts always match

end

-- SetWindowFontScale was removed in ImGui 1.92. A previous vanadial polyfill
-- emulated it with a process-global PushFont that was not popped at window End,
-- so later addons AVed in Present. Replace that (or a missing API) with a no-op.
if not rawget(_G, '_VANADIAL_FONTSCALE_NOOP') then
    imgui.SetWindowFontScale = function(_scale) end;
    _G._VANADIAL_FONTSCALE_NOOP = true;
end

-- If a previous vanadial load wrapped PushFont and returned without pushing
-- when font was nil, callers still PopFont and corrupt later addons. Re-wrap
-- once so a push always happens.
if imgui.PushFont and not rawget(_G, '_VANADIAL_PUSHFONT_SAFE') then
    local currentPushFont = imgui.PushFont;
    imgui.PushFont = function(font, size)
        if size == nil then
            local style = imgui.GetStyle();
            if style and style.FontSizeBase and style.FontSizeBase > 0 then
                size = style.FontSizeBase;
            else
                size = imgui.GetFontSize() or 13;
            end
        end
        if font == nil then
            font = imgui.GetFont();
        end
        return currentPushFont(font, size);
    end
    _G._VANADIAL_PUSHFONT_SAFE = true;
end

-- Tab color renames (ImGui 1.90+) — apply whenever new names exist, any branch.
if ImGuiCol_TabSelected ~= nil then
    ImGuiCol_TabActive = ImGuiCol_TabSelected;
    ImGuiCol_TabUnfocused = ImGuiCol_TabDimmed;
    ImGuiCol_TabUnfocusedActive = ImGuiCol_TabDimmedSelected;
end
if ImGuiCol_Tab == nil then
    ImGuiCol_Tab = ImGuiCol_Header or 0;
end
if ImGuiCol_TabHovered == nil then
    ImGuiCol_TabHovered = ImGuiCol_HeaderHovered or 0;
end
if ImGuiCol_TabActive == nil then
    ImGuiCol_TabActive = ImGuiCol_HeaderActive or 0;
end
if ImGuiCol_TabUnfocused == nil then
    ImGuiCol_TabUnfocused = ImGuiCol_Header or 0;
end
if ImGuiCol_TabUnfocusedActive == nil then
    ImGuiCol_TabUnfocusedActive = ImGuiCol_HeaderActive or 0;
end

-- ImGuiWindowFlags_NoInputs: skip missing on some Ashita builds (PetBarTarget mouse pass-through during drag-drop)
if ImGuiWindowFlags_NoInputs == nil then
    if ImGuiWindowFlags_NoMouseInputs ~= nil and ImGuiWindowFlags_NoNavInputs ~= nil then
        ImGuiWindowFlags_NoInputs = bit.bor(ImGuiWindowFlags_NoMouseInputs, ImGuiWindowFlags_NoNavInputs);
    elseif ImGuiWindowFlags_NoMouseInputs ~= nil then
        ImGuiWindowFlags_NoInputs = ImGuiWindowFlags_NoMouseInputs;
    else
        -- Dear ImGui 1.83-style composite (NoMouseInputs|NoNavInputs); used when Ashita exposes neither constant
        ImGuiWindowFlags_NoInputs = 1536;
    end
end

-- Return module info for debugging
return {
    version = '1.0.0',
    mode = use43 and '4.3' or 'main',
    description = 'ImGui compatibility layer for Ashita v4beta main/4.3'
};
