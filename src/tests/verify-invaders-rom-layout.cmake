if(NOT DEFINED VT100_BINARY_DIRECTORY)
    message(FATAL_ERROR "VT100_BINARY_DIRECTORY is required")
endif()

set(VT100_BASE_ROM "${VT100_BINARY_DIRECTORY}/vt100.bin")
set(VT100_BASE_SYMBOLS "${VT100_BINARY_DIRECTORY}/vt100.sym")
set(INVADERS_BASE_ROM "${VT100_BINARY_DIRECTORY}/invaders.bin")
set(INVADERS_AVO_ROM "${VT100_BINARY_DIRECTORY}/invaders-avo.bin")
set(INVADERS_BASE_SYMBOLS "${VT100_BINARY_DIRECTORY}/invaders.sym")
set(INVADERS_BASE_EQUATES "${VT100_BINARY_DIRECTORY}/invaders.equ")
set(INVADERS_BASE_INCLUDE "${VT100_BINARY_DIRECTORY}/invaders-base.inc")
set(INVADERS_AVO_SYMBOLS "${VT100_BINARY_DIRECTORY}/invaders-avo.sym")

set(INVADERS_SPLIT_ROM_IMAGES
    invaders-1.bin
    invaders-2.bin
    invaders-3.bin
    invaders-4.bin
)

set(REQUIRED_INVADERS_FILES
    "${VT100_BASE_ROM}"
    "${VT100_BASE_SYMBOLS}"
    "${INVADERS_BASE_ROM}"
    "${INVADERS_AVO_ROM}"
    "${INVADERS_BASE_SYMBOLS}"
    "${INVADERS_BASE_EQUATES}"
    "${INVADERS_BASE_INCLUDE}"
    "${INVADERS_AVO_SYMBOLS}"
)
foreach(INVADERS_SPLIT_ROM_IMAGE IN LISTS INVADERS_SPLIT_ROM_IMAGES)
    list(APPEND REQUIRED_INVADERS_FILES "${VT100_BINARY_DIRECTORY}/${INVADERS_SPLIT_ROM_IMAGE}")
endforeach()

foreach(REQUIRED_INVADERS_FILE IN LISTS REQUIRED_INVADERS_FILES)
    if(NOT EXISTS "${REQUIRED_INVADERS_FILE}")
        message("SKIP: Invaders ROM artifacts are not built; missing ${REQUIRED_INVADERS_FILE}")
        return()
    endif()
endforeach()

function(assert_file_size FILE_NAME EXPECTED_SIZE)
    file(SIZE "${FILE_NAME}" ACTUAL_SIZE)
    if(NOT ACTUAL_SIZE EQUAL EXPECTED_SIZE)
        message(FATAL_ERROR "Expected ${FILE_NAME} to be ${EXPECTED_SIZE} bytes; got ${ACTUAL_SIZE}")
    endif()
endfunction()

function(read_symbol SYMBOL_FILE SYMBOL_NAME OUTPUT_VARIABLE)
    file(STRINGS "${SYMBOL_FILE}" SYMBOL_FILE_LINES)
    set(SYMBOL_ADDRESSES "")
    foreach(SYMBOL_LINE IN LISTS SYMBOL_FILE_LINES)
        if(SYMBOL_LINE MATCHES "^([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])[ \t]+${SYMBOL_NAME}$")
            list(APPEND SYMBOL_ADDRESSES "${CMAKE_MATCH_1}")
        endif()
    endforeach()
    list(LENGTH SYMBOL_ADDRESSES SYMBOL_ADDRESS_COUNT)
    if(NOT SYMBOL_ADDRESS_COUNT EQUAL 1)
        message(FATAL_ERROR "Expected exactly one ${SYMBOL_NAME} symbol in ${SYMBOL_FILE}; got ${SYMBOL_ADDRESS_COUNT}")
    endif()
    list(GET SYMBOL_ADDRESSES 0 SYMBOL_ADDRESS)
    string(TOUPPER "${SYMBOL_ADDRESS}" SYMBOL_ADDRESS)
    set(${OUTPUT_VARIABLE} "${SYMBOL_ADDRESS}" PARENT_SCOPE)
endfunction()

