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
        sta     inv_laser_active
        sta     inv_laser_row_lo
        sta     inv_laser_row_hi
        sta     inv_laser_col_lo
        sta     inv_laser_col_hi
        sta     inv_laser_timer
        sta     inv_laser_shots_lo
        sta     inv_laser_shots_hi
        mvi     a,inv_initial_gunners
        sta     inv_gunners
        mvi     a,inv_initial_level
        sta     inv_level
        mvi     a,inv_turret_start_x_lo
        sta     inv_turret_x_lo
        mvi     a,inv_turret_start_x_hi
        sta     inv_turret_x_hi
        call    inv_reset_aliens
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
        cpi     inv_scan_setup  ; SET-UP exits the game
        jz      inv_setup_pressed
        cpi     inv_scan_arrow_left
        jz      inv_left_arrow_pressed
        cpi     inv_scan_arrow_right
        jz      inv_right_arrow_pressed
        cpi     inv_scan_space
        jz      inv_space_pressed
inv_next_key:
        inx     h
        dcr     b
        jnz     inv_check_keys
        jmp     clear_keyboard
;
inv_left_arrow_pressed:
        mvi     a,0ffh
        sta     inv_left_pressed
        jmp     inv_next_key
;
inv_right_arrow_pressed:
        mvi     a,0ffh
        sta     inv_right_pressed
        jmp     inv_next_key
;
inv_space_pressed:
        mvi     a,0ffh
        sta     inv_fire_pressed
        jmp     inv_next_key
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
        mov     a,m
        ani     0fh
        mov     m,a
        rnz
        dcx     h
        inr     m
        mov     a,m
        ani     0fh
        mov     m,a
        ret
;
inv_frame:
        call    inv_test_tick
        lda     inv_active
        ora     a
        rz
        call    inv_update_aliens
        call    inv_update_turret
        call    inv_update_laser
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
        call    inv_get_turret_x
        mov     c,a
        jmp     inv_draw_turret_at
;
inv_draw_turret_at:
        push    b
        mvi     b,inv_turret_top_row
        lxi     h,inv_turret_top
        call    inv_puts_sg
        pop     b
        mvi     b,inv_turret_top_row+1
        lxi     h,inv_turret_bottom
        jmp     inv_puts_sg
;
inv_erase_turret_at:
        push    b
        mvi     b,inv_turret_top_row
        mvi     d,inv_turret_w
        mvi     a,12h
        call    inv_fill_cells
        pop     b
        mvi     b,inv_turret_top_row+1
        mvi     d,inv_turret_w
        xra     a
        jmp     inv_fill_cells
;
inv_fill_cells:
        mov     e,a
inv_fill_cell:
        mov     a,e
        push    b
        push    d
        call    inv_putc
        pop     d
        pop     b
        inr     c
        dcr     d
        jnz     inv_fill_cell
        ret
;
inv_get_turret_x:
        lda     inv_turret_x_hi
        ani     0fh
        rlc
        rlc
        rlc
        rlc
        mov     b,a
        lda     inv_turret_x_lo
        ani     0fh
        ora     b
        ret
;
inv_store_turret_x:
        push    psw
        ani     0fh
        sta     inv_turret_x_lo
        pop     psw
        rrc
        rrc
        rrc
        rrc
        ani     0fh
        sta     inv_turret_x_hi
        ret
;
inv_get_laser_row:
        lda     inv_laser_row_hi
        ani     0fh
        rlc
        rlc
        rlc
        rlc
        mov     b,a
        lda     inv_laser_row_lo
        ani     0fh
        ora     b
        ret
;
inv_store_laser_row:
        push    psw
        ani     0fh
        sta     inv_laser_row_lo
        pop     psw
        rrc
        rrc
        rrc
        rrc
        ani     0fh
        sta     inv_laser_row_hi
        ret
;
inv_get_laser_col:
        lda     inv_laser_col_hi
        ani     0fh
        rlc
        rlc
        rlc
        rlc
        mov     b,a
        lda     inv_laser_col_lo
        ani     0fh
        ora     b
        ret
;
inv_store_laser_col:
        push    psw
        ani     0fh
        sta     inv_laser_col_lo
        pop     psw
        rrc
        rrc
        rrc
        rrc
        ani     0fh
        sta     inv_laser_col_hi
        ret
;
inv_inc_laser_shots:
        lxi     h,inv_laser_shots_lo
        inr     m
        mov     a,m
        ani     0fh
        mov     m,a
        rnz
        dcx     h
        inr     m
        mov     a,m
        ani     0fh
        mov     m,a
        ret
