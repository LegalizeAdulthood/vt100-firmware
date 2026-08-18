# VT100 Firmware Squish Notes

## Screen Saver Code Refactoring Opportunities

This section records a review of the `VT100-Hax` screen saver code after
surveying the full repertoire of routines in `vt100-firmware/src/vt100.asm`.
The goal here is to reduce the screen saver code itself without removing
functionality.

The current `VT100-Hax/ROMs/haxrom.d80` implementation uses about 105 ROM bytes
of new code:

| Piece | Bytes | Notes |
|---|---:|---|
| `in_kb` wrapper | 14 | Saves `PSW`/`H`, samples keyboard port, conditionally leaves saver, jumps to original keyboard handler. |
| `in_rcv` wrapper | 10 | Saves `PSW`/`H`, always leaves saver, jumps to original receiver handler. |
| `in_vrt` wrapper | 50 | Saves `PSW`/`H`, handles countdown, enters saver by swapping `line1_dma`, jumps to original vertical handler. |
| `call initss` initialization hook | 3 | Added after terminal/NVR initialization. |
| `initss` | 11 | Resets countdown and active state. |
| `lv_ss` | 17 | If active, restores saved `line1_dma`; then resets countdown and state. |
| **Total** | **105** | Does not include reclaimed space from deleted POST diagnostics. |

### Main conclusion

The strongest screen-saver-specific byte win is not reuse of large stock helper
routines. It is tighter integration with the stock interrupt handlers.

The hax ROM currently wraps `keyboard_int`, `receiver_int`, and `vertical_int`
from the interrupt vectors. Those stock handlers already save the registers they
need:

- `keyboard_int` saves `PSW`, `H`, and `B`.
- `receiver_int` saves `PSW`, `B`, and `H`.
- `vertical_int` saves `PSW`, `H`, `D`, and later `B`.

Because of that, the screen saver wrappers pay redundant save/restore overhead.
Folding the saver hooks into the existing handlers should preserve behavior and
save roughly 22 bytes before any logic cleanup:

| Current wrapper | Current bytes | Likely integrated form | Estimated saving |
|---|---:|---|---:|
| `in_kb` | 14 | Add a small "real keypress?" test after the stock keyboard port read. | ~8 |
| `in_rcv` | 10 | Call or inline leave-saver logic after the stock receiver has accepted a non-local, non-NUL character. | ~7 |
| `in_vrt` | 50 | Add countdown logic inside `vertical_int` after its existing `push psw/push h`. | ~7 |

### Use `SSprv` as the active flag

The current screen saver keeps a separate state byte:

```asm
SSst   equ 022c5h
SSprv  equ 022c6h
```

Only bit 1 of `SSst` is used. This can likely be removed by using the high byte
of `SSprv` as the active flag:

- inactive: `SSprv+1 == 0`
- active: `SSprv` contains the saved `line1_dma`, whose high byte is nonzero

This makes entering the saver naturally mark it active when the current
`line1_dma` is saved. Leaving the saver restores `line1_dma` and then clears the
high byte of `SSprv`.

Possible smaller `lv_ss`:

```asm
lv_ss:
        lhld    SSprv
        mov     a,h
        ora     a
        jz      initss
        shld    line1_dma
        jmp     initss
```

This version removes the `lda SSst / ani 02h` state test and the separate state
byte. It also makes the `SSst` RAM byte available for other use.

Risk: low to medium. This assumes that no valid saved `line1_dma` has a zero
high byte. In stock operation, `line1_dma` is a DMA-order pointer into screen
layout memory and its high byte is not zero.

### Merge active-state clearing into `initss`

With `SSprv+1` as the active flag, `initss` can reset both the countdown and the
active marker. A compact form is:

```asm
initss:
        lxi     h,8ca0h
        shld    SSvfl
        mvi     h,0
        shld    SSprv
        ret
```

This is 11 bytes, the same size as the current `initss`, but it removes the need
for `SSst` and lets `lv_ss` shrink.

If the vertical countdown is changed to decrement before testing, use `8ca1h`
instead of `8ca0h` to preserve the effective timeout.

### Shrink the vertical countdown logic

The current `in_vrt` tests for zero before decrementing:

