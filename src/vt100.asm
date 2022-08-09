;
;  DZ80 V3.4.1 8080 Disassembly of VT100.bin
;  Initial disassembly: 2021-12-03 08:56
;  Last updated:        2022-08-09 11:00
;
;  Comments by Paul Flo Williams <paul@frixxon.co.uk>,
;  released under Creative Commons Attribution 4.0 International licence.
;
; Documentation random things:
; 1. Sequences not mentioned in User Guide:
;    a) DECHCP and its VT52 equivalent ESC ];
;    b) DECGON/DECGOFF,
;    c) SS2 and SS3.
;    DECHCP and DECGON are dependent on GPO anyway, but SS2/SS3 work for unexpanded VT100.
;    DECHCP is mentioned in TM p.A-21
;
; Comments on notation in comments:
; A <- x means "A becomes/is set to x", which frees up "=" to be the straightforward mathematical "is equal to"
; HL <- x means HL becomes x, mostly implying that HL is now a pointer to something at location x.
;
; References to TM here are all to EK-VT100-TM-003, "VT100 Series Video Terminal Technical Manual"
;
;	TM Table 4-2-3, p.4-18, explains the RST interrupt handling.
;	
;	Table 4-2-3  Interrupt Addresses
;
;	00H     Power-up (Not hardware driven)
;	08H     Keyboard
;	10H     Receiver
;	18H     Receiver and keyboard
;	20H     Vertical frequency
;	28H     Vertical frequency and keyboard
;	30H     Vertical frequency and receiver
;	38H     Vertical frequency, receiver and keyboard
;
		org	00h
start:		di
		lxi	sp,stack_top
		jmp	post
;
restart1:	org	08h
		call	keyboard_int
		ei
		ret
;
restart2:	org	10h
		call	receiver_int
		ei
		ret
;
restart3:	org	18h
		call	receiver_int
		call	keyboard_int
		ei
		ret
;
restart4:	org	20h
		call	vertical_int
		ret
;
restart5:	org	28h
		call	vertical_int
		ret
;
		org	30h
restart6:	call	receiver_int
		call	vertical_int
		ei
		ret
;
restart7:	org	38h
		jmp	restart6
;
; post
; self_test

; The only difference between "proper" POST and the Self Test invoked by DECTST is making sure that POST
; doesn't repeat indefinitely. As register E is a mask of requested tests and repeat indication, POST sets
; the mask just as if DECTST had been invoked with "just self-test, no repeats."
;
; TM §4.2.8, "Power-Up and Self-Test", p. 4-19, describes POST.
;
post:		mvi	e,1		; Pretend this is DECTST and we requested POST without repeats
;
; Self-test starts by checksumming ROMs, which is a rotate-and-XOR operation across all four 2K ROMs
; individually. The checksum is expected to produce a zero result, which is ensured by including a
; byte somewhere in each ROM that can mix-in to make zero. Checksum bytes are marked in this listing
; where they have been identified.
;
self_test:	di
		mvi	a,0fh
		out	iow_nvr_latch	; "standby" to NVR latch (see port definition for details)
		cma			; A <- 0xf0
		out	iow_brightness	; set mid brightness
		xra	a
		mov	d,a
		mov	l,a
		mov	h,a		; HL <- 0, starting address of ROMs
					; Checksumming ROMS 1 to 4
next_rom:	inr	a
		mov	b,a
		out	iow_keyboard	; Place ROM number on LEDs
		mvi	c,8		; Each ROM is 8 x 256 = 2K bytes
next_byte:	rlc			; checksum is rotate and XOR
		xra	m
		inr	l
		jnz	next_byte
		inr	h
		dcr	c
		jnz	next_byte
		ora	a		; A spare byte in each ROM is programmmed to ensure the correct
hang_rom:	jnz	hang_rom	; checksum is always zero. Failed? Hang with ROM number on keyboard.
		mov	a,b
		cpi	4
		jnz	next_rom	; Loop for all four ROMs
;
		inr	a
		out	iow_keyboard	; RAM test next; failure leaves "5" on the LEDs
		mvi	c,0aah		; C is test pattern
		mvi	b,HIGH ram_top+1
		in	ior_flags
		ani	iob_flags_avo	; Test for presence of AVO
		jnz	next_pattern	; jump if absent
		mvi	b,HIGH avo_ram_top+1
next_pattern:	mov	h,b		; Start at top of RAM (L zero either from ROM test, or from last loop) 
		dcx	h
zero_ram:	mvi	m,0
		dcx	h
		mov	a,h
		cpi	HIGH ram_start - 1
		jnz	zero_ram
					; Now work back up through RAM, applying pattern
		inx	h
patt_loop:	mov	a,m		; A <- current contents, which should be zero
		ora	a
		jz	zero_good
		ani	0fh		; A <- low 4 bits of memory value
		mov	a,h		; 
		jnz	ram_fail	; if low 4 bits are not zero, we've failed
		cpi	HIGH avo_ram_start
		jc	ram_fail	; Don't fail RAM if we're looking at AVO, because its RAM is 4 bits wide
zero_good:	mov	m,c		; Now place pattern
		mov	a,m		; and read back
		xra	c		; should be identical (i.e. XOR to zero)
		jz	patt_good
		ani	0fh		; Again, AVO RAM is only 4 bits wide
		mov	a,h
		jnz	ram_fail
		cpi	HIGH avo_ram_start
		jnc	patt_good	; so don't fail RAM for 4 high bit being wrong, in AVO space
ram_fail:	mvi	d,1		; D <- accumulates test failures
		cpi	HIGH ram_top+1
hang_ram:	jc	hang_ram	; Hang for baseboard RAM, not AVO
patt_good:	xra	a
		inx	h
		ora	l
		jnz	patt_loop
		ora	h
		cmp	b
		jnz	patt_loop
		mov	a,c		; A <- pattern 
		rlc			; 1st time: 0xaa -> 0x55 set carry; 2nd time: 0x55 -> 0xaa, reset carry
		mov	c,a		; C <- new pattern
		jc	next_pattern
		push	d
		call	clear_scratch
		call	init_terminal
		call	recall_nvr
		pop	d
		jz	recall_ok
		mov	a,d
		ori	2		; add "nvr failed" to test results
		mov	d,a
recall_ok:	mvi	a,2fh		; c111 d1 = "standby" (inv)
		sta	vint_nvr
		out	iow_nvr_latch
					; Keyboard test
		lxi	b,0fffh		; good long loop
		ei			; We rely on keyboard_int going off to detect end-of-scan
beep_loop:	mvi	a,8		; If we entered POST from DECTST, and we requested repeating tests,
		ana	e	
		mvi	a,7fh		; clear the "SPKR. CLICK" bit in the byte we send to the keyboard,
		jnz	skip_click
		mvi	a,0ffh		; If we're not repeating test, go wild, beep-boy!
skip_click:	out	iow_keyboard
		dcx	b
		mov	a,b
		ora	c
		jnz	beep_loop
		out	iow_keyboard	; quieten keyboard again
		lda	key_flags	; Check key_flags that have been maintained by keyboard_int
		ora	a
		jm	seen_eos	; We should have seen an end of scan after that loop
		mov	a,d
		ori	4		; add "keyboard failed" to test results
		mov	d,a
seen_eos:	push	d
		call	init_devices
		pop	d
		jmp	continue_tests
;
; The keyboard interrupt detects modifier keys and "end of scan" and places them into a
; flags location, and places other keys into what the Technical Manual calls the SILO,
; here called key_silo.
;
; The TM describes the SETUP key going into key_flags but it doesn't; its key code of 7bh
; falls just under the cut-off established here and it goes into the SILO.
;
; Interpretation of keys happens in _see_ process_keys.
;
keyboard_int:	push	psw
		in	ior_keyboard
		push	h
		push	b
		mov	b,a		; B <- key row/column
		sui	7ch		; 07ch and up are the modifier keys: CTRL, SHIFT and CAPS LOCK
		jm	into_key_buf	; normal keys will go into SILO
		mov	h,a		; H <- key code - 7ch
		inr	h		; H <- 1 = CTRL, 2 = SHIFT, 3 = CAPS, 4 = EOS
		mvi	a,10h		; Not at all sure why A could not have been initialised to
		rrc			; 08h at this point, and we could lose the RRC instruction.
shift_key:	rlc
		dcr	h
		jnz	shift_key
		lxi	h,key_flags
		ora	m
		mov	m,a
		jmp	kexit		; Done for this key, exit interrupt
;
into_key_buf:	lxi	h,key_flags
		mvi	a,7
		ana	m
		cpi	4		; Number of keys waiting to be processed?
		jp	kexit		; No room if already got 4
		inr	m		; Increment number of keys waiting
		lxi	h,key_silo
		call	add_a_to_hl
		mov	m,b		; Add this key to queue
kexit:		pop	b
		pop	h
		pop	psw
		ret
;
; proc_func_key
;
;	Having placed keyboard scan codes through the switch array, we now have a key code that identifies
;	a non-ASCII, or "function" key.
;
;	BREAK is 081h, NO SCROLL is 082h (although it has already been acted upon, and doesn't get here)
;	Numeric keypad keys all have their ASCII codes with the high bit set, i.e. KP COMMA is 0ach, and
;	the digits 0 to 9 have codes 0b0h to 0b9h.
;	Arrow keys are codes 0c1h to 0c4h (bit 7 plus 41h to 44h, i.e. 'A' to 'D')
;	PF1 to PF4 are 0d0h to 0d3h (bit 7 plus 50h to 053h, i.e 'p' to 's')

proc_func_key:	ani	7fh		; All keys entering here at the bit 7 set, so remove it
		mov	c,a		; C <- adjusted key code
		lda	in_setup
		ora	a
		jnz	setup_cursor
		mov	a,c
		cpi	1		; BREAK was 081h, adjusted to 01h
		jz	break_pressed
		lda	setup_b2
		ani	sb2_ansi
		jnz	ansi_keys	; jump to ANSI mode processing
		lda	keypad_mode
		ora	a
		jnz	vt52_app_mode
		mov	a,c		; A <- adjusted key code
		cpi	'A'		; If it isn't a cursor key, it's a number from the numeric
		jm	send_c		; keypad and they are sent just as '0' to '9' on VT52
		mvi	a,C0_ESC	; otherwise it's a cursor key and they have leading ESC
		call	send_key_byte
send_c:		mov	a,c
		jmp	send_key_end
;
vt52_app_mode:	mvi	a,C0_ESC
		call	send_key_byte
		mov	a,c		; A <- adjusted key code
		cpi	'A'		; Is it an arrow key?
		jp	send_c		; we've sent ESC already, so just send 'A' to 'D' now
		mvi	a,'?'		; else numeric keypad keys are KP0 -> ESC ? p
send_plus_col4:	call	send_key_byte
		mov	a,c		; A <- adjusted key code
		adi	40h		; '0' -> 'p'
		jmp	send_key_end
;
ansi_keys:	lda	keypad_mode
		ora	a
		jnz	ansi_app_mode
		mov	a,c		; A <- adjusted key code
		cpi	'A'		; If it isn't a cursor key (and here we're in numeric keypad mode),
		jm	send_c		; send the plain digit
		cpi	'P'		; PF1 to PF4?
		jm	ansi_app_mode	; No, deal with arrow keys
esc_o_last:	mvi	a,C0_ESC	; PF1 to PF4 are the same in numeric and application modes,
		call	send_key_byte	; sending ESC O P to ESC O S
		mvi	a,'O'
send_ac:	call	send_key_byte
		jmp	send_c
;
esc_brack_last:	mvi	a,C0_ESC
		call	send_key_byte
		mvi	a,'['
		jmp	send_ac
;
ansi_app_mode:	lda	mode_ckm	; Responses may also depend on DECCKM (cursor key mode)
		ora	a
		jz	decckm_reset	; CKM is reset
		mov	a,c		; A <- adjusted key code
		cpi	'A'		; Cursor keys?
		jp	esc_o_last	; Yes, in ANSI + CKM mode, these are ESC O A to ESC O D
ansi_digits:	mvi	a,C0_ESC
		call	send_key_byte
		mvi	a,'O'
		jmp	send_plus_col4
;
decckm_reset:	mov	a,c		; A <- adjusted key code
		cpi	'A'		; Is this a digit key?
		jm	ansi_digits	; ANSI-mode digits are same with CKM set or reset
		cpi	'P'		; PF1 to PF4?
		jm	esc_brack_last	; ANSI-mode arrows are ESC [ A to ESC [ D
		jmp	esc_o_last	; ANSI + CKM reset PF1 to PF4 are ESC O P to ESC O S
;
;
;
;
break_pressed:	lxi	h,pk_noclick	; Return to a "tidy keyboard processing" point
		push	h
		lda	local_mode	; BREAK has no function in local mode
		ora	a
		rnz
		call	make_keyclick
		lxi	b,020eh		; B <- "not DTR" for PUSART; C <- 14 vert. frames =~ 0.2333 s
		lxi	h,key_flags
		mov	a,m
		ani	key_flag_ctrl	; CTRL + BREAK sends answerback message
		jnz	c0_answerback
		mov	a,m		; A <- key flags
		ani	key_flag_shift	; SHIFT + BREAK is a longer break
		jz	not_shift	; but if we're not doing that, keep counter short
		lxi	b,00d2h		; Long break C <- 210 vertical frames =~ 3.5 s
not_shift:	mvi	a,25h		; A <- base command: "not RTS, rx enable, tx enable"
		ori	8		; A <- mix in "send break character"
		ora	b		; A <- possibly mix in disconnect (dropping DTR) for SHIFT+BREAK
		out	iow_pusart_cmd	; send PUSART command
		lda	frame_count	; get current vertical frame count
		add	c		; add number we want
		mov	c,a		; C <- end number of frames
wait_break:	push	b
		call	update_kbd
		pop	b
		lda	frame_count
		cmp	c		; are we there yet?
		jnz	wait_break
		jmp	ready_comms
;
setup_cursor:	lxi	h,pk_click	; Push a return address that will tidy up keyboard
		push	h
		xra	a
		sta	csi_params
		sta	csi_private
		lxi	h,brightness
		mov	a,c
		sui	'A'
		mov	b,a		; B <- adjusted cursor key
		mov	a,m		; Get current brightness
		jz	brighter	; up arrow - screen brighter
		dcr	b
		jz	dim_screen	; down arrow - screen more dim
		dcr	b
		jz	cuf_action	; right arrow - normal cursor movement
		dcr	b
		jz	cub_action	; left arrow - normal cursor movement
		ret
;
brighter:	dcr	a
		rm			; limit at 0
		mov	m,a		; write new brightness
		ret
;
dim_screen:	inr	a
		cpi	20h		; limit at 1fh
		rz
		mov	m,a		; write new brightness
		ret
;
no_scroll_key:	lda	setup_b2
		cma			; complement sense of switches
		ani	10h		; A <- 10h if autoxon is OFF
		lxi	h,local_mode
		ora	m
		jnz	clear_keyboard	; Can't send XOFF if autoxon is OFF or we're in local mode
		lda	why_xoff
		lxi	b,2<<8|C0_XON
		ana	b		; NZ if we had previously sent XOFF, in which case
		jnz	send_xany	; we'll send an XON
		mvi	c,C0_XOFF
send_xany:	mov	a,c
		sui	C0_XON		; If we've sent XON, A = 0, XOFF -> A = 2
		sta	noscroll
		call	send_xonoff
		jmp	pk_click
;
after_tests:	di
		lxi	sp,stack_top
		lxi	h,ram_start	; Just done tests, so this is the where failures are recorded
		push	h
		mov	a,m		; A <- test results
		rar			; Set carry if AVO failed tests
		jc	no_avo
		in	ior_flags
		ani	iob_flags_avo
		jz	have_avo	; AVO is an "absence" flag
no_avo:		inr	a
		sta	avo_missing
have_avo:	call	init_devices
		lda	screen_cols
		dcr	a
		sta	right_margin
		pop	h
		mov	a,m		; A <- test results
		mvi	m,7fh		; Write line terminator over test results, at start of screen layout
		ora	a		; Did any fail?
		jz	done_results	; no, don't bother displaying
		jp	no_cycle_bit	; jump if we aren't cycling through results
		lxi	h,test_field	; To show that tests are being repeated and failing, the entire screen
		mvi	m,0ah		; is toggled between normal and reverse field, so initialise this.
		ani	7fh		; Remove cycle bit when storing results
no_cycle_bit:	sta	test_results
		adi	'0'		; convert to printable range
		lhld	cursor_address
		mov	m,a		; Display results at cursor position
		cpi	'4'		; was it just modem test that failed?
		jz	done_results	; OK, don't go into local mode just for that
		mvi	a,20h		; 
		sta	local_mode	; any other failures, go into local
done_results:	call	set_charsets
		lxi	b,C0_XON
		call	send_xonoff
		jmp	idle_loop
;
clear_scratch:	lxi	h,stack_top
		lxi	d,avo_ram_start - stack_top
		mvi	b,0
		call	memset		; Clear all of scratch RAM above stack
		cma			; A <- 0ffh (because memset always zeroes A)
		sta	saved_rend	; saved character rendering
		lxi	h,line1_dma
		shld	UNREAD_X2052
		lxi	h,main_video	; (home address)
		shld	cursor_address
		ret
;
; init_video_ram
;
init_video_ram:	call	to_ground	; initialise character processing routine
		lxi	h,ram_start	; HL <- start of screen RAM
		lxi	d,screen_layout
		mvi	b,12h
		call	memcopy		; initial video RAM layout
		lxi	h,avo_ram_start
		lxi	d,avo_ram_top - avo_ram_start + 1
		mvi	b,0ffh
		jmp	memset		; attribute RAM blank (default rendition)
;
; This is the initial configuration of screen RAM. TM §4.6 explains the
; screen refresh and three termination bytes on each line.
; This layout almost matches TM Figure 4-7-3, p.4-89, except that that figure seems to have
; a typo (repeated 7F 70 06 line, when second should be 7F 70 0C) - other figures in that
; chapter get this right.
;
screen_layout:	db	07fh,70h,03h
		db	07fh,0f2h,0d0h
		db	07fh,70h,06h
		db	07fh,70h,0ch
		db	07fh,70h,0fh
		db	07fh,70h,03h
;
; init_terminal
;	Initialise a bunch of terminal settings: timers, scroll, cursor and receiver buffer
;
init_terminal:	lxi	h,0212h		; long, visible, cursor timer 
		shld	cursor_timer
		mvi	a,35h
		sta	blink_timer
		mvi	a,1
		sta	scroll_dir
		sta	tparm_solicited	; By default reports cannot be sent unsolicited
		lxi	h,07ffh		; Never used
		shld	UNREAD_X2149	; Never used
		mvi	a,2
		sta	key_rpt_pause
		mvi	a,0f7h		; All attributes off, normal character set
		sta	char_rend
		in	ior_flags
		ani	iob_flags_gpo
		mvi	a,1
		jnz	no_gpo		; AVO and GPO flags are both "absence" flags
		sta	gpo_flags
no_gpo:		mvi	a,0ffh
		sta	saved_curs_row	; invalidate cursor row
		sta	cursor_visible
		mvi	h,80h
		mov	l,h
		shld	rx_head		; Initialise rx_head and rx_tail of receive buffer
		ret
;
reset_pusart:	mvi	a,40h		; Reset PUSART so we can write a mode byte again
		out	iow_pusart_cmd
		lda	tx_rx_speed
		out	iow_baud_rate
		lda	pusart_mode
		out	iow_pusart_cmd
		call	ready_comms
		mvi	a,10h
		sta	vint_nvr
		out	iow_nvr_latch
		ret
;
; update_dc011
;
;	This is the only routine that writes to I/O port 0c2h, which drives DC011, the circuit
;	that provides most of the timing signals to the Video Processor. Because setting
;	columns or refresh rate always sets or resets interlaced mode, we may need to write
;	the column mode twice.
;
;	See TM §4.6.2, p. 4-55
;
update_dc011:	lda	columns_132
		ora	a
		jz	is80
		mvi	a,10h
is80:		mov	b,a		; B <- 0 for 80 columns, 10h for 132 columns
		out	iow_dc011	; this write also sets interlaced mode
		lda	refresh_rate
		out	iow_dc011	; also sets non-interlaced mode
		cpi	refresh_60Hz
		lxi	h,0970h		; 50Hz fill, per TM Figure 4-7-3, p. 4-89
		jnz	fill_req
		lxi	h,0370h		; 60Hz fill
fill_req:	shld	line0_dma
		lda	setup_b3
		ani	sb3_interlace	
		rz
		mov	a,b		; A <- 0 for 80 columns, 10h for 132 columns
		out	iow_dc011	; write columns again, so we get interlaced mode
		ret
;
; update_dc012
;	DC012 is the video controller chip, and here we update the field colour (reverse/normal field) and
;	whether the basic attribute (important in the absence of the AVO) is underline or reverse video.
;
update_dc012:	lda	setup_b1
		ani	sb1_lightback
		jnz	is_light
		mvi	a,1
is_light:	ori	0ah		; A <- 0ah/0bh = "set reverse field on/off", respectively
		out	iow_dc012
		lda	basic_rev_video ; 0 = underline, 1 = reverse video
		ori	0ch		; "set basic attribute" command
		out	iow_dc012
		ret
;
clear_display:	lda	columns_132
		ora	a
		jz	init_80col
		jmp	init_132col
;
; memcopy - copy B bytes from (DE) to (HL)
memcopy:	ldax	d
		mov	m,a
		inx	h
		inx	d
		dcr	b
		jnz	memcopy
		ret
;
ready_comms:	lda	local_mode
		ora	a
		mvi	a,1		; "RTS"
		jnz	skip_dtr	; don't set DTR if we're in local mode
		mvi	a,5		; "RTS" and "DTR"
skip_dtr:	jmp	modem_signals	;
;
; Initialise display, PUSART, and the video devices DC011 and DC012
;
init_devices:	call	clear_display
		call	program_pusart
		call	update_dc012
		jmp	update_dc011
;
idle_loop:	call	keyboard_tick
		call	receiver_tick
		lxi	h,pending_setup
		mov	a,m
		ora	a
		mvi	m,0
		cnz	in_out_setup
		lda	local_mode
		ora	a
		jz	idle_loop
		xra	a
		sta	keyboard_locked
		jmp	idle_loop
;
receiver_int:	push	psw
		push	b
		push	h
		in	ior_pusart_data
		ani	7fh
		jz	exit_rx_int	; quick exit for received NULs
		mov	c,a		; C <- character received
		lda	local_mode
		ora	a
		jnz	exit_rx_int	; if we're in local mode, reject received characters too
		in	ior_pusart_cmd	; read PUSART status
		ani	38h		; do we have framing, overrun or parity errors?
		jz	no_rx_errors	; no, phew
		mvi	c,C0_SUB	; Rx errors are treated as SUB, shown as checkboard on screen
		mvi	a,27h		; PUSART command enables RTS*, DTR*, transmit and receive
		ori	10h		; mix-in "error reset"
		out	iow_pusart_cmd
no_rx_errors:	mov	a,c		; A <- received character (or SUB)
		cpi	7fh		; Is this DEL?
		jz	pass_on
		lda	setup_b2
		ani	sb2_autoxon	; test XON
		mov	a,c		; A <- received character
		jz	no_autoxon	; jump if we don't do auto XON/XOFF
		lxi	h,received_xoff
		cpi	C0_XON		; have we received XON?
		jz	rx_xon
		cpi	C0_XOFF		; have we received XOFF?
		jz	rx_xoff
no_autoxon:	lxi	h,rx_head
		mov	c,m		; Get pointer
		mov	b,h		; as 16-bits
		stax	b		; Place in buffer
		mov	a,c		; A <- rx_head pointer
		inr	a		; move along
		ani	0bfh		; And wrapping, so location after 20bf is 2080
		mov	m,a		; Write rx_head back
		mov	b,a		; B <- rx_head
		lda	rx_tail		; A <- rx_tail
		sub	b		; A <- rx_tail - rx_head (= space in buffer)
		jnz	not_caught
		mov	m,c		; Put old head back, so we lose newest character
		mov	a,b		; A <- new rx_head
		inr	a		; move along
		ani	0bfh		; and wrap
		mov	l,a		; make a pointer
		mvi	m,C0_SUB	; place SUB in buffer to mark lost character
		jmp	do_xoff
;
not_caught:	jp	nowrap		; If rx_head > rx_tail
		adi	40h		; space is "over the wrap"
nowrap:		cpi	32		; Have we got half a buffer full?
		jnz	pass_on
do_xoff:	lxi	b,1<<8|C0_XOFF	; Half buffer full, so sent XOFF
		call	send_xonoff
pass_on:	call	try_tx2
exit_rx_int:
		pop	h
		pop	b
		pop	psw
		ret
;
rx_xon:		mvi	a,0feh		; Clear bit 0 of received_xoff
		ana	m
		jmp	track_xon_xoff
;
rx_xoff:	mvi	a,1		; Set bit 0 of received_xoff 
		ora	m
track_xon_xoff:	mov	m,a		; Update received_xoff
		jmp	pass_on
;
;
; Map from an unshifted key to the symbol it has when shifted. This table has no terminator,
; so it is exhaustive, i.e. every code other than the letter keys that passes through here
; must be found somewhere. Taking the table as ending at the byte of key_scan_map, every
; ASCII code from 20h to 7fh is here, either as the unshifted code or the shifted one.
;
key_shift_map:	db	'0', ')'
		db	'1', '!'
		db	'2', '@'
		db	'3', '#'
		db	'4', '$'
		db	'5', '%'
		db	'6', '^'
		db	'7', '&'
		db	'8', '*'
		db	'9', '('
		db	'-', '_'
		db	'=', '+'
		db	'`', '~'
		db	'[', '{'
		db	']', '}'
		db	03bh, ':'	; 03bh is semicolon, which asm8080 hates in quotes :-)
		db	'/', '?'
		db	027h, 022h	; 027h is single quote, 022h is double quote
		db	',', '<'
		db	'.', '>'
		db	'\', '|'
		db	20h,20h
		db	7fh,7fh
;
; Key map. Keys are received from the keyboard in a column/row form, shown in TM Figure 4-4-4,
; "Keyboard Switch Array". This table is arranged in natural order, by columns as
; labelled in that figure, except there are just 11 rows for each column (most of the remaining
; key codes being either absent or corresponding to key modifier functions like SHIFT, which
; were weeded out by the keyboard interrupt.
;
; Because the first three keys of column 0 (rows 0 to 2) are absent from the array (i.e. these
; scan codes are never sent by the keyboard), this table is overlapped by three bytes with
; key_shift_map, hence the equate below. So, at first glance, each column should have 11 rows,
; but column 0 appears to have 8.
;
; Numeric keypad entries have their "normal" ASCII code with the top bit set, so that KP9 is
; '9'|80h, i.e. 0b9h. However, asm8080 won't let me write '9'|80h in a DB directive without
; parenthesizing, so I'm just leaving hex values here. Whinge over.
;
; For stability, because of its big reversed "L" shape, the RETURN key has two switches,
; with scan codes 04h and 64h. This table converts 04h to 0 and 64h to 13 (i.e. C0_CR) so
; that it only counts once.
;
key_scan_map	equ	$-3
		; Column 0 - this starts with row 3 (see comments above).
		db	  07fh,    0,  'p',  'o',  'y',  't',  'w',  'q'
		; Column 1 - c3 is arrow right
key_scan_col1:	db	 0c3h,    0,    0,    0,  ']',  '[',  'i',  'u',  'r',  'e',  '1'
		; Column 2 - c4 is arrow left, c2 is arrow down, 81 is break
key_scan_col2:	db	 0c4h,    0, 0c2h,  81h,  '`',  '-',  '9',  '7',  '4',  '3',C0_ESC
		; Column 3 - c1 is arrow up, d2 is PF3, d0 is PF1, backspace and
		; tab have their natural codes
key_scan_col3:	db	 0c1h, 0d2h, 0d0h,C0_BS,  '=',  '0',  '8',  '6',  '5',  '2',C0_HT
		; Column 4 - b7 is num7, d3 is PF4, d1 is PF2
key_scan_col4:	db	 0b7h, 0d3h, 0d1h, 0b0h,C0_LF,  '\',  'l',  'k',  'g',  'f',  'a'
		; Column 5 - bx is numeric keypad,
key_scan_col5:	db	 0b8h, 08dh, 0b2h, 0b1h,    0,  27h,  3bh,  'j',  'h',  'd',  's'
		; Column 6
key_scan_col6:	db	 0aeh, 0ach, 0b5h, 0b4h,C0_CR,  '.',  ',',  'n',  'b',  'x', 082h
		; Column 7
key_scan_col7:	db	 0b9h, 0b3h, 0b6h, 0adh,    0,  '/',  'm',  20h,  'v',  'c',  'z'

; This is the checksum byte for ROM 1 (0000-07FF)
		db	0ffh		; CHECKSUM
;
vertical_int:	push	psw
		push	h
		push	d
		call	shuffle		; finalise shuffle, if ready
		push	b
		mvi	a,9		; "clear vertical frequency interrupt"
		out	iow_dc012
		ei
		lda	smooth_scroll
		ora	a
		jnz	update_scroll
		lxi	h,scroll_pending
		ora	m
		jz	check_bell	; (not been asked to scroll, so skip to next job)
		mvi	a,1		; Now start a smooth scroll, so mark it as in progress
		sta	smooth_scroll
		ora	m		; reading scroll_pending (direction) setting flags too
		mvi	m,0		; scroll_pending <- 0
		mvi	a,1		; scrolling up if
		sta	scroll_dir
		lda	bottom_margin
		jp	connectx	; scroll direction is positive
		mvi	a,99h		; else we're scrolling down (BCD 99h = -1)
		sta	scroll_dir
		lda	top_margin
		dcr	a
connectx:	call	connect_extra	; 
		sta	shuffle_ready	; A is not zero here
update_scroll:	lxi	b,scroll_dir
		ldax	b		; A <- scroll direction (-1 or 1)
		lxi	h,scroll_scan
		add	m		; A <- scan line ± 1
		daa			; keep arithmetic decimal, as there are 10 scan lines
		ani	0fh		; A <- scan line (single BCD digit)
		mov	m,a		; update scroll_scan
		mov	d,a		; D <- scroll latch
		ani	3		; Update scroll latch in DC012, two low bits first
		out	iow_dc012
		mov	a,d		; A <- scroll latch
		rar			; 
		ana	a		;
		rar			; shift right two bits
		ori	4		; mark this as "high bits of scroll latch"
		out	iow_dc012	; Update scroll latch in DC012, two high bits
		mov	a,d		; A <- scroll latch
		ora	a		; done?
		jnz	check_bell	; still scrolling, so skip the termination stuff
		sta	smooth_scroll	; now we've finished that scroll
		ldax	b		; A <- scroll direction
		ora	a
		lda	bottom_margin
		jm	do_shuf		; A is -1 if screen is scrolling down
		lda	top_margin	; no, we're going up
		dcr	a
do_shuf:	call	calc_shuf1
		sta	shuffle_ready	; A is not zero here
check_bell:	lxi	h,bell_duration
		mov	a,m
		ora	a
		jz	nobell
		dcr	m		; decrease remaining duration
		ani	4		; and flip speaker click bit every 8 cycles
		rrc			; bit 2 -> bit 1
		rrc			; bit 1 -> bit 0
		rrc			; bit 0 -> bit 7 (speaker click)
		sta	kbd_online_mask
nobell:		lxi	h,blink_timer
		mov	a,m
		dcr	a
		jnz	no_blink
		mvi	m,35h		; reset blink timer if it's expired, then do blink
		mvi	a,8
		out	iow_dc012	; DC012 <- "toggle blink flip flop"
		lxi	h,test_field
		mov	a,m		; If tests are repeatedly failing, the screen toggles between
		ora	a		; normal and reverse field at the blink rate
		jz	out_ports
		out	iow_dc012
		xri	1
no_blink:	mov	m,a		; update blink_timer or test_field, as necessary
out_ports:	mvi	a,iow_kbd_scan	; Keyboard scan is started by vertical refresh
		sta	kbd_scan_mask	; When this mask is sent to the keyboard, it gets cleared
		lxi	h,frame_count	; increment frame count, used for timing purposes
		inr	m
		lda	brightness
		out	iow_brightness
		lda	tx_rx_speed
		out	iow_baud_rate
		lda	vint_nvr
		out	iow_nvr_latch
		pop	b
		pop	d
		pop	h
		pop	psw
		ret
;
receiver_tick:	lda	local_mode	; Do nothing in local mode
		lxi	h,in_setup	; or if we are in SET-UP
		ora	m
		rnz
		call	test_rx_q
		rz			; No characters waiting
reflect_char:	mov	b,a		; B <- received char
		lda	in_setup
		ora	a
		mov	a,b		; A <- received char
		jnz	no_exec	
		lda	gpo_flags
		rlc			; Test if we are currently passing characters to GPO
		mov	a,b		; A <- received char
		jc	no_exec		; and if we are, don't interpret control characters
		cpi	20h
		jc	exec_c0
no_exec:	lhld	char_action
		pchl
;
; Once DECGON has been received, all characters are passed through to the graphics
; port until DECGOFF, ESC 2, is detected. This requires two states, an escape detector,
; installed first, and a "2" detector. If detect ESC and then the next character isn't
; "2", these routines will pass through the ESC and other character, and then head back
; to escape detector.
;
gfx_det_esc:	cpi	C0_ESC
		jnz	gfx_send_char
		lxi	h,gfx_det_final
		jmp	install_action
;
; This state detects the final character of DECGOFF: '2'. Any other character will
; need to be forwarded to the graphics port, after catching up by sending the preceding
; ESC.
;
; Detecting DECGOFF will transition to ground state.
;
gfx_det_final:	cpi	'2'
		jnz	gfx_send_esc
		mvi	a,1		; mark as present (bit 0) but not using (bit 7)
		sta	gpo_flags
		jmp	to_ground
;
gfx_send_esc:	mov	b,a		; Save the character that we weren't looking for
		mvi	a,C0_ESC	; while we send through the ESC we previously detected
		call	gfx_tx_char
		mov	a,b
gfx_send_char:	call	gfx_tx_char
		jmp	gfx_set_state	; back to detecting ESC
;
gfx_tx_char:	mov	c,a
wait_gpo_rdy:	push	b
		call	keyboard_tick
		pop	b
		in	ior_flags	; TM §6.4.1 "When data is passed, the GRAPHICS FLAG goes
		ani	iob_flags_gpo	; high and stays high until the data is stored in [RAM]"
		jnz	wait_gpo_rdy
		mov	a,c
		out	iow_graphics
		ret
;
; This early entry point (fall through) for print_char is only called from one place, when
; we insert a control character in an answerback string, and at that point this point is
; called with A = 1, in order to represent the control character onscreen as a diamond shape,
; which is ROM glyph 1. It would be important at that point to ensure that the mappings
; didn't disrupt the display, and calling single_shift would do that for ASCII range, but
; codes 00h to 01fh pass straight through print_char anyway and produce Special Graphics codes,
; without any mappings getting in the way.  In fact, that is exactly what happens when CAN
; and SUB are used to cancel an escape/control sequence and a checkboard character is printed;
; the print_char entry point is used. Am I missing something?
;
print_nomap:	call	single_shift
		; fall through
;
; There is a bug with character set mapping at the line marked [* BUG *] below.
;
; To find out which character should be printed, the number in gl_invocation (normally 0 or 1),
; is added to the address g0_charset, which is 20fdh, and the encoding designated into that set
; will be used to print a character. If a single shift is in effect, the number in gl_invocation
; will have been increased by 2, so G0 invoked into GL will have become G2 invoked into GL for
; a single character. If SHIFT OUT (^N) was already in effect, such that G1 was invoked into GL,
; and then a single shift is applied, G3 will be invoked into GL.
;
; At this point, the address of g0_charset (20fdh), in HL, has 3 added to it to find the mapping,
; except that the addition only affects the L register, making HL now point to 2000h, when it
; should be pointing to 2100h.
;
; Because 2000h always contains the value 7fh, as the start of the video DMA stream, this bug
; will make it appear as if the United Kingdom character set had been invoked, regardless of the
; SET-UP condition.
;
; To demonstrate this, the following three sequences should produce a string of three '#' (hash)
; characters, but the third one will produce two '#' and a '£' (pound).
;
;
;	a) SI # SO # SI #	(designations being G0, G1, G0)
;	b) SI # ESC N # #	(     "         "   G0, G2, G0)
;	c) SI # SO # ESC N #	(     "         "   G0, G1, G3)
;
print_char:	push	psw
		cpi	7fh		; Discard DEL
		jz	delete_exit
		push	h
		push	d
		push	b
		mov	c,a		; C <- character to be printed
		lxi	h,gl_invocation	; Now perform character set mapping
		mov	d,m		; D <- character set (0 = G0, 1 = G1) invoked
		inx	h		; HL <- g0_charset
		mov	a,d		; A <-  charset
		add	l		; advance to invoked charset
		mov	l,a		; HL <- mapped charset [* BUG *]
		mov	a,d		; A <- charset
		sui	2		; Speculatively remove single shift
		jp	charset_range	; detect whether this worked
		mov	a,d		; A <- charset, which was fine anyway
