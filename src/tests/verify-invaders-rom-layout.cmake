if(NOT DEFINED VT100_BINARY_DIRECTORY)
    message(FATAL_ERROR "VT100_BINARY_DIRECTORY is required")
endif()

set(VT100_BASE_ROM "${VT100_BINARY_DIRECTORY}/vt100.bin")
set(VT100_BASE_SYMBOLS "${VT100_BINARY_DIRECTORY}/vt100.sym")
set(INVADERS_BASE_ROM "${VT100_BINARY_DIRECTORY}/invaders.bin")
set(INVADERS_AVO_ROM "${VT100_BINARY_DIRECTORY}/invaders-avo.bin")
set(INVADERS_BASE_SYMBOLS "${VT100_BINARY_DIRECTORY}/invaders.sym")
set(INVADERS_BASE_EQUATES "${VT100_BINARY_DIRECTORY}/invaders.equ")
set(INVADERS_BASE_INCLUDE "${VT100_BINARY_DIRECTORY}/invaders-base.inc")
set(INVADERS_AVO_SYMBOLS "${VT100_BINARY_DIRECTORY}/invaders-avo.sym")
set(INVADERS_AVO_EQUATES "${VT100_BINARY_DIRECTORY}/invaders-avo.equ")

set(INVADERS_SPLIT_ROM_IMAGES
    invaders-1.bin
    invaders-2.bin
    invaders-3.bin
    invaders-4.bin
)

set(REQUIRED_INVADERS_FILES
    "${VT100_BASE_ROM}"
    "${VT100_BASE_SYMBOLS}"
    "${INVADERS_BASE_ROM}"
    "${INVADERS_AVO_ROM}"
    "${INVADERS_BASE_SYMBOLS}"
    "${INVADERS_BASE_EQUATES}"
    "${INVADERS_BASE_INCLUDE}"
    "${INVADERS_AVO_SYMBOLS}"
    "${INVADERS_AVO_EQUATES}"
)
foreach(INVADERS_SPLIT_ROM_IMAGE IN LISTS INVADERS_SPLIT_ROM_IMAGES)
    list(APPEND REQUIRED_INVADERS_FILES "${VT100_BINARY_DIRECTORY}/${INVADERS_SPLIT_ROM_IMAGE}")
endforeach()

foreach(REQUIRED_INVADERS_FILE IN LISTS REQUIRED_INVADERS_FILES)
    if(NOT EXISTS "${REQUIRED_INVADERS_FILE}")
        message("SKIP: Invaders ROM artifacts are not built; missing ${REQUIRED_INVADERS_FILE}")
        return()
    endif()
endforeach()

function(assert_file_size FILE_NAME EXPECTED_SIZE)
    file(SIZE "${FILE_NAME}" ACTUAL_SIZE)
    if(NOT ACTUAL_SIZE EQUAL EXPECTED_SIZE)
        message(FATAL_ERROR "Expected ${FILE_NAME} to be ${EXPECTED_SIZE} bytes; got ${ACTUAL_SIZE}")
    endif()
endfunction()

function(read_symbol SYMBOL_FILE SYMBOL_NAME OUTPUT_VARIABLE)
    file(STRINGS "${SYMBOL_FILE}" SYMBOL_FILE_LINES)
    set(SYMBOL_ADDRESSES "")
    foreach(SYMBOL_LINE IN LISTS SYMBOL_FILE_LINES)
        if(SYMBOL_LINE MATCHES "^([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])[ \t]+${SYMBOL_NAME}$")
            list(APPEND SYMBOL_ADDRESSES "${CMAKE_MATCH_1}")
        endif()
    endforeach()
    list(LENGTH SYMBOL_ADDRESSES SYMBOL_ADDRESS_COUNT)
    if(NOT SYMBOL_ADDRESS_COUNT EQUAL 1)
        message(FATAL_ERROR "Expected exactly one ${SYMBOL_NAME} symbol in ${SYMBOL_FILE}; got ${SYMBOL_ADDRESS_COUNT}")
    endif()
    list(GET SYMBOL_ADDRESSES 0 SYMBOL_ADDRESS)
    string(TOUPPER "${SYMBOL_ADDRESS}" SYMBOL_ADDRESS)
    set(${OUTPUT_VARIABLE} "${SYMBOL_ADDRESS}" PARENT_SCOPE)
endfunction()

function(read_equate EQUATE_FILE EQUATE_NAME OUTPUT_VARIABLE)
    file(STRINGS "${EQUATE_FILE}" EQUATE_FILE_LINES)
    set(EQUATE_ADDRESSES "")
    foreach(EQUATE_LINE IN LISTS EQUATE_FILE_LINES)
        if(EQUATE_LINE MATCHES "^([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])[ \t]+${EQUATE_NAME}$")
            list(APPEND EQUATE_ADDRESSES "${CMAKE_MATCH_1}")
        endif()
    endforeach()
    list(LENGTH EQUATE_ADDRESSES EQUATE_ADDRESS_COUNT)
    if(NOT EQUATE_ADDRESS_COUNT EQUAL 1)
        message(FATAL_ERROR "Expected exactly one ${EQUATE_NAME} equate in ${EQUATE_FILE}; got ${EQUATE_ADDRESS_COUNT}")
    endif()
    list(GET EQUATE_ADDRESSES 0 EQUATE_ADDRESS)
    string(TOUPPER "${EQUATE_ADDRESS}" EQUATE_ADDRESS)
    set(${OUTPUT_VARIABLE} "${EQUATE_ADDRESS}" PARENT_SCOPE)
endfunction()

function(assert_base_abi_equates EQUATE_FILE)
    set(EXPECTED_INVADERS_ABI_EQUATES
        inv_idle_hook
        inv_setup_keys_hook
        inv_sound_status_hook
        inv_reset_hook
        inv_setup_cursor_hook
    )

    file(STRINGS "${EQUATE_FILE}" EQUATE_FILE_LINES)
    foreach(EQUATE_LINE IN LISTS EQUATE_FILE_LINES)
        if(EQUATE_LINE MATCHES "^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][ \t]+(inv_[A-Za-z0-9_]+)$")
            set(EQUATE_NAME "${CMAKE_MATCH_1}")
            list(FIND EXPECTED_INVADERS_ABI_EQUATES "${EQUATE_NAME}" ABI_INDEX)
            if(ABI_INDEX EQUAL -1)
                message(FATAL_ERROR "${EQUATE_FILE} exports private Invaders equate ${EQUATE_NAME}")
            endif()
        endif()
    endforeach()

    foreach(EXPECTED_INVADERS_ABI_EQUATE IN LISTS EXPECTED_INVADERS_ABI_EQUATES)
        read_equate("${EQUATE_FILE}" "${EXPECTED_INVADERS_ABI_EQUATE}" ABI_EQUATE_ADDRESS)
    endforeach()
