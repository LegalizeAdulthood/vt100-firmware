-- license:BSD-3-Clause

local exports = {
    name = "vt100invadersscoring",
    version = "0.0.1",
    description = "VT100 Invaders scoring and level reset test",
    license = "BSD-3-Clause",
    author = { name = "VT100 Firmware" } }

local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local scoring_test

function exports.startplugin()
    scoring_test = dofile(script_directory .. "/../mame-invaders-scoring.lua")
    scoring_test.start()
end

return exports
