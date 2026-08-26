# VT100 AVO Superboard Design Notes

This note sketches a possible "AVO superboard": a modern board that installs
in the VT100 Advanced Video Option position, behaves like a stock AVO by
default, and then uses extra program memory, data memory, firmware hooks, and
local peripherals to make the VT100 extensible.

The core idea is not to turn the AVO position into a graphics board. Advanced
graphics, richer video generation, and video signal processing belong on a
modern STP/graphics-port option, following the architectural role played by
the VT125 graphics system. The AVO superboard should be the terminal-controller
extension board: ROM overlay, RAM, private control protocol, resident firmware,
diagnostics, and small peripherals.

## Scope

The AVO superboard should assume only the signals available at the AVO
connector. It should not require the graphics port connector, because other
VT100 options may already occupy that connector.

In scope:

- Stock AVO compatibility.
- Main ROM overlay or patching, as the original AVO option can provide.
- Extra AVO program memory and data memory.
- A documented extension ABI for code running from AVO memory.
- Private escape sequences that let the host communicate with the superboard.
- Downloadable resident code and data.
- SET-UP key bindings for local firmware entry points.
- Small firmware-visible peripherals such as an RTC, I2C accessory connector,
  enhanced sound, persistent settings, diagnostics, and trace support.

Out of scope for this board:

- HDMI, VGA, DVI, or composite output generated from graphics-port video
  signals.
- Pixel-perfect video capture.
- Direct access to the VT100 raw character-dot stream.
- Features that require H-sync, V-sync, or video from the graphics connector.
- Advanced vector/raster graphics. Those should be implemented by an STP and
  graphics-port board.

The superboard may still provide a host-side textual screen mirror by
shadowing CPU-visible screen and attribute memory, but that is a debugging and
inspection feature rather than a replacement video output.

## Design Principles

- Be stock-compatible after reset.
- Require an explicit opt-in before any private protocol or firmware extension
  changes visible terminal behavior.
- Keep normal VT100 escape sequences and SET-UP behavior intact unless a user
  deliberately binds an extension.
- Treat all extension behavior as discoverable through versioned capability
  tables.
- Preserve a recovery path that does not depend on valid uploaded code.
- Separate terminal-controller extensions from graphics-port extensions.
- Make uploaded code boring to call: fixed entry points, stable calling
  convention, and predictable ownership of registers and RAM.

## AVO Connector Capabilities

The AVO connector exposes the terminal-controller bus and several video-related
control signals. The exact electrical design needs to follow the DEC schematics,
but at the design level the important groups are:

| Group | Signals | Use |
|---|---|---|
| CPU address bus | `A00`-`A15` | Decode memory windows, ROM overlays, RAM, and control registers. |
| CPU data bus | `DB00`-`DB07` | Supply ROM/RAM data and accept writes. |
| Memory strobes | `MEM RD`, `MEM WR` | Participate in 8080 memory cycles. |
| AVO selection | `SEL ATT RAM`, `SEL 8-12K`, `MEM DISABLE`, `ADVANCED VIDEO` | Emulate the stock AVO memory map and option presence behavior. |
| DMA arbitration | `DMA ENA`, `HOLD REQ` | Respect display DMA and avoid corrupting bus ownership. |
| Line-buffer timing | `LBA0`-`LBA7`, `WRITE LB`, `CHAR CLK` | Observe or reproduce line-buffer and attribute timing behavior. |
| Attribute outputs | `BOLD`, `BLINK`, `UNDERLINE`, `ALT CHAR SET` | Provide stock AVO attribute effects. |
| Power | `+5V`, `GND` | Power input, likely with local regulation for modern logic. |

These signals make a superboard a good place for memory, ROM overlay, firmware
extension, and attribute behavior. They are not enough, by themselves, to make
a complete external video board.

## Compatibility Mode

The board should power up in a conservative compatibility mode that is
indistinguishable from a normal AVO to stock firmware.

Required behavior:

- Present the expected AVO option-detect state.
- Provide the stock AVO attribute RAM window at `3000h`-`3fffh`.
- Preserve 4-bit AVO RAM read behavior where stock firmware expects it.
- Maintain the normal active-low attribute interpretation:
  - bold
  - blink
  - underline
  - alternate character set
- Respect normal line attributes stored in the high nibble of DMA address
  bytes.
- Avoid changing stock cursor, SET-UP, keyboard, receiver, and vertical
  interrupt behavior unless the ROM overlay has deliberately installed hooks.
