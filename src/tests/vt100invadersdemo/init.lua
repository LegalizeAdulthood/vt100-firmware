-- license:BSD-3-Clause

local exports = {
    name = "vt100invadersdemo",
    version = "0.0.1",
    description = "VT100 Invaders attract demo state test",
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

local function make_demo_state_step()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary_directory .. "/invaders-avo.equ")
    local symbols = test.load_symbols(binary_directory .. "/invaders-avo.sym")

    local inv_active = test.required_equate(equates, "inv_active")
    local inv_active_value = test.required_equate(equates, "inv_active_value")
    local inv_attract_mode = test.required_equate(equates, "inv_attract_mode")
    local inv_frame_lo = test.required_equate(equates, "inv_frame_lo")
    local inv_frame_hi = test.required_equate(equates, "inv_frame_hi")
    local inv_score0 = test.required_equate(equates, "inv_score0")
    local inv_score1 = test.required_equate(equates, "inv_score1")
    local inv_score2 = test.required_equate(equates, "inv_score2")
    local inv_gunners = test.required_equate(equates, "inv_gunners")
    local inv_level = test.required_equate(equates, "inv_level")
    local inv_game_over = test.required_equate(equates, "inv_game_over")
    local inv_high_score_dirty = test.required_equate(equates, "inv_high_score_dirty")
    local inv_high_initial_index = test.required_equate(equates, "inv_high_initial_index")
    local inv_turret_x_lo = test.required_equate(equates, "inv_turret_x_lo")
    local inv_turret_x_hi = test.required_equate(equates, "inv_turret_x_hi")
    local inv_initial_gunners = test.required_equate(equates, "inv_initial_gunners")
    local inv_initial_level = test.required_equate(equates, "inv_initial_level")
    local inv_turret_start_x = test.required_equate(equates, "inv_turret_start_x")
    local inv_turret_start_x_lo = test.required_equate(equates, "inv_turret_start_x_lo")
    local inv_turret_start_x_hi = test.required_equate(equates, "inv_turret_start_x_hi")
    local inv_score_row = test.required_equate(equates, "inv_score_row")
    local inv_ground_row = test.required_equate(equates, "inv_ground_row")
    local inv_play_left = test.required_equate(equates, "inv_play_left")
    local inv_play_width = test.required_equate(equates, "inv_play_width")
    local inv_cell_blank = test.required_equate(equates, "inv_cell_blank")
    local inv_cell_checker = test.required_equate(equates, "inv_cell_checker")
    local inv_cell_roof_left = test.required_equate(equates, "inv_cell_roof_left")
    local inv_cell_roof_right = test.required_equate(equates, "inv_cell_roof_right")
    local inv_shield_w = test.required_equate(equates, "inv_shield_w")
    local inv_shield_cells_each = test.required_equate(equates, "inv_shield_cells_each")
    local inv_shield_count = test.required_equate(equates, "inv_shield_count")
    local inv_shield_damage_count = test.required_equate(equates, "inv_shield_damage_count")
    local inv_shield_cells_base = test.required_equate(equates, "inv_shield_cells_base")
    local inv_shield_damage_base = test.required_equate(equates, "inv_shield_damage_base")
    local inv_alien_rows = test.required_equate(equates, "inv_alien_rows")
    local inv_alien_cols = test.required_equate(equates, "inv_alien_cols")
    local inv_alien_count = test.required_equate(equates, "inv_alien_count")
    local inv_alien_slot_w = test.required_equate(equates, "inv_alien_slot_w")
    local inv_alien_slot_h = test.required_equate(equates, "inv_alien_slot_h")
    local inv_alien_start_x = test.required_equate(equates, "inv_alien_start_x")
    local inv_alien_top_row = test.required_equate(equates, "inv_alien_top_row")
    local inv_alien_dir_right = test.required_equate(equates, "inv_alien_dir_right")
    local inv_alien_init_lo = test.required_equate(equates, "inv_alien_init_lo")
    local inv_alien_init_hi = test.required_equate(equates, "inv_alien_init_hi")
    local inv_alien_live_lo = test.required_equate(equates, "inv_alien_live_lo")
    local inv_alien_live_hi = test.required_equate(equates, "inv_alien_live_hi")
    local inv_alien_last_lo = test.required_equate(equates, "inv_alien_last_lo")
    local inv_alien_last_hi = test.required_equate(equates, "inv_alien_last_hi")
    local inv_alien_dir = test.required_equate(equates, "inv_alien_dir")
    local inv_alien_reverse = test.required_equate(equates, "inv_alien_reverse")
    local inv_alien_y_delta = test.required_equate(equates, "inv_alien_y_delta")
    local inv_alien_descents = test.required_equate(equates, "inv_alien_descents")
    local inv_alien_anim_phase = test.required_equate(equates, "inv_alien_anim_phase")
    local inv_alien_min_col = test.required_equate(equates, "inv_alien_min_col")
    local inv_alien_max_col = test.required_equate(equates, "inv_alien_max_col")
    local inv_alien_min_row = test.required_equate(equates, "inv_alien_min_row")
    local inv_alien_max_row = test.required_equate(equates, "inv_alien_max_row")
    local inv_alien_live_base = test.required_equate(equates, "inv_alien_live_base")
    local inv_alien_x_lo_base = test.required_equate(equates, "inv_alien_x_lo_base")
    local inv_alien_x_hi_base = test.required_equate(equates, "inv_alien_x_hi_base")
    local inv_alien_y_lo_base = test.required_equate(equates, "inv_alien_y_lo_base")
    local inv_alien_y_hi_base = test.required_equate(equates, "inv_alien_y_hi_base")
    local inv_missile_count = test.required_equate(equates, "inv_missile_count")
    local inv_missile_active_count = test.required_equate(equates, "inv_missile_active_count")
    local inv_missile_active_base = test.required_equate(equates, "inv_missile_active_base")
    local inv_ufo_state = test.required_equate(equates, "inv_ufo_state")
    local inv_ufo_timer_lo = test.required_equate(equates, "inv_ufo_timer_lo")
    local inv_ufo_timer_hi = test.required_equate(equates, "inv_ufo_timer_hi")
    local inv_ufo_first_delay_lo = test.required_equate(equates, "inv_ufo_first_delay_lo")
    local inv_ufo_first_delay_hi = test.required_equate(equates, "inv_ufo_first_delay_hi")
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
    local inv_attract_prompt_row = test.required_equate(equates, "inv_attract_prompt_row")
    local inv_attract_prompt_col = test.required_equate(equates, "inv_attract_prompt_col")
    local inv_high_score_first_row = test.required_equate(equates, "inv_high_score_first_row")
    local inv_high_score_col = test.required_equate(equates, "inv_high_score_col")
    local inv_high_score_entry_width = test.required_equate(equates, "inv_high_score_entry_width")
    local inv_scan_setup = test.required_equate(equates, "inv_scan_setup")
    local inv_scan_return_b = test.required_equate(equates, "inv_scan_return_b")
    local in_setup = test.required_equate(equates, "in_setup")
    local key_flags = test.required_equate(equates, "key_flags")
    local key_silo = test.required_equate(equates, "key_silo")
    local key_flag_shift = test.required_equate(equates, "key_flag_shift")
    local key_flag_eos = test.required_equate(equates, "key_flag_eos")
    local led_state = test.required_equate(equates, "led_state")
    local inv_row_addr = test.required_symbol(symbols, "inv_row_addr")

    local scan_i = 0x16
    local game_led_state = 0x0f
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

    local function read_nibble(address)
        return read_u8(address) % 16
    end

    local function read_nibble_pair(lo_address, hi_address)
        return read_nibble(lo_address) + read_nibble(hi_address) * 16
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

    local function turret_x()
        return read_nibble_pair(inv_turret_x_lo, inv_turret_x_hi)
    end

    local function set_turret_x(value)
        write_nibble_pair(inv_turret_x_lo, inv_turret_x_hi, value)
    end

    local function game_frame()
        return read_nibble_pair(inv_frame_lo, inv_frame_hi)
    end

    local function alien_init_count()
        return read_nibble_pair(inv_alien_init_lo, inv_alien_init_hi)
    end

    local function alien_live_count()
        return read_nibble_pair(inv_alien_live_lo, inv_alien_live_hi)
    end

    local function alien_last()
        return read_nibble_pair(inv_alien_last_lo, inv_alien_last_hi)
    end

    local function alien_x(id)
        return read_nibble_pair(inv_alien_x_lo_base + id, inv_alien_x_hi_base + id)
    end

    local function alien_y(id)
        return read_nibble_pair(inv_alien_y_lo_base + id, inv_alien_y_hi_base + id)
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

    local shield_cells = {
        inv_cell_roof_left, inv_cell_checker, inv_cell_checker, inv_cell_checker,
        inv_cell_checker, inv_cell_checker, inv_cell_roof_right,
        inv_cell_checker, inv_cell_checker, inv_cell_checker,
        inv_cell_checker, inv_cell_checker, inv_cell_checker,
        inv_cell_checker,
        inv_cell_checker, inv_cell_checker, inv_cell_checker,
        inv_cell_blank, inv_cell_checker, inv_cell_checker,
        inv_cell_checker,
    }

    local function assert_shield_state(description)
        test.assert_eq(#shield_cells, inv_shield_cells_each, description .. " shape width")
        for damage_index = 0, inv_shield_damage_count - 1 do
            test.assert_eq(
                read_u8(inv_shield_damage_base + damage_index),
                0,
                description .. " shield damage " .. tostring(damage_index))
        end
        for shield = 0, inv_shield_count - 1 do
            for cell_index = 0, inv_shield_cells_each - 1 do
                local address = inv_shield_cells_base + shield * inv_shield_cells_each + cell_index
                test.assert_eq(
                    read_u8(address),
                    shield_cells[cell_index + 1],
                    description .. " shield " .. tostring(shield) .. " cell " .. tostring(cell_index))
            end
        end
        test.assert_eq(inv_shield_cells_each, inv_shield_w * 3, description .. " shield cell count")
    end

    local function assert_alien_reset_state(description)
        test.assert_eq(alien_init_count(), 0, description .. " alien initialized count")
        test.assert_eq(alien_live_count(), 0, description .. " alien live count")
        test.assert_eq(alien_last(), 0xff, description .. " alien last")
        test.assert_eq(read_u8(inv_alien_min_col), 0, description .. " minimum alien column")
        test.assert_eq(read_u8(inv_alien_max_col), inv_alien_cols - 1, description .. " maximum alien column")
        test.assert_eq(read_u8(inv_alien_min_row), 0, description .. " minimum alien row")
        test.assert_eq(read_u8(inv_alien_max_row), inv_alien_rows - 1, description .. " maximum alien row")
        test.assert_eq(read_u8(inv_alien_dir), inv_alien_dir_right, description .. " alien direction")
        test.assert_eq(read_u8(inv_alien_reverse), 0, description .. " alien reverse")
        test.assert_eq(read_u8(inv_alien_y_delta), 0, description .. " alien y delta")
        test.assert_eq(read_u8(inv_alien_descents), 0, description .. " alien descents")
        test.assert_eq(read_u8(inv_alien_anim_phase), 0, description .. " alien animation")
        for id = 0, inv_alien_count - 1 do
            test.assert_eq(read_u8(inv_alien_live_base + id), 0, description .. " alien live " .. tostring(id))
            test.assert_eq(alien_x(id), 0, description .. " alien x " .. tostring(id))
            test.assert_eq(alien_y(id), 0, description .. " alien y " .. tostring(id))
        end
    end

    local function assert_high_scores_loaded(description)
        test.assert_eq(high_score_units(0), 123, description .. " high score slot 0")
        test.assert_eq(high_score_units(1), 45, description .. " high score slot 1")
        test.assert_eq(high_score_units(2), 0, description .. " high score slot 2")
        test.assert_eq(initial_value(0), 0x21, description .. " initial A")
        test.assert_eq(initial_value(1), 0x22, description .. " initial B")
        test.assert_eq(initial_value(2), 0, description .. " initial space")
        test.assert_eq(initial_value(3), 0x23, description .. " initial C")
        test.assert_eq(initial_value(4), 0, description .. " second initial space")
        test.assert_eq(initial_value(5), 0, description .. " third initial space")
        for slot = 2, inv_high_score_count - 1 do
            test.assert_eq(high_score_units(slot), 0, description .. " empty score " .. tostring(slot))
        end
    end

    local function assert_play_state(description)
        test.assert_eq(read_u8(inv_score0), 0, description .. " score0")
        test.assert_eq(read_u8(inv_score1), 0, description .. " score1")
        test.assert_eq(read_u8(inv_score2), 0, description .. " score2")
        test.assert_eq(read_u8(inv_gunners), inv_initial_gunners, description .. " gunners")
        test.assert_eq(read_u8(inv_level), inv_initial_level, description .. " level")
        test.assert_eq(read_u8(inv_game_over), 0, description .. " game over")
        test.assert_eq(read_u8(inv_high_score_dirty), 0, description .. " high score dirty")
        test.assert_eq(read_u8(inv_high_initial_index), 0, description .. " initial index")
        test.assert_eq(turret_x(), inv_turret_start_x, description .. " turret x")
        test.assert_eq(read_u8(inv_missile_active_count), 0, description .. " missile count")
        for missile = 0, inv_missile_count - 1 do
            test.assert_eq(
                read_u8(inv_missile_active_base + missile),
                0,
                description .. " missile active " .. tostring(missile))
        end
        test.assert_eq(read_u8(inv_ufo_state), 0, description .. " ufo state")
        test.assert_eq(read_u8(inv_ufo_timer_lo), inv_ufo_first_delay_lo, description .. " ufo timer lo")
        test.assert_eq(read_u8(inv_ufo_timer_hi), inv_ufo_first_delay_hi, description .. " ufo timer hi")
        test.assert_eq(read_u8(led_state), game_led_state, description .. " LEDs")
        assert_alien_reset_state(description)
        assert_shield_state(description)
        assert_text(inv_score_row, 0, "SCORE 0000  LEVEL 1")
        test.assert_eq(cell(inv_ground_row, inv_play_left), sg("q"), description .. " ground left")
        test.assert_eq(
            cell(inv_ground_row, inv_play_left + inv_play_width - 1),
            sg("q"),
            description .. " ground right")
    end

    local function assert_overlay()
        assert_text(inv_attract_title_row, inv_attract_title_col, "VT100 INVADERS")
        assert_text(inv_attract_scores_row, inv_attract_scores_col, "HIGH SCORES")
        assert_text(inv_attract_prompt_row, inv_attract_prompt_col, "PRESS ENTER")
        assert_text(inv_high_score_first_row, inv_high_score_col, "AB  1230")
        assert_text(inv_high_score_first_row + 1, inv_high_score_col, "C   0450")
        for slot = 2, inv_high_score_count - 1 do
            assert_spaces(
                inv_high_score_first_row + slot,
                inv_high_score_col,
                inv_high_score_entry_width,
                "empty high score row " .. tostring(slot))
        end
    end

    local function mutate_demo_state()
        write_u8(inv_score0, 7)
        write_u8(inv_score1, 8)
        write_u8(inv_score2, 9)
        write_u8(inv_gunners, 1)
        write_u8(inv_level, 7)
        write_u8(inv_game_over, 0xff)
        write_u8(inv_high_initial_index, 3)
        set_turret_x(inv_turret_start_x + 5)
        write_u8(inv_missile_active_count, 1)
        write_u8(inv_missile_active_base, 0xff)
        write_u8(inv_ufo_state, 1)
        write_u8(inv_ufo_timer_lo, 0)
        write_u8(inv_ufo_timer_hi, 0)
        write_nibble_pair(inv_alien_init_lo, inv_alien_init_hi, inv_alien_count)
        write_nibble_pair(inv_alien_live_lo, inv_alien_live_hi, inv_alien_count - 1)
        write_u8(inv_alien_live_base, 0)
        write_nibble_pair(inv_alien_x_lo_base, inv_alien_x_hi_base, inv_alien_start_x + inv_alien_slot_w)
        write_nibble_pair(inv_alien_y_lo_base, inv_alien_y_hi_base, inv_alien_top_row + inv_alien_slot_h)
        write_u8(inv_alien_reverse, 0xff)
        write_u8(inv_alien_y_delta, 1)
        write_u8(inv_alien_descents, 2)
        write_u8(inv_alien_anim_phase, 1)
        write_u8(inv_shield_cells_base, inv_cell_blank)
        write_u8(inv_shield_damage_base, 3)
    end

    local frame = 0
    local stage = "boot"
    local stage_frame = 0
    local setup_key_repeats = 0
    local shift_i_repeats = 0
    local enter_key_repeats = 0

    local function enter_stage(next_stage)
        stage = next_stage
        stage_frame = frame
    end

    local function fail_timeout(description)
        test.fail(string.format(
            "%s timed out at frame %d: active=%s attract=%s setup=%s game_frame=%s",
            description,
            frame,
            test.hex(read_u8(inv_active), 2),
            test.hex(read_u8(inv_attract_mode), 2),
            test.hex(read_u8(in_setup), 2),
            test.hex(game_frame(), 2)))
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
                    assert_play_state("demo")
                    assert_high_scores_loaded("demo")
                    assert_overlay()
                    mutate_demo_state()
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
                enter_stage("wait-real-game")
                return
            end

            if stage == "wait-real-game" then
                if read_u8(inv_active) == inv_active_value and read_u8(inv_attract_mode) == 0 then
                    assert_play_state("real game")
                    assert_high_scores_loaded("real game")
                    test.pass()
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("starting real game")
                end
                return
            end
        end)

        if not ok then
            test.fail(err)
        end
    end
end

function exports.startplugin()
    local step_demo_state_test = nil

    emu.register_prestart(function()
        local ok, result = pcall(make_demo_state_step)
        if not ok then
            test.fail(result)
            return
        end
        step_demo_state_test = result
    end)

    frame_subscription = emu.add_machine_frame_notifier(function()
        if step_demo_state_test == nil then
            return
        end
        local ok, err = pcall(step_demo_state_test)
        if not ok then
            test.fail(err)
        end
    end)
end

return exports
