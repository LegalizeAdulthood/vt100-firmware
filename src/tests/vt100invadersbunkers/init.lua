-- license:BSD-3-Clause

local exports = {
    name = "vt100invadersbunkers",
    version = "0.0.1",
    description = "VT100 Invaders bunker overrun test",
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
    local function pair(name, value)
        w(name .. "_lo", value % 16)
        w(name .. "_hi", math.floor(value / 16))
    end
    local function row_address(row)
        local address = test.required_symbol(symbols, "inv_row_addr") + row * 2
        return mem:read_u8(address) + mem:read_u8(address + 1) * 256
    end
    local function cell(row, col) return mem:read_u8(row_address(row) + col) end
    local function put_cell(row, col, glyph) mem:write_u8(row_address(row) + col, glyph) end
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

    local width, height = e("inv_shield_w"), e("inv_shield_h")
    local top = e("inv_shield_top_row")
    local left = { e("inv_shield0_x"), e("inv_shield1_x"), e("inv_shield2_x"), e("inv_shield3_x") }
    local initial = { 7, 1, 1, 1, 1, 1, 8, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1 }
    local glyphs = { [0] = 0, [1] = 2, [7] = string.byte("/"), [8] = string.byte("\\"),
        [9] = string.byte("*"), [10] = string.byte(".") }
    local model, damage = {}, {}
    local alien_x, alien_y
    local function reset_model()
        for shield = 1, #left do
            model[shield], damage[shield] = {}, {}
            for index, value in ipairs(initial) do model[shield][index] = value end
            for col = 1, width do damage[shield][col] = 0 end
        end
        alien_x, alien_y = nil, nil
    end
    local function assert_bunkers(description, state_only)
        for shield = 1, #left do
            for row = 0, height - 1 do
                for col = 0, width - 1 do
                    local index = row * width + col + 1
                    local expected = model[shield][index]
                    local address = e("inv_shield_cells_base") + (shield - 1) * width * height + index - 1
                    local label = description .. " bunker " .. shield .. " cell " .. index
                    test.assert_eq(mem:read_u8(address), expected, label .. " collision")
                    local covered = alien_x and top + row >= alien_y and top + row < alien_y + e("inv_alien_h")
                        and left[shield] + col >= alien_x and left[shield] + col < alien_x + e("inv_alien_w")
                    if not state_only and not covered then
                        test.assert_eq(cell(top + row, left[shield] + col), glyphs[expected], label .. " screen")
                    end
                end
            end
            for col = 1, width do
                test.assert_eq(mem:read_u8(e("inv_shield_damage_base") + (shield - 1) * width + col - 1),
                    damage[shield][col], description .. " column damage")
            end
        end
    end
    local function crush_model()
        for shield = 1, #left do
            for row = 0, height - 1 do
                for col = 0, width - 1 do
                    if top + row >= alien_y and top + row < alien_y + e("inv_alien_h")
                        and left[shield] + col >= alien_x and left[shield] + col < alien_x + e("inv_alien_w") then
                        model[shield][row * width + col + 1] = 0
                    end
                end
            end
        end
    end
    local function damage_model(shield, col)
        damage[shield][col + 1] = math.min(3, damage[shield][col + 1] + 1)
        local code = ({ 9, 10, 0 })[damage[shield][col + 1]]
        for row = 0, height - 1 do
            local index = row * width + col + 1
            if model[shield][index] ~= 0 then model[shield][index] = code end
        end
    end

    local keys, modifiers = {}, 0
    local function inject_keys()
        w("key_flags", e("key_flag_eos") + #keys + modifiers)
        for index = 1, 4 do mem:write_u8(e("key_silo") + index - 1, keys[index] or 0) end
    end
    local function launch_game()
        keys, modifiers = { e("inv_scan_setup") }, 0
        wait(2)
        keys = {}
        until_true(function() return r("in_setup") ~= 0 end, 60, "SET-UP")
        keys, modifiers = { 0x16 }, e("key_flag_shift")
        until_true(function() return r("inv_active") == e("inv_active_value") end, 60, "launch")
        keys, modifiers = {}, 0
        wait(3)
        reset_model()
        assert_bunkers("fresh demo", true)
        keys = { e("inv_scan_return_b") }
        until_true(function() return r("inv_attract_mode") == 0 end, 30, "start game")
        keys = {}
        until_true(function()
            return r("inv_alien_init_lo") + r("inv_alien_init_hi") * 16 == e("inv_alien_count")
        end, 60, "formation")
        for id = 0, e("inv_alien_count") - 1 do mem:write_u8(e("inv_alien_live_base") + id, 0) end
        pair("inv_alien_live", 0)
        pair("inv_alien_last", 0xff)
        assert_bunkers("fresh game")
    end
    local function restart_game()
        keys = { e("inv_scan_setup") }
        until_true(function() return r("inv_active") == 0 end, 3, "exit")
        keys = {}
        wait(4)
        launch_game()
    end
    local function place_alien(x, y)
        alien_x, alien_y = x, y
        w("inv_alien_x_lo_base", x % 16)
        w("inv_alien_x_hi_base", math.floor(x / 16))
        w("inv_alien_y_lo_base", y % 16)
        w("inv_alien_y_hi_base", math.floor(y / 16))
        w("inv_alien_live_base", 1)
        pair("inv_alien_last", 0)
    end
    local function move_alien(dx, descend)
        pair("inv_alien_live", 1)
        w("inv_alien_dir", (dx == 1) ~= (descend == true) and 1 or 0)
        w("inv_alien_reverse", descend and 1 or 0)
        w("inv_alien_y_delta", 0)
        alien_x, alien_y = alien_x + dx, alien_y + (descend and 1 or 0)
        crush_model()
        wait(1)
        pair("inv_alien_live", 0) -- keep the drawn alien still during projectile checks
        test.assert_eq(r("inv_alien_x_lo_base") + r("inv_alien_x_hi_base") * 16, alien_x, "moved alien x")
        test.assert_eq(r("inv_alien_y_lo_base") + r("inv_alien_y_hi_base") * 16, alien_y, "moved alien y")
        assert_bunkers("alien movement")
    end
    local function laser(row, col)
        w("inv_laser_active", 0xff)
        w("inv_laser_timer", 1)
        pair("inv_laser_row", row)
        pair("inv_laser_col", col)
        put_cell(row, col, e("inv_laser_glyph"))
    end
    local function missile(row, col)
        w("inv_missile_active_base", 0xff)
        w("inv_missile_active_count", 1)
        w("inv_missile_row_base", row)
        w("inv_missile_col_base", col)
        w("inv_missile_phase_base", 0)
        w("inv_missile_tick_timer", 1)
        put_cell(row, col, e("inv_missile_glyph"))
    end
    local function laser_hit(shield, col)
        laser(top + height, left[shield] + col)
        damage_model(shield, col)
        until_true(function() return r("inv_laser_active") == 0 end, 5, "laser hits surviving bunker")
        assert_bunkers("laser column damage")
    end
    local function next_level()
        local level = r("inv_level")
        w("inv_level_timer", 1)
        wait(1)
        alien_x, alien_y = nil, nil
        test.assert_eq(r("inv_level"), level + 1, "next level")
        assert_bunkers("next level retains destruction")
    end
    local function alien_image()
        local image = {}
        for row = alien_y, alien_y + e("inv_alien_h") - 1 do
            for col = alien_x, alien_x + e("inv_alien_w") - 1 do image[#image + 1] = cell(row, col) end
        end
        return table.concat(image, ",")
    end

    local routine = coroutine.create(function()
        wait(120)
        test.poison_invaders_memory(equates, mem)
        test.disable_invaders_test_mode(equates, mem)
        w("inv_active", 0)
        launch_game()

        for shield = 1, #left do
            -- Keep intact columns alongside columns at both partial-damage levels.
            w("inv_alien_live_base", 0)
            alien_x, alien_y = nil, nil
            laser_hit(shield, 1)
            laser_hit(shield, 5)
            laser_hit(shield, 5)
            local dx = shield % 2 == 1 and 1 or -1
            local start = dx == 1 and left[shield] - e("inv_alien_w") or left[shield] + width
            place_alien(start, top - 1)
            for _ = 1, width + e("inv_alien_w") do move_alien(dx) end
            -- The reverse pass covers the body and bottom opening, not just the roof.
            place_alien(alien_x, top + 1)
            for _ = 1, width + e("inv_alien_w") do move_alien(-dx) end
            assert_bunkers("after alien leaves bunker")
        end
        next_level()
        restart_game()

        -- Descend from above into only part of the roof, including sprite padding.
        place_alien(left[1], top - 2)
        move_alien(1, true)
        local image = alien_image()
        laser_hit(1, 1)
        if alien_image() ~= image then error("column redraw painted over live alien", 0) end
        for _ = 1, width do move_alien(1) end
        assert_bunkers("after roof overrun")

        -- Enemy fire passes the crushed roof and hits the surviving body below it.
        missile(top - 1, left[1] + 1)
        wait(1)
        test.assert_eq(r("inv_missile_active_base"), 0xff, "missile crosses crushed roof")
        test.assert_eq(r("inv_missile_row_base"), top, "missile in roof gap")
        test.assert_eq(cell(top, left[1] + 1), e("inv_missile_glyph"), "missile visible in gap")
        damage_model(1, 1)
        until_true(function() return r("inv_missile_active_base") == 0 end, 5, "missile hits body")
        assert_bunkers("missile damage cannot restore roof")
        laser_hit(1, 1)

        laser(top + height, left[1] + 1)
        wait(height + 1)
        test.assert_eq(r("inv_laser_active"), 0xff, "laser crosses crushed column")
        test.assert_eq(r("inv_laser_row_lo") + r("inv_laser_row_hi") * 16, top - 1, "laser above bunker")
        assert_bunkers("laser leaves no trail in crushed column")
        until_true(function() return r("inv_laser_active") == 0 end, 25, "laser exits")
        missile(top - 1, left[1] + 1)
        until_true(function() return r("inv_missile_active_base") == 0 end, 15, "missile crosses crushed column")
        assert_bunkers("missile leaves no trail in crushed column")
        missile(top - 1, left[1])
        damage_model(1, 0)
        until_true(function() return r("inv_missile_active_base") == 0 end, 5, "missile hits adjacent roof")
        assert_bunkers("adjacent roof still blocks missiles")

        place_alien(left[1] - e("inv_alien_w"), top)
        move_alien(1, true)
        move_alien(1)
        move_alien(1)
        -- Kill the survivor over the bunker, retaining adjacent roof and body cells.
        pair("inv_alien_live", 1)
        w("inv_alien_reverse", 0)
        w("inv_alien_dir", 1)
        laser(top + height, alien_x + 2)
        alien_x = alien_x + 1
        crush_model()
        wait(1)
        test.assert_eq(r("inv_alien_live_base"), 0, "alien killed")
        alien_x, alien_y = nil, nil
        assert_bunkers("alien death does not restore bunker")
        next_level()
        restart_game()
        assert_bunkers("new game restores bunkers and column hit points")
        test.pass()
    end)

    local failed = false
    local function step()
        if failed or coroutine.status(routine) == "dead" then return end
        local ok, err = coroutine.resume(routine)
        if not ok then failed = true; test.fail(err) end
    end
    local function watch_call(name, callback)
        local address = test.required_symbol(symbols, name)
        taps[#taps + 1] = mem:install_read_tap(address, address, name, callback)
    end
    watch_call("inv_read_keys", inject_keys)
    watch_call("inv_frame", function()
        w("inv_missile_fire_timer", 0xff) -- isolate seeded projectiles from scheduled enemy fire
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