endfunction()

function(assert_address_in_window ADDRESS_NAME ADDRESS_VALUE)
    math(EXPR NUMERIC_ADDRESS "0x${ADDRESS_VALUE}")
    if(NUMERIC_ADDRESS LESS 32768 OR NUMERIC_ADDRESS GREATER 40959)
        message(FATAL_ERROR "${ADDRESS_NAME} is outside the AVO ROM window: 0x${ADDRESS_VALUE}")
    endif()
endfunction()

function(assert_address_equals ADDRESS_NAME ADDRESS_VALUE EXPECTED_ADDRESS)
    if(NOT ADDRESS_VALUE STREQUAL EXPECTED_ADDRESS)
        message(FATAL_ERROR "${ADDRESS_NAME} expected 0x${EXPECTED_ADDRESS}; got 0x${ADDRESS_VALUE}")
    endif()
endfunction()

function(hex_byte HEX_DATA BYTE_OFFSET OUTPUT_VARIABLE)
    math(EXPR HEX_OFFSET "${BYTE_OFFSET} * 2")
    string(SUBSTRING "${HEX_DATA}" ${HEX_OFFSET} 2 BYTE_VALUE)
    string(TOUPPER "${BYTE_VALUE}" BYTE_VALUE)
    set(${OUTPUT_VARIABLE} "${BYTE_VALUE}" PARENT_SCOPE)
endfunction()

function(assert_hex_byte HEX_DATA BYTE_OFFSET EXPECTED_BYTE DESCRIPTION)
    hex_byte("${HEX_DATA}" ${BYTE_OFFSET} ACTUAL_BYTE)
    if(NOT ACTUAL_BYTE STREQUAL EXPECTED_BYTE)
        message(FATAL_ERROR "${DESCRIPTION} expected byte ${EXPECTED_BYTE}; got ${ACTUAL_BYTE}")
    endif()
endfunction()

function(assert_jump_target HEX_DATA BYTE_OFFSET EXPECTED_TARGET DESCRIPTION)
    hex_byte("${HEX_DATA}" ${BYTE_OFFSET} OPCODE)
    math(EXPR TARGET_LOW_OFFSET "${BYTE_OFFSET} + 1")
    math(EXPR TARGET_HIGH_OFFSET "${BYTE_OFFSET} + 2")
    hex_byte("${HEX_DATA}" ${TARGET_LOW_OFFSET} TARGET_LOW)
    hex_byte("${HEX_DATA}" ${TARGET_HIGH_OFFSET} TARGET_HIGH)
    set(ACTUAL_TARGET "${TARGET_HIGH}${TARGET_LOW}")
    if(NOT OPCODE STREQUAL "C3")
        message(FATAL_ERROR "${DESCRIPTION} expected jmp opcode C3; got ${OPCODE}")
    endif()
    if(NOT ACTUAL_TARGET STREQUAL EXPECTED_TARGET)
        message(FATAL_ERROR "${DESCRIPTION} expected target 0x${EXPECTED_TARGET}; got 0x${ACTUAL_TARGET}")
    endif()
endfunction()

function(assert_call_target HEX_DATA BYTE_OFFSET EXPECTED_TARGET DESCRIPTION)
    hex_byte("${HEX_DATA}" ${BYTE_OFFSET} OPCODE)
    math(EXPR TARGET_LOW_OFFSET "${BYTE_OFFSET} + 1")
    math(EXPR TARGET_HIGH_OFFSET "${BYTE_OFFSET} + 2")
    hex_byte("${HEX_DATA}" ${TARGET_LOW_OFFSET} TARGET_LOW)
    hex_byte("${HEX_DATA}" ${TARGET_HIGH_OFFSET} TARGET_HIGH)
    set(ACTUAL_TARGET "${TARGET_HIGH}${TARGET_LOW}")
    if(NOT OPCODE STREQUAL "CD")
        message(FATAL_ERROR "${DESCRIPTION} expected call opcode CD; got ${OPCODE}")
    endif()
    if(NOT ACTUAL_TARGET STREQUAL EXPECTED_TARGET)
        message(FATAL_ERROR "${DESCRIPTION} expected target 0x${EXPECTED_TARGET}; got 0x${ACTUAL_TARGET}")
    endif()
endfunction()

function(append_allowed_range OUTPUT_VARIABLE FIRST_OFFSET BYTE_COUNT)
    set(ALLOWED_OFFSETS ${${OUTPUT_VARIABLE}})
    math(EXPR LAST_OFFSET "${FIRST_OFFSET} + ${BYTE_COUNT} - 1")
    foreach(ALLOWED_OFFSET RANGE ${FIRST_OFFSET} ${LAST_OFFSET})
        list(APPEND ALLOWED_OFFSETS "${ALLOWED_OFFSET}")
    endforeach()
    set(${OUTPUT_VARIABLE} "${ALLOWED_OFFSETS}" PARENT_SCOPE)
endfunction()

function(append_allowed_symbol OUTPUT_VARIABLE SYMBOL_ADDRESS)
    set(ALLOWED_OFFSETS ${${OUTPUT_VARIABLE}})
    math(EXPR SYMBOL_OFFSET "0x${SYMBOL_ADDRESS}")
    list(APPEND ALLOWED_OFFSETS "${SYMBOL_OFFSET}")
    set(${OUTPUT_VARIABLE} "${ALLOWED_OFFSETS}" PARENT_SCOPE)
endfunction()

