# VT100 Firmware Byte-Squish Review

This note records a space-saving review of `vt100-firmware/src/vt100.asm`.
The source file and its comments were treated as the ground truth.

The goal of this review is to find refactors and restructures that save ROM
bytes without losing VT100 functionality. Deleting diagnostics, setup features,
GPO/STP behavior, protocol responses, or terminal modes is intentionally out of
scope.

## Context

The firmware is an 8 KiB 8080 ROM image. The assembled output currently occupies
the whole `0000h`-`1fffh` address range, but not all of that range is functional
code or data.

Relevant generated files used during the review:

- `build-vt100-firmware-default/src/vt100.lst`
- `build-vt100-firmware-default/src/vt100.sym`
- `build-vt100-firmware-default/src/vt100.equ`
- `vt100-firmware/awnty/vt100-coverage.txt`

Important constraint: the ROM self-test checks each 2 KiB ROM with the
rotate-and-XOR checksum routine at `self_test`. Any byte-level change to the ROM
requires recomputing the checksum bytes if POST checksum behavior remains
enabled.

Known checksum locations in `vt100.asm`:

- ROM 1: line 747, `db 0ffh`
- ROM 2: line 2420, `db 42h`
- ROM 3: line 3820, `db 74h`
- ROM 4: line 4977, `sbb b`, probably checksum plus start of unreachable code

## Summary

The no-functionality-loss savings are close to, and possibly enough for, the
`VT100-Hax` screen saver, but not as one simple contiguous hole. The hax screen
saver uses about 105 bytes of new ROM code. A conservative review found roughly
75-85 bytes of plausible savings, plus larger timing-sensitive NVR refactoring
that could raise the total into the 100-byte range.

The most promising path is a ROM-packing exercise:

- put larger new code in the trailing `1fd7h`-`1fffh` slack;
- use small reclaimed holes for jump stubs or helper routines;
- refactor selected duplicated code to create additional space;
- recompute all affected ROM checksums.

## Candidate Savings

### 1. Factor NVR LBA7 polling loops

Estimated saving: 26-43 bytes.

Confidence: medium.

The ER1400 NVR routines repeatedly inline the same edge-wait idiom:

```asm
	in	ior_flags
	ana	c
	jz	...
```

and the matching low wait:

```asm
	in	ior_flags
	ana	c
	jnz	...
```

The pattern appears around:

- `read_nvr_data`: lines 4525, 4528, 4533, 4536, 4543, 4546, 4551, 4557
- `set_nvr_addr`: lines 4616, 4621, 4626
- `nvr_accept`: lines 4650, 4653
- `erase_nvr`: lines 4664, 4667
- `wait_nvr`: lines 4681, 4684
- `write_nvr`: lines 4696, 4699

A pair of helpers such as:

```asm
wait_lba7_high:
	in	ior_flags
	ana	c
	jz	wait_lba7_high
	ret

wait_lba7_low:
	in	ior_flags
	ana	c
	jnz	wait_lba7_low
	ret
```

would replace each 6-byte inline loop with a 3-byte call, at the cost of the
helper bodies. Replacing all 19 loops is a static saving of about 43 bytes:

- 19 inline loops at 6 bytes each: 114 bytes
- 19 calls at 3 bytes each: 57 bytes
- two helper bodies at 7 bytes each: 14 bytes
- net: 43 bytes

Risk: the NVR code comments emphasize timing, especially in `set_nvr_addr`,
where the address sequence must complete within a fixed number of LBA7 cycles.
The helper calls add call/return latency after the edge is detected. This may be
fine for long waits and command waits, but it should be tested on real hardware
or in a timing-aware emulator before applying everywhere.

Safer subset: factor only the less timing-critical waits in `erase_nvr`,
`wait_nvr`, and `write_nvr`, then measure. That probably saves less than the
full 43 bytes, but it is a better first move.

### 2. Remove redundant margin setup in `col_common`

Estimated saving: 11 bytes.

Confidence: high.

Both display-width entry paths call `make_line_t` before reaching `col_common`:

