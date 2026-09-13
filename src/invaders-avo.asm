;
; Space Invaders AVO ROM image.
;
; This source is assembled separately from the base VT100 CPU ROM. The entry
; points live at fixed addresses so the modified base ROM can call into the AVO
; payload without a linker.
;
        include "invaders-base.inc"

;
; Private AVO ROM entry points and game layout.
;
inv_avo_base            equ     8000h
inv_code_base           equ     inv_avo_base
inv_code_top            equ     inv_avo_base+1fffh
inv_enter               equ     inv_code_base+0
inv_idle                equ     inv_code_base+3
inv_exit                equ     inv_code_base+6
inv_screen_rows         equ     24
inv_screen_cols         equ     80
inv_row_stride          equ     inv_screen_cols+3
inv_sg_source_base      equ     5fh
inv_sg_source_limit     equ     7fh
inv_play_left           equ     10
inv_play_width          equ     60
inv_score_row           equ     23
inv_ground_row          equ     21
inv_shield_top_row      equ     18
inv_shield_w            equ     7
inv_shield_h            equ     3
inv_shield_cells_each   equ     inv_shield_w*inv_shield_h
inv_shield_count        equ     4
inv_shield_cell_count   equ     inv_shield_cells_each*inv_shield_count
inv_shield_damage_each  equ     inv_shield_w
inv_shield_damage_count equ     inv_shield_damage_each*inv_shield_count
inv_shield_damage_gone  equ     3
inv_shield0_x           equ     15
inv_shield1_x           equ     30
inv_shield2_x           equ     45
inv_shield3_x           equ     60
inv_turret_top_row      equ     21
inv_turret_w            equ     7
inv_turret_h            equ     2
inv_turret_start_x      equ     36
inv_turret_start_x_lo   equ     04h
inv_turret_start_x_hi   equ     02h
inv_turret_min_x        equ     inv_play_left
inv_turret_max_x        equ     inv_play_left+inv_play_width-inv_turret_w
inv_laser_start_row     equ     inv_turret_top_row-1
inv_laser_top_row       equ     0
inv_laser_period        equ     1
inv_laser_glyph         equ     19h
inv_missile_count       equ     3
inv_missile_tick_period equ     3
inv_missile_initial_delay equ   40
inv_missile_reload_delay equ    17
inv_missile_empty_delay equ     4
inv_missile_glyph       equ     18h
inv_missile_shoot_order_count equ 76
inv_turret_death_frames equ     55
inv_ufo_row             equ     0
inv_ufo_w               equ     7
inv_ufo_h               equ     2
inv_ufo_left_x          equ     4
inv_ufo_right_x         equ     inv_screen_cols-inv_ufo_w-4
inv_ufo_state_idle      equ     0
inv_ufo_state_active    equ     1
inv_ufo_state_explode   equ     2
inv_ufo_state_score     equ     3
inv_ufo_first_delay_lo  equ     58h
inv_ufo_first_delay_hi  equ     02h
inv_ufo_interval_lo     equ     0dch
inv_ufo_interval_hi     equ     05h
inv_ufo_move_period     equ     5
inv_ufo_explosion_frames equ    21
inv_ufo_score_frames    equ     72
inv_ufo_disable_count   equ     8
inv_ufo_point_count     equ     15
inv_sound_mode_silent   equ     0
inv_sound_mode_heartbeat equ    1
inv_sound_mode_death    equ     2
inv_sound_death_words   equ     200
inv_active_value        equ     05ah
inv_level_pause_frames  equ     0fh
inv_alien_rows          equ     4
inv_alien_cols          equ     11
inv_alien_count         equ     inv_alien_rows*inv_alien_cols
inv_alien_w             equ     4
inv_alien_h             equ     2
inv_alien_slot_w        equ     5
inv_alien_slot_h        equ     3
inv_alien_start_x       equ     inv_play_left
inv_alien_top_row       equ     2
inv_alien_bottom_row    equ     inv_alien_top_row+((inv_alien_rows-1)*inv_alien_slot_h)
inv_alien_right_edge    equ     inv_play_left+inv_play_width-1
inv_alien_dir_left      equ     0
inv_alien_dir_right     equ     1
inv_initial_gunners     equ     4
inv_initial_level       equ     1
inv_scan_arrow_right    equ     10h
inv_scan_arrow_left     equ     20h
inv_scan_space          equ     77h
inv_scan_setup          equ     7bh
inv_cell_blank          equ     0
inv_cell_checker        equ     1
inv_cell_upper_left     equ     2
inv_cell_upper_right    equ     3
inv_cell_lower_left     equ     4
inv_cell_lower_right    equ     5
inv_cell_hline          equ     6
inv_cell_roof_left      equ     7
inv_cell_roof_right     equ     8
inv_cell_damaged        equ     9
inv_cell_weak           equ     10
;
; Mutable Invaders state lives in AVO RAM and grows downward from the top.
;
inv_avo_ram_start       equ     3000h
inv_avo_ram_top         equ     3fffh
inv_data_top            equ     inv_avo_ram_top
inv_data_floor          equ     3800h
;
; Fixed test and diagnostic bytes.
;
inv_test_signature      equ     inv_data_top-2
inv_test_signature0     equ     05h
inv_test_signature1     equ     0ah
inv_test_signature2     equ     0fh
inv_test_mode           equ     inv_test_signature-1
inv_test_script         equ     inv_test_mode-1
inv_test_stop_lo        equ     inv_test_script-1
inv_test_stop_hi        equ     inv_test_stop_lo-1
inv_test_result         equ     inv_test_stop_hi-1
inv_test_trace_head     equ     inv_test_result-1
inv_test_trace_top      equ     inv_test_trace_head-1
inv_test_trace_size     equ     128
inv_test_trace_base     equ     inv_test_trace_top-inv_test_trace_size+1
;
; Test mode result codes.
;
inv_pass                equ     00h
inv_fail_no_avo         equ     01h
inv_fail_bad_state      equ     02h
inv_fail_bad_sprite     equ     03h
inv_fail_timeout        equ     04h
inv_test_script_none    equ     00h
inv_test_script_render  equ     01h
inv_test_script_input   equ     02h
inv_test_input_left     equ     01h
inv_test_input_right    equ     02h
inv_test_input_fire     equ     04h
;
; Persistent scalar game state.
;
inv_active              equ     inv_test_trace_base-1
inv_last_vframe         equ     inv_active-1
inv_frame_lo            equ     inv_last_vframe-1
inv_frame_hi            equ     inv_frame_lo-1
inv_left_pressed        equ     inv_frame_hi-1
inv_right_pressed       equ     inv_left_pressed-1
inv_fire_pressed        equ     inv_right_pressed-1
inv_score0              equ     inv_fire_pressed-1
inv_score1              equ     inv_score0-1
inv_score2              equ     inv_score1-1
inv_gunners             equ     inv_score2-1
inv_level               equ     inv_gunners-1
inv_saved_led_state     equ     inv_level-1
inv_game_over           equ     inv_saved_led_state-1
inv_level_timer         equ     inv_game_over-1
inv_turret_death_timer  equ     inv_level_timer-1
inv_missile_tick_timer  equ     inv_turret_death_timer-1
inv_missile_fire_timer  equ     inv_missile_tick_timer-1
inv_missile_active_count equ    inv_missile_fire_timer-1
inv_missile_shot_index  equ     inv_missile_active_count-1
inv_missile_slot_tmp    equ     inv_missile_shot_index-1
inv_sound_mode          equ     inv_missile_slot_tmp-1
inv_sound_timer         equ     inv_sound_mode-1
inv_sound_phase         equ     inv_sound_timer-1
inv_heartbeat_timer     equ     inv_sound_phase-1
inv_death_sound_timer   equ     inv_heartbeat_timer-1
inv_last_stock_kbd_status equ    inv_death_sound_timer-1
inv_last_output_kbd_status equ   inv_last_stock_kbd_status-1
inv_ufo_state           equ     inv_last_output_kbd_status-1
inv_ufo_x               equ     inv_ufo_state-1
inv_ufo_dx              equ     inv_ufo_x-1
inv_ufo_timer_lo        equ     inv_ufo_dx-1
inv_ufo_timer_hi        equ     inv_ufo_timer_lo-1
inv_ufo_move_timer      equ     inv_ufo_timer_hi-1
inv_ufo_state_timer     equ     inv_ufo_move_timer-1
inv_ufo_points          equ     inv_ufo_state_timer-1
inv_ufo_disabled        equ     inv_ufo_points-1
inv_turret_x            equ     inv_ufo_disabled-1
inv_turret_x_lo         equ     inv_turret_x
inv_turret_x_hi         equ     inv_turret_x_lo-1
inv_laser_active        equ     inv_turret_x_hi-1
inv_laser_row_lo        equ     inv_laser_active-1
inv_laser_row_hi        equ     inv_laser_row_lo-1
inv_laser_col_lo        equ     inv_laser_row_hi-1
inv_laser_col_hi        equ     inv_laser_col_lo-1
inv_laser_timer         equ     inv_laser_col_hi-1
inv_laser_shots_lo      equ     inv_laser_timer-1
inv_laser_shots_hi      equ     inv_laser_shots_lo-1
inv_hit_row_lo          equ     inv_laser_shots_hi-1
inv_hit_row_hi          equ     inv_hit_row_lo-1
inv_hit_col_lo          equ     inv_hit_row_hi-1
inv_hit_col_hi          equ     inv_hit_col_lo-1
inv_alien_init_lo       equ     inv_hit_col_hi-1
inv_alien_init_hi       equ     inv_alien_init_lo-1
inv_alien_live_lo       equ     inv_alien_init_hi-1
inv_alien_live_hi       equ     inv_alien_live_lo-1
inv_alien_last_lo       equ     inv_alien_live_hi-1
inv_alien_last_hi       equ     inv_alien_last_lo-1
inv_alien_dir           equ     inv_alien_last_hi-1
inv_alien_reverse       equ     inv_alien_dir-1
inv_alien_y_delta       equ     inv_alien_reverse-1
inv_alien_descents      equ     inv_alien_y_delta-1
inv_alien_anim_phase    equ     inv_alien_descents-1
inv_alien_min_col       equ     inv_alien_anim_phase-1
inv_alien_max_col       equ     inv_alien_min_col-1
inv_alien_min_row       equ     inv_alien_max_col-1
inv_alien_max_row       equ     inv_alien_min_row-1
inv_alien_scalar_low    equ     inv_alien_max_row
;
; Alien arrays store one 4-bit cell per coordinate nibble or live flag.
;
inv_alien_live_top      equ     inv_alien_scalar_low-1
inv_alien_live_base     equ     inv_alien_live_top-inv_alien_count+1
inv_alien_x_lo_top      equ     inv_alien_live_base-1
inv_alien_x_lo_base     equ     inv_alien_x_lo_top-inv_alien_count+1
inv_alien_x_hi_top      equ     inv_alien_x_lo_base-1
inv_alien_x_hi_base     equ     inv_alien_x_hi_top-inv_alien_count+1
inv_alien_y_lo_top      equ     inv_alien_x_hi_base-1
inv_alien_y_lo_base     equ     inv_alien_y_lo_top-inv_alien_count+1
inv_alien_y_hi_top      equ     inv_alien_y_lo_base-1
inv_alien_y_hi_base     equ     inv_alien_y_hi_top-inv_alien_count+1
inv_alien_data_top      equ     inv_alien_live_top
inv_alien_data_base     equ     inv_alien_y_hi_base
inv_alien_data_size     equ     inv_alien_data_top-inv_alien_data_base+1
inv_alien_state_low     equ     inv_alien_data_base
;
; Enemy missile arrays store one byte per missile slot.
;
inv_missile_active_top  equ     inv_alien_state_low-1
inv_missile_active_base equ     inv_missile_active_top-inv_missile_count+1
inv_missile_row_top     equ     inv_missile_active_base-1
inv_missile_row_base    equ     inv_missile_row_top-inv_missile_count+1
inv_missile_col_top     equ     inv_missile_row_base-1
inv_missile_col_base    equ     inv_missile_col_top-inv_missile_count+1
inv_missile_phase_top   equ     inv_missile_col_base-1
inv_missile_phase_base  equ     inv_missile_phase_top-inv_missile_count+1
inv_missile_data_top    equ     inv_missile_active_top
inv_missile_data_base   equ     inv_missile_phase_base
inv_missile_data_size   equ     inv_missile_data_top-inv_missile_data_base+1
inv_state_low           equ     inv_missile_data_base
;
; Larger buffers live below the fixed scalar state.
;
inv_shield_damage_top   equ     inv_state_low-1
inv_shield_damage_base  equ     inv_shield_damage_top-inv_shield_damage_count+1
inv_shield_cells_top    equ     inv_shield_damage_base-1
inv_shield_cells_base   equ     inv_shield_cells_top-inv_shield_cell_count+1
inv_dirty_queue_top     equ     inv_shield_cells_base-1
inv_dirty_queue_size    equ     32
inv_dirty_queue_base    equ     inv_dirty_queue_top-inv_dirty_queue_size+1
inv_object_map_top      equ     inv_dirty_queue_base-1
inv_object_map_size     equ     1440
inv_object_map_base     equ     inv_object_map_top-inv_object_map_size+1
inv_data_low            equ     inv_object_map_base

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
        org     inv_sound_status_hook
        jmp     inv_sound_status_hook_impl

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
        sta     inv_level_timer
        sta     inv_test_result
        sta     inv_laser_active
        sta     inv_laser_row_lo
        sta     inv_laser_row_hi
        sta     inv_laser_col_lo
        sta     inv_laser_col_hi
        sta     inv_laser_timer
        sta     inv_laser_shots_lo
        sta     inv_laser_shots_hi
        call    inv_reset_enemy_fire
        call    inv_reset_sound
        call    inv_reset_ufo
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
        mvi     a,inv_active_value
        sta     inv_active
        ret
