local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local test = dofile(script_directory .. "/mame-test.lua")

local M = {}
local frame_subscription

local function make_frame_step()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary_directory .. "/invaders-avo.equ")

    local inv_active = test.required_equate(equates, "inv_active")
    local inv_test_mode = test.required_equate(equates, "inv_test_mode")
    local inv_test_script = test.required_equate(equates, "inv_test_script")
    local inv_test_stop_lo = test.required_equate(equates, "inv_test_stop_lo")
    local inv_test_stop_hi = test.required_equate(equates, "inv_test_stop_hi")
    local inv_test_result = test.required_equate(equates, "inv_test_result")
    local inv_frame_lo = test.required_equate(equates, "inv_frame_lo")
    local inv_frame_hi = test.required_equate(equates, "inv_frame_hi")
    local in_setup = test.required_equate(equates, "in_setup")
    local key_flags = test.required_equate(equates, "key_flags")
    local key_silo = test.required_equate(equates, "key_silo")

    local key_flag_shift = 0x20
    local key_flag_eos = 0x80
    local scan_setup = 0x7b
    local scan_i = 0x16
    local stop_frame = 8

    local mem = test.program_space()

    local function read_u8(address)
        return mem:read_u8(address)
    end

    local function read_u16(lo_address, hi_address)
        return read_u8(lo_address) + (read_u8(hi_address) * 256)
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
    local shift_i_repeats = 0
    local last_game_frame = nil
    local saw_frame_advance = false

    local function enter_stage(next_stage)
        stage = next_stage
        stage_frame = frame
    end

    local function fail_timeout(description)
        test.fail(string.format(
            "%s timed out at frame %d: active=%s game_frame=%s result=%s in_setup=%s",
            description,
            frame,
            test.hex(read_u8(inv_active), 2),
            test.hex(read_u16(inv_frame_lo, inv_frame_hi), 4),
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
                test.poison_invaders_memory(equates, mem)
                test.enable_invaders_test_mode(equates, mem)
                write_u8(inv_active, 0)
                write_u8(inv_test_mode, 1)
                write_u8(inv_test_script, 0)
                write_u8(inv_test_stop_lo, stop_frame)
                write_u8(inv_test_stop_hi, 0)
                write_u8(inv_test_result, 0x0e)
                enter_stage("setup-key")
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
                enter_stage("wait-active")
                return
            end

            if stage == "wait-active" then
                if read_u8(inv_active) ~= 0 then
                    local game_frame = read_u16(inv_frame_lo, inv_frame_hi)
                    if game_frame >= stop_frame then
                        test.fail(string.format(
                            "missed active frame window: game_frame=%s stop_frame=%s",
                            test.hex(game_frame, 4),
                            test.hex(stop_frame, 4)))
                        return
                    end
                    test.assert_eq(read_u8(inv_test_result), 0, "initial test result")
                    last_game_frame = game_frame
                    enter_stage("wait-stop")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("entering Invaders")
                end
                return
            end

            if stage == "wait-stop" then
                local game_frame = read_u16(inv_frame_lo, inv_frame_hi)
                if game_frame < last_game_frame then
                    test.fail(string.format(
                        "game frame moved backward: was %s, now %s",
                        test.hex(last_game_frame, 4),
                        test.hex(game_frame, 4)))
                    return
                end
                if game_frame > last_game_frame then
                    saw_frame_advance = true
                end
                last_game_frame = game_frame

                if read_u8(inv_active) == 0 then
                    test.assert_eq(game_frame, stop_frame, "stop game frame")
                    test.assert_eq(read_u8(inv_test_result), 0, "stop test result")
                    if not saw_frame_advance then
                        test.fail("game frame counter did not advance")
                        return
                    end
                    test.pass()
                    return
                end

                if frame - stage_frame > 120 then
                    fail_timeout("waiting for test stop frame")
                end
            end
        end)

        if not ok then
            test.fail(err)
        end
    end
end

function M.start()
    local step_frame_test = nil

    emu.register_prestart(function()
        local ok, result = pcall(make_frame_step)
        if not ok then
            test.fail(result)
            return
        end
        step_frame_test = result
    end)

    frame_subscription = emu.add_machine_frame_notifier(function()
        if step_frame_test == nil then
            return
        end
        local ok, err = pcall(step_frame_test)
        if not ok then
            test.fail(err)
        end
    end)
end

return M
