#include <array>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <sstream>
#include <exception>
#include <string>
#include <vector>

namespace {

constexpr std::size_t ROM_SIZE = 8192;
constexpr std::size_t BLOCK_SIZE = 2048;

struct ChecksumByte {
    std::size_t offset;
    const char *symbol_name;
    const char *rom_name;
    bool found;
};

std::array<ChecksumByte, 4> CHECKSUM_BYTES = {{
    {0, "rom1_checksum", "23-061E2.bin", false},
    {0, "rom2_checksum", "23-032E2.bin", false},
    {0, "rom3_checksum", "23-033E2.bin", false},
    {0, "rom4_checksum", "23-034E2.bin", false},
}};

std::uint8_t rotate_left(std::uint8_t value)
{
    return static_cast<std::uint8_t>((value << 1) | (value >> 7));
}

std::uint8_t checksum_block(
    const std::vector<std::uint8_t> &rom,
    std::size_t block_index)
{
    auto checksum = static_cast<std::uint8_t>(block_index + 1);
    const std::size_t first = block_index * BLOCK_SIZE;
    const std::size_t last = first + BLOCK_SIZE;

    for (std::size_t offset = first; offset < last; ++offset) {
        checksum = rotate_left(checksum);
        checksum = static_cast<std::uint8_t>(checksum ^ rom[offset]);
    }

    return checksum;
}

std::string hex_byte(std::uint8_t value)
{
    std::ostringstream stream;
    stream << "0x" << std::uppercase << std::hex << std::setw(2)
           << std::setfill('0') << static_cast<unsigned int>(value);
    return stream.str();
}

std::string hex_offset(std::size_t value)
{
    std::ostringstream stream;
    stream << "0x" << std::uppercase << std::hex << std::setw(4)
           << std::setfill('0') << value;
    return stream.str();
}

bool parse_offset(const std::string &text, std::size_t &offset)
{
    std::size_t parsed_chars = 0;
    try {
        const unsigned long value = std::stoul(text, &parsed_chars, 16);
        if (parsed_chars != text.size() || value >= ROM_SIZE) {
            return false;
        }
        offset = static_cast<std::size_t>(value);
        return true;
    } catch (const std::exception &) {
        return false;
    }
}

bool load_checksum_symbols(
    const std::string &path,
    std::array<ChecksumByte, 4> &checksum_bytes)
{
    std::ifstream input(path);
    if (!input) {
        std::cerr << "failed to open symbol file: " << path << "\n";
        return false;
    }

    std::string line;
    unsigned int line_number = 0;
    while (std::getline(input, line)) {
        ++line_number;

        std::istringstream stream(line);
        std::string address_text;
        std::string name;
        if (!(stream >> address_text >> name)) {
            continue;
        }

        for (auto &checksum_byte : checksum_bytes) {
            if (name != checksum_byte.symbol_name) {
                continue;
            }
            if (checksum_byte.found) {
                std::cerr << "duplicate symbol " << name << " in " << path
                          << " at line " << line_number << "\n";
                return false;
            }
            if (!parse_offset(address_text, checksum_byte.offset)) {
                std::cerr << "invalid address for symbol " << name << " in "
                          << path << " at line " << line_number << ": "
                          << address_text << "\n";
                return false;
            }
            checksum_byte.found = true;
        }
    }

    for (const auto &checksum_byte : checksum_bytes) {
        if (!checksum_byte.found) {
            std::cerr << "missing required symbol "
                      << checksum_byte.symbol_name << " in " << path << "\n";
            return false;
        }
    }

    return true;
}

bool patch_checksum_byte(
    std::vector<std::uint8_t> &rom,
    std::size_t block_index,
    const ChecksumByte &checksum_byte)
{
    if (checksum_byte.offset / BLOCK_SIZE != block_index) {
        std::cerr << "Checksum byte " << hex_offset(checksum_byte.offset)
                  << " is not in ROM block " << (block_index + 1) << "\n";
        return false;
    }

    for (unsigned int value = 0; value <= 0xff; ++value) {
        rom[checksum_byte.offset] = static_cast<std::uint8_t>(value);
        if (checksum_block(rom, block_index) == 0) {
            std::cout << "ROM " << (block_index + 1) << " ("
                      << checksum_byte.rom_name << "): wrote "
                      << hex_byte(rom[checksum_byte.offset]) << " at "
                      << hex_offset(checksum_byte.offset) << " ("
                      << checksum_byte.symbol_name << ")\n";
            return true;
        }
    }

    std::cerr << "No checksum byte found for ROM block "
              << (block_index + 1) << "\n";
    return false;
}

} // namespace

int main(int argc, char *argv[])
{
    if (argc != 3) {
        std::cerr << "usage: write-checksum <path-to-vt100.sym> "
                     "<path-to-vt100.bin>\n";
        return 2;
    }

    const std::string sym_path = argv[1];
    const std::string bin_path = argv[2];

    if (!load_checksum_symbols(sym_path, CHECKSUM_BYTES)) {
        return 1;
    }

    std::ifstream input(bin_path, std::ios::binary);
    if (!input) {
        std::cerr << "failed to open input file: " << bin_path << "\n";
        return 1;
    }

    std::vector<std::uint8_t> rom(
        (std::istreambuf_iterator<char>(input)),
        std::istreambuf_iterator<char>());

    if (rom.size() != ROM_SIZE) {
        std::cerr << "expected " << ROM_SIZE << " bytes in " << bin_path
                  << "; got " << rom.size() << "\n";
        return 1;
    }

    for (std::size_t block_index = 0;
         block_index < CHECKSUM_BYTES.size();
         ++block_index) {
        if (!patch_checksum_byte(rom, block_index, CHECKSUM_BYTES[block_index])) {
            return 1;
        }
    }

    std::ofstream output(bin_path, std::ios::binary | std::ios::trunc);
    if (!output) {
        std::cerr << "failed to open output file: " << bin_path << "\n";
        return 1;
    }

    output.write(
        reinterpret_cast<const char *>(rom.data()),
        static_cast<std::streamsize>(rom.size()));
    if (!output) {
        std::cerr << "failed to write output file: " << bin_path << "\n";
        return 1;
    }

    return 0;
}
