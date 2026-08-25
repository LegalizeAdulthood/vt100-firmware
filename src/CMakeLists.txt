find_program(ASM8080_EXECUTABLE NAMES asm8080)
if(NOT ASM8080_EXECUTABLE)
    message(FATAL_ERROR "asm8080 was not found. Configure with the vcpkg manifest so the asm8080 host tool is installed.")
endif()

set(MAME_COMMAND "" CACHE FILEPATH "Path to the MAME executable")
if(NOT MAME_COMMAND)
    unset(MAME_COMMAND CACHE)
    find_program(MAME_COMMAND NAMES mame mame.exe DOC "Path to the MAME executable")
    if(NOT MAME_COMMAND)
        set(MAME_COMMAND "" CACHE FILEPATH "Path to the MAME executable" FORCE)
    endif()
endif()

add_custom_command(
    OUTPUT
        vt100.bin
        vt100.hex
        vt100.lst
        vt100.sym
    COMMAND
        "${ASM8080_EXECUTABLE}" "-I${CMAKE_CURRENT_SOURCE_DIR}" -lvt100 -ovt100 "${CMAKE_CURRENT_SOURCE_DIR}/vt100.asm"
    COMMAND
        "${CMAKE_COMMAND}" -DLST_FILE=vt100.lst -DOUTPUT_FILE=vt100.sym -P "${CMAKE_CURRENT_SOURCE_DIR}/lst_to_sym.cmake"
    COMMAND
        "$<TARGET_FILE:write-checksum>" "${CMAKE_CURRENT_BINARY_DIR}/vt100.sym" "${CMAKE_CURRENT_BINARY_DIR}/vt100.bin"
    DEPENDS
        base.asm
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

add_custom_command(
    OUTPUT
        invaders.bin
        invaders.hex
        invaders.lst
        invaders.sym
    COMMAND
        "${ASM8080_EXECUTABLE}" "-I${CMAKE_CURRENT_SOURCE_DIR}" -linvaders -oinvaders "${CMAKE_CURRENT_SOURCE_DIR}/invaders.asm"
    COMMAND
        "${CMAKE_COMMAND}" -DLST_FILE=invaders.lst -DOUTPUT_FILE=invaders.sym -P "${CMAKE_CURRENT_SOURCE_DIR}/lst_to_sym.cmake"
    COMMAND
        "$<TARGET_FILE:write-checksum>" "${CMAKE_CURRENT_BINARY_DIR}/invaders.sym" "${CMAKE_CURRENT_BINARY_DIR}/invaders.bin"
    DEPENDS
        base.asm
        invaders.asm
        invaders-abi.asm
        write-checksum
        lst_to_sym.cmake
    WORKING_DIRECTORY
        "${CMAKE_CURRENT_BINARY_DIR}"
    COMMENT
        "Assembling and checksumming invaders.asm"
    VERBATIM
)

add_custom_command(
    OUTPUT
        invaders-avo.bin
        invaders-avo.hex
        invaders-avo.lst
        invaders-avo.sym
    COMMAND
        "${ASM8080_EXECUTABLE}" "-I${CMAKE_CURRENT_SOURCE_DIR}" "-I${CMAKE_CURRENT_BINARY_DIR}" -linvaders-avo -oinvaders-avo "${CMAKE_CURRENT_SOURCE_DIR}/invaders-avo.asm"
    COMMAND
        "${CMAKE_COMMAND}" -DLST_FILE=invaders-avo.lst -DOUTPUT_FILE=invaders-avo.sym -P "${CMAKE_CURRENT_SOURCE_DIR}/lst_to_sym.cmake"
    DEPENDS
        invaders-base.inc
        invaders-avo.asm
        lst_to_sym.cmake
    WORKING_DIRECTORY
        "${CMAKE_CURRENT_BINARY_DIR}"
    COMMENT
        "Assembling invaders-avo.asm"
    VERBATIM
)

add_custom_command(
    OUTPUT
        invaders-base.inc
    COMMAND
        "${CMAKE_COMMAND}" -DLST_FILE=invaders.lst -DOUTPUT_FILE=invaders-base.inc -P "${CMAKE_CURRENT_SOURCE_DIR}/lst_to_asm_equ.cmake"
    DEPENDS
        invaders.lst
        lst_to_asm_equ.cmake
    WORKING_DIRECTORY
        "${CMAKE_CURRENT_BINARY_DIR}"
    COMMENT
        "Generating invaders base assembly include"
    VERBATIM
)

set(VT100_SPLIT_ROM_IMAGES
    23-061E2.bin
    23-032E2.bin
    23-033E2.bin
    23-034E2.bin
)

set(INVADERS_SPLIT_ROM_IMAGES
    invaders-1.bin
    invaders-2.bin
    invaders-3.bin
    invaders-4.bin
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

add_custom_command(
    OUTPUT
        ${INVADERS_SPLIT_ROM_IMAGES}
    COMMAND
        "${CMAKE_COMMAND}"
            "-DINPUT_FILE=${CMAKE_CURRENT_BINARY_DIR}/invaders.bin"
            "-DOUTPUT_DIRECTORY=${CMAKE_CURRENT_BINARY_DIR}"
            "-DOUTPUT_PREFIX=invaders"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/split_vt100_roms.cmake"
    DEPENDS
        invaders.bin
        split_vt100_roms.cmake
    WORKING_DIRECTORY
        "${CMAKE_CURRENT_BINARY_DIR}"
    COMMENT
        "Splitting invaders.bin into ROM images"
    VERBATIM
)

add_custom_target(vt100-rom ALL
    DEPENDS
        vt100.bin
        ${VT100_SPLIT_ROM_IMAGES}
        vt100.sym
        vt100.equ
    SOURCES
        base.asm
        vt100.asm
        compare_bin.cmake
        split_vt100_roms.cmake
        lst_to_equ.cmake
        lst_to_sym.cmake
)
target_folder(vt100-rom "Firmware")

if(MAME_COMMAND)
    get_filename_component(MAME_ROOT "${MAME_COMMAND}" DIRECTORY)
    set(MAME_ROM_DIRECTORY "${MAME_ROOT}/roms/vt100")

    add_custom_target(mame
        COMMAND
            "${CMAKE_COMMAND}" -E make_directory "${MAME_ROM_DIRECTORY}"
        COMMAND
            "${CMAKE_COMMAND}" -E copy_if_different
                "${CMAKE_CURRENT_BINARY_DIR}/23-061E2.bin"
                "${MAME_ROM_DIRECTORY}/23-061e2-00.e56"
        COMMAND
            "${CMAKE_COMMAND}" -E copy_if_different
                "${CMAKE_CURRENT_BINARY_DIR}/23-032E2.bin"
                "${MAME_ROM_DIRECTORY}/23-032e2-00.e52"
        COMMAND
            "${CMAKE_COMMAND}" -E copy_if_different
                "${CMAKE_CURRENT_BINARY_DIR}/23-033E2.bin"
                "${MAME_ROM_DIRECTORY}/23-033e2-00.e45"
        COMMAND
            "${CMAKE_COMMAND}" -E copy_if_different
                "${CMAKE_CURRENT_BINARY_DIR}/23-034E2.bin"
                "${MAME_ROM_DIRECTORY}/23-034e2-00.e40"
        COMMAND
            "${CMAKE_COMMAND}" -E copy_if_different
                "${CMAKE_SOURCE_DIR}/bin/23-018E2.bin"
                "${MAME_ROM_DIRECTORY}/23-018e2-00.e4"
        DEPENDS
            ${VT100_SPLIT_ROM_IMAGES}
            "${CMAKE_SOURCE_DIR}/bin/23-018E2.bin"
        COMMENT
            "Copying VT100 ROM images to ${MAME_ROM_DIRECTORY}"
        VERBATIM
    )
    target_folder(mame "Firmware")

    add_custom_target(mame-invaders
        COMMAND
            "${CMAKE_COMMAND}" -E make_directory "${MAME_ROM_DIRECTORY}"
        COMMAND
            "${CMAKE_COMMAND}" -E copy_if_different
                "${CMAKE_CURRENT_BINARY_DIR}/invaders-1.bin"
                "${MAME_ROM_DIRECTORY}/23-061e2-00.e56"
        COMMAND
            "${CMAKE_COMMAND}" -E copy_if_different
                "${CMAKE_CURRENT_BINARY_DIR}/invaders-2.bin"
                "${MAME_ROM_DIRECTORY}/23-032e2-00.e52"
        COMMAND
            "${CMAKE_COMMAND}" -E copy_if_different
                "${CMAKE_CURRENT_BINARY_DIR}/invaders-3.bin"
                "${MAME_ROM_DIRECTORY}/23-033e2-00.e45"
        COMMAND
            "${CMAKE_COMMAND}" -E copy_if_different
                "${CMAKE_CURRENT_BINARY_DIR}/invaders-4.bin"
                "${MAME_ROM_DIRECTORY}/23-034e2-00.e40"
        COMMAND
            "${CMAKE_COMMAND}" -E copy_if_different
                "${CMAKE_CURRENT_BINARY_DIR}/invaders-avo.bin"
                "${MAME_ROM_DIRECTORY}/23-225e4-00.e69"
        COMMAND
            "${CMAKE_COMMAND}" -E copy_if_different
                "${CMAKE_SOURCE_DIR}/bin/23-018E2.bin"
                "${MAME_ROM_DIRECTORY}/23-018e2-00.e4"
        DEPENDS
            ${INVADERS_SPLIT_ROM_IMAGES}
            invaders-avo.bin
            "${CMAKE_SOURCE_DIR}/bin/23-018E2.bin"
        COMMENT
            "Copying Invaders ROM images to ${MAME_ROM_DIRECTORY}"
        VERBATIM
    )
    target_folder(mame-invaders "Firmware")
endif()

add_custom_target(invaders-rom
    DEPENDS
        invaders.bin
        invaders.sym
        invaders-base.inc
        ${INVADERS_SPLIT_ROM_IMAGES}
        invaders-avo.bin
        invaders-avo.sym
    SOURCES
        base.asm
        invaders.asm
        invaders-avo.asm
        invaders-abi.asm
        lst_to_asm_equ.cmake
        lst_to_sym.cmake
)
target_folder(invaders-rom "Firmware")

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