- `init_80col`, lines 1937-1944
- `init_132col`, lines 1949-1956

`make_line_t`, lines 3115-3153, already does:

- `top_margin <- 0`
- `bottom_margin <- last_row`

`col_common`, lines 1956-1963, repeats the same work:

```asm
col_common:	xra	a
		sta	top_margin
		call	last_row
		mov	a,b
		sta	bottom_margin
```

This block can be removed if `col_common` remains reachable only from the two
width initializers that have just called `make_line_t`.

Risk: low. Before changing, re-check that no new caller bypasses `make_line_t`.

### 3. Remove unreachable VT52 coordinate ESC path

Estimated saving: 12 bytes.

Confidence: high.

In `vt52_get_coord`, lines 1896-1904, this block is unreachable:

```asm
	cpi	C0_ESC
	lxi	h,got_vt52_row
	jnz	store_coord
	lxi	h,recog_esc
	shld	char_action
	ret
```

The reason is immediately above it: the routine tests for C0 controls with
`cpi 20h / jc exec_c0`. ESC is `1bh`, so ESC will have already gone to
`exec_c0` and cannot reach the later `cpi C0_ESC`.

The behavior-preserving shape is:

```asm
	lxi	h,got_vt52_row
	; fall through to store_coord
```

This removes the redundant compare, branch, and dead action reset.

Risk: low, assuming the current parser ordering is kept.

### 4. Drop unread/unwritten scratch RAM traffic

Estimated saving: 20 bytes.

Confidence: medium-high.

Several writes/reads target locations that the source itself labels as unread or
unwritten:

- lines 450-451:

```asm
	lxi	h,line1_dma
	shld	UNREAD_X2052
```

- lines 490-491:

```asm
	lxi	h,07ffh
	shld	UNREAD_X2149
```

- line 3072:

```asm
	shld	UNREAD_X2054
```

- lines 3785-3787:

```asm
	lda	UNWRIT_X2077
	ora	a
	rnz
```

The first three are writes to locations that are never read by firmware. The
last is a read from a location that firmware never writes; after scratch RAM is
cleared, it should remain zero unless an external agent pokes RAM.

Risk: moderate only because this changes RAM side effects. It should not change
terminal behavior, but it could matter to diagnostics, probes, or unknown
hardware/service assumptions.

### 5. Convert tail `call ... / ret` pairs to `jmp`

Estimated saving: 7 normal ROM bytes, plus 2 scattered RST-vector bytes.

Confidence: high.

Several routines end with a call followed immediately by `ret`. Replacing that
with `jmp` preserves behavior and saves one byte per normal site.

Normal ROM candidates:

- `tbc_action`, line 2425: `call clear_this_tab / ret`
- `check_tbc_opt`, line 2430: `call clear_all_tabs / ret`
- `mode_lookup`, line 3626: `call find_action_a / ret`
- `decom_mode`, line 3689: `call cursor_home / ret`
- `deccolm_mode`, line 3704: `call clear_display / ret`
- `post_nvr`, line 4953: `call setup_display / ret`
- `program_pusart`, line 5430: `call move_updates / ret`

RST vector candidates:

- line 58: `call vertical_int / ret`
- line 62: `call vertical_int / ret`

The RST vector cases are address-slot constrained by following `org`
directives, so they produce small vector-slot slack rather than shifting the
main body down.

Risk: low. Keep an eye on routines that intentionally use return-address tricks,
but these specific cases are ordinary tail calls.

### 6. Replace `real_addr2` clone with the existing `real_addr`

Estimated saving: 3 bytes.

Confidence: high.

`real_addr2`, lines 5004-5008, duplicates `real_addr`, lines 3354-3358:

```asm
	mov	a,h
	ani	0fh
	ori	20h
	mov	h,a
	ret
```

`extra_addr` can jump to `real_addr` directly. `wait_screen` would need to load
`wait_addr` and then jump to `real_addr`, because it currently falls through
into the local clone.

Net effect:

