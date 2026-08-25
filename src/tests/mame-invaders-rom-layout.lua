local script_directory = debug.getinfo(1, "S").source
if script_directory:sub(1, 1) == "@" then
    script_directory = script_directory:sub(2)
end
script_directory = script_directory:gsub("\\", "/")
script_directory = script_directory:match("^(.*)/[^/]+$") or "."

local test = dofile(script_directory .. "/mame-test.lua")

test.run(function()
    local binary_directory = test.required_env("VT100_INVADERS_BINARY_DIRECTORY")
    local symbols = test.load_symbols(binary_directory .. "/invaders-avo.sym")
    local inv_enter_impl = test.required_symbol(symbols, "inv_enter_impl")
    local inv_idle_impl = test.required_symbol(symbols, "inv_idle_impl")
    local inv_exit_impl = test.required_symbol(symbols, "inv_exit_impl")

    test.assert_between(inv_enter_impl, 0x8000, 0x9fff, "inv_enter_impl address")
    test.assert_between(inv_idle_impl, 0x8000, 0x9fff, "inv_idle_impl address")
    test.assert_between(inv_exit_impl, 0x8000, 0x9fff, "inv_exit_impl address")

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
    test.assert_eq(jump_target(0x8000), inv_enter_impl, "inv_enter target")
    test.assert_eq(jump_target(0x8003), inv_idle_impl, "inv_idle target")
    test.assert_eq(jump_target(0x8006), inv_exit_impl, "inv_exit target")

    local old_3ffd = read_u8(0x3ffd)
    local old_3ffe = read_u8(0x3ffe)
    local old_3fff = read_u8(0x3fff)

    write_u8(0x3ffd, 0x05)
    write_u8(0x3ffe, 0x0a)
    write_u8(0x3fff, 0x0f)
    test.assert_eq(read_u8(0x3ffd), 0x05, "AVO RAM 3ffdh")
    test.assert_eq(read_u8(0x3ffe), 0x0a, "AVO RAM 3ffeh")
    test.assert_eq(read_u8(0x3fff), 0x0f, "AVO RAM 3fffh")

    write_u8(0x3ffd, old_3ffd)
    write_u8(0x3ffe, old_3ffe)
    write_u8(0x3fff, old_3fff)
end)
