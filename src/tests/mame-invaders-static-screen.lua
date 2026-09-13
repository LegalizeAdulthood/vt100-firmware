local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local test = dofile(script_directory .. "/mame-test.lua")

local M = {}
local frame_subscription

local function make_static_screen_step()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary_directory .. "/invaders-avo.equ")
    local symbols = test.load_symbols(binary_directory .. "/invaders-avo.sym")

    local inv_active = test.required_equate(equates, "inv_active")
    local inv_test_mode = test.required_equate(equates, "inv_test_mode")
    local inv_test_script = test.required_equate(equates, "inv_test_script")
    local inv_test_stop_lo = test.required_equate(equates, "inv_test_stop_lo")
    local inv_test_stop_hi = test.required_equate(equates, "inv_test_stop_hi")
    local inv_test_result = test.required_equate(equates, "inv_test_result")
    local inv_score0 = test.required_equate(equates, "inv_score0")
    local inv_score1 = test.required_equate(equates, "inv_score1")
    local inv_score2 = test.required_equate(equates, "inv_score2")
    local inv_gunners = test.required_equate(equates, "inv_gunners")
    local inv_level = test.required_equate(equates, "inv_level")
    local inv_saved_led_state = test.required_equate(equates, "inv_saved_led_state")
    local inv_game_over = test.required_equate(equates, "inv_game_over")
    local inv_turret_x_lo = test.required_equate(equates, "inv_turret_x_lo")
    local inv_turret_x_hi = test.required_equate(equates, "inv_turret_x_hi")
    local inv_shield_damage_base = test.required_equate(equates, "inv_shield_damage_base")
    local inv_shield_damage_count = test.required_equate(equates, "inv_shield_damage_count")
    local inv_shield_cells_base = test.required_equate(equates, "inv_shield_cells_base")
    local inv_score_row = test.required_equate(equates, "inv_score_row")
    local inv_ground_row = test.required_equate(equates, "inv_ground_row")
    local inv_play_left = test.required_equate(equates, "inv_play_left")
    local inv_play_width = test.required_equate(equates, "inv_play_width")
    local inv_shield_top_row = test.required_equate(equates, "inv_shield_top_row")
    local inv_shield_w = test.required_equate(equates, "inv_shield_w")
    local inv_shield_h = test.required_equate(equates, "inv_shield_h")
    local inv_shield0_x = test.required_equate(equates, "inv_shield0_x")
    local inv_shield1_x = test.required_equate(equates, "inv_shield1_x")
    local inv_shield2_x = test.required_equate(equates, "inv_shield2_x")
    local inv_shield3_x = test.required_equate(equates, "inv_shield3_x")
    local inv_turret_top_row = test.required_equate(equates, "inv_turret_top_row")
    local inv_turret_start_x = test.required_equate(equates, "inv_turret_start_x")
    local inv_initial_gunners = test.required_equate(equates, "inv_initial_gunners")
    local inv_initial_level = test.required_equate(equates, "inv_initial_level")
    local inv_cell_blank = test.required_equate(equates, "inv_cell_blank")
    local inv_cell_checker = test.required_equate(equates, "inv_cell_checker")
    local inv_cell_roof_left = test.required_equate(equates, "inv_cell_roof_left")
    local inv_cell_roof_right = test.required_equate(equates, "inv_cell_roof_right")
    local led_state = test.required_equate(equates, "led_state")
    local in_setup = test.required_equate(equates, "in_setup")
    local key_flags = test.required_equate(equates, "key_flags")
    local key_silo = test.required_equate(equates, "key_silo")
    local inv_row_addr = test.required_symbol(symbols, "inv_row_addr")

    local key_flag_shift = 0x20
    local key_flag_eos = 0x80
    local scan_setup = 0x7b
    local scan_i = 0x16
    local original_led_state = 0x0a
    local game_led_state = 0x0f

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

    local function row_address(row)
        return read_u16(inv_row_addr + row * 2)
    end

    local function cell(row, column)
        return read_u8(row_address(row) + column)
    end

    local function sg(source)
        return string.byte(source) - 0x5f
    end

    local function inject_key(scan, modifiers)
        write_u8(key_flags, key_flag_eos + 1 + modifiers)
        write_u8(key_silo, scan)
        write_u8(key_silo + 1, 0)
        write_u8(key_silo + 2, 0)
        write_u8(key_silo + 3, 0)
    end

    local function assert_cell(row, column, expected, description)
        test.assert_eq(cell(row, column), expected, description)
    end

    local function assert_text(row, column, text)
        for index = 1, #text do
            assert_cell(
                row,
                column + index - 1,
                string.byte(text, index),
                text .. " byte " .. tostring(index))
        end
    end

    local shield_cells = {
        inv_cell_roof_left, inv_cell_checker, inv_cell_checker, inv_cell_checker,
        inv_cell_checker, inv_cell_checker, inv_cell_roof_right,
        inv_cell_checker, inv_cell_checker, inv_cell_checker,
        inv_cell_checker, inv_cell_checker, inv_cell_checker,
        inv_cell_checker,
        inv_cell_checker, inv_cell_checker, inv_cell_checker,
        inv_cell_blank, inv_cell_checker, inv_cell_checker, inv_cell_checker,
    }

    local shield_glyphs = {
        string.byte("/"), sg("a"), sg("a"), sg("a"), sg("a"), sg("a"), string.byte("\\"),
        sg("a"), sg("a"), sg("a"), sg("a"), sg("a"), sg("a"), sg("a"),
        sg("a"), sg("a"), sg("a"), sg("_"), sg("a"), sg("a"), sg("a"),
    }

    local shield_x = {
        inv_shield0_x,
        inv_shield1_x,
        inv_shield2_x,
        inv_shield3_x,
    }

    local function assert_shields()
        for damage_index = 0, inv_shield_damage_count - 1 do
            test.assert_eq(
                read_u8(inv_shield_damage_base + damage_index),
                0,
                "shield damage " .. tostring(damage_index))
        end

        local index = 0
        for shield = 1, #shield_x do
            for cell_index = 1, #shield_cells do
                test.assert_eq(
                    read_u8(inv_shield_cells_base + index),
                    shield_cells[cell_index],
                    "shield cell " .. tostring(index))
                index = index + 1
            end

            local glyph = 1
            for row = 0, inv_shield_h - 1 do
                for column = 0, inv_shield_w - 1 do
                    assert_cell(
                        inv_shield_top_row + row,
                        shield_x[shield] + column,
                        shield_glyphs[glyph],
                        "shield " .. tostring(shield) .. " glyph " .. tostring(glyph))
                    glyph = glyph + 1
                end
            end
        end
    end

    local function assert_static_screen()
        test.assert_eq(read_u8(inv_score0), 0, "score0")
        test.assert_eq(read_u8(inv_score1), 0, "score1")
        test.assert_eq(read_u8(inv_score2), 0, "score2")
        test.assert_eq(read_u8(inv_gunners), inv_initial_gunners, "gunners")
        test.assert_eq(read_u8(inv_level), inv_initial_level, "level")
        test.assert_eq(read_u8(inv_game_over), 0, "game over")
        test.assert_eq(read_u8(inv_saved_led_state), original_led_state % 16, "saved LEDs")
        test.assert_eq(read_u8(led_state), game_led_state, "game LEDs")
        test.assert_eq(
            read_u8(inv_turret_x_lo) + read_u8(inv_turret_x_hi) * 16,
            inv_turret_start_x,
            "turret x")

        assert_text(inv_score_row, 0, "SCORE 0000  LEVEL 1")
        assert_cell(inv_ground_row, inv_play_left, sg("q"), "ground left edge")
        assert_cell(inv_ground_row, inv_turret_start_x - 1, sg("q"), "ground before turret")
        assert_cell(inv_ground_row, inv_turret_start_x, sg("_"), "turret clears ground left")
        assert_cell(inv_ground_row, inv_turret_start_x + 3, sg("a"), "turret top")
        assert_cell(inv_ground_row, inv_turret_start_x + 7, sg("q"), "ground after turret")
        assert_cell(
            inv_ground_row,
            inv_play_left + inv_play_width - 1,
            sg("q"),
            "ground right edge")
        assert_cell(inv_turret_top_row + 1, inv_turret_start_x, sg("_"), "turret bottom left")
        assert_cell(inv_turret_top_row + 1, inv_turret_start_x + 1, sg("a"), "turret bottom")
        assert_cell(inv_turret_top_row + 1, inv_turret_start_x + 5, sg("a"), "turret bottom right")
        assert_cell(inv_turret_top_row + 1, inv_turret_start_x + 6, sg("_"), "turret bottom blank")
        assert_shields()
    end

    local function static_screen_ready()
        return read_u8(inv_active) ~= 0
            and cell(inv_score_row, 0) == string.byte("S")
            and cell(inv_ground_row, inv_play_left) == sg("q")
            and cell(inv_turret_top_row + 1, inv_turret_start_x + 3) == sg("a")
            and read_u8(led_state) == game_led_state
    end

    local frame = 0
    local stage = "boot"
    local stage_frame = 0
    local setup_key_repeats = 0
    local shift_i_repeats = 0
    local exit_key_repeats = 0

    local function enter_stage(next_stage)
        stage = next_stage
        stage_frame = frame
    end

    local function fail_timeout(description)
        test.fail(string.format(
            "%s timed out at frame %d: active=%s LEDs=%s in_setup=%s",
            description,
            frame,
            test.hex(read_u8(inv_active), 2),
            test.hex(read_u8(led_state), 2),
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
                write_u8(inv_active, 0)
                write_u8(led_state, original_led_state)
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
                enter_stage("wait-static")
                return
            end

            if stage == "wait-static" then
                if static_screen_ready() then
                    assert_static_screen()
                    enter_stage("exit-key")
                    return
                end
                if frame - stage_frame > 180 then
                    fail_timeout("static screen")
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
                    test.assert_eq(read_u8(led_state), original_led_state, "restored LEDs")
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
    local step_static_screen_test = nil

    emu.register_prestart(function()
        local ok, result = pcall(make_static_screen_step)
        if not ok then
            test.fail(result)
            return
        end
        step_static_screen_test = result
    end)

    frame_subscription = emu.add_machine_frame_notifier(function()
        if step_static_screen_test == nil then
            return
        end
        local ok, err = pcall(step_static_screen_test)
        if not ok then
            test.fail(err)
        end
    end)
end

return M
