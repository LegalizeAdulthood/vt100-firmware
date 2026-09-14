local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local test = dofile(script_directory .. "/mame-test.lua")

local M = {}
local frame_subscription
local output_tap

local function make_sound_step()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary_directory .. "/invaders-avo.equ")

    local iow_keyboard = test.required_equate(equates, "iow_keyboard")
    local iow_kbd_click = test.required_equate(equates, "iow_kbd_click")
    local kbd_click_mask = test.required_equate(equates, "kbd_click_mask")
    local kbd_scan_mask = test.required_equate(equates, "kbd_scan_mask")
    local inv_active = test.required_equate(equates, "inv_active")
    local inv_active_value = test.required_equate(equates, "inv_active_value")
    local inv_attract_mode = test.required_equate(equates, "inv_attract_mode")
    local inv_test_mode = test.required_equate(equates, "inv_test_mode")
    local inv_test_script = test.required_equate(equates, "inv_test_script")
    local inv_test_result = test.required_equate(equates, "inv_test_result")
    local inv_frame_lo = test.required_equate(equates, "inv_frame_lo")
    local inv_frame_hi = test.required_equate(equates, "inv_frame_hi")
    local inv_gunners = test.required_equate(equates, "inv_gunners")
    local inv_initial_gunners = test.required_equate(equates, "inv_initial_gunners")
    local inv_game_over = test.required_equate(equates, "inv_game_over")
    local inv_level_timer = test.required_equate(equates, "inv_level_timer")
    local inv_turret_death_timer = test.required_equate(equates, "inv_turret_death_timer")
    local inv_turret_death_frames = test.required_equate(equates, "inv_turret_death_frames")
    local inv_turret_start_x = test.required_equate(equates, "inv_turret_start_x")
    local inv_turret_top_row = test.required_equate(equates, "inv_turret_top_row")
    local inv_turret_w = test.required_equate(equates, "inv_turret_w")
    local inv_turret_x_lo = test.required_equate(equates, "inv_turret_x_lo")
    local inv_turret_x_hi = test.required_equate(equates, "inv_turret_x_hi")
    local inv_alien_count = test.required_equate(equates, "inv_alien_count")
    local inv_alien_init_lo = test.required_equate(equates, "inv_alien_init_lo")
    local inv_alien_init_hi = test.required_equate(equates, "inv_alien_init_hi")
    local inv_alien_live_lo = test.required_equate(equates, "inv_alien_live_lo")
    local inv_alien_live_hi = test.required_equate(equates, "inv_alien_live_hi")
    local inv_missile_count = test.required_equate(equates, "inv_missile_count")
    local inv_missile_tick_timer = test.required_equate(equates, "inv_missile_tick_timer")
    local inv_missile_fire_timer = test.required_equate(equates, "inv_missile_fire_timer")
    local inv_missile_active_count = test.required_equate(equates, "inv_missile_active_count")
    local inv_missile_shot_index = test.required_equate(equates, "inv_missile_shot_index")
    local inv_missile_active_base = test.required_equate(equates, "inv_missile_active_base")
    local inv_missile_row_base = test.required_equate(equates, "inv_missile_row_base")
    local inv_missile_col_base = test.required_equate(equates, "inv_missile_col_base")
    local inv_missile_phase_base = test.required_equate(equates, "inv_missile_phase_base")
    local inv_sound_mode = test.required_equate(equates, "inv_sound_mode")
    local inv_sound_timer = test.required_equate(equates, "inv_sound_timer")
    local inv_sound_phase = test.required_equate(equates, "inv_sound_phase")
    local inv_heartbeat_timer = test.required_equate(equates, "inv_heartbeat_timer")
    local inv_death_sound_timer = test.required_equate(equates, "inv_death_sound_timer")
    local inv_last_stock_kbd_status = test.required_equate(equates, "inv_last_stock_kbd_status")
    local inv_last_output_kbd_status = test.required_equate(equates, "inv_last_output_kbd_status")
    local inv_sound_mode_silent = test.required_equate(equates, "inv_sound_mode_silent")
    local inv_sound_mode_heartbeat = test.required_equate(equates, "inv_sound_mode_heartbeat")
    local inv_sound_mode_death = test.required_equate(equates, "inv_sound_mode_death")
    local inv_sound_death_words = test.required_equate(equates, "inv_sound_death_words")
    local inv_scan_setup = test.required_equate(equates, "inv_scan_setup")
    local inv_scan_return_b = test.required_equate(equates, "inv_scan_return_b")
    local in_setup = test.required_equate(equates, "in_setup")
    local key_flags = test.required_equate(equates, "key_flags")
    local key_silo = test.required_equate(equates, "key_silo")
    local key_flag_shift = test.required_equate(equates, "key_flag_shift")
    local key_flag_eos = test.required_equate(equates, "key_flag_eos")

    local scan_i = 0x16
    local mem = test.program_space()

    local function read_u8(address)
        return mem:read_u8(address)
    end

    local function write_u8(address, value)
        mem:write_u8(address, value)
    end

    local function read_nibble_pair(lo_address, hi_address)
        return (read_u8(lo_address) % 16) + (read_u8(hi_address) % 16) * 16
    end

    local function write_nibble_pair(lo_address, hi_address, value)
        write_u8(lo_address, value % 16)
        write_u8(hi_address, math.floor(value / 16) % 16)
    end

    local function input_output_space()
        local cpu = manager.machine.devices[":maincpu"]
        if cpu == nil then
            error("could not find :maincpu device", 0)
        end
        local space = cpu.spaces["io"] or cpu.spaces["iospace"]
        if space == nil then
            local names = {}
            for name, _ in pairs(cpu.spaces) do
                names[#names + 1] = tostring(name)
            end
            table.sort(names)
            error("could not find :maincpu I/O space; found " .. table.concat(names, ", "), 0)
        end
        return space
    end

    local function game_frame()
        return read_nibble_pair(inv_frame_lo, inv_frame_hi)
    end

    local function bit7(value)
        return value % 256 >= 0x80
    end

    local function low7(value)
        return value % 0x80
    end

    local function inject_key(scan, modifiers)
        write_u8(key_flags, key_flag_eos + 1 + modifiers)
        write_u8(key_silo, scan)
        write_u8(key_silo + 1, 0)
        write_u8(key_silo + 2, 0)
        write_u8(key_silo + 3, 0)
    end

    local function write_alien_live_count(value)
        write_nibble_pair(inv_alien_live_lo, inv_alien_live_hi, value)
    end

    local function set_turret_x(value)
        write_nibble_pair(inv_turret_x_lo, inv_turret_x_hi, value)
    end

    local frame = 0
    local output_log = {}
    local stage = "boot"
    local stage_frame = 0
    local setup_key_repeats = 0
    local shift_i_repeats = 0
    local enter_key_repeats = 0
    local exit_key_repeats = 0
    local log_start = 1
    local heartbeat_case = 1

    output_tap = input_output_space():install_write_tap(
        iow_keyboard,
        iow_keyboard,
        "vt100-invaders-sound",
        function(offset, data, mem_mask)
            output_log[#output_log + 1] = {
                frame = frame,
                data = data % 256,
                stock = read_u8(inv_last_stock_kbd_status),
                output = read_u8(inv_last_output_kbd_status),
                active = read_u8(inv_active),
                attract = read_u8(inv_attract_mode),
                game_over = read_u8(inv_game_over),
                level_timer = read_u8(inv_level_timer),
                mode = read_u8(inv_sound_mode),
                heartbeat = read_u8(inv_heartbeat_timer),
                death = read_u8(inv_death_sound_timer) }
        end)

    local heartbeat_cases = {
        { count = 44, period = 24 },
        { count = 29, period = 16 },
        { count = 14, period = 10 },
        { count = 6, period = 6 },
    }

    local function enter_stage(next_stage)
        stage = next_stage
        stage_frame = frame
    end

    local function reset_sound_state()
        write_u8(inv_sound_mode, inv_sound_mode_silent)
        write_u8(inv_sound_timer, 0)
        write_u8(inv_sound_phase, 0)
        write_u8(inv_heartbeat_timer, 0)
        write_u8(inv_death_sound_timer, 0)
        write_u8(inv_last_stock_kbd_status, 0)
        write_u8(inv_last_output_kbd_status, 0)
        write_u8(kbd_click_mask, 0)
        write_u8(kbd_scan_mask, 0)
    end

    local function fail_timeout(description)
        test.fail(string.format(
            "%s timed out at host frame %d: game_frame=%s active=%s setup=%s game_over=%s mode=%s heartbeat=%s death=%s writes=%d",
            description,
            frame,
            test.hex(game_frame(), 2),
            test.hex(read_u8(inv_active), 2),
            test.hex(read_u8(in_setup), 2),
            test.hex(read_u8(inv_game_over), 2),
            test.hex(read_u8(inv_sound_mode), 2),
            test.hex(read_u8(inv_heartbeat_timer), 2),
            test.hex(read_u8(inv_death_sound_timer), 2),
            #output_log))
    end

    local function validate_status_entries(start_index)
        for index = start_index, #output_log do
            local entry = output_log[index]
            if entry.data ~= entry.output then
                error(string.format(
                    "keyboard status write %d did not match hook output: data=%s output=%s",
                    index,
                    test.hex(entry.data, 2),
                    test.hex(entry.output, 2)), 0)
            end
            if entry.attract ~= 0 then
                -- Attract mode owns the screen but is not part of this gameplay sound test.
            elseif entry.active == inv_active_value
                and entry.level_timer == 0
                and (entry.game_over == 0 or entry.death > 0) then
                if low7(entry.data) ~= low7(entry.stock) then
                    error(string.format(
                        "keyboard status write %d changed stock bits 0-6: stock=%s data=%s attract=%s mode=%s heartbeat=%s death=%s",
                        index,
                        test.hex(entry.stock, 2),
                        test.hex(entry.data, 2),
                        test.hex(entry.attract, 2),
                        test.hex(entry.mode, 2),
                        test.hex(entry.heartbeat, 2),
                        test.hex(entry.death, 2)), 0)
                end
            elseif entry.output ~= entry.stock then
                error(string.format(
                    "keyboard status write %d did not preserve stock status: stock=%s output=%s",
                    index,
                    test.hex(entry.stock, 2),
                    test.hex(entry.output, 2)), 0)
            end
        end
    end

    local function find_entry_since(start_index, predicate)
        for index = start_index, #output_log do
            local entry = output_log[index]
            if predicate(entry) then
                return entry, index
            end
        end
        return nil, nil
    end

    local function count_death_entries(start_index, final_death)
        local total = 0
        local clicks = 0
        local silences = 0
        local first_index = nil
        for index = start_index, #output_log do
            local entry = output_log[index]
            local game_over_matches = entry.game_over == 0
            if final_death then
                game_over_matches = entry.game_over ~= 0
            end
            if entry.active == inv_active_value
                and game_over_matches
                and entry.level_timer == 0
                and entry.death > 0 then
                if first_index == nil then
                    first_index = index
                end
                total = total + 1
                if bit7(entry.data) then
                    clicks = clicks + 1
                else
                    silences = silences + 1
                end
            end
        end
        return total, clicks, silences, first_index
    end

    local function start_heartbeat_case()
        local current = heartbeat_cases[heartbeat_case]
        reset_sound_state()
        write_u8(inv_game_over, 0)
        write_u8(inv_level_timer, 0)
        write_u8(inv_turret_death_timer, 0)
        write_u8(inv_missile_tick_timer, 0xff)
        write_u8(inv_missile_fire_timer, 0xff)
        write_alien_live_count(current.count)
        log_start = #output_log + 1
        enter_stage("heartbeat-sync")
    end

    local function seed_turret_hit(gunners, next_stage)
        reset_sound_state()
        write_u8(inv_game_over, 0)
        write_u8(inv_level_timer, 0)
        write_u8(inv_turret_death_timer, 0)
        write_u8(inv_gunners, gunners)
        set_turret_x(inv_turret_start_x)
        write_u8(inv_missile_tick_timer, 0)
        write_u8(inv_missile_fire_timer, 0xff)
        write_u8(inv_missile_active_count, 1)
        write_u8(inv_missile_shot_index, 0)
        for slot = 0, inv_missile_count - 1 do
            write_u8(inv_missile_active_base + slot, 0)
            write_u8(inv_missile_row_base + slot, 0)
            write_u8(inv_missile_col_base + slot, 0)
            write_u8(inv_missile_phase_base + slot, 0)
        end
        write_u8(inv_missile_active_base, 0xff)
        write_u8(inv_missile_row_base, inv_turret_top_row - 1)
        write_u8(inv_missile_col_base, inv_turret_start_x + math.floor(inv_turret_w / 2))
        write_u8(inv_missile_phase_base, 0)
        log_start = #output_log + 1
        enter_stage(next_stage)
    end

    local function start_game_over_silence()
        reset_sound_state()
        write_u8(inv_game_over, 0xff)
        write_u8(inv_level_timer, 0)
        write_u8(inv_sound_mode, inv_sound_mode_heartbeat)
        write_u8(inv_sound_timer, 1)
        log_start = #output_log + 1
        enter_stage("game-over-silence-sync")
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
                if read_u8(inv_active) == inv_active_value
                    and read_u8(inv_attract_mode) == 0
                    and read_nibble_pair(inv_alien_init_lo, inv_alien_init_hi) == inv_alien_count then
                    start_heartbeat_case()
                    return
                end
                if frame - stage_frame > 240 then
                    fail_timeout("formation")
                end
                return
            end

            if stage == "heartbeat-sync" then
                if #output_log >= log_start then
                    log_start = #output_log + 1
                    enter_stage("heartbeat")
                    return
                end
                if frame - stage_frame > 60 then
                    fail_timeout("heartbeat sync")
                end
                return
            end

            if stage == "heartbeat" then
                local entry, entry_index = find_entry_since(log_start, function(candidate)
                    return candidate.active == inv_active_value
                        and candidate.game_over == 0
                        and candidate.level_timer == 0
                        and candidate.death == 0
                        and bit7(candidate.data)
                end)
                if entry ~= nil then
                    validate_status_entries(entry_index)
                    local expected = heartbeat_cases[heartbeat_case].period
                    local timer = read_u8(inv_heartbeat_timer)
                    if timer > expected or timer + 2 < expected then
                        error(string.format(
                            "heartbeat timer for %d aliens: expected near %d, got %d",
                            heartbeat_cases[heartbeat_case].count,
                            expected,
                            timer), 0)
                    end
                    heartbeat_case = heartbeat_case + 1
                    if heartbeat_case > #heartbeat_cases then
                        seed_turret_hit(inv_initial_gunners, "wait-death-sound")
                    else
                        start_heartbeat_case()
                    end
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("heartbeat")
                end
                return
            end

            if stage == "wait-death-sound" then
                if read_u8(inv_turret_death_timer) ~= 0 then
                    local total, clicks, silences, first_index = count_death_entries(log_start, false)
                    if total >= 8 and clicks >= 2 and silences >= 2 then
                        validate_status_entries(first_index)
                        test.assert_eq(read_u8(inv_gunners), inv_initial_gunners - 1, "gunners after sound-tested turret hit")
                        test.assert_eq(read_u8(inv_heartbeat_timer), 0, "death sound suppresses heartbeat")
                        if read_u8(inv_death_sound_timer) >= inv_sound_death_words then
                            error("death sound timer did not advance from its starting value", 0)
                        end
                        if read_u8(inv_turret_death_timer) > inv_turret_death_frames then
                            error("turret death timer exceeded its starting value", 0)
                        end
                        seed_turret_hit(1, "wait-final-death-sound")
                        return
                    end
                end
                if frame - stage_frame > 120 then
                    fail_timeout("death sound")
                end
                return
            end

            if stage == "wait-final-death-sound" then
                if read_u8(inv_game_over) ~= 0 then
                    local total, clicks, silences, first_index = count_death_entries(log_start, true)
                    if total >= 8 and clicks >= 2 and silences >= 2 then
                        validate_status_entries(first_index)
                        test.assert_eq(read_u8(inv_gunners), 0, "gunners after final sound-tested hit")
                        test.assert_eq(read_u8(inv_turret_death_timer), 0, "final hit has no respawn timer")
                        if read_u8(inv_death_sound_timer) >= inv_sound_death_words then
                            error("final death sound timer did not advance from its starting value", 0)
                        end
                        start_game_over_silence()
                        return
                    end
                end
                if frame - stage_frame > 120 then
                    fail_timeout("final death sound")
                end
                return
            end

            if stage == "game-over-silence-sync" then
                if #output_log >= log_start then
                    log_start = #output_log + 1
                    enter_stage("game-over-silence")
                    return
                end
                if frame - stage_frame > 60 then
                    fail_timeout("game-over silence sync")
                end
                return
            end

            if stage == "game-over-silence" then
                if #output_log >= log_start then
                    validate_status_entries(log_start)
                    for index = log_start, #output_log do
                        if bit7(output_log[index].data) then
                            error("game over did not silence game-owned sound", 0)
                        end
                    end
                    test.assert_eq(read_u8(inv_sound_mode), inv_sound_mode_silent, "game over sound mode")
                    test.assert_eq(read_u8(inv_sound_timer), 0, "game over sound timer")
                    test.assert_eq(read_u8(inv_death_sound_timer), 0, "game over death sound timer")
                    enter_stage("exit-key")
                    return
                end
                if frame - stage_frame > 60 then
                    fail_timeout("game-over silence")
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
                if read_u8(inv_active) == 0 then
                    write_u8(kbd_click_mask, iow_kbd_click)
                    write_u8(kbd_scan_mask, 0)
                    log_start = #output_log + 1
                    enter_stage("stock-click")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("leaving Invaders")
                end
                return
            end

            if stage == "stock-click" then
                local entry = find_entry_since(log_start, function(candidate)
                    return candidate.active == 0 and bit7(candidate.data)
                end)
                if entry ~= nil then
                    validate_status_entries(log_start)
                    test.assert_eq(entry.stock, entry.data, "inactive stock click status")
                    test.assert_eq(entry.output, entry.data, "inactive hook output")
                    test.pass()
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("inactive stock click")
                end
            end
        end)

        if not ok then
            test.fail(err)
        end
    end
end

function M.start()
    local step_sound_test = nil

    emu.register_prestart(function()
        local ok, result = pcall(make_sound_step)
        if not ok then
            test.fail(result)
            return
        end
        step_sound_test = result
    end)

    frame_subscription = emu.add_machine_frame_notifier(function()
        if step_sound_test == nil then
            return
        end
        local ok, err = pcall(step_sound_test)
        if not ok then
            test.fail(err)
        end
    end)
end

return M
