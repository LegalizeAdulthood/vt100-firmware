# vt100-firmware

This repository is a fork of
[The Annotated VT100 Firmware](https://vt100.net/dec/vt100/rom/). It builds on
the upstream annotated assembly source, adding preset-based CMake/vcpkg builds,
ROM regression tests, and MAME integration.

This fork also adds [VT100 Invaders](docs/invaders.md), a firmware-resident
Space Invaders-style game that uses the AVO program expansion ROM. The stock
VT100 and Invaders ROMs are built separately from shared base firmware using
[asm8080](https://github.com/begoon/asm8080); building the stock ROMs does not
enable the game.

## Requirements

- CMake 3.25 or newer, required by the version 6 presets and workflow presets.
- Git and a C/C++ compiler with its native build tools. On Windows, install the
  Visual Studio C++ workload and a Windows SDK.
- `powershell` or `pwsh` on Windows, or `dd` on other platforms, for splitting
  ROM images. The Windows commands below can be run from Command Prompt.
- MAME for the Invaders workflow, emulator launch targets, and MAME-backed
  tests. Building ROM images and testing the stock firmware do not need MAME.

Run all commands from the repository root. Initialize the bundled vcpkg
submodule before configuring:

```bat
git submodule update --init --recursive
```

The presets select the bundled vcpkg toolchain and the repository's overlay
ports. The first configuration bootstraps vcpkg if needed and downloads/builds
the dependencies, including the asm8080 host tool, libgd, pkgconf, and SDL2.
There is no need to install asm8080 separately.

## Build And Test The Stock Firmware

Configure, build, and test with the `default` workflow:

```bat
cmake --workflow --preset default
```

The equivalent individual steps are:

```bat
cmake --preset default
cmake --build --preset default
ctest --preset default
```

The default build includes `vt100-rom` and the host utilities. The default test
preset compares the stock ROM images with the checked-in originals and excludes
Invaders tests. To build only the stock ROM images after configuration:

```bat
cmake --build --preset default --target vt100-rom
```

## Build And Run Invaders Under MAME

If MAME is not on `PATH`, configure its executable path first. Replace
`<MAMEDir>` with your MAME installation directory:

```bat
cmake --preset invaders "-DMAME_COMMAND=<MAMEDir>/mame.exe"
cmake --workflow --preset invaders
cmake --build --preset invaders --target run-invaders
```

The `invaders` workflow builds `vt100-rom` for stock firmware regression tests
and `mame-invaders` to build and stage the Invaders ROMs, then runs all CTest
tests. MAME must be found or configured for this workflow because its build
preset explicitly selects `mame-invaders`.

The `run-invaders` target stages the ROMs and launches MAME from its installation
directory. It uses the `vt102` machine to load the AVO expansion ROM and assigns
F12 as MAME's UI-mode key. Staging requires write access to `<MAMEDir>/roms` and
does not replace existing NVRAM settings or high scores. Automated tests use
separate build-local MAME state.

To rebuild or rerun tests independently:

```bat
cmake --build --preset invaders
ctest --preset invaders
```

For a ROM-only Invaders build without MAME, use the default configuration and
select `invaders-rom` explicitly:

```bat
cmake --preset default
cmake --build --preset default --target invaders-rom
```

To stage the stock VT100 ROMs instead:

```bat
cmake --preset default "-DMAME_COMMAND=<MAMEDir>/mame.exe"
cmake --build --preset default --target mame
```

See [Running MAME](docs/mame.md) for emulator setup and keyboard bindings, and
[Invaders](docs/invaders.md) for the game design and test harness.

## How To Play

Press SET-UP, then `i` or `I` to launch the animated attract screen. Press
RETURN to start a fresh game with four lives. Use Left and Right to move and
Space to fire; the four keyboard LEDs show the remaining lives. SET-UP exits
from any game screen to a cleared 80-column terminal, restoring the saved
cursor rendition and LEDs but not the previous screen or 132-column layout.

After a qualifying nonzero score, enter one to three initials using upper-case
letters, digits, or punctuation. Left and Right move within the field, typing
replaces a character, and Backspace moves back and clears it. RETURN confirms
after at least one character; SET-UP cancels without saving. The animated
attract screen returns after game over or confirmation. Release RETURN before
pressing it again to start the next game.

With default MAME paths, manual high scores and terminal settings are saved in
`<MAMEDir>/nvram/vt102/nvr`. Exit MAME normally to write the file. Rebuilding
or running `run-invaders` does not overwrite it, and automated tests use
isolated state. See [NVRAM Settings](docs/mame.md#nvram-settings),
[Keyboard Bindings](docs/mame.md#keyboard-bindings), and
[Machine Configuration Menu](docs/mame.md#machine-configuration-menu) for
emulator details.

Physical VT100 operation requires AVO, its byte-wide screen RAM, and the
program expansion ROM at `8000h`; selecting `vt102` is only a MAME workaround.
Physical-hardware acceptance and the 50/60 Hz timing decision remain pending
in the [implementation plan](docs/invaders.md#implementation).

## Configuration Variables

Pass cache variables with `-D` to `cmake --preset default` or
`cmake --preset invaders`, not to the build, test, or workflow commands. Each
preset has its own build directory and cache. Configure it once with local
values before running its workflow; subsequent workflow runs retain them.

| Variable | Purpose |
|---|---|
| `MAME_COMMAND` | Full path to the MAME executable. When empty, CMake searches for `mame` or `mame.exe`. A non-empty result enables `mame`, `mame-invaders`, `run-invaders`, and MAME-backed tests. If MAME is not found, ROM-only builds remain available. |
| `BUILD_TESTING` | Defaults to `ON`. Set to `OFF` to omit all CTest tests; use a build command rather than a test workflow in that configuration. |
| `ASM8080_EXECUTABLE` | Normally discovered automatically from vcpkg. Set an absolute path only to use a different asm8080 executable. |
| `VCPKG_TARGET_TRIPLET` | Override vcpkg's inferred target platform, for example `x64-windows`. Usually unnecessary for a native build. |
| `VCPKG_HOST_TRIPLET` | Override the platform used to build host tools such as asm8080. Usually inferred automatically. |
| `CMAKE_BUILD_TYPE` | Set to `Release` when using a single-configuration generator such as Ninja or Unix Makefiles. The build presets already select `Release` for multi-configuration generators such as Visual Studio. |

For example, configure a single-configuration Ninja build before running its
workflow:

```bat
cmake --preset default -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --workflow --preset default
```

Choose the generator when first configuring a build directory; an existing
build tree cannot be switched to a different generator. Local preset overrides
can be kept in the untracked `CMakeUserPresets.json`.

## Build Outputs

The presets create sibling build directories named
`build-<SourceDirName>-<PresetName>`. For a checkout named `vt100-firmware`, these
are `../build-vt100-firmware-default` and `../build-vt100-firmware-invaders`.
Generated ROMs, listings, symbols, and equates are under each build's `src`
directory.

| Target | ROM Outputs |
|---|---|
| `vt100-rom` | Combined 8 KiB `vt100.bin` and four 2 KiB images: `23-061E2.bin`, `23-032E2.bin`, `23-033E2.bin`, and `23-034E2.bin`. |
| `invaders-rom` | Combined 8 KiB `invaders.bin`, four 2 KiB images `invaders-1.bin` through `invaders-4.bin`, and the 8 KiB `invaders-avo.bin`. |
| `mame` | Builds and copies the stock ROMs and character generator to `<MAMEDir>/roms/vt100` with MAME's expected filenames. |
| `mame-invaders` | Builds and copies the combined Invaders base ROM, AVO ROM, and character generator to `<MAMEDir>/roms/vt102` with MAME's expected filenames. |

The four split Invaders images are the physical base-ROM outputs. MAME's
`vt102` machine uses the combined image instead; see the
[ROM staging table](docs/invaders.md#build-and-rom-preparation).