function(read_equate EQUATE_FILE EQUATE_NAME OUTPUT_VARIABLE)
    file(STRINGS "${EQUATE_FILE}" EQUATE_FILE_LINES)
    set(EQUATE_ADDRESSES "")
    foreach(EQUATE_LINE IN LISTS EQUATE_FILE_LINES)
        if(EQUATE_LINE MATCHES "^([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])[ \t]+${EQUATE_NAME}$")
            list(APPEND EQUATE_ADDRESSES "${CMAKE_MATCH_1}")
        endif()
    endforeach()
    list(LENGTH EQUATE_ADDRESSES EQUATE_ADDRESS_COUNT)
    if(NOT EQUATE_ADDRESS_COUNT EQUAL 1)
        message(FATAL_ERROR "Expected exactly one ${EQUATE_NAME} equate in ${EQUATE_FILE}; got ${EQUATE_ADDRESS_COUNT}")
    endif()
    list(GET EQUATE_ADDRESSES 0 EQUATE_ADDRESS)
    string(TOUPPER "${EQUATE_ADDRESS}" EQUATE_ADDRESS)
    set(${OUTPUT_VARIABLE} "${EQUATE_ADDRESS}" PARENT_SCOPE)
endfunction()

function(assert_address_in_window ADDRESS_NAME ADDRESS_VALUE)
    math(EXPR NUMERIC_ADDRESS "0x${ADDRESS_VALUE}")
    if(NUMERIC_ADDRESS LESS 32768 OR NUMERIC_ADDRESS GREATER 40959)
        message(FATAL_ERROR "${ADDRESS_NAME} is outside the AVO ROM window: 0x${ADDRESS_VALUE}")
    endif()
endfunction()

function(assert_address_equals ADDRESS_NAME ADDRESS_VALUE EXPECTED_ADDRESS)
    if(NOT ADDRESS_VALUE STREQUAL EXPECTED_ADDRESS)
        message(FATAL_ERROR "${ADDRESS_NAME} expected 0x${EXPECTED_ADDRESS}; got 0x${ADDRESS_VALUE}")
    endif()
endfunction()

function(hex_byte HEX_DATA BYTE_OFFSET OUTPUT_VARIABLE)
    math(EXPR HEX_OFFSET "${BYTE_OFFSET} * 2")
    string(SUBSTRING "${HEX_DATA}" ${HEX_OFFSET} 2 BYTE_VALUE)
    string(TOUPPER "${BYTE_VALUE}" BYTE_VALUE)
    set(${OUTPUT_VARIABLE} "${BYTE_VALUE}" PARENT_SCOPE)
endfunction()

function(assert_hex_byte HEX_DATA BYTE_OFFSET EXPECTED_BYTE DESCRIPTION)
    hex_byte("${HEX_DATA}" ${BYTE_OFFSET} ACTUAL_BYTE)
    if(NOT ACTUAL_BYTE STREQUAL EXPECTED_BYTE)
        message(FATAL_ERROR "${DESCRIPTION} expected byte ${EXPECTED_BYTE}; got ${ACTUAL_BYTE}")
    endif()
endfunction()

function(assert_jump_target HEX_DATA BYTE_OFFSET EXPECTED_TARGET DESCRIPTION)
    hex_byte("${HEX_DATA}" ${BYTE_OFFSET} OPCODE)
    math(EXPR TARGET_LOW_OFFSET "${BYTE_OFFSET} + 1")
    math(EXPR TARGET_HIGH_OFFSET "${BYTE_OFFSET} + 2")
    hex_byte("${HEX_DATA}" ${TARGET_LOW_OFFSET} TARGET_LOW)
    hex_byte("${HEX_DATA}" ${TARGET_HIGH_OFFSET} TARGET_HIGH)
    set(ACTUAL_TARGET "${TARGET_HIGH}${TARGET_LOW}")
    if(NOT OPCODE STREQUAL "C3")
        message(FATAL_ERROR "${DESCRIPTION} expected jmp opcode C3; got ${OPCODE}")
    endif()
    if(NOT ACTUAL_TARGET STREQUAL EXPECTED_TARGET)
        message(FATAL_ERROR "${DESCRIPTION} expected target 0x${EXPECTED_TARGET}; got 0x${ACTUAL_TARGET}")
    endif()
endfunction()

