;
; Space Invaders AVO ROM image.
;
; This source is assembled separately from the base VT100 CPU ROM. The entry
; points live at fixed addresses so the modified base ROM can call into the AVO
; payload without a linker.
;
	include	"invaders-base.inc"

	org	inv_enter
	jmp	inv_enter_impl
	org	inv_idle
	jmp	inv_idle_impl
	org	inv_exit
	jmp	inv_exit_impl
	org	inv_idle_hook
	jmp	inv_idle_hook_impl
	org	inv_setup_keys_hook
	jmp	inv_setup_keys_hook_impl

inv_enter_impl:	mvi	a,0ffh
		sta	inv_active
		ret
;
inv_idle_impl:	call	update_kbd
		lda	key_flags
		ani	7
		rz
		mov	b,a
		lxi	h,key_silo
inv_check_keys:	mov	a,m
		cpi	7bh		; SET-UP exits the game
		jz	inv_setup_pressed
		inx	h
		dcr	b
		jnz	inv_check_keys
		jmp	clear_keyboard
;
inv_setup_pressed:
		call	inv_exit
		jmp	clear_keyboard
;
inv_exit_impl:	xra	a
		sta	inv_active
		ret
;
; Replaces the idle-loop call to keyboard_tick in the Invaders base ROM.
; When the game is inactive, repeat the displaced call and return to the
; following base-ROM instruction.
;
inv_idle_hook_impl:
		lda	inv_active
		ora	a
		jnz	inv_idle_active
		call	keyboard_tick
		ret
;
inv_idle_active:
		call	inv_idle
		pop	h		; discard return to the terminal idle path
		jmp	idle_loop
;
; Replaces "mov a,b / cpi 'S'" in setup_keys. Non-Invaders SET-UP keys leave
; flags exactly as the displaced comparison would have left them.
;
inv_setup_keys_hook_impl:
		mov	a,b
		cpi	'I'		; SHIFT I starts Space Invaders
		jz	inv_setup_start
		mov	a,b
		cpi	'S'		; repeat the displaced comparison
		ret
;
inv_setup_start:
		pop	h		; discard return to setup_keys
		pop	h		; discard setup_ready return address
		xra	a
		sta	in_setup
		call	inv_leave_setup_for_game
		jmp	inv_enter
;
inv_leave_setup_for_game:
		lhld	saved_action
		shld	char_action
		call	extra_addr
		lxi	d,1000h
		dad	d
		lda	screen_cols
inv_restore_attr:
		mvi	m,0ffh
		inx	h
		dcr	a
		jnz	inv_restore_attr
		lxi	h,saved_curs_col
		mov	a,m
		sta	curs_col
		mvi	a,0ffh
		inx	h
		mov	m,a
		call	move_updates
		lhld	saved_line1_dma
		shld	line1_dma
		xra	a
		sta	noscroll
		sta	received_xoff
		ret

; Emit a full 8 KiB program expansion ROM image for MAME.
	org	inv_avo_base+1fffh
	db	0

	end
