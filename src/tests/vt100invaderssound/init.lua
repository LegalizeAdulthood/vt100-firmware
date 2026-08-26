-- license:BSD-3-Clause

local exports = {
    name = "vt100invaderssound",
    version = "0.0.1",
    description = "VT100 Invaders sound test",
    license = "BSD-3-Clause",
    author = { name = "VT100 Firmware" } }

local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local sound_test

function exports.startplugin()
    sound_test = dofile(script_directory .. "/../mame-invaders-sound.lua")
    sound_test.start()
end

return exports
