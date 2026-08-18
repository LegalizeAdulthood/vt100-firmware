cmake_minimum_required(VERSION 3.10)

project(asm8080 C)

add_executable(asm8080
    src/asm_dir.c
    src/exp_parser.c
    src/main.c
    src/msg.c
    src/opcode.c
    src/util.c
)
target_include_directories(asm8080 PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")

if(WIN32)
    target_sources(asm8080 PRIVATE windows/strncasecmp.c)
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        target_compile_definitions(asm8080 PRIVATE _TGT_OS_WIN64=1)
    else()
        target_compile_definitions(asm8080 PRIVATE _TGT_OS_WIN32=1)
    endif()
else()
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        target_compile_definitions(asm8080 PRIVATE _TGT_OS_LINUX64=1)
    else()
        target_compile_definitions(asm8080 PRIVATE _TGT_OS_LINUX32=1)
    endif()
endif()

install(TARGETS asm8080 RUNTIME DESTINATION bin)
