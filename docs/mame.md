# Running `vt100.bin` in MAME on Windows

This note explains how to build this repository's VT100 firmware, prepare it
as a MAME ROM set, and run it with the official Windows MAME binary.

MAME's current upstream Windows source-build instructions use MSYS2/GNU make,
not CMake. This document therefore does not build MAME from source. It uses the
prebuilt `mame.exe` release instead.

## Build the firmware

From Command Prompt, or from a `.bat` file:

```bat
cd /d C:\code\vt100\vt100-firmware
cmake --workflow --preset default
```

The CMake target assembles `src\vt100.asm` and writes the combined 8 KiB ROM
image here:

```text
C:\code\vt100\build-vt100-firmware-default\src\vt100.bin
```

The build also splits that image into the four 2 KiB ROM images used by the
VT100 CPU board:

```text
C:\code\vt100\build-vt100-firmware-default\src\23-061E2.bin
C:\code\vt100\build-vt100-firmware-default\src\23-032E2.bin
C:\code\vt100\build-vt100-firmware-default\src\23-033E2.bin
C:\code\vt100\build-vt100-firmware-default\src\23-034E2.bin
```

The CTest suite compares those generated split images with the matching
reference files in `bin`.

## Install MAME

Download the official Windows MAME binary package from the MAME release page:

```text
https://www.mamedev.org/release.html
```

Extract the archive to a local directory. The examples below assume:

```text
C:\code\mame
```

The MAME executable should then be:

```text
C:\code\mame\mame.exe
```

## Prepare the ROM set

MAME's `vt100` driver does not load a single file named `vt100.bin`. It expects
the main CPU firmware as four 2 KiB ROM images with the DEC part/location names
used by the driver. Copy the generated split images into the MAME ROM set with
these names:

| Generated file | MAME file name |
|---|---|
| `23-061E2.bin` | `23-061e2-00.e56` |
| `23-032E2.bin` | `23-032e2-00.e52` |
| `23-033E2.bin` | `23-033e2-00.e45` |
| `23-034E2.bin` | `23-034e2-00.e40` |

The driver also needs the character generator ROM. This repository includes it
as `bin\23-018E2.bin`; copy it into the MAME ROM set as
`23-018e2-00.e4`.

From Command Prompt, or from a `.bat` file:

```bat
set "FIRMWARE_ROOT=C:\code\vt100\vt100-firmware"
set "BUILD_SRC=C:\code\vt100\build-vt100-firmware-default\src"
set "MAME_ROOT=C:\code\mame"
set "ROM_DIR=%MAME_ROOT%\roms\vt100"

if not exist "%ROM_DIR%" mkdir "%ROM_DIR%"

copy /Y "%BUILD_SRC%\23-061E2.bin" "%ROM_DIR%\23-061e2-00.e56"
copy /Y "%BUILD_SRC%\23-032E2.bin" "%ROM_DIR%\23-032e2-00.e52"
copy /Y "%BUILD_SRC%\23-033E2.bin" "%ROM_DIR%\23-033e2-00.e45"
copy /Y "%BUILD_SRC%\23-034E2.bin" "%ROM_DIR%\23-034e2-00.e40"
copy /Y "%FIRMWARE_ROOT%\bin\23-018E2.bin" "%ROM_DIR%\23-018e2-00.e4"

dir "%ROM_DIR%"
```

Current MAME source also names `23-094e2-00.e9` for the optional alternate
character set ROM, but marks it as `NO_DUMP`. No file is needed for normal
VT100 testing unless you have an alternate character generator ROM to try.

Keep the ROMs unpacked in `roms\vt100` while iterating. MAME also accepts a
`roms\vt100.zip` archive, but the directory form is easier to update after each
firmware rebuild.

## Run the emulator

From Command Prompt:

```bat
cd /d C:\code\mame
mame.exe vt100 -rompath C:\code\mame\roms -window
```

The `vt100` system is still flagged by MAME as not working and having imperfect
graphics, so expect the startup warning screen. Type `OK` when MAME asks for
acknowledgement.

## Diagnostics

List the ROM files that the current MAME driver expects:

```bat
cd /d C:\code\mame
mame.exe -listroms vt100
```

Ask MAME to check the local ROM set:

```bat
cd /d C:\code\mame
mame.exe -verifyroms vt100 -rompath C:\code\mame\roms
```

If `vt100.bin` has been modified from the stock firmware, MAME will report
checksum differences for the four CPU ROM chunks. That is expected for local
firmware experiments. Missing-file errors usually mean the ROM set directory or
one of the MAME file names is wrong.

## References

- [MAME source repository](https://github.com/mamedev/mame)
- [MAME Windows installation](https://docs.mamedev.org/initialsetup/installingmame.html)
- [MAME compiling instructions](https://docs.mamedev.org/initialsetup/compilingmame.html)
- [MAME VT100 driver](https://github.com/mamedev/mame/blob/master/src/mame/dec/vt100.cpp)
- [MAME media search rules](https://docs.mamedev.org/usingmame/assetsearch.html)