```asm
        lhld    SSvfl
        cmp     h
        jnz     no_ss
        cmp     l
        jnz     no_ss
        ; enter saver
no_ss:
        dcx     h
        shld    SSvfl
```

A smaller shape decrements first, stores the new value, then tests `HL`:

```asm
        lhld    SSvfl
        dcx     h
        shld    SSvfl
        mov     a,h
        ora     l
        jnz     inv_dn
```

This avoids the two `cmp`/branch pairs. To preserve the old duration, initialize
the countdown one higher.

Combined with `SSprv`-as-state, the vertical routine can test whether the saver
is already active by loading `SSprv`, checking `H`, and skipping countdown work
when active. That avoids a separate `SSst` read.

Risk: low. The only intentional behavior change to guard against is an
off-by-one frame in the timeout, handled by changing the initial value.

### Use `line0_dma` instead of hard-coded `0370h`

When entering the saver, the hax code points `line1_dma` at `0370h`:

```asm
        lxi     h,0370h
        shld    line1_dma
```

The stock firmware already maintains the fill-line DMA pointer in `line0_dma`.
Using that value is the same size:

```asm
        lhld    line0_dma
        shld    line1_dma
```

This does not save bytes, but it is a better integration with `vt100.asm`
because `update_dc011` chooses `0370h` for 60 Hz and `0970h` for 50 Hz. It keeps
the screen saver aligned with the existing video timing setup.

Risk: low.

### Avoid large stock display helpers

The existing helper routines are not good replacements for the screen saver's
core trick:

- `clear_display` and `init_screen` rebuild or clear display state rather than
  merely blanking/restoring the live screen.
- `move_updates` recalculates cursor state and has visible cursor side effects.
- `wait_n_frames` is useful for screen rebuild timing but costs more than the
  direct `line1_dma` swap.
- `to_ground`/`install_action` are parser-state helpers, not useful for saver
  activation.

The screen saver is already using the cheapest available mechanism: save
`line1_dma`, point display DMA at a fill line, then restore `line1_dma` on
activity. Refactoring should keep that strategy.

### Possible integrated shape

One plausible implementation outline is:

```asm
; Called after stock init has established line0_dma and line1_dma.
initss:
        lxi     h,8ca1h        ; one higher if countdown decrements first
        shld    SSvfl
        mvi     h,0
        shld    SSprv          ; also marks inactive
        ret

; Called on real keyboard/receiver activity.
lv_ss:
        lhld    SSprv
        mov     a,h
        ora     a
        jz      initss
        shld    line1_dma
        jmp     initss

; Called from inside vertical_int, after PSW/H are already saved.
tick_ss:
        lhld    SSprv
        mov     a,h
        ora     a
        rnz                     ; already active
        lhld    SSvfl
        dcx     h
        shld    SSvfl
        mov     a,h
        ora     l
        rnz
        lhld    line1_dma
        shld    SSprv           ; also marks active
        lhld    line0_dma       ; respects 50/60 Hz fill pointer
        shld    line1_dma
        ret
```

Whether `tick_ss` should be a subroutine or inline code depends on placement. If
there is only one vertical call site, inlining saves the `call`/`ret` overhead.
If it can sit in a reclaimed hole and be called from a tiny stub, the subroutine
form may be easier to pack.

### Estimated size after refactor

Approximate target size:

| Piece | Estimated bytes |
|---|---:|
| Integrated keyboard hook | 5-6 |
| Integrated receiver hook | 3-6 |
| Integrated vertical hook or `tick_ss` call | 3-6 |
| `tick_ss`, if out-of-line | 31-35 |
| `initss` with state reset | 11 |
| `lv_ss` using `SSprv` as state | 13 |
| Init hook | 3 |
| **Likely total** | **68-74** |

That is a reduction of roughly 31-37 bytes from the current 105-byte hax
implementation.

### Caveats

- Integrating with stock handlers means editing original routines rather than
  redirecting interrupt vectors to wrappers. It saves bytes but is less isolated
  as a patch.
- The exact byte count depends on where the code is packed and whether the
  vertical code is inline or out-of-line.
- Any change to ROM bytes requires recomputing the POST checksum bytes if the
  checksum self-test remains enabled.
- The screen saver should be tested while receiving host data, while typing, in
  SET-UP, during smooth scroll, and across 50/60 Hz configurations.