charset_range:	sta	gl_invocation	; Unshifted, ready for next character
		mov	d,m		; D <- character map (_see_ charset_list)
		lda	char_rend
		ora	d
		mov	b,a		; B <- mixed map + rendition
		mov	a,d		; A <- character map
		rlc			; Set carry flag for Special Graphics or Alternate ROM Graphics
		mov	a,c		; A <- character
		jnc	normal_mapping	; jump for "normal" sets
		sui	5fh		; Special graphics are encoded from 05fh, but are in ROM from glyph 0
		cpi	20h		; ... but there are only 20h of them, so may unmap for rest of range
		jnc	normal_mapping
		mov	c,a		; Preserve our adjusted mapping for graphics only
normal_mapping:	mov	a,d		; A <- character map
		ani	40h		; Only United Kingdom will be non-zero here
		mov	a,c		; A <- character
		jz	not_uk_enc
		cpi	23h		; Only difference between UK and ASCII is '#', 023h
		jnz	not_uk_enc	; So leave everything else untouched
		mvi	c,1eh		; '#' becomes '£', at ROM glyph 01eh (TM Figure 4-6-18, p.4-78)
not_uk_enc:	lda	char_rvid	; A <- 0 = normal video, 80h = reverse video
		ora	c
		mov	c,a		; C <- ROM glyph + normal/reverse video bit
		lda	pending_wrap
		ora	a
		jz	skip_wrap
		lxi	h,curs_col
		lda	right_margin	; test for cursor at right-hand edge
		cmp	m
		jnz	skip_wrap
		mvi	m,0		; wrap to next line
		push	b
		call	index_down	; and move cursor down
		pop	b
skip_wrap:	lhld	cursor_address	; HL <- cursor address in screen RAM
		mov	m,c		; display it
		mov	a,h		; Now adjust address to point at attributes
		adi	10h
		mov	h,a
		mov	m,b		; Apply rendition (and mapping)
		mov	a,b
		sta	rend_und_curs	; Record this rendition and mapping
		lxi	h,char_und_curs
		mov	m,c		; Store character under cursor
		lxi	h,curs_col
		lda	right_margin
		cmp	m
		jnz	no_wrap_needed
		mov	a,c		; A <- glyph + normal/reverse
		sta	char_und_curs
		lda	setup_b3
		ani	sb3_autowrap
		jmp	may_need_wrap
;
no_wrap_needed:	inr	m		; move cursor right
		call	move_updates
		xra	a
may_need_wrap:	sta	pending_wrap
		pop	b
		pop	d
		pop	h
delete_exit:	pop	psw
		ret
;
; test_rx_q
;	See if there are any received characters waiting to be processed,
;	provided the user hasn't pressed NO SCROLL.
;	Returns NZ if there is a character available; character in A.
;	Returns Z if no scroll in operation or no characters waiting.
;
test_rx_q:	lda	noscroll
		ora	a
		jnz	no_test_q
		lxi	h,rx_head
		mov	a,m		; A <- rx_head	
		inx	h		; HL <- rx_tail
		sub	m		; A <- rx_head - rx_tail
		jnz	rx_not_empty	; jump if characters received
no_test_q:	xra	a
		ret
;
rx_not_empty:	mov	l,m		; L <- rx_tail
		mvi	h,20h		; Make HL pointer to character
		mov	d,m		; D <- first character in buffer
		lxi	h,rx_tail
		mov	a,m
		inr	a		; advance rx_tail pointer
		ani	0bfh		; with wrap 
		ori	80h
		mov	m,a		; write new rx_tail 
		dcx	h		; HL <- rx_head
		sub	m		; A <- tail - head
		jp	nowrap2
		adi	40h		; space is "over the wrap"
nowrap2:	cpi	30h		; Is the buffer three-quarters empty?
		jnz	not_empty_yet
		lxi	b,1<<8|C0_XON
		call	send_xonoff
not_empty_yet:	mov	a,d		; A <- first character in buffer
		ora	a
		ret
;
process_keys:	lda	key_flags
		mov	e,a
		ani	key_flag_eos	; Don't bother processing anything until end of scan,
		rz			; so exit immediately
		lxi	h,clear_keyboard
		push	h		; always exit by clearing down keyboard flags and silo
		mov	a,e		; A <- key_flags
		ani	7		; isolate count
		cpi	4
		jm	process_silo	; if fewer than 4 keys waiting, process them
		xra	a		; else we've overflowed
		sta	new_key_scan	; there are no new keys
		ret			; throw away flags and silo on way out
;
process_silo:	mov	d,a		; D <- number of keys in silo
		mvi	c,0		; C <- 0, number of keys in silo matching history
		mvi	b,4		; loop through (up to) 4 history entries
		lxi	h,key_history
next_history:	mov	a,m		; grab next key from history
		ora	a
		jz	zero_history	; if there wasn't a key here, skip search
		push	h
		push	b
		; Having grabbed a key from the key history, we try to find it in the silo. Finding
		; it still down confirms it as something other than a bounce, and we'll leave it for
		; processing. If we don't find it, we'll zero out the entry in the history.
		; This loop employs a neat trick of distinguishing between a silo match and
		; exhausting the the search. If we find a match, we'll jump out of the comparison
		; loop with Z flag set. The normal way of running a count would also leave us
		; looping from a number down to zero though, meaning the Z flag would be set in
		; either case. So here, the loop is run from one count less and B is decremented
		; and loops while it is still positive. So, exhausting the silo leaves us with
		; Z flag *unset*.
		mvi	b,3
		lxi	h,key_silo
compare_silo:	cmp	m		; Does old key exist in silo?
		jz	silo_match	; yes, process
		inx	h		; next location in silo
		dcr	b
		jp	compare_silo
silo_match:	pop	b
		pop	h
		jz	found_in_silo	; If we found key in silo (result of cmp), add to history
		mvi	m,0		; zero out the key from history
		dcr	c		; Reduce the number of matching keys, to overcome next instruction
found_in_silo:	inr	c		; Increase the number of matching keys
zero_history:	inx	h		; next history entry
		dcr	b
		jnz	next_history
;
		mov	a,e		; A <- key flags
		ani	8		; According to TM, this bit was intended for SETUP, but this
		rnz			; must be out of date; can't see a way of setting this bit now.
		ora	d		; Include the number of keys in silo
		jnz	keys_avail
		mvi	a,-31		; When there are no keys down, reset the key repeat timer
		sta	key_rpt_timer
		ret
;
keys_avail:	lxi	h,check_history	; next stage
		push	h
		lda	key_rpt_timer
		inr	a
		jz	rpt_expired
		sta	key_rpt_timer
rpt_expired:	lda	setup_b1
		ani	sb1_autorep	; If we're not auto-repeating, timer expiry is irrelevant
		rz
		mov	a,e		; A <- key flags
		ani	10h		; CTRL pressed?
		rnz			; A key with control cannot repeat (TM §4.4.9.5)
		lda	latest_key_scan
		lxi	h,nonrepeat	; Five keys are not allowed to auto-repeat
		mvi	b,5
chk_nonrep:	cmp	m		; If this is one of them, reject it (return early)
		rz
		inx	h
		dcr	b
		jnz	chk_nonrep
		lxi	h,key_rpt_pause	; Pause before repeating begins (about half a second)
		dcr	m
		rnz
		mvi	m,2		; Two counts per repeat (30 per second)
		lda	key_rpt_timer
		cpi	0ffh
		rnz
		mov	a,c		; A <- number of matching keys (in history)
		cpi	1		; Only one key can repeat at a time
		rnz
		mvi	b,4		; The key could be in any of the history slots
		lxi	h,key_history
check_rpt_slot:	mov	a,m
		ora	a
		jnz	got_repeater
		inx	h
		dcr	b
		jnz	check_rpt_slot
		ret			; We should have found one, but failed!
;
got_repeater:	pop	h		; Pop the return address we stacked earlier
		jmp	set_latest
;
check_history:	mov	a,c		; A <- number of matching keys in history
		cpi	4		; Still got false keys down?
		rp			; if so, exit 
		lxi	b,key_silo
comp_silo_hist:	lxi	h,key_history
try_next_hist:	mov	a,m		; A <- key from history
		ora	a
		jz	next_hist_key
		ldax	b		; Is this key in silo same as this history key?
		cmp	m
		jz	next_silo_key	; OK, found it
next_hist_key:	inx	h		; try next key in history
		mov	a,l		; 
		cpi	LOW key_history + 4
		jnz	try_next_hist	; try again, unless at end of history buffer
		ldax	b		; A <- key from silo
		jmp	found_new_key
;
next_silo_key:	inx	b		; point to next silo entry
		dcr	d		; decrease number of keys in silo
		jnz	comp_silo_hist
		ret
;
found_new_key:	mov	b,a		; B <- scan code
		lda	new_key_scan
		cmp	b
		mov	a,b		; A <- scan code
		sta	new_key_scan
		rnz
set_latest:	pop	h
		sta	latest_key_scan
		cpi	7bh		; is SETUP pressed?
		jz	setup_pressed	; yes, mark as pending
		cpi	6ah		; is NO SCROLL pressed?
		jz	no_scroll_key
		mov	b,e		; B <- key flags
		mov	e,a		; E <- scan code
		lda	keyboard_locked	; Don't process while keyboard locked - clear SILO
		ora	a
		jnz	clear_keyboard
;
; Each column of the key switch array contains 11 entries, so need to take a column
; number in the top four bits of E, divide by 16, and then multiply by 11.
;
		mov	a,e		; A <- scan code
		ani	0f0h		; A <- 16 * column (because shifted)
		rrc
		rrc
		mov	d,a		; D <- 4 * column
		rrc
		rrc			; A <- column
		add	d		; A <- 5 * column
		mov	d,a		; D <- 5 * column
		mov	a,e		; A <- scan code = 16 * column + row
		sub	d		; A <- 11 * column + row
		lxi	h,key_scan_map
		mov	e,a
		mvi	d,0		; DE <- A (offset)
		dad	d		; HL <- offset into array for this scan code
		mov	c,m		; C <- key code
		mov	a,c		; A <- key code
		ora	a		;
		jm	proc_func_key	; jump to deal with function keys
		cpi	20h
		jc	done_modifiers	; unmapped, ESC, BS, TAB, LF, RETURN
		mov	a,b		; A <- key flags
		ani	70h		; any modifiers pressed?
		jz	done_modifiers	; no, simple path
		; Given that some modifiers have been pressed, work out a candidate shift code
		mov	a,c		; A <- key code
		cpi	7bh		; candidates for table shift
		jnc	use_shift_map
		cpi	61h		; also shift these by table
		jc	use_shift_map
		; Otherwise, we are just left with lowercase letter range (61h to 07ah),
		; and they are shifted to uppercase by a simple logical and.
		ani	0dfh		; make uppercase from lowercase
		mov	c,a		; C <- shifted key code
		jmp	exam_key_mods
;
use_shift_map:	mov	a,b		; A <- key flags
		ani	30h		; are CTRL or SHIFT pressed?
		jz	exam_key_mods	; no, skip shift table
		lxi	h,key_shift_map	; HL <- start of shift table
next_shift:	mov	a,m		; get unshifted code from table
		cmp	c		; compare with ours
		jz	pick_shift	; match, go and pick up shift code
		inx	h		; go past shifted code
		inx	h		; to next key
		jmp	next_shift	; round again
;
pick_shift:	inx	h		; advance to shift code
		mov	c,m		; C <- shifted key code
exam_key_mods:	mov	a,b		; A <- key flags
		ani	10h		; mask with CTRL
		jz	done_modifiers	; not CTRL, straight out, we've got final code
		mov	a,c		; A <- shifted key code
		cpi	'A'
		jc	below_alpha
		cpi	'['		; (the real '[' has already been shifted to '{')
		jc	apply_ctrl	; apply to 'A' to 'Z'
below_alpha:	cpi	'?'
		jz	apply_ctrl	; '?' 3fh => 1fh (US)
		cpi	20h		;
		jz	apply_ctrl	; SP 20h => 00h (NUL)
		cpi	7bh
		jc	clear_keyboard
		cpi	7fh
		jnc	clear_keyboard
					; Codes 07bh to 07eh drop through here, allowing us to
					; produce control codes from 1bh (ESC) to 1eh (RS)
apply_ctrl:	ani	9fh		; e.g. 'A' 01000001 & 10011111 -> 00000001
		mov	c,a		; C <- final code
done_modifiers:	ora	c
		push	psw
		lda	setup_b2
		ani	sb2_marginbell
		jz	mbell_disabled
		sta	margin_bell	; Typing a key could potentially trigger a margin bell
mbell_disabled:	pop	psw
send_key_end:	ori	80h		; Set high bit to mark as last character we're sending
		call	send_key_byte
;
pk_click:	call	make_keyclick
;
; Now we've identified the latest key, place it in a zeroed location in the key history,
; if it isn't already there.
;
pk_noclick:	lda	latest_key_scan
		mvi	d,4
		lxi	h,key_history
next_hist:	cmp	m
		jz	clear_keyboard
		inx	h
		dcr	d
		jnz	next_hist
		mvi	d,4
		lxi	h,key_history
next_hist2:	mov	a,m
		ora	a
		jz	got_hist_place
		inx	h
		dcr	d
		jnz	next_hist2
		jmp	clear_keyboard
;
got_hist_place:	lda	latest_key_scan
		mov	m,a		; place key in history
		mvi	a,-31		; reset key repeat timer
		sta	key_rpt_timer
;
; clear_keyboard
;	At the end of keyboard processing, clear key_flags and the keyboard silo.
;
clear_keyboard:	xra	a	
		lxi	h,key_flags
		mov	d,m		; D <- key_flags
		mov	m,a		; zero key_flags
		inx	h		; HL <- last_key_flags
		mov	m,d		; last_key_flags <- key_flags
		inx	h		; HL <- key_silo
		mvi	d,4		; 4 locations to clear
clear_silo:	mov	m,a		; zero silo location
		inx	h		; next location
		dcr	d
		jnz	clear_silo
		ret
;
make_keyclick:	lda	setup_b2
		ani	sb2_keyclick
		rz			; exit if keyclick is not enabled
		mvi	a,iow_kbd_click
		sta	kbd_click_mask	; When this mask is sent to the keyboard, it gets cleared
		ret
;
; Table of keys that are not allowed to auto-repeat (TM §4.4.9.5)
; These are: SETUP, ESC, NO SCROLL, TAB, RETURN
;
nonrepeat:	db	7bh, 2ah, 6ah, 3ah, 64h

