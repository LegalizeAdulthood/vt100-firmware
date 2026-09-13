local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local test = dofile(script_directory .. "/mame-test.lua")

local M = {}
local frame_subscription

local function make_entry_step()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary_directory .. "/invaders-avo.equ")

    local inv_active = test.required_equate(equates, "inv_active")
    local inv_active_value = test.required_equate(equates, "inv_active_value")
    local inv_test_mode = test.required_equate(equates, "inv_test_mode")
    local inv_test_script = test.required_equate(equates, "inv_test_script")
    local inv_test_stop_lo = test.required_equate(equates, "inv_test_stop_lo")
    local inv_test_stop_hi = test.required_equate(equates, "inv_test_stop_hi")
    local inv_test_result = test.required_equate(equates, "inv_test_result")
    local inv_attract_mode = test.required_equate(equates, "inv_attract_mode")
    local inv_scan_return_b = test.required_equate(equates, "inv_scan_return_b")
    local in_setup = test.required_equate(equates, "in_setup")
    local char_action = test.required_equate(equates, "char_action")
    local saved_action = test.required_equate(equates, "saved_action")
    local new_key_scan = test.required_equate(equates, "new_key_scan")
    local key_flags = test.required_equate(equates, "key_flags")
    local key_silo = test.required_equate(equates, "key_silo")
    local key_history = test.required_equate(equates, "key_history")
    local latest_key_scan = test.required_equate(equates, "latest_key_scan")
    local pending_setup = test.required_equate(equates, "pending_setup")
    local inv_level_timer = test.required_equate(equates, "inv_level_timer")

    local key_flag_shift = 0x20
    local key_flag_eos = 0x80
    local scan_setup = 0x7b
    local scan_i = 0x16

    local mem = test.program_space()

    local function read_u8(address)
        return mem:read_u8(address)
    end

    local function read_u16(address)
        return read_u8(address) + (read_u8(address + 1) * 256)
    end

    local function write_u8(address, value)
        mem:write_u8(address, value)
    end

    local function inject_key(scan, modifiers)
        write_u8(key_flags, key_flag_eos + 1 + modifiers)
        write_u8(key_silo, scan)
        write_u8(key_silo + 1, 0)
        write_u8(key_silo + 2, 0)
        write_u8(key_silo + 3, 0)
    end

    local frame = 0
    local stage = "boot"
    local stage_frame = 0
    local setup_key_repeats = 0
    local lower_i_repeats = 0
    local enter_key_repeats = 0
    local exit_key_repeats = 0
    local saved_action_value = 0

    local function enter_stage(next_stage)
        stage = next_stage
        stage_frame = frame
    end

    local function fail_timeout(description)
        test.fail(string.format(
            "%s timed out at frame %d: key_flags=%s key_silo=%s new_key_scan=%s latest_key_scan=%s key_history=%s pending_setup=%s in_setup=%s",
            description,
            frame,
            test.hex(read_u8(key_flags), 2),
            test.hex(read_u8(key_silo), 2),
            test.hex(read_u8(new_key_scan), 2),
            test.hex(read_u8(latest_key_scan), 2),
            test.hex(read_u8(key_history), 2),
            test.hex(read_u8(pending_setup), 2),
            test.hex(read_u8(in_setup), 2)))
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
                write_u8(inv_active, 0xff)
                write_u8(inv_level_timer, 1)
                enter_stage("prelaunch-junk")
                return
            end

            if stage == "prelaunch-junk" then
                if frame - stage_frame >= 8 then
                    test.assert_eq(read_u8(inv_active), 0xff, "prelaunch junk active byte")
                    test.assert_eq(read_u8(inv_level_timer), 1, "prelaunch level timer")
                    write_u8(inv_level_timer, 0)
                    write_u8(inv_active, 0)
                    enter_stage("setup-key")
                    return
                end
                return
            end

            if stage == "setup-key" then
                if setup_key_repeats < 2 then
                    inject_key(scan_setup, 0)
                    setup_key_repeats = setup_key_repeats + 1
                    return
                end
                enter_stage("wait-setup")
                return
            end

            if stage == "wait-setup" then
                if read_u8(in_setup) ~= 0 then
                    saved_action_value = read_u16(saved_action)
                    enter_stage("lower-i")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("entering SET-UP")
                end
                return
            end

            if stage == "lower-i" then
                if lower_i_repeats < 2 then
                    inject_key(scan_i, 0)
                    lower_i_repeats = lower_i_repeats + 1
                    return
                end
                enter_stage("wait-attract")
                return
            end

            if stage == "wait-attract" then
                if read_u8(inv_active) == inv_active_value then
                    test.assert_eq(read_u8(inv_attract_mode), 0xff, "attract mode after Invaders entry")
                    test.assert_eq(read_u8(in_setup), 0, "in_setup after Invaders entry")
                    test.assert_eq(read_u16(char_action), saved_action_value, "char_action after Invaders entry")
                    enter_stage("enter-key")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("entering Invaders attract mode")
                end
                return
            end

            if stage == "enter-key" then
                if enter_key_repeats < 2 then
                    inject_key(inv_scan_return_b, 0)
                    enter_key_repeats = enter_key_repeats + 1
                    return
                end
                enter_stage("wait-active")
                return
            end

            if stage == "wait-active" then
                if read_u8(inv_active) == inv_active_value and read_u8(inv_attract_mode) == 0 then
                    enter_stage("exit-key")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("starting Invaders")
                end
                return
            end

            if stage == "exit-key" then
                if exit_key_repeats < 2 then
                    inject_key(scan_setup, 0)
                    exit_key_repeats = exit_key_repeats + 1
                    return
                end
                enter_stage("wait-exit")
                return
            end

            if stage == "wait-exit" then
                if read_u8(inv_active) == 0 then
                    test.assert_eq(read_u8(inv_attract_mode), 0, "attract mode after exit")
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
    local step_entry_test = nil

    emu.register_prestart(function()
        local ok, result = pcall(make_entry_step)
        if not ok then
            test.fail(result)
            return
        end
        step_entry_test = result
    end)

    frame_subscription = emu.add_machine_frame_notifier(function()
        if step_entry_test == nil then
            return
        end
        local ok, err = pcall(step_entry_test)
        if not ok then
            test.fail(err)
        end
    end)
end

return M
