find_program(ASM8080_EXECUTABLE NAMES asm8080)
if(NOT ASM8080_EXECUTABLE)
    message(FATAL_ERROR "asm8080 was not found. Configure with the vcpkg manifest so the asm8080 host tool is installed.")
endif()

add_custom_command(
    OUTPUT
        vt100.bin
        vt100.hex
        vt100.lst
    BYPRODUCTS
        src/vt100.asm
    COMMAND
        "${CMAKE_COMMAND}" -E make_directory src
    COMMAND
        "${CMAKE_COMMAND}" -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/vt100.asm" src/vt100.asm
    COMMAND
        "${ASM8080_EXECUTABLE}" -lvt100 -ovt100 src/vt100.asm
    DEPENDS
        vt100.asm
    WORKING_DIRECTORY
        "${CMAKE_CURRENT_BINARY_DIR}"
    COMMENT
        "Assembling vt100.asm"
    VERBATIM
)

add_custom_target(vt100-rom ALL
    DEPENDS
        vt100.bin
    SOURCES
        vt100.asm
)
target_folder(vt100-rom "Firmware")
