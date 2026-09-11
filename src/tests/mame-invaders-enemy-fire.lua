local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local test = dofile(script_directory .. "/mame-test.lua")

local M = {}
local frame_subscription

local function make_enemy_fire_step()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary_directory .. "/invaders-avo.equ")
    local symbols = test.load_symbols(binary_directory .. "/invaders-avo.sym")

    local inv_active = test.required_equate(equates, "inv_active")
    local inv_test_mode = test.required_equate(equates, "inv_test_mode")
    local inv_test_script = test.required_equate(equates, "inv_test_script")
    local inv_test_result = test.required_equate(equates, "inv_test_result")
    local inv_frame_lo = test.required_equate(equates, "inv_frame_lo")
    local inv_frame_hi = test.required_equate(equates, "inv_frame_hi")
    local inv_gunners = test.required_equate(equates, "inv_gunners")
    local inv_game_over = test.required_equate(equates, "inv_game_over")
    local inv_turret_death_timer = test.required_equate(equates, "inv_turret_death_timer")
    local inv_turret_death_frames = test.required_equate(equates, "inv_turret_death_frames")
    local inv_turret_x_lo = test.required_equate(equates, "inv_turret_x_lo")
    local inv_turret_x_hi = test.required_equate(equates, "inv_turret_x_hi")
    local inv_turret_start_x = test.required_equate(equates, "inv_turret_start_x")
    local inv_turret_top_row = test.required_equate(equates, "inv_turret_top_row")
    local inv_turret_w = test.required_equate(equates, "inv_turret_w")
    local inv_laser_active = test.required_equate(equates, "inv_laser_active")
    local inv_alien_rows = test.required_equate(equates, "inv_alien_rows")
    local inv_alien_cols = test.required_equate(equates, "inv_alien_cols")
    local inv_alien_count = test.required_equate(equates, "inv_alien_count")
    local inv_alien_h = test.required_equate(equates, "inv_alien_h")
    local inv_alien_slot_w = test.required_equate(equates, "inv_alien_slot_w")
    local inv_alien_slot_h = test.required_equate(equates, "inv_alien_slot_h")
    local inv_alien_start_x = test.required_equate(equates, "inv_alien_start_x")
    local inv_alien_top_row = test.required_equate(equates, "inv_alien_top_row")
    local inv_alien_init_lo = test.required_equate(equates, "inv_alien_init_lo")
    local inv_alien_init_hi = test.required_equate(equates, "inv_alien_init_hi")
    local inv_alien_live_lo = test.required_equate(equates, "inv_alien_live_lo")
    local inv_alien_live_hi = test.required_equate(equates, "inv_alien_live_hi")
    local inv_alien_last_lo = test.required_equate(equates, "inv_alien_last_lo")
    local inv_alien_last_hi = test.required_equate(equates, "inv_alien_last_hi")
    local inv_alien_live_base = test.required_equate(equates, "inv_alien_live_base")
    local inv_alien_x_lo_base = test.required_equate(equates, "inv_alien_x_lo_base")
    local inv_alien_x_hi_base = test.required_equate(equates, "inv_alien_x_hi_base")
    local inv_alien_y_lo_base = test.required_equate(equates, "inv_alien_y_lo_base")
    local inv_alien_y_hi_base = test.required_equate(equates, "inv_alien_y_hi_base")
    local inv_shield_top_row = test.required_equate(equates, "inv_shield_top_row")
    local inv_shield_w = test.required_equate(equates, "inv_shield_w")
    local inv_shield_h = test.required_equate(equates, "inv_shield_h")
    local inv_shield_cells_each = test.required_equate(equates, "inv_shield_cells_each")
    local inv_shield_count = test.required_equate(equates, "inv_shield_count")
    local inv_shield_cell_count = test.required_equate(equates, "inv_shield_cell_count")
    local inv_shield0_x = test.required_equate(equates, "inv_shield0_x")
    local inv_shield_cells_base = test.required_equate(equates, "inv_shield_cells_base")
    local inv_missile_count = test.required_equate(equates, "inv_missile_count")
    local inv_missile_empty_delay = test.required_equate(equates, "inv_missile_empty_delay")
    local inv_missile_glyph = test.required_equate(equates, "inv_missile_glyph")
    local inv_missile_tick_timer = test.required_equate(equates, "inv_missile_tick_timer")
    local inv_missile_fire_timer = test.required_equate(equates, "inv_missile_fire_timer")
    local inv_missile_active_count = test.required_equate(equates, "inv_missile_active_count")
    local inv_missile_shot_index = test.required_equate(equates, "inv_missile_shot_index")
    local inv_missile_active_base = test.required_equate(equates, "inv_missile_active_base")
    local inv_missile_row_base = test.required_equate(equates, "inv_missile_row_base")
    local inv_missile_col_base = test.required_equate(equates, "inv_missile_col_base")
    local inv_missile_phase_base = test.required_equate(equates, "inv_missile_phase_base")
    local inv_scan_setup = test.required_equate(equates, "inv_scan_setup")
    local in_setup = test.required_equate(equates, "in_setup")
    local key_flags = test.required_equate(equates, "key_flags")
    local key_silo = test.required_equate(equates, "key_silo")
    local key_flag_shift = test.required_equate(equates, "key_flag_shift")
    local key_flag_eos = test.required_equate(equates, "key_flag_eos")
    local led_state = test.required_equate(equates, "led_state")
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

    local function write_cell(row, column, value)
        write_u8(row_address(row) + column, value)
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

    local function alien_last()
        return read_nibble_pair(inv_alien_last_lo, inv_alien_last_hi)
    end

    local function write_alien_live_count(value)
        write_nibble_pair(inv_alien_live_lo, inv_alien_live_hi, value)
    end

    local function write_alien_last(value)
        write_nibble_pair(inv_alien_last_lo, inv_alien_last_hi, value)
    end

    local function set_turret_x(value)
        write_nibble_pair(inv_turret_x_lo, inv_turret_x_hi, value)
    end

    local function missile_active(slot)
        return read_u8(inv_missile_active_base + slot)
    end

    local function missile_row(slot)
        return read_u8(inv_missile_row_base + slot)
    end

    local function missile_col(slot)
        return read_u8(inv_missile_col_base + slot)
    end

    local function led_bits()
        return read_u8(led_state) % 16
    end

    local function inject_key(scan, modifiers)
        write_u8(key_flags, key_flag_eos + 1 + modifiers)
        write_u8(key_silo, scan)
        write_u8(key_silo + 1, 0)
        write_u8(key_silo + 2, 0)
        write_u8(key_silo + 3, 0)
    end

    local function force_next_enemy_fire()
        write_u8(inv_missile_tick_timer, 0)
        write_u8(inv_missile_fire_timer, 0)
        write_u8(inv_missile_active_count, 0)
        write_u8(inv_missile_shot_index, 0)
        for slot = 0, inv_missile_count - 1 do
            write_u8(inv_missile_active_base + slot, 0)
            write_u8(inv_missile_row_base + slot, 0)
            write_u8(inv_missile_col_base + slot, 0)
            write_u8(inv_missile_phase_base + slot, 0)
        end
    end

    local function clear_all_shields()
        for index = 0, inv_shield_cell_count - 1 do
            write_u8(inv_shield_cells_base + index, 0)
        end
        for shield = 0, inv_shield_count - 1 do
            local left = inv_shield0_x + shield * 15
            for row = inv_shield_top_row, inv_shield_top_row + inv_shield_h - 1 do
                for column = left, left + inv_shield_w - 1 do
                    write_cell(row, column, 0)
                end
            end
        end
    end

    local function shield0_cell(row, column)
        local index = (row - inv_shield_top_row) * inv_shield_w + (column - inv_shield0_x)
        return read_u8(inv_shield_cells_base + index)
    end

    local function prepare_single_shooter(id, x, y)
        for alien = 0, inv_alien_count - 1 do
            write_u8(inv_alien_live_base + alien, 0)
        end
        write_u8(inv_alien_live_base + id, 0x0f)
        write_alien_live_count(1)
        write_alien_last((id + inv_alien_count - 1) % inv_alien_count)
        write_nibble_pair(inv_alien_x_lo_base + id, inv_alien_x_hi_base + id, x)
        write_nibble_pair(inv_alien_y_lo_base + id, inv_alien_y_hi_base + id, y)
    end

    local function assert_all_missiles_inactive()
        test.assert_eq(read_u8(inv_missile_active_count), 0, "active missile count")
        for slot = 0, inv_missile_count - 1 do
            test.assert_eq(missile_active(slot), 0, "missile active " .. tostring(slot))
        end
    end

    local function assert_turret_explosion_at(x)
        local top = { "*", "a", "a", "a", "a", "a", "*" }
        local bottom = { "a", "*", "a", "*", "a", "*", "a" }
        for offset = 0, inv_turret_w - 1 do
            test.assert_eq(
                cell(inv_turret_top_row, x + offset),
                string.byte(top[offset + 1]),
                "turret explosion top " .. tostring(offset))
            test.assert_eq(
                cell(inv_turret_top_row + 1, x + offset),
                string.byte(bottom[offset + 1]),
                "turret explosion bottom " .. tostring(offset))
        end
    end

    local function assert_no_turret_explosion_at(x)
        for offset = 0, inv_turret_w - 1 do
            local top_cell = cell(inv_turret_top_row, x + offset)
            local bottom_cell = cell(inv_turret_top_row + 1, x + offset)
            if top_cell == string.byte("a") or top_cell == string.byte("*") then
                test.fail("stale turret explosion top " .. tostring(offset))
            end
            if bottom_cell == string.byte("a") or bottom_cell == string.byte("*") then
                test.fail("stale turret explosion bottom " .. tostring(offset))
            end
        end
    end

    local frame = 0
    local stage = "boot"
    local stage_frame = 0
    local setup_key_repeats = 0
    local shift_i_repeats = 0
    local shield_missile_col = nil
    local turret_death_x = nil
    local frozen_alien_last = nil

    local shield_shooter_id = 1
    local shield_shooter_x = inv_alien_start_x + inv_alien_slot_w
    local shield_shooter_y = inv_alien_top_row
    local turret_shooter_id = (inv_alien_rows - 1) * inv_alien_cols + 1
    local turret_shooter_x = inv_alien_start_x + inv_alien_slot_w
    local turret_shooter_y = inv_alien_top_row + (inv_alien_rows - 1) * inv_alien_slot_h

    local function enter_stage(next_stage)
        stage = next_stage
        stage_frame = frame
    end

    local function fail_timeout(description)
        test.fail(string.format(
            "%s timed out at host frame %d: game_frame=%s active=%s gunners=%s game_over=%s death=%s missiles=%s last=%s",
            description,
            frame,
            test.hex(game_frame(), 2),
            test.hex(read_u8(inv_active), 2),
            test.hex(read_u8(inv_gunners), 2),
            test.hex(read_u8(inv_game_over), 2),
            test.hex(read_u8(inv_turret_death_timer), 2),
            test.hex(read_u8(inv_missile_active_count), 2),
            test.hex(alien_last(), 2)))
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
                enter_stage("wait-formation")
                return
            end

            if stage == "wait-formation" then
                if read_u8(inv_active) ~= 0 and alien_init_count() == inv_alien_count then
                    test.assert_eq(read_u8(inv_gunners), 3, "initial gunners")
                    test.assert_eq(led_bits(), 0x07, "initial gunner LEDs")
                    prepare_single_shooter(shield_shooter_id, shield_shooter_x, shield_shooter_y)
                    set_turret_x(shield_shooter_x)
                    force_next_enemy_fire()
                    enter_stage("wait-shield-missile")
                    return
                end
                if frame - stage_frame > 240 then
                    fail_timeout("formation")
                end
                return
            end

            if stage == "wait-shield-missile" then
                if read_u8(inv_missile_active_count) == 1 and missile_active(0) ~= 0 then
                    shield_missile_col = missile_col(0)
                    test.assert_eq(missile_row(0), shield_shooter_y + inv_alien_h + 1, "first missile row")
                    test.assert_eq(cell(missile_row(0), shield_missile_col), inv_missile_glyph, "first missile glyph")
                    enter_stage("wait-shield-hit")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("first missile launch")
                end
                return
            end

            if stage == "wait-shield-hit" then
                if read_u8(inv_missile_active_count) == 0 then
                    assert_all_missiles_inactive()
                    test.assert_eq(shield0_cell(inv_shield_top_row, shield_missile_col), 0, "shield cell removed")
                    test.assert_eq(cell(inv_shield_top_row, shield_missile_col), 0, "shield screen cell erased")
                    test.assert_eq(read_u8(inv_gunners), 3, "shield hit preserves gunners")
                    test.assert_eq(read_u8(inv_missile_fire_timer), inv_missile_empty_delay, "empty missile delay")

                    clear_all_shields()
                    set_turret_x(turret_shooter_x)
                    prepare_single_shooter(turret_shooter_id, turret_shooter_x, turret_shooter_y)
                    force_next_enemy_fire()
                    enter_stage("wait-turret-hit")
                    return
                end
                if frame - stage_frame > 240 then
                    fail_timeout("shield hit")
                end
                return
            end

            if stage == "wait-turret-hit" then
                if read_u8(inv_turret_death_timer) ~= 0 then
                    test.assert_eq(read_u8(inv_turret_death_timer), inv_turret_death_frames, "turret death timer")
                    test.assert_eq(read_u8(inv_gunners), 2, "gunners after first turret hit")
                    test.assert_eq(led_bits(), 0x03, "LEDs after first turret hit")
                    test.assert_eq(read_u8(inv_laser_active), 0, "laser cleared by turret hit")
                    assert_all_missiles_inactive()
                    turret_death_x = read_nibble_pair(inv_turret_x_lo, inv_turret_x_hi)
                    test.assert_eq(turret_death_x, turret_shooter_x, "first turret death x")
                    assert_turret_explosion_at(turret_death_x)
                    enter_stage("wait-respawn")
                    return
                end
                if frame - stage_frame > 240 then
                    fail_timeout("first turret hit")
                end
                return
            end

            if stage == "wait-respawn" then
                if read_u8(inv_turret_death_timer) == 0 then
                    test.assert_eq(read_u8(inv_game_over), 0, "not game over after respawn")
                    test.assert_eq(read_nibble_pair(inv_turret_x_lo, inv_turret_x_hi), inv_turret_start_x, "respawn turret x")
                    assert_no_turret_explosion_at(turret_death_x)
                    test.assert_eq(cell(inv_turret_top_row, inv_turret_start_x + 3), sg("a"), "respawn turret top")

                    write_u8(inv_gunners, 1)
                    write_u8(inv_game_over, 0)
                    write_u8(inv_turret_death_timer, 0)
                    set_turret_x(inv_turret_start_x)
                    prepare_single_shooter(turret_shooter_id, turret_shooter_x, turret_shooter_y)
                    force_next_enemy_fire()
                    enter_stage("wait-final-hit")
                    return
                end
                if frame - stage_frame > inv_turret_death_frames + 40 then
                    fail_timeout("turret respawn")
                end
                return
            end

            if stage == "wait-final-hit" then
                if read_u8(inv_game_over) ~= 0 then
                    test.assert_eq(read_u8(inv_gunners), 0, "gunners after final hit")
                    test.assert_eq(led_bits(), 0x00, "LEDs after final hit")
                    test.assert_eq(read_u8(inv_turret_death_timer), 0, "death timer after game over")
                    assert_all_missiles_inactive()
                    frozen_alien_last = alien_last()
                    enter_stage("wait-game-over-freeze")
                    return
                end
                if frame - stage_frame > 240 then
                    fail_timeout("final turret hit")
                end
                return
            end

            if stage == "wait-game-over-freeze" then
                if frame - stage_frame >= 12 then
                    test.assert_eq(alien_last(), frozen_alien_last, "aliens stopped by game over")
                    test.assert_eq(read_u8(inv_game_over), 0xff, "game over remains set")
                    test.pass()
                    return
                end
                return
            end
        end)

        if not ok then
            test.fail(err)
        end
    end
end

function M.start()
    local step_enemy_fire_test = nil

    emu.register_prestart(function()
        local ok, result = pcall(make_enemy_fire_step)
        if not ok then
            test.fail(result)
            return
        end
        step_enemy_fire_test = result
    end)

    frame_subscription = emu.add_machine_frame_notifier(function()
        if step_enemy_fire_test == nil then
            return
        end
        local ok, err = pcall(step_enemy_fire_test)
        if not ok then
            test.fail(err)
        end
    end)
end

return M