function(assert_call_target HEX_DATA BYTE_OFFSET EXPECTED_TARGET DESCRIPTION)
    hex_byte("${HEX_DATA}" ${BYTE_OFFSET} OPCODE)
    math(EXPR TARGET_LOW_OFFSET "${BYTE_OFFSET} + 1")
    math(EXPR TARGET_HIGH_OFFSET "${BYTE_OFFSET} + 2")
    hex_byte("${HEX_DATA}" ${TARGET_LOW_OFFSET} TARGET_LOW)
    hex_byte("${HEX_DATA}" ${TARGET_HIGH_OFFSET} TARGET_HIGH)
    set(ACTUAL_TARGET "${TARGET_HIGH}${TARGET_LOW}")
    if(NOT OPCODE STREQUAL "CD")
        message(FATAL_ERROR "${DESCRIPTION} expected call opcode CD; got ${OPCODE}")
    endif()
    if(NOT ACTUAL_TARGET STREQUAL EXPECTED_TARGET)
        message(FATAL_ERROR "${DESCRIPTION} expected target 0x${EXPECTED_TARGET}; got 0x${ACTUAL_TARGET}")
    endif()
endfunction()

function(append_allowed_range OUTPUT_VARIABLE FIRST_OFFSET BYTE_COUNT)
    set(ALLOWED_OFFSETS ${${OUTPUT_VARIABLE}})
    math(EXPR LAST_OFFSET "${FIRST_OFFSET} + ${BYTE_COUNT} - 1")
    foreach(ALLOWED_OFFSET RANGE ${FIRST_OFFSET} ${LAST_OFFSET})
        list(APPEND ALLOWED_OFFSETS "${ALLOWED_OFFSET}")
    endforeach()
    set(${OUTPUT_VARIABLE} "${ALLOWED_OFFSETS}" PARENT_SCOPE)
endfunction()

function(append_allowed_symbol OUTPUT_VARIABLE SYMBOL_ADDRESS)
    set(ALLOWED_OFFSETS ${${OUTPUT_VARIABLE}})
    math(EXPR SYMBOL_OFFSET "0x${SYMBOL_ADDRESS}")
    list(APPEND ALLOWED_OFFSETS "${SYMBOL_OFFSET}")
    set(${OUTPUT_VARIABLE} "${ALLOWED_OFFSETS}" PARENT_SCOPE)
endfunction()

function(assert_mutable_state_layout EQUATE_FILE RAM_START RAM_TOP DATA_FLOOR)
    set(MUTABLE_STATE_RANGES
        inv_test_signature 3
        inv_test_mode 1
        inv_test_script 1
        inv_test_stop_lo 1
        inv_test_stop_hi 1
        inv_test_result 1
        inv_test_trace_head 1
        inv_test_trace_base 128
        inv_active 1
        inv_last_vframe 1
        inv_frame_lo 1
        inv_frame_hi 1
        inv_left_pressed 1
        inv_right_pressed 1
        inv_fire_pressed 1
        inv_score0 1
        inv_score1 1
        inv_score2 1
        inv_gunners 1
        inv_level 1
        inv_saved_led_state 1
        inv_dirty_queue_base 64
        inv_object_map_base 1440
    )

    set(USED_MUTABLE_OFFSETS "")
    list(LENGTH MUTABLE_STATE_RANGES MUTABLE_STATE_RANGE_COUNT)
    math(EXPR LAST_MUTABLE_STATE_RANGE_INDEX "${MUTABLE_STATE_RANGE_COUNT} - 1")
    foreach(MUTABLE_STATE_RANGE_INDEX RANGE 0 ${LAST_MUTABLE_STATE_RANGE_INDEX} 2)
        list(GET MUTABLE_STATE_RANGES ${MUTABLE_STATE_RANGE_INDEX} MUTABLE_EQUATE_NAME)
        math(EXPR MUTABLE_STATE_SIZE_INDEX "${MUTABLE_STATE_RANGE_INDEX} + 1")
        list(GET MUTABLE_STATE_RANGES ${MUTABLE_STATE_SIZE_INDEX} MUTABLE_BYTE_COUNT)
        read_equate("${EQUATE_FILE}" "${MUTABLE_EQUATE_NAME}" MUTABLE_EQUATE_ADDRESS)
        math(EXPR MUTABLE_START "0x${MUTABLE_EQUATE_ADDRESS}")
        math(EXPR MUTABLE_END "${MUTABLE_START} + ${MUTABLE_BYTE_COUNT} - 1")

        if(MUTABLE_START LESS RAM_START OR MUTABLE_END GREATER RAM_TOP)
            message(FATAL_ERROR "${MUTABLE_EQUATE_NAME} is outside AVO RAM: 0x${MUTABLE_EQUATE_ADDRESS}")
        endif()
        if(MUTABLE_START LESS DATA_FLOOR)
            message(FATAL_ERROR "${MUTABLE_EQUATE_NAME} crosses inv_data_floor: 0x${MUTABLE_EQUATE_ADDRESS}")
        endif()

        foreach(MUTABLE_OFFSET RANGE ${MUTABLE_START} ${MUTABLE_END})
            list(FIND USED_MUTABLE_OFFSETS "${MUTABLE_OFFSET}" MUTABLE_OFFSET_INDEX)
            if(NOT MUTABLE_OFFSET_INDEX EQUAL -1)
                message(FATAL_ERROR "${MUTABLE_EQUATE_NAME} overlaps another mutable AVO RAM allocation at ${MUTABLE_OFFSET}")
            endif()
            list(APPEND USED_MUTABLE_OFFSETS "${MUTABLE_OFFSET}")
        endforeach()
    endforeach()
