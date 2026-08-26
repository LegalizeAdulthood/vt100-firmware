local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local test = dofile(script_directory .. "/mame-test.lua")

local M = {}
local frame_subscription

local function make_laser_step()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary_directory .. "/invaders-avo.equ")
    local symbols = test.load_symbols(binary_directory .. "/invaders-avo.sym")

    local inv_active = test.required_equate(equates, "inv_active")
    local inv_test_mode = test.required_equate(equates, "inv_test_mode")
    local inv_test_script = test.required_equate(equates, "inv_test_script")
    local inv_test_result = test.required_equate(equates, "inv_test_result")
    local inv_laser_active = test.required_equate(equates, "inv_laser_active")
    local inv_laser_row_lo = test.required_equate(equates, "inv_laser_row_lo")
    local inv_laser_row_hi = test.required_equate(equates, "inv_laser_row_hi")
    local inv_laser_col_lo = test.required_equate(equates, "inv_laser_col_lo")
    local inv_laser_col_hi = test.required_equate(equates, "inv_laser_col_hi")
    local inv_laser_shots_lo = test.required_equate(equates, "inv_laser_shots_lo")
    local inv_laser_shots_hi = test.required_equate(equates, "inv_laser_shots_hi")
    local inv_laser_start_row = test.required_equate(equates, "inv_laser_start_row")
    local inv_laser_top_row = test.required_equate(equates, "inv_laser_top_row")
    local inv_laser_glyph = test.required_equate(equates, "inv_laser_glyph")
    local inv_shield_top_row = test.required_equate(equates, "inv_shield_top_row")
    local inv_shield_w = test.required_equate(equates, "inv_shield_w")
    local inv_shield_cells_each = test.required_equate(equates, "inv_shield_cells_each")
    local inv_shield_cells_base = test.required_equate(equates, "inv_shield_cells_base")
    local inv_shield1_x = test.required_equate(equates, "inv_shield1_x")
    local inv_turret_start_x = test.required_equate(equates, "inv_turret_start_x")
    local inv_turret_top_row = test.required_equate(equates, "inv_turret_top_row")
    local inv_turret_x_lo = test.required_equate(equates, "inv_turret_x_lo")
    local inv_turret_x_hi = test.required_equate(equates, "inv_turret_x_hi")
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

    local function read_u16(address)
        return read_u8(address) + read_u8(address + 1) * 256
    end

    local function write_u8(address, value)
        mem:write_u8(address, value)
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

    local function laser_row()
        return read_nibble_pair(inv_laser_row_lo, inv_laser_row_hi)
    end

    local function laser_col()
        return read_nibble_pair(inv_laser_col_lo, inv_laser_col_hi)
    end

    local function laser_shots()
        return read_nibble_pair(inv_laser_shots_lo, inv_laser_shots_hi)
    end

    local function set_turret_x(value)
        write_nibble_pair(inv_turret_x_lo, inv_turret_x_hi, value)
    end

    local function inject_key(scan, modifiers)
        write_u8(key_flags, key_flag_eos + 1 + modifiers)
        write_u8(key_silo, scan)
        write_u8(key_silo + 1, 0)
        write_u8(key_silo + 2, 0)
        write_u8(key_silo + 3, 0)
    end

    local function static_screen_ready()
        return read_u8(inv_active) ~= 0
            and read_u8(inv_laser_active) == 0
            and cell(inv_turret_top_row, inv_turret_start_x + 3) ~= 0
    end

    local function assert_laser_cell(description)
        test.assert_eq(cell(laser_row(), laser_col()), inv_laser_glyph, description)
    end

    local function shield_cell_address(row, column)
        local shield_index = 1
        local shield_row = row - inv_shield_top_row
        local shield_column = column - inv_shield1_x
        return inv_shield_cells_base
            + shield_index * inv_shield_cells_each
            + shield_row * inv_shield_w
            + shield_column
    end

    local frame = 0
    local stage = "boot"
    local stage_frame = 0
    local setup_key_repeats = 0
    local shift_i_repeats = 0
    local empty_column = inv_turret_start_x + 3
    local shield_row = inv_laser_start_row
    local shield_column = inv_shield1_x
    local shield_cell = shield_cell_address(shield_row, shield_column)
    local shield_turret_x = shield_column - 3
    local shield_original = nil
    local last_empty_row = nil
    local saw_empty_motion = false

    local function enter_stage(next_stage)
        stage = next_stage
        stage_frame = frame
    end

    local function fail_timeout(description)
        test.fail(string.format(
            "%s timed out at frame %d: active=%s laser=%s row=%s col=%s shots=%s",
            description,
            frame,
            test.hex(read_u8(inv_active), 2),
            test.hex(read_u8(inv_laser_active), 2),
            test.hex(laser_row(), 2),
            test.hex(laser_col(), 2),
            test.hex(laser_shots(), 2)))
    end

    return function()
        local ok, err = pcall(function()
            frame = frame + 1

            if stage == "boot" then
                if frame < 120 then
                    return
                end
                write_u8(inv_active, 0)
                write_u8(inv_test_mode, 0)
                write_u8(inv_test_script, 0)
                write_u8(inv_test_result, 0)
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
                enter_stage("wait-static")
                return
            end

            if stage == "wait-static" then
                if static_screen_ready() then
                    test.assert_eq(laser_shots(), 0, "initial laser shots")
                    test.assert_eq(read_u8(inv_laser_active), 0, "initial laser active")
                    shield_original = read_u8(shield_cell)
                    if shield_original == 0 then
                        test.fail("selected shield cell is blank before firing")
                        return
                    end
                    enter_stage("fire-empty")
                    return
                end
                if frame - stage_frame > 180 then
                    fail_timeout("static screen")
                end
                return
            end

            if stage == "fire-empty" then
                inject_key(inv_scan_space, 0)
                enter_stage("wait-empty-shot")
                return
            end

            if stage == "wait-empty-shot" then
                if laser_shots() == 1 and read_u8(inv_laser_active) ~= 0 then
                    test.assert_eq(laser_col(), empty_column, "empty laser column")
                    test.assert_between(laser_row(), inv_laser_top_row, inv_laser_start_row, "empty laser row")
                    assert_laser_cell("empty laser glyph")
                    last_empty_row = laser_row()
                    enter_stage("refire-while-active")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("empty laser launch")
                end
                return
            end

            if stage == "refire-while-active" then
                inject_key(inv_scan_space, 0)
                enter_stage("assert-refire-blocked")
                return
            end

            if stage == "assert-refire-blocked" then
                if frame - stage_frame >= 3 then
                    test.assert_eq(laser_shots(), 1, "refire while active did not spawn")
                    if read_u8(inv_laser_active) == 0 then
                        test.fail("laser ended before refire assertion")
                        return
                    end
                    if laser_row() < last_empty_row then
                        saw_empty_motion = true
                    end
                    enter_stage("wait-empty-done")
                end
                return
            end

            if stage == "wait-empty-done" then
                if read_u8(inv_laser_active) == 0 then
                    test.assert_eq(laser_shots(), 1, "empty laser shot count")
                    test.assert_eq(cell(inv_laser_top_row, empty_column), 0, "top laser cell erased")
                    if not saw_empty_motion and laser_row() == inv_laser_start_row then
                        test.fail("empty laser did not move")
                        return
                    end
                    set_turret_x(shield_turret_x)
                    enter_stage("fire-shield")
                    return
                end
                if laser_row() < last_empty_row then
                    saw_empty_motion = true
                end
                last_empty_row = laser_row()
                if frame - stage_frame > 180 then
                    fail_timeout("empty laser completion")
                end
                return
            end

            if stage == "fire-shield" then
                inject_key(inv_scan_space, 0)
                enter_stage("wait-shield-hit")
                return
            end

            if stage == "wait-shield-hit" then
                if laser_shots() == 2 then
                    test.assert_eq(read_u8(inv_laser_active), 0, "shield hit deactivates laser")
                    test.assert_eq(laser_row(), shield_row, "shield hit row")
                    test.assert_eq(laser_col(), shield_column, "shield hit column")
                    test.assert_eq(read_u8(shield_cell), 0, "shield cell cleared")
                    test.assert_eq(cell(shield_row, shield_column), 0, "shield screen cell cleared")
                    test.pass()
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("shield laser hit")
                end
            end
        end)

        if not ok then
            test.fail(err)
        end
    end
end

function M.start()
    local step_laser_test = nil

    emu.register_prestart(function()
        local ok, result = pcall(make_laser_step)
        if not ok then
            test.fail(result)
            return
        end
        step_laser_test = result
    end)

    frame_subscription = emu.add_machine_frame_notifier(function()
        if step_laser_test == nil then
            return
        end
        local ok, err = pcall(step_laser_test)
        if not ok then
            test.fail(err)
        end
    end)
end

return M
