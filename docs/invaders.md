# VT100 Firmware Invaders Design

This note sketches an 8080 implementation of a Space Invaders-style game in
VT100 firmware, using [vtinvaders](https://github.com/j4james/vtinvaders) and
[ascii-invaders](https://github.com/macdice/ascii-invaders) as gameplay and
rendering references.

The design assumes that the base firmware ROM contains only the launcher,
dispatch glue, and clean exit path. The game code lives in the AVO program
expansion ROM window starting at `8000h`, while mutable game state lives in the
AVO RAM range, `3000h`-`3fffh`. While the game is active, the normal terminal
screen contents and AVO attribute contents are considered owned by the game.
Returning to terminal mode should restore or rebuild the normal terminal display
state.

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
- Use the VT100 keyboard click as the alien heartbeat sound effect.

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
ship, a 7 by 3 shelter, and a simple animated bomb. The firmware version should
translate those silhouettes into DEC Special Graphics line, block, and scanline
characters.

Adopted choices:

| Area | Adopt from | Reason |
|---|---|---|
| Main loop and frame clock | `vtinvaders` | Maps cleanly to `frame_count` and the firmware idle loop. |
| Alien movement | `vtinvaders` | One alien per frame is cheap and produces arcade-like speedup. |
| Enemy firing | `vtinvaders` | Fixed shoot order is deterministic and testable. |
| Missile storage | `vtinvaders` | Three fixed slots are simpler than linked-list bombs on 8080. |
| Collision IDs | `vtinvaders` | A shadow object map is affordable with AVO RAM. |
| Alien, gunner, UFO, shelter silhouettes | `ascii-invaders` | Larger sprites read better on a VT100. |
| Actual sprite character set | VT100 firmware | DEC Special Graphics is native and already mapped by the ROM. |
| Formation bounds | `ascii-invaders` | Cached live edges avoid scanning empty margins every frame. |
| Shield storage | `ascii-invaders` | A cell buffer is simpler and more expressive than packed damage nibbles. |
| Bomb animation | `ascii-invaders` | A one-cell rotating glyph is compact and animates well. |

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
- `kbd_click_mask` is ORed into the keyboard status byte by `update_kbd` and
  then cleared, making it a one-shot click latch suitable for the heartbeat.

The game should add an `inv_active` mode flag, but the base ROM has too little
slack for inline game dispatch. Every Invaders change in `base.asm` should be a
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

inv_idle_hook:
        lda     inv_active
        ora     a
        jnz     inv_idle_active
        call    keyboard_tick       ; displaced base-ROM call
        ret

inv_idle_active:
        call    inv_idle
        pop     h                   ; discard return into terminal idle path
        jmp     idle_loop

inv_idle:
        call    update_kbd          ; keep scan/status/click output alive
        call    inv_read_keys       ; consume raw game keys
        lda     inv_active          ; input may have requested exit
        ora     a
        jz      idle_loop
        call    inv_wait_frame      ; wait for frame_count to change
        call    inv_frame
        jmp     idle_loop
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

Use `i` or `I` on the SET-UP screen as the game launcher. Since the stock
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
                cpi     'I'             ; i or I starts Invaders
                jz      inv_setup_start
                lda     last_key_flags  ; existing SET-UP actions continue
                ret
```

`setup_action` pushes `setup_ready` before dispatching a SET-UP key action.
`inv_setup_start` must not return through that path, because `setup_ready`
would re-register `setup_action` after the game has taken over. Discard that
synthetic return, leave SET-UP mode, restore the normal terminal dispatch state,
and then enter the game:

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

`q`/`Q` can remain as a development or MAME convenience exit, but the
hardware-facing launcher and escape hatch should be SET-UP based.

## Invaders ROM And AVO Memory Plan

The Invaders entry points are shared between the base ROM and the AVO expansion
image through `src/invaders-abi.asm`. The expansion ROM starts at `8000h`; the
AVO RAM range remains available for mutable state, scratch data, and attribute
or screen-related storage. Allocate persistent game state from `3fffh`
downward, leaving lower AVO addresses untouched as long as possible to reduce
conflict with normal screen and attribute memory use.

```asm
inv_avo_base    equ 8000h
inv_code_base   equ inv_avo_base
inv_code_top    equ 9fffh       ; 8 KiB AVO program expansion ROM

avo_ram_start   equ 3000h
avo_ram_top     equ 3fffh

inv_data_top    equ avo_ram_top ; allocate mutable state downward from here
inv_data_floor  equ 3800h       ; soft low-water mark; move only if needed
```

If code size grows, keep it in the expansion ROM and adjust only the mutable
AVO RAM layout. The main constraint is that the game should own the selected
top-down AVO RAM state range while active. If the normal terminal display is to
be restored exactly, save the visible screen and attribute data before
entering. If exact restoration is not required, leave through a normal terminal
reset/rebuild path.

Suggested entry sequence:

```asm
inv_enter:
        di
        mvi     a,0ffh
        sta     inv_active
        call    inv_save_leds
        call    inv_save_terminal_state
        call    inv_init_screen
        call    inv_reset_state
        call    inv_update_gunner_leds
        lda     frame_count
        sta     inv_last_vframe
        ei
        ret
```

Suggested exit sequence:

```asm
inv_exit:
        di
        xra     a
        sta     inv_active
        call    inv_restore_leds
        call    inv_restore_terminal_state
        call    clear_keyboard
        ei
        ret
```

## Frame Clock

Use the low byte `frame_count` as the hardware refresh marker. The game keeps a
separate 16-bit logical frame counter for gameplay timing.

```asm
inv_wait_frame:
        lda     frame_count
        lxi     h,inv_last_vframe
        cmp     m
        jz      inv_wait_frame
        mov     m,a
        call    inv_inc_frame16
        ret

inv_inc_frame16:
        lxi     h,inv_frame_lo
        inr     m
        rnz
        inx     h
        inr     m
        ret
```

At 60 Hz, `vtinvaders` timings map directly. At 50 Hz, either accept slightly
slower play or scale long timers using `refresh_rate`.

## Main Game Loop

The C++ reference does this in `engine::run`:

1. Reset screen, status, shields, aliens, missiles, turret, laser, and UFO.
2. Initialize one alien per frame until all 55 are present.
3. Each frame, move one live alien.
4. Start full gameplay after `aliens::count + 73` frames.
5. Every third frame, possibly fire and update alien missiles.
6. Process turret movement, firing, explosions, and laser collisions.
7. Flush only the changed output.

The firmware loop should keep the same ordering:

```asm
inv_frame:
        call    inv_spawn_one_alien     ; Z while still spawning
        rz

        call    inv_update_alien        ; one live alien per frame
        call    inv_update_heartbeat
        call    inv_score_pending_kill
        call    inv_check_landed
        call    inv_check_level_done

        call    inv_update_ufo
        call    inv_update_shields

        call    inv_after_start_gate    ; frame >= 55 + 73
        rz

        call    inv_enemy_fire_tick     ; every 3 frames
        call    inv_update_missiles

        call    inv_update_turret
        call    inv_update_laser
        ret
```

When `inv_check_level_done` sees no remaining aliens and the turret is not
exploding, pause for about 30 frames, increment `inv_level`, and restart the
level with lower initial alien rows.

## Keyboard Handling

Game input should read raw scan results, not normal translated terminal reports.
`keyboard_int` already queues up to four scan codes in `key_silo`; `update_kbd`
keeps the keyboard scan and LED/status write side alive.

`inv_read_keys` can interpret the scan codes directly:

- left arrow: set `inv_left_pressed`
- right arrow: set `inv_right_pressed`
- space: set `inv_fire_pressed`
- SET-UP: call `inv_exit`
- `q`, `Q`, or a chosen control chord: call `inv_exit`

The exact scan codes should be confirmed on real hardware or MAME. For the
first implementation, it is acceptable to support a small physical-key subset
with a table near the game code:

```asm
inv_key_table:
        db      <left_scan>,  inv_key_left
        db      <right_scan>, inv_key_right
        db      <space_scan>, inv_key_fire
        db      7bh,          inv_key_setup
        db      <q_scan>,     inv_key_quit
        db      0ffh
```

After consuming keys, clear the stock keyboard silo with `clear_keyboard` or an
equivalent local routine. Do not call `send_key_byte` while the game is active.

## Keyboard LEDs

The game should use the four VT100 keyboard LEDs as the gunner counter. During
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

On entry, save the previous `led_state` byte in AVO RAM. On exit, restore it so
terminal mode gets its previous LEDs back. Gunner LEDs should be refreshed on
game start, after losing a gunner, after earning an extra gunner, and when
entering game-over state.

## Heartbeat Sound

The game should use the VT100 keyboard click for the Space Invaders heartbeat.
The stock firmware already sends the click bit through `update_kbd`: it ORs
`kbd_click_mask` into the keyboard status byte, writes `iow_keyboard`, and then
clears `kbd_click_mask`. That makes `kbd_click_mask` a good one-frame,
one-shot sound latch.

Do not call `make_keyclick` for the heartbeat. That routine checks
`setup_b2 & sb2_keyclick`, which is appropriate for typing but not for an
intentional game sound effect. Also avoid `bell_duration`: the bell path is a
longer alert and uses `kbd_online_mask` during vertical interrupt processing,
so it is not the right shape for a rhythmic heartbeat.

The heartbeat routine can write `iow_kbd_click` directly:

```asm
inv_click:
        mvi     a,iow_kbd_click
        sta     kbd_click_mask
        ret
```

Call `inv_update_heartbeat` once per game frame after `inv_update_alien`. The
sound should stop while the turret is exploding, during level pauses, and after
game over. The period should shrink as aliens are killed so the click cadence
accelerates with the game:

```asm
inv_heartbeat_timer db 0
inv_heartbeat_phase db 0

inv_update_heartbeat:
        lda     turret_state
        ora     a
        rnz
        lda     alien_dead_count
        call    inv_heartbeat_period   ; A = period in frames
        lxi     h,inv_heartbeat_timer
        dcr     m
        rnz
        mov     m,a
        call    inv_click
        lxi     h,inv_heartbeat_phase
        inr     m
        ret
```

Suggested 50/60 Hz frame periods:

```text
55-45 aliens remaining: 32 frames
44-30 aliens remaining: 24 frames
29-15 aliens remaining: 16 frames
14-7 aliens remaining:  10 frames
6-1 aliens remaining:   6 frames
```

The VT100 click has fixed pitch and duration, so `inv_heartbeat_phase` cannot
produce true four-tone arcade audio. It is still useful for patterning: every
fourth beat can be skipped or doubled if playtesting needs a stronger
"marching" feel. The simplest implementation should use one click per beat.

## Screen Model

The hybrid playfield keeps the VT100-friendly fixed dimensions from
`vtinvaders`, but uses taller `ascii-invaders`-style sprites:

- physical width: 80 columns
- logical playfield width: 60 columns, centered or left-biased inside the
  physical display
- height: 24 rows
- UFO rows: 2 and 3
- alien rows: 2 visible rows in a 3-row slot
- shield rows: 19, 20, and 21
- turret rows: 22 and 23
- score/status row: 24

The original `ascii-invaders` alien silhouettes are six columns wide including
padding. The firmware version trims them to four visible columns in a five-cell
slot. That keeps the 11-column arcade formation inside a 60-column playfield:

```text
11 columns * 5-cell slots = 55 columns
```

The recommended geometry is:

```asm
inv_play_w      equ 60
inv_alien_cols  equ 11
inv_alien_rows  equ 5
inv_alien_w     equ 4        ; visible sprite width
inv_alien_slot  equ 5        ; width plus one blank column
inv_alien_h     equ 2
inv_alien_vslot equ 3        ; height plus one blank row
inv_ufo_w       equ 7
inv_ufo_h       equ 2
inv_gunner_w    equ 7
inv_gunner_h    equ 2
inv_shelter_w   equ 7
inv_shelter_h   equ 3
```

The game should render into normal VT100 screen RAM. A simple first pass can use
a direct row-address table in the AVO ROM. Do not store this table in AVO RAM:
the AVO RAM is nibble-wide, so it is unsuitable for 16-bit screen pointers.

```asm
inv_row_addr:
        dw      main_video+(inv_row_stride*0)
        dw      main_video+(inv_row_stride*1)
        ; ...
        dw      main_video+(inv_row_stride*23)
```

`inv_init_screen` should:

1. Stop normal receive processing for game mode.
2. Rebuild a stable 80-column screen using the stock screen setup routines or a
   private 60-column-centered layout.
3. Clear the visible playfield.
4. Draw shields, score, and any static playfield decoration.
5. Reset the cursor state or hide the cursor by keeping the cursor off-screen.

Rendering routines should update only cells that changed:

```asm
; input: B = row, C = column, A = character
inv_putc:
        ; use inv_row_addr[row] + column to find screen RAM
        ; write already-mapped glyph byte
        ; optionally write normal AVO attribute byte if attributes are enabled
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

If enough RAM is available, keep a compact 60 by 24 object-id shadow map in AVO
RAM. That is 1440 bytes and makes collision tests cheap. If code simplicity is
more valuable than RAM, this is the easiest route:

```asm
id_empty        equ 0ffh
id_shield       equ 0f0h
id_turret       equ 0f1h
id_missile      equ 0f2h
id_ufo          equ 0f3h
id_alien0       equ 00h         ; 00h-36h are the 55 alien IDs

inv_id_map      ds 60 * 24
```

Without a shadow map, collisions can be resolved from entity coordinates and
shield damage state. That saves RAM but costs more code.

## Special Graphics Encoding

The VT100 firmware already knows the DEC Special Graphics character set.
`charset_list` maps SCS final `0` to internal charset value `88h`, and
`print_char` maps Special Graphics source bytes from `05fh` through `07eh` down
to ROM glyphs `00h` through `1fh`. The game should use the same mapping for
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

Sprite tables in this design are written with the Special Graphics source
characters for readability. For example, source `lqqk` means "upper-left
corner, horizontal line, horizontal line, upper-right corner." The assembled
table should either store those source bytes and have `inv_puts_sg` subtract
`05fh`, or pre-convert the table to ROM glyph numbers. Pre-converted tables are
faster and smaller at runtime.

Direct screen RAM writes should not change `g0_charset`, `g1_charset`, or
`gl_invocation`. Those variables matter when characters pass through
`print_char`; the game is writing already-mapped glyph numbers to screen RAM.
On game exit, normal terminal character-set state should therefore be unchanged
unless the entry path intentionally used the parser for diagnostics.

The ordinary ASCII set should still be used for text such as `SCORE`,
`GAME OVER`, and decimal point values. DEC Special Graphics is for moving game
sprites, shelters, missiles, and decorative playfield marks.

## Proposed Special Graphics Rendering

These sprites are written as DEC Special Graphics source characters, not as the
literal ASCII characters that should appear on screen. They are derived from
the silhouettes in `ascii-invaders`, with horizontal padding trimmed where
useful. They are designed for direct screen RAM writes and for a simple
object-ID shadow map.

### Alien Formation

There are 5 rows and 11 columns. Each alien is 4 visible columns wide in a
5-column slot. Each alien is 2 rows tall in a 3-row vertical slot.

```text
30-point alien, animation A, source:
laak
maaj

30-point alien, animation B, source:
lqqk
maaj

20-point alien, animation A, source:
lqqk
x__x

20-point alien, animation B, source:
xqqx
mqqj

10-point alien, animation A, source:
_lqk
mqj_

10-point alien, animation B, source:
lqk_
_mqj

Alien explosion, source:
qnnq
xnnx

Landed alien, source:
laak
maaj
```

Here `_` means the Special Graphics blank glyph, not ASCII underscore. These
shapes use line corners for the outline and checkerboard fill for stronger
aliens. The 10-point alien intentionally shifts left/right between animation
frames, echoing the wiggle in both references.

When converting these diagrams to byte tables, right-pad each row to its
declared sprite width; markdown may not show trailing spaces. The animation
phase can be selected from the formation phase or from alien X coordinate
parity; the important point is to keep it global and cheap.

Recommended row types:

```text
top row:          30-point alien
next two rows:    20-point alien
bottom two rows:  10-point alien
```

### Player Turret

Use the `ascii-invaders` gunner as the player turret. It is 7 columns wide and
2 rows tall, rendered with checkerboard cells.

```text
Normal, source:
___a___
_aaaaa_

Explosion frame A, source:
__n_n__
_n_n_n_

Explosion frame B, source:
_q_n_q_
n__n__n
```

The turret collision point is the center column, `turret_x + 3`. The player
laser starts above that column.

### Player Laser

```text
Normal shot, source:          x
Top sparkle phase 1, source:  n
Top sparkle phase 2, source:  a
```

The laser is a single active shot. Use Special Graphics vertical line and cross
glyphs, while keeping the `vtinvaders` single-shot state machine and hit
ordering.

### Alien Missiles

Use a one-cell rotating bomb glyph, but keep `vtinvaders` fixed missile slots
and firing cadence.

```text
Bomb animation source:       x q n a
Laser/bomb collision source: n
Ground explosion A source:   a
Ground explosion B source:   n
Ground scar, even source:    o
Ground scar, odd source:     s
```

Three missile slots are enough. Keep the `vtinvaders` pacing: one active
missile until frame 2000, then up to three. A new missile may launch 50 frames
after the last launch, or 12 frames after all missiles have ended.

### UFO

Use the `ascii-invaders` mystery ship. It is 7 columns wide and 2 rows tall,
moving on rows 2 and 3.

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

The reference alternates UFO direction based on the number of player shots
fired. Preserve that rule because it costs little and gives deterministic
arcade-like behavior.

### Shields

Use the `ascii-invaders` shelter as the preferred shield. It is 7 columns wide
and 3 rows tall.

```text
Initial, source:
_lqqqk_
laaaaak
aaa_aaa
```

Because AVO RAM is nibble-wide, store the shield as one 4-bit cell code per
visible shield cell rather than as full glyph bytes or packed damage nibbles.
The cell code indexes a ROM glyph table when rendering. Any code other than
`inv_cell_blank` is solid. A missile or laser hit turns the struck cell into
`inv_cell_blank`, optionally also eroding one neighboring cell to make damage
look less like pinholes.

```text
Light top hit, source:
_l__qk_
laaaaak
aaa_aaa

Light bottom hit, source:
_lqqqk_
laaaaak
aa___aa

Heavy damage, source:
_l___k_
la___ak
a_____a
```

This is less compact than the earlier 4-column damage-nibble design, but it is
simpler to test, fits the AVO RAM hardware, and looks much better. The packed
damage design remains a fallback if the AVO memory budget tightens.

### Ground And Status

```text
Status row 24:               SCORE 0000
Game over center:            GAME OVER
```

Gunners are shown on the keyboard LEDs rather than in the playfield. If
double-width line support is wanted for score or game-over text, it can be
added later. The first implementation should keep all game lines single-width
to simplify addressing.

## Entity State

With AVO RAM available, store clear per-entity state rather than packing every
bit immediately.

```asm
inv_active          db 0
inv_last_vframe     db 0
inv_frame_lo        db 0
inv_frame_hi        db 0

inv_level           db 0
inv_score_lo        db 0
inv_score_hi        db 0
inv_gunners         db 3
inv_game_over       db 0
inv_play_x          db 10       ; physical column for logical playfield col 0
inv_saved_leds      db 0        ; previous low nibble of terminal led_state
inv_heartbeat_timer db 0
inv_heartbeat_phase db 0

inv_left_pressed    db 0
inv_right_pressed   db 0
inv_fire_pressed    db 0

turret_x_lo         db 4        ; left edge of 7-column gunner sprite
turret_x_hi         db 2        ; 24h = physical column 36
turret_state        db 0        ; 0 normal, 1 exploding
turret_timer        db 0

laser_x             db 0
laser_y             db 0
laser_phase         db 0
laser_active        db 0
laser_shots         db 0

alien_last          db 0ffh
alien_xdelta        db 1
alien_ydelta        db 0
alien_reverse       db 0
alien_kill_timer    db 0
alien_killed_id     db 0
alien_dead_count    db 0
alien_landed        db 0
alien_best_column   db 0
alien_shot_index    db 0
alien_anim_phase    db 0
alien_bottom_y      db 17       ; top row of bottom alien sprite
alien_min_col       db 0
alien_max_col       db 10
alien_min_row       db 0        ; lowest live row index
alien_max_row       db 4        ; highest live row index
alien_x             ds 55
alien_y             ds 55
alien_live_bits     ds 7
alien_shooters      ds 11       ; alien ID per firing column, 0ffh if none

missile_x           ds 3
missile_y           ds 3
missile_phase       ds 3
missile_active      ds 3
missile_active_n    db 0
missile_fire_lo     db 0
missile_fire_hi     db 0

ufo_state           db 0        ; 0 idle, 1 active, 2 exploding, 3 score
ufo_x               db 0
ufo_dx              db 0
ufo_death_lo        db 0
ufo_death_hi        db 0
ufo_points          db 0
ufo_disabled        db 0

shield_cells        ds 84       ; 4-bit cell codes, not full glyph bytes
shield_x            ds 4        ; left edge of each shelter
```

`alien_live_bits` can store 55 live/dead bits. The simpler alternative is one
byte per alien, but seven bytes is easy enough and keeps the state tidy.

## Alien Update

`vtinvaders` moves only one live alien per frame. This is the most important
performance trick to preserve.

```asm
inv_update_alien:
        lda     alien_kill_timer
        ora     a
        jnz     inv_update_kill_timer

        lda     turret_state
        ora     a
        rnz

        call    inv_next_live_alien     ; updates alien_last
        call    inv_check_cycle_wrap
        call    inv_move_current_alien
        call    inv_update_best_shooter
        ret
```

On cycle wrap:

- recompute the formation horizontal offset from the first live alien in the
  new sweep;
- clear `alien_ydelta`;
- if `alien_reverse` is set, negate `alien_xdelta`, set `alien_ydelta` to 1,
  and clear `alien_reverse`.

When an alien reaches the left or right boundary, set `alien_reverse`. The
actual reversal and downward step happen on the next sweep.

Borrow `ascii-invaders`' formation trimming idea as cached bounds. After a kill,
if the killed alien was on `alien_min_col`, `alien_max_col`, `alien_min_row`, or
`alien_max_row`, rescan only that edge and update the cached value. The edge
cache makes boundary checks, collision coarse tests, and row clearing cheaper
with the wider two-line sprites.

## Alien Firing

The firing column should follow the fixed `vtinvaders` shoot order. Values of
zero mean "use the column closest to the turret"; other values select a 1-based
alien column. If the selected column has no shooter, advance through the table
until a live shooter is found.

```asm
inv_shoot_order:
        db 0,1,11,1,0,7,0,1,6,3,0,1,1,0,1,1,0,4,11
        db 9,2,0,11,0,1,8,2,0,6,0,3,11,4,0,1,7,0,1
        db 0,11,0,9,0,2,10,11,1,0,8,0,1,6,3,0,7,0,1
        db 1,0,1,1,0,1,11,9,2,0,4,0,11,0,9,0,1,0,5
inv_shoot_order_len equ 74
```

Fire from `alien_y + 1`, `alien_x + 1`. Keep `alien_shooters[column]` updated
when an alien dies: if the killed alien was the bottom live alien in that
column, search upward for the next live alien.

## Missile Update

Every third frame after the start gate:

1. If aliens can fire, missiles can fire, and the turret is not exploding, call
   `inv_alien_fire`.
2. Update all active missile slots.
3. On collision with the player laser, cancel both shots and draw a brief `*`.
4. On collision with turret, start turret explosion.
5. On collision with shield, erode the shield from above.
6. On ground impact, show a short two-frame explosion and then a small scar.

The frame modulo test can use the low logical frame byte:

```asm
        lda     inv_frame_lo
        ; divide or table-test for frame % 3
```

A cheaper implementation can maintain a 0,1,2 counter instead of dividing.

## Turret And Laser Update

When the turret is alive:

- reveal it on the start gate frame;
- apply one left or right movement flag per frame;
- consume one fire flag if no laser is active and no alien explosion is in
  progress.

When the turret is exploding:

- toggle explosion sprite every 5 frames;
- after 55 frames, clear the turret;
- lose one gunner, or all gunners if aliens landed;
- call `inv_update_gunner_leds`;
- either reset the turret or enter game-over state.

Laser update:

```asm
inv_update_laser:
        lda     laser_active
        ora     a
        rz
        call    inv_test_laser_hit
        call    inv_render_laser_phase
        call    inv_advance_laser
        ret
```

Hit priority should be shield, UFO, alien. Alien hits set `alien_kill_timer` to
16 and render the killed-alien explosion immediately. Points are awarded when
the timer expires, matching the reference.

## UFO Update

Use the reference timing:

- first UFO: around frame `35 * 60`;
- later UFOs: every `25 * 60`;
- move every 5 frames;
- disable UFOs when fewer than 8 aliens remain;
- direction depends on `laser_shots` parity;
- point value depends on `laser_shots` modulo 15.

Point table:

```asm
inv_ufo_points:
        db 100,50,50,100,150,100,100,50,300,100,100,100,50,150,100
```

If storing values above 255 is inconvenient, encode UFO points as score units of
10, i.e. `10,5,5,10,15,10,10,5,30,10,10,10,5,15,10`.

## Shield Damage

The preferred AVO implementation stores shields as one 4-bit cell code per
visible shield cell:

```asm
shield_cells        ds 84       ; 4 shields * 7 columns * 3 rows
shield_x            ds 4
```

A code other than `inv_cell_blank` is solid. `inv_cell_blank` is already
destroyed. Rendering expands the current `shield_cells` codes through a ROM
glyph table, writes those glyphs to screen RAM, and writes `id_shield` to the
object map for every non-blank glyph.

On a hit from above:

1. convert the playfield hit coordinate to shelter number, local X, and local Y;
2. scan downward from the top row at that local X until a non-blank cell is
   found;
3. blank that cell;
4. optionally blank one nearby lower-left or lower-right cell using a small
   deterministic pattern.

On a hit from below:

1. convert the playfield hit coordinate to shelter number, local X, and local Y;
2. scan upward from the bottom row at that local X until a non-blank cell is
   found;
3. blank that cell;
4. optionally blank one nearby upper-left or upper-right cell.

This reproduces the feel of `ascii-invaders`, where shelters are simply glyph
art with cells erased by shots. It is also easier to test than a
packed damage state: MAME tests can compare the 84 shield cell codes directly.

The earlier packed-column design remains a compact fallback. In that version,
each 4-column shield column has a 4-bit damage value:

```asm
; compact fallback from above
damage = (((damage >> 1) + 8) & 15) | (damage & 7)

; compact fallback from below
damage = (((damage << 1) + 1) & 15) | (damage & 14)
```

If used, implement those transforms as small table lookups:

```asm
shield_hit_above_table:
        db 8,9,9,11,10,11,11,15,12,13,13,15,14,15,15,15

shield_hit_below_table:
        db 1,3,5,7,5,7,13,15,9,11,13,15,13,15,15,15
```

## Collision Strategy

Preferred AVO-RAM implementation:

- maintain `inv_id_map` for the 60 by 24 logical playfield;
- every sprite write updates both screen RAM and object ID map;
- blank characters write `id_empty`;
- `sg_blank` writes `id_empty`, while every remaining shield glyph writes
  `id_shield`;
- multi-line sprites write IDs for each non-blank glyph, not for the whole
  bounding rectangle.

This matches the reference design closely and keeps missile/laser collision code
small. It is especially helpful with the larger sprites because the bounding
boxes contain deliberate blank glyphs.

If `inv_id_map` is too expensive, switch to coordinate tests:

- test UFO rectangle;
- test current live alien rectangles;
- test shield cells;
- test turret rectangle;
- treat the screen edge below the turret as the bottom boundary.

The map costs 1440 bytes, which is acceptable under the AVO assumption.

## Level Reset

The larger Special Graphics sprites cannot reuse the `vtinvaders` one-row alien
offsets literally. Keep the same ID layout, but compute positions with the
2-row sprite and 3-row slot geometry.

Alien IDs should still be arranged with the bottom row first:

```text
id 0..10     bottom row, 10-point aliens
id 11..21    next row, 10-point aliens
id 22..32    middle row, 20-point aliens
id 33..43    next row, 20-point aliens
id 44..54    top row, 30-point aliens
```

That preserves the useful `vtinvaders` shooter rule: the next shooter above a
killed alien is `id + 11`.

Recommended starting bottom-row Y positions:

```asm
level 0: bottom-row sprite y = 16
level 1: bottom-row sprite y = 16
level 2: bottom-row sprite y = 17
level 3+: bottom-row sprite y = 17
```

For alien ID `id`:

```text
row = id / 11        ; 0 is bottom, 4 is top
col = id % 11
y   = alien_bottom_y - row * inv_alien_vslot
x   = alien_left_x + col * inv_alien_slot
type = 10, 20, or 30 points from the row table above
```

With `alien_bottom_y = 16`, the top row occupies rows 4 and 5 and the bottom
row occupies rows 16 and 17, leaving row 18 as a buffer before the shelters.
With `alien_bottom_y = 17`, the top row occupies rows 5 and 6 and the bottom
row occupies rows 17 and 18, immediately above the shelter rows. If this feels
cramped on hardware, keep the visual sprites but reduce the formation to 4 rows
rather than shrinking the sprites.

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
   from `3fffh` inside AVO RAM.
4. Direct MAME Lua smoke tests inspect ROM entry points and AVO RAM without
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

Test-only state bytes live in AVO RAM and are defined in `src/invaders-abi.asm`
alongside the rest of the game ABI. Keep these in the same top-down allocation
style as the game state, and load their addresses from `invaders.equ` in tests
instead of duplicating numeric addresses.

```asm
inv_test_signature  equ     inv_data_top-2        ; 3 bytes, through 3fffh
inv_test_mode       equ     inv_test_signature-1
inv_test_script     equ     inv_test_mode-1
inv_test_stop_lo    equ     inv_test_script-1
inv_test_stop_hi    equ     inv_test_stop_lo-1
inv_test_result     equ     inv_test_stop_hi-1
inv_test_trace_head equ     inv_test_result-1
inv_test_trace_top  equ     inv_test_trace_head-1
inv_test_trace_base equ     inv_test_trace_top-inv_test_trace_size+1
```

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

### Screenshot Regression

Screenshot tests should use a small set of deterministic frames:

| Frame | Expected screen state |
|---:|---|
| 0 | cleared playfield and static status |
| 55 | alien formation has completed initialization |
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
  symbols, and writable AVO RAM;
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
- Can AVO attributes be disabled or ignored while game state occupies AVO RAM,
  or should the game reserve a safe subrange that does not conflict with active
  attribute bytes?
- Does the installed MAME `vt100` configuration expose both the `8000h`
  expansion ROM and the `3000h`-`3fffh` AVO RAM range, or do we need a small
  driver patch for full automated testing?

# Implementation

Each slice should leave the repository in a buildable, testable state. Add tests
as CTest tests, and exercise the complete implementation with
`cmake --workflow --preset invaders`. CTest entries should run CMake driver
scripts from `src/tests`. For MAME-backed tests, those CMake scripts set the
working directory to `<MAMEDir>`, run `mame.exe` against the staged ROMs, and
pass the matching Lua script with `-autoboot_script`. MAME Lua test scripts and
shared Lua helpers also live under `src/tests`.

The base ROM is space constrained. Invaders changes in `base.asm` must remain
same-size trampoline replacements of existing bytes with calls into the AVO ROM.
The AVO ROM must repeat the displaced base-ROM bytes on normal terminal paths.
Static tests should fail if `invaders.bin` differs from `vt100.bin` outside the
explicit trampoline spans and checksum bytes.

## 11. Enemy Missiles, Turret Death, And Game Over

Implement enemy fire using the deterministic shooter order. Track a small fixed
set of missiles, move them downward, collide with shields and the turret, and
advance the gunner/death sequence. Losing a gunner should update LEDs and
respawn the turret after the configured delay. Losing the final gunner should
enter game-over state and stop active play until SET-UP exits or a restart path
is added.

Test this slice with a CTest test whose CMake driver launches
`src/tests/mame-invaders-enemy-fire.lua`. Select a known shooter script, run
until a missile hits a shield, then until a missile hits the turret. Assert
missile slots, shield damage, gunner count, LED mask, death timer, respawn
state, and final game-over state.

## 12. UFO, Heartbeat, Exit, And Regression Gate

Finish the remaining arcade polish and close the regression loop. Add UFO
timing, movement, collision, and score selection. Drive the keyboard click
heartbeat from alien movement cadence. Harden `inv_exit` so it restores or
rebuilds terminal state, clears transient game state, restores LEDs, and returns
the terminal to normal input handling. Add CTest entries for the MAME Lua smoke
tests once the local MAME invocation is stable, and include them in the workflow
preset's normal test pass.

Test this slice with a CTest test whose CMake driver launches
`src/tests/mame-invaders-full-smoke.lua`. Run from a clean ROM install, enter
the game, execute scripted movement and firing, wait through alien movement,
enemy fire, UFO appearance, and exit. Assert the high-level acceptance gates
listed above, add screen-RAM golden checks for a small set of deterministic
frames, and exercise the whole suite with `cmake --workflow --preset invaders`.
Keep hardware testing as the final gate for keyboard feel, brightness, AVO
attribute behavior, and exact video timing.
