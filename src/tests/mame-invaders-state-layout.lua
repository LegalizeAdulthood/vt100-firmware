local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local test = dofile(script_directory .. "/mame-test.lua")

test.run(function()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary_directory .. "/invaders-avo.equ")
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
        { "inv_attract_mode", 1 },
        { "inv_level_timer", 1 },
        { "inv_turret_death_timer", 1 },
        { "inv_missile_tick_timer", 1 },
        { "inv_missile_fire_timer", 1 },
        { "inv_missile_active_count", 1 },
        { "inv_missile_shot_index", 1 },
        { "inv_missile_slot_tmp", 1 },
        { "inv_sound_mode", 1 },
        { "inv_sound_timer", 1 },
        { "inv_sound_phase", 1 },
        { "inv_heartbeat_timer", 1 },
        { "inv_death_sound_timer", 1 },
        { "inv_last_stock_kbd_status", 1 },
        { "inv_last_output_kbd_status", 1 },
        { "inv_ufo_state", 1 },
        { "inv_ufo_x", 1 },
        { "inv_ufo_dx", 1 },
        { "inv_ufo_timer_lo", 1 },
        { "inv_ufo_timer_hi", 1 },
        { "inv_ufo_move_timer", 1 },
        { "inv_ufo_state_timer", 1 },
        { "inv_ufo_points", 1 },
        { "inv_ufo_disabled", 1 },
        { "inv_high_score_dirty", 1 },
        { "inv_high_score_slot", 1 },
        { "inv_high_shift_index", 1 },
        { "inv_high_nvr_index", 1 },
        { "inv_high_initial_ready", 1 },
        { "inv_turret_x_lo", 1 },
        { "inv_turret_x_hi", 1 },
        { "inv_laser_active", 1 },
        { "inv_laser_row_lo", 1 },
        { "inv_laser_row_hi", 1 },
        { "inv_laser_col_lo", 1 },
        { "inv_laser_col_hi", 1 },
        { "inv_laser_timer", 1 },
        { "inv_laser_shots_lo", 1 },
        { "inv_laser_shots_hi", 1 },
        { "inv_hit_row_lo", 1 },
        { "inv_hit_row_hi", 1 },
        { "inv_hit_col_lo", 1 },
        { "inv_hit_col_hi", 1 },
        { "inv_alien_init_lo", 1 },
        { "inv_alien_init_hi", 1 },
        { "inv_alien_live_lo", 1 },
        { "inv_alien_live_hi", 1 },
        { "inv_alien_last_lo", 1 },
        { "inv_alien_last_hi", 1 },
        { "inv_alien_dir", 1 },
        { "inv_alien_reverse", 1 },
        { "inv_alien_y_delta", 1 },
        { "inv_alien_descents", 1 },
        { "inv_alien_anim_phase", 1 },
        { "inv_alien_min_col", 1 },
        { "inv_alien_max_col", 1 },
        { "inv_alien_min_row", 1 },
        { "inv_alien_max_row", 1 },
        { "inv_alien_data_base", 220 },
        { "inv_missile_data_base", 12 },
        { "inv_shield_damage_base", 28 },
        { "inv_shield_cells_base", 84 },
        { "inv_high_initial_index", 1 },
        { "inv_high_initial_used", 1 },
        { "inv_saved_curs_attr_rend", 2 },
        { "inv_high_score_digit_base", 30 },
        { "inv_high_initial_lo_base", 30 },
        { "inv_high_initial_hi_base", 30 },
    }

    local screen_snapshot = {}
    local low = test.required_equate(equates, "inv_data_low")
    local top = test.required_equate(equates, "inv_data_top")
    test.assert_between(low, 0x2c00, 0x2fff, "state lower bound")
    test.assert_eq(top, 0x2fff, "state upper bound")
    for address = 0x2000, 0x3fff do
        if address < low or address > top then
            screen_snapshot[address] = mem:read_u8(address)
        end
    end

    local sentinel = 1
    for _, range in ipairs(mutable_ranges) do
        local address = test.required_equate(equates, range[1])
        local byte_count = range[2]
        for offset = 0, byte_count - 1 do
            test.assert_between(address + offset, low, top, range[1] .. " allocation")
            local value = test.invaders_junk_byte(sentinel, 1)
            mem:write_u8(address + offset, value)
            test.assert_eq(
                mem:read_u8(address + offset),
                value,
                range[1] .. " sentinel at offset " .. tostring(offset))
            sentinel = sentinel + 1
        end
    end

    for address, value in pairs(screen_snapshot) do
        test.assert_eq(
            mem:read_u8(address),
            value,
            "terminal/screen/attribute RAM unchanged at " .. test.hex(address))
    end

    local attribute = mem:read_u8(0x3000)
    mem:write_u8(0x3000, 0x5a)
    test.assert_eq(mem:read_u8(0x3000), 0xfa, "attribute RAM cannot retain a full byte")
    mem:write_u8(0x3000, attribute)
end)