function(assert_mutable_state_layout EQUATE_FILE RAM_START RAM_TOP DATA_FLOOR)
    set(MUTABLE_STATE_RANGES
        inv_test_signature 3
        inv_test_mode 1
        inv_test_script 1
        inv_test_stop_lo 1
        inv_test_stop_hi 1
        inv_test_result 1
        inv_test_trace_head 1
        inv_test_trace_base 128
        inv_active 1
        inv_last_vframe 1
        inv_frame_lo 1
        inv_frame_hi 1
        inv_left_pressed 1
        inv_right_pressed 1
        inv_fire_pressed 1
        inv_score0 1
        inv_score1 1
        inv_score2 1
        inv_gunners 1
        inv_level 1
        inv_saved_led_state 1
        inv_game_over 1
        inv_attract_mode 1
        inv_level_timer 1
        inv_turret_death_timer 1
        inv_missile_tick_timer 1
        inv_missile_fire_timer 1
        inv_missile_active_count 1
        inv_missile_shot_index 1
        inv_missile_slot_tmp 1
        inv_sound_mode 1
        inv_sound_timer 1
        inv_sound_phase 1
        inv_heartbeat_timer 1
        inv_death_sound_timer 1
        inv_last_stock_kbd_status 1
        inv_last_output_kbd_status 1
        inv_ufo_state 1
        inv_ufo_x 1
        inv_ufo_dx 1
        inv_ufo_timer_lo 1
        inv_ufo_timer_hi 1
        inv_ufo_move_timer 1
        inv_ufo_state_timer 1
        inv_ufo_points 1
        inv_ufo_disabled 1
        inv_high_score_dirty 1
        inv_high_score_slot 1
        inv_high_shift_index 1
        inv_high_nvr_index 1
        inv_high_initial_ready 1
        inv_turret_x_lo 1
        inv_turret_x_hi 1
        inv_laser_active 1
        inv_laser_row_lo 1
        inv_laser_row_hi 1
        inv_laser_col_lo 1
        inv_laser_col_hi 1
        inv_laser_timer 1
        inv_laser_shots_lo 1
        inv_laser_shots_hi 1
        inv_hit_row_lo 1
        inv_hit_row_hi 1
        inv_hit_col_lo 1
        inv_hit_col_hi 1
        inv_alien_init_lo 1
        inv_alien_init_hi 1
        inv_alien_live_lo 1
        inv_alien_live_hi 1
        inv_alien_last_lo 1
        inv_alien_last_hi 1
        inv_alien_dir 1
        inv_alien_reverse 1
        inv_alien_y_delta 1
        inv_alien_descents 1
        inv_alien_anim_phase 1
        inv_alien_min_col 1
        inv_alien_max_col 1
        inv_alien_min_row 1
        inv_alien_max_row 1
        inv_alien_data_base 220
        inv_missile_data_base 12
        inv_shield_damage_base 28
        inv_shield_cells_base 84
        inv_high_initial_index 1
        inv_high_initial_used 1
        inv_saved_curs_attr_rend 2
        inv_high_score_digit_base 30
        inv_high_initial_lo_base 30
        inv_high_initial_hi_base 30
    )

    set(USED_MUTABLE_OFFSETS "")
    list(LENGTH MUTABLE_STATE_RANGES MUTABLE_STATE_RANGE_COUNT)
    math(EXPR LAST_MUTABLE_STATE_RANGE_INDEX "${MUTABLE_STATE_RANGE_COUNT} - 1")
    foreach(MUTABLE_STATE_RANGE_INDEX RANGE 0 ${LAST_MUTABLE_STATE_RANGE_INDEX} 2)
        list(GET MUTABLE_STATE_RANGES ${MUTABLE_STATE_RANGE_INDEX} MUTABLE_EQUATE_NAME)
        math(EXPR MUTABLE_STATE_SIZE_INDEX "${MUTABLE_STATE_RANGE_INDEX} + 1")
        list(GET MUTABLE_STATE_RANGES ${MUTABLE_STATE_SIZE_INDEX} MUTABLE_BYTE_COUNT)
        read_equate("${EQUATE_FILE}" "${MUTABLE_EQUATE_NAME}" MUTABLE_EQUATE_ADDRESS)
        math(EXPR MUTABLE_START "0x${MUTABLE_EQUATE_ADDRESS}")
        math(EXPR MUTABLE_END "${MUTABLE_START} + ${MUTABLE_BYTE_COUNT} - 1")

        if(MUTABLE_START LESS RAM_START OR MUTABLE_END GREATER RAM_TOP)
            message(FATAL_ERROR "${MUTABLE_EQUATE_NAME} is outside byte-wide screen RAM: 0x${MUTABLE_EQUATE_ADDRESS}")
        endif()
        if(MUTABLE_START LESS DATA_FLOOR)
            message(FATAL_ERROR "${MUTABLE_EQUATE_NAME} crosses inv_data_floor: 0x${MUTABLE_EQUATE_ADDRESS}")
        endif()

        foreach(MUTABLE_OFFSET RANGE ${MUTABLE_START} ${MUTABLE_END})
            list(FIND USED_MUTABLE_OFFSETS "${MUTABLE_OFFSET}" MUTABLE_OFFSET_INDEX)
            if(NOT MUTABLE_OFFSET_INDEX EQUAL -1)
                message(FATAL_ERROR "${MUTABLE_EQUATE_NAME} overlaps another game-state allocation at ${MUTABLE_OFFSET}")
            endif()
            list(APPEND USED_MUTABLE_OFFSETS "${MUTABLE_OFFSET}")
        endforeach()
    endforeach()
endfunction()

assert_file_size("${INVADERS_BASE_ROM}" 8192)
assert_file_size("${INVADERS_AVO_ROM}" 8192)

set(INVADERS_SPLIT_OFFSET 0)
foreach(INVADERS_SPLIT_ROM_IMAGE IN LISTS INVADERS_SPLIT_ROM_IMAGES)
    set(INVADERS_SPLIT_ROM "${VT100_BINARY_DIRECTORY}/${INVADERS_SPLIT_ROM_IMAGE}")
    assert_file_size("${INVADERS_SPLIT_ROM}" 2048)

    file(READ "${INVADERS_BASE_ROM}" EXPECTED_SPLIT_HEX OFFSET ${INVADERS_SPLIT_OFFSET} LIMIT 2048 HEX)
    file(READ "${INVADERS_SPLIT_ROM}" ACTUAL_SPLIT_HEX HEX)
    if(NOT ACTUAL_SPLIT_HEX STREQUAL EXPECTED_SPLIT_HEX)
        message(FATAL_ERROR "${INVADERS_SPLIT_ROM_IMAGE} does not match invaders.bin at offset ${INVADERS_SPLIT_OFFSET}")
    endif()
    math(EXPR INVADERS_SPLIT_OFFSET "${INVADERS_SPLIT_OFFSET} + 2048")