endfunction()

assert_file_size("${INVADERS_BASE_ROM}" 8192)
assert_file_size("${INVADERS_AVO_ROM}" 8192)

set(INVADERS_SPLIT_OFFSET 0)
foreach(INVADERS_SPLIT_ROM_IMAGE IN LISTS INVADERS_SPLIT_ROM_IMAGES)
    set(INVADERS_SPLIT_ROM "${VT100_BINARY_DIRECTORY}/${INVADERS_SPLIT_ROM_IMAGE}")
    assert_file_size("${INVADERS_SPLIT_ROM}" 2048)

    file(READ "${INVADERS_BASE_ROM}" EXPECTED_SPLIT_HEX OFFSET ${INVADERS_SPLIT_OFFSET} LIMIT 2048 HEX)
    file(READ "${INVADERS_SPLIT_ROM}" ACTUAL_SPLIT_HEX HEX)
    if(NOT ACTUAL_SPLIT_HEX STREQUAL EXPECTED_SPLIT_HEX)
        message(FATAL_ERROR "${INVADERS_SPLIT_ROM_IMAGE} does not match invaders.bin at offset ${INVADERS_SPLIT_OFFSET}")
    endif()
    math(EXPR INVADERS_SPLIT_OFFSET "${INVADERS_SPLIT_OFFSET} + 2048")
endforeach()

