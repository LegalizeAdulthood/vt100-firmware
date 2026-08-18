if(NOT DEFINED ACTUAL_FILE)
    message(FATAL_ERROR "ACTUAL_FILE is required")
endif()
if(NOT DEFINED EXPECTED_FILE)
    message(FATAL_ERROR "EXPECTED_FILE is required")
endif()

if(NOT EXISTS "${ACTUAL_FILE}")
    message(FATAL_ERROR "Actual file does not exist: ${ACTUAL_FILE}")
endif()
if(NOT EXISTS "${EXPECTED_FILE}")
    message(FATAL_ERROR "Expected file does not exist: ${EXPECTED_FILE}")
endif()

file(READ "${ACTUAL_FILE}" ACTUAL_HEX HEX)
file(READ "${EXPECTED_FILE}" EXPECTED_HEX HEX)

string(TOUPPER "${ACTUAL_HEX}" ACTUAL_HEX)
string(TOUPPER "${EXPECTED_HEX}" EXPECTED_HEX)
string(LENGTH "${ACTUAL_HEX}" ACTUAL_HEX_LENGTH)
string(LENGTH "${EXPECTED_HEX}" EXPECTED_HEX_LENGTH)

math(EXPR ACTUAL_BYTES "${ACTUAL_HEX_LENGTH} / 2")
math(EXPR EXPECTED_BYTES "${EXPECTED_HEX_LENGTH} / 2")

if(ACTUAL_BYTES LESS EXPECTED_BYTES)
    set(COMMON_BYTES "${ACTUAL_BYTES}")
else()
    set(COMMON_BYTES "${EXPECTED_BYTES}")
endif()

set(MISMATCH_COUNT 0)
set(MISMATCH_REPORT "")

if(COMMON_BYTES GREATER 0)
    math(EXPR LAST_COMMON_BYTE "${COMMON_BYTES} - 1")
    foreach(BYTE_INDEX RANGE 0 ${LAST_COMMON_BYTE})
        math(EXPR HEX_INDEX "${BYTE_INDEX} * 2")
        string(SUBSTRING "${ACTUAL_HEX}" ${HEX_INDEX} 2 ACTUAL_BYTE)
        string(SUBSTRING "${EXPECTED_HEX}" ${HEX_INDEX} 2 EXPECTED_BYTE)
        if(NOT ACTUAL_BYTE STREQUAL EXPECTED_BYTE)
            math(EXPR MISMATCH_COUNT "${MISMATCH_COUNT} + 1")
            string(APPEND MISMATCH_REPORT "byte ${BYTE_INDEX}: expected 0x${EXPECTED_BYTE}, actual 0x${ACTUAL_BYTE}\n")
        endif()
    endforeach()
endif()

if(EXPECTED_BYTES GREATER COMMON_BYTES)
    math(EXPR LAST_EXPECTED_BYTE "${EXPECTED_BYTES} - 1")
    foreach(BYTE_INDEX RANGE ${COMMON_BYTES} ${LAST_EXPECTED_BYTE})
        math(EXPR HEX_INDEX "${BYTE_INDEX} * 2")
        string(SUBSTRING "${EXPECTED_HEX}" ${HEX_INDEX} 2 EXPECTED_BYTE)
        math(EXPR MISMATCH_COUNT "${MISMATCH_COUNT} + 1")
        string(APPEND MISMATCH_REPORT "byte ${BYTE_INDEX}: expected 0x${EXPECTED_BYTE}, actual <EOF>\n")
    endforeach()
endif()

if(ACTUAL_BYTES GREATER COMMON_BYTES)
    math(EXPR LAST_ACTUAL_BYTE "${ACTUAL_BYTES} - 1")
    foreach(BYTE_INDEX RANGE ${COMMON_BYTES} ${LAST_ACTUAL_BYTE})
        math(EXPR HEX_INDEX "${BYTE_INDEX} * 2")
        string(SUBSTRING "${ACTUAL_HEX}" ${HEX_INDEX} 2 ACTUAL_BYTE)
        math(EXPR MISMATCH_COUNT "${MISMATCH_COUNT} + 1")
        string(APPEND MISMATCH_REPORT "byte ${BYTE_INDEX}: expected <EOF>, actual 0x${ACTUAL_BYTE}\n")
    endforeach()
endif()

if(MISMATCH_COUNT GREATER 0)
    message(FATAL_ERROR
        "Binary files differ: ${MISMATCH_COUNT} byte(s) do not match\n"
        "Expected: ${EXPECTED_FILE} (${EXPECTED_BYTES} bytes)\n"
        "Actual: ${ACTUAL_FILE} (${ACTUAL_BYTES} bytes)\n"
        "${MISMATCH_REPORT}"
    )
endif()

message(STATUS "Binary files match: ${ACTUAL_FILE} equals ${EXPECTED_FILE} (${ACTUAL_BYTES} bytes)")
