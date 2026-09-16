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

    function(add_mame_invaders_test TEST_NAME LUA_SCRIPT)
        set(MAME_SECONDS_TO_RUN 5)
        if(ARGC GREATER 3)
            set(MAME_SECONDS_TO_RUN "${ARGV3}")
        endif()
        set(MAME_TEST_DRIVER_ARGUMENTS
            "-DMAME_COMMAND=${MAME_COMMAND}"
            "-DMAME_WORKING_DIRECTORY=${MAME_WORKING_DIRECTORY}"
            "-DMAME_MACHINE=vt102"
            "-DMAME_TEST_NAME=${TEST_NAME}"
            "-DMAME_SECONDS_TO_RUN=${MAME_SECONDS_TO_RUN}"
            "-DVT100_BINARY_DIRECTORY=${VT100_BINARY_DIRECTORY}"
            "-DVT100_PROJECT_SOURCE_DIRECTORY=${CMAKE_SOURCE_DIR}"
            "-DMAME_LUA_SCRIPT=${CMAKE_CURRENT_SOURCE_DIR}/${LUA_SCRIPT}"
        )
        if(ARGC GREATER 2)
            list(APPEND MAME_TEST_DRIVER_ARGUMENTS "-DMAME_TEST_PLUGIN=${ARGV2}")
        endif()
        if(TEST_NAME STREQUAL "mame-invaders-high-score")
            list(APPEND MAME_TEST_DRIVER_ARGUMENTS "-DMAME_EXPECT_NVR_WORDS=51=7B00,61=6100,62=0000")
        endif()
        if(TEST_NAME STREQUAL "mame-invaders-game-over")
            list(APPEND MAME_TEST_DRIVER_ARGUMENTS "-DMAME_EXPECT_NVR_WORDS=51=7B00,52=0000,61=2100,62=0000")
        endif()
        if(TEST_NAME STREQUAL "mame-invaders-high-score-load" OR
                TEST_NAME STREQUAL "mame-invaders-demo-state")
            list(APPEND MAME_TEST_DRIVER_ARGUMENTS "-DMAME_SEED_NVR_WORDS=51=007B,52=002D,61=08A1,62=08C0")
            list(APPEND MAME_TEST_DRIVER_ARGUMENTS "-DMAME_EXPECT_NVR_UNCHANGED=TRUE")
        endif()

        add_test(NAME ${TEST_NAME}
            COMMAND
                "${CMAKE_COMMAND}"
                    ${MAME_TEST_DRIVER_ARGUMENTS}
                    -P "${CMAKE_CURRENT_SOURCE_DIR}/run-mame-test.cmake"
        )
        set_tests_properties(${TEST_NAME}
            PROPERTIES
                LABELS "invaders;mame"
                SKIP_REGULAR_EXPRESSION "^SKIP:"
                TIMEOUT 15
        )
    endfunction()

    add_mame_invaders_test(mame-invaders-rom-layout mame-invaders-rom-layout.lua)
    add_mame_invaders_test(mame-invaders-state-layout mame-invaders-state-layout.lua)
    add_mame_invaders_test(mame-invaders-entry vt100invadersentry/init.lua vt100invadersentry)
    add_mame_invaders_test(mame-invaders-frame vt100invadersframe/init.lua vt100invadersframe)
    add_mame_invaders_test(mame-invaders-render vt100invadersrender/init.lua vt100invadersrender)
    add_mame_invaders_test(mame-invaders-static-screen vt100invadersstatic/init.lua vt100invadersstatic)
    add_mame_invaders_test(mame-invaders-input vt100invadersinput/init.lua vt100invadersinput)
    add_mame_invaders_test(mame-invaders-laser vt100invaderslaser/init.lua vt100invaderslaser)
    add_mame_invaders_test(mame-invaders-aliens vt100invadersaliens/init.lua vt100invadersaliens 10)
    add_mame_invaders_test(mame-invaders-bunkers vt100invadersbunkers/init.lua vt100invadersbunkers 30)
    add_mame_invaders_test(mame-invaders-scoring vt100invadersscoring/init.lua vt100invadersscoring 10)
    add_mame_invaders_test(mame-invaders-high-score vt100invadershighscore/init.lua vt100invadershighscore 15)
    add_mame_invaders_test(mame-invaders-high-score-load vt100invadershighscoreload/init.lua vt100invadershighscoreload 10)
    add_mame_invaders_test(mame-invaders-demo-state vt100invadersdemo/init.lua vt100invadersdemo 30)
    add_mame_invaders_test(mame-invaders-enemy-fire vt100invadersenemyfire/init.lua vt100invadersenemyfire 10)
    add_mame_invaders_test(mame-invaders-game-over vt100invadersgameover/init.lua vt100invadersgameover 30)
    add_mame_invaders_test(mame-invaders-sound vt100invaderssound/init.lua vt100invaderssound 10)
    add_mame_invaders_test(mame-invaders-full-smoke vt100invadersfullsmoke/init.lua vt100invadersfullsmoke 45)
endif()