endforeach()

read_symbol("${INVADERS_AVO_SYMBOLS}" inv_enter_impl INV_ENTER_IMPL)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_reset_for_attract INV_RESET_FOR_ATTRACT)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_start_game INV_START_GAME)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_idle_impl INV_IDLE_IMPL)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_exit_impl INV_EXIT_IMPL)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_idle_hook_impl INV_IDLE_HOOK_IMPL)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_setup_keys_hook_impl INV_SETUP_KEYS_HOOK_IMPL)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_sound_status_hook_impl INV_SOUND_STATUS_HOOK_IMPL)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_reset_hook_impl INV_RESET_HOOK_IMPL)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_setup_cursor_hook_impl INV_SETUP_CURSOR_HOOK_IMPL)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_wait_frame INV_WAIT_FRAME)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_inc_frame16 INV_INC_FRAME16)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_frame INV_FRAME)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_prepare_screen INV_PREPARE_SCREEN)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_save_leds INV_SAVE_LEDS)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_restore_leds INV_RESTORE_LEDS)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_led_for_gunners INV_LED_FOR_GUNNERS)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_update_gunner_leds INV_UPDATE_GUNNER_LEDS)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_cell_addr INV_CELL_ADDR)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_putc INV_PUTC)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_puts_glyphs INV_PUTS_GLYPHS)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_puts_sg INV_PUTS_SG)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_cell_code_to_glyph INV_CELL_CODE_TO_GLYPH)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_put_cell_row INV_PUT_CELL_ROW)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_draw_shield INV_DRAW_SHIELD)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_reset_shields INV_RESET_SHIELDS)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_draw_shields INV_DRAW_SHIELDS)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_draw_status INV_DRAW_STATUS)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_draw_ground INV_DRAW_GROUND)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_draw_turret INV_DRAW_TURRET)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_draw_turret_at INV_DRAW_TURRET_AT)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_erase_turret_at INV_ERASE_TURRET_AT)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_fill_cells INV_FILL_CELLS)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_get_turret_x INV_GET_TURRET_X)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_store_turret_x INV_STORE_TURRET_X)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_get_laser_shots INV_GET_LASER_SHOTS)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_draw_score INV_DRAW_SCORE)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_draw_level INV_DRAW_LEVEL)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_reset_ufo INV_RESET_UFO)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_clear_ufo INV_CLEAR_UFO)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_disable_ufo INV_DISABLE_UFO)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_tick_ufo_timer INV_TICK_UFO_TIMER)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_update_ufo INV_UPDATE_UFO)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_spawn_ufo INV_SPAWN_UFO)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_update_active_ufo INV_UPDATE_ACTIVE_UFO)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_try_ufo_collision INV_TRY_UFO_COLLISION)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_kill_ufo INV_KILL_UFO)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_select_ufo_points INV_SELECT_UFO_POINTS)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_draw_ufo INV_DRAW_UFO)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_draw_ufo_explosion INV_DRAW_UFO_EXPLOSION)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_draw_ufo_score INV_DRAW_UFO_SCORE)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_try_alien_collision INV_TRY_ALIEN_COLLISION)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_laser_hits_alien INV_LASER_HITS_ALIEN)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_dec_alien_live_count INV_DEC_ALIEN_LIVE_COUNT)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_inc_score_digit INV_INC_SCORE_DIGIT)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_add_alien_score INV_ADD_ALIEN_SCORE)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_maybe_add_high_score INV_MAYBE_ADD_HIGH_SCORE)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_load_high_scores INV_LOAD_HIGH_SCORES)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_load_high_scores_raw INV_LOAD_HIGH_SCORES_RAW)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_store_high_scores INV_STORE_HIGH_SCORES)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_update_level_reset INV_UPDATE_LEVEL_RESET)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_next_level INV_NEXT_LEVEL)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_reset_sound INV_RESET_SOUND)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_next_sound_mask INV_NEXT_SOUND_MASK)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_start_death_sound INV_START_DEATH_SOUND)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_update_heartbeat INV_UPDATE_HEARTBEAT)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_heartbeat_period INV_HEARTBEAT_PERIOD)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_reset_aliens INV_RESET_ALIENS)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_alien_level_y_offset INV_ALIEN_LEVEL_Y_OFFSET)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_spawn_alien INV_SPAWN_ALIEN)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_next_live_alien INV_NEXT_LIVE_ALIEN)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_kill_alien INV_KILL_ALIEN)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_recompute_alien_bounds INV_RECOMPUTE_ALIEN_BOUNDS)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_cycle_aliens INV_CYCLE_ALIENS)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_draw_alien INV_DRAW_ALIEN)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_move_alien INV_MOVE_ALIEN)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_update_aliens INV_UPDATE_ALIENS)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_update_turret INV_UPDATE_TURRET)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_draw_static_screen INV_DRAW_STATIC_SCREEN)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_draw_attract_screen INV_DRAW_ATTRACT_SCREEN)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_clear_gunner_leds INV_CLEAR_GUNNER_LEDS)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_clear_playfield INV_CLEAR_PLAYFIELD)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_test_render_probe INV_TEST_RENDER_PROBE)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_test_input_probe INV_TEST_INPUT_PROBE)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_test_high_score_probe INV_TEST_HIGH_SCORE_PROBE)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_test_tick INV_TEST_TICK)
read_symbol("${INVADERS_AVO_SYMBOLS}" inv_row_addr INV_ROW_ADDR)
assert_base_abi_equates("${INVADERS_BASE_EQUATES}")
read_equate("${INVADERS_AVO_EQUATES}" inv_enter INV_ENTER)
read_equate("${INVADERS_AVO_EQUATES}" inv_idle INV_IDLE)
read_equate("${INVADERS_AVO_EQUATES}" inv_exit INV_EXIT)
read_equate("${INVADERS_BASE_EQUATES}" inv_idle_hook INV_IDLE_HOOK)
read_equate("${INVADERS_BASE_EQUATES}" inv_setup_keys_hook INV_SETUP_KEYS_HOOK)
read_equate("${INVADERS_BASE_EQUATES}" inv_sound_status_hook INV_SOUND_STATUS_HOOK)
read_equate("${INVADERS_BASE_EQUATES}" inv_reset_hook INV_RESET_HOOK)
read_equate("${INVADERS_BASE_EQUATES}" inv_setup_cursor_hook INV_SETUP_CURSOR_HOOK)
read_equate("${INVADERS_AVO_EQUATES}" inv_screen_ram_start INV_SCREEN_RAM_START)
read_equate("${INVADERS_AVO_EQUATES}" inv_screen_ram_top INV_SCREEN_RAM_TOP)
read_equate("${INVADERS_AVO_EQUATES}" inv_screen_buffer_end INV_SCREEN_BUFFER_END)
read_equate("${INVADERS_AVO_EQUATES}" inv_active INV_ACTIVE)
read_equate("${INVADERS_BASE_EQUATES}" main_video MAIN_VIDEO)
read_equate("${INVADERS_AVO_EQUATES}" inv_data_top INV_DATA_TOP)
read_equate("${INVADERS_AVO_EQUATES}" inv_data_floor INV_DATA_FLOOR)
read_equate("${INVADERS_AVO_EQUATES}" inv_volatile_data_low INV_VOLATILE_DATA_LOW)
read_equate("${INVADERS_BASE_EQUATES}" last_key_flags LAST_KEY_FLAGS)
read_symbol("${INVADERS_BASE_SYMBOLS}" idle_loop INVADERS_IDLE_LOOP)
read_symbol("${INVADERS_BASE_SYMBOLS}" reset_init_devices INVADERS_RESET_INIT_DEVICES)
read_symbol("${INVADERS_BASE_SYMBOLS}" init_devices INVADERS_INIT_DEVICES)
read_symbol("${INVADERS_BASE_SYMBOLS}" keyboard_tick INVADERS_KEYBOARD_TICK)
read_symbol("${INVADERS_BASE_SYMBOLS}" kb_scan_status INVADERS_KB_SCAN_STATUS)
read_symbol("${INVADERS_BASE_SYMBOLS}" setup_keys INVADERS_SETUP_KEYS)
read_symbol("${INVADERS_BASE_SYMBOLS}" setup_cursor INVADERS_SETUP_CURSOR)
read_symbol("${INVADERS_BASE_SYMBOLS}" rom1_checksum INVADERS_ROM1_CHECKSUM)
read_symbol("${INVADERS_BASE_SYMBOLS}" rom2_checksum INVADERS_ROM2_CHECKSUM)
read_symbol("${INVADERS_BASE_SYMBOLS}" rom3_checksum INVADERS_ROM3_CHECKSUM)
read_symbol("${INVADERS_BASE_SYMBOLS}" rom4_checksum INVADERS_ROM4_CHECKSUM)
read_symbol("${VT100_BASE_SYMBOLS}" idle_loop VT100_IDLE_LOOP)
read_symbol("${VT100_BASE_SYMBOLS}" init_devices VT100_INIT_DEVICES)
read_symbol("${VT100_BASE_SYMBOLS}" keyboard_tick VT100_KEYBOARD_TICK)
read_symbol("${VT100_BASE_SYMBOLS}" kb_scan_status VT100_KB_SCAN_STATUS)
read_symbol("${VT100_BASE_SYMBOLS}" setup_keys VT100_SETUP_KEYS)
read_symbol("${VT100_BASE_SYMBOLS}" setup_cursor VT100_SETUP_CURSOR)
read_symbol("${VT100_BASE_SYMBOLS}" pk_click VT100_PK_CLICK)
assert_address_in_window(inv_enter_impl "${INV_ENTER_IMPL}")
assert_address_in_window(inv_reset_for_attract "${INV_RESET_FOR_ATTRACT}")
assert_address_in_window(inv_start_game "${INV_START_GAME}")
assert_address_in_window(inv_idle_impl "${INV_IDLE_IMPL}")
assert_address_in_window(inv_exit_impl "${INV_EXIT_IMPL}")
assert_address_in_window(inv_idle_hook_impl "${INV_IDLE_HOOK_IMPL}")
assert_address_in_window(inv_setup_keys_hook_impl "${INV_SETUP_KEYS_HOOK_IMPL}")
assert_address_in_window(inv_sound_status_hook_impl "${INV_SOUND_STATUS_HOOK_IMPL}")
assert_address_in_window(inv_reset_hook_impl "${INV_RESET_HOOK_IMPL}")
assert_address_in_window(inv_setup_cursor_hook_impl "${INV_SETUP_CURSOR_HOOK_IMPL}")
assert_address_in_window(inv_wait_frame "${INV_WAIT_FRAME}")
assert_address_in_window(inv_inc_frame16 "${INV_INC_FRAME16}")
assert_address_in_window(inv_frame "${INV_FRAME}")
assert_address_in_window(inv_prepare_screen "${INV_PREPARE_SCREEN}")
assert_address_in_window(inv_save_leds "${INV_SAVE_LEDS}")
assert_address_in_window(inv_restore_leds "${INV_RESTORE_LEDS}")
assert_address_in_window(inv_led_for_gunners "${INV_LED_FOR_GUNNERS}")
assert_address_in_window(inv_update_gunner_leds "${INV_UPDATE_GUNNER_LEDS}")
assert_address_in_window(inv_cell_addr "${INV_CELL_ADDR}")
assert_address_in_window(inv_putc "${INV_PUTC}")
assert_address_in_window(inv_puts_glyphs "${INV_PUTS_GLYPHS}")
assert_address_in_window(inv_puts_sg "${INV_PUTS_SG}")
assert_address_in_window(inv_cell_code_to_glyph "${INV_CELL_CODE_TO_GLYPH}")
assert_address_in_window(inv_put_cell_row "${INV_PUT_CELL_ROW}")
assert_address_in_window(inv_draw_shield "${INV_DRAW_SHIELD}")
assert_address_in_window(inv_reset_shields "${INV_RESET_SHIELDS}")
assert_address_in_window(inv_draw_shields "${INV_DRAW_SHIELDS}")
assert_address_in_window(inv_draw_status "${INV_DRAW_STATUS}")
assert_address_in_window(inv_draw_ground "${INV_DRAW_GROUND}")
assert_address_in_window(inv_draw_turret "${INV_DRAW_TURRET}")
assert_address_in_window(inv_draw_turret_at "${INV_DRAW_TURRET_AT}")
assert_address_in_window(inv_erase_turret_at "${INV_ERASE_TURRET_AT}")
assert_address_in_window(inv_fill_cells "${INV_FILL_CELLS}")
assert_address_in_window(inv_get_turret_x "${INV_GET_TURRET_X}")
assert_address_in_window(inv_store_turret_x "${INV_STORE_TURRET_X}")
assert_address_in_window(inv_get_laser_shots "${INV_GET_LASER_SHOTS}")
assert_address_in_window(inv_draw_score "${INV_DRAW_SCORE}")
assert_address_in_window(inv_draw_level "${INV_DRAW_LEVEL}")
assert_address_in_window(inv_reset_ufo "${INV_RESET_UFO}")
assert_address_in_window(inv_clear_ufo "${INV_CLEAR_UFO}")
assert_address_in_window(inv_disable_ufo "${INV_DISABLE_UFO}")
assert_address_in_window(inv_tick_ufo_timer "${INV_TICK_UFO_TIMER}")
assert_address_in_window(inv_update_ufo "${INV_UPDATE_UFO}")
assert_address_in_window(inv_spawn_ufo "${INV_SPAWN_UFO}")
assert_address_in_window(inv_update_active_ufo "${INV_UPDATE_ACTIVE_UFO}")
assert_address_in_window(inv_try_ufo_collision "${INV_TRY_UFO_COLLISION}")
assert_address_in_window(inv_kill_ufo "${INV_KILL_UFO}")
assert_address_in_window(inv_select_ufo_points "${INV_SELECT_UFO_POINTS}")
assert_address_in_window(inv_draw_ufo "${INV_DRAW_UFO}")
assert_address_in_window(inv_draw_ufo_explosion "${INV_DRAW_UFO_EXPLOSION}")
assert_address_in_window(inv_draw_ufo_score "${INV_DRAW_UFO_SCORE}")
assert_address_in_window(inv_try_alien_collision "${INV_TRY_ALIEN_COLLISION}")
assert_address_in_window(inv_laser_hits_alien "${INV_LASER_HITS_ALIEN}")
assert_address_in_window(inv_dec_alien_live_count "${INV_DEC_ALIEN_LIVE_COUNT}")
assert_address_in_window(inv_inc_score_digit "${INV_INC_SCORE_DIGIT}")
assert_address_in_window(inv_add_alien_score "${INV_ADD_ALIEN_SCORE}")
assert_address_in_window(inv_maybe_add_high_score "${INV_MAYBE_ADD_HIGH_SCORE}")
assert_address_in_window(inv_load_high_scores "${INV_LOAD_HIGH_SCORES}")
assert_address_in_window(inv_load_high_scores_raw "${INV_LOAD_HIGH_SCORES_RAW}")
assert_address_in_window(inv_store_high_scores "${INV_STORE_HIGH_SCORES}")
assert_address_in_window(inv_update_level_reset "${INV_UPDATE_LEVEL_RESET}")
assert_address_in_window(inv_next_level "${INV_NEXT_LEVEL}")
assert_address_in_window(inv_reset_sound "${INV_RESET_SOUND}")
assert_address_in_window(inv_next_sound_mask "${INV_NEXT_SOUND_MASK}")
assert_address_in_window(inv_start_death_sound "${INV_START_DEATH_SOUND}")
assert_address_in_window(inv_update_heartbeat "${INV_UPDATE_HEARTBEAT}")
assert_address_in_window(inv_heartbeat_period "${INV_HEARTBEAT_PERIOD}")
assert_address_in_window(inv_reset_aliens "${INV_RESET_ALIENS}")
assert_address_in_window(inv_alien_level_y_offset "${INV_ALIEN_LEVEL_Y_OFFSET}")
assert_address_in_window(inv_spawn_alien "${INV_SPAWN_ALIEN}")
assert_address_in_window(inv_next_live_alien "${INV_NEXT_LIVE_ALIEN}")
assert_address_in_window(inv_kill_alien "${INV_KILL_ALIEN}")
assert_address_in_window(inv_recompute_alien_bounds "${INV_RECOMPUTE_ALIEN_BOUNDS}")
assert_address_in_window(inv_cycle_aliens "${INV_CYCLE_ALIENS}")
assert_address_in_window(inv_draw_alien "${INV_DRAW_ALIEN}")
assert_address_in_window(inv_move_alien "${INV_MOVE_ALIEN}")
assert_address_in_window(inv_update_aliens "${INV_UPDATE_ALIENS}")
assert_address_in_window(inv_update_turret "${INV_UPDATE_TURRET}")
assert_address_in_window(inv_draw_static_screen "${INV_DRAW_STATIC_SCREEN}")
assert_address_in_window(inv_draw_attract_screen "${INV_DRAW_ATTRACT_SCREEN}")
assert_address_in_window(inv_clear_gunner_leds "${INV_CLEAR_GUNNER_LEDS}")
assert_address_in_window(inv_clear_playfield "${INV_CLEAR_PLAYFIELD}")
assert_address_in_window(inv_test_render_probe "${INV_TEST_RENDER_PROBE}")
assert_address_in_window(inv_test_input_probe "${INV_TEST_INPUT_PROBE}")
assert_address_in_window(inv_test_high_score_probe "${INV_TEST_HIGH_SCORE_PROBE}")
assert_address_in_window(inv_test_tick "${INV_TEST_TICK}")
assert_address_in_window(inv_row_addr "${INV_ROW_ADDR}")
assert_address_in_window(inv_enter "${INV_ENTER}")
assert_address_in_window(inv_idle "${INV_IDLE}")
assert_address_in_window(inv_exit "${INV_EXIT}")
assert_address_in_window(inv_idle_hook "${INV_IDLE_HOOK}")
assert_address_in_window(inv_setup_keys_hook "${INV_SETUP_KEYS_HOOK}")
assert_address_in_window(inv_sound_status_hook "${INV_SOUND_STATUS_HOOK}")
assert_address_in_window(inv_reset_hook "${INV_RESET_HOOK}")
assert_address_equals(inv_setup_cursor_hook "${INV_SETUP_CURSOR_HOOK}" "8015")
assert_address_equals(inv_screen_ram_start "${INV_SCREEN_RAM_START}" "2C00")
assert_address_equals(inv_screen_ram_top "${INV_SCREEN_RAM_TOP}" "2FFF")
assert_address_equals(inv_data_top "${INV_DATA_TOP}" "2FFF")
assert_address_equals(inv_active "${INV_ACTIVE}" "2FFF")
assert_address_equals(inv_data_floor "${INV_DATA_FLOOR}" "2C00")
assert_address_equals(inv_screen_buffer_end "${INV_SCREEN_BUFFER_END}" "2AEB")
math(EXPR SCREEN_132_END "0x${MAIN_VIDEO} + (132 + 3) * 25")
math(EXPR INV_ACTIVE_ADDRESS "0x${INV_ACTIVE}")
if(INV_ACTIVE_ADDRESS LESS SCREEN_132_END)
    message(FATAL_ERROR "inv_active overlaps the 132-column display or SET-UP scratch row")