;
inv_idle_impl:
        call    update_kbd
        call    inv_read_keys
        lda     inv_active
        cpi     inv_active_value
        rnz
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
        jnz     inv_frame_ready
        call    update_kbd
        jmp     inv_wait_frame
inv_frame_ready:
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
        cpi     inv_active_value
        rnz
        call    inv_update_level_reset
        rnz
        call    inv_update_turret_death
        rnz
        call    inv_update_aliens
        call    inv_update_heartbeat
        call    inv_update_ufo
        call    inv_update_enemy_fire
        lda     inv_game_over
        ora     a
        rnz
        lda     inv_turret_death_timer
        ora     a
        rnz
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
        lxi     h,inv_shield_damage_base
        mvi     b,inv_shield_damage_count
        xra     a
inv_reset_shield_damage:
        mov     m,a
        inx     h
        dcr     b
        jnz     inv_reset_shield_damage
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
        call    inv_puts_glyphs
        call    inv_draw_score
        jmp     inv_draw_level
;
inv_draw_score:
        mvi     b,inv_score_row
        mvi     c,6
        lda     inv_score2
        call    inv_draw_digit
        mvi     b,inv_score_row
        mvi     c,7
        lda     inv_score1
        call    inv_draw_digit
        mvi     b,inv_score_row
        mvi     c,8
        lda     inv_score0
        call    inv_draw_digit
        mvi     b,inv_score_row
        mvi     c,9
        mvi     a,'0'
        jmp     inv_putc
