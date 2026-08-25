if(NOT DEFINED VT100_BINARY_DIRECTORY)
    message(FATAL_ERROR "VT100_BINARY_DIRECTORY is required")
endif()

set(INVADERS_BASE_ROM "${VT100_BINARY_DIRECTORY}/invaders.bin")
set(INVADERS_AVO_ROM "${VT100_BINARY_DIRECTORY}/invaders-avo.bin")
set(INVADERS_BASE_SYMBOLS "${VT100_BINARY_DIRECTORY}/invaders.sym")
set(INVADERS_AVO_SYMBOLS "${VT100_BINARY_DIRECTORY}/invaders-avo.sym")

set(INVADERS_SPLIT_ROM_IMAGES
    invaders-1.bin
    invaders-2.bin
    invaders-3.bin
    invaders-4.bin
)

set(REQUIRED_INVADERS_FILES
    "${INVADERS_BASE_ROM}"
    "${INVADERS_AVO_ROM}"
    "${INVADERS_BASE_SYMBOLS}"
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
    file(STRINGS "${SYMBOL_FILE}" SYMBOL_LINES REGEX "^[0-9A-Fa-f]+[ \t]+${SYMBOL_NAME}$")
    list(LENGTH SYMBOL_LINES SYMBOL_LINE_COUNT)
    if(NOT SYMBOL_LINE_COUNT EQUAL 1)
        message(FATAL_ERROR "Expected exactly one ${SYMBOL_NAME} symbol in ${SYMBOL_FILE}; got ${SYMBOL_LINE_COUNT}")
    endif()
    list(GET SYMBOL_LINES 0 SYMBOL_LINE)
    if(NOT SYMBOL_LINE MATCHES "^([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])[ \t]+${SYMBOL_NAME}$")
        message(FATAL_ERROR "Could not parse ${SYMBOL_NAME} symbol from ${SYMBOL_FILE}: ${SYMBOL_LINE}")
    endif()
    string(TOUPPER "${CMAKE_MATCH_1}" SYMBOL_ADDRESS)
    set(${OUTPUT_VARIABLE} "${SYMBOL_ADDRESS}" PARENT_SCOPE)
endfunction()

function(assert_symbol_in_window SYMBOL_NAME SYMBOL_ADDRESS)
    math(EXPR SYMBOL_VALUE "0x${SYMBOL_ADDRESS}")
    if(SYMBOL_VALUE LESS 32768 OR SYMBOL_VALUE GREATER 40959)
        message(FATAL_ERROR "${SYMBOL_NAME} is outside the AVO ROM window: 0x${SYMBOL_ADDRESS}")
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
assert_symbol_in_window(inv_enter_impl "${INV_ENTER_IMPL}")
assert_symbol_in_window(inv_idle_impl "${INV_IDLE_IMPL}")
assert_symbol_in_window(inv_exit_impl "${INV_EXIT_IMPL}")

file(READ "${INVADERS_AVO_ROM}" INVADERS_AVO_HEADER HEX OFFSET 0 LIMIT 12)
string(TOUPPER "${INVADERS_AVO_HEADER}" INVADERS_AVO_HEADER)
assert_hex_byte("${INVADERS_AVO_HEADER}" 0 "C3" "inv_enter")
assert_hex_byte("${INVADERS_AVO_HEADER}" 3 "C3" "inv_idle")
assert_hex_byte("${INVADERS_AVO_HEADER}" 6 "C3" "inv_exit")
assert_jump_target("${INVADERS_AVO_HEADER}" 0 "${INV_ENTER_IMPL}" "inv_enter")
assert_jump_target("${INVADERS_AVO_HEADER}" 3 "${INV_IDLE_IMPL}" "inv_idle")
assert_jump_target("${INVADERS_AVO_HEADER}" 6 "${INV_EXIT_IMPL}" "inv_exit")

message(STATUS "Invaders ROM layout verified")