;
inv_deactivate_laser:
        xra     a
        sta     inv_laser_active
        sta     inv_laser_timer
        ret
;
inv_erase_laser:
        call    inv_get_laser_col
        mov     c,a
        call    inv_get_laser_row
        mov     b,a
        xra     a
        jmp     inv_putc
;
inv_shield_cell_addr:
        mov     a,b
        cpi     inv_shield_top_row
        jc      inv_no_shield_cell
        sui     inv_shield_top_row
        cpi     inv_shield_h
        jnc     inv_no_shield_cell
        mov     e,a
        mov     a,c
        cpi     inv_shield0_x
        jc      inv_no_shield_cell
        cpi     inv_shield0_x+inv_shield_w
        jc      inv_shield0_cell_addr
        cpi     inv_shield1_x
        jc      inv_no_shield_cell
        cpi     inv_shield1_x+inv_shield_w
        jc      inv_shield1_cell_addr
        cpi     inv_shield2_x
        jc      inv_no_shield_cell
        cpi     inv_shield2_x+inv_shield_w
        jc      inv_shield2_cell_addr
        cpi     inv_shield3_x
        jc      inv_no_shield_cell
        cpi     inv_shield3_x+inv_shield_w
        jnc     inv_no_shield_cell
        lxi     h,inv_shield_cells_base+(inv_shield_cells_each*3)
        mvi     a,inv_shield3_x
        jmp     inv_shield_cell_at
inv_shield2_cell_addr:
        lxi     h,inv_shield_cells_base+(inv_shield_cells_each*2)
        mvi     a,inv_shield2_x
        jmp     inv_shield_cell_at
inv_shield1_cell_addr:
        lxi     h,inv_shield_cells_base+inv_shield_cells_each
        mvi     a,inv_shield1_x
        jmp     inv_shield_cell_at
inv_shield0_cell_addr:
        lxi     h,inv_shield_cells_base
        mvi     a,inv_shield0_x
inv_shield_cell_at:
        mov     d,a
        mov     a,c
        sub     d
        mov     d,a
        mov     a,e
        add     a
        add     a
        add     e
        add     e
        add     e
        add     d
        call    add_a_to_hl
        mov     a,m
        ora     a
        ret
inv_no_shield_cell:
        xra     a
        ret
;
inv_try_shield_collision:
        call    inv_shield_cell_addr
        rz
        mvi     m,inv_cell_blank
        xra     a
        call    inv_putc
        mvi     a,0ffh
        ret
;
inv_place_laser:
        call    inv_try_shield_collision
        ora     a
        jz      inv_draw_laser
        jmp     inv_deactivate_laser
;
inv_draw_laser:
        mvi     a,inv_laser_glyph
        jmp     inv_putc
;
inv_spawn_laser:
        call    inv_get_turret_x
        adi     inv_turret_w/2
        mov     c,a
        mvi     b,inv_laser_start_row
        mvi     a,0ffh
        sta     inv_laser_active
        mvi     a,inv_laser_period
        sta     inv_laser_timer
        mvi     a,inv_laser_start_row
        call    inv_store_laser_row
        mov     a,c
        call    inv_store_laser_col
        call    inv_inc_laser_shots
        jmp     inv_place_laser
;
inv_move_laser:
        mvi     a,inv_laser_period
        sta     inv_laser_timer
        call    inv_erase_laser
        call    inv_get_laser_row
        cpi     inv_laser_top_row
        jz      inv_deactivate_laser
        dcr     a
        push    psw
        call    inv_store_laser_row
        pop     psw
        mov     b,a
        call    inv_get_laser_col
        mov     c,a
        jmp     inv_place_laser
;
inv_update_laser:
        lda     inv_laser_active
        ora     a
        jnz     inv_laser_tick
        lda     inv_fire_pressed
        ora     a
        rz
        jmp     inv_spawn_laser
inv_laser_tick:
        lda     inv_laser_timer
        ora     a
        jz      inv_move_laser
        dcr     a
        sta     inv_laser_timer
        rnz
        jmp     inv_move_laser
;
inv_get_nibble_pair:
        mov     a,m
        ani     0fh
        mov     e,a
        dcx     h
        mov     a,m
        ani     0fh
        rlc
        rlc
        rlc
        rlc
        ora     e
        ret
