-- license:BSD-3-Clause

local exports = {
    name = "vt100invadersgameover",
    version = "0.0.1",
    description = "VT100 Invaders game-over loop test",
    license = "BSD-3-Clause",
    author = { name = "VT100 Firmware" } }

local directory = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]+$")
local test = dofile(directory .. "/../mame-test.lua")
local taps = {}
local frame_subscription

local function make_test()
    local binary = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary .. "/invaders-avo.equ")
    local symbols = test.load_symbols(binary .. "/invaders-avo.sym")
    local mem = test.program_space()
    local function e(name) return test.required_equate(equates, name) end
    local function r(name) return mem:read_u8(e(name)) end
    local function w(name, value) mem:write_u8(e(name), value) end
    local function pair(name, value, index)
        index = index or 0
        mem:write_u8(e(name .. "_lo") + index, value % 16)
        mem:write_u8(e(name .. "_hi") + index, math.floor(value / 16))
    end
    local function row_address(row)
        local address = test.required_symbol(symbols, "inv_row_addr") + row * 2
        return mem:read_u8(address) + mem:read_u8(address + 1) * 256
    end
    local function screen()
        local cells = {}
        for row = 0, e("inv_screen_rows") - 1 do
            for column = 0, e("inv_screen_cols") - 1 do
                cells[#cells + 1] = string.char(mem:read_u8(row_address(row) + column))
            end
        end
        return table.concat(cells)
    end
    local function text_at(row, col, text)
        for index = 1, #text do
            test.assert_eq(mem:read_u8(row_address(row) + col + index - 1),
                text:byte(index), "displayed " .. text)
        end
    end
    local function cursor_hidden()
        test.assert_eq(r("curs_char_rend"), 0, "cursor character rendition")
        test.assert_eq(r("curs_attr_rend"), 0, "cursor attribute rendition")
        local cells = screen()
        for index = 1, #cells do
            test.assert_eq(cells:byte(index) & 0x80, 0, "no cursor left in screen RAM")
        end
    end

    local keys, modifiers = {}, 0
    local function inject_keys()
        w("key_flags", e("key_flag_eos") + #keys + modifiers)
        for index = 1, 4 do
            mem:write_u8(e("key_silo") + index - 1, keys[index] or 0)
        end
    end
    local ticks, ended_at, ended_refresh = 0, 0, 0
    local ends, qualifications, saves, status_words = 0, 0, 0, 0
    local message_writes, watching_message = 0, false
    local function watch_call(name, callback)
        local address = test.required_symbol(symbols, name)
        taps[#taps + 1] = mem:install_read_tap(address, address, name, function()
            local ok, err = pcall(callback)
            if not ok then test.fail(err) end
        end)
    end
    watch_call("inv_read_keys", inject_keys)
    watch_call("inv_set_game_over", function()
        ends = ends + 1
        ended_at, ended_refresh = ticks, r("frame_count")
        message_writes, watching_message = 0, true
    end)
    watch_call("inv_maybe_add_high_score", function()
        qualifications = qualifications + 1
        test.assert_between(ticks - ended_at, e("inv_game_over_frames"), 150,
            "qualification waits for presentation")
        test.assert_between((r("frame_count") - ended_refresh) % 256,
            e("inv_game_over_frames"), 160, "presentation lasts 90 refresh frames")
        test.assert_eq(r("inv_death_sound_timer"), 0, "qualification waits for sound")
        watching_message = false
    end)
    watch_call("inv_store_high_scores", function() saves = saves + 1 end)
    local message_address = row_address(e("inv_game_over_row")) + e("inv_game_over_col")
    taps[#taps + 1] = mem:install_write_tap(message_address, message_address + 10,
        "game-over-message", function()
            if watching_message then message_writes = message_writes + 1 end
        end)
    local io = manager.machine.devices[":maincpu"].spaces["io"]
    taps[#taps + 1] = io:install_write_tap(e("iow_keyboard"), e("iow_keyboard"),
        "game-over-status", function() status_words = status_words + 1 end)

    local function wait(frames)
        for _ = 1, frames do coroutine.yield() end
    end
    local function until_true(predicate, limit, description)
        for _ = 1, limit do
            if predicate() then return end
            wait(1)
        end
        error(description .. " timed out", 0)
    end
    local function launch()
        keys, modifiers = { e("inv_scan_setup") }, 0
        wait(2)
        keys = {}
        until_true(function() return r("in_setup") ~= 0 end, 60, "SET-UP")
        keys, modifiers = { 0x16 }, e("key_flag_shift")
        until_true(function() return r("inv_active") == e("inv_active_value") end, 60, "launch")
        keys, modifiers = {}, 0
        wait(3)
    end
    local function start_game()
        keys = { e("inv_scan_return_b") }
        until_true(function() return r("inv_attract_mode") == 0 end, 30, "fresh RETURN")
        keys = {}
        test.assert_eq(r("inv_game_over"), 0, "new game clears game over")
        test.assert_eq(r("inv_game_over_timer"), 0, "new game clears presentation timer")
        test.assert_eq(r("inv_gunners"), e("inv_initial_gunners"), "new game restores lives")
        test.assert_eq(r("inv_score0") + r("inv_score1") + r("inv_score2"), 0, "new score")
        cursor_hidden()
        until_true(function()
            return r("inv_alien_init_lo") + r("inv_alien_init_hi") * 16 == e("inv_alien_count")
        end, 60, "new formation")
    end
    local function table_digits(value)
        for offset = 0, e("inv_high_score_digits") - 1 do
            mem:write_u8(e("inv_high_score_digit_base") + offset, value)
        end
    end
    local function arm_end(invasion, score)
        w("inv_score0", score % 10)
        w("inv_score1", math.floor(score / 10) % 10)
        w("inv_score2", math.floor(score / 100))
        if invasion then
            for id = 0, e("inv_alien_count") - 1 do
                mem:write_u8(e("inv_alien_live_base") + id, id == 0 and 1 or 0)
            end
            pair("inv_alien_live", 1)
            pair("inv_alien_last", 0xff)
            w("inv_alien_x_lo_base", 9)
            w("inv_alien_x_hi_base", 1)
            local y = e("inv_ground_row") - e("inv_alien_h") + 1
            w("inv_alien_y_lo_base", y % 16)
            w("inv_alien_y_hi_base", math.floor(y / 16))
            w("inv_alien_reverse", 0)
            w("inv_alien_y_delta", 0)
        else
            w("inv_gunners", 1)
            w("inv_missile_active_base", 0xff)
            w("inv_missile_active_count", 1)
            w("inv_missile_row_base", e("inv_turret_top_row") - 1)
            w("inv_missile_col_base", e("inv_turret_start_x") + 3)
            w("inv_missile_tick_timer", 0)
        end
        keys = { e("inv_scan_return_b") }
        until_true(function() return r("inv_game_over") ~= 0 end, 4, "game over")
        test.assert_eq(r("inv_gunners"), 0, "all lives gone")
        test.assert_eq(r("led_state") & 15, 0, "life LEDs cleared")
        text_at(e("inv_game_over_row"), e("inv_game_over_col"), " GAME OVER ")
    end
    local function presentation(extend_sound)
        local frozen, q, words = screen(), qualifications, status_words
        for remaining = e("inv_game_over_frames"), 1, -1 do
            test.assert_eq(r("inv_game_over_timer"), remaining, "presentation countdown")
            test.assert_eq(qualifications, q, "no early qualification")
            test.assert_eq(r("inv_high_score_dirty"), 0, "no early initials")
            if screen() ~= frozen then error("playfield moved during GAME OVER", 0) end
            test.assert_eq(message_writes, 11, "GAME OVER drawn only once")
            if remaining == 1 and extend_sound then w("inv_death_sound_timer", 200) end
            wait(1)
        end
        if extend_sound then
            for _ = 1, 10 do
                test.assert_eq(r("inv_game_over_timer"), 0, "presentation timer expired")
                test.assert_eq(qualifications, q, "outstanding sound delays qualification")
                if screen() ~= frozen then error("playfield moved while sound finished", 0) end
                w("inv_death_sound_timer", 200)
                wait(1)
            end
            until_true(function() return qualifications ~= q end, 30, "death sound finishes")
        end
        test.assert_eq(qualifications, q + 1, "one qualification per game")
        test.assert_between(status_words - words, 90, 10000, "keyboard status continues")
    end
    local function moving_demo(expected_saves)
        until_true(function() return r("inv_attract_mode") ~= 0 end, 30, "return to demo")
        local q, first_frame = qualifications, ticks
        local first_screen = screen()
        wait(60) -- RETURN remains held throughout the post-game transition.
        test.assert_eq(r("inv_attract_mode"), 0xff, "held RETURN cannot start game")
        test.assert_eq(r("inv_game_over"), 0, "demo resets game over")
        test.assert_eq(r("inv_high_score_dirty"), 0, "demo clears pending initials")
        test.assert_eq(qualifications, q, "no repeated qualification")
        test.assert_eq(saves, expected_saves, "save count")
        test.assert_between(ticks - first_frame, 60, 60, "demo frames advance")
        if screen() == first_screen then error("returned demo is not animated", 0) end
        text_at(e("inv_attract_title_row"), e("inv_attract_title_col"), "VT100 INVADERS")
        text_at(e("inv_attract_prompt_row"), e("inv_attract_prompt_col"), "PRESS ENTER")
        cursor_hidden()
        keys = { e("inv_scan_arrow_left") } -- release RETURN, not necessarily all keys
        wait(3)
        test.assert_eq(r("inv_return_blocked"), 0, "RETURN release rearms start")
        keys = {}
    end

    local routine = coroutine.create(function()
        wait(120)
        test.poison_invaders_memory(equates, mem)
        test.disable_invaders_test_mode(equates, mem)
        w("inv_active", 0)
        launch()
        start_game()
        table_digits(0)
        arm_end(false, 0)
        presentation(false)
        moving_demo(0)

        start_game()
        table_digits(9)
        arm_end(true, 123)
        presentation(false)
        moving_demo(0)

        start_game()
        table_digits(0)
        arm_end(false, 123)
        presentation(true)
        test.assert_eq(r("inv_high_score_dirty"), 0xff, "qualifying score enters editor")
        wait(12)
        test.assert_eq(r("inv_high_initial_used"), 0, "held RETURN cannot enter initials")
        test.assert_eq(saves, 0, "no save without initials")
        keys = {}
        wait(3)
        keys = { 0x4a }
        until_true(function() return r("inv_high_initial_used") ~= 0 end, 10, "initial A")
        keys = {}
        wait(3)
        keys = { e("inv_scan_return_b") }
        moving_demo(1)
        test.assert_eq(r("inv_high_score_digit_base"), 3, "saved score in demo cache")
        text_at(e("inv_high_score_first_row"), e("inv_high_score_col"), "A   1230")

        start_game()
        arm_end(true, 124)
        presentation(false)
        keys = {}
        wait(3)
        keys = { 0x4a }
        until_true(function() return r("inv_high_initial_used") ~= 0 end, 10, "unconfirmed A")
        keys = { e("inv_scan_setup") }
        until_true(function() return r("inv_active") == 0 end, 3, "cancel initials")
        watching_message = false
        keys = {}
        wait(4)
        test.assert_eq(saves, 1, "cancelled initials not saved")
        test.assert_eq(r("cursor_visible"), 0, "cancel hides initials cursor")
        launch()
        test.assert_eq(r("inv_high_score_digit_base"), 3, "cancelled score not reloaded")
        start_game()
        arm_end(true, 0)
        local q = qualifications
        keys = { e("inv_scan_setup") }
        until_true(function() return r("inv_active") == 0 end, 3, "exit presentation")
        test.assert_eq(qualifications, q, "SET-UP exits before qualification")
        test.assert_eq(r("inv_game_over_timer"), 0, "exit clears presentation")
        test.assert_eq(saves, 1, "only confirmed score saved")
        test.assert_eq(ends, 5, "one end per game")
        test.pass()
    end)
    local failed = false
    local function step()
        if failed or coroutine.status(routine) == "dead" then return end
        local ok, err = coroutine.resume(routine)
        if not ok then
            failed = true
            test.fail(err)
        end
    end
    watch_call("inv_frame", function()
        ticks = ticks + 1
        step()
    end)
    return function()
        if r("inv_active") ~= e("inv_active_value") then
            inject_keys()
            step()
        end
    end
end

function exports.startplugin()
    local step
    emu.register_prestart(function()
        local ok, result = pcall(make_test)
        if ok then step = result else test.fail(result) end
    end)
    frame_subscription = emu.add_machine_frame_notifier(function()
        if step then
            local ok, err = pcall(step)
            if not ok then test.fail(err) end
        end
    end)
end

return exports