endif()
math(EXPR SCREEN_80_END "0x${INV_SCREEN_BUFFER_END}")
math(EXPR STATE_LOW "0x${INV_VOLATILE_DATA_LOW}")
if(STATE_LOW LESS SCREEN_80_END)
    message(FATAL_ERROR "Game state overlaps the 80-column display or SET-UP scratch row")
endif()
assert_address_equals(idle_loop "${INVADERS_IDLE_LOOP}" "${VT100_IDLE_LOOP}")
assert_address_equals(init_devices "${INVADERS_INIT_DEVICES}" "${VT100_INIT_DEVICES}")
assert_address_equals(keyboard_tick "${INVADERS_KEYBOARD_TICK}" "${VT100_KEYBOARD_TICK}")
assert_address_equals(kb_scan_status "${INVADERS_KB_SCAN_STATUS}" "${VT100_KB_SCAN_STATUS}")
assert_address_equals(setup_keys "${INVADERS_SETUP_KEYS}" "${VT100_SETUP_KEYS}")
assert_address_equals(setup_cursor "${INVADERS_SETUP_CURSOR}" "${VT100_SETUP_CURSOR}")

math(EXPR INVADERS_RAM_START "0x${INV_SCREEN_RAM_START}")
math(EXPR INVADERS_RAM_TOP "0x${INV_SCREEN_RAM_TOP}")
math(EXPR INVADERS_DATA_FLOOR_VALUE "0x${INV_DATA_FLOOR}")
assert_mutable_state_layout("${INVADERS_AVO_EQUATES}" ${INVADERS_RAM_START} ${INVADERS_RAM_TOP} ${INVADERS_DATA_FLOOR_VALUE})

