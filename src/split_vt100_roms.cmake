if(NOT DEFINED INPUT_FILE)
    message(FATAL_ERROR "INPUT_FILE is required")
endif()
if(NOT DEFINED OUTPUT_DIRECTORY)
    message(FATAL_ERROR "OUTPUT_DIRECTORY is required")
endif()

if(NOT EXISTS "${INPUT_FILE}")
    message(FATAL_ERROR "Input file does not exist: ${INPUT_FILE}")
endif()

file(READ "${INPUT_FILE}" INPUT_HEX HEX)
string(LENGTH "${INPUT_HEX}" INPUT_HEX_LENGTH)
math(EXPR INPUT_SIZE "${INPUT_HEX_LENGTH} / 2")
if(NOT INPUT_SIZE EQUAL 8192)
    message(FATAL_ERROR "Expected an 8192-byte VT100 ROM image: ${INPUT_FILE} is ${INPUT_SIZE} bytes")
endif()

file(MAKE_DIRECTORY "${OUTPUT_DIRECTORY}")

set(ROM_CHUNK_SIZE 2048)
set(ROM_OFFSETS
    0
    2048
    4096
    6144
)
set(ROM_SKIPS
    0
    1
    2
    3
)
set(ROM_FILES
    23-061E2.bin
    23-032E2.bin
    23-033E2.bin
    23-034E2.bin
)

list(LENGTH ROM_FILES ROM_FILE_COUNT)
math(EXPR LAST_ROM_FILE_INDEX "${ROM_FILE_COUNT} - 1")

if(WIN32)
    find_program(POWERSHELL_COMMAND NAMES powershell pwsh)
    if(NOT POWERSHELL_COMMAND)
        message(FATAL_ERROR "PowerShell was not found")
    endif()
else()
    find_program(DD_COMMAND NAMES dd)
    if(NOT DD_COMMAND)
        message(FATAL_ERROR "dd was not found")
    endif()
endif()

foreach(ROM_FILE_INDEX RANGE 0 ${LAST_ROM_FILE_INDEX})
    list(GET ROM_OFFSETS ${ROM_FILE_INDEX} ROM_OFFSET)
    list(GET ROM_SKIPS ${ROM_FILE_INDEX} ROM_SKIP)
    list(GET ROM_FILES ${ROM_FILE_INDEX} ROM_FILE)
    set(OUTPUT_FILE "${OUTPUT_DIRECTORY}/${ROM_FILE}")

    if(WIN32)
        set(PS_INPUT_FILE "${INPUT_FILE}")
        set(PS_OUTPUT_FILE "${OUTPUT_FILE}")
        string(REPLACE "'" "''" PS_INPUT_FILE "${PS_INPUT_FILE}")
        string(REPLACE "'" "''" PS_OUTPUT_FILE "${PS_OUTPUT_FILE}")
        set(PS_SPLIT_COMMAND
            "$ErrorActionPreference = 'Stop'
            $rom = [System.IO.File]::ReadAllBytes('${PS_INPUT_FILE}')
            $chunk = New-Object byte[] ${ROM_CHUNK_SIZE}
            [Array]::Copy($rom, ${ROM_OFFSET}, $chunk, 0, ${ROM_CHUNK_SIZE})
            [System.IO.File]::WriteAllBytes('${PS_OUTPUT_FILE}', $chunk)"
        )
        execute_process(
            COMMAND
                "${POWERSHELL_COMMAND}"
                -NoProfile
                -ExecutionPolicy Bypass
                -Command
                    "${PS_SPLIT_COMMAND}"
            RESULT_VARIABLE SPLIT_RESULT
            OUTPUT_VARIABLE SPLIT_OUTPUT
            ERROR_VARIABLE SPLIT_ERROR
        )
    else()
        execute_process(
            COMMAND
                "${DD_COMMAND}"
                "if=${INPUT_FILE}"
                "of=${OUTPUT_FILE}"
                "bs=${ROM_CHUNK_SIZE}"
                "count=1"
                "skip=${ROM_SKIP}"
            RESULT_VARIABLE SPLIT_RESULT
            OUTPUT_VARIABLE SPLIT_OUTPUT
            ERROR_VARIABLE SPLIT_ERROR
        )
    endif()

    if(NOT SPLIT_RESULT EQUAL 0)
        message(FATAL_ERROR "Failed to write ${OUTPUT_FILE}\n${SPLIT_OUTPUT}${SPLIT_ERROR}")
    endif()

    file(READ "${OUTPUT_FILE}" OUTPUT_HEX HEX)
    string(LENGTH "${OUTPUT_HEX}" OUTPUT_HEX_LENGTH)
    math(EXPR OUTPUT_SIZE "${OUTPUT_HEX_LENGTH} / 2")
    if(NOT OUTPUT_SIZE EQUAL ROM_CHUNK_SIZE)
        message(FATAL_ERROR "Expected ${ROM_CHUNK_SIZE} bytes in ${OUTPUT_FILE}; got ${OUTPUT_SIZE}")
    endif()
endforeach()