- Provide a hardware stock-mode jumper or switch that disables all overlays and
  extension decode except the minimum needed for normal AVO behavior.

The stock firmware and current emulator both rely on the idea that AVO RAM is
only four bits wide. Extra RAM may exist internally, but compatibility reads
from the stock AVO attribute range should still look like stock AVO reads.

## Main ROM Overlay

The original AVO can override or patch base-board ROM. The superboard should
use that capability as the foundation for a stable extension surface.

The overlay should be small and disciplined. It should not replace the terminal
firmware wholesale. Its job is to patch a small set of strategic locations so
the base firmware can call into AVO-resident code.

Useful overlay responsibilities:

- Detect and initialize the superboard.
- Install parser hooks for private control strings.
- Install SET-UP key dispatch hooks.
- Install idle-loop and periodic-service hooks.
- Install optional sound/status hooks.
- Expose a versioned trampoline table.
- Preserve displaced stock instructions for the normal path.
- Provide a recovery mode when the AVO firmware image or uploaded code is
  invalid.

The existing Invaders firmware model is the right shape: keep a tiny set of
fixed base-ROM calls, and put substantial behavior in the AVO ROM/RAM window.
The superboard should generalize that into an official ABI rather than
hard-coding one game.

## Extension Memory Map

The exact map is a hardware and firmware decision, but a useful logical model
is:

| Region | Purpose |
|---|---|
| `0000h`-`1fffh` | Base VT100 ROM, optionally patched or overlaid in small windows. |
| `2000h`-`2bffh` | Stock VT100 RAM and screen layout memory. |
| `3000h`-`3fffh` | Stock AVO attribute RAM behavior, plus carefully banked extension RAM. |
| `8000h`-`9fffh` | Primary AVO extension ROM window, matching the existing Invaders convention. |
| Optional banked window | Additional uploaded code, assets, diagnostics, and service firmware. |
| Control block | Board registers, mailbox, bank selectors, capability table, status, and error state. |

Several constraints follow from this:

- The stock attribute RAM view must remain available.
- Bank switching must not surprise stock firmware.
- Bank selectors should have both firmware-callable and host-protocol access.
- Uploaded code should be able to run from RAM, but a protected ROM monitor
  must always remain callable.
- Memory exposed through escape-sequence upload should include checksums and
  explicit execute permissions.

One practical layout is to make `8000h` contain an immutable monitor and ABI
jump table, while larger flash/RAM banks are selected behind another 8K window.
That keeps the entry points stable even when user payloads change.

## Private Host Protocol

The host should communicate with the superboard through private escape
sequences handled by the ROM overlay. This keeps the feature inside the normal
terminal data path: the host "prints" a control string, the terminal consumes
it, and the superboard performs the requested operation.

This replaces many jobs that might otherwise be assigned to a separate USB
debug link:

- Query board identity and capabilities.
- Read or write memory blocks.
- Upload code or data.
- Select banks.
- Bind or unbind SET-UP key handlers.
- Read and write persistent configuration.
- Read the RTC.
- Scan or access I2C devices.
- Play sound effects or upload sound banks.
- Start diagnostics.
- Retrieve logs, traces, or crash records.

### DCS Framing

Device Control String, DCS, is a good envelope for this protocol:

```text
ESC P ... ESC \
```