;	Entry point for DECTST, which has form ESC [ 2 ; Ps y
tst_action:	lda	csi_p1		; The first parameter to DECTST
		sui	2		; must be the value 2
		rnz			; else quit early!
		mov	d,a		; D <- 0
		lda	csi_p2		; Now grab the test(s) we'd like to perform
		mov	e,a		; E <- test values (each bit set is a test)
rep_tests:
		mvi	a,1		; Test mask 0x01 - power up self test
		ana	e		; if POST is requested,
		jnz	self_test	; do it. (POST knows to return here.)
continue_tests:	mov	a,d		; A <- cumulative test results
		ora	a
		cnz	note_failure
		push	d		; preserve current results on stack ...
		call	print_wait	; "Wait", we could be here a while
		pop	d		; ... and restore
		mvi	a,2		; Test mask 0x02 - data loop back test
		ana	e
		cnz	data_loop_test
		mvi	a,8		; A <- display mask for failing tests
		cc	note_failure
		mvi	a,4		; Test mask 0x04 - modem control test
		ana	e
		cnz	modem_test
		mvi	a,10h		; A <- display mask for failing tests
		cc	note_failure
		mov	a,d		; Have we failed any tests?
		ora	a
		jnz	skip_repeat	; if so, don't go round again
		mvi	a,8		; Test mask 0x08
		ana	e		; means repeat selected tests indefinitely until
		jnz	rep_tests	; failure or power off
skip_repeat:
		mov	a,d		; Get test results
		sta	ram_start	; squirrel away (_see_ after_tests)
		jmp	after_tests	
;
;	Add bits to D register as tests fail. Current mask to add to failure is in A register.
;	This corresponds directly to the characters displayed on screen for test failure,
;	except bit 7. The displayed characters are shown in TM Table 5-6.
;	Pulling this into ASCII range is done in _see_ after_tests.
;
;	       7     6     5     4     3     2     1     0
;	    +-----+-----+-----+-----+-----+-----+-----+-----+
;	D:  |cycle|     |     |modem| data| kbd | RAM | AVO |
;	    +-----+-----+-----+-----+-----+-----+-----+-----+
;
note_failure:	ora	d		; A <- new failure mask | previous failures
		mov	d,a		; D <- new failure tally
		mvi	a,8		; 8 is a request to cycle tests
		ana	e		; E is tests requested
		rz
		mvi	a,80h		; Mark "cycle tests" in failure mask
		ora	d
		mov	d,a
		ret
;
exec_c0:	cpi	C0_ESC
		jz	c0_escape	; start extended processing
		cpi	C0_DLE		; Are we in column 0 or column 1?
		jc	process_col0	; Column 0 controls go through a jump table
		mov	e,a		; E <- character
		sui	18h
		ani	0fdh		; Z if A was 018h (CAN) or 01ah (SUB)
		rnz			; No? No action for anything else in this column
		mov	a,e		; A <- character
		cpi	C0_SUB
		jz	cancel_seq
		cpi	C0_CAN
		rnz
cancel_seq:	call	to_ground
		mvi	a,2		; ROM glyph 2 is checkerboard (error indicator)
		jmp	print_char
;
		ret			; UNREACHABLE
;
; It happens that the only C0 controls that the VT100 "processes" are those from column 0,
; i.e. with codes 00h to 0fh, and they are looked up here. Codes from column 1 are either
; dealt with earlier for communication control (XON and XOFF), invoke extended processing
; (ESC) or just cancel that extended processing (CAN and SUB).
;
process_col0:	sui	5		; Codes 00h to 04h are ignored (actually, NUL never got here)
		rm
		lxi	h,c0_actions
		add	a		; Addresses are two bytes long, so double up our code,
		mov	e,a		; use DE to hold a 16-bit offset
		mvi	d,0
		dad	d		; and add to the table base address
		mov	e,m		; extract action routine
		inx	h		; address
		mov	d,m		; DE <- action routine
		xchg			; HL <-> DE (can't jump to DE)
		xra	a		; convenience clear - used for SHIFT IN/OUT
		pchl			; Jump to action routine, so its return will continue
					; other processing
; JUMP TABLE
c0_actions:
		dw	c0_answerback	; 05 ENQ (answerback)
		dw	do_nothing_ack	; 06 ACK (acknowledge) - does nothing
		dw	c0_bell		; 07 BEL (bell)
		dw	c0_backspace	; 08 BS	 (backspace)
		dw	c0_horiz_tab	; 09 HT  (horizontal tab)
		dw	index_down	; 0a LF	 (line feed)
		dw	index_down	; 0b VT  (vertical tab)
		dw	index_down	; 0c FF	 (form feed)
		dw	c0_return	; 0d CR	 (carriage return)
		dw	c0_shift_out	; 0e SO  (shift out)
		dw	c0_shift_in	; 0f SI  (shift in)

c0_shift_out:	inr	a
c0_shift_in:	sta	gl_invocation
		ret
;
c0_answerback:	lda	local_mode	; Can't send answerback in local mode
		ora	a
		rnz
		lhld	aback_buffer
		mov	a,h		; If the first two characters of the answerback buffer
		cmp	l		; are the same, they are two delimiters and the message
		rz			; is empty, so exit
		lxi	h,pending_report
		mvi	a,pend_aback
		ora	m
		mov	m,a
		ret
;
; aback_report
;	Produce the answerback report by dumping the buffer from aback_buffer, raw, to the serial stream.
;	There can be up to 20 characters in this buffer, but may be fewer, as determined by the first
;	byte, the delimiter.
;
aback_report:	lxi	h,pending_report
		mov	a,m
		ani	~pend_aback
		mov	m,a
		lxi	h,aback_buffer
		mov	b,m		; B <- delimiter
		inx	h		; next character
		mvi	c,20		; we're going to send 20 characters at most
		lxi	d,report_buffer
more_aback:	mov	a,m		; grab next character
		cmp	b		; if it is the delimiter, exit
		jz	aback_repend
		stax	d		; add character to report
		inx	d		; next report location
		inx	h		; next answerback location
		dcr	c
		jnz	more_aback
aback_repend:	dcx	d		; go back one character
		ldax	d		; grab the last character
		ori	80h		; mark it as the end of string, by setting bit 7
		stax	d		; put it back
		jmp	send_report
;
c0_bell:	lxi	h,bell_duration
		mov	a,m
		adi	8
		rc
		mov	m,a
		ret
;
c0_backspace:	lxi	h,curs_col
		mov	a,m
		ora	a
		rz			; Can't backspace beyond the start of the line
		dcr	m		; Move cursor one column left
		jmp	move_updates
;
; c0_return - move the cursor to the start of the line, the CR action
c0_return:	xra	a
		sta	curs_col	; Column zero
		jmp	move_updates
;
nextline:	call	c0_return
;
; C0 codes LF, VT and FF, as well as escape sequence IND, are all processed the same way
index_down:	lda	setup_b3	; Check newline (LNM) mode, to see if moving down also
		ani	sb3_newline	; implies moving to the start of the (next) line.
		cnz	c0_return
		lxi	h,curs_row
		mov	d,m
		lda	bottom_margin
		cmp	d
		jz	at_margin_b
		call	last_row	; B <- last row number
		mov	a,b
		cmp	d
		rz
		inr	d		; Not at bottom of screen, so just increment row number
		mov	m,d
		jmp	move_updates
;
at_margin_b:	lda	setup_b1
		ani	sb1_smooth
		jz	jump_scroll_up	
		mvi	c,1
		call	wait_scroll
		mvi	a,0ffh
		sta	row_clearing
		inr	m		; scroll_pending <- 1
		call	move_lines_up
wait_clear1:	lda	row_clearing
		ora	a
		jnz	wait_clear1
		sta	char_und_curs	; blank under cursor (00h)
		dcr	a
		sta	rend_und_curs	; and default rendition (0ffh)
;
; This return instruction is used as a handy jump point for the C0 ACK control,
; which the terminal ignores.
do_nothing_ack:	ret
;
jump_scroll_up:	call	start_jump_up
		jmp	inv_saved_row
;
; The routine that kicks off all escape and control sequence processing in the terminal.
;
c0_escape:	xra	a
		sta	inter_chars
		sta	csi_private
		lxi	h,recog_esc
		jmp	install_action
;
recog_esc:	cpi	'0'		; all characters >= '0' are finals
		jnc	esc_final
		lxi	h,inter_chars	; so this is an intermediate character that we will
		mov	c,a		; store for later
		mov	a,m
		ora	a		; check that we haven't already had an intermediate
		jz	store_inter
		mvi	c,0ffh		; invalidate the intermediate if so
store_inter:	mov	m,c		; store valid or invalid intermediate
		ret
;
esc_final:	sta	final_char
		lxi	h,to_ground	; Setup a return address for after the escape sequence's action
		push	h
		lda	inter_chars	; Is there an intermediate character? (Or one we invalidated
		ora	a		; earlier by storing 0ffh?)
		jnz	esc_inter
		lda	setup_b2	; Given that there are no intermediates, we are now dealing
		ani	sb2_ansi	; with a simple ESC Final sequence, which we will now lookup
		lxi	h,ansiesct	; in either the ANSI (VT100) table, or VT52 table.
		jnz	do_esc_find
		lxi	h,vt52esct
do_esc_find:	jmp	find_action
;
esc_inter:	mov	b,a		; B <- intermediate
		lda	setup_b2	; Check if we're in ANSI mode
		ani	sb2_ansi	; and if not, exit immediately because
		mov	a,b		; there are no VT52 escape sequences with
		rz			; intermediate characters
		cpi	'('		; SCS sequence - designate to G0
		lxi	d,g0_charset	; DE <- location of G0 mapping, for when we've looked up charset
		jz	scs_g0
		cpi	')'		; SCS sequence - designate to G1
		jz	scs_g1
		cpi	'#'		; ESC # Final are the presentation sequences (DECDWL, etc.)
		lxi	h,esc_hash_table
		rnz			; If the intermediate was something else, or invalid (0ffh), do nothing
		; drop through to find an action for the final character of the ESC # sequence

; find_action is used to search a table for a final character and extract the address of the
; appropriate action routine. A secondary entry point,
; find_action_a is used to select an action when a Ps parameter value is already in register A
;(_see_ sgr_action for an example.)
; find_action will jump to the found action routine, which means a normal return from that routine
; will return to find_action's caller. In some cases we see someone jumping to this routine, having
; stowed another return address on the stack in advance.
; As well as calling an action routine, record the found entry in found_action, which allows the
; caller to try several tables in sequence, if needed (i.e. CSI execution.)
; This routine preserves B, as it is used to store the selective parameter to be
; passed to the action routine.
;
find_action:	lxi	d,found_action	; we'll record success here
		xra	a
		stax	d		; but initally say "nothing found"
		lda	final_char
find_action_a:	mov	c,a
next_action:	xra	a
		add	m		; A <- next comparison value
		rz			; return if reached end of table
		inx	h		; increment to action routine low byte
		cmp	c		; is this the value we want?
		jz	exec_action	; found value/character we were looking for
		inx	h		; else increment over the action routine address
		inx	h		; to the next comparison value
		jmp	next_action	; and try again
;
exec_action:	stax	d		; record entry that matched
		mov	a,m		; A <- low byte of action address
		inx	h		; hop to high byte
		mov	h,m		; H <- high byte of action address
		mov	l,a		; L <- low byte of action address
		xra	a
		pchl			; jump to action routine
;
; pop_to_ground is only jumped to if initialisation for DECGON fails, in _see_ gfx_init. We now pop the
; original return address before returning to ground state. Because gfx_init was reached through either
; the ANSI or VT52 escape jump tables, and the stack had already been primed with the address to_ground,
; gfx_init could have just returned instead of jumping to this point, which pops the stack and then
; falls through to the original destination anyway. _test_ t/decgon-init.txt
;
pop_to_ground:	pop	h		; throw away a return address if DECGON fails
;
; This address gets stored on the stack before find_action is jumped to, for escape sequences
to_ground:	lxi	h,print_char
install_action:	shld	char_action
		ret
;
;       VT52 escape sequence action table (0a1c - 0a4f)
;       Each entry is three bytes: character after ESC has been
;       recognised, and then a word of an action routine.
; JUMP TABLE
vt52esct:				; Cursor movement
		db      'A'
		dw      vt52curmove
		db      'B'
		dw      vt52curmove
		db      'C'
		dw      vt52curmove
		db      'D'
		dw      vt52curmove

				        ; "Graphics" mode - selects special character set
		db      'F'
		dw      vt52gfxenter
		db      'G'
		dw      vt52gfxexit

		db      'H'
		dw      vt52curhome

		db      'I'
		dw      reverse_index

		; Erase to end of screen
		db      'J'
		dw      vt52curmove

		db      'K'
		dw      vt52curmove

		db      'Y'
		dw      vt52_det_cup

		db      'Z'
		dw      identify

		db      '='
		dw      app_keypad

		db      '>'
		dw      num_keypad

		db      '1'		; DECGON - graphics mode
		dw      gfx_init

		db      '<'
		dw      ansi_mode

		db      ']'
		dw      print_screen

		db      0		; end of table
;
; Same as above but for ANSI (VT100) mode
; JUMP TABLE
ansiesct:	db      'c'             ; RIS - reset to initial state
		dw      start

		db      'E'             ; NEL - next line
		dw      nextline

		db      'M'             ; RI - reverse index
		dw      reverse_index

		db      '1'             ; DECGON - graphics mode
		dw      gfx_init

		db	'['		; CSI - control sequence introducer
		dw	recog_csi

		db	'H'		; Set tab at current column
		dw	set_tab_here

		db	'D'		; IND - index (move down without changing column)
		dw	index_down

		db	'7'		; DECSC - save cursor and attributes
		dw	save_cursor

		db	'8'
		dw	restore_cursor	; DECRC - restore cursor and attributes

		db	'='
		dw	app_keypad

		db	'>'
		dw	num_keypad

		db	'Z'
		dw	identify

		db	'N'		; SS2 - mentioned in TM p.D-3, but not UG
		dw	single_shift

		db	'O'		; SS3 - mentioned in TM p.D-3 but not UG
		dw	single_shift

		db	0		; end of table
;
; JUMP TABLE
esc_hash_table:	; Triple byte entries again, with final character followed by address of routine
		db	'3'		; DECDHL - double height line, top half
		dw	dhl_top_action

		db	'4'		; DECDHL - double height line, bottom half
		dw	dhl_bot_action

		db	'5'		; DECSWL - single-width line
		dw	line_attr_swl

		db	'6'		; DECDWL - double-width line
		dw	line_attr_dwl

		db	'7'		; DECHCP - hard copy
		dw	print_screen

		db	'8'		; DECALN - screen alignment display
		dw	align_pattern

		db	0		; end of table
;
; Received ESC [ (CSI), so set up processing for next character
recog_csi:	lxi	h,start_csi
		shld	char_action
		pop	h
		ret
;
vt52curhome:	mvi	a,'H'		; setup to pretend this is ANSI sequence
		sta	final_char
vt52curmove:	lxi	h,0
		shld	csi_params
		pop	h
;
execute_seq:	lxi	h,to_ground	; we are always going to transition to ground state next
		push	h		; pushing so we can just return from this routine
		lda	inter_chars	; Did we get any intermediate characters?
		ora	a		; If so, quit early, as no VT100 sequences allow them
		rnz
		lxi	h,fixed_param_t	; search the table of fixed parameter sequences first
		call	find_action
		lda	found_action	; and if any of those matched (and just got executed),
		ora	a		; we can stop looking
		rnz
		lxi	h,csi_params	; HL <- start of parameter list. We'll iterate through this
		lda	num_params
		ora	a		; if there weren't any parameters, we'll treat the sequence
		mov	e,a		; as if there was a single, defaulted, parameter
		jnz	loop_params
		inr	e		; pretend we have one parameter
loop_params:	mov	a,m		; retrieve this parameter
		push	h		; preserve param list pointer
		push	d		; preserve param count
		lxi	h,sel_param_t	; search the selective parameters table
		mov	b,a		; B <- selective parameter for action routine
		call	find_action
		pop	d		; restore param count
		pop	h		; and list
		lda	found_action	; If we couldn't find an action at all, no point iterating ...
		ora	a
		rz			; ... so quit early
		inx	h		; point to next parameter
		dcr	e
		jnz	loop_params	; and go round again
		ret
;
; Table of sequences that have a fixed number of parameters, whether defaulted or not.
; All other sequences have "Ps" selective parameters, in the next table.
; JUMP TABLE
fixed_param_t:	db	'D'		; CUB - cursor left n columns
		dw	cub_action
		db	'B'		; CUD - cursor down n rows
		dw	cud_action
		db	'C'		; CUF - cursor forward n columns
		dw	cuf_action
		db	'H'		; CUP - cursor position
		dw	curpos_action
		db	'A'		; CUU - cursor up n rows
		dw	cuu_action
		db	'r'		; DECSTBM - set top and bottom margins
		dw	stbm_action
		db	'f'		; HVP - horizontal and vertical position
		dw	curpos_action	; (same routine as CUP)	
		db	'x'		; DECREQTPARM - request terminal parameters
		dw	tparm_action
		db	'y'		; DECTST - invoke confidence test
		dw	tst_action
		db	0		; end of table

; Table of sequences with selective parameters. There action routines will be called
; multiple times, with a single parameter each time. This way, conflicts between parameters
; get resolved naturally, by having later parameters override earlier ones.
; JUMP TABLE
sel_param_t:	db	'c'		; DA - device attributes
		dw	da_action
		db	'q'		; DECLL - load LEDs
		dw	decll_action
		db	'n'		; DSR - device status report
		dw	dsr_action
		db	'J'		; ED - erase in display
		dw	ed_action
		db	'K'		; EL - erase in line
		dw	el_action
		db	'l'		; RM - reset mode
		dw	rm_action
		db	'm'		; SGR - select graphic rendition
		dw	sgr_action
		db	'h'		; SM - set mode
		dw	sm_action
		db	'g'		; TBC - tabulation clear
		dw	tbc_action
			db	0		; end of table
;
; In VT52 mode, recognised ESC Y, which now needs two more characters, row and column.
;
vt52_det_cup:	lxi	h,vt52_get_coord
		shld	char_action
		pop	h
		ret
;
; vt52_get_coord
;	Two characters after ESC Y should be row and column. This state gathers them both, using a flag
;	to record whether we've seen the row already.
;
; NOTE: This routine shows that the VT100 will execute C0 controls when coordinates are expected
;	for this sequence, making ESC Y BEL SP SP identical in effect to ESC Y SP SP BEL.
;	Would be interesting to check this against later terminals' behaviour and VSRM.
;
;	There is a "sub-state" flag here, called got_vt52_row. It is not initialised when ESC Y is
;	recognised and is only cleared when a column has been received, which means that not only will
;	single-character C0 controls be executed in the middle of a sequence, but that a second ESC Y
;	received after the row character will not stop the very next printable character being
;	interpreted as a column coordinate and terminating the sequence.
;
;	For example:
;		a) ESC Y ESC Y 0 0 executes as ESC Y 0 0
;		b) ESC Y 0 ESC Y 0 also executes as ESC Y 0 0
;
vt52_get_coord:	mov	b,a
		cpi	20h		; Do we have a C0 control? Pointless test as these are processed
		jc	exec_c0		; before other characters are passed to action routines, like this.
		cpi	C0_ESC		; Similarly, ESC cannot reach here.
		lxi	h,got_vt52_row	; HL <- flag location, kind of sub-state
		jnz	store_coord	; this character wasn't ESC, so treat as coordinate
		lxi	h,recog_esc	; UNREACHABLE
		shld	char_action	; UNREACHABLE
		ret			; UNREACHABLE
;
store_coord:	mov	a,m		; Check whether we've had a coord already
		ora	a
		jnz	vt52_move	; if we have, perform the move
		mvi	m,1		; got_vt52_row <- 1 "had a row, now need column"
		mov	a,b		; grab raw character
		sui	20h		; turn it into a zero-based row number
		sta	vt52_row_coord	; keep it for later
		lxi	h,vt52_get_coord
		shld	char_action	; keep the same action, really
		ret
;
vt52_move:	mvi	m,0		; got_vt52_row <- 0 -- clear the "had a row" flag
		mov	a,b		; grab raw character
		sui	20h		; turn it into a zero-based column number
		cpi	50h		; which can only take us up to column 80!
		jnc	skip_col_upd	; Could end up only moving the cursor row, if the column is invalid
		sta	curs_col	; in range, so update
skip_col_upd:	call	last_row	; B <- last row number
		lda	vt52_row_coord
		inr	b
		cmp	b
		jnc	skip_row_upd
		sta	curs_row
skip_row_upd:	call	to_ground
		jmp	move_updates
;
; init_80col
;	Create an 80 column display, which involves clearing the 132-column flag and setting up the
;	screen RAM with terminators at the righ places. Margins, cursor position and DC011 updates
;	are shared with the 132-column initialisation, below.
;
init_80col:	xra	a
		sta	columns_132
		call	init_screen
		mvi	c,80
		call	make_screen
		call	make_line_t
		mvi	c,80
		jmp	col_common
;
; init_132col
;	Create a 132 column display, in the same manner as described above.
;
init_132col:	mvi	a,1
		sta	columns_132
		call	init_screen
		mvi	c,132
		call	make_screen
		call	make_line_t
		mvi	c,132
col_common:	xra	a
		sta	top_margin	; Reset top margin again (make_line_t just did this)
		call	last_row	; B <- last row number
		mov	a,b
		sta	bottom_margin	; Deja margin
		mov	a,c		; A <- screen columns
		sta	screen_cols
		call	update_dc011
		call	cursor_home
		mvi	a,1
		jmp	wait_n_frames
;
reverse_index:	lxi	h,curs_row	; Move cursor up one row, in the same column
		lda	top_margin
		mov	b,a		; B <- top margin
		mov	a,m		; A <- cursor row
		cmp	b
		jz	at_margin_t	; Need to scroll up if we are at the top margin
		ora	a
		rz
		lxi	h,curs_row	; Just move the cursor up one row
		dcr	m
		jmp	move_updates
;
at_margin_t:	lda	setup_b1
		ani	sb1_smooth
		jz	jump_scroll_dn
		mvi	c,1
		call	wait_scroll
		mvi	a,0ffh
		sta	row_clearing
		dcr	m		; scroll_pending <- -1
		call	move_lines_dn
wait_clear2:	lda	row_clearing
		ora	a
		jnz	wait_clear2
		sta	char_und_curs
		ret
;
jump_scroll_dn:	call	start_jump_dn
		jmp	inv_saved_row
;
app_keypad:	lxi	h,keypad_mode
		mvi	m,1
		ret
;
num_keypad:	lxi	h,keypad_mode
		mvi	m,0
		ret
;
ansi_mode:	lxi	h,setup_b2
		mov	a,m
		ori	sb2_ansi
		mov	m,a
;
set_charsets:	lda	setup_b3
		ani	sb3_uk
		mvi	h,8		; H <- ASCII Set
		jz	not_uk
		mvi	h,48h		; H <- United Kingdom Set
not_uk:		mov	l,h		; L <- same set as H
		shld	g0_charset	; Place in all four designators
		shld	g2_charset
		xra	a
		sta	gl_invocation	; Invoke G0 into GL
		ret
;
vt52gfxenter:	mvi	h,88h		; H <- Special Graphics Character Set
		jmp	vt52gfx1
;
vt52gfxexit:	mvi	h,8		; H <- ASCII Set
vt52gfx1:	mov	l,h		; L <- same set as h
		shld	g0_charset	; Map G0 and G1 in a single operation
		ret
;
; decll_action
;
;	DECLL - ESC [ Ps q [* BUG *]
;
;	Single Ps parameter:
;	0 - clears all LEDs
;	1 - lights L1
;	2 - lights L2
;	3 - lights L3
;	4 - lights L4
;
;	This routine either masks four lowest bits to zero for Ps = 0,
;	on constructs a single-bit-on mask that it can OR with the existing
;	LED state value. No writing of the LED state to the keyboard is done
;	here, so presumably that's a periodic thing elsewhere.
;
;	However, this routine has a bug. It checks for a zero parameter, and then
;	subtracts 5 from any non-zero parameter, bombs out for a positive result,
;	and then attempts to make a LED mask with the result (Ps - 5). However,
;	values of Ps between 133 and 255 will still be negative when 5 is subtracted,
;	meaning that some of them will make masks to affect bits 4 - 7, and these will
;	be sent to the keyboard without further censoring. The keyboard byte itself
;	is described in TM Figure 4-4-2 (_see_ iow_keyboard)
;
;	This bug accounts for the strange behaviour documented by John 'Sloppy' Millington
;	in his "VT100 Oddities" document: https://vt100.net/dec/vt100/oddities
;
;	To find out which bit will be set by this routine, calculate (260 - Ps) % 9.
;	Result  Effect
;	 0 - 3  lights one of the LEDs L1 to L4 in the normal fashion
;	     4  lights the keyboard locked LED such that it cannot be unlit
;	     5  lights the online/local LED such that it cannot be unlit
;	     6  sets "start scan", which will result in a mad repeat rate
;	     7  sets "speaker click", which will make the terminal beep continuously
;	     8  leaves a 1 in the carry flags, so it is completely harmless
;
decll_action:	lxi	h,led_state
		mov	a,b		; On entry to action routines, B is always the selection value
		ora	a		; zero is special case (all off)
		jnz	make_led_mask
		mov	a,m		; A <- current LED state
		ani	0f0h		; mask all LEDs to zero
		mov	m,a		; place back
		ret
;
make_led_mask:	sui	5
		rp			; maximum allowed parameter value is 4
		mov	b,a		; Because LEDs register are reversed in order from the number of
		xra	a		; the selection parameter, b will count up to zero to find bit
		stc			; start with a "1" bit for our mask
rot_m:		ral			; shift mask bit left through register
		inr	b
		jnz	rot_m
		ora	m		; A <- new mask
		mov	m,a		; led_state <- old value | new mask
		ret
;
;	SCS - select character set
;	On entry, de is 20fdh (G0), and the earlier entry point, scs_g1, increments
;	it so that G1 is affected.
;
scs_g1:		inx	d
scs_g0:		lda	final_char
		mov	b,a		; B <- charset name
		lxi	h,charset_list-2
nxtmap:		inx	h
		inx	h
		mov	a,m
		ora	a
		rz			; end of table without finding a match?
		cmp	b		; is this the charset we're looking for?
		jnz	nxtmap
		inx	h		; yes, so grab internal charset number
		mov	a,m
		stax	d		; and store it in either G0 or G1
		ret
;
; single_shift
;	This routine is used to implement an action for SS2 and SS3, neither of which are
;	documented as being supported in the VT100 User Guide, though they are mentioned
;	the Technical Manual as being supported by the "VT100 Family."
;
;	SS2 (ESC N) is supposed to invoke G2 into GL for a single printable character,
;	after which the terminal reverts to the previous invocation, G0 or G1. SS3 (ESC O)
;	is supposed to do the same with G3.
;
;	What they actually do on the VT100 is to act identically, in increasing the current
;	invocation by two sets, so that they will both invoke G2 into GL if G0 was previously
;	there, or invoke G3 into GL if SHIFT OUT was previously in effect. After a single
;	displayed character, the invocation drops by two sets, leaving the terminal as before.
;
;	This behaviour is cheaper to implement than the correct one, and doesn't make any
;	difference because both G2 and G3 have the default character set (ASCII or UK)
;	designated at start-up, and there is no way to designate anything else.
;
;	In fact, the only way you can tell the difference between the VT100 ignoring these
;	controls completely and implementing them is by designating the Special Graphics Set
;	into G0, invoking it to GL and then using SS2 and sending a character that would be
;	different between the two sets. For example:
;
;		ESC ( 0 a ESC N a a
;
;	On a terminal that didn't support this sequence at all, the above sequence would
;	display three lowercase "a" characters. On the VT100, this will display a checkerboard,
;	a lowercase "a", and another checkerboard.
;
single_shift:	lxi	h,gl_invocation
		inr	m
		inr	m
		ret
;
charset_list:	db	'A',48h		; United Kingdom Set
		db	'B',08h		; ASCII Set
		db	'0',88h		; Special Graphics
		db	'1',0		; Alternate Character ROM Standard Character Set
		db	'2',80h		; Alternate Character ROM Special Graphics
		db	0		; end of table

gfx_init:	lxi	h,gpo_flags
		mov	a,m
		ora	a
		jz	pop_to_ground
		mvi	m,81h
		pop	h
gfx_set_state:	lxi	h,gfx_det_esc
		jmp	install_action
;
save_cursor:	lxi	h,gfx_saved
		lxi	d,gfx_state
		jmp	copy_state
;
restore_cursor:	lxi	h,gfx_state
		lxi	d,gfx_saved
copy_state:	mvi	b,0bh
		call	memcopy
		jmp	move_updates
;
;	SGR - select graphics rendition
sgr_action:	lxi	h,sgr_ps_table	; we're looking for rendition value in this table
		mov	a,b		; this is the selective parameter we're finding
		ora	a
		jz	sgr_off		; zero (all attributes off) is special
		jmp	find_action_a	; employing tail recursion to take us back to execute_seq
;
; JUMP TABLE
sgr_ps_table:	db	1		; bold
		dw	sgr_bold
		db	4		; underscore
		dw	sgr_underscore
		db	5		; blink
		dw	sgr_blink
		db	7		; negative (reverse) image
		dw	sgr_reverse
		db	0		; end of table

sgr_off:	sta	char_rvid	; A is zero on entry, so clear reverse video
		lxi	h,char_rend
		mov	a,m
		ori	0f7h		; and set all the normal rendition bits
		mov	m,a
		ret
;
sgr_bold:	mvi	a,rend_bold
		jmp	sgr_mask
;
; If we don't have AVO, then we are limited to the "base attribute", bit 7 of each character in
; screen RAM, which will render as underscore if the cursor is underline, or reverse video if the
; cursor is a block.
;
sgr_underscore:	lda	avo_missing
		ora	a
		jnz	set_base_attr
		mvi	a,rend_under
		jmp	sgr_mask
;
sgr_blink:	mvi	a,rend_blink
sgr_mask:	lxi	h,char_rend
		ana	m
		mov	m,a
		ret
;
; Reverse attribute is available without AVO, if the cursor is a block. All the same, in that case,
; it is the only attribute available, and sgr_underscore will also set the base attribute.
;
; If you have AVO, the reverse is one of four attributes available.
;
; (Two names for the same entry point, just to clarify the above, and why sgr_underscore is jumping here.)
;
sgr_reverse:
set_base_attr:	mvi	a,80h
		sta	char_rvid
		ret

; 	ANSI entry point - ESC [ c
da_action:	lda	csi_p1
		ora	a		; This sequence only allows no parameter or a parameter of 0
		rnz
;	ANSI/VT52 entry point - ESC Z
identify:	lxi	h,pending_report
		mov	a,m
		ori	pend_ident
		mov	m,a
		ret
;
ident_report:	mvi	a,~pend_ident
		call	prepare_report
		lda	setup_b2
		ani	sb2_ansi	; Are we in ANSI mode?
		jnz	ansi_identity
; now producing VT52 report, which is just ESC / Z. As we're at the character
; after the prepared template of "ESC [", we'll write the terminating 'Z' first
; (with bit 7 set), and then move backwards to overwrite the '[' with '/'.
		mvi	m,'Z'|80h	; in reverse order, ladies and gentlemen
		dcx	h
		mvi	m,'/'
		jmp	send_report
;
		; Going to produce the sequence ESC [ ? 1 ; <n> c
		; where <n> is produced from the installed options.
ansi_identity:	mvi	m,'?'		; add the fixed part of response
		inx	h		; to the buffer
		mvi	a,'1'
		call	rep_char_semi
		in	ior_flags
		mov	b,a		; B <- flags byte
		cma			; complement because the AVO and GPO flags
		ani	6		; are "missing" flags, not "present" flags
		mov	c,a		; C <- AVO and GPO presence flags
		mov	a,b		; A <- flags byte
		ani	iob_flags_stp	; check STP
		jz	stp_not_found	; not present, skip
		inr	c		; STP adds 1 to the result
stp_not_found:	mov	a,c		; A <- final answer
		ori	'0'		; ASCII-ify this digit
		mov	m,a		; into buffer
		inx	h
		mvi	m,'c'|80h	; terminate with 'c' + high bit
		jmp	send_report
;
dsr_action:	lda	csi_private	; This sequence doesn't accept any private characters
		ora	a
		rnz			; so quit early if supplied
		mov	a,b		; B is the selection parameter
		lxi	h,pending_report
		cpi	6		; is it "please report active position"?
		jz	get_active_pos
		cpi	5		; is it "please report status"?
		rnz			; if not, quit
		mov	a,m
		ori	pend_devstat
		mov	m,a
		ret
;
devstat_report:	mvi	a,~pend_devstat
		call	prepare_report
		mvi	b,3		; Assume the worst, which is a report of '3'
		lda	test_results
		ora	a
		mov	a,b
		jnz	devr2		; If any tests failed, we were right
		xra	a		; Didn't find any errors, so report '0'
devr2:		ori	'0'		; Convert our value to ASCII digiit
		mov	m,a		; add it to the report buffer
		inx	h
		mvi	m,'n'|80h	; 'n' makes this a DSR sequence
		jmp	send_report
;
get_active_pos:	mov	a,m
		ori	pend_curpos	; Received DSR triggers a cursor position report 
		mov	m,a
		ret
;
curpos_report:	mvi	a,~pend_curpos
		call	prepare_report
		lda	curs_row
		mov	b,a
		lda	origin_mode
		ora	a
		jz	skip_tm		; Not in origin mode, so don't need to add margin 
		lda	top_margin	; In origin mode, so get cursor row relative to start of area
skip_tm:	mov	c,a		; C <- margin (or 0)
		mov	a,b		; A <- cursor row (absolute)
		sub	c		; A <- cursor row (relative to top of scrolling area)
		inr	a		; Reports call the top row 1, not 0, to match CUP/HVP
		call	ascii_decimal
		call	report_semi
		lda	curs_col
		inr	a		; Left column is 1, to match CUP/HVP
		call	ascii_decimal
		mvi	m,'R'|80h	; 'R' makes this a CPR sequence
		jmp	send_report
;
; print_screen
;
;	Triggered in VT52 mode by ESC ], and in VT100 mode by ESC # 7, though that is not mentioned in the
;	User Guide. All of the work is done by the GPO, which is explained in the block diagrams in the TM.
;	The VT100 main terminal board just commands the print and waits for the GPO to become ready again.
;
print_screen:	in	ior_flags
		ani	iob_flags_gpo
		rnz			; Exit if we don't have the graphics processor option
		mvi	c,81h
		call	wait_scroll
		mvi	a,0ffh
		out	iow_graphics
		nop
wait_gpo_rdy2:	call	keyboard_tick
		in	ior_flags
		ani	iob_flags_gpo
		jnz	wait_gpo_rdy2
		ret
;
; ascii_decimal
;	Convert the unsigned number in A to an ASCII decimal string, loading it
;	into the buffer pointed to by HL.
;
ascii_decimal:	mov	e,a
		mvi	d,'0'		; digit to suppress
		mvi	c,100		; try hundreds first
		call	ascii_digit	; produce an ASCII hundreds digit
		jz	tens		; suppress leading zero
		mov	m,a		; store hundreds digit
		inx	h		; next place in buffer
		dcr	d		; if we've had a hundreds digit, then can't suppress tens!
tens:		mvi	c,10		; now try tens
		call	ascii_digit	; produce an ASCII tens digit
		jz	units		; suppress leading zero (if possible!)
		dcr	d		; again, can't suppress next digit (but we don't try)
		mov	m,a		; store tens digit
		inx	h
units:		mov	a,e		; get the remaining single-digit number
		ori	'0'		; And make it ASCII
		mov	m,a		; add to buffer
		inx	h		; and increment buffer pointer
		ret
;
; ascii_digit
;	Convert value in E to an ASCII digit for the decimal places given by C, which will probably
;	start at 100 and be reduced to 10 on the next call. Returns ASCII digit in A and will
;	return with Z flag set if that digit matches D (which is set to '0' before entry). The Z
;	flag enables skipping of leading zeroes on reported numbers. Look at routine above for the
;	cute trick to not suppress tens digits if we've produced a hundreds digit already.
;
ascii_digit:	mov	a,e
		mvi	b,'0'		; lowest digit we could return
repeat_sub:	inr	b		; assume subtraction will succeed
		sub	c		; before attempting (because of flag states)
		jp	repeat_sub	; and if it worked (no overflow), keep going
		add	c		; last subtraction failed, so restore original minuend
		dcr	b		; and reduce the ASCII digit too
		mov	e,a		; E <- remaining number
		mov	a,b		; A <- ASCII digit for this place
		cmp	d		; Is it zero? (for leading digit suppression)
		ret
;
align_pattern:	mvi	a,'E'
		sta	cls_char
		call	clear_display
		mvi	a,'E'
		sta	char_und_curs
		xra	a
		sta	cls_char	; Back to normal clear screen 
		ret
;
; rep_char_semi
;	Add the character in A to the buffer pointed to by HL, and increment
;	pointer. Follow it up with a semi-colon.
rep_char_semi:	mov	m,a
		inx	h
report_semi:	mvi	m,3bh		; Semi-colon, which asm8080 will not allow in quotes, boo.
		inx	h
		ret
;
; prepare_report
;	Setup a scratch buffer at 215ch with the start of an control sequence,
;	ESC [, ready to be appended to, and return the address of the next
;	character in HL. On entry, A contains the inverse bit mask of the report
;	that we are preparing, so it can be removed from the pending pile.
;
prepare_report:	lxi	h,pending_report
		ana	m
		mov	m,a		; this report won't be processed again
		lxi	h,report_buffer
		mvi	m,C0_ESC
		inx	h
		mvi	m,'['
		inx	h
		ret
;
		db	42h		; CHECKSUM
;	TBC - tabulation clear
tbc_action:	mov	a,b		; A <- which tabs to clear (0 = here, 3 = all)
		ora	a
		jnz	check_tbc_opt
		call	clear_this_tab
		ret
;
check_tbc_opt:	cpi	3		; If the parameter is not zero or defaulted,
		rnz			; it must be 3.
		call	clear_all_tabs
		ret
;
set_tab_here:	call	tab_offs_curs
		ora	m		; set the appropriate tab bit
		mov	m,a
		ret
;
clear_this_tab:	call	tab_offs_curs
		cma			; complement the tab bit mask because we're clearing
		ana	m
		mov	m,a
		ret
;
; clear_all_tabs
;
;	Zeroes the entire 17-byte tab_settings area. Can be invoked either from SET-UP or by control sequence.
;
clear_all_tabs:	lxi	h,tab_settings
clrnxt:		xra	a
		mov	m,a
		inx	h
		mov	a,l
		cpi	LOW tab_settings + tablen
		jnz	clrnxt
		ret
;
; c0_horiz_tab
;	Move the cursor to the next horizontal tab. Movement off the end of the tab array is checked for,
;	column by column, but movement beyond the 80th column will be caught by a margin check at the end.
;
c0_horiz_tab:	call	tab_offs_curs
next_tab_col:	inr	c		; increment cursor column
		ora	a		; clear carry
		rar			; rotate tab mask, so carry will mean next column's tab mask will
		jc	next_tab_loc	; be in next location
try_tab_loc:	mov	d,a		; D <- tab mask
		ana	m		; Is there a tab set here?
		mov	a,d		; A <- tab mask
		jz	next_tab_col	; no, try next column
		jmp	chk_rmargin	; yes tab, check we don't stray beyond right margin before setting
;
next_tab_loc:	inx	h		; tab mask for next column is in next tab setting entry
		mov	a,l
		cpi	LOW tab_settings + tablen	; have we gone off end of array?
		mvi	a,80h		; set up a fresh tab mask for new location
		jnz	try_tab_loc	; not off end, try again
		dcr	c		; off end, so column number is before our prospective increment, above
chk_rmargin:	lda	right_margin
		cmp	c
		jc	stop_at_margin
		mov	a,c		; We found a tab, not beyond right margin, all good
stop_at_margin:	sta	curs_col
		jmp	move_updates
;
; tab_offs_curs
;	Grab the cursor column and return HL with a pointer to correct location in tab settings,
;	and A with a single-bit mask that addresses that location, so we can determine whether
;	there is a tab set (or use the mask to change it).
;	Returns cursor column in C (as a bonus for the single caller that needs it.)
;
tab_offs_curs:	lda	curs_col
		mov	c,a
; tab_offs
;	Alternate entry point used for SET-UP A, where we are iterating over every column in
;	order to determine whether to print a 'T' or not. Register A contains column number.
;
tab_offs:	mov	d,a		; D <- cursor column, while we destroy A
		lxi	h,tab_settings
; col_in_bits
;	Third entry point (value for money, this one), where A is the number of a bit offset
;	into a table pointed to by HL. For this entry point, D must be equal to A on entry.
;	On return, HL is advanced to the appropriate location and A is the bit mask
;
;	(It strikes me that the two preceding instructions could have been reversed, and this
;	entry point made one byte earlier, to grab the "mov d,a" instruction.)
;
col_in_bits:	rrc			; divide cursor position by 8, in order to get byte offset
		rrc
		rrc
		ani	1fh		; range is really 0 to 16 for 132-column display
		add	l		; offset to HL, assuming HL is aligned to allow single-byte add
		mov	l,a		; HL is now byte containing tab bit
		mov	a,d		; A <- cursor column again
		ani	7		; divided by 8 before, now just want remainder
		mov	d,a		; which we will use as a count for a bit shift
		mvi	a,80h		; Bit 7 is tab at column 0, bit 6 is column 1, etc.
t_shft:		dcr	d		;
		rm			; if count's gone negative, A contains correct mask
		rrc			; rotate right for next column
		jmp	t_shft
;
;
; try_tx_byte
;	Returns with B containing local OR setup
;
try_tx_byte:	lda	local_mode	; Do nothing in local mode
		lxi	h,in_setup	; or setup.
		ora	m
		mov	b,a
		rnz
try_tx2:	in	ior_flags
		ani	iob_flags_xmit	; Can't send to PUSART until XMIT high
		rz
		lxi	h,tx_xo_flag	; Is there an XON/XOFF to transmit?
		mov	a,m
		ora	a
		mvi	m,0
		dcx	h		; HL <- tx_xo_char
		rz			; No, return
		mov	a,m		; A <- XON/XOFF
		out	iow_pusart_data
		ret
;
try_report:	di
		call	try_tx_byte
		ei
		mov	a,b		; local mode OR setup
		ora	a
		jnz	X0e6d_		; jump if local mode or setup
		in	ior_flags
		ani	iob_flags_xmit	; Can't send to PUSART until XMIT high
		rz
		lda	received_xoff	; Have we received XOFF?
		ora	a
		rnz			; We have, so can't transmit
X0e6d_:		lxi	h,sending_report
		mov	a,m
		ora	a
		jz	pick_report	; If we aren't sending a report already, pick the next one
		lhld	report_action	; otherwise, continue doing the current one
		pchl
;
pick_report:	lda	pending_report	; Do we have any reports that need sending?
		ora	a
		rz			; No, return 
		mvi	e,0		; Turn one bit into a report table offset
next_report:	rar
		jc	find_report
		inr	e
		inr	e		; 16-bit offsets
		jmp	next_report
;
find_report:	mvi	d,0		; Ready for 16-bit add
		lxi	h,report_table
		dad	d		; Get to report routine 
		mov	a,m		; A <- low byte of report routine
		inx	h
		mov	h,m		; H <- high byte of report routine
		mov	l,a		; L <- low byte of report routine
		pchl			; jump to it!
;
; 	Address of routines that will produce reports that have
;	been asked for. In the ROM, they generally live very close to the
;	that set the "pending report" bit :-)
; JUMP TABLE
report_table:
		dw	curpos_report	; DSR 6
		dw	tparm_report	; DECREQTPARM
		dw	ident_report	; DECID/DA
		dw	devstat_report	; DSR 5
		dw	aback_report	; Response to answerback request (C0 ENQ)
		dw	key_report	; Sending a cursor key sequence
;
; key_report
;
;	Responsible for transmitting both single key presses and more multi-key presses, such
;	as cursor and other function keys. These are all handled as reports so that they can't
;	reports aren't interleaved with key presses or vice versa.
;
; 	When a key report is being prepared, sending CR will also add LF if newline mode is
;	enabled, and both of those controls will enter the queue with high bits set. This routine
;	will clear "sending report" as soon as it encounters a character with high bit set. Does
;	this have any material impact on the sending of the following LF? Not sure how to test this.
;
key_report:	lxi	h,curkey_queue
		mov	b,m		; B <- first character
		mov	d,h
		mov	e,l		; DE <- HL
		inx	d		; DE points to second character
		mvi	c,8
shift_queue:	ldax	d		; move all bytes up one place
		mov	m,a		; in queue, because we've removed the first
		inx	h
		inx	d
		dcr	c
		jnz	shift_queue
		lxi	h,curkey_qcount
		dcr	m		; mark that we've popped a byte
		mov	a,m
		mov	c,a		; C <- remaining count
		jnz	q_not_empty
		lxi	h,pending_report
		mov	a,m
		ani	~pend_key	; If we emptied the queue, we're done with this report
		mov	m,a
q_not_empty:	lda	local_mode	; If we're in local mode, keyboard is locked 
		ora	a
		jnz	upd_kbd_locked
		mov	a,c		; A <- remaining count
		cpi	5
		jnc	key_tx		; If got less than half a queue to transmit, can clear keyboard
		xra	a		; else, clear it
upd_kbd_locked:	sta	keyboard_locked
key_tx:		mov	a,b		; A <- first character
		ani	80h		; isolate the high bit
		ral			; rotate it into carry 
		cmc			; complement
		rar			; and back again
		sta	sending_report	; say that we're sending a report if character didn't have high bit set
		lxi	h,key_report	; Further characters in the queue will come through here
		shld	report_action
		; Fall through. Now send the character we've just retrieved from the queue
;
; report_char
;
;	The routine that is responsible for either transmitted reports (including key presses)
;	to the host or, if we are in LOCAL or SETUP mode, reflecting them internally to cause
;	actions on the screen (so that cursor keys work, we can type normal characters, etc.)
;
report_char:	mov	a,b
		ani	7fh		; This may be last character, so mask off top bit
		mov	b,a
		lda	local_mode	; Are we in local mode 
		lxi	h,in_setup
		ora	m		; or setup?
		mov	a,b		; A <- character to send
		jnz	reflect_char	; jump if in local mode or setup -- denied!
		out	iow_pusart_data	; got a report character out of the door
		ret

; this routine is jumped to when a report has been prepared
send_report:	lxi	h,cont_report
		shld	report_action
		xra	a
		sta	rep_send_offset
		inr	a
		sta	sending_report
cont_report:	lxi	h,rep_send_offset
		mov	a,m		; A <- offset into report buffer
		inr	m		; increment offset to next character
		lxi	h,report_buffer
		add	l		; add offset to report buffer start
		mov	l,a		; point to character to send
		mov	b,m		; B <- next character of report
		mov	a,b
		ora	a
		jp	report_char	; jump if not last character
		xra	a
		sta	sending_report
		jmp	report_char
;
; send_key_byte
; 	Cursor keys and other function keys send multiple bytes, so they are gathered before transmission
;	like any other report.
;	Individual bytes of the sequence are sent through here, with the final byte of the sequence having
;	the high bit set.
;
send_key_byte:	push	h
		push	d
		mov	d,a		; D <- byte to store
		lda	setup_b2
		ani	sb2_autoxon
		jz	noautox		; Auto XON/XOFF is OFF
		mov	a,d
		sui	91h
		ani	0fdh
		jz	xhigh		; Jump if this is XON or XOFF with high bit set 
noautox:	lxi	h,pending_report
		mov	a,m
		ori	pend_key	; mark the cursor key report as in progress
		mov	m,a
add_a_key:	lxi	h,curkey_qcount
		mov	a,m		; A <- count (= offset)
		inr	m
		lxi	h,curkey_queue	; HL <- buffer address 
		mov	e,a		; E <- offset
		add	l
		mov	l,a		; Get to free location
		mov	m,d		; Store key byte
		mvi	a,8dh		; 
		cmp	d		; Is this CR with high bit?
		jnz	key_not_cr
		lda	setup_b3
		ani	sb3_newline
		mvi	d,8ah		; Newline mode implies LF after CR
		jnz	add_a_key	; so go round again.
key_not_cr:	lda	local_mode	; If we are in local mode
		ora	a
		jnz	apply_lock	; Lock keyboard
		mvi	a,5		;
		cmp	e		; Set carry if offset is greater than 5
		mvi	a,0
		rar			; Rotate that carry into high bit of A, which will lock keyboard
apply_lock:	sta	keyboard_locked
popret:		pop	d
		pop	h
		ret
;
; Found XON or XOFF with high bit set, in send_key_byte
;
xhigh:		mov	a,d
		ani	7fh		; bring back to C0 range 
		mov	d,a
		lxi	h,tx_xo_flag
		mov	a,m		; Is there an XON/XOFF to transmit?
		ora	a		;
		jnz	sendx		; Yes
		dcx	h		; HL <- tx_xo_char
		mov	a,m		; A <- last XON/XOFF transmitted
		cmp	d		; is it the same as this one?
		jnz	sendx		; No
		inx	h		; HL <- tx_xo_flag
		mov	m,d		; Flag this one to go
sendx:		mov	c,d		; C <- XON/XOFF
		mvi	b,2
		call	send_xonoff
		jmp	popret
;
; send_xonoff
;	On entry:
;		C is the character we went to sent, XON or XOFF
;		B is the reason we're sending:
;			1 = receive buffer exhaustion [XOFF] or space available [XON])
;			2 = user-initiated (pressing NO SCROLL)
;
send_xonoff:	lda	setup_b2	; If we aren't configured for
		ani	sb2_autoxon	; auto XON/XOFF,
		rz			; exit
		lda	local_mode	; Similarly, if we're in local mode
		ora	a		; then there is no point
		rnz			; in sending XOFF
		mov	a,c
		lxi	h,why_xoff
		cpi	C0_XOFF
		mov	a,b		; A <- mask for why we're XON/XOFF-ing
		jz	is_xoff
		cma			; If we're sending asking for XON, be aware that there is more
		ana	m		; than one reason for the XOFF, so only release the mask for
		mov	m,a		; this reason.
		push	psw
		ani	2		; If we're released NO SCROLL, mark that
		sta	noscroll
		pop	psw
		rnz
is_xoff:	ora	m		; Add this XOFF reason to why_xoff
		mov	m,a
		mov	a,c
		lxi	h,tx_xo_char	; If this Xany isn't the same as the last one,
		cmp	m		; then we'll send it
		rz			; else quit
		mov	m,a		; write to tx_xo_char
		inx	h		; HL <- tx_xo_flag
		mov	m,a		; flag so that tx_xo_char gets sent
		ret
;
; wait_n_frames
;	Only ever called to wait one frame, when screens are (re)initialised and we want the DMA
;	to catch up.
;
wait_n_frames:	lxi	h,frame_count
		add	m
test_frames:	cmp	m
		rz
		push	h
		push	psw
		lda	in_setup
		ora	a
		cz	keyboard_tick
		pop	psw
		pop	h
		jmp	test_frames
;
; Change the extra line's attributes so it becomes part of the scrolling region and is normal width.
;
reset_extra:	lhld	line_25_addr
		mov	a,h
		ori	0f0h
		mov	h,a
		shld	line_25_addr
;
; clear_row
;	On entry: HL is a pointer to start of line in screen RAM.
;
clear_row:	lda	screen_cols
;
; clear_part_row
;	On entry: HL is a pointer to screen RAM. A is number of positions to clear (forward)
;
clear_part_row:
		mov	b,a		; B <- number of columns to clear
		mov	a,h		; Make sure that HL is proper pointer (no attributes)
		ani	0fh
		ori	20h
		mov	h,a
		adi	10h		; Now make an attribute RAM pointer, for DE 
		mov	d,a
		mov	e,l
		mvi	a,0ffh		; A <- default rendition
clr_next_col:	mvi	m,0		; clear screen RAM
		stax	d		; and attribute RAM
		inx	d		; next column
		inx	h		; ... in both
		dcr	b
		jnz	clr_next_col
		inr	a		; zero A (was 0ffh throughout loop)
		sta	row_clearing	; done clearing of row
		ret
;
; for scrolling up
move_lines_up:	mvi	b,0ffh
		jmp	move_lines
;
; for scrolling down
move_lines_dn:	mvi	b,1
;
; at this point, B is either -1 or +1, for the direction of movement
;
move_lines:	lxi	h,top_margin
		mov	d,m		; D <- top margin
		inx	h		; HL ^ bottom_margin
		mov	e,m		; E <- bottom margin
		mov	a,b		; A <- direction
		ora	a
		mov	a,d		; A <- top margin
		jp	grab_phys	; jump if scrolling down (i.e. at top margin)
		mov	a,e		; A <- bottom margin (because scrolling up
grab_phys:	call	phl_num		; A <- physical line number of this row (HL points to entry in LATOFS)
		mov	a,e
		sub	d		; A <- bottom margin - top margin
		mov	c,a		; C <- no. lines to scroll - 1
		lda	latofs_last	; physical line number of "25th line"
shuffle_latofs:	mov	d,m		; D <- physical line number of old row (margin row, initially)
		mov	m,a		; replace this with row in A (initially, 25th row, because that will come into view)
		mov	a,b		; A <- direction
		add	l		; next logical line (one line nearer beginning when scrolling up)
		mov	l,a
		dcr	c		; decrement number of lines to shift
		mov	a,d		; A <- previous row (one we just overwrote)
		jp	shuffle_latofs
		ani	7fh		; remove any line attributes from line about to disappear
		sta	latofs_last	; and this becomes the new "25th row"
		; fall through
;
; Other routines that perform major reorganisation of the screen, including changing the
; size of a line, jump here so that they can invalidate cursor row before do all the normal
; post cursor move actions. That way, we get a full recalculation of the cursor position,
; because we're claiming it was previously on row -1, which can't be the same as the current row.
;
inv_saved_row:	mvi	a,0ffh
		sta	saved_curs_row
		jmp	move_updates
;
;
; start a jump scroll up
start_jump_up:	call	wait_for_x
		lda	bottom_margin
		call	connect_extra	; Clear extra line and connect it to screen list
		call	move_lines_up	; Move logical lines 
		lda	top_margin
		dcr	a
		jmp	scroll_common
;
; start a jump scroll down
start_jump_dn:	call	wait_for_x
		lda	top_margin
		dcr	a
		call	connect_extra
		call	move_lines_dn
		lda	bottom_margin
		dcr	a
scroll_common:	call	calc_shuf1
		ei
		sta	shuffle_ready	; A is not zero here
		lxi	h,bottom_margin
		mov	a,m
		dcx	h
		sub	m
		cpi	17h		; Even jump scrolls can only be completed in one go 
		rnz			; if they apply to full screen, else they must be
					; delayed until frame refresh. (TM §4.7.5)
;
; shuffle
;
;	This performs a test-and-clear on the shuffle_ready semaphore and then moves the lines pointers
;	around as described on TM p.4-92. The connecting of the extra line has
;	been done in advance, and the working out of the other connections for shuffle data 1 and 2.
;	Now all that remains is for the pointers to be updated.
;
shuffle:	lxi	h,shuffle_ready
		mov	a,m
		mvi	m,0
		ora	a
		rz
		lhld	shufdt2
		xchg
		lhld	shufad2		; Place the DMA address in shufdt2 into shufad2
		mov	m,d
		inx	h
		mov	m,e
		lhld	shufdt1
		xchg
		lhld	shufad1		; Place the DMA address in shufdt1 into shufad1
		mov	m,d
		inx	h
		mov	m,e
reset_shuffle:	lxi	h,shufdt2
		shld	shufad2
		shld	shufad1
		ret
;
; curs_line_addr
;	Returns pointer to current line in screen RAM
;
;	On entry:	--
;	On exit:	HL is address of first location of line in screen RAM
;
curs_line_addr:	call	curs_phl_num
		ani	80h		; Grab double-width marker
		sta	curr_line_dbl	; and store it
		call	curs_phl_addr	; HL <- start of cursor line in screen RAM
		shld	start_line_addr	; and store it
		ret
;
; memset - set DE bytes from (HL) to B
memset:		mov	m,b
		inx	h
		dcx	d
		mov	a,d
		ora	e
		jnz	memset
		ret
;
; wait_scroll
;
;	Certain actions wait for a quiet screen, i.e. scrolling to finish, before they
;	take place. The TM says that entering SET-UP mode is one of those. Examination of the
;	code shows three other actions that will wait:
;	1. Changing the top and bottom margins
;	2. Scrolling up or down the display (RI or LF), because there is only one extra line,
;	   and scrolling needs to have finished using it before we can connect is again
;	3. Print screen, which waits before telling GPO to go
;
; oddity - this routine uses C, but no one ever jumps to the line below, which
; sets C to 0. This routine feels like C=0 could be legitimate, but worthwhile finding
; out why it's never called like that. So the line below is UNUSED but is not
; this ROM's checksum address.
;
; C is a combination of two flags, in bit 0 and bit 7 (for ease of testing with rotate
; and carry testing).
; C = 01h allows keyboard processing to take place while waiting
; C = 80h makes routine exit through wait_for_x (still needs bottoming out)
;
; When using for scrolling, i.e. processing index or reverse_index, this routine is called
; with C=1, and that results in it exiting with HL pointing to scroll_pending. The callers
; then change scroll_pending through this pointer, which was quite hard to find!
;
		mvi	c,0		; UNUSED
wait_scroll:	lxi	h,scroll_pending
		di
		lda	smooth_scroll	; in smooth scroll?
		ora	m		; or scroll pending?
		ei
		jz	scroll_done
		mov	a,c
		rar
		push	b		; save our wait flags 
		cc	keyboard_tick
		call	update_kbd
		pop	b		; restore wait flags
		jmp	wait_scroll
;
scroll_done:	mov	a,c
		ral			; Test bit 7 
		rnc
		jmp	wait_for_x
;
init_screen:	lxi	h,0670h		; DMA address (2006h)
		shld	line1_dma	; blank screen by pointing direct to fill lines
		xra	a		; A <- 0
		sta	scroll_pending	; there is no scroll pending 
		sta	smooth_scroll	; we are not smooth scrolling now
		sta	scroll_scan
		out	iow_dc012	; DC012 <- "low order scroll latch = 00"
		mvi	a,4
		out	iow_dc012	; DC012 <- "high order scroll latch = 00"
		call	reset_shuffle	; feels like cleaning up shuffle
		ei
		mvi	a,1
		call	wait_n_frames	; allow DMA to blank screen
		lxi	h,main_video	; (first byte of screen definition)
		mov	a,h
		adi	10h		; Attribute RAM is Screen RAM + 1000h
		mov	d,a
		mov	e,l		; DE <- start of attribute RAM for default display
		lxi	b,0d2fh		; 22d0h + 0d2fh = 2fffh
					;
					; clear screen, including AVO's additional 1K of screen RAM
					;
cls:		lda	cls_char
		mov	m,a		; "clear" screen RAM (maybe to 'E', for alignment display) 
		inx	h
		mvi	a,0ffh
		stax	d		; Normal attributes
		inx	d
		dcx	b
		mov	a,b
		ora	c
		jnz	cls
;
		lda	cls_char
		sta	char_und_curs
		xra	a
		sta	curs_row
		sta	curs_col
		mvi	a,0ffh
		sta	rend_und_curs
		ret
;
; make_screen
;	Write all the line terminators for a screen of a given width in normal screen RAM.
;	Writes pointers only; makes no attempt to zero the display.
;
; 	On entry: C is number of columns on screen
;
make_screen:	xra	a		; A <- 0
		sta	scroll_pending	; there is no scroll pending
wait_smooth:	lda	smooth_scroll	; are we in middle of smooth scroll?
		ora	a
		jnz	wait_smooth
		lxi	h,main_video	; HL <- start of screen RAM
		mvi	b,0		; BC <- number of columns
		dad	b		; advance to end of first line
		call	last_row	; B <- last row number (23 or 13)
		inr	c		; C <- number of columns + 1 (oddity in make_lines)
		call	make_lines
		push	h
		mvi	b,1		; Need a 24th line
		call	make_lines
		pop	h
		mvi	m,7fh		; Terminate 23rd line (already done this?)
		inx	h		; HL <- 24th line DMA address (big endian) 
		shld	UNREAD_X2054	; Store this
		mvi	m,70h		; Make DMA address for 24th line 7006h (i.e. fill lines)
		inx	h
		mvi	m,6
		mov	a,c		; A <- number of columns + 1
		call	add_a_to_hl	; Get to end of 24th line
		mvi	m,7fh		; Write terminator (first time!)
		dcr	c		; C <- number of columns
		mvi	a,3		; Point initial screen DMA to line 1 (2003h)
		sta	line0_dma + 1
		lxi	h,main_video_be	; byte-swapped video address
		shld	line1_dma	; Point to our new screen
		ret
;
; Given a pointer HL, to end of a line, make another B lines of (C - 1) columns wide
; (create a full screen display)
; HL isn't advanced after writing low byte of screen address, so C is passed in
; with number of columns + 1 (small oddity)
;
make_lines:	mvi	m,7fh		; write terminator
		inx	h		; advance to point at high byte (DMA order)
		mov	d,h		; DE <- HL
		mov	e,l
		inx	d		; In DMA terms, DE is byte-swapped, so advance 2 locations
		inx	d
		mov	a,d		; And add normal line attributes
		ori	0f0h
		mov	m,a		; Write high byte + attrs first
		inx	h
		mov	m,e		; Then low byte
		mov	a,c		; A <- columns + 1 (didn't increment HL already)
		call	add_a_to_hl	; advance to next line
		dcr	b
		jnz	make_lines
		ret
;
; make_line_t
;
;	Create the physical line address and logical offset tables for screen rows.
;	The logical offset table is what the TM calls LATOFS.
;
;	On entry, C is number of columns
;
make_line_t:	lxi	h,pline_addr	; Start of table of physical line addresses
		inr	c		; Each line is columns + 3 terminators bytes long
		inr	c
		inr	c
		lxi	d,main_video
		mvi	b,0		; Make BC <- columns + 3 (for 16-bit additions)
		mvi	a,25
store_physline:	mov	m,e		; Store address of physical line in table
		inx	h
		mov	m,d
		inx	h
		xchg			; HL <- screen RAM address 
		dad	b		; get to next line, past terminators too
		xchg			; DE <- next line screen RAM address
		dcr	a		; Do all 24 lines
		jnz	store_physline
		sta	top_margin	; new screen, reset top margin
		call	last_row	; B <- last row number
		mov	a,b
		sta	bottom_margin	; and bottom margin 
		inr	a		; row number of one line beyond bottom margin, 
		sta	latofs_last	; as last place in latofs
		lhld	pline_extra	; Now grab screen address of 0-based row 24
		mvi	a,23 
		cmp	b
		jz	ok24		; unless this is a 14-row screen, in which case
		lhld	pline_addr+(14*2)    ; use 0-based row 14 (20deh)
ok24:		mov	a,h
		ori	0f0h
		mov	h,a
		shld	line_25_addr	; extra line attributes to single width
		lxi	h,latofs	; Now write LATOFS, with all logical lines pointing 
		xra	a		; to the same physical lines, so just 0 to 23.
next_lof:	mov	m,a
		inr	l		; [* fragile *] LATOFS can't go just anywhere
		inr	a
		dcr	b
		jp	next_lof
		ret
;
wait_for_x:	di
		lda	shuffle_ready
		ora	a
		jz	no_shuffle
do_tick:	ei
		call	keyboard_tick
		jmp	wait_for_x
;
no_shuffle:	lda	smooth_scroll	; are we in middle of smooth scroll? 
		ora	a
		jnz	next_scan
		lda	scroll_pending
		ora	a
		ei
		rz			; no scroll pending, so exit
		jmp	do_tick
;
next_scan:	lda	scroll_dir
		lxi	h,scroll_scan
		add	m
		daa
		ani	0fh
		jz	do_tick
		ei
		ret
;
; last_row
;	Returns with B set to last row number, i.e. 13 or 23
;
last_row:
		push	h
		mvi	b,23		; assume we have 24 lines
		lda	columns_132	; unless we're in 132-column mode
		lxi	h,avo_missing
		ana	m		; AND we DON'T have AVO
		pop	h
		rz
		mvi	b,13		; in which case, we only have 14 lines
		ret
;
; calc_shuf1
;	Work out which line will be the new top line and take the line that will disappear and store it as
;	the new extra line.
;
; On entry: A is the top or bottom margin - 1 (i.e. RI at top of full screen will enter here with A = 23)
;
calc_shuf1:	ora	a
		jp	pos_margin
		lxi	h,line1_dma	; HL <- address of video line (big-endian)
		push	h
		mov	a,m		; A <- high byte the video address
		inx	h		; HL points to low byte
		mov	l,m		; L <- low byte of video address
		ori	0f0h		; Change attributes of high byte to be scrolling region, normal size
		mov	h,a		; H <- high byte of video address
		shld	line_25_addr	; stow it as new extra line address
		call	next_line_addr	; DE <- DMA address of next line
		pop	h		; HL <- address that will need changing to point to line 2 (new top line)
		mov	b,d
		mov	c,e		; BC <- DMA address of line 2
		jmp	store_shufad1
;
pos_margin:	call	to_line_n
		call	next_line_addr	; DE <- DMA address of line we're losing from bottom
		push	h
		push	d
		xchg			; HL <- DMA address of losing line
		call	next_line_addr	; DE <- address of line after (fill address)
		mov	b,d
		mov	c,e		; BC <- fill address
		pop	d		; DE <- losing line address, again
		mov	a,d
		ori	0f0h		; Restore its line attributes
		mov	h,a
		mov	l,e		; HL <- (corrected) losing line address
		shld	line_25_addr	; which now becomes available as the extra line
		pop	h		; HL <- new bottom line address
		mov	a,h
		ori	9fh		; testing for double-width attributes
		inr	a
		jnz	not_sinwid1	; If line isn't single-width, there are two pointers to next line
		call	eoline_addr
store_shufad1:	di			; Make shufad1 & shufdt1 consistent before vertical refresh
		shld	shufad1		; Now store the address of the terminating info to be updated
		jmp	store_shufdt1
;
not_sinwid1:	call	real_addr
		lda	screen_cols
		rrc			; Need to get to halfway terminator because line is double-width
		mov	d,a		; D <- half screen width
		call	add_a_to_hl
		inx	h		; HL <- next DMA address
		di
		shld	shufad1		; This is the address we'll write to during shuffle 
		mov	a,d		; A <- half screen width
		call	add_a_to_hl	; Get to the address we aren't using at the moment 
		mov	m,b		; and make it consistent with the one we'll update during shuffle
		inx	h
		mov	m,c
store_shufdt1:	mov	h,b
		mov	l,c
		shld	shufdt1
		ei
		ret
;
; connect_extra
;	In advance of the shuffle happening, connect the extra line to the screen lines.
;	If we are indexing down, the extra line will be connected to the first line
;	(within margins). If we are reverse indexing then we are shifting all the lines
;	down and the extra line connection will be made to the second line. At the same
;	time, we write shufad2 and shufdt2, per TM Figure 4-7-9, so that one of the
;	existing lines will get a join to the extra line when the shuffle gets performed.
;
;	On entry: A is the row number of the bottom margin, or the top margin - 1 (so may be negative)
;
connect_extra:	push	psw
		call	reset_extra	; make the cursor line scrollable
		pop	psw
		ora	a
		lxi	h,line1_dma	; set HL in case we're at the top and
		jm	at_top		; the extra line will be connected after the fill line
		call	to_line_n	; otherwise work out which line will be connected to extra
		mov	a,h		; A <- high byte of screen RAM address with attrs
		ori	9fh
		inr	a
		jnz	not_sinwid2	; jump if line attrs were not single width
		call	eoline_addr	; HL <- next line DMA address
at_top:		di
		shld	shufad2		; points to line DMA address
		mov	b,m
		inx	h
		mov	c,m		; BC <- line DMA address + attrs
		jmp	conn_shuf2
;
not_sinwid2:	call	real_addr
		lda	screen_cols	; As the line we're connecting to extra isn't single
		rrc			; width, work out where the terminator is (i.e. half way)
		mov	b,a
		call	add_a_to_hl
		inx	h		; HL <- next DMA address
		di
		shld	shufad2		; This is the address we'll write to during shuffle
		mov	a,b		; A <- half width 
		mov	b,m		; Grab the current DMA address
		inx	h
		mov	c,m
		call	add_a_to_hl	; move to full width (HL points one byte too far, to DMA low byte)
		xchg			; DE <- DMA low byte
		lhld	line_25_addr
		xchg
		mov	m,e		; Place LOW byte of extra line address
		dcx	h		; Move back to high byte
		mov	m,d		; Place HIGH byte of extra line address
					; Mid-line address (the active one) will be updated during shuffle
conn_shuf2:	lhld	line_25_addr	; Line 24 will have its end pointer updated
		shld	shufdt2		; to point to the extra line during shuffle
		call	eoline_addr
		mov	m,b		; Update extra line's next DMA address now 
		inx	h
		mov	m,c
		ei
		ret
;
; to_line_n
;	On entry:
;		A is the row number of physical screen to get to (0 gets to address line1_dma points to)
;	On exit:
;		HL points to first character of screen RAM of line
;
to_line_n:	inr	a
		mov	b,a
		lxi	h,line1_dma
adv_line:	mov	a,m		; A <- high byte of screen DMA address (and attrs)
		inx	h
		mov	l,m		; L <-low byte
		mov	h,a		; H <- high byte
		dcr	b
		rz
		call	eoline_addr	; advance to next DMA address
		jmp	adv_line
;
; Given start of line address in HL, returns DE with address of next line
;
next_line_addr:	push	h
		call	eoline_addr
		mov	d,m		; D <- high byte (incl. attrs)
		inx	h
		mov	e,m		; E <- low byte
		pop	h
		ret
;
; Given start of line address in HL, add screen width to get end of line
eoline_addr:	call	add_cols_to_hl
		inx	h
; real_addr
;
;	On entry, HL is an address in screen RAM with the line attribute and scrolling region bits
;	in the top four bits. Mask out these attributes and add the 2000h offset to get a real address.
;
real_addr:	mov	a,h
		ani	0fh
		ori	20h
		mov	h,a
		ret
;
line_attr_dwl:	call	double_line
		db	50h
;
dhl_top_action:	call	double_line
		db	30h
;
dhl_bot_action:	call	double_line
		db	10h
;
; double_line
;
;	The single byte at the return address is the line attributes to be applied to the current line.
;	We are not going to go back there, so no attempt is made to restore the stacked address.
;	As these are all double-width line attributes, the right margin must be adjusted, and the cursor
;	pulled back onto screen if necessary.
;
double_line:	call	wait_for_x
		lxi	h,latofs	; Find current physical line number in LATOFS	`
		lda	curs_row	;						 |  duplicates
		add	l		;						  > curs_phl_num
		mov	l,a		;						 |
		mov	a,m		;						,
		ori	80h		; Mark the current row in LATOFS as double width
		mov	m,a
		; We've now set bit 7 of the physical line number in LATOFS, but this doesn't affect
		; the next routine, even though it again looks up a physical line number in LATOFS,
		; as the (corrupted) line number it receives will be doubled in order to extract an
		; address from the table at pline_addr.
		;
		call	curs_phl_addr	; HL <- address of cursor line in screen RAM?
		call	halve_line
		pop	h		; Grab return address (which we will discard)
		mov	a,m		; A <- line attributes to be applied
		call	add_line_attrs
		lda	right_margin
		lxi	h,curs_col
		ora	a		; clear carry because RAR brings it into bit 7 (why not use RRC?)
		rar			; A <- right margin / 2
		cmp	m
		jnc	inv_saved_row	; jump if right margin / 2 is still greater than current cursor column
		;
		; The next two lines look odd because they aren't storing a screen RAM address in
		; cursor_address, as you'd expect. However, we're about to go into move_updates,
		; which is going to attempt to restore the old character under the cursor and the
		; old rendition in attribute RAM. If we allowed that to happen with the cursor just
		; beyond the margin, this restoration could wreck the new terminators, so by
		; storing the address of these locations in the cursor address, move_updates
		; will place the character under the cursor in char_und_curs, a cunning no-op.
		;
		lxi	h,char_und_curs
		shld	cursor_address
		jmp	inv_saved_row
;
;	Process DECREQTPARM - ESC [ <sol> x
tparm_action:	lda	csi_p1
		cpi	2		; request parameter can only be 0 or 1
		rnc
		sta	tparm_solicited
; If they are allowed, exiting SET-UP will send a TPARM report
setup_tparm:
		lxi	h,pending_report
		mov	a,m
		ori	pend_tparm
		mov	m,a
		ret
;
; tparm_report
;
;	Produce a DECREPTPARM sequence:
;	ESC [ <sol>; <par>; <nbits>; <xspeed>; <rspeed>; <clkmul>; <flags> x
;
tparm_report:	mvi	a,~pend_tparm
		call	prepare_report
		lda	tparm_solicited	; A <- solicited flag (0 or 1)
		ori	'2'		; convert to ASCII digit '2' or '3'
		call	rep_char_semi	; <sol>
		lda	setup_b4	; A <- comms + power settings
		push	psw		; save for later, when we'd like bits/char
		ani	0c0h		; keep just parity bits
		ori	18h		; mix in half an ASCII '0'
		add	a		; shift even/odd into carry
		inr	a		; and convert "no parity" into '1'
		jp	skip_odd_even	; skip to display if parity is off (new bit 7)
		rar			; bring carry back into bit 7
		rlc			; and rotate it into bit 0
		ori	4		; making odd parity '4' and even '5'|80h
		ani	7fh		; clean up that high bit
skip_odd_even:	call	rep_char_semi	; <par>
		mvi	b,'1'		; prepare "8 bits" answer
		pop	psw		; A <- comms + power settings again
		ani	20h		; bit 5 is zero for "7 bits"
		jnz	skip_bit_adj	; display if we've got right answer already
		inr	b		; change to '2' for "7 bits"
skip_bit_adj:	mov	a,b
		call	rep_char_semi	; <nbits>
		lda	tx_spd
		rrc
		call	ascii_decimal	; <xspeed>
		call	report_semi
		lda	rx_spd
		rrc
		call	ascii_decimal	; <rspeed>
		call	report_semi
		mvi	a,'1'		; <clkmul> is a constant
		call	rep_char_semi
		lda	setup_b5	; report STP switch values
		ani	0f0h		; as with all other setup blocks, only top 4 bits
		rrc
		rrc
		rrc
		rrc			; which we shift down to report as number 0 to 15
		call	ascii_decimal
		mvi	m,'x'|80h	; 'x' for DECREPTPARM sequence final
		jmp	send_report
;
;	DECSWL - single-width-line
line_attr_swl:
		lxi	h,curr_line_dbl
		mov	a,m
		ora	a
		rz			; Nothing to do if current line is already single width
		call	wait_for_x
		lxi	h,latofs
		lda	curs_row	; Retrieve logical line number entry
		add	l
		mov	l,a
		mov	a,m
		ani	7fh		; Zero bit 7, the double width indicator
		mov	m,a		; place back
		call	curs_phl_addr	; HL <- screen address of cursor row
		lda	screen_cols
		rrc
		mov	b,a		; B <- half number of columns
		call	add_a_to_hl	; Move halfway across line, to where the "half" terminator is
		xra	a
zap_2nd_half:	mov	m,a		; Remove terminator, DMA address and all following characters
		inx	h
		dcr	b
		jnz	zap_2nd_half
		mvi	a,0f0h
		sta	saved_curs_row
		call	add_line_attrs
		xra	a
		sta	curr_line_dbl
		jmp	move_updates
;
; curs_phl_loc
curs_phl_loc:	lda	curs_row
		call	phl_num
; phl_loc
;	Given a physical line number in A, look up the address of this line
;	in an address table (doubling and adding, so we're returning a proper
;	address in HL).
phl_loc:	lxi	h,pline_addr
		add	a
		add	l		; [* fragile *] pline_addr table must not go over 8-bit boundary
		mov	l,a
		ret
;
; curs_phl_addr
;
;	Get the address of the physical line in screen RAM of the cursor row
;	Returns this in HL.
;
curs_phl_addr:	call	curs_phl_loc
ld_hl_from_hl:
		mov	a,m
		inx	h
		mov	h,m
		mov	l,a
		ret
;
; add_line_attrs
;
;	Apply the line attributes in A to the current (cursor) row. This involves finding the start address
;	of the previous line and marching across to its terminating bytes, because they determine the attributes
;	for this line, as well as the address. Two wrinkles:
;
;	1) If this is the first line, then we have to modify the attributes as stored in the initial
;	   screen layout (at address line1_dma)
;	2) LATOFS stores the physical line number with bit 7 high if that line (the previous one, in our case)
;	   is double-wdith. In that case, the terminators have been placed half across the line, instead of
;	   screen width columns across.
;
add_line_attrs:	ani	70h		; Censor attributes (don't affect scrolling region, for example)
		mov	b,a
		lda	curs_row	; It's the terminating bytes for the previous line that decides
		dcr	a		; the attributes (and address) for this one
		lxi	h,line1_dma	; Set up for initial line address if we were at row 0 anyway
		jm	set_attrs	; yep, we were
		call	phl_num		; As we weren't at beginning, grab physical line number from LATOFS
		mov	d,a		; D <- physical line number
		ani	7fh		; Get rid of any double line marker
		call	phl_loc		; HL <- address in physical line table
		call	ld_hl_from_hl	; HL <- start of line in screen RAM
		lda	screen_cols
		rrc			; A <- screen width / 2
		mov	e,a		; E <- screen width / 2
		inx	h		; 
		inr	d		; 
		dcr	d		; set flags for phys line number from LATOFS (i.e. was it doubled?)
		mvi	d,0		; Set up DE to be offset of half-way across line
		dad	d
		cm	set_attrs	; If this line was double-width, do middle first (CALL)
		dad	d		; and then (or just) the end of line
set_attrs:	mov	a,m		; A <- first (high) byte of DMA address + attrs
		ani	8fh		; Remove line attrs, keeping scroll flags + address
		ora	b		; Place new line attributes
		mov	m,a		; Store new high byte of DMA address
		ret
;
; On entry (from double_line at least), HL is the screen address of start of current line
; This routine halves the length of the line by moving this line's terminator and next screen address to half way.
halve_line:	lda	screen_cols
		rrc			; A <- screen width / 2
		mov	d,h		; 
		mov	e,l		; DE <- start of current line
		call	add_a_to_hl	; HL is half way across line
		xchg			; DE <- half way, HL <- start
		call	add_cols_to_hl	; HL <- addr of right margin + 1 (terminator)
		mvi	b,3
end_byte_loop:	mov	a,m		; get post-EOL bytes (terminator first, then two screen addresses)
		stax	d		; place half way
		inx	d
		inx	h
		dcr	b
		jnz	end_byte_loop
		ret
;
add_cols_to_hl:	lda	screen_cols
add_a_to_hl:	add	l
		mov	l,a
		rnc
		inr	h
		ret
;
; curs_phl_num
;	Return physical line number of cursor row in A
; phl_num
;	Return physical line number of logical row A, in A
;	
curs_phl_num:	lda	curs_row
;
phl_num:	lxi	h,latofs
		add	l
		mov	l,a
		mov	a,m
		ret
;
;	RM - reset modes
rm_action:	mvi	c,0
		jmp	do_modes
;
;	SM - set modes
sm_action:	mvi	c,0ffh
;
;	At this point, we are either setting (C = 0ffh) or resetting (C = 0) modes. The mode number is in B.
do_modes:	lda	csi_private
		ora	a
		lxi	h,ansi_mode_t	; We're dealing with ANSI modes
		jz	mode_lookup	;   if there isn't a private character
		cpi	'?'		; But if the private character isn't '?', quit
		rnz
		lxi	h,dec_mode_t	; Look up DEC private modes
mode_lookup:	mov	a,b		; A <- mode number
		mov	b,c		; B <- set/reset
		call	find_action_a
		ret
; JUMP TABLE
dec_mode_t:	db	1		; DECCKM - cursor key
		dw	decckm_mode
		db	2		; DECANM - ANSI/VT52
		dw	decanm_mode
		db	3		; DECCOLM - column
		dw	deccolm_mode
		db	4		; DECSCLM - scrolling
		dw	decsclm_mode
		db	5		; DECSCNM - screen
		dw	decscnm_mode
		db	6		; DECOM - origin
		dw	decom_mode
		db	7		; DECAWM - auto wrap
		dw	decawm_mode
		db	8		; DECARM - auto repeating
		dw	decarm_mode
		db	9		; DECINLM - interlace
		dw	decinlm_mode
		db	0		; end of table
;
;	Only a single ANSI mode can be set/reset: LNM - line feed new line mode
ansi_mode_t:	db	20
		dw	lnm_mode
		db	0		; end of table

decckm_mode:	lxi	h,mode_ckm
		mov	m,b
		ret
;
decanm_mode:	call	apply_mask_sp
		dw	setup_b2
		db	sb2_ansi
		jmp	set_charsets

lnm_mode:	call	apply_mask_sp
		dw	setup_b3
		db	sb3_newline
		ret

; decom_mode [* BUG *]
;	This routine changes origin mode and sends the cursor to the home position.
;	However, this routine contains a bug because it calls cursor_home, and that routine
;	clears the first two CSI parameters before dropping into the general cursor positioning routine.
;
;	That means that, if DECOM is the first mode in an RM or SM sequence, the second mode will be
;	cleared by cursor_home and won't be executed. This can be shown by using a highly visible change
;	for the second parameter, such as DECSCNM (screen mode - light or dark).
;
;	For example:
;	1. Go into reverse screen mode: ESC [ ? 5 h
;	2. Go into normal screen mode:  ESC [ ? 5 l
;	3. Set origin mode and reverse screen mode: ESC [ ? 6 ; 5 h
;
;	The third sequence will completely ignore DECSCNM (private mode 5). However, third and
;	subsequent modes will still be processed, so this works:
;
;	4. Set origin mode and reverse screen mode: ESC [ ? 6 ; ; 5 h
;
decom_mode:	lxi	h,origin_mode
		mov	m,b
		call	cursor_home	; *BUG* (_see_ cursor_home)
		ret
;
decsclm_mode:	call	apply_mask_sp
		dw	setup_b1
		db	sb1_smooth
		ret

decscnm_mode:	call	apply_mask_sp
		dw	setup_b1
		db	sb1_lightback
		jmp	update_dc012

deccolm_mode:	lxi	h,columns_132
		mov	m,b
		call	clear_display
		ret
;
decarm_mode:	call	apply_mask_sp
		dw	setup_b1
		db	sb1_autorep
		ret

decawm_mode:	call	apply_mask_sp
		dw	setup_b3
		db	sb3_autowrap
		ret

decinlm_mode:	call	apply_mask_sp
		dw	setup_b3
		db	sb3_interlace
		jmp	update_dc011

; apply_mask_sp
;	The stacked return address is the address of a setup switch block and the following byte
;	is a bit mask that must either be set (B = 0ffh) or reset (B = 0).
;
apply_mask_sp:	pop	h		; HL <- return address
		mov	e,m		; E <- byte after
		inx	h		;
		mov	d,m		; D <- byte after that
		inx	h		;
		mov	a,m		; A <- mask value
		inx	h		; increment hl again, to make new return address
		xchg			; DE <--> HL (DE is now return address)
		mov	c,a		; C <- mask value
		cma			; A <- all the other bits set
		ana	m		; clear our bit in location
		mov	m,a		; and write it back
		mov	a,b		; get all ones if we'd like to set, or all zeros to reset
		ana	c		; either mask for set, or zero for reset
		ora	m		; (we already reset the mode, so now possibly set it)
		mov	m,a		; apply to location
		xchg			; HL <- return address again
		pchl			; return
;
keyboard_tick:	call	update_kbd
		ani	10h		; Probably intended to prevent processing when keyboard locked,
		cz	process_keys	; but see notes below.
		jmp	try_report
;
; If the keyboard is ready to receive and isn't locked, make up the status byte to transmit
; to it. Then do the cursor timer housekeeping.
; Return value:
; 	If keyboard is not ready to receive, A is 0
;	If UNWRIT_X2077 had a purpose, that value would be returned in A
;	If smooth scrolling or pending scroll, A will be 1 or -1 (direction of scroll)
;	Otherwise it will be the OR of the high and low bytes of the cursor timer.
;
;	Because the keyboard locked flag in the keyboard status is 10h, it feels as if this routine
;	was originally intended to return when the keyboard was locked, which would naturally mean
;	that there was point calling process_keys.
;
update_kbd:	in	ior_flags
		ani	iob_flags_kbd
		rz			; Keyboard not ready to receive
		lxi	h,keyboard_locked
		mov	a,m
		ora	a
		jz	kbd_not_locked
		mvi	a,iow_kbd_locked
kbd_not_locked:	lxi	h,local_mode
		ora	m		; Local mode is 20h, to set LOCAL LED
		lxi	h,led_state	; Make up a keyboard command from all status bytes
		ora	m
		inx	h		; HL <- kbd_online_mask (can also affect click if bell is sounding)
		ora	m
		inx	h		; HL <- kbd_click_mask
		ora	m
		mvi	m,0		; zero "click" after use: kbd_click_mask <- 0
		inx	h		; HL <- kbd_scan_mask
		ora	m
		mvi	m,0		; zero "start scan" after use: kbd_scan_mask <- 0
		out	iow_keyboard
		lxi	h,num_kbd_updates
		inr	m
		lda	UNWRIT_X2077
		ora	a
		rnz
		lda	smooth_scroll	; are we in middle of smooth scroll?
		lxi	h,scroll_pending; or are we about to start one?
		ora	m
		rnz			; exit if either scroll condition is true
		lhld	cursor_timer	; Maintain cursor timer 
		dcx	h
		mov	a,h
		ora	l
		jz	curs_timer_up
		shld	cursor_timer
		ret
;
; Cursor time has counted down to zero
curs_timer_up:	lda	cursor_visible	; toggle cursor visibility
		xri	0ffh
		sta	cursor_visible
		lxi	h,0212h		; Cursor will be on for about 2/3 second
		jnz	curs_was_off
		lxi	h,0109h		; Cursor will be off for about 1/3 second
curs_was_off:	shld	cursor_timer	; Set new timer
		lhld	cursor_address
		mov	b,m		; B <- current char at cursor position
		lda	curs_char_rend	; A <- 0x80 or 0, depending on whether we're using base rendition
		xra	b		; Flip bit, if bit fit to flip
		mov	m,a		; Place back on screen
		lxi	d,1000h		; Make an address in attribute RAM
		dad	d
		lda	curs_attr_rend	; Again, flip cursor rendition
		xra	m
		mov	m,a		; and replace
		ret
;
		db	74h		; CHECKSUM
;
el_action:	mov	a,b		; A <- selective parameter
		ora	a
		jz	el_to_end	; default is "erase from cursor to end of line"
		dcr	a
		jz	el_to_start	; Ps = 1 means "beginning of line to cursor"
		dcr	a
		rnz			; No options beyond Ps = 2
		call	el_to_end	; Ps = 2 means "erase whole line"
el_to_start:	lda	curs_col
		mov	b,a
		inr	b		; number of locations is cursor column (0-based) + 1
		lhld	start_line_addr	; from the start of the line 
		jmp	blank_chars
;
el_to_end:	lda	curs_col
		mov	b,a
		lda	curr_line_dbl
		ora	a		; NZ flag if current line is double width
		lda	screen_cols
		jz	not_double
		rrc			; divide columns by 2, on double width line
not_double:	sub	b
		mov	b,a		; B <- screen columns - cursor column
		lhld	cursor_address
;
; blank the number of characters in B, from the screen RAM position in HL
;
blank_chars:	mov	a,h		; Convert screen address in HL
		adi	10h		; to attribute RAM address in DE
		mov	d,a
		mov	e,l
		mvi	a,0ffh		; default rendition
blank_loop:	stax	d		; blank attributes
		mvi	m,0		; blank screen
		inx	h		; next addresses in screen RAM
		inx	d		; and attribute RAM
		dcr	b
		jnz	blank_loop
		sta	rend_und_curs	; default rendition is 0ffh
		xra	a
		sta	char_und_curs	; and character under cursor is blank, 00h
		ret
;
; ed_action
;
;	Implements the ED (erase in display) control sequence, which has a single selective parameter
;
;	Lines that are wholly erased are made single width. The cursor line's width attribute is only
;	changed if the cursor is in column 0 when "erase to end of screen" is invoked, or the entire
;	display is erased.
;
ed_action:	mov	a,b		; A <- selective parameter
		ora	a
		jz	ed_to_end	; Ps = null/0 is "erase from cursor to end of display"
		dcr	a
		jz	ed_to_start	; Ps = 1 is "erase from start of screen to cursor"
		dcr	a
		rnz			; No options beyond Ps = 2, which is "erase entire display"
		call	ed_to_start
		call	ed_to_end
		jmp	line_attr_swl
;
;
ed_to_start:	lxi	h,curs_row
		mov	a,m		; A <- cursor row
		push	psw
		mov	b,a		; B <- cursor row
		xra	a		; 
		mov	m,a		; zero cursor row, for the sake of erase_n_lines
		mvi	c,-1		; Pretend cursor row is -1
		call	erase_n_lines
		pop	psw
		mov	m,a		; Now restore proper cursor row
		call	curs_line_addr	; HL <- start of cursor line in screen RAM
		jmp	el_to_start	; this line does not have line attributes changed
;
ed_to_end:	lda	curs_col
		ora	a		; If the cursor is at the start of the line, the line is made
		cz	line_attr_swl	; single width, otherwise not
		call	el_to_end
		lxi	h,curs_row
		mov	a,m		; A <- cursor row (for restoration later)
		push	psw
		mov	c,a		; C <- cursor row 
		mvi	a,23
		sub	c		; A <- number of complete lines to be erased
		mov	b,a
		call	erase_n_lines
		pop	psw
		mov	m,a		; restore original cursor row 
		jmp	curs_line_addr	; correct relevant pointers
;
; erase_n_lines
;	On entry:	HL points to curs_row
;			B is number of lines to erase (this may be zero)
;			C is one less than the row number of the first line to be *wholly* erased
erase_n_lines:	dcr	b
		rm			; done erasing whole lines
		inr	c		; increment row number
		mov	m,c		; write cursor row
		push	b
		push	h
		call	curs_phl_num	; A <- physical line number of cursor row, HL <- LATOFS entry
		ani	7fh		; ignore any double-width marker
		mov	m,a		; Erased lines become single width
		mvi	a,70h		; single width line attributes
		call	add_line_attrs
		call	curs_line_addr	; HL <- start of line in screen RAM
		lda	screen_cols
		mov	b,a
		call	blank_chars
		pop	h
		pop	b
		jmp	erase_n_lines
;
;	Set top and bottom margins
stbm_action:	mvi	c,81h
		call	wait_scroll
		call	last_row	; B <- last row number
		lda	csi_p1		; A <- first parameter (top margin)
		ora	a
		jz	p1_def		; If the first parameter is not zero (or zero by default)
		dcr	a		; reduce by one for internal numbering
p1_def:		mov	d,a		; D <- top margin
		lda	csi_p2		; A <- second parameter (bottom margin)
		ora	a		; Is the bottom margin defaulted, or zero?
		jnz	supp_b		; No, use it
		mov	a,b		; else make it the bottom of the screen
		inr	a
supp_b:		dcr	a
		mov	e,a		; E <- bottom margin
		mov	a,b		; A <- last row
		cmp	e		; If last row < bottom margin
		rc			; don't do anything
		mov	a,d		; A <- top margin
		cmp	e		; If top margin > bottom margin
		rnc			; don't do anything
		lxi	h,top_margin
		mov	m,d		; store top margin
		inx	h
		mov	m,e		; store bottom margin
		mov	c,e		; C <- bottom margin
		mov	b,d		; B <- top margin
		mov	a,c
		sub	b
		inr	a		; A <- bottom - top + 1
		mov	e,a		; E <- lines in scrolling region
		lxi	h,line1_dma
		mov	a,b		; A <- top margin
		ora	a
		jz	n_scroll_reg	; jump if top margin is top row 
		mov	d,b		; D <- top margin
top_mar_loop:	mov	a,m		; A <- high byte of DMA address 
		ani	7fh		; remove scroll region flag
		mov	m,a		; put back
		call	advance_line
		dcr	d
		jnz	top_mar_loop	; follow line links until we're at first line of new scroll region
n_scroll_reg:	mov	a,m		; A <- high byte of DMA address
		ori	80h		; add scroll region flag
		mov	m,a		; put back
		call	advance_line
		dcr	e
		jnz	n_scroll_reg
		mvi	a,23
		sub	c		; A <- number of non-scrollable lines at bottom
		jz	done_lines
		mov	d,a		; D <- line count
bot_mar_loop:	mov	a,m		; A <- high byte of DMA address
		ani	7fh		; remove scroll region flag
		mov	m,a		; put back
		call	advance_line
		dcr	d
		jnz	bot_mar_loop
done_lines:	mov	a,b		; A <- top margin
		sta	top_margin	; store
		mov	a,c		; A <- bottom margin
		sta	bottom_margin	; store
		lxi	h,latofs	; Now work our way through the logical address offset table,
		mvi	c,24		; halving each line again, if appropriate. This way, we grab
					; the terminating line attributes at the full length of each line,
					; which we've just modified, to re-copy them into the middle of each
					; double-width line.
half_line_loop:	mov	a,m		; Grab physical number of logical line 
		ora	a		; 
		jp	skip_single	; if it isn't double width, skip it
		push	h
		call	phl_loc		; HL <- addresss of pline_addr entry for this line
		mov	a,m
		inx	h
		mov	h,m
		mov	l,a		; HL <- start of screen RAM for line
		call	halve_line
		pop	h
skip_single:	inx	h
		dcr	c
		jnz	half_line_loop
		jmp	cursor_home
;
; advance_line
;	On entry: HL points to high byte of DMA address, A contains that byte
;	On exit:  HL points to high byte of next DMA address
;
advance_line:	inx	h		; HL points to low byte of DMA address
		mov	l,m		; L <- low byte
		ani	0fh		; A <- high byte already, which
		ori	20h		; we convert into proper address (i.e. discard line attributes)
		mov	h,a		; HL <- points to first character of next line
		inx	h		; and increment
		jmp	add_cols_to_hl	; so on return HL <- high byte of next DMA address
;
; move_updates
;	This routine is called any time that cursor row or column have been updated. This has a lot of work to do:
;	1. Place the old character and rendition where the cursor was
;	2. Possibly adjusting cursor position if we've moved to a double-width line
;	3. Triggering margin bell if this movement was caused by receiving printable characters
;	4. Saving the character and rendition of the new cursor position.
;
move_updates:	lxi	h,0dh		; set a tiny cursor timer
		shld	cursor_timer
		xra	a		; and record cursor visibility as off
		sta	cursor_visible	; so it will come back quickly after movement
		lhld	cursor_address
		lda	char_und_curs
		mov	b,a		; B <- char under cursor
		mov	m,a		; place char back on screen
		mov	a,h		; move HL to point to attribute RAM
		adi	10h
		mov	h,a
		lda	rend_und_curs
		mov	m,a		; place old rendition
		lda	screen_cols
		dcr	a
		mov	e,a		; E <- last column number
		lda	in_setup
		ora	a
		jnz	skip_half_col	; In setup, can't have double-width cursor line
		lda	curs_row
		lxi	h,saved_curs_row
		cmp	m
		jz	same_row
		mov	m,a		; save the new row
		call	curs_line_addr
		xra	a		; We didn't get here by typing, so clear the flag
		sta	margin_bell	; that allows the margin bell to be triggered by movement
		lxi	h,curr_line_dbl	; Is current line double width?
		mov	a,m
		ora	a
		jz	skip_half_col	; No, so last column number is correct
		mov	a,e		; Double-width, so halve last column number (e.g. 79 -> 39)
		dcr	a
		ora	a		; clear carry for the rotate
		rar
		mov	e,a
skip_half_col:	mov	a,e		; A <- last column number (adjusted, if necessary, for double width)
		sta	right_margin
same_row:	lxi	h,right_margin	; test if cursor has moved beyond right margin
		lxi	d,curs_col
		ldax	d		; A <- cursor column
		cmp	m
		jc	less_rmargin	; jump if less than margin
		mov	a,m		; otherwise place margin
		stax	d		; into current column
less_rmargin:	lda	last_curs_col
		adi	8		; Margin bell is triggered exactly 8 columns from right edge
		sub	m
		jnz	no_margin_bell
		inx	h		; HL <- margin_bell
		ora	m		; A was zero, so now NZ if we want a margin bell
		jz	no_margin_bell
		call	c0_bell
		xra	a		; now don't permit another margin bell until typed char
		sta	margin_bell	; sets this flag again (_see_ process_keys)
no_margin_bell:	lda	curs_col
		sta	last_curs_col
		lhld	start_line_addr
		call	add_a_to_hl
		shld	cursor_address	; Make new cursor address
		mov	a,m		; Grab character "under" cursor
		sta	char_und_curs	; store it until cursor moves
		mov	b,a		; B <- new character under cursor
		mov	a,h		; move HL to point to attribute RAM
		adi	10h
		mov	h,a
		mov	a,m		; A <- rendition "under" cursor
		sta	rend_und_curs	; store it until cursor moves
		lhld	cursor_address	; HL <- new cursor address
		mov	m,b		; place new/old character back
		ret
;
; Entry point for CSI state, initialising parameters, private flag, intermediate
; and final characters
start_csi:	mov	b,a		; B <- received char while we initialise state
		lxi	h,gather_params	; private flag and params are first part of control sequence
		shld	char_action	; set up processing for next character
		xra	a
		sta	param_value	; zero out csi_param state
		sta	num_params
		sta	inter_chars
		; zero out the params array
		lxi	h,csi_params
		mvi	c,0fh
		xra	a
zero_csi:	mov	m,a		; zero this parameter
		inx	h
		dcr	c
		jnz	zero_csi
;
		lxi	h,csi_private	;
		mvi	m,0		; mark that we haven't seen a private character
		mov	a,b		; A <- received char
		cpi	'@'		; is it a final character?
		jnc	gather2		; yes
		cpi	'<'		; less than flag character range?
		jc	gather2		; yes, start building parameter value
		mov	m,a		; store flag character
		ret
;
; This is the entry point for all subsequent characters while we're in this state.
;
; This section has to deal with parameter values, which are sequences of ASCII digits '0' to '9',
; separated with ';' and recognising intermediate and final characters. Intermediates are from
; SP (20h) to '/' (2fh), Finals are from '@' (40h) to '~' (7eh) and most other characters will
; invalidate the sequence. Because the VT100 doesn't support any sequences with intermediates,
; it gathers them, along with other invalid characters, and only disposes of them when a Final
; character has been found and the sequence is executed.
;
; This section has a bug at the marked line. Any character other than a digit is supposed to be
; passed through to finish_param, which puts aside the current character while the gathered current
; numeric parameter (param_value) is placed at the end of the list (csi_params). Then, the current
; character is restored from the stack and we drop through to detect_i_f, to determine what to do
; with the current character. Characters above the digit range, like the semicolon or final characters,
; will be dealt with correctly here, but characters below digit range (intermediates) have already
; been corrupted by having 30h subtracted from their value, leaving them in the range 0f0h to 0ffh,
; and detect_i_f will incorrectly treat them as final characters, leading to immediate execution of
; the sequence, with a final character in this high range, which fails to match any of the tables.
;
; A valid but unsupported sequence like: ESC [ 9 ! p
; will be executed by the VT100 on reaching the '!', leaving the parser in "ground" state, which
; means that the final character "p" will be displayed on the screen.
;
; With this bug, the bytes from the label not_final to the next "ret" (17 bytes) are all unreachable.
;
; If the buggy line is replaced by:
;
;	cmp '0'
;
; then all the rest works as intended.
;
gather_params:	mov	b,a
gather2:	mov	a,b
		cpi	'9'+1		; above digit range?
		jnc	finish_param	; then we've finished with this parameter (at least)
		sui	'0'		; convert to actual digit value [* BUG *]
		jm	finish_param	; might have hit an intermediate, or something invalid
		mov	c,a		; C <- value of this digit
		lxi	h,param_value
		mov	a,m		; A <- current param value
		cpi	1ah		; if the current param value >= 26, multiplying by
					; 10 would send us out of range,
		jnc	par_range	; so limit it to 255
					; otherwise, multiply current value by 10
		rlc			; A <- param * 2
		mov	b,a		; B <- param * 2
		rlc			; A <- param * 4
		rlc			; A <- param * 8
		add	b		; A <- param * 8 + param * 2 (= param * 10)
		jc	par_range	; don't think this could be OOR now?
		add	c		; A <- param + current digit value
		jnc	par_store	; but this could be OOR (e.g. 259)
par_range:	mvi	a,0ffh		; out of range parameters are limited at 255
par_store:	mov	m,a		; store new param_value
		ret
		;
		; We've now collected a CSI parameter value in param_value (212fh)
		; and we want to store it in the list of parameters for this sequence.
		; We do this regardless of what we're going to do next, which might be to
		; start a new parameter, invalidate the sequence, or execute it.
		;	
finish_param:	lxi	d,csi_params	; base of csi_params array
		push	psw		; push the character we're working on
		lxi	h,num_params
		mov	c,m		; retrieve offset into array
		mvi	b,0
		xchg			; HL <- base of array, DE <- num_params
		dad	b		; HL <- addr of next param to store
		lxi	b,param_value
		ldax	b		; A <- new param value
		mov	m,a		; store in array
		xra	a
		stax	b		; now we've stowed parameter, zero current value
		ldax	d		; A <- num params (array offset)
		cpi	0fh		; Limit ourselves to storing 16 params
		jz	no_more_params	; Have we just stored the 16th parameter?
		inr	a		; Still OK
		stax	d
no_more_params:	pop	psw		; A <- character we're working on
		;
		; This is a control sequence state where we're only collecting intermediates and
		; finals. This state also allows ';' parameter separators to appear, which would be
		; illegal after intermediate characters. However, the VT100 doesn't support any
		; sequences with intermediates, so this state can harmlessly use the next few lines
		; as part of two different states.
		;
detect_i_f:	mov	b,a		; B <- copy of original character
		cpi	03bh		; if it's a ';' separator, we're done for now
		rz
		ani	0c0h		; Control sequence finals are 040h to 07fh
		mov	a,b
		jz	not_final	; not a final character
		sta	final_char
		jmp	execute_seq
		;
		; At this stage, we know the current character didn't form part of a parameter value
		; so, having tidied away the last parameter value, we now know that we're not
		; dealing with a parameter separator or a final character. This could only be an
		; intermediate or an illegal character (e.g. ':') or a character out of place, such
		; as another private flag. We'll untangle these later but for now we'll add them
		; into the intermediate store and change the action to collect the rest of the
		; sequence until a final arrives, without storing further numeric parameters.
		;
not_final:	lxi	h,inter_chars	; Mix this character into the intermediate store, and we'll
		add	m		; untangle invalidity here when it's time to execute the sequence.
		jnc	inter_range_ok	; Mindful that we wouldn't want to wrap addition round to where
		mvi	a,0ffh		; we appear to have a legal intermediate again.
inter_range_ok:	mov	m,a		; Store our intermediate (or illegal mix)
		lxi	h,detect_i_f	; Only collect "intermediates" and detect finals from now on.
		shld	char_action
		ret
;
; store_nvr
;	Store current settings back in NVR. The opposite of _see_ recall_nvr.
;
store_nvr:	mvi	d,0		; direction is write
		mvi	b,1		; try once
		jmp	settings_nvr
;
recall_nvr:	call	init_video_ram
		mvi	b,10		; try 10 times
		mvi	d,1		; direction is read
;
settings_nvr:	push	b
		push	d
		call	print_wait	; "Wait"
		pop	d
		di			; all NVR access is done with interrupts disabled
		lxi	h,aback_buffer
		mvi	e,33h		; Number of bytes in NVR, including checksum
		mvi	c,1		; C <- initial checksum
		xra	a
rw_byte_loop:	sta	nvr_addr 
		mov	a,c
		sta	nvr_checksum
		push	d
		push	h
		mov	a,d		; A <- direction flag
		ora	a		; Flag Z if storing settings
		mov	a,m		; A <- settings byte
		sta	nvr_data	; stow copy for working on
		cz	write_nvr_byte
		call	read_nvr_byte
		pop	h
		pop	d
		lda	nvr_data	; A <- read back settings byte
		dcr	e
		jz	finished_rw
		mov	m,a		; place settings byte in scratch RAM
		lda	nvr_checksum	; get checksum 
		rlc			; rotate and exclusive-or this byte into it
		xra	m
		mov	c,a		; C <- checksum
		inx	h		; point to next settings byte
		lda	nvr_addr	; increase NVR address
		inr	a
		jmp	rw_byte_loop
;
finished_rw:	cmp	m		; compare final byte (A) with checksum
		pop	b
		mvi	c,0		; return result
		jz	nvrchk_ok
		dcr	b		; checksum wrong, so try again (on recall only)
		jnz	settings_nvr
		call	init_scratch	; Otherwise give up and put reasonable defaults in scratch
nvrchk_ok:	mov	a,c
		ora	a		; This routine returns Z flag for "ok, read NVR and checksum matched"
		push	psw
		mvi	c,iob_flags_lba7
		mvi	a,99		; last address in NVR
		call	set_nvr_addr_a
		lxi	h,main_video_be	; To match screen address main_video
		shld	line1_dma	; Put normal screen back
		pop	psw
		ret
;
; A tiny area of scratch RAM is used for the tiny screen definition used when
; NVR is being accessed and "Wait" is displayed.
;
print_wait:	lxi	d,wait_display
		mvi	b,7
		lxi	h,wait_addr	; Copy "Wait" to video RAM, with terminators
		call	memcopy		; that point to fill lines.
		lxi	h,wait_addr_be
		shld	line1_dma
		ret
;
; init_scratch
;	Initialise all scratch locations from the answerback buffer up to rx_spd, inclusive
;	Returns C = 1, for the benefit of recall_nvr, which wants to return non-zero
;	if NVR couldn't be read (or checksum didn't match.) (_see_ recall_nvr)
;
init_scratch:	lxi	h,aback_buffer
		mvi	b,27h		; Answerback buffer + tab settings
scribble_loop:	mvi	m,80h		; scribble (80h is "end of string" for answerback and tab-every-8)
		inx	h
		dcr	b
		jnz	scribble_loop	; HL finishes pointing to columns_132
		lxi	d,scratch_defs
		mvi	b,11		; 11 locations to initialise
		call	memcopy
		mvi	c,1		; C <- 1 is for the benefit of recall_nvr
		mvi	a,30h
		sta	bell_duration	; going to sound bell
		ret
;
; "Wait" is followed by terminator and address that leads back to the fill lines.
;
wait_display:	db	'Wait',7fh,70h,06h

; Initialisation values for scratch area from columns_132 to rx_spd, inclusive
; Note that failure of NVR leaves the terminal in VT52 mode rather than ANSI mode!
;
scratch_defs:	db	0		; columns_132 <- 80 columns
		db	8		; brightness <- three quarters brightness
		db	6eh		; pusart_mode <- 1 stop bit, no parity, 8 bits, 16x clock
		db	20h		; local_mode <- "local"
		db	0d0h		; setup_b1 <- smooth scroll, autorepeat, dark background, block cursor
		db	50h		; setup_b2 <- no margin bell, keyclick on, VT52 mode, auto xon/off
		db	0		; setup_b3 <- ASCII, no autowrap, no newline, no interlace
		db	20h		; setup_b4 <- no parity, 8 bits, power 60 Hz
		db	0		; setup_b5 <- (don't care)
		db	0e0h		; tx_spd <- 9600 baud
		db	0e0h		; rx_spd <- 9600 baud
;
;	CUU - cursor up n rows
cuu_action:	lda	top_margin
		lxi	b,00ffh		; B <- limit of movement (row 0), C <- direction (-1 = up)
		jmp	row_mv
;
;	CUD - cursor down n rows
cud_action:	call	last_row	; B <- last row number (i.e. 13, or 23 with AVO)
		lda	bottom_margin
		mvi	c,1		; C <- direction of movement (+1 = down)
;
; row_mv
;	On entry, B is limit of movement, which is 0 or last row (cursor movement can't cause scrolling)
;	          C is direction of movement, -1 for up, or +1 for down
;
row_mv:		lxi	h,curs_row	; HL <- coordinate location we're affecting (row)
		jmp	cur_mv
;
;	CUF - cursor forward n columns
cuf_action:	lda	right_margin
		lxi	b,0ff01h	; B <- limit of movement (column 255!), c is direction of movement (+1)
		jmp	col_mv		; shared code with CUB
;
;	CUB - cursor backward (left) n columns
cub_action:	xra	a
		lxi	b,00ffh		; B <- limit of movement (column 0), c is direction of movement (-1)
col_mv:		lxi	h,curs_col
; Row movement can also be processed here, by having HL initialised to the curs_row address and
; appropriate limits set
cur_mv:		mov	d,a		; D <- appropriate margin, to limit movement
		lda	csi_private	; Check that we haven't got any private characters
		ora	a		; because there is no private meaning for any of the
		jnz	to_ground	; cursor movement sequences
		lda	csi_p1		; Defaulting the first parameter: if the parameter
		ora	a		; hasn't been supplied, or is supplied as zero,
		jnz	got_p1
		inr	a		; then treat it as one
got_p1:		mov	e,a		; E <- number of times to move
		mov	a,m		; A <- current column
repeat_move:	cmp	d		; check against margin
		jz	stop_move
		cmp	b
		jz	stop_move
		add	c
		dcr	e		; Do this movement until limited (conditions above)
		jnz	repeat_move	; or until we've exhaused the count
stop_move:	mov	m,a		; store final column address
		jmp	move_updates
;
; cursor_home
;
;	Because this routine clears the first two CSI parameter locations in order to act like a CUP
;	or HVP sequence with defaulted row and column positions, it provokes a bug in DECOM.
;	_See_ decom_mode for details.
;
cursor_home:	lxi	h,0
		shld	csi_params
		mvi	a,0ffh
		sta	saved_curs_row

;
; curpos_action
;
;	The sequences CUP (CSI H) and HVP (CSI f) both come here, as they have identifical effects on all
;	models of DEC VTs.
;
;	This routine has a bug in that it starts off by storing the origin mode flag in the C register,
;	but can lose track of that and use C for a row number instead, but then make a further decision
;	as if it still contained the flag.
;
;	The fault path is triggered if we are not in origin mode, which means the code validates the
;	row parameter against the last row of the screen, not the bottom margin. At this point, C is
;	changed from storing the origin mode flag to storing the requested new row. Next, the column
;	number is validated by checking the column number against either the right margin (origin mode)
;	or the last column on the screen (non origin mode). If we are in origin mode, the test proceeds
;	as intended, but if we were not in origin mode, using the right margin or last column depends
;	on whether the new internal row number is 0 or not. If it is non-zero, we check the right margin
;	(i.e. acting like origin mode) instead of last column.
;
;	This bug constrains the cursor column update to the right margin even if origin mode is not in
;	effect. However, the VT100 doesn't have settable left and right margins, and the right margin is
;	only ever different from last column number on double width lines. So there is no case in which
;	this code will allow the setting of a column number beyond the right margin, which means the
;	corruption of the middle-of-line terminators on double width lines cannot occur. (In any case, all
;	cursor moves are then re-validated by _see_ move_updates.)
;
;	The effect of the bug is that cursor moves from a line that is double-width to a line that is
;	single width are constrained by the right margin of the current line, provided the new row
;	is anything other than row 1, which is incorrect.
;
;	This is demonstrated by test t/margin-bug.txt. [* BUG *]
;
curpos_action:	lda	origin_mode
		mov	c,a
		lxi	h,csi_p1
		mov	a,m		; Pn1 is row
		ora	a		; default/0 will be top row 
		jz	def_row	
		dcr	a		; Otherwise, our internal rows are 0-based, not 1-based
def_row:	mov	b,a		; B <- row
		mov	a,c		; A <- origin mode flag
		ora	a
		jz	add_top		; jump if not in origin mode
		lda	top_margin	; In origin mode, move within margins
add_top:	add	b
		mov	b,a		; B <- adjusted row
		mov	a,c		; A <- origin mode flag 
		ora	a
		lda	bottom_margin	; A <- bottom margin
		jnz	chk_bot_limit	; jump if origin mode
		mov	c,b		; C <- new row
		call	last_row	; B <- last row on screen
		mov	a,b		; A <- last row
		mov	b,c		; B <- new row
chk_bot_limit:	cmp	b		; comparing new row against either bottom margin or last row
		jc	skip_row	; if last row < new row, go store last row
		mov	a,b		; else new row is ok
skip_row:	sta	curs_row	; store row
		inx	h		; HL points to csi_p2
		mov	a,m		; A <- Pn2 (column)
		ora	a		; default/0 will be left column
		jz	def_col
		dcr	a		; Otherwise, our internal cols are 0-based, not 1-based
def_col:	mov	b,a		; B <- col
		mov	a,c		; A <- 1 if origin mode flag had been set, new row if unset
		ora	a		;
		jnz	use_rmargin	; jump if origin mode
		lda	screen_cols
		dcr	a		; A <- last column number
		jmp	chk_rlimit
;
use_rmargin:	lda	right_margin
chk_rlimit:	cmp	b
		jc	nolim_rm	; if right margin < requested column, store margin
		mov	a,b		; else A <- request column
nolim_rm:	sta	curs_col	; store
		jmp	move_updates
;
; read_nvr_byte
;
read_nvr_byte:	mvi	c,iob_flags_lba7
		call	set_nvr_addr
		call	read_nvr_data
		jmp	nvr_idle
;
; write_nvr_byte
;
;	Writing a byte to the NVR involves addressing the location and an erase cycle first,
;	which involves commanding the erase operation and waiting; there is no positive
;	acknowledgement	of completion.
;
write_nvr_byte:	mvi	c,iob_flags_lba7
		call	set_nvr_addr
		call	erase_nvr	; includes 20 ms delay
		call	nvr_accept
		call	write_nvr	; includes 20 ms delay
nvr_idle:	mvi	a,30h		; c000 d0 = "accept data" (inv)
		out	iow_nvr_latch
		ret
;
read_nvr_data:
w1h:		in	ior_flags	; ER1400 shows command acceptance on rising
		ana	c		; edge of clock. Wait for high, low,
		jz	w1h		; command, then wait for high again.
w1l:		in	ior_flags
		ana	c
		jnz	w1l
		mvi	a,2dh		; c110 d1 = "read" (inv)
		out	iow_nvr_latch
w2h:		in	ior_flags
		ana	c
		jz	w2h
w2l:		in	ior_flags
		ana	c
		jnz	w2l
		mvi	a,2fh		; c111 d1 = "standby" (inv)
		out	iow_nvr_latch
		lxi	h,nvr_bits
		mvi	b,14		; shifting 14 bits out of NVR
w3h:		in	ior_flags
		ana	c
		jz	w3h
w3l:		in	ior_flags
		ana	c
		jnz	w3l
		mvi	a,25h		; c010 d1 = "shift data out" (inv)
		out	iow_nvr_latch
w4h:		in	ior_flags	; \
		ana	c		;  |
		jz	w4h		;  |
		in	ior_flags	;  |
		mov	m,a		;  | - squirrel away raw flags buffer value
		inx	h		;   > 14 bits
w4l:		in	ior_flags	;  |
		ana	c		;  |
		jnz	w4l		;  |
		dcr	b		;  |
		jnz	w4h		; /
		mvi	a,2fh		; c111 d1 = "standby" (inv)
		out	iow_nvr_latch	; 
		lxi	d,nvr_bits
		mvi	b,14		; 14 bits again
		lxi	h,0
accum_bits:	dad	h		; shift HL left, clearing bit 0 of L
		ldax	d		; grab next bit, which is raw flags buffer read
		ani	iob_flags_nvr	; isolate bit 5
		rlc			; data is bit 6
		rlc			; data is bit 7
		rlc			; data is bit 0
		ora	l		; Add to HL
		mov	l,a
		inx	d		; next raw read
		dcr	b		; for all 14 bits 
		jnz	accum_bits
		shld	nvr_data	; stow all 14 bits
		ret
;
; used for both read and write operations
; only routine that uses nvr_addr
;
; Addresses are represented by 20 bits are split into a tens and units part, each represented by ten
; bits. Addresses are clocked into the ER1400 with all address bits held high except for the single
; bit of the digit that represents your tens or units.
;
; In order to get the timing right, this routine pre-calculates all 20 bits of the address in memory,
; in the nvr_bits array, including the complete C1, C2, C3 for each NVR latch byte.
;
set_nvr_addr:	lda	nvr_addr
set_nvr_addr_a:	mvi	b,-1		; The address is broken up into tens and units
addr_tens:	inr	b
		sui	0ah
		jp	addr_tens
		adi	0ah		; Now B is tens, A is units
		lxi	h,nvr_bits
		mvi	e,23h		; c001 d1 "accept address" (inv)
		mvi	d,20		; 20 address bits
addr_const:	mov	m,e		; some kind of constant lead-in?
		inx	h
		dcr	d
		jnz	addr_const
		mvi	m,2fh		; c111 d1 "standby" (inv) 
		lxi	h,nvr_bits
		mov	e,a		; 
		mvi	d,0		; DE <- units address
		dad	d		; Advance HL by units address
		mvi	m,22h		; c001 d0 "accept address" (inv)
		lxi	h,nvr_bits
		mvi	a,0ah
		add	b		; A = address tens + 10
		mov	e,a		; 
		dad	d		; Advance HL by 10 + tens address
		mvi	m,22h		; c001 d0 "accept address" (inv)
wa1l:		in	ior_flags
		ana	c
		jnz	wa1l
		lxi	h,nvr_bits	; Back to beginning of bits, ready for latching on clock lows
		mvi	b,21		; must be complete in 21 clock periods (including high after last bit)
wa1h:		in	ior_flags
		ana	c
		jz	wa1h
		dcr	b
		rm			; limited cycles for entire write
wa2l:		in	ior_flags
		ana	c
		jnz	wa2l
		mov	a,m
		out	iow_nvr_latch
		inx	h
		jmp	wa1h
;
nvr_accept:	lhld	nvr_data	; grab 14 bits of data
		dad	h		; shift the bits 2 places left so that the
		dad	h		; next add will start forcing data into carry
		lxi	d,nvr_bits
		mvi	b,14		; going to process 14 bits
next_split:	mvi	a,20h		; c000 d0 = "accept data" (inv)
		dad	h		; shift top by of HL into carry flag
		ral			; and pull it into bit 0 of A
		stax	d		; place in nvr_bits buffer
		inx	d
		dcr	b
		jnz	next_split
		mvi	a,2fh		; c111 d1 = "standby" (inv)
		stax	d
		lxi	h,nvr_bits
		mvi	b,15		; 14 data bits + standby terminator
wd1h:		in	ior_flags
		ana	c
		jz	wd1h
wd1l:		in	ior_flags
		ana	c
		jnz	wd1l
		mov	a,m
		out	iow_nvr_latch
		inx	h
		dcr	b
		jnz	wd1h
		ret
;
erase_nvr:
wl1h:		in	ior_flags
		ana	c
		jz	wl1h
wl1l:		in	ior_flags
		ana	c
		jnz	wl1l
		mvi	a,2bh		; c101 d1 = "erase" (inv)
		out	iow_nvr_latch
		call	wait_nvr
		mvi	a,2fh		; c111 d1 = "standby" (inv)
		out	iow_nvr_latch
		ret
;
; If we're expected to clock data out of NVR and we don't want it,
; we just wait out a number of clocks.
;
wait_nvr:	lxi	h,315		; 315 x LBA 7 cycles at 63.5 µs per cycle = 20 ms
w20h:		in	ior_flags
		ana	c
		jz	w20h
w20l:		in	ior_flags
		ana	c
		jnz	w20l
		dcx	h
		mov	a,h
		ora	l
		jnz	w20h
		ret
;
; After an "accept data" operation, command the NVR to write the data. Then wait.
; The datasheet says that the ER1400 will finish in a maximum of 24 ms.
write_nvr:
wwwh:		in	ior_flags
		ana	c
		jz	wwwh
wwwl:		in	ior_flags
		ana	c
		jnz	wwwl
		mvi	a,29h		; c100 d1 = "write" (inv)
		out	iow_nvr_latch
		call	wait_nvr
		mvi	a,2fh		; c111 d1 = "standby (inv)
		out	iow_nvr_latch
		ret
;
; Processing next "received" character for SET-UP, which means handling a keypress, as we're now in
; LOCAL mode, and keypresses aren't going to the host, but being reflected internally. For the
; mechanism here, _see_ report_char.
;
; On entry, A and B both contain the received character (_see_ reflect_char)
;
setup_action:	cpi	20h		; If SPACE is pressed,
		mvi	c,43h		; it is treated the same as RIGHT ARROW,
		jz	setup_cursor	; so perform cursor movement
		lxi	h,setup_ready
		push	h		; Push return address on stack
		cpi	C0_CR
		jz	c0_return
		cpi	C0_HT
		jz	c0_horiz_tab
		cpi	'9'+1		; Keys above numeric range are handled separately
		jnc	setup_keys
		sui	'0'		; Numeric keys are handled through a jump table,
		rm			; bring down into range and reject any keys lower than '0'
		add	a		; double up code because addresses are two bytes
		lxi	h,setup_key_t	; HL <- base of key table
		call	add_a_to_hl	;
		call	ld_hl_from_hl
		mov	a,b		; A <- received char
		lxi	d,rx_spd	; DE <- rx_spd, which is convenient for toggle speed keys, at least
		pchl			; jump to action routine
;
; Keyboard processing has detected SETUP key, which either takes us into or out of SET-UP
setup_pressed:	sta	pending_setup
		jmp	pk_click
;
; Pressing "SET UP" will mark a SET-UP action as pending, and then this routine will be called
; to either enter or exit.
;
in_out_setup:	lda	in_setup
		xri	0ffh		; Toggle in/out of SET-UP
		sta	in_setup
		jz	exit_setup
;
; TM says that, on entering SET-UP, it waits for scrolls to finish.
;
enter_setup:	mvi	c,80h
		call	wait_scroll
		lhld	char_action	; We're going to redirect all key actions
		shld	saved_action	; so save previous state
		lxi	h,setup_action	; and register the SET-UP action
		shld	char_action
		lxi	h,0
		shld	curkey_qcount	; keyboard_locked <- 0 too
		shld	pending_report	; sending_report <- 0 too
setup_addrs:	lhld	line1_dma
		shld	saved_line1_dma
		lhld	curs_col	; HL <- curs_row and curs_col
		shld	saved_curs_col	; save them
		call	extra_addr
		shld	start_line_addr
		xra	a
		sta	curs_col
		call	setup_display
		jmp	move_updates
;
exit_setup:	lhld	saved_action	; Restore character processing state (we could have been in the middle
		shld	char_action	; of receiving a control sequence when SET-UP was pressed.)
		call	extra_addr	; HL <- extra line screen RAM
		lxi	d,1000h
		dad	d		; HL <- start of cursor line attribute RAM
		lda	screen_cols	; Default attributes for entire line
restore_attr:	mvi	m,0ffh
		inx	h
		dcr	a
		jnz	restore_attr
		lxi	h,saved_curs_col
		mov	a,m		; A <- saved cursor column
		sta	curs_col
		mvi	a,0ffh		; A <- 0ffh
		inx	h		; HL points to saved_curs_row
		mov	m,a		; destroy it
		call	move_updates
		lhld	saved_line1_dma
		shld	line1_dma
		xra	a
		sta	noscroll
		sta	received_xoff
		in	ior_flags	; Exiting SET-UP will trigger DECREPTPARM if we are 
		ani	iob_flags_stp	; allowed to send them unsolicited, and if we don't have STP.
		jz	skip_tparm
		lda	tparm_solicited
		ora	a
		cz	setup_tparm
skip_tparm:	ret
;
; Jump table for digit keys pressed in either SET-UP mode
;
setup_key_t:	dw	restart		; Key 0 - reset
		dw	do_nothing_key	; Key 1 - has no function in SET-UP
		dw	toggle_tab	; Key 2 - set or clear tab 	(SET-UP A only)
		dw	setup_clr_tabs	; Key 3 - clear all tabs	(SET-UP A only)
		dw	toggle_online	; Key 4 - line/local
		dw	toggle_a_b	; Key 5 - SET-UP A/B
		dw	toggle_bit	; Key 6 - Toggle 1/0 		(SET-UP B only)
		dw	cycle_tx_speed	; Key 7 - Transmit speed
		dw	cycle_rx_speed	; Key 8 - Receive speed
		dw	switch_columns	; Key 9 - 80/132 columns
;
switch_columns:	call	setup_a_only
		xra	a
		sta	saved_curs_row
		sta	saved_curs_col
		lda	columns_132
		ora	a
		push	psw
		cz	init_132col
		pop	psw
		cnz	init_80col
		jmp	setup_addrs	; same address-setting code as entering SET-UP
;
restart:	rst	0
;
toggle_tab:	call	setup_a_only
;
		lda	curs_col
		ora	a		; Can't have a tab at first column on line
		rz			; so quit early
		call	tab_offs_curs
		xra	m		; flip tab state
		mov	m,a		; and write back
		call	tab_offs_curs
		ana	m
		mvi	b,'T'		; Assume there'll be a tab stop
		jnz	is_tab
no_tab:		mvi	b,0		; B <- blank
is_tab:		mov	a,b		; A <- 'T'/blank 
		sta	char_und_curs
		lda	curs_col
		jmp	disp_char_col
;
setup_clr_tabs:	call	setup_a_only
		call	clear_all_tabs
		call	clear_extra
		jmp	no_tab
;
; SET-UP key 4 toggles line/local
toggle_online:	lxi	h,local_mode
		mov	a,m
		xri	20h		; Toggle local mode
		mov	m,a
		xra	a
		sta	keyboard_locked
; this is just a convenient "ret" for a key that does nothing in SET-UP
do_nothing_key:	ret
;
toggle_a_b:	call	c0_return
		lxi	h,setup_video+7	; Screen location of final character of "SET-UP A" (or "B")
		mov	a,m		; A <- character
		xri	3		; A <- "A" ^ "B"
		mov	m,a		; Write it back
		sta	setup_video+12h	; And same thing on bottom line, because it's double height
		ani	1		; And the low bit of the ASCII "A" conveniently matches
		sta	in_setup_a	; our flag for which screen we're on
		jz	draw_setup_b
		jmp	draw_setup_a
;
; toggle_bit allows any of the SET-UP B configuration blocks to be updated, with
; addressing made easy by a cunning screen layout; The screen looks like this:
;
; 1 1101  2 1111  3 0100  4 0010  5 0000 <- (optional block 5)
;
; As each setup block is only 4 bits in the top half of each setup byte, the
; placement of the bit blocks 4 columns apart, allows the col_in_bits
; routine to directly address the correct bit (after the starting column offset
; has been removed.)
;
toggle_bit:	call	setup_b_only
		lxi	h,setup_b1	; First block on screen (lowest in memory)
		lda	curs_col
		sui	2		; Ignore the "1 " at the start of line
		cpi	28h		; To accommodate possible block 5
		rnc			; Return if out of range
		nop			; Feels like last-minute code removal here
		nop
		nop
		nop
		mov	d,a		; D <- A because col_in_bits uses both
		call	col_in_bits
		xra	m		; toggle the appropriate bit
		mov	m,a		; and write back
		call	program_pusart
		jmp	draw_setup_b
;
; cycle_tx_speed
; cycle_rx_speed
;
;	SET-UP initialises DE to point to rx_spd before jumping to action routines, so cycle_tx_speed
;	just adjusts this location before dropping through to the generic routine.
;	SET-UP B ONLY
;
cycle_tx_speed:	dcx	d		; DE <- tx_spd
cycle_rx_speed:	xchg			; HL <-> DE, so HL points at speed location
		call	setup_b_only	; A is 0 on exit!
		sta	curs_col
		mov	a,m		; Read current speed
		adi	10h		; add to the value in top 4 bits
		mov	m,a		; Store new value
		call	program_pusart
		jmp	draw_setup_b
;
; setup_a_only
; setup_b_only
;	These guard routines are called by functions that should only work in one of the two
;	SET-UP modes, because key dispatching happens through the same table for both screens.
;	These routines are called by action routines and they will just return if the correct
;	SET-UP screen is in use. Otherwise, they'll pop the stack, to quit the action routine
;	early and return to the action routine's caller.
;
setup_a_only:	lda	in_setup_a
		ora	a
		rnz			; Correct screen; return to caller
		pop	h
		ret			; else discard the action routine
;
setup_b_only:	lda	in_setup_a
		ora	a
		rz			; Correct screen; return to caller
		pop	h
		ret			; else discard the action routine
;
; In SET-UP mode, deal with keys other than digits (which are handled through a table)
;
setup_keys:	lda	last_key_flags	; All other keys will need SHIFT to be pressed
		ani	key_flag_shift
		rz			; so if it isn't, exit
		mov	a,b
		cpi	'S'		; SHIFT S stores settings in NVR
		jnz	try_recall
		call	store_nvr
		jmp	post_nvr
;
try_recall:	cpi	'R'		; SHIFT R recalls settings from NVR
		jnz	try_answerback
		call	recall_nvr
		ei
		call	init_devices
		call	enter_setup
post_nvr:	ei
		call	setup_display
		ret
;
try_answerback:	cpi	'A'
		rnz
		call	setup_b_only
		call	c0_return	
		mvi	a,'A'		; extra line is initialised with "A= " and then you type a
		call	print_char	; delimiter, rest of message and another delimiter to finish.
		mvi	a,'='
		call	print_char
		mvi	a,' '
		call	print_char
		lxi	h,aback_entry
		shld	char_action
		pop	h
		ret
;
; These 10 bytes are all valid 8080 instructions but are unreachable. The first byte is a little out of
; place, hence my assumption that it's the checksum for ROM 4 (1800h - 1fffh), as there are no unused
; non-zero bytes elsewhere in this ROM. The other 9 bytes would result in a lowercase character in the
; A register being made uppercase, returning all others unchanged. As this is very far from the keyboard
; routines, perhaps this is the remnants of some VT50 compatibility code. Who knows?
;
		sbb	b		; = 98h. Probably CHECKSUM (first byte of unused code)
		cpi	61h		; UNREACHABLE (see note above)
		rm
		cpi	7bh
		rp
		ani	0dfh
		ret
;
; Gets us ready for next setup action. Used as a handy return point by being pushed on the stack.
;
setup_ready:	call	ready_comms
		lxi	h,setup_action
		shld	char_action
		ret
;
; extra_addr 
;	Returns with HL containing address of the extra line in screen RAM.
;	This is the line that gets used as the cursor line in SET-UP mode, so in SET-UP A, it
;	shows all the tab stops; in SET-UP B the cursor moves along it to select a switch to be
;	changed, and the answerback message gets entered here. 
;
extra_addr:	lhld	line_25_addr
		jmp	real_addr2
;
wait_screen:	lxi	h,wait_addr
					; fall through, pointlessly, as HL is already in screen range
; local copy of real_addr
real_addr2:	mov	a,h
		ani	0fh
		ori	20h
		mov	h,a
		ret
;
; finish_setup
;
;	The final part of drawing the setup screen is connecting the cursor line (23rd line = row 22), to the
;	"Wait" line that we're using as 24th line (row 23).
;
finish_setup:	call	extra_addr	; HL <- extra line in screen RAM
		call	clear_row
		push	h		; HL points to where terminator should be/is
		mvi	m,7fh		; OK, put terminator there
		inx	h		; point to where screen DMA address will be
		xchg			; Stow it in DE
		call	wait_screen	; HL <- wait screen line
		mov	a,h		; Add line attributes for use as DMA high byte
		ani	0fh
		ori	70h
		stax	d		; Next line address is "Wait" line
		inx	d
		mov	a,l
		stax	d
		pop	h		; HL <- back to terminator address
;
; Now write a line containing a 'T' at every tab stop position.
; Other columns aren't written, so they remain blank.
;
		lda	screen_cols
		mov	e,a		; E <- column number
		mvi	b,'T'		; B <- character drawn at tab stops
tloop:		mov	a,e
		call	tab_offs
		ana	m		; If the bit in A is not set in (HL),
		jz	tnotab		; then there is no tab set here.
		mov	a,e		; Otherwise, draw a 'T' at this column
		call	disp_char_col
tnotab:		dcr	e		; Loop for all columns
		jnz	tloop
		ret
;
setup_display:	lxi	b,setup_a_string
		lxi	h,setup_video	
		mvi	a,0fah		; "SET-UP x" is bold and blinking
		call	display_zstr
		mvi	c,1		; terminate 1 line
		mvi	b,10h		; line attributes *for next line*: bottom half, double height
		call	term_line
		lxi	b,setup_a_string
		mvi	a,0fah		; still bold and blinking
		call	display_zstr
		mvi	c,1
		mvi	b,50h		; line attributes for next line: double width
		call	term_line
; "To exit..." is underlined
		lxi	b,to_exit_string
		mvi	a,rend_under
		call	display_zstr
		mvi	c,13h		; terminate 19 lines
		call	term_line1	; use entry point that sets single width line attributes
		; Now the 3 top lines and 18 middle blank lines have been written,
		; we're about to terminate the 22nd line and point to the current
		; cursor line for the 23rd line of the setup screen, which is where
		; the cursor will be movign, and also where answerback can be entered.
		; This cursor line is the 25th line of the main screen, which is
		; known to have nothing needing preserving on it, as scrolling has been
		; completed.
		mvi	m,7fh		; Terminate the last blank line, so that's 22 lines terminated.
		inx	h		; HL now points to where we're going to the write DMA addres
		xchg			; Pop this into DE temporarily
		call	extra_addr	; HL <- extra line address (25th line of main screen, i.e.
		mov	a,h		;   main_video + (ncols + 3 ) * 24 = 2a98h (80) or 2f78h (132)
		ori	70h		; Add line attributes
		stax	d		; Write high byte
		inx	d		; advance to low byte of DMA address
		mov	a,l		; A <- low byte of cursor line address
		stax	d		; Write low byte 
;
draw_setup_a:	call	wait_screen	; HL <- wait screen
;
; The final line of the screen, which for SET-UP is the column numbers,
; will go in the same place the "Wait" display is created.
; Now draw the column numbers at the bottom. We start with '1' and increment the
; number, discarding tens. Every tenth position we change between normal video
; and reverse video.
		lda	screen_cols
		mov	b,a
		mvi	a,'1'
n_col:		mov	m,a		; write current digit
		inx	h
		mov	c,a		; preserve number + rendition
		ani	0fh		; just consider units column
		mov	a,c		; restore number
		jnz	noflip		; If we've just written a '0', we'll
		xri	80h		; flip between normal and reverse video
noflip:		inr	a		; next column digit
		daa			; staying decimal
		jnc	normok		; carry from daa if we are in reverse video
		ori	80h		; so restore the reverse video bit
normok:		ani	8fh		; remove tens digit
		ori	'0'		; and ASCII-ify it
		dcr	b
		jnz	n_col
;
		call	end_screen
		call	finish_setup
		mvi	a,1		; 1 = "SET-UP A"
;
; Now we've drawn the SET-UP screen, switch the Video DMA to point to it.
;
display_setup:	sta	in_setup_a
		lxi	h,setup_video	; Our address, 2253h, will be sent to Video RAM as 3000h+(2)253h
		mov	a,h
		mov	h,l		; Video RAM address are big-endian, so swap bytes
		ani	0fh
		ori	30h		; Force top bits to say: not scrolling region, double-height top half
		mov	l,a
		shld	line1_dma
		ret
;
; display_zstr
;	Display the zero-terminated string pointed to by BC, at the screen address given by HL,
;	with character attributes in A.
;	Returns screen address in DE, attribute address in HL
;
display_zstr:	push	h		; Given a pointer to character memory,
		lxi	d,1000h		; Attributes are 1000h further on (somewhere beyond 3000h)
		dad	d
		pop	d		; swap so that HL <- attribute memory, DE <- character memory
n_ch:		push	psw		; push rendition while we grab character
		ldax	b		; Grab next character
		ora	a
		jz	z_term		; Zero byte to finish
		stax	d		; Place in character memory
		pop	psw		; A <- rendition
		mov	m,a		; Place rendition in attribute memory
		inx	h		; inc. attr ptr
		inx	d		; inc. char ptr
		inx	b		; inc. string ptr
		jmp	n_ch
;
z_term:		pop	psw		; clean the last rendition push
		ret
;
; term_line1
; term_line
;
;	This routine (with two entry points) helds construct SET-UP displays by providing a fast way
;	of terminating lines and writing video DMA addresses, with line attributes.
;
;	DE points to just beyond the last character of the line
;	B  holds the upper four bits of the video address, while is scroll region flag and line attributes (size);
;	   term_line1 is a convenient second entry point to say "single height, single width"
;	C is the number of lines to terminate, effective performing line feeds, which is used to make the blank
;	space in the middle of the SET-UP screen.
;
term_line1:	mvi	b,70h
term_line:	xchg			; DE <-> HL
;
term_loop:	mvi	m,7fh		; (HL) <- line terminator
		inx	h
		mov	d,h		; The characters for the next line will start two bytes
		mov	e,l		; further on, so get DE pointing to where they'll be
		inx	d
		inx	d
		mov	a,d		; Now make up a DMA address high byte for DE
		ani	0fh		; Mask off high nybble, '2', as that's a given
		ora	b		; and put in scrolling region and line attributes instead
		mov	m,a		; Write DMA high byte
		inx	h		; Point to DMA low byte
		mov	m,e		; ... and that's our real address low byte
		inx	h		; Move on, so that HL points to next character
		dcr	c		; If C is non-zero here, the next line is empty and
		jnz	term_loop	; we'll just terminate again (line feed operation)
		ret
;
; Write the terminator to mark this line as finished, and then write the next DMA address
; to point back to this terminator, to produce fill lines.
;
end_screen:	mvi	m,7fh		; write terminator
		mov	d,h		; DE <- address of terminator, so we write back to here
		mov	e,l
		inx	h		; Point to high byte of DMA address
		mov	a,d		; A <- high byte of terminator address
		ani	0fh
		ori	70h		; Write not scrolling, normal lines attributes, 2000h
		mov	m,a		; Write modified high byte
		inx	h		; Point to low byte
		mov	m,e		; Point low byte back to terminator too
		ret
;
setup_a_string:	db	'SET-UP A',0
to_exit_string:	db	'TO EXIT PRESS ',22h,'SET-UP',22h,0 ; asm8080 doesn't like nested quotes
;
; clear_extra
;	Clear the extra line
;
clear_extra:
		call	extra_addr
		jmp	clear_row
;
; SET-UP B screen initialisation
;
; Every change made to setup fields causes this line to be redrawn.
;
draw_setup_b:	call	clear_extra
		call	wait_screen	; HL <- start of screen line
		push	h
		mvi	a,4eh		; Clear 78 positions
		call	clear_part_row	; on current line to blanks and default rendition
		pop	h		; HL <- start of screen line
		push	h
		inx	h		; Leave first two locations blank for now,
		inx	h		; as we'll draw switch block numbers later.
		mvi	e,0		; E <- switch number (starting from high bit in setup_b1)
		mvi	b,4		; assume 4 setup blocks
		in	ior_flags	; read flag buffer
		ani	iob_flags_stp	; check for STP
		push	psw
		jz	next_block
		inr	b		; If we have STP, add another switch block
; must be drawing the setup blocks loop
next_block:	mvi	c,4		; C <- switches per block
nx_sw:		call	bit_from_setup	; A <- 1 or 0 of switch bit E
		ori	0b0h		; ASCII-ify in reverse video
		mov	m,a		; place on screen
		inr	e		; next switch bit
		inx	h		; next column on screen
		dcr	c
		jnz	nx_sw
;
; Gaps of four blanks between switch blocks (we fill in the switch block numbers later)
		mvi	c,4
blank4:		mvi	m,0		; write blank to screen
		inr	e		; next switch bit
		inx	h		; next column on screen
		dcr	c
		jnz	blank4
		dcr	b		; next switch block
		jnz	next_block
;
; Now draw the blanks between the last switch block and the baud rate fields
		mvi	c,4		; At least 4 blanks
		pop	psw
		push	psw
		jnz	draw_blanks	; We pushed the "test for STP" result, above
		mov	a,c		; Without an STP switch block,
		adi	8		; we need another 8 blanks
		mov	c,a
draw_blanks:	mvi	m,0		; write blank to screen
		inx	h		; next column on screen
		dcr	c
		jnz	draw_blanks
;
; Baud rate fields
		lxi	d,t_speed_string
		lda	tx_spd
		call	copy_baud_str
;
		lxi	d,r_speed_string
		lda	rx_spd
		call	copy_baud_str
;
		call	end_screen
;
; Finally, draw the numbers on the switch blocks
		lxi	d,8		; 8 characters between switch block numbers
		mvi	c,4		; Again, 4 blocks by default
		pop	psw		; Flags NZ means "got STP"
		jz	no_block_5
		inr	c		; Add that fifth block for STP
no_block_5:	mvi	a,'1'		; Switch block number one coming up
		pop	h		; HL <- start of screen line
next_block2:	mov	m,a
		inr	a		; next block number
		dad	d		; skip past block bits we drew earlier
		dcr	c
		jnz	next_block2
		xra	a		; A <- 0 means "in SET-UP B"
		jmp	display_setup
;
t_speed_string:	db	'   T SPEED '
r_speed_string:	db	'   R SPEED '

; copy_baud_str
;	Comms speeds are encoded internally as values 0 to 15 in the upper 4 bits
;	of the locations tx_spd and rx_spd.
;	The baud strings are 5 characters long, stored sequentially in the table
;	below this routine, without terminators, so this routine copies the
;	appropriate string to the buffer pointed to by HL.
;
;	The placement of these values in the upper 4 bits of a byte is the same as the
;	switch block settings that are also on the SET-UP B screen. It feels as if they
;	might originally have been planned as switch block settings.
;
copy_baud_str:	mov	c,a		; C <- speed value (memcopy corrupts A)
		mvi	b,11		; speed strings above are 11 characters long
		call	memcopy		; place in buffer
		mov	a,c		; A <- speed value, in upper 4 bits
		rrc			; To avoid shifting this value down 4 bits and
		rrc			; multiplying by 5 (x * 4 + x * 1), we combine
		mov	c,a		; the shift and multiply by calculating
		rrc			; x / 4 + x / 16. Same result but shorter by
		rrc			; four instructions.
		add	c		;
		mov	c,a		;
		mvi	b,0		; BC <- offset of string from baud_strings
		lxi	d,baud_strings
		xchg			; Swap HL <-> DE because can only add BC to HL
		dad	b		; HL <- string location
		xchg			; HL <-> DE because DE is "copy from" pointer
		mvi	b,5		; 5 chars to copy
		jmp	memcopy		; copy and return
;
; These strings aren't delimited because they are all five characters long
baud_strings:	db	'   50'
		db	'   75'
		db	'  110'
		db	'  134'
		db	'  150'
		db	'  200'
		db	'  300'
		db	'  600'
		db	' 1200'
		db	' 1800'
		db	' 2000'
		db	' 2400'
		db	' 3600'
		db	' 4800'
		db	' 9600'
		db	'19200'

; bit_from_setup
;	Retrieve bit E from setup blocks 1 to 5, numbered with bit 0 being bit 7
;	of setup block 1.
;	Returns 1 or 0 in A for bit state (don't need a mask from this routine,
;	as we're just going to print the result.)
;
bit_from_setup:	push	h
		lxi	h,setup_b1
		mov	d,e		; It's a quirk of col_in_bits that the bit number
		mov	a,e		; must be provided in A and D
		call	col_in_bits
		ana	m
		pop	h
		rz
		mvi	a,1
		ret
;
; Combine rx_spd and tx_spd configuration locations into a single byte, which the
; Technical Manual says allows both speeds to be altered by a single write to the PUSART.
;
program_pusart:	lda	rx_spd		; A <- receive speed, in bits 7-4
		ani	0f0h		; mask and shift down to low 4 bits
		rrc
		rrc
		rrc
		rrc
		mov	b,a
		lda	tx_spd		; A <- transmit speed, in bits 7-4
		ani	0f0h		; mask and combine with receive speed
		ora	b
		sta	tx_rx_speed	; store combined speed byte
		ani	0f0h		; Now look at just transmit speed
		cpi	20h		; Is it 110 baud?
		lda	pusart_mode
		jz	two_stop	; jump if 110 baud
		ani	3fh
		ori	80h		; Set 1½ stop bits (according to TM Figure 4-3-3 and 8251A datasheet)
		jmp	stow_m		; Why not one stop bit? 
;
two_stop:	ani	3fh		; Set two stop bits for transmit at low speed (TM §1.1)
		ori	0c0h
stow_m:		sta	pusart_mode
		in	ior_flags
		ani	iob_flags_stp
		jz	add_parity
		lxi	h,setup_b2
		mov	a,m
		ori	sb2_autoxon	; If we have STP, force Auto XON
		mov	m,a
		mvi	a,6eh		; And set serial to 1 stop bit, no parity, 8 data bits
		jmp	stow_m2
;
; Make another PUSART mode by combining parity information and other bits
add_parity:	lda	setup_b4
		ani	sb4_paritybits	
		mov	b,a		; B <- |pe|p1|  |  |  |  |  |  |
		lda	setup_b4
		ani	sb4_8bits	; A <- |  |  |8b|  |  |  |  |  |
		rrc			; A <- |  |  |  |8b|  |  |  |  |
		ori	20h
		ora	b		; A <- |pe|p1| 1|8b|  |  |  |  |
		rrc	
		rrc
		mov	b,a		; B <- |  |  |pe|p1| 1|8b|  |  |
		lda	pusart_mode	; grab existing mode
		ani	0c3h		; and preserve opposite bits from B
		ora	b		; combine
stow_m2:	sta	pusart_mode	; place back
		lda	setup_b4
		ani	sb4_50Hz
		jz	is_60
		mvi	a,10h
is_60:		adi	20h		; A <- 20h for 60Hz, 30h for 50Hz
		sta	refresh_rate	; Ends up in DC011 video processor
		lda	setup_b1
		ani	sb1_curblock
		jz	is_und
		mvi	a,1
is_und:		call	cursor_type	; A <- 1 for block cursor, 0 for underline
		call	reset_pusart
		lda	curs_col
		cpi	15h
		cz	update_dc011	; Update DC011 for interlace setting
		cpi	1dh
		cz	update_dc011	; Update DC011 for power hertz
		cpi	0ch		; 
		cz	set_charsets	; Update charsets on ANSI/VT52 change. There is no difference
					; between charset designation in ANSI/VT52 mode, but this
					; action merely mirrors the SM/RM ANSI sequence action
					; (_see_ ansi_mode)
		cpi	12h
		cz	set_charsets	; Update charsets on ASCII/UK change
		call	move_updates
		ret
;
; cursor_type
;
;	Called with A = 0 for underline cursor, 1 = block cursor.
;	Sets whether the basic character attribute has to match the cursor selection (not required if AVO
;	is present), and flags the cursor selection to video processor through basic_rev_video (which gets
;	sent to DC012.)
;
cursor_type:	ora	a		; NZ if block cursor
		jz	und_cursor
		sta	basic_rev_video	; block cursor selection will set basic attribute to reverse video
		xra	a
		jmp	set_curs_rend
;
und_cursor:	in	ior_flags
		ani	iob_flags_avo
		jnz	und_curs_base
		sta	curs_char_rend	; no character attribute (bit 7) change for cursor (because AVO present)
		mvi	a,1
		sta	basic_rev_video
		mvi	a,2
		sta	curs_attr_rend
		jmp	update_dc012
;
; Without AVO, picking a cursor type will also set the basic attribute for characters
;
und_curs_base:	xra	a
		sta	basic_rev_video
set_curs_rend:	sta	curs_attr_rend
		mvi	a,80h		; Set up character attribute use for cursor
		sta	curs_char_rend
		jmp	update_dc012
;
; The first character of an answerback message comes here, in order to store it as the answerback
; delimiters. The action then changes to answer_action for all the rest, up to a matching delimiter.
;
aback_entry:	call	answer_print
		lxi	h,aback_buffer
		mov	m,a		; First character becomes the delimiter
		inx	h
		shld	answerback_ptr
		mov	b,a		; B <- delimiter
		lxi	d,20
		call	memset		; Fill the answerback buffer with the delimiter
		lxi	h,answer_action	; Switch to the "rest of the message" handler
		shld	char_action
		ret
;
; answer_action
;
;	This routine handles keys that are pressed while we're entering an answerback message.
;
answer_action:	call	answer_print
		lhld	answerback_ptr
		mov	b,a		; B <- character pressed
		lda	aback_buffer	; A <- delimiter
		mov	c,a		; C <- delimiter
		cmp	b		; Have we had the delimiter again?
		jz	delim_found
		mov	a,l
		cpi	LOW aback_bufend ; have we exhausted the buffer?
		jz	delim_found
		mov	m,b		; add character to buffer
		inx	h
		shld	answerback_ptr
		ret
;
delim_found:	mov	m,c		; delimit the buffer
		call	clear_extra
		call	c0_return
		jmp	setup_ready
;
; answer_print:
;
;	Going to print_char, but making sure that control characters are shown as a diamond.
;
answer_print:	push	psw
		cpi	20h
		jnc	skip_ctrl_sub
		mvi	a,1		; A <- diamond glyph to represent control characters
skip_ctrl_sub:	call	print_nomap
		pop	psw
		ret
;
; disp_char_col
;	Display the character in register B at the column in register
;	A on the current line. 
;
disp_char_col:	push	h
		lxi	h,line_25_addr
		mov	c,a		; C <- column
		lda	columns_132
		ora	a
		jnz	c132
		mov	a,c		; A <- column
		cpi	80
		jp	col_oor		; column >= 80 in 80-column mode? Exit
c132:		mov	a,m		; A <- low byte of addr    \
		inx	h		; HL <- point to high byte  | load_hl_from_hl, unrolled
		mov	h,m		; H <- high byte of addr    |
		mov	l,a		; L <- low byte            /
		mov	a,h		; \
		ani	0fh		;  | screen_addr, unrolled
		ori	20h		;  |
		mov	h,a		; /
		mov	a,c		; A <- column
		add	l		; \
		mov	l,a		;  | add A to HL
		jnc	no_h_inc	;  |
		inr	h		; /
no_h_inc:	mov	m,b		; Place character on screen
		mov	a,b		; A <- character
col_oor:	pop	h
		ret
;
;	Called from DECTST
data_loop_test:	push	d
		xra	a
		sta	local_mode
		mvi	b,0		; Start with lowest speed
test_next_spd:	mov	a,b
		sta	tx_rx_speed	; Storing same speed as both transmit and receive
		out	iow_baud_rate
		mvi	c,1		; Going to send 01h, 02h, 04h, 08h, 10h, 20h, 40h
test_tx_ch:	mov	a,c
		out	iow_pusart_data	; send a character
		lxi	h,0c000h	; a long counter
test_wait_ch:	push	b
		push	h
		call	test_rx_q	; Set NZ for characters available
		pop	h
		pop	b
		jnz	test_got_ch
		inx	h
		mov	a,h
		ora	l
		jnz	test_wait_ch
data_failed:	mvi	a,5		; command byte: rx enable, tx enable
		out	iow_pusart_cmd
		lda	tx_rx_speed
		out	iow_baud_rate
		mvi	a,25h		; Into local mode and (briefly) light LEDs L2 and L4
		sta	local_mode	; (these are cleared during _see_ after_tests)
		xra	a
		stc			; set "test failed"
		pop	d
		ret
;
test_got_ch:	ani	7fh		; Ignore parity
		cmp	c		; check received character is the same
		jnz	data_failed
		mov	a,c
		rlc			; rotate set bit to next higher position
		cpi	80h
		mov	c,a
		jnz	test_tx_ch
		mov	a,b		; A <- speed
		adi	11h		; advance tx and rx speed together
		mov	b,a
		cpi	10h		; Last speed is 0ffh (+ 11h = 10h)
		jnz	test_next_spd
		xra	a		; clear carry - "test passed"
		pop	d
		ret
;
; modem_test
;	For this test, try commanding 7 combinations of three modem signals (except for all off)
;	and read back the resultant signals that should come from a modem or, in this case,
;	an appropriate loopback connector.
;
modem_test:	push	d
		mvi	d,7		; D <- signal combination
modem_loop:	mov	a,d
		call	modem_signals	; command signals through PUSART and NVR latch
		call	read_modem	; and read the response
		cmp	d		; which should be identical
		jnz	data_failed
		dcr	d
		jnz	modem_loop
		mvi	a,5		; command byte: rx enable, tx enable
		out	iow_pusart_cmd	; PUSART back to normal
		xra	a
		pop	d
		ret
;
; modem_signals
;
;	Register A is a modem signal enable mask:
;		01h - RTS (ready to send)
;		02h - SPDS (speed select)
;		04h - DTR (data terminal ready)
;
;	RTS and DTR are controlled by sending a PUSART command word.
;	SPDS is an output from the NVR latch.
;
;	NVR latch bit 5 drives BV2 /SPDS, which goes to the EIA pin 11, "speed select"
;
modem_signals:	mov	b,a
		ani	2		; A <- bit 1
		rrc			; A <- bit 0
		rrc			; A <- bit 7
		rrc			; A <- bit 6
		rrc			; A <- bit 5 (20h / 00h)
		ori	10h		; A <- bit 5 + bit 4 (30h / 10h)
		sta	vint_nvr
		out	iow_nvr_latch
		mvi	c,5		; command byte: rx enable, tx enable
		mov	a,b
		ani	1
		jz	no_rts
		mvi	c,25h		; command byte: RTS (request to send), rx enable, tx enable
no_rts:		mov	a,b
		ani	4
		jz	no_dtr
		mov	a,c
		ori	2		; mix in DTR (data terminal ready)
		mov	c,a
no_dtr:		mov	a,c
		out	iow_pusart_cmd
		ret
;
; read_modem
;
;	Reads modem buffer (read only I/O port 22h)
;	Not documented in TM
;	Looking at print set MP-00633-00 sheet 3 of 6, Modem Buffer is E41, an 81LS97 addressed
;	by signal BV2 MODEM RD L
;	DB 07 H is /CTS
;	DB 06 H is /SPDI
;	DB 05 H is /RI	-- ignored here
;	DB 04 H is /CD
;
;	This is designed to return a mask that matches the number passed to modem_signals, i.e.
;	01h will indicate that RTS (ready to send) worked,
;		because the modem returns CTS (clear to send) and CD (carrier detect)
;	02h will indicate that SPDS (speed select) worked,
;		because the modem returns SPDI (speed indicator)
;	04h will indicate that DTR (data terminal ready) worked
;		because the PUSART status indicates DSR (data set ready)
;
read_modem:	in	ior_modem
		mov	b,a		; B <- modem signals
		mvi	c,1		; Assume RTS worked
		mov	a,b
		ani	90h		; mask /CTS and /CD
		jz	test_spdi
		cpi	90h		; expecting both signals in same state
		mvi	a,0ffh
		rnz			; return with failure if not
		mvi	c,0		; if CTS and CD are not enabled, mark 0 so far
test_spdi:	mov	a,b		; A <- modem signals
		ani	40h		; mask /SPDI
		jz	test_ri		; not enabled
		mov	a,c
		ori	2		; mix in "SPDS worked" to result
		mov	c,a
test_ri:	in	ior_pusart_cmd	; read PUSART status byte
		rrc			; Looking for DSR (bit 7) and we want it to be low
		rrc			; to 5,
		cma			; invert
		ani	20h		; and mask
		xra	b		; xor with /RI from modem signals
		ani	20h		; and mask again (making the first mask pointless)
		mvi	a,0ffh		; failure if they weren't in the same state
		rnz
		mov	a,b		; A <- modem signals
		ani	20h		; if /RI not found, skip marking DTR
		jnz	modem_result
		mov	a,c
		ori	4		; mix in "DTR worked" to result
		mov	c,a
modem_result:	ora	a
		mov	a,c
		ret
;
; Zeroes till end of ROM ...
;
		org 1fffh
		db	0

; C0 Codes
C0_BS		equ	08h
C0_HT		equ	09h
C0_LF		equ	0ah
C0_CR		equ	0dh
C0_DLE		equ	10h
C0_XON		equ	11h
C0_XOFF		equ	13h
C0_CAN		equ	18h
C0_SUB		equ	1ah
C0_ESC		equ	1bh

; I/O Ports
; From TM Table 4-2-2 "List of Hex I/O Addresses", p.4-17
;
ior_pusart_data	equ	0
iow_pusart_data	equ	0

ior_pusart_cmd	equ	1
iow_pusart_cmd	equ	1

iow_baud_rate	equ	2

ior_modem	equ	22h

; This is the flags buffer. This defined in the VT100 Print Set, MP-00633-00,
; VT100 Basic Video (Sheet 6 of 6). It is an 81LS97 chip, buffering the signal
; names (and active H/L) shown in the comments
; TM §4.6.2.7 says that LBA 7 is used for clocking the NVR, and the print set shows this
ior_flags	equ	42h
iob_flags_xmit	equ	01h ; BV3 XMIT FLAG H
iob_flags_avo	equ	02h ; BV1 ADVANCED VIDEO L
iob_flags_gpo	equ	04h ; BV1 GRAPHICS FLAG L
iob_flags_stp	equ	08h ; BV3 OPTION PRESENT H
iob_flags_unk4	equ	10h ; BV4 EVEN FIELD L
iob_flags_nvr	equ	20h ; BV2 NVR DATA H
iob_flags_lba7	equ	40h ; LBA 7 H
iob_flags_kbd	equ	80h ; BV6 KBD TBMT H

; On Print Set MP-00633-00, this appears to drive the D/A latch E49, a 74LS174 device,
; with five bits of data and a sixth "init" value.
; POST sends 0f0h and the other writes are from a scratch location that goes from
; 0 (brightest) to 1fh (dimmest), making it look as if the POST write says "mid-brightness, init"
;
iow_brightness	equ	42h

; iow_nvr_latch
;
;	   7     6     5     4     3     2     1     0
;	+-----+-----+-----+-----+-----+-----+-----+-----+
;	|     |     |/SPDS| --- | C3  | C2  | C1  |data |
;	+-----+-----+-----+-----+-----+-----+-----+-----+
;
;	Not defined in TM - this from print set MP-00633-00.
;	Bit 4 is not connected. TM §4.2.7 says it was intended to disable receiver interrupts,
;		though it isn't used. In the earliest print set available, this drives a signal
;		called BV2 REC INT ENA H, which is ANDed with the "Receive Ready" BV3 REC FLAG H
;		signal from the PUSART.
;
;	Bit 5 drives BV2 /SPDS (active low), which goes to the EIA connector as "speed select"
;	Other modem signals are driven by PUSART command words.
;
;	The NVR latch is often driven (early initialisation and modem test, for instance) with
;	the command bits C3, C2 and C1 set to 0, the ER1400 "accept data" which the Technical
;	Manual explains as a handy idle command because the all zeroes protects the NVR from
;	spontaneous writes during power down.

iow_nvr_latch	equ	62h

ior_keyboard	equ	82h

; iow_keyboard
;
;	   7     6     5     4     3     2     1     0
;	+-----+-----+-----+-----+-----+-----+-----+-----+
;	|     |     |     |     |L1 on|L2 on|L3 on|L4 on|
;	+-----+-----+-----+-----+-----+-----+-----+-----+
;	   |     |     |     `-- keyboard locked LED
;	   |     |     `-- online/local LED
;	   |     `-- start scan
;	   `-- speaker click

iow_keyboard	equ	82h
iow_kbd_led4	equ	01h
iow_kbd_led3	equ	02h
iow_kbd_led2	equ	04h
iow_kbd_led1	equ	08h
iow_kbd_locked	equ	10h
iow_kbd_local	equ	20h
iow_kbd_scan	equ	40h
iow_kbd_click	equ	80h

; Detailed in TM p.4-70
iow_dc012	equ	0a2h

iow_dc011	equ	0c2h

iow_graphics	equ	0e2h

;
; Equates for RAM locations, 2000h - 2bffh (3 KiB)
;
; The Video Processor is hard-wired to DMA from this region, always starting a frame at 2000h.
;
; Memory layout
rom_top		equ	1fffh
;
ram_start	equ	2000h	; The VT100 without AVO has 3K of RAM, from 2000h to 2bffh
ram_top		equ	2bffh
avo_ram_start	equ	3000h
avo_ram_top	equ	3fffh	; AVO adds another 4K of RAM

line0_dma	equ	2001h
line1_dma	equ	2004h
; There are two names for this location because, although it is stack_top,
; the stack always decrements before a push, so 204eh itself is available for some other
; purpose, and we'd like a name for that.
stack_top	equ	204eh
;
; Extra line address, i.e. the line that is available to be scrolled onto the screen.
; From soon after reset, set to FA98, which is address of 25th (spare) line.
; If we go to bottom of screen, and execute LF, it becomes F2D0, i.e. the old 1st line.
;
line_25_addr	equ	204eh
; screen_cols is either 80 or 132
screen_cols	equ	2050h
;
; zeroed on width change. read in vertint
; When processing index_down, when smooth scrolling is enabled and we reach the bottom margin,
; this gets set to 1 and when processing reverse index and the top margin is reached, it'll get
; set to -1, to indicate the direction of the pending scroll.
; Pending scrolls are acted upon during vertical interrupts, as they will then cause single scan line
; changes until the extra line has fully scrolled into view (over 10 scans).
scroll_pending	equ	2051h
; stores pointer to screen DMA address (can only see a single write, and no reads)
; this name will have _dma on the end
UNREAD_X2052	equ	2052h
; Pointer to 25th line DMA address in screen RAM. Never read; confirmed by tests.
UNREAD_X2054	equ	2054h
; stores a line address for shuffle
shufdt2		equ	2056h
; stores a line address for shuffle
shufad2		equ	2058h
; Scan line of current scroll (to DC012 scroll latch). Zeroed on width change
scroll_scan	equ	205ah
; scroll direction, as initialised to 01h but could be 99h (=-1 daa)
scroll_dir	equ	205bh
; Buffer where cursor and function keys are prepared for sending to host
; offset into buffer is curkey_qcount
curkey_queue	equ	205ch ; 10 locs
; updated in vertical int, non-zero seems to hold up width change (fast loop, so must be waiting
; on vertical int to update it) Perhaps scroll to finish?
smooth_scroll	equ	2065h
UNUSED_X2066	equ	2066h
; scan code of the latest new key seen in silo
new_key_scan	equ	2067h
; key_flags low 3 bits are number of keys waiting to be processed, which
; can only be up to 4.
; Bits 4-7 are the "shift" key flags, which get processed by the interrupt
; routine instead of being buffered.
;
;	   7     6     5     4     3     2     1     0
;	+-----+-----+-----+-----+-----+-----+-----+-----+
;	|EOS  |CAPS |SHIFT|CTRL |     | OVR key count   |
;	+-----+-----+-----+-----+-----+-----+-----+-----+
;
key_flags	equ	2068h
key_flag_ctrl	equ	10h
key_flag_shift	equ	20h
key_flag_caps	equ	40h
key_flag_eos	equ	80h
; last_key_flags are updated at the end of the keyboard processing
last_key_flags	equ	2069h
; Space for 4 keys pending processing 206ah to 206dh. TM says "SILO" throughout
key_silo	equ 	206ah ; 4 locs
; Buffer for previous keys which we'll attempt to match with silo
key_history	equ	206eh ; 4 locs
key_rpt_timer	equ	2072h
; used while processing keys - initialised to 2 and decremented
key_rpt_pause	equ	2073h
; incremented every time we send byte to keyboard
num_kbd_updates	equ	2074h
; storing a line address, possibly also to do with shuffle
shufad1		equ	2075h
; Confirmed unwritten by tests. Reading non-zero causes premature exit from update_kbd
UNWRIT_X2077	equ	2077h
; C0 BEL and margin bell add to this location, and it is processed in vertical interrupt with other keyboard bits
bell_duration	equ	2078h
;
; At start-up, GPO presence is read from the I/O flags buffer and sets bit 0 of these flags.
; Bit 7 is set if we are currently passing characters to the GPO, between DECGON and DECGOFF.
; No other bits are used.
gpo_flags	equ	2079h
; tested and cleared during vert. int.
; shuffle cannot happen until this is nonzero. made nonzero when extra line is connected
shuffle_ready	equ	207ah
; checked in proc_func_key
; 0ffh = in setup, 0 = not in setup
in_setup	equ	207bh
; refresh_rate is 20h for 60Hz, 30h for 50Hz
refresh_rate	equ	207ch
refresh_60Hz	equ	20h
refresh_50Hz	equ	30h
inter_chars	equ	207dh	; intermediate chars are added together in this byte
final_char	equ	207eh	; final character of ESC or CSI sequence
; Count of vertical interrupts, at 60 Hz, used for timing BREAK and synchronising switch to SET-UP screen
frame_count	equ 	207fh
; Received characters go into this buffer, at the location 2000h + rx_head,
; and they are pulled out from 2000h + rx_tail. Both rx_head and rx_tail are
; initialised to 80h, and when they increment past 0bfh, that's where they
; wrap back to, so the buffer is 64 characters long.
rx_buffer	equ	2080h
; initialised to 80h, seems to be where next received character is placed,
; and will run up to 0bfh, then wrap back to 80h
; Receiver int
rx_head		equ	20c0h
rx_tail		equ	20c1h
; 20c2 is a table of 25 (including pline_extra) addresses of physical lines in the screen RAM.
; X20de is because it is the address of row 14 (0-based), so for a 14 line
; display it is the line beyond the last on the screen. Looking at the code
; around X117e, pline_extra seems to have a similar function.
pline_addr	equ	20c2h ; 28 locs
; address of last line in screen ram?
pline_extra	equ	20f2h
; move_updates seems to place this where cursor *was*
char_und_curs	equ	20f4h
rend_und_curs	equ	20f5h
; Must be cursor address in screen RAM
cursor_address	equ	20f6h
; The graphics state that DECSC saves, and DECRC restores, is stored from 20f8h to 2101h.
; Not all of these bytes have been decoded yet.
gfx_state	equ	20f8h	; live graphics state (cursor position, SGR, etc.)
curs_col	equ	20f8h	; first location of state seems to be X (column)
curs_row	equ	20f9h	; this is absolute cursor row (regardless of origin mode)
; Default rendition is 0f7h (_see_ sgr_off)
; blink      masks with 0feh (11111110b)
; underscore masks with 0fdh (11111101b)
; bold       masks with 0fbh (11111011b)
char_rend	equ	20fah
rend_blink	equ	0feh
rend_under	equ	0fdh
rend_bold	equ	0fbh
; reverse video is treated differently, with normal video being
; 0 and reverse video setting this to 80h.
char_rvid	equ	20fbh
gl_invocation	equ	20fch	; 0 or 1, depending on whether G0 or G1 is invoked into GL
g0_charset	equ	20fdh
g1_charset	equ	20feh
g2_charset	equ	20ffh	; can't designate a charset into G2 or G3 but they are initialised
g3_charset	equ	2100h	; with the same defaults as G0 and G1
; origin mode DECOM 1/0
origin_mode	equ	2101h

gfx_saved	equ	2102h	; saved graphics state
saved_rend	equ	2104h	; saved char_rend
; enter_setup stores curs_col and curs_row here
saved_curs_col	equ	210dh
; initialised to 0ffh at startup. Something to do with margins, but looks more like a flag than value
; Seems to be very commonly invalidated by storing 0ffh (many places) and 0f0h (one place)
saved_curs_row	equ	210eh
UNUSED_X210f	equ	210fh
UNUSED_X2110	equ	2110h
; When we enter SET-UP, the previous action for received characters, char_action, is
; saved here.
saved_action	equ	2111h
;
; Detailed in TM §4.7.3.2, p. 4-92
; Each entry in this array contains the number of a line on the physical screen. What the TM
; doesn't say is that bit 7 might be set on the physical line number; this means that the line
; is double width, which in turn means that a second set of terminating bytes have been placed
; half-way across the line.
;
; LATOFS runs from 2113h (row 0) to 212a (row 23). I don't yet know whether X212b is related,
; as perhaps being the physical number of the 25th line.
latofs		equ	2113h
; Bottom row number + 1 is written in latofs_last, even for 14-line screens
latofs_last	equ	212bh
; Counts down from 35h, toggles blink flip-flop every time it reaches zero
blink_timer	equ	212ch
; 16-bit counts down in update_kbd and then flips cursor visibility
cursor_timer	equ	212dh
param_value	equ	212fh ; current CSI parameter value we're collecting

; TWO names for same location here. csi_params is used to refer to the array, when the
; code is going to iterate over params and the name csi_p1 is used when we're explicitly
; looking for the first parameter.
csi_params	equ	2130h ; list of 16 params for CSI sequence
csi_p1		equ	2130h ; parameter p1 is start of array
csi_p2		equ	2131h
; None of these names for further parameters are used in the source because there are no
; sequences on a VT100 with more than two fixed parameters. All other sequences have
; selection parameters, and they are addressed by iterating over the array as a whole.
; Nevertheless, the presence of names in the symbol table aids debugging.
csi_p3		equ	2132h
csi_p4		equ	2133h
csi_p5		equ	2134h
csi_p6		equ	2135h
csi_p7		equ	2136h
csi_p8		equ	2137h
csi_p9		equ	2138h
csi_p10		equ	2139h
csi_p11		equ	213ah
csi_p12		equ	213bh
csi_p13		equ	213ch
csi_p14		equ	213dh
csi_p15		equ	213eh
; The 16th numeric parameter is here for convenience of processing. It can be written
; to, but it is never used during execution of a control sequence.
csi_p16		equ	213fh
;
char_action	equ	2140h ; address of routine used to process next incoming character
; If we write to location on right-hand edge of screen and auto-wrap is on,
; need for a wrap on the next write is recorded here. Always cleared after
; a non-edge character is written.
pending_wrap	equ	2142h
; used in send_key_byte to hold offset into curkey_queue
curkey_qcount	equ	2143h
keyboard_locked	equ	2144h
; Supposed to be a mask for four bits (0-3, here) that are masked with other
; bytes to form an instruction for the keyword. However, a bug (_see_ decll_action)
; means that this byte can have bits 4-7 set, causing interference with the
; keyboard, and they cannot be then unset without resetting the terminal.
;
;	   7     6     5     4     3     2     1     0
;	+-----+-----+-----+-----+-----+-----+-----+-----+
;	|     |     |     |     |L1 on|L2 on|L3 on|L4 on|
;	+-----+-----+-----+-----+-----+-----+-----+-----+
led_state	equ	2145h
; online/local mask for keyboard (directly ORed with led_state)
kbd_online_mask	equ	2146h
; spkr./click mask (directly ORed with led_state)
kbd_click_mask	equ	2147h
kbd_scan_mask	equ	2148h
; Never see this being read, or jumped through but looks like address location
; I believe this always contains 07ffh. Confirmed by tests.
UNREAD_X2149	equ	2149h
UNREAD_X214a	equ	214ah
num_params	equ	214bh	; offset into params array of the current param
UNUSED_X214c	equ	214ch
UNUSED_X214d	equ	214dh
;
; Start of the cursor line in video RAM
start_line_addr	equ	214eh
; a key scan code - checked when processing auto repeat
latest_key_scan	equ	2150h
; This flag is only cleared when a column has been received, rather than when ESC Y has been
; recognised, which means that intervening C0 controls won't affect the very next printable
; characters from being recognised as a row or column.
got_vt52_row	equ	2151h
vt52_row_coord	equ	2152h
;
; Internal column number of right margin of the current line.
; This will be 79 or 131 for single-width lines. One of the jobs of _see_ move_updates
; is to halve this for double-width lines.
;
right_margin	equ	2153h
;
; Set up if a margin bell is required. Stealth read at 1696h.
margin_bell	equ	2154h
top_margin	equ	2155h
bottom_margin	equ	2156h
; Gets 80h double-width marker if appropriate, or 0 for single line
curr_line_dbl	equ	2157h
; This tx_spd and rx_spd combined to make a single byte, sent to iow_baud_rate
tx_rx_speed	equ	2158h
;
; Next two locations control how the cursor is going to work, either by changing the
; base attribute in the video RAM for each character, which is what must happen without
; AVO present, or by changing attribute RAM, when AVO is present. Cursor setup records
; both options in these locations, which get XORed with video RAM and attribute RAM,
; respectively.
;
; without AVO, this is 80h, so toggles between normal and reverse video (or underline)
curs_char_rend	equ	2159h
; 0 for underline cursor, 2 for block
curs_attr_rend	equ	215ah
; 0 = basic attribute is underline, 1 = basic attribute is reverse video
basic_rev_video	equ	215bh
; Reports to be sent out from the terminal are built in this buffer.
; Longest report is DECREPTPARM, which can reach 21 characters, making
; this buffer extend from 215ch to 2170h.
; DECREPTPARM: ESC [ 2 ; 1 ; 1 ; 120 ; 120 ; 1 ; 15 c
report_buffer	equ	215ch
; Offset into report_buffer of the character to be sent next
rep_send_offset	equ	2171h

; When a sequence is received that requires a response, the need for a response is placed in
; location pending_report, and then dealt with later, as part of the periodic keyboard
; tick routine.
;
; pend_<x> are the individual bit flags to say what needs reporting
pending_report	equ	2172h
pend_curpos	equ	01h ; DSR 6 (cursor position) has been requested
pend_tparm	equ	02h ; DECREQTPARM has been received
pend_ident	equ	04h ; DECID has been received
pend_devstat	equ	08h ; DSR 5 (device status) has been requested
pend_aback	equ	10h ; Answerback has been triggered
pend_key	equ	20h ; Keys to host (single or multi-byte)

; When a report has been prepared and send_report has been called, this goes to 1,
; then back to zero when last character of report has been grabbed from buffer
sending_report	equ	2173h
;
; Used to hold the address of a routine that will produce a report, then holds
; the address of the routine that pumps them out, which is cont_report for all
; reports other than cursor keys, because they are prepared in advance, one at
; a time, but several cursor key reports can be buffered.
report_action	equ	2174h

; Flag whether DECREPTPARM can be sent unsolicited (i.e. whenever SET-UP is exited),
; or only on request. This is controlled by the parameter sent with DECREQTPARM,
; so this flag will be 0 = unsolicited reports allowed, 1 = solicited only
; Status on reset will be 1, i.e. no unsolicited reports
tparm_solicited	equ	2176h
; When SETUP is detected in keyboard processing, this flag is set to indicate that
; SET-UP should be entered.
pending_setup	equ	2177h
; keypad_mode: 0 = numeric, 1 = application
keypad_mode     equ	2178h
; For line shuffling
shufdt1		equ	2179h
; TM §4.7.11 details SET-UP scratch RAM (saying it is subject to change.)
; It confirms that the first area here is the answerback message, 22 bytes, with 20 characters and 2 delimiters.
aback_buffer	equ	217bh
aback_bufend	equ	2190h
; 132/8 = 16.5 bytes, so tab buffer is 17 bytes, 2191h to 21a1h
tab_settings	equ	2191h
tablen		equ	17 ; bytes in tab settings area
; 1 = 132 columns, 0 = 80 columns
columns_132	equ	21a2h
; brightest = 0, dimmest = 1fh
brightness	equ	21a3h
; pusart_mode, based on TM §4.7.11
pusart_mode	equ	21a4h
;
; local_mode flag is ORed into the keyboard byte in order to set the Local LED,
; so the value 20h is used as "local". Data loopback test will indicate failure
; by placing 25h, in order to briefly light LEDs L2 and L4 - these then get removed
; by after_tests.
local_mode	equ	21a5h
;	21a6: SET-UP B block 1
;
;	   7     6     5     4     3     2     1     0
;	+-----+-----+-----+-----+-----+-----+-----+-----+
;	|     |     |     |     |     |     |     |     |
;	+-----+-----+-----+-----+-----+-----+-----+-----+
;	   |     |     |     `-- 1 = cursor block, 0 = cursor underline
;	   |     |     `-- 1 = light background, 0 = dark background
;	   |     `-- 1 = autorepeat on, 0 = autorepeat off
;          `-- 1 = smooth scroll, 0 = jump scroll
;
setup_b1	equ	21a6h
sb1_curblock	equ	10h
sb1_lightback	equ	20h
sb1_autorep	equ	40h
sb1_smooth	equ	80h
;
;	21a7: SET-UP B block 2
;
;	   7     6     5     4     3     2     1     0
;	+-----+-----+-----+-----+-----+-----+-----+-----+
;	|     |     |     |     |     |     |     |     |
;	+-----+-----+-----+-----+-----+-----+-----+-----+
;	   |     |     |     `-- 1 = auto xon/xoff, 0 = no auto xon/off
;	   |     |     `-- 1 = ANSI mode, 0 = VT52 (_see_ ansi_mode)
;          |     `-- 1 = keyclick on, 0 = keyclick off
;          `-- 1 = margin bell on, 0 = margin bell off
;
setup_b2	equ	21a7h
sb2_autoxon	equ	10h
sb2_ansi	equ	20h
sb2_keyclick	equ	40h
sb2_marginbell	equ	80h

;	21a8: SET-UP B block 3
;
;	   7     6     5     4     3     2     1     0
;	+-----+-----+-----+-----+-----+-----+-----+-----+
;	|     |     |     |     |     |     |     |     |
;	+-----+-----+-----+-----+-----+-----+-----+-----+
;	   |     |     |     `-- 1 = interlace on, 0 = interlace off (_see_ decinlm_mode)
;	   |     |     `-- 1 = ?, 0 = ?
;          |     `-- 1 = autowrap, 0 = no autowrap (_see_ decawm_mode)
;          `-- 1 = UK, 0 = ASCII
setup_b3	equ	21a8h
sb3_interlace	equ	10h
sb3_newline	equ	20h
sb3_autowrap	equ	40h
sb3_uk		equ	80h

;	21a9: SET-UP B block 4
;
;	   7     6     5     4     3     2     1     0
;	+-----+-----+-----+-----+-----+-----+-----+-----+
;	|     |     |     |     |     |     |     |     |
;	+-----+-----+-----+-----+-----+-----+-----+-----+
;	   |     |     |     `-- 1 - power 50 Hz, 0 = power 60 Hz
;	   |     |     `-- bits/char: 1 = 8 bits, 0 = 7 bits
;          |     `-- 1 = parity on, 0 = parity off
;          `-- 1 = even parity, 0 = odd parity
setup_b4	equ	21a9h
sb4_50Hz	equ	10h
sb4_8bits	equ	20h
sb4_parityon	equ	40h
sb4_evenparity	equ	80h
sb4_paritybits	equ	(sb4_parityon|sb4_evenparity)
;
setup_b5	equ	21aah ; only visible with STP option installed
tx_spd		equ	21abh ; encoded transmit speed in high 4 bits
rx_spd		equ	21ach ; encoded receive speed in high 4 bits
nvr_checksum	equ	21adh
;
nvr_addr	equ	21aeh
nvr_data	equ	21afh ; 2 locs
UNUSED_X21b1	equ	21b1h
UNUSED_X21b2	equ	21b2h
UNUSED_X21b3	equ	21b3h
answerback_ptr	equ	21b4h
UNUSED_X21b6	equ	21b6h
UNUSED_X21b7	equ	21b7h
csi_private	equ	21b8h ; CSI sequence private character is stored here
found_action	equ	21b9h
; initialised to 0ffh at startup
cursor_visible	equ	21bah
; updated post cursor move, used for margin bell calculations because it matters whether
; we got to the current column by typing or cursor positioning sequences.
last_curs_col	equ	21bbh
mode_ckm	equ	21bch
; POST results go here
test_results	equ	21bdh
; in_setup_a is 1 for SET-UP A, 0 for SET-UP B.
in_setup_a	equ	21beh
;
; If the host is allowed to send characters (receive buffer has enough space,
; user has pressed Ctrl/Q, we've come out of SETUP, etc.) then this will be zero,
; and an XON will probably have been sent. Otherwise, this records why the host has
; been told to stop, as a bit mask. 01h means the receive buffer is getting full,
; and 02h means the user has pressed NO SCROLL or Ctrl/S.
; 03h means the receive buffer was already getting full, and the user also panicked
; and hit NO SCROLL!
;
why_xoff	equ	21bfh
; XON/XOFF character to transmit is pulled from here, as long as 21c1h is not zero
tx_xo_char	equ	21c0h
tx_xo_flag	equ	21c1h
; Contents of this ANDed with 0feh if we've received XON, ORed with 1 if we've received XOFF
received_xoff	equ	21c2h
; gets zeroed by clear_part_row
; flag marked when smooth scroll and need to clear extra line, so non-interrupt path
; sets this flag and then waits until the clearance happens in vertical interrupt and
; the flag gets zeroed.
row_clearing	equ	21c3h
; no_scroll_key stores 2 (sent XOFF) or 0 (sent XON) here
noscroll	equ	21c4h
; When we enter SET-UP mode, we save the previous video pointer here
saved_line1_dma	equ	21c5h
; This is zero, except for alignment display, which makes it 'E' (and then zeroes again)
cls_char	equ	21c7h
; Recorded early in start-up. Non zero if no AVO found
avo_missing	equ	21c8h
; gets sent to iow_nvr_latch during vertical int
; Vertical interrupt outputs to the NVR latch, so any code that is writing to the latch while
; interrupts are still enabled also stores the value here, so it persists.
vint_nvr	equ	21c9h
UNUSED_X21ca	equ	21cah
; updated when blink timer goes off in vertical interrupt
; repeat test field
; If DECTST has requested some tests to be repeatedly executed and they fail, the screen field
; is toggled between normal and reverse on each cycle. This can be seen by sending the sequence
; ESC [ 2 ; 10 y (data loopback with repeat). Data loopback will always fail in the absence of
; a loopback connector, so the screen will show "8" for failure in the first character position,
; and the entire screen will blink between normal and reverse field.
;
test_field	equ	21cbh
; This area holds the mini screen definition for "Wait", with terminators that
; point back to the fill lines. The entire screen definition is just 7 bytes long.
wait_addr	equ	21cch
; wait screen address in DMA (big-endian) form, with normal line attributes
wait_addr_be	equ	0cc71h
nvr_bits	equ	21d3h ; must be at least 14 locations
; setup_video is where the SET-UP characters are drawn, and then the Video DMA is switched
; to point to here while we are in this mode.
setup_video	equ	2253h
;
; Normal screen display starts here in scratch RAM, and line1_dma gets initialised to point to it.
; screen_layout (the initial 18 bytes of definition) point here literally, and any other time
; we want to get back to this location, main_video_be will be loaded into HL and then
; written to line1_dma. This establishes the first line as part of the scrolling region,
; with normal lines attributes.
;
main_video	equ	22d0h
main_video_be	equ	0d0f2h
;
		end
;
; vim: set ts=8 noet :