- remove 6-byte `real_addr2` body;
- add a 3-byte `jmp real_addr` after `wait_screen`;
- net saving: 3 bytes.

Risk: low.

### 7. Collapse `toggle_bit` padding and adjust `col_in_bits` entry

Estimated saving: 6 bytes.

Confidence: high.

`toggle_bit`, lines 4887-4890, contains four `nop`s already commented as likely
last-minute removed code:

```asm
	nop
	nop
	nop
	nop
```

Those can be removed.

There is also a source comment at lines 2504-2505 noting that `col_in_bits`
could have absorbed the preceding `mov d,a`. Current shape:

```asm
tab_offs:	mov	d,a
		lxi	h,tab_settings
col_in_bits:	rrc
```

Restructure to:

```asm
tab_offs:	lxi	h,tab_settings
col_in_bits:	mov	d,a
		rrc
```

Then callers no longer need to preload `D`:

- `toggle_bit`, line 4891: remove `mov d,a`
- `bit_from_setup`, line 5346: remove `mov d,e`; keep `mov a,e`

Risk: low if all `col_in_bits` callers are updated together. Current callers
are only `toggle_bit` and `bit_from_setup`; `tab_offs` falls through.

### 8. Peepholes in `program_pusart`

Estimated saving: 7 bytes.

Confidence: medium-high.

Refresh-rate selection at lines 5406-5410:

```asm
	lda	setup_b4
	ani	sb4_50Hz
	jz	is_60
	mvi	a,10h
is_60:	adi	20h
```

can be reduced to:

```asm
	lda	setup_b4
	ani	sb4_50Hz
	adi	20h
```

That preserves the current outputs:

- bit clear: `20h` for 60 Hz
- bit set: `30h` for 50 Hz

Estimated saving: 5 bytes.

Cursor-type selection at lines 5412-5416 can avoid the branch by shifting the
masked `sb1_curblock` bit down to bit 0 before calling `cursor_type`. That saves
about 1 byte.

Finally, line 5430 is one of the tail-call sites:

```asm
	call	move_updates
	ret
```

This can become:

```asm
	jmp	move_updates
```

Estimated saving: 1 byte.

Risk: low to medium. The refresh-rate rewrite is straightforward. The cursor
boolean rewrite should preserve the `A = 0/1` contract of `cursor_type`.

### 9. Modem/data-test peepholes

Estimated saving: 4-8 bytes.

Confidence: medium.

`data_failed`, lines 5569-5578, does:

```asm
	xra	a
	stc
	pop	d
	ret
```

Only carry is used by the caller, so the `xra a` before `stc` appears
unnecessary. Saving: 1 byte.

In `read_modem`, lines 5688-5694, the first `ani 20h` is already commented as
pointless:

```asm
	cma
	ani	20h
	xra	b
	ani	20h
```

The second mask is the one that matters. Saving: 2 bytes.

`modem_result`, lines 5703-5705, starts with `ora a` but then immediately
overwrites `A` with `C`, and the only caller follows the return with `cmp d`.
Saving: 1 byte.

Additional possible saving: the two `mvi a,0ffh / rnz` failure returns in
`read_modem` could likely become just `rnz`, because the only caller compares
the returned value against `D`, which ranges from 1 to 7. The natural failing
values are outside that range. This would save another 4 bytes, but it changes
the exact failure value returned by `read_modem`.

Risk: medium. These are probably behavior-preserving for current callers, but
they rely on `read_modem` not having an external contract of returning `0ffh`
on failure.

## Already-Available Space

These bytes do not require losing user-visible functionality, but using them
still requires ROM checksum handling and careful placement.

### Trailing ROM slack

Available space: 41 bytes.

The assembled image has zero fill from `1fd7h` through `1fffh`. This is the same
area used by `VT100-Hax` for `initss` and `lv_ss`.

Risk: low, except for checksum recomputation and any ROM-layout assumptions.

### RST vector gaps

Available space: scattered.

Coverage marks these as unreachable:

- `0007h`
- `000dh`-`000fh`
- `0015h`-`0017h`
- `0024h`-`0027h`
- `002ch`-`002fh`

