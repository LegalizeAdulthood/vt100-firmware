find_program(ASM8080_EXECUTABLE NAMES asm8080)
if(NOT ASM8080_EXECUTABLE)
    message(FATAL_ERROR "asm8080 was not found. Configure with the vcpkg manifest so the asm8080 host tool is installed.")
endif()

add_custom_command(
    OUTPUT
        vt100.bin
        vt100.hex
        vt100.lst
        vt100.sym
    BYPRODUCTS
        src/vt100.asm
    COMMAND
        "${CMAKE_COMMAND}" -E make_directory src
    COMMAND
        "${CMAKE_COMMAND}" -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/vt100.asm" src/vt100.asm
    COMMAND
        "${ASM8080_EXECUTABLE}" -lvt100 -ovt100 src/vt100.asm
    COMMAND
        "${CMAKE_COMMAND}" -DLST_FILE=vt100.lst -DOUTPUT_FILE=vt100.sym -P "${CMAKE_CURRENT_SOURCE_DIR}/lst_to_sym.cmake"
    COMMAND
        "$<TARGET_FILE:write-checksum>" "${CMAKE_CURRENT_BINARY_DIR}/vt100.sym" "${CMAKE_CURRENT_BINARY_DIR}/vt100.bin"
    DEPENDS
        vt100.asm
        write-checksum
        lst_to_sym.cmake
    WORKING_DIRECTORY
        "${CMAKE_CURRENT_BINARY_DIR}"
    COMMENT
        "Assembling and checksumming vt100.asm"
    VERBATIM
)

add_custom_command(
    OUTPUT
        vt100.equ
    COMMAND
        "${CMAKE_COMMAND}" -DLST_FILE=vt100.lst -DOUTPUT_FILE=vt100.equ -P "${CMAKE_CURRENT_SOURCE_DIR}/lst_to_equ.cmake"
    DEPENDS
        vt100.lst
        lst_to_equ.cmake
    WORKING_DIRECTORY
        "${CMAKE_CURRENT_BINARY_DIR}"
    COMMENT
        "Generating vt100.equ"
    VERBATIM
)

set(VT100_SPLIT_ROM_IMAGES
    23-061E2.bin
    23-032E2.bin
    23-033E2.bin
    23-034E2.bin
)

add_custom_command(
    OUTPUT
        ${VT100_SPLIT_ROM_IMAGES}
    COMMAND
        "${CMAKE_COMMAND}"
            "-DINPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/vt100.bin"
            "-DOUTPUT_DIRECTORY=${CMAKE_CURRENT_BINARY_DIR}"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/split_vt100_roms.cmake"
    DEPENDS
        vt100.bin
        split_vt100_roms.cmake
    WORKING_DIRECTORY
        "${CMAKE_CURRENT_BINARY_DIR}"
    COMMENT
        "Splitting vt100.bin into ROM images"
    VERBATIM
)

add_custom_target(vt100-rom ALL
    DEPENDS
        vt100.bin
        ${VT100_SPLIT_ROM_IMAGES}
        vt100.sym
        vt100.equ
    SOURCES
        vt100.asm
        compare_bin.cmake
        split_vt100_roms.cmake
        lst_to_equ.cmake
        lst_to_sym.cmake
)
target_folder(vt100-rom "Firmware")

if(BUILD_TESTING)
    add_test(NAME vt100.bin
        COMMAND
            "${CMAKE_COMMAND}"
                "-DACTUAL_FILE=${CMAKE_CURRENT_BINARY_DIR}/vt100.bin"
                "-DEXPECTED_FILE=${CMAKE_SOURCE_DIR}/bin/vt100.bin"
                -P "${CMAKE_CURRENT_SOURCE_DIR}/compare_bin.cmake"
    )

    foreach(VT100_SPLIT_ROM_IMAGE IN LISTS VT100_SPLIT_ROM_IMAGES)
        add_test(NAME ${VT100_SPLIT_ROM_IMAGE}
            COMMAND
                "${CMAKE_COMMAND}"
                    "-DACTUAL_FILE=${CMAKE_CURRENT_BINARY_DIR}/${VT100_SPLIT_ROM_IMAGE}"
                    "-DEXPECTED_FILE=${CMAKE_SOURCE_DIR}/bin/${VT100_SPLIT_ROM_IMAGE}"
                    -P "${CMAKE_CURRENT_SOURCE_DIR}/compare_bin.cmake"
        )
    endforeach()
endif()
