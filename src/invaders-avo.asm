;
; Space Invaders AVO ROM image.
;
; This source is assembled separately from the base VT100 CPU ROM. The entry
; points live at fixed addresses so the modified base ROM can call into the AVO
; payload without a linker.
;
	include	"invaders-abi.asm"

	org	inv_enter
	jmp	inv_enter_impl
	org	inv_idle
	jmp	inv_idle_impl
	org	inv_exit
	jmp	inv_exit_impl

inv_enter_impl:	ret
inv_idle_impl:	ret
inv_exit_impl:	ret

; Emit a full 8 KiB program expansion ROM image for MAME.
	org	inv_avo_base+1fffh
	db	0

	end