file(READ "${VT100_BASE_ROM}" VT100_BASE_HEX HEX)
file(READ "${INVADERS_BASE_ROM}" INVADERS_BASE_HEX HEX)
math(EXPR IDLE_LOOP_OFFSET "0x${INVADERS_IDLE_LOOP}")
math(EXPR RESET_INIT_DEVICES_OFFSET "0x${INVADERS_RESET_INIT_DEVICES}")
math(EXPR SETUP_CURSOR_HOOK_OFFSET "0x${INVADERS_SETUP_CURSOR}")
math(EXPR SETUP_KEYS_HOOK_OFFSET "0x${INVADERS_SETUP_KEYS}")
math(EXPR SETUP_KEYS_HOOK_LOW_OFFSET "${SETUP_KEYS_HOOK_OFFSET} + 1")
math(EXPR SETUP_KEYS_HOOK_HIGH_OFFSET "${SETUP_KEYS_HOOK_OFFSET} + 2")
math(EXPR KB_SCAN_STATUS_OFFSET "0x${INVADERS_KB_SCAN_STATUS}")
math(EXPR KB_SCAN_STATUS_LOW_OFFSET "${KB_SCAN_STATUS_OFFSET} + 1")
math(EXPR KB_SCAN_STATUS_HIGH_OFFSET "${KB_SCAN_STATUS_OFFSET} + 2")
string(SUBSTRING "${LAST_KEY_FLAGS}" 0 2 LAST_KEY_FLAGS_HIGH)
string(SUBSTRING "${LAST_KEY_FLAGS}" 2 2 LAST_KEY_FLAGS_LOW)

