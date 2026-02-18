find_package(PkgConfig)
pkg_check_modules(LIBGD REQUIRED IMPORTED_TARGET gdlib)
find_package(SDL2 CONFIG REQUIRED)

add_executable(awnty
    awnty.c
    coverage.c
    coverage.h
    er1400.c
    er1400.h
    gdfont.h
    i8080.c
    i8080.h
    sdl_gd.c
    sdl_gd.h
    unused.h
    vt100-charset-rom.h
    vt100_memory.c
    vt100_memory.h
)
target_link_libraries(awnty
    PRIVATE
        $<TARGET_NAME_IF_EXISTS:SDL2::SDL2main>
        $<IF:$<TARGET_EXISTS:SDL2::SDL2>,SDL2::SDL2,SDL2::SDL2-static>
        PkgConfig::LIBGD)
target_folder(awnty "Tools")