read_symbol("${INVADERS_AVO_SYMBOLS}" inv_enter_impl INV_ENTER_IMPL)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_idle_impl INV_IDLE_IMPL)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_exit_impl INV_EXIT_IMPL)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_wait_frame INV_WAIT_FRAME)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_inc_frame16 INV_INC_FRAME16)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_frame INV_FRAME)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_test_tick INV_TEST_TICK)
read_equate("${INVADERS_BASE_EQUATES}" inv_enter INV_ENTER)
read_equate("${INVADERS_BASE_EQUATES}" inv_idle INV_IDLE)
read_equate("${INVADERS_BASE_EQUATES}" inv_exit INV_EXIT)
read_equate("${INVADERS_BASE_EQUATES}" inv_idle_hook INV_IDLE_HOOK)
read_equate("${INVADERS_BASE_EQUATES}" inv_setup_keys_hook INV_SETUP_KEYS_HOOK)
read_equate("${INVADERS_BASE_EQUATES}" inv_avo_ram_start INV_AVO_RAM_START)
read_equate("${INVADERS_BASE_EQUATES}" inv_avo_ram_top INV_AVO_RAM_TOP)
read_equate("${INVADERS_BASE_EQUATES}" inv_data_top INV_DATA_TOP)
read_equate("${INVADERS_BASE_EQUATES}" inv_data_floor INV_DATA_FLOOR)
read_symbol("${INVADERS_BASE_SYMBOLS}" idle_loop INVADERS_IDLE_LOOP)
read_symbol("${INVADERS_BASE_SYMBOLS}" keyboard_tick INVADERS_KEYBOARD_TICK)
read_symbol("${INVADERS_BASE_SYMBOLS}" setup_keys INVADERS_SETUP_KEYS)
read_symbol("${INVADERS_BASE_SYMBOLS}" rom1_checksum INVADERS_ROM1_CHECKSUM)
read_symbol("${INVADERS_BASE_SYMBOLS}" rom2_checksum INVADERS_ROM2_CHECKSUM)
read_symbol("${INVADERS_BASE_SYMBOLS}" rom3_checksum INVADERS_ROM3_CHECKSUM)
read_symbol("${INVADERS_BASE_SYMBOLS}" rom4_checksum INVADERS_ROM4_CHECKSUM)
read_symbol("${VT100_BASE_SYMBOLS}" idle_loop VT100_IDLE_LOOP)
read_symbol("${VT100_BASE_SYMBOLS}" keyboard_tick VT100_KEYBOARD_TICK)
read_symbol("${VT100_BASE_SYMBOLS}" setup_keys VT100_SETUP_KEYS)
assert_address_in_window(inv_enter_impl "${INV_ENTER_IMPL}")
assert_address_in_window(inv_idle_impl "${INV_IDLE_IMPL}")
assert_address_in_window(inv_exit_impl "${INV_EXIT_IMPL}")
assert_address_in_window(inv_wait_frame "${INV_WAIT_FRAME}")
assert_address_in_window(inv_inc_frame16 "${INV_INC_FRAME16}")
assert_address_in_window(inv_frame "${INV_FRAME}")
assert_address_in_window(inv_test_tick "${INV_TEST_TICK}")
assert_address_in_window(inv_enter "${INV_ENTER}")
assert_address_in_window(inv_idle "${INV_IDLE}")
assert_address_in_window(inv_exit "${INV_EXIT}")
assert_address_in_window(inv_idle_hook "${INV_IDLE_HOOK}")
assert_address_in_window(inv_setup_keys_hook "${INV_SETUP_KEYS_HOOK}")
assert_address_equals(inv_avo_ram_start "${INV_AVO_RAM_START}" "3000")
assert_address_equals(inv_avo_ram_top "${INV_AVO_RAM_TOP}" "3FFF")
assert_address_equals(inv_data_top "${INV_DATA_TOP}" "3FFF")
assert_address_equals(inv_data_floor "${INV_DATA_FLOOR}" "3800")
assert_address_equals(idle_loop "${INVADERS_IDLE_LOOP}" "${VT100_IDLE_LOOP}")
assert_address_equals(keyboard_tick "${INVADERS_KEYBOARD_TICK}" "${VT100_KEYBOARD_TICK}")
assert_address_equals(setup_keys "${INVADERS_SETUP_KEYS}" "${VT100_SETUP_KEYS}")

math(EXPR INVADERS_RAM_START "0x${INV_AVO_RAM_START}")
math(EXPR INVADERS_RAM_TOP "0x${INV_AVO_RAM_TOP}")
math(EXPR INVADERS_DATA_FLOOR_VALUE "0x${INV_DATA_FLOOR}")
assert_mutable_state_layout("${INVADERS_BASE_EQUATES}" ${INVADERS_RAM_START} ${INVADERS_RAM_TOP} ${INVADERS_DATA_FLOOR_VALUE})

file(READ "${VT100_BASE_ROM}" VT100_BASE_HEX HEX)
file(READ "${INVADERS_BASE_ROM}" INVADERS_BASE_HEX HEX)
math(EXPR IDLE_LOOP_OFFSET "0x${INVADERS_IDLE_LOOP}")
math(EXPR SETUP_KEYS_HOOK_OFFSET "0x${INVADERS_SETUP_KEYS} + 6")
math(EXPR SETUP_KEYS_HOOK_CPI_OFFSET "${SETUP_KEYS_HOOK_OFFSET} + 1")
math(EXPR SETUP_KEYS_HOOK_S_OFFSET "${SETUP_KEYS_HOOK_OFFSET} + 2")

