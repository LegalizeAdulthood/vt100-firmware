set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO begoon/asm8080
    REF 8dd1f4d2567838583b7c0509a16f38fd8a1e14b1
    SHA512 b50ba4596b60159abc1d4b5d2532e2144eab172fc9e20dfb12dd3047699edf12c63c1703c3be33f1978f8f238724e63dfff6a7ce6732b9c159cf056ece7a7841
    HEAD_REF master
)

file(COPY "${CMAKE_CURRENT_LIST_DIR}/CMakeLists.txt" DESTINATION "${SOURCE_PATH}")

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
)
vcpkg_cmake_install()
vcpkg_copy_tools(TOOL_NAMES asm8080 AUTO_CLEAN)
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
