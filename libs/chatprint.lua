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
    print(chat.header(HEADER):append(chat.message(SanitizeChat(msg))));
end

return M;