;
inv_draw_level:
        mvi     b,inv_score_row
        mvi     c,18
        lda     inv_level
        jmp     inv_draw_digit
;
inv_draw_digit:
        ani     0fh
        adi     '0'
        jmp     inv_putc
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
        mov     d,a
        lda     inv_laser_row_lo
        ani     0fh
        ora     d
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
        mov     d,a
        lda     inv_laser_col_lo
        ani     0fh
        ora     d
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
inv_get_laser_shots:
        lxi     h,inv_laser_shots_lo
        jmp     inv_get_nibble_pair
;
inv_deactivate_laser:
        xra     a
        sta     inv_laser_active
        sta     inv_laser_timer
        ret
;
inv_clear_laser:
        lda     inv_laser_active
        ora     a
        jz      inv_deactivate_laser
        call    inv_erase_laser
        jmp     inv_deactivate_laser
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
        call    inv_damage_shield_column
        mvi     a,0ffh
        ret
;
inv_damage_shield_column:
        call    inv_shield_damage_addr
        mov     a,m
        inr     a
        cpi     inv_shield_damage_gone+1
        jc      inv_store_shield_damage
        mvi     a,inv_shield_damage_gone
inv_store_shield_damage:
        mov     m,a
        push    psw
        mvi     b,inv_shield_top_row
        call    inv_redraw_shield_cell
        pop     psw
        push    psw
        mvi     b,inv_shield_top_row+1
        call    inv_redraw_shield_cell
        pop     psw
        push    psw
        mvi     b,inv_shield_top_row+2
        call    inv_redraw_shield_cell
        pop     psw
        ret
;
inv_shield_damage_addr:
        mov     a,c
        cpi     inv_shield0_x
        jc      inv_no_shield_damage
        cpi     inv_shield0_x+inv_shield_w
        jc      inv_shield0_damage_addr
        cpi     inv_shield1_x
        jc      inv_no_shield_damage
        cpi     inv_shield1_x+inv_shield_w
        jc      inv_shield1_damage_addr
        cpi     inv_shield2_x
        jc      inv_no_shield_damage
        cpi     inv_shield2_x+inv_shield_w
        jc      inv_shield2_damage_addr
        cpi     inv_shield3_x
        jc      inv_no_shield_damage
        cpi     inv_shield3_x+inv_shield_w
        jnc     inv_no_shield_damage
        lxi     h,inv_shield_damage_base+(inv_shield_damage_each*3)
        mvi     a,inv_shield3_x
        jmp     inv_shield_damage_at
inv_shield2_damage_addr:
        lxi     h,inv_shield_damage_base+(inv_shield_damage_each*2)
        mvi     a,inv_shield2_x
        jmp     inv_shield_damage_at
inv_shield1_damage_addr:
        lxi     h,inv_shield_damage_base+inv_shield_damage_each
        mvi     a,inv_shield1_x
        jmp     inv_shield_damage_at
inv_shield0_damage_addr:
        lxi     h,inv_shield_damage_base
        mvi     a,inv_shield0_x
inv_shield_damage_at:
        mov     d,a
        mov     a,c
        sub     d
        call    add_a_to_hl
        mov     a,m
        ret
inv_no_shield_damage:
        xra     a
        ret
;
inv_redraw_shield_cell:
        push    psw
        call    inv_shield_cell_addr
        pop     psw
        mov     d,a
        mov     a,m
        ora     a
        rz
        mov     a,d
        cpi     1
        jz      inv_redraw_shield_damaged
        cpi     2
        jz      inv_redraw_shield_weak
        mvi     m,inv_cell_blank
        xra     a
        jmp     inv_putc
inv_redraw_shield_damaged:
        mvi     a,inv_cell_damaged
        mov     m,a
        call    inv_cell_code_to_glyph
        jmp     inv_putc
inv_redraw_shield_weak:
        mvi     a,inv_cell_weak
        mov     m,a
        call    inv_cell_code_to_glyph
        jmp     inv_putc
;
inv_try_alien_collision:
        push    b
        mov     a,b
        lxi     h,inv_hit_row_lo
        call    inv_store_nibble_pair
        mov     a,c
        lxi     h,inv_hit_col_lo
        call    inv_store_nibble_pair
        mvi     b,0
inv_try_alien_collision_loop:
        call    inv_alien_live_addr
        mov     a,m
        ora     a
        jz      inv_try_alien_collision_next
        call    inv_laser_hits_alien
        ora     a
        jz      inv_try_alien_collision_next
        call    inv_kill_alien
        pop     b
        mvi     a,0ffh
        ret
inv_try_alien_collision_next:
        inr     b
        mov     a,b
        cpi     inv_alien_count
        jc      inv_try_alien_collision_loop
        pop     b
        xra     a
        ret
;
inv_laser_hits_alien:
        call    inv_get_alien_y
        mov     d,a
        lxi     h,inv_hit_row_lo
        call    inv_get_nibble_pair
        cmp     d
        jc      inv_laser_misses_alien
        mov     a,d
        adi     inv_alien_h
        mov     d,a
        lxi     h,inv_hit_row_lo
        call    inv_get_nibble_pair
        cmp     d
        jnc     inv_laser_misses_alien
        call    inv_get_alien_x
        mov     d,a
        lxi     h,inv_hit_col_lo
        call    inv_get_nibble_pair
        cmp     d
        jc      inv_laser_misses_alien
        mov     a,d
        adi     inv_alien_w
        mov     d,a
        lxi     h,inv_hit_col_lo
        call    inv_get_nibble_pair
        cmp     d
        jnc     inv_laser_misses_alien
        mvi     a,0ffh
        ret
