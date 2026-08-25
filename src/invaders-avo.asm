;
; Space Invaders AVO ROM image.
;
; This source is assembled separately from the base VT100 CPU ROM. The entry
; points live at fixed addresses so the modified base ROM can call into the AVO
; payload without a linker.
;
        include "invaders-base.inc"

        org     inv_enter
        jmp     inv_enter_impl
        org     inv_idle
        jmp     inv_idle_impl
        org     inv_exit
        jmp     inv_exit_impl
        org     inv_idle_hook
        jmp     inv_idle_hook_impl
        org     inv_setup_keys_hook
        jmp     inv_setup_keys_hook_impl

inv_enter_impl:
        call    inv_prepare_screen
        call    inv_save_leds
        xra     a
        sta     inv_frame_lo
        sta     inv_frame_hi
        sta     inv_left_pressed
        sta     inv_right_pressed
        sta     inv_fire_pressed
        sta     inv_score0
        sta     inv_score1
        sta     inv_score2
        sta     inv_game_over
        sta     inv_test_result
        mvi     a,inv_initial_gunners
        sta     inv_gunners
        mvi     a,inv_initial_level
        sta     inv_level
        mvi     a,inv_turret_start_x_lo
        sta     inv_turret_x_lo
        mvi     a,inv_turret_start_x_hi
        sta     inv_turret_x_hi
        call    inv_reset_shields
        call    inv_draw_static_screen
        lda     frame_count
        sta     inv_last_vframe
        mvi     a,0ffh
        sta     inv_active
        ret
;
inv_idle_impl:
        call    update_kbd
        call    inv_read_keys
        lda     inv_active
        ora     a
        rz
        call    inv_wait_frame
        call    inv_frame
        ret
;
inv_read_keys:
        xra     a
        sta     inv_left_pressed
        sta     inv_right_pressed
        sta     inv_fire_pressed
        lda     key_flags
        ani     7
        rz
        mov     b,a
        lxi     h,key_silo
inv_check_keys:
        mov     a,m
        cpi     7bh             ; SET-UP exits the game
        jz      inv_setup_pressed
        inx     h
        dcr     b
        jnz     inv_check_keys
        jmp     clear_keyboard
;
inv_setup_pressed:
        call    inv_exit
        jmp     clear_keyboard
;
inv_wait_frame:
        lda     frame_count
        lxi     h,inv_last_vframe
        cmp     m
        jz      inv_wait_frame
        mov     m,a
        call    inv_inc_frame16
        ret
;
inv_inc_frame16:
        lxi     h,inv_frame_lo
        inr     m
        rnz
        inx     h
        inr     m
        ret
;
inv_frame:
        call    inv_test_tick
        ret
;
inv_prepare_screen:
        xra     a
        sta     columns_132
        sta     scroll_pending
        sta     smooth_scroll
        mvi     c,inv_screen_cols
        call    make_screen
        call    make_line_t
        mvi     a,inv_screen_cols
        sta     screen_cols
        call    update_dc011
        ret
;
inv_save_leds:
        lda     led_state
        ani     0fh
        sta     inv_saved_led_state
        ret
;
inv_restore_leds:
        lda     led_state
        ani     0f0h
        mov     b,a
        lda     inv_saved_led_state
        ani     0fh
        ora     b
        sta     led_state
        ret
;
inv_led_for_gunners:
        ora     a
        rz
        cpi     1
        jz      inv_led_one
        cpi     2
        jz      inv_led_two
        cpi     3
        jz      inv_led_three
        mvi     a,0fh
        ret
inv_led_one:
        mvi     a,01h
        ret
inv_led_two:
        mvi     a,03h
        ret
inv_led_three:
        mvi     a,07h
        ret
;
inv_update_gunner_leds:
        lda     inv_gunners
        call    inv_led_for_gunners
        mov     b,a
        lda     led_state
        ani     0f0h
        ora     b
        sta     led_state
        ret
;
; Return HL pointing at the screen cell for row B and column C.
;
inv_cell_addr:
        mov     a,b
        add     a
        lxi     h,inv_row_addr
        call    add_a_to_hl
        mov     e,m
        inx     h
        mov     d,m
        xchg
        mvi     b,0
        dad     b
        ret
;
; Write already-mapped glyph A at row B, column C.
;
inv_putc:
        mov     e,a
        mov     a,b
        cpi     inv_screen_rows
        rnc
        mov     a,c
        cpi     inv_screen_cols
        rnc
        push    d
        call    inv_cell_addr
        pop     d
        mov     m,e
        ret
;
; Write zero-terminated already-mapped glyph bytes from HL.
;
inv_puts_glyphs:
        mov     a,m
        ora     a
        rz
        push    h
        push    b
        call    inv_putc
        pop     b
        pop     h
        inx     h
        inr     c
        jmp     inv_puts_glyphs
;
; Write zero-terminated DEC Special Graphics source bytes from HL.
;
inv_puts_sg:
        mov     a,m
        ora     a
        rz
        cpi     inv_sg_source_base
        jc      inv_puts_sg_emit
        cpi     inv_sg_source_limit
        jnc     inv_puts_sg_emit
        sui     inv_sg_source_base
