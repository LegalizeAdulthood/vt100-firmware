local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local test = dofile(script_directory .. "/mame-test.lua")

test.run(function()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local equates = test.load_equates(binary_directory .. "/invaders-avo.equ")
    local symbols = test.load_symbols(binary_directory .. "/invaders-avo.sym")
    local inv_test_signature = test.required_equate(equates, "inv_test_signature")
    local inv_enter_impl = test.required_symbol(symbols, "inv_enter_impl")
    local inv_idle_impl = test.required_symbol(symbols, "inv_idle_impl")
    local inv_exit_impl = test.required_symbol(symbols, "inv_exit_impl")
    local inv_idle_hook_impl = test.required_symbol(symbols, "inv_idle_hook_impl")
    local inv_setup_keys_hook_impl = test.required_symbol(symbols, "inv_setup_keys_hook_impl")
    local inv_sound_status_hook_impl = test.required_symbol(symbols, "inv_sound_status_hook_impl")
    local inv_reset_hook_impl = test.required_symbol(symbols, "inv_reset_hook_impl")
    local inv_setup_cursor_hook_impl = test.required_symbol(symbols, "inv_setup_cursor_hook_impl")

    test.assert_between(inv_enter_impl, 0x8000, 0x9fff, "inv_enter_impl address")
    test.assert_between(inv_idle_impl, 0x8000, 0x9fff, "inv_idle_impl address")
    test.assert_between(inv_exit_impl, 0x8000, 0x9fff, "inv_exit_impl address")
    test.assert_between(inv_idle_hook_impl, 0x8000, 0x9fff, "inv_idle_hook_impl address")
    test.assert_between(inv_setup_keys_hook_impl, 0x8000, 0x9fff, "inv_setup_keys_hook_impl address")
    test.assert_between(inv_sound_status_hook_impl, 0x8000, 0x9fff, "inv_sound_status_hook_impl address")
    test.assert_between(inv_reset_hook_impl, 0x8000, 0x9fff, "inv_reset_hook_impl address")
    test.assert_between(inv_setup_cursor_hook_impl, 0x8000, 0x9fff, "inv_setup_cursor_hook_impl address")

    local mem = test.program_space()
    local function read_u8(address)
        return mem:read_u8(address)
    end
    local function write_u8(address, value)
        mem:write_u8(address, value)
    end
    local function jump_target(address)
        return read_u8(address + 1) + (read_u8(address + 2) * 256)
    end

    test.assert_eq(read_u8(0x8000), 0xc3, "inv_enter opcode")
    test.assert_eq(read_u8(0x8003), 0xc3, "inv_idle opcode")
    test.assert_eq(read_u8(0x8006), 0xc3, "inv_exit opcode")
    test.assert_eq(read_u8(0x8009), 0xc3, "inv_idle_hook opcode")
    test.assert_eq(read_u8(0x800c), 0xc3, "inv_setup_keys_hook opcode")
    test.assert_eq(read_u8(0x800f), 0xc3, "inv_sound_status_hook opcode")
    test.assert_eq(read_u8(0x8012), 0xc3, "inv_reset_hook opcode")
    test.assert_eq(read_u8(0x8015), 0xc3, "inv_setup_cursor_hook opcode")
    test.assert_eq(jump_target(0x8000), inv_enter_impl, "inv_enter target")
    test.assert_eq(jump_target(0x8003), inv_idle_impl, "inv_idle target")
    test.assert_eq(jump_target(0x8006), inv_exit_impl, "inv_exit target")
    test.assert_eq(jump_target(0x8009), inv_idle_hook_impl, "inv_idle_hook target")
    test.assert_eq(jump_target(0x800c), inv_setup_keys_hook_impl, "inv_setup_keys_hook target")
    test.assert_eq(jump_target(0x800f), inv_sound_status_hook_impl, "inv_sound_status_hook target")
    test.assert_eq(jump_target(0x8012), inv_reset_hook_impl, "inv_reset_hook target")
    test.assert_eq(jump_target(0x8015), inv_setup_cursor_hook_impl, "inv_setup_cursor_hook target")

    local old_sig0 = read_u8(inv_test_signature)
    local old_sig1 = read_u8(inv_test_signature + 1)
    local old_sig2 = read_u8(inv_test_signature + 2)

    write_u8(inv_test_signature, 0x05)
    write_u8(inv_test_signature + 1, 0x0a)
    write_u8(inv_test_signature + 2, 0x0f)
    test.assert_eq(read_u8(inv_test_signature), 0x05, "game RAM signature byte 0")
    test.assert_eq(read_u8(inv_test_signature + 1), 0x0a, "game RAM signature byte 1")
    test.assert_eq(read_u8(inv_test_signature + 2), 0x0f, "game RAM signature byte 2")

    write_u8(inv_test_signature, old_sig0)
    write_u8(inv_test_signature + 1, old_sig1)
    write_u8(inv_test_signature + 2, old_sig2)
end)
