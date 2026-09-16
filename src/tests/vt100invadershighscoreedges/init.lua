-- license:BSD-3-Clause

local exports = {
    name = "vt100invadershighscoreedges",
    version = "0.0.1",
    description = "VT100 Invaders high-score edge cases and restart test",
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
    local file = assert(io.open(directory .. "/../high-score-cases.json", "r"))
    local cases = require("json").parse(file:read("a"))
    file:close()
    local case = assert(cases[test.required_env("VT100_INVADERS_TEST_CASE")])
    local reload = test.required_env("VT100_INVADERS_TEST_PHASE") == "reload"
    local mem = test.program_space()
    local function e(name) return test.required_equate(equates, name) end
    local function r(name, index) return mem:read_u8(e(name) + (index or 0)) end
    local function w(name, value, index) mem:write_u8(e(name) + (index or 0), value) end
    local function pair(name, value, index)
        w(name .. "_lo", value % 16, index)
        w(name .. "_hi", math.floor(value / 16), index)
    end
    local function row_address(row)
        local address = test.required_symbol(symbols, "inv_row_addr") + row * 2
        return mem:read_u8(address) + mem:read_u8(address + 1) * 256
    end
    local function text_at(row, column, text)
        for index = 1, #text do
            test.assert_eq(mem:read_u8(row_address(row) + column + index - 1) & 0x7f,
                text:byte(index), "displayed " .. text .. " character " .. index)
        end
    end
    local expected = {}
    for slot, score in ipairs(case.scores) do
        expected[slot] = {
            score = score <= 999 and score or 0,
            initials = score > 0 and score <= 999 and case.initials[slot] or "   " }
    end
    local function inserted(rows, score, initials, slot)
        local result = {}
        for index, entry in ipairs(rows) do
            result[index] = { score = entry.score, initials = entry.initials }
        end
        table.insert(result, slot + 1, { score = score, initials = initials })
        table.remove(result)
        return result
    end
    if reload then
        for _, operation in ipairs(case.operations) do
            if operation.slot >= 0 and not operation.cancel then
                expected = inserted(expected, (operation.score + (operation.award or 0)) % 1000,
                    operation.initials, operation.slot)
            end
        end
    end
    local function assert_table(rows, description, display)
        for slot = 0, 9 do
            local entry = rows[slot + 1]
            local score = r("inv_high_score_digit_base", slot * 3)
                + r("inv_high_score_digit_base", slot * 3 + 1) * 10
                + r("inv_high_score_digit_base", slot * 3 + 2) * 100
            test.assert_eq(score, entry.score, description .. " score " .. slot)
            for index = 0, 2 do
                local offset = slot * 3 + index
                local code = r("inv_high_initial_lo_base", offset)
                    + r("inv_high_initial_hi_base", offset) * 16
                test.assert_eq(code + 32, entry.initials:byte(index + 1),
                    description .. " initial " .. offset)
            end
            if display then
                local text = entry.score == 0 and "        "
                    or entry.initials .. " " .. string.format("%04d", entry.score * 10)
                text_at(e("inv_high_score_first_row") + slot, e("inv_high_score_col"), text)
            end
        end
    end
    local function packed_word(address)
        if address <= 60 then return expected[address - 50].score end
        local initials = {}
        for _, entry in ipairs(expected) do initials[#initials + 1] = entry.initials end
        initials = table.concat(initials)
        local index = (address - 61) * 2 + 1
        return (initials:byte(index) - 32) | ((initials:byte(index + 1) - 32) << 6)
    end

    local keys, modifiers = {}, 0
    local function inject_keys()
        w("key_flags", e("key_flag_eos") + #keys + modifiers)
        for index = 1, 4 do w("key_silo", keys[index] or 0, index - 1) end
    end
    local saves, writes, qualifications = 0, 0, 0
    local watching_nvr = false
    local function watch_call(name, callback)
        local address = test.required_symbol(symbols, name)
        taps[#taps + 1] = mem:install_read_tap(address, address, name, function()
            local ok, err = pcall(callback)
            if not ok then test.fail(err) end
        end)
    end
    watch_call("inv_read_keys", inject_keys)
    watch_call("inv_maybe_add_high_score", function() qualifications = qualifications + 1 end)
    watch_call("inv_store_high_scores", function() saves = saves + 1 end)
    local base_symbols = test.load_symbols(binary .. "/invaders.sym")
    local write_address = test.required_symbol(base_symbols, "write_nvr_byte")
    taps[#taps + 1] = mem:install_read_tap(write_address, write_address, "high-score-nvr-write", function()
        if not watching_nvr then return end -- POST reads this byte while checksumming base ROM.
        local ok, err = pcall(function()
            local address = r("nvr_addr")
            test.assert_eq(address, 51 + writes % 25, "only sequential high-score words written")
            test.assert_eq(r("nvr_data") + r("nvr_data", 1) * 256,
                packed_word(address), "packed NVR word " .. address)
            writes = writes + 1
        end)
        if not ok then test.fail(err) end
    end)

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
    local function release()
        keys, modifiers = {}, 0
        wait(3)
    end
    local function launch()
        keys = { e("inv_scan_setup") }
        wait(2)
        keys = {}
        until_true(function() return r("in_setup") ~= 0 end, 60, "SET-UP")
        keys, modifiers = { 0x16 }, e("key_flag_shift")
        until_true(function() return r("inv_active") == e("inv_active_value") end, 60, "launch")
        release()
        assert_table(expected, "loaded attract table", true)
    end
    local function exit_game()
        keys = { e("inv_scan_setup") }
        until_true(function() return r("inv_active") == 0 end, 10, "SET-UP exit")
        release()
    end
    local function start_game()
        keys = { e("inv_scan_return_b") }
        until_true(function() return r("inv_attract_mode") == 0 end, 30, "RETURN start")
        release()
    end
    local function set_score(value)
        w("inv_score0", value % 10)
        w("inv_score1", math.floor(value / 10) % 10)
        w("inv_score2", math.floor(value / 100))
    end
    local function set_alien(id, x, y)
        w("inv_alien_live_base", 1, id)
        w("inv_alien_x_lo_base", x % 16, id)
        w("inv_alien_x_hi_base", math.floor(x / 16), id)
        w("inv_alien_y_lo_base", y % 16, id)
        w("inv_alien_y_hi_base", math.floor(y / 16), id)
    end
    local function clear_aliens()
        for id = 0, e("inv_alien_count") - 1 do w("inv_alien_live_base", 0, id) end
        pair("inv_alien_init", e("inv_alien_count"))
        pair("inv_alien_last", 0xff)
        w("inv_alien_reverse", 0)
        w("inv_alien_y_delta", 0)
        w("inv_alien_dir", e("inv_alien_dir_right"))
    end
    local function award_points(units, resulting_score)
        clear_aliens()
        local target = units == 3 and 0 or e("inv_alien_count") - 1
        local other = target == 0 and e("inv_alien_count") - 1 or 0
        set_alien(target, 20, 4)
        set_alien(other, 50, 8)
        pair("inv_alien_live", 2)
        w("inv_laser_active", 0xff)
        pair("inv_laser_row", 5)
        pair("inv_laser_col", 22)
        w("inv_laser_timer", 0)
        until_true(function() return r("inv_laser_active") == 0 end, 3, "rollover laser collision")
        test.assert_eq(r("inv_alien_live_base", target), 0, "award killed target alien")
        test.assert_eq(r("inv_score0") + r("inv_score1") * 10 + r("inv_score2") * 100,
            resulting_score, "score rollover")
        text_at(e("inv_score_row"), 6, string.format("%04d", resulting_score * 10))
    end
    local function end_game()
        clear_aliens()
        pair("inv_alien_live", 1)
        set_alien(0, 25, e("inv_ground_row") - e("inv_alien_h") + 1)
        local q = qualifications
        until_true(function() return qualifications == q + 1 end, 100, "game-over qualification")
    end
    local keymap = { A = {0x4a, 0}, B = {0x68, 0}, ["!"] = {0x1a, e("key_flag_shift")},
        [" "] = {e("inv_scan_space"), 0} }
    local function enter_initials(text)
        release()
        for index = 1, #text do
            local key = assert(keymap[text:sub(index, index)])
            keys, modifiers = { key[1] }, key[2]
            until_true(function() return r("inv_high_initial_index") == index end, 10, "initial " .. index)
            release()
        end
    end

    local routine = coroutine.create(function()
        wait(120)
        watching_nvr = true
        test.poison_invaders_memory(equates, mem)
        test.disable_invaders_test_mode(equates, mem)
        w("inv_active", 0)
        launch()
        if reload then
            wait(64)
            assert_table(expected, "restarted emulator", true)
            test.assert_eq(writes, 0, "reload does not write NVR")
            test.pass()
            return
        end
        local confirmed = 0
        for number, operation in ipairs(case.operations) do
            start_game()
            local score = (operation.score + (operation.award or 0)) % 1000
            set_score(operation.score)
            if operation.award then award_points(operation.award, score) end
            end_game()
            if operation.slot < 0 then
                test.assert_eq(r("inv_high_score_dirty"), 0, "nonqualifying score skips initials")
                test.assert_eq(r("inv_attract_mode"), 0xff, "nonqualifying score returns to attract")
            else
                test.assert_eq(r("inv_high_score_dirty"), 0xff, "qualifying score enters initials")
                test.assert_eq(r("inv_high_score_slot"), operation.slot, "insertion position")
                assert_table(inserted(expected, score, "   ", operation.slot), "pending insertion", false)
                enter_initials(operation.initials)
                local pending = inserted(expected, score, operation.initials, operation.slot)
                assert_table(pending, "edited insertion", false)
                if operation.cancel then
                    exit_game()
                    launch()
                else
                    expected = pending
                    keys = { e("inv_scan_return_b") }
                    until_true(function() return r("inv_attract_mode") ~= 0 end, 30, "confirm initials")
                    confirmed = confirmed + 1
                end
            end
            release()
            assert_table(expected, "operation " .. number, true)
            test.assert_eq(saves, confirmed, "only confirmed entries saved")
            test.assert_eq(writes, confirmed * 25, "all score and packed initial words saved")
            exit_game()
            launch() -- Reload from the emulated ER1400 after every operation.
            assert_table(expected, "recalled operation " .. number, true)
        end
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
    watch_call("inv_frame", step)
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