assert_call_target("${VT100_BASE_HEX}" ${IDLE_LOOP_OFFSET} "${VT100_KEYBOARD_TICK}" "idle_loop displaced call")
assert_call_target("${INVADERS_BASE_HEX}" ${IDLE_LOOP_OFFSET} "${INV_IDLE_HOOK}" "idle_loop Invaders hook")
assert_call_target("${VT100_BASE_HEX}" ${RESET_INIT_DEVICES_OFFSET} "${VT100_INIT_DEVICES}" "reset_init_devices displaced call")
assert_call_target("${INVADERS_BASE_HEX}" ${RESET_INIT_DEVICES_OFFSET} "${INV_RESET_HOOK}" "reset_init_devices Invaders hook")
math(EXPR SETUP_CURSOR_HEX_OFFSET "${SETUP_CURSOR_HOOK_OFFSET} * 2")
string(SUBSTRING "${VT100_BASE_HEX}" ${SETUP_CURSOR_HEX_OFFSET} 6 SETUP_CURSOR_DISPLACED_HEX)
string(TOUPPER "${SETUP_CURSOR_DISPLACED_HEX}" SETUP_CURSOR_DISPLACED_HEX)
string(SUBSTRING "${VT100_PK_CLICK}" 0 2 PK_CLICK_HIGH)
string(SUBSTRING "${VT100_PK_CLICK}" 2 2 PK_CLICK_LOW)
if(NOT SETUP_CURSOR_DISPLACED_HEX STREQUAL "21${PK_CLICK_LOW}${PK_CLICK_HIGH}")
    message(FATAL_ERROR "setup_cursor displaced instruction must be lxi h,pk_click")
endif()
assert_call_target("${INVADERS_BASE_HEX}" ${SETUP_CURSOR_HOOK_OFFSET} "${INV_SETUP_CURSOR_HOOK}" "setup_cursor Invaders hook")
math(EXPR SETUP_CURSOR_IMPL_OFFSET "0x${INV_SETUP_CURSOR_HOOK_IMPL} - 0x8000")
file(READ "${INVADERS_AVO_ROM}" SETUP_CURSOR_REPEATED_HEX OFFSET ${SETUP_CURSOR_IMPL_OFFSET} LIMIT 3 HEX)
string(TOUPPER "${SETUP_CURSOR_REPEATED_HEX}" SETUP_CURSOR_REPEATED_HEX)
if(NOT SETUP_CURSOR_REPEATED_HEX STREQUAL SETUP_CURSOR_DISPLACED_HEX)
    message(FATAL_ERROR "setup_cursor AVO hook must repeat the displaced instruction")
