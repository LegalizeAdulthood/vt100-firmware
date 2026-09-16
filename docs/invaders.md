# VT100 Firmware Invaders Design

This note describes the current 8080 implementation of a Space Invaders-style game in
VT100 firmware, using [vtinvaders](https://github.com/j4james/vtinvaders) and
[ascii-invaders](https://github.com/macdice/ascii-invaders) as gameplay and
rendering references.

The base firmware ROM contains only same-size trampoline replacements for the
game hooks. The game code lives in the AVO program
expansion ROM window starting at `8000h`, while mutable game state lives at the
tail of byte-wide screen RAM, below `3000h`. Attribute RAM is not game storage.
While the game is active, it owns the 80-column display and unused screen-RAM
tail; normal terminal processing resumes on exit.
Returning to terminal mode clears the game display and restores the saved LED
and cursor rendition state; it does not restore the previous screen contents.

The implementation is in [invaders-avo.asm](../src/invaders-avo.asm), with the
base-ROM trampoline addresses in [invaders-abi.asm](../src/invaders-abi.asm).
The build and test definitions in [src/CMakeLists.txt](../src/CMakeLists.txt)
and [src/tests/CMakeLists.txt](../src/tests/CMakeLists.txt) are the authority for
target names, artifacts, and registered tests.

## Goals

- Keep the stock VT100 interrupt model intact.
- Use the vertical refresh interrupt as the frame clock, but run game logic from
  the idle path rather than inside the interrupt handler.
- Reuse the stock keyboard scan and key silo where possible.
- Write directly to VT100 screen RAM instead of emitting escape sequences.
- Avoid whole-screen redraws during play.
- Preserve the important pacing tricks from `vtinvaders`, especially moving one
  alien per frame.
- Borrow the stronger sprite silhouettes from `ascii-invaders`, but render them
  with the DEC Special Graphics character set.
- Use the keyboard LEDs to show the number of player gunners remaining.
- Use the VT100 keyboard click/bell bit for alien heartbeat and turret death
  sound effects.

## Reference Comparison

The two references solve different problems. `vtinvaders` is designed for DEC
VT-family terminals and is much closer to the firmware target. It has a small
fixed playfield, deterministic enemy firing, fixed missile slots, one active
player laser, direct dirty-cell rendering, and a shadow ID map for collisions.
Most importantly, it moves only one live alien per frame, so the formation
naturally speeds up as aliens are killed without needing to redraw the entire
matrix.

`ascii-invaders` is less suitable as a firmware architecture. It uses curses,
a realtime signal handler, heap allocation, linked-list bombs, and random bomb
drops. Those choices should not be copied into ROM. Its art direction is still
useful, though: two-line aliens, a chunky two-line gunner, a two-line mystery
ship, and a 7 by 3 shelter. The firmware version adapts those silhouettes using
DEC Special Graphics and ordinary ASCII; it does not use a downloadable font.

Adopted choices:

| Area | Adopt from | Reason |
|---|---|---|
| Main loop and frame clock | `vtinvaders` | Maps cleanly to `frame_count` and the firmware idle loop. |
| Alien movement | `vtinvaders` | One alien per frame is cheap and produces arcade-like speedup. |
| Enemy firing | `vtinvaders` | Fixed shoot order is deterministic and testable. |
| Missile storage | `vtinvaders` | Three fixed slots are simpler than linked-list bombs on 8080. |
| Collisions | Firmware implementation | Coordinate rectangles for entities and cell codes for shields; no active shadow ID map. |
| Alien, gunner, UFO, shelter silhouettes | `ascii-invaders` | Larger sprites read better on a VT100. |
| Actual sprite character set | VT100 firmware | DEC Special Graphics is native and already mapped by the ROM. |
| Formation bounds | `ascii-invaders` | Cached live edges avoid scanning empty margins every frame. |
| Shield shape | `ascii-invaders` | Four 7 by 3 shelters leave room for recognizable roofs and openings. |
| Shield durability | `vtinvaders` | Per-column damage drives full, damaged, weak, and empty cell appearances. |
| Enemy missile rendering | Firmware implementation | A fixed one-cell glyph keeps drawing inexpensive. |

The result is a hybrid: `vtinvaders` for behavior, `ascii-invaders` for the
visual language.

## Firmware Anchors

The stock firmware already provides the scheduling pieces needed by the game:

- `vertical_int` increments `frame_count` once per video refresh.
- `keyboard_int` reads `ior_keyboard` and queues scan codes in `key_silo`, with
  modifier state in `key_flags`.
- `keyboard_tick` calls `update_kbd`, processes keys, and pumps pending reports.
- `idle_loop` repeatedly calls `keyboard_tick` and `receiver_tick`.
- `line1_dma`, `pline_addr`, `latofs`, and the screen RAM tables define the
  visible display.
- `led_state` is ORed into the keyboard status byte by `update_kbd`, making the
  four keyboard LEDs available as a game status display.
- `kbd_click_mask` and `kbd_online_mask` are ORed into the keyboard status
  byte by `update_kbd`; the former is a one-shot keyclick latch and the latter
  carries the stock BEL bit pattern.
- Game sound trampolines the keyboard status-byte assembly path so
  Invaders can own only the click/bell bit while active and leave LEDs,
  local/online state, lock state, and scan-start behavior under stock control.

The game uses `inv_active == inv_active_value` (`5ah`) as its mode guard; a
nonzero byte alone does not mean game mode. The base ROM has too little slack
for inline game dispatch. Every Invaders change in `base.asm` must be a
same-size replacement of existing bytes with a call into the AVO ROM. The AVO
hook must repeat the displaced stock bytes on the normal terminal path and only
skip them when game mode owns control.

The idle-loop patch replaces the existing `call keyboard_tick` with
`call inv_idle_hook`:

```asm
idle_loop:
        call    inv_idle_hook       ; Invaders build only
        call    receiver_tick
        ; existing setup/local handling remains here
        jmp     idle_loop

inv_idle_hook_impl:
        lda     inv_active
        cpi     inv_active_value
        jz      inv_idle_active
        call    keyboard_tick       ; displaced base-ROM call
        ret

inv_idle_active:
        call    inv_idle
        pop     h                   ; discard return into terminal idle path
        jmp     idle_loop

inv_idle_impl:
        call    update_kbd          ; keep scan/status/click output alive
        call    inv_read_keys       ; consume raw game keys
        lda     inv_active          ; input may have requested exit
        cpi     inv_active_value
        rnz
        call    inv_wait_frame      ; wait for frame_count to change
        call    inv_frame
        ret
```

`vertical_int` should not run the game. It should continue to do short,
time-critical hardware work: finish line shuffles, clear the vertical interrupt,
advance smooth scroll state if any remains enabled, update bell/blink state,
start keyboard scan, increment `frame_count`, and refresh hardware output ports.

## SET-UP Entry

The game is entered from the VT100 SET-UP screen. The stock firmware path is a
good launcher because it already moves keypresses into local handling and
visibly tells the operator that they are leaving normal terminal use.

The existing flow is:

- the SET-UP key has scan code `7bh`;
- `setup_pressed` marks `pending_setup`;
- `idle_loop` notices `pending_setup` and calls `in_out_setup`;
- `enter_setup` saves `char_action` in `saved_action` and redirects received
  key actions to `setup_action`;
- `setup_action` dispatches digit keys through `setup_key_t` and non-digit
  SET-UP actions through `setup_keys`;
- `setup_keys` currently handles shifted `S`, `R`, and `A`.

Use `i` or `I` on the SET-UP screen as the Invaders launcher. Since the stock
`setup_keys` path normally rejects non-digit SET-UP actions unless SHIFT is
pressed, the base ROM patch replaces the existing `lda last_key_flags` bytes
with a same-size call into the AVO ROM before the SHIFT gate:

```asm
setup_keys:     call    inv_setup_keys_hook
                ani     key_flag_shift
                rz
                mov     a,b
                cpi     'S'
                jnz     try_recall
```

The AVO hook intercepts `i` and `I` first by clearing the ASCII lowercase bit
and comparing once against upper-case `I`. For normal SET-UP behavior, it
repeats the displaced `lda last_key_flags` so the base ROM can continue through
the stock SHIFT gate and shifted `S`, `R`, and `A` handling:

```asm
inv_setup_keys_hook:
                mov     a,b
                ani     0dfh            ; convert lower-case i to upper-case I
                cpi     'I'             ; i or I launches Invaders attract
                jz      inv_setup_start
                lda     last_key_flags  ; existing SET-UP actions continue
                ret
```

`setup_action` pushes `setup_ready` before dispatching a SET-UP key action.
`inv_setup_start` must not return through that path, because `setup_ready`
would re-register `setup_action` after the game has taken over. Discard that
synthetic return, leave SET-UP mode, restore the normal terminal dispatch state,
and then enter Invaders attract mode:

```asm
inv_setup_start:
        pop     h                   ; discard return to setup_keys
        pop     h                   ; discard setup_ready return address
        xra     a
        sta     in_setup
        call    inv_leave_setup_for_game
        jmp     inv_enter
```

`inv_leave_setup_for_game` lives in the AVO ROM and repeats the display and
dispatch restoration work from `exit_setup`: restore `char_action` from
`saved_action`, restore the saved cursor bookkeeping and `line1_dma`, clear
keyboard/report scratch state, and leave the normal terminal in a known state
before `inv_enter` takes over the screen. For game launch, it must not emit an
unsolicited DECREPTPARM report to the host.

The game exits to normal terminal mode. If the operator presses SET-UP while
the game is active, treat it the same way SET-UP behaves while the SET-UP
screen is visible: leave the special mode and return to normal terminal
operation.

```asm
inv_key_setup:
        call    inv_exit
        ret
```

SET-UP is the game exit key. There is no `q`/`Q` exit binding.

## Attract Mode

Launching Invaders from SET-UP enters attract mode first. Attract mode owns the
screen and keyboard, runs a deterministic demo game, and displays the title,
high-score table, and start prompt over the demo. Draw the overlay once, then
clip gameplay drawing and erasing to exclude the three overlay rectangles,
including their one-character box borders. Demo restarts also preserve these cells.
The shared renderer must leave them untouched so the overlay does not flicker
as objects move behind it. RETURN removes the overlay and disables clipping
when initializing the real game.

The demo reuses the same game state, frame clock, update
routines, and rendering paths as real gameplay. The demo driver waits for the
formation to finish spawning, then steers below the lowest live alien in the
leftmost occupied column. It fires when aligned and no player laser is active.
The driver only writes the existing input state bytes before the normal turret
and laser updates; it does not duplicate rendering or collision handling.

Pressing RETURN leaves attract mode and starts a fresh real game by running the
normal gameplay initialization path. Pressing SET-UP from attract mode exits
back to the terminal. Demo play must never prompt for initials, write high
scores, or persist anything to NVR.

The attract overlay text is:

```text
VT100 INVADERS

HIGH SCORES

PRESS ENTER
```

Each overlay element uses its one-character gutter for a box border drawn with
DEC Special Graphics line-drawing characters. The high-score table and start
prompt share a horizontal border with T-junctions at its ends. The high-score
table remains a fixed rectangle: empty entries draw spaces across their row so
moving gameplay cannot show through holes in the text area.

## Invaders ROM And AVO Memory Plan

Only trampoline entry points referenced by `base.asm` are shared through
`src/invaders-abi.asm`: idle dispatch, SET-UP launch, keyboard sound status,
reset-time high-score loading, and initials cursor handling. Private entry
points, constants, and state addresses stay in `src/invaders-avo.asm`.
The expansion ROM starts at `8000h`. AVO also supplies an additional 1 KiB of
byte-wide screen RAM at `2c00h`-`2fffh`, distinct from its four-bit attribute
RAM at `3000h`-`3fffh`. Game state grows downward from `2fffh`, with `2c00h`
as the allocation floor.

```asm
inv_avo_base    equ 8000h
inv_code_base   equ inv_avo_base
inv_code_top    equ 9fffh       ; 8 KiB AVO program expansion ROM

inv_screen_ram_start equ 2c00h
inv_screen_ram_top   equ 2fffh

inv_data_top    equ inv_screen_ram_top
inv_data_floor  equ inv_screen_ram_start
```

Keep new game code within the 8 KiB expansion window; changing the RAM layout
does not increase ROM capacity. Mutable storage is allocated with address
equates, not `db` or `ds` directives that would emit storage into the ROM image.

The current allocation occupies 647 bytes at `2d79h`-`2fffh`, including the
high-score cache and test state, leaving 377 bytes free above `2c00h`. The
80-column display plus its extra SET-UP row ends just before `2aebh`, so neither
overlaps game state. The unused object-map and dirty-queue reservations have
been removed; rendering and collisions do not use those buffers.

`inv_active` occupies `2fffh`, just beyond even the 132-column display and its
extra row. All other state may be overwritten by normal 132-column terminal
use and is reinitialized or reloaded on game entry. Inactive hooks do not write
diagnostic values into that screen area.

`inv_enter_impl` prepares the 80-column screen, saves and disables the terminal
cursor rendition, saves the LED state, reloads high scores from NVR, and enters
`inv_start_demo`. Shared initialization resets play state, starts with four
gunners at level 1, initializes shields and aliens, and draws the static screen.
The attract overlay is drawn before setting the active-mode guard.

`inv_exit_impl` hides an initials cursor if necessary, clears game-mode flags,
resets projectiles and sound, clears the playfield, and restores saved LED and
cursor rendition state. The SET-UP key path also clears the keyboard silo. The
prior terminal screen and prior 132-column layout are not saved and restored.

### Hardware RAM Constraint

All mutable game state must remain in byte-wide screen RAM, not four-bit
attribute RAM. Existing nibble pairs and cell codes remain unchanged, but
full-byte flags, coordinates, and timers now use physical byte-wide storage.
Static layout tests enforce the screen-RAM bounds and non-overlap with display
storage. MAME tests restrict attribute reads/writes to four writable bits so
the emulator's byte-wide mapping cannot conceal another allocation error.

## Frame Clock

`inv_wait_frame` waits for `frame_count` to differ from `inv_last_vframe`,
calling `update_kbd` while waiting so keyboard status and sound keep flowing.
It then records the refresh marker and advances the logical game counter once.

Despite its historical name, `inv_inc_frame16` maintains an eight-bit counter
in two four-bit locations, `inv_frame_lo` and `inv_frame_hi`. It carries at 16,
uses descending addresses, and wraps after 256 frames. Longer gameplay timers
have their own state; they do not rely on a 16-bit global frame count.

Timers use refresh frames without 50 Hz compensation. The same frame counts
therefore take longer in wall-clock time on a 50 Hz terminal.

## Main Game Loop

`inv_frame` checks the active guard, then dispatches attract mode to
`inv_demo_frame` or runs the optional test hook before `inv_play_frame`.
The shared play loop runs in this order:

1. Handle a pending level reset; pause ordinary updates while its timer runs.
2. Handle turret death or game over; pause ordinary updates during that state.
3. Call `inv_update_aliens` to spawn one alien or move one live alien.
4. Update heartbeat, UFO, and enemy fire, including active missiles.
5. Stop this frame if an enemy missile caused turret death or game over.
6. In attract mode, synthesize the demo's movement and fire input.
7. Update the turret, then the player laser.

The turret is drawn at initialization and real-game input is available while
the 44 aliens spawn. Enemy firing and the UFO countdown wait for spawn
completion; there is no additional `count + 73` start gate.

The last alien kill starts a 15-frame level pause. `inv_next_level` increments
the displayed level up to 9, resets aliens, enemy fire, sound, and UFO state,
and redraws the screen. It preserves score, remaining gunners, turret position,
and existing shield damage.

## Keyboard Handling

Gameplay input reads raw scan results, not normal translated terminal reports.
`keyboard_int` already queues up to four scan codes in `key_silo`; `update_kbd`
keeps the keyboard scan and LED/status write side alive.

`inv_read_keys` clears the movement/fire flags, then interprets the key silo:

| Key | Scan code | Gameplay action |
|---|---|---|
| RETURN | `04h` or `64h` | Start a fresh real game from attract mode |
| Left arrow | `20h` | Set `inv_left_pressed` |
| Right arrow | `10h` | Set `inv_right_pressed` |
| Space | `77h` | Set `inv_fire_pressed` |
| SET-UP | `7bh` | Exit to normal terminal operation |

Both movement flags together cancel movement. Attract mode replaces movement
and fire input with its demo driver. Consumed gameplay keys are discarded with
`clear_keyboard` rather than sent to the host.

Initials entry is the exception: it temporarily uses the stock SET-UP-style
keycode-to-ASCII path, including modifier processing and bounded cursor editing,
as described under [Persistent High Scores](#persistent-high-scores).

## Keyboard LEDs

The game uses the four VT100 keyboard LEDs as the gunner counter. During
game mode, the number of lit LEDs equals the number of player gunners
available:

```text
0 gunners:  no LEDs lit
1 gunner:   L1
2 gunners:  L1 L2
3 gunners:  L1 L2 L3
4+ gunners: L1 L2 L3 L4
```

The stock firmware exposes this through `led_state`; `update_kbd` includes the
low four LED bits when it writes the keyboard status byte. Game code should
only modify the low four bits:

```asm
inv_led_for_gunners:
        ; A = gunners, returns A = low-nibble LED mask
        ; 0 -> 00h, 1 -> 01h, 2 -> 03h, 3 -> 07h, 4+ -> 0fh
        ret

inv_update_gunner_leds:
        lda     inv_gunners
        call    inv_led_for_gunners
        lxi     h,led_state
        mov     b,a
        mov     a,m
        ani     0f0h            ; preserve any non-LED state defensively
        ora     b
        mov     m,a
        ret
```

On entry, the game saves the previous low nibble of `led_state` in game RAM.
On exit, it restores that nibble while preserving the upper bits. Gunner LEDs
are refreshed when drawing the static screen and immediately after losing a
gunner. A new game starts with four gunners; there is no extra-life award.

## Game Sound

The game uses the VT100 keyboard click/bell bit at the point where the stock
firmware assembles the keyboard status word. The base-ROM patch replaces
`ora m` / `mvi m,0` in `update_kbd` with a same-size call to
`inv_sound_status_hook`. The AVO implementation repeats those instructions to
merge and clear the stock click latch, then checks the active-mode guard.
While game sound owns the output, it preserves bits 0-6 and replaces bit 7
before the status word is written to `iow_keyboard`.

This keeps keyboard LEDs, local/online indication, keyboard lock, scan start,
and normal key scanning on the stock path while allowing Invaders to pattern
the click/bell bit per keyboard status word. The status-word cadence matters:
the VT100 technical manual describes BEL as about 200 consecutive keyboard
status words with the bell bit set, producing an approximately 0.25 second
tone from the keyboard speaker circuit.

Do not call `make_keyclick` for game audio. That routine checks
`setup_b2 & sb2_keyclick`, which is appropriate for normal typing but not for
intentional game sound. Likewise, do not write `iow_keyboard` directly from
gameplay code; that risks corrupting unrelated keyboard status bits.

Heartbeat output is a one-status-word pulse. Turret death takes priority and
starts a 200-status-word countdown, gating the click bit with a repeating
two-on/two-off pattern. `inv_next_sound_mask` advances the sound at keyboard
status cadence, not at video-frame cadence.

`inv_update_heartbeat` runs after `inv_update_aliens`. It does not schedule new
pulses during turret death, level pauses, or game over. The final death sound
continues after game over until its countdown expires; the hook then returns
to stock status output. Level pauses and game exit also reset game sound.

Heartbeat frame periods for the current 44-alien formation are:

```text
44-30 aliens remaining: 24 frames
29-15 aliens remaining: 16 frames
14-7 aliens remaining:  10 frames
6-1 aliens remaining:   6 frames
```

Automated tests verify the status-word bit pattern and preservation of the
other keyboard bits, not sampled audio. Audible output in MAME does not prove
that its speaker model reproduces the hardware RC circuit. Real hardware
remains the final gate for the exact timbre of heartbeat and death sound.

## Screen Model

The hybrid playfield keeps the VT100-friendly fixed dimensions from
`vtinvaders`, but uses taller `ascii-invaders`-style sprites:

- physical width: 80 columns
- logical playfield width: 60 columns, centered at physical columns 11-70
- height: 24 rows
- UFO rows: 1 and 2, with no top gutter
- alien rows: 2 visible rows in a 3-row slot starting at row 3
- shield rows: 19, 20, and 21
- turret rows: 22 and 23
- score/status row: 24

The original `ascii-invaders` alien silhouettes are six columns wide including
padding. The firmware version trims them to four visible columns in a five-cell
slot. That keeps the 11-column arcade formation inside a 60-column playfield:

```text
11 columns * 5-cell slots = 55 columns
```

These screen row/column descriptions are one-based. Assembly coordinates are
zero-based. The implemented geometry is:

```asm
inv_play_width  equ 60
inv_alien_cols  equ 11
inv_alien_rows  equ 4
inv_alien_w     equ 4        ; visible sprite width
inv_alien_slot_w equ 5       ; width plus one blank column
inv_alien_h     equ 2
inv_alien_slot_h equ 3       ; height plus one blank row
inv_ufo_w       equ 7
inv_ufo_h       equ 2
inv_turret_w    equ 7
inv_turret_h    equ 2
inv_shield_w    equ 7
inv_shield_h    equ 3
```

The game renders into normal VT100 screen RAM. `inv_row_addr` is a direct
row-address table in the AVO ROM; screen rows have an 83-byte stride, including
their three-byte line links. Keep this pointer table in ROM, not in four-bit
AVO attribute RAM.

```asm
inv_row_addr:
        dw      main_video+(inv_row_stride*0)
        dw      main_video+(inv_row_stride*1)
        ; ...
        dw      main_video+(inv_row_stride*23)
```

`inv_prepare_screen` disables 132-column mode and scrolling, then calls the
stock `make_screen`, `make_line_t`, and `update_dc011` routines to establish a
stable 80-column display. `inv_draw_static_screen` clears it and draws the
status, ground line, shields, turret, and LED count. The active idle hook bypasses
normal receiver processing. Cursor rendition is disabled except during initials
entry.

Rendering writes changed objects directly; there is no deferred output flush.
The drawing interfaces are:

```asm
; input: B = row, C = column, A = character
inv_putc:
        ; bounds-check, clip attract boxes, then write through inv_cell_addr
        ret

; input: B = row, C = column, HL = zero-terminated mapped-glyph sprite
inv_puts_glyphs:
        ; write consecutive characters
        ret

; input: B = row, C = column, HL = zero-terminated Special Graphics source
; Converts bytes in the range 05fh-07eh to mapped glyphs before writing.
inv_puts_sg:
        ret
```

There is no object-map or dirty-queue allocation. `inv_putc` writes screen
RAM only. Collisions use entity
coordinates and shield cell state, as described under
[Collision Strategy](#collision-strategy).

## Special Graphics Encoding

The VT100 firmware already knows the DEC Special Graphics character set.
`charset_list` maps SCS final `0` to internal charset value `88h`, and
`print_char` maps Special Graphics source bytes from `05fh` through `07eh` down
to ROM glyphs `00h` through `1fh`. The game uses the same mapping for
direct screen RAM writes:

```asm
; source is the byte that would be printed after ESC ( 0 selected Special
; Graphics into G0. The direct screen RAM glyph is source - 05fh.
sg_blank        equ '_' - 05fh
sg_checker      equ 'a' - 05fh
sg_lower_right  equ 'j' - 05fh
sg_upper_right  equ 'k' - 05fh
sg_upper_left   equ 'l' - 05fh
sg_lower_left   equ 'm' - 05fh
sg_cross        equ 'n' - 05fh
sg_scan_1       equ 'o' - 05fh
sg_scan_3       equ 'p' - 05fh
sg_hline        equ 'q' - 05fh
sg_scan_7       equ 'r' - 05fh
sg_scan_9       equ 's' - 05fh
sg_tee_left     equ 't' - 05fh
sg_tee_right    equ 'u' - 05fh
sg_tee_up       equ 'v' - 05fh
sg_tee_down     equ 'w' - 05fh
sg_vline        equ 'x' - 05fh
sg_bullet       equ '~' - 05fh
```

Alien and UFO tables store Special Graphics source characters and use
`inv_puts_sg` to subtract `05fh` at runtime. For example, source `lqqk` means
"upper-left corner, horizontal line, horizontal line, upper-right corner."
Shield cell codes instead index `inv_cell_glyphs`, a table of final glyph bytes.

`inv_puts_glyphs` writes bytes literally. Text and the turret's mixed ASCII/DEC
top row use this path so ASCII underscore remains an underscore. Its zero byte
is the string terminator; use ASCII space for blanks in a literal glyph string.
The turret bottom uses `inv_puts_sg`, where `_` maps to a blank cell.

Direct screen RAM writes should not change `g0_charset`, `g1_charset`, or
`gl_invocation`. Those variables matter when characters pass through
`print_char`; the game is writing already-mapped glyph numbers to screen RAM.
On game exit, normal terminal character-set state should therefore be unchanged
unless the entry path intentionally used the parser for diagnostics.

The ordinary ASCII set should still be used for text such as `SCORE`,
`GAME OVER`, and decimal point values. DEC Special Graphics is for moving game
sprites, shelters, missiles, and decorative playfield marks.

## Special Graphics Rendering

The following tables match the current ROM sprites. Diagrams labelled "source"
use DEC Special Graphics source characters, not their ASCII appearance; `a`
means checkerboard and `_` means blank. Literal ASCII and mixed-glyph diagrams
are identified separately.

### Alien Formation

There are 4 rows and 11 columns. Each alien is 4 visible columns wide in a
5-column slot. Each alien is 2 rows tall in a 3-row vertical slot.

```text
30-point alien, animation A, source:
_aa_
maaj

30-point alien, animation B, source:
a__a
_aa_

20-point alien, animation A, source:
aqqa
_xx_

20-point alien, animation B, source:
xaax
mqqj

10-point alien, animation A, source:
laak
x__x

10-point alien, animation B, source:
_aa_
mqqj
```

The global `inv_alien_anim_phase` toggles at each completed sweep. Aliens use
that phase when drawn; a kill erases the sprite immediately without a separate
alien-explosion or landed-alien image.

Row types:

```text
top row:          30-point alien
next two rows:    20-point alien
bottom row:       10-point alien
```

### Player Turret

Use the `ascii-invaders` gunner as the player turret. It is 7 columns wide and
2 rows tall, with a `_/|\_` top row above checkerboard cells.

```text
Normal, appearance (a = checkerboard):
 _/|\_
 aaaaa

Explosion, literal ASCII:
*aaaaa*
a*a*a*a
```

The top row mixes ASCII space, underscore, slash, and backslash with the DEC
vertical-line glyph `19h` at the center. The lower row uses Special Graphics
checkerboard cells. The explosion is one static, literal ASCII sprite, not an
alternating Special Graphics animation.

The player laser starts above the center column, `inv_turret_x + 3`. Incoming
missiles use the whole 7 by 2 turret rectangle for collision detection.

### Player Laser

```text
Normal shot, source: x
```

Only one laser can be active. It uses glyph `19h`, moves upward one row per
frame, and disappears after reaching row 0 or hitting an object. There is no
top-edge sparkle animation.

### Alien Missiles

Enemy missiles have three fixed slots and a one-cell glyph:

```text
Missile source: w
```

The renderer always writes glyph `18h` (`w` in Special Graphics). A phase byte
toggles during movement but does not select a different glyph. All three slots
are available from the beginning; there is no later one-to-three missile gate.
See [Missile Update](#missile-update) for the firing countdowns.

### UFO

Use the `ascii-invaders` mystery ship. It is 7 columns wide and 2 rows tall,
moving on display rows 1 and 2 (zero-based rows 0 and 1).

```text
Normal, source:
_lqqqk_
laaaaak

Explosion, source:
_qnnnq_
_aaaaa_

Score 50:                    50
Score 100:                   100
Score 150:                   150
Score 300:                   300
```

UFO direction depends on player-shot parity: even counts start at the left and
move right; odd counts start at the right and move left.

### Shields

Each of the four shelters is 7 columns wide and 3 rows tall. The roof corners
use ASCII slash and backslash, with Special Graphics checkerboard fill:

```text
Initial, source:
/aaaaa\
aaaaaaa
aaa_aaa
```

The 84 visible cells use four-bit codes indexing a ROM glyph table. A separate
28-element array tracks damage per column, shared by all three cells in that
column. Any nonblank cell is solid. Successive hits replace its column's
remaining cells with `*`, then `.`, then blanks; existing openings stay blank.

```text
One hit in column 2:
/*aaaa\
a*aaaaa
a*a_aaa

Two hits in column 2:
/.aaaa\
a.aaaaa
a.a_aaa

Three hits in column 2 (_ = blank):
/_aaaa\
a_aaaaa
a_a_aaa
```

Damage from player lasers and enemy missiles shares this same column state.

### Ground And Status

```text
Status row 24: SCORE 0000  LEVEL 1
```

The ground line spans the 60-column playfield on display row 22, behind the
turret's top row. Gunners are shown on the keyboard LEDs. All lines are
single-width. A qualifying game-over score opens initials entry; there is no
separate `GAME OVER` text sprite for a nonqualifying score.

## Entity State

All state addresses are equates in `src/invaders-avo.asm`, allocated downward
from `inv_data_top`. ROM tables and geometry constants remain in the expansion
image. The important groups are:

| State | Current representation |
|---|---|
| Mode and input | Active guard, attract/game-over flags, and left/right/fire flags |
| Logical frame | `inv_frame_lo` and `inv_frame_hi`, one nibble each |
| Score | Three decimal digits, `inv_score0` through `inv_score2`, in units of 10 |
| Lives and level | `inv_gunners` starts at 4; `inv_level` starts at 1 |
| Turret and laser positions | Low/high nibble pairs; laser also has active, timer, and shot-count state |
| Alien state | 44 live flags and four 44-element coordinate-nibble arrays |
| Formation state | Spawn/live counts, last alien, direction, reversal, descent, animation phase, and live row/column bounds |
| Enemy missiles | Three-element active, row, column, and phase arrays, plus firing/tick counters |
| UFO | Idle/active/explosion/score state, position/direction, timers, points, and disabled flag |
| Sound | Mode, phase, heartbeat and death counters, and diagnostic keyboard status bytes |
| High scores | 30 decimal score digits and two 30-element initials arrays, plus entry/editing state |
| Shields | 84 cell codes and 28 shared column-damage values |

Alien state is not a six-byte packed bitset, and there is no cached shooter
array. `inv_find_column_shooter` searches the live flags when needed. The
high-score cache sits with the other top-down game state, with a separately
named range so tests can leave it out of volatile-memory poisoning.

## Persistent High Scores

The stock VT100 firmware uses ER1400 NVR addresses 0 through 50 for terminal
settings and their checksum. Invaders must leave those words alone and use the
unused address range from 51 through 99 for persistent game data.

The high-score table stores ten entries and uses 25 NVR words:

| Address range | Count | Contents |
|---:|---:|---|
| 51-60 | 10 | Score values, one word per entry |
| 61-75 | 15 | Initials, two 6-bit characters per word |

Scores are stored divided by 10, matching the displayed arcade score units.
For example, a displayed score of `2940` is stored as `294`. The current
three-digit score-unit counter supports `0` through `999`, displayed as `0000`
through `9990`, and wraps on overflow. Those values fit in one 14-bit ER1400
word. A zero score word marks an unused table entry; zero scores are never
inserted. Loaded words above `999` are also treated as unused.

Initials are stored as one compact 30-character stream, not as padded per-entry
records. Entry `n` consumes characters `n*3` through `n*3+2` in that stream.
Initials word `61 + floor(character_index / 2)` stores the even character in
bits 0 through 5 and the odd character in bits 6 through 11. Bits 12 and 13 are
reserved and should be written as zero.

Use a 6-bit printable character set that excludes lower-case letters. Encode
ASCII characters from space through underscore as `character - 20h`, and decode
them by adding `20h`. This gives the table spaces, digits, punctuation, and
upper-case letters without wasting NVR words on byte-sized character storage.
Remaining NVR words 76 through 99 stay available for future metadata such as a
version or checksum.

On reset, the stock `recall_nvr` path still loads terminal settings first. The
Invaders base ROM then replaces the later stock `call init_devices` with a
same-size trampoline call through the AVO ROM. The AVO hook repeats the
displaced `init_devices` call, then reads NVR addresses 51 through 75 into the
high-score cache in the top-down screen-RAM allocation after reset-time display
initialization. If the terminal is in 132-column mode, reset-time cache loading
is skipped because those addresses contain visible screen data. Score words
are decoded into three score-unit digits, and the packed initials stream keeps
its existing low-nibble and high-bit arrays. The RAM
cache is cleared before loading; any zero-score slot remains unused and has
its initials cleared even if stale initials are present in NVR.

Launching Invaders from SET-UP refreshes the cache from NVR again before the
attract screen is drawn. Normal screen clearing or 132-column terminal activity
may have overwritten the cache, so the game treats NVR as the authority and
reloads the table after preparing its 80-column screen.

When a game ends, the current score is compared against the cached table. A
qualifying non-zero score is inserted, lower entries are shifted down, initials
for the new entry are cleared to spaces, and the high-score prompt is shown.
The prompt temporarily routes key input through the stock firmware keycode to
ASCII path. `inv_ascii_to_initial_code` clears bit 5 for characters with bit 6
set, folding ASCII columns 6 and 7 into columns 4 and 5, then rejects values
below `20h`. The resulting space-through-underscore characters use the same
6-bit encoding as the table. Left and Right move the
cursor between the three initial positions without leaving the field. Typing
replaces the character at the selected position. Backspace moves the cursor
back and clears the corrected character. RETURN confirms the entry only after
at least one initial has been entered, regardless of the cursor position;
moving through empty positions does not count as entering an initial. Unused
positions are saved as spaces, and addresses 51 through 75 are written back to
NVR. The cursor is visible only during entry and is hidden before returning to
attract mode. SET-UP can cancel unconfirmed entry and leave the game without
writing that pending score.

For manual MAME runs, persistent words are saved in
`<MAMEDir>\nvram\vt102\nvr` with the default path settings. `run-invaders`
stages ROMs only; it does not seed or replace this file. Exit MAME normally so
the emulated NVR state is written to disk. Automated tests use separate,
disposable NVR directories.

## Alien Update

`inv_update_aliens` first spawns one alien per frame in ascending ID order.
After all 44 have spawned, `inv_next_live_alien` selects one live alien per
frame, skipping dead entries. `inv_move_alien` erases its old rectangle, moves
it one column, applies any pending one-row descent, and redraws it.

On a completed sweep, `inv_cycle_aliens` toggles the animation phase and clears
`inv_alien_y_delta`. If `inv_alien_reverse` is pending, it also reverses
direction, sets a one-row descent for the new sweep, and clears the reversal
flag. Reaching a horizontal boundary requests reversal for the next sweep.
Returning to the same ID counts as a completed sweep when only one alien is
left, so the descent does not incorrectly persist through horizontal movement.

`inv_kill_alien` erases the alien, clears its live flag, decrements the live
count, awards points immediately, and recomputes all live row/column bounds.
This scans the live flags rather than only rescanning the killed alien's edge.
There is no alien explosion timer or delayed scoring phase.

## Alien Firing

`inv_next_shoot_column` follows the fixed `vtinvaders` shoot order. Zero
selects a column calculated from the turret's left edge relative to
`inv_alien_start_x`, divided by the five-cell slot width and clamped to 0-10.
Other values select a one-based alien column. If a column has no live shooter,
`inv_enemy_pick_shooter` advances through the table, trying at most one complete
pass.

```asm
inv_missile_shoot_order:
        db 0,1,11,1,0,7,0,1,6,3,0,1,1,0,1,1,0,4,11
        db 9,2,0,11,0,1,8,2,0,6,0,3,11,4,0,1,7,0,1
        db 0,11,0,9,0,2,10,11,1,0,8,0,1,6,3,0,7,0,1
        db 1,0,1,1,0,1,11,9,2,0,4,0,11,0,9,0,1,0,5
inv_missile_shoot_order_count equ 76
```

`inv_find_column_shooter` starts at the bottom ID in the selected column and
subtracts 11 until it finds a live alien. There is no shooter cache to maintain
after kills. Missiles start at `alien_y + inv_alien_h` and `alien_x + 1`, just
below the two-row sprite, in the first free missile slot.

## Missile Update

`inv_update_enemy_fire` uses `inv_missile_tick_timer` to run every third play
frame. It tries to launch a missile, then advances each active missile one row.
New launches wait until all aliens have spawned and require a live shooter and
a free slot.

`inv_missile_fire_timer` counts these three-frame ticks, not individual frames:

| Event | Countdown loaded |
|---|---:|
| Game/level initialization or turret respawn | 40 |
| A missile launches | 17 |
| The last active missile ends | 4 |

A nonzero countdown is decremented and returns; firing is tried on a later tick
that starts at zero. All three slots can be active at any time.

At each new position, a missile hitting a solid shield cell damages that column
and ends. At the turret row it either hits the turret rectangle or ends without
an explosion or ground scar. Missiles do not intercept the player laser.
Turret death clears every active missile and the player laser before drawing
the turret blast.

## Turret And Laser Update

The turret is visible from initialization. `inv_update_turret` moves it one
column per frame when exactly one direction flag is set, bounded by physical
zero-based columns 10 and 63. `inv_update_laser` spawns a shot if fire is pressed
and no shot is active; otherwise it moves the existing shot upward.

`inv_place_laser` checks shield, UFO, then alien collisions in that order.
An alien hit is erased and scored immediately. The laser is removed on a hit
or after reaching the top row; there is no sparkle phase or explosion delay.

`inv_start_turret_death` erases the turret and all projectiles, draws the static
blast, starts death sound, and immediately decrements the gunner count and
updates LEDs. With gunners remaining, gameplay pauses for 55 frames before
erasing the blast and respawning the turret at column 36. With none remaining,
it enters game over immediately while allowing the death sound to finish.
A qualifying score opens initials entry; otherwise the game remains stopped
until SET-UP exits. There is no separate real-game landing-to-game-over check
in the shared play loop; the demo has its own bottom-row restart condition.

## UFO Update

The UFO uses its own countdowns:

- first UFO: after 600 UFO-update frames, starting when alien spawning completes;
- later UFOs: a 1500-frame interval reloaded when a UFO spawns;
- move every 5 frames;
- disable UFOs when fewer than 8 aliens remain;
- direction depends on the player-shot counter's parity;
- point value depends on the player-shot counter modulo 15.

Point table:

```asm
inv_ufo_points_table:
        db 10,5,5,10,15,10,10,5,30,10,10,10,5,15,10
```

The table stores score units of 10, giving awards of 50, 100, 150, or 300.
A hit shows an explosion for 21 update frames, then awards and displays the
points for 72 update frames before clearing the UFO. UFO updates pause along
with ordinary gameplay during turret death and level transitions. Each level
resets the first-appearance countdown.

## Shield Damage

`inv_shield_cell_addr` converts a projectile's row and column into one of the
84 shield cells. Only a nonblank cell registers a hit. Both the player laser
and enemy missiles call `inv_try_shield_collision`, which damages the entire
column through `inv_damage_shield_column`.

The shared damage value at `inv_shield_damage_base` saturates at 3:

| Damage | Remaining nonblank cells in the column |
|---:|---|
| 0 | Original roof/checkerboard glyphs |
| 1 | `inv_cell_damaged`, rendered as ASCII `*` |
| 2 | `inv_cell_weak`, rendered as ASCII `.` |
| 3 | `inv_cell_blank` |

`inv_redraw_shield_cell` updates each of the column's three rows, preserving
cells that were already blank. The original bottom opening therefore remains
open. Damage does not spread into neighboring columns and does not use separate
above/below erosion transforms. `inv_reset_shields` restores both cell codes and
damage counters at the start of a new game/demo; level changes retain damage.

## Collision Strategy

Collision detection reads game state, not the rendered screen or a shadow map:

- Player laser: test the shield cell, active UFO rectangle, then each live
  alien rectangle.
- Enemy missile: test shield cells above the turret row; at the turret row,
  test the turret rectangle and end the missile whether it hits or misses.
- Shield blanks are passable. Alien, UFO, and turret rectangles include blank
  cells inside the sprite bounds.
- There is no player-laser/enemy-missile interception test.

The attract overlay clips drawing only. Entities continue to move and collide
behind its boxes using the same game state as real play. No collision state is
stored in attribute RAM.

## Level Reset

The larger Special Graphics sprites cannot reuse the `vtinvaders` one-row alien
offsets literally. Keep the same ID layout, but compute positions with the
2-row sprite and 3-row slot geometry.

Alien IDs are arranged with the top row first:

```text
id 0..10     top row, 30-point aliens
id 11..21    next row, 20-point aliens
id 22..32    next row, 20-point aliens
id 33..43    bottom row, 10-point aliens
```

With top-first IDs, the next candidate above an alien is `id - 11`.
Level 1 has no vertical offset; levels 2 through 9 start one row lower.

For alien ID `id`:

```text
row = id / 11        ; 0 is top, 3 is bottom
col = id % 11
y   = 2 + row * inv_alien_slot_h + (level >= 2 ? 1 : 0)
x   = inv_alien_start_x + col * inv_alien_slot_w
type = 10, 20, or 30 points from the row table above
```

These formulas use zero-based screen coordinates. At level 1, the top sprite
occupies display rows 3-4 and the bottom sprite rows 12-13. At later levels
those become rows 4-5 and 13-14. Shields begin on display row 19, leaving room
for several descents before the formation reaches them.

## Testing

MAME is the main repeatable regression environment for Invaders firmware
changes. CTest owns the host orchestration, CMake scripts stage a private MAME
ROM set, and Lua code running inside MAME drives the emulated VT100 and asserts
against memory. Final confidence still comes from real VT100 hardware or a
hardware-equivalent emulator setup.

The repository MAME setup note is in [mame.md](mame.md). Configure with a
non-empty `MAME_COMMAND` to enable the `mame-invaders` staging target and the
MAME-backed CTest tests. When `MAME_COMMAND` is empty, the normal ROM build and
non-MAME CTest tests still run, but MAME-dependent tests are not registered.

The current MAME VT100-family driver is useful for ROM layout checks, input
tests, frame sequencing, memory-state assertions, and screen-RAM assertions.
The tests use `vt102` because the MAME `vt100` machine does not currently load
the AVO program expansion ROM. This is an emulator limitation, not a firmware
requirement: the real VT100 supports the AVO expansion ROM.

### Test Layers

Use several layers so most bugs are caught before manual MAME or hardware
testing:

1. Stock VT100 ROM tests compare `vt100.bin` and the four split VT100 ROM
   images against the checked-in originals.
2. Static Invaders ROM tests verify that `invaders.bin` remains compatible with
   the base-ROM trampoline constraints, that `invaders-[1-4].bin` are exactly
   2048 bytes each, and that `invaders-avo.bin` is exactly 8192 bytes.
3. AVO layout tests parse labels from generated `.sym` files and address
   equates from generated `.equ` files. Invaders code must stay in the
   `8000h`-`9fffh` expansion ROM window, while mutable state grows downward
   from `2fffh` inside byte-wide screen RAM, above the 80-column display and
   its SET-UP scratch row. The active guard must also sit beyond the 132-column
   display and its scratch row.
4. Direct MAME Lua smoke tests inspect ROM entry points and game RAM without
   needing frame-by-frame input.
5. Plugin-backed MAME Lua tests boot the terminal, enter SET-UP, launch the
   game, inject keyboard input, wait for frames, and inspect game state and
   screen RAM.
6. Future host-side logic tests should cover deterministic tables such as alien
   spawn order, UFO scoring, shield damage, and frame gates.
7. Future visual tests should prefer screen-RAM character assertions over raw
   screenshots when possible.

### Existing Build And ROM Preparation

Configure with `MAME_COMMAND` when `mame.exe` is not already on `PATH`. The
`mame-invaders` target and the MAME-backed CTest tests are only created when
CMake has a non-empty `MAME_COMMAND`.

```bat
cd /d <SourceDir>
cmake --preset invaders -DMAME_COMMAND=<MAMEDir>\mame.exe
```

Exercise the full build and test path with the `invaders` CMake workflow
preset:

```bat
cmake --workflow --preset invaders
```

The workflow configures the build tree, runs the `invaders` build preset, and
runs the `invaders` CTest preset. The `invaders` build preset selects
`vt100-rom` so stock VT100 ROM regression tests have fresh build artifacts, and
`mame-invaders` to build and stage the Invaders ROMs for manual MAME runs.
Invaders-specific CTest tests run CMake scripts from `src/tests`. Those scripts
create a private ROM path under the build tree, set the MAME working directory,
run `mame.exe` headlessly, and pass either a direct Lua script or a MAME plugin.

The `invaders-rom` target assembles and checksum-patches `invaders.bin`, then
splits it into these files:

| Generated file | MAME file name |
|---|---|
| `invaders-1.bin` | `23-061e2-00.e56` |
| `invaders-2.bin` | `23-032e2-00.e52` |
| `invaders-3.bin` | `23-033e2-00.e45` |
| `invaders-4.bin` | `23-034e2-00.e40` |

The same build assembles `invaders-avo.bin` as a full 8 KiB expansion image.
The `mame-invaders` target installs it as `23-225e4-00.e69`, the MAME
VT100-family 8 KiB program expansion ROM name for the `8000h` window. It also
installs the character generator ROM as `23-018e2-00.e4`.

MAME can verify that the manual ROM set is discoverable:

```bat
cd /d <MAMEDir>
mame.exe -verifyroms vt100 -rompath roms
```

Checksum differences for modified CPU ROM chunks are expected during local
firmware experiments. Missing files are not expected. If the installed MAME
`vt100` driver does not load the expansion ROM image, a driver change or an
alternate VT100-family machine configuration may be needed for full Invaders
coverage.

### MAME Test Driver

`src/tests/CMakeLists.txt` registers MAME tests inside `if(MAME_COMMAND)`.
Each test invokes `src/tests/run-mame-test.cmake`, which validates the required
inputs, stages ROMs into a private directory, runs MAME, and converts the Lua
test result into a CTest pass or failure.

The test driver uses a build-local ROM path:

| Built file | Private MAME file name |
|---|---|
| `invaders.bin` | `vt102/23-226e4-00.e71` |
| `invaders-avo.bin` | `vt102/23-225e4-00.e69` |
| `bin/23-018E2.bin` | `vt102/23-018e2-00.e3` |

It also creates isolated `cfg`, `nvram`, `inp`, `sta`, and `snap` directories
under the build tree so automated tests do not depend on, or mutate, the user's
normal MAME state.

The MAME command shape is:

```bat
cd /d <MAMEDir>
mame.exe vt102 ^
  -rompath <BuildDir>\src\mame-roms ^
  -cfg_directory <BuildDir>\src\mame-test\cfg ^
  -nvram_directory <BuildDir>\src\mame-test\nvram ^
  -input_directory <BuildDir>\src\mame-test\inp ^
  -state_directory <BuildDir>\src\mame-test\sta ^
  -snapshot_directory <BuildDir>\src\mame-test\snap ^
  -skip_gameinfo ^
  -nothrottle ^
  -video none ^
  -sound none ^
  -seconds_to_run 5
```

Direct scripts append `-autoboot_delay 0 -autoboot_script <LuaScript>`.
Plugin-backed tests append `-pluginspath <MAMEDir>\plugins;<SourceDir>\src\tests`
and `-plugin <PluginName>`.

### Scriptable Test Hooks

Test-only state bytes live in the byte-wide screen-RAM tail and are defined in
`src/invaders-avo.asm` alongside the rest of the game state. Keep these in the
same top-down allocation style as the game state, and load their addresses from
generated `.equ` files in tests instead of duplicating numeric addresses.

```asm
inv_active          equ     inv_data_top          ; 2fffh, beyond terminal DMA
inv_test_signature  equ     inv_active-3          ; 3 bytes, 2ffch-2ffeh
inv_test_signature0 equ     05h
inv_test_signature1 equ     0ah
inv_test_signature2 equ     0fh
inv_test_mode       equ     inv_test_signature-1
inv_test_script     equ     inv_test_mode-1
inv_test_stop_lo    equ     inv_test_script-1
inv_test_stop_hi    equ     inv_test_stop_lo-1
inv_test_result     equ     inv_test_stop_hi-1
inv_test_trace_head equ     inv_test_result-1
inv_test_trace_top  equ     inv_test_trace_head-1
inv_test_trace_base equ     inv_test_trace_top-inv_test_trace_size+1
```

Before any MAME test enters Invaders through SET-UP, it fills the mutable
game-state allocation from `inv_volatile_data_low` through `inv_data_top` by
repeating the `de ad be ef` junk byte pattern. The poison helper skips the
persistent high-score cache range, `inv_high_score_cache_base` through
`inv_high_score_cache_top`, so reset-loaded table data survives while the rest
of the game proves that it initializes its own state. Tests that need firmware
test mode then write the three signature bytes before setting `inv_test_mode`;
normal gameplay tests leave the signature cleared so stale screen data cannot
turn into an accidental test command.

The state-layout test round-trips full `de ad be ef` bytes through every game
allocation, checking that terminal RAM, display storage, and attribute RAM
outside the allocation are unchanged. The entry test also fills the reused
132-column character cells with `Z` (`5ah`, the active guard value), preserving
line links, and verifies that inactive hooks neither enter the game nor corrupt
the text. It then launches from 132-column SET-UP and checks reinitialization.

Current result codes:

```asm
inv_pass            equ 00h
inv_fail_no_avo     equ 01h
inv_fail_bad_state  equ 02h
inv_fail_bad_sprite equ 03h
inv_fail_timeout    equ 04h
```

In test mode, replace any random or timing-dependent choices with deterministic
tables. The `vtinvaders` reference is already mostly deterministic, so this
mainly means freezing entry timing and scripted input.

### MAME Lua Tests And Plugins

All Lua tests live under `src/tests`. The shared `mame-test.lua` helper loads
addresses from generated `.equ` files, loads labels from generated `.sym`
files, returns the `:maincpu` program address space, and reports test status by
printing `VT100_INVADERS_TEST_PASS` or `VT100_INVADERS_TEST_FAIL`.

The helper installs memory taps that allow only bits 0-3 to be stored in
`3000h`-`3fffh` and force bits 4-7 high on CPU reads. This is a test constraint
on writable storage, not a claim about the electrical value of unused hardware
data bits. All gameplay tests run with it; values requiring more than four bits
must round-trip through byte-wide game RAM instead.

Direct Lua scripts are enough for immediate checks that do not need to stay
attached to the emulator frame loop. These tests are run with
`-autoboot_delay 0 -autoboot_script <LuaScript>`.

Temporal tests use MAME's plugin mechanism. Each plugin-backed test has a
small directory such as `src/tests/vt100invaderslaser` containing `plugin.json`
and `init.lua`. The plugin's `exports.startplugin()` function loads the shared
test module from `src/tests`, then that module registers MAME callbacks such as
`emu.register_prestart` and `emu.add_machine_frame_notifier`. This lets the test
wait for boot, enter SET-UP, inject keys at precise frames, observe game state,
and exit MAME when the assertions pass or fail.

Use plugin-backed tests for anything that depends on time or input sequencing:
entry through SET-UP, frame advancement, rendering after boot, static screen
state, keyboard input, laser movement, collisions, missiles, and game-over
behavior. Use direct scripts for ROM layout and memory layout probes.

The demo-state test watches screen-RAM writes throughout demo play and restarts
so even transient writes into the overlay boxes fail. An autopilot-fired laser
crosses all three rectangles, appears in the gaps, and leaves no trail. The
test also watches high-score insertion, initials entry, NVR-save calls, dirty
flag writes, and cache writes while forcing a qualifying demo game-over score.
RETURN must discard the demo score and restore unclipped real gameplay.

The high-score load test checks seeded entries and empty rows after 64 demo
frames. Both it and the demo-state test compare the complete seeded NVR file
before and after MAME runs; demo play must leave it byte-for-byte unchanged.
The real-game high-score test still verifies initials entry and saved NVR words.

### Screenshot Regression

Screenshot tests should use a small set of deterministic frames:

| Frame | Expected screen state |
|---:|---|
| 0 | cleared playfield and static status |
| 44 | alien formation has completed initialization |
| 128 | turret visible, aliens moving, no random input |
| 220 | scripted laser has hit a chosen alien |
| 600 | missiles and shield damage visible |

Screenshots should be compared with a tolerance or with character-cell
extraction rather than raw PNG bytes. MAME rendering options, warning screens,
window scaling, and imperfect graphics flags can otherwise cause noisy diffs.
For this game, a better visual assertion is often to read screen RAM and compare
the 60 by 24 character grid directly.

### Running The Test Harness

Manual smoke command, from `docs/mame.md`:

```bat
cd /d <MAMEDir>
mame.exe vt100 -rompath roms -window
```

Automated runs go through CTest. The normal entry point is:

```bat
cmake --workflow --preset invaders
```

To run one test directly through the same CMake driver, use the same variables
CTest passes:

```bat
cmake ^
  -DMAME_COMMAND=<MAMEDir>\mame.exe ^
  -DMAME_WORKING_DIRECTORY=<MAMEDir> ^
  -DMAME_MACHINE=vt102 ^
  -DMAME_LUA_SCRIPT=<SourceDir>\src\tests\mame-invaders-rom-layout.lua ^
  -P <SourceDir>\src\tests\run-mame-test.cmake
```

For a plugin-backed test, use the plugin wrapper script and plugin name:

```bat
cmake ^
  -DMAME_COMMAND=<MAMEDir>\mame.exe ^
  -DMAME_WORKING_DIRECTORY=<MAMEDir> ^
  -DMAME_MACHINE=vt102 ^
  -DVT100_BINARY_DIRECTORY=<BuildDir>\src ^
  -DVT100_PROJECT_SOURCE_DIRECTORY=<SourceDir> ^
  -DMAME_LUA_SCRIPT=<SourceDir>\src\tests\vt100invaderslaser\init.lua ^
  -DMAME_TEST_PLUGIN=vt100invaderslaser ^
  -P <SourceDir>\src\tests\run-mame-test.cmake
```

The CMake driver treats a non-zero MAME exit code, a
`VT100_INVADERS_TEST_FAIL` marker, or the absence of
`VT100_INVADERS_TEST_PASS` as a test failure.

### CI Acceptance Gates

The current `invaders` workflow gate is:

- firmware builds successfully;
- the stock VT100 ROM and split-ROM regression tests pass;
- the Invaders ROM layout test passes;
- direct MAME scripts can see the staged ROMs, generated equates, generated
  symbols, and byte-wide game RAM;
- plugin-backed MAME tests can enter SET-UP, start Invaders, advance frames,
  verify screen rendering, inject input, move the turret, fire the laser, and
  damage a shield cell.

As new gameplay slices land, extend the MAME gate with alien formation, scoring,
enemy missile, game-over, UFO, heartbeat, and exit-regression tests. Hardware
testing remains the final gate for keyboard feel, brightness, AVO attribute
interactions, and exact video timing.

## Open Implementation Questions

- Should game exit restore the exact previous screen, or simply rebuild normal
  terminal state?
- Should 50 Hz machines play slower, or should frame timers be scaled?
- Should the first implementation require AVO presence and refuse to start
  without it?
- Does the installed MAME `vt100` configuration expose both the `8000h`
  expansion ROM and the `2c00h`-`2fffh` byte-wide screen-RAM range, or do we need a small
  driver patch for full automated testing?

# Implementation

Each slice should leave the repository in a buildable, testable state. Add tests
as CTest tests, and exercise the complete implementation with
`cmake --workflow --preset invaders`. CTest entries should run CMake driver
scripts from `src/tests`. For MAME-backed tests, those CMake scripts set the
working directory to `<MAMEDir>`, run `mame.exe` against the staged ROMs, and
pass the matching Lua script with `-autoboot_script` or load its plugin for
frame-driven tests. MAME Lua test scripts and shared Lua helpers also live under
`src/tests`. Register MAME tests only when `MAME_COMMAND` is non-empty. Read
equates from generated `.equ` files and labels from generated `.sym` files.

The base ROM is space constrained. Invaders changes in `base.asm` must remain
same-size trampoline replacements of existing bytes with calls into the AVO ROM.
The AVO ROM must repeat the displaced base-ROM bytes on normal terminal paths.
Static tests should fail if `invaders.bin` differs from `vt100.bin` outside the
explicit trampoline spans and checksum bytes.

Attract-mode demo work should add orchestration only where possible. Reuse
`inv_reset_for_attract`, `inv_start_game`, `inv_frame`, `inv_update_aliens`,
`inv_update_heartbeat`, `inv_update_ufo`, `inv_update_enemy_fire`,
`inv_update_turret`, `inv_update_laser`, `inv_draw_static_screen`,
`inv_draw_high_score_table`, and the existing sprite/collision routines rather
than creating parallel demo renderers.

The remaining close-out slices continue after completed attract-mode slice 5.
Remove each slice only when its implementation and verification are complete;
do not renumber the remaining slices. Keep game state in byte-wide screen RAM
and all new game code within the existing AVO ROM budget. Additional visual
effects, a UFO siren, and other new gameplay features are outside this list.

### 6. Invasion Ends The Game

Add the missing real-game loss condition when a live alien's bottom row reaches
the ground row. Use the same boundary as the existing demo check:
`alien_y + inv_alien_h - 1 >= inv_ground_row`. Check the alien just updated by
the shared formation routine, before later gameplay updates can move other
objects or award points. Do not scan the full formation on every frame.

Landing ends the entire game, regardless of remaining gunners; it is not an
ordinary turret hit followed by a respawn. Clear the remaining-gunner LEDs,
stop formation movement and firing, and erase active projectiles and the UFO.
Preserve the final score and use the existing game-over and high-score paths.
Keep demo landing on its existing restart path, without initials entry or NVR
writes. Reuse the boundary calculation where practical rather than maintaining
different real-game and demo definitions of landing.

Extend the alien/enemy-fire MAME tests under `src/tests` to place a live alien
just above the boundary, force a descent, and verify that landing ends the game
exactly once with multiple gunners still available. Verify that an alien above
the boundary does not end play, a dead alien cannot trigger landing, and a lone
survivor still moves horizontally between descents. Check score preservation,
projectile cleanup, stopped updates, and the existing demo landing restart.
Run the complete `invaders` workflow, including stock-ROM regression tests.

### 7. Complete The Game-Over Loop

Introduce one real-game end sequence for final-turret death and invasion.
Display a centered `GAME OVER` message over the stopped playfield for 90 refresh
frames, and do not leave this presentation until any outstanding death sound
has finished. Keep keyboard status output and interrupts running throughout;
use state and timers rather than a blocking delay. Draw the message once using
the existing renderer and clear projectiles without leaving trails.

After the presentation, compare the final score with the high-score table once.
A qualifying nonzero score enters the existing initials editor. A zero score
or a score that does not qualify returns directly to the animated attract
screen. Confirming initials saves once and then enters the same attract path.
Use `inv_start_demo` and the shared initialization/rendering routines so both
paths start a clean demo with the current high-score table and correct overlay
clipping. Do not add a separate post-game renderer or duplicate the editor.

SET-UP must still exit immediately from the presentation or initials entry.
RETURN must not bypass required initials entry or accidentally start a new
game using a key held during the transition. Once attract mode is ready, a
fresh RETURN starts a clean game without a SET-UP round trip. Hide the initials
cursor on every completion/cancellation path and preserve the existing rule
that cancelling unconfirmed initials does not save that pending score.

Add frame-driven MAME coverage for zero-score, nonqualifying, and qualifying
game overs, plus the invasion path from slice 6. Assert presentation duration,
completion of final-life sound, frozen gameplay, exactly one qualification/save
attempt, and return to a moving demo. Exercise confirmation, cancellation,
held/released RETURN, and starting another game. Update existing game-over
tests to wait for the documented states without weakening their sound,
persistence, cursor, or freeze assertions. Run the full `invaders` workflow.

### 8. Aliens Crush Bunker Material

When an alien moves into bunker rows, remove the bunker cells covered by its
sprite rectangle from `inv_shield_cells_base` before drawing the alien. The
collision representation and display must agree: an alien must not erase
visible material while leaving an invisible obstacle for later projectiles.
Use the existing alien rectangle convention, including padding cells, and the
existing shield-address helpers. Handle both horizontal movement and descent.

Remove only overlapped cells, preserving adjacent material, the existing bottom
openings, and the per-column hit-point model for surviving cells. Crushed cells
remain blank when later projectile hits redraw their column and when the next
level preserves shield damage. Do not redraw a bunker over a live alien or
restore crushed material when that alien moves away or dies. New-game and demo
initialization still restore the original bunkers through `inv_reset_shields`.

Extend the alien/shield MAME coverage with intact and partially damaged
bunkers. Move aliens across a roof, body, opening, and bunker edge in both
directions, then descend through them. Compare screen cells with collision
state after the alien leaves; fire both projectile types through crushed gaps
and at surviving material. Verify that column damage cannot resurrect a
crushed cell, level changes retain destruction, and a new game restores the
bunkers. Retain attract-overlay clipping coverage and run the full workflow.

### 9. High-Score And Rollover Edge Cases

Extend the existing high-score MAME tests beyond insertion into an empty table.
Use deterministic tables containing ten distinct descending scores and
different three-character initials. Cover insertion at the top, middle, and
last position, eviction of the lowest entry, a nonqualifying score, and zero.
Preserve the existing strict-comparison rule: equal scores remain ahead of the
new entry, which may qualify below them if a lower score exists; a tie with a
full table's lowest score does not qualify. Assert all ten score/initial pairs
after each operation, including packing across NVR word boundaries.

Exercise repeated insertion and confirmation, cancellation with SET-UP, and
reload after saving. Compare the complete NVR image so terminal words 0-50 and
unused words 76-99 remain unchanged. Run a second MAME process against the
first process's private saved NVR file to verify persistence through an actual
emulator restart, without substituting a freshly seeded file. Keep all state
under the test build directory; never use the manual MAME NVR file.

Explicitly test the existing four-digit displayed-score rollover after `9990`,
including an award that crosses the boundary, and verify how the resulting
score qualifies. Preserve rollover behavior in this slice rather than silently
changing it to saturation or adding digits. Test zero/unused NVR entries,
out-of-range score words, and stale initials associated with unused entries.
Fix defects exposed by these cases within the existing score representation
and storage format; do not add NVR metadata or change the format speculatively.

Register any added fixtures through the existing CMake test driver and CTest,
conditional on `MAME_COMMAND`. Run focused high-score/scoring tests and then
`cmake --workflow --preset invaders`.

### 10. Documentation Close-Out

Reconcile `docs/invaders.md`, `docs/mame.md`, and `ReadMe.md` with the completed
implementation and the authoritative CMake targets. Correct the manual
Invaders staging table to describe the combined base ROM and character ROM
under `vt102`, while retaining the four split images as physical-ROM outputs.
Use the actual `run-invaders` command options, remove its stale `-window` claim,
and repair direct test-driver examples to supply every required variable.
Use `<MAMEDir>`, `<SourceDir>`, and `<BuildDir>`, not machine-specific paths.

Replace already-completed "future" test descriptions and resolved open
questions with current behavior. Document the game-over and bunker-overrun
rules from the preceding slices, turret underline, score rollover, and the
chosen terminal-exit behavior. State the physical AVO/expansion-ROM requirement
and distinguish it from MAME's need to select `vt102`. Keep 50 Hz timing and
physical-hardware acceptance explicitly pending until slice 11 resolves them;
do not describe unperformed hardware checks as passing.

Add a compact "How To Play" section to `ReadMe.md`: SET-UP then `i`/`I`, RETURN
to start, arrows to move, Space to fire, SET-UP to exit, keyboard LEDs for lives,
and initials editing/confirmation. Explain where manual MAME high scores are
saved and that automated tests use isolated state. Link to the detailed MAME
setup rather than duplicating its keyboard/UI instructions.

Validate target names, ROM filenames, options, and example variables against
`src/CMakeLists.txt` and `src/tests/run-mame-test.cmake`. Exercise repaired
automated examples against the configured build, review local links and title
casing, and run the `invaders` workflow. The manual launch example may be
checked through its generated command without starting an unattended GUI.

### 11. Physical-Hardware Acceptance And Timing Decision

Add a reproducible manual acceptance checklist and results record to
`docs/invaders.md`, recording the terminal/AVO configuration, ROM revision,
refresh rate, checks performed, and any limitations. Perform the checks on a
physical VT100 with the required expansion ROM and byte-wide screen RAM; MAME
results do not substitute for this gate. Keep stock firmware and a backup of
terminal settings available before the hardware trial.

Check cold boot, SET-UP launch, attract play, repeated real games, invasion,
game over with and without a qualifying score, initials correction and
cancellation, and exit back to normal terminal operation. Include entry from
80- and 132-column configurations. Confirm the documented 80-column return
behavior, restored cursor/LED state, local typing, and serial receive/transmit
after exit. Check simultaneous movement/fire, key release, and keyboard feel.

Evaluate the turret underline and existing sprites on the CRT at practical
brightness settings, heartbeat pacing, and death sound including the final
life. Save multiple high scores, exit normally, power-cycle the terminal, and
verify scores and initials while confirming ordinary terminal settings remain
unchanged. These checks must use the real keyboard speaker and ER1400 rather
than emulator approximations.

Compare play at 50 and 60 Hz where available. Record the current refresh-based
timing difference and obtain an explicit decision to accept it as a documented
limitation or require compensation. Do not silently rescale gameplay timers;
if compensation is requested, add a separately scoped implementation slice
with pacing and regression tests before claiming timing acceptance.

Record actual observations and fixes, rerunning the `invaders` workflow after
any firmware change. Leave unavailable configurations or equipment marked as
untested, and keep this slice pending until the hardware checks and timing
decision are complete or the user explicitly accepts a documented limitation.