inv_laser_misses_alien:
        xra     a
        ret
;
inv_place_laser:
        call    inv_try_shield_collision
        ora     a
        jnz     inv_deactivate_laser
        call    inv_try_ufo_collision
        ora     a
        jnz     inv_deactivate_laser
        call    inv_try_alien_collision
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
inv_reset_ufo:
        xra     a
        sta     inv_ufo_state
        sta     inv_ufo_x
        sta     inv_ufo_dx
        sta     inv_ufo_move_timer
        sta     inv_ufo_state_timer
        sta     inv_ufo_points
        sta     inv_ufo_disabled
        mvi     a,inv_ufo_first_delay_lo
        sta     inv_ufo_timer_lo
        mvi     a,inv_ufo_first_delay_hi
        sta     inv_ufo_timer_hi
        ret
;
inv_clear_ufo:
        lda     inv_ufo_state
        ora     a
        jz      inv_reset_ufo
        call    inv_erase_ufo
        jmp     inv_reset_ufo
;
inv_disable_ufo:
        lda     inv_ufo_state
        ora     a
        jz      inv_disable_ufo_clear
        call    inv_erase_ufo
inv_disable_ufo_clear:
        xra     a
        sta     inv_ufo_state
        sta     inv_ufo_move_timer
        sta     inv_ufo_state_timer
        sta     inv_ufo_points
        sta     inv_ufo_timer_lo
        sta     inv_ufo_timer_hi
        mvi     a,0ffh
        sta     inv_ufo_disabled
        ret
;
inv_set_ufo_interval:
        mvi     a,inv_ufo_interval_lo
        sta     inv_ufo_timer_lo
        mvi     a,inv_ufo_interval_hi
        sta     inv_ufo_timer_hi
        ret
;
inv_tick_ufo_timer:
        lda     inv_ufo_timer_hi
        mov     d,a
        lda     inv_ufo_timer_lo
        ora     d
        rz
        lxi     h,inv_ufo_timer_lo
        mov     a,m
        ora     a
        jz      inv_tick_ufo_timer_borrow
        dcr     m
        mov     a,m
        dcx     h
        ora     m
        ret
inv_tick_ufo_timer_borrow:
        mvi     m,0ffh
        dcx     h
        dcr     m
        mov     a,m
        inx     h
        ora     m
        ret
;
inv_update_ufo:
        lda     inv_game_over
        ora     a
        rnz
        call    inv_get_alien_init
        cpi     inv_alien_count
        rc
        call    inv_get_alien_live_count
        cpi     inv_ufo_disable_count
        jc      inv_disable_ufo
        call    inv_tick_ufo_timer
        lda     inv_ufo_state
        ora     a
        jz      inv_update_ufo_idle
        cpi     inv_ufo_state_active
        jz      inv_update_active_ufo
        cpi     inv_ufo_state_explode
        jz      inv_update_ufo_explosion
        cpi     inv_ufo_state_score
        jz      inv_update_ufo_score
        ret
;
inv_update_ufo_idle:
        lda     inv_ufo_disabled
        ora     a
        rnz
        lda     inv_ufo_timer_hi
        mov     b,a
        lda     inv_ufo_timer_lo
        ora     b
        rnz
        jmp     inv_spawn_ufo
;
inv_spawn_ufo:
        call    inv_set_ufo_interval
        call    inv_get_laser_shots
        ani     1
        jz      inv_spawn_ufo_right
        mvi     a,inv_ufo_right_x
        sta     inv_ufo_x
        mvi     a,0ffh
        sta     inv_ufo_dx
        jmp     inv_spawn_ufo_draw
inv_spawn_ufo_right:
        mvi     a,inv_ufo_left_x
        sta     inv_ufo_x
        mvi     a,1
        sta     inv_ufo_dx
inv_spawn_ufo_draw:
        mvi     a,inv_ufo_state_active
        sta     inv_ufo_state
        mvi     a,inv_ufo_move_period
        sta     inv_ufo_move_timer
        jmp     inv_draw_ufo
;
inv_update_active_ufo:
        lda     inv_ufo_move_timer
        ora     a
        jz      inv_move_ufo_now
        dcr     a
        sta     inv_ufo_move_timer
        rnz
inv_move_ufo_now:
        mvi     a,inv_ufo_move_period
        sta     inv_ufo_move_timer
        call    inv_erase_ufo
        lda     inv_ufo_dx
        cpi     1
        jz      inv_move_ufo_right
        lda     inv_ufo_x
        dcr     a
        sta     inv_ufo_x
        cpi     inv_ufo_left_x
        jc      inv_finish_ufo
        jmp     inv_draw_ufo
inv_move_ufo_right:
        lda     inv_ufo_x
        inr     a
        sta     inv_ufo_x
        cpi     inv_ufo_right_x+1
        jnc     inv_finish_ufo
        jmp     inv_draw_ufo
;
inv_finish_ufo:
        xra     a
        sta     inv_ufo_state
        sta     inv_ufo_move_timer
        sta     inv_ufo_state_timer
        sta     inv_ufo_points
        ret
;
inv_update_ufo_explosion:
        lda     inv_ufo_state_timer
        ora     a
        jz      inv_show_ufo_score
        dcr     a
        sta     inv_ufo_state_timer
        rnz
inv_show_ufo_score:
        call    inv_draw_ufo_score
        lda     inv_ufo_points
        call    inv_add_score_units
        mvi     a,inv_ufo_state_score
        sta     inv_ufo_state
        mvi     a,inv_ufo_score_frames
        sta     inv_ufo_state_timer
        ret
;
inv_update_ufo_score:
        lda     inv_ufo_state_timer
        ora     a
        jz      inv_clear_scored_ufo
        dcr     a
        sta     inv_ufo_state_timer
        rnz
inv_clear_scored_ufo:
        call    inv_erase_ufo
        jmp     inv_finish_ufo
;
inv_try_ufo_collision:
        lda     inv_ufo_state
        cpi     inv_ufo_state_active
        jnz     inv_laser_misses_ufo
        mov     a,b
        cpi     inv_ufo_row
        jc      inv_laser_misses_ufo
        cpi     inv_ufo_row+inv_ufo_h
        jnc     inv_laser_misses_ufo
        lda     inv_ufo_x
        mov     d,a
        mov     a,c
        cmp     d
        jc      inv_laser_misses_ufo
        mov     a,d
        adi     inv_ufo_w
        mov     d,a
        mov     a,c
        cmp     d
        jnc     inv_laser_misses_ufo
        call    inv_kill_ufo
        mvi     a,0ffh
        ret
inv_laser_misses_ufo:
        xra     a
        ret