endif()
assert_hex_byte("${VT100_BASE_HEX}" ${SETUP_KEYS_HOOK_OFFSET} "3A" "setup_keys displaced lda opcode")
assert_hex_byte("${VT100_BASE_HEX}" ${SETUP_KEYS_HOOK_LOW_OFFSET} "${LAST_KEY_FLAGS_LOW}" "setup_keys displaced lda low byte")
assert_hex_byte("${VT100_BASE_HEX}" ${SETUP_KEYS_HOOK_HIGH_OFFSET} "${LAST_KEY_FLAGS_HIGH}" "setup_keys displaced lda high byte")
assert_call_target("${INVADERS_BASE_HEX}" ${SETUP_KEYS_HOOK_OFFSET} "${INV_SETUP_KEYS_HOOK}" "setup_keys Invaders hook")
assert_hex_byte("${VT100_BASE_HEX}" ${KB_SCAN_STATUS_OFFSET} "B6" "kb_scan_status displaced ora opcode")
assert_hex_byte("${VT100_BASE_HEX}" ${KB_SCAN_STATUS_LOW_OFFSET} "36" "kb_scan_status displaced mvi opcode")
assert_hex_byte("${VT100_BASE_HEX}" ${KB_SCAN_STATUS_HIGH_OFFSET} "00" "kb_scan_status displaced mvi immediate")
assert_call_target("${INVADERS_BASE_HEX}" ${KB_SCAN_STATUS_OFFSET} "${INV_SOUND_STATUS_HOOK}" "kb_scan_status Invaders hook")

set(ALLOWED_DIFF_OFFSETS "")
append_allowed_range(ALLOWED_DIFF_OFFSETS ${IDLE_LOOP_OFFSET} 3)
append_allowed_range(ALLOWED_DIFF_OFFSETS ${RESET_INIT_DEVICES_OFFSET} 3)
append_allowed_range(ALLOWED_DIFF_OFFSETS ${SETUP_CURSOR_HOOK_OFFSET} 3)
append_allowed_range(ALLOWED_DIFF_OFFSETS ${SETUP_KEYS_HOOK_OFFSET} 3)
append_allowed_range(ALLOWED_DIFF_OFFSETS ${KB_SCAN_STATUS_OFFSET} 3)
append_allowed_symbol(ALLOWED_DIFF_OFFSETS "${INVADERS_ROM1_CHECKSUM}")
append_allowed_symbol(ALLOWED_DIFF_OFFSETS "${INVADERS_ROM2_CHECKSUM}")
append_allowed_symbol(ALLOWED_DIFF_OFFSETS "${INVADERS_ROM3_CHECKSUM}")
append_allowed_symbol(ALLOWED_DIFF_OFFSETS "${INVADERS_ROM4_CHECKSUM}")

foreach(BASE_OFFSET RANGE 0 8191)
    hex_byte("${VT100_BASE_HEX}" ${BASE_OFFSET} VT100_BYTE)
    hex_byte("${INVADERS_BASE_HEX}" ${BASE_OFFSET} INVADERS_BYTE)
    if(NOT VT100_BYTE STREQUAL INVADERS_BYTE)
        list(FIND ALLOWED_DIFF_OFFSETS "${BASE_OFFSET}" ALLOWED_INDEX)
        if(ALLOWED_INDEX EQUAL -1)
            message(FATAL_ERROR "Unexpected Invaders base ROM byte difference at 0x${BASE_OFFSET}: vt100=${VT100_BYTE} invaders=${INVADERS_BYTE}")
        endif()
    endif()
endforeach()

file(READ "${INVADERS_AVO_ROM}" INVADERS_AVO_HEADER HEX OFFSET 0 LIMIT 24)
string(TOUPPER "${INVADERS_AVO_HEADER}" INVADERS_AVO_HEADER)
assert_hex_byte("${INVADERS_AVO_HEADER}" 0 "C3" "inv_enter")
assert_hex_byte("${INVADERS_AVO_HEADER}" 3 "C3" "inv_idle")
assert_hex_byte("${INVADERS_AVO_HEADER}" 6 "C3" "inv_exit")
assert_hex_byte("${INVADERS_AVO_HEADER}" 9 "C3" "inv_idle_hook")
assert_hex_byte("${INVADERS_AVO_HEADER}" 12 "C3" "inv_setup_keys_hook")
assert_hex_byte("${INVADERS_AVO_HEADER}" 15 "C3" "inv_sound_status_hook")
assert_hex_byte("${INVADERS_AVO_HEADER}" 18 "C3" "inv_reset_hook")
assert_hex_byte("${INVADERS_AVO_HEADER}" 21 "C3" "inv_setup_cursor_hook")
assert_jump_target("${INVADERS_AVO_HEADER}" 0 "${INV_ENTER_IMPL}" "inv_enter")
assert_jump_target("${INVADERS_AVO_HEADER}" 3 "${INV_IDLE_IMPL}" "inv_idle")
assert_jump_target("${INVADERS_AVO_HEADER}" 6 "${INV_EXIT_IMPL}" "inv_exit")
assert_jump_target("${INVADERS_AVO_HEADER}" 9 "${INV_IDLE_HOOK_IMPL}" "inv_idle_hook")
assert_jump_target("${INVADERS_AVO_HEADER}" 12 "${INV_SETUP_KEYS_HOOK_IMPL}" "inv_setup_keys_hook")
assert_jump_target("${INVADERS_AVO_HEADER}" 15 "${INV_SOUND_STATUS_HOOK_IMPL}" "inv_sound_status_hook")
assert_jump_target("${INVADERS_AVO_HEADER}" 18 "${INV_RESET_HOOK_IMPL}" "inv_reset_hook")
assert_jump_target("${INVADERS_AVO_HEADER}" 21 "${INV_SETUP_CURSOR_HOOK_IMPL}" "inv_setup_cursor_hook")

message(STATUS "Invaders ROM layout verified")
