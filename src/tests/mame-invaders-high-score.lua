local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local test = dofile(script_directory .. "/mame-test.lua")

local M = {}
local frame_subscription

local function make_high_score_step()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary_directory .. "/invaders-avo.equ")
    local symbols = test.load_symbols(binary_directory .. "/invaders-avo.sym")

    local inv_active = test.required_equate(equates, "inv_active")
    local inv_active_value = test.required_equate(equates, "inv_active_value")
    local inv_attract_mode = test.required_equate(equates, "inv_attract_mode")
    local inv_test_mode = test.required_equate(equates, "inv_test_mode")
    local inv_test_script = test.required_equate(equates, "inv_test_script")
    local inv_test_script_high_score = test.required_equate(equates, "inv_test_script_high_score")
    local inv_test_result = test.required_equate(equates, "inv_test_result")
    local inv_test_pending = test.required_equate(equates, "inv_test_pending")
    local inv_test_high_score_waiting = test.required_equate(equates, "inv_test_high_score_waiting")
    local inv_high_score_dirty = test.required_equate(equates, "inv_high_score_dirty")
    local inv_high_score_slot = test.required_equate(equates, "inv_high_score_slot")
    local inv_high_shift_index = test.required_equate(equates, "inv_high_shift_index")
    local inv_high_initial_index = test.required_equate(equates, "inv_high_initial_index")
    local inv_high_initial_used = test.required_equate(equates, "inv_high_initial_used")
    local inv_high_initial_ready = test.required_equate(equates, "inv_high_initial_ready")
    local inv_high_score_cache_base = test.required_equate(equates, "inv_high_score_cache_base")
    local inv_high_score_cache_top = test.required_equate(equates, "inv_high_score_cache_top")
    local inv_high_score_count = test.required_equate(equates, "inv_high_score_count")
    local inv_high_score_digit_base = test.required_equate(equates, "inv_high_score_digit_base")
    local inv_high_initial_count = test.required_equate(equates, "inv_high_initial_count")
    local inv_high_initial_lo_base = test.required_equate(equates, "inv_high_initial_lo_base")
    local inv_high_initial_hi_base = test.required_equate(equates, "inv_high_initial_hi_base")
    local inv_score0 = test.required_equate(equates, "inv_score0")
    local inv_score1 = test.required_equate(equates, "inv_score1")
    local inv_score2 = test.required_equate(equates, "inv_score2")
    local inv_gunners = test.required_equate(equates, "inv_gunners")
    local inv_turret_top_row = test.required_equate(equates, "inv_turret_top_row")
    local inv_turret_x_lo = test.required_equate(equates, "inv_turret_x_lo")
    local inv_turret_x_hi = test.required_equate(equates, "inv_turret_x_hi")
    local inv_missile_active_base = test.required_equate(equates, "inv_missile_active_base")
    local inv_missile_active_count = test.required_equate(equates, "inv_missile_active_count")
    local inv_missile_row_base = test.required_equate(equates, "inv_missile_row_base")
    local inv_missile_col_base = test.required_equate(equates, "inv_missile_col_base")
    local inv_missile_tick_timer = test.required_equate(equates, "inv_missile_tick_timer")
    local inv_high_score_first_row = test.required_equate(equates, "inv_high_score_first_row")
    local inv_high_score_col = test.required_equate(equates, "inv_high_score_col")
    local inv_high_prompt_title_row = test.required_equate(equates, "inv_high_prompt_title_row")
    local inv_high_prompt_title_col = test.required_equate(equates, "inv_high_prompt_title_col")
    local inv_high_prompt_initials_row = test.required_equate(equates, "inv_high_prompt_initials_row")
    local inv_high_prompt_initials_col = test.required_equate(equates, "inv_high_prompt_initials_col")
    local inv_high_prompt_entry_col = test.required_equate(equates, "inv_high_prompt_entry_col")
    local inv_high_prompt_score_row = test.required_equate(equates, "inv_high_prompt_score_row")
    local inv_high_prompt_score_col = test.required_equate(equates, "inv_high_prompt_score_col")
    local inv_scan_setup = test.required_equate(equates, "inv_scan_setup")
    local inv_scan_return_b = test.required_equate(equates, "inv_scan_return_b")
    local inv_scan_space = test.required_equate(equates, "inv_scan_space")
    local inv_scan_arrow_left = test.required_equate(equates, "inv_scan_arrow_left")
    local inv_scan_arrow_right = test.required_equate(equates, "inv_scan_arrow_right")
    local brightness = test.required_equate(equates, "brightness")
    local curs_col = test.required_equate(equates, "curs_col")
    local curs_row = test.required_equate(equates, "curs_row")
    local curs_char_rend = test.required_equate(equates, "curs_char_rend")
    local curs_attr_rend = test.required_equate(equates, "curs_attr_rend")
    local cursor_address = test.required_equate(equates, "cursor_address")
    local cursor_visible = test.required_equate(equates, "cursor_visible")
    local in_setup = test.required_equate(equates, "in_setup")
    local key_flags = test.required_equate(equates, "key_flags")
    local key_silo = test.required_equate(equates, "key_silo")
    local key_flag_shift = test.required_equate(equates, "key_flag_shift")
    local key_flag_eos = test.required_equate(equates, "key_flag_eos")
    local inv_row_addr = test.required_symbol(symbols, "inv_row_addr")

    local scan_i = 0x16
    local scan_a = 0x4a
    local scan_b = 0x68
    local scan_1 = 0x1a
    local scan_backspace = 0x33
    local scan_up = 0x30
    local scan_down = 0x22
    local setup_actions = {
        { scan = inv_scan_arrow_right, column = 1 },
        { scan = inv_scan_arrow_left, column = 0 },
    }
    local initial_actions = {
        { scan = inv_scan_return_b, modifiers = 0, index = 0, field = "___", reject_empty = true },
        { scan = inv_scan_arrow_left, modifiers = 0, index = 0, field = "___" },
        { scan = inv_scan_arrow_right, modifiers = 0, index = 1, field = "___" },
        { scan = inv_scan_arrow_right, modifiers = 0, index = 2, field = "___" },
        { scan = inv_scan_arrow_right, modifiers = 0, index = 2, field = "___" },
        { scan = inv_scan_return_b, modifiers = 0, index = 2, field = "___", reject_empty = true },
        { scan = scan_up, modifiers = 0, index = 2, field = "___" },
        { scan = scan_down, modifiers = 0, index = 2, field = "___" },
        { scan = scan_b, modifiers = 0, index = 3, value = 0x22, field = "__B", used = 4 },
        { scan = scan_backspace, modifiers = 0, index = 2, cleared = 2, field = "___", used = 0 },
        { scan = inv_scan_return_b, modifiers = 0, index = 2, field = "___", reject_empty = true },
        { scan = inv_scan_arrow_left, modifiers = 0, index = 1, field = "___" },
        { scan = inv_scan_arrow_left, modifiers = 0, index = 0, field = "___" },
        { scan = scan_a, modifiers = 0, index = 1, value = 0x21, field = "A__", used = 1 },
        { scan = scan_b, modifiers = 0, index = 2, value = 0x22, field = "AB_", used = 3 },
        { scan = scan_backspace, modifiers = 0, index = 1, cleared = 1, field = "A__", used = 1 },
        { scan = scan_1, modifiers = key_flag_shift, index = 2, value = 0x01, field = "A!_", used = 3 },
        { scan = scan_b, modifiers = 0, index = 3, value = 0x22, field = "A!B", used = 7 },
        { scan = scan_a, modifiers = 0, index = 3, field = "A!B" },
        { scan = inv_scan_arrow_left, modifiers = 0, index = 1, field = "A!B" },
        { scan = inv_scan_arrow_left, modifiers = 0, index = 0, field = "A!B" },
        { scan = inv_scan_arrow_left, modifiers = 0, index = 0, field = "A!B" },
        { scan = scan_b, modifiers = 0, index = 1, value = 0x22, field = "B!B", used = 7 },
        { scan = inv_scan_arrow_right, modifiers = 0, index = 2, field = "B!B" },
        { scan = inv_scan_arrow_right, modifiers = 0, index = 2, field = "B!B" },
        { scan = scan_b, modifiers = 0, index = 3, value = 0x22, field = "B!B", used = 7 },
        { scan = scan_backspace, modifiers = 0, index = 2, cleared = 2, field = "B!_", used = 3 },
        { scan = inv_scan_arrow_left, modifiers = 0, index = 1, field = "B!_" },
        { scan = scan_backspace, modifiers = 0, index = 0, cleared = 0, field = "_!_", used = 2 },
        { scan = scan_a, modifiers = 0, index = 1, value = 0x21, field = "A!_", used = 3 },
        { scan = inv_scan_arrow_left, modifiers = 0, index = 0, field = "A!_" },
        { scan = scan_up, modifiers = 0, index = 0, field = "A!_" },
        { scan = scan_down, modifiers = 0, index = 0, field = "A!_" },
        { scan = inv_scan_return_b, modifiers = 0, commit = true },
    }
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

    local function row_address(row)
        return read_u16(inv_row_addr + row * 2)
    end

    local function cell(row, column)
        return read_u8(row_address(row) + column)
    end

    local function read_nibble(address)
        return read_u8(address) % 16
    end

    local function inject_key(scan, modifiers)
        write_u8(key_flags, key_flag_eos + 1 + modifiers)
        write_u8(key_silo, scan)
        write_u8(key_silo + 1, 0)
        write_u8(key_silo + 2, 0)
        write_u8(key_silo + 3, 0)
    end

    local function high_score_units(slot)
        local address = inv_high_score_digit_base + slot * 3
        return read_nibble(address) +
            read_nibble(address + 1) * 10 +
            read_nibble(address + 2) * 100
    end

    local function score_units()
        return read_nibble(inv_score0) +
            read_nibble(inv_score1) * 10 +
            read_nibble(inv_score2) * 100
    end

    local function initial_value(index)
        return read_nibble(inv_high_initial_lo_base + index) +
            read_nibble(inv_high_initial_hi_base + index) * 16
    end

    local function assert_empty_high_scores()
        for slot = 0, inv_high_score_count - 1 do
            test.assert_eq(high_score_units(slot), 0, "reset high score slot " .. tostring(slot))
        end
        for index = 0, inv_high_initial_count - 1 do
            test.assert_eq(initial_value(index), 0, "reset high score initial " .. tostring(index))
        end
    end

    local function poison_high_score_cache()
        for address = inv_high_score_cache_base, inv_high_score_cache_top do
            write_u8(address, test.invaders_junk_byte(address, inv_high_score_cache_base))
        end
    end

    local function high_score_state()
        return string.format(
            "score=%s slot0=%s slot1=%s dirty=%s slot=%s shift=%s initial=%s result=%s",
            test.hex(score_units(), 3),
            test.hex(high_score_units(0), 3),
            test.hex(high_score_units(1), 3),
            test.hex(read_nibble(inv_high_score_dirty), 1),
            test.hex(read_nibble(inv_high_score_slot), 1),
            test.hex(read_nibble(inv_high_shift_index), 1),
            test.hex(read_nibble(inv_high_initial_index), 1),
            test.hex(read_u8(inv_test_result), 2))
    end

    local function assert_text(row, column, text)
        for index = 1, #text do
            test.assert_eq(
                cell(row, column + index - 1) % 128,
                string.byte(text, index),
                text .. " byte " .. tostring(index))
        end
    end

    local function assert_initial_cursor(index, description)
        local cursor_index = index
        if cursor_index > 2 then
            cursor_index = 2
        end
        test.assert_eq(read_u8(curs_row), inv_high_prompt_initials_row, description .. " cursor row")
        test.assert_eq(
            read_u8(curs_col),
            inv_high_prompt_entry_col + cursor_index,
            description .. " cursor column")
        test.assert_eq(read_u8(curs_char_rend), 0x80, description .. " cursor character rendition")
        test.assert_eq(read_u8(curs_attr_rend), 0, description .. " cursor attribute rendition")
        test.assert_eq(
            read_u16(cursor_address),
            row_address(inv_high_prompt_initials_row) + inv_high_prompt_entry_col + cursor_index,
            description .. " cursor screen address")
        for row = 0, 23 do
            for column = 0, 79 do
                local expected = read_u8(cursor_visible) ~= 0
                    and row == inv_high_prompt_initials_row
                    and column == inv_high_prompt_entry_col + cursor_index and 0x80 or 0
                test.assert_eq(cell(row, column) & 0x80, expected,
                    description .. " cursor bit at " .. row .. "," .. column)
            end
        end
    end

    local function assert_rendered_initial_cursor()
        local screen = manager.machine.screens[":screen"]
        local cell_width = screen.width / 80
        local cell_height = screen.height / 25
        screen:snapshot("initial-cursor.png")
        for y = 0, cell_height - 1 do
            for x = 0, screen.width - 1 do
                test.assert_eq(screen:pixel(x, y) & 0xffffff, 0, "no cursor on top row")
            end
        end
        test.assert_between(screen:pixel(inv_high_prompt_entry_col * cell_width + 1,
            inv_high_prompt_initials_row * cell_height + 1) & 0xffffff, 1, 0xffffff,
            "rendered cursor on first initial")
    end

    local function assert_game_cursor_disabled(description)
        test.assert_eq(read_u8(curs_char_rend), 0, description .. " cursor character rendition")
        test.assert_eq(read_u8(curs_attr_rend), 0, description .. " cursor attribute rendition")
    end

    local frame = 0
    local stage = "boot"
    local stage_frame = 0
    local setup_key_repeats = 0
    local shift_i_repeats = 0
    local enter_key_repeats = 0
    local initial_action_index = 1
    local initial_key_repeats = 0
    local setup_action_index = 1
    local setup_action_repeats = 0
    local initial_brightness
    local final_cursor_visible_frame

    local function enter_stage(next_stage)
        stage = next_stage
        stage_frame = frame
    end

    local function fail_timeout(description)
        test.fail(string.format(
            "%s timed out at frame %d: active=%s attract=%s setup=%s result=%s score=%s",
            description,
            frame,
            test.hex(read_u8(inv_active), 2),
            test.hex(read_u8(inv_attract_mode), 2),
            test.hex(read_u8(in_setup), 2),
            test.hex(read_u8(inv_test_result), 2),
            test.hex(read_nibble(inv_score0) + read_nibble(inv_score1) * 10 + read_nibble(inv_score2) * 100, 3)))
    end

    return function()
        local ok, err = pcall(function()
            frame = frame + 1

            if stage == "boot" then
                if frame < 120 then
                    return
                end
                test.poison_invaders_memory(equates, mem)
                poison_high_score_cache()
                test.enable_invaders_test_mode(equates, mem)
                write_u8(inv_active, 0)
                write_u8(inv_attract_mode, 0)
                write_u8(inv_test_mode, 1)
                write_u8(inv_test_script, inv_test_script_high_score)
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
                if read_u8(in_setup) ~= 0 and frame - stage_frame >= 3 then
                    enter_stage("setup-arrow")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("entering SET-UP")
                end
                return
            end

            if stage == "setup-arrow" then
                local action = setup_actions[setup_action_index]
                if setup_action_repeats < 2 then
                    inject_key(action.scan, 0)
                    setup_action_repeats = setup_action_repeats + 1
                    return
                end
                if read_u8(curs_col) == action.column then
                    setup_action_index = setup_action_index + 1
                    setup_action_repeats = 0
                    enter_stage(setup_action_index <= #setup_actions and "setup-arrow" or "shift-i")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("ordinary SET-UP arrow")
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
                    assert_empty_high_scores()
                    assert_text(8, 34, "HIGH SCORES")
                    enter_stage("enter-key")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("attract screen")
                end
                return
            end

            if stage == "enter-key" then
                if enter_key_repeats < 2 then
                    inject_key(inv_scan_return_b, 0)
                    enter_key_repeats = enter_key_repeats + 1
                    return
                end
                enter_stage("arm-high-score-probe")
                return
            end

            if stage == "arm-high-score-probe" then
                if read_u8(inv_active) == inv_active_value
                    and read_u8(inv_attract_mode) == 0 then
                    write_u8(inv_test_result, inv_test_pending)
                    enter_stage("wait-result")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("arming high-score probe")
                end
                return
            end

            if stage == "wait-result" then
                local result = read_u8(inv_test_result)
                if read_u8(inv_active) == inv_active_value
                    and result == inv_test_high_score_waiting
                    and read_u8(inv_high_score_dirty) ~= 0 then
                    if score_units() ~= 123 then
                        test.fail("high-score probe stopped before setting score: " .. high_score_state())
                    end
                    test.assert_eq(high_score_units(0), 123, "stored high score slot 0")
                    test.assert_eq(high_score_units(1), 0, "stored high score slot 1")
                    test.assert_eq(read_u8(inv_high_score_slot), 0, "pending high score slot")
                    test.assert_eq(read_u8(inv_high_initial_index), 0, "pending initial index")
                    test.assert_eq(read_u8(inv_high_initial_used), 0, "pending initials empty")
                    assert_text(inv_high_prompt_title_row, inv_high_prompt_title_col, "NEW HIGH SCORE")
                    assert_text(inv_high_prompt_initials_row, inv_high_prompt_initials_col, "ENTER INITIALS ___")
                    assert_text(inv_high_prompt_score_row, inv_high_prompt_score_col, "SCORE 1230")
                    assert_initial_cursor(0, "pending initials")
                    initial_brightness = read_u8(brightness)
                    enter_stage("wait-first-cursor")
                    return
                end
                if result ~= inv_test_pending and result ~= inv_test_high_score_waiting then
                    test.fail("high-score probe failed with result " .. test.hex(result, 2))
                end
                if frame - stage_frame > 240 then
                    fail_timeout("high-score prompt")
                end
                return
            end

            if stage == "wait-first-cursor" then
                assert_initial_cursor(0, "waiting for first initial")
                if read_u8(cursor_visible) ~= 0 and frame - stage_frame >= 3 then
                    test.assert_eq(
                        cell(inv_high_prompt_initials_row, inv_high_prompt_entry_col),
                        string.byte("_") + 0x80,
                        "visible cursor on first initial")
                    enter_stage("initial-key")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("first initial cursor")
                end
                return
            end

            if stage == "initial-key" then
                local action = initial_actions[initial_action_index]
                if initial_key_repeats < 2 then
                    inject_key(action.scan, action.modifiers)
                    initial_key_repeats = initial_key_repeats + 1
                    return
                end
                initial_key_repeats = 0
                enter_stage("wait-initial")
                return
            end

            if stage == "wait-initial" then
                local action = initial_actions[initial_action_index]
                if action.commit then
                    if read_u8(inv_high_score_dirty) == 0
                        and read_u8(inv_attract_mode) ~= 0 then
                        test.assert_eq(high_score_units(0), 123, "stored high score slot 0")
                        test.assert_eq(high_score_units(1), 0, "stored high score slot 1")
                        test.assert_eq(initial_value(0), 0x21, "stored initials char 0")
                        test.assert_eq(initial_value(1), 0x01, "stored initials char 1")
                        test.assert_eq(initial_value(2), 0, "stored initials char 2")
                        test.assert_eq(read_nibble(inv_high_score_dirty), 0, "high score dirty flag")
                        assert_text(inv_high_score_first_row, inv_high_score_col, "A!  1230")
                        assert_game_cursor_disabled("attract after high-score entry")
                        enter_stage("wait-nvr-save")
                        return
                    end
                    if frame - stage_frame > 240 then
                        fail_timeout("high-score initials completion")
                    end
                    return
                end
                if read_u8(inv_high_initial_index) == action.index then
                    test.assert_eq(read_u8(brightness), initial_brightness, "initials do not change brightness")
                    if action.reject_empty then
                        test.assert_eq(read_nibble(inv_high_score_dirty), 15, "empty return leaves entry dirty")
                        test.assert_eq(read_u8(inv_high_initial_used), 0, "empty return requires an initial")
                    end
                    if action.used ~= nil then
                        test.assert_eq(read_u8(inv_high_initial_used), action.used, "occupied initial positions")
                    end
                    if action.value ~= nil then
                        test.assert_eq(
                            initial_value(action.index - 1),
                            action.value,
                            "stored initial action " .. tostring(initial_action_index))
                    end
                    if action.cleared ~= nil then
                        test.assert_eq(
                            initial_value(action.cleared),
                            0,
                            "cleared initial action " .. tostring(initial_action_index))
                    end
                    assert_text(inv_high_prompt_initials_row, inv_high_prompt_entry_col, action.field)
                    assert_initial_cursor(action.index, "initial action " .. tostring(initial_action_index))
                    initial_action_index = initial_action_index + 1
                    if initial_action_index <= #initial_actions then
                        enter_stage("initial-key")
                    end
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("initial action " .. tostring(initial_action_index))
                end
                return
            end

            if stage == "wait-nvr-save" then
                if frame - stage_frame > 120 then
                    enter_key_repeats = 0
                    enter_stage("restart-key")
                end
                return
            end

            if stage == "restart-key" then
                if enter_key_repeats < 2 then
                    inject_key(inv_scan_return_b, 0)
                    enter_key_repeats = enter_key_repeats + 1
                    return
                end
                enter_stage("wait-restart")
                return
            end

            if stage == "wait-restart" then
                if read_u8(inv_active) == inv_active_value
                    and read_u8(inv_attract_mode) == 0 then
                    assert_game_cursor_disabled("gameplay after high-score entry")
                    write_u8(inv_test_mode, 0)
                    write_u8(inv_score0, 4)
                    write_u8(inv_score1, 2)
                    write_u8(inv_score2, 1)
                    write_u8(inv_gunners, 1)
                    write_u8(inv_missile_active_base, 0xff)
                    write_u8(inv_missile_active_count, 1)
                    write_u8(inv_missile_row_base, inv_turret_top_row - 1)
                    write_u8(inv_missile_col_base,
                        read_nibble(inv_turret_x_lo) + read_nibble(inv_turret_x_hi) * 16 + 3)
                    write_u8(inv_missile_tick_timer, 1)
                    inject_key(inv_scan_space, 0)
                    enter_stage("wait-final-life-cursor")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("restart after high-score entry")
                end
            end

            if stage == "wait-final-life-cursor" then
                if read_u8(inv_high_score_dirty) == 0 then
                    if frame - stage_frame > 120 then
                        fail_timeout("final life presentation")
                    end
                    inject_key(inv_scan_space, 0)
                    return
                end
                if read_u8(inv_high_score_dirty) ~= 0 and read_u8(curs_char_rend) ~= 0
                    and read_u8(cursor_visible) ~= 0 then
                    -- Let both interlaced display fields catch up with the RAM cursor.
                    final_cursor_visible_frame = final_cursor_visible_frame or frame
                    if frame - final_cursor_visible_frame < 2 then
                        return
                    end
                    test.assert_eq(read_u8(inv_high_initial_index), 0, "final life initial index")
                    test.assert_eq(read_u8(inv_high_initial_used), 0, "final life initials empty")
                    assert_initial_cursor(0, "final life initials")
                    assert_text(inv_high_prompt_initials_row, inv_high_prompt_initials_col, "ENTER INITIALS ___")
                    test.assert_eq(
                        cell(inv_high_prompt_initials_row, inv_high_prompt_entry_col),
                        string.byte("_") + 0x80,
                        "final life visible cursor on first initial")
                    assert_rendered_initial_cursor()
                    initial_key_repeats = 0
                    enter_stage("release-fire-key")
                    return
                end
                final_cursor_visible_frame = nil
                if frame - stage_frame > 120 then
                    fail_timeout("final life initial cursor")
                end
            end

            if stage == "release-fire-key" then
                test.assert_eq(read_u8(inv_high_initial_index), 0, "released fire leaves initials empty")
                if read_u8(inv_high_initial_ready) ~= 0 then
                    enter_stage("fresh-initial-key")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("releasing fire before initials")
                end
                return
            end

            if stage == "fresh-initial-key" then
                if initial_key_repeats < 2 then
                    inject_key(scan_a, 0)
                    initial_key_repeats = initial_key_repeats + 1
                    return
                end
                if read_u8(inv_high_initial_index) == 1 then
                    assert_text(inv_high_prompt_initials_row, inv_high_prompt_entry_col, "A__")
                    assert_initial_cursor(1, "fresh initial after fire release")
                    test.pass()
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("fresh initial after fire release")
                end
            end
        end)

        if not ok then
            test.fail(err)
        end
    end
end

function M.start()
    local step_high_score_test = nil

    emu.register_prestart(function()
        local ok, result = pcall(make_high_score_step)
        if not ok then
            test.fail(result)
            return
        end
        step_high_score_test = result
    end)

    frame_subscription = emu.add_machine_frame_notifier(function()
        if step_high_score_test == nil then
            return
        end
        local ok, err = pcall(step_high_score_test)
        if not ok then
            test.fail(err)
        end
    end)
end

return M
