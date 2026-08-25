get_filename_component(VT100_SOURCE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
get_filename_component(VT100_BINARY_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/.." ABSOLUTE)

add_test(NAME vt100.bin
    COMMAND
        "${CMAKE_COMMAND}"
            "-DACTUAL_FILE=${VT100_BINARY_DIRECTORY}/vt100.bin"
            "-DEXPECTED_FILE=${CMAKE_SOURCE_DIR}/bin/vt100.bin"
            -P "${VT100_SOURCE_DIRECTORY}/compare_bin.cmake"
)
set_tests_properties(vt100.bin PROPERTIES LABELS vt100)

foreach(VT100_SPLIT_ROM_IMAGE IN LISTS VT100_SPLIT_ROM_IMAGES)
    add_test(NAME ${VT100_SPLIT_ROM_IMAGE}
        COMMAND
            "${CMAKE_COMMAND}"
                "-DACTUAL_FILE=${VT100_BINARY_DIRECTORY}/${VT100_SPLIT_ROM_IMAGE}"
                "-DEXPECTED_FILE=${CMAKE_SOURCE_DIR}/bin/${VT100_SPLIT_ROM_IMAGE}"
                -P "${VT100_SOURCE_DIRECTORY}/compare_bin.cmake"
    )
    set_tests_properties(${VT100_SPLIT_ROM_IMAGE} PROPERTIES LABELS vt100)
endforeach()

add_test(NAME invaders-rom-layout
    COMMAND
        "${CMAKE_COMMAND}"
            "-DVT100_BINARY_DIRECTORY=${VT100_BINARY_DIRECTORY}"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/verify-invaders-rom-layout.cmake"
)
set_tests_properties(invaders-rom-layout
    PROPERTIES
        LABELS invaders
        SKIP_REGULAR_EXPRESSION "^SKIP:"
)

if(MAME_COMMAND)
    get_filename_component(MAME_WORKING_DIRECTORY "${MAME_COMMAND}" DIRECTORY)
    add_test(NAME mame-invaders-rom-layout
        COMMAND
            "${CMAKE_COMMAND}"
                "-DMAME_COMMAND=${MAME_COMMAND}"
                "-DMAME_WORKING_DIRECTORY=${MAME_WORKING_DIRECTORY}"
                "-DMAME_MACHINE=vt102"
                "-DVT100_BINARY_DIRECTORY=${VT100_BINARY_DIRECTORY}"
                "-DVT100_PROJECT_SOURCE_DIRECTORY=${CMAKE_SOURCE_DIR}"
                "-DMAME_LUA_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/mame-invaders-rom-layout.lua"
                -P "${CMAKE_CURRENT_SOURCE_DIR}/run-mame-test.cmake"
    )
    set_tests_properties(mame-invaders-rom-layout
        PROPERTIES
            LABELS "invaders;mame"
            SKIP_REGULAR_EXPRESSION "^SKIP:"
            TIMEOUT 15
    )
endif()