The 8-bit form is `0x90 ... 0x9c`, but the 7-bit `ESC P` and `ESC \` form is
friendlier to a VT100-era path.

The stock VT100 firmware does not provide a general DCS API for a superboard.
The ROM overlay would add private handling for these strings. Ordinary text and
ordinary VT100 escape sequences should continue through the normal parser.

Suggested command shape:

```text
ESC P $AVO;<command>;<arguments>:<payload> ESC \
```

Examples:

```text
ESC P $AVO;CAPS ESC \
ESC P $AVO;READ;bank=2;addr=9000;len=128 ESC \
ESC P $AVO;WRITE;bank=2;addr=9000;len=128;crc=4a31:<data> ESC \
ESC P $AVO;CALL;bank=2;addr=9000;mode=near ESC \
ESC P $AVO;BIND;key=I;bank=2;addr=9000;name=Invaders ESC \
ESC P $AVO;RTC;READ ESC \
ESC P $AVO;I2C;SCAN ESC \
ESC P $AVO;SOUND;TONE;hz=440;ms=120;vol=4 ESC \
```

### Payload Encoding

Raw binary payloads are tempting, but the serial path may not be perfectly
transparent:

- `ESC` conflicts with the string terminator prefix.
- XON/XOFF flow control may intercept `0x11` and `0x13`.
- NUL or DEL handling may vary by host software.
- Some communication paths normalize line endings.

For reliability, use printable encodings for bulk data:

- Hex for simplicity and easy debugging.
- Base64 or base85 for better density.
- Optional packet numbering for large uploads.

Every mutating packet should include:

- command name
- protocol version
- target bank
- target address
- payload length
- sequence number
- checksum or CRC
- commit/apply flag

The superboard should respond with private reports, for example:

```text
ESC P $AVO;OK;seq=12 ESC \
ESC P $AVO;ERR;seq=12;code=CRC ESC \
ESC P $AVO;DATA;seq=13;len=128:<encoded-data> ESC \
```

The exact response format can change, but responses should be parseable,
bounded, and versioned.

## Parser Hook

The parser hook should be narrow. It should recognize only the private prefix
and should leave all normal terminal behavior untouched.

Recommended parser behavior:

- Detect `ESC P` as a possible DCS.
- Buffer until `ESC \` or until a maximum length is exceeded.
- If the payload begins with the chosen private prefix, consume it and dispatch
  to the superboard protocol.
- If the payload is not private, either ignore it in a VT100-compatible way or
  fall back to stock behavior if such behavior exists.
- Abort cleanly on CAN, SUB, timeout, overflow, or malformed payload.
- Never let an unterminated private string wedge the terminal indefinitely.

The implementation should avoid doing expensive work directly inside receive
interrupt handling. The receiver path should buffer and flag work; the idle
path should parse, validate, and execute larger operations.

## SET-UP Key Binding

Unused SET-UP keystrokes are a good local launcher for AVO-resident firmware.
The host can upload code, install a binding, and then the operator can enter
that code directly from the terminal keyboard.

A binding table entry might contain:

| Field | Purpose |
|---|---|
| key | SET-UP key or key combination. |
| flags | Shift/control requirements, visibility, lock state, confirmation requirement. |
| bank | Code bank containing the handler. |
| entry | Handler address or trampoline index. |
| name | Short label for diagnostics or an enhanced SET-UP page. |
| checksum | Expected payload or handler checksum. |

Private protocol examples:

```text
ESC P $AVO;BIND;key=I;bank=2;addr=9000;name=Invaders ESC \
ESC P $AVO;BIND;key=T;vector=TRACE_VIEWER;name=Trace ESC \
ESC P $AVO;UNBIND;key=I ESC \
ESC P $AVO;BINDINGS? ESC \
```

Stock SET-UP actions must remain reserved. The binding system should avoid
overriding stock digits, cursor actions, reset/recall actions, and other known
SET-UP behaviors unless an explicit unsafe/development mode is enabled.

Handler entry should save and restore the normal terminal state unless the
handler declares that it will own the display. A game may own the screen until
exit; a small clock or diagnostic popup might save only the minimal state it
needs.

## Generalized Trampoline ABI

The superboard should formalize the Invaders-style trampolines into a generic
ABI for resident programs and board services.

Suggested fixed entry points in the immutable AVO ROM window:

| Entry | Purpose |
|---|---|
| `avo_reset` | Called after terminal reset or POST initialization. |
| `avo_caps` | Return board ID, firmware version, ABI version, and feature flags. |
| `avo_idle` | Called from the base firmware idle loop. |
| `avo_receiver_service` | Process buffered private host commands outside interrupt context. |
| `avo_setup_key` | Intercept candidate SET-UP keys and dispatch bindings. |
| `avo_sound_status` | Optionally contribute to the keyboard/speaker status byte. |
| `avo_enter_program` | Enter an uploaded or ROM-resident program. |
| `avo_exit_program` | Restore terminal state and return to ordinary operation. |
| `avo_call` | Call a banked handler through a descriptor. |
| `avo_error` | Report and recover from ABI, checksum, or handler failures. |

The existing Invaders-specific entries can then become one program using this
ABI rather than special-case firmware:

| Current idea | Generalized equivalent |
|---|---|
| `inv_enter` | Program descriptor `entry` or `start`. |
| `inv_idle` | Program descriptor `idle`. |
| `inv_exit` | Program descriptor `exit`. |
| `inv_idle_hook` | Base-ROM `avo_idle` trampoline. |
| `inv_setup_keys_hook` | Base-ROM `avo_setup_key` trampoline. |
| `inv_sound_status_hook` | Optional `avo_sound_status` service. |

### Calling Convention

The ABI should be written down in assembly-level terms:

- Which registers the caller saves.
- Which registers the callee may destroy.
- Whether interrupts are enabled or disabled on entry.
- Whether the callee may call stock firmware routines.
- How the callee returns an error.
- How banked calls preserve the previous bank.
- Which RAM ranges belong to the monitor, current program, and stock firmware.

A conservative convention:

- `AF`/`PSW`, `BC`, `DE`, and `HL` are caller-saved unless a specific entry
  says otherwise.
- Interrupts are enabled for normal idle/setup calls and disabled only for
  short critical sections.
- Long work must be split across idle calls.
- Handlers return with carry set on failure and `A` containing an error code.
- Banked calls restore the previous bank before returning.
- A handler that owns the screen must declare that ownership in its descriptor.

### Program Descriptor

Uploaded or ROM-resident programs should have a small descriptor, such as:

| Field | Purpose |
|---|---|
| magic | Identifies an AVO program. |
| abi_version | Minimum ABI version required. |
| program_version | User payload version. |
| flags | Screen ownership, sound use, I2C use, persistence use, etc. |
| init | Optional initialization entry. |
| start | Main entry when launched. |
| idle | Optional idle service while active. |
| key | Optional raw key handler. |
| escape | Optional private subcommand handler. |
| sound | Optional sound service. |
| exit | Cleanup entry. |
| required_caps | Feature bits required by the payload. |
| checksum | Descriptor and code checksum. |

This lets the monitor reject programs that require absent hardware.

## Resident Firmware Uses

Useful resident programs include:

- Games such as Invaders.
- Screen savers.
- Local clock/calendar display.
- Field diagnostics.
- Memory and bus exercisers.
- Character-set/font tools.
- I2C device browsers.
- Sound test and tune players.
- Host-uploaded terminal demos.
- A local monitor/debugger for VT100 firmware development.

The key distinction is that these run as terminal-local software. They are
not merely host applications drawing through escape sequences.

## RTC

A battery-backed real-time clock is a strong fit for the superboard.

Uses:

- Host-readable time and date.
- Local clock display from a SET-UP binding.
- Timestamped diagnostic logs.
- Persistent high-score timestamps.
- Time-based screen saver behavior.
- Manufacturing or maintenance record keeping.

Hardware recommendations:

- Use a low-power RTC with battery or supercapacitor backup.
- Keep the battery serviceable without removing the whole board, if practical.
- Include battery-good status.
- Protect against leakage damage with sane placement and chemistry choice.
- Expose calibration or trim only through explicit service commands.

Protocol examples:

```text
ESC P $AVO;RTC;READ ESC \
ESC P $AVO;RTC;SET;iso=2026-08-26T14:30:00-06:00 ESC \
ESC P $AVO;RTC;STATUS ESC \
```

The board can also provide a firmware-callable RTC service so local programs do
not need to know the RTC chip details.

## Qwiic/STEMMA QT Breakout

A rear breakout for Qwiic/STEMMA QT-style I2C accessories is a good way to add
small peripherals without consuming the graphics port.

The VT100 CPU should not need to bit-bang this bus directly. The superboard
controller should own the I2C bus and expose a transaction API through the
private protocol and the local firmware ABI.

Possible accessories:

- temperature, humidity, pressure, and light sensors
- accelerometers
- GPIO expanders
- rotary encoders
- small OLED displays
- EEPROMs
- IR receivers/transmitters
- real-time clock variants
- simple ADC/DAC modules

Hardware recommendations:

- Run the accessory bus at 3.3 V.
- Use level shifting between any 5 V logic and the accessory bus.
- Provide selectable or removable pull-ups.
- Add ESD protection on rear-facing pins.
- Use a current-limited load switch for accessory power.
- Provide firmware-controlled accessory power cycling.
- Keep cable length expectations modest.
- Include a way to disable the external connector for stock/recovery mode.

Protocol examples:

```text
ESC P $AVO;I2C;SCAN ESC \
ESC P $AVO;I2C;READ;addr=68;reg=00;len=7 ESC \
ESC P $AVO;I2C;WRITE;addr=3c;len=16:<encoded-data> ESC \
ESC P $AVO;I2C;POWER;state=off ESC \
ESC P $AVO;I2C;POWER;state=on ESC \
```

The ABI should also provide simple services:

- scan bus
- read register
- write register
- combined write/read transaction
- power-cycle accessories
- query bus fault state

## Enhanced Sound

The stock VT100 has keyboard click and bell behavior. A superboard can add
better local sound without touching the graphics port.

Useful sound tiers:

| Tier | Features |
|---|---|
| Compatibility | Preserve stock click and bell behavior. |
| Simple | Internal speaker, volume control, tone frequency, duration, mute. |
| PSG-like | Multiple square/noise channels, envelopes, simple mixer. |
| Sample | Short PCM or ADPCM playback from RAM or flash. |

Hardware possibilities:

- Small internal speaker or piezo.
- Low-power audio amplifier.
- Rear line-level or headphone-level output.
- Digital volume control.
- Optional mixer path for stock click/bell style events.

Firmware uses:

- Better bell.
- Key click variants.
- Game sound effects.
- Diagnostic tones.
- Alert sounds for host applications using private sequences.
- Small tune playback from uploaded data.

Protocol examples:

```text
ESC P $AVO;SOUND;MUTE;state=on ESC \
ESC P $AVO;SOUND;BELL;profile=soft ESC \
ESC P $AVO;SOUND;TONE;hz=880;ms=60;vol=5 ESC \
ESC P $AVO;SOUND;CHAN;id=0;wave=square;hz=220;env=fast ESC \
ESC P $AVO;SOUND;UPLOAD;slot=3;len=512;crc=9a12:<encoded-data> ESC \
ESC P $AVO;SOUND;PLAY;slot=3 ESC \
```

The default should be polite:

- stock sounds unless enhanced sound is enabled
- persistent mute
- bounded volume
- no sound during POST except explicit diagnostics
- a physical or SET-UP-accessible way to silence the board

## Persistent Storage

Some nonvolatile storage is useful even if the board has large flash for
firmware.

Recommended persistent items:

- board configuration
- protocol enable state
- SET-UP key bindings
- sound volume and mute
- RTC calibration
- uploaded program descriptors
- high scores or local program state
- diagnostic logs
- crash records

Use a protected layout:

- immutable boot/monitor bank
- updateable firmware bank
- user payload area
- configuration records with version and checksum
- log ring buffer

Updates should be transactional. A failed upload or power loss should not leave
the board unbootable.

## Diagnostics And Development

A superboard can make VT100 firmware development much easier.

Useful diagnostic features:

- Memory read/write through private protocol.
- Bus-cycle trace with address/data/control strobes.
- Trigger-on-address or trigger-on-write capture.
- Shadow screen and attribute RAM dump.
- AVO RAM test independent of stock POST.
- ROM checksum and bank inventory.
- Last-error register and crash record.
- Firmware self-test.
- I2C bus fault reporting.
- Sound test.
- RTC status and battery status.
- Human-visible diagnostic LEDs.

The bus trace should be bounded and opt-in. The VT100 bus is not a modern debug
fabric, and trace capture must not stretch cycles or contend with DMA unless
the hardware has been designed to do so safely.

Host protocol examples:

```text
ESC P $AVO;TRACE;ARM;addr=2050;mask=ffff;type=write;count=64 ESC \
ESC P $AVO;TRACE;READ ESC \
ESC P $AVO;MEM;DUMP;addr=2000;len=512 ESC \
ESC P $AVO;SCREEN;DUMP ESC \
ESC P $AVO;SELFTEST ESC \
```

## Hardware Architecture

A practical board likely wants two kinds of logic:

- A timing-critical programmable logic device for bus decode, ROM/RAM control,
  stock AVO behavior, and safe tri-state control.
- A microcontroller for protocol parsing assistance, I2C, RTC, sound assets,
  persistent storage, USB service mode if present, and slow diagnostics.

The programmable logic should own anything that must happen on the 8080 bus at
VT100 timing. The microcontroller should not be in the critical read path for
program ROM or RAM unless there is a proven wait-state or buffering strategy.

Hardware blocks:

- 5 V-tolerant bus transceivers.
- CPLD/FPGA/GAL-style decode and control.
- SRAM or FRAM for extension RAM.
- Flash for monitor, firmware banks, and user payloads.
- RTC with backup power.
- I2C accessory connector and protection.
- Audio generator/amplifier.
- Configuration switches.
- Recovery and write-protect jumpers.
- Diagnostic LEDs and test points.
- Optional internal service connector.

Important electrical rules:

- Default all bus drivers to high impedance until configured.
- Never fight the base board, display DMA, or another option.
- Treat active-low AVO signals explicitly in naming and schematics.
- Make stock compatibility work without the microcontroller firmware running,
  if practical.
- Regulate local 3.3 V loads from the available 5 V supply.
- Budget accessory and audio current conservatively.

## Security And Safety

The VT100 is not a secure computer, but the extension protocol can still avoid
easy accidents.

Recommended safeguards:

- Extension protocol disabled by default, or enabled only after a handshake.
- Physical jumper for protocol write enable.
- Separate enable for executing uploaded code.
- CRC/checksum on all uploads.
- Maximum payload size and timeout for string controls.
- Protected recovery monitor.
- Write-protected factory firmware bank.
- Binding table validation at boot.
- Clear error responses rather than silent failure.
- Optional "local only" mode that blocks host-initiated execution.

Uploaded code should not be able to overwrite the recovery monitor or brick the
stock AVO compatibility path.

## Advanced Graphics Boundary

It is worth making this boundary explicit in the design documentation:

- The AVO superboard extends terminal-controller firmware and memory.
- A graphics board extends display generation and graphics features.
- If a design needs video signals, it should use the STP and graphics port.
- If a design needs private firmware, memory, resident programs, or small
  peripherals, it is a good fit for the AVO superboard.

This mirrors the historical split. The AVO option provides attributes and
memory expansion. The VT125-style graphics system uses additional graphics
hardware and the graphics/video path.

The two board types could cooperate through private escape sequences and
well-documented firmware hooks, but neither should require the other's physical
connector.

## Implementation Phases

### Phase 1: Compatibility And Monitor

- Implement stock AVO attribute RAM behavior.
- Implement base ROM overlay detection.
- Add fixed monitor jump table at the AVO ROM base.
- Add capability query.
- Add recovery jumper behavior.
- Verify stock firmware self-test and normal terminal behavior.

### Phase 2: Private Protocol

- Add DCS-style private command parser.
- Implement capability, status, memory read, and memory write commands.
- Add checksummed block upload.
- Add error responses.
- Add persistent configuration records.

### Phase 3: General Trampolines

- Replace Invaders-specific hook assumptions with a generic ABI.
- Add idle hook.
- Add SET-UP key hook.
- Add optional sound/status hook.
- Add program descriptors.
- Port Invaders to run as one resident program using the generic ABI.

### Phase 4: Local Peripherals

- Add RTC.
- Add enhanced sound.
- Add I2C accessory connector.
- Add protocol and ABI services for each peripheral.
- Add basic SET-UP or resident diagnostic tools.

### Phase 5: Developer Tooling

- Add host-side uploader.
- Add binding manager.
- Add memory/screen dump tools.
- Add trace capture tools.
- Add firmware image packer and checksum generator.

## Open Questions

- Which exact private prefix should be used for DCS commands?
- Should the protocol be enabled by default, by SET-UP option, by jumper, or by
  host handshake?
- What maximum DCS payload length is safe in the patched firmware?
- Which base-ROM hooks are essential, and how many bytes can be patched without
  destabilizing stock firmware?
- Should uploaded code run only from RAM, only from flash, or both?
- How should bank switching interact with interrupts?
- What is the smallest useful monitor that can remain immutable?
- Which SET-UP keys are truly unused across VT100 variants and installed
  options?
- Should the sound system be a simple tone generator, a PSG-like engine, or a
  sample player?
- How much current can be safely reserved for rear I2C accessories?
- Should there be a separate service connector in addition to host escape
  sequences, or should the host protocol remain the only normal management
  path?

## Summary

The strongest AVO superboard is not a hidden graphics card. It is a clean,
recoverable extension environment for the VT100 terminal controller.

The board should boot as a faithful AVO, then expose a private, documented,
opt-in control surface:

- base ROM overlay hooks
- DCS-style private host protocol
- memory upload/download
- SET-UP key launch bindings
- generalized resident-program trampolines
- RTC
- Qwiic/STEMMA QT accessory I2C
- enhanced sound
- persistent configuration
- diagnostics and bus trace

That gives the VT100 a modern extension personality while respecting the old
option architecture: AVO for firmware and attributes, STP/graphics port for
advanced graphics and video.