assert_call_target("${VT100_BASE_HEX}" ${IDLE_LOOP_OFFSET} "${VT100_KEYBOARD_TICK}" "idle_loop displaced call")
assert_call_target("${INVADERS_BASE_HEX}" ${IDLE_LOOP_OFFSET} "${INV_IDLE_HOOK}" "idle_loop Invaders hook")
assert_hex_byte("${VT100_BASE_HEX}" ${SETUP_KEYS_HOOK_OFFSET} "78" "setup_keys displaced mov a,b")
assert_hex_byte("${VT100_BASE_HEX}" ${SETUP_KEYS_HOOK_CPI_OFFSET} "FE" "setup_keys displaced cpi opcode")
assert_hex_byte("${VT100_BASE_HEX}" ${SETUP_KEYS_HOOK_S_OFFSET} "53" "setup_keys displaced 'S' operand")
assert_call_target("${INVADERS_BASE_HEX}" ${SETUP_KEYS_HOOK_OFFSET} "${INV_SETUP_KEYS_HOOK}" "setup_keys Invaders hook")

set(ALLOWED_DIFF_OFFSETS "")
append_allowed_range(ALLOWED_DIFF_OFFSETS ${IDLE_LOOP_OFFSET} 3)
append_allowed_range(ALLOWED_DIFF_OFFSETS ${SETUP_KEYS_HOOK_OFFSET} 3)
append_allowed_symbol(ALLOWED_DIFF_OFFSETS "${INVADERS_ROM1_CHECKSUM}")
append_allowed_symbol(ALLOWED_DIFF_OFFSETS "${INVADERS_ROM2_CHECKSUM}")
append_allowed_symbol(ALLOWED_DIFF_OFFSETS "${INVADERS_ROM3_CHECKSUM}")
append_allowed_symbol(ALLOWED_DIFF_OFFSETS "${INVADERS_ROM4_CHECKSUM}")

foreach(BASE_OFFSET RANGE 0 8191)
    hex_byte("${VT100_BASE_HEX}" ${BASE_OFFSET} VT100_BYTE)
    hex_byte("${INVADERS_BASE_HEX}" ${BASE_OFFSET} INVADERS_BYTE)
    if(NOT VT100_BYTE STREQUAL INVADERS_BYTE)
        list(FIND ALLOWED_DIFF_OFFSETS "${BASE_OFFSET}" ALLOWED_INDEX)
        if(ALLOWED_INDEX EQUAL -1)
            message(FATAL_ERROR "Unexpected Invaders base ROM byte difference at 0x${BASE_OFFSET}: vt100=${VT100_BYTE} invaders=${INVADERS_BYTE}")
        endif()
    endif()
endforeach()

file(READ "${INVADERS_AVO_ROM}" INVADERS_AVO_HEADER HEX OFFSET 0 LIMIT 12)
string(TOUPPER "${INVADERS_AVO_HEADER}" INVADERS_AVO_HEADER)
assert_hex_byte("${INVADERS_AVO_HEADER}" 0 "C3" "inv_enter")
assert_hex_byte("${INVADERS_AVO_HEADER}" 3 "C3" "inv_idle")
assert_hex_byte("${INVADERS_AVO_HEADER}" 6 "C3" "inv_exit")
assert_hex_byte("${INVADERS_AVO_HEADER}" 9 "C3" "inv_idle_hook")
assert_jump_target("${INVADERS_AVO_HEADER}" 0 "${INV_ENTER_IMPL}" "inv_enter")
assert_jump_target("${INVADERS_AVO_HEADER}" 3 "${INV_IDLE_IMPL}" "inv_idle")
assert_jump_target("${INVADERS_AVO_HEADER}" 6 "${INV_EXIT_IMPL}" "inv_exit")
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_idle_hook_impl INV_IDLE_HOOK_IMPL)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_setup_keys_hook_impl INV_SETUP_KEYS_HOOK_IMPL)
assert_address_in_window(inv_idle_hook_impl "${INV_IDLE_HOOK_IMPL}")
assert_address_in_window(inv_setup_keys_hook_impl "${INV_SETUP_KEYS_HOOK_IMPL}")
assert_jump_target("${INVADERS_AVO_HEADER}" 9 "${INV_IDLE_HOOK_IMPL}" "inv_idle_hook")

file(READ "${INVADERS_AVO_ROM}" INVADERS_AVO_SETUP_HOOK HEX OFFSET 12 LIMIT 3)
string(TOUPPER "${INVADERS_AVO_SETUP_HOOK}" INVADERS_AVO_SETUP_HOOK)
assert_jump_target("${INVADERS_AVO_SETUP_HOOK}" 0 "${INV_SETUP_KEYS_HOOK_IMPL}" "inv_setup_keys_hook")

message(STATUS "Invaders ROM layout verified")
