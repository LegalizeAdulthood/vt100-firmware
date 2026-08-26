# VT100 ROM Options For Modified Firmware

This note summarizes the ROM devices and adapter boards that are useful when
installing modified VT100 firmware. It is written for two common jobs:

- Replace terminal-controller program ROM blocks with modified 2K images that
  contain trampoline hooks.
- Add an 8K AVO program expansion ROM for extension code.

The important distinction is that the original VT100 terminal controller does
not use plain JEDEC EPROM sockets for its four 2K program ROMs. It uses
8316E/2316E-style mask ROM sockets with programmable chip-select polarity. A
bare 2716 is therefore not a safe drop-in replacement for those main-board
2K sockets. Use an adapter unless the board was specifically wired or modified
for the EPROM.

## References

- DEC, [`EK-VT100-TM-003_VT100_Technical_Manual_Jul82.pdf`](https://bitsavers.org/pdf/dec/terminal/vt100/EK-VT100-TM-003_VT100_Technical_Manual_Jul82.pdf)
  - Section 4.1.5.2: program ROM is 8K x 8, originally four 2K packages,
    later possibly one 8K package.
  - Section 4.2.5: terminal-controller memory devices and ROM decoding.
  - Table 4-2-1: 2K ROM chip-select addressing.
  - Table 5-7: terminal-controller ROM part numbers.
  - Section 6.2.3: AVO program memory expansion.
  - Table 5-9: AVO ROM sets.
- DEC, [`MP00633_VT100_Schematic_Feb82.pdf`](https://bitsavers.org/pdf/dec/terminal/vt100/MP00633_VT100_Schematic_Feb82.pdf)
  - Sheet 2 of 6 shows the original four 8316E program ROMs.
- Adapter home pages are linked in the adapter section below.

## Quick Choices

Use these as starting points:

| Goal | Recommended approach |
| --- | --- |
| Replace one or more original 2K main-board ROMs | Use a configurable 23XX/2316 adapter in each changed socket. Program each 2K image into the adapter's EPROM/EEPROM, repeating the image if the memory device is larger. |
| Replace all main-board ROMs on a later single-8K configuration | Use a 2364/2664-compatible 24-pin 8K carrier or adapter. Program the combined 8K image. |
| Add an AVO expansion ROM | Configure the AVO for an 8K ROM at either `8000h-9fffh` or `a000h-bfffh` in socket `E8`. Use a 2364/2664-compatible 24-pin 8K carrier or adapter. Program the expansion image linked for that address range. |

## Main Board Program ROMs

The terminal-controller program ROM occupies `0000h-1fffh`. Original boards
use four 2K x 8 packages. Later boards may use one 8K x 8 package. The VT100
self-test still checks the firmware as four 2K blocks even when a later board
uses one 8K device.

### Original Four 2K x 8 Version

The schematic labels the four original program ROM packages as 8316E devices
at `E42`, `E45`, `E52`, and `E56`. The four sockets share the data bus and
address lines `A0-A10`; lines `A11` and `A12` select the active 2K block by
feeding programmable chip-select inputs rather than by acting as address lines
inside each ROM.

The DEC technical manual's Table 5-7 gives these base VT100 ROM part numbers:

| Address range | DEC ROM name | DEC part number |
| --- | --- | --- |
| `0000h-07ffh` | ROM 0 | `23-031E2` or `23-061E2` |
| `0800h-0fffh` | ROM 1 | `23-032E2` |
| `1000h-17ffh` | ROM 2 | `23-033E2` |
| `1800h-1fffh` | ROM 3 | `23-034E2` |

This repository uses the newer ROM 0 image, `23-061E2.bin`, when splitting
or building stock-compatible VT100 firmware.

The MAME-oriented filenames used by this repository for the stock ROM blocks
are:

| Build artifact | MAME ROM filename |
| --- | --- |
| `23-061E2.bin` | `23-061e2-00.e56` |
| `23-032E2.bin` | `23-032e2-00.e52` |
| `23-033E2.bin` | `23-033e2-00.e45` |
| `23-034E2.bin` | `23-034e2-00.e40` |

Note the physical schematic and emulator ROM suffixes are not a perfect
silkscreen guide. Use the actual board reference designator when inserting
parts in a real terminal.

#### 2K Main-Board Socket Pinout

This is the 24-pin 8316E/2316E-family pinout used by the original main-board
2K ROM sockets. It is also the pinout DEC documents for the Intel 2316E
equivalent alternate character ROM.

| Pin | 8316E/2316E signal | VT100 main-board use | Standard 2716 signal |
| --- | --- | --- | --- |
| 1 | `A7` | ROM address `A7` | `A7` |
| 2 | `A6` | ROM address `A6` | `A6` |
| 3 | `A5` | ROM address `A5` | `A5` |
| 4 | `A4` | ROM address `A4` | `A4` |
| 5 | `A3` | ROM address `A3` | `A3` |
| 6 | `A2` | ROM address `A2` | `A2` |
| 7 | `A1` | ROM address `A1` | `A1` |
| 8 | `A0` | ROM address `A0` | `A0` |
| 9 | `D0` | Data bit 0 | `D0` |
| 10 | `D1` | Data bit 1 | `D1` |
| 11 | `D2` | Data bit 2 | `D2` |
| 12 | `GND` | Ground | `GND` |
| 13 | `D3` | Data bit 3 | `D3` |
| 14 | `D4` | Data bit 4 | `D4` |
| 15 | `D5` | Data bit 5 | `D5` |
| 16 | `D6` | Data bit 6 | `D6` |
| 17 | `D7` | Data bit 7 | `D7` |
| 18 | `CS2` | One A11/A12-derived select input | `/CE` |
| 19 | `A10` | ROM address `A10` | `A10` |
| 20 | `CS1` | Common ROM enable | `/OE` |
| 21 | `CS3` | One A11/A12-derived select input | `VPP`, tied to +5 V for read |
| 22 | `A9` | ROM address `A9` | `A9` |
| 23 | `A8` | ROM address `A8` | `A8` |
| 24 | `VCC` | +5 V | `VCC` |

The table shows why a bare 2716 is not a drop-in main-board replacement:
pin 21 is `VPP` on a 2716, but the VT100 original socket drives it as a
chip-select input. A 2716 or 27C16 is a good programmable source part only
when an adapter converts the VT100's select signals into the EPROM's `/CE`
and `/OE`, and ties `VPP` to +5 V.

#### 2K Main-Board Chip-Select Polarity

The terminal selects the four 2K blocks by ordering each mask ROM with a
different `CS2`/`CS3` polarity. The common `CS1` line enables the ROM group.

| `A11` | `A12` | Required `CS2` polarity | Required `CS3` polarity | Selected 2K block |
| --- | --- | --- | --- | --- |
| 0 | 0 | Active low | Active low | ROM 0 |
| 1 | 0 | Active high | Active low | ROM 1 |
| 0 | 1 | Active low | Active high | ROM 2 |
| 1 | 1 | Active high | Active high | ROM 3 |

#### 2K Main-Board Programmable Replacements

Use these as source devices behind a 2316/8316E adapter. They are not bare
drop-ins for the original main-board sockets unless the terminal board or the
replacement PCB explicitly converts the chip-select pins.

| EPROM/EEPROM family | Capacity and package | Direct original socket fit? | How to use |
| --- | --- | --- | --- |
| `2716`, `27C16`, Intel-compatible 2K x 8 EPROMs | 2K x 8, 24-pin | No, not as a bare EPROM | Use a 2316/8316E adapter that maps `CS1`/`CS2`/`CS3` to `/CE` and `/OE`, and ties `VPP` to +5 V. |
| `2732`, `27C32` | 4K x 8, usually 24-pin | No | Use only with an adapter that supports 2732 pinout and bank selection; repeat or place the 2K image in the selected half. |
| `2764`, `27C64`, `28C64`, `AT28C64B` | 8K x 8, usually 28-pin or SOIC-28 | No | Use a configurable 23XX adapter in 2316 mode; repeat the 2K image four times or strap the extra address lines. |
| `27128`, `27C128`, `27256`, `27C256` | 16K/32K x 8, 28-pin | No | Use a configurable 23XX adapter in 2316 mode; repeat the 2K image or strap the extra address lines to the selected bank. |

For modified firmware with trampoline hooks, replace only the 2K images that
changed. A modified build may touch any subset of the four logical 2K blocks;
compare the output images with the stock ROMs before deciding which physical
parts need replacement.

### Later Single 8K x 8 Main-Board Version

The technical manual says later VT100s may use a single 8K x 8 ROM. In that
arrangement `A11` and `A12` are regular address lines, and only one chip-select
line enables the device. The manual also notes jumpers `W2` and `W3` on later
boards for selecting high- or low-asserted common chip select.

The compatible socket family is the 24-pin 2364/2664-style 8K x 8 mask ROM
pinout. DEC mentions the same Signetics 2664 type for the AVO 8K socket; other
common names for this 24-pin 8K family include MK36000-style 2364 ROMs.
Pin-compatible 24-pin EPROMs are uncommon, but Motorola `MCM68764` and
`MCM68766` parts are examples. Ordinary 2764/27C64/27C128/27C256 EPROMs are
28-pin JEDEC parts and require an adapter.

#### 8K 2364/2664 Pinout

| Pin | 2364/2664 signal | VT100 use |
| --- | --- | --- |
| 1 | `A7` | ROM address `A7` |
| 2 | `A6` | ROM address `A6` |
| 3 | `A5` | ROM address `A5` |
| 4 | `A4` | ROM address `A4` |
| 5 | `A3` | ROM address `A3` |
| 6 | `A2` | ROM address `A2` |
| 7 | `A1` | ROM address `A1` |
| 8 | `A0` | ROM address `A0` |
| 9 | `D0` | Data bit 0 |
| 10 | `D1` | Data bit 1 |
| 11 | `D2` | Data bit 2 |
| 12 | `GND` | Ground |
| 13 | `D3` | Data bit 3 |
| 14 | `D4` | Data bit 4 |
| 15 | `D5` | Data bit 5 |
| 16 | `D6` | Data bit 6 |
| 17 | `D7` | Data bit 7 |
| 18 | `A11` | ROM address `A11` |
| 19 | `A10` | ROM address `A10` |
| 20 | `CS` or `/CS` | Single ROM enable; polarity depends on part and jumpers |
| 21 | `A12` | ROM address `A12` |
| 22 | `A9` | ROM address `A9` |
| 23 | `A8` | ROM address `A8` |
| 24 | `VCC` | +5 V |

DEC's service documentation still identifies the firmware contents as four
logical 2K ROM blocks. A later single-package board holds the same 8K program
image in one physical ROM, so a modified build should use the combined 8K
image rather than four separately inserted 2K parts.

#### 8K Main-Board Programmable Replacements

| EPROM/EEPROM family | Capacity and package | Direct 2364/2664 socket fit? | How to use |
| --- | --- | --- | --- |
| `MCM68764`, `MCM68766` | 8K x 8, 24-pin EPROM | Potentially, if select polarity and speed match | Program the combined 8K image; confirm the terminal's common-select jumper and the part's enable polarity. |
| `2764`, `27C64`, `28C64`, `AT28C64B` | 8K x 8, 28-pin or SOIC-28 | No | Use a 2364/2664 carrier or adapter, then program the combined 8K image. |
| `27128`, `27C128` | 16K x 8, 28-pin | No | Use a 2364/2664 adapter; repeat the 8K image twice or strap the extra address line. |
| `27256`, `27C256` | 32K x 8, 28-pin | No | Use a 2364/2664 adapter; repeat the 8K image four times or strap the extra address lines. |
| `2732`, `27C32` | 4K x 8, 24-pin | No | Too small for the single 8K main-board image and not pin-compatible with a 2364/2664 socket. |

## AVO Board Program ROMs

The AVO adds RAM and also provides sockets and decoders for program memory
patching, overlay, and expansion. Section 6.2.3 of the technical manual is the
key table for configuring these sockets.

### AVO 2K Patch Or Expansion Sockets

DEC documents the 2K AVO program sockets as compatible with Intel 2716 or
2316E devices. These are different from the original main-board 2K sockets:
the AVO patch sockets are explicitly intended to accept Intel 2716 EPROMs.

| Address range | Purpose | Socket | Device type |
| --- | --- | --- | --- |
| `0000h-07ffh` | Patch base ROM A | `E19` | Intel 2716 or 2316E |
| `0800h-0fffh` | Patch base ROM B | `E17` | Intel 2716 or 2316E |
| `1000h-17ffh` | Patch base ROM C | `E13` | Intel 2716 or 2316E |
| `1800h-1fffh` | Patch base ROM D | `E8` | Intel 2716 or 2316E |
| `8000h-87ffh` | 2K expansion | `E19` | Intel 2716 or 2316E |
| `8800h-8fffh` | 2K expansion | `E17` | Intel 2716 or 2316E |
| `9000h-97ffh` | 2K expansion | `E13` | Intel 2716 or 2316E |
| `9800h-9fffh` | 2K expansion | `E8` | Intel 2716 or 2316E |

Common programmable choices are `2716` and `27C16` family EPROMs with the
Intel 2716 read-mode pinout. Larger EPROMs require an adapter and explicit
bank selection; they should not be plugged directly into these 2K AVO sockets.

When using 2K AVO expansion sockets, each socket can either patch or expand;
it cannot do both at the same time.

#### AVO 2716 Pinout

| Pin | 2716 signal | AVO 2K socket use |
| --- | --- | --- |
| 1 | `A7` | ROM address `A7` |
| 2 | `A6` | ROM address `A6` |
| 3 | `A5` | ROM address `A5` |
| 4 | `A4` | ROM address `A4` |
| 5 | `A3` | ROM address `A3` |
| 6 | `A2` | ROM address `A2` |
| 7 | `A1` | ROM address `A1` |
| 8 | `A0` | ROM address `A0` |
| 9 | `D0` | Data bit 0 |
| 10 | `D1` | Data bit 1 |
| 11 | `D2` | Data bit 2 |
| 12 | `GND` | Ground |
| 13 | `D3` | Data bit 3 |
| 14 | `D4` | Data bit 4 |
| 15 | `D5` | Data bit 5 |
| 16 | `D6` | Data bit 6 |
| 17 | `D7` | Data bit 7 |
| 18 | `/CE` | Chip enable |
| 19 | `A10` | ROM address `A10` |
| 20 | `/OE` | Output enable |
| 21 | `VPP` | +5 V in read mode |
| 22 | `A9` | ROM address `A9` |
| 23 | `A8` | ROM address `A8` |
| 24 | `VCC` | +5 V |

### AVO 8K x 8 Expansion Socket

For a single 8K AVO expansion ROM, DEC specifies socket `E8` and the Signetics
2664 type. This is the same 24-pin 2364/2664-style pinout shown above for the
later single-8K main-board case.

The AVO can decode the 8K socket in two useful locations:

| Address range | Socket | Device type | Notes |
| --- | --- | --- | --- |
| `8000h-9fffh` | `E8` | Signetics 2664 / 2364-style 8K x 8 | Convenient default for expansion code linked at `8000h`. |
| `a000h-bfffh` | `E8` | Signetics 2664 / 2364-style 8K x 8 | Alternative 8K expansion region. |

Compatible programmable choices for the AVO 8K ROM are the same as for the
later single-8K main-board socket:

| EPROM/EEPROM family | AVO `E8` fit? | Notes |
| --- | --- | --- |
| `MCM68764`, `MCM68766` | Potential direct 24-pin fit | Confirm active-low or active-high select configuration and access time. |
| `2764`, `27C64`, `28C64`, `AT28C64B` | Adapter required | Use a 2364/2664 carrier or adapter. |
| `27128`, `27C128`, `27256`, `27C256` | Adapter required | Use a 2364/2664 adapter and repeat or bank-select the 8K image. |
| `2732`, `27C32` | No | These are 4K devices and are not pin-compatible with the AVO 8K 2364/2664 socket. |

The manual states the AVO program memory parts must have 350 ns maximum access
time for the documented configurations. Modern CMOS EPROMs and EEPROMs are
usually much faster, but always check the specific part.

Choose one decoded range and link or assemble the expansion code for that
range. If the base terminal-controller ROMs contain trampoline hooks into the
AVO ROM, those hook targets must match the selected AVO address range.

## Modern PCB Adapters

### RETRO Innovations 23XX Adapter

Home page: [RETRO Innovations 23XX Adapter](https://www.go4retro.com/products/23xx-adapter/)

This adapter converts a 28-pin JEDEC EPROM, EEPROM, or flash ROM into 2316,
2332, or 2364-style 24-pin sockets. It includes configurable handling for
active-high and active-low select lines and uses a 74HCT138 to decode the
possible 23XX chip-select combinations.

How it applies:

- Original main-board 2K ROMs: good choice. Configure each adapter for the
  2316-style select polarity required by the target 2K block.
- Later main-board 8K ROM: configure as 2364 with the correct `/CS` or `CS`
  polarity.
- AVO 8K expansion at `E8`: configure as 2364. For a larger EPROM or EEPROM,
  repeat the 8K image or strap the extra address lines to one bank.

### Retro Electronics 23XX EPROM Adapter Board

Home page: [Retro Electronics 23XX EPROM adapter board](https://myretrostore.co.uk/product/23xx/)

This is another 23XX adapter for using 28-pin EPROMs in 2316, 2332, and 2364
sockets. The product page explicitly mentions using newer EEPROMs or older
28-pin EPROMs such as 27C128 and 27C256.

How it applies:

- Original main-board 2K ROMs: suitable when configured for the correct 2316
  chip-select polarity.
- Later main-board 8K ROM and AVO `E8`: suitable when configured as 2364
  active-low or active-high, matching the VT100/AVO jumper selection.

### One ROM

Home page: [One ROM](https://github.com/piersfinlayson/one-rom)

One ROM is a software-defined ROM replacement with 24-pin and 28-pin variants.
Its documentation lists support for 2316, 2332, 2364, 2716, 2732, 2764,
27128, 27256, and other related devices.

How it applies:

- Original main-board 2K ROMs: potentially useful with the 24-pin hardware
  variant configured as the required 2316 block.
- Later main-board 8K ROM and AVO `E8`: potentially useful when configured as
  a 2364/2664-style 8K ROM.

Check One ROM's programming and electrical notes before using it in an EPROM
programmer or a socket with non-5 V programming pins.

### PCBWay 2364/2332/2316 Universal Re-Programmable Replacement ROM

Home page: [Version 2: 2364 2332 2316 Universal Re-Programmable Replacement ROM](https://www.pcbway.com/project/shareproject/Version_2_2364_2332_2316_Universal_Re_Programmable_Replacement_ROM_c2f82c1c.html)

This shared PCB uses 28C64 or 28C256 EEPROMs and presents a configurable
2316/2332/2364-compatible 24-pin replacement. The board uses solder jumpers
for chip-select polarity and pinout selection. It requires the matching
programming adapter if you want to program the soldered EEPROM with a TL866 or
similar programmer.

How it applies:

- Original main-board 2K ROMs: suitable when configured for the target 2316
  chip-select polarity and programmed with the selected 2K image repeated to
  fill the EEPROM as needed.
- Later main-board 8K ROM and AVO `E8`: suitable in 2364 mode.

### pdaehne 2332/2364 EPROM Adapter

Home page: [pdaehne 2332-2364 EPROM Adapter](https://github.com/pdaehne/2332-2364-EPROM-Adapter)

This KiCad project provides Gerbers for replacing 2332 and 2364 ROMs with
2764, 27128, 27256, or 27512 EPROMs. The README says the 2364 use case is the
tested one.

How it applies:

- Later main-board 8K ROM: suitable for a 2364/2664-style socket if the
  select polarity matches the board configuration.
- AVO `E8`: suitable for the 8K AVO expansion socket.
- Original main-board 2K ROMs: not the right adapter family because it does
  not target 2316 sockets.

### RetroStack 2332/2364 ROM Adapter

Home page: [RetroStack 2332/2364 ROM Adapter](https://github.com/RetroStack/2332_2364-ROM_Adapter)

This is a compact 2332/2364 adapter. Its documentation lists a default 2364
active-low configuration and an optional active-high 2364 configuration using
an inverter.

How it applies:

- Later main-board 8K ROM: suitable for 2364/2664-style use.
- AVO `E8`: suitable for the 8K AVO expansion socket.
- Original main-board 2K ROMs: not the right adapter family because it does
  not target 2316 sockets.

### NEAT 2364

Home page: [NEAT 2364](https://lectronz.com/products/neat-2364-reprogrammable-24pin-rom-replacement)

The NEAT 2364 is a compact 24-pin replacement built around a modern EEPROM.
The product page describes it as a replacement for 2316, 2332, and 2364 mask
ROMs, but its compatibility notes emphasize systems with active-low chip
select and call out active-high select systems as incompatible.

How it applies:

- Later main-board 8K ROM: suitable only if the VT100 common select is
  configured active-low.
- AVO `E8`: suitable only if the AVO 8K select is configured active-low.
- Original main-board 2K ROMs: use caution. The four stock main-board blocks
  require different chip-select polarities, so a simple active-low-only
  replacement is not generally sufficient.

## VT100-Hax ROM Carrier

Repository: [LegalizeAdulthood/VT100-Hax](https://github.com/LegalizeAdulthood/VT100-Hax)

Local files:

- `VT100-Hax/ROM-Carrier/24dip-8k.sch`
- `VT100-Hax/ROM-Carrier/24dip-8k.brd`
- `VT100-Hax/ROM-Carrier/eeprom.lbr`

The VT100-Hax carrier is an Eagle design for an 8K x 8 24-pin ROM carrier. It
uses an AT28C64B EEPROM in an SOIC-28 package and adapts it to a 24-pin header.
The schematic maps `A0-A12` and `D0-D7` to the carrier header, brings the
socket select into the EEPROM `/CE`, pulls `/WE` inactive, and exposes the
control lines on pads.

In practical terms, it behaves like an active-low 2364/2664-style 8K ROM
replacement using a modern 8K EEPROM.

VT100 sockets that can use it:

| Socket/use | Can use VT100-Hax carrier? | Notes |
| --- | --- | --- |
| Later single-8K terminal-controller ROM | Yes, if the board is configured for active-low common select | Program the combined 8K main ROM image. |
| AVO `E8` as 8K expansion at `8000h-9fffh` | Yes, if the AVO is configured for active-low 8K select | Program an 8K expansion image linked for `8000h-9fffh`. |
| AVO `E8` as 8K expansion at `a000h-bfffh` | Yes, if active-low and the code is linked for that address | Program an 8K expansion image linked for `a000h-bfffh`. |
| Original four 2K terminal-controller ROM sockets | No, not as-is | Those sockets use 2316/8316E chip-select polarity per 2K block, not a straight 8K addressable 2364 footprint. |
| AVO 2K patch sockets `E19`, `E17`, `E13`, `E8` | No, not as-is | Those positions are for 2716/2316E 2K devices when used as 2K patch or expansion sockets. |

## Programming Notes

### 2K Images On Larger Devices

When using a larger EPROM/EEPROM behind a 2316 adapter, either strap the
unused address lines to select the desired bank or repeat the 2K image through
the entire device. Repetition is simple and avoids surprises if a high address
line floats or is jumper-selectable.

Examples:

| Device | Capacity | Repetitions for a 2K image |
| --- | --- | --- |
| 2716 / 27C16 | 2K | 1 |
| 2764 / 27C64 | 8K | 4 |
| 27128 / 27C128 | 16K | 8 |
| 27256 / 27C256 | 32K | 16 |

### 8K Images On Larger Devices

When using a larger EPROM/EEPROM behind a 2364 adapter, either strap the extra
address lines to one bank or repeat the 8K image through the entire device.

Examples:

| Device | Capacity | Repetitions for an 8K image |
| --- | --- | --- |
| MCM68764 / MCM68766 / 28C64 / AT28C64B | 8K | 1 |
| 27128 / 27C128 | 16K | 2 |
| 27256 / 27C256 | 32K | 4 |

### Generic Deployment Checklist

- Program changed main-board 2K images into 2316 adapters for the affected
  original main-board sockets.
- If using a later single-8K main-board ROM arrangement, program the combined
  8K main-board image instead.
- Program the AVO expansion image into a 2364/2664-style 8K AVO carrier or
  adapter in socket `E8`.
- Configure the AVO decode jumpers for the same range used when linking the
  expansion code.

The build system writes checksum bytes so the VT100 self-test still sees each
2K main-ROM block as checksum-clean.