;
inv_store_nibble_pair:
        push    psw
        ani     0fh
        mov     m,a
        pop     psw
        dcx     h
        rrc
        rrc
        rrc
        rrc
        ani     0fh
        mov     m,a
        ret
;
inv_inc_nibble_pair:
        inr     m
        mov     a,m
        ani     0fh
        mov     m,a
        rnz
        dcx     h
        inr     m
        mov     a,m
        ani     0fh
        mov     m,a
        ret
;
inv_get_alien_init:
        lxi     h,inv_alien_init_lo
        jmp     inv_get_nibble_pair
;
inv_inc_alien_init:
        lxi     h,inv_alien_init_lo
        jmp     inv_inc_nibble_pair
;
inv_get_alien_live_count:
        lxi     h,inv_alien_live_lo
        jmp     inv_get_nibble_pair
;
inv_inc_alien_live_count:
        lxi     h,inv_alien_live_lo
        jmp     inv_inc_nibble_pair
;
inv_get_alien_last:
        lxi     h,inv_alien_last_lo
        jmp     inv_get_nibble_pair
;
inv_store_alien_last:
        lxi     h,inv_alien_last_lo
        jmp     inv_store_nibble_pair
;
inv_alien_live_addr:
        mov     a,b
        lxi     h,inv_alien_live_base
        jmp     add_a_to_hl
;
inv_alien_x_lo_addr:
        mov     a,b
        lxi     h,inv_alien_x_lo_base
        jmp     add_a_to_hl
;
inv_alien_x_hi_addr:
        mov     a,b
        lxi     h,inv_alien_x_hi_base
        jmp     add_a_to_hl
;
inv_alien_y_lo_addr:
        mov     a,b
        lxi     h,inv_alien_y_lo_base
        jmp     add_a_to_hl
;
inv_alien_y_hi_addr:
        mov     a,b
        lxi     h,inv_alien_y_hi_base
        jmp     add_a_to_hl
;
inv_get_alien_x:
        call    inv_alien_x_hi_addr
        mov     a,m
        ani     0fh
        rlc
        rlc
        rlc
        rlc
        mov     d,a
        call    inv_alien_x_lo_addr
        mov     a,m
        ani     0fh
        ora     d
        ret
;
inv_store_alien_x:
        push    psw
        call    inv_alien_x_lo_addr
        pop     psw
        push    psw
        ani     0fh
        mov     m,a
        pop     psw
        rrc
        rrc
        rrc
        rrc
        ani     0fh
        push    psw
        call    inv_alien_x_hi_addr
        pop     psw
        mov     m,a
        ret
;
inv_get_alien_y:
        call    inv_alien_y_hi_addr
        mov     a,m
        ani     0fh
        rlc
        rlc
        rlc
        rlc
        mov     d,a
        call    inv_alien_y_lo_addr
        mov     a,m
        ani     0fh
        ora     d
        ret
;
inv_store_alien_y:
        push    psw
        call    inv_alien_y_lo_addr
        pop     psw
        push    psw
        ani     0fh
        mov     m,a
        pop     psw
        rrc
        rrc
        rrc
        rrc
        ani     0fh
        push    psw
        call    inv_alien_y_hi_addr
        pop     psw
        mov     m,a
        ret
;
inv_set_alien_live:
        push    psw
        call    inv_alien_live_addr
        pop     psw
        mov     m,a
        ret
;
inv_alien_id_to_row_col:
        mvi     d,0
inv_alien_row_col_loop:
        cpi     inv_alien_cols
        jc      inv_alien_row_col_done
        sui     inv_alien_cols
        inr     d
        jmp     inv_alien_row_col_loop
inv_alien_row_col_done:
        mov     e,a
        ret
;
inv_alien_type_for_id:
        call    inv_alien_id_to_row_col
        mov     a,d
        cpi     1
        jc      inv_alien_type_30
        cpi     3
        jc      inv_alien_type_20
        mvi     a,2
        ret
inv_alien_type_30:
        xra     a
        ret
inv_alien_type_20:
        mvi     a,1
        ret
;
inv_reset_aliens:
        lxi     h,inv_alien_data_base
        lxi     b,inv_alien_data_size
        mvi     e,0
