;
; Fixed addresses shared by the invaders base ROM and AVO ROM.
;
inv_avo_base            equ     8000h
inv_code_base           equ     inv_avo_base
inv_code_top            equ     inv_avo_base+1fffh
inv_enter               equ     inv_code_base+0
inv_idle                equ     inv_code_base+3
inv_exit                equ     inv_code_base+6
inv_idle_hook           equ     inv_code_base+9
inv_setup_keys_hook     equ     inv_code_base+12
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
inv_test_signature      equ     inv_data_top-2        ; 3 bytes, through 3fffh
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
inv_state_low           equ     inv_saved_led_state
;
; Larger buffers live below the fixed scalar state.
;
inv_dirty_queue_top     equ     inv_state_low-1
inv_dirty_queue_size    equ     64
inv_dirty_queue_base    equ     inv_dirty_queue_top-inv_dirty_queue_size+1
inv_object_map_top      equ     inv_dirty_queue_base-1
inv_object_map_size     equ     1440
inv_object_map_base     equ     inv_object_map_top-inv_object_map_size+1
inv_data_low            equ     inv_object_map_base
