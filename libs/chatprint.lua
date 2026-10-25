--[[
* Vana'Dial chat output — Ashita addon header + cream/yellow message body.
]]--

local chat = require('chat');

local M = {};

local HEADER = "Vana'Dial";

local function SanitizeChat(text)
    return tostring(text or ''):gsub('[^\32-\126]', '');
end

function M.Print(msg)
    -- FFXI treats ">" as the start of an auto-translate phrase. A route key
    -- such as "Selbina>Mhaura>>" then shows up as a blank chat line.
    local text = SanitizeChat(msg):gsub('>', '/');
    if text == '' then return; end
    print(chat.header(HEADER):append(chat.message(text)));
end

return M;
