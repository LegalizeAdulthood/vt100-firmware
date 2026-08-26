foreach(REQUIRED_VARIABLE
        MAME_COMMAND
        MAME_WORKING_DIRECTORY
        MAME_LUA_SCRIPT
        VT100_BINARY_DIRECTORY
        VT100_PROJECT_SOURCE_DIRECTORY)
    if(NOT DEFINED ${REQUIRED_VARIABLE})
        message(FATAL_ERROR "${REQUIRED_VARIABLE} is required")
    endif()
endforeach()

if(NOT DEFINED MAME_MACHINE)
    set(MAME_MACHINE vt102)
endif()
if(NOT DEFINED MAME_SECONDS_TO_RUN)
    set(MAME_SECONDS_TO_RUN 5)
endif()

set(MAME_TEST_ROMPATH "${VT100_BINARY_DIRECTORY}/mame-roms")
set(MAME_TEST_OUTPUT_DIRECTORY "${VT100_BINARY_DIRECTORY}/mame-test")
set(MAME_TEST_MACHINE_ROM_DIRECTORY "${MAME_TEST_ROMPATH}/${MAME_MACHINE}")

set(INVADERS_BASE_ROM "${VT100_BINARY_DIRECTORY}/invaders.bin")
set(INVADERS_AVO_ROM "${VT100_BINARY_DIRECTORY}/invaders-avo.bin")
set(INVADERS_AVO_EQUATES "${VT100_BINARY_DIRECTORY}/invaders-avo.equ")
set(VT100_CHARACTER_ROM "${VT100_PROJECT_SOURCE_DIRECTORY}/bin/23-018E2.bin")

foreach(REQUIRED_FILE
        "${MAME_COMMAND}"
        "${MAME_LUA_SCRIPT}"
        "${INVADERS_BASE_ROM}"
        "${INVADERS_AVO_ROM}"
        "${INVADERS_AVO_EQUATES}"
        "${VT100_CHARACTER_ROM}")
    if(NOT EXISTS "${REQUIRED_FILE}")
        message("SKIP: MAME test artifacts are not ready; missing ${REQUIRED_FILE}")
        return()
    endif()
endforeach()

if(NOT MAME_MACHINE STREQUAL "vt102")
    message(FATAL_ERROR "Unsupported MAME_MACHINE for Invaders tests: ${MAME_MACHINE}")
endif()

if(DEFINED MAME_TEST_PLUGIN AND NOT MAME_TEST_PLUGIN STREQUAL "")
    get_filename_component(MAME_TEST_PLUGIN_DIRECTORY "${MAME_LUA_SCRIPT}" DIRECTORY)
    get_filename_component(MAME_TEST_PLUGIN_PATH "${MAME_TEST_PLUGIN_DIRECTORY}" DIRECTORY)
    set(MAME_PLUGIN_PATH "${MAME_WORKING_DIRECTORY}/plugins\;${MAME_TEST_PLUGIN_PATH}")
    set(MAME_SCRIPT_ARGUMENTS
        -pluginspath "${MAME_PLUGIN_PATH}"
        -plugin "${MAME_TEST_PLUGIN}"
    )
else()
    set(MAME_SCRIPT_ARGUMENTS
        -autoboot_delay 0
        -autoboot_script "${MAME_LUA_SCRIPT}"
    )
endif()

file(MAKE_DIRECTORY
    "${MAME_TEST_MACHINE_ROM_DIRECTORY}"
    "${MAME_TEST_OUTPUT_DIRECTORY}/cfg"
    "${MAME_TEST_OUTPUT_DIRECTORY}/nvram"
    "${MAME_TEST_OUTPUT_DIRECTORY}/inp"
    "${MAME_TEST_OUTPUT_DIRECTORY}/sta"
    "${MAME_TEST_OUTPUT_DIRECTORY}/snap"
)

file(COPY_FILE "${INVADERS_BASE_ROM}" "${MAME_TEST_MACHINE_ROM_DIRECTORY}/23-226e4-00.e71" ONLY_IF_DIFFERENT)
file(COPY_FILE "${INVADERS_AVO_ROM}" "${MAME_TEST_MACHINE_ROM_DIRECTORY}/23-225e4-00.e69" ONLY_IF_DIFFERENT)
file(COPY_FILE "${VT100_CHARACTER_ROM}" "${MAME_TEST_MACHINE_ROM_DIRECTORY}/23-018e2-00.e3" ONLY_IF_DIFFERENT)

execute_process(
    COMMAND
        "${CMAKE_COMMAND}" -E env
            "VT100_INVADERS_BINARY_DIRECTORY=${VT100_BINARY_DIRECTORY}"
            "VT100_INVADERS_SOURCE_DIRECTORY=${VT100_PROJECT_SOURCE_DIRECTORY}"
            "VT100_INVADERS_MAME_MACHINE=${MAME_MACHINE}"
            "${MAME_COMMAND}" "${MAME_MACHINE}"
                -rompath "${MAME_TEST_ROMPATH}"
                -cfg_directory "${MAME_TEST_OUTPUT_DIRECTORY}/cfg"
                -nvram_directory "${MAME_TEST_OUTPUT_DIRECTORY}/nvram"
                -input_directory "${MAME_TEST_OUTPUT_DIRECTORY}/inp"
                -state_directory "${MAME_TEST_OUTPUT_DIRECTORY}/sta"
                -snapshot_directory "${MAME_TEST_OUTPUT_DIRECTORY}/snap"
                ${MAME_SCRIPT_ARGUMENTS}
                -skip_gameinfo
                -nothrottle
                -video none
                -sound none
                -seconds_to_run "${MAME_SECONDS_TO_RUN}"
    WORKING_DIRECTORY
        "${MAME_WORKING_DIRECTORY}"
    RESULT_VARIABLE MAME_RESULT
    OUTPUT_VARIABLE MAME_OUTPUT
    ERROR_VARIABLE MAME_ERROR
)

set(MAME_TEST_OUTPUT "${MAME_OUTPUT}${MAME_ERROR}")
if(NOT MAME_RESULT EQUAL 0)
    message(FATAL_ERROR "MAME exited with ${MAME_RESULT}\n${MAME_TEST_OUTPUT}")
endif()
if(MAME_TEST_OUTPUT MATCHES "VT100_INVADERS_TEST_FAIL")
    message(FATAL_ERROR "MAME Invaders test failed\n${MAME_TEST_OUTPUT}")
endif()
if(NOT MAME_TEST_OUTPUT MATCHES "VT100_INVADERS_TEST_PASS")
    message(FATAL_ERROR "MAME Invaders test did not report success\n${MAME_TEST_OUTPUT}")
endif()

message(STATUS "MAME Invaders test passed: ${MAME_LUA_SCRIPT}")
