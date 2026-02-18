cmake_minimum_required(VERSION 3.10)

set(VT100_FIRMWARE_PROJECT_NAME "vt100-firmware")
project("${VT100_FIRMWARE_PROJECT_NAME}" C)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")

include(misc_target)
include(target_folder)

add_subdirectory(awnty)
add_subdirectory(src)

misc_target(FILES
    cmake/misc_target.cmake
    CMakePresets.json
    README.md
)
misc_group_sources("Docs" FILES README.md)
misc_group_sources("CMake" FILES CMakePresets.json)
misc_group_sources("CMake Scripts" FILES "cmake/misc_target.cmake")

