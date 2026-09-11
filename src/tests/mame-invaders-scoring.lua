local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local test = dofile(script_directory .. "/mame-test.lua")

local M = {}
local frame_subscription

local function make_scoring_step()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary_directory .. "/invaders-avo.equ")
    local symbols = test.load_symbols(binary_directory .. "/invaders-avo.sym")

    local inv_active = test.required_equate(equates, "inv_active")
    local inv_test_mode = test.required_equate(equates, "inv_test_mode")
    local inv_test_script = test.required_equate(equates, "inv_test_script")
    local inv_test_result = test.required_equate(equates, "inv_test_result")
    local inv_frame_lo = test.required_equate(equates, "inv_frame_lo")
    local inv_frame_hi = test.required_equate(equates, "inv_frame_hi")
    local inv_score_row = test.required_equate(equates, "inv_score_row")
    local inv_score0 = test.required_equate(equates, "inv_score0")
    local inv_score1 = test.required_equate(equates, "inv_score1")
    local inv_score2 = test.required_equate(equates, "inv_score2")
    local inv_initial_level = test.required_equate(equates, "inv_initial_level")
    local inv_level = test.required_equate(equates, "inv_level")
    local inv_level_timer = test.required_equate(equates, "inv_level_timer")
    local inv_turret_x_lo = test.required_equate(equates, "inv_turret_x_lo")
    local inv_turret_x_hi = test.required_equate(equates, "inv_turret_x_hi")
    local inv_laser_active = test.required_equate(equates, "inv_laser_active")
    local inv_laser_row_lo = test.required_equate(equates, "inv_laser_row_lo")
    local inv_laser_row_hi = test.required_equate(equates, "inv_laser_row_hi")
    local inv_laser_col_lo = test.required_equate(equates, "inv_laser_col_lo")
    local inv_laser_col_hi = test.required_equate(equates, "inv_laser_col_hi")
    local inv_laser_timer = test.required_equate(equates, "inv_laser_timer")
    local inv_laser_shots_lo = test.required_equate(equates, "inv_laser_shots_lo")
    local inv_laser_shots_hi = test.required_equate(equates, "inv_laser_shots_hi")
    local inv_alien_count = test.required_equate(equates, "inv_alien_count")
    local inv_alien_rows = test.required_equate(equates, "inv_alien_rows")
    local inv_alien_cols = test.required_equate(equates, "inv_alien_cols")
    local inv_alien_w = test.required_equate(equates, "inv_alien_w")
    local inv_alien_h = test.required_equate(equates, "inv_alien_h")
    local inv_alien_dir = test.required_equate(equates, "inv_alien_dir")
    local inv_alien_dir_right = test.required_equate(equates, "inv_alien_dir_right")
    local inv_alien_reverse = test.required_equate(equates, "inv_alien_reverse")
    local inv_alien_y_delta = test.required_equate(equates, "inv_alien_y_delta")
    local inv_alien_init_lo = test.required_equate(equates, "inv_alien_init_lo")
    local inv_alien_init_hi = test.required_equate(equates, "inv_alien_init_hi")
    local inv_alien_live_lo = test.required_equate(equates, "inv_alien_live_lo")
    local inv_alien_live_hi = test.required_equate(equates, "inv_alien_live_hi")
    local inv_alien_last_lo = test.required_equate(equates, "inv_alien_last_lo")
    local inv_alien_last_hi = test.required_equate(equates, "inv_alien_last_hi")
    local inv_alien_live_base = test.required_equate(equates, "inv_alien_live_base")
    local inv_alien_x_lo_base = test.required_equate(equates, "inv_alien_x_lo_base")
    local inv_alien_x_hi_base = test.required_equate(equates, "inv_alien_x_hi_base")
    local inv_alien_y_lo_base = test.required_equate(equates, "inv_alien_y_lo_base")
    local inv_alien_y_hi_base = test.required_equate(equates, "inv_alien_y_hi_base")
    local inv_scan_space = test.required_equate(equates, "inv_scan_space")
    local inv_scan_setup = test.required_equate(equates, "inv_scan_setup")
    local in_setup = test.required_equate(equates, "in_setup")
    local key_flags = test.required_equate(equates, "key_flags")
    local key_silo = test.required_equate(equates, "key_silo")
    local key_flag_shift = test.required_equate(equates, "key_flag_shift")
    local key_flag_eos = test.required_equate(equates, "key_flag_eos")
    local inv_row_addr = test.required_symbol(symbols, "inv_row_addr")

    local scan_i = 0x16
    local mem = test.program_space()

    local function read_u8(address)
        return mem:read_u8(address)
    end

    local function write_u8(address, value)
        mem:write_u8(address, value)
    end

    local function read_u16(address)
        return read_u8(address) + read_u8(address + 1) * 256
    end

    local function read_nibble_pair(lo_address, hi_address)
        return (read_u8(lo_address) % 16) + (read_u8(hi_address) % 16) * 16
    end

    local function write_nibble_pair(lo_address, hi_address, value)
        write_u8(lo_address, value % 16)
        write_u8(hi_address, math.floor(value / 16) % 16)
    end

    local function row_address(row)
        return read_u16(inv_row_addr + row * 2)
    end

    local function cell(row, column)
        return read_u8(row_address(row) + column)
    end

    local function game_frame()
        return read_nibble_pair(inv_frame_lo, inv_frame_hi)
    end

    local function laser_shots()
        return read_nibble_pair(inv_laser_shots_lo, inv_laser_shots_hi)
    end

    local function laser_row()
        return read_nibble_pair(inv_laser_row_lo, inv_laser_row_hi)
    end

    local function laser_col()
        return read_nibble_pair(inv_laser_col_lo, inv_laser_col_hi)
    end

    local function alien_init_count()
        return read_nibble_pair(inv_alien_init_lo, inv_alien_init_hi)
    end

    local function alien_live_count()
        return read_nibble_pair(inv_alien_live_lo, inv_alien_live_hi)
    end

    local function write_alien_live_count(value)
        write_nibble_pair(inv_alien_live_lo, inv_alien_live_hi, value)
    end

    local function write_alien_last(value)
        write_nibble_pair(inv_alien_last_lo, inv_alien_last_hi, value)
    end

    local function alien_x(id)
        return read_nibble_pair(inv_alien_x_lo_base + id, inv_alien_x_hi_base + id)
    end

    local function alien_y(id)
        return read_nibble_pair(inv_alien_y_lo_base + id, inv_alien_y_hi_base + id)
    end

    local function set_turret_x(value)
        write_nibble_pair(inv_turret_x_lo, inv_turret_x_hi, value)
    end

    local function arm_laser(row, column)
        write_u8(inv_laser_active, 0x0f)
        write_u8(inv_laser_timer, 0)
        write_nibble_pair(inv_laser_row_lo, inv_laser_row_hi, row)
        write_nibble_pair(inv_laser_col_lo, inv_laser_col_hi, column)
    end

    local function score_units()
        return read_u8(inv_score0) + read_u8(inv_score1) * 10 + read_u8(inv_score2) * 100
    end

    local function assert_score(expected_units)
        test.assert_eq(score_units(), expected_units, "score units")
        local digits = string.format("%04d", expected_units * 10)
        for index = 1, #digits do
            test.assert_eq(
                cell(inv_score_row, 5 + index),
                string.byte(digits, index),
                "score digit " .. tostring(index))
        end
    end

    local function assert_level(expected_level)
        test.assert_eq(read_u8(inv_level), expected_level, "level")
        test.assert_eq(cell(inv_score_row, 18), string.byte("0") + expected_level, "level digit")
    end

    local function inject_key(scan, modifiers)
        write_u8(key_flags, key_flag_eos + 1 + modifiers)
        write_u8(key_silo, scan)
        write_u8(key_silo + 1, 0)
        write_u8(key_silo + 2, 0)
        write_u8(key_silo + 3, 0)
    end

    local function clear_all_but(id)
        for alien = 0, inv_alien_count - 1 do
            write_u8(inv_alien_live_base + alien, 0)
        end
        write_u8(inv_alien_live_base + id, 0x0f)
        write_alien_live_count(1)
        write_alien_last((id + inv_alien_count - 1) % inv_alien_count)
        write_u8(inv_alien_dir, inv_alien_dir_right)
        write_u8(inv_alien_reverse, 0)
        write_u8(inv_alien_y_delta, 0)
    end

    local frame = 0
    local stage = "boot"
    local stage_frame = 0
    local setup_key_repeats = 0
    local shift_i_repeats = 0
    local bottom_target = (inv_alien_rows - 1) * inv_alien_cols
    local top_target = 0
    local final_target = inv_alien_cols * 2
    local bottom_x = nil
    local bottom_y = nil
    local top_x = nil
    local top_y = nil
    local final_x = nil
    local final_y = nil

    local function enter_stage(next_stage)
        stage = next_stage
        stage_frame = frame
    end

    local function fail_timeout(description)
        test.fail(string.format(
            "%s timed out at host frame %d: game_frame=%s live=%s score=%s level=%s timer=%s shots=%s laser=%s row=%s col=%s",
            description,
            frame,
            test.hex(game_frame(), 2),
            test.hex(alien_live_count(), 2),
            test.hex(score_units(), 2),
            test.hex(read_u8(inv_level), 2),
            test.hex(read_u8(inv_level_timer), 2),
            test.hex(laser_shots(), 2),
            test.hex(read_u8(inv_laser_active), 2),
            test.hex(laser_row(), 2),
            test.hex(laser_col(), 2)))
    end

    return function()
        local ok, err = pcall(function()
            frame = frame + 1

            if stage == "boot" then
                if frame < 120 then
                    return
                end
                test.poison_invaders_memory(equates, mem)
                test.disable_invaders_test_mode(equates, mem)
                write_u8(inv_active, 0)
                enter_stage("setup-key")
                return
            end

            if stage == "setup-key" then
                if setup_key_repeats < 2 then
                    inject_key(inv_scan_setup, 0)
                    setup_key_repeats = setup_key_repeats + 1
                    return
                end
                enter_stage("wait-setup")
                return
            end

            if stage == "wait-setup" then
                if read_u8(in_setup) ~= 0 then
                    enter_stage("shift-i")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("entering SET-UP")
                end
                return
            end

            if stage == "shift-i" then
                if shift_i_repeats < 2 then
                    inject_key(scan_i, key_flag_shift)
                    shift_i_repeats = shift_i_repeats + 1
                    return
                end
                enter_stage("wait-formation")
                return
            end

            if stage == "wait-formation" then
                if read_u8(inv_active) ~= 0 and alien_init_count() == inv_alien_count then
                    test.assert_eq(alien_live_count(), inv_alien_count, "initial live aliens")
                    assert_score(0)
                    assert_level(inv_initial_level)
                    bottom_x = alien_x(bottom_target)
                    bottom_y = alien_y(bottom_target)
                    set_turret_x(bottom_x)
                    enter_stage("fire-bottom")
                    return
                end
                if frame - stage_frame > 240 then
                    fail_timeout("formation")
                end
                return
            end

            if stage == "fire-bottom" then
                inject_key(inv_scan_space, 0)
                enter_stage("wait-bottom-hit")
                return
            end

            if stage == "wait-bottom-hit" then
                if read_u8(inv_alien_live_base + bottom_target) == 0
                    and read_u8(inv_laser_active) == 0 then
                    test.assert_eq(alien_live_count(), inv_alien_count - 1, "bottom hit live count")
                    test.assert_eq(read_u8(inv_laser_active), 0, "bottom hit deactivates laser")
                    test.assert_eq(laser_shots(), 1, "bottom hit fired shot")
                    test.assert_eq(cell(bottom_y, bottom_x), 0, "bottom alien top cell erased")
                    test.assert_eq(cell(bottom_y + 1, bottom_x + inv_alien_w - 1), 0, "bottom alien bottom cell erased")
                    assert_score(1)

                    top_x = alien_x(top_target)
                    top_y = alien_y(top_target)
                    arm_laser(top_y + inv_alien_h, top_x + 1)
                    enter_stage("wait-top-hit")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("bottom alien hit")
                end
                return
            end

            if stage == "wait-top-hit" then
                if read_u8(inv_alien_live_base + top_target) == 0
                    and read_u8(inv_laser_active) == 0 then
                    test.assert_eq(alien_live_count(), inv_alien_count - 2, "top hit live count")
                    test.assert_eq(read_u8(inv_laser_active), 0, "top hit deactivates laser")
                    test.assert_eq(cell(top_y, top_x), 0, "top alien top cell erased")
                    assert_score(4)

                    clear_all_but(final_target)
                    final_x = alien_x(final_target)
                    final_y = alien_y(final_target)
                    arm_laser(final_y + inv_alien_h, final_x + 2)
                    enter_stage("wait-final-hit")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("top alien hit")
                end
                return
            end

            if stage == "wait-final-hit" then
                if alien_live_count() == 0 and read_u8(inv_laser_active) == 0 then
                    test.assert_eq(read_u8(inv_alien_live_base + final_target), 0, "final alien dead flag")
                    test.assert_eq(read_u8(inv_laser_active), 0, "final hit deactivates laser")
                    test.assert_eq(read_u8(inv_level_timer), 0x0f, "level reset timer starts")
                    test.assert_eq(cell(final_y, final_x + 2), 0, "final alien cell erased")
                    assert_score(6)
                    assert_level(inv_initial_level)
                    enter_stage("wait-level-reset")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("final alien hit")
                end
                return
            end

            if stage == "wait-level-reset" then
                if read_u8(inv_level) == inv_initial_level + 1
                    and cell(inv_score_row, 18) == string.byte("0") + inv_initial_level + 1 then
                    test.assert_eq(read_u8(inv_level_timer), 0, "level reset timer ended")
                    test.assert_eq(alien_init_count(), 0, "next level init count")
                    test.assert_eq(alien_live_count(), 0, "next level live count")
                    assert_score(6)
                    assert_level(inv_initial_level + 1)
                    test.pass()
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("level reset")
                end
            end
        end)

        if not ok then
            test.fail(err)
        end
    end
end

function M.start()
    local step_scoring_test = nil

    emu.register_prestart(function()
        local ok, result = pcall(make_scoring_step)
        if not ok then
            test.fail(result)
            return
        end
        step_scoring_test = result
    end)

    frame_subscription = emu.add_machine_frame_notifier(function()
        if step_scoring_test == nil then
            return
        end
        local ok, err = pcall(step_scoring_test)
        if not ok then
            test.fail(err)
        end
    end)
end

return M