inv_clear_alien_data:
        mov     m,e
        inx     h
        dcx     b
        mov     a,b
        ora     c
        jnz     inv_clear_alien_data
        xra     a
        sta     inv_alien_init_lo
        sta     inv_alien_init_hi
        sta     inv_alien_live_lo
        sta     inv_alien_live_hi
        sta     inv_alien_reverse
        sta     inv_alien_y_delta
        sta     inv_alien_descents
        sta     inv_alien_anim_phase
        sta     inv_alien_min_col
        sta     inv_alien_min_row
        mvi     a,0fh
        sta     inv_alien_last_lo
        sta     inv_alien_last_hi
        mvi     a,inv_alien_dir_right
        sta     inv_alien_dir
        mvi     a,inv_alien_cols-1
        sta     inv_alien_max_col
        mvi     a,inv_alien_rows-1
        sta     inv_alien_max_row
        ret
;
inv_spawn_alien:
        mov     a,b
        call    inv_alien_id_to_row_col
        push    d
        mov     a,e
        add     a
        add     a
        add     e
        adi     inv_alien_start_x
        call    inv_store_alien_x
        pop     d
        push    d
        mov     a,d
        add     a
        add     d
        adi     inv_alien_top_row
        call    inv_store_alien_y
        mvi     a,0ffh
        call    inv_set_alien_live
        pop     d
        jmp     inv_draw_alien
;
inv_next_live_alien:
        call    inv_get_alien_last
inv_next_live_alien_loop:
        inr     a
        cpi     inv_alien_count
        jc      inv_next_live_candidate
        xra     a
inv_next_live_candidate:
        mov     b,a
        call    inv_alien_live_addr
        mov     a,m
        ora     a
        mov     a,b
        jz      inv_next_live_alien_loop
        call    inv_store_alien_last
        mov     a,b
        ret
;
inv_cycle_aliens:
        lda     inv_alien_anim_phase
        xri     1
        ani     1
        sta     inv_alien_anim_phase
        xra     a
        sta     inv_alien_y_delta
        lda     inv_alien_reverse
        ora     a
        rz
        xra     a
        sta     inv_alien_reverse
        mvi     a,1
        sta     inv_alien_y_delta
        lda     inv_alien_descents
        inr     a
        ani     0fh
        sta     inv_alien_descents
        lda     inv_alien_dir
        xri     1
        ani     1
        sta     inv_alien_dir
        ret
;
inv_erase_alien:
        call    inv_get_alien_x
        mov     c,a
        call    inv_get_alien_y
        mov     b,a
        push    b
        mvi     d,inv_alien_w
        xra     a
        call    inv_fill_cells
        pop     b
        inr     b
        mvi     d,inv_alien_w
        xra     a
        jmp     inv_fill_cells
;
inv_draw_alien:
        push    b
        mov     a,b
        call    inv_alien_type_for_id
        mov     d,a
        pop     b
        push    d
        call    inv_get_alien_x
        mov     c,a
        call    inv_get_alien_y
        mov     b,a
        pop     d
        lda     inv_alien_anim_phase
        ora     a
        jnz     inv_draw_alien_phase_b
        mov     a,d
        ora     a
        jz      inv_draw_alien_30a
        cpi     1
        jz      inv_draw_alien_20a
        lxi     h,inv_alien10a_top
        lxi     d,inv_alien10a_bottom
        jmp     inv_draw_alien_pair
inv_draw_alien_30a:
        lxi     h,inv_alien30a_top
        lxi     d,inv_alien30a_bottom
        jmp     inv_draw_alien_pair
inv_draw_alien_20a:
        lxi     h,inv_alien20a_top
        lxi     d,inv_alien20a_bottom
        jmp     inv_draw_alien_pair
inv_draw_alien_phase_b:
        mov     a,d
        ora     a
        jz      inv_draw_alien_30b
        cpi     1
        jz      inv_draw_alien_20b
        lxi     h,inv_alien10b_top
        lxi     d,inv_alien10b_bottom
        jmp     inv_draw_alien_pair
inv_draw_alien_30b:
        lxi     h,inv_alien30b_top
        lxi     d,inv_alien30b_bottom
        jmp     inv_draw_alien_pair
inv_draw_alien_20b:
        lxi     h,inv_alien20b_top
        lxi     d,inv_alien20b_bottom
;
inv_draw_alien_pair:
        push    d
        push    b
        call    inv_puts_sg
        pop     b
        pop     d
        inr     b
        xchg
        jmp     inv_puts_sg
;
inv_move_alien:
        push    b
        call    inv_erase_alien
        pop     b
        lda     inv_alien_y_delta
        ora     a
        jz      inv_move_alien_x
        call    inv_get_alien_y
        inr     a
        call    inv_store_alien_y
