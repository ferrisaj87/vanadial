--[[
* Exception-safe ImGui scope management for Ashita v4 / Lua 5.1.
*
* Cleanup callbacks are registered only after their matching Begin/Push call
* succeeds, then unwound in reverse order even when drawing raises an error.
]]--

local imgui = require('imgui');

local M = {};
local Scope = {};
Scope.__index = Scope;

function Scope:Defer(fn)
    self.cleanups[#self.cleanups + 1] = fn;
end

function Scope:Mark()
    return #self.cleanups;
end

function Scope:CloseTo(mark)
    local firstError = nil;
    while #self.cleanups > mark do
        local index = #self.cleanups;
        local fn = self.cleanups[index];
        self.cleanups[index] = nil;
        local ok, err = pcall(fn);
        if not ok and firstError == nil then
            firstError = err;
        end
    end
    if firstError ~= nil then
        error(firstError);
    end
end

function Scope:PushStyleColor(index, value)
    imgui.PushStyleColor(index, value);
    self:Defer(function() imgui.PopStyleColor(1); end);
end

function Scope:PushStyleVar(index, value)
    imgui.PushStyleVar(index, value);
    self:Defer(function() imgui.PopStyleVar(1); end);
end

function Scope:PushFont(font, size)
    imgui.PushFont(font, size);
    self:Defer(function() imgui.PopFont(); end);
end

function Scope:PushTextWrapPos(pos)
    imgui.PushTextWrapPos(pos);
    self:Defer(function() imgui.PopTextWrapPos(); end);
end

function Scope:Indent(amount)
    imgui.Indent(amount);
    self:Defer(function() imgui.Unindent(amount); end);
end

function Scope:BeginWindow(name, open, flags)
    local visible = imgui.Begin(name, open, flags);
    -- Dear ImGui requires End after every completed Begin call, even when the
    -- returned visibility value is false.
    self:Defer(function() imgui.End(); end);
    return visible;
end

function Scope:BeginTooltip()
    imgui.BeginTooltip();
    self:Defer(function() imgui.EndTooltip(); end);
    return true;
end

function Scope:BeginCombo(label, preview)
    local visible = imgui.BeginCombo(label, preview);
    if visible then
        self:Defer(function() imgui.EndCombo(); end);
    end
    return visible;
end

function Scope:BeginTabBar(id, flags)
    local visible;
    if flags ~= nil then
        visible = imgui.BeginTabBar(id, flags);
    else
        visible = imgui.BeginTabBar(id);
    end
    if visible then
        self:Defer(function() imgui.EndTabBar(); end);
    end
    return visible;
end

function Scope:BeginTabItem(label, open, flags)
    local visible;
    if open ~= nil or flags ~= nil then
        visible = imgui.BeginTabItem(label, open, flags or 0);
    else
        visible = imgui.BeginTabItem(label);
    end
    if visible then
        self:Defer(function() imgui.EndTabItem(); end);
    end
    return visible;
end

local function Traceback(err)
    if debug and debug.traceback then
        return debug.traceback(tostring(err), 2);
    end
    return tostring(err);
end

function M.Run(fn)
    local scope = setmetatable({ cleanups = {} }, Scope);
    local ok, result = xpcall(function() return fn(scope); end, Traceback);
    local cleanupOk, cleanupErr = pcall(function() scope:CloseTo(0); end);
    if not ok then
        return false, result;
    end
    if not cleanupOk then
        return false, cleanupErr;
    end
    return true, result;
end

return M;
