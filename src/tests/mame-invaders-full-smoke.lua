local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local test = dofile(script_directory .. "/mame-test.lua")

local M = {}
local frame_subscription

local function make_full_smoke_step()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary_directory .. "/invaders-avo.equ")
    local symbols = test.load_symbols(binary_directory .. "/invaders-avo.sym")

    local inv_active = test.required_equate(equates, "inv_active")
    local inv_attract_mode = test.required_equate(equates, "inv_attract_mode")
    local inv_test_mode = test.required_equate(equates, "inv_test_mode")
    local inv_test_script = test.required_equate(equates, "inv_test_script")
    local inv_test_result = test.required_equate(equates, "inv_test_result")
    local inv_frame_lo = test.required_equate(equates, "inv_frame_lo")
    local inv_frame_hi = test.required_equate(equates, "inv_frame_hi")
    local inv_score_row = test.required_equate(equates, "inv_score_row")
    local inv_score0 = test.required_equate(equates, "inv_score0")
    local inv_score1 = test.required_equate(equates, "inv_score1")
    local inv_score2 = test.required_equate(equates, "inv_score2")
    local inv_gunners = test.required_equate(equates, "inv_gunners")
    local inv_initial_gunners = test.required_equate(equates, "inv_initial_gunners")
    local inv_game_over = test.required_equate(equates, "inv_game_over")
    local inv_level_timer = test.required_equate(equates, "inv_level_timer")
    local inv_turret_death_timer = test.required_equate(equates, "inv_turret_death_timer")
    local inv_turret_x_lo = test.required_equate(equates, "inv_turret_x_lo")
    local inv_turret_x_hi = test.required_equate(equates, "inv_turret_x_hi")
    local inv_turret_start_x = test.required_equate(equates, "inv_turret_start_x")
    local inv_turret_min_x = test.required_equate(equates, "inv_turret_min_x")
    local inv_turret_top_row = test.required_equate(equates, "inv_turret_top_row")
    local inv_play_left = test.required_equate(equates, "inv_play_left")
    local inv_ground_row = test.required_equate(equates, "inv_ground_row")
    local inv_alien_count = test.required_equate(equates, "inv_alien_count")
    local inv_alien_init_lo = test.required_equate(equates, "inv_alien_init_lo")
    local inv_alien_init_hi = test.required_equate(equates, "inv_alien_init_hi")
    local inv_alien_live_lo = test.required_equate(equates, "inv_alien_live_lo")
    local inv_alien_live_hi = test.required_equate(equates, "inv_alien_live_hi")
    local inv_alien_live_base = test.required_equate(equates, "inv_alien_live_base")
    local inv_alien_x_lo_base = test.required_equate(equates, "inv_alien_x_lo_base")
    local inv_alien_x_hi_base = test.required_equate(equates, "inv_alien_x_hi_base")
    local inv_alien_y_lo_base = test.required_equate(equates, "inv_alien_y_lo_base")
    local inv_alien_y_hi_base = test.required_equate(equates, "inv_alien_y_hi_base")
    local inv_laser_active = test.required_equate(equates, "inv_laser_active")
    local inv_laser_row_lo = test.required_equate(equates, "inv_laser_row_lo")
    local inv_laser_row_hi = test.required_equate(equates, "inv_laser_row_hi")
    local inv_laser_col_lo = test.required_equate(equates, "inv_laser_col_lo")
    local inv_laser_col_hi = test.required_equate(equates, "inv_laser_col_hi")
    local inv_laser_timer = test.required_equate(equates, "inv_laser_timer")
    local inv_laser_shots_lo = test.required_equate(equates, "inv_laser_shots_lo")
    local inv_laser_shots_hi = test.required_equate(equates, "inv_laser_shots_hi")
    local inv_missile_count = test.required_equate(equates, "inv_missile_count")
    local inv_missile_glyph = test.required_equate(equates, "inv_missile_glyph")
    local inv_missile_tick_timer = test.required_equate(equates, "inv_missile_tick_timer")
    local inv_missile_fire_timer = test.required_equate(equates, "inv_missile_fire_timer")
    local inv_missile_active_count = test.required_equate(equates, "inv_missile_active_count")
    local inv_missile_shot_index = test.required_equate(equates, "inv_missile_shot_index")
    local inv_missile_active_base = test.required_equate(equates, "inv_missile_active_base")
    local inv_missile_row_base = test.required_equate(equates, "inv_missile_row_base")
    local inv_missile_col_base = test.required_equate(equates, "inv_missile_col_base")
    local inv_missile_phase_base = test.required_equate(equates, "inv_missile_phase_base")
    local inv_sound_mode = test.required_equate(equates, "inv_sound_mode")
    local inv_death_sound_timer = test.required_equate(equates, "inv_death_sound_timer")
    local inv_ufo_row = test.required_equate(equates, "inv_ufo_row")
    local inv_ufo_w = test.required_equate(equates, "inv_ufo_w")
    local inv_ufo_h = test.required_equate(equates, "inv_ufo_h")
    local inv_ufo_left_x = test.required_equate(equates, "inv_ufo_left_x")
    local inv_ufo_state = test.required_equate(equates, "inv_ufo_state")
    local inv_ufo_state_active = test.required_equate(equates, "inv_ufo_state_active")
    local inv_ufo_state_explode = test.required_equate(equates, "inv_ufo_state_explode")
    local inv_ufo_state_score = test.required_equate(equates, "inv_ufo_state_score")
    local inv_ufo_x = test.required_equate(equates, "inv_ufo_x")
    local inv_ufo_dx = test.required_equate(equates, "inv_ufo_dx")
    local inv_ufo_timer_lo = test.required_equate(equates, "inv_ufo_timer_lo")
    local inv_ufo_timer_hi = test.required_equate(equates, "inv_ufo_timer_hi")
    local inv_ufo_move_timer = test.required_equate(equates, "inv_ufo_move_timer")
    local inv_ufo_state_timer = test.required_equate(equates, "inv_ufo_state_timer")
    local inv_ufo_points = test.required_equate(equates, "inv_ufo_points")
    local inv_ufo_disabled = test.required_equate(equates, "inv_ufo_disabled")
    local inv_scan_arrow_right = test.required_equate(equates, "inv_scan_arrow_right")
    local inv_scan_space = test.required_equate(equates, "inv_scan_space")
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
    local original_led_state = 0x0a
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

    local function sg(source)
        return string.byte(source) - 0x5f
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

    local function alien_x(id)
        return read_nibble_pair(inv_alien_x_lo_base + id, inv_alien_x_hi_base + id)
    end

    local function alien_y(id)
        return read_nibble_pair(inv_alien_y_lo_base + id, inv_alien_y_hi_base + id)
    end

    local function turret_x()
        return read_nibble_pair(inv_turret_x_lo, inv_turret_x_hi)
    end

    local function set_turret_x(value)
        write_nibble_pair(inv_turret_x_lo, inv_turret_x_hi, value)
    end

    local function laser_shots()
        return read_nibble_pair(inv_laser_shots_lo, inv_laser_shots_hi)
    end

    local function set_laser_shots(value)
        write_nibble_pair(inv_laser_shots_lo, inv_laser_shots_hi, value)
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

    local function assert_text(row, column, text)
        for index = 1, #text do
            test.assert_eq(
                cell(row, column + index - 1),
                string.byte(text, index),
                text .. " byte " .. tostring(index))
        end
    end

    local function inject_key(scan, modifiers)
        write_u8(key_flags, key_flag_eos + 1 + modifiers)
        write_u8(key_silo, scan)
        write_u8(key_silo + 1, 0)
        write_u8(key_silo + 2, 0)
        write_u8(key_silo + 3, 0)
    end

    local function clear_missiles()
        write_u8(inv_missile_tick_timer, 0xff)
        write_u8(inv_missile_fire_timer, 0xff)
        write_u8(inv_missile_active_count, 0)
        write_u8(inv_missile_shot_index, 0)
        for slot = 0, inv_missile_count - 1 do
            write_u8(inv_missile_active_base + slot, 0)
            write_u8(inv_missile_row_base + slot, 0)
            write_u8(inv_missile_col_base + slot, 0)
            write_u8(inv_missile_phase_base + slot, 0)
        end
    end

    local function force_enemy_fire()
        clear_missiles()
        set_turret_x(inv_turret_min_x)
        write_u8(inv_missile_tick_timer, 0)
        write_u8(inv_missile_fire_timer, 0)
    end

    local function assert_ufo_sprite(x)
        local top = "_lqqqk_"
        local bottom = "laaaaak"
        for index = 1, inv_ufo_w do
            test.assert_eq(
                cell(inv_ufo_row, x + index - 1),
                sg(top:sub(index, index)),
                "UFO top glyph " .. tostring(index))
            test.assert_eq(
                cell(inv_ufo_row + 1, x + index - 1),
                sg(bottom:sub(index, index)),
                "UFO bottom glyph " .. tostring(index))
        end
    end

    local function assert_ufo_explosion(x)
        local top = "_qnnnq_"
        local bottom = "_aaaaa_"
        for index = 1, inv_ufo_w do
            test.assert_eq(
                cell(inv_ufo_row, x + index - 1),
                sg(top:sub(index, index)),
                "UFO explosion top glyph " .. tostring(index))
            test.assert_eq(
                cell(inv_ufo_row + 1, x + index - 1),
                sg(bottom:sub(index, index)),
                "UFO explosion bottom glyph " .. tostring(index))
        end
    end

    local frame = 0
    local stage = "boot"
    local stage_frame = 0
    local setup_key_repeats = 0
    local shift_i_repeats = 0
    local enter_key_repeats = 0
    local right_key_repeats = 0
    local exit_key_repeats = 0
    local tracked_alien = 0
    local tracked_alien_x = 0
    local tracked_alien_y = 0
    local spawned_ufo_x = 0
    local moved_ufo_x = 0
    local score_before_ufo = 0

    local function enter_stage(next_stage)
        stage = next_stage
        stage_frame = frame
    end

    local function fail_timeout(description)
        test.fail(string.format(
            "%s timed out at host frame %d: game_frame=%s active=%s setup=%s init=%s live=%s gunners=%s game_over=%s level_timer=%s death_timer=%s score=%s missile=%s ufo=%s x=%s timer=%s:%s",
            description,
            frame,
            test.hex(game_frame(), 2),
            test.hex(read_u8(inv_active), 2),
            test.hex(read_u8(in_setup), 2),
            test.hex(alien_init_count(), 2),
            test.hex(alien_live_count(), 2),
            test.hex(read_u8(inv_gunners), 2),
            test.hex(read_u8(inv_game_over), 2),
            test.hex(read_u8(inv_level_timer), 2),
            test.hex(read_u8(inv_turret_death_timer), 2),
            test.hex(score_units(), 3),
            test.hex(read_u8(inv_missile_active_count), 2),
            test.hex(read_u8(inv_ufo_state), 2),
            test.hex(read_u8(inv_ufo_x), 2),
            test.hex(read_u8(inv_ufo_timer_hi), 2),
            test.hex(read_u8(inv_ufo_timer_lo), 2)))
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
                if read_u8(inv_attract_mode) ~= 0 then
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
                enter_stage("wait-formation")
                return
            end

            if stage == "wait-formation" then
                if read_u8(inv_active) ~= 0 and read_u8(inv_attract_mode) == 0 and alien_init_count() == inv_alien_count then
                    test.assert_eq(alien_live_count(), inv_alien_count, "initial live aliens")
                    test.assert_eq(read_u8(inv_gunners), inv_initial_gunners, "initial gunners")
                    test.assert_eq(turret_x(), inv_turret_start_x, "initial turret x")
                    assert_text(inv_score_row, 0, "SCORE 0000  LEVEL 1")
                    test.assert_eq(cell(inv_ground_row, inv_play_left), sg("q"), "ground left edge")
                    tracked_alien_x = alien_x(tracked_alien)
                    tracked_alien_y = alien_y(tracked_alien)
                    enter_stage("scripted-move")
                    return
                end
                if frame - stage_frame > 240 then
                    fail_timeout("formation")
                end
                return
            end

            if stage == "scripted-move" then
                if right_key_repeats < 3 then
                    inject_key(inv_scan_arrow_right, 0)
                    right_key_repeats = right_key_repeats + 1
                    return
                end
                inject_key(inv_scan_space, 0)
                enter_stage("wait-scripted-input")
                return
            end

            if stage == "wait-scripted-input" then
                if turret_x() > inv_turret_start_x and laser_shots() >= 1 then
                    write_u8(inv_laser_active, 0)
                    write_u8(inv_laser_timer, 0)
                    set_laser_shots(8)
                    enter_stage("wait-alien-movement")
                    return
                end
                if frame - stage_frame > 90 then
                    fail_timeout("scripted movement and firing")
                end
                return
            end

            if stage == "wait-alien-movement" then
                if alien_x(tracked_alien) ~= tracked_alien_x
                    or alien_y(tracked_alien) ~= tracked_alien_y then
                    force_enemy_fire()
                    enter_stage("wait-enemy-fire")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("alien movement")
                end
                return
            end

            if stage == "wait-enemy-fire" then
                if read_u8(inv_missile_active_count) ~= 0 then
                    local missile_row = read_u8(inv_missile_row_base)
                    local missile_col = read_u8(inv_missile_col_base)
                    test.assert_eq(cell(missile_row, missile_col), inv_missile_glyph, "enemy missile glyph")
                    clear_missiles()
                    enter_stage("wait-ufo")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("enemy fire")
                end
                return
            end

            if stage == "wait-ufo" then
                clear_missiles()
                if read_u8(inv_ufo_state) == inv_ufo_state_active then
                    spawned_ufo_x = read_u8(inv_ufo_x)
                    test.assert_eq(spawned_ufo_x, inv_ufo_left_x, "even-shot UFO starts left")
                    test.assert_eq(read_u8(inv_ufo_dx), 1, "even-shot UFO direction")
                    test.assert_eq(read_u8(inv_ufo_disabled), 0, "UFO enabled")
                    assert_ufo_sprite(spawned_ufo_x)
                    enter_stage("wait-ufo-move")
                    return
                end
                if frame - stage_frame > 2300 then
                    fail_timeout("UFO appearance")
                end
                return
            end

            if stage == "wait-ufo-move" then
                if read_u8(inv_ufo_x) ~= spawned_ufo_x then
                    moved_ufo_x = read_u8(inv_ufo_x)
                    test.assert_eq(moved_ufo_x, spawned_ufo_x + 1, "UFO first move")
                    test.assert_eq(cell(inv_ufo_row, spawned_ufo_x), 0, "UFO old left cell cleared")
                    assert_ufo_sprite(moved_ufo_x)
                    write_u8(inv_ufo_move_timer, 0xff)
                    score_before_ufo = score_units()
                    arm_laser(inv_ufo_row + inv_ufo_h, moved_ufo_x + math.floor(inv_ufo_w / 2))
                    enter_stage("wait-ufo-hit")
                    return
                end
                if frame - stage_frame > 60 then
                    fail_timeout("UFO movement")
                end
                return
            end

            if stage == "wait-ufo-hit" then
                if read_u8(inv_ufo_state) == inv_ufo_state_explode then
                    test.assert_eq(read_u8(inv_laser_active), 0, "UFO hit deactivates laser")
                    test.assert_eq(read_u8(inv_ufo_points), 30, "UFO selected 300-point score")
                    assert_ufo_explosion(moved_ufo_x)
                    enter_stage("wait-ufo-score")
                    return
                end
                if frame - stage_frame > 60 then
                    fail_timeout("UFO hit")
                end
                return
            end

            if stage == "wait-ufo-score" then
                if read_u8(inv_ufo_state) == inv_ufo_state_score then
                    test.assert_eq(score_units(), score_before_ufo + 30, "score after UFO")
                    assert_text(inv_ufo_row, moved_ufo_x + 2, "300")
                    enter_stage("exit-key")
                    return
                end
                if frame - stage_frame > 90 then
                    fail_timeout("UFO score display")
                end
                return
            end

            if stage == "exit-key" then
                if exit_key_repeats < 2 then
                    inject_key(inv_scan_setup, 0)
                    exit_key_repeats = exit_key_repeats + 1
                    return
                end
                enter_stage("wait-exit")
                return
            end

            if stage == "wait-exit" then
                if read_u8(inv_active) == 0
                    and read_u8(led_state) == original_led_state
                    and read_u8(inv_laser_active) == 0
                    and read_u8(inv_missile_active_count) == 0
                    and read_u8(inv_ufo_state) == 0
                    and read_u8(inv_sound_mode) == 0
                    and read_u8(inv_death_sound_timer) == 0
                    and read_u8(inv_game_over) == 0
                    and read_u8(inv_level_timer) == 0
                    and read_u8(inv_turret_death_timer) == 0
                    and cell(inv_score_row, 0) == 0 then
                    test.assert_eq(read_u8(led_state), original_led_state, "restored LEDs")
                    test.assert_eq(read_u8(inv_laser_active), 0, "exit clears laser")
                    test.assert_eq(read_u8(inv_missile_active_count), 0, "exit clears missiles")
                    test.assert_eq(read_u8(inv_ufo_state), 0, "exit clears UFO")
                    test.assert_eq(read_u8(inv_sound_mode), 0, "exit clears sound mode")
                    test.assert_eq(read_u8(inv_death_sound_timer), 0, "exit clears death sound")
                    test.assert_eq(read_u8(inv_game_over), 0, "exit clears game over")
                    test.assert_eq(read_u8(inv_level_timer), 0, "exit clears level timer")
                    test.assert_eq(read_u8(inv_turret_death_timer), 0, "exit clears turret death")
                    test.assert_eq(cell(inv_score_row, 0), 0, "exit clears score row")
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
    local step_full_smoke_test = nil

    emu.register_prestart(function()
        local ok, result = pcall(make_full_smoke_step)
        if not ok then
            test.fail(result)
            return
        end
        step_full_smoke_test = result
    end)

    frame_subscription = emu.add_machine_frame_notifier(function()
        if step_full_smoke_test == nil then
            return
        end
        local ok, err = pcall(step_full_smoke_test)
        if not ok then
            test.fail(err)
        end
    end)
end

return M