These are not a convenient contiguous block, but they can hold tiny stubs or
single-byte data if a packing strategy needs them.

### Unreachable VT52 coordinate path

Available space after refactor: 12 bytes, near `0b27h`.

This is covered above as a direct refactor.

### Unreachable ROM 4 fragment

Available space: 9-10 bytes, near `1ba6h`.

Lines 4977-4983 are documented as unreachable:

```asm
	sbb	b
	cpi	61h
	rm
	cpi	7bh
	rp
	ani	0dfh
	ret
```

The first byte, `sbb b`, is probably the ROM 4 checksum byte. If checksum bytes
are recomputed elsewhere, this whole fragment may be reusable. If preserving the
same checksum-byte location matters, only the following 9 bytes should be
considered easy slack.

Risk: low for behavior, medium for checksum/layout.

## Candidates Rejected Or Deferred

### Dropping POST/RAM diagnostics

This is what `VT100-Hax` does to make a large early hole, but it loses
functionality. It is therefore out of scope for this review.

The hax ROM drops/skips:

- the ROM checksum pass;
- most of the RAM verification/pattern-test logic;
- the old final checksum-byte requirement.

### Removing data loopback or modem tests

The data loopback test begins at line 5548. The modem test begins at line 5602.
Together they are a large amount of code, but they are invoked by DECTST and are
documented behavior. Deleting them would save a lot of space, but it is not
functionality-preserving.

### Removing GPO, STP, SS2/SS3, or undocumented DEC sequences

These features may be tempting from a "minimum terminal" perspective, but the
source comments explicitly identify them as real VT100 behavior or option-card
behavior. They were not counted as byte-squish candidates.

### Sharing the `pop b / pop d / pop h / pop psw / ret` epilogue

This epilogue appears in both `vertical_int` and `print_char`, but only twice.
Turning it into a shared helper usually costs a 3-byte jump at each site and a
5-byte helper, so it does not save space unless more compatible epilogue sites
are found or one site can fall through naturally.

## Implementation Strategy

A careful implementation should proceed in small groups:

1. Apply high-confidence mechanical wins first:
   - tail-call conversions;
   - `toggle_bit` `nop` removal;
   - `col_common` redundant margin removal;
   - unreachable VT52 coordinate cleanup;
   - `real_addr2` clone removal.

2. Rebuild and compare behavior with the existing emulator/test harness.

3. Recompute checksum bytes and verify POST checksum behavior.

4. Apply medium-risk cleanup:
   - unread/unwritten scratch RAM traffic;
   - `program_pusart` peepholes;
   - modem/data-test peepholes.

5. Treat NVR wait factoring as a separate experiment:
   - first factor less timing-sensitive wait loops;
   - validate with the emulator;
   - test on real hardware if the screen saver ROM is intended for a physical
     VT100.

## Rough Byte Budget

Conservative, no NVR factoring:

| Candidate | Estimated bytes |
|---|---:|
| Redundant `col_common` margin setup | 11 |
| Unreachable VT52 coordinate path | 12 |
| Unread/unwritten scratch RAM traffic | 20 |
| Tail-call conversions | 7 |
| `real_addr2` clone removal | 3 |
| `toggle_bit` padding and `col_in_bits` entry | 6 |
| `program_pusart` peepholes | 7 |
| Modem/data-test peepholes, conservative | 4 |
| ROM 4 unreachable fragment after checksum byte | 9 |
| **Subtotal** | **79** |

Additional space:

| Candidate | Estimated bytes |
|---|---:|
| Trailing ROM slack, `1fd7h`-`1fffh` | 41 |
| Full NVR polling-loop factoring | up to 43 |
| Scattered RST-vector gaps | about 15 scattered |

Practical interpretation: preserving all functionality probably gives enough
raw bytes for the roughly 105-byte `VT100-Hax` screen saver, but fitting it cleanly
requires layout work. The screen saver cannot simply reuse the large early POST
hole from `VT100-Hax`, because that hole came from deleting diagnostics.