;
inv_kill_ufo:
        call    inv_select_ufo_points
        call    inv_erase_ufo
        call    inv_draw_ufo_explosion
        mvi     a,inv_ufo_state_explode
        sta     inv_ufo_state
        mvi     a,inv_ufo_explosion_frames
        sta     inv_ufo_state_timer
        ret
;
inv_select_ufo_points:
        call    inv_get_laser_shots
inv_select_ufo_points_mod:
        cpi     inv_ufo_point_count
        jc      inv_select_ufo_points_lookup
        sui     inv_ufo_point_count
        jmp     inv_select_ufo_points_mod
inv_select_ufo_points_lookup:
        lxi     h,inv_ufo_points_table
        call    add_a_to_hl
        mov     a,m
        sta     inv_ufo_points
        ret
;
inv_draw_ufo:
        lda     inv_ufo_x
        mov     c,a
        mvi     b,inv_ufo_row
        lxi     h,inv_ufo_top
        call    inv_puts_sg
        lda     inv_ufo_x
        mov     c,a
        mvi     b,inv_ufo_row+1
        lxi     h,inv_ufo_bottom
        jmp     inv_puts_sg
;
inv_draw_ufo_explosion:
        lda     inv_ufo_x
        mov     c,a
        mvi     b,inv_ufo_row
        lxi     h,inv_ufo_explosion_top
        call    inv_puts_sg
        lda     inv_ufo_x
        mov     c,a
        mvi     b,inv_ufo_row+1
        lxi     h,inv_ufo_explosion_bottom
        jmp     inv_puts_sg
;
inv_erase_ufo:
        lda     inv_ufo_x
        mov     c,a
        mvi     b,inv_ufo_row
        mvi     d,inv_ufo_w
        xra     a
        call    inv_fill_cells
        lda     inv_ufo_x
        mov     c,a
        mvi     b,inv_ufo_row+1
        mvi     d,inv_ufo_w
        xra     a
        jmp     inv_fill_cells
;
inv_draw_ufo_score:
        call    inv_erase_ufo
        lda     inv_ufo_x
        adi     2
        mov     c,a
        mvi     b,inv_ufo_row
        lda     inv_ufo_points
        cpi     5
        jz      inv_draw_ufo_score_50
        cpi     15
        jz      inv_draw_ufo_score_150
        cpi     30
        jz      inv_draw_ufo_score_300
        mvi     a,'1'
        call    inv_put_ufo_score_char
        mvi     a,'0'
        call    inv_put_ufo_score_char
        mvi     a,'0'
        jmp     inv_put_ufo_score_char
inv_draw_ufo_score_50:
        mvi     a,'5'
        call    inv_put_ufo_score_char
        mvi     a,'0'
        jmp     inv_put_ufo_score_char
inv_draw_ufo_score_150:
        mvi     a,'1'
        call    inv_put_ufo_score_char
        mvi     a,'5'
        call    inv_put_ufo_score_char
        mvi     a,'0'
        jmp     inv_put_ufo_score_char
inv_draw_ufo_score_300:
        mvi     a,'3'
        call    inv_put_ufo_score_char
        mvi     a,'0'
        call    inv_put_ufo_score_char
        mvi     a,'0'
        jmp     inv_put_ufo_score_char
;
inv_put_ufo_score_char:
        push    b
        call    inv_putc
        pop     b
        inr     c
        ret
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
inv_reset_enemy_fire:
        xra     a
        sta     inv_turret_death_timer
        sta     inv_missile_active_count
        sta     inv_missile_shot_index
        sta     inv_missile_slot_tmp
        lxi     h,inv_missile_data_base
        mvi     b,inv_missile_data_size
inv_clear_missile_data:
        mov     m,a
        inx     h
        dcr     b
        jnz     inv_clear_missile_data
        mvi     a,inv_missile_tick_period
        sta     inv_missile_tick_timer
        mvi     a,inv_missile_initial_delay
        sta     inv_missile_fire_timer
        ret
;
inv_reset_sound:
        xra     a
        sta     inv_sound_mode
        sta     inv_sound_timer
        sta     inv_sound_phase
        sta     inv_heartbeat_timer
        sta     inv_death_sound_timer
        sta     inv_last_stock_kbd_status
        sta     inv_last_output_kbd_status
        ret
;
inv_sound_status_hook_impl:
        ora     m
        mvi     m,0
        sta     inv_last_stock_kbd_status
        mov     b,a
        lda     inv_active
        cpi     inv_active_value
        jnz     inv_sound_status_stock
        lda     inv_game_over
        ora     a
        jnz     inv_sound_status_game_over
        lda     inv_level_timer
        ora     a
        jnz     inv_sound_status_reset_stock
inv_sound_status_game_owned:
        mov     a,b
        ani     7fh
        mov     b,a
        call    inv_next_sound_mask
        ora     b
        jmp     inv_sound_status_store
inv_sound_status_game_over:
        lda     inv_death_sound_timer
        ora     a
        jnz     inv_sound_status_game_owned
        jmp     inv_sound_status_reset_stock
inv_sound_status_reset_stock:
        push    b
        call    inv_reset_sound
        pop     b
        mov     a,b
        sta     inv_last_stock_kbd_status
inv_sound_status_stock:
        mov     a,b
inv_sound_status_store:
        sta     inv_last_output_kbd_status
        ret
;
inv_next_sound_mask:
        lda     inv_death_sound_timer
        ora     a
        jnz     inv_next_death_sound
        lda     inv_sound_mode
        cpi     inv_sound_mode_heartbeat
        jz      inv_next_heartbeat_sound
        xra     a
        ret
;
inv_next_heartbeat_sound:
        lda     inv_sound_timer
        ora     a
        jz      inv_stop_sound
        dcr     a
        sta     inv_sound_timer
        jnz     inv_heartbeat_sound_click
        xra     a
        sta     inv_sound_mode
inv_heartbeat_sound_click:
        mvi     a,iow_kbd_click
        ret
;
inv_next_death_sound:
        lda     inv_death_sound_timer
        dcr     a
        sta     inv_death_sound_timer
        jz      inv_stop_sound
        lda     inv_sound_phase
        inr     a
        ani     07h
        sta     inv_sound_phase
        ani     03h
        cpi     02h
        jc      inv_death_sound_click
        xra     a
        ret
inv_death_sound_click:
        mvi     a,iow_kbd_click
        ret
;
inv_stop_sound:
        xra     a
        sta     inv_sound_mode
        sta     inv_sound_timer
        sta     inv_sound_phase
        ret
;
inv_missile_active_addr:
        mov     a,b
        lxi     h,inv_missile_active_base
        jmp     add_a_to_hl
;
inv_missile_row_addr:
        mov     a,b
        lxi     h,inv_missile_row_base
        jmp     add_a_to_hl
;
inv_missile_col_addr:
        mov     a,b
        lxi     h,inv_missile_col_base
        jmp     add_a_to_hl
;
inv_missile_phase_addr:
        mov     a,b
        lxi     h,inv_missile_phase_base
        jmp     add_a_to_hl
