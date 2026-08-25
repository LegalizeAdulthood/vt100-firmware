# Running `vt100.bin` in MAME on Windows

This note explains how to build this repository's VT100 firmware, prepare it
as a MAME ROM set, and run it with the official Windows MAME binary.

MAME's current upstream Windows source-build instructions use MSYS2/GNU make,
not CMake. This document therefore does not build MAME from source. It uses the
prebuilt `mame.exe` release instead.

## Build the Firmware

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

## Prepare the ROM Set

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
as `bin\23-018E2.bin`; the `mame` target installs it in the MAME ROM set as
`23-018e2-00.e4`.

The CMake cache variable `MAME_COMMAND` specifies the path to `mame.exe`. If it
is left empty, CMake searches for `mame` or `mame.exe` with `find_program`.
When `MAME_COMMAND` is non-empty after configuration, CMake creates a `mame`
target that copies the ROM files into MAME's `roms\vt100` directory.

If `mame.exe` is already on `PATH`, configure normally. Otherwise, set
`MAME_COMMAND` when configuring:

```bat
cmake --preset default -DMAME_COMMAND=<MAMEDir>\mame.exe
```

Then build the `mame` target:

```bat
cmake --build --preset default --target mame
```

Current MAME source also names `23-094e2-00.e9` for the optional alternate
character set ROM, but marks it as `NO_DUMP`. No file is needed for normal
VT100 testing unless you have an alternate character generator ROM to try.

The target keeps the ROMs unpacked in `<MAMEDir>\roms\vt100` while iterating.
MAME also accepts a `roms\vt100.zip` archive, but the directory form is easier
to update after each firmware rebuild.

## Running MAME

From Command Prompt:

```bat
cd /d C:\code\mame
mame.exe vt100 -rompath C:\code\mame\roms -window
```

The `vt100` system is still flagged by MAME as not working and having imperfect
graphics, so expect the startup warning screen. Type `OK` when MAME asks for
acknowledgement.

Use the `vt102` machine instead of `vt100` in MAME when testing firmware that
needs the AVO program expansion ROM. This is a MAME `vt100` driver limitation,
not a VT100 hardware limitation: a real VT100 can use an AVO board with an
expansion ROM, but MAME's `vt100` machine currently loads only the base CPU ROMs
and does not expose the AVO expansion ROM at `8000h`; MAME's `vt102` machine
does.

### Machine Configuration Menu

Because the VT100 has its own keyboard, MAME normally sends keyboard input to
the emulated terminal. Press `Scroll Lock` to toggle MAME UI controls, then
press `Tab` to open the MAME menu and choose `Machine Configuration`. Press
`Esc` to back out of the MAME menus, then press `Scroll Lock` again to return
keyboard input to the VT100.

If the keyboard does not have a `Scroll Lock` key, choose a different MAME UI
mode key on the command line:

```bat
cd /d <MAMEDir>
mame.exe vt100 -rompath roms -window -uimodekey F12
```

Press `F12` anywhere these instructions say to press `Scroll Lock`. To start
with MAME UI controls already active, add `-ui_active`; press `F12` after using
the menus so normal key presses go to the VT100 again.

## NVRAM Settings

MAME stores the VT100's non-volatile settings in the machine's NVRAM directory:

```text
<MAMEDir>\nvram\vt100\nvr
```

MAME derives this path from `homepath` and `nvram_directory`; check the active
values with `mame.exe -showconfig`. In the default Windows configuration,
`homepath` is `.` and `nvram_directory` is `nvram`, so the file is written
relative to the directory where MAME is run as `nvram\vt100\nvr` unless the
configuration overrides it.

## Keyboard Bindings

The table below lists the default VT100 keyboard bindings reported by MAME
0.289. MAME displays host keyboard inputs with a leading `Kbd` device prefix;
that prefix is omitted here. Bindings where the host key and VT100 key have the
same name are omitted. If the keyboard is controlling the MAME UI instead of
the emulated VT100, press `Scroll Lock` once to toggle keyboard focus. Rows are
grouped by host keyboard area.

| Host key | VT100 key |
|---|---|
| `F1` | `PF1` |
| `F2` | `PF2` |
| `F3` | `PF3` |
| `F4` | `PF4` |
| `F5` | `Setup` |
| `F6` | `Break` |
| `Backquote` | `~` |
| `Enter` | `Return` |
| `Shift or Right Shift` | `Shift` |
| `Alt` | `No scroll` |
| `Right Alt` | `Line feed` |
| `Num Enter` | `Num Return` |
| `Num Del` | `Num .` |
| `Num +` | `Num ,` |

## Serial Port

The emulated VT100 has one RS-232 port named `rs232`. MAME leaves the slot
empty unless a device is selected with `-rs232`. The `null_modem` device is the
most useful bridge to the host: it adds a `bitbanger` image device, and MAME
reads bytes from that stream into the VT100 while writing bytes transmitted by
the VT100 back to the same stream.

