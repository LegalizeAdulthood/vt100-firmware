#include <array>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <sstream>
#include <string>
#include <vector>

namespace {

constexpr std::size_t ROM_SIZE = 8192;
constexpr std::size_t BLOCK_SIZE = 2048;

struct ChecksumByte {
    std::size_t offset;
    const char *rom_name;
};

constexpr std::array<ChecksumByte, 4> CHECKSUM_BYTES = {{
    {0x04ce, "23-061E2.bin"},
    {0x0dce, "23-032E2.bin"},
    {0x14fb, "23-033E2.bin"},
    {0x1ba6, "23-034E2.bin"},
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
                      << hex_offset(checksum_byte.offset) << "\n";
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
    if (argc != 2) {
        std::cerr << "usage: write-checksum <path-to-vt100.bin>\n";
        return 2;
    }

    const std::string path = argv[1];
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        std::cerr << "failed to open input file: " << path << "\n";
        return 1;
    }

    std::vector<std::uint8_t> rom(
        (std::istreambuf_iterator<char>(input)),
        std::istreambuf_iterator<char>());

    if (rom.size() != ROM_SIZE) {
        std::cerr << "expected " << ROM_SIZE << " bytes in " << path
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

    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    if (!output) {
        std::cerr << "failed to open output file: " << path << "\n";
        return 1;
    }

    output.write(
        reinterpret_cast<const char *>(rom.data()),
        static_cast<std::streamsize>(rom.size()));
    if (!output) {
        std::cerr << "failed to write output file: " << path << "\n";
        return 1;
    }

    return 0;
}
