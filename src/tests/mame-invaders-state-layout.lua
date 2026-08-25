local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local test = dofile(script_directory .. "/mame-test.lua")

test.run(function()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary_directory .. "/invaders.equ")
    local mem = test.program_space()

    local mutable_ranges = {
        { "inv_test_signature", 3 },
        { "inv_test_mode", 1 },
        { "inv_test_script", 1 },
        { "inv_test_stop_lo", 1 },
        { "inv_test_stop_hi", 1 },
        { "inv_test_result", 1 },
        { "inv_test_trace_head", 1 },
        { "inv_test_trace_base", 128 },
        { "inv_active", 1 },
        { "inv_last_vframe", 1 },
        { "inv_frame_lo", 1 },
        { "inv_frame_hi", 1 },
        { "inv_left_pressed", 1 },
        { "inv_right_pressed", 1 },
        { "inv_fire_pressed", 1 },
        { "inv_score0", 1 },
        { "inv_score1", 1 },
        { "inv_score2", 1 },
        { "inv_gunners", 1 },
        { "inv_level", 1 },
        { "inv_saved_led_state", 1 },
        { "inv_game_over", 1 },
        { "inv_turret_x_lo", 1 },
        { "inv_turret_x_hi", 1 },
        { "inv_shield_cells_base", 84 },
        { "inv_dirty_queue_base", 64 },
        { "inv_object_map_base", 1440 },
    }

    local screen_snapshot = {}
    for address = 0x2000, 0x2fff do
        screen_snapshot[address] = mem:read_u8(address)
    end

    local sentinel = 1
    for _, range in ipairs(mutable_ranges) do
        local address = test.required_equate(equates, range[1])
        local byte_count = range[2]
        for offset = 0, byte_count - 1 do
            local value = sentinel % 16
            mem:write_u8(address + offset, value)
            test.assert_eq(
                mem:read_u8(address + offset) % 16,
                value,
                range[1] .. " sentinel at offset " .. tostring(offset))
            sentinel = sentinel + 1
        end
    end

    for address = 0x2000, 0x2fff do
        test.assert_eq(
            mem:read_u8(address),
            screen_snapshot[address],
            "visible screen RAM unchanged at " .. test.hex(address))
    end
end)