inv_puts_sg_emit:
        push    h
        push    b
        call    inv_putc
        pop     b
        pop     h
        inx     h
        inr     c
        jmp     inv_puts_sg
;
inv_cell_code_to_glyph:
        ani     0fh
        lxi     h,inv_cell_glyphs
        call    add_a_to_hl
        mov     a,m
        ret
;
inv_put_cell_row:
        mov     a,m
        push    h
        call    inv_cell_code_to_glyph
        push    b
        push    d
        call    inv_putc
        pop     d
        pop     b
        pop     h
        inx     h
        inr     c
        dcr     e
        jnz     inv_put_cell_row
        ret
;
inv_draw_shield:
        mvi     d,inv_shield_h
inv_draw_shield_row:
        push    d
        push    b
        mvi     e,inv_shield_w
        call    inv_put_cell_row
        pop     b
        pop     d
        inr     b
        dcr     d
        jnz     inv_draw_shield_row
        ret
;
inv_reset_shields:
        lxi     d,inv_shield_cells_base
        mvi     b,inv_shield_count
inv_reset_shield:
        lxi     h,inv_initial_shield_cells
        mvi     c,inv_shield_cells_each
inv_reset_shield_cell:
        mov     a,m
        stax    d
        inx     h
        inx     d
        dcr     c
        jnz     inv_reset_shield_cell
        dcr     b
        jnz     inv_reset_shield
        ret
;
inv_draw_shields:
        lxi     h,inv_shield_cells_base
        mvi     b,inv_shield_top_row
        mvi     c,inv_shield0_x
        call    inv_draw_shield
        mvi     b,inv_shield_top_row
        mvi     c,inv_shield1_x
        call    inv_draw_shield
        mvi     b,inv_shield_top_row
        mvi     c,inv_shield2_x
        call    inv_draw_shield
        mvi     b,inv_shield_top_row
        mvi     c,inv_shield3_x
        call    inv_draw_shield
        ret
;
inv_draw_status:
        mvi     b,inv_score_row
        mvi     c,0
        lxi     h,inv_status_text
        jmp     inv_puts_glyphs
;
inv_draw_ground:
        mvi     b,inv_ground_row
        mvi     c,inv_play_left
        lxi     h,inv_ground_line
        jmp     inv_puts_sg
;
inv_draw_turret:
        mvi     b,inv_turret_top_row
        mvi     c,inv_turret_start_x
        lxi     h,inv_turret_top
        call    inv_puts_sg
        mvi     b,inv_turret_top_row+1
        mvi     c,inv_turret_start_x
        lxi     h,inv_turret_bottom
        jmp     inv_puts_sg
;
inv_draw_static_screen:
        call    inv_clear_playfield
        call    inv_draw_status
        call    inv_draw_ground
        call    inv_draw_shields
        call    inv_draw_turret
        call    inv_update_gunner_leds
        ret
;
inv_clear_playfield:
        lxi     h,inv_row_addr
        mvi     b,inv_screen_rows
inv_clear_row:
        mov     e,m
        inx     h
        mov     d,m
        inx     h
        push    h
        xchg
        mvi     c,inv_screen_cols
        xra     a
inv_clear_col:
        mov     m,a
        inx     h
        dcr     c
        jnz     inv_clear_col
        pop     h
        dcr     b
        jnz     inv_clear_row
        ret
;
inv_test_render_probe:
        call    inv_clear_playfield
        mvi     b,0
        mvi     c,0
        lxi     h,inv_render_text
        call    inv_puts_glyphs
        mvi     b,1
        mvi     c,78
        lxi     h,inv_render_edge
        call    inv_puts_glyphs
        mvi     b,2
        mvi     c,4
        lxi     h,inv_render_sg_line
        call    inv_puts_sg
        mvi     b,3
        mvi     c,10
        lxi     h,inv_render_sg_blank
        call    inv_puts_sg
        mvi     b,23
        mvi     c,79
        mvi     a,'!'
        call    inv_putc
        mvi     b,24
        mvi     c,0
        mvi     a,'B'
        call    inv_putc
        mvi     b,0
        mvi     c,80
        mvi     a,'C'
        call    inv_putc
        mvi     a,inv_pass
        sta     inv_test_result
        xra     a
        sta     inv_active
        ret
;
inv_test_tick:
        lda     inv_test_mode
        ora     a
        rz
        lda     inv_test_script
        ora     a
        jz      inv_test_frame_stop
        cpi     inv_test_script_render
        jz      inv_test_render_probe
        jmp     inv_test_bad_script
inv_test_frame_stop:
        lda     inv_test_stop_lo
        lxi     h,inv_test_stop_hi
        ora     m
        rz
        lda     inv_frame_hi
        cmp     m
        rnz
        lda     inv_frame_lo
        lxi     h,inv_test_stop_lo
        cmp     m
        rnz
        mvi     a,inv_pass
        sta     inv_test_result
        xra     a
        sta     inv_active
        ret
