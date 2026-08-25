local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local test = dofile(script_directory .. "/mame-test.lua")

local M = {}
local frame_subscription

local function make_input_step()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary_directory .. "/invaders.equ")
    local symbols = test.load_symbols(binary_directory .. "/invaders-avo.sym")

    local inv_active = test.required_equate(equates, "inv_active")
    local inv_test_mode = test.required_equate(equates, "inv_test_mode")
    local inv_test_script = test.required_equate(equates, "inv_test_script")
    local inv_test_result = test.required_equate(equates, "inv_test_result")
    local inv_test_script_input = test.required_equate(equates, "inv_test_script_input")
    local inv_test_input_left = test.required_equate(equates, "inv_test_input_left")
    local inv_test_input_right = test.required_equate(equates, "inv_test_input_right")
    local inv_test_input_fire = test.required_equate(equates, "inv_test_input_fire")
    local inv_left_pressed = test.required_equate(equates, "inv_left_pressed")
    local inv_right_pressed = test.required_equate(equates, "inv_right_pressed")
    local inv_fire_pressed = test.required_equate(equates, "inv_fire_pressed")
    local inv_turret_x_lo = test.required_equate(equates, "inv_turret_x_lo")
    local inv_turret_x_hi = test.required_equate(equates, "inv_turret_x_hi")
    local inv_turret_start_x = test.required_equate(equates, "inv_turret_start_x")
    local inv_turret_min_x = test.required_equate(equates, "inv_turret_min_x")
    local inv_turret_max_x = test.required_equate(equates, "inv_turret_max_x")
    local inv_turret_top_row = test.required_equate(equates, "inv_turret_top_row")
    local inv_scan_arrow_left = test.required_equate(equates, "inv_scan_arrow_left")
    local inv_scan_arrow_right = test.required_equate(equates, "inv_scan_arrow_right")
    local inv_scan_space = test.required_equate(equates, "inv_scan_space")
    local inv_scan_setup = test.required_equate(equates, "inv_scan_setup")
    local in_setup = test.required_equate(equates, "in_setup")
    local key_flags = test.required_equate(equates, "key_flags")
    local key_silo = test.required_equate(equates, "key_silo")
    local key_flag_shift = test.required_equate(equates, "key_flag_shift")
    local key_flag_eos = test.required_equate(equates, "key_flag_eos")
    local curkey_queue = test.required_equate(equates, "curkey_queue")
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

    local function has_bit(value, bit)
        return value % (bit * 2) >= bit
    end

    local function row_address(row)
        return read_u16(inv_row_addr + row * 2)
    end

    local function cell(row, column)
        return read_u8(row_address(row) + column)
    end

    local function sg(source)
        return string.byte(source) - 0x5f
    end

    local function turret_x()
        return read_u8(inv_turret_x_lo) + read_u8(inv_turret_x_hi) * 16
    end

    local function set_turret_x(value)
        write_u8(inv_turret_x_lo, value % 16)
        write_u8(inv_turret_x_hi, math.floor(value / 16))
    end

    local function inject_key(scan, modifiers)
        write_u8(key_flags, key_flag_eos + 1 + modifiers)
        write_u8(key_silo, scan)
        write_u8(key_silo + 1, 0)
        write_u8(key_silo + 2, 0)
        write_u8(key_silo + 3, 0)
    end

    local function clear_function_key_queue()
        for index = 0, 9 do
            write_u8(curkey_queue + index, 0)
        end
    end

    local function assert_no_function_key_output()
        for index = 0, 9 do
            test.assert_eq(read_u8(curkey_queue + index), 0, "function key output byte " .. tostring(index))
        end
    end

    local function assert_keyboard_cleared()
        test.assert_eq(read_u8(key_flags), 0, "key flags")
        for index = 0, 3 do
            test.assert_eq(read_u8(key_silo + index), 0, "key silo byte " .. tostring(index))
        end
    end

    local function assert_latch_seen(bit, description)
        if not has_bit(read_u8(inv_test_result), bit) then
            test.fail(description .. " was not latched")
        end
    end

    local function assert_left_position()
        test.assert_eq(turret_x(), inv_turret_start_x - 1, "turret left movement")
        test.assert_eq(cell(inv_turret_top_row, inv_turret_start_x + 6), sg("q"), "old right edge restored")
        test.assert_eq(cell(inv_turret_top_row, inv_turret_start_x + 2), sg("a"), "new left center")
    end

    local function assert_start_position()
        test.assert_eq(turret_x(), inv_turret_start_x, "turret returned to start")
        test.assert_eq(cell(inv_turret_top_row, inv_turret_start_x - 1), sg("q"), "old left edge restored")
        test.assert_eq(cell(inv_turret_top_row, inv_turret_start_x + 3), sg("a"), "start center")
    end

    local function static_screen_ready()
        return read_u8(inv_active) ~= 0
            and turret_x() == inv_turret_start_x
            and cell(inv_turret_top_row, inv_turret_start_x + 3) == sg("a")
    end

    local frame = 0
    local stage = "boot"
    local stage_frame = 0
    local setup_key_repeats = 0
    local shift_i_repeats = 0

    local function enter_stage(next_stage)
        stage = next_stage
        stage_frame = frame
    end

    local function fail_timeout(description)
        test.fail(string.format(
            "%s timed out at frame %d: active=%s x=%s result=%s in_setup=%s",
            description,
            frame,
            test.hex(read_u8(inv_active), 2),
            test.hex(turret_x(), 2),
            test.hex(read_u8(inv_test_result), 2),
            test.hex(read_u8(in_setup), 2)))
    end

    return function()
        local ok, err = pcall(function()
            frame = frame + 1

            if stage == "boot" then
                if frame < 120 then
                    return
                end
                write_u8(inv_active, 0)
                write_u8(inv_test_mode, 1)
                write_u8(inv_test_script, inv_test_script_input)
                write_u8(inv_test_result, 0)
                clear_function_key_queue()
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
                    test.assert_eq(read_u8(inv_test_result), 0, "initial input result")
                    assert_no_function_key_output()
                    enter_stage("press-left")
                    return
                end
                if frame - stage_frame > 180 then
                    fail_timeout("static screen")
                end
                return
            end

            if stage == "press-left" then
                inject_key(inv_scan_arrow_left, 0)
                enter_stage("wait-left")
                return
            end

            if stage == "wait-left" then
                if turret_x() == inv_turret_start_x - 1 then
                    assert_left_position()
                    assert_latch_seen(inv_test_input_left, "left arrow")
                    assert_no_function_key_output()
                    write_u8(inv_test_result, 0)
                    enter_stage("press-right")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("left movement")
                end
                return
            end

            if stage == "press-right" then
                inject_key(inv_scan_arrow_right, 0)
                enter_stage("wait-right")
                return
            end

            if stage == "wait-right" then
                if turret_x() == inv_turret_start_x then
                    assert_start_position()
                    assert_latch_seen(inv_test_input_right, "right arrow")
                    assert_no_function_key_output()
                    write_u8(inv_test_result, 0)
                    set_turret_x(inv_turret_min_x)
                    enter_stage("left-bound-extra")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("right movement")
                end
                return
            end

            if stage == "left-bound-extra" then
                inject_key(inv_scan_arrow_left, 0)
                enter_stage("wait-left-bound")
                return
            end

            if stage == "wait-left-bound" then
                if frame - stage_frame >= 3 then
                    test.assert_eq(turret_x(), inv_turret_min_x, "left bound clamp")
                    assert_latch_seen(inv_test_input_left, "left bound arrow")
                    write_u8(inv_test_result, 0)
                    set_turret_x(inv_turret_max_x)
                    enter_stage("right-bound-extra")
                end
                return
            end

            if stage == "right-bound-extra" then
                inject_key(inv_scan_arrow_right, 0)
                enter_stage("wait-right-bound")
                return
            end

            if stage == "wait-right-bound" then
                if frame - stage_frame >= 3 then
                    test.assert_eq(turret_x(), inv_turret_max_x, "right bound clamp")
                    assert_latch_seen(inv_test_input_right, "right bound arrow")
                    write_u8(inv_test_result, 0)
                    enter_stage("press-fire")
                end
                return
            end

            if stage == "press-fire" then
                inject_key(inv_scan_space, 0)
                enter_stage("wait-fire")
                return
            end

            if stage == "wait-fire" then
                if has_bit(read_u8(inv_test_result), inv_test_input_fire) then
                    assert_no_function_key_output()
                    enter_stage("wait-fire-clear")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("fire latch")
                end
                return
            end

            if stage == "wait-fire-clear" then
                if frame - stage_frame >= 3 then
                    test.assert_eq(read_u8(inv_left_pressed), 0, "left latch cleared")
                    test.assert_eq(read_u8(inv_right_pressed), 0, "right latch cleared")
                    test.assert_eq(read_u8(inv_fire_pressed), 0, "fire latch cleared")
                    enter_stage("exit-key")
                end
                return
            end

            if stage == "exit-key" then
                inject_key(inv_scan_setup, 0)
                enter_stage("wait-exit")
                return
            end

            if stage == "wait-exit" then
                if read_u8(inv_active) == 0 then
                    assert_keyboard_cleared()
                    assert_no_function_key_output()
                    test.pass()
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("leaving Invaders")
                end
            end
        end)

        if not ok then
            test.fail(err)
        end
    end
end

function M.start()
    local step_input_test = nil

    emu.register_prestart(function()
        local ok, result = pcall(make_input_step)
        if not ok then
            test.fail(result)
            return
        end
        step_input_test = result
    end)

    frame_subscription = emu.add_machine_frame_notifier(function()
        if step_input_test == nil then
            return
        end
        local ok, err = pcall(step_input_test)
        if not ok then
            test.fail(err)
        end
    end)
end

return M