;
inv_current_missile_active_addr:
        lda     inv_missile_slot_tmp
        mov     b,a
        jmp     inv_missile_active_addr
;
inv_current_missile_row_addr:
        lda     inv_missile_slot_tmp
        mov     b,a
        jmp     inv_missile_row_addr
;
inv_current_missile_col_addr:
        lda     inv_missile_slot_tmp
        mov     b,a
        jmp     inv_missile_col_addr
;
inv_current_missile_phase_addr:
        lda     inv_missile_slot_tmp
        mov     b,a
        jmp     inv_missile_phase_addr
;
inv_current_missile_position:
        call    inv_current_missile_row_addr
        mov     d,m
        call    inv_current_missile_col_addr
        mov     c,m
        mov     b,d
        ret
;
inv_find_free_missile:
        mvi     b,0
inv_find_free_missile_loop:
        call    inv_missile_active_addr
        mov     a,m
        ora     a
        jz      inv_find_free_missile_done
        inr     b
        mov     a,b
        cpi     inv_missile_count
        jc      inv_find_free_missile_loop
        xra     a
        ret
inv_find_free_missile_done:
        mvi     a,0ffh
        ret
;
inv_draw_current_missile:
        call    inv_current_missile_position
        mvi     a,inv_missile_glyph
        call    inv_putc
        xra     a
        ret
;
inv_erase_current_missile:
        call    inv_current_missile_position
        xra     a
        jmp     inv_putc
;
inv_deactivate_current_missile:
        call    inv_current_missile_active_addr
        mov     a,m
        ora     a
        jz      inv_deactivate_current_missile_done
        mvi     m,0
        lxi     h,inv_missile_active_count
        mov     a,m
        ora     a
        jz      inv_deactivate_current_missile_done
        dcr     m
        mov     a,m
        ora     a
        jnz     inv_deactivate_current_missile_done
        mvi     a,inv_missile_empty_delay
        sta     inv_missile_fire_timer
inv_deactivate_current_missile_done:
        xra     a
        ret
;
inv_clear_active_missiles:
        mvi     b,0
inv_clear_active_missiles_loop:
        mov     a,b
        sta     inv_missile_slot_tmp
        call    inv_current_missile_active_addr
        mov     a,m
        ora     a
        jz      inv_clear_active_missiles_next
        call    inv_erase_current_missile
        call    inv_current_missile_active_addr
        mvi     m,0
inv_clear_active_missiles_next:
        lda     inv_missile_slot_tmp
        inr     a
        mov     b,a
        cpi     inv_missile_count
        jc      inv_clear_active_missiles_loop
        xra     a
        sta     inv_missile_active_count
        ret
;
inv_update_enemy_fire:
        lda     inv_missile_tick_timer
        ora     a
        jz      inv_enemy_fire_tick_now
        dcr     a
        sta     inv_missile_tick_timer
        rnz
inv_enemy_fire_tick_now:
        mvi     a,inv_missile_tick_period
        sta     inv_missile_tick_timer
        call    inv_enemy_try_fire
        jmp     inv_update_missiles
;
inv_enemy_try_fire:
        call    inv_get_alien_init
        cpi     inv_alien_count
        rc
        call    inv_get_alien_live_count
        ora     a
        rz
        lda     inv_missile_fire_timer
        ora     a
        jz      inv_enemy_try_fire_now
        dcr     a
        sta     inv_missile_fire_timer
        ret
inv_enemy_try_fire_now:
        lda     inv_missile_active_count
        cpi     inv_missile_count
        rnc
        call    inv_enemy_pick_shooter
        ora     a
        rz
        jmp     inv_fire_enemy_missile
;
inv_enemy_pick_shooter:
        mvi     e,inv_missile_shoot_order_count
inv_enemy_pick_shooter_loop:
        push    d
        call    inv_next_shoot_column
        pop     d
        mov     c,a
        push    d
        call    inv_find_column_shooter
        pop     d
        ora     a
        rnz
        dcr     e
        jnz     inv_enemy_pick_shooter_loop
        xra     a
        ret
;
inv_next_shoot_column:
        lda     inv_missile_shot_index
        lxi     h,inv_missile_shoot_order
        call    add_a_to_hl
        mov     d,m
        lda     inv_missile_shot_index
        inr     a
        cpi     inv_missile_shoot_order_count
        jc      inv_next_shoot_column_store
        xra     a
inv_next_shoot_column_store:
        sta     inv_missile_shot_index
        mov     a,d
        ora     a
        jz      inv_enemy_best_column
        dcr     a
        ret
;
inv_enemy_best_column:
        call    inv_get_turret_x
        cpi     inv_alien_start_x
        jc      inv_enemy_best_first_column
        sui     inv_alien_start_x
        mov     d,a
        mvi     b,0
inv_enemy_best_column_loop:
        mov     a,d
        cpi     inv_alien_slot_w
        jc      inv_enemy_best_column_done
        sui     inv_alien_slot_w
        mov     d,a
        inr     b
        mov     a,b
        cpi     inv_alien_cols
        jc      inv_enemy_best_column_loop
        mvi     a,inv_alien_cols-1
        ret
inv_enemy_best_column_done:
        mov     a,b
        ret
inv_enemy_best_first_column:
        xra     a
        ret
;
inv_find_column_shooter:
        mov     a,c
        adi     (inv_alien_rows-1)*inv_alien_cols
        mov     b,a
        mvi     d,inv_alien_rows
inv_find_column_shooter_loop:
        call    inv_alien_live_addr
        mov     a,m
        ora     a
        jnz     inv_find_column_shooter_done
        mov     a,b
        sui     inv_alien_cols
        mov     b,a
        dcr     d
        jnz     inv_find_column_shooter_loop
        xra     a
        ret
inv_find_column_shooter_done:
        mvi     a,0ffh
        ret
;
inv_fire_enemy_missile:
        mov     c,b
        call    inv_find_free_missile
        ora     a
        rz
        mov     a,b
        sta     inv_missile_slot_tmp
        mov     b,c
        call    inv_get_alien_y
        adi     inv_alien_h
        push    psw
        call    inv_get_alien_x
        inr     a
        mov     d,a
        pop     psw
        push    d
        push    psw
        call    inv_current_missile_row_addr
        pop     psw
        mov     m,a
        pop     d
        mov     a,d
        push    psw
        call    inv_current_missile_col_addr
        pop     psw
        mov     m,a
        call    inv_current_missile_phase_addr
        mvi     m,0
        call    inv_current_missile_active_addr
        mvi     m,0ffh
        lxi     h,inv_missile_active_count
        inr     m
        mvi     a,inv_missile_reload_delay
        sta     inv_missile_fire_timer
        jmp     inv_place_current_missile
;
inv_place_current_missile:
        call    inv_current_missile_position
        mov     a,b
        cpi     inv_turret_top_row
        jnc     inv_current_missile_bottom
        call    inv_try_shield_collision
        ora     a
        jnz     inv_deactivate_current_missile
        jmp     inv_draw_current_missile
