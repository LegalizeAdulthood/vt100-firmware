;
; Fixed addresses shared by the invaders base ROM and AVO ROM.
;
inv_avo_base	equ	8000h
inv_enter	equ	inv_avo_base+0
inv_idle	equ	inv_avo_base+3
inv_exit	equ	inv_avo_base+6
inv_idle_hook	equ	inv_avo_base+9
inv_setup_keys_hook	equ	inv_avo_base+12
inv_active	equ	3fffh
