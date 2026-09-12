local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local test = dofile(script_directory .. "/mame-test.lua")

local M = {}
local frame_subscription

local function make_aliens_step()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary_directory .. "/invaders-avo.equ")
    local symbols = test.load_symbols(binary_directory .. "/invaders-avo.sym")

    local inv_active = test.required_equate(equates, "inv_active")
    local inv_test_mode = test.required_equate(equates, "inv_test_mode")
    local inv_test_script = test.required_equate(equates, "inv_test_script")
    local inv_test_result = test.required_equate(equates, "inv_test_result")
    local inv_frame_lo = test.required_equate(equates, "inv_frame_lo")
    local inv_frame_hi = test.required_equate(equates, "inv_frame_hi")
    local inv_alien_rows = test.required_equate(equates, "inv_alien_rows")
    local inv_alien_cols = test.required_equate(equates, "inv_alien_cols")
    local inv_alien_count = test.required_equate(equates, "inv_alien_count")
    local inv_alien_w = test.required_equate(equates, "inv_alien_w")
    local inv_alien_slot_w = test.required_equate(equates, "inv_alien_slot_w")
    local inv_alien_slot_h = test.required_equate(equates, "inv_alien_slot_h")
    local inv_alien_start_x = test.required_equate(equates, "inv_alien_start_x")
    local inv_alien_top_row = test.required_equate(equates, "inv_alien_top_row")
    local inv_alien_right_edge = test.required_equate(equates, "inv_alien_right_edge")
    local inv_alien_dir_left = test.required_equate(equates, "inv_alien_dir_left")
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

    local function alien_last()
        return read_nibble_pair(inv_alien_last_lo, inv_alien_last_hi)
    end

    local function write_alien_last(value)
        write_nibble_pair(inv_alien_last_lo, inv_alien_last_hi, value)
    end

    local function alien_x(id)
        return read_nibble_pair(inv_alien_x_lo_base + id, inv_alien_x_hi_base + id)
    end

    local function alien_y(id)
        return read_nibble_pair(inv_alien_y_lo_base + id, inv_alien_y_hi_base + id)
    end

    local function set_alien_x(id, value)
        write_nibble_pair(inv_alien_x_lo_base + id, inv_alien_x_hi_base + id, value)
    end

    local function expected_initial_x(id)
        return inv_alien_start_x + (id % inv_alien_cols) * inv_alien_slot_w
    end

    local function expected_initial_y(id)
        return inv_alien_top_row + math.floor(id / inv_alien_cols) * inv_alien_slot_h
    end

    local function inject_key(scan, modifiers)
        write_u8(key_flags, key_flag_eos + 1 + modifiers)
        write_u8(key_silo, scan)
        write_u8(key_silo + 1, 0)
        write_u8(key_silo + 2, 0)
        write_u8(key_silo + 3, 0)
    end

    local function assert_alien_position(id, expected_x, expected_y, description)
        test.assert_eq(alien_x(id), expected_x, description .. " x")
        test.assert_eq(alien_y(id), expected_y, description .. " y")
    end

    local function assert_initial_formation()
        test.assert_eq(alien_init_count(), inv_alien_count, "initialized alien count")
        test.assert_eq(alien_live_count(), inv_alien_count, "live alien count")
        test.assert_eq(read_u8(inv_alien_min_col), 0, "minimum alien column")
        test.assert_eq(read_u8(inv_alien_max_col), inv_alien_cols - 1, "maximum alien column")
        test.assert_eq(read_u8(inv_alien_min_row), 0, "minimum alien row")
        test.assert_eq(read_u8(inv_alien_max_row), inv_alien_rows - 1, "maximum alien row")
        test.assert_eq(read_u8(inv_alien_dir), inv_alien_dir_right, "initial alien direction")
        test.assert_eq(read_u8(inv_alien_reverse), 0, "initial alien reverse")
        test.assert_eq(read_u8(inv_alien_descents), 0, "initial alien descents")
        test.assert_eq(read_u8(inv_alien_anim_phase), 0, "initial alien animation")

        for id = 0, inv_alien_count - 1 do
            if read_u8(inv_alien_live_base + id) == 0 then
                test.fail("alien " .. tostring(id) .. " is not live after initialization")
                return
            end
        end

        assert_alien_position(0, inv_alien_start_x, inv_alien_top_row, "alien 0")
        assert_alien_position(
            inv_alien_cols - 1,
            inv_alien_start_x + (inv_alien_cols - 1) * inv_alien_slot_w,
            inv_alien_top_row,
            "top right alien")

        local bottom_left = (inv_alien_rows - 1) * inv_alien_cols
        local bottom_right = inv_alien_count - 1
        assert_alien_position(
            bottom_left,
            inv_alien_start_x,
            expected_initial_y(bottom_left),
            "bottom left alien")
        assert_alien_position(
            bottom_right,
            expected_initial_x(bottom_right),
            expected_initial_y(bottom_right),
            "bottom right alien")

        test.assert_eq(cell(inv_alien_top_row, inv_alien_start_x + 1), sg("a"), "30-point alien body")
        test.assert_eq(cell(inv_alien_top_row + 1, inv_alien_start_x), sg("m"), "30-point alien bottom left")
        test.assert_eq(cell(inv_alien_top_row + 1, inv_alien_start_x + 3), sg("j"), "30-point alien bottom right")
        test.assert_eq(
            cell(expected_initial_y(bottom_right), expected_initial_x(bottom_right)),
            sg("l"),
            "10-point alien top left")
        test.assert_eq(
            cell(expected_initial_y(bottom_right) + 1, expected_initial_x(bottom_right)),
            sg("x"),
            "10-point alien bottom left")
    end

    local frame = 0
    local stage = "boot"
    local stage_frame = 0
    local setup_key_repeats = 0
    local shift_i_repeats = 0
    local formation_frame = inv_alien_count
    local movement_frame = formation_frame + inv_alien_count + 18
    local skip_frame = nil
    local edge_frame = nil
    local alien0_x_before_edge = nil
    local alien0_y_before_edge = nil
    local moved_once_alien = 18
    local skipped_alien = 21
    local edge_alien = inv_alien_count - 1

    local function enter_stage(next_stage)
        stage = next_stage
        stage_frame = frame
    end

    local function fail_timeout(description)
        test.fail(string.format(
            "%s timed out at host frame %d: game_frame=%s init=%s live=%s last=%s",
            description,
            frame,
            test.hex(game_frame(), 2),
            test.hex(alien_init_count(), 2),
            test.hex(alien_live_count(), 2),
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
                enter_stage("wait-start")
                return
            end

            if stage == "wait-start" then
                if read_u8(inv_active) ~= 0 then
                    enter_stage("wait-formation-frame")
                    return
                end
                if frame - stage_frame > 120 then
                    fail_timeout("entering Invaders")
                end
                return
            end

            if stage == "wait-formation-frame" then
                if game_frame() == formation_frame then
                    assert_initial_formation()
                    enter_stage("wait-movement-frame")
                    return
                end
                if game_frame() > formation_frame then
                    test.fail("missed formation frame")
                    return
                end
                if frame - stage_frame > 240 then
                    fail_timeout("formation frame")
                end
                return
            end

            if stage == "wait-movement-frame" then
                if game_frame() == movement_frame then
                    test.assert_eq(alien_last(), 17, "alien moved at checkpoint")
                    test.assert_eq(read_u8(inv_alien_anim_phase), 1, "animation toggled after one sweep")
                    test.assert_eq(read_u8(inv_alien_descents), 0, "no descent before edge")
                    test.assert_eq(read_u8(inv_alien_dir), inv_alien_dir_right, "direction before edge")
                    assert_alien_position(0, expected_initial_x(0) + 2, expected_initial_y(0), "twice-moved alien 0")
                    assert_alien_position(
                        moved_once_alien,
                        expected_initial_x(moved_once_alien) + 1,
                        expected_initial_y(moved_once_alien),
                        "once-moved alien")

                    write_u8(inv_alien_live_base + skipped_alien, 0)
                    write_nibble_pair(inv_alien_live_lo, inv_alien_live_hi, inv_alien_count - 1)
                    write_alien_last(skipped_alien - 1)
                    skip_frame = game_frame()
                    enter_stage("wait-skip-dead")
                    return
                end
                if game_frame() > movement_frame then
                    test.fail("missed movement checkpoint")
                    return
                end
                if frame - stage_frame > 240 then
                    fail_timeout("movement checkpoint")
                end
                return
            end

            if stage == "wait-skip-dead" then
                if alien_last() == skipped_alien + 1 then
                    test.assert_eq(alien_live_count(), inv_alien_count - 1, "live count after forced removal")
                    alien0_x_before_edge = alien_x(0)
                    alien0_y_before_edge = alien_y(0)
                    write_u8(inv_alien_live_base + edge_alien, 0x0f)
                    set_alien_x(edge_alien, inv_alien_right_edge - inv_alien_w)
                    write_alien_last(edge_alien - 1)
                    write_u8(inv_alien_dir, inv_alien_dir_right)
                    write_u8(inv_alien_reverse, 0)
                    write_u8(inv_alien_y_delta, 0)
                    write_u8(inv_alien_descents, 0)
                    write_u8(inv_alien_anim_phase, 0)
                    edge_frame = game_frame()
                    enter_stage("wait-edge-hit")
                    return
                end
                if game_frame() > skip_frame + 4 then
                    fail_timeout("skipping removed alien")
                end
                return
            end

            if stage == "wait-edge-hit" then
                if alien_last() == edge_alien then
                    test.assert_eq(
                        alien_x(edge_alien),
                        inv_alien_right_edge - inv_alien_w + 1,
                        "right edge alien x")
                    if read_u8(inv_alien_reverse) == 0 then
                        test.fail("right edge did not request reversal")
                        return
                    end
                    enter_stage("wait-edge-wrap")
                    return
                end
                if game_frame() > edge_frame + 4 then
                    fail_timeout("right edge hit")
                end
                return
            end

            if stage == "wait-edge-wrap" then
                if alien_last() == 0 then
                    test.assert_eq(read_u8(inv_alien_dir), inv_alien_dir_left, "direction after edge wrap")
                    test.assert_eq(read_u8(inv_alien_reverse), 0, "reverse cleared after edge wrap")
                    test.assert_eq(read_u8(inv_alien_y_delta), 1, "descent delta after edge wrap")
                    test.assert_eq(read_u8(inv_alien_descents), 1, "descent count after edge wrap")
                    test.assert_eq(read_u8(inv_alien_anim_phase), 1, "animation toggled on edge wrap")
                    test.assert_eq(alien_x(0), alien0_x_before_edge - 1, "alien 0 descended x")
                    test.assert_eq(alien_y(0), alien0_y_before_edge + 1, "alien 0 descended y")
                    test.pass()
                    return
                end
                if game_frame() > edge_frame + 8 then
                    fail_timeout("edge wrap")
                end
            end
        end)

        if not ok then
            test.fail(err)
        end
    end
end

function M.start()
    local step_aliens_test = nil

    emu.register_prestart(function()
        local ok, result = pcall(make_aliens_step)
        if not ok then
            test.fail(result)
            return
        end
        step_aliens_test = result
    end)

    frame_subscription = emu.add_machine_frame_notifier(function()
        if step_aliens_test == nil then
            return
        end
        local ok, err = pcall(step_aliens_test)
        if not ok then
            test.fail(err)
        end
    end)
end

return M
