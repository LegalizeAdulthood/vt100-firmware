get_filename_component(VT100_SOURCE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
get_filename_component(VT100_BINARY_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/.." ABSOLUTE)

add_test(NAME vt100.bin
    COMMAND
        "${CMAKE_COMMAND}"
            "-DACTUAL_FILE=${VT100_BINARY_DIRECTORY}/vt100.bin"
            "-DEXPECTED_FILE=${CMAKE_SOURCE_DIR}/bin/vt100.bin"
            -P "${VT100_SOURCE_DIRECTORY}/compare_bin.cmake"
)

foreach(VT100_SPLIT_ROM_IMAGE IN LISTS VT100_SPLIT_ROM_IMAGES)
    add_test(NAME ${VT100_SPLIT_ROM_IMAGE}
        COMMAND
            "${CMAKE_COMMAND}"
                "-DACTUAL_FILE=${VT100_BINARY_DIRECTORY}/${VT100_SPLIT_ROM_IMAGE}"
                "-DEXPECTED_FILE=${CMAKE_SOURCE_DIR}/bin/${VT100_SPLIT_ROM_IMAGE}"
                -P "${VT100_SOURCE_DIRECTORY}/compare_bin.cmake"
    )
endforeach()