The `null_modem` defaults are 9600 baud, 8 data bits, no parity, 1 stop bit,
and no flow control. Match the VT100 SET-UP B transmit and receive speeds to the
host-side settings. To change the MAME-side serial format or enable XON/XOFF
flow control, open MAME's Machine Configuration menu while the emulator is
running and edit the RS-232 null modem settings.

To play back a VT100 animation file through the serial port, mount the animation
file as the bitbanger stream:

```bat
cd /d <MAMEDir>
mame.exe vt100 -rompath roms -window -rs232 null_modem -bitbanger "<AnimationFile>"
```

If playback overruns the terminal, enable XON/XOFF flow control for the
`null_modem` device or lower the receive speed in both MAME and the VT100 setup.

To connect the emulated terminal to a physical serial port on the Windows host,
configure the host port first, then use the Windows device path as the
bitbanger stream:

```bat
mode <COMPort>: BAUD=9600 PARITY=N DATA=8 STOP=1
cd /d <MAMEDir>
mame.exe vt100 -rompath roms -window -rs232 null_modem -bitbanger \\.\<COMPort>
```

For example, use `<COMPort>` values like `COM1` or `COM3`. The `\\.\COMx` form
also works for ports numbered `COM10` and higher.

To make the terminal reachable from a local telnet client, use a socket
bitbanger stream:

```bat
cd /d <MAMEDir>
mame.exe vt100 -rompath roms -window -rs232 null_modem -bitbanger socket.127.0.0.1:20000
```

Then connect from another terminal:

```bat
telnet 127.0.0.1 20000
```

The socket is a raw serial byte stream, not a Telnet protocol server. A telnet
client is fine for simple local typing, but a client with a raw TCP mode avoids
Telnet option-negotiation bytes if those become visible on the VT100.

### Connecting to SIMH

[OpenSIMH](https://github.com/open-simh/simh) can move a simulated machine's console
from the SIMH process window to a TCP port. Add these commands to the SIMH
setup file, using any unused local TCP port:

```text
set console telnet=<SIMHPort>
set console telnet=buffered
```

Start SIMH first and wait for it to listen on the console port. Then start MAME
and connect the VT100 serial port to that socket:

```bat
cd /d <MAMEDir>
mame.exe vt100 -rompath roms -window -rs232 null_modem -bitbanger socket.127.0.0.1:<SIMHPort>
```

When the VT100 completes self-test, start or boot the simulated machine from
the SIMH command prompt. The simulated machine's console I/O will appear on the
MAME VT100. If the SIMH setup file boots automatically before MAME connects,
either enable console buffering as shown above or move the boot command later so
the VT100 is connected before the operating system starts writing to the
console.

Some SIMH machines also have terminal multiplexer devices for additional login
lines. The device name depends on the simulated hardware. For example, a PDP-11
configuration using a DZ11-style multiplexer can listen for terminal
connections like this:

```text
set dz lines=8
attach dz <SIMHPort>
```

Connect MAME to that port with the same `-rs232 null_modem -bitbanger
socket.127.0.0.1:<SIMHPort>` command. The simulated operating system must also
be configured to use that terminal line.

### Connecting to the Internet

MAME's socket bitbanger can open a raw outbound TCP connection, but it is not a
Telnet or SSH client. For BBSs or remote hosts, run a local bridge program that
looks like a modem to the VT100 and connects to the remote site from the host
machine.

With [`tcpser`](https://github.com/go4retro/tcpser), start a virtual modem on a
local TCP port:

```bat
tcpser -v 25232 -s 9600 -l 4
```

Then connect MAME to it:

```bat
cd /d <MAMEDir>
mame.exe vt100 -rompath roms -window -rs232 null_modem -bitbanger socket.127.0.0.1:25232
```

From the VT100, type `AT` and expect `OK`, then dial a site:

```text
ATDT bbs.example.com:23
```

`tcpser` handles Telnet negotiation for Telnet services. It does not provide an
SSH client.

Windows bridge programs such as
[InternetModem](https://github.com/tolsen64/InternetModem) and
[ModemBridge](https://sourceforge.net/projects/atari-usb-modem/) can be used
the same way if they provide a TCP listener for the emulated serial side. If
the bridge only talks to a Windows COM port, create a virtual null-modem
COM-port pair, configure the bridge for one port, and connect MAME to the
other:

```bat
cd /d <MAMEDir>
mame.exe vt100 -rompath roms -window -rs232 null_modem -bitbanger \\.\<COMPort>
```

[InternetModem](https://github.com/tolsen64/InternetModem) provides
Hayes-style `ATDT <host>[:port]` dialing for Telnet.
[ModemBridge](https://sourceforge.net/projects/atari-usb-modem/) is the bridge
to try when the remote side requires SSH.

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
- [MAME and SIMH](https://wiki.mamedev.org/index.php/MAME_and_SIMH)
- [OpenSIMH Source Repository](https://github.com/open-simh/simh)
- [tcpser](https://github.com/go4retro/tcpser)
- [InternetModem](https://github.com/tolsen64/InternetModem)
- [ModemBridge 2k26](https://sourceforge.net/projects/atari-usb-modem/)