;
inv_current_missile_bottom:
        call    inv_current_missile_hits_turret
        ora     a
        jnz     inv_current_missile_hit_turret
        jmp     inv_deactivate_current_missile
;
inv_current_missile_hits_turret:
        call    inv_current_missile_position
        mov     a,b
        cpi     inv_turret_top_row
        jc      inv_current_missile_misses_turret
        cpi     inv_turret_top_row+inv_turret_h
        jnc     inv_current_missile_misses_turret
        call    inv_get_turret_x
        mov     d,a
        mov     a,c
        cmp     d
        jc      inv_current_missile_misses_turret
        mov     a,d
        adi     inv_turret_w
        mov     d,a
        mov     a,c
        cmp     d
        jnc     inv_current_missile_misses_turret
        mvi     a,0ffh
        ret
inv_current_missile_misses_turret:
        xra     a
        ret
;
inv_current_missile_hit_turret:
        call    inv_deactivate_current_missile
        call    inv_start_turret_death
        mvi     a,0ffh
        ret
;
inv_update_missiles:
        mvi     b,0
inv_update_missiles_loop:
        push    b
        call    inv_update_current_missile
        pop     b
        ora     a
        rnz
        inr     b
        mov     a,b
        cpi     inv_missile_count
        jc      inv_update_missiles_loop
        xra     a
        ret
;
inv_update_current_missile:
        mov     a,b
        sta     inv_missile_slot_tmp
        call    inv_current_missile_active_addr
        mov     a,m
        ora     a
        rz
        call    inv_erase_current_missile
        call    inv_current_missile_row_addr
        inr     m
        call    inv_current_missile_phase_addr
        mov     a,m
        xri     1
        ani     1
        mov     m,a
        jmp     inv_place_current_missile
;
inv_start_turret_death:
        lda     inv_game_over
        ora     a
        rnz
        lda     inv_turret_death_timer
        ora     a
        rnz
        call    inv_get_turret_x
        mov     c,a
        call    inv_erase_turret_at
        call    inv_clear_laser
        call    inv_clear_active_missiles
        call    inv_draw_turret_explosion
        call    inv_start_death_sound
        lda     inv_gunners
        ora     a
        jz      inv_set_game_over
        dcr     a
        sta     inv_gunners
        call    inv_update_gunner_leds
        lda     inv_gunners
        ora     a
        jz      inv_set_game_over
        mvi     a,inv_turret_death_frames
        sta     inv_turret_death_timer
        ret
;
inv_start_death_sound:
        mvi     a,inv_sound_mode_death
        sta     inv_sound_mode
        xra     a
        sta     inv_sound_timer
        sta     inv_sound_phase
        sta     inv_heartbeat_timer
        mvi     a,inv_sound_death_words
        sta     inv_death_sound_timer
        ret
;
inv_set_game_over:
        mvi     a,0ffh
        sta     inv_game_over
        xra     a
        sta     inv_turret_death_timer
        call    inv_clear_ufo
        ret
;
inv_update_heartbeat:
        lda     inv_game_over
        ora     a
        rnz
        lda     inv_level_timer
        ora     a
        rnz
        lda     inv_turret_death_timer
        ora     a
        rnz
        lda     inv_death_sound_timer
        ora     a
        rnz
        call    inv_get_alien_live_count
        ora     a
        rz
        lda     inv_heartbeat_timer
        ora     a
        jz      inv_schedule_heartbeat
        dcr     a
        sta     inv_heartbeat_timer
        rnz
inv_schedule_heartbeat:
        call    inv_heartbeat_period
        sta     inv_heartbeat_timer
        mvi     a,inv_sound_mode_heartbeat
        sta     inv_sound_mode
        mvi     a,1
        sta     inv_sound_timer
        ret
;
inv_heartbeat_period:
        call    inv_get_alien_live_count
        cpi     45
        jnc     inv_heartbeat_period_32
        cpi     30
        jnc     inv_heartbeat_period_24
        cpi     15
        jnc     inv_heartbeat_period_16
        cpi     7
        jnc     inv_heartbeat_period_10
        mvi     a,6
        ret
inv_heartbeat_period_32:
        mvi     a,32
        ret
inv_heartbeat_period_24:
        mvi     a,24
        ret
inv_heartbeat_period_16:
        mvi     a,16
        ret
inv_heartbeat_period_10:
        mvi     a,10
        ret
;
inv_update_turret_death:
        lda     inv_game_over
        ora     a
        rnz
        lda     inv_turret_death_timer
        ora     a
        rz
        dcr     a
        sta     inv_turret_death_timer
        jnz     inv_turret_death_active
        call    inv_get_turret_x
        mov     c,a
        call    inv_erase_turret_at
        mvi     a,inv_turret_start_x_lo
        sta     inv_turret_x_lo
        mvi     a,inv_turret_start_x_hi
        sta     inv_turret_x_hi
        call    inv_draw_turret
        mvi     a,inv_missile_initial_delay
        sta     inv_missile_fire_timer
inv_turret_death_active:
        mvi     a,0ffh
        ret
;
inv_draw_turret_explosion:
        call    inv_get_turret_x
        mov     c,a
        mvi     b,inv_turret_top_row
        lxi     h,inv_turret_explosion_top
        call    inv_puts_glyphs
        call    inv_get_turret_x
        mov     c,a
        mvi     b,inv_turret_top_row+1
        lxi     h,inv_turret_explosion_bottom
        jmp     inv_puts_glyphs
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
inv_dec_alien_live_count:
        lxi     h,inv_alien_live_lo
        mov     a,m
        ani     0fh
        jz      inv_dec_alien_live_borrow
        dcr     a
        mov     m,a
        ret
inv_dec_alien_live_borrow:
        dcx     h
        mov     a,m
        ani     0fh
        rz
        dcr     a
        mov     m,a
        inx     h
        mvi     m,0fh
        ret
;
inv_add_score_units:
        mov     e,a
inv_add_score_unit:
        lxi     h,inv_score0
        call    inv_inc_score_digit
        jnc     inv_add_score_unit_done
        dcx     h
        call    inv_inc_score_digit
        jnc     inv_add_score_unit_done
        dcx     h
        call    inv_inc_score_digit
inv_add_score_unit_done:
        dcr     e
        jnz     inv_add_score_unit
        jmp     inv_draw_score
;
inv_inc_score_digit:
        inr     m
        mov     a,m
        ani     0fh
        cpi     10
        jc      inv_inc_score_digit_store
        xra     a
        mov     m,a
        stc
        ret
inv_inc_score_digit_store:
        mov     m,a
        ora     a
        ret
;
inv_add_alien_score:
        mov     a,b
        call    inv_alien_type_for_id
        ora     a
        jz      inv_add_alien_score30
        cpi     1
        jz      inv_add_alien_score20
        mvi     a,1
        jmp     inv_add_score_units
inv_add_alien_score30:
        mvi     a,3
        jmp     inv_add_score_units