;
inv_test_bad_script:
        mvi     a,inv_fail_bad_state
        sta     inv_test_result
        xra     a
        sta     inv_active
        ret
;
inv_row_addr:
        dw      main_video+(inv_row_stride*0)
        dw      main_video+(inv_row_stride*1)
        dw      main_video+(inv_row_stride*2)
        dw      main_video+(inv_row_stride*3)
        dw      main_video+(inv_row_stride*4)
        dw      main_video+(inv_row_stride*5)
        dw      main_video+(inv_row_stride*6)
        dw      main_video+(inv_row_stride*7)
        dw      main_video+(inv_row_stride*8)
        dw      main_video+(inv_row_stride*9)
        dw      main_video+(inv_row_stride*10)
        dw      main_video+(inv_row_stride*11)
        dw      main_video+(inv_row_stride*12)
        dw      main_video+(inv_row_stride*13)
        dw      main_video+(inv_row_stride*14)
        dw      main_video+(inv_row_stride*15)
        dw      main_video+(inv_row_stride*16)
        dw      main_video+(inv_row_stride*17)
        dw      main_video+(inv_row_stride*18)
        dw      main_video+(inv_row_stride*19)
        dw      main_video+(inv_row_stride*20)
        dw      main_video+(inv_row_stride*21)
        dw      main_video+(inv_row_stride*22)
        dw      main_video+(inv_row_stride*23)
;
inv_render_text:
        db      'R','O','M',0
inv_render_edge:
        db      'X','Y','Z',0
inv_render_sg_line:
        db      'l','q','k',0
inv_render_sg_blank:
        db      '_','a','~',0
;
inv_cell_glyphs:
        db      00h,02h,0dh,0ch,0eh,0bh,12h
        db      00h,00h,00h,00h,00h,00h,00h,00h,00h
;
inv_initial_shield_cells:
        db      inv_cell_blank,inv_cell_upper_left,inv_cell_hline
        db      inv_cell_hline,inv_cell_hline,inv_cell_upper_right
        db      inv_cell_blank
        db      inv_cell_upper_left,inv_cell_checker,inv_cell_checker
        db      inv_cell_checker,inv_cell_checker,inv_cell_checker
        db      inv_cell_upper_right
        db      inv_cell_checker,inv_cell_checker,inv_cell_checker
        db      inv_cell_blank,inv_cell_checker,inv_cell_checker
        db      inv_cell_checker
;
inv_status_text:
        db      'S','C','O','R','E',' ','0','0','0','0',' '
        db      ' ','L','E','V','E','L',' ','1',0
inv_ground_line:
        db      'q','q','q','q','q','q','q','q','q','q'
        db      'q','q','q','q','q','q','q','q','q','q'
        db      'q','q','q','q','q','q','q','q','q','q'
        db      'q','q','q','q','q','q','q','q','q','q'
        db      'q','q','q','q','q','q','q','q','q','q'
        db      'q','q','q','q','q','q','q','q','q','q'
        db      0
inv_turret_top:
        db      '_','_','_','a','_','_','_',0
inv_turret_bottom:
        db      '_','a','a','a','a','a','_',0
;
inv_exit_impl:
        xra     a
        sta     inv_active
        call    inv_restore_leds
        ret
;
; Replaces the idle-loop call to keyboard_tick in the Invaders base ROM.
; When the game is inactive, repeat the displaced call and return to the
; following base-ROM instruction.
;
inv_idle_hook_impl:
        lda     inv_active
        ora     a
        jnz     inv_idle_active
        call    keyboard_tick
        ret
;
inv_idle_active:
        call    inv_idle
        pop     h               ; discard return to the terminal idle path
        jmp     idle_loop
;
; Replaces "mov a,b / cpi 'S'" in setup_keys. Non-Invaders SET-UP keys leave
; flags exactly as the displaced comparison would have left them.
;
inv_setup_keys_hook_impl:
        mov     a,b
        cpi     'I'             ; SHIFT I starts Space Invaders
        jz      inv_setup_start
        mov     a,b
        cpi     'S'             ; repeat the displaced comparison
        ret
;
inv_setup_start:
        pop     h               ; discard return to setup_keys
        pop     h               ; discard setup_ready return address
        xra     a
        sta     in_setup
        call    inv_leave_setup_for_game
        jmp     inv_enter
;
inv_leave_setup_for_game:
        lhld    saved_action
        shld    char_action
        call    extra_addr
        lxi     d,1000h
        dad     d
        lda     screen_cols
inv_restore_attr:
        mvi     m,0ffh
        inx     h
        dcr     a
        jnz     inv_restore_attr
        lxi     h,saved_curs_col
        mov     a,m
        sta     curs_col
        mvi     a,0ffh
        inx     h
        mov     m,a
        call    move_updates
        lhld    saved_line1_dma
        shld    line1_dma
        xra     a
        sta     noscroll
        sta     received_xoff
        ret

; Emit a full 8 KiB program expansion ROM image for MAME.
        org     inv_avo_base+1fffh
        db      0

        end