inv_move_alien_x:
        lda     inv_alien_dir
        ora     a
        jz      inv_move_alien_left
        call    inv_get_alien_x
        inr     a
        call    inv_store_alien_x
        jmp     inv_move_alien_draw
inv_move_alien_left:
        call    inv_get_alien_x
        dcr     a
        call    inv_store_alien_x
inv_move_alien_draw:
        push    b
        call    inv_draw_alien
        pop     b
        jmp     inv_check_alien_edge
;
inv_check_alien_edge:
        call    inv_get_alien_x
        mov     c,a
        lda     inv_alien_dir
        ora     a
        jz      inv_check_alien_left_edge
        mov     a,c
        adi     inv_alien_w-1
        cpi     inv_alien_right_edge
        rc
        jmp     inv_set_alien_reverse
inv_check_alien_left_edge:
        mov     a,c
        cpi     inv_alien_start_x+1
        rnc
inv_set_alien_reverse:
        mvi     a,0ffh
        sta     inv_alien_reverse
        ret
;
inv_update_aliens:
        call    inv_get_alien_init
        cpi     inv_alien_count
        jnc     inv_move_next_alien
        mov     b,a
        call    inv_spawn_alien
        call    inv_inc_alien_init
        call    inv_inc_alien_live_count
        ret
inv_move_next_alien:
        call    inv_get_alien_live_count
        ora     a
        rz
        call    inv_get_alien_last
        push    psw
        call    inv_next_live_alien
        pop     psw
        mov     e,a
        cpi     0ffh
        jz      inv_move_next_alien_now
        mov     a,b
        cmp     e
        jnc     inv_move_next_alien_now
        call    inv_cycle_aliens
inv_move_next_alien_now:
        jmp     inv_move_alien
;
inv_update_turret:
        lda     inv_left_pressed
        mov     b,a
        lda     inv_right_pressed
        ora     b
        rz
        lda     inv_left_pressed
        ora     a
        jz      inv_update_turret_right
        lda     inv_right_pressed
        ora     a
        rnz
        call    inv_get_turret_x
        cpi     inv_turret_min_x
        rc
        rz
        mov     b,a
        dcr     a
        jmp     inv_move_turret
;
inv_update_turret_right:
        call    inv_get_turret_x
        cpi     inv_turret_max_x
        rnc
        mov     b,a
        inr     a
;
inv_move_turret:
        push    psw
        mov     c,b
        call    inv_erase_turret_at
        pop     psw
        push    psw
        call    inv_store_turret_x
        pop     psw
        mov     c,a
        jmp     inv_draw_turret_at
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
        cpi     inv_test_script_input
        jz      inv_test_input_probe
        jmp     inv_test_bad_script
;
inv_test_input_probe:
        lda     inv_test_result
        mov     b,a
        lda     inv_left_pressed
        ora     a
        jz      inv_test_no_left
        mov     a,b
        ori     inv_test_input_left
        mov     b,a
inv_test_no_left:
        lda     inv_right_pressed
        ora     a
        jz      inv_test_no_right
        mov     a,b
        ori     inv_test_input_right
        mov     b,a
inv_test_no_right:
        lda     inv_fire_pressed
        ora     a
        jz      inv_test_no_fire
        mov     a,b
        ori     inv_test_input_fire
        mov     b,a
inv_test_no_fire:
        mov     a,b
        sta     inv_test_result
        ret
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
inv_alien30a_top:
        db      'l','a','a','k',0
inv_alien30a_bottom:
        db      'm','a','a','j',0
inv_alien30b_top:
        db      'l','q','q','k',0
inv_alien30b_bottom:
        db      'm','a','a','j',0
inv_alien20a_top:
        db      'l','q','q','k',0
inv_alien20a_bottom:
        db      'x','_','_','x',0
inv_alien20b_top:
        db      'x','q','q','x',0
inv_alien20b_bottom:
        db      'm','q','q','j',0
inv_alien10a_top:
        db      '_','l','q','k',0
inv_alien10a_bottom:
        db      'm','q','j','_',0
inv_alien10b_top:
        db      'l','q','k','_',0
inv_alien10b_bottom:
        db      '_','m','q','j',0
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
; Replaces "lda last_key_flags" in setup_keys. Non-Invaders SET-UP keys leave
; A exactly as the displaced load would have left it.
;
inv_setup_keys_hook_impl:
        mov     a,b
        ani     0dfh            ; convert lower-case i to upper-case I
        cpi     'I'             ; i or I starts Space Invaders
        jz      inv_setup_start
        lda     last_key_flags  ; repeat the displaced load
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
