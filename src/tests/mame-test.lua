local M = {}

function M.required_env(name)
    local value = os.getenv(name)
    if value == nil or value == "" then
        error("missing required environment variable " .. name, 0)
    end
    return value
end

function M.load_symbols(path)
    local symbols = {}
    local file, err = io.open(path, "r")
    if not file then
        error("could not open symbol file " .. path .. ": " .. tostring(err), 0)
    end
    for line in file:lines() do
        local address, name = line:match("^%s*([0-9A-Fa-f]+)%s+([%w_]+)%s*$")
        if address and name then
            symbols[name] = tonumber(address, 16)
        else
            name, address = line:match("^%s*([%w_]+)%s+[Ee][Qq][Uu]%s+([0-9A-Fa-f]+)[Hh]%s*$")
            if address and name then
                symbols[name] = tonumber(address, 16)
            end
        end
    end
    file:close()
    return symbols
end

function M.load_equates(path)
    return M.load_symbols(path)
end

function M.required_symbol(symbols, name)
    local value = symbols[name]
    if value == nil then
        error("missing symbol " .. name, 0)
    end
    return value
end

function M.required_equate(equates, name)
    local value = equates[name]
    if value == nil then
        error("missing equate " .. name, 0)
    end
    return value
end

function M.hex(value, width)
    width = width or 4
    return string.format("0x%0" .. tostring(width) .. "X", value)
end

function M.assert_eq(actual, expected, description)
    if actual ~= expected then
        error(
            string.format(
                "%s: expected %s, got %s",
                description,
                M.hex(expected),
                M.hex(actual)),
            0)
    end
end

function M.assert_between(value, low, high, description)
    if value < low or value > high then
        error(
            string.format(
                "%s: expected %s through %s, got %s",
                description,
                M.hex(low),
                M.hex(high),
                M.hex(value)),
            0)
    end
end

function M.program_space()
    local cpu = manager.machine.devices[":maincpu"]
    if cpu == nil then
        error("could not find :maincpu device", 0)
    end
    local space = cpu.spaces["program"]
    if space == nil then
        error("could not find :maincpu program space", 0)
    end
    return space
end

local INVADERS_JUNK_PATTERN = { 0xde, 0xad, 0xbe, 0xef }

function M.invaders_junk_byte(address, base)
    local offset = address - base
    return INVADERS_JUNK_PATTERN[(offset % #INVADERS_JUNK_PATTERN) + 1]
end

function M.poison_invaders_memory(equates, mem)
    mem = mem or M.program_space()
    local low = equates["inv_volatile_data_low"]
    if low == nil then
        low = M.required_equate(equates, "inv_data_low")
    end
    local top = M.required_equate(equates, "inv_data_top")
    local skip_low = equates["inv_high_score_cache_base"]
    local skip_top = equates["inv_high_score_cache_top"]
    for address = low, top do
        if skip_low == nil or address < skip_low or address > skip_top then
            mem:write_u8(address, M.invaders_junk_byte(address, low))
        end
    end
end

function M.enable_invaders_test_mode(equates, mem)
    mem = mem or M.program_space()
    local signature = M.required_equate(equates, "inv_test_signature")
    mem:write_u8(signature, M.required_equate(equates, "inv_test_signature0"))
    mem:write_u8(signature + 1, M.required_equate(equates, "inv_test_signature1"))
    mem:write_u8(signature + 2, M.required_equate(equates, "inv_test_signature2"))
end

function M.disable_invaders_test_mode(equates, mem)
    mem = mem or M.program_space()
    local signature = M.required_equate(equates, "inv_test_signature")
    mem:write_u8(signature, 0)
    mem:write_u8(signature + 1, 0)
    mem:write_u8(signature + 2, 0)
end

function M.fail(message)
    print("VT100_INVADERS_TEST_FAIL: " .. tostring(message))
    manager.machine:exit()
end

function M.pass()
    print("VT100_INVADERS_TEST_PASS")
    manager.machine:exit()
end

function M.run(callback)
    local ok, err = pcall(callback)
    if ok then
        M.pass()
    else
        M.fail(err)
    end
end

return M
