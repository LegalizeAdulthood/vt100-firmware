-- license:BSD-3-Clause

local exports = {
    name = "vt100invadershighscoreload",
    version = "0.0.1",
    description = "VT100 Invaders high-score load test",
    license = "BSD-3-Clause",
    author = { name = "VT100 Firmware" } }

local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local test = dofile(script_directory .. "/../mame-test.lua")
local frame_subscription
local frame_tap

local function make_high_score_load_step()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary_directory .. "/invaders-avo.equ")
    local symbols = test.load_symbols(binary_directory .. "/invaders-avo.sym")

    local inv_active = test.required_equate(equates, "inv_active")
    local inv_active_value = test.required_equate(equates, "inv_active_value")
    local inv_attract_mode = test.required_equate(equates, "inv_attract_mode")
    local inv_last_vframe = test.required_equate(equates, "inv_last_vframe")
    local inv_high_score_count = test.required_equate(equates, "inv_high_score_count")
    local inv_high_score_cache_base = test.required_equate(equates, "inv_high_score_cache_base")
    local inv_high_score_cache_top = test.required_equate(equates, "inv_high_score_cache_top")
    local inv_high_score_digit_base = test.required_equate(equates, "inv_high_score_digit_base")
    local inv_high_initial_lo_base = test.required_equate(equates, "inv_high_initial_lo_base")
    local inv_high_initial_hi_base = test.required_equate(equates, "inv_high_initial_hi_base")
    local inv_attract_title_row = test.required_equate(equates, "inv_attract_title_row")
    local inv_attract_title_col = test.required_equate(equates, "inv_attract_title_col")
    local inv_attract_scores_row = test.required_equate(equates, "inv_attract_scores_row")
    local inv_attract_scores_col = test.required_equate(equates, "inv_attract_scores_col")
    local inv_attract_scores_len = test.required_equate(equates, "inv_attract_scores_len")
    local inv_attract_prompt_row = test.required_equate(equates, "inv_attract_prompt_row")
    local inv_attract_prompt_col = test.required_equate(equates, "inv_attract_prompt_col")
    local inv_high_score_entry_width = test.required_equate(equates, "inv_high_score_entry_width")
    local inv_high_score_first_row = test.required_equate(equates, "inv_high_score_first_row")
    local inv_high_score_col = test.required_equate(equates, "inv_high_score_col")
    local nvr_addr = test.required_equate(equates, "nvr_addr")
    local nvr_data = test.required_equate(equates, "nvr_data")
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

    local function read_nibble(address)
        return read_u8(address) % 16
    end

    local function row_address(row)
        return read_u16(inv_row_addr + row * 2)
    end

    local function cell(row, column)
        return read_u8(row_address(row) + column)
    end

    local function high_score_units(slot)
        local address = inv_high_score_digit_base + slot * 3
        return read_nibble(address) +
            read_nibble(address + 1) * 10 +
            read_nibble(address + 2) * 100
    end

    local function initial_value(index)
        return read_nibble(inv_high_initial_lo_base + index) +
            read_nibble(inv_high_initial_hi_base + index) * 16
    end

    local function high_score_cache_state()
        local values = {}
        for offset = 0, 8 do
            values[#values + 1] = string.format("%X", read_nibble(inv_high_score_digit_base + offset))
        end
        return table.concat(values, "")
    end

    local function assert_loaded_eq(actual, expected, description)
        if actual ~= expected then
            test.fail(string.format(
                "%s: expected %s, got %s; nvr_addr=%s nvr_data=%s high_score_cache=%s",
                description,
                test.hex(expected, 4),
                test.hex(actual, 4),
                test.hex(read_u8(nvr_addr), 2),
                test.hex(read_u16(nvr_data), 4),
                high_score_cache_state()))
        end
    end

    local function inject_key(scan, modifiers)
        write_u8(key_flags, key_flag_eos + 1 + modifiers)
        write_u8(key_silo, scan)
        write_u8(key_silo + 1, 0)
        write_u8(key_silo + 2, 0)
        write_u8(key_silo + 3, 0)
    end

    local function poison_high_score_cache()
        for address = inv_high_score_cache_base, inv_high_score_cache_top do
            write_u8(address, test.invaders_junk_byte(address, inv_high_score_cache_base))
        end
    end

    local function assert_text(row, column, text)
        for index = 1, #text do
            test.assert_eq(
                cell(row, column + index - 1) % 128,
                string.byte(text, index),
                text .. " byte " .. tostring(index))
        end
    end

    local function assert_spaces(row, column, count, description)
        for offset = 0, count - 1 do
            test.assert_eq(
                cell(row, column + offset) % 128,
                string.byte(" "),
                description .. " byte " .. tostring(offset + 1))
        end
    end

    local function assert_box(top, left, height, width, top_corners, bottom_corners, description)
        local right, bottom = left + width - 1, top + height - 1
        local function assert_glyph(row, column, source)
            test.assert_eq(cell(row, column) % 128, string.byte(source) - 0x5f,
                string.format("%s border at %d,%d", description, row, column))
        end
        assert_glyph(top, left, top_corners:sub(1, 1))
        assert_glyph(top, right, top_corners:sub(2, 2))
        assert_glyph(bottom, left, bottom_corners:sub(1, 1))
        assert_glyph(bottom, right, bottom_corners:sub(2, 2))
        for column = left + 1, right - 1 do
            assert_glyph(top, column, "q")
            assert_glyph(bottom, column, "q")
        end
        for row = top + 1, bottom - 1 do
            assert_glyph(row, left, "x")
            assert_glyph(row, right, "x")
        end
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
            "%s timed out at frame %d: active=%s attract=%s setup=%s slot0=%s slot1=%s",
            description,
            frame,
            test.hex(read_u8(inv_active), 2),
            test.hex(read_u8(inv_attract_mode), 2),
            test.hex(read_u8(in_setup), 2),
            test.hex(high_score_units(0), 3),
            test.hex(high_score_units(1), 3)))
    end

    local function step(at_frame_boundary)
        local ok, err = pcall(function()
            if not at_frame_boundary then
                frame = frame + 1
                if frame - stage_frame > 120 then
                    fail_timeout(stage)
                end
            end
            if at_frame_boundary ~= (stage == "wait-overlay-stable") then
                return
            end

            if stage == "boot" then
                if frame < 120 then
                    return
                end
                test.poison_invaders_memory(equates, mem)
                poison_high_score_cache()
                write_u8(inv_active, 0)
                write_u8(inv_attract_mode, 0)
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
                enter_stage("wait-attract")
                return
            end

            if stage == "wait-attract" then
                if read_u8(inv_active) == inv_active_value and read_u8(inv_attract_mode) ~= 0 then
                    enter_stage("wait-overlay-stable")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("attract screen")
                end
                return
            end

            if stage == "wait-overlay-stable" then
                if frame - stage_frame < 6 then
                    return
                end
                if read_u8(inv_active) == inv_active_value and read_u8(inv_attract_mode) ~= 0 then
                    assert_box(inv_attract_title_row - 1, inv_attract_title_col - 1,
                        3, #"VT100 INVADERS" + 2, "lk", "mj", "title")
                    assert_box(inv_attract_scores_row - 1, inv_attract_scores_col - 1,
                        inv_high_score_count + 3, inv_attract_scores_len + 2, "lk", "tu", "high scores")
                    assert_box(inv_attract_prompt_row - 1, inv_attract_prompt_col - 1,
                        3, #"PRESS ENTER" + 2, "tu", "mj", "prompt")
                    assert_text(inv_attract_title_row, inv_attract_title_col, "VT100 INVADERS")
                    assert_text(inv_attract_prompt_row, inv_attract_prompt_col, "PRESS ENTER")
                    assert_text(inv_attract_scores_row, inv_attract_scores_col, "HIGH SCORES")
                    assert_loaded_eq(high_score_units(0), 123, "loaded high score slot 0")
                    assert_loaded_eq(high_score_units(1), 45, "loaded high score slot 1")
                    assert_loaded_eq(high_score_units(2), 0, "loaded high score slot 2")
                    assert_loaded_eq(initial_value(0), 0x21, "loaded initial A")
                    assert_loaded_eq(initial_value(1), 0x22, "loaded initial B")
                    assert_loaded_eq(initial_value(2), 0, "loaded initial space")
                    assert_loaded_eq(initial_value(3), 0x23, "loaded initial C")
                    assert_loaded_eq(initial_value(4), 0, "loaded second initial space")
                    assert_loaded_eq(initial_value(5), 0, "loaded third initial space")
                    assert_text(inv_high_score_first_row, inv_high_score_col, "AB  1230")
                    assert_text(inv_high_score_first_row + 1, inv_high_score_col, "C   0450")
                    for slot = 2, inv_high_score_count - 1 do
                        test.assert_eq(high_score_units(slot), 0, "empty loaded high score slot " .. tostring(slot))
                        assert_spaces(
                            inv_high_score_first_row + slot,
                            inv_high_score_col,
                            inv_high_score_entry_width,
                            "empty high score row " .. tostring(slot))
                    end
                    test.pass()
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("attract screen")
                end
            end
        end)

        if not ok then
            test.fail(err)
        end
    end

    -- Inspect the completed overlay before the next game frame starts drawing.
    frame_tap = mem:install_write_tap(inv_last_vframe, inv_last_vframe, "invaders-high-score-frame", function()
        step(true)
    end)
    return function() step(false) end
end

function exports.startplugin()
    local step_high_score_load_test = nil

    emu.register_prestart(function()
        local ok, result = pcall(make_high_score_load_step)
        if not ok then
            test.fail(result)
            return
        end
        step_high_score_load_test = result
    end)

    frame_subscription = emu.add_machine_frame_notifier(function()
        if step_high_score_load_test == nil then
            return
        end
        local ok, err = pcall(step_high_score_load_test)
        if not ok then
            test.fail(err)
        end
    end)
end

return exports
