local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local test = dofile(script_directory .. "/mame-test.lua")

local M = {}
local frame_subscription

local function make_render_step()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary_directory .. "/invaders.equ")
    local symbols = test.load_symbols(binary_directory .. "/invaders-avo.sym")

    local inv_active = test.required_equate(equates, "inv_active")
    local inv_test_mode = test.required_equate(equates, "inv_test_mode")
    local inv_test_script = test.required_equate(equates, "inv_test_script")
    local inv_test_script_render = test.required_equate(equates, "inv_test_script_render")
    local inv_test_stop_lo = test.required_equate(equates, "inv_test_stop_lo")
    local inv_test_stop_hi = test.required_equate(equates, "inv_test_stop_hi")
    local inv_test_result = test.required_equate(equates, "inv_test_result")
    local pline_addr = test.required_equate(equates, "pline_addr")
    local in_setup = test.required_equate(equates, "in_setup")
    local key_flags = test.required_equate(equates, "key_flags")
    local key_silo = test.required_equate(equates, "key_silo")
    local inv_row_addr = test.required_symbol(symbols, "inv_row_addr")

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

    local function row_address(row)
        return read_u16(inv_row_addr + row * 2)
    end

    local function cell(row, column)
        return read_u8(row_address(row) + column)
    end

    local function sg(source)
        return string.byte(source) - 0x5f
    end

    local function render_complete()
        return cell(0, 0) == string.byte("R")
            and cell(0, 1) == string.byte("O")
            and cell(0, 2) == string.byte("M")
            and cell(1, 78) == string.byte("X")
            and cell(1, 79) == string.byte("Y")
            and cell(2, 4) == sg("l")
            and cell(2, 5) == sg("q")
            and cell(2, 6) == sg("k")
            and cell(3, 10) == sg("_")
            and cell(3, 11) == sg("a")
            and cell(3, 12) == sg("~")
            and cell(23, 79) == string.byte("!")
    end

    local function assert_cell(row, column, expected, description)
        test.assert_eq(cell(row, column), expected, description)
    end

    local function assert_render()
        for row = 0, 23 do
            test.assert_eq(
                row_address(row),
                read_u16(pline_addr + row * 2),
                "row address " .. tostring(row))
        end

        assert_cell(0, 0, string.byte("R"), "normal glyph R")
        assert_cell(0, 1, string.byte("O"), "normal glyph O")
        assert_cell(0, 2, string.byte("M"), "normal glyph M")
        assert_cell(0, 3, 0, "clear cell after normal glyphs")
        assert_cell(1, 77, 0, "clear cell before right-edge write")
        assert_cell(1, 78, string.byte("X"), "right-edge glyph X")
        assert_cell(1, 79, string.byte("Y"), "right-edge glyph Y")
        assert_cell(2, 0, 0, "right-edge write does not wrap")
        assert_cell(2, 4, sg("l"), "Special Graphics upper-left")
        assert_cell(2, 5, sg("q"), "Special Graphics horizontal line")
        assert_cell(2, 6, sg("k"), "Special Graphics upper-right")
        assert_cell(3, 10, sg("_"), "Special Graphics blank")
        assert_cell(3, 11, sg("a"), "Special Graphics checkerboard")
        assert_cell(3, 12, sg("~"), "Special Graphics bullet")
        assert_cell(4, 4, 0, "cleared playfield cell")
        assert_cell(23, 79, string.byte("!"), "last visible cell")
        test.assert_eq(read_u8(inv_active), 0, "render probe stopped game")
        test.assert_eq(read_u8(inv_test_result), 0, "render probe result")
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
            "%s timed out at frame %d: active=%s result=%s in_setup=%s",
            description,
            frame,
            test.hex(read_u8(inv_active), 2),
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
                write_u8(inv_test_script, inv_test_script_render)
                write_u8(inv_test_stop_lo, 0)
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
                enter_stage("wait-render")
                return
            end

            if stage == "wait-render" then
                if render_complete() then
                    assert_render()
                    test.pass()
                    return
                end
                if frame - stage_frame > 180 then
                    fail_timeout("render probe")
                end
            end
        end)

        if not ok then
            test.fail(err)
        end
    end
end

function M.start()
    local step_render_test = nil

    emu.register_prestart(function()
        local ok, result = pcall(make_render_step)
        if not ok then
            test.fail(result)
            return
        end
        step_render_test = result
    end)

    frame_subscription = emu.add_machine_frame_notifier(function()
        if step_render_test == nil then
            return
        end
        local ok, err = pcall(step_render_test)
        if not ok then
            test.fail(err)
        end
    end)
end

return M