inv_add_alien_score20:
        mvi     a,2
        jmp     inv_add_score_units
;
inv_update_level_reset:
        lda     inv_level_timer
        ora     a
        rz
        dcr     a
        sta     inv_level_timer
        jnz     inv_level_pause_active
        call    inv_next_level
inv_level_pause_active:
        mvi     a,0ffh
        ret
;
inv_next_level:
        lda     inv_level
        cpi     9
        jnc     inv_next_level_store
        inr     a
inv_next_level_store:
        sta     inv_level
        call    inv_reset_aliens
        call    inv_reset_enemy_fire
        call    inv_reset_sound
        call    inv_reset_ufo
        jmp     inv_draw_static_screen
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
inv_alien_level_y_offset:
        lda     inv_level
        cpi     2
        jc      inv_alien_level_y_top
        mvi     a,1
        ret
inv_alien_level_y_top:
        xra     a
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
        mov     e,a
        call    inv_alien_level_y_offset
        add     e
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
inv_kill_alien:
        push    b
        call    inv_erase_alien
        pop     b
        push    b
        xra     a
        call    inv_set_alien_live
        pop     b
        call    inv_dec_alien_live_count
        push    b
        call    inv_add_alien_score
        pop     b
        call    inv_recompute_alien_bounds
        call    inv_deactivate_laser
        call    inv_get_alien_live_count
        ora     a
        rnz
        mvi     a,inv_level_pause_frames
        sta     inv_level_timer
        ret
;
inv_recompute_alien_bounds:
        call    inv_get_alien_live_count
        ora     a
        jnz     inv_recompute_alien_bounds_live
        sta     inv_alien_min_col
        sta     inv_alien_max_col
        sta     inv_alien_min_row
        sta     inv_alien_max_row
        ret
inv_recompute_alien_bounds_live:
        mvi     a,inv_alien_cols
        sta     inv_alien_min_col
        xra     a
        sta     inv_alien_max_col
        mvi     a,inv_alien_rows
        sta     inv_alien_min_row
        xra     a
        sta     inv_alien_max_row
        mvi     b,0
inv_recompute_alien_bounds_loop:
        call    inv_alien_live_addr
        mov     a,m
        ora     a
        jz      inv_recompute_alien_bounds_next
        mov     a,b
        call    inv_alien_id_to_row_col
        mov     a,e
        lxi     h,inv_alien_min_col
        cmp     m
        jnc     inv_recompute_alien_min_col_done
        mov     m,a
inv_recompute_alien_min_col_done:
        lda     inv_alien_max_col
        cmp     e
        jnc     inv_recompute_alien_max_col_done
        mov     a,e
        sta     inv_alien_max_col
inv_recompute_alien_max_col_done:
        mov     a,d
        lxi     h,inv_alien_min_row
        cmp     m
        jnc     inv_recompute_alien_min_row_done
        mov     m,a
inv_recompute_alien_min_row_done:
        lda     inv_alien_max_row
        cmp     d
        jnc     inv_recompute_alien_bounds_next
        mov     a,d
        sta     inv_alien_max_row
inv_recompute_alien_bounds_next:
        inr     b
        mov     a,b
        cpi     inv_alien_count
        jc      inv_recompute_alien_bounds_loop
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
        jz      inv_move_next_alien_cycle
        jnc     inv_move_next_alien_now
inv_move_next_alien_cycle:
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
        call    inv_test_enabled
        ora     a
        rz
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
inv_test_enabled:
        lda     inv_test_signature
        cpi     inv_test_signature0
        jnz     inv_test_disabled
        lda     inv_test_signature+1
        cpi     inv_test_signature1
        jnz     inv_test_disabled
        lda     inv_test_signature+2
        cpi     inv_test_signature2
        jnz     inv_test_disabled
        mvi     a,0ffh
        ret
inv_test_disabled:
        xra     a
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
        db      '_','a','a','_',0
inv_alien30a_bottom:
        db      'm','a','a','j',0
inv_alien30b_top:
        db      'a','_','_','a',0
inv_alien30b_bottom:
        db      '_','a','a','_',0
inv_alien20a_top:
        db      'a','q','q','a',0
inv_alien20a_bottom:
        db      '_','x','x','_',0
inv_alien20b_top:
        db      'x','a','a','x',0
inv_alien20b_bottom:
        db      'm','q','q','j',0
inv_alien10a_top:
        db      'l','a','a','k',0
inv_alien10a_bottom:
        db      'x','_','_','x',0
inv_alien10b_top:
        db      '_','a','a','_',0
inv_alien10b_bottom:
        db      'm','q','q','j',0
;
inv_cell_glyphs:
        db      00h,02h,0dh,0ch,0eh,0bh,12h,'/',5ch,'*','.'
        db      00h,00h,00h,00h,00h
;
inv_initial_shield_cells:
        db      inv_cell_roof_left,inv_cell_checker,inv_cell_checker
        db      inv_cell_checker,inv_cell_checker,inv_cell_checker
        db      inv_cell_roof_right
        db      inv_cell_checker,inv_cell_checker,inv_cell_checker
        db      inv_cell_checker,inv_cell_checker,inv_cell_checker
        db      inv_cell_checker
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
inv_turret_explosion_top:
        db      '*','a','a','a','a','a','*',0
inv_turret_explosion_bottom:
        db      'a','*','a','*','a','*','a',0
;
inv_ufo_top:
        db      '_','l','q','q','q','k','_',0
inv_ufo_bottom:
        db      'l','a','a','a','a','a','k',0
inv_ufo_explosion_top:
        db      '_','q','n','n','n','q','_',0
inv_ufo_explosion_bottom:
        db      '_','a','a','a','a','a','_',0
inv_ufo_points_table:
        db      10,5,5,10,15,10,10,5,30,10,10,10,5,15,10
;
inv_missile_shoot_order:
        db      0,1,11,1,0,7,0,1,6,3,0,1,1,0,1,1,0,4,11
        db      9,2,0,11,0,1,8,2,0,6,0,3,11,4,0,1,7,0,1
        db      0,11,0,9,0,2,10,11,1,0,8,0,1,6,3,0,7,0,1
        db      1,0,1,1,0,1,11,9,2,0,4,0,11,0,9,0,1,0,5
;
inv_exit_impl:
        xra     a
        sta     inv_active
        sta     inv_left_pressed
        sta     inv_right_pressed
        sta     inv_fire_pressed
        sta     inv_game_over
        sta     inv_level_timer
        sta     inv_turret_death_timer
        call    inv_deactivate_laser
        call    inv_reset_enemy_fire
        call    inv_reset_sound
        call    inv_clear_ufo
        call    inv_clear_playfield
        call    inv_restore_leds
        ret
;
; Replaces the idle-loop call to keyboard_tick in the Invaders base ROM.
; When the game is inactive, repeat the displaced call and return to the
; following base-ROM instruction.
;
inv_idle_hook_impl:
        lda     inv_active
        cpi     inv_active_value
        jz      inv_idle_active
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
