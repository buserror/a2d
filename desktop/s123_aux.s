        .setcpu "65C02"

        .include "apple2.inc"
        .include "../inc/apple2.inc"
        .include "../inc/auxmem.inc"
        .include "../inc/prodos.inc"
        .include "../inc/mouse.inc"
        .include "../a2d.inc"
        .include "../desktop.inc"


.proc a2d

;;; ==================================================
;;; A2D - the GUI library
;;; ==================================================

        .org $4000


;;; ==================================================

;;; ZP Usage

        params_addr     := $80

        ;; $8A initialized same way as state (see $01 IMPL)

        ;; $A8          - Menu count

        ;; $A9-$AA      - Address of current window
        ;; $AB-...      - Copy of current window params (first 12 bytes)

        ;; $D0-$F3      - Drawing state
        ;;  $D0-$DF      - Box
        ;;   $D0-D1       - left
        ;;   $D2-D3       - top
        ;;   $D4-D5       - addr (low byte might be mask?)
        ;;   $D6-D7       - stride
        ;;   $D8-D9       - hoff
        ;;   $DA-DB       - voff
        ;;   $DC-DD       - width
        ;;   $DE-DF       - height
        ;;  $E0-$E7      - Pattern
        ;;  $E8-$E9      - mskand/mskor
        ;;  $EA-$ED      - position (x/y words)
        ;;  $EE-$EF      - thickness (h/v bytes)
        ;;  $F0          - fill mode (still sketchy on this???)
        ;;  $F1          - text mask
        ;;  $F2-$F3      - font

        ;;  $F4-$F5      - Active state (???)
        ;;  $F6-$FA      - ???
        ;;  $FB-$FC      - glyph widths
        ;;  $FD          - glyph flag (if set, stride is 2x???)
        ;;  $FE          - last glyph index (count is this + 1)
        ;;  $FF          - glyph height


        state           := $D0
        state_box       := $D0
        state_left      := $D0
        state_top       := $D2
        state_addr      := $D4
        state_stride    := $D6
        state_hoff      := $D8
        state_voff      := $DA
        state_width     := $DC
        state_height    := $DE
        state_pattern   := $E0
        state_msk       := $E8
        state_mskand    := $E8
        state_mskor     := $E9
        state_pos       := $EA
        state_xpos      := $EA
        state_ypos      := $EC
        state_thick     := $EE
        state_hthick    := $EE
        state_vthick    := $EF
        state_fill      := $F0
        state_tmask     := $F1
        state_font      := $F2

        sizeof_window_params := $3A

        sizeof_state    := 36
        state_offset_in_window_params := $14
        next_offset_in_window_params := $38

        active          := $F4
        active_state    := $F4  ; address of live state block

        fill_eor_mask   := $F6

        glyph_widths    := $FB  ; address
        glyph_flag      := $FD  ;
        glyph_last      := $FE  ; last glyph index
        glyph_height_p  := $FF  ; glyph height

;;; ==================================================
;;; A2D

.proc a2d_dispatch
        .assert * = A2D, error, "A2D entry point must be at $4000"

        lda     LOWSCR
        sta     SET80COL

        bit     preserve_zp_flag ; save ZP?
        bpl     adjust_stack

        ;; Save $80...$FF, swap in what A2D needs at $F4...$FF
        ldx     #$7F
:       lda     $80,x
        sta     zp_saved,x
        dex
        bpl     :-
        ldx     #$0B
:       lda     active_saved,x
        sta     active,x
        dex
        bpl     :-
        jsr     apply_active_state_to_state

adjust_stack:                   ; Adjust stack to account for params
        pla                     ; and stash address at params_addr.
        sta     params_addr
        clc
        adc     #<3
        tax
        pla
        sta     params_addr+1
        adc     #>3
        pha
        txa
        pha

        tsx
        stx     stack_ptr_stash

        ldy     #1              ; Command index
        lda     (params_addr),y
        asl     a
        tax
        lda     a2d_jump_table,x
        sta     jump+1
        lda     a2d_jump_table+1,x
        sta     jump+2

        iny                     ; Point params_addr at params
        lda     (params_addr),y
        pha
        iny
        lda     (params_addr),y
        sta     params_addr+1
        pla
        sta     params_addr

        ;; Param length format is a byte pair;
        ;; * first byte is ZP address to copy bytes to
        ;; * second byte's high bit is "hide cursor" flag
        ;; * rest of second byte is # bytes to copy

        ldy     param_lengths+1,x ; Check param length...
        bpl     done_hiding

        txa                     ; if high bit was set, stash
        pha                     ; registers and params_addr and then
        tya                     ; optionally hide cursor
        pha
        lda     params_addr
        pha
        lda     params_addr+1
        pha
        bit     hide_cursor_flag
        bpl     :+
        jsr     hide_cursor
:       pla
        sta     params_addr+1
        pla
        sta     params_addr
        pla
        and     #$7F            ; clear high bit in length count
        tay
        pla
        tax

done_hiding:
        lda     param_lengths,x ; ZP offset for params
        beq     jump            ; nothing to copy
        sta     store+1
        dey
:       lda     (params_addr),y
store:  sta     $FF,y           ; self modified
        dey
        bpl     :-

jump:   jsr     $FFFF           ; the actual call

        ;; Exposed for routines to call directly
cleanup:
        bit     hide_cursor_flag
        bpl     :+
        jsr     show_cursor

:       bit     preserve_zp_flag
        bpl     exit_with_0
        jsr     apply_state_to_active_state
        ldx     #$0B
:       lda     active,x
        sta     active_saved,x
        dex
        bpl     :-
        ldx     #$7F
:       lda     zp_saved,x
        sta     $80,x
        dex
        bpl     :-

        ;; default is to return with A=0
exit_with_0:
        lda     #0

rts1:   rts
.endproc

;;; ==================================================
;;; Routines can jmp here to exit with A set

a2d_exit_with_a:
        pha
        jsr     a2d_dispatch::cleanup
        pla
        ldx     stack_ptr_stash
        txs
        ldy     #$FF
rts2:   rts

;;; ==================================================
;;; Copy state params (36 bytes) to/from active state addr

.proc apply_active_state_to_state
        ldy     #sizeof_state-1
:       lda     (active_state),y
        sta     state,y
        dey
        bpl     :-
        rts
.endproc

.proc apply_state_to_active_state
        ldy     #sizeof_state-1
:       lda     state,y
        sta     (active_state),y
        dey
        bpl     :-
        rts
.endproc

;;; ==================================================
;;; Drawing calls show/hide cursor before/after
;;; A recursion count is kept to allow rentrancy.

hide_cursor_count:
        .byte   0

.proc hide_cursor
        dec     hide_cursor_count
        jmp     HIDE_CURSOR_IMPL
.endproc

.proc show_cursor
        bit     hide_cursor_count
        bpl     rts2
        inc     hide_cursor_count
        jmp     SHOW_CURSOR_IMPL
.endproc

;;; ==================================================
;;; Jump table for A2D entry point calls

        ;; jt_rts can be used if the only thing the
        ;; routine needs to do is copy params into
        ;; the zero page (state)
        jt_rts := a2d_dispatch::rts1

a2d_jump_table:
        .addr   jt_rts              ; $00
        .addr   L5E51               ; $01
        .addr   CFG_DISPLAY_IMPL    ; $02 CFG_DISPLAY
        .addr   QUERY_SCREEN_IMPL   ; $03 QUERY_SCREEN
        .addr   SET_STATE_IMPL      ; $04 SET_STATE
        .addr   GET_STATE_IMPL      ; $05 GET_STATE
        .addr   SET_BOX_IMPL        ; $06 SET_BOX
        .addr   SET_FILL_MODE_IMPL  ; $07 SET_FILL_MODE
        .addr   SET_PATTERN_IMPL    ; $08 SET_PATTERN
        .addr   jt_rts              ; $09 SET_MSK
        .addr   jt_rts              ; $0A SET_THICKNESS
        .addr   SET_FONT_IMPL       ; $0B SET_FONT
        .addr   jt_rts              ; $0C SET_TEXT_MASK
        .addr   OFFSET_POS_IMPL     ; $0D OFFSET_POS
        .addr   jt_rts              ; $0E SET_POS
        .addr   DRAW_LINE_IMPL      ; $0F DRAW_LINE
        .addr   DRAW_LINE_ABS_IMPL  ; $10 DRAW_LINE_ABS
        .addr   FILL_RECT_IMPL      ; $11 FILL_RECT
        .addr   DRAW_RECT_IMPL      ; $12 DRAW_RECT
        .addr   TEST_BOX_IMPL       ; $13 TEST_BOX
        .addr   DRAW_BITMAP_IMPL    ; $14 DRAW_BITMAP
        .addr   L537E               ; $15
        .addr   DRAW_POLYGONS_IMPL  ; $16 DRAW_POLYGONS
        .addr   L537A               ; $17
        .addr   MEASURE_TEXT_IMPL   ; $18 MEASURE_TEXT
        .addr   DRAW_TEXT_IMPL      ; $19 DRAW_TEXT
        .addr   CONFIGURE_ZP_IMPL   ; $1A CONFIGURE_ZP_USE
        .addr   L5EDE               ; $1B
        .addr   L5F0A               ; $1C
        .addr   L6341               ; $1D
        .addr   L64A5               ; $1E
        .addr   L64D2               ; $1F
        .addr   L65B3               ; $20
        .addr   L8427               ; $21
        .addr   L7D61               ; $22
        .addr   L6747               ; $23
        .addr   SET_CURSOR_IMPL     ; $24 SET_CURSOR
        .addr   SHOW_CURSOR_IMPL    ; $25 SHOW_CURSOR
        .addr   HIDE_CURSOR_IMPL    ; $26 HIDE_CURSOR
        .addr   ERASE_CURSOR_IMPL   ; $27 ERASE_CURSOR
        .addr   GET_CURSOR_IMPL     ; $28 GET_CURSOR
        .addr   L6663               ; $29
        .addr   GET_INPUT_IMPL      ; $2A GET_INPUT
        .addr   CALL_2B_IMPL        ; $2B
        .addr   L65D4               ; $2C
        .addr   SET_INPUT_IMPL      ; $2D SET_INPUT
        .addr   L6814               ; $2E
        .addr   L6ECD               ; $2F
        .addr   SET_MENU_IMPL       ; $30 SET_MENU
        .addr   MENU_CLICK_IMPL     ; $31 MENU_CLICK
        .addr   L6B60               ; $32
        .addr   L6B1D               ; $33
        .addr   L6BCB               ; $34
        .addr   L6BA9               ; $35
        .addr   L6BB5               ; $36
        .addr   L6F1C               ; $37
        .addr   CREATE_WINDOW_IMPL  ; $38 CREATE_WINDOW
        .addr   DESTROY_WINDOW_IMPL ; $39 DESTROY_WINDOW
        .addr   L7836               ; $3A
        .addr   QUERY_WINDOW_IMPL   ; $3B QUERY_WINDOW
        .addr   QUERY_STATE_IMPL    ; $3C QUERY_STATE
        .addr   UPDATE_STATE_IMPL   ; $3D UPDATE_STATE
        .addr   REDRAW_WINDOW_IMPL  ; $3E REDRAW_WINDOW
        .addr   L758C               ; $3F
        .addr   QUERY_TARGET_IMPL   ; $40 QUERY_TARGET
        .addr   QUERY_TOP_IMPL      ; $41 QUERY_TOP
        .addr   RAISE_WINDOW_IMPL   ; $42 RAISE_WINDOW
        .addr   CLOSE_CLICK_IMPL    ; $43 CLOSE_CLICK
        .addr   DRAG_WINDOW_IMPL    ; $44 DRAG_WINDOW
        .addr   DRAG_RESIZE_IMPL    ; $45 DRAG_RESIZE
        .addr   MAP_COORDS_IMPL     ; $46 MAP_COORDS
        .addr   L78E1               ; $47
        .addr   QUERY_CLIENT_IMPL   ; $48 QUERY_CLIENT
        .addr   RESIZE_WINDOW_IMPL  ; $49 RESIZE_WINDOW
        .addr   DRAG_SCROLL_IMPL    ; $4A DRAG_SCROLL
        .addr   UPDATE_SCROLL_IMPL  ; $4B UPDATE_SCROLL
        .addr   L7965               ; $4C
        .addr   L51B3               ; $4D
        .addr   L7D69               ; $4E

        ;; Entry point param lengths
        ;; (length, ZP destination, hide cursor flag)
param_lengths:

.macro PARAM_DEFN length, zp, cursor
        .byte zp, ((length) | ((cursor) << 7))
.endmacro

        PARAM_DEFN  0, $00, 0           ; $00
        PARAM_DEFN  0, $00, 0           ; $01
        PARAM_DEFN  1, $82, 0           ; $02
        PARAM_DEFN  0, $00, 0           ; $03 QUERY_SCREEN
        PARAM_DEFN 36, state, 0         ; $04 SET_STATE
        PARAM_DEFN  0, $00, 0           ; $05 GET_STATE
        PARAM_DEFN 16, state_box, 0     ; $06 SET_BOX
        PARAM_DEFN  1, state_fill, 0    ; $07 SET_FILL_MODE
        PARAM_DEFN  8, state_pattern, 0 ; $08 SET_PATTERN
        PARAM_DEFN  2, state_msk, 0     ; $09
        PARAM_DEFN  2, state_thick, 0   ; $0A SET_THICKNESS
        PARAM_DEFN  0, $00, 0           ; $0B
        PARAM_DEFN  1, state_tmask, 0   ; $0C SET_TEXT_MASK
        PARAM_DEFN  4, $A1, 0           ; $0D
        PARAM_DEFN  4, state_pos, 0     ; $0E SET_POS
        PARAM_DEFN  4, $A1, 1           ; $0F DRAW_LINE
        PARAM_DEFN  4, $92, 1           ; $10 DRAW_LINE_ABS
        PARAM_DEFN  8, $92, 1           ; $11 FILL_RECT
        PARAM_DEFN  8, $9F, 1           ; $12 DRAW_RECT
        PARAM_DEFN  8, $92, 0           ; $13 TEST_BOX
        PARAM_DEFN 16, $8A, 0           ; $14 DRAW_BITMAP
        PARAM_DEFN  0, $00, 1           ; $15
        PARAM_DEFN  0, $00, 1           ; $16 DRAW_POLYGONS
        PARAM_DEFN  0, $00, 0           ; $17
        PARAM_DEFN  3, $A1, 0           ; $18 MEASURE_TEXT
        PARAM_DEFN  3, $A1, 1           ; $19 DRAW_TEXT
        PARAM_DEFN  1, $82, 0           ; $1A CONFIGURE_ZP_USE
        PARAM_DEFN  1, $82, 0           ; $1B
        PARAM_DEFN  0, $00, 0           ; $1C
        PARAM_DEFN 12, $82, 0           ; $1D
        PARAM_DEFN  0, $00, 0           ; $1E
        PARAM_DEFN  3, $82, 0           ; $1F
        PARAM_DEFN  2, $82, 0           ; $20
        PARAM_DEFN  2, $82, 0           ; $21
        PARAM_DEFN  1, $82, 0           ; $22
        PARAM_DEFN  0, $00, 0           ; $23
        PARAM_DEFN  0, $00, 0           ; $24 SET_CURSOR
        PARAM_DEFN  0, $00, 0           ; $25 SHOW_CURSOR
        PARAM_DEFN  0, $00, 0           ; $26 HIDE_CURSOR
        PARAM_DEFN  0, $00, 0           ; $27 ERASE_CURSOR
        PARAM_DEFN  0, $00, 0           ; $28 GET_CURSOR
        PARAM_DEFN  0, $00, 0           ; $29
        PARAM_DEFN  0, $00, 0           ; $2A GET_INPUT
        PARAM_DEFN  0, $00, 0           ; $2B
        PARAM_DEFN  0, $00, 0           ; $2C
        PARAM_DEFN  5, $82, 0           ; $2D SET_INPUT
        PARAM_DEFN  1, $82, 0           ; $2E
        PARAM_DEFN  4, $82, 0           ; $2F
        PARAM_DEFN  0, $00, 0           ; $30 SET_MENU
        PARAM_DEFN  0, $00, 0           ; $31 MENU_CLICK
        PARAM_DEFN  4, $C7, 0           ; $32
        PARAM_DEFN  1, $C7, 0           ; $33
        PARAM_DEFN  2, $C7, 0           ; $34
        PARAM_DEFN  3, $C7, 0           ; $35
        PARAM_DEFN  3, $C7, 0           ; $36
        PARAM_DEFN  4, $C7, 0           ; $37
        PARAM_DEFN  0, $00, 0           ; $38 CREATE_WINDOW
        PARAM_DEFN  1, $82, 0           ; $39 DESTROY_WINDOW
        PARAM_DEFN  0, $00, 0           ; $3A
        PARAM_DEFN  1, $82, 0           ; $3B QUERY_WINDOW
        PARAM_DEFN  3, $82, 0           ; $3C QUERY_STATE
        PARAM_DEFN  2, $82, 0           ; $3D UPDATE_STATE
        PARAM_DEFN  1, $82, 0           ; $3E REDRAW_WINDOW
        PARAM_DEFN  1, $82, 0           ; $3F
        PARAM_DEFN  4, state_pos, 0     ; $40 QUERY_TARGET
        PARAM_DEFN  0, $00, 0           ; $41
        PARAM_DEFN  1, $82, 0           ; $42 RAISE_WINDOW
        PARAM_DEFN  0, $00, 0           ; $43 CLOSE_CLICK
        PARAM_DEFN  5, $82, 0           ; $44 DRAG_WINDOW
        PARAM_DEFN  5, $82, 0           ; $45 DRAG_RESIZE
        PARAM_DEFN  5, $82, 0           ; $46 MAP_COORDS
        PARAM_DEFN  5, $82, 0           ; $47
        PARAM_DEFN  4, state_pos, 0     ; $48 QUERY_CLIENT
        PARAM_DEFN  3, $82, 0           ; $49 RESIZE_WINDOW
        PARAM_DEFN  5, $82, 0           ; $4A DRAG_SCROLL
        PARAM_DEFN  3, $8C, 0           ; $4B UPDATE_SCROLL
        PARAM_DEFN  2, $8C, 0           ; $4C
        PARAM_DEFN 16, $8A, 0           ; $4D
        PARAM_DEFN  2, $82, 0           ; $4E

;;; ==================================================

        ;; ???
L4221:  .byte   $00,$02,$04,$06,$08,$0A,$0C,$0E
        .byte   $10,$12,$14,$16,$18,$1A,$1C,$1E
        .byte   $20,$22,$24,$26,$28,$2A,$2C,$2E
        .byte   $30,$32,$34,$36,$38,$3A,$3C,$3E
        .byte   $40,$42,$44,$46,$48,$4A,$4C,$4E
        .byte   $50,$52,$54,$56,$58,$5A,$5C,$5E
        .byte   $60,$62,$64,$66,$68,$6A,$6C,$6E
        .byte   $70,$72,$74,$76,$78,$7A,$7C,$7E
        .byte   $00,$02,$04,$06,$08,$0A,$0C,$0E
        .byte   $10,$12,$14,$16,$18,$1A,$1C,$1E
        .byte   $20,$22,$24,$26,$28,$2A,$2C,$2E
        .byte   $30,$32,$34,$36,$38,$3A,$3C,$3E
        .byte   $40,$42,$44,$46,$48,$4A,$4C,$4E
        .byte   $50,$52,$54,$56,$58,$5A,$5C,$5E
        .byte   $60,$62,$64,$66,$68,$6A,$6C,$6E
        .byte   $70,$72,$74,$76,$78,$7A,$7C,$7E

L42A1:  .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $01,$01,$01,$01,$01,$01,$01,$01
        .byte   $01,$01,$01,$01,$01,$01,$01,$01
        .byte   $01,$01,$01,$01,$01,$01,$01,$01
        .byte   $01,$01,$01,$01,$01,$01,$01,$01
        .byte   $01,$01,$01,$01,$01,$01,$01,$01
        .byte   $01,$01,$01,$01,$01,$01,$01,$01
        .byte   $01,$01,$01,$01,$01,$01,$01,$01
        .byte   $01,$01,$01,$01,$01,$01,$01,$01

L4321:  .byte   $00,$04,$08,$0C,$10,$14,$18,$1C
        .byte   $20,$24,$28,$2C,$30,$34,$38,$3C
        .byte   $40,$44,$48,$4C,$50,$54,$58,$5C
        .byte   $60,$64,$68,$6C,$70,$74,$78,$7C
        .byte   $00,$04,$08,$0C,$10,$14,$18,$1C
        .byte   $20,$24,$28,$2C,$30,$34,$38,$3C
        .byte   $40,$44,$48,$4C,$50,$54,$58,$5C
        .byte   $60,$64,$68,$6C,$70,$74,$78,$7C
        .byte   $00,$04,$08,$0C,$10,$14,$18,$1C
        .byte   $20,$24,$28,$2C,$30,$34,$38,$3C
        .byte   $40,$44,$48,$4C,$50,$54,$58,$5C
        .byte   $60,$64,$68,$6C,$70,$74,$78,$7C
        .byte   $00,$04,$08,$0C,$10,$14,$18,$1C
        .byte   $20,$24,$28,$2C,$30,$34,$38,$3C
        .byte   $40,$44,$48,$4C,$50,$54,$58,$5C
        .byte   $60,$64,$68,$6C,$70,$74,$78,$7C

L43A1:  .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $01,$01,$01,$01,$01,$01,$01,$01
        .byte   $01,$01,$01,$01,$01,$01,$01,$01
        .byte   $01,$01,$01,$01,$01,$01,$01,$01
        .byte   $01,$01,$01,$01,$01,$01,$01,$01
        .byte   $02,$02,$02,$02,$02,$02,$02,$02
        .byte   $02,$02,$02,$02,$02,$02,$02,$02
        .byte   $02,$02,$02,$02,$02,$02,$02,$02
        .byte   $02,$02,$02,$02,$02,$02,$02,$02
        .byte   $03,$03,$03,$03,$03,$03,$03,$03
        .byte   $03,$03,$03,$03,$03,$03,$03,$03
        .byte   $03,$03,$03,$03,$03,$03,$03,$03
        .byte   $03,$03,$03,$03,$03,$03,$03,$03

L4421:  .byte   $00,$08,$10,$18,$20,$28,$30,$38
        .byte   $40,$48,$50,$58,$60,$68,$70,$78
        .byte   $00,$08,$10,$18,$20,$28,$30,$38
        .byte   $40,$48,$50,$58,$60,$68,$70,$78
        .byte   $00,$08,$10,$18,$20,$28,$30,$38
        .byte   $40,$48,$50,$58,$60,$68,$70,$78
        .byte   $00,$08,$10,$18,$20,$28,$30,$38
        .byte   $40,$48,$50,$58,$60,$68,$70,$78
        .byte   $00,$08,$10,$18,$20,$28,$30,$38
        .byte   $40,$48,$50,$58,$60,$68,$70,$78
        .byte   $00,$08,$10,$18,$20,$28,$30,$38
        .byte   $40,$48,$50,$58,$60,$68,$70,$78
        .byte   $00,$08,$10,$18,$20,$28,$30,$38
        .byte   $40,$48,$50,$58,$60,$68,$70,$78
        .byte   $00,$08,$10,$18,$20,$28,$30,$38
        .byte   $40,$48,$50,$58,$60,$68,$70,$78

L44A1:  .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $01,$01,$01,$01,$01,$01,$01,$01
        .byte   $01,$01,$01,$01,$01,$01,$01,$01
        .byte   $02,$02,$02,$02,$02,$02,$02,$02
        .byte   $02,$02,$02,$02,$02,$02,$02,$02
        .byte   $03,$03,$03,$03,$03,$03,$03,$03
        .byte   $03,$03,$03,$03,$03,$03,$03,$03
        .byte   $04,$04,$04,$04,$04,$04,$04,$04
        .byte   $04,$04,$04,$04,$04,$04,$04,$04
        .byte   $05,$05,$05,$05,$05,$05,$05,$05
        .byte   $05,$05,$05,$05,$05,$05,$05,$05
        .byte   $06,$06,$06,$06,$06,$06,$06,$06
        .byte   $06,$06,$06,$06,$06,$06,$06,$06
        .byte   $07,$07,$07,$07,$07,$07,$07,$07
        .byte   $07,$07,$07,$07,$07,$07,$07,$07

L4521:  .byte   $00,$10,$20,$30,$40,$50,$60,$70
        .byte   $00,$10,$20,$30,$40,$50,$60,$70
        .byte   $00,$10,$20,$30,$40,$50,$60,$70
        .byte   $00,$10,$20,$30,$40,$50,$60,$70
        .byte   $00,$10,$20,$30,$40,$50,$60,$70
        .byte   $00,$10,$20,$30,$40,$50,$60,$70
        .byte   $00,$10,$20,$30,$40,$50,$60,$70
        .byte   $00,$10,$20,$30,$40,$50,$60,$70
        .byte   $00,$10,$20,$30,$40,$50,$60,$70
        .byte   $00,$10,$20,$30,$40,$50,$60,$70
        .byte   $00,$10,$20,$30,$40,$50,$60,$70
        .byte   $00,$10,$20,$30,$40,$50,$60,$70
        .byte   $00,$10,$20,$30,$40,$50,$60,$70
        .byte   $00,$10,$20,$30,$40,$50,$60,$70
        .byte   $00,$10,$20,$30,$40,$50,$60,$70
        .byte   $00,$10,$20,$30,$40,$50,$60,$70

L45A1:  .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $01,$01,$01,$01,$01,$01,$01,$01
        .byte   $02,$02,$02,$02,$02,$02,$02,$02
        .byte   $03,$03,$03,$03,$03,$03,$03,$03
        .byte   $04,$04,$04,$04,$04,$04,$04,$04
        .byte   $05,$05,$05,$05,$05,$05,$05,$05
        .byte   $06,$06,$06,$06,$06,$06,$06,$06
        .byte   $07,$07,$07,$07,$07,$07,$07,$07
        .byte   $08,$08,$08,$08,$08,$08,$08,$08
        .byte   $09,$09,$09,$09,$09,$09,$09,$09
        .byte   $0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A
        .byte   $0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B
        .byte   $0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C
        .byte   $0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D
        .byte   $0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E
        .byte   $0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F

L4621:  .byte   $00,$20,$40,$60,$00,$20,$40,$60
        .byte   $00,$20,$40,$60,$00,$20,$40,$60
        .byte   $00,$20,$40,$60,$00,$20,$40,$60
        .byte   $00,$20,$40,$60,$00,$20,$40,$60
        .byte   $00,$20,$40,$60,$00,$20,$40,$60
        .byte   $00,$20,$40,$60,$00,$20,$40,$60
        .byte   $00,$20,$40,$60,$00,$20,$40,$60
        .byte   $00,$20,$40,$60,$00,$20,$40,$60
        .byte   $00,$20,$40,$60,$00,$20,$40,$60
        .byte   $00,$20,$40,$60,$00,$20,$40,$60
        .byte   $00,$20,$40,$60,$00,$20,$40,$60
        .byte   $00,$20,$40,$60,$00,$20,$40,$60
        .byte   $00,$20,$40,$60,$00,$20,$40,$60
        .byte   $00,$20,$40,$60,$00,$20,$40,$60
        .byte   $00,$20,$40,$60,$00,$20,$40,$60
        .byte   $00,$20,$40,$60,$00,$20,$40,$60

L46A1:  .byte   $00,$00,$00,$00,$01,$01,$01,$01
        .byte   $02,$02,$02,$02,$03,$03,$03,$03
        .byte   $04,$04,$04,$04,$05,$05,$05,$05
        .byte   $06,$06,$06,$06,$07,$07,$07,$07
        .byte   $08,$08,$08,$08,$09,$09,$09,$09
        .byte   $0A,$0A,$0A,$0A,$0B,$0B,$0B,$0B
        .byte   $0C,$0C,$0C,$0C,$0D,$0D,$0D,$0D
        .byte   $0E,$0E,$0E,$0E,$0F,$0F,$0F,$0F
        .byte   $10,$10,$10,$10,$11,$11,$11,$11
        .byte   $12,$12,$12,$12,$13,$13,$13,$13
        .byte   $14,$14,$14,$14,$15,$15,$15,$15
        .byte   $16,$16,$16,$16,$17,$17,$17,$17
        .byte   $18,$18,$18,$18,$19,$19,$19,$19
        .byte   $1A,$1A,$1A,$1A,$1B,$1B,$1B,$1B
        .byte   $1C,$1C,$1C,$1C,$1D,$1D,$1D,$1D
        .byte   $1E,$1E,$1E,$1E,$1F,$1F,$1F,$1F

L4721:  .byte   $00,$40,$00,$40,$00,$40,$00,$40
        .byte   $00,$40,$00,$40,$00,$40,$00,$40
        .byte   $00,$40,$00,$40,$00,$40,$00,$40
        .byte   $00,$40,$00,$40,$00,$40,$00,$40
        .byte   $00,$40,$00,$40,$00,$40,$00,$40
        .byte   $00,$40,$00,$40,$00,$40,$00,$40
        .byte   $00,$40,$00,$40,$00,$40,$00,$40
        .byte   $00,$40,$00,$40,$00,$40,$00,$40
        .byte   $00,$40,$00,$40,$00,$40,$00,$40
        .byte   $00,$40,$00,$40,$00,$40,$00,$40
        .byte   $00,$40,$00,$40,$00,$40,$00,$40
        .byte   $00,$40,$00,$40,$00,$40,$00,$40
        .byte   $00,$40,$00,$40,$00,$40,$00,$40
        .byte   $00,$40,$00,$40,$00,$40,$00,$40
        .byte   $00,$40,$00,$40,$00,$40,$00,$40
        .byte   $00,$40,$00,$40,$00,$40,$00,$40

L47A1:  .byte   $00,$00,$01,$01,$02,$02,$03,$03
        .byte   $04,$04,$05,$05,$06,$06,$07,$07
        .byte   $08,$08,$09,$09,$0A,$0A,$0B,$0B
        .byte   $0C,$0C,$0D,$0D,$0E,$0E,$0F,$0F
        .byte   $10,$10,$11,$11,$12,$12,$13,$13
        .byte   $14,$14,$15,$15,$16,$16,$17,$17
        .byte   $18,$18,$19,$19,$1A,$1A,$1B,$1B
        .byte   $1C,$1C,$1D,$1D,$1E,$1E,$1F,$1F
        .byte   $20,$20,$21,$21,$22,$22,$23,$23
        .byte   $24,$24,$25,$25,$26,$26,$27,$27
        .byte   $28,$28,$29,$29,$2A,$2A,$2B,$2B
        .byte   $2C,$2C,$2D,$2D,$2E,$2E,$2F,$2F
        .byte   $30,$30,$31,$31,$32,$32,$33,$33
        .byte   $34,$34,$35,$35,$36,$36,$37,$37
        .byte   $38,$38,$39,$39,$3A,$3A,$3B,$3B
        .byte   $3C,$3C,$3D,$3D,$3E,$3E,$3F,$3F

L4821:  .byte   $00,$00,$00,$00
L4825:  .byte   $00,$00,$00

L4828:  .byte   $01,$01,$01,$01,$01,$01,$01,$02
        .byte   $02,$02,$02,$02,$02,$02,$03,$03
        .byte   $03,$03,$03,$03,$03,$04,$04,$04
        .byte   $04,$04,$04,$04,$05,$05,$05,$05
        .byte   $05,$05,$05,$06,$06,$06,$06,$06
        .byte   $06,$06,$07,$07,$07,$07,$07,$07
        .byte   $07,$08,$08,$08,$08,$08,$08,$08
        .byte   $09,$09,$09,$09,$09,$09,$09,$0A
        .byte   $0A,$0A,$0A,$0A,$0A,$0A,$0B,$0B
        .byte   $0B,$0B,$0B,$0B,$0B,$0C,$0C,$0C
        .byte   $0C,$0C,$0C,$0C,$0D,$0D,$0D,$0D
        .byte   $0D,$0D,$0D,$0E,$0E,$0E,$0E,$0E
        .byte   $0E,$0E,$0F,$0F,$0F,$0F,$0F,$0F
        .byte   $0F,$10,$10,$10,$10,$10,$10,$10
        .byte   $11,$11,$11,$11,$11,$11,$11,$12
        .byte   $12,$12,$12,$12,$12,$12,$13,$13
        .byte   $13,$13,$13,$13,$13,$14,$14,$14
        .byte   $14,$14,$14,$14,$15,$15,$15,$15
        .byte   $15,$15,$15,$16,$16,$16,$16,$16
        .byte   $16,$16,$17,$17,$17,$17,$17,$17
        .byte   $17,$18,$18,$18,$18,$18,$18,$18
        .byte   $19,$19,$19,$19,$19,$19,$19,$1A
        .byte   $1A,$1A,$1A,$1A,$1A,$1A,$1B,$1B
        .byte   $1B,$1B,$1B,$1B,$1B,$1C,$1C,$1C
        .byte   $1C,$1C,$1C,$1C,$1D,$1D,$1D,$1D
        .byte   $1D,$1D,$1D,$1E,$1E,$1E,$1E,$1E
        .byte   $1E,$1E,$1F,$1F,$1F,$1F,$1F,$1F
        .byte   $1F,$20,$20,$20,$20,$20,$20,$20
        .byte   $21,$21,$21,$21,$21,$21,$21,$22
        .byte   $22,$22,$22,$22,$22,$22,$23,$23
        .byte   $23,$23,$23,$23,$23,$24,$24,$24
        .byte   $24
L4921:  .byte   $00,$01,$02,$03
L4925:  .byte   $04,$05,$06,$00,$01,$02,$03,$04
        .byte   $05,$06,$00,$01,$02,$03,$04,$05
        .byte   $06,$00,$01,$02,$03,$04,$05,$06
        .byte   $00,$01,$02,$03,$04,$05,$06,$00
        .byte   $01,$02,$03,$04,$05,$06,$00,$01
        .byte   $02,$03,$04,$05,$06,$00,$01,$02
        .byte   $03,$04,$05,$06,$00,$01,$02,$03
        .byte   $04,$05,$06,$00,$01,$02,$03,$04
        .byte   $05,$06,$00,$01,$02,$03,$04,$05
        .byte   $06,$00,$01,$02,$03,$04,$05,$06
        .byte   $00,$01,$02,$03,$04,$05,$06,$00
        .byte   $01,$02,$03,$04,$05,$06,$00,$01
        .byte   $02,$03,$04,$05,$06,$00,$01,$02
        .byte   $03,$04,$05,$06,$00,$01,$02,$03
        .byte   $04,$05,$06,$00,$01,$02,$03,$04
L499D:  .byte   $05,$06,$00,$01,$02,$03,$04,$05
        .byte   $06,$00,$01,$02,$03,$04,$05,$06
        .byte   $00,$01,$02,$03,$04,$05,$06,$00
        .byte   $01,$02,$03,$04,$05,$06,$00,$01
        .byte   $02,$03,$04,$05,$06,$00,$01,$02
        .byte   $03,$04,$05,$06,$00,$01,$02,$03
        .byte   $04,$05,$06,$00,$01,$02,$03,$04
        .byte   $05,$06,$00,$01,$02,$03,$04,$05
        .byte   $06,$00,$01,$02,$03,$04,$05,$06
        .byte   $00,$01,$02,$03,$04,$05,$06,$00
        .byte   $01,$02,$03,$04,$05,$06,$00,$01
        .byte   $02,$03,$04,$05,$06,$00,$01,$02
        .byte   $03,$04,$05,$06,$00,$01,$02,$03
        .byte   $04,$05,$06,$00,$01,$02,$03,$04
        .byte   $05,$06,$00,$01,$02,$03,$04,$05
        .byte   $06,$00,$01,$02,$03,$04,$05,$06
        .byte   $00,$01,$02,$03

;;; ==================================================

hires_table_lo:
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $80,$80,$80,$80,$80,$80,$80,$80
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $80,$80,$80,$80,$80,$80,$80,$80
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $80,$80,$80,$80,$80,$80,$80,$80
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $80,$80,$80,$80,$80,$80,$80,$80
        .byte   $28,$28,$28,$28,$28,$28,$28,$28
        .byte   $A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8
        .byte   $28,$28,$28,$28,$28,$28,$28,$28
        .byte   $A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8
        .byte   $28,$28,$28,$28,$28,$28,$28,$28
        .byte   $A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8
        .byte   $28,$28,$28,$28,$28,$28,$28,$28
        .byte   $A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8
        .byte   $50,$50,$50,$50,$50,$50,$50,$50
        .byte   $D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0
        .byte   $50,$50,$50,$50,$50,$50,$50,$50
        .byte   $D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0
        .byte   $50,$50,$50,$50,$50,$50,$50,$50
        .byte   $D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0
        .byte   $50,$50,$50,$50,$50,$50,$50,$50
        .byte   $D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0

hires_table_hi:
        .byte   $00,$04,$08,$0C,$10,$14,$18,$1C
        .byte   $00,$04,$08,$0C,$10,$14,$18,$1C
        .byte   $01,$05,$09,$0D,$11,$15,$19,$1D
        .byte   $01,$05,$09,$0D,$11,$15,$19,$1D
        .byte   $02,$06,$0A,$0E,$12,$16,$1A,$1E
        .byte   $02,$06,$0A,$0E,$12,$16,$1A,$1E
        .byte   $03,$07,$0B,$0F,$13,$17,$1B,$1F
        .byte   $03,$07,$0B,$0F,$13,$17,$1B,$1F
        .byte   $00,$04,$08,$0C,$10,$14,$18,$1C
        .byte   $00,$04,$08,$0C,$10,$14,$18,$1C
        .byte   $01,$05,$09,$0D,$11,$15,$19,$1D
        .byte   $01,$05,$09,$0D,$11,$15,$19,$1D
        .byte   $02,$06,$0A,$0E,$12,$16,$1A,$1E
        .byte   $02,$06,$0A,$0E,$12,$16,$1A,$1E
        .byte   $03,$07,$0B,$0F,$13,$17,$1B,$1F
        .byte   $03,$07,$0B,$0F,$13,$17,$1B,$1F
        .byte   $00,$04,$08,$0C,$10,$14,$18,$1C
        .byte   $00,$04,$08,$0C,$10,$14,$18,$1C
        .byte   $01,$05,$09,$0D,$11,$15,$19,$1D
        .byte   $01,$05,$09,$0D,$11,$15,$19,$1D
        .byte   $02,$06,$0A,$0E,$12,$16,$1A,$1E
        .byte   $02,$06,$0A,$0E,$12,$16,$1A,$1E
        .byte   $03,$07,$0B,$0F,$13,$17,$1B,$1F
        .byte   $03,$07,$0B,$0F,$13,$17,$1B,$1F

;;; ==================================================
;;; Routines called during FILL_RECT etc based on
;;; state_fill

.proc fillmode0
        lda     ($84),y
        eor     ($8E),y
        eor     fill_eor_mask
        and     $89
        eor     ($84),y
        bcc     :+
loop:   lda     ($8E),y
        eor     fill_eor_mask
:       and     state_mskand
        ora     state_mskor
        sta     ($84),y
        dey
        bne     loop
.endproc
.proc fillmode0a
        lda     ($84),y
        eor     ($8E),y
        eor     fill_eor_mask
        and     $88
        eor     ($84),y
        and     state_mskand
        ora     state_mskor
        sta     ($84),y
        rts
.endproc

.proc fillmode1
        lda     ($8E),y
        eor     fill_eor_mask
        and     $89
        bcc     :+
loop:   lda     ($8E),y
        eor     fill_eor_mask
:       ora     ($84),y
        and     state_mskand
        ora     state_mskor
        sta     ($84),y
        dey
        bne     loop
.endproc
.proc fillmode1a
        lda     ($8E),y
        eor     fill_eor_mask
        and     $88
        ora     ($84),y
        and     state_mskand
        ora     state_mskor
        sta     ($84),y
        rts
.endproc

.proc fillmode2
        lda     ($8E),y
        eor     fill_eor_mask
        and     $89
        bcc     :+
loop:   lda     ($8E),y
        eor     fill_eor_mask
:       eor     ($84),y
        and     state_mskand
        ora     state_mskor
        sta     ($84),y
        dey
        bne     loop
.endproc
.proc fillmode2a
        lda     ($8E),y
        eor     fill_eor_mask
        and     $88
        eor     ($84),y
        and     state_mskand
        ora     state_mskor
        sta     ($84),y
        rts
.endproc

.proc fillmode3
        lda     ($8E),y
        eor     fill_eor_mask
        and     $89
        bcc     :+
loop:   lda     ($8E),y
        eor     fill_eor_mask
:       eor     #$FF
        and     ($84),y
        and     state_mskand
        ora     state_mskor
        sta     ($84),y
        dey
        bne     loop
.endproc
.proc fillmode3a
        lda     ($8E),y
        eor     fill_eor_mask
        and     $88
        eor     #$FF
        and     ($84),y
        and     state_mskand
        ora     state_mskor
        sta     ($84),y
        rts
.endproc

L4C41:  cpx     $98
        beq     L4C49
        inx
L4C46:
L4C47           := * + 1
L4C48           := * + 2
        jmp     L4CFB

L4C49:  rts

        lda     L4C5B
        adc     $90
        sta     L4C5B
        bcc     L4C57
        inc     L4C5C
L4C57:  ldy     L5168
L4C5A:
L4C5B           := * + 1
L4C5C           := * + 2
        lda     $FFFF,y
        and     #$7F
        sta     $0601,y
        dey
        bpl     L4C5A
        bmi     L4C9F
L4C67:  ldy     $8C
        inc     $8C
        lda     hires_table_hi,y
        ora     $80
        sta     $83
        lda     hires_table_lo,y
        adc     $8A
        sta     $82
L4C79:  stx     $81
        ldy     #0
        ldx     #0
L4C7F:  sta     HISCR
        lda     ($82),y
        and     #$7F
        sta     LOWSCR
L4C8A           := * + 1
        sta     $0601,x
        lda     ($82),y
        and     #$7F
L4C91           := * + 1
        sta     $0602,x
        iny
        inx
        inx
        cpx     L5168
        bcc     L4C7F
        beq     L4C7F
        ldx     $81
L4C9F:  clc
L4CA1           := * + 1
L4CA2           := * + 2
        jmp     L4CBE

L4CA3:  stx     $82
        ldy     L5168
        lda     #$00
L4CAA:  ldx     $0601,y
L4CAE           := * + 1
L4CAF           := * + 2
        ora     L42A1,x
L4CB1           := * + 1
        sta     $0602,y
L4CB4           := * + 1
L4CB5           := * + 2
        lda     L4221,x
        dey
        bpl     L4CAA
L4CBA           := * + 1
        sta     $0601
        ldx     $82
L4CBE:
L4CBF           := * + 1
L4CC0           := * + 2
        jmp     L4D38

L4CC1:  stx     $82
        ldx     #0
        ldy     #0
L4CC7:
L4CC8           := * + 1
        lda     $0601,x
        sta     HISCR
        sta     $0601,y
        sta     LOWSCR
L4CD4           := * + 1
        lda     $0602,x
        sta     $0601,y
        inx
        inx
        iny
        cpy     $91
        bcc     L4CC7
        beq     L4CC7
        ldx     $82
        jmp     L4D38

L4CE7:  ldx     $94
        clc
        jmp     L4C46

L4CED:  ldx     L4D6A
        stx     L4C47
        ldx     L4D6B
        stx     L4C48
        ldx     $94
L4CFB:
L4CFC           := * + 1
L4CFD           := * + 2
        jmp     L4D11

L4CFE:
        txa
        ror     a
        ror     a
        ror     a
        and     #$C0
        ora     $86
        sta     $82
        lda     #$04
        adc     #$00
        sta     $83
        jmp     L4C79

L4D11:  txa
        ror     a
        ror     a
        ror     a
        and     #$C0
        ora     $86
        sta     $8E
        lda     #$04
        adc     #0
        sta     $8F
L4D22           := * + 1
L4D23           := * + 2
        jmp     L4D38

L4D24:  lda     $84
        clc
        adc     state_stride
        sta     $84
        bcc     L4D30
        inc     $85
        clc
L4D30:  ldy     $91
        jsr     L4D67
        jmp     L4C41

L4D38:  lda     hires_table_hi,x
        ora     state_addr+1
        sta     $85
        lda     hires_table_lo,x
        clc
        adc     $86
        sta     $84
        ldy     #1
        jsr     L4D54
        ldy     #0
        jsr     L4D54
        jmp     L4C41

L4D54:  sta     LOWSCR,y
        lda     $92,y
        ora     #$80
        sta     $88
        lda     $96,y
        ora     #$80
        sta     $89
        ldy     $91
L4D67:  jmp     fillmode0       ; modified with fillmode routine

L4D6A:  .byte   $FB
L4D6B:
L4D6C           := * + 1
        jmp     $0000

        .byte   $00,$00,$00,$00,$00
L4D73:  .byte   $01,$03,$07,$0F,$1F,$3F,$7F
L4D7A:  .byte   $7F,$7F,$7F,$7F,$7F,$7F,$7F
L4D81:  .byte   $7F,$7E,$7C,$78,$70,$60,$40,$00
        .byte   $00,$00,$00,$00,$00,$00

        ;; Tables used for fill modes
fill_mode_table:
        .addr   fillmode0,fillmode1,fillmode2,fillmode3
        .addr   fillmode0,fillmode1,fillmode2,fillmode3

fill_mode_table_a:
        .addr   fillmode0a,fillmode1a,fillmode2a,fillmode3a
        .addr   fillmode0a,fillmode1a,fillmode2a,fillmode3a

;;; ==================================================

SET_FILL_MODE_IMPL:
        lda     state_fill
        ldx     #0
        cmp     #4
        bcc     :+
        ldx     #$7F
:       stx     fill_eor_mask
        rts

        ;; Called from FILL_RECT, DRAW_TEXT, etc to configure
        ;; fill routines from mode.
set_up_fill_mode:
        lda     $F7
        clc
        adc     $96
        sta     $96
        lda     $F8
        adc     $96+1
        sta     $96+1
        lda     $F8+1
        clc
        adc     $98
        sta     $98
        lda     $FA
        adc     $98+1
        sta     $98+1
        lda     $F7
        clc
        adc     $92
        sta     $92
        lda     $F8
        adc     $92+1
        sta     $92+1
        lda     $F8+1
        clc
        adc     $94
        sta     $94
        lda     $FA
        adc     $94+1
        sta     $94+1
        lsr     $97
        beq     :+
        jmp     L4E79

:       lda     $96
        ror     a
        tax
        lda     L4821,x
        ldy     L4921,x
L4E01:  sta     $82
        tya
        rol     a
        tay
        lda     L4D73,y
        sta     $97
        lda     L4D6C,y
        sta     $96
        lsr     $93
        bne     L4E68
        lda     $92
        ror     a
        tax
        lda     L4821,x
        ldy     L4921,x
L4E1E:  sta     $86
        tya
        rol     a
        tay
        sty     $87
        lda     L4D81,y
        sta     $93
        lda     L4D7A,y
        sta     $92
        lda     $82
        sec
        sbc     $86
L4E34:  sta     $91
        pha
        lda     state_fill
        asl     a
        tax
        pla
        bne     L4E5B
        lda     $93
        and     $97
        sta     $93
        sta     $97
        lda     $92
        and     $96
        sta     $92
        sta     $96
        lda     fill_mode_table_a,x
        sta     L4D67+1
        lda     fill_mode_table_a+1,x
        sta     L4D67+2
        rts

L4E5B:  lda     fill_mode_table,x
        sta     L4D67+1
        lda     fill_mode_table+1,x
        sta     L4D67+2
        rts

L4E68:  lda     $92
        ror     a
        tax
        php
        lda     L4825,x
        clc
        adc     #$24
        plp
        ldy     L4925,x
        bpl     L4E1E
L4E79:  lda     $96
        ror     a
        tax
        php
        lda     L4825,x
        clc
        adc     #$24
        plp
        ldy     L4925,x
        bmi     L4E8D
        jmp     L4E01

L4E8D:  lsr     a
        bne     L4E9A
        txa
        ror     a
        tax
        lda     L4821,x
        ldy     L4921,x
        rts

L4E9A:  txa
        ror     a
        tax
        php
        lda     L4825,x
        clc
        adc     #$24
        plp
        ldy     L4925,x
        rts

L4EA9:  lda     $86
        ldx     $94
        ldy     state_stride
        jsr     L4F6D
        clc
        adc     state_addr
        sta     $84
        tya
        adc     state_addr+1
        sta     $85
        lda     #$02
        tax
        tay
        bit     state_stride
        bmi     L4EE9
        lda     #$01
        sta     $8E
        lda     #$06
        sta     $8F
        jsr     L4F11
        txa
        inx
        stx     L5168
        jsr     L4E34
        lda     L4F31
        sta     L4CA1
        lda     L4F31+1
        sta     L4CA2
        lda     #0
        ldx     #0
        ldy     #0
L4EE9:  pha
        lda     L4F37,x
        sta     L4D22
        lda     L4F37+1,x
        sta     L4D23
        pla
        tax
        lda     L4F33,x
        sta     L4CFC
        lda     L4F33+1,x
        sta     L4CFD
        lda     L4F3B,y
        sta     L4CBF
        lda     L4F3B+1,y
        sta     L4CC0
        rts

L4F11:  lda     $91
        asl     a
        tax
        inx
        lda     $93
        bne     L4F25
        dex
        inc     $8E
        inc     $84
        bne     L4F23
        inc     $85
L4F23:  lda     $92
L4F25:  sta     $88
        lda     $96
        bne     L4F2E
        dex
        lda     $97
L4F2E:  sta     $89
        rts

L4F31:  .addr   L4CBE
L4F33:  .addr   L4CFE,L4D11
L4F37:  .addr   L4D24,L4D38
L4F3B:  .addr   L4D24,L4CC1

L4F3F:  ldx     $8C
        ldy     $90
        bmi     L4F48
        jsr     L4F70
L4F48:  clc
        adc     $8E
        sta     L4C5B
        tya
        adc     $8F
        sta     L4C5C
        ldx     #$02
        bit     $90
        bmi     L4F5C
        ldx     #$00
L4F5C:  lda     L4F69,x
        sta     L4C47
        lda     L4F6A,x
        sta     L4C48
        rts

L4F69:  lsr     a
L4F6A:  jmp     L4C67

L4F6D:  bmi     L4F8E
        asl     a
L4F70:  stx     $82
        sty     $83
        ldx     #$08
L4F76:  lsr     $83
        bcc     L4F7D
        clc
        adc     $82
L4F7D:  ror     a
        ror     $84
        dex
        bne     L4F76
        sty     $82
        tay
        lda     $84
        sec
        sbc     $82
        bcs     L4F8E
        dey
L4F8E:  rts

;;; ==================================================

SET_PATTERN_IMPL:
        lda     #$00
        sta     $8E
        lda     $F9
        and     #$07
        lsr     a
        ror     $8E
        lsr     a
        ror     $8E
        adc     #$04
        sta     $8F
        ldx     #$07
L4FA3:  lda     $F7
        and     #$07
        tay
        lda     state_pattern,x
L4FAA:  dey
        bmi     L4FB2
        cmp     #$80
        rol     a
        bne     L4FAA
L4FB2:  ldy     #$27
L4FB4:  pha
        lsr     a
        sta     LOWSCR
        sta     ($8E),y
        pla
        ror     a
        pha
        lsr     a
        sta     HISCR
        sta     ($8E),y
        pla
        ror     a
        dey
        bpl     L4FB4
        lda     $8E
        sec
        sbc     #$40
        sta     $8E
        bcs     L4FDD
        ldy     $8F
        dey
        cpy     #$04
        bcs     L4FDB
        ldy     #$05
L4FDB:  sty     $8F
L4FDD:  dex
        bpl     L4FA3
        sta     LOWSCR
        rts

;;; ==================================================

;;; 4 bytes of params, copied to $9F

L4FE4:  .byte   0

DRAW_RECT_IMPL:

        left   := $9F
        top    := $A1
        right  := $A3
        bottom := $A5

        ldy     #$03
L4FE7:  ldx     #$07
L4FE9:  lda     $9F,x
        sta     $92,x
        dex
        bpl     L4FE9
        ldx     L5016,y
        lda     $9F,x
        pha
        lda     $A0,x
        ldx     L501A,y
        sta     $93,x
        pla
        sta     $92,x
        sty     L4FE4
        jsr     L501E
        ldy     L4FE4
        dey
        bpl     L4FE7
        ldx     #$03
L500E:  lda     $9F,x
        sta     state_pos,x
        dex
        bpl     L500E
L5015:  rts

L5016:  .byte   $00,$02,$04,$06
L501A:  .byte   $04,$06,$00,$02

L501E:  lda     state_hthick    ; Also: draw horizontal line $92 to $96 at $98
        sec
        sbc     #1
        cmp     #$FF
        beq     L5015
        adc     $96
        sta     $96
        bcc     L502F
        inc     $96+1

L502F:  lda     state_vthick
        sec
        sbc     #1
        cmp     #$FF
        beq     L5015
        adc     $98
        sta     $98
        bcc     FILL_RECT_IMPL
        inc     $98+1
        ;; Fall through...

;;; ==================================================

;;; 4 bytes of params, copied to $92

FILL_RECT_IMPL:
        jsr     L514C
L5043:  jsr     L50A9
        bcc     L5015
        jsr     set_up_fill_mode
        jsr     L4EA9
        jmp     L4CED

;;; ==================================================

;;; 4 bytes of params, copied to $92

.proc TEST_BOX_IMPL

        left   := $92
        top    := $94
        right  := $96
        bottom := $98

        jsr     L514C
        lda     state_xpos
        ldx     state_xpos+1
        cpx     left+1
        bmi     fail
        bne     :+
        cmp     left
        bcc     fail
:       cpx     right+1
        bmi     :+
        bne     fail
        cmp     right
        bcc     :+
        bne     fail
:       lda     state_ypos
        ldx     state_ypos+1
        cpx     top+1
        bmi     fail
        bne     :+
        cmp     top
        bcc     fail
:       cpx     bottom+1
        bmi     :+
        bne     fail
        cmp     bottom
        bcc     :+
        bne     fail
:       lda     #$80            ; success!
        jmp     a2d_exit_with_a

fail:   rts
.endproc

;;; ==================================================

SET_BOX_IMPL:
        lda     state_left
        sec
        sbc     state_hoff
        sta     $F7
        lda     state_left+1
        sbc     state_hoff+1
        sta     $F8
        lda     state_top
        sec
        sbc     state_voff
        sta     $F9
        lda     state_top+1
        sbc     state_voff+1
        sta     $FA
        rts

L50A9:  lda     state_width+1
        cmp     $92+1
        bmi     L50B7
        bne     L50B9
        lda     state_width
        cmp     $92
        bcs     L50B9
L50B7:  clc
L50B8:  rts

L50B9:  lda     $96+1
        cmp     state_hoff+1
        bmi     L50B7
        bne     L50C7
        lda     $96
        cmp     state_hoff
        bcc     L50B8
L50C7:  lda     state_height+1
        cmp     $94+1
        bmi     L50B7
        bne     L50D5
        lda     state_height
        cmp     $94
        bcc     L50B8
L50D5:  lda     $98+1
        cmp     state_voff+1
        bmi     L50B7
        bne     L50E3
        lda     $98
        cmp     state_voff
        bcc     L50B8
L50E3:  ldy     #$00
        lda     $92
        sec
        sbc     state_hoff
        tax
        lda     $92+1
        sbc     state_hoff+1
        bpl     L50FE
        stx     $9B
        sta     $9C
        lda     state_hoff
        sta     $92
        lda     state_hoff+1
        sta     $92+1
        iny
L50FE:  lda     state_width
        sec
        sbc     $96
        tax
        lda     state_width+1
        sbc     $96+1
        bpl     L5116
        lda     state_width
        sta     $96
        lda     state_width+1
        sta     $96+1
        tya
        ora     #$04
        tay
L5116:  lda     $94
        sec
        sbc     state_voff
        tax
        lda     $94+1
        sbc     state_voff+1
        bpl     L5130
        stx     $9D
        sta     $9E
        lda     state_voff
        sta     $94
        lda     state_voff+1
        sta     $94+1
        iny
        iny
L5130:  lda     state_height
        sec
        sbc     $98
        tax
        lda     state_height+1
        sbc     $98+1
        bpl     L5148
        lda     state_height
        sta     $98
        lda     state_height+1
        sta     $98+1
        tya
        ora     #$08
        tay
L5148:  sty     $9A
        sec
        rts

L514C:  sec
        lda     $96
        sbc     $92
        lda     $96+1
        sbc     $92+1
        bmi     L5163
        sec
        lda     $98
        sbc     $94
        lda     $98+1
        sbc     $94+1
        bmi     L5163
        rts

L5163:  lda     #$81
        jmp     a2d_exit_with_a

;;; ==================================================

;;; 16 bytes of params, copied to $8A

L5168:  .byte   0
L5169:  .byte   0

DRAW_BITMAP_IMPL:

        dbi_left   := $8A
        dbi_top    := $8C
        dbi_bitmap := $8E
        dbi_stride := $90
        dbi_hoff   := $92
        dbi_voff   := $94
        dbi_width  := $96
        dbi_height := $98

        dbi_x      := $9B
        dbi_y      := $9D

        ldx     #3         ; copy left/top to $9B/$9D
:       lda     dbi_left,x ; and hoff/voff to $8A/$8C (overwriting left/top)
        sta     dbi_x,x
        lda     dbi_hoff,x
        sta     dbi_left,x
        dex
        bpl     :-

        lda     dbi_width
        sec
        sbc     dbi_hoff
        sta     $82
        lda     dbi_width+1
        sbc     dbi_hoff+1
        sta     $83
        lda     dbi_x
        sta     dbi_hoff

        clc
        adc     $82
        sta     dbi_width
        lda     dbi_x+1
        sta     dbi_hoff+1
        adc     $83
        sta     dbi_width+1

        lda     dbi_height
        sec
        sbc     dbi_voff
        sta     $82
        lda     dbi_height+1
        sbc     dbi_voff+1
        sta     $83
        lda     dbi_y
        sta     dbi_voff
        clc
        adc     $82
        sta     dbi_height
        lda     dbi_y+1
        sta     dbi_voff+1
        adc     $83
        sta     dbi_height+1
        ;; fall through

;;; ==================================================

;;; $4D IMPL

;;; 16 bytes of params, copied to $8A

L51B3:  lda     #0
        sta     $9B
        sta     $9C
        sta     $9D
        lda     $8F
        sta     $80
        jsr     L50A9
        bcs     L51C5
        rts

L51C5:  jsr     set_up_fill_mode
        lda     $91
        asl     a
        ldx     $93
        beq     L51D1
        adc     #1
L51D1:  ldx     $96
        beq     L51D7
        adc     #1
L51D7:  sta     L5169
        sta     L5168
        lda     #2
        sta     $81
        lda     #0
        sec
        sbc     $9D
        clc
        adc     $8C
        sta     $8C
        lda     #0
        sec
        sbc     $9B
        tax
        lda     #0
        sbc     $9C
        tay
        txa
        clc
        adc     $8A
        tax
        tya
        adc     $8B
        jsr     L4E8D
        sta     $8A
        tya
        rol     a
        cmp     #7
        ldx     #1
        bcc     L520E
        dex
        sbc     #7
L520E:  stx     L4C8A
        inx
        stx     L4C91
        sta     $9B
        lda     $8A
        rol     a
        jsr     L4F3F
        jsr     L4EA9
        lda     #$01
        sta     $8E
        lda     #$06
        sta     $8F
        ldx     #$01
        lda     $87
        sec
        sbc     #$07
        bcc     L5234
        sta     $87
        dex
L5234:  stx     L4CC8
        inx
        stx     L4CD4
        lda     $87
        sec
        sbc     $9B
        bcs     L5249
        adc     #7
        inc     L5168
        dec     $81
L5249:  tay
        bne     L5250
        ldx     #0
        beq     L5276
L5250:  tya
        asl     a
        tay
        lda     L5293,y
        sta     L4CAE
        lda     L5293+1,y
        sta     L4CAF
        lda     L5285+2,y
        sta     L4CB4
        lda     L5285+3,y
        sta     L4CB5
        ldy     $81
        sty     L4CB1
        dey
        sty     L4CBA
        ldx     #2
L5276:  lda     L5285,x
        sta     L4CA1
        lda     L5285+1,x
        sta     L4CA2
        jmp     L4CE7

L5285:  .addr   L4CBE,L4CA3

        .addr   L4221,L4321,L4421,L4521,L4621

L5293:  .addr   L4721,L42A1,L43A1,L44A1,L45A1,L46A1,L47A1


L52A1:  stx     $B0
        asl     a
        asl     a
        sta     $B3

        ldy     #3              ; Copy params_addr... to $92... and $96...
:       lda     (params_addr),y
        sta     $92,y
L52AE:  sta     $96,y
        dey
        bpl     :-

        lda     $94             ; y coord
        sta     $A7
        lda     $94+1
        sta     $A7+1
        ldy     #0
        stx     $AE
L52C0:  stx     $82
        lda     (params_addr),y
        sta     $0700,x
        pha
        iny
        lda     (params_addr),y
        sta     $073C,x
        tax
        pla
        iny
        cpx     $92+1
        bmi     L52DB
        bne     L52E1
        cmp     $92
        bcs     L52E1
L52DB:  sta     $92
        stx     $92+1
        bcc     L52EF
L52E1:  cpx     $96+1
        bmi     L52EF
        bne     L52EB
        cmp     $96
        bcc     L52EF
L52EB:  sta     $96
        stx     $96+1
L52EF:  ldx     $82
        lda     (params_addr),y
        sta     $0780,x
        pha
        iny
        lda     (params_addr),y
        sta     $07BC,x
        tax
        pla
        iny
        cpx     $94+1
        bmi     L530A
        bne     L5310
        cmp     $94
        bcs     L5310
L530A:  sta     $94
        stx     $94+1
        bcc     L531E
L5310:  cpx     $98+1
        bmi     L531E
        bne     L531A
        cmp     $98
        bcc     L531E
L531A:  sta     $98
        stx     $98+1
L531E:  cpx     $A8
        stx     $A8
        bmi     L5330
        bne     L532C
        cmp     $A7
        bcc     L5330
        beq     L5330
L532C:  ldx     $82
        stx     $AE
L5330:  sta     $A7
        ldx     $82
        inx
        cpx     #$3C
        beq     L5398
        cpy     $B3
        bcc     L52C0
        lda     $94
        cmp     $98
        bne     L5349
        lda     $94+1
        cmp     $98+1
        beq     L5398
L5349:  stx     $B3
        bit     $BA
        bpl     L5351
        sec
        rts

L5351:  jmp     L50A9

L5354:  lda     $B4
        bpl     L5379
        asl     a
        asl     a
        adc     params_addr
        sta     params_addr
        bcc     ora_2_param_bytes
        inc     params_addr+1


        ;; ORAs together first two bytes at (params_addr) and stores
        ;; in $B4, then advances params_addr
ora_2_param_bytes:
        ldy     #0
        lda     (params_addr),y
        iny
        ora     (params_addr),y
        sta     $B4
        inc     params_addr
        bne     :+
        inc     params_addr+1
:       inc     params_addr
        bne     :+
        inc     params_addr+1
:       ldy     #$80
L5379:  rts

;;; ==================================================

;;; $17 IMPL

L537A:
        lda     #$80
        bne     L5380

;;; ==================================================

;;; $15 IMPL

        ;; also called from the end of DRAW_LINE_ABS_IMPL

L537E:  lda     #$00
L5380:  sta     $BA
        ldx     #0
        stx     $AD
        jsr     ora_2_param_bytes
L5389:  jsr     L52A1
        bcs     L539D
        ldx     $B0
L5390:  jsr     L5354
        bmi     L5389
        jmp     L546F

L5398:  lda     #$82
        jmp     a2d_exit_with_a

L539D:  ldy     #1
        sty     $AF
        ldy     $AE
        cpy     $B0
        bne     L53A9
        ldy     $B3
L53A9:  dey
        sty     $AB
        php
L53AD:  sty     $AC
        iny
        cpy     $B3
        bne     L53B6
        ldy     $B0
L53B6:  sty     $AA
        cpy     $AE
        bne     L53BE
        dec     $AF
L53BE:  lda     $0780,y
        ldx     $07BC,y
        stx     $83
L53C6:  sty     $A9
        iny
        cpy     $B3
        bne     L53CF
        ldy     $B0
L53CF:  cmp     $0780,y
        bne     L53DB
        ldx     $07BC,y
        cpx     $83
        beq     L53C6
L53DB:  ldx     $AB
        sec
        sbc     $0780,x
        lda     $83
        sbc     $07BC,x
        bmi     L5448
        lda     $A9
        plp
        bmi     L53F8
        tay
        sta     $0680,x
        lda     $AA
        sta     $06BC,x
        bpl     L545D
L53F8:  ldx     $AD
        cpx     #$10
        bcs     L5398
        sta     $0468,x
        lda     $AA
        sta     $04A8,x
        ldy     $AB
        lda     $0680,y
        sta     $0469,x
        lda     $06BC,y
        sta     $04A9,x
        lda     $0780,y
        sta     $05E8,x
        sta     $05E9,x
        lda     $07BC,y
        sta     L5E01,x
        sta     L5E02,x
        lda     $0700,y
        sta     L5E32,x
        lda     $073C,y
        sta     L5E42,x
        ldy     $AC
        lda     $0700,y
        sta     L5E31,x
        lda     $073C,y
        sta     L5E41,x
        inx
        inx
        stx     $AD
        ldy     $A9
        bpl     L545D
L5448:  plp
        bmi     L5450
        lda     #$80
        sta     $0680,x
L5450:  ldy     $AA
        txa
        sta     $0680,y
        lda     $AC
        sta     $06BC,y
        lda     #$80
L545D:  php
        sty     $AB
        ldy     $A9
        bit     $AF
        bmi     L5469
        jmp     L53AD

L5469:  plp
        ldx     $B3
        jmp     L5390

L546F:  ldx     #$00
        stx     $B1
        lda     #$80
        sta     $0428
        sta     $B2
L547A:  inx
        cpx     $AD
        bcc     L5482
        beq     L54B2
        rts

L5482:  lda     $B1
L5484:  tay
        lda     $05E8,x
        cmp     $05E8,y
        bcs     L54A2
        tya
        sta     $0428,x
        cpy     $B1
        beq     L549E
        ldy     $82
        txa
        sta     $0428,y
        jmp     L547A

L549E:  stx     $B1
        bcs     L547A
L54A2:  sty     $82
        lda     $0428,y
        bpl     L5484
        sta     $0428,x
        txa
        sta     $0428,y
        bpl     L547A
L54B2:  ldx     $B1
        lda     $05E8,x
        sta     $A9
        sta     $94
        lda     L5E01,x
        sta     $AA
        sta     $95
L54C2:  ldx     $B1
        bmi     L5534
L54C6:  lda     $05E8,x
        cmp     $A9
        bne     L5532
        lda     L5E01,x
        cmp     $AA
        bne     L5532
        lda     $0428,x
        sta     $82
        jsr     L5606
        lda     $B2
        bmi     L5517
L54E0:  tay
        lda     L5E41,x
        cmp     L5E41,y
        bmi     L5520
        bne     L5507
        lda     L5E31,x
        cmp     L5E31,y
        bcc     L5520
        bne     L5507
        lda     L5E11,x
        cmp     L5E11,y
        bcc     L5520
        bne     L5507
        lda     L5E21,x
        cmp     L5E21,y
        bcc     L5520
L5507:  sty     $83
        lda     $0428,y
        bpl     L54E0
        sta     $0428,x
        txa
        sta     $0428,y
        bpl     L552E
L5517:  sta     $0428,x
        stx     $B2
        jmp     L552E

L551F:  rts

L5520:  tya
        cpy     $B2
        beq     L5517
        sta     $0428,x
        txa
        ldy     $83
        sta     $0428,y
L552E:  ldx     $82
        bpl     L54C6
L5532:  stx     $B1
L5534:  lda     #$00
        sta     $AB
        lda     $B2
        sta     $83
        bmi     L551F
L553E:  tax
        lda     $A9
        cmp     $05E8,x
        bne     L5584
        lda     $AA
        cmp     L5E01,x
        bne     L5584
        ldy     $0468,x
        lda     $0680,y
        bpl     L556C
        cpx     $B2
        beq     L5564
        ldy     $83
        lda     $0428,x
        sta     $0428,y
        jmp     L55F8

L5564:  lda     $0428,x
        sta     $B2
        jmp     L55F8

L556C:  sta     $0468,x
        lda     $0700,y
        sta     L5E31,x
        lda     $073C,y
        sta     L5E41,x
        lda     $06BC,y
        sta     $04A8,x
        jsr     L5606
L5584:  stx     $AC
        ldy     L5E41,x
        lda     L5E31,x
        tax
        lda     $AB
        eor     #$FF
        sta     $AB
        bpl     L559B
        stx     $92
        sty     $93
        bmi     L55CE
L559B:  stx     $96
        sty     $97
        cpy     $93
        bmi     L55A9
        bne     L55B5
        cpx     $92
        bcs     L55B5
L55A9:  lda     $92
        stx     $92
        sta     $96
        lda     $93
        sty     $93
        sta     $97
L55B5:  lda     $A9
        sta     $94
        sta     $98
        lda     $AA
        sta     $95
        sta     $99
        bit     $BA
        bpl     L55CB
        jsr     TEST_BOX_IMPL
        jmp     L55CE

L55CB:  jsr     L5043
L55CE:  ldx     $AC
        lda     L5E21,x
        clc
        adc     $0528,x
        sta     L5E21,x
        lda     L5E11,x
        adc     $04E8,x
        sta     L5E11,x
        lda     L5E31,x
        adc     $0568,x
        sta     L5E31,x
        lda     L5E41,x
        adc     $05A8,x
        sta     L5E41,x
        lda     $0428,x
L55F8:  bmi     L55FD
        jmp     L553E

L55FD:  inc     $A9
        bne     L5603
        inc     $AA
L5603:  jmp     L54C2

L5606:  ldy     $04A8,x
        lda     $0780,y
        sta     $05E8,x
        sec
        sbc     $A9
        sta     $A3
        lda     $07BC,y
        sta     L5E01,x
        sbc     $AA
        sta     $A4
        lda     $0700,y
        sec
        sbc     L5E31,x
        sta     $A1
        lda     $073C,y
        sbc     L5E41,x
        sta     $A2
        php
        bpl     L563F
        lda     #$00
        sec
        sbc     $A1
        sta     $A1
        lda     #$00
        sbc     $A2
        sta     $A2
L563F:  stx     $84
        jsr     L569A
        ldx     $84
        plp
        bpl     L5662
        lda     #$00
        sec
        sbc     $9F
        sta     $9F
        lda     #0
        sbc     $A0
        sta     $A0
        lda     #0
        sbc     $A1
        sta     $A1
        lda     #0
        sbc     $A2
        sta     $A2
L5662:  lda     $A2
        sta     $05A8,x
        cmp     #$80
        ror     a
        pha
        lda     $A1
        sta     $0568,x
        ror     a
        pha
        lda     $A0
        sta     $04E8,x
        ror     a
        pha
        lda     $9F
        sta     $0528,x
        ror     a
        sta     L5E21,x
        pla
        clc
        adc     #$80
        sta     L5E11,x
        pla
        adc     L5E31,x
        sta     L5E31,x
        pla
        adc     L5E41,x
        sta     L5E41,x
        rts

L5698:  lda     $A2
L569A:  ora     $A1
        bne     L56A8
        sta     $9F
        sta     $A0
        sta     $A1
        sta     $A2
        beq     L56D5
L56A8:  ldy     #$20
        lda     #$00
        sta     $9F
        sta     $A0
        sta     $A5
        sta     $A6
L56B4:  asl     $9F
        rol     $A0
        rol     $A1
        rol     $A2
        rol     $A5
        rol     $A6
        lda     $A5
        sec
        sbc     $A3
        tax
        lda     $A6
        sbc     $A4
        bcc     L56D2
        stx     $A5
        sta     $A6
        inc     $9F
L56D2:  dey
        bne     L56B4
L56D5:  rts

;;; ==================================================

;;; DRAW_POLYGONS IMPL

.proc DRAW_POLYGONS_IMPL
        lda     #0
        sta     $BA
        jsr     ora_2_param_bytes

        ptr := $B7
        draw_line_params := $92

L56DD:  lda     params_addr
        sta     ptr
        lda     params_addr+1
        sta     ptr+1
        lda     $B4             ; ORAd param bytes
        sta     $B6
        ldx     #0
        jsr     L52A1           ; ???
        bcc     L572F

        lda     $B3
        sta     $B5             ; loop counter

        ;; Loop for drawing
        ldy     #0
loop:   dec     $B5
        beq     endloop
        sty     $B9

        ldx     #0
:       lda     (ptr),y
        sta     draw_line_params,x
        iny
        inx
        cpx     #8
        bne     :-
        jsr     DRAW_LINE_ABS_IMPL_L5783

        lda     $B9
        clc
        adc     #4
        tay
        bne     loop

endloop:
        ;; Draw from last point back to start
        ldx     #0
:       lda     (ptr),y
        sta     draw_line_params,x
        iny
        inx
        cpx     #4
        bne     :-
        ldy     #3
:       lda     (ptr),y
        sta     draw_line_params+4,y
        sta     state_pos,y
        dey
        bpl     :-
        jsr     DRAW_LINE_ABS_IMPL_L5783

        ;; Handle multiple segments, e.g. when drawing outlines for multi icons?

L572F:  ldx     #1
:       lda     ptr,x
        sta     $80,x
        lda     $B5,x
        sta     $B3,x
        dex
        bpl     :-
        jsr     L5354           ; ???
        bmi     L56DD

        rts
.endproc

;;; ==================================================

;;; OFFSET_POS IMPL

;;; 4 bytes of params, copied to $A1

.proc OFFSET_POS_IMPL
        xdelta := $A1
        ydelta := $A3

        lda     xdelta
        ldx     xdelta+1
        jsr     adjust_xpos
        lda     ydelta
        ldx     ydelta+1
        clc
        adc     state_ypos
        sta     state_ypos
        txa
        adc     state_ypos+1
        sta     state_ypos+1
        rts
.endproc

        ;; Adjust state_xpos by (X,A)
.proc adjust_xpos
        clc
        adc     state_xpos
        sta     state_xpos
        txa
        adc     state_xpos+1
        sta     state_xpos+1
        rts
.endproc

;;; ==================================================

;;; 4 bytes of params, copied to $A1

.proc DRAW_LINE_IMPL

        xdelta := $A1
        ydelta := $A2

        ldx     #2              ; Convert relative x/y to absolute x/y at $92,$94
loop:   lda     xdelta,x
        clc
        adc     state_xpos,x
        sta     $92,x
        lda     xdelta+1,x
        adc     state_xpos+1,x
        sta     $93,x
        dex
        dex
        bpl     loop
        ;; fall through
.endproc

;;; ==================================================

;;; 4 bytes of params, copied to $92

.proc DRAW_LINE_ABS_IMPL

        params  := $92
        xend    := params + 0
        yend    := params + 2

        pt1     := $92
        x1      := pt1
        y1      := pt1+2

        pt2     := $96
        x2      := pt2
        y2      := pt2+2

        ldx     #3
L5778:  lda     state_pos,x     ; move pos to $96, assign params to pos
        sta     pt2,x
        lda     pt1,x
        sta     state_pos,x
        dex
        bpl     L5778

        ;; Called from elsewhere; draw $92,$94 to $96,$98; values modified
L5783:
        lda     y2+1
        cmp     y1+1
        bmi     L57B0
        bne     L57BF
        lda     y2
        cmp     y1
        bcc     L57B0
        bne     L57BF

        ;; y1 == y2
        lda     x1
        ldx     x1+1
        cpx     x2+1
        bmi     L57AD
        bne     L57A1
        cmp     x2
        bcc     L57AD

L57A1:  ldy     x2              ; swap so x1 < x2
        sta     x2
        sty     x1
        ldy     x2+1
        stx     x2+1
        sty     x1+1
L57AD:  jmp     L501E

L57B0:  ldx     #3              ; Swap start/end
:       lda     $92,x
        tay
        lda     $96,x
        sta     $92,x
        tya
        sta     $96,x
        dex
        bpl     :-

L57BF:  ldx     state_hthick
        dex
        stx     $A2
        lda     state_vthick
        sta     $A4
        lda     #0
        sta     $A1
        sta     $A3
        lda     $92
        ldx     $93
        cpx     $97
        bmi     L57E9
        bne     L57E1
        cmp     $96
        bcc     L57E9
        bne     L57E1
        jmp     L501E

L57E1:  lda     $A1
        ldx     $A2
        sta     $A2
        stx     $A1
L57E9:  ldy     #5
L57EB:  sty     $82
        ldx     L583E,y
        ldy     #3
L57F2:  lda     $92,x
        sta     $83,y
        dex
        dey
        bpl     L57F2
        ldy     $82
        ldx     L5844,y
        lda     $A1,x
        clc
        adc     $83
        sta     $83
        bcc     L580B
        inc     $84
L580B:  ldx     L584A,y
        lda     $A3,x
        clc
        adc     $85
        sta     $85
        bcc     L5819
        inc     $86
L5819:  tya
        asl     a
        asl     a
        tay
        ldx     #0
L581F:  lda     $83,x
        sta     L5852,y
        iny
        inx
        cpx     #4
        bne     L581F
        ldy     $82
        dey
        bpl     L57EB
        lda     L583C
        sta     params_addr
        lda     L583C+1
        sta     params_addr+1
        jmp     L537E

L583C:  .addr   L5850

L583E:  .byte   $03,$03,$07,$07,$07,$03
L5844:  .byte   $00,$00,$00,$01,$01,$01
L584A:  .byte   $00,$01,$01,$01,$00,$00

        ;; params for a $15 call
L5850:  .byte   $06,$00
L5852:  .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
.endproc
        DRAW_LINE_ABS_IMPL_L5783 := DRAW_LINE_ABS_IMPL::L5783

;;; ==================================================

;;; SET_FONT IMPL

.proc SET_FONT_IMPL
        lda     params_addr     ; set font to passed address
        sta     state_font
        lda     params_addr+1
        sta     state_font+1

        ;; Compute addresses of each row of the glyphs.
prepare_font:
        ldy     #0              ; copy first 3 bytes of font defn ($00 ??, $7F ??, height) to $FD-$FF
:       lda     (state_font),y
        sta     $FD,y
        iny
        cpy     #3
        bne     :-

        cmp     #17             ; if height >= 17, skip this next bit
        bcs     end

        lda     state_font
        ldx     state_font+1
        clc
        adc     #3
        bcc     :+
        inx
:       sta     glyph_widths    ; set $FB/$FC to start of widths
        stx     glyph_widths+1

        sec
        adc     glyph_last
        bcc     :+
        inx

:       ldy     #0              ; loop 0... height-1
loop:   sta     glyph_row_lo,y
        pha
        txa
        sta     glyph_row_hi,y
        pla

        sec
        adc     glyph_last
        bcc     :+
        inx

:       bit     glyph_flag   ; if flag is set, double the offset (???)
        bpl     :+

        sec
        adc     glyph_last
        bcc     :+
        inx

:       iny
        cpy     glyph_height_p
        bne     loop
        rts

end:    lda     #$83
        jmp     a2d_exit_with_a
.endproc

glyph_row_lo:
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
glyph_row_hi:
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00

;;; ==================================================

;;; 3 bytes of params, copied to $A1

.proc MEASURE_TEXT_IMPL
        jsr     measure_text
        ldy     #3              ; Store result (X,A) at params+3
        sta     (params_addr),y
        txa
        iny
        sta     (params_addr),y
        rts
.endproc

        ;; Call with data at ($A1), length in $A3, result in (X,A)
.proc measure_text
        data   := $A1
        length := $A3

        accum  := $82

        ldx     #0
        ldy     #0
        sty     accum
loop:   sty     accum+1
        lda     (data),y
        tay
        txa
        clc
        adc     (glyph_widths),y
        bcc     :+
        inc     accum
:       tax
        ldy     accum+1
        iny
        cpy     length
        bne     loop
        txa
        ldx     accum
        rts
.endproc

;;; ==================================================

L5907:  sec
        sbc     #1
        bcs     L590D
        dex
L590D:  clc
        adc     state_xpos
        sta     $96
        txa
        adc     state_xpos+1
        sta     $97
        lda     state_xpos
        sta     $92
        lda     state_xpos+1
        sta     $93
        lda     state_ypos
        sta     $98
        ldx     state_ypos+1
        stx     $99
        clc
        adc     #1
        bcc     L592D
        inx
L592D:  sec
        sbc     $FF
        bcs     L5933
        dex
L5933:  sta     $94
        stx     $95
        rts

;;; ==================================================

;;; 3 bytes of params, copied to $A1

DRAW_TEXT_IMPL:
        jsr     L5EFA
        jsr     measure_text
        sta     $A4
        stx     $A5
        ldy     #0
        sty     $9F
        sty     $A0
        sty     $9B
        sty     $9D
        jsr     L5907
        jsr     L50A9
        bcc     L59B9
        tya
        ror     a
        bcc     L5972
        ldy     #0
        ldx     $9C
L595C:  sty     $9F
        lda     ($A1),y
        tay
        lda     (glyph_widths),y
        clc
        adc     $9B
        bcc     L596B
        inx
        beq     L5972
L596B:  sta     $9B
        ldy     $9F
        iny
        bne     L595C
L5972:  jsr     set_up_fill_mode
        jsr     L4EA9
        lda     $87
        clc
        adc     $9B
        bpl     L5985
        inc     $91
        dec     $A0
        adc     #$0E
L5985:  sta     $87
        lda     $91
        inc     $91
        ldy     state_stride
        bpl     L599F
        asl     a
        tax
        lda     $87
        cmp     #7
        bcs     L5998
        inx
L5998:  lda     $96
        beq     L599D
        inx
L599D:  stx     $91
L599F:  lda     $87
        sec
        sbc     #7
        bcc     L59A8
        sta     $87
L59A8:  lda     #0
        rol     a
        eor     #1
        sta     $9C
        tax
        sta     LOWSCR,x
        jsr     L59C3
        sta     LOWSCR
L59B9:  jsr     L5EEA
        lda     $A4
        ldx     $A4+1
        jmp     adjust_xpos

L59C3:  lda     $98
        sec
        sbc     $94
        asl     a
        tax
        lda     L5D81,x
        sta     L5B02
        lda     L5D81+1,x
        sta     L5B03
        lda     L5DA1,x
        sta     L5A95
        lda     L5DA1+1,x
        sta     L5A96
        lda     L5DC1,x
        sta     L5C22
        lda     L5DC1+1,x
        sta     L5C23
        lda     L5DE1,x
        sta     L5CBE
        lda     L5DE1+1,x
        sta     L5CBF
        txa
        lsr     a
        tax
        sec
        stx     $80
        stx     $81
        lda     #0
        sbc     $9D
        sta     $9D
        tay
        ldx     #$C3
        sec
L5A0C:  lda     glyph_row_lo,y
        sta     L5B04+1,x
        lda     glyph_row_hi,y
        sta     L5B04+2,x
        txa
        sbc     #$0D
        tax
        iny
        dec     $80
        bpl     L5A0C
        ldy     $9D
        ldx     #$4B
        sec
L5A26:  lda     glyph_row_lo,y
        sta     L5A97+1,x
        lda     glyph_row_hi,y
        sta     L5A97+2,x
        txa
        sbc     #$05
        tax
        iny
        dec     $81
        bpl     L5A26
        ldy     $94
        ldx     #$00
L5A3F:  bit     state_stride
        bmi     L5A56
        lda     $84
        clc
        adc     state_stride
        sta     $84
        sta     $20,x
        lda     $85
        adc     #$00
        sta     $85
        sta     $21,x
        bne     L5A65
L5A56:  lda     hires_table_lo,y
        clc
        adc     $86
        sta     $20,x
        lda     hires_table_hi,y
        ora     state_addr+1
        sta     $21,x
L5A65:  cpy     $98
L5A68           := * + 1
        beq     L5A6E
        iny
        inx
        inx
        bne     L5A3F
L5A6E:  ldx     #$0F
        lda     #$00
L5A72:  sta     $0000,x
        dex
        bpl     L5A72
        sta     $81
        sta     $40
        lda     #$80
        sta     $42
        ldy     $9F
L5A81:  lda     ($A1),y
        tay
        bit     $81
        bpl     L5A8B
        sec
        adc     $FE
L5A8B:  tax
        lda     (glyph_widths),y
        beq     L5AE7
        ldy     $87
        bne     L5AEA
L5A95           := * + 1
L5A96           := * + 2
        jmp     L5A97

L5A97:  lda     $FFFF,x
        sta     $0F
L5A9C:  lda     $FFFF,x
        sta     $0E
L5AA1:  lda     $FFFF,x
        sta     $0D
L5AA6:  lda     $FFFF,x
        sta     $0C
L5AAB:  lda     $FFFF,x
        sta     $0B
L5AB0:  lda     $FFFF,x
        sta     $0A
L5AB5:  lda     $FFFF,x
        sta     $09
L5ABA:  lda     $FFFF,x
        sta     $08
L5ABF:  lda     $FFFF,x
        sta     $07
L5AC4:  lda     $FFFF,x
        sta     $06
L5AC9:  lda     $FFFF,x
        sta     $05
L5ACE:  lda     $FFFF,x
        sta     $04
L5AD3:  lda     $FFFF,x
        sta     $03
L5AD8:  lda     $FFFF,x
        sta     $02
L5ADD:  lda     $FFFF,x
        sta     $01
L5AE2:  lda     $FFFF,x
        sta     $0000
L5AE7:  jmp     L5BD4

L5AEA:  tya
        asl     a
        tay
        lda     L5285+2,y
        sta     $40
        lda     L5285+3,y
        sta     $41
        lda     L5293,y
        sta     $42
        lda     L5293+1,y
        sta     $43
L5B02           := * + 1
L5B03           := * + 2
        jmp     L5B04

L5B04:  ldy     $FFFF,x         ; All of these $FFFFs are modified
        lda     ($42),y
        sta     $1F
        lda     ($40),y
        ora     $0F
        sta     $0F
L5B11:  ldy     $FFFF,x
        lda     ($42),y
        sta     $1E
        lda     ($40),y
        ora     $0E
        sta     $0E
L5B1E:  ldy     $FFFF,x
        lda     ($42),y
        sta     $1D
        lda     ($40),y
        ora     $0D
        sta     $0D
L5B2B:  ldy     $FFFF,x
        lda     ($42),y
        sta     $1C
        lda     ($40),y
        ora     $0C
        sta     $0C
L5B38:  ldy     $FFFF,x
        lda     ($42),y
        sta     $1B
        lda     ($40),y
        ora     $0B
        sta     $0B
L5B45:  ldy     $FFFF,x
        lda     ($42),y
        sta     $1A
        lda     ($40),y
        ora     $0A
        sta     $0A
L5B52:  ldy     $FFFF,x
        lda     ($42),y
        sta     $19
        lda     ($40),y
        ora     $09
        sta     $09
L5B5F:  ldy     $FFFF,x
        lda     ($42),y
        sta     $18
        lda     ($40),y
        ora     $08
        sta     $08
L5B6C:  ldy     $FFFF,x
        lda     ($42),y
        sta     $17
        lda     ($40),y
        ora     $07
        sta     $07
L5B79:  ldy     $FFFF,x
        lda     ($42),y
        sta     $16
        lda     ($40),y
        ora     $06
        sta     $06
L5B86:  ldy     $FFFF,x
        lda     ($42),y
        sta     $15
        lda     ($40),y
        ora     $05
        sta     $05
L5B93:  ldy     $FFFF,x
        lda     ($42),y
        sta     $14
        lda     ($40),y
        ora     $04
        sta     $04
L5BA0:  ldy     $FFFF,x
        lda     ($42),y
        sta     $13
        lda     ($40),y
        ora     $03
        sta     $03
L5BAD:  ldy     $FFFF,x
        lda     ($42),y
        sta     $12
        lda     ($40),y
        ora     $02
        sta     $02
L5BBA:  ldy     $FFFF,x
        lda     ($42),y
        sta     $11
        lda     ($40),y
        ora     $01
        sta     $01
L5BC7:  ldy     $FFFF,x
        lda     ($42),y
        sta     $10
        lda     ($40),y
        ora     $0000
        sta     $0000
L5BD4:  bit     $81
        bpl     L5BE2
        inc     $9F
        lda     #$00
        sta     $81
        lda     $9A
        bne     L5BF6
L5BE2:  txa
        tay
        lda     (glyph_widths),y
        cmp     #$08
        bcs     L5BEE
        inc     $9F
        bcc     L5BF6
L5BEE:  sbc     #$07
        sta     $9A
        ror     $81
        lda     #$07
L5BF6:  clc
        adc     $87
        cmp     #$07
        bcs     L5C0D
        sta     $87
L5BFF:  ldy     $9F
        cpy     $A3
        beq     L5C08
        jmp     L5A81

L5C08:  ldy     $A0
        jmp     L5CB5

L5C0D:  sbc     #$07
        sta     $87
        ldy     $A0
        bne     L5C18
        jmp     L5CA2

L5C18:  bmi     L5C84
        dec     $91
        bne     L5C21
        jmp     L5CB5

L5C21:
L5C22           := * + 1
L5C23           := * + 2
        jmp     L5C24

L5C24:  lda     $0F
        eor     state_tmask
        sta     ($3E),y
L5C2A:  lda     $0E
        eor     state_tmask
        sta     ($3C),y
L5C30:  lda     $0D
        eor     state_tmask
        sta     ($3A),y
L5C36:  lda     $0C
        eor     state_tmask
        sta     ($38),y
L5C3C:  lda     $0B
        eor     state_tmask
        sta     ($36),y
L5C42:  lda     $0A
        eor     state_tmask
        sta     ($34),y
L5C48:  lda     $09
        eor     state_tmask
        sta     ($32),y
L5C4E:  lda     $08
        eor     state_tmask
        sta     ($30),y
L5C54:  lda     $07
        eor     state_tmask
        sta     ($2E),y
L5C5A:  lda     $06
        eor     state_tmask
        sta     ($2C),y
L5C60:  lda     $05
        eor     state_tmask
        sta     ($2A),y
L5C66:  lda     $04
        eor     state_tmask
        sta     ($28),y
L5C6C:  lda     $03
        eor     state_tmask
        sta     ($26),y
L5C72:  lda     $02
        eor     state_tmask
        sta     ($24),y
L5C78:  lda     $01
        eor     state_tmask
        sta     ($22),y
L5C7E:  lda     $00
        eor     state_tmask
        sta     ($20),y
L5C84:  bit     state_stride
        bpl     L5C94
        lda     $9C
        eor     #$01
        tax
        sta     $9C
        sta     LOWSCR,x
        beq     L5C96
L5C94:  inc     $A0
L5C96:  ldx     #$0F
L5C98:  lda     $10,x
        sta     $0000,x
        dex
        bpl     L5C98
        jmp     L5BFF

L5CA2:  ldx     $9C
        lda     $92,x
        dec     $91
        beq     L5CB0
        jsr     L5CB9
        jmp     L5C84

L5CB0:  and     $96,x
        bne     L5CB9
        rts

L5CB5:  ldx     $9C
        lda     $96,x
L5CB9:  ora     #$80
        sta     $80
L5CBE           := * + 1
L5CBF           := * + 2
        jmp     L5CC0

L5CC0:  lda     $0F
        eor     state_tmask
        eor     ($3E),y
        and     $80
        eor     ($3E),y
        sta     ($3E),y
L5CCC:  lda     $0E
        eor     state_tmask
        eor     ($3C),y
        and     $80
        eor     ($3C),y
        sta     ($3C),y
L5CD8:  lda     $0D
        eor     state_tmask
        eor     ($3A),y
        and     $80
        eor     ($3A),y
        sta     ($3A),y
L5CE4:  lda     $0C
        eor     state_tmask
        eor     ($38),y
        and     $80
        eor     ($38),y
        sta     ($38),y
L5CF0:  lda     $0B
        eor     state_tmask
        eor     ($36),y
        and     $80
        eor     ($36),y
        sta     ($36),y
L5CFC:  lda     $0A
        eor     state_tmask
        eor     ($34),y
        and     $80
        eor     ($34),y
        sta     ($34),y
L5D08:  lda     $09
        eor     state_tmask
        eor     ($32),y
        and     $80
        eor     ($32),y
        sta     ($32),y
L5D14:  lda     $08
        eor     state_tmask
        eor     ($30),y
        and     $80
        eor     ($30),y
        sta     ($30),y
L5D20:  lda     $07
        eor     state_tmask
        eor     ($2E),y
        and     $80
        eor     ($2E),y
        sta     ($2E),y
L5D2C:  lda     $06
        eor     state_tmask
        eor     ($2C),y
        and     $80
        eor     ($2C),y
        sta     ($2C),y
L5D38:  lda     $05
        eor     state_tmask
        eor     ($2A),y
        and     $80
        eor     ($2A),y
        sta     ($2A),y
L5D44:  lda     $04
        eor     state_tmask
        eor     ($28),y
        and     $80
        eor     ($28),y
        sta     ($28),y
L5D50:  lda     $03
        eor     state_tmask
        eor     ($26),y
        and     $80
        eor     ($26),y
        sta     ($26),y
L5D5C:  lda     $02
        eor     state_tmask
        eor     ($24),y
        and     $80
        eor     ($24),y
        sta     ($24),y
L5D68:  lda     $01
        eor     state_tmask
        eor     ($22),y
        and     $80
        eor     ($22),y
        sta     ($22),y
L5D74:  lda     $00
        eor     state_tmask
        eor     ($20),y
        and     $80
        eor     ($20),y
        sta     ($20),y
        rts

L5D81:  .addr   L5BC7,L5BBA,L5BAD,L5BA0,L5B93,L5B86,L5B79,L5B6C,L5B5F,L5B52,L5B45,L5B38,L5B2B,L5B1E,L5B11,L5B04
L5DA1:  .addr   L5AE2,L5ADD,L5AD8,L5AD3,L5ACE,L5AC9,L5AC4,L5ABF,L5ABA,L5AB5,L5AB0,L5AAB,L5AA6,L5AA1,L5A9C,L5A97
L5DC1:  .addr   L5C7E,L5C78,L5C72,L5C6C,L5C66,L5C60,L5C5A,L5C54,L5C4E,L5C48,L5C42,L5C3C,L5C36,L5C30,L5C2A,L5C24
L5DE1:  .addr   L5D74,L5D68,L5D5C,L5D50,L5D44,L5D38,L5D2C,L5D20,L5D14,L5D08,L5CFC,L5CF0,L5CE4,L5CD8,L5CCC,L5CC0

L5E01:  .byte   $00
L5E02:  .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00

L5E11:  .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00

L5E21:  .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00

L5E31:  .byte   $00
L5E32:  .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00
L5E41:  .byte   $00
L5E42:  .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00

;;; ==================================================

;;; $01 IMPL

.proc L5E51

        lda     #$71            ; %0001 lo nibble = HiRes, Page 1, Full, Graphics
        sta     $82             ; (why is high nibble 7 ???)
        jsr     CFG_DISPLAY_IMPL

        ;; Initialize state
        ldx     #sizeof_state-1
loop:   lda     screen_state,x
        sta     $8A,x
        sta     $D0,x
        dex
        bpl     loop

        lda     L5E79
        ldx     L5E79+1
        jsr     assign_and_prepare_state

        lda     #$7F
        sta     fill_eor_mask
        jsr     FILL_RECT_IMPL
        lda     #$00
        sta     fill_eor_mask
        rts

L5E79:  .addr   L5F42
.endproc

;;; ==================================================

;;; CFG_DISPLAY_IMPL

;;; 1 byte param, copied to $82

;;; Toggle display softswitches
;;;   bit 0: LoRes if clear, HiRes if set
;;;   bit 1: Page 1 if clear, Page 2 if set
;;;   bit 2: Full screen if clear, split screen if set
;;;   bit 3: Graphics if clear, text if set

.proc CFG_DISPLAY_IMPL
        param := $82

        lda     DHIRESON        ; enable dhr graphics
        sta     SET80VID

        ldx     #3
loop:   lsr     param           ; shift low bit into carry
        lda     table,x
        rol     a
        tay                     ; y = table[x] * 2 + carry
        bcs     store

        lda     $C000,y         ; why load vs. store ???
        bcc     :+

store:  sta     $C000,y

:       dex
        bpl     loop
        rts

table:  .byte   <(TXTCLR / 2), <(MIXCLR / 2), <(LOWSCR / 2), <(LORES / 2)
.endproc

;;; ==================================================

.proc SET_STATE_IMPL
        lda     params_addr
        ldx     params_addr+1
        ;; fall through
.endproc

        ;; Call with state address in (X,A)
assign_and_prepare_state:
        sta     active_state
        stx     active_state+1
        ;; fall through

        ;; Initializes font (if needed), box, pattern, and fill mode
prepare_state:
        lda     state_font+1
        beq     :+              ; only prepare font if necessary
        jsr     SET_FONT_IMPL::prepare_font
:       jsr     SET_BOX_IMPL
        jsr     SET_PATTERN_IMPL
        jmp     SET_FILL_MODE_IMPL

;;; ==================================================

.proc GET_STATE_IMPL
        jsr     apply_state_to_active_state
        lda     active_state
        ldx     active_state+1
        ;;  fall through
.endproc

        ;; Store result (X,A) at params
store_xa_at_params:
        ldy     #0

        ;; Store result (X,A) at params+Y
store_xa_at_params_y:
        sta     (params_addr),y
        txa
        iny
        sta     (params_addr),y
        rts

;;; ==================================================

.proc QUERY_SCREEN_IMPL
        ldy     #sizeof_state-1 ; Store 36 bytes at params
loop:   lda     screen_state,y
        sta     (params_addr),y
        dey
        bpl     loop
.endproc
rts3:   rts

;;; ==================================================

;;; 1 byte of params, copied to $82

.proc CONFIGURE_ZP_IMPL
        param := $82

        lda     param
        cmp     preserve_zp_flag
        beq     rts3
        sta     preserve_zp_flag
        bcc     rts3
        jmp     a2d_dispatch::cleanup
.endproc

;;; ==================================================

;;; $1B IMPL

;;; 1 byte of params, copied to $82

L5EDE:
        lda     $82
        cmp     L5F1C
        beq     rts3
        sta     L5F1C
        bcc     L5EFF
L5EEA:  bit     L5F1C
        bpl     L5EF9
        ldx     #$43
L5EF1:  lda     L5E01,x
        sta     $00,x
        dex
        bpl     L5EF1
L5EF9:  rts


L5EFA:  bit     L5F1C
        bpl     L5EF9
L5EFF:  ldx     #$43
L5F01:  lda     $00,x
        sta     L5E01,x
        dex
        bpl     L5F01
        rts

;;; ==================================================

;;; $1C IMPL

;;; Just copies static bytes to params???

.proc L5F0A
        ldy     #5              ; Store 6 bytes at params
loop:   lda     table,y
        sta     (params_addr),y
        dey
        bpl     loop
        rts

table:  .byte   $01,$00,$00,$46,$01,$00
.endproc

;;; ==================================================

preserve_zp_flag:         ; if high bit set, ZP saved during A2D calls
        .byte   $80

L5F1C:  .byte   $80

stack_ptr_stash:
        .byte   0

;;; ==================================================

;;; Screen State

.proc screen_state
left:   .word   0
top:    .word   0
addr:   .addr   A2D_SCREEN_ADDR
stride: .word   A2D_SCREEN_STRIDE
hoff:   .word   0
voff:   .word   0
width:  .word   560-1
height: .word   192-1
pattern:.res    8, $FF
mskand: .byte   A2D_DEFAULT_MSKAND
mskor:  .byte   A2D_DEFAULT_MSKOR
xpos:   .word   0
ypos:   .word   0
hthick: .byte   1
vthick: .byte   1
mode:   .byte   0
tmask:  .byte   0
font:   .addr   0
.endproc

;;; ==================================================


.proc L5F42
left:   .word   0
top:    .word   0
addr:   .addr   A2D_SCREEN_ADDR
stride: .word   A2D_SCREEN_STRIDE
hoff:   .word   0
voff:   .word   0
width:  .word   560-1
height: .word   192-1
pattern:.res    8, $FF
mskand: .byte   A2D_DEFAULT_MSKAND
mskor:  .byte   A2D_DEFAULT_MSKOR
xpos:   .word   0
ypos:   .word   0
hthick: .byte   1
vthick: .byte   1
mode:   .byte   0
tmask:  .byte   0
font:   .addr   0
.endproc

active_saved:           ; saved copy of $F4...$FF when ZP swapped
        .addr   L5F42
        .res    10, 0

zp_saved:               ; top half of ZP for when preserve_zp_flag set
        .res    128, 0

        ;; cursor shown/hidden flags/counts
cursor_flag:                    ; high bit clear if cursor drawn, set if not drawn
        .byte   0
cursor_count:
        .byte   $FF             ; decremented on hide, incremented on shown; 0 = visible

.proc set_pos_params
xcoord: .word   0
ycoord: .word   0
.endproc

mouse_x_lo:  .byte   0
mouse_x_hi:  .byte   0
mouse_y_lo:  .byte   0
mouse_y_hi:  .byte   0          ; not really used due to clamping
mouse_status:.byte   0

L5FFD:  .byte   $00
L5FFE:  .byte   $00
L5FFF:  .byte   $00
L6000:  .byte   $00
L6001:  .byte   $00

cursor_hotspot_x:  .byte   $00
cursor_hotspot_y:  .byte   $00

L6004:  .byte   $00
L6005:  .byte   $00
L6006:  .byte   $00
L6007:  .byte   $00
L6008:  .byte   $00
L6009:  .byte   $00
L600A:  .byte   $00
L600B:  .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00
L602F:  .byte   $00,$00,$00,$00,$00,$00,$02,$00
        .byte   $06,$00,$0E,$00,$1E,$00,$3E,$00
        .byte   $7E,$00,$1A,$00,$30,$00,$30,$00
        .byte   $60,$00,$00,$00,$03,$00,$07,$00
        .byte   $0F,$00,$1F,$00,$3F,$00,$7F,$00
        .byte   $7F,$01,$7F,$00,$78,$00,$78,$00
        .byte   $70,$01,$70,$01,$01,$01
L6065:  .byte   $33
L6066:  .byte   $60
L6067:  lda     #$FF
        sta     cursor_count
        lda     #0
        sta     cursor_flag
        lda     L6065
        sta     params_addr
        lda     L6066
        sta     params_addr+1
        ;; fall through

;;; ==================================================

        cursor_height := 12
        cursor_width  := 2
        cursor_mask_offset := cursor_width * cursor_height
        cursor_hotspot_offset := 2 * cursor_width * cursor_height

SET_CURSOR_IMPL:
        php
        sei
        lda     params_addr
        ldx     params_addr+1
        sta     active_cursor
        stx     active_cursor+1
        clc
        adc     #cursor_mask_offset
        bcc     :+
        inx
:       sta     active_cursor_mask
        stx     active_cursor_mask+1
        ldy     #cursor_hotspot_offset
        lda     (params_addr),y
        sta     cursor_hotspot_x
        iny
        lda     (params_addr),y
        sta     cursor_hotspot_y
        jsr     restore_cursor_background
        jsr     draw_cursor
        plp
L60A7:  rts

update_cursor:
        lda     cursor_count           ; hidden? if so, skip
        bne     L60A7
        bit     cursor_flag
        bmi     L60A7

draw_cursor:
        lda     #$00
        sta     cursor_count
        sta     cursor_flag
        lda     set_pos_params::ycoord
        clc
        sbc     cursor_hotspot_y
        sta     $84
        clc
        adc     #$0C
        sta     $85
        lda     set_pos_params::xcoord
        sec
        sbc     cursor_hotspot_x
        tax
        lda     set_pos_params::xcoord+1
        sbc     #$00
        bpl     L60E1
        txa
        ror     a
        tax
        ldy     L499D,x
        lda     #$FF
        bmi     L60E4
L60E1:  jsr     L4E8D
L60E4:  sta     $82
        tya
        rol     a
        cmp     #$07
        bcc     L60EE
        sbc     #$07
L60EE:  tay
        lda     #$2A
        rol     a
        eor     #$01
        sta     $83
        sty     L6004
        tya
        asl     a
        tay
        lda     L5293,y
        sta     L6164
        lda     L5293+1,y
        sta     L6165
        lda     L5285+2,y
        sta     L616A
        lda     L5285+3,y
        sta     L616B
        ldx     #$03
L6116:  lda     $82,x
        sta     L602F,x
        dex
        bpl     L6116
        ldx     #$17
        stx     $86
        ldx     #$23
        ldy     $85
L6126:  cpy     #$C0
        bcc     L612D
        jmp     L61B9

L612D:  lda     hires_table_lo,y
        sta     $88
        lda     hires_table_hi,y
        ora     #$20
        sta     $89
        sty     $85
        stx     $87
        ldy     $86
        ldx     #$01
L6141:
active_cursor           := * + 1
        lda     $FFFF,y
        sta     L6005,x
active_cursor_mask      := * + 1
        lda     $FFFF,y
        sta     L6008,x
        dey
        dex
        bpl     L6141
        lda     #$00
        sta     L6007
        sta     L600A
        ldy     L6004
        beq     L6172
        ldy     #$05
L6160:  ldx     L6004,y
L6164           := * + 1
L6165           := * + 2
        ora     $FF80,x
        sta     L6005,y
L616A           := * + 1
L616B           := * + 2
        lda     $FF00,x
        dey
        bne     L6160
        sta     L6005
L6172:  ldx     $87
        ldy     $82
        lda     $83
        jsr     L622A
        bcs     L618D
        lda     ($88),y
        sta     L600B,x
        lda     L6008
        ora     ($88),y
        eor     L6005
        sta     ($88),y
        dex
L618D:  jsr     L6220
        bcs     L61A2
        lda     ($88),y
        sta     L600B,x
        lda     L6009
        ora     ($88),y
        eor     L6006
        sta     ($88),y
        dex
L61A2:  jsr     L6220
        bcs     L61B7
        lda     ($88),y
        sta     L600B,x
        lda     L600A
        ora     ($88),y
        eor     L6007
        sta     ($88),y
        dex
L61B7:  ldy     $85
L61B9:  dec     $86
        dec     $86
        dey
        cpy     $84
        beq     L621C
        jmp     L6126

L61C5:  rts

restore_cursor_background:
        lda     cursor_count           ; already hidden?
        bne     L61C5
        bit     cursor_flag
        bmi     L61C5

        ldx     #$03
L61D2:  lda     L602F,x
        sta     $82,x
        dex
        bpl     L61D2
        ldx     #$23
        ldy     $85
L61DE:  cpy     #$C0
        bcs     L6217
        lda     hires_table_lo,y
        sta     $88
        lda     hires_table_hi,y
        ora     #$20
        sta     $89
        sty     $85
L61F1           := * + 1
        ldy     $82
        lda     $83
        jsr     L622A
        bcs     L61FF
        lda     L600B,x
        sta     ($88),y
        dex
L61FF:  jsr     L6220
        bcs     L620A
        lda     L600B,x
        sta     ($88),y
        dex
L620A:  jsr     L6220
        bcs     L6215
        lda     L600B,x
        sta     ($88),y
        dex
L6215:  ldy     $85
L6217:  dey
        cpy     $84
        bne     L61DE
L621C:  sta     LOWSCR
        rts

L6220:  lda     L622E
        eor     #$01
        cmp     #$54
        beq     L622A
        iny
L622A:  sta     L622E
        .byte   $8D
L622E:  bbs7    $C0,L61F1
        plp
        rts

;;; ==================================================

.proc SHOW_CURSOR_IMPL
        php
        sei
        lda     cursor_count
        beq     done
        inc     cursor_count
        bmi     done
        beq     :+
        dec     cursor_count
:       bit     cursor_flag
        bmi     done
        jsr     draw_cursor
done:   plp
        rts
.endproc

;;; ==================================================

;;; ERASE_CURSOR IMPL

.proc ERASE_CURSOR_IMPL
        php
        sei
        jsr     restore_cursor_background
        lda     #$80
        sta     cursor_flag
        plp
        rts
.endproc

;;; ==================================================

HIDE_CURSOR_IMPL:
        php
        sei
        jsr     restore_cursor_background
        dec     cursor_count
        plp
L6263:  rts

;;; ==================================================

L6264:  .byte   0
L6265:  bit     L6339
        bpl     L627C
        lda     L7D74
        bne     L627C
        dec     L6264
        lda     L6264
        bpl     L6263
        lda     #$02
        sta     L6264
L627C:  ldx     #2
L627E:  lda     mouse_x_lo,x
        cmp     set_pos_params,x
        bne     L628B
        dex
        bpl     L627E
        bmi     L629F
L628B:  jsr     restore_cursor_background
        ldx     #2
        stx     cursor_flag
L6293:  lda     mouse_x_lo,x
        sta     set_pos_params,x
        dex
        bpl     L6293
        jsr     update_cursor
L629F:  bit     no_mouse_flag
        bmi     L62A7
        jsr     L62BA
L62A7:  bit     no_mouse_flag
        bpl     L62B1
        lda     #$00
        sta     mouse_status
L62B1:  lda     L7D74
        beq     rts4
        jsr     L7EF5
rts4:   rts

L62BA:  ldy     #READMOUSE
        jsr     call_mouse
        bit     L5FFF
        bmi     L62D9
        ldx     mouse_firmware_hi
        lda     MOUSE_X_LO,x
        sta     mouse_x_lo
        lda     MOUSE_X_HI,x
        sta     mouse_x_hi
        lda     MOUSE_Y_LO,x
        sta     mouse_y_lo
L62D9:  ldy     L5FFD
        beq     L62EF
L62DE:  lda     mouse_x_lo
        asl     a
        sta     mouse_x_lo
        lda     mouse_x_hi
        rol     a
        sta     mouse_x_hi
        dey
        bne     L62DE
L62EF:  ldy     L5FFE
        beq     L62FE
        lda     mouse_y_lo
L62F7:  asl     a
        dey
        bne     L62F7
        sta     mouse_y_lo
L62FE:  bit     L5FFF
        bmi     L6309
        lda     MOUSE_STATUS,x
        sta     mouse_status
L6309:  rts

;;; ==================================================

;;; GET_CURSOR IMPL

.proc GET_CURSOR_IMPL
        lda     active_cursor
        ldx     active_cursor+1
        jmp     store_xa_at_params
.endproc

;;; ==================================================

        ;; Call mouse firmware, operation in Y, param in A
call_mouse:
        bit     no_mouse_flag
        bmi     rts4

        bit     L5FFF
        bmi     L6332
        pha
        ldx     mouse_firmware_hi
        stx     $89
        lda     #$00
        sta     $88
        lda     ($88),y
        sta     $88
        pla
        ldy     mouse_operand
        jmp     ($88)

L6332:  jmp     (L6000)

L6335:  .byte   $00
L6336:  .byte   $00
L6337:  .byte   $00
L6338:  .byte   $00
L6339:  .byte   $00
L633A:  .byte   $00
L633B:  .byte   $00
L633C:  .byte   $00
L633D:  .byte   $00
L633E:  .byte   $00

hide_cursor_flag:
        .byte   0

L6340:  .byte   $00

;;; ==================================================

;;; $1D IMPL

;;; 12 bytes of params, copied to $82

L6341:
        php
        pla
        sta     L6340
        ldx     #$04
L6348:  lda     $82,x
        sta     L6335,x
        dex
        bpl     L6348
        lda     #$7F
        sta     screen_state::tmask
        lda     $87
        sta     screen_state::font
        lda     $88
        sta     screen_state::font+1
        lda     $89
        sta     L6835
        lda     $8A
        sta     L6836
        lda     $8B
        sta     L633B
        lda     $8C
        sta     L633C
        jsr     L646F
        jsr     L6491
        ldy     #$02
        lda     ($87),y
        tax
        stx     L6822
        dex
        stx     L78CB
        inx
        inx
        inx
        stx     fill_rect_params2_height
        inx
        stx     L78CD
        stx     test_box_params_bottom
        stx     test_box_params2_top
        stx     fill_rect_params4_top
        inx
        stx     set_box_params_top
        stx     L78CF
        stx     L6594
        stx     fill_rect_params_top
        dex
        stx     L6847
        clc
        ldy     #$00
L63AC:  txa
        adc     L6847,y
        iny
        sta     L6847,y
        cpy     #$0E
        bcc     L63AC
        lda     #$01
        sta     L5FFD
        lda     #$00
        sta     L5FFE
        bit     L6336
        bvs     L63D1
        lda     #$02
        sta     L5FFD
        lda     #$01
        sta     L5FFE
L63D1:  ldx     L6338
        jsr     find_mouse
        bit     L6338
        bpl     L63F6
        cpx     #$00
        bne     L63E5
        lda     #$92
        jmp     a2d_exit_with_a

L63E5:  lda     L6338
        and     #$7F
        beq     L63F6
        cpx     L6338
        beq     L63F6
        lda     #$91
        jmp     a2d_exit_with_a

L63F6:  stx     L6338
        lda     #$80
        sta     hide_cursor_flag
        lda     L6338
        bne     L640D
        bit     L6339
        bpl     L640D
        lda     #$00
        sta     L6339
L640D:  ldy     #$03
        lda     L6338
        sta     (params_addr),y
        iny
        lda     L6339
        sta     (params_addr),y
        bit     L6339
        bpl     L642A
        bit     L6337
        bpl     L642A
        MLI_CALL ALLOC_INTERRUPT, alloc_interrupt_params
L642A:  lda     $FBB3
        pha
        lda     #$06
        sta     $FBB3
        ldy     #SETMOUSE
        lda     #$01
        bit     L6339
        bpl     L643F
        cli
        ora     #$08
L643F:  jsr     call_mouse
        pla
        sta     $FBB3
        jsr     L5E51
        jsr     L6067
        jsr     CALL_2B_IMPL
        lda     #$00
        sta     L700C
L6454:  jsr     L653F
        jsr     L6588
        A2D_CALL A2D_SET_PATTERN, checkerboard_pattern
        A2D_CALL A2D_FILL_RECT, fill_rect_params
        jmp     L6556

.proc alloc_interrupt_params
count:  .byte   2
int_num:.byte   0
code:   .addr   interrupt_handler
.endproc

.proc dealloc_interrupt_params
count:  .byte   1
int_num:.byte   0
.endproc

L646F:
        lda     #$00
        sta     L633A
        lda     L6339
        beq     L648B
        cmp     #$01
        beq     L6486
        cmp     #$03
        bne     L648C
        lda     #$80
        sta     L633A
L6486:  lda     #$80
        sta     L6339
L648B:  rts

L648C:  lda     #$93
        jmp     a2d_exit_with_a

L6491:
        lda     L6337
        beq     L649F
        cmp     #$01
        beq     L64A4
        lda     #$90
        jmp     a2d_exit_with_a

L649F:  lda     #$80
        sta     L6337
L64A4:  rts

;;; ==================================================

;;; $1E IMPL

L64A5:
        ldy     #SETMOUSE
        lda     #MOUSE_MODE_OFF
        jsr     call_mouse
        ldy     #SERVEMOUSE
        jsr     call_mouse
        bit     L6339
        bpl     L64C7
        bit     L6337
        bpl     L64C7
        lda     alloc_interrupt_params::int_num
        sta     dealloc_interrupt_params::int_num
        MLI_CALL DEALLOC_INTERRUPT, dealloc_interrupt_params
L64C7:  lda     L6340
        pha
        plp
        lda     #$00
        sta     hide_cursor_flag
        rts

;;; ==================================================

;;; $1F IMPL

;;; 3 bytes of params, copied to $82

L64D2:
        lda     $82
        cmp     #$01
        bne     L64E5
        lda     $84
        bne     L64F6
        sta     L6522
        lda     $83
        sta     L6521
        rts

L64E5:  cmp     #$02
        bne     L6508
        lda     $84
        bne     L64FF
        sta     L6538
        lda     $83
        sta     L6537
        rts

L64F6:  lda     #$00
        sta     L6521
        sta     L6522
        rts

L64FF:  lda     #$00
        sta     L6537
        sta     L6538
        rts

L6508:  lda     #$94
        jmp     a2d_exit_with_a

L650D:  lda     L6522
        beq     L651D
        jsr     L653F
        jsr     L651E
        php
        jsr     L6556
        plp
L651D:  rts

L651E:  jmp     (L6521)

L6521:  .byte   0
L6522:  .byte   0
L6523:  lda     L6538
        beq     L6533
        jsr     L653F
        jsr     L6534
        php
        jsr     L6556
        plp
L6533:  rts

L6534:  jmp     (L6537)

L6537:  .byte   $00
L6538:  .byte   $00
L6539:  .byte   $00
L653A:  .byte   $00
L653B:  .byte   $00

L653C:  jsr     HIDE_CURSOR_IMPL
L653F:  lda     params_addr
        sta     L6539
        lda     params_addr+1
        sta     L653A
        lda     stack_ptr_stash
        sta     L653B
        lsr     preserve_zp_flag
        rts

L6553:  jsr     SHOW_CURSOR_IMPL
L6556:  asl     preserve_zp_flag
        lda     L6539
        sta     params_addr
        lda     L653A
        sta     params_addr+1
        lda     active_state
L6566           := * + 1
        ldx     active_state+1
L6567:  sta     $82
        stx     $83
        lda     L653B
        sta     stack_ptr_stash
        ldy     #sizeof_state-1
L6573:  lda     ($82),y
        sta     $D0,y
        dey
        bpl     L6573
        jmp     prepare_state

L657E:  lda     L6586
        ldx     L6587
        bne     L6567
L6586:
L6587           := * + 1
L6588           := * + 2
        asl     $205F,x
        ror     $2065,x
        .byte   0
        rti

        .byte   $06
        .addr   L6592
        rts

L6592:  .byte   $00,$00
L6594:  .byte   $0D,$00,$00,$20,$80,$00

.proc fill_rect_params
left:   .word   0
top:    .word   0
right:  .word   559
bottom: .word   191
.endproc
        fill_rect_params_top := fill_rect_params::top

        .byte   $00,$00,$00,$00,$00,$00,$00,$00

checkerboard_pattern:
        .byte   %01010101
        .byte   %10101010
        .byte   %01010101
        .byte   %10101010
        .byte   %01010101
        .byte   %10101010
        .byte   %01010101
        .byte   %10101010
        .byte   $00

;;; ==================================================

;;; $20 IMPL

;;; 2 bytes of params, copied to $82

L65B3:
        bit     $633F
        bmi     L65CD
        lda     $82
        sta     L6000
        lda     $83
        sta     L6001
        lda     L65D2
        ldx     L65D3
        ldy     #$02
        jmp     store_xa_at_params_y

L65CD:  lda     #$95
        jmp     a2d_exit_with_a

L65D2:  .byte   $F8
L65D3:  .byte   $5F

;;; ==================================================

L65D4:
        clc
        bcc     L65D8

;;; ==================================================

GET_INPUT_IMPL:
        sec
L65D8:  php
        bit     L6339
        bpl     L65E1
        sei
        bmi     L65E4
L65E1:  jsr     L6663
L65E4:  jsr     L67FE
L65E7:  bcs     L6604
        plp
        php
        bcc     L65F0
        sta     L6752
L65F0:  tax
        ldy     #0              ; Store 5 bytes at params
L65F3:  lda     L6754,x
        sta     (params_addr),y
        inx
        iny
        cpy     #4
        bne     L65F3
        lda     #$00
        sta     (params_addr),y
        beq     L6607
L6604:  jsr     L6645
L6607:  plp
        bit     L6339
        bpl     L660E
        cli
L660E:  rts

;;; ==================================================

;;; 5 bytes of params, copied to $82

SET_INPUT_IMPL:
        php
        sei
        lda     $82
        bmi     L6626
        cmp     #$06
        bcs     L663B
        cmp     #$03
        beq     L6626
        ldx     $83
        ldy     $84
        lda     $85
        jsr     L7E19
L6626:  jsr     L67E4
        bcs     L663F
        tax
        ldy     #$00
L662E:  lda     (params_addr),y
        sta     L6754,x
        inx
        iny
        cpy     #$04
        bne     L662E
        plp
        rts

L663B:  lda     #$98
        bmi     L6641
L663F:  lda     #$99
L6641:  plp
        jmp     a2d_exit_with_a

L6645:  lda     #0
        bit     mouse_status
        bpl     L664E
        lda     #4
L664E:  ldy     #0
        sta     (params_addr),y         ; Store 5 bytes at params
        iny
L6653:  lda     cursor_count,y
        sta     (params_addr),y
        iny
        cpy     #$05
        bne     L6653
        rts

;;; ==================================================

;;; $29 IMPL


.proc input
state:  .byte   0

key        := *
kmods      := * + 1

xpos       := *
ypos       := * + 2
modifiers  := * + 3

        .res    4, 0
.endproc

.proc L6663
        bit     L6339
        bpl     L666D
        lda     #$97
        jmp     a2d_exit_with_a

L666D:
        sec                     ; called from interrupt handler
        jsr     L650D
        bcc     end

        lda     BUTN1           ; Look at buttons (apple keys), compute modifiers
        asl     a
        lda     BUTN0
        and     #$80
        rol     a
        rol     a
        sta     input::modifiers

        jsr     L7F66
        jsr     L6265
        lda     mouse_status    ; bit 7 = is down, bit 6 = was down, still down
        asl     a
        eor     mouse_status
        bmi     L66B9           ; minus = (is down & !was down)

        bit     mouse_status
        bmi     end             ; minus = is down
        bit     L6813
        bpl     L66B9
        lda     L7D74
        bne     L66B9

        lda     KBD
        bpl     end             ; no key
        and     #$7F
        sta     input::key
        bit     KBDSTRB         ; clear strobe

        lda     input::modifiers
        sta     input::kmods
        lda     #A2D_INPUT_KEY
        sta     input::state
        bne     L66D8

L66B9:  bcc     up
        lda     input::modifiers
        beq     :+
        lda     #A2D_INPUT_DOWN_MOD
        bne     set_state

:       lda     #A2D_INPUT_DOWN
        bne     set_state

up:     lda     #A2D_INPUT_UP

set_state:
        sta     input::state

        ldx     #2
:       lda     set_pos_params,x
        sta     input::key,x
        dex
        bpl     :-

L66D8:  jsr     L67E4
        tax
        ldy     #$00
L66DE:  lda     input,y
        sta     L6754,x
        inx
        iny
        cpy     #$04
        bne     L66DE

end:    jmp     L6523
.endproc

;;; ==================================================
;;; Interrupt Handler

int_stash_zp:
        .res    9, 0
int_stash_rdpage2:
        .byte   0
int_stash_rd80store:
        .byte   0

.proc interrupt_handler
        cld                     ; required for interrupt handlers

        lda     RDPAGE2         ; record softswitch state
        sta     int_stash_rdpage2
        lda     RD80STORE
        sta     int_stash_rd80store
        lda     LOWSCR
        sta     SET80COL

        ldx     #8              ; preserve 9 bytes of ZP
sloop:  lda     $82,x
        sta     int_stash_zp,x
        dex
        bpl     sloop

        ldy     #SERVEMOUSE
        jsr     call_mouse
        bcs     :+
        jsr     L6663::L666D
        clc
:       bit     L633A
        bpl     :+
        clc                     ; carry clear if interrupt handled

:       ldx     #8              ; restore ZP
rloop:  lda     int_stash_zp,x
        sta     $82,x
        dex
        bpl     rloop

        lda     LOWSCR          ;  restore soft switches
        sta     CLR80COL
        lda     int_stash_rdpage2
        bpl     :+
        lda     HISCR
:       lda     int_stash_rd80store
        bpl     :+
        sta     SET80COL

:       rts
.endproc

;;; ==================================================

;;; $23 IMPL

L6747:
        lda     L6750
        ldx     L6751
        jmp     store_xa_at_params

L6750:  .byte   $F9
L6751:  .byte   $66

;;; ==================================================

;;; $2B IMPL

;;; This is called during init by the DAs, just before
;;; entering the input loop.

L6752:  .byte   0
L6753:  .byte   0

L6754:  .byte   $00
L6755:  .res    128, 0
        .byte   $00,$00,$00

.proc CALL_2B_IMPL
        php
        sei
        lda     #0
        sta     L6752
        sta     L6753
        plp
        rts
.endproc
        ;; called during SET_INPUT and a few other places
.proc L67E4
        lda     L6753
        cmp     #$80            ; if L675E is not $80, add $4
        bne     :+
        lda     #$00            ; otherwise reset to 0
        bcs     compare
:       clc
        adc     #$04

compare:
        cmp     L6752           ; did L6753 catch up with L6752?
        beq     rts_with_carry_set
        sta     L6753           ; nope, maybe next time
        clc
        rts
.endproc

rts_with_carry_set:
        sec
        rts

        ;; called during GET_INPUT
L67FE:  lda     L6752           ; equal?
        cmp     L6753
        beq     rts_with_carry_set
        cmp     #$80
        bne     L680E
        lda     #0
        bcs     L6811
L680E:  clc
        adc     #$04
L6811:  clc
        rts

;;; ==================================================

;;; $2E IMPL

;;; 1 byte of params, copied to $82

L6813:  .byte   $80
L6814:
        asl     L6813
        ror     $82
        ror     L6813
        rts

L681D:  .byte   $02
L681E:  .byte   $09
L681F:  .byte   $10
L6820:  .byte   $09
L6821:  .byte   $1E
L6822:  .byte   $00

active_menu:
        .addr   0


.proc test_box_params
left:   .word   $ffff
top:    .word   $ffff
right:  .word   $230
bottom: .word   $C
.endproc
        test_box_params_top := test_box_params::top
        test_box_params_bottom := test_box_params::bottom

.proc fill_rect_params2
left:   .word   0
top:    .word   0
width:  .word   0
height: .word   11
.endproc
        fill_rect_params2_height := fill_rect_params2::height

L6835:  .byte   $00
L6836:  .byte   $00

.proc test_box_params2
left:   .word   0
top:    .word   12
right:  .word   0
bottom: .word   0
.endproc
        test_box_params2_top := test_box_params2::top

.proc fill_rect_params4
left:   .word   0
top:    .word   12
right:  .word   0
bottom: .word   0
.endproc
        fill_rect_params4_top := fill_rect_params4::top

L6847:  .byte   $0C
L6848:  .byte   $18,$24,$30,$3C,$48,$54,$60,$6C
        .byte   $78,$84,$90,$9C,$A8,$B4
L6856:  .byte   $1E
L6857:  .byte   $1F
L6858:  .byte   $1D
L6859:  .byte   $01,$02
L685B:  .byte   $1E
L685C:  .byte   $FF,$01
L685E:  .byte   $1D
L685F:  .byte   $25
L6860:  .byte   $68
L6861:  .byte   $37
L6862:  .byte   $68
L6863:  .byte   $5D
L6864:  .byte   $68
L6865:  .byte   $5A
L6866:  .byte   $68

get_menu_count:
        lda     active_menu
        sta     $82
        lda     active_menu+1
        sta     $83
        ldy     #0
        lda     ($82),y
        sta     $A8
        rts

L6878:  stx     $A7
        lda     #$02
        clc
L687D:  dex
        bmi     L6884
        adc     #$0C
        bne     L687D
L6884:  adc     active_menu
        sta     $AB
        lda     active_menu+1
        adc     #$00
        sta     $AC
        ldy     #$0B
L6892:  lda     ($AB),y
        sta     $AF,y
        dey
        bpl     L6892
        ldy     #$05
L689C:  lda     ($B3),y
        sta     $BA,y
        dey
        bne     L689C
        lda     ($B3),y
        sta     $AA
        rts

L68A9:  ldy     #$0B
L68AB:  lda     $AF,y
        sta     ($AB),y
        dey
        bpl     L68AB
        ldy     #$05
L68B5:  lda     $BA,y
        sta     ($B3),y
        dey
        bne     L68B5
        rts

L68BE:  stx     $A9
        lda     #$06
        clc
L68C3:  dex
        bmi     L68CA
        adc     #$06
        bne     L68C3
L68CA:  adc     $B3
        sta     $AD
        lda     $B4
        adc     #$00
        sta     $AE
        ldy     #$05
L68D6:  lda     ($AD),y
        sta     $BF,y
        dey
        bpl     L68D6
        rts

L68DF:  ldy     #$05
L68E1:  lda     $BF,y
        sta     ($AD),y
        dey
        bpl     L68E1
        rts

L68EA:  sty     state_ypos
        ldy     #0
        sty     state_ypos+1
L68F0:  sta     state_xpos
        stx     state_xpos+1
        rts

        ;; Set fill mode to A
set_fill_mode:
        sta     state_fill
        jmp     SET_FILL_MODE_IMPL

do_measure_text:
        jsr     prepare_text_params
        jmp     measure_text

draw_text:
        jsr     prepare_text_params
        jmp     DRAW_TEXT_IMPL

        ;; Prepare $A1,$A2 as params for MEASURE_TEXT/DRAW_TEXT call
        ;; ($A3 is length)
prepare_text_params:
        sta     $82
        stx     $83
        clc
        adc     #1
        bcc     L6910
        inx
L6910:  sta     $A1
        stx     $A2
        ldy     #0
        lda     ($82),y
        sta     $A3
        rts

L691B:  A2D_CALL A2D_GET_INPUT, $82
        lda     $82
        rts

;;; ==================================================

;;; SET_MENU IMPL

L6924:  .byte   0
L6925:  .byte   0

SET_MENU_IMPL:
        lda     #$00
        sta     L633D
        sta     L633E
        lda     params_addr
        sta     active_menu
        lda     params_addr+1
        sta     active_menu+1

        jsr     get_menu_count  ; into $A8
        jsr     L653C
        jsr     L657E
        lda     L685F
        ldx     L6860
        jsr     fill_and_frame_rect

        lda     #$0C
        ldx     #$00
        ldy     L6822
        iny
        jsr     L68EA
        ldx     #$00
L6957:  jsr     L6878
        lda     state_xpos
        ldx     state_xpos+1
        sta     $B5
        stx     $B6
        sec
        sbc     #$08
        bcs     L6968
        dex
L6968:  sta     $B7
        stx     $B8
        sta     $BB
        stx     $BC
        ldx     #$00
        stx     $C5
        stx     $C6
L6976:  jsr     L68BE
        bit     $BF
        bvs     L69B4
        lda     $C3
        ldx     $C3+1
        jsr     do_measure_text
        sta     $82
        stx     $83
        lda     $BF
        and     #$03
        bne     L6997
        lda     $C1
        bne     L6997
        lda     L6820
        bne     L699A
L6997:  lda     L6821
L699A:  clc
        adc     $82
        sta     $82
        bcc     L69A3
        inc     $83
L69A3:  sec
        sbc     $C5
        lda     $83
        sbc     $C6
        bmi     L69B4
        lda     $82
        sta     $C5
        lda     $83
        sta     $C6
L69B4:  ldx     $A9
        inx
        cpx     $AA
        bne     L6976
        lda     $AA
        tax
        ldy     L6822
        iny
        iny
        iny
        jsr     L4F70
        pha
        lda     $C5
        sta     $A1
        lda     $C6
        sta     $A2
        lda     #$07
        sta     $A3
        lda     #$00
        sta     $A4
        jsr     L5698
        ldy     $A1
        iny
        iny
        pla
        tax
        jsr     L4F70
        sta     L6924
        sty     L6925
        sec
        sbc     L633D
        tya
        sbc     L633E
        bmi     L6A00
        lda     L6924
        sta     L633D
        lda     L6925
        sta     L633E
L6A00:  lda     $BB
        clc
        adc     $C5
        sta     $BD
        lda     $BC
        adc     #$00
        sta     $BE
        jsr     L68A9
        lda     $B1
        ldx     $B1+1
        jsr     draw_text
        jsr     L6A5C
        lda     state_xpos
        ldx     state_xpos+1
        clc
        adc     #$08
        bcc     L6A24
        inx
L6A24:  sta     $B9
        stx     $BA
        jsr     L68A9
        lda     #<12
        ldx     #>12
        jsr     adjust_xpos
        ldx     $A7
        inx
        cpx     $A8
        beq     L6A3C
        jmp     L6957

L6A3C:  lda     #$00
        sta     L7D7A
        sta     L7D7B
        jsr     L6553
        sec
        lda     L633B
        sbc     L633D
        lda     L633C
        sbc     L633E
        bpl     L6A5B
        lda     #$9C
        jmp     a2d_exit_with_a

L6A5B:  rts

L6A5C:  ldx     $A7
        jsr     L6878
        ldx     $A9
        jmp     L68BE

        ;; Fills rect (params at X,A) then inverts border
.proc fill_and_frame_rect
        sta     fill_params
        stx     fill_params+1
        sta     draw_params
        stx     draw_params+1
        lda     #0
        jsr     set_fill_mode
        A2D_CALL A2D_FILL_RECT, 0, fill_params
        lda     #4
        jsr     set_fill_mode
        A2D_CALL A2D_DRAW_RECT, 0, draw_params
        rts
.endproc

L6A89:  jsr     L6A94
        bne     L6A93
        lda     #$9A
        jmp     a2d_exit_with_a

L6A93:  rts

L6A94:  lda     #$00
L6A96:  sta     $C6
        jsr     get_menu_count
        ldx     #$00
L6A9D:  jsr     L6878
        bit     $C6
        bvs     L6ACA
        bmi     L6AAE
        lda     $AF
        cmp     $C7
        bne     L6ACF
        beq     L6AD9
L6AAE:  lda     set_pos_params::xcoord
        ldx     set_pos_params::xcoord+1
        cpx     $B8
        bcc     L6ACF
        bne     L6ABE
        cmp     $B7
        bcc     L6ACF
L6ABE:  cpx     $BA
        bcc     L6AD9
        bne     L6ACF
        cmp     $B9
        bcc     L6AD9
        bcs     L6ACF
L6ACA:  jsr     L6ADC
        bne     L6AD9
L6ACF:  ldx     $A7
        inx
        cpx     $A8
        bne     L6A9D
        lda     #$00
        rts

L6AD9:  lda     $AF
        rts

L6ADC:  ldx     #$00
L6ADE:  jsr     L68BE
        ldx     $A9
        inx
        bit     $C6
        bvs     L6AFA
        bmi     L6AF0
        cpx     $C8
        bne     L6B16
        beq     L6B1C
L6AF0:  lda     L6847,x
        cmp     set_pos_params::ycoord
        bcs     L6B1C
        bcc     L6B16
L6AFA:  lda     $C9
        and     #$7F
        cmp     $C1
        beq     L6B06
        cmp     $C2
        bne     L6B16
L6B06:  cmp     #$20
        bcc     L6B1C
        lda     $BF
        and     #$C0
        bne     L6B16
        lda     $BF
        and     $CA
        bne     L6B1C
L6B16:  .byte   $E4
L6B17:  tax
        bne     L6ADE
        ldx     #$00
L6B1C:  rts

;;; ==================================================

;;; $33 IMPL

;;; 2 bytes of params, copied to $C7

L6B1D:  lda     $C7
        bne     L6B26
        lda     L6BD9
        sta     $C7
L6B26:  jsr     L6A89
L6B29:  jsr     L653C
        jsr     L657E
        jsr     L6B35
        jmp     L6553

        ;; Highlight/Unhighlight top level menu item
.proc L6B35
        ldx     #$01
loop:   lda     $B7,x
        sta     fill_rect_params2::left,x
        lda     $B9,x
        sta     fill_rect_params2::width,x
        lda     $BB,x
        sta     test_box_params2::left,x
        sta     fill_rect_params4::left,x
        lda     $BD,x
        sta     test_box_params2::right,x
        sta     fill_rect_params4::right,x
        dex
        bpl     loop
        lda     #$02
        jsr     set_fill_mode
        A2D_CALL A2D_FILL_RECT, fill_rect_params2
        rts
.endproc

;;; ==================================================

;;; $32 IMPL

;;; 4 bytes of params, copied to $C7

L6B60:
        lda     $C9
        cmp     #$1B            ; Menu height?
        bne     L6B70
        lda     $CA
        bne     L6B70
        jsr     L7D61
        jmp     MENU_CLICK_IMPL

L6B70:  lda     #$C0
        jsr     L6A96
        beq     L6B88
        lda     $B0
        bmi     L6B88
        lda     $BF
        and     #$C0
        bne     L6B88
        lda     $AF
        sta     L6BD9
        bne     L6B8B
L6B88:  lda     #$00
        tax
L6B8B:  ldy     #$00
        sta     (params_addr),y
        iny
        txa
        sta     (params_addr),y
        bne     L6B29
        rts

L6B96:  jsr     L6A89
        jsr     L6ADC
        cpx     #$00
L6B9E:  rts

L6B9F:  jsr     L6B96
        bne     L6B9E
        lda     #$9B
        jmp     a2d_exit_with_a

;;; ==================================================

;;; $35 IMPL

;;; 3 bytes of params, copied to $C7

L6BA9:
        jsr     L6B9F
        asl     $BF
        ror     $C9
        ror     $BF
        jmp     L68DF

;;; ==================================================

;;; $36 IMPL

;;; 3 bytes of params, copied to $C7

L6BB5:
        jsr     L6B9F
        lda     $C9
        beq     L6BC2
        lda     #$20
        ora     $BF
        bne     L6BC6
L6BC2:  lda     #$DF
        and     $BF
L6BC6:  sta     $BF
        jmp     L68DF

;;; ==================================================

;;; $34 IMPL

;;; 2 bytes of params, copied to $C7

L6BCB:
        jsr     L6A89
        asl     $B0
        ror     $C8
        ror     $B0
        ldx     $A7
        jmp     L68A9

;;; ==================================================

;;; MENU_CLICK IMPL

L6BD9:  .byte   0
L6BDA:  .byte   0

MENU_CLICK_IMPL:
        jsr     L7ECD
        jsr     get_menu_count
        jsr     L653F
        jsr     L657E
        bit     L7D74
        bpl     L6BF2
        jsr     L7FE1
        jmp     L6C23

L6BF2:  lda     #0
        sta     L6BD9
        sta     L6BDA
        jsr     L691B
L6BFD:  bit     L7D81
        bpl     L6C05
        jmp     L8149

L6C05:  A2D_CALL A2D_SET_POS, $83
        A2D_CALL A2D_TEST_BOX, test_box_params
        bne     L6C58
        lda     L6BD9
        beq     L6C23
        A2D_CALL A2D_TEST_BOX, test_box_params2
        bne     L6C73
        jsr     L6EA1
L6C23:  jsr     L691B
        beq     L6C2C
        cmp     #$02
        bne     L6BFD
L6C2C:  lda     L6BDA
        bne     L6C37
        jsr     L6D23
        jmp     L6C40

L6C37:  jsr     HIDE_CURSOR_IMPL
        jsr     L657E
        jsr     L6CF4
L6C40:  jsr     L6556
        lda     #$00
        ldx     L6BDA
        beq     L6C55
        lda     L6BD9
        ldy     $A7
        sty     L7D7A
        stx     L7D7B
L6C55:  jmp     store_xa_at_params

L6C58:  jsr     L6EA1
        lda     #$80
        jsr     L6A96
        cmp     L6BD9
        beq     L6C23
        pha
        jsr     L6D23
        pla
        sta     L6BD9
        jsr     L6D26
        jmp     L6C23

L6C73:  lda     #$80
        sta     $C6
        jsr     L6ADC
        cpx     L6BDA
        beq     L6C23
        lda     $B0
        ora     $BF
        and     #$C0
        beq     L6C89
        ldx     #$00
L6C89:  txa
        pha
        jsr     L6EAA
        pla
        sta     L6BDA
        jsr     L6EAA
        jmp     L6C23

L6C98:  lda     $BC
        lsr     a
        lda     $BB
        ror     a
        tax
        lda     L4821,x
        sta     $82
        lda     $BE
        lsr     a
        lda     $BD
        ror     a
        tax
        lda     L4821,x
        sec
        sbc     $82
        sta     $90
        lda     L6835
        sta     $8E
        lda     L6836
        sta     $8F
        ldy     $AA
        ldx     L6847,y
        inx
        stx     $83
        stx     fill_rect_params4::bottom
        stx     test_box_params2::bottom
        ldx     L6822
        inx
        inx
        inx
        stx     fill_rect_params4::top
        stx     test_box_params2::top
        rts

L6CD8:  lda     hires_table_lo,x
        clc
        adc     $82
        sta     $84
        lda     hires_table_hi,x
        ora     #$20
        sta     $85
        rts

L6CE8:  lda     $8E
        sec
        adc     $90
        sta     $8E
        bcc     L6CF3
        inc     $8F
L6CF3:  rts

L6CF4:  jsr     L6C98
L6CF7:  jsr     L6CD8
        sta     HISCR
        ldy     $90
L6CFF:  lda     ($8E),y
        sta     ($84),y
        dey
        bpl     L6CFF
        jsr     L6CE8
        sta     LOWSCR
        ldy     $90
L6D0E:  lda     ($8E),y
        sta     ($84),y
        dey
        bpl     L6D0E
        jsr     L6CE8
        inx
        cpx     $83
        bcc     L6CF7
        beq     L6CF7
        jmp     SHOW_CURSOR_IMPL

L6D22:  rts

L6D23:  clc
        bcc     L6D27
L6D26:  sec
L6D27:  lda     L6BD9
        beq     L6D22
        php
        sta     $C7
        jsr     L6A94
        jsr     HIDE_CURSOR_IMPL
        jsr     L6B35
        plp
        bcc     L6CF4
        jsr     L6C98
L6D3E:  jsr     L6CD8
        sta     HISCR
        ldy     $90
L6D46:  lda     ($84),y
        sta     ($8E),y
        dey
        bpl     L6D46
        jsr     L6CE8
        sta     LOWSCR
        ldy     $90
L6D55:  lda     ($84),y
        sta     ($8E),y
        dey
        bpl     L6D55
        jsr     L6CE8
        inx
        cpx     $83
        bcc     L6D3E
        beq     L6D3E
        jsr     L657E
        lda     L6861
        ldx     L6862
        jsr     fill_and_frame_rect
        inc     fill_rect_params4::left
        bne     L6D7A
        inc     fill_rect_params4::left+1
L6D7A:  lda     fill_rect_params4::right
        bne     L6D82
        dec     fill_rect_params4::right+1
L6D82:  dec     fill_rect_params4::right
        jsr     L6A5C
        ldx     #$00
L6D8A:  jsr     L68BE
        bit     $BF
        bvc     L6D94
        jmp     L6E18

L6D94:  lda     $BF
        and     #$20
        beq     L6DBD
        lda     L681D
        jsr     L6E25
        lda     L6858
        sta     L685E
        lda     $BF
        and     #$04
        beq     L6DB1
        lda     $C0
        sta     L685E
L6DB1:  lda     L6863
        ldx     L6863+1
        jsr     draw_text
        jsr     L6A5C
L6DBD:  lda     L681E
        jsr     L6E25
        lda     $C3
        ldx     $C3+1
        jsr     draw_text
        jsr     L6A5C
        lda     $BF
        and     #$03
        bne     L6DE0
        lda     $C1
        beq     L6E0A
        lda     L6859
        sta     L685B
        jmp     L6E0A

L6DE0:  cmp     #$01
        bne     L6DED
        lda     L6857
        sta     L685B
        jmp     L6DF3

L6DED:  lda     L6856
        sta     L685B
L6DF3:  lda     $C1
        sta     L685C
        lda     L681F
        jsr     L6E92
        lda     L6865
        ldx     L6865+1
        jsr     draw_text
        jsr     L6A5C
L6E0A:  bit     $B0
        bmi     L6E12
        bit     $BF
        bpl     L6E18
L6E12:  jsr     L6E36
        jmp     L6E18

L6E18:  ldx     $A9
        inx
        cpx     $AA
        beq     L6E22
        jmp     L6D8A

L6E22:  jmp     SHOW_CURSOR_IMPL

L6E25:  ldx     $A9
        ldy     L6848,x
        dey
        ldx     $BC
        clc
        adc     $BB
        bcc     L6E33
        inx
L6E33:  jmp     L68EA

L6E36:  ldx     $A9
        lda     L6847,x
        sta     fill_rect_params3_top
        inc     fill_rect_params3_top
        lda     L6848,x
        sta     fill_rect_params3_bottom
        clc
        lda     $BB
        adc     #$05
        sta     fill_rect_params3_left
        lda     $BC
        adc     #$00
        sta     fill_rect_params3_left+1
        sec
        lda     $BD
        sbc     #$05
        sta     fill_rect_params3_right
        lda     $BE
        sbc     #$00
        sta     fill_rect_params3_right+1
        A2D_CALL A2D_SET_PATTERN, light_speckle_pattern
        lda     #$01
        jsr     set_fill_mode
        A2D_CALL A2D_FILL_RECT, fill_rect_params3
        A2D_CALL A2D_SET_PATTERN, screen_state::pattern
        lda     #$02
        jsr     set_fill_mode
        rts

light_speckle_pattern:
        .byte   %10001000
        .byte   %01010101
        .byte   %10001000
        .byte   %01010101
        .byte   %10001000
        .byte   %01010101
        .byte   %10001000
        .byte   %01010101

.proc fill_rect_params3
left:   .word   0
top:    .word   0
right:  .word   0
bottom: .word   0
.endproc
        fill_rect_params3_left := fill_rect_params3::left
        fill_rect_params3_top := fill_rect_params3::top
        fill_rect_params3_right := fill_rect_params3::right
        fill_rect_params3_bottom := fill_rect_params3::bottom

L6E92:  sta     $82
        lda     $BD
        ldx     $BE
        sec
        sbc     $82
        bcs     L6E9E
        dex
L6E9E:  jmp     L68F0

L6EA1:  jsr     L6EAA
        lda     #$00
        sta     L6BDA
L6EA9:  rts

L6EAA:  ldx     L6BDA
        beq     L6EA9
        ldy     fill_rect_params4::bottom+1,x ; ???
        iny
        sty     fill_rect_params4::top
        ldy     L6847,x
        sty     fill_rect_params4::bottom
        jsr     HIDE_CURSOR_IMPL
        lda     #$02
        jsr     set_fill_mode
        A2D_CALL A2D_FILL_RECT, fill_rect_params4
        jmp     SHOW_CURSOR_IMPL

;;; ==================================================

;;; $2F IMPL

;;; 4 bytes of params, copied to $82

.proc L6ECD
        ldx     #$03
loop:   lda     $82,x
        sta     L6856,x
        dex
        bpl     loop
        lda     screen_state::font
        sta     $82
        lda     screen_state::font+1
        sta     $83
        ldy     #$00
        lda     ($82),y
        bmi     :+

        lda     #$02
        sta     L681D
        lda     #$09
        sta     L681E
        lda     #$10
        sta     L681F
        lda     #$09
        sta     L6820
        lda     #$1E
        sta     L6821
        bne     end

:       lda     #$02
        sta     L681D
        lda     #$10
        sta     L681E
        lda     #$1E
        sta     L681F
        lda     #$10
        sta     L6820
        lda     #$33
        sta     L6821
end:    rts
.endproc

;;; ==================================================

;;; $37 IMPL

;;; 4 bytes of params, copied to $C7

L6F1C:
        jsr     L6B9F
        lda     $C9
        beq     L6F30
        lda     #$04
        ora     $BF
        sta     $BF
        lda     $CA
        sta     $C0
        jmp     L68DF

L6F30:  lda     #$FB
        and     $BF
        sta     $BF
        jmp     L68DF

.proc up_scroll_params
        .byte   $00,$00
incr:   .byte   $00,$00
        .byte   $13,$0A
        .addr   up_scroll_bitmap
.endproc

.proc down_scroll_params
        .byte   $00,$00
unk1:   .byte   $00
unk2:   .byte   $00
        .byte   $13,$0A
        .addr   down_scroll_bitmap
.endproc

.proc left_scroll_params
        .byte   $00,$00,$00,$00
        .byte   $14,$09
        .addr   left_scroll_bitmap
.endproc

.proc right_scroll_params
        .byte   $00
        .byte   $00,$00,$00
        .byte   $12,$09
        .addr   right_scroll_bitmap
.endproc

.proc resize_box_params
        .byte   $00,$00,$00,$00
        .byte   $14,$0A
        .addr   resize_box_bitmap
.endproc

        ;;  Up Scroll
up_scroll_bitmap:
        .byte   px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0001100),px(%0000000)
        .byte   px(%0000000),px(%0110011),px(%0000000)
        .byte   px(%0000001),px(%1000000),px(%1100000)
        .byte   px(%0000110),px(%0000000),px(%0011000)
        .byte   px(%0011111),px(%1000000),px(%1111110)
        .byte   px(%0000001),px(%1000000),px(%1100000)
        .byte   px(%0000001),px(%1000000),px(%1100000)
        .byte   px(%0000001),px(%1111111),px(%1100000)
        .byte   px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0111111),px(%1111111),px(%1111111)

        ;; Down Scroll
down_scroll_bitmap:
        .byte   px(%0111111),px(%1111111),px(%1111111)
        .byte   px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000001),px(%1111111),px(%1100000)
        .byte   px(%0000001),px(%1000000),px(%1100000)
        .byte   px(%0000001),px(%1000000),px(%1100000)
        .byte   px(%0011111),px(%1000000),px(%1111110)
        .byte   px(%0000110),px(%0000000),px(%0011000)
        .byte   px(%0000001),px(%1000000),px(%1100000)
        .byte   px(%0000000),px(%0110011),px(%0000000)
        .byte   px(%0000000),px(%0001100),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000)

        ;;  Left Scroll
left_scroll_bitmap:
        .byte   px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0001100),px(%0000001)
        .byte   px(%0000000),px(%0111100),px(%0000001)
        .byte   px(%0000001),px(%1001111),px(%1111001)
        .byte   px(%0000110),px(%0000000),px(%0011001)
        .byte   px(%0011000),px(%0000000),px(%0011001)
        .byte   px(%0000110),px(%0000000),px(%0011001)
        .byte   px(%0000001),px(%1001111),px(%1111001)
        .byte   px(%0000000),px(%0111100),px(%0000001)
        .byte   px(%0000000),px(%0001100),px(%0000001)

        ;; Right Scroll
right_scroll_bitmap:
        .byte   px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%1000000),px(%0011000),px(%0000000)
        .byte   px(%1000000),px(%0011110),px(%0000000)
        .byte   px(%1001111),px(%1111001),px(%1000000)
        .byte   px(%1001100),px(%0000000),px(%0110000)
        .byte   px(%1001100),px(%0000000),px(%0001100)
        .byte   px(%1001100),px(%0000000),px(%0110000)
        .byte   px(%1001111),px(%1111001),px(%1000000)
        .byte   px(%1000000),px(%0011110),px(%0000000)
        .byte   px(%1000000),px(%0011000),px(%0000000)

L6FDF:  .byte   0

        ;; Resize Box
resize_box_bitmap:
        .byte   px(%1111111),px(%1111111),px(%1111111)
        .byte   px(%1000000),px(%0000000),px(%0000001)
        .byte   px(%1001111),px(%1111110),px(%0000001)
        .byte   px(%1001100),px(%0000111),px(%1111001)
        .byte   px(%1001100),px(%0000110),px(%0011001)
        .byte   px(%1001100),px(%0000110),px(%0011001)
        .byte   px(%1001111),px(%1111110),px(%0011001)
        .byte   px(%1000011),px(%0000000),px(%0011001)
        .byte   px(%1000011),px(%1111111),px(%1111001)
        .byte   px(%1000000),px(%0000000),px(%0000001)
        .byte   px(%1111111),px(%1111111),px(%1111111)

up_scroll_params_addr:
        .addr   up_scroll_params

down_scroll_params_addr:
        .addr   down_scroll_params

left_scroll_params_addr:
        .addr   left_scroll_params

right_scroll_params_addr:
        .addr   right_scroll_params

resize_box_params_addr:
        .addr   resize_box_params

L700B:  .byte   $00
L700C:  .byte   $00
L700D:  .byte   $00
L700E:  .byte   $00
L700F:  .byte   $00
L7010:  .byte   $00

L7011:  .addr   $6FD3

        ;; Start window enumeration at top ???
.proc top_window
        lda     L7011
        sta     $A7
        lda     L7011+1
        sta     $A7+1
        lda     L700B
        ldx     L700B+1
        bne     next_window_L7038
end:    rts
.endproc

        ;; Look up next window in chain. $A9/$AA will point at
        ;; window params block (also returned in X,A).
.proc next_window
        lda     $A9
        sta     $A7
        lda     $A9+1
        sta     $A7+1
        ldy     #next_offset_in_window_params+1
        lda     ($A9),y
        beq     top_window::end  ; if high byte is 0, end of chain
        tax
        dey
        lda     ($A9),y
L7038:  sta     L700E
        stx     L700E+1
L703E:  lda     L700E
        ldx     L700E+1
L7044:  sta     $A9
        stx     $A9+1
        ldy     #$0B            ; copy first 12 bytes of window defintion to
L704A:  lda     ($A9),y         ; to $AB
        sta     $AB,y
        dey
        bpl     L704A
        ldy     #sizeof_state-1
L7054:  lda     ($A9),y
        sta     $A3,y
        dey
        cpy     #$13
        bne     L7054
L705E:  lda     $A9
        ldx     $A9+1
        rts
.endproc
        next_window_L7038 := next_window::L7038

        ;; Look up window state by id (in $82); $A9/$AA will point at
        ;; window params (also X,A).
.proc window_by_id
        jsr     top_window
        beq     end
loop:   lda     $AB
        cmp     $82
        beq     next_window::L705E
        jsr     next_window
        bne     loop
end:    rts
.endproc

        ;; Look up window state by id (in $82); $A9/$AA will point at
        ;; window params (also X,A).
        ;; This will exit the A2D call directly (restoring stack, etc)
        ;; if the window is not found.
.proc window_by_id_or_exit
        jsr     window_by_id
        beq     nope
        rts
nope:   lda     #$9F
        jmp     a2d_exit_with_a
.endproc

L707F:  A2D_CALL A2D_DRAW_RECT, $C7
        rts

L7086:  A2D_CALL A2D_TEST_BOX, $C7
        rts

L708D:  ldx     #$03
L708F:  lda     $B7,x
        sta     $C7,x
        dex
        bpl     L708F
        ldx     #$02
L7098:  lda     $C3,x
        sec
        sbc     $BF,x
        tay
        lda     $C4,x
        sbc     $C0,x
        pha
        tya
        clc
        adc     $C7,x
        sta     $CB,x
        pla
        adc     $C8,x
        sta     $CC,x
        dex
        dex
        bpl     L7098
L70B2:  lda     #$C7
        ldx     #$00
        rts

L70B7:  jsr     L708D
        lda     $C7
        bne     L70C0
        dec     $C8
L70C0:  dec     $C7
        bit     $B0
        bmi     L70D0
        lda     $AC
        and     #$04
        bne     L70D0
        lda     #$01
        bne     L70D2
L70D0:  lda     #$15
L70D2:  clc
        adc     $CB
        sta     $CB
        bcc     L70DB
        inc     $CC
L70DB:  lda     #$01
        bit     $AF
        bpl     L70E3
        lda     #$0B
L70E3:  clc
        adc     $CD
        sta     $CD
        bcc     L70EC
        inc     $CE
L70EC:  lda     #$01
        and     $AC
        bne     L70F5
        lda     L78CF
L70F5:  sta     $82
        lda     $C9
        sec
        sbc     $82
        sta     $C9
        bcs     L70B2
        dec     $CA
        bcc     L70B2
L7104:  jsr     L70B7
        lda     $CB
        ldx     $CC
        sec
        sbc     #$14
        bcs     L7111
        dex
L7111:  sta     $C7
        stx     $C8
        lda     $AC
        and     #$01
        bne     L70B2
        lda     $C9
        clc
        adc     L78CD
        sta     $C9
        bcc     L70B2
        inc     $CA
        bcs     L70B2
L7129:  jsr     L70B7
L712C:  lda     $CD
        ldx     $CE
        sec
        sbc     #$0A
        bcs     L7136
        dex
L7136:  sta     $C9
        stx     $CA
        jmp     L70B2

L713D:  jsr     L7104
        jmp     L712C

L7143:  jsr     L70B7
        lda     $C9
        clc
        adc     L78CD
        sta     $CD
        lda     $CA
        adc     #$00
        sta     $CE
        jmp     L70B2

L7157:  jsr     L7143
        lda     $C7
        ldx     $C8
        clc
        adc     #$0C
        bcc     L7164
        inx
L7164:  sta     $C7
        stx     $C8
        clc
        adc     #$0E
        bcc     L716E
        inx
L716E:  sta     $CB
        stx     $CC
        lda     $C9
        ldx     $CA
        clc
        adc     #$02
        bcc     L717C
        inx
L717C:  sta     $C9
        stx     $CA
        clc
        adc     L78CB
        bcc     L7187
        inx
L7187:  sta     $CD
        stx     $CE
        jmp     L70B2

L718E:  jsr     L70B7
        jsr     fill_and_frame_rect
        lda     $AC
        and     #$01
        bne     L71AA
        jsr     L7143
        jsr     fill_and_frame_rect
        jsr     L73BF
        lda     $AD
        ldx     $AD+1
        jsr     draw_text
L71AA:  jsr     next_window::L703E
        bit     $B0
        bpl     L71B7
        jsr     L7104
        jsr     L707F
L71B7:  bit     $AF
        bpl     L71C1
        jsr     L7129
        jsr     L707F
L71C1:  lda     $AC
        and     #$04
        beq     L71D3
        jsr     L713D
        jsr     L707F
        jsr     L7104
        jsr     L707F
L71D3:  jsr     next_window::L703E
        lda     $AB
        cmp     L700D
        bne     L71E3
        jsr     L6588
        jmp     L720B

L71E3:  rts

        ;;  Drawing title bar, maybe?
L71E4:  .byte   $01
stripes_pattern:
stripes_pattern_alt := *+1
        .byte   %11111111
        .byte   %00000000
        .byte   %11111111
        .byte   %00000000
        .byte   %11111111
        .byte   %00000000
        .byte   %11111111
        .byte   %00000000
        .byte   %11111111

L71EE:  jsr     L7157
        lda     $C9
        and     #$01
        beq     L71FE
        A2D_CALL A2D_SET_PATTERN, stripes_pattern
        rts

L71FE:  A2D_CALL A2D_SET_PATTERN, stripes_pattern_alt
        rts

L7205:  lda     #$01
        ldx     #$00
        beq     L720F
L720B:  lda     #$03
        ldx     #$01
L720F:  stx     L71E4
        jsr     set_fill_mode
        lda     $AC
        and     #$02
        beq     L7255
        lda     $AC
        and     #$01
        bne     L7255
        jsr     L7157
        jsr     L707F
        jsr     L71EE
        lda     $C7
        ldx     $C8
        sec
        sbc     #$09
        bcs     L7234
        dex
L7234:  sta     $92
        stx     $93
        clc
        adc     #$06
        bcc     L723E
        inx
L723E:  sta     $96
        stx     $97
        lda     $C9
        sta     $94
        lda     $CA
        sta     $95
        lda     $CD
        sta     $98
        lda     $CE
        sta     $99
        jsr     FILL_RECT_IMPL  ; draws title bar stripes to left of close box
L7255:  lda     $AC
        and     #$01
        bne     L72C9
        jsr     L7143
        jsr     L73BF
        jsr     L5907
        jsr     L71EE
        lda     $CB
        ldx     $CC
        clc
        adc     #$03
        bcc     L7271
        inx
L7271:  tay
        lda     $AC
        and     #$02
        bne     L7280
        tya
        sec
        sbc     #$1A
        bcs     L727F
        dex
L727F:  tay
L7280:  tya
        ldy     $96
        sty     $CB
        ldy     $97
        sty     $CC
        ldy     $92
        sty     $96
        ldy     $93
        sty     $97
        sta     $92
        stx     $93
        lda     $96
        sec
        sbc     #$0A
        sta     $96
        bcs     L72A0
        dec     $97
L72A0:  jsr     FILL_RECT_IMPL  ; Draw title bar stripes between close box and title
        lda     $CB
        clc
        adc     #$0A
        sta     $92
        lda     $CC
        adc     #$00
        sta     $93
        jsr     L7143
        lda     $CB
        sec
        sbc     #$03
        sta     $96
        lda     $CC
        sbc     #$00
        sta     $97
        jsr     FILL_RECT_IMPL  ; Draw title bar stripes to right of title
        A2D_CALL A2D_SET_PATTERN, screen_state::pattern
L72C9:  jsr     next_window::L703E
        bit     $B0
        bpl     L7319
        jsr     L7104
        ldx     #$03
L72D5:  lda     $C7,x
        sta     up_scroll_params,x
        sta     down_scroll_params,x
        dex
        bpl     L72D5
        inc     up_scroll_params::incr
        lda     $CD
        ldx     $CE
        sec
        sbc     #$0A
        bcs     L72ED
        dex
L72ED:  pha
        lda     $AC
        and     #$04
        bne     L72F8
        bit     $AF
        bpl     L7300
L72F8:  pla
        sec
        sbc     #$0B
        bcs     L72FF
        dex
L72FF:  pha
L7300:  pla
        sta     down_scroll_params::unk1
        stx     down_scroll_params::unk2
        lda     down_scroll_params_addr
        ldx     down_scroll_params_addr+1
        jsr     L791C
        lda     up_scroll_params_addr
        ldx     up_scroll_params_addr+1
        jsr     L791C
L7319:  bit     $AF
        bpl     L7363
        jsr     L7129
        ldx     #$03
L7322:  lda     $C7,x
        sta     left_scroll_params,x
        sta     right_scroll_params,x
        dex
        bpl     L7322
        lda     $CB
        ldx     $CC
        sec
        sbc     #$14
        bcs     L7337
        dex
L7337:  pha
        lda     $AC
        and     #$04
        bne     L7342
        bit     $B0
        bpl     L734A
L7342:  pla
        sec
        sbc     #$15
        bcs     L7349
        dex
L7349:  pha
L734A:  pla
        sta     right_scroll_params
        stx     right_scroll_params+1
        lda     right_scroll_params_addr
        ldx     right_scroll_params_addr+1
        jsr     L791C
        lda     left_scroll_params_addr
        ldx     left_scroll_params_addr+1
        jsr     L791C
L7363:  lda     #$00
        jsr     set_fill_mode
        lda     $B0
        and     #$01
        beq     L737B
        lda     #$80
        sta     $8C
        lda     L71E4
        jsr     L79A0
        jsr     next_window::L703E
L737B:  lda     $AF
        and     #$01
        beq     L738E
        lda     #$00
        sta     $8C
        lda     L71E4
        jsr     L79A0
        jsr     next_window::L703E
L738E:  lda     $AC
        and     #$04
        beq     L73BE
        jsr     L713D
        lda     L71E4
        bne     L73A6
        lda     #$C7
        ldx     #$00
        jsr     fill_and_frame_rect
        jmp     L73BE

        ;; Draw resize box
L73A6:  ldx     #$03
L73A8:  lda     $C7,x
        sta     resize_box_params,x
        dex
        bpl     L73A8
        lda     #$04
        jsr     set_fill_mode
        lda     resize_box_params_addr
        ldx     resize_box_params_addr+1
        jsr     L791C
L73BE:  rts

L73BF:  lda     $AD
        ldx     $AD+1
        jsr     do_measure_text
        sta     $82
        stx     $83
        lda     $C7
        clc
        adc     $CB
        tay
        lda     $C8
        adc     $CC
        tax
        tya
        sec
        sbc     $82
        tay
        txa
        sbc     $83
        cmp     #$80
        ror     a
        sta     state_xpos+1
        tya
        ror     a
        sta     state_xpos
        lda     $CD
        ldx     $CE
        sec
        sbc     #$02
        bcs     L73F0
        dex
L73F0:  sta     state_ypos
        stx     state_ypos+1
        lda     $82
        ldx     $83
        rts

;;; ==================================================

;;; 4 bytes of params, copied to state_pos

QUERY_TARGET_IMPL:
        jsr     L653F
        A2D_CALL A2D_TEST_BOX, test_box_params
        beq     L7416
        lda     #$01
L7406:  ldx     #$00
L7408:  pha
        txa
        pha
        jsr     L6556
        pla
        tax
        pla
        ldy     #$04
        jmp     store_xa_at_params_y

L7416:  lda     #$00
        sta     L747A
        jsr     top_window
        beq     L7430
L7420:  jsr     L70B7
        jsr     L7086
        bne     L7434
        jsr     next_window
        stx     L747A
        bne     L7420
L7430:  lda     #$00
        beq     L7406
L7434:  lda     $AC
        and     #$01
        bne     L745D
        jsr     L7143
        jsr     L7086
        beq     L745D
        lda     L747A
        bne     L7459
        lda     $AC
        and     #$02
        beq     L7459
        jsr     L7157
        jsr     L7086
        beq     L7459
        lda     #$05
        bne     L7472
L7459:  lda     #$03
        bne     L7472
L745D:  lda     L747A
        bne     L7476
        lda     $AC
        and     #$04
        beq     L7476
        jsr     L713D
        jsr     L7086
        beq     L7476
        lda     #$04
L7472:  ldx     $AB
        bne     L7408
L7476:  lda     #$02
        bne     L7472

;;; ==================================================

L747A:  .byte   0
CREATE_WINDOW_IMPL:
        lda     params_addr
        sta     $A9
        lda     params_addr+1
        sta     $AA
        ldy     #$00
        lda     ($A9),y
        bne     L748E
        lda     #$9E
        jmp     a2d_exit_with_a

L748E:  sta     $82
        jsr     window_by_id
        beq     L749A
        lda     #$9D
        jmp     a2d_exit_with_a

L749A:  lda     params_addr
        sta     $A9
        lda     params_addr+1
        sta     $AA
        ldy     #$0A
        lda     ($A9),y
        ora     #$80
        sta     ($A9),y
        bmi     L74BD

;;; ==================================================

;;; RAISE_WINDOW IMPL

;;; 1 byte of params, copied to $82

RAISE_WINDOW_IMPL:
        jsr     window_by_id_or_exit
        cmp     L700B
        bne     L74BA
        cpx     L700C
        bne     L74BA
        rts

L74BA:  jsr     L74F4
L74BD:  ldy     #next_offset_in_window_params ; Called from elsewhere
        lda     L700B
        sta     ($A9),y
        iny
        lda     L700C
        sta     ($A9),y
        lda     $A9
        pha
        lda     $AA
        pha
        jsr     L653C
        jsr     L6588
        jsr     top_window
        beq     L74DE
        jsr     L7205
L74DE:  pla
        sta     L700C
        pla
        sta     L700B
        jsr     top_window
        lda     $AB
        sta     L700D
        jsr     L718E
        jmp     L6553

L74F4:  ldy     #next_offset_in_window_params ; Called from elsewhere
        lda     ($A9),y
        sta     ($A7),y
        iny
        lda     ($A9),y
        sta     ($A7),y
        rts

;;; ==================================================

;;; QUERY_WINDOW IMPL

;;; 1 byte of params, copied to $C7

.proc QUERY_WINDOW_IMPL
        ptr := $A9
        jsr     window_by_id_or_exit
        lda     ptr
        ldx     ptr+1
        ldy     #1
        jmp     store_xa_at_params_y
.endproc

;;; ==================================================

;;; REDRAW_WINDOW_IMPL

;;; 1 byte of params, copied to $82

L750C:  .res    38,0

.proc REDRAW_WINDOW_IMPL
        jsr     window_by_id_or_exit
        lda     $AB
        cmp     L7010
        bne     L753F
        inc     L7871
L753F:  jsr     L653C
        jsr     L6588
        lda     L7871
        bne     L7550
        A2D_CALL A2D_SET_BOX, set_box_params
L7550:  jsr     L718E
        jsr     L6588
        lda     L7871
        bne     L7561
        A2D_CALL A2D_SET_BOX, set_box_params
L7561:  jsr     next_window::L703E
        lda     active_state
        sta     L750C
        lda     active_state+1
        sta     L750C+1
        jsr     L75C6
        php
        lda     L758A
        ldx     L758B
        jsr     assign_and_prepare_state
        asl     preserve_zp_flag
        plp
        bcc     L7582
        rts
.endproc

L7582:  jsr     L758C
L7585:  lda     #$A3
        jmp     a2d_exit_with_a

;;; ==================================================

;;; $3F IMPL

;;; 1 byte of params, copied to $82

L758A:  .byte   $0E
L758B:  .byte   $75

L758C:  jsr     SHOW_CURSOR_IMPL
        lda     L750C
        ldx     L750C+1
        sta     active_state
        stx     active_state+1
        jmp     L6567

;;; ==================================================

;;; 3 bytes of params, copied to $82

QUERY_STATE_IMPL:
        jsr     apply_state_to_active_state
        jsr     window_by_id_or_exit
        lda     $83
        sta     params_addr
        lda     $84
        sta     params_addr+1
        ldx     #$07
L75AC:  lda     fill_rect_params,x
        sta     $D8,x
        dex
        bpl     L75AC
        jsr     L75C6
        bcc     L7585
        ldy     #sizeof_state-1
L75BB:  lda     $D0,y
        sta     (params_addr),y
        dey
        bpl     L75BB
        jmp     apply_active_state_to_state

L75C6:  jsr     L708D
        ldx     #$07
L75CB:  lda     #$00
        sta     $9B,x
        lda     $C7,x
        sta     $92,x
        dex
        bpl     L75CB
        jsr     L50A9
        bcs     L75DC
        rts

L75DC:  ldy     #$14
L75DE:  lda     ($A9),y
        sta     $BC,y
        iny
        cpy     #$38
        bne     L75DE
        ldx     #$02
L75EA:  lda     $92,x
        sta     $D0,x
        lda     $93,x
        sta     $D1,x
        lda     $96,x
        sec
        sbc     $92,x
        sta     $82,x
        lda     $97,x
        sbc     $93,x
        sta     $83,x
        lda     $D8,x
        sec
        sbc     $9B,x
        sta     $D8,x
        lda     $D9,x
        sbc     $9C,x
        sta     $D9,x
        lda     $D8,x
        clc
        adc     $82,x
        sta     $DC,x
        lda     $D9,x
        adc     $83,x
        sta     $DD,x
        dex
        dex
        bpl     L75EA
        sec
        rts

;;; ==================================================

;;; UPDATE_STATE IMPL

;;; 2 bytes of params, copied to $82

        ;; This updates current state from params ???
        ;; The math is weird; $82 is the window id so
        ;; how does ($82),y do anything useful - is
        ;; this buggy ???

        ;; It seems like it's trying to update a fraction
        ;; of the drawing state (from |pattern| to |font|)

.proc UPDATE_STATE_IMPL
        ptr := $A9

        jsr     window_by_id_or_exit
        lda     ptr
        clc
        adc     #state_offset_in_window_params
        sta     ptr
        bcc     :+
        inc     ptr+1
:       ldy     #sizeof_state-1
loop:   lda     ($82),y
        sta     ($A9),y
        dey
        cpy     #$10
        bcs     loop
        rts
.endproc

;;; ==================================================

;;; QUERY_TOP IMPL

.proc QUERY_TOP_IMPL
        jsr     top_window
        beq     nope
        lda     $AB
        bne     :+
nope:   lda     #0
:       ldy     #0
        sta     (params_addr),y
        rts
.endproc

;;; ==================================================

in_close_box:  .byte   0

.proc CLOSE_CLICK_IMPL
        jsr     top_window
        beq     end
        jsr     L7157
        jsr     L653F
        jsr     L6588
        lda     #$80
toggle: sta     in_close_box
        lda     #$02
        jsr     set_fill_mode
        jsr     HIDE_CURSOR_IMPL
        A2D_CALL A2D_FILL_RECT, $C7
        jsr     SHOW_CURSOR_IMPL
loop:   jsr     L691B
        cmp     #$02
        beq     L768B
        A2D_CALL A2D_SET_POS, set_pos_params
        jsr     L7086
        eor     in_close_box
        bpl     loop
        lda     in_close_box
        eor     #$80
        jmp     toggle

L768B:  jsr     L6556
        ldy     #$00
        lda     in_close_box
        beq     end
        lda     #$01
end:    sta     (params_addr),y
        rts
.endproc

;;; ==================================================

        .byte   $00
L769B:  .byte   $00
L769C:  .byte   $00
L769D:  .byte   $00
L769E:  .byte   $00
L769F:  .byte   $00
L76A0:  .byte   $00,$00,$00
L76A3:  .byte   $00
L76A4:  .byte   $00,$00,$00
L76A7:  .byte   $00

;;; ==================================================

;;; 5 bytes of params, copied to $82

DRAG_RESIZE_IMPL:
        lda     #$80
        bmi     L76AE

;;; ==================================================

;;; 5 bytes of params, copied to $82

DRAG_WINDOW_IMPL:
        lda     #$00

L76AE:  sta     L76A7
        jsr     L7ECD
        ldx     #$03
L76B6:  lda     $83,x
        sta     L769B,x
        sta     L769F,x
        lda     #$00
        sta     L76A3,x
        dex
        bpl     L76B6
        jsr     window_by_id_or_exit
        bit     L7D74
        bpl     L76D1
        jsr     L817C
L76D1:  jsr     L653C
        jsr     L784C
        lda     #$02
        jsr     set_fill_mode
        A2D_CALL A2D_SET_PATTERN, checkerboard_pattern
L76E2:  jsr     next_window::L703E
        jsr     L7749
        jsr     L70B7
        jsr     L707F
        jsr     SHOW_CURSOR_IMPL
L76F1:  jsr     L691B
        cmp     #$02
        bne     L773B
        jsr     L707F
        bit     L7D81
        bmi     L770A
        ldx     #$03
L7702:  lda     L76A3,x
        bne     L7714
        dex
        bpl     L7702
L770A:  jsr     L6553
        lda     #$00
L770F:  ldy     #$05
        sta     (params_addr),y
        rts

L7714:  ldy     #$14
L7716:  lda     $A3,y
        sta     ($A9),y
        iny
        cpy     #$24
        bne     L7716
        jsr     HIDE_CURSOR_IMPL
        lda     $AB
        jsr     L7872
        jsr     L653C
        bit     L7D81
        bvc     L7733
        jsr     L8347
L7733:  jsr     L6553
        lda     #$80
        jmp     L770F

L773B:  jsr     L77E0
        beq     L76F1
        jsr     HIDE_CURSOR_IMPL
        jsr     L707F
        jmp     L76E2

L7749:  ldy     #$13
L774B:  lda     ($A9),y
        sta     $BB,y
        dey
        cpy     #$0B
        bne     L774B
        ldx     #$00
        stx     set_input_params_unk
        bit     L76A7
        bmi     L777D
L775F:  lda     $B7,x
        clc
        adc     L76A3,x
        sta     $B7,x
        lda     $B8,x
        adc     L76A4,x
        sta     $B8,x
        inx
        inx
        cpx     #$04
        bne     L775F
        lda     #$12
        cmp     $B9
        bcc     L777C
        sta     $B9
L777C:  rts

L777D:  lda     #$00
        sta     L83F5
L7782:  clc
        lda     $C3,x
        adc     L76A3,x
        sta     $C3,x
        lda     $C4,x
        adc     L76A4,x
        sta     $C4,x
        sec
        lda     $C3,x
        sbc     $BF,x
        sta     $82
        lda     $C4,x
        sbc     $C0,x
        sta     $83
        sec
        lda     $82
        sbc     $C7,x
        lda     $83
        sbc     $C8,x
        bpl     L77BC
        clc
        lda     $C7,x
        adc     $BF,x
        sta     $C3,x
        lda     $C8,x
        adc     $C0,x
        sta     $C4,x
        jsr     L83F6
        jmp     L77D7

L77BC:  sec
        lda     $CB,x
        sbc     $82
        lda     $CC,x
        sbc     $83
        bpl     L77D7
        clc
        lda     $CB,x
        adc     $BF,x
        sta     $C3,x
        lda     $CC,x
        adc     $C0,x
        sta     $C4,x
        jsr     L83F6
L77D7:  inx
        inx
        cpx     #$04
        bne     L7782
        jmp     L83FC

L77E0:  ldx     #$02
        ldy     #$00
L77E4:  lda     $84,x
        cmp     L76A0,x
        bne     L77EC
        iny
L77EC:  lda     $83,x
        cmp     L769F,x
        bne     L77F4
        iny
L77F4:  sta     L769F,x
        sec
        sbc     L769B,x
        sta     L76A3,x
        lda     $84,x
        sta     L76A0,x
        sbc     L769C,x
        sta     L76A4,x
        dex
        dex
        bpl     L77E4
        cpy     #$04
        bne     L7814
        lda     set_input_params_unk
L7814:  rts

;;; ==================================================

;;; 1 byte of params, copied to $82

.proc DESTROY_WINDOW_IMPL
        jsr     window_by_id_or_exit
        jsr     L653C
        jsr     L784C
        jsr     L74F4
        ldy     #$0A
        lda     ($A9),y
        and     #$7F
        sta     ($A9),y
        jsr     top_window
        lda     $AB
        sta     L700D
        lda     #$00
        jmp     L7872
.endproc

;;; ==================================================

;;; $3A IMPL

L7836:  jsr     top_window
        beq     L7849
        ldy     #$0A
        lda     ($A9),y
        and     #$7F
        sta     ($A9),y
        jsr     L74F4
        jmp     L7836

L7849:  jmp     L6454

L784C:  jsr     L6588
        jsr     L70B7
        ldx     #$07
L7854:  lda     $C7,x
        sta     $92,x
        dex
        bpl     L7854
        jsr     L50A9
        ldx     #$03
L7860:  lda     $92,x
        sta     set_box_params_box,x
        sta     set_box_params,x
        lda     $96,x
        sta     set_box_params_size,x
        dex
        bpl     L7860
        rts

        ;; Erases window after destruction
L7871:  .byte   0
L7872:  sta     L7010
        lda     #$00
        sta     L7871
        A2D_CALL A2D_SET_BOX, set_box_params
        lda     #$00
        jsr     set_fill_mode
        A2D_CALL A2D_SET_PATTERN, checkerboard_pattern
        A2D_CALL A2D_FILL_RECT, set_box_params_box
        jsr     L6553
        jsr     top_window
        beq     L78CA
        php
        sei
        jsr     CALL_2B_IMPL
L789E:  jsr     next_window
        bne     L789E
L78A3:  jsr     L67E4
        bcs     L78C9
        tax
        lda     #$06
        sta     L6754,x
        lda     $AB
        sta     L6755,x
        lda     $AB
        cmp     L700D
        beq     L78C9
        sta     $82
        jsr     window_by_id
        lda     $A7
        ldx     $A8
        jsr     next_window::L7044
        jmp     L78A3

L78C9:  plp
L78CA:  rts

L78CB:  .byte   $08,$00
L78CD:  .byte   $0C,$00
L78CF:  .byte   $0D,$00

.proc set_box_params
left:   .word   0
top:    .word   $D
addr:   .addr   A2D_SCREEN_ADDR
stride: .word   A2D_SCREEN_STRIDE
hoffset:.word   0
voffset:.word   0
width:  .word   0
height: .word   0
.endproc
        set_box_params_top  := set_box_params::top
        set_box_params_size := set_box_params::width
        set_box_params_box  := set_box_params::hoffset ; Re-used since h/voff are 0

;;; ==================================================

;;; $47 IMPL

        ;; $83/$84 += $B7/$B8
        ;; $85/$86 += $B9/$BA

.proc L78E1
        jsr     window_by_id_or_exit
        ldx     #2
loop:   lda     $83,x
        clc
        adc     $B7,x
        sta     $83,x
        lda     $84,x
        adc     $B8,x
        sta     $84,x
        dex
        dex
        bpl     loop
        bmi     L790F
.endproc

;;; ==================================================

;;; 5 bytes of params, copied to $82

MAP_COORDS_IMPL:
        jsr     window_by_id_or_exit
        ldx     #$02
L78FE:  lda     $83,x
        sec
        sbc     $B7,x
        sta     $83,x
        lda     $84,x
        sbc     $B8,x
        sta     $84,x
        dex
        dex
        bpl     L78FE
L790F:  ldy     #$05
L7911:  lda     $7E,y
        sta     (params_addr),y
        iny
        cpy     #$09
        bne     L7911
        rts

        ;; Used to draw scrollbar arrows
L791C:  sta     $82
        stx     $83
        ldy     #$03
L7922:  lda     #$00
        sta     $8A,y
        lda     ($82),y
        sta     $92,y
        dey
        bpl     L7922
        iny
        sty     $91
        ldy     #$04
        lda     ($82),y
        tax
        lda     L4828,x
        sta     $90
        txa
        ldx     $93
        clc
        adc     $92
        bcc     L7945
        inx
L7945:  sta     $96
        stx     $97
        iny
        lda     ($82),y
        ldx     $95
        clc
        adc     $94
        bcc     L7954
        inx
L7954:  sta     $98
        stx     $99
        iny
        lda     ($82),y
        sta     $8E
        iny
        lda     ($82),y
        sta     $8F
        jmp     L51B3

;;; ==================================================

;;; $4C IMPL

;;; 2 bytes of params, copied to $8C

L7965:
        lda     $8C
        cmp     #$01
        bne     L7971
        lda     #$80
        sta     $8C
        bne     L797C
L7971:  cmp     #$02
        bne     L797B
        lda     #$00
        sta     $8C
        beq     L797C
L797B:  rts

L797C:  jsr     L653C
        jsr     top_window
        bit     $8C
        bpl     L798C
        lda     $B0
        ldy     #$05
        bne     L7990
L798C:  lda     $AF
        ldy     #$04
L7990:  eor     $8D
        and     #$01
        eor     ($A9),y
        sta     ($A9),y
        lda     $8D
        jsr     L79A0
        jmp     L6553

L79A0:  bne     L79AF
        jsr     L79F1
        jsr     L657E
        A2D_CALL A2D_FILL_RECT, $C7
        rts

L79AF:  bit     $8C
        bmi     L79B8
        bit     $AF
        bmi     L79BC
L79B7:  rts

L79B8:  bit     $B0
        bpl     L79B7
L79BC:  jsr     L657E
        jsr     L79F1
        A2D_CALL A2D_SET_PATTERN, light_speckles_pattern
        A2D_CALL A2D_FILL_RECT, $C7
        A2D_CALL A2D_SET_PATTERN, screen_state::pattern
        bit     $8C
        bmi     L79DD
        bit     $AF
        bvs     L79E1
L79DC:  rts

L79DD:  bit     $B0
        bvc     L79DC
L79E1:  jsr     L7A73
        jmp     fill_and_frame_rect

light_speckles_pattern:
        .byte   %11011101
        .byte   %01110111
        .byte   %11011101
        .byte   %01110111
        .byte   %11011101
        .byte   %01110111
        .byte   %11011101
        .byte   %01110111

        .byte   $00,$00

L79F1:  bit     $8C
        bpl     L7A34
        jsr     L7104
        lda     $C9
        clc
        adc     #$0C
        sta     $C9
        bcc     L7A03
        inc     $CA
L7A03:  lda     $CD
        sec
        sbc     #$0B
        sta     $CD
        bcs     L7A0E
        dec     $CE
L7A0E:  lda     $AC
        and     #$04
        bne     L7A18
        bit     $AF
        bpl     L7A23
L7A18:  lda     $CD
        sec
        sbc     #$0B
        sta     $CD
        bcs     L7A23
        dec     $CE
L7A23:  inc     $C7
        bne     L7A29
        inc     $C8
L7A29:  lda     $CB
        bne     L7A2F
        dec     $CC
L7A2F:  dec     $CB
        jmp     L7A70

L7A34:  jsr     L7129
        lda     $C7
        clc
        adc     #$15
        sta     $C7
        bcc     L7A42
        inc     $C8
L7A42:  lda     $CB
        sec
        sbc     #$15
        sta     $CB
        bcs     L7A4D
        dec     $CC
L7A4D:  lda     $AC
        and     #$04
        bne     L7A57
        bit     $B0
        bpl     L7A62
L7A57:  lda     $CB
        sec
        sbc     #$15
        sta     $CB
        bcs     L7A62
        dec     $CC
L7A62:  inc     $C9
        bne     L7A68
        inc     $CA
L7A68:  lda     $CD
        bne     L7A6E
        dec     $CE
L7A6E:  dec     $CD
L7A70:  jmp     L70B2

L7A73:  jsr     L79F1
        jsr     L7CE3
        jsr     L5698
        lda     $A1
        pha
        jsr     L7CFB
        jsr     L7CBA
        pla
        tax
        lda     $A3
        ldy     $A4
        cpx     #$01
        beq     L7A94
        ldx     $A0
        jsr     L7C93
L7A94:  sta     $82
        sty     $83
        ldx     #$00
        lda     #$14
        bit     $8C
        bpl     L7AA4
        ldx     #$02
        lda     #$0C
L7AA4:  pha
        lda     $C7,x
        clc
        adc     $82
        sta     $C7,x
        lda     $C8,x
        adc     $83
        sta     $C8,x
        pla
        clc
        adc     $C7,x
        sta     $CB,x
        lda     $C8,x
        adc     #$00
        sta     $CC,x
        jmp     L70B2

;;; ==================================================

;;; 4 bytes of params, copied to state_pos

QUERY_CLIENT_IMPL:
        jsr     L653F
        jsr     top_window
        bne     L7ACE
        lda     #$A0
        jmp     a2d_exit_with_a

L7ACE:  bit     $B0
        bpl     L7B15
        jsr     L7104
        jsr     L7086
        beq     L7B15
        ldx     #$00
        lda     $B0
        and     #$01
        beq     L7B11
        lda     #$80
        sta     $8C
        jsr     L79F1
        jsr     L7086
        beq     L7AFE
        bit     $B0
        bcs     L7B70
        jsr     L7A73
        jsr     L7086
        beq     L7B02
        ldx     #$05
        bne     L7B11
L7AFE:  lda     #$01
        bne     L7B04
L7B02:  lda     #$03
L7B04:  pha
        jsr     L7A73
        pla
        tax
        lda     state_ypos
        cmp     $C9
        bcc     L7B11
        inx
L7B11:  lda     #$01
        bne     L7B72
L7B15:  bit     $AF
        bpl     L7B64
        jsr     L7129
        jsr     L7086
        beq     L7B64
        ldx     #$00
        lda     $AF
        and     #$01
        beq     L7B60
        lda     #$00
        sta     $8C
        jsr     L79F1
        jsr     L7086
        beq     L7B45
        bit     $AF
        bvc     L7B70
        jsr     L7A73
        jsr     L7086
        beq     L7B49
        ldx     #$05
        bne     L7B60
L7B45:  lda     #$01
        bne     L7B4B
L7B49:  lda     #$03
L7B4B:  pha
        jsr     L7A73
        pla
        tax
        lda     state_xpos+1
        cmp     $C8
        bcc     L7B60
        bne     L7B5F
        lda     state_xpos
        cmp     $C7
        bcc     L7B60
L7B5F:  inx
L7B60:  lda     #$02
        bne     L7B72
L7B64:  jsr     L708D
        jsr     L7086
        beq     L7B70
        lda     #$00
        beq     L7B72
L7B70:  lda     #$03
L7B72:  jmp     L7408

;;; ==================================================

;;; 3 bytes of params, copied to $82

RESIZE_WINDOW_IMPL:
        lda     $82
        cmp     #$01
        bne     L7B81
        lda     #$80
        sta     $82
        bne     L7B90
L7B81:  cmp     #$02
        bne     L7B8B
        lda     #$00
        sta     $82
        beq     L7B90
L7B8B:  lda     #$A4
        jmp     a2d_exit_with_a

L7B90:  jsr     top_window
        bne     L7B9A
        lda     #$A0
        jmp     a2d_exit_with_a

L7B9A:  ldy     #$06
        bit     $82
        bpl     L7BA2
        ldy     #$08
L7BA2:  lda     $83
        sta     ($A9),y
        sta     $AB,y
        rts

;;; ==================================================

;;; 5 bytes of params, copied to $82

DRAG_SCROLL_IMPL:
        lda     $82
        cmp     #$01
        bne     L7BB6
        lda     #$80
        sta     $82
        bne     L7BC5
L7BB6:  cmp     #$02
        bne     L7BC0
        lda     #$00
        sta     $82
        beq     L7BC5
L7BC0:  lda     #$A4
        jmp     a2d_exit_with_a

L7BC5:  lda     $82
        sta     $8C
        ldx     #$03
L7BCB:  lda     $83,x
        sta     L769B,x
        sta     L769F,x
        dex
        bpl     L7BCB
        jsr     top_window
        bne     L7BE0
        lda     #$A0
        jmp     a2d_exit_with_a

L7BE0:  jsr     L7A73
        jsr     L653F
        jsr     L6588
        lda     #$02
        jsr     set_fill_mode
        A2D_CALL A2D_SET_PATTERN, light_speckles_pattern
        jsr     HIDE_CURSOR_IMPL
L7BF7:  jsr     L707F
        jsr     SHOW_CURSOR_IMPL
L7BFD:  jsr     L691B
        cmp     #$02
        beq     L7C66
        jsr     L77E0
        beq     L7BFD
        jsr     HIDE_CURSOR_IMPL
        jsr     L707F
        jsr     top_window
        jsr     L7A73
        ldx     #$00
        lda     #$14
        bit     $8C
        bpl     L7C21
        ldx     #$02
        lda     #$0C
L7C21:  sta     $82
        lda     $C7,x
        clc
        adc     L76A3,x
        tay
        lda     $C8,x
        adc     L76A4,x
        cmp     L7CB9
        bcc     L7C3B
        bne     L7C41
        cpy     L7CB8
        bcs     L7C41
L7C3B:  lda     L7CB9
        ldy     L7CB8
L7C41:  cmp     L7CB7
        bcc     L7C53
        bne     L7C4D
        cpy     L7CB6
        bcc     L7C53
L7C4D:  lda     L7CB7
        ldy     L7CB6
L7C53:  sta     $C8,x
        tya
        sta     $C7,x
        clc
        adc     $82
        sta     $CB,x
        lda     $C8,x
        adc     #$00
        sta     $CC,x
        jmp     L7BF7

L7C66:  jsr     HIDE_CURSOR_IMPL
        jsr     L707F
        jsr     L6553
        jsr     L7CBA
        jsr     L5698
        ldx     $A1
        jsr     L7CE3
        lda     $A3
        ldy     #$00
        cpx     #$01
        bcs     L7C87
        ldx     $A0
        jsr     L7C93
L7C87:  ldx     #$01
        cmp     $A1
        bne     L7C8E
        dex
L7C8E:  ldy     #$05
        jmp     store_xa_at_params_y

L7C93:  sta     $82
        sty     $83
        lda     #$80
        sta     $84
        ldy     #$00
        sty     $85
        txa
        beq     L7CB5
L7CA2:  lda     $82
        clc
        adc     $84
        sta     $84
        lda     $83
        adc     $85
        sta     $85
        bcc     L7CB2
        iny
L7CB2:  dex
        bne     L7CA2
L7CB5:  rts

L7CB6:  .byte   0
L7CB7:  .byte   0
L7CB8:  .byte   0
L7CB9:  .byte   0

L7CBA:  lda     L7CB6
        sec
        sbc     L7CB8
        sta     $A3
        lda     L7CB7
        sbc     L7CB9
        sta     $A4
        ldx     #$00
        bit     $8C
        bpl     L7CD3
        ldx     #$02
L7CD3:  lda     $C7,x
        sec
        sbc     L7CB8
        sta     $A1
        lda     $C8,x
        sbc     L7CB9
        sta     $A2
        rts

L7CE3:  ldy     #$06
        bit     $8C
        bpl     L7CEB
        ldy     #$08
L7CEB:  lda     ($A9),y
        sta     $A3
        iny
        lda     ($A9),y
        sta     $A1
        lda     #$00
        sta     $A2
        sta     $A4
        rts

L7CFB:  ldx     #$00
        lda     #$14
        bit     $8C
        bpl     L7D07
        ldx     #$02
        lda     #$0C
L7D07:  sta     $82
        lda     $C7,x
        ldy     $C8,x
        sta     L7CB8
        sty     L7CB9
        lda     $CB,x
        ldy     $CC,x
        sec
        sbc     $82
        bcs     L7D1D
        dey
L7D1D:  sta     L7CB6
        sty     L7CB7
        rts

;;; ==================================================

;;; 3 bytes of params, copied to $8C

UPDATE_SCROLL_IMPL:
        lda     $8C
        cmp     #$01
        bne     L7D30
        lda     #$80
        sta     $8C
        bne     L7D3F
L7D30:  cmp     #$02
        bne     L7D3A
        lda     #$00
        sta     $8C
        beq     L7D3F
L7D3A:  lda     #$A4
        jmp     a2d_exit_with_a

L7D3F:  jsr     top_window
        bne     L7D49
        lda     #$A0
        jmp     a2d_exit_with_a

L7D49:  ldy     #$07
        bit     $8C
        bpl     L7D51
        ldy     #$09
L7D51:  lda     $8D
        sta     ($A9),y
        jsr     L653C
        jsr     L657E
        jsr     L79A0
        jmp     L6553


;;; ==================================================

;;; $22 IMPL

;;; 1 byte of params, copied to $82

L7D61:  lda     #$80
        sta     L7D74
        jmp     CALL_2B_IMPL

;;; ==================================================

;;; $4E IMPL

;;; 2 bytes of params, copied to $82

L7D69:
        lda     $82
        sta     L7D7A
        lda     $83
        sta     L7D7B
        rts

L7D74:  .byte   $00
L7D75:  .byte   $00
L7D76:  .byte   $00
L7D77:  .byte   $00,$00
L7D79:  .byte   $00
L7D7A:  .byte   $00
L7D7B:  .byte   $00
L7D7C:  .byte   $00
L7D7D:  .byte   $00
L7D7E:  .byte   $00
L7D7F:  .byte   $00
L7D80:  .byte   $00
L7D81:  .byte   $00
L7D82:  .byte   $00
L7D83:  ldx     #$7F
L7D85:  lda     $80,x
        sta     L7D99,x
        dex
        bpl     L7D85
        rts

L7D8E:  ldx     #$7F
L7D90:  lda     L7D99,x
        sta     $80,x
        dex
        bpl     L7D90
        rts

L7D99:  .res    128, 0

L7E19:  bit     L5FFF
        bmi     L7E49
        bit     no_mouse_flag
        bmi     L7E49
        pha
        txa
        sec
        jsr     L7E75
        ldx     mouse_firmware_hi
        sta     MOUSE_X_LO,x
        tya
        sta     MOUSE_X_HI,x
        pla
        ldy     #$00
        clc
        jsr     L7E75
        ldx     mouse_firmware_hi
        sta     MOUSE_Y_LO,x
        tya
        sta     MOUSE_Y_HI,x
        ldy     #POSMOUSE
        jmp     call_mouse

L7E49:  stx     mouse_x_lo
        sty     mouse_x_hi
        sta     mouse_y_lo
        bit     L5FFF
        bpl     L7E5C
        ldy     #POSMOUSE
        jmp     call_mouse

L7E5C:  rts

L7E5D:  ldx     L7D7C
        ldy     L7D7D
        lda     L7D7E
        jmp     L7E19

L7E69:  ldx     L7D75
        ldy     L7D76
        lda     L7D77
        jmp     L7E19

L7E75:  bcc     L7E7D
        ldx     L5FFD
        bne     L7E82
L7E7C:  rts

L7E7D:  ldx     L5FFE
        beq     L7E7C
L7E82:  pha
        tya
        lsr     a
        tay
        pla
        ror     a
        dex
        bne     L7E82
        rts

L7E8C:  ldx     #$02
L7E8E:  lda     L7D75,x
        sta     mouse_x_lo,x
        dex
        bpl     L7E8E
        rts

L7E98:  jsr     L7E8C
        jmp     L7E69

L7E9E:  jsr     L62BA
        ldx     #$02
L7EA3:  lda     mouse_x_lo,x
        sta     L7D7C,x
        dex
        bpl     L7EA3
        rts

L7EAD:  jsr     stash_params_addr
        lda     L7F2E
        sta     params_addr
        lda     L7F2F
        sta     params_addr+1
        jsr     SET_CURSOR_IMPL
        jsr     restore_params_addr
        lda     #$00
        sta     L7D74
        lda     #$40
        sta     mouse_status
        jmp     L7E5D

L7ECD:  lda     #$00
        sta     L7D81
        sta     set_input_params_unk
        rts

        ;; Look at buttons (apple keys), compute modifiers in A
        ;; (bit = button 0 / open apple, bit 1 = button 1 / closed apple)
.proc compute_modifiers
        lda     BUTN1
        asl     a
        lda     BUTN0
        and     #$80
        rol     a
        rol     a
        rts
.endproc

L7EE2:  jsr     compute_modifiers
        sta     set_input_params_modifiers
L7EE8:  clc
        lda     KBD
        bpl     L7EF4
        stx     KBDSTRB
        and     #$7F
        sec
L7EF4:  rts

L7EF5:  lda     L7D74
        bne     L7EFB
        rts

L7EFB:  cmp     #$04
        beq     L7F48
        jsr     L7FB4
        lda     L7D74
        cmp     #$01
        bne     L7F0C
        jmp     L804D

L7F0C:  jmp     L825F

L7F0F:  jsr     stash_params_addr
        lda     active_cursor
        sta     L7F2E
        lda     active_cursor+1
        sta     L7F2F
        lda     L6065
        sta     params_addr
        lda     L6066
        sta     params_addr+1
        jsr     SET_CURSOR_IMPL
        jmp     restore_params_addr

L7F2E:  .byte   0
L7F2F:  .byte   0

stash_params_addr:
        lda     params_addr
        sta     stashed_params_addr
        lda     params_addr+1
        sta     stashed_params_addr+1
        rts

restore_params_addr:
        lda     stashed_params_addr
        sta     params_addr
        lda     stashed_params_addr+1
        sta     params_addr+1
        rts

stashed_params_addr:  .addr     0

L7F48:  jsr     compute_modifiers
        ror     a
        ror     a
        ror     L7D82
        lda     L7D82
        sta     mouse_status
        lda     #0
        sta     input::modifiers
        jsr     L7EE8
        bcc     L7F63
        jmp     L8292

L7F63:  jmp     L7E98

L7F66:  pha
        lda     L7D74
        bne     L7FA3
        pla
        cmp     #$03
        bne     L7FA2
        bit     mouse_status
        bmi     L7FA2
        lda     #$04
        sta     L7D74
        ldx     #$0A
L7F7D:  lda     SPKR            ; Beep?
        ldy     #$00
L7F82:  dey
        bne     L7F82
        dex
        bpl     L7F7D
L7F88:  jsr     compute_modifiers
        cmp     #3
        beq     L7F88
        sta     input::modifiers
        lda     #$00
        sta     L7D82
        ldx     #$02
L7F99:  lda     set_pos_params,x
        sta     L7D75,x
        dex
        bpl     L7F99
L7FA2:  rts

L7FA3:  cmp     #$04
        bne     L7FB2
        pla
        and     #$01
        bne     L7FB1
        lda     #$00
        sta     L7D74
L7FB1:  rts

L7FB2:  pla
        rts

L7FB4:  bit     mouse_status
        bpl     L7FC1
        lda     #$00
        sta     L7D74
        jmp     L7E69

L7FC1:  lda     mouse_status
        pha
        lda     #$C0
        sta     mouse_status
        pla
        and     #$20
        beq     L7FDE
        ldx     #$02
L7FD1:  lda     mouse_x_lo,x
        sta     L7D75,x
        dex
        bpl     L7FD1
        stx     L7D79
        rts

L7FDE:  jmp     L7E8C

L7FE1:  php
        sei
        jsr     L7E9E
        lda     #$01
        sta     L7D74
        jsr     L800F
        lda     #$80
        sta     mouse_status
        jsr     L7F0F
        ldx     L7D7A
        jsr     L6878
        lda     $AF
        sta     L6BD9
        jsr     L6D26
        lda     L7D7B
        sta     L6BDA
        jsr     L6EAA
        plp
        rts

L800F:  ldx     L7D7A
        jsr     L6878
        clc
        lda     $B7
        adc     #$05
        sta     L7D75
        lda     $B8
        adc     #$00
        sta     L7D76
        ldy     L7D7B
        lda     L6847,y
        sta     L7D77
        lda     #$C0
        sta     mouse_status
        jmp     L7E98

L8035:  bit     L7D79
        bpl     L804C
        lda     L6BDA
        sta     L7D7B
        ldx     L6BD9
        dex
        stx     L7D7A
        lda     #$00
        sta     L7D79
L804C:  rts

L804D:  jsr     L7D83
        jsr     L8056
        jmp     L7D8E

L8056:  jsr     L7EE2
        bcs     handle_menu_key
        rts


        ;; Keyboard navigation of menu
.proc handle_menu_key
        pha
        jsr     L8035
        pla
        cmp     #KEY_ESCAPE
        bne     try_return
        lda     #0
        sta     L7D80
        sta     L7D7F
        lda     #$80
        sta     L7D81
        rts

try_return:
        cmp     #KEY_RETURN
        bne     try_up
        jsr     L7E8C
        jmp     L7EAD

try_up:
        cmp     #KEY_UP
        bne     try_down
L8081:  dec     L7D7B
        bpl     L8091
        ldx     L7D7A
        jsr     L6878
        ldx     $AA
        stx     L7D7B
L8091:  ldx     L7D7B
        beq     L80A0
        dex
        jsr     L68BE
        lda     $BF
        and     #$C0
        bne     L8081
L80A0:  jmp     L800F

try_down:
        cmp     #KEY_DOWN
        bne     try_right
L80A7:  inc     L7D7B
        ldx     L7D7A
        jsr     L6878
        lda     L7D7B
        cmp     $AA
        bcc     L80BE
        beq     L80BE
        lda     #0
        sta     L7D7B
L80BE:  ldx     L7D7B
        beq     L80CD
        dex
        jsr     L68BE
        lda     $BF
        and     #$C0
        bne     L80A7
L80CD:  jmp     L800F

try_right:
        cmp     #KEY_RIGHT
        bne     try_left
        lda     #0
        sta     L7D7B
        inc     L7D7A
        lda     L7D7A
        cmp     $A8
        bcc     L80E8
        lda     #$00
        sta     L7D7A
L80E8:  jmp     L800F

try_left:
        cmp     #KEY_LEFT
        bne     nope
        lda     #0
        sta     L7D7B
        dec     L7D7A
        bmi     L80FC
        jmp     L800F

L80FC:  ldx     $A8
        dex
        stx     L7D7A
        jmp     L800F

nope:   jsr     L8110
        bcc     L810F
        lda     #$80
        sta     L7D81
L810F:  rts
.endproc

L8110:  sta     $C9
        lda     set_input_params_modifiers
        and     #$03
        sta     $CA
        lda     L6BD9
        pha
        lda     L6BDA
        pha
        lda     #$C0
        jsr     L6A96
        beq     L813D
        stx     L7D80
        lda     $B0
        bmi     L813D
        lda     $BF
        and     #$C0
        bne     L813D
        lda     $AF
        sta     L7D7F
        sec
        bcs     L813E
L813D:  clc
L813E:  pla
        sta     L6BDA
        pla
        sta     L6BD9
        sta     $C7
        rts

L8149:  php
        sei
        jsr     L6D23
        jsr     L7EAD
        lda     L7D7F
        sta     $C7
        sta     L6BD9
        lda     L7D80
        sta     $C8
        sta     L6BDA
        jsr     L6556
        lda     L7D7F
        beq     L816F
        jsr     L6B1D
        lda     L7D7F
L816F:  sta     L6BD9
        ldx     L7D80
        stx     L6BDA
        plp
        jmp     store_xa_at_params

L817C:  php
        sei
        jsr     L7E9E
        lda     #$80
        sta     mouse_status
        jsr     L70B7
        bit     L76A7
        bpl     L81E4
        lda     $AC
        and     #$04
        beq     L81D9
        ldx     #$00
L8196:  sec
        lda     $CB,x
        sbc     #$04
        sta     L7D75,x
        sta     L769B,x
        sta     L769F,x
        lda     $CC,x
        sbc     #$00
        sta     L7D76,x
        sta     L769C,x
        sta     L76A0,x
        inx
        inx
        cpx     #$04
        bcc     L8196
        sec
        lda     #<(560-1)
        sbc     L769B
        lda     #>(560-1)
        sbc     L769B+1
        bmi     L81D9
        sec
        lda     #<(192-1)
        sbc     L769D
        lda     #>(192-1)
        sbc     L769D+1
        bmi     L81D9
        jsr     L7E98
        jsr     L7F0F
        plp
        rts

L81D9:  lda     #$00
        sta     L7D74
        lda     #$A2
        plp
        jmp     a2d_exit_with_a

L81E4:  lda     $AC
        and     #$01
        beq     L81F4
        lda     #$00
        sta     L7D74
        lda     #$A1
        jmp     a2d_exit_with_a

L81F4:  ldx     #$00
L81F6:  clc
        lda     $C7,x
        cpx     #$02
        beq     L8202
        adc     #$23
        jmp     L8204

L8202:  adc     #$05
L8204:  sta     L7D75,x
        sta     L769B,x
        sta     L769F,x
        lda     $C8,x
        adc     #$00
        sta     L7D76,x
        sta     L769C,x
        sta     L76A0,x
        inx
        inx
        cpx     #$04
        bcc     L81F6
        bit     L7D76
        bpl     L8235
        ldx     #$01
        lda     #$00
L8229:  sta     L7D75,x
        sta     L769B,x
        sta     L769F,x
        dex
        bpl     L8229
L8235:  jsr     L7E98
        jsr     L7F0F
        plp
        rts

L823D:  php
        clc
        adc     L7D77
        sta     L7D77
        plp
        bpl     L8254
        cmp     #$C0
        bcc     L8251
        lda     #$00
        sta     L7D77
L8251:  jmp     L7E98

L8254:  cmp     #$C0
        bcc     L8251
        lda     #$BF
        sta     L7D77
        bne     L8251
L825F:  jsr     L7D83
        jsr     L8268
        jmp     L7D8E

L8268:  jsr     L7EE2
        bcs     L826E
        rts

L826E:  cmp     #$1B
        bne     L827A
        lda     #$80
        sta     L7D81
        jmp     L7EAD

L827A:  cmp     #$0D
        bne     L8281
        jmp     L7EAD

L8281:  pha
        lda     set_input_params_modifiers
        beq     L828C
        ora     #$80
        sta     set_input_params_modifiers
L828C:  pla
        ldx     #$C0
        stx     mouse_status
L8292:  cmp     #$0B
        bne     L82A2
        lda     #$F8
        bit     set_input_params_modifiers
        bpl     L829F
        lda     #$D0
L829F:  jmp     L823D

L82A2:  cmp     #$0A
        bne     L82B2
        lda     #$08
        bit     set_input_params_modifiers
        bpl     L82AF
        lda     #$30
L82AF:  jmp     L823D

L82B2:  cmp     #$15
        bne     L82ED
        jsr     L839A
        bcc     L82EA
        clc
        lda     #$08
        bit     set_input_params_modifiers
        bpl     L82C5
        lda     #$40
L82C5:  adc     L7D75
        sta     L7D75
        lda     L7D76
        adc     #$00
        sta     L7D76
        sec
        lda     L7D75
        sbc     #$2F
        lda     L7D76
        sbc     #$02
        bmi     L82EA
        lda     #$02
        sta     L7D76
        lda     #$2F
        sta     L7D75
L82EA:  jmp     L7E98

L82ED:  cmp     #$08
        bne     L831D
        jsr     L8352
        bcc     L831A
        lda     L7D75
        bit     set_input_params_modifiers
        bpl     L8303
        sbc     #$40
        jmp     L8305

L8303:  sbc     #$08
L8305:  sta     L7D75
        lda     L7D76
        sbc     #$00
        sta     L7D76
        bpl     L831A
        lda     #$00
        sta     L7D75
        sta     L7D76
L831A:  jmp     L7E98

L831D:  sta     set_input_params_key
        ldx     #sizeof_state-1
L8322:  lda     $A7,x
        sta     $0600,x
        dex
        bpl     L8322
        lda     set_input_params_key
        jsr     L8110
        php
        ldx     #sizeof_state-1
L8333:  lda     $0600,x
        sta     $A7,x
        dex
        bpl     L8333
        plp
        bcc     L8346
        lda     #$40
        sta     L7D81
        jmp     L7EAD

L8346:  rts

L8347:  A2D_CALL A2D_SET_INPUT, set_input_params
        rts

.proc set_input_params          ; 1 byte shorter than normal, since KEY
state:  .byte   A2D_INPUT_KEY
key:    .byte   0
modifiers:
        .byte   0
unk:    .byte   0
.endproc
        set_input_params_key := set_input_params::key
        set_input_params_modifiers := set_input_params::modifiers
        set_input_params_unk := set_input_params::unk

L8352:  lda     L7D74
        cmp     #$04
        beq     L8368
        lda     L7D75
        bne     L8368
        lda     L7D76
        bne     L8368
        bit     L76A7
        bpl     L836A
L8368:  sec
        rts

L836A:  jsr     L70B7
        lda     $CC
        bne     L8380
        lda     #$09
        bit     set_input_params::modifiers
        bpl     L837A
        lda     #$41
L837A:  cmp     $CB
        bcc     L8380
        clc
        rts

L8380:  inc     set_input_params::unk
        clc
        lda     #$08
        L8388 := *+2
        bit     set_input_params::modifiers
        bpl     L838D
        lda     #$40
L838D:  adc     L769B
        sta     L769B
        bcc     L8398
        inc     L769C
L8398:  clc
        rts

L839A:  lda     L7D74
        cmp     #$04
        beq     L83B3
        bit     L76A7
        .byte   $30
L83A5:  ora     $75AD
        adc     $2FE9,x
        lda     L7D76
        sbc     #$02
        beq     L83B5
        sec
L83B3:  sec
        rts

L83B5:  jsr     L70B7
        sec
        lda     #$2F
        sbc     $C7
        tax
        lda     #$02
        sbc     $C8
        beq     L83C6
        ldx     #$FF
L83C6:  bit     set_input_params_modifiers
        bpl     L83D1
        cpx     #$64
        bcc     L83D7
        bcs     L83D9
L83D1:  cpx     #$2C
        bcc     L83D7
        bcs     L83E2
L83D7:  clc
        rts

L83D9:  sec
        lda     L769B
        sbc     #$40
        jmp     L83E8

L83E2:  sec
        lda     L769B
        sbc     #$08
L83E8:  sta     L769B
        bcs     L83F0
        dec     L769C
L83F0:  inc     set_input_params_unk
        clc
        rts

L83F5:  .byte   0
L83F6:  lda     #$80
        sta     L83F5
L83FB:  rts

L83FC:  bit     L7D74
        bpl     L83FB
        bit     L83F5
        bpl     L83FB
        jsr     L70B7
        php
        sei
        ldx     #$00
L840D:  sec
        lda     $CB,x
        sbc     #$04
        sta     L7D75,x
        lda     $CC,x
        sbc     #$00
        sta     L7D76,x
        inx
        inx
        cpx     #$04
        bcc     L840D
        jsr     L7E98
        plp
        rts

;;; ==================================================

;;; $21 IMPL

;;; Sets up mouse clamping

;;; 2 bytes of params, copied to $82
;;; byte 1 controls x clamp, 2 controls y clamp
;;; clamp is to fractions of screen (0 = full, 1 = 1/2, 2 = 1/4, 3 = 1/8) (why???)

.proc L8427
        lda     $82
        sta     L5FFD
        lda     $83
        sta     L5FFE

L8431:  bit     no_mouse_flag   ; called after INITMOUSE
        bmi     end

        lda     L5FFD
        asl     a
        tay
        lda     #0
        sta     mouse_x_lo
        sta     mouse_x_hi
        bit     L5FFF
        bmi     :+

        sta     CLAMP_MIN_LO
        sta     CLAMP_MIN_HI

:       lda     clamp_x_table,y
        sta     mouse_y_lo
        bit     L5FFF
        bmi     :+

        sta     CLAMP_MAX_LO

:       lda     clamp_x_table+1,y
        sta     mouse_y_hi
        bit     L5FFF
        bmi     :+
        sta     CLAMP_MAX_HI
:       lda     #CLAMP_X
        ldy     #CLAMPMOUSE
        jsr     call_mouse

        lda     L5FFE
        asl     a
        tay
        lda     #0
        sta     mouse_x_lo
        sta     mouse_x_hi
        bit     L5FFF
        bmi     :+
        sta     CLAMP_MIN_LO
        sta     CLAMP_MIN_HI
:       lda     clamp_y_table,y
        sta     mouse_y_lo
        bit     L5FFF
        bmi     :+
        sta     CLAMP_MAX_LO
:       lda     clamp_y_table+1,y
        sta     mouse_y_hi
        bit     L5FFF
        bmi     :+
        sta     CLAMP_MAX_HI
:       lda     #CLAMP_Y
        ldy     #CLAMPMOUSE
        jsr     call_mouse
end:    rts

clamp_x_table:  .word   560-1, 560/2-1, 560/4-1, 560/8-1
clamp_y_table:  .word   192-1, 192/2-1, 192/4-1, 192/8-1

.endproc

;;; ==================================================
;;; Locate Mouse Slot


        ;; If X's high bit is set, only slot in low bits is tested.
        ;; Otherwise all slots are scanned.

.proc find_mouse
        txa
        and     #$7F
        beq     scan
        jsr     check_mouse_in_a
        sta     no_mouse_flag
        beq     found
        ldx     #0
        rts

        ;; Scan for mouse starting at slot 7
scan:   ldx     #7
loop:   txa
        jsr     check_mouse_in_a
        sta     no_mouse_flag
        beq     found
        dex
        bpl     loop
        ldx     #0              ; no mouse found
        rts

found:  ldy     #INITMOUSE
        jsr     call_mouse
        jsr     L8427::L8431
        ldy     #HOMEMOUSE
        jsr     call_mouse
        lda     mouse_firmware_hi
        and     #$0F
        tax                     ; return with mouse slot in X
        rts

        ;; Check for mouse in slot A
.proc check_mouse_in_a
        ptr := $88

        ora     #>$C000
        sta     ptr+1
        lda     #<$0000
        sta     ptr

        ldy     #$0C            ; $Cn0C = $20
        lda     (ptr),y
        cmp     #$20
        bne     nope

        ldy     #$FB            ; $CnFB = $D6
        lda     (ptr),y
        cmp     #$D6
        bne     nope

        lda     ptr+1           ; yay, found it!
        sta     mouse_firmware_hi
        asl     a
        asl     a
        asl     a
        asl     a
        sta     mouse_operand
        lda     #$00
        rts

nope:   lda     #$80
        rts
.endproc
.endproc

no_mouse_flag:               ; high bit set if no mouse present
        .byte   0
mouse_firmware_hi:           ; e.g. if mouse is in slot 4, this is $C4
        .byte   0
mouse_operand:               ; e.g. if mouse is in slot 4, this is $40
        .byte   0

;;; ==================================================

        .byte   $03
        sbc     #$85
        php
        lda     $E904,x
        sta     $09
        ldy     #$14
        ldx     #$00
L852C:  lda     ($08),y
        sta     L8590,x
        iny
        inx
        cpx     #$04
        bne     L852C
        ldy     #$1C
        ldx     #$00
L853B:  lda     ($08),y
        sta     L8594,x
        iny
        inx
        cpx     #$04
        bne     L853B
        ldy     #$03
        lda     ($06),y
        sec
        sbc     L8590
        sta     ($06),y
        iny
        lda     ($06),y
        sbc     L8591
        sta     ($06),y
        iny
        lda     ($06),y
        sec
        sbc     L8592
        sta     ($06),y
        iny
        lda     ($06),y
        sbc     L8593
        sta     ($06),y
        ldy     #$03
        lda     ($06),y
        clc
        adc     L8594
        sta     ($06),y
        iny
        lda     ($06),y
        adc     L8595
        sta     ($06),y
        iny
        lda     ($06),y
        clc
        adc     L8596
        sta     ($06),y
        iny
        lda     ($06),y
        adc     L8597
        sta     ($06),y
        jsr     L83A5
        rts

L8590:  .byte   $24
L8591:  .byte   $00
L8592:  .byte   $23
L8593:  .byte   $00
L8594:  .byte   $00
L8595:  .byte   $00
L8596:  .byte   $00
L8597:  .byte   $00
        lda     #$00
        ldx     #$00
L859C:  sta     $D409,x
        sta     $D401,x
        sta     $D40D
        inx
        cpx     #$04
        bne     L859C
        lda     #$0A
        sta     $D40D
        sta     $D40F

        ;; Relay for main>aux A2D call (Y=call, X,A=params addr)
.macro A2D_RELAY_CALL call, addr
        ldy     #(call)
        lda     #<(addr)
        ldx     #>(addr)
        jsr     desktop_A2D_RELAY
.endmacro

        A2D_RELAY_CALL A2D_SET_STATE, $D401
        rts

        lda     #$39
        ldx     #$1A
        jsr     L6B17
        ldx     $D5CA
        txs
        rts

        lda     #$56
        ldx     #$1A
        jsr     L6B17
        ldx     $D5CA
        txs
        rts

        lda     #$71
        ldx     #$1A
        jsr     L6B17
        ldx     $D5CA
        txs
        rts

        cmp     #$27
        bne     L85F2
        lda     #$22
        ldx     #$1B
        jsr     L6B17
        ldx     $D5CA
        txs
        jmp     L8625

L85F2:  cmp     #$45
        bne     L8604
        lda     #$3B
        ldx     #$1B
        jsr     L6B17
        ldx     $D5CA
        txs
        jmp     L8625

L8604:  cmp     #$52
        bne     L8616
        lda     #$5B
        ldx     #$1B
        jsr     L6B17
        ldx     $D5CA
        txs
        jmp     L8625

L8616:  cmp     #$57
        bne     L8625
        lda     #$7C
        ldx     #$1B
        jsr     L6B17
        ldx     $D5CA
        txs
L8625:  A2D_RELAY_CALL $33, desktop_win18_state
        rts

        lda     #$9C
        ldx     #$1B
        jsr     L6B17
        ldx     $D5CA
        txs
        A2D_RELAY_CALL $33, desktop_win18_state
        rts

        lda     #$BF
        ldx     #$1B
        jsr     L6B17
        ldx     $D5CA
        txs
        A2D_RELAY_CALL $33, desktop_win18_state
        rts

        sta     L8737
        sty     L8738
        and     #$F0
        sta     online_params_unit
        sta     ALTZPOFF
        MLI_CALL ON_LINE, online_params
        sta     ALTZPON
        beq     L867B
L8672:  pha
        dec     $EF8A
        dec     $EF88
        pla
        rts

L867B:  lda     online_params_buffer
        beq     L8672
        jsr     L8388           ; ??? This is the middle of an instruction?
        jsr     desktop_LD05E
        ldy     L8738
        sta     $D464,y
        asl     a
        tax
        lda     $F13A,x
        sta     $06
        lda     $F13B,x
        sta     $07
        ldx     #$00
        ldy     #$09
        lda     #$20
L869E:  sta     ($06),y
        iny
        inx
        cpx     #$12
        bne     L869E
        ldy     #$09
        lda     online_params_buffer
        and     #$0F
        sta     online_params_buffer
        sta     ($06),y
        ldx     #$00
        ldy     #$0B
L86B6:  lda     online_params_buffer+1,x
        cmp     #$41
        bcc     L86C4
        cmp     #$5F
        bcs     L86C4
        clc
        adc     #$20
L86C4:  sta     ($06),y
        iny
        inx
        cpx     online_params_buffer
        bne     L86B6
        ldy     #$09
        lda     ($06),y
        clc
        adc     #$02
        sta     ($06),y
        lda     L8737
        and     #$0F
        cmp     #$04
        bne     L86ED
        ldy     #$07
        lda     #$B4
        sta     ($06),y
        iny
        lda     #$14
        sta     ($06),y
        jmp     L870A

L86ED:  cmp     #$0B
        bne     L86FF
        ldy     #$07
        lda     #$70
        sta     ($06),y
        iny
        lda     #$14
        sta     ($06),y
        jmp     L870A

L86FF:  ldy     #$07
        lda     #$40
        sta     ($06),y
        iny
        lda     #$14
        sta     ($06),y
L870A:  ldy     #$02
        lda     #$00
        sta     ($06),y
        inc     L8738
        lda     L8738
        asl     a
        asl     a
        tax
        ldy     #$03
L871B:  lda     L8739,x
        sta     ($06),y
        inx
        iny
        cpy     #$07
        bne     L871B
        ldx     $EF8A
        dex
        ldy     #$00
        lda     ($06),y
        sta     $EF8B,x
        jsr     L83A5
        lda     #$00
        rts

L8737:  rts

L8738:  .byte   $04
L8739:  .byte   $00,$00,$00,$00

        ;; Desktop icon placements?
        .word   500, 16
        .word   500, 41
        .word   500, 66
        .word   500, 91
        .word   500, 116

        .word   440, 16
        .word   440, 41
        .word   440, 66
        .word   440, 91
        .word   440, 116
        .word   440, 141

        .word   400, 16
        .word   400, 41
        .word   400, 66

.proc online_params
count:  .byte   2
unit:   .byte   $60             ; Slot 6 Drive 1
buffer: .addr   online_params_buffer
.endproc
        online_params_unit := online_params::unit

        ;; Per ProDOS TRM this should be 256 bytes!
online_params_buffer:
        .byte   $0B
        .byte   "GRAPHICS.TK",$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$C8

;;; ==================================================
;;; Font

font_table:
        .byte   $00,$7F         ; ??

glyph_height:
        .byte   9

glyph_width_table:
        .byte   $01,$07,$07,$07,$07,$07,$01,$07
        .byte   $07,$07,$07,$07,$07,$07,$07,$07
        .byte   $07,$03,$07,$06,$07,$07,$07,$07
        .byte   $07,$07,$07,$07,$07,$07,$07,$07
        .byte   $05,$03,$04,$07,$06,$06,$06,$02
        .byte   $03,$03,$06,$06,$03,$06,$03,$07
        .byte   $06,$06,$06,$06,$06,$06,$06,$06
        .byte   $06,$06,$03,$03,$05,$06,$05,$06
        .byte   $07,$07,$07,$07,$07,$07,$07,$07
        .byte   $07,$07,$07,$07,$07,$07,$07,$07
        .byte   $07,$07,$07,$07,$07,$07,$06,$07
        .byte   $07,$07,$07,$05,$06,$06,$04,$06
        .byte   $05,$07,$07,$06,$07,$06,$06,$06
        .byte   $06,$03,$05,$06,$03,$07,$06,$06
        .byte   $06,$06,$06,$06,$06,$06,$06,$07
        .byte   $06,$06,$06,$04,$02,$04,$05,$07

glyph_bitmaps:
        ;; Format is: glyph0-row0, glyph1-row0, ...
        .byte   $00,$00,$00,$3F,$77,$01,$01,$00
        .byte   $00,$7F,$00,$00,$7F,$20,$3E,$3E
        .byte   $00,$00,$3C,$00,$00,$00,$00,$00
        .byte   $14,$55,$2A,$00,$7F,$00,$10,$10
        .byte   $00,$03,$05,$12,$04,$03,$02,$01
        .byte   $02,$01,$00,$00,$00,$00,$00,$00
        .byte   $0E,$0C,$0E,$0E,$1B,$1F,$0E,$1F
        .byte   $0E,$0E,$00,$00,$00,$00,$00,$0E
        .byte   $00,$1E,$1F,$1E,$1F,$3F,$3F,$1E
        .byte   $33,$3F,$3E,$33,$03,$33,$33,$1E
        .byte   $1F,$1E,$1F,$1E,$3F,$33,$1B,$33
        .byte   $33,$33,$3F,$0F,$00,$0F,$02,$00
        .byte   $03,$00,$03,$00,$30,$00,$1C,$00
        .byte   $03,$03,$0C,$03,$03,$00,$00,$00
        .byte   $00,$00,$00,$00,$06,$00,$00,$00
        .byte   $00,$00,$00,$04,$01,$01,$05,$00
        .byte   $00,$7F,$00,$21,$1C,$03,$01,$00
        .byte   $00,$01,$08,$08,$40,$20,$41,$41
        .byte   $00,$00,$42,$00,$00,$00,$08,$00
        .byte   $14,$2A,$55,$00,$3F,$40,$08,$08
        .byte   $00,$03,$05,$12,$1E,$13,$05,$01
        .byte   $01,$02,$04,$04,$00,$00,$00,$30
        .byte   $1B,$0F,$1B,$1B,$1B,$03,$1B,$18
        .byte   $1B,$1B,$00,$00,$0C,$00,$03,$1B
        .byte   $1E,$33,$33,$33,$33,$03,$03,$33
        .byte   $33,$0C,$18,$1B,$03,$3F,$33,$33
        .byte   $33,$33,$33,$33,$0C,$33,$1B,$33
        .byte   $33,$33,$30,$03,$00,$0C,$05,$00
        .byte   $06,$00,$03,$00,$30,$00,$06,$00
        .byte   $03,$00,$00,$03,$03,$00,$00,$00
        .byte   $00,$00,$00,$00,$06,$00,$00,$00
        .byte   $00,$00,$00,$02,$01,$02,$0A,$00
        .byte   $00,$41,$00,$12,$08,$07,$01,$00
        .byte   $0C,$01,$08,$1C,$40,$20,$5D,$5D
        .byte   $77,$03,$04,$1F,$0C,$18,$1C,$0C
        .byte   $14,$55,$2A,$0C,$1F,$60,$36,$36
        .byte   $00,$03,$00,$3F,$05,$08,$05,$00
        .byte   $01,$02,$15,$04,$00,$00,$00,$18
        .byte   $1B,$0C,$18,$18,$1B,$0F,$03,$0C
        .byte   $1B,$1B,$03,$03,$06,$0F,$06,$18
        .byte   $21,$33,$33,$03,$33,$03,$03,$03
        .byte   $33,$0C,$18,$0F,$03,$3F,$37,$33
        .byte   $33,$33,$33,$03,$0C,$33,$1B,$33
        .byte   $1E,$33,$18,$03,$01,$0C,$00,$00
        .byte   $0C,$1E,$1F,$1E,$3E,$0E,$06,$0E
        .byte   $0F,$03,$0C,$1B,$03,$1F,$0F,$0E
        .byte   $0F,$1E,$0F,$1E,$1F,$1B,$1B,$23
        .byte   $1B,$1B,$1F,$02,$01,$02,$00,$00
        .byte   $00,$41,$3F,$0C,$08,$0F,$01,$00
        .byte   $06,$01,$08,$3E,$40,$24,$45,$55
        .byte   $52,$02,$08,$0A,$00,$30,$36,$12
        .byte   $77,$2A,$55,$1E,$4E,$31,$7F,$49
        .byte   $00,$03,$00,$12,$0E,$04,$02,$00
        .byte   $01,$02,$0E,$1F,$00,$1F,$00,$0C
        .byte   $1B,$0C,$0C,$0C,$1F,$18,$0F,$06
        .byte   $0E,$1E,$00,$00,$03,$00,$0C,$0C
        .byte   $2D,$3F,$1F,$03,$33,$0F,$0F,$3B
        .byte   $3F,$0C,$18,$0F,$03,$33,$3B,$33
        .byte   $1F,$33,$1F,$1E,$0C,$33,$1B,$33
        .byte   $0C,$1E,$0C,$03,$02,$0C,$00,$00
        .byte   $00,$30,$33,$03,$33,$1B,$0F,$1B
        .byte   $1B,$03,$0C,$0F,$03,$2B,$1B,$1B
        .byte   $1B,$1B,$1B,$03,$06,$1B,$1B,$2B
        .byte   $0E,$1B,$18,$01,$01,$04,$00,$2A
        .byte   $00,$01,$20,$0C,$08,$1F,$01,$7F
        .byte   $7F,$01,$6B,$6B,$40,$26,$45,$4D
        .byte   $12,$02,$3E,$0A,$3F,$7F,$63,$21
        .byte   $00,$55,$2A,$3F,$64,$1B,$3F,$21
        .byte   $00,$03,$00,$12,$14,$02,$15,$00
        .byte   $01,$02,$15,$04,$00,$00,$00,$06
        .byte   $1B,$0C,$06,$18,$18,$18,$1B,$03
        .byte   $1B,$10,$00,$00,$06,$0F,$06,$06
        .byte   $3D,$33,$33,$03,$33,$03,$03,$33
        .byte   $33,$0C,$18,$0F,$03,$33,$33,$33
        .byte   $03,$33,$33,$30,$0C,$33,$1B,$3F
        .byte   $1E,$0C,$06,$03,$04,$0C,$00,$00
        .byte   $00,$3E,$33,$03,$33,$1F,$06,$1B
        .byte   $1B,$03,$0C,$07,$03,$2B,$1B,$1B
        .byte   $1B,$1B,$03,$0E,$06,$1B,$1B,$2B
        .byte   $04,$1B,$0C,$02,$01,$02,$00,$14
        .byte   $00,$01,$20,$12,$08,$3F,$01,$00
        .byte   $06,$01,$3E,$08,$40,$3F,$5D,$55
        .byte   $12,$02,$10,$0A,$00,$30,$7F,$12
        .byte   $77,$2A,$55,$1E,$71,$0E,$3F,$21
        .byte   $00,$00,$00,$3F,$0F,$19,$09,$00
        .byte   $01,$02,$04,$04,$00,$00,$00,$03
        .byte   $1B,$0C,$03,$1B,$18,$1B,$1B,$03
        .byte   $1B,$1B,$03,$03,$0C,$00,$03,$00
        .byte   $1D,$33,$33,$33,$33,$03,$03,$33
        .byte   $33,$0C,$1B,$1B,$03,$33,$33,$33
        .byte   $03,$33,$33,$33,$0C,$33,$0E,$3F
        .byte   $33,$0C,$03,$03,$08,$0C,$00,$00
        .byte   $00,$33,$33,$03,$33,$03,$06,$1B
        .byte   $1B,$03,$0C,$0F,$03,$2B,$1B,$1B
        .byte   $1B,$1B,$03,$18,$06,$1B,$0E,$2B
        .byte   $0E,$1B,$06,$02,$01,$02,$00,$2A
        .byte   $00,$01,$20,$2D,$08,$0D,$01,$00
        .byte   $0C,$01,$1C,$08,$40,$06,$41,$41
        .byte   $00,$00,$1A,$0A,$0C,$18,$00,$0C
        .byte   $14,$55,$2A,$0C,$7B,$04,$7E,$6A
        .byte   $00,$03,$00,$12,$04,$18,$16,$00
        .byte   $02,$01,$00,$00,$02,$00,$03,$00
        .byte   $0E,$1F,$1F,$0E,$18,$0E,$0E,$03
        .byte   $0E,$0E,$00,$03,$00,$00,$00,$06
        .byte   $01,$33,$1F,$1E,$1F,$3F,$03,$1E
        .byte   $33,$3F,$0E,$33,$3F,$33,$33,$1E
        .byte   $03,$1E,$33,$1E,$0C,$1E,$04,$33
        .byte   $33,$0C,$3F,$0F,$10,$0F,$00,$00
        .byte   $00,$3F,$1F,$1E,$3E,$1E,$06,$1E
        .byte   $1B,$03,$0C,$1B,$03,$2B,$1B,$0E
        .byte   $0F,$1E,$03,$0F,$06,$1E,$04,$1F
        .byte   $1B,$1E,$1F,$04,$01,$01,$00,$14
        .byte   $00,$7F,$3F,$3F,$1C,$18,$01,$00
        .byte   $00,$01,$08,$08,$40,$04,$3E,$3E
        .byte   $00,$00,$4F,$00,$00,$00,$00,$00
        .byte   $14,$2A,$55,$00,$7F,$00,$36,$36
        .byte   $00,$00,$00,$12,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$02,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$01,$00,$00,$00,$00
        .byte   $3E,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$30,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$1F
        .byte   $00,$00,$00,$00,$00,$00,$00,$18
        .byte   $00,$00,$0C,$00,$00,$00,$00,$00
        .byte   $03,$18,$00,$00,$00,$00,$00,$00
        .byte   $00,$18,$00,$00,$00,$00,$00,$2A
        ;; end of font glyphs

;;; ==================================================

        .byte   $00,$00,$00,$00,$77,$30,$01
        .byte   $00,$00,$7F,$00,$00,$7F,$00,$00
        .byte   $00,$00,$00,$7A,$00,$00,$00,$00
        .byte   $00,$14,$55,$2A,$00,$7F,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$01,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $0E,$00,$00,$07,$00,$00,$00,$00
        .byte   $00,$03,$18,$00,$00,$00,$00,$00
        .byte   $00,$00,$0E,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00
.endproc

.proc desktop
;;; ==================================================
;;; DeskTop - the actual application
;;; ==================================================

        ;; Entry point for "DESKTOP"
        .assert * = DESKTOP, error, "DESKTOP entry point must be at $8E00"
        jmp     DESKTOP_DIRECT

.macro A2D_RELAY2_CALL call, addr
        ldy     #call
        .if .paramcount = 1
        lda     #0
        ldx     #0
        .else
        lda     #<(addr)
        ldx     #>(addr)
        .endif
        jsr     A2D_RELAY2
.endmacro

L8E03:  .byte   $08,$00
L8E05:  .byte   $00
L8E06:  .byte   $00
L8E07:  .byte   $00
L8E08:  .byte   $00
L8E09:  .byte   $00
L8E0A:  .byte   $00
L8E0B:  .byte   $00
L8E0C:  .byte   $00
L8E0D:  .byte   $00
L8E0E:  .byte   $00
L8E0F:  .byte   $00
L8E10:  .byte   $00
L8E11:  .byte   $00
L8E12:  .byte   $00
L8E13:  .byte   $00
L8E14:  .byte   $00
L8E15:  .byte   $00
L8E16:  .byte   $00
L8E17:  .byte   $00
L8E18:  .byte   $00
L8E19:  .byte   $00
L8E1A:  .byte   $00
L8E1B:  .byte   $00
L8E1C:  .byte   $00
L8E1D:  .byte   $00
L8E1E:  .byte   $00
L8E1F:  .byte   $00
L8E20:  .byte   $00
L8E21:  .byte   $00
L8E22:  .byte   $00
L8E23:  .byte   $00
L8E24:  .byte   $00

.proc draw_bitmap_params2
left:   .word   0
top:    .word   0
addr:   .addr   0
stride: .word   0
hoff:   .word   0
voff:   .word   0
width:  .word   0
height: .word   0
.endproc

.proc draw_bitmap_params
left:   .word   0
top:    .word   0
addr:   .addr   0
stride: .word   0
hoff:   .word   0
voff:   .word   0
.endproc

        .byte   $00,$00
L8E43:  .byte   $00,$00

.proc fill_rect_params6
left:   .word   0
top:    .word   0
right:  .word   0
bottom: .word   0
.endproc

.proc measure_text_params
addr:   .addr   text_buffer
length: .byte   0
width:  .word   0
.endproc
set_text_mask_params :=  measure_text_params::width + 1 ; re-used

.proc draw_text_params
addr:   .addr   text_buffer
length: .byte   0
.endproc

text_buffer:
        .res    19, 0

white_pattern2:
        .byte   %11111111
        .byte   %11111111
        .byte   %11111111
        .byte   %11111111
        .byte   %11111111
        .byte   %11111111
        .byte   %11111111
        .byte   %11111111
        .byte   $FF

black_pattern:
        .byte   %00000000
        .byte   %00000000
        .byte   %00000000
        .byte   %00000000
        .byte   %00000000
        .byte   %00000000
        .byte   %00000000
        .byte   %00000000
        .byte   $FF

checkerboard_pattern2:
        .byte   %01010101
        .byte   %10101010
        .byte   %01010101
        .byte   %10101010
        .byte   %01010101
        .byte   %10101010
        .byte   %01010101
        .byte   %10101010
        .byte   $FF

dark_pattern:
        .byte   %00010001
        .byte   %01000100
        .byte   %00010001
        .byte   %01000100
        .byte   %00010001
        .byte   %01000100
        .byte   %00010001
        .byte   %01000100
        .byte   $FF

light_pattern:
        .byte   %11101110
        .byte   %10111011
        .byte   %11101110
        .byte   %10111011
        .byte   %11101110
        .byte   %10111011
        .byte   %11101110
        .byte   %10111011
L8E94:  .byte   $FF

L8E95:
        L8E96 := * + 1
        L8E97 := * + 2
        .res    128, 0

L8F15:  .res    256, 0

L9015:  .byte   $00
L9016:  .byte   $00
L9017:  .byte   $00
L9018:  .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00

drag_outline_buffer:
        .res    680, 0

L933E:  .byte   $00

.proc query_target_params2
queryx: .word   0
queryy: .word   0
element:.byte   0
id:     .byte   0
.endproc

.proc query_screen_params
left:   .word   0
top:    .word   0
addr:   .addr   A2D_SCREEN_ADDR
stride: .word   A2D_SCREEN_STRIDE
L934D:
hoff:   .word   0
voff:   .word   0
width:  .word   560-1
height: .word   192-1
pattern:.res    8, $FF
mskand: .byte   A2D_DEFAULT_MSKAND
mskor:  .byte   A2D_DEFAULT_MSKOR
xpos:   .word   0
ypos:   .word   0
hthick: .byte   1
vthick: .byte   1
mode:   .byte   $96             ; ???
tmask:  .byte   0
font:   .addr   A2D_DEFAULT_FONT
.endproc

.proc query_state_params
id:     .byte   0
addr:   .addr   set_state_params
.endproc

.proc set_state_params
left:   .word   0
top:    .word   0
addr:   .addr   0
stride: .word   0
hoff:   .word   0
voff:   .word   0
width:  .word   0
height: .word   0
pattern:.res    8, 0
mskand: .byte   0
mskor:  .byte   0
xpos:   .word   0
ypos:   .word   0
hthick: .byte   0
vthick: .byte   0
mode:   .byte   0
tmask:  .byte   0
font:   .addr   0
.endproc

        .byte   $00,$00,$00
        .byte   $00,$FF,$80

        ;; Used for FILL_MODE params
const0a:.byte   0
const1a:.byte   1
const2a:.byte   2
const3a:.byte   3
const4a:.byte   4
        .byte   5, 6, 7

        ;; DESKTOP command jump table
L939E:  .addr   0               ; $00
        .addr   L9419           ; $01
        .addr   L9454           ; $02
        .addr   L94C0           ; $03
        .addr   L9508           ; $04
        .addr   L95A2           ; $05
        .addr   L9692           ; $06
        .addr   L96D2           ; $07
        .addr   L975B           ; $08
        .addr   L977D           ; $09
        .addr   L97F7           ; $0A
        .addr   L9EBE           ; $0B
        .addr   LA2A6           ; $0C REDRAW_ICONS
        .addr   L9EFB           ; $0D
        .addr   L958F           ; $0E

.macro  DESKTOP_DIRECT_CALL    op, addr, label
        jsr DESKTOP_DIRECT
        .byte op
        .addr addr
.endmacro

        ;; DESKTOP entry point (after jump)
DESKTOP_DIRECT:

        ;; Stash return value from stack, adjust by 3
        ;; (command byte, params addr)
        pla
        sta     call_params
        clc
        adc     #<3
        tax
        pla
        sta     call_params+1
        adc     #>3
        pha
        txa
        pha

        ;; Save $06..$09 on the stack
        ldx     #0
:       lda     $06,x
        pha
        inx
        cpx     #4
        bne     :-

        ;; Point ($06) at call command
        lda     call_params
        clc
        adc     #<1
        sta     $06
        lda     call_params+1
        adc     #>1
        sta     $07

        ldy     #0
        lda     ($06),y
        asl     a
        tax
        lda     L939E,x
        sta     dispatch + 1
        lda     L939E+1,x
        sta     dispatch + 2
        iny
        lda     ($06),y
        tax
        iny
        lda     ($06),y
        sta     $07
        stx     $06

dispatch:
        jsr     $0000

        tay
        ldx     #$03
L9409:  pla
        sta     $06,x
        dex
        cpx     #$FF
        bne     L9409
        tya
        rts

call_params:  .addr     0

.proc set_pos_params2
xcoord: .word   0
ycoord: .word   0
.endproc

;;; ==================================================

;;; DESKTOP $01 IMPL

L9419:
        ldy     #$00
        lda     ($06),y
        ldx     L8E95
        beq     L9430
        dex
L9423:  .byte   $DD
        .byte   $96
L9425:  stx     $05F0
        dex
        bpl     L9423
        bmi     L9430
        lda     #$01
        rts

L9430:  jsr     L943E
        jsr     L9F98
        lda     #$01
        tay
        sta     ($06),y
        lda     #$00
        rts

L943E:  ldx     L8E95
        sta     L8E96,x
        inc     L8E95
        asl     a
        tax
        lda     $06
        sta     L8F15,x
        lda     $07
        sta     L8F15+1,x
        rts

;;; ==================================================

;;; DESKTOP $02 IMPL

L9454:  ldx     L8E95
        beq     L9466
        dex
        ldy     #$00
        lda     ($06),y
L945E:  cmp     L8E96,x
        beq     L9469
        dex
        bpl     L945E
L9466:  lda     #$01
        rts

L9469:  asl     a
        tax
        lda     L8F15,x
        sta     $06
        lda     L8F15+1,x
        sta     $07
        ldy     #$01
        lda     ($06),y
        bne     L947E
        lda     #$02
        rts

L947E:  lda     L9015
        beq     L9498
        dey
        lda     ($06),y
        ldx     L9016
        dex
L948A:  cmp     L9017,x
        beq     L9495
        dex
        bpl     L948A
        jmp     L949D

L9495:  lda     #$03
        rts

L9498:  lda     #$01
        sta     L9015
L949D:  ldx     L9016
        ldy     #$00
        lda     ($06),y
        sta     L9017,x
        inc     L9016
        lda     ($06),y
        ldx     #$01
        jsr     LA324
        ldy     #$00
        lda     ($06),y
        ldx     #$01
        jsr     LA2E3
        jsr     L9F9F
        lda     #$00
        rts

;;; ==================================================

;;; DESKTOP $03 IMPL

L94C0:
        ldx     L8E95
        beq     L94D2
        dex
        ldy     #$00
        lda     ($06),y
L94CA:  cmp     L8E96,x
        beq     L94D5
        dex
        bpl     L94CA
L94D2:  lda     #$01
        rts

L94D5:  asl     a
        tax
        lda     L8F15,x
        sta     $06
        lda     L8F15+1,x
        sta     $07
        lda     L9015
        bne     L94E9
        jmp     L9502

L94E9:  ldx     L9016
        dex
        ldy     #$00
        lda     ($06),y
L94F1:  cmp     L9017,x
        beq     L94FC
        dex
        bpl     L94F1
        jmp     L9502

L94FC:  jsr     L9F9F
        lda     #$00
        rts

L9502:  jsr     L9F98
        lda     #$00
        rts

;;; ==================================================

;;; DESKTOP $04 IMPL

L9508:
        ldy     #$00
        ldx     L8E95
        beq     L951A
        dex
        lda     ($06),y
L9512:  cmp     L8E96,x
        beq     L951D
        dex
        bpl     L9512
L951A:  lda     #$01
        rts

L951D:  asl     a
        tax
        lda     L8F15,x
        sta     $06
        lda     L8F15+1,x
        sta     $07
        ldy     #$01
        lda     ($06),y
        bne     L9532
        lda     #$02
        rts

L9532:  jsr     LA18A
        A2D_CALL A2D_SET_FILL_MODE, const0a
        jsr     LA39D
        ldy     #$00
        lda     ($06),y
        ldx     L8E95
        jsr     LA2E3
        dec     L8E95
        lda     #$00
        ldx     L8E95
        sta     L8E96,x
        ldy     #$01
        lda     #$00
        sta     ($06),y
        lda     L9015
        beq     L958C
        ldx     L9016
        dex
        ldy     #$00
        lda     ($06),y
L9566:  cmp     L9017,x
        beq     L9571
        dex
        bpl     L9566
        jmp     L958C

L9571:  ldx     L9016
        jsr     LA324
        dec     L9016
        lda     L9016
        bne     L9584
        lda     #$00
        sta     L9015
L9584:  lda     #$00
        ldx     L9016
        sta     L9017,x
L958C:  lda     #$00
        rts

;;; ==================================================

;;; DESKTOP $0E IMPL

L958F:
        ldy     #$00
        lda     ($06),y
        asl     a
        tax
        lda     L8F15,x
        sta     $06
        lda     L8F15+1,x
        sta     $07
        jmp     LA39D

;;; ==================================================

;;; DESKTOP $05 IMPL

L95A2:
        jmp     L9625

L95A5:
L95A6 := * + 1
        .res    128, 0

L9625:  lda     L9454
        beq     L9639
        lda     L9017
        sta     L95A5
        DESKTOP_DIRECT_CALL $B, $95A5
        jmp     L9625

L9639:  ldx     #$7E
        lda     #$00
L963D:  sta     L95A6,x
        dex
        bpl     L963D
        ldx     #$00
        stx     L95A5
L9648:  lda     L8E96,x
        asl     a
        tay
        lda     L8F15,y
        sta     $08
        lda     L8F15+1,y
        sta     $09
        ldy     #$02
        lda     ($08),y
        and     #$0F
        ldy     #$00
        cmp     ($06),y
        bne     L9670
        ldy     #$00
        lda     ($08),y
        ldy     L95A5
        sta     L95A6,y
        inc     L95A5
L9670:  inx
        cpx     L8E95
        bne     L9648
        ldx     #$00
        txa
        pha
L967A:  lda     L95A6,x
        bne     L9681
        pla
        rts

L9681:  sta     L95A5
        DESKTOP_DIRECT_CALL $2, $95A5
        pla
        tax
        inx
        txa
        pha
        jmp     L967A

;;; ==================================================

;;; DESKTOP $06 IMPL

L9692:
        jmp     L9697

L9695:  .byte   0
L9696:  .byte   0

L9697:  lda     L8E95
        sta     L9696
L969D:  ldx     L9696
        cpx     #$00
        beq     L96CF
        dec     L9696
        dex
        lda     L8E96,x
        sta     L9695
        asl     a
        tax
        lda     L8F15,x
        sta     $08
        lda     L8F15+1,x
        sta     $09
        ldy     #$02
        lda     ($08),y
        and     #$0F
        ldy     #$00
        cmp     ($06),y
        bne     L969D
        DESKTOP_DIRECT_CALL $4, $9695
        jmp     L969D
L96CF:  lda     #$00
        rts

;;; ==================================================

;;; DESKTOP $07 IMPL

L96D2:
        jmp     L96D7

L96D5:  .byte   0
L96D6:  .byte   0

L96D7:  lda     L8E95
        sta     L96D6
L96DD:  ldx     L96D6
        bne     L96E5
        lda     #$00
        rts

L96E5:  dec     L96D6
        dex
        lda     L8E96,x
        sta     L96D5
        asl     a
        tax
        lda     L8F15,x
        sta     $08
        lda     L8F15+1,x
        sta     $09
        ldy     #$02
        lda     ($08),y
        and     #$0F
        ldy     #$00
        cmp     ($06),y
        bne     L96DD
        ldy     #$00
        lda     ($08),y
        ldx     L8E95
        jsr     LA2E3
        dec     L8E95
        lda     #$00
        ldx     L8E95
        sta     L8E96,x
        ldy     #$01
        lda     #$00
        sta     ($08),y
        lda     L9015
        beq     L9758
        ldx     #$00
        ldy     #$00
L972B:  lda     ($08),y
        cmp     L9017,x
        beq     L973B
        inx
        cpx     L9016
        bne     L972B
        jmp     L9758

L973B:  lda     ($08),y
        ldx     L9016
        jsr     LA324
        dec     L9016
        lda     L9016
        bne     L9750
        lda     #$00
        sta     L9015
L9750:  lda     #$00
        ldx     L9016
        sta     L9017,x
L9758:  jmp     L96DD

;;; ==================================================

;;; DESKTOP $08 IMPL

L975B:
        ldx     #$00
        txa
        tay
L975F:  sta     ($06),y
        iny
        inx
        cpx     #$14
        bne     L975F
        ldx     #$00
        ldy     #$00
L976B:  lda     L9017,x
        sta     ($06),y
        cpx     L9016
        beq     L977A
        iny
        inx
        jmp     L976B

L977A:  lda     #$00
        rts

;;; ==================================================

;;; DESKTOP $09 IMPL

L977D:
        jmp     L9789

        .byte   0
        .byte   0
        .byte   0
        .byte   0
        .byte   0
        .byte   0
        .byte   0
        .byte   0
        .byte   0

L9789:  ldy     #$03
L978B:  lda     ($06),y
        sta     set_pos_params2,y
        dey
        bpl     L978B
        lda     $06
        sta     $08
        lda     $07
        sta     $09
        ldy     #$05
        lda     ($06),y
        sta     L97F5
        A2D_CALL A2D_SET_POS, set_pos_params2
        ldx     #$00
L97AA:  cpx     L8E95
        bne     L97B9
        ldy     #$04
        lda     #$00
        sta     ($08),y
        sta     L97F6
        rts

L97B9:  txa
        pha
        lda     L8E96,x
        asl     a
        tax
        lda     L8F15,x
        sta     $06
        lda     L8F15+1,x
        sta     $07
        ldy     #$02
        lda     ($06),y
        and     #$0F
        cmp     L97F5
        bne     L97E0
        jsr     LA18A
        A2D_CALL $17, L8E03
        bne     L97E6
L97E0:  pla
        tax
        inx
        jmp     L97AA

L97E6:  pla
        tax
        lda     L8E96,x
        ldy     #$04
        sta     ($08),y
        sta     L97F6
        rts

        rts

        .byte   0
L97F5:  .byte   0
L97F6:  .byte   0

;;; ==================================================

;;; DESKTOP $0A IMPL

L97F7:
        ldy     #$00
        lda     ($06),y
        sta     L982A
        tya
        sta     ($06),y
        ldy     #$04
L9803:  lda     ($06),y
        sta     L9C8D,y
        sta     L9C91,y
        dey
        cpy     #$00
        bne     L9803
        jsr     LA365
        lda     L982A
        jsr     L9EB4
        sta     $06
        stx     $07
        ldy     #$02
        lda     ($06),y
        and     #$0F
        sta     L9829
        jmp     L983D

L9829:  .byte   $00
L982A:  .byte   $00,$00
L982C:  .byte   $00
L982D:  .byte   $00
L982E:  .byte   $00
L982F:  .byte   $00
L9830:  .byte   $00
L9831:  .byte   $00
L9832:  .byte   $00
L9833:  .byte   $00
L9834:  .byte   $00
L9835:  .byte   $00,$00,$00,$00,$00,$00,$00,$00

L983D:  lda     #$00
        sta     L9830
        sta     L9833
L9845:  A2D_CALL $2C, L933E
        lda     L933E
        cmp     #$04
        beq     L9857
L9852:  lda     #$02
        jmp     L9C65

L9857:  lda     query_target_params2::queryx
        sec
        sbc     L9C8E
        sta     L982C
        lda     query_target_params2::queryx+1
        sbc     L9C8F
        sta     L982D
        lda     query_target_params2::queryy
        sec
        sbc     L9C90
        sta     L982E
        lda     query_target_params2::queryy+1
        sbc     L9C91
        sta     L982F
        lda     L982D
        bpl     L988C
        lda     L982C
        cmp     #$FB
        bcc     L98AC
        jmp     L9893

L988C:  lda     L982C
        cmp     #$05
        bcs     L98AC
L9893:  lda     L982F
        bpl     L98A2
        lda     L982E
        cmp     #$FB
        bcc     L98AC
        jmp     L9845

L98A2:  lda     L982E
        cmp     #$05
        bcs     L98AC
        jmp     L9845

L98AC:  lda     L9016
        cmp     #$15
        bcc     L98B6
        jmp     L9852

L98B6:  lda     #<drag_outline_buffer
        sta     $08
        lda     #>drag_outline_buffer
        sta     $08+1
        lda     L9015
        bne     L98C8
        lda     #$03
        jmp     L9C65

L98C8:  lda     L9017
        jsr     L9EB4
        sta     $06
        stx     $07
        ldy     #$02
        lda     ($06),y
        and     #$0F
        sta     L9832
        A2D_CALL A2D_QUERY_SCREEN, query_screen_params
        ldx     #$07
L98E3:  lda     query_screen_params::L934D,x
        sta     L9835,x
        dex
        bpl     L98E3
        ldx     L9016
        stx     L9C74
L98F2:  lda     L9016,x
        jsr     L9EB4
        sta     $06
        stx     $07
        ldy     #$00
        lda     ($06),y
        cmp     #$01
        bne     L9909
        ldx     #$80
        stx     L9833
L9909:  sta     L9834
        DESKTOP_DIRECT_CALL $D, $9834
        beq     L9954
        jsr     LA18A
        lda     L9C74
        cmp     L9016
        beq     L9936
        jsr     LA365
        lda     $08
        sec
        sbc     #$22
        sta     $08
        bcs     L992D
        dec     $09
L992D:  ldy     #$01
        lda     #$80
        sta     ($08),y
        jsr     LA382
L9936:  ldx     #$21
        ldy     #$21
L993A:  lda     L8E03,x
        sta     ($08),y
        dey
        dex
        bpl     L993A
        lda     #$08
        ldy     #$00
        sta     ($08),y
        lda     $08
        clc
        adc     #$22
        sta     $08
        bcc     L9954
        inc     $09
L9954:  dec     L9C74
        beq     L995F
        ldx     L9C74
        jmp     L98F2

L995F:  ldx     #$07
L9961:  lda     drag_outline_buffer+2,x
        sta     L9C76,x
        dex
        bpl     L9961
        lda     #<drag_outline_buffer
        sta     $08
        lda     #>drag_outline_buffer
        sta     $08+1
L9972:  ldy     #$02
L9974:  lda     ($08),y
        cmp     L9C76
        iny
        lda     ($08),y
        sbc     L9C77
        bcs     L9990
        lda     ($08),y
        sta     L9C77
        dey
        lda     ($08),y
        sta     L9C76
        iny
        jmp     L99AA

L9990:  dey
        lda     ($08),y
        cmp     L9C7A
        iny
        lda     ($08),y
        sbc     L9C7B
        bcc     L99AA
        lda     ($08),y
        sta     L9C7B
        dey
        lda     ($08),y
        sta     L9C7A
        iny
L99AA:  iny
        lda     ($08),y
        cmp     L9C78
        iny
        lda     ($08),y
        sbc     L9C79
        bcs     L99C7
        lda     ($08),y
        sta     L9C79
        dey
        lda     ($08),y
        sta     L9C78
        iny
        jmp     L99E1

L99C7:  dey
        lda     ($08),y
        cmp     L9C7C
        iny
        lda     ($08),y
        sbc     L9C7D
        bcc     L99E1
        lda     ($08),y
        sta     L9C7D
        dey
        lda     ($08),y
        sta     L9C7C
        iny
L99E1:  iny
        cpy     #$22
        bne     L9974
        ldy     #$01
        lda     ($08),y
        beq     L99FC
        lda     $08
        clc
        adc     #$22
        sta     $08
        lda     $09
        adc     #$00
        sta     $09
        jmp     L9972

L99FC:  A2D_CALL A2D_SET_PATTERN, checkerboard_pattern2
        A2D_CALL A2D_SET_FILL_MODE, const2a
        A2D_CALL A2D_DRAW_POLYGONS, drag_outline_buffer
L9A0E:  A2D_CALL $2C, L933E
        lda     L933E
        cmp     #$04
        beq     L9A1E
        jmp     L9BA5

L9A1E:  ldx     #$03
L9A20:  lda     query_target_params2,x
        cmp     L9C92,x
        bne     L9A31
        dex
        bpl     L9A20
        jsr     L9E14
        jmp     L9A0E

L9A31:  ldx     #$03
L9A33:  lda     query_target_params2,x
        sta     L9C92,x
        dex
        bpl     L9A33
        lda     L9830
        beq     L9A84
        lda     L9831
        sta     query_target_params2::id
        DESKTOP_DIRECT_CALL $9, $933F
        lda     query_target_params2::element
        cmp     L9830
        beq     L9A84
        A2D_CALL A2D_SET_PATTERN, checkerboard_pattern2
        A2D_CALL A2D_SET_FILL_MODE, const2a
        A2D_CALL A2D_DRAW_POLYGONS, drag_outline_buffer
        DESKTOP_DIRECT_CALL $B, $9830
        A2D_CALL A2D_SET_PATTERN, checkerboard_pattern2
        A2D_CALL A2D_SET_FILL_MODE, const2a
        A2D_CALL A2D_DRAW_POLYGONS, drag_outline_buffer
        lda     #$00
        sta     L9830
L9A84:  lda     query_target_params2::queryx
        sec
        sbc     L9C8E
        sta     L9C96
        lda     query_target_params2::queryx+1
        sbc     L9C8F
        sta     L9C97
        lda     query_target_params2::queryy
        sec
        sbc     L9C90
        sta     L9C98
        lda     query_target_params2::queryy+1
        sbc     L9C91
        sta     L9C99
        jsr     L9C9E
        ldx     #$00
L9AAF:  lda     L9C7A,x
        clc
        adc     L9C96,x
        sta     L9C7A,x
        lda     L9C7B,x
        adc     L9C97,x
        sta     L9C7B,x
        lda     L9C76,x
        clc
        adc     L9C96,x
        sta     L9C76,x
        lda     L9C77,x
        adc     L9C97,x
        sta     L9C77,x
        inx
        inx
        cpx     #$04
        bne     L9AAF
        lda     #$00
        sta     L9C75
        lda     L9C77
        bmi     L9AF7
        lda     L9C7A
        cmp     #$30
        lda     L9C7B
        sbc     #$02
        bcs     L9AFE
        jsr     L9DFA
        jmp     L9B0E

L9AF7:  jsr     L9CAA
        bmi     L9B0E
        bpl     L9B03
L9AFE:  jsr     L9CD1
        bmi     L9B0E
L9B03:  jsr     L9DB8
        lda     L9C75
        ora     #$80
        sta     L9C75
L9B0E:  lda     L9C79
        bmi     L9B31
        lda     L9C78
        cmp     #$0D
        lda     L9C79
        sbc     #$00
        bcc     L9B31
        lda     L9C7C
        cmp     #$C0
        lda     L9C7D
        sbc     #$00
        bcs     L9B38
        jsr     L9E07
        jmp     L9B48

L9B31:  jsr     L9D31
        bmi     L9B48
        bpl     L9B3D
L9B38:  jsr     L9D58
        bmi     L9B48
L9B3D:  jsr     L9DD9
        lda     L9C75
        ora     #$40
        sta     L9C75
L9B48:  bit     L9C75
        bpl     L9B52
        .byte   $50
L9B4E:  .byte   $03
        jmp     L9A0E

L9B52:  A2D_CALL A2D_DRAW_POLYGONS, drag_outline_buffer
        lda     #<drag_outline_buffer
        sta     $08
        lda     #>drag_outline_buffer
        sta     $08+1
L9B60:  ldy     #$02
L9B62:  lda     ($08),y
        clc
        adc     L9C96
        sta     ($08),y
        iny
        lda     ($08),y
        adc     L9C97
        sta     ($08),y
        iny
        lda     ($08),y
        clc
        adc     L9C98
        sta     ($08),y
        iny
        lda     ($08),y
        adc     L9C99
        sta     ($08),y
        iny
        cpy     #$22
        bne     L9B62
        ldy     #$01
        lda     ($08),y
        beq     L9B9C
        lda     $08
        clc
        adc     #$22
        sta     $08
        bcc     L9B99
        inc     $09
L9B99:  jmp     L9B60

L9B9C:  A2D_CALL A2D_DRAW_POLYGONS, drag_outline_buffer
        jmp     L9A0E

L9BA5:  A2D_CALL A2D_DRAW_POLYGONS, drag_outline_buffer
        lda     L9830
        beq     L9BB9
        DESKTOP_DIRECT_CALL $B, $9830
        jmp     L9C63

L9BB9:  A2D_CALL A2D_QUERY_TARGET, query_target_params2
        lda     query_target_params2::id
        cmp     L9832
        beq     L9BE1
        bit     L9833
        bmi     L9BDC
        lda     query_target_params2::id
        bne     L9BD4
L9BD1:  jmp     L9852

L9BD4:  ora     #$80
        sta     L9830
        jmp     L9C63

L9BDC:  lda     L9832
        beq     L9BD1
L9BE1:  jsr     LA365
        A2D_CALL A2D_QUERY_SCREEN, query_screen_params
        A2D_CALL A2D_SET_STATE, query_screen_params
        ldx     L9016
L9BF3:  dex
        bmi     L9C18
        txa
        pha
        lda     L9017,x
        asl     a
        tax
        lda     L8F15,x
        sta     $06
        lda     L8F15+1,x
        sta     $07
        jsr     LA18A
        A2D_CALL A2D_SET_FILL_MODE, const0a
        jsr     LA39D
        pla
        tax
        jmp     L9BF3

L9C18:  jsr     LA382
        ldx     L9016
        dex
        txa
        pha
        lda     #<drag_outline_buffer
        sta     $08
        lda     #>drag_outline_buffer
        sta     $09
L9C29:  lda     L9017,x
        asl     a
        tax
        lda     L8F15,x
        sta     $06
        lda     L8F15+1,x
        sta     $07
        ldy     #$02
        lda     ($08),y
        iny
        sta     ($06),y
        lda     ($08),y
        iny
        sta     ($06),y
        lda     ($08),y
        iny
        sta     ($06),y
        lda     ($08),y
        iny
        sta     ($06),y
        pla
        tax
        dex
        bmi     L9C63
        txa
        pha
        lda     $08
        clc
        adc     #$22
        sta     $08
        bcc     L9C60
        inc     $09
L9C60:  jmp     L9C29

L9C63:  lda     #$00
L9C65:  tay
        jsr     LA382
        tya
        tax
        ldy     #$00
        lda     L9830
        sta     ($06),y
        txa
        rts

L9C74:  .byte   $00
L9C75:  .byte   $00
L9C76:  .byte   $00
L9C77:  .byte   $00
L9C78:  .byte   $00
L9C79:  .byte   $00
L9C7A:  .byte   $00
L9C7B:  .byte   $00
L9C7C:  .byte   $00
L9C7D:  .byte   $00
L9C7E:  .byte   $00
L9C7F:  .byte   $00
L9C80:  .byte   $0D
L9C81:  .byte   $00
L9C82:  .byte   $30
L9C83:  .byte   $02
L9C84:  .byte   $C0
L9C85:  .byte   $00
L9C86:  .byte   $00
L9C87:  .byte   $00
L9C88:  .byte   $00
L9C89:  .byte   $00
L9C8A:  .byte   $00
L9C8B:  .byte   $00
L9C8C:  .byte   $00
L9C8D:  .byte   $00
L9C8E:  .byte   $00
L9C8F:  .byte   $00
L9C90:  .byte   $00
L9C91:  .byte   $00
L9C92:  .byte   $00,$00,$00,$00
L9C96:  .byte   $00
L9C97:  .byte   $00
L9C98:  .byte   $00
L9C99:  .byte   $00,$00,$00,$00,$00
L9C9E:  ldx     #$07
L9CA0:  lda     L9C76,x
        sta     L9C86,x
        dex
        bpl     L9CA0
        rts

L9CAA:  lda     L9C76
        cmp     L9C7E
        bne     L9CBD
        lda     L9C77
        cmp     L9C7F
        bne     L9CBD
        lda     #$00
        rts

L9CBD:  lda     #$00
        sec
        sbc     L9C86
        sta     L9C96
        lda     #$00
        sbc     L9C87
        sta     L9C97
        jmp     L9CF5

L9CD1:  lda     L9C7A
        cmp     L9C82
        bne     L9CE4
        lda     L9C7B
        cmp     L9C83
        bne     L9CE4
        lda     #$00
        rts

L9CE4:  lda     #$30
        sec
        sbc     L9C8A
        sta     L9C96
        lda     #$02
        sbc     L9C8B
        sta     L9C97
L9CF5:  lda     L9C86
        clc
        adc     L9C96
        sta     L9C76
        lda     L9C87
        adc     L9C97
        sta     L9C77
        lda     L9C8A
        clc
        adc     L9C96
        sta     L9C7A
        lda     L9C8B
        adc     L9C97
        sta     L9C7B
        lda     L9C8E
        clc
        adc     L9C96
        sta     L9C8E
        lda     L9C8F
        adc     L9C97
        sta     L9C8F
        lda     #$FF
        rts

L9D31:  lda     L9C78
        cmp     L9C80
        bne     L9D44
        lda     L9C79
        cmp     L9C81
        bne     L9D44
        lda     #$00
        rts

L9D44:  lda     #$0D
        sec
        sbc     L9C88
        sta     L9C98
        lda     #$00
        sbc     L9C89
        sta     L9C99
        jmp     L9D7C

L9D58:  lda     L9C7C
        cmp     L9C84
        bne     L9D6B
        lda     L9C7D
        cmp     L9C85
        bne     L9D6B
        lda     #$00
        rts

L9D6B:  lda     #$BF
        sec
        sbc     L9C8C
        sta     L9C98
        lda     #$00
        sbc     L9C8D
        sta     L9C99
L9D7C:  lda     L9C88
        clc
        adc     L9C98
        sta     L9C78
        lda     L9C89
        adc     L9C99
        sta     L9C79
        lda     L9C8C
        clc
        adc     L9C98
        sta     L9C7C
        lda     L9C8D
        adc     L9C99
        sta     L9C7D
        lda     L9C90
        clc
        adc     L9C98
        sta     L9C90
        lda     L9C91
        adc     L9C99
        sta     L9C91
        lda     #$FF
        rts

L9DB8:  lda     L9C86
        sta     L9C76
        lda     L9C87
        sta     L9C77
        lda     L9C8A
        sta     L9C7A
        lda     L9C8B
        sta     L9C7B
        lda     #$00
        sta     L9C96
        sta     L9C97
        rts

L9DD9:  lda     L9C88
        sta     L9C78
        lda     L9C89
        sta     L9C79
        lda     L9C8C
        sta     L9C7C
        lda     L9C8D
        sta     L9C7D
        lda     #$00
        sta     L9C98
        sta     L9C99
        rts

L9DFA:  lda     query_target_params2::queryx+1
        sta     L9C8F
        lda     query_target_params2::queryx
        sta     L9C8E
        rts

L9E07:  lda     query_target_params2::queryy+1
        sta     L9C91
        lda     query_target_params2::queryy
        sta     L9C90
        rts

L9E14:  bit     L9833
        bpl     L9E1A
        rts

L9E1A:  jsr     LA365
L9E1D:  A2D_CALL A2D_QUERY_TARGET, query_target_params2
        lda     query_target_params2::element
        bne     L9E2B
        sta     query_target_params2::id
L9E2B:  DESKTOP_DIRECT_CALL $9, $933F
        lda     query_target_params2::element
        bne     L9E39
        jmp     L9E97

L9E39:  ldx     L9016
        dex
L9E3D:  cmp     L9017,x
        beq     L9E97
        dex
        bpl     L9E3D
        sta     L9EB3
        cmp     #$01
        beq     L9E6A
        asl     a
        tax
        lda     L8F15,x
        sta     $06
        lda     L8F15+1,x
        sta     $07
        ldy     #$02
        lda     ($06),y
        and     #$0F
        sta     L9831
        lda     ($06),y
        and     #$70
        bne     L9E97
        lda     L9EB3
L9E6A:  sta     L9830
        A2D_CALL A2D_SET_PATTERN, checkerboard_pattern2
        A2D_CALL A2D_SET_FILL_MODE, const2a
        A2D_CALL A2D_DRAW_POLYGONS, drag_outline_buffer
        DESKTOP_DIRECT_CALL $2, $9830
        A2D_CALL A2D_SET_PATTERN, checkerboard_pattern2
        A2D_CALL A2D_SET_FILL_MODE, const2a
        A2D_CALL A2D_DRAW_POLYGONS, drag_outline_buffer
L9E97:  A2D_CALL A2D_QUERY_SCREEN, query_screen_params
        A2D_CALL A2D_SET_STATE, query_screen_params
        A2D_CALL A2D_SET_PATTERN, checkerboard_pattern2
        A2D_CALL A2D_SET_FILL_MODE, const2a
        jsr     LA382
        rts

L9EB3:  .byte   0
L9EB4:  asl     a
        tay
        lda     L8F15+1,y
        tax
        lda     L8F15,y
        rts

;;; ==================================================

;;; DESKTOP $08 IMPL

L9EBE:
        jmp     L9EC3

        .byte   0
L9EC2:  .byte   0
L9EC3:  lda     L9015
        bne     L9ECB
        lda     #$01
        rts

L9ECB:  ldx     L9016
        ldy     #$00
        lda     ($06),y
        jsr     LA324
        ldx     L9016
        lda     #$00
        sta     L9016,x
        dec     L9016
        lda     L9016
        bne     L9EEA
        lda     #$00
        sta     L9015
L9EEA:  ldy     #$00
        lda     ($06),y
        sta     L9EC2
        DESKTOP_DIRECT_CALL $3, $9EC2
        lda     #0
        rts

        rts

;;; ==================================================

;;; DESKTOP $0D IMPL

L9EFB:
        jmp     L9F07

L9EFE:  .byte   0
L9EFF:  .byte   0
L9F00:  .byte   0
L9F01:  .byte   0
L9F02:  .byte   0
L9F03:  .byte   0
L9F04:  .byte   0
L9F05:  .byte   0
L9F06:  .byte   0
L9F07:  ldy     #$00
        lda     ($06),y
        sta     L9EFE
        ldy     #$08
L9F10:  lda     ($06),y
        sta     L9EFE,y
        dey
        bne     L9F10
        lda     L9EFE
        asl     a
        tax
        lda     L8F15,x
        sta     $06
        lda     L8F15+1,x
        sta     $07
        jsr     LA18A
        lda     L8E07
        cmp     L9F05
        lda     L8E08
        sbc     L9F06
        bpl     L9F8C
        lda     L8E1B
        cmp     L9F01
        lda     L8E1C
        sbc     L9F02
        bmi     L9F8C
        lda     L8E19
        cmp     L9F03
        lda     L8E1A
        sbc     L9F04
        bpl     L9F8C
        lda     L8E15
        cmp     L9EFF
        lda     L8E16
        sbc     L9F00
        bmi     L9F8C
        lda     L8E23
        cmp     L9F05
        lda     L8E24
        sbc     L9F06
        bmi     L9F8F
        lda     L8E21
        cmp     L9F03
        lda     L8E22
        sbc     L9F04
        bpl     L9F8C
        lda     L8E0D
        cmp     L9EFF
        lda     L8E0E
        sbc     L9F00
        bpl     L9F8F
L9F8C:  lda     #$00
        rts

L9F8F:  lda     #$01
        rts

L9F92:  .byte   0
L9F93:  .byte   0
L9F94:  .byte   0
        .byte   0
        .byte   0
        .byte   0
L9F98:  lda     #$00
        sta     L9F92
        beq     L9FA4
L9F9F:  lda     #$80
        sta     L9F92
L9FA4:  ldy     #$02
        lda     ($06),y
        and     #$0F
        bne     L9FB4
        lda     L9F92
        ora     #$40
        sta     L9F92
L9FB4:  ldy     #$03
L9FB6:  lda     ($06),y
        sta     L8E22,y
        iny
        cpy     #$09
        bne     L9FB6
        jsr     LA365
        lda     draw_bitmap_params2::addr
        sta     $08
        lda     draw_bitmap_params2::addr+1
        sta     $09
        ldy     #$0B
L9FCF:  lda     ($08),y
        sta     draw_bitmap_params2::addr,y
        dey
        bpl     L9FCF
        bit     L9F92
        bpl     L9FDF
        jsr     LA12C
L9FDF:  jsr     LA382
        ldy     #$09
L9FE4:  lda     ($06),y
        sta     fill_rect_params6::bottom,y
        iny
        cpy     #$1D
        bne     L9FE4
L9FEE:  lda     draw_text_params::length
        sta     measure_text_params::length
        A2D_CALL A2D_MEASURE_TEXT, measure_text_params
        lda     measure_text_params::width
        cmp     draw_bitmap_params2::width
        bcs     LA010
        inc     draw_text_params::length
        ldx     draw_text_params::length
        lda     #$20
        sta     text_buffer-1,x
        jmp     L9FEE

LA010:  lsr     a
        sta     set_pos_params2::xcoord+1
        lda     draw_bitmap_params2::width
        lsr     a
        sta     set_pos_params2
        lda     set_pos_params2::xcoord+1
        sec
        sbc     set_pos_params2::xcoord
        sta     set_pos_params2::xcoord
        lda     draw_bitmap_params2::left
        sec
        sbc     set_pos_params2::xcoord
        sta     set_pos_params2::xcoord
        lda     draw_bitmap_params2::left+1
        sbc     #$00
        sta     set_pos_params2::xcoord+1
        lda     draw_bitmap_params2::top
        clc
        adc     draw_bitmap_params2::height
        sta     set_pos_params2::ycoord
        lda     draw_bitmap_params2::top+1
        adc     #$00
        sta     set_pos_params2::ycoord+1
        lda     set_pos_params2::ycoord
        clc
        adc     #$01
        sta     set_pos_params2::ycoord
        lda     set_pos_params2::ycoord+1
        adc     #$00
        sta     set_pos_params2::ycoord+1
        lda     set_pos_params2::ycoord
        clc
        adc     a2d::glyph_height
        sta     set_pos_params2::ycoord
        lda     set_pos_params2::ycoord+1
        adc     #$00
        sta     set_pos_params2::ycoord+1
        ldx     #$03
LA06E:  lda     set_pos_params2,x
        sta     L9F94,x
        dex
        bpl     LA06E
        bit     L9F92
        bvc     LA097
        A2D_CALL A2D_QUERY_SCREEN, query_screen_params
        jsr     LA63F
LA085:  jsr     LA6A3
        jsr     LA097
        lda     L9F93
        bne     LA085
        A2D_CALL A2D_SET_BOX, query_screen_params
        rts

LA097:  A2D_CALL A2D_HIDE_CURSOR, DESKTOP_DIRECT ; These params should be ignored - bogus?
        A2D_CALL A2D_SET_FILL_MODE, const4a
        bit     L9F92
        bpl     LA0C2
        bit     L9F92
        bvc     LA0B6
        A2D_CALL A2D_SET_FILL_MODE, const0a
        jmp     LA0C2

LA0B6:  A2D_CALL A2D_DRAW_BITMAP, draw_bitmap_params
        A2D_CALL A2D_SET_FILL_MODE, const2a
LA0C2:  A2D_CALL A2D_DRAW_BITMAP, draw_bitmap_params2
        ldy     #$02
        lda     ($06),y
        and     #$80
        beq     LA0F2
        jsr     LA14D
        A2D_CALL A2D_SET_PATTERN, dark_pattern
        bit     L9F92
        bmi     LA0E6
        A2D_CALL A2D_SET_FILL_MODE, const3a
        beq     LA0EC
LA0E6:  A2D_CALL A2D_SET_FILL_MODE, const1a
LA0EC:  A2D_CALL A2D_FILL_RECT, fill_rect_params6
LA0F2:  ldx     #$03
LA0F4:  lda     L9F94,x
        sta     set_pos_params2,x
        dex
        bpl     LA0F4
        A2D_CALL A2D_SET_POS, set_pos_params2
        bit     L9F92
        bmi     LA10C
        lda     #$7F
        bne     LA10E
LA10C:  lda     #$00
LA10E:  sta     set_text_mask_params
        A2D_CALL A2D_SET_TEXT_MASK, set_text_mask_params
        lda     text_buffer+1
        and     #$DF
        sta     text_buffer+1
        A2D_CALL A2D_DRAW_TEXT, draw_text_params
        A2D_CALL A2D_SHOW_CURSOR
        rts

LA12C:  ldx     #$0F
LA12E:  lda     draw_bitmap_params2,x
        sta     draw_bitmap_params,x
        dex
        bpl     LA12E
        ldy     L8E43
LA13A:  lda     draw_bitmap_params::stride
        clc
        adc     draw_bitmap_params::addr
        sta     draw_bitmap_params::addr
        bcc     LA149
        inc     draw_bitmap_params::addr+1
LA149:  dey
        bpl     LA13A
        rts

LA14D:  ldx     #$00
LA14F:  lda     draw_bitmap_params2::left,x
        clc
        adc     draw_bitmap_params2::hoff,x
        sta     fill_rect_params6,x
        lda     draw_bitmap_params2::left+1,x
        adc     draw_bitmap_params2::hoff+1,x
        sta     fill_rect_params6::left+1,x
        lda     draw_bitmap_params2::left,x
        clc
        adc     draw_bitmap_params2::width,x
        sta     fill_rect_params6::right,x
        lda     draw_bitmap_params2::left+1,x
        adc     draw_bitmap_params2::width+1,x
        sta     fill_rect_params6::right+1,x
        inx
        inx
        cpx     #$04
        bne     LA14F
        lda     fill_rect_params6::bottom
        sec
        sbc     #$01
        sta     fill_rect_params6::bottom
        bcs     LA189
        dec     fill_rect_params6::bottom+1
LA189:  rts

LA18A:  jsr     LA365
        ldy     #$06
        ldx     #$03
LA191:  lda     ($06),y
        sta     L8E05,x
        dey
        dex
        bpl     LA191
        lda     L8E07
        sta     L8E0B
        lda     L8E08
        sta     L8E0C
        lda     L8E05
        sta     L8E21
        lda     L8E06
        sta     L8E22
        ldy     #$07
        lda     ($06),y
        sta     $08
        iny
        lda     ($06),y
        sta     $09
        ldy     #$08
        lda     ($08),y
        clc
        adc     L8E05
        sta     L8E09
        sta     L8E0D
        iny
        lda     ($08),y
        adc     L8E06
        sta     L8E0A
        sta     L8E0E
        ldy     #$0A
        lda     ($08),y
        clc
        adc     L8E07
        sta     L8E0F
        iny
        lda     ($08),y
        adc     L8E08
        sta     L8E10
        lda     L8E0F
        clc
        adc     #$02
        sta     L8E0F
        sta     L8E13
        sta     L8E1F
        sta     L8E23
        lda     L8E10
        adc     #$00
        sta     L8E10
        sta     L8E14
        sta     L8E20
        sta     L8E24
        lda     a2d::glyph_height
        clc
        adc     L8E0F
        sta     L8E17
        sta     L8E1B
        lda     L8E10
        adc     #$00
        sta     L8E18
        sta     L8E1C
        ldy     #$1C
        ldx     #$13
LA22A:  lda     ($06),y
        sta     text_buffer-1,x
        dey
        dex
        bpl     LA22A
LA233:  lda     draw_text_params::length
        sta     measure_text_params::length
        A2D_CALL A2D_MEASURE_TEXT, measure_text_params
        ldy     #$08
        lda     measure_text_params::width
        cmp     ($08),y
        bcs     LA256
        inc     draw_text_params::length
        ldx     draw_text_params::length
        lda     #$20
        sta     text_buffer-1,x
        jmp     LA233

LA256:  lsr     a
        sta     LA2A5
        lda     ($08),y
        lsr     a
        sta     LA2A4
        lda     LA2A5
        sec
        sbc     LA2A4
        sta     LA2A4
        lda     L8E05
        sec
        sbc     LA2A4
        sta     L8E1D
        sta     L8E19
        lda     L8E06
        sbc     #$00
        sta     L8E1E
        sta     L8E1A
        inc     measure_text_params::width
        inc     measure_text_params::width
        lda     L8E19
        clc
        adc     measure_text_params::width
        sta     L8E11
        sta     L8E15
        lda     L8E1A
        adc     #$00
        sta     L8E12
        sta     L8E16
        jsr     LA382
        rts

LA2A4:  .byte   0
LA2A5:  .byte   0

;;; ==================================================

DESKTOP_REDRAW_ICONS_IMPL:

LA2A6:
        jmp     LA2AE

LA2A9:  .byte   0
LA2AA:  jsr     LA382
        rts

LA2AE:  jsr     LA365
        ldx     L8E95
        dex
LA2B5:  bmi     LA2AA
        txa
        pha
        lda     L8E96,x
        asl     a
        tax
        lda     L8F15,x
        sta     $06
        lda     L8F15+1,x
        sta     $07
        ldy     #$02
        lda     ($06),y
        and     #$0F
        bne     LA2DD
        ldy     #$00
        lda     ($06),y
        sta     LA2A9
        DESKTOP_DIRECT_CALL $3, $A2A9
LA2DD:  pla
        tax
        dex
        jmp     LA2B5

LA2E3:  stx     LA322
        sta     LA323
        ldx     #$00
LA2EB:  lda     L8E96,x
        cmp     LA323
        beq     LA2FA
        inx
        cpx     L8E95
        bne     LA2EB
        rts

LA2FA:  lda     L8E97,x
        sta     L8E96,x
        inx
        cpx     L8E95
        bne     LA2FA
        ldx     L8E95
LA309:  cpx     LA322
        beq     LA318
        lda     L8E94,x
        sta     L8E95,x
        dex
        jmp     LA309

LA318:  ldx     LA322
        lda     LA323
        sta     L8E95,x
        rts

LA322:  .byte   0
LA323:  .byte   0
LA324:  stx     LA363
        sta     LA364
        ldx     #$00
LA32C:  lda     L9017,x
        cmp     LA364
        beq     LA33B
        inx
        cpx     L9016
        bne     LA32C
        rts

LA33B:  lda     L9018,x
        sta     L9017,x
        inx
        cpx     L9016
        bne     LA33B
        ldx     L9016
LA34A:  cpx     LA363
        beq     LA359
        lda     L9015,x
        sta     L9016,x
        dex
        jmp     LA34A

LA359:  ldx     LA363
        lda     LA364
        sta     L9016,x
        rts

LA363:  .byte   0
LA364:  .byte   0
LA365:  pla
        sta     LA380
        pla
        sta     LA381
        ldx     #$00
LA36F:  lda     $06,x
        pha
        inx
        cpx     #$04
        bne     LA36F
        lda     LA381
        pha
        lda     LA380
        pha
        rts

LA380:  .byte   0
LA381:  .byte   0
LA382:  pla
        sta     LA39B
        pla
        sta     LA39C
        ldx     #$03
LA38C:  pla
        sta     $06,x
        dex
        bpl     LA38C
        lda     LA39C
        pha
        lda     LA39B
        pha
        rts

LA39B:  .byte   0
LA39C:  .byte   0
LA39D:  A2D_CALL A2D_QUERY_SCREEN, query_screen_params
        A2D_CALL A2D_SET_STATE, query_screen_params
        jmp     LA3B9

LA3AC:  .byte   0
LA3AD:  .byte   0
LA3AE:  .byte   0
LA3AF:  .byte   0
LA3B0:  .byte   0
LA3B1:  .byte   0
LA3B2:  .byte   0
LA3B3:  .byte   0
        .byte   0
        .byte   0
        .byte   0
LA3B7:  .byte   0
LA3B8:  .byte   0
LA3B9:  ldy     #$00
        lda     ($06),y
        sta     LA3AC
        iny
        iny
        lda     ($06),y
        and     #$0F
        sta     LA3AD
        beq     LA3F4
        lda     #$80
        sta     LA3B7
        A2D_CALL A2D_SET_PATTERN, white_pattern2
        A2D_CALL $41, LA3B8
        lda     LA3B8
        sta     query_state_params
        A2D_CALL A2D_QUERY_STATE, query_state_params
        jsr     LA4CC
        jsr     LA938
        jsr     LA41C
        jmp     LA446

LA3F4:  A2D_CALL A2D_QUERY_SCREEN, query_screen_params
        jsr     LA63F
LA3FD:  jsr     LA6A3
        jsr     LA411
        lda     L9F93
        bne     LA3FD
        A2D_CALL A2D_SET_BOX, query_screen_params
        jmp     LA446

LA411:  lda     #$00
        sta     LA3B7
        A2D_CALL A2D_SET_PATTERN, checkerboard_pattern2
LA41C:  lda     L8E07
        sta     LA3B1
        lda     L8E08
        sta     LA3B2
        lda     L8E1D
        sta     LA3AF
        lda     L8E1E
        sta     LA3B0
        ldx     #$03
LA436:  lda     L8E15,x
        sta     LA3B3,x
        dex
        bpl     LA436
        A2D_CALL $15, L8E03
        rts

LA446:  jsr     LA365
        ldx     L8E95
        dex
LA44D:  cpx     #$FF
        bne     LA466
        bit     LA3B7
        bpl     LA462
        A2D_CALL A2D_QUERY_SCREEN, query_screen_params
        A2D_CALL A2D_SET_STATE, set_state_params
LA462:  jsr     LA382
        rts

LA466:  txa
        pha
        lda     L8E96,x
        cmp     LA3AC
        beq     LA4C5
        asl     a
        tax
        lda     L8F15,x
        sta     $08
        lda     L8F15+1,x
        sta     $09
        ldy     #$02
        lda     ($08),y
        and     #$07
        cmp     LA3AD
        bne     LA4C5
        lda     L9015
        beq     LA49D
        ldy     #$00
        lda     ($08),y
        ldx     #$00
LA492:  cmp     L9017,x
        beq     LA4C5
        inx
        cpx     L9016
        bne     LA492
LA49D:  ldy     #$00
        lda     ($08),y
        sta     LA3AE
        bit     LA3B7
        bpl     LA4AC
        jsr     LA4D3
LA4AC:  DESKTOP_DIRECT_CALL $D, $A3AE
        beq     LA4BA

        DESKTOP_DIRECT_CALL $3, $A3AE

LA4BA:  bit     LA3B7
        bpl     LA4C5
        lda     LA3AE
        jsr     LA4DC
LA4C5:  pla
        tax
        dex
        jmp     LA44D

LA4CB:  .byte   0

LA4CC:  lda     #$80
        sta     LA4CB
        bmi     LA4E2
LA4D3:  pha
        lda     #$40
        sta     LA4CB
        jmp     LA4E2

LA4DC:  pha
        lda     #$00
        sta     LA4CB
LA4E2:  ldy     #$00
LA4E4:  lda     set_state_params,y
        sta     LA567,y
        iny
        cpy     #$04
        bne     LA4E4
        ldy     #$08
LA4F1:  lda     set_state_params,y
        sta     LA567-4,y
        iny
        cpy     #$0C
        bne     LA4F1
        bit     LA4CB
        bmi     LA506
        bvc     LA56F
        jmp     LA5CB

LA506:  ldx     #$00
LA508:  lda     L8E05,x
        sec
        sbc     LA567
        sta     L8E05,x
        lda     L8E06,x
        sbc     LA568
        sta     L8E06,x
        lda     L8E07,x
        sec
        sbc     LA569
        sta     L8E07,x
        lda     L8E08,x
        sbc     LA56A
        sta     L8E08,x
        inx
        inx
        inx
        inx
        cpx     #$20
        bne     LA508
        ldx     #$00
LA538:  lda     L8E05,x
        clc
        adc     LA56B
        sta     L8E05,x
        lda     L8E06,x
        adc     LA56C
        sta     L8E06,x
        lda     L8E07,x
        clc
        adc     LA56D
        sta     L8E07,x
        lda     L8E08,x
        adc     LA56E
        sta     L8E08,x
        inx
        inx
        inx
        inx
        cpx     #$20
        bne     LA538
        rts

LA567:  .byte   0
LA568:  .byte   0
LA569:  .byte   0
LA56A:  .byte   0
LA56B:  .byte   0
LA56C:  .byte   0
LA56D:  .byte   0
LA56E:  .byte   0
LA56F:  pla
        tay
        jsr     LA365
        tya
        asl     a
        tax
        lda     L8F15,x
        sta     $06
        lda     L8F15+1,x
        sta     $07
        ldy     #$03
        lda     ($06),y
        clc
        adc     LA567
        sta     ($06),y
        iny
        lda     ($06),y
        adc     LA568
        sta     ($06),y
        iny
        lda     ($06),y
        clc
        adc     LA569
        sta     ($06),y
        iny
        lda     ($06),y
        adc     LA56A
        sta     ($06),y
        ldy     #$03
        lda     ($06),y
        sec
        sbc     LA56B
        sta     ($06),y
        iny
        lda     ($06),y
        sbc     LA56C
        sta     ($06),y
        iny
        lda     ($06),y
        sec
        sbc     LA56D
        sta     ($06),y
        iny
        lda     ($06),y
        sbc     LA56E
        sta     ($06),y
        jsr     LA382
        rts

LA5CB:  pla
        tay
        jsr     LA365
        tya
        asl     a
        tax
        lda     L8F15,x
        sta     $06
        lda     L8F15+1,x
        sta     $07
        ldy     #$03
        lda     ($06),y
        sec
        sbc     LA567
        sta     ($06),y
        iny
        lda     ($06),y
        sbc     LA568
        sta     ($06),y
        iny
        lda     ($06),y
        sec
        sbc     LA569
        sta     ($06),y
        iny
        lda     ($06),y
        sbc     LA56A
        sta     ($06),y
        ldy     #$03
        lda     ($06),y
        clc
        adc     LA56B
        sta     ($06),y
        iny
        lda     ($06),y
        adc     LA56C
        sta     ($06),y
        iny
        lda     ($06),y
        clc
        adc     LA56D
        sta     ($06),y
        iny
        lda     ($06),y
        adc     LA56E
        sta     ($06),y
        jsr     LA382
        rts

LA627:  .byte   $00
LA628:  .byte   $00
LA629:  .byte   $00
LA62A:  .byte   $00
LA62B:  .byte   $00
LA62C:  .byte   $00,$00,$00

.proc set_box_params2
left:   .word   0
top:    .word   0
addr:   .addr   A2D_SCREEN_ADDR
stride: .word   A2D_SCREEN_STRIDE
hoff:   .word   0
voff:   .word   0
width:  .word   0
height: .word   0
.endproc

LA63F:  jsr     LA18A
        lda     L8E07
        sta     LA629
        sta     set_box_params2::voff
        sta     set_box_params2::top
        lda     L8E08
        sta     LA62A
        sta     set_box_params2::voff+1
        sta     set_box_params2::top+1
        lda     L8E19
        sta     LA627
        sta     set_box_params2::hoff
        sta     set_box_params2::left
        lda     L8E1A
        sta     LA628
        sta     set_box_params2::hoff+1
        sta     set_box_params2::left+1
        ldx     #$03
LA674:  lda     L8E15,x
        sta     LA62B,x
        sta     set_box_params2::width,x
        dex
        bpl     LA674
        lda     LA62B
        cmp     #$2F
        lda     LA62C
        sbc     #$02
        bmi     LA69C
        lda     #$2E
        sta     LA62B
        sta     set_box_params2::width
        lda     #$02
        sta     LA62C
        sta     set_box_params2::width+1
LA69C:  A2D_CALL A2D_SET_BOX, set_box_params2
        rts

LA6A3:  lda     #$00
        jmp     LA6C7

.proc query_target_params
queryx: .word   0
queryy: .word   0
element:.byte   0
id:     .byte   0
.endproc

LA6AE:  .byte   $00
LA6AF:  .byte   $00
LA6B0:  .byte   $00
LA6B1:  .byte   $00
LA6B2:  .byte   $00
LA6B3:  .byte   $00
LA6B4:  .byte   $00
LA6B5:  .byte   $00
LA6B6:  .byte   $00
LA6B7:  .byte   $00
LA6B8:  .byte   $00
LA6B9:  .byte   $00
LA6BA:  .byte   $00
LA6BB:  .byte   $00
LA6BC:  .byte   $00
LA6BD:  .byte   $00
LA6BE:  .byte   $00
LA6BF:  .byte   $00
LA6C0:  .byte   $00
LA6C1:  .byte   $00
LA6C2:  .byte   $00
LA6C3:  .byte   $00
LA6C4:  .byte   $00
LA6C5:  .byte   $00
LA6C6:  .byte   $00
LA6C7:  lda     L9F93
        beq     LA6FA
        lda     set_box_params2::width
        clc
        adc     #$01
        sta     set_box_params2::hoff
        sta     set_box_params2::left
        lda     set_box_params2::width+1
        adc     #$00
        sta     set_box_params2::hoff+1
        sta     set_box_params2::left+1
        ldx     #$05
LA6E5:  lda     LA629,x
        sta     set_box_params2::voff,x
        dex
        bpl     LA6E5
        lda     set_box_params2::voff
        sta     set_box_params2::top
        lda     set_box_params2::voff+1
        sta     set_box_params2::top+1
LA6FA:  lda     set_box_params2::hoff
        sta     LA6B3
        sta     LA6BF
        lda     set_box_params2::hoff+1
        sta     LA6B4
        sta     LA6C0
        lda     set_box_params2::voff
        sta     LA6B5
        sta     LA6B9
        lda     set_box_params2::voff+1
        sta     LA6B6
        sta     LA6BA
        lda     set_box_params2::width
        sta     LA6B7
        sta     LA6BB
        lda     set_box_params2::width+1
        sta     LA6B8
        sta     LA6BC
        lda     set_box_params2::height
        sta     LA6BD
        sta     LA6C1
        lda     set_box_params2::height+1
        sta     LA6BE
        sta     LA6C2
        lda     #$00
        sta     LA6B0
LA747:  lda     LA6B0
        cmp     #$04
        bne     LA775
        lda     #$00
        sta     LA6B0
LA753:  A2D_CALL A2D_SET_BOX, set_box_params2
        lda     set_box_params2::width+1
        cmp     LA62C
        bne     LA76F
        lda     set_box_params2::width
        cmp     LA62B
        bcc     LA76F
        lda     #$00
        sta     L9F93
        rts

LA76F:  lda     #$01
        sta     L9F93
        rts

LA775:  lda     LA6B0
        asl     a
        asl     a
        tax
        ldy     #$00
LA77D:  lda     LA6B3,x
        sta     query_target_params,y
        iny
        inx
        cpy     #$04
        bne     LA77D
        inc     LA6B0
        A2D_CALL A2D_QUERY_TARGET, query_target_params
        lda     query_target_params::element
        beq     LA747
        lda     query_target_params::id
        sta     query_state_params
        A2D_CALL A2D_QUERY_STATE, query_state_params
        jsr     LA365
        A2D_CALL A2D_QUERY_WINDOW, query_target_params::id
        lda     LA6AE
        sta     $06
        lda     LA6AF
        sta     $07
        ldy     #$01
        lda     ($06),y
        and     #$01
        bne     LA7C3
        sta     LA6B2
        beq     LA7C8
LA7C3:  lda     #$80
        sta     LA6B2
LA7C8:  ldy     #$04
        lda     ($06),y
        and     #$80
        sta     LA6B1
        iny
        lda     ($06),y
        and     #$80
        lsr     a
        ora     LA6B1
        sta     LA6B1
        lda     set_state_params::left
        sec
        sbc     #2
        sta     set_state_params::left
        lda     set_state_params::left+1
        sbc     #0
        sta     set_state_params::left+1
        lda     set_state_params::hoff
        sec
        sbc     #2
        sta     set_state_params::hoff
        lda     set_state_params::hoff+1
        sbc     #0
        sta     set_state_params::hoff+1
        bit     LA6B2
        bmi     LA820
        lda     set_state_params::top
        sec
        sbc     #$0E
        sta     set_state_params::top
        bcs     LA812
        dec     set_state_params::top+1
LA812:  lda     set_state_params::voff
        sec
        sbc     #$0E
        sta     set_state_params::voff
        bcs     LA820
        dec     set_state_params::voff+1
LA820:  bit     LA6B1
        bpl     LA833
        lda     set_state_params::height
        clc
        adc     #$0C
        sta     set_state_params::height
        bcc     LA833
        inc     set_state_params::height+1
LA833:  bit     LA6B1
        bvc     LA846
        lda     set_state_params::width
        clc
        adc     #$14
        sta     set_state_params::width
        bcc     LA846
        inc     set_state_params::width+1
LA846:  jsr     LA382
        lda     set_state_params::width
        sec
        sbc     set_state_params::hoff
        sta     LA6C3
        lda     set_state_params::width+1
        sbc     set_state_params::hoff+1
        sta     LA6C4
        lda     set_state_params::height
        sec
        sbc     set_state_params::voff
        sta     LA6C5
        lda     set_state_params::height+1
        sbc     set_state_params::voff+1
        sta     LA6C6
        lda     LA6C3
        clc
        adc     set_state_params::left
        sta     LA6C3
        lda     set_state_params::left+1
        adc     LA6C4
        sta     LA6C4
        lda     LA6C5
        clc
        adc     set_state_params::top
        sta     LA6C5
        lda     LA6C6
        adc     set_state_params::top+1
        sta     LA6C6
        lda     set_box_params2::width
        cmp     LA6C3
        lda     set_box_params2::width+1
        sbc     LA6C4
        bmi     LA8B7
        lda     LA6C3
        clc
        adc     #$01
        sta     set_box_params2::width
        lda     LA6C4
        adc     #$00
        sta     set_box_params2::width+1
        jmp     LA8D4

LA8B7:  lda     set_state_params::left
        cmp     set_box_params2::hoff
        lda     set_state_params::left+1
        sbc     set_box_params2::hoff+1
        bmi     LA8D4
        lda     set_state_params::left
        sta     set_box_params2::width
        lda     set_state_params::left+1
        sta     set_box_params2::width+1
        jmp     LA6FA

LA8D4:  lda     set_state_params::top
        cmp     set_box_params2::voff
        lda     set_state_params::top+1
        sbc     set_box_params2::voff+1
        bmi     LA8F6
        lda     set_state_params::top
        sta     set_box_params2::height
        lda     set_state_params::top+1
        sta     set_box_params2::height+1
        lda     #$01
        sta     L9F93
        jmp     LA6FA

LA8F6:  lda     LA6C5
        cmp     set_box_params2::height
        lda     LA6C6
        sbc     set_box_params2::height+1
        bpl     LA923
        lda     LA6C5
        clc
        adc     #$02
        sta     set_box_params2::voff
        sta     set_box_params2::top
        lda     LA6C6
        adc     #$00
        sta     set_box_params2::voff+1
        sta     set_box_params2::top+1
        lda     #$01
        sta     L9F93
        jmp     LA6FA

LA923:  lda     set_box_params2::width
        sta     set_box_params2::hoff
        sta     set_box_params2::left
        lda     set_box_params2::width+1
        sta     set_box_params2::hoff+1
        sta     set_box_params2::left+1
        jmp     LA753

LA938:  lda     set_state_params::top
        clc
        adc     #$0F
        sta     set_state_params::top
        lda     set_state_params::top+1
        adc     #0
        sta     set_state_params::top+1
        lda     set_state_params::voff
        clc
        adc     #$0F
        sta     set_state_params::voff
        lda     set_state_params::voff+1
        adc     #0
        sta     set_state_params::voff+1
        A2D_CALL A2D_SET_STATE, set_state_params
        rts

        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00


        ;; 5.25" Floppy Disk
LA980:  .addr   LA9AC           ; address
        .word   4               ; stride
        .word   0               ; left
        .word   1               ; top
        .word   26              ; width
        .word   15              ; height

LA9AC:
        .byte   px(%1010101),px(%0101010),px(%1010101),px(%0101010)
        .byte   px(%1111111),px(%1111111),px(%1111111),px(%1111111)
        .byte   px(%1100000),px(%0000011),px(%1000000),px(%0000110)
        .byte   px(%1100000),px(%0000011),px(%1000000),px(%0000111)
        .byte   px(%1100000),px(%0000011),px(%1000000),px(%0000110)
        .byte   px(%1100000),px(%0000011),px(%1000000),px(%0000111)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000110)
        .byte   px(%1100000),px(%0000011),px(%1000000),px(%0000111)
        .byte   px(%1100000),px(%0000111),px(%1100000),px(%0000110)
        .byte   px(%1100000),px(%0000011),px(%1000000),px(%0000111)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000110)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000111)
        .byte   px(%1011000),px(%0000000),px(%0000000),px(%0000110)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000111)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000110)
        .byte   px(%1111111),px(%1111111),px(%1111111),px(%1111111)

        ;; RAM Disk
LA9CC:  .addr   LA9D8           ; address
        .word   6               ; stride
        .word   1               ; left (???)
        .word   0               ; top
        .word   38              ; width
        .word   11              ; height
LA9D8:
        .byte   px(%1111111),px(%1111111),px(%1111111),px(%1111111),px(%1111111),px(%1111101)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0001110)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0001101)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0001110)
        .byte   px(%1100000),px(%0001111),px(%1000111),px(%1100110),px(%0000110),px(%0001101)
        .byte   px(%1100000),px(%0001100),px(%1100110),px(%0110111),px(%1011110),px(%0001110)
        .byte   px(%1100000),px(%0001111),px(%1000111),px(%1110110),px(%1110110),px(%0001101)
        .byte   px(%1100000),px(%0001100),px(%1100110),px(%0110110),px(%0000110),px(%0001110)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0001101)
        .byte   px(%1111111),px(%1111111),px(%1111111),px(%1001100),px(%1100110),px(%0001110)
        .byte   px(%0101010),px(%1010101),px(%0101010),px(%1001100),px(%1100110),px(%0001101)
        .byte   px(%1010101),px(%0101010),px(%1010101),px(%1111111),px(%1111111),px(%1111110)

        ;; 3.5" Floppy Disk
LAA20:  .addr   LAA2C           ; address
        .word   3               ; stride
        .word   0               ; left
        .word   0               ; top
        .word   20              ; width
        .word   11              ; height
LAA2C:
        .byte   px(%1111111),px(%1111111),px(%1111110)
        .byte   px(%1100011),px(%0000000),px(%1100111)
        .byte   px(%1100011),px(%0000000),px(%1100111)
        .byte   px(%1100011),px(%1111111),px(%1100011)
        .byte   px(%1100000),px(%0000000),px(%0000011)
        .byte   px(%1100000),px(%0000000),px(%0000011)
        .byte   px(%1100111),px(%1111111),px(%1110011)
        .byte   px(%1100110),px(%0000000),px(%0110011)
        .byte   px(%1100110),px(%0000000),px(%0110011)
        .byte   px(%1100110),px(%0000000),px(%0110011)
        .byte   px(%1100110),px(%0000000),px(%0110011)
        .byte   px(%1111111),px(%1111111),px(%1111111)

        ;; Hard Disk
LAA50:  .addr   LAA5C           ; address
        .word   8               ; stride
        .word   1               ; left
        .word   0               ; top
        .word   51              ; width
        .word   9               ; height
LAA5C:
        .byte   px(%0111111),px(%1111111),px(%1111111),px(%1111111),px(%1111111),px(%1111111),px(%1111111),px(%1110101)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0011010)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0011101)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0011010)
        .byte   px(%1100011),px(%1000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0011101)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0011101)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0011010)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0011101)
        .byte   px(%0111111),px(%1111111),px(%1111111),px(%1111111),px(%1111111),px(%1111111),px(%1111111),px(%1110101)
        .byte   px(%1010111),px(%0101010),px(%1010101),px(%0101010),px(%1010101),px(%0101010),px(%1010111),px(%0101010)

        ;; Trash Can
LAAAC:  .addr   LAAB8           ; address
        .word   5               ; stride
        .word   7               ; left
        .word   1               ; top
        .word   27              ; width
        .word   18              ; height
LAAB8:
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%1010101),PX(%1111111),px(%1010101),px(%0000000)
        .byte   px(%0000000),px(%0101010),PX(%1100011),px(%0101010),px(%0000000)
        .byte   px(%0000000),PX(%1111111),PX(%1111111),PX(%1111111),px(%0000000)
        .byte   px(%0000000),px(%1100000),px(%0000000),PX(%0000011),px(%0000000)
        .byte   px(%0000000),PX(%1111111),PX(%1111111),PX(%1111111),px(%0000000)
        .byte   px(%0000000),px(%1100000),px(%0000000),px(%0000011),px(%0000000)
        .byte   px(%0000000),px(%1100001),px(%0000100),px(%0010011),px(%0000000)
        .byte   px(%0000000),px(%1100010),px(%0001000),px(%0100011),px(%0000000)
        .byte   px(%0000000),px(%1100010),px(%0001000),px(%0100011),px(%0000000)
        .byte   px(%0000000),px(%1100010),px(%0001000),px(%0100011),px(%0000000)
        .byte   px(%0000000),px(%1100010),px(%0001000),px(%0100011),px(%0000000)
        .byte   px(%0000000),px(%1100010),px(%0001000),px(%0100011),px(%0000000)
        .byte   px(%0000000),px(%1100010),px(%0001000),px(%0100011),px(%0000000)
        .byte   px(%0000000),px(%1100010),px(%0001000),px(%0100011),px(%0000000)
        .byte   px(%0000000),px(%1100010),px(%0001000),px(%0100011),px(%0000000)
        .byte   px(%0000000),px(%1100001),px(%0000100),px(%0010011),px(%0000000)
        .byte   px(%0000000),px(%1100000),px(%0000000),px(%0000011),px(%0000000)
        .byte   px(%0000000),PX(%1111111),PX(%1111111),PX(%1111111),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)

label_apple:
        PASCAL_STRING A2D_GLYPH_CAPPLE
label_file:
        PASCAL_STRING "File"
label_view:
        PASCAL_STRING "View"
label_special:
        PASCAL_STRING "Special"
label_startup:
        PASCAL_STRING "Startup"
label_selector:
        PASCAL_STRING "Selector"

label_new_folder:
        PASCAL_STRING "New Folder ..."
label_open:
        PASCAL_STRING "Open"
label_close:
        PASCAL_STRING "Close"
label_close_all:
        PASCAL_STRING "Close All"
label_select_all:
        PASCAL_STRING "Select All"
label_copy_file:
        PASCAL_STRING "Copy a File ..."
label_delete_file:
        PASCAL_STRING "Delete a File ..."
label_eject:
        PASCAL_STRING "Eject"
label_quit:
        PASCAL_STRING "Quit"

label_by_icon:
        PASCAL_STRING "By Icon"
label_by_name:
        PASCAL_STRING "By Name"
label_by_date:
        PASCAL_STRING "By Date"
label_by_size:
        PASCAL_STRING "By Size"
label_by_type:
        PASCAL_STRING "By Type"

label_check_drives:
        PASCAL_STRING "Check Drives"
label_format_disk:
        PASCAL_STRING "Format a Disk ..."
label_erase_disk:
        PASCAL_STRING "Erase a Disk ..."
label_disk_copy:
        PASCAL_STRING "Disk Copy ..."
label_lock:
        PASCAL_STRING "Lock ..."
label_unlock:
        PASCAL_STRING "Unlock ..."
label_get_info:
        PASCAL_STRING "Get Info ..."
label_get_size:
        PASCAL_STRING "Get Size ..."
label_rename_icon:
        PASCAL_STRING "Rename an Icon ..."

LAC44:  .word   6
        .addr   1, label_apple, apple_menu, 0,0,0
        .addr   2, label_file, file_menu, 0,0,0
        .addr   4, label_view, view_menu, 0,0,0
        .addr   5, label_special, special_menu, 0,0,0
        .addr   8, label_startup, startup_menu, 0,0,0
        .addr   3, label_selector, selector_menu, 0,0,0

.macro  DEFINE_MENU count
        .word   count, 0, 0
.endmacro
.macro  DEFINE_MENU_ITEM saddr, shortcut1, shortcut2
        .if .paramcount > 1
        .word   1
        .byte   shortcut1
        .byte   shortcut2
        .else
        .word   0
        .byte   0
        .byte   0
        .endif
        .addr   saddr
.endmacro
.macro  DEFINE_MENU_SEPARATOR
        .addr   $0040, $0013, $0000
.endmacro

file_menu:
        DEFINE_MENU 12
        DEFINE_MENU_ITEM label_new_folder, 'F', 'f'
        DEFINE_MENU_SEPARATOR
        DEFINE_MENU_ITEM label_open, 'O', 'o'
        DEFINE_MENU_ITEM label_close, 'C', 'c'
        DEFINE_MENU_ITEM label_close_all, 'B', 'b'
        DEFINE_MENU_ITEM label_select_all, 'A', 'a'
        DEFINE_MENU_SEPARATOR
        DEFINE_MENU_ITEM label_copy_file, 'Y', 'y'
        DEFINE_MENU_ITEM label_delete_file, 'D', 'd'
        DEFINE_MENU_SEPARATOR
        DEFINE_MENU_ITEM label_eject, 'E', 'e'
        DEFINE_MENU_ITEM label_quit, 'Q', 'q'

view_menu:
        DEFINE_MENU 5
        DEFINE_MENU_ITEM label_by_icon, 'J', 'j'
        DEFINE_MENU_ITEM label_by_name, 'N', 'n'
        DEFINE_MENU_ITEM label_by_date, 'T', 't'
        DEFINE_MENU_ITEM label_by_size, 'K', 'k'
        DEFINE_MENU_ITEM label_by_type, 'L', 'l'

special_menu:
        DEFINE_MENU 13
        DEFINE_MENU_ITEM label_check_drives
        DEFINE_MENU_SEPARATOR
        DEFINE_MENU_ITEM label_format_disk, 'S', 's'
        DEFINE_MENU_ITEM label_erase_disk, 'Z', 'z'
        DEFINE_MENU_ITEM label_disk_copy
        DEFINE_MENU_SEPARATOR
        DEFINE_MENU_ITEM label_lock
        DEFINE_MENU_ITEM label_unlock
        DEFINE_MENU_SEPARATOR
        DEFINE_MENU_ITEM label_get_info, 'I', 'i'
        DEFINE_MENU_ITEM label_get_size
        DEFINE_MENU_SEPARATOR
        DEFINE_MENU_ITEM label_rename_icon

        .addr   $0000,$0000

        .res    168, 0

        .byte   $04
        .byte   $00,$02,$00,$8C,$01,$62,$00,$05
        .byte   $00,$03,$00,$8B,$01,$61,$00,$28
        .byte   $00,$51,$00,$8C,$00,$5C,$00,$C1
        .byte   $00,$1E,$00,$25,$01,$29,$00,$04
        .byte   $01,$51,$00,$68,$01,$5C,$00,$C8
        .byte   $00,$51,$00,$F0,$00,$5C,$00,$04
        .byte   $01,$51,$00,$2C,$01,$5C,$00,$40
        .byte   $01,$51,$00,$68,$01,$5C,$00

        PASCAL_STRING {"OK            ",A2D_GLYPH_RETURN}

        .byte   $09
        .byte   $01,$5B,$00,$2D,$00,$5B,$00,$CD
        .byte   $00,$5B,$00,$09,$01,$5B,$00,$45
        .byte   $01,$5B,$00,$1C,$00,$70,$00,$1C
        .byte   $00,$87,$00,$00,$7F,$27,$00,$19
        .byte   $00,$68,$01,$50,$00,$28,$00,$3C
        .byte   $00,$68,$01,$50,$00,$41,$00,$2B
        .byte   $00,$41,$00,$33,$00,$41,$00,$23
        .byte   $00,$8A,$01,$2A,$00,$41,$00,$2B
        .byte   $00,$8A,$01,$32,$00

LAE96:  PASCAL_STRING "Cancel        Esc"
LAEA8:  PASCAL_STRING " Yes"
LAEAD:  PASCAL_STRING " No"
LAEB1:  PASCAL_STRING " All"
LAEB6:  PASCAL_STRING "Source filename:"
LAEC7:  PASCAL_STRING "Destination filename:"

        .byte   $04,$00,$02,$00
        .byte   $8C,$01,$6C,$00,$05,$00,$03,$00
        .byte   $8B,$01,$6B,$00

LAEED:  PASCAL_STRING "Apple II DeskTop"
LAEFE:  PASCAL_STRING "Copyright Apple Computer Inc., 1986"
LAF22:  PASCAL_STRING "Copyright Version Soft, 1985 - 1986"
LAF46:  PASCAL_STRING "All Rights Reserved"
LAF5A:  PASCAL_STRING "Authors: Stephane Cavril, Bernard Gallet, Henri Lamiraux"
LAF93:  PASCAL_STRING "Richard Danais and Luc Barthelet"
LAFB4:  PASCAL_STRING "With thanks to: A. Gerard, J. Gerber, P. Pahl, J. Bernard"
LAFEE:  PASCAL_STRING "November 26, 1986"
LB000:  PASCAL_STRING "Version 1.1"

LB00C:  PASCAL_STRING "Copy ..."
LB015:  PASCAL_STRING "Now Copying "
LB022:  PASCAL_STRING "from:"
LB028:  PASCAL_STRING "to :"
LB02D:  PASCAL_STRING "Files remaining to copy: "
LB047:  PASCAL_STRING "That file already exists. Do you want to write over it ?"
LB080:  PASCAL_STRING "This file is too large to copy, click OK to continue."

        .byte   $6E,$00,$23
        .byte   $00,$AA,$00,$3B,$00

LB0BE:  PASCAL_STRING "Delete ..."
LB0C9:  PASCAL_STRING "Click OK to delete:"
LB0DD:  PASCAL_STRING "Clicking OK will immediately empty the trash of:"
LB10E:  PASCAL_STRING "File:"
LB114:  PASCAL_STRING "Files remaining to be deleted:"
LB133:  PASCAL_STRING "This file is locked, do you want to delete it anyway ?"

        .byte   $91,$00,$3B,$00,$C8,$00,$3B,$00,$2C,$01,$3B,$00

LB176:  PASCAL_STRING "New Folder ..."
LB185:  PASCAL_STRING "in:"
LB189:  PASCAL_STRING "Enter the folder name:"
LB1A0:  PASCAL_STRING "Rename an Icon ..."
LB1B3:	PASCAL_STRING "Rename: "
LB1BC:  PASCAL_STRING "New name:"
LB1C6:  PASCAL_STRING "Get Info ..."
LB1D3:  PASCAL_STRING "Name"
LB1D8:  PASCAL_STRING "Locked"
LB1DF:  PASCAL_STRING "Size"
LB1E4:  PASCAL_STRING "Creation date"
LB1F2:  PASCAL_STRING "Last modification"
LB204:  PASCAL_STRING "Type"
LB209:  PASCAL_STRING "Write protected"
LB219:  PASCAL_STRING "Blocks free/size"
LB22A:  PASCAL_STRING ": "

        .byte   $A0,$00,$3B,$00
        .byte   $91,$00,$3B,$00,$C8,$00,$3B,$00
        .byte   $B9,$00,$3B,$00,$CD,$00,$3B,$00
        .byte   $C3,$00,$3B,$00

LB245:  PASCAL_STRING "Format a Disk ..."
LB257:  PASCAL_STRING "Select the location where the disk is to be formatted"
LB28D:  PASCAL_STRING "Enter the name of the new volume:"
LB2AF:  PASCAL_STRING "Do you want to format "
LB2C6:  PASCAL_STRING "Formatting the disk...."
LB2DE:  PASCAL_STRING "Formatting error. Check drive, then click OK to try again."
LB319:  PASCAL_STRING "Erase a Disk ..."
LB32A:  PASCAL_STRING "Select the location where the disk is to be erased"
LB35D:  PASCAL_STRING "Do you want to erase "
LB373:  PASCAL_STRING "Erasing the disk...."
LB388:  PASCAL_STRING "Erasing error. Check drive, then click OK to try again."
LB3C0:  PASCAL_STRING "Unlock ..."
LB3CB:  PASCAL_STRING "Click OK to unlock "
LB3DF:  PASCAL_STRING "Files remaining to be unlocked: "
LB400:  PASCAL_STRING "Lock ..."
LB409:  PASCAL_STRING "Click OK to lock "
LB41B:  PASCAL_STRING "Files remaining to be locked: "
LB43A:  PASCAL_STRING "Get Size ..."
LB447:  PASCAL_STRING "Number of files"
LB457:  PASCAL_STRING "Blocks used on disk"

        .byte   $6E,$00,$23,$00,$6E,$00,$2B,$00

LB473:  PASCAL_STRING "DownLoad ..."
LB480:  PASCAL_STRING "The RAMCard is full. The copy was not completed."
LB4B1:  PASCAL_STRING " "
LB4B3:  PASCAL_STRING "Warning !"
LB4BD:  PASCAL_STRING "Please insert the system disk."
LB4DC:  PASCAL_STRING "The Selector list is full. You must delete an entry"
LB50C:  PASCAL_STRING "before you can add new entries."
LB530:  PASCAL_STRING "A window must be closed before opening this new catalog."

LB569:  PASCAL_STRING "There are too many windows open on the desktop !"
LB59A:  PASCAL_STRING "Do you want to save the new Selector list"
LB5C4:  PASCAL_STRING "on the system disk ?"


        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00

LB600:  jmp     show_alert_dialog

alert_bitmap:
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),px(%0000000),PX(%1111111),PX(%1111111),px(%0000000),px(%0000000)
        .byte   px(%0111100),px(%1111100),px(%0000001),px(%1110000),PX(%0000111),px(%0000000),px(%0000000)
        .byte   px(%0111100),px(%1111100),px(%0000011),px(%1100000),px(%0000011),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0000111),PX(%1100111),px(%1111001),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0001111),PX(%1100111),px(%1111001),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0011111),PX(%1111111),px(%1111001),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0011111),PX(%1111111),px(%1110011),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0011111),PX(%1111111),PX(%1100111),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0011111),PX(%1111111),PX(%1001111),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0011111),PX(%1111111),PX(%0011111),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0011111),px(%1111110),PX(%0111111),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0011111),px(%1111100),PX(%1111111),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0011111),px(%1111100),PX(%1111111),px(%0000000),px(%0000000)
        .byte   px(%0111110),px(%0000000),PX(%0111111),PX(%1111111),PX(%1111111),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1100000),PX(%1111111),px(%1111100),PX(%1111111),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1100001),PX(%1111111),PX(%1111111),PX(%1111111),px(%0000000),px(%0000000)
        .byte   px(%0111000),px(%0000011),PX(%1111111),PX(%1111111),px(%1111110),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1100000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1100000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)

.proc alert_bitmap_params
        .word   $14             ; left
        .word   $8              ; top
        .addr   alert_bitmap    ; addr
        .word   7               ; stride
        .word   0               ; left
        .word   0               ; top
        .word   $24             ; width
        .word   $17             ; height
.endproc

alert_rect:
        .word   $41, $57, $1E5, $8E
alert_inner_frame_rect1:
        .word   $4, $2, $1A0, $35
alert_inner_frame_rect2:
        .word   $5, $3, $19F, $34

LB6D3:  .byte   $41
LB6D4:  .byte   $00
LB6D5:  .byte   $57
LB6D6:  .byte   $00,$00,$20,$80,$00,$00,$00,$00
        .byte   $00
LB6DF:  .byte   $A4
LB6E0:  .byte   $01
LB6E1:  .byte   $37,$00

ok_label:
        PASCAL_STRING {"OK            ",A2D_GLYPH_RETURN}

try_again_rect:
        .word   $14,$25,$78,$30
try_again_pos:
        .word   $0019,$002F

cancel_rect:
        .word   $12C,$25,$190,$30
cancel_pos:  .word   $0131,$002F
        .word   $00BE,$0010
LB70F:  .word   $004B,$001D

alert_action:  .byte   $00
LB714:  .byte   $00
LB715:  .byte   $00

try_again_label:
        PASCAL_STRING "Try Again     A"
cancel_label:
        PASCAL_STRING "Cancel     Esc"

LB735:  PASCAL_STRING "System Error"
LB742:  PASCAL_STRING "I/O error"
LB74C:  PASCAL_STRING "No device connected"
LB760:  PASCAL_STRING "The disk is write protected."
LB77D:  PASCAL_STRING "The syntax of the pathname is invalid."
LB7A4:  PASCAL_STRING "Part of the pathname doesn't exist."
LB7C8:  PASCAL_STRING "The volume cannot be found."
LB7E4:  PASCAL_STRING "The file cannot be found."
LB7FE:  PASCAL_STRING "That name already exists. Please use another name."
LB831:  PASCAL_STRING "The disk is full."
LB843:  PASCAL_STRING "The volume directory cannot hold more than 51 files."
LB878:  PASCAL_STRING "The file is locked."
LB88C:  PASCAL_STRING "This is not a ProDOS disk."
LB8A7:  PASCAL_STRING "There is another volume with that name on the desktop."
LB8DE:  PASCAL_STRING "There are 2 volumes with the same name."
LB906:  PASCAL_STRING "This file cannot be run."
LB91F:  PASCAL_STRING "That name is too long."
LB936:  PASCAL_STRING "Please insert source disk"
LB950:  PASCAL_STRING "Please insert destination disk"
LB96F:  PASCAL_STRING "BASIC.SYSTEM not found"

        ;; number of alert messages
alert_count:
        .byte   $14

        ;; message number-to-index table
        ;; (look up by scan to determine index)
alert_table:
        .byte   $00,$27,$28,$2B,$40,$44,$45,$46
        .byte   $47,$48,$49,$4E,$52,$57,$F9,$FA
        .byte   $FB,$FC,$FD,$FE

        ;; alert index to string address
prompt_table:
        .addr   LB735,LB742,LB74C,LB760,LB77D,LB7A4,LB7C8,LB7E4
        .addr   LB7FE,LB831,LB843,LB878,LB88C,LB8A7,LB8DE,LB906
        .addr   LB91F,LB936,LB950,LB96F

        ;; alert index to action (0 = Cancel, $80 = Try Again)
alert_action_table:
        .byte   $00,$00,$00,$80,$00,$80,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$80,$80,$00

        ;; Show alert; prompt number in A
.proc show_alert_dialog
        pha
        txa
        pha
        A2D_RELAY2_CALL A2D_HIDE_CURSOR
        A2D_RELAY2_CALL A2D_SET_CURSOR, pointer_cursor
        A2D_RELAY2_CALL A2D_SHOW_CURSOR
        sta     ALTZPOFF
        sta     ROMIN2
        jsr     $FBDD
        sta     ALTZPON
        lda     LCBANK1
        lda     LCBANK1
        ldx     #$03
        lda     #$00
LBA0B:  sta     $D239,x
        sta     $D241,x
        dex
        bpl     LBA0B
        lda     #$26
        sta     $D245
        lda     #$02
        sta     $D246
        lda     #$B9
        sta     $D247
        lda     #$00
        sta     $D248
        A2D_RELAY2_CALL A2D_SET_STATE, $D239
        lda     LB6D3
        ldx     LB6D4
        jsr     LBF8B
        sty     LBFCA
        sta     LBFCD
        lda     LB6D3
        clc
        adc     LB6DF
        pha
        lda     LB6D4
        adc     LB6E0
        tax
        pla
        jsr     LBF8B
        sty     LBFCC
        sta     LBFCE
        lda     LB6D5
        sta     LBFC9
        clc
        adc     LB6E1
        sta     LBFCB
        A2D_RELAY2_CALL A2D_HIDE_CURSOR
        jsr     LBE08
        A2D_RELAY2_CALL A2D_SHOW_CURSOR
        A2D_RELAY2_CALL A2D_SET_FILL_MODE, const0
        A2D_RELAY2_CALL A2D_FILL_RECT, alert_rect ; alert background
        A2D_RELAY2_CALL A2D_SET_FILL_MODE, const2 ; ensures corners are inverted
        A2D_RELAY2_CALL A2D_DRAW_RECT, alert_rect ; alert outline
        A2D_RELAY2_CALL A2D_SET_BOX, $B6D3
        A2D_RELAY2_CALL A2D_DRAW_RECT, alert_inner_frame_rect1 ; inner 2x border
        A2D_RELAY2_CALL A2D_DRAW_RECT, alert_inner_frame_rect2
        A2D_RELAY2_CALL A2D_SET_FILL_MODE, const0 ; restores normal mode
        A2D_RELAY2_CALL A2D_HIDE_CURSOR
        A2D_RELAY2_CALL A2D_DRAW_BITMAP, alert_bitmap_params
        A2D_RELAY2_CALL A2D_SHOW_CURSOR
        pla
        tax
        pla
        ldy     alert_count
        dey
LBAE5:  cmp     alert_table,y
        beq     LBAEF
        dey
        bpl     LBAE5
        ldy     #$00
LBAEF:  tya
        asl     a
        tay
        lda     prompt_table,y
        sta     LB714
        lda     prompt_table+1,y
        sta     LB715
        cpx     #$00
        beq     LBB0B
        txa
        and     #$FE
        sta     alert_action
        jmp     LBB14

.macro DRAW_PASCAL_STRING addr
        lda     #<(addr)
        ldx     #>(addr)
        jsr     draw_pascal_string
.endmacro

LBB0B:  tya
        lsr     a
        tay
        lda     alert_action_table,y
        sta     alert_action
LBB14:  A2D_RELAY2_CALL A2D_SET_FILL_MODE, const2
        bit     alert_action
        bpl     LBB5C
        A2D_RELAY2_CALL A2D_DRAW_RECT, cancel_rect
        A2D_RELAY2_CALL A2D_SET_POS, cancel_pos
        DRAW_PASCAL_STRING cancel_label
        bit     alert_action
        bvs     LBB5C
        A2D_RELAY2_CALL A2D_DRAW_RECT, try_again_rect
        A2D_RELAY2_CALL A2D_SET_POS, try_again_pos
        DRAW_PASCAL_STRING try_again_label
        jmp     LBB75
.endproc

LBB5C:  A2D_RELAY2_CALL A2D_DRAW_RECT, try_again_rect
        A2D_RELAY2_CALL A2D_SET_POS, try_again_pos
        DRAW_PASCAL_STRING ok_label
LBB75:  A2D_RELAY2_CALL A2D_SET_POS, $B70F
        lda     LB714
        ldx     LB715
        jsr     draw_pascal_string
LBB87:  A2D_RELAY2_CALL A2D_GET_INPUT, alert_input_params
        lda     alert_input_params
        cmp     #$01
        bne     LBB9A
        jmp     LBC0C

LBB9A:  cmp     #$03
        bne     LBB87
        lda     alert_input_params+1
        and     #$7F
        bit     alert_action
        bpl     LBBEE
        cmp     #$1B
        bne     LBBC3
        A2D_RELAY2_CALL A2D_SET_FILL_MODE, const2
        A2D_RELAY2_CALL A2D_FILL_RECT, cancel_rect
        lda     #$01
        jmp     LBC55

LBBC3:  bit     alert_action
        bvs     LBBEE
        cmp     #$61
        bne     LBBE3
LBBCC:  A2D_RELAY2_CALL A2D_SET_FILL_MODE, const2
        A2D_RELAY2_CALL A2D_FILL_RECT, try_again_rect
        lda     #$00
        jmp     LBC55

LBBE3:  cmp     #$41
        beq     LBBCC
        cmp     #$0D
        beq     LBBCC
        jmp     LBB87

LBBEE:  cmp     #$0D
        bne     LBC09
        A2D_RELAY2_CALL A2D_SET_FILL_MODE, const2
        A2D_RELAY2_CALL A2D_FILL_RECT, try_again_rect
        lda     #$02
        jmp     LBC55

LBC09:  jmp     LBB87

LBC0C:  jsr     LBDE1
        A2D_RELAY2_CALL A2D_SET_POS, alert_input_params+1
        bit     alert_action
        bpl     LBC42
        A2D_RELAY2_CALL A2D_TEST_BOX, cancel_rect
        cmp     #$80
        bne     LBC2D
        jmp     LBCE9

LBC2D:  bit     alert_action
        bvs     LBC42
        A2D_RELAY2_CALL A2D_TEST_BOX, try_again_rect
        cmp     #$80
        bne     LBC52
        jmp     LBC6D

LBC42:  A2D_RELAY2_CALL A2D_TEST_BOX, try_again_rect
        cmp     #$80
        bne     LBC52
        jmp     LBD65

LBC52:  jmp     LBB87

LBC55:  pha
        A2D_RELAY2_CALL A2D_HIDE_CURSOR
        jsr     LBE5D
        A2D_RELAY2_CALL A2D_SHOW_CURSOR
        pla
        rts

LBC6D:  A2D_RELAY2_CALL A2D_SET_FILL_MODE, const2
        A2D_RELAY2_CALL A2D_FILL_RECT, try_again_rect
        lda     #$00
        sta     LBCE8
LBC84:  A2D_RELAY2_CALL A2D_GET_INPUT, alert_input_params
        lda     alert_input_params
        cmp     #$02
        beq     LBCDB
        jsr     LBDE1
        A2D_RELAY2_CALL A2D_SET_POS, alert_input_params+1
        A2D_RELAY2_CALL A2D_TEST_BOX, try_again_rect
        cmp     #$80
        beq     LBCB5
        lda     LBCE8
        beq     LBCBD
        jmp     LBC84

LBCB5:  lda     LBCE8
        bne     LBCBD
        jmp     LBC84

LBCBD:  A2D_RELAY2_CALL A2D_SET_FILL_MODE, const2
        A2D_RELAY2_CALL A2D_FILL_RECT, try_again_rect
        lda     LBCE8
        clc
        adc     #$80
        sta     LBCE8
        jmp     LBC84

LBCDB:  lda     LBCE8
        beq     LBCE3
        jmp     LBB87

LBCE3:  lda     #$00
        jmp     LBC55

LBCE8:  .byte   0
LBCE9:  A2D_RELAY2_CALL A2D_SET_FILL_MODE, const2
        A2D_RELAY2_CALL A2D_FILL_RECT, cancel_rect
        lda     #$00
        sta     LBD64
LBD00:  A2D_RELAY2_CALL A2D_GET_INPUT, alert_input_params
        lda     alert_input_params
        cmp     #$02
        beq     LBD57
        jsr     LBDE1
        A2D_RELAY2_CALL A2D_SET_POS, alert_input_params+1
        A2D_RELAY2_CALL A2D_TEST_BOX, cancel_rect
        cmp     #$80
        beq     LBD31
        lda     LBD64
        beq     LBD39
        jmp     LBD00

LBD31:  lda     LBD64
        bne     LBD39
        jmp     LBD00

LBD39:  A2D_RELAY2_CALL A2D_SET_FILL_MODE, const2
        A2D_RELAY2_CALL A2D_FILL_RECT, cancel_rect
        lda     LBD64
        clc
        adc     #$80
        sta     LBD64
        jmp     LBD00

LBD57:  lda     LBD64
        beq     LBD5F
        jmp     LBB87

LBD5F:  lda     #$01
        jmp     LBC55

LBD64:  .byte   0
LBD65:  lda     #$00
        sta     LBDE0
        A2D_RELAY2_CALL A2D_SET_FILL_MODE, const2
        A2D_RELAY2_CALL A2D_FILL_RECT, try_again_rect
LBD7C:  A2D_RELAY2_CALL A2D_GET_INPUT, alert_input_params
        lda     alert_input_params
        cmp     #$02
        beq     LBDD3
        jsr     LBDE1
        A2D_RELAY2_CALL A2D_SET_POS, alert_input_params+1
        A2D_RELAY2_CALL A2D_TEST_BOX, try_again_rect
        cmp     #$80
        beq     LBDAD
        lda     LBDE0
        beq     LBDB5
        jmp     LBD7C

LBDAD:  lda     LBDE0
        bne     LBDB5
        jmp     LBD7C

LBDB5:  A2D_RELAY2_CALL A2D_SET_FILL_MODE, const2
        A2D_RELAY2_CALL A2D_FILL_RECT, try_again_rect
        lda     LBDE0
        clc
        adc     #$80
        sta     LBDE0
        jmp     LBD7C

LBDD3:  lda     LBDE0
        beq     LBDDB
        jmp     LBB87

LBDDB:  lda     #$02
        jmp     LBC55

LBDE0:  .byte   0
LBDE1:  lda     alert_input_params+1
        sec
        sbc     LB6D3
        sta     alert_input_params+1
        lda     alert_input_params+2
        sbc     LB6D4
        sta     alert_input_params+2
        lda     $D20B
        sec
        sbc     LB6D5
        sta     $D20B
        lda     $D20C
        sbc     LB6D6
        sta     $D20C
        rts

LBE08:  lda     #$00
        sta     LBE37
        lda     #$08
        sta     LBE38
        lda     LBFC9
        jsr     LBF10
        lda     LBFCB
        sec
        sbc     LBFC9
        tax
        inx
LBE21:  lda     LBFCA
        sta     LBE5C
LBE27:  lda     LBE5C
        lsr     a
        tay
        sta     LOWSCR
        bcs     LBE34
        sta     HISCR
LBE34:  lda     ($06),y
LBE37           := * + 1
LBE38           := * + 2
        sta     $1234
        inc     LBE37
        bne     LBE41
        inc     LBE38
LBE41:  lda     LBE5C
        cmp     LBFCC
        bcs     LBE4E
        inc     LBE5C
        bne     LBE27
LBE4E:  jsr     LBF52
        dex
        bne     LBE21
        lda     LBE37
        ldx     LBE38
        rts

        .byte   0
LBE5C:  .byte   0
LBE5D:  lda     #$00
        sta     LBEBC
        lda     #$08
        sta     LBEBD
        ldx     LBFCD
        ldy     LBFCE
        lda     #$FF
        cpx     #$00
        beq     LBE78
LBE73:  clc
        rol     a
        dex
        bne     LBE73
LBE78:  sta     LBF0C
        eor     #$FF
        sta     LBF0D
        lda     #$01
        cpy     #$00
        beq     LBE8B
LBE86:  sec
        rol     a
        dey
        bne     LBE86
LBE8B:  sta     LBF0E
        eor     #$FF
        sta     LBF0F
        lda     LBFC9
        jsr     LBF10
        lda     LBFCB
        sec
        sbc     LBFC9
        tax
        inx
        lda     LBFCA
        sta     LBF0B
LBEA8:  lda     LBFCA
        sta     LBF0B
LBEAE:  lda     LBF0B
        lsr     a
        tay
        sta     LOWSCR
        bcs     LBEBB
        sta     HISCR
LBEBB:  .byte   $AD
LBEBC:  .byte   0
LBEBD:  php
        pha
        lda     LBF0B
        cmp     LBFCA
        beq     LBEDD
        cmp     LBFCC
        bne     LBEEB
        lda     ($06),y
        and     LBF0F
        sta     ($06),y
        pla
        and     LBF0E
        ora     ($06),y
        pha
        jmp     LBEEB

LBEDD:  lda     ($06),y
        and     LBF0D
        sta     ($06),y
        pla
        and     LBF0C
        ora     ($06),y
        pha
LBEEB:  pla
        sta     ($06),y
        inc     LBEBC
        bne     LBEF6
        inc     LBEBD
LBEF6:  lda     LBF0B
        cmp     LBFCC
        bcs     LBF03
        inc     LBF0B
        bne     LBEAE
LBF03:  jsr     LBF52
        dex
        bne     LBEA8
        rts

        .byte   $00
LBF0B:  .byte   $00
LBF0C:  .byte   $00
LBF0D:  .byte   $00
LBF0E:  .byte   $00
LBF0F:  .byte   $00

LBF10:  sta     LBFCF
        and     #$07
        sta     LBFB0
        lda     LBFCF
        and     #$38
        sta     LBFAF
        lda     LBFCF
        and     #$C0
        sta     LBFAE
        jsr     LBF2C
        rts

LBF2C:  lda     LBFAE
        lsr     a
        lsr     a
        ora     LBFAE
        pha
        lda     LBFAF
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     LBF51
        pla
        ror     a
        sta     $06
        lda     LBFB0
        asl     a
        asl     a
        ora     LBF51
        ora     #$20
        sta     $07
        clc
        rts

LBF51:  .byte   0
LBF52:  lda     LBFB0
        cmp     #$07
        beq     LBF5F
        inc     LBFB0
        jmp     LBF2C

LBF5F:  lda     #$00
        sta     LBFB0
        lda     LBFAF
        cmp     #$38
        beq     LBF74
        clc
        adc     #$08
        sta     LBFAF
        jmp     LBF2C

LBF74:  lda     #$00
        sta     LBFAF
        lda     LBFAE
        clc
        adc     #$40
        sta     LBFAE
        cmp     #$C0
        beq     LBF89
        jmp     LBF2C

LBF89:  sec
        rts

LBF8B:  ldy     #$00
        cpx     #$02
        bne     LBF96
        ldy     #$49
        clc
        adc     #$01
LBF96:  cpx     #$01
        bne     LBFA4
        ldy     #$24
        clc
        adc     #$04
        bcc     LBFA4
        iny
        sbc     #$07
LBFA4:  cmp     #$07
        bcc     LBFAD
        sbc     #$07
        iny
        bne     LBFA4
LBFAD:  rts

LBFAE:  .byte   $00
LBFAF:  .byte   $00
LBFB0:  .byte   $00,$FF,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00
LBFC9:  .byte   $00
LBFCA:  .byte   $00
LBFCB:  .byte   $00
LBFCC:  .byte   $00
LBFCD:  .byte   $00
LBFCE:  .byte   $00
LBFCF:  .byte   $00

        ;; Draw pascal string; address in (X,A)
.proc draw_pascal_string
        ptr := $06

        sta     ptr
        stx     ptr+1
        ldy     #$00
        lda     (ptr),y         ; Check length
        beq     end
        sta     ptr+2
        inc     ptr
        bne     call
        inc     ptr+1
call:   A2D_RELAY2_CALL A2D_DRAW_TEXT, ptr
end:    rts
.endproc

        ;; A2D call in Y, params addr (X,A)
.proc A2D_RELAY2
        sty     call
        sta     addr
        stx     addr+1
        jsr     A2D
call:   .byte   0
addr:   .addr   0
        rts
.endproc

        .byte   0
        .byte   0
        .byte   0
        .byte   0

        .org $D000

L87F6           := $87F6
L8813           := $8813

        ;; A2D call from main>aux, call in Y, params at (X,A)
.proc A2D_RELAY
        sty     addr-1
        sta     addr
        stx     addr+1
        sta     RAMRDON
        sta     RAMWRTON
        A2D_CALL 0, 0, addr
        sta     RAMRDOFF
        sta     RAMWRTOFF
        rts
.endproc


        ;; SET_POS with params at (X,A) followed by DRAW_TEXT call
.proc LD01C
        sta     addr
        stx     addr+1
        sta     RAMRDON
        sta     RAMWRTON
        A2D_CALL A2D_SET_POS, 0, addr
        A2D_RELAY_CALL A2D_DRAW_TEXT, text_buffer2
        tay
        sta     RAMRDOFF
        sta     RAMWRTOFF
        tya
        rts
.endproc

        ;; DESKTOP call from aux>main, call in Y params at (X,A)
.proc LD040
        sty     addr-1
        sta     addr
        stx     addr+1
        sta     RAMRDON
        sta     RAMWRTON
        DESKTOP_CALL 0, 0, addr
        tay
        sta     RAMRDOFF
        sta     RAMWRTOFF
        tya
        rts
.endproc

        ;; Find first 0 in AUX $1F80 ... $1F7F; if present,
        ;; mark it 1 and return index+1 in A
.proc LD05E
        sta     RAMRDON
        sta     RAMWRTON
        ldx     #0
loop:   lda     $1F80,x
        beq     :+
        inx
        cpx     #$7F
        bne     loop
        rts

:       inx
        txa
        dex
        tay
        lda     #1
        sta     $1F80,x
        sta     RAMRDOFF
        sta     RAMWRTOFF
        tya
        rts
.endproc

        tay
        sta     RAMRDON
        sta     RAMWRTON
        dey
        lda     #0
        sta     $1F80,y
        sta     RAMRDOFF
        sta     RAMWRTOFF
        rts

        lda     #$80
        bne     LD09C
        lda     #$00
LD09C:  sta     LD106
        jsr     L87F6
        lda     LDE9F
        asl     a
        tax
        lda     LEC01,x
        sta     $06
        lda     LEC01+1,x
        sta     $07
        sta     RAMRDON
        sta     RAMWRTON
        bit     LD106
        bpl     LD0C6
        lda     LDEA0
        ldy     #$00
        sta     ($06),y
        jmp     LD0CD

LD0C6:  ldy     #$00
        lda     ($06),y
        sta     LDEA0
LD0CD:  lda     LEC13,x
        sta     $06
        lda     LEC13+1,x
        sta     $07
        bit     LD106
        bmi     LD0EC
        ldy     #0
LD0DE:  cpy     LDEA0
        beq     LD0FC
        lda     ($06),y
        sta     LDEA0+1,y
        iny
        jmp     LD0DE

LD0EC:  ldy     #0
LD0EE:  cpy     LDEA0
        beq     LD0FC
        lda     LDEA0+1,y
        sta     ($06),y
        iny
        jmp     LD0EE

LD0FC:  sta     RAMRDOFF
        sta     RAMWRTOFF
        jsr     L8813
        rts

LD106:  .byte   0
        rts                     ; ???

        sta     RAMRDON
        sta     RAMWRTON
        A2D_CALL A2D_GET_STATE, $06
        lda     LEC25
        asl     a
        tax
        lda     LDFA1,x
        sta     $08
        lda     LDFA1+1,x
        sta     $09
        lda     $08
        clc
        adc     #$14
        sta     $08
        bcc     LD12E
        inc     $09
LD12E:  ldy     #$23
LD130:  lda     ($06),y
        sta     ($08),y
        dey
        bpl     LD130
        sta     RAMRDOFF
        sta     RAMWRTOFF
        rts

        ;; From MAIN, load AUX (X,A) into A
.proc LD13E
        stx     op+2
        sta     op+1
        sta     RAMRDON
        sta     RAMWRTON
op:     lda     $1234
        sta     RAMRDOFF
        sta     RAMWRTOFF
        rts
.endproc

.proc LD154
        ldx     #$00
        sta     RAMRDON
        sta     RAMWRTON
        jsr     LB600
        sta     RAMRDOFF
        sta     RAMWRTOFF
        rts
.endproc

        .res    154, 0

const0: .byte   0
const1: .byte   1
const2: .byte   2
const3: .byte   3
const4: .byte   4
const5: .byte   5
const6: .byte   6
const7: .byte   7

alert_input_params:
        .byte   $00,$00,$00,$00,$00,$00

        .byte   $00,$00,$00,$00,$00
        .addr   buffer
buffer: .byte   $00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$20,$80,$00,$00
        .byte   $00,$00,$00,$0A,$00,$0A,$00,$FF
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        .byte   $00,$00,$00,$00,$00,$01,$01,$00
        .byte   $00,$00,$88,$FF,$FF,$FF,$FF,$FF
        .byte   $FF,$FF,$FF,$FF,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$FF

LD293:
        .byte   px(%1010101)
        .byte   PX(%0101010)
        .byte   px(%1010101)
        .byte   PX(%0101010)
        .byte   px(%1010101)
        .byte   PX(%0101010)
        .byte   px(%1010101)
        .byte   PX(%0101010)

        .byte   $FF,$06,$EA
        .byte   $00,$00,$00,$00,$88,$00,$08,$00
        .byte   $13,$00,$00,$00,$00,$00,$00

;;; Cursors (bitmap - 2x12 bytes, mask - 2x12 bytes, hotspot - 2 bytes)

;;; Pointer

pointer_cursor:
        .byte   px(%0000000),px(%0000000)
        .byte   px(%0100000),px(%0000000)
        .byte   px(%0110000),px(%0000000)
        .byte   px(%0111000),px(%0000000)
        .byte   px(%0111100),px(%0000000)
        .byte   px(%0111110),px(%0000000)
        .byte   px(%0111111),px(%0000000)
        .byte   px(%0101100),px(%0000000)
        .byte   px(%0000110),px(%0000000)
        .byte   px(%0000110),px(%0000000)
        .byte   px(%0000011),px(%0000000)
        .byte   px(%0000000),px(%0000000)
        .byte   px(%1100000),px(%0000000)
        .byte   px(%1110000),px(%0000000)
        .byte   px(%1111000),px(%0000000)
        .byte   px(%1111100),px(%0000000)
        .byte   px(%1111110),px(%0000000)
        .byte   px(%1111111),px(%0000000)
        .byte   px(%1111111),px(%1000000)
        .byte   px(%1111111),px(%0000000)
        .byte   px(%0001111),px(%0000000)
        .byte   px(%0001111),px(%0000000)
        .byte   px(%0000111),px(%1000000)
        .byte   px(%0000111),px(%1000000)
        .byte   1,1

;;; Insertion Point
LD2DF:
        .byte   px(%0000000),px(%0000000)
        .byte   px(%0110001),px(%1000000)
        .byte   px(%0001010),px(%0000000)
        .byte   px(%0000100),px(%0000000)
        .byte   px(%0000100),px(%0000000)
        .byte   px(%0000100),px(%0000000)
        .byte   px(%0000100),px(%0000000)
        .byte   px(%0000100),px(%0000000)
        .byte   px(%0001010),px(%0000000)
        .byte   px(%0110001),px(%1000000)
        .byte   px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000)
        .byte   px(%0110001),px(%1000000)
        .byte   px(%1111011),px(%1100000)
        .byte   px(%0111111),px(%1000000)
        .byte   px(%0001110),px(%0000000)
        .byte   px(%0001110),px(%0000000)
        .byte   px(%0001110),px(%0000000)
        .byte   px(%0001110),px(%0000000)
        .byte   px(%0001110),px(%0000000)
        .byte   px(%0111111),px(%1000000)
        .byte   px(%1111011),px(%1100000)
        .byte   px(%0110001),px(%1000000)
        .byte   px(%0000000),px(%0000000)
        .byte   4, 5

;;; Watch
LD311:
        .byte   px(%0000000),px(%0000000)
        .byte   px(%0011111),px(%1100000)
        .byte   px(%0011111),px(%1100000)
        .byte   px(%0100000),px(%0010000)
        .byte   px(%0100001),px(%0010000)
        .byte   px(%0100110),px(%0011000)
        .byte   px(%0100000),px(%0010000)
        .byte   px(%0100000),px(%0010000)
        .byte   px(%0011111),px(%1100000)
        .byte   px(%0011111),px(%1100000)
        .byte   px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000)
        .byte   px(%0011111),px(%1100000)
        .byte   px(%0111111),px(%1110000)
        .byte   px(%0111111),px(%1110000)
        .byte   px(%1111111),px(%1111000)
        .byte   px(%1111111),px(%1111000)
        .byte   px(%1111111),px(%1111100)
        .byte   px(%1111111),px(%1111000)
        .byte   px(%1111111),px(%1111000)
        .byte   px(%0111111),px(%1110000)
        .byte   px(%0111111),px(%1110000)
        .byte   px(%0011111),px(%1100000)
        .byte   px(%0000000),px(%0000000)
        .byte   5, 5

        .res    384, 0

        .byte   $00,$00

alert_bitmap2:
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),px(%0000000),PX(%1111111),PX(%1111111),px(%0000000),px(%0000000)
        .byte   px(%0111100),px(%1111100),px(%0000001),px(%1110000),PX(%0000111),px(%0000000),px(%0000000)
        .byte   px(%0111100),px(%1111100),px(%0000011),px(%1100000),px(%0000011),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0000111),PX(%1100111),px(%1111001),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0001111),PX(%1100111),px(%1111001),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0011111),PX(%1111111),px(%1111001),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0011111),PX(%1111111),px(%1110011),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0011111),PX(%1111111),PX(%1100111),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0011111),PX(%1111111),PX(%1001111),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0011111),PX(%1111111),PX(%0011111),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0011111),px(%1111110),PX(%0111111),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0011111),px(%1111100),PX(%1111111),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1111100),PX(%0011111),px(%1111100),PX(%1111111),px(%0000000),px(%0000000)
        .byte   px(%0111110),px(%0000000),PX(%0111111),PX(%1111111),PX(%1111111),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1100000),PX(%1111111),px(%1111100),PX(%1111111),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1100001),PX(%1111111),PX(%1111111),PX(%1111111),px(%0000000),px(%0000000)
        .byte   px(%0111000),px(%0000011),PX(%1111111),PX(%1111111),px(%1111110),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1100000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   PX(%0111111),px(%1100000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)

LD56D:
        .word   $28, $8         ; left, top
        .addr   alert_bitmap2
        .byte   $07             ; stride
        .byte   $00
        .word   0, 0, $24, $17  ; hoff, voff, width, height

        ;; Looks like window param blocks starting here

.proc winF
id:     .byte   $0F
flags:  .byte   A2D_CWF_NOTITLE
title:  .addr   0
hscroll:.byte   A2D_CWS_NOSCROLL
vscroll:.byte   A2D_CWS_NOSCROLL
hsmax:  .byte   0
hspos:  .byte   0
vsmax:  .byte   0
vspos:  .byte   0
        .byte   0,0             ; ???
w1:     .word   $96
h1:     .word   $32
w2:     .word   $1F4
h2:     .word   $8C
left:   .word   $4B
top:    .word   $23
addr:   .addr   A2D_SCREEN_ADDR
stride: .word   A2D_SCREEN_STRIDE
hoff:   .word   0
voff:   .word   0
width:  .word   $190
height: .word   $64
pattern:.res    8, $FF
mskand: .byte   A2D_DEFAULT_MSKAND
mskor:  .byte   A2D_DEFAULT_MSKOR
xpos:   .word   0
ypos:   .word   0
hthick: .byte   1
vthick: .byte   1
fill:   .byte   0
tmask:  .byte   A2D_DEFAULT_TMASK
font:   .addr   A2D_DEFAULT_FONT
next:   .addr   0
.endproc

.proc win12
id:     .byte   $12
flags:  .byte   A2D_CWF_NOTITLE
title:  .addr   0
hscroll:.byte   A2D_CWS_NOSCROLL
vscroll:.byte   A2D_CWS_NOSCROLL
hsmax:  .byte   0
hspos:  .byte   0
vsmax:  .byte   0
vspos:  .byte   0
        .byte   0,0             ; ???
w1:     .word   $96
h1:     .word   $32
w2:     .word   $1F4
h2:     .word   $8C
left:   .word   $19
top:    .word   $14
addr:   .addr   A2D_SCREEN_ADDR
stride: .word   A2D_SCREEN_STRIDE
hoff:   .word   0
voff:   .word   0
width:  .word   $1F4
height: .word   $99
pattern:.res    8, $FF
mskand: .byte   A2D_DEFAULT_MSKAND
mskor:  .byte   A2D_DEFAULT_MSKOR
xpos:   .word   0
ypos:   .word   0
hthick: .byte   1
vthick: .byte   1
mode:   .byte   0
tmask:  .byte   A2D_DEFAULT_TMASK
font:   .addr   A2D_DEFAULT_FONT
next:   .addr   0
.endproc

.proc win15
id:     .byte   $15
flags:  .byte   A2D_CWF_NOTITLE
title:  .addr   0
hscroll:.byte   A2D_CWS_NOSCROLL
vscroll:.byte   A2D_CWS_SCROLL_NORMAL
hsmax:  .byte   0
hspos:  .byte   0
vsmax:  .byte   3
vspos:  .byte   0
        .byte   0,0             ; ???
w1:     .word   $64
h1:     .word   $46
w2:     .word   $64
h2:     .word   $46
left:   .word   $35
top:    .word   $32
addr:   .addr   A2D_SCREEN_ADDR
stride: .word   A2D_SCREEN_STRIDE
hoff:   .word   0
voff:   .word   0
width:  .word   $7D
height: .word   $46
pattern:.res    8, $FF
mskand: .byte   A2D_DEFAULT_MSKAND
mskor:  .byte   A2D_DEFAULT_MSKOR
xpos:   .word   0
ypos:   .word   0
hthick: .byte   1
vthick: .byte   1
mode:   .byte   0
tmask:  .byte   A2D_DEFAULT_TMASK
font:   .addr   A2D_DEFAULT_FONT
next:   .addr   0
.endproc

.proc win18
id:     .byte   $18
flags:  .byte   A2D_CWF_NOTITLE
title:  .addr   0
hscroll:.byte   A2D_CWS_NOSCROLL
vscroll:.byte   A2D_CWS_NOSCROLL
hsmax:  .byte   0
hspos:  .byte   0
vsmax:  .byte   0
vspos:  .byte   0
        .byte   0,0             ; ???
w1:     .word   $96
h1:     .word   $32
w2:     .word   $1F4
h2:     .word   $8C
state:
left:   .word   $50
top:    .word   $28
addr:   .addr   A2D_SCREEN_ADDR
stride: .word   A2D_SCREEN_STRIDE
hoff:   .word   0
voff:   .word   0
width:  .word   $190
height: .word   $6E
pattern:.res    8, $FF
mskand: .byte   A2D_DEFAULT_MSKAND
mskor:  .byte   A2D_DEFAULT_MSKOR
xpos:   .word   0
ypos:   .word   0
hthick: .byte   1
vthick: .byte   1
mode:   .byte   0
tmask:  .byte   A2D_DEFAULT_TMASK
font:   .addr   A2D_DEFAULT_FONT
next:   .addr   0
.endproc

.proc win1B
id:     .byte   $1B
flags:  .byte   A2D_CWF_NOTITLE
title:  .addr   0
hscroll:.byte   A2D_CWS_NOSCROLL
vscroll:.byte   A2D_CWS_NOSCROLL
hsmax:  .byte   0
hspos:  .byte   0
vsmax:  .byte   0
vspos:  .byte   0
        .byte   0,0             ; ???
w1:     .word   $96
h1:     .word   $32
w2:     .word   $1F4
h2:     .word   $8C
left:   .word   $69
top:    .word   $19
addr:   .addr   A2D_SCREEN_ADDR
stride: .word   A2D_SCREEN_STRIDE
hoff:   .word   0
voff:   .word   0
width:  .word   $15E
height: .word   $6E
pattern:.res    8, $FF
mskand: .byte   A2D_DEFAULT_MSKAND
mskor:  .byte   A2D_DEFAULT_MSKOR
xpos:   .word   0
ypos:   .word   0
hthick: .byte   1
vthick: .byte   1
mode:   .byte   0
tmask:  .byte   A2D_DEFAULT_TMASK
font:   .addr   A2D_DEFAULT_FONT
next:   .addr   0
.endproc

        ;; Coordinates for labels?
        .byte   $28,$00,$25,$00,$68,$01,$2F,$00,$2D,$00,$2E,$00,$28,$00,$3D,$00,$68,$01,$47,$00,$2D,$00,$46,$00,$00,$00,$12,$00,$28,$00,$12,$00,$28,$00,$23,$00,$28,$00,$00,$00

        .word   $4B, $23        ; left, top
        .addr   A2D_SCREEN_ADDR
        .word   A2D_SCREEN_STRIDE
        .word   0, 0            ; width, height

        .byte   $66,$01,$64,$00,$00,$04,$00,$02,$00,$5A,$01,$6C,$00,$05,$00,$03,$00,$59,$01,$6B,$00,$06,$00,$16,$00,$58,$01,$16,$00,$06,$00,$59,$00,$58,$01,$59,$00,$D2,$00,$5C,$00,$36,$01,$67,$00,$28,$00,$5C,$00,$8C,$00,$67,$00,$D7,$00,$66,$00,$2D,$00,$66,$00,$82,$00,$07,$00,$DC,$00,$13,$00

LD718:  PASCAL_STRING "Add an Entry ..."
LD729:  PASCAL_STRING "Edit an Entry ..."
LD73B:  PASCAL_STRING "Delete an Entry ..."
LD74F:  PASCAL_STRING "Run an Entry ..."

LD760:  PASCAL_STRING "Run list"
        PASCAL_STRING "Enter the full pathname of the run list file:"
        PASCAL_STRING "Enter the name (14 characters max)  you wish to appear in the run list"
        PASCAL_STRING "Add a new entry to the:"
        PASCAL_STRING {A2D_GLYPH_OAPPLE,"1 Run list"}
        PASCAL_STRING {A2D_GLYPH_OAPPLE,"2 Other Run list"}
        PASCAL_STRING "Down load:"
        PASCAL_STRING {A2D_GLYPH_OAPPLE,"3 at first boot"}
        PASCAL_STRING {A2D_GLYPH_OAPPLE,"4 at first use"}
        PASCAL_STRING {A2D_GLYPH_OAPPLE,"5 never"}
        PASCAL_STRING "Enter the full pathname of the run list file:"

        .byte   $00,$00,$00,$00,$00,$00,$00
        .byte   $00,$06,$00,$17,$00,$58,$01,$57
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00

        PASCAL_STRING "the DOS 3.3 disk in slot   drive   ?"

        .byte   $1A,$22

        PASCAL_STRING "the disk in slot   drive   ?"

        .byte   $12
        .byte   $1A,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$14,$00,$00,$00,$00
        .byte   $01,$06,$00,$00,$00,$00,$00,$00
        .byte   $01,$00

        PASCAL_STRING "  "

        PASCAL_STRING "Files"

        PASCAL_STRING "       "

        .byte   $00,$00,$00,$00,$0D
        .byte   $00,$00,$00,$00,$00,$7D,$00,$00
        .byte   $00,$02,$00,$00,$00,$00,$00,$02
        .byte   $01,$02,$00,$00,$57,$01,$28,$00
        .byte   $6B,$01,$30,$00,$6B,$01,$38,$00
        .byte   $57,$01,$4B,$00,$6B,$01,$53,$00
        .byte   $6B,$01,$5B,$00,$6B,$01,$63,$00
        .byte   $5A,$01,$29,$00,$64,$01,$2F,$00
        .byte   $5A,$01,$31,$00,$64,$01,$37,$00
        .byte   $5A,$01,$4C,$00,$64,$01,$52,$00
        .byte   $5A,$01,$54,$00,$64,$01,$5A,$00
        .byte   $5A,$01,$5C,$00,$64,$01,$62,$00
        .byte   $5A,$01,$29,$00,$E0,$01,$30,$00
        .byte   $5A,$01,$31,$00,$E0,$01,$37,$00
        .byte   $5A,$01,$4C,$00,$E0,$01,$53,$00
        .byte   $5A,$01,$54,$00,$E0,$01,$5B,$00
        .byte   $5A,$01,$5C,$00,$E0,$01,$63,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$04,$00,$02,$00,$F0,$01
        .byte   $97,$00,$1B,$00,$10,$00,$AE,$00
        .byte   $1A,$00,$C1,$00,$3A,$00,$25,$01
        .byte   $45,$00,$C1,$00,$59,$00,$25,$01
        .byte   $64,$00,$C1,$00,$2C,$00,$25,$01
        .byte   $37,$00,$C1,$00,$49,$00,$25,$01
        .byte   $54,$00,$C1,$00,$1E,$00,$25,$01
        .byte   $29,$00,$43,$01,$1E,$00,$43,$01
        .byte   $64,$00,$81,$D3,$00

        .word   $C6,$63
        PASCAL_STRING {"OK            ",A2D_GLYPH_RETURN}

        .word   $C6,$44
        PASCAL_STRING "Close"

        .word   $C6,$36
        PASCAL_STRING "Open"

        .word   $C6,$53
        PASCAL_STRING "Cancel        Esc"

        .word   $C6,$28
        PASCAL_STRING "Change Drive"

        .byte   $1C,$00,$19,$00,$1C
        .byte   $00,$70,$00,$1C,$00,$87,$00,$00
        .byte   $7F

        PASCAL_STRING " Disk: "

        PASCAL_STRING "Copy a File ..."
        PASCAL_STRING "Source filename:"
        PASCAL_STRING "Destination filename:"

        .byte   $1C,$00,$71,$00,$CF,$01,$7C,$00
        .byte   $1E,$00,$7B,$00,$1C,$00,$88,$00
        .byte   $CF,$01,$93,$00,$1E,$00,$92,$00

        PASCAL_STRING "Delete a File ..."
        PASCAL_STRING "File to delete:"

        .res    40, 0

        .addr   sd0s, sd1s, sd2s, sd3s, sd4s, sd5s, sd6s
        .addr   sd7s, sd8s, sd9s, sd10s, sd11s, sd12s, sd13s

        .addr   selector_menu

        ;; Buffer for Run List entries
run_list_entries:
        .res    896, 0

        .byte   $00
LDE9F:  .byte   $00
LDEA0:  .res    256, 0
        .byte   $00

        ;; Buffer for desktop windows
LDFA1:  .addr   0,win1,win2,win3,win4,win5,win6,win7,win8
        .addr   $0000
        .repeat 8,i
        .addr   buf2+i*$41
        .endrepeat

        .byte   $00,$00,$00,$00,$00

        .res    144, 0

        .byte   $00,$00,$00,$00,$0D,$00,$00,$00

        .res    440, 0

        .byte   $00,$00,$00,$00,$7F,$64,$00,$1C
        .byte   $00,$1E,$00,$32,$00,$1E,$00,$40
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$04,$00,$00,$00,$04,$00,$00
        .byte   $04,$00,$00,$00,$00,$00,$04,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00

        .addr   str_all

LE27C:  DEFINE_MENU_SEPARATOR
        DEFINE_MENU_ITEM sd0s
        DEFINE_MENU_ITEM sd1s
        DEFINE_MENU_ITEM sd2s
        DEFINE_MENU_ITEM sd3s
        DEFINE_MENU_ITEM sd4s
        DEFINE_MENU_ITEM sd5s
        DEFINE_MENU_ITEM sd6s
        DEFINE_MENU_ITEM sd7s
        DEFINE_MENU_ITEM sd8s
        DEFINE_MENU_ITEM sd9s
        DEFINE_MENU_ITEM sd10s
        DEFINE_MENU_ITEM sd11s
        DEFINE_MENU_ITEM sd12s
        DEFINE_MENU_ITEM sd13s

startup_menu:
        DEFINE_MENU 7
        DEFINE_MENU_ITEM s00
        DEFINE_MENU_ITEM s01
        DEFINE_MENU_ITEM s02
        DEFINE_MENU_ITEM s03
        DEFINE_MENU_ITEM s04
        DEFINE_MENU_ITEM s05
        DEFINE_MENU_ITEM s06

str_all:PASCAL_STRING "All"

sd0:    A2D_DEFSTRING "Slot    drive       ", sd0s
sd1:    A2D_DEFSTRING "Slot    drive       ", sd1s
sd2:    A2D_DEFSTRING "Slot    drive       ", sd2s
sd3:    A2D_DEFSTRING "Slot    drive       ", sd3s
sd4:    A2D_DEFSTRING "Slot    drive       ", sd4s
sd5:    A2D_DEFSTRING "Slot    drive       ", sd5s
sd6:    A2D_DEFSTRING "Slot    drive       ", sd6s
sd7:    A2D_DEFSTRING "Slot    drive       ", sd7s
sd8:    A2D_DEFSTRING "Slot    drive       ", sd8s
sd9:    A2D_DEFSTRING "Slot    drive       ", sd9s
sd10:   A2D_DEFSTRING "Slot    drive       ", sd10s
sd11:   A2D_DEFSTRING "Slot    drive       ", sd11s
sd12:   A2D_DEFSTRING "Slot    drive       ", sd12s
sd13:   A2D_DEFSTRING "Slot    drive       ", sd13s

s00:    PASCAL_STRING "Slot 0 "
s01:    PASCAL_STRING "Slot 0 "
s02:    PASCAL_STRING "Slot 0 "
s03:    PASCAL_STRING "Slot 0 "
s04:    PASCAL_STRING "Slot 0 "
s05:    PASCAL_STRING "Slot 0 "
s06:    PASCAL_STRING "Slot 0 "

        .addr   sd0, sd1, sd2, sd3, sd4, sd5, sd6, sd7
        .addr   sd8, sd9, sd10, sd11, sd12, sd13

        PASCAL_STRING "ProFile Slot x     "
        PASCAL_STRING "UniDisk 3.5  Sx,y  "
        PASCAL_STRING "RAMCard Slot x      "
        PASCAL_STRING "Slot    drive       "

selector_menu:
        DEFINE_MENU 5
        DEFINE_MENU_ITEM label_add
        DEFINE_MENU_ITEM label_edit
        DEFINE_MENU_ITEM label_del
        DEFINE_MENU_ITEM label_run, '0', '0'
        DEFINE_MENU_SEPARATOR
        DEFINE_MENU_ITEM run_list_entries + 0 * $10, '1', '1'
        DEFINE_MENU_ITEM run_list_entries + 1 * $10, '2', '2'
        DEFINE_MENU_ITEM run_list_entries + 2 * $10, '3', '3'
        DEFINE_MENU_ITEM run_list_entries + 3 * $10, '4', '4'
        DEFINE_MENU_ITEM run_list_entries + 4 * $10, '5', '5'
        DEFINE_MENU_ITEM run_list_entries + 5 * $10, '6', '6'
        DEFINE_MENU_ITEM run_list_entries + 6 * $10, '7', '7'
        DEFINE_MENU_ITEM run_list_entries + 7 * $10, '8', '8'

label_add:
        PASCAL_STRING "Add an Entry ..."
label_edit:
        PASCAL_STRING "Edit an Entry ..."
label_del:
        PASCAL_STRING "Delete an Entry ...      "
label_run:
        PASCAL_STRING "Run an Entry ..."

        ;; Apple Menu
apple_menu:
        DEFINE_MENU 1
        DEFINE_MENU_ITEM label_about
        DEFINE_MENU_SEPARATOR
        DEFINE_MENU_ITEM buf + 0 * $10
        DEFINE_MENU_ITEM buf + 1 * $10
        DEFINE_MENU_ITEM buf + 2 * $10
        DEFINE_MENU_ITEM buf + 3 * $10
        DEFINE_MENU_ITEM buf + 4 * $10
        DEFINE_MENU_ITEM buf + 5 * $10
        DEFINE_MENU_ITEM buf + 6 * $10
        DEFINE_MENU_ITEM buf + 7 * $10

label_about:
        PASCAL_STRING "About Apple II DeskTop ... "

buf:    .res    $80, 0

        .byte   $01,$00,$01,$00,$9A,$E6,$8E,$E6
        .byte   $00,$00,$00,$00,$00,$00,$01,$00
        .byte   $01,$00,$B7,$E6,$8E,$E6,$00,$00
        .byte   $00,$00,$00,$00,$01,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$B9,$E6

        PASCAL_STRING "Apple II DeskTop Version 1.1"

        .byte   $01,$20,$04
        .byte   $52,$69,$65,$6E,$00,$00,$00,$5D
        .byte   $E7,$A9,$E7,$F5,$E7,$41,$E8,$8D
        .byte   $E8,$D9,$E8,$25,$E9,$71,$E9,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$70,$00,$00,$00,$8C
        .byte   $00,$00,$00,$E7,$00,$00,$00

.proc text_buffer2
        .addr   data
        .byte   0
data:   .res    55, 0
.endproc

.macro WIN_PARAMS_DEFN window_id, label, buflabel
.proc label
id:     .byte   window_id
flags:  .byte   A2D_CWF_ADDCLOSE | A2D_CWF_ADDRESIZE
title:  .addr   buflabel
hscroll:.byte   A2D_CWS_SCROLL_NORMAL
vscroll:.byte   A2D_CWS_SCROLL_NORMAL
hsmax:  .byte   3
hspos:  .byte   0
vsmax:  .byte   3
vspos:  .byte   0
        .byte   0,0             ; ???
w1:     .word   170
h1:     .word   50
w2:     .word   545
h2:     .word   175
left:   .word   20
top:    .word   27
addr:   .addr   A2D_SCREEN_ADDR
stride: .word   A2D_SCREEN_STRIDE
hoff:   .word   0
voff:   .word   0
width:  .word   440
height: .word   120
pattern:.res    8, $FF
mskand: .byte   A2D_DEFAULT_MSKAND
mskor:  .byte   A2D_DEFAULT_MSKOR
xpos:   .word   0
ypos:   .word   0
hthick: .byte   1
vthick: .byte   1
mode:   .byte   0
tmask:  .byte   A2D_DEFAULT_TMASK
font:   .addr   A2D_DEFAULT_FONT
next:   .addr   0
.endproc
buflabel:.res    18, 0
.endmacro

        WIN_PARAMS_DEFN 1, win1, win1buf
        WIN_PARAMS_DEFN 2, win2, win2buf
        WIN_PARAMS_DEFN 3, win3, win3buf
        WIN_PARAMS_DEFN 4, win4, win4buf
        WIN_PARAMS_DEFN 5, win5, win5buf
        WIN_PARAMS_DEFN 6, win6, win6buf
        WIN_PARAMS_DEFN 7, win7, win7buf
        WIN_PARAMS_DEFN 8, win8, win8buf

buf2:   .res    560, 0

        PASCAL_STRING " Items"

        .byte   $08,$00,$0A,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00

        PASCAL_STRING "K in disk"
        PASCAL_STRING "K available"
        PASCAL_STRING "      "

        .byte   $00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00

LEC01:  .byte   $00,$1B,$80,$1B,$00,$1C,$80,$1C,$00,$1D,$80,$1D,$00,$1E,$80,$1E,$00,$1F
LEC13:  .byte   $01,$1B,$81,$1B,$01,$1C,$81,$1C,$01,$1D,$81,$1D,$01,$1E,$81,$1E,$01,$1F

LEC25:  .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00,$00,$00,$00,$00,$00,$00,$00
        .byte   $00
        .word   500, 160
        .byte   $00,$00,$00

        .res    147, 0

;;; ==================================================

        .org $FB00

LFB00:  .addr type_table
LFB02:  .addr type_icons
LFB04:  .addr LFB11
LFB06:  .addr type_names

type_table:
        .byte   8
        .byte   FT_TYPELESS, FT_SRC, FT_TEXT, FT_BINARY
        .byte   FT_DIRECTORY, FT_SYSTEM, FT_BASIC, FT_BAD

        ;; ???
LFB11:  .byte   $60,$50,$50,$50,$20,$00,$10,$30,$10

type_names:
        .byte   " ???"

        ;; Same order as icon list below
        .byte   " ???", " SRC", " TXT", " BIN"
        .byte   " DIR", " SYS", " BAS", " SYS"

        .byte   " BAD"

type_icons:
        .addr  gen, src, txt, bin, dir, sys, bas, app

.macro  DEFICON addr, stride, left, top, width, height
        .addr   addr
        .word   stride, left, top, width, height
.endmacro

gen:    DEFICON generic_icon, 4, 0, 0, 27, 17
src:
txt:    DEFICON text_icon, 4, 0, 0, 27, 17
bin:    DEFICON binary_icon, 4, 0, 0, 27, 17
dir:    DEFICON folder_icon, 4, 0, 0, 27, 17
sys:    DEFICON sys_icon, 4, 0, 0, 27, 17
bas:    DEFICON basic_icon, 4, 0, 0, 27, 17
app:    DEFICON app_icon, 5, 0, 0, 34, 17

;;; Generic

generic_icon:
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),px(%1000000)
        .byte   px(%1000000),px(%0000000),PX(%0000001),px(%1100000)
        .byte   px(%1000000),px(%0000000),PX(%0000001),px(%0110000)
        .byte   px(%1000000),px(%0000000),PX(%0000001),px(%0011000)
        .byte   px(%1000000),px(%0000000),PX(%0000001),PX(%0001100)
        .byte   px(%1000000),px(%0000000),PX(%0000001),PX(%0000110)
        .byte   px(%1000000),px(%0000000),PX(%0000001),PX(%0000011)
        .byte   px(%1000000),px(%0000000),PX(%0000001),PX(%1111111)
        .byte   px(%1000000),px(%0000000),px(%0000000),PX(%0000001)
        .byte   px(%1000000),px(%0000000),px(%0000000),PX(%0000001)
        .byte   px(%1000000),px(%0000000),px(%0000000),PX(%0000001)
        .byte   px(%1000000),px(%0000000),px(%0000000),PX(%0000001)
        .byte   px(%1000000),px(%0000000),px(%0000000),PX(%0000001)
        .byte   px(%1000000),px(%0000000),px(%0000000),PX(%0000001)
        .byte   px(%1000000),px(%0000000),px(%0000000),PX(%0000001)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)

generic_mask:
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),px(%1000000)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),px(%1100000)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),px(%1110000)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),px(%1111000)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),px(%1111100)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),px(%1111110)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)

;;; Text File

text_icon:
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),px(%1000000)
        .byte   px(%1000000),px(%0000000),PX(%0000001),px(%1100000)
        .byte   px(%1001100),px(%0111110),PX(%0111111),px(%0110000)
        .byte   px(%1000000),px(%0000000),PX(%0000001),px(%0011000)
        .byte   px(%1001111),px(%1100111),px(%1000001),PX(%0001100)
        .byte   px(%1000000),px(%0000000),px(%0000001),px(%0000110)
        .byte   px(%1001111),px(%0011110),px(%0110001),PX(%0000011)
        .byte   px(%1000000),px(%0000000),PX(%0000001),PX(%1111111)
        .byte   px(%1000000),px(%0000000),px(%0000000),px(%0000001)
        .byte   px(%1001111),px(%1100110),px(%0111100),px(%1111001)
        .byte   px(%1000000),px(%0000000),px(%0000000),px(%0000001)
        .byte   px(%1001111),px(%0011110),px(%1111111),px(%0000001)
        .byte   px(%1000000),px(%0000000),px(%0000000),PX(%0000001)
        .byte   px(%1001111),px(%0011111),px(%1001111),px(%1100001)
        .byte   px(%1000000),px(%0000000),px(%0000000),PX(%0000001)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)

text_mask:
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),px(%1000000)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),px(%1100000)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),px(%1110000)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),px(%1111000)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),px(%1111100)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),px(%1111110)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)

;;; Binary

binary_icon:
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),PX(%0000001),px(%1000000),px(%0000000)
        .byte   px(%0000000),px(%0000110),px(%0110000),px(%0000000)
        .byte   px(%0000000),px(%0011000),px(%0001100),px(%0000000)
        .byte   px(%0000000),px(%1100000),px(%0000011),px(%0000000)
        .byte   px(%0000011),px(%0000000),px(%0000000),px(%1100000)
        .byte   px(%0001100),px(%0011000),px(%0011000),px(%0011000)
        .byte   px(%0110000),px(%0100100),px(%0101000),px(%0000110)
        .byte   px(%1000000),px(%0100100),px(%0001000),px(%0000001)
        .byte   px(%0110000),px(%0100100),px(%0001000),px(%0000110)
        .byte   px(%0001100),px(%0011000),px(%0001000),px(%0011000)
        .byte   px(%0000011),px(%0000000),px(%0000000),px(%1100000)
        .byte   px(%0000000),px(%1100000),px(%0000011),px(%0000000)
        .byte   px(%0000000),px(%0011000),px(%0001100),px(%0000000)
        .byte   px(%0000000),px(%0000110),px(%0110000),px(%0000000)
        .byte   px(%0000000),PX(%0000001),px(%1000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)

binary_mask:
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),PX(%0000001),px(%1000000),px(%0000000)
        .byte   px(%0000000),px(%0000111),px(%1110000),px(%0000000)
        .byte   px(%0000000),PX(%0011111),px(%1111100),px(%0000000)
        .byte   px(%0000000),PX(%1111111),PX(%1111111),px(%0000000)
        .byte   px(%0000011),PX(%1111111),PX(%1111111),px(%1100000)
        .byte   PX(%0001111),PX(%1111111),PX(%1111111),px(%1111000)
        .byte   PX(%0111111),PX(%1111111),PX(%1111111),px(%1111110)
        .byte   PX(%0001111),PX(%1111111),PX(%1111111),px(%1111000)
        .byte   px(%0000011),PX(%1111111),PX(%1111111),px(%1100000)
        .byte   px(%0000000),PX(%1111111),PX(%1111111),px(%0000000)
        .byte   px(%0000000),PX(%0011111),px(%1111100),px(%0000000)
        .byte   px(%0000000),px(%0000111),px(%1110000),px(%0000000)
        .byte   px(%0000000),PX(%0000001),px(%1000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)

;;; Folder
folder_icon:
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   PX(%0011111),px(%1111110),px(%0000000),px(%0000000)
        .byte   px(%0100000),px(%0000001),px(%0000000),px(%0000000)
        .byte   PX(%0111111),PX(%1111111),PX(%1111111),px(%1111110)
        .byte   px(%1000000),px(%0000000),px(%0000000),PX(%0000001)
        .byte   px(%1000000),px(%0000000),px(%0000000),PX(%0000001)
        .byte   px(%1000000),px(%0000000),px(%0000000),PX(%0000001)
        .byte   px(%1000000),px(%0000000),px(%0000000),PX(%0000001)
        .byte   px(%1000000),px(%0000000),px(%0000000),PX(%0000001)
        .byte   px(%1000000),px(%0000000),px(%0000000),PX(%0000001)
        .byte   px(%1000000),px(%0000000),px(%0000000),PX(%0000001)
        .byte   px(%1000000),px(%0000000),px(%0000000),PX(%0000001)
        .byte   PX(%0111111),PX(%1111111),PX(%1111111),px(%1111110)

folder_mask:
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   PX(%0011111),px(%1111110),px(%0000000),px(%0000000)
        .byte   PX(%0111111),PX(%1111111),px(%0000000),px(%0000000)
        .byte   PX(%0111111),PX(%1111111),PX(%1111111),px(%1111110)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%0111111),PX(%1111111),PX(%1111111),px(%1111110)

;;; System (no .SYSTEM suffix)

sys_icon:
        .byte   px(%0001111),px(%1111111),px(%1111111),px(%1111000)
        .byte   px(%0110000),px(%0000000),px(%0000000),px(%0000110)
        .byte   px(%0110011),px(%1111111),px(%1111111),px(%1100110)
        .byte   px(%0110011),px(%0000000),px(%0010000),px(%1100110)
        .byte   px(%0110011),px(%0000000),px(%0100000),px(%1100110)
        .byte   px(%0110011),px(%0010000),px(%1000100),px(%1100110)
        .byte   px(%0110011),px(%0100000),px(%0001000),px(%1100110)
        .byte   px(%0110011),px(%1111111),px(%1111111),px(%1100110)
        .byte   px(%0110000),px(%0000000),px(%0000000),px(%0000110)
        .byte   px(%0001111),px(%1111111),px(%1111111),px(%1111000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%1111111),px(%1111111),px(%1111111),px(%1111111)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000011)
        .byte   px(%1100110),px(%0000000),px(%0000000),px(%0000011)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000011)
        .byte   px(%1111111),px(%1111111),px(%1111111),px(%1111111)
        .byte   px(%1100000),px(%0000000),px(%0000000),px(%0000011)
        .byte   px(%1111111),px(%1111111),px(%1111111),px(%1111111)

sys_mask:
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0001111),px(%1111111),px(%1111111),px(%1111000)
        .byte   px(%0001111),px(%1111111),px(%1111111),px(%1111000)
        .byte   px(%0001111),px(%1111111),px(%1111111),px(%1111000)
        .byte   px(%0001111),px(%1111111),px(%1111111),px(%1111000)
        .byte   px(%0001111),px(%1111111),px(%1111111),px(%1111000)
        .byte   px(%0001111),px(%1111111),px(%1111111),px(%1111000)
        .byte   px(%0001111),px(%1111111),px(%1111111),px(%1111000)
        .byte   px(%0001111),px(%1111111),px(%1111111),px(%1111000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0011111),px(%1111111),px(%1111111),px(%1111100)
        .byte   px(%0011111),px(%1111111),px(%1111111),px(%1111100)
        .byte   px(%0011111),px(%1111111),px(%1111111),px(%1111100)
        .byte   px(%0011111),px(%1111111),px(%1111111),px(%1111100)
        .byte   px(%0011111),px(%1111111),px(%1111111),px(%1111100)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)

;;; Basic

basic_icon:
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),PX(%0000001),px(%1000000),px(%0000000)
        .byte   px(%0000000),px(%0000110),px(%0110000),px(%0000000)
        .byte   px(%0000000),px(%0011000),px(%0001100),px(%0000000)
        .byte   px(%0000000),px(%1100000),px(%0000011),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0111110),px(%0111000),px(%1111010),px(%0111100)
        .byte   px(%0100010),px(%1000100),px(%1000010),px(%1000110)
        .byte   px(%0111100),px(%1111100),px(%1111010),px(%1000000)
        .byte   px(%0100010),px(%1000100),px(%0001010),px(%1000110)
        .byte   px(%0111110),px(%1000100),px(%1111010),px(%0111100)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%1100000),px(%0000011),px(%0000000)
        .byte   px(%0000000),px(%0011000),px(%0001100),px(%0000000)
        .byte   px(%0000000),px(%0000110),px(%0110000),px(%0000000)
        .byte   px(%0000000),PX(%0000001),px(%1000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)

basic_mask:
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),PX(%0000001),px(%1000000),px(%0000000)
        .byte   px(%0000000),px(%0000111),px(%1110000),px(%0000000)
        .byte   px(%0000000),PX(%0011111),px(%1111100),px(%0000000)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   PX(%1111111),PX(%1111111),PX(%1111111),PX(%1111111)
        .byte   px(%0000000),PX(%0011111),px(%1111100),px(%0000000)
        .byte   px(%0000000),px(%0000111),px(%1110000),px(%0000000)
        .byte   px(%0000000),PX(%0000001),px(%1000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000)

;;; System (with .SYSTEM suffix)

app_icon:
        .byte   px(%0000000),px(%0000000),px(%0011000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%1100110),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000011),px(%0000001),px(%1000000),px(%0000000)
        .byte   px(%0000000),px(%0001100),px(%0000000),px(%0110000),px(%0000000)
        .byte   px(%0000000),px(%0110000),px(%0000000),px(%0001100),px(%0000000)
        .byte   px(%0000001),px(%1000000),px(%0000000),px(%0000011),px(%0000000)
        .byte   px(%0000110),px(%0000000),px(%0000000),px(%0000000),px(%1100000)
        .byte   px(%0011000),px(%0000000),px(%0000001),px(%1111100),px(%0011000)
        .byte   px(%1100000),px(%0000000),px(%0000110),px(%0000011),px(%0000110)
        .byte   px(%0011000),px(%0000000),px(%0011000),px(%1110000),px(%1111000)
        .byte   px(%0000110),px(%0000111),px(%1111111),px(%1111100),px(%0011110)
        .byte   px(%0000001),px(%1000000),px(%0110000),px(%1100000),px(%0011110)
        .byte   px(%0000000),px(%0110000),px(%0001110),px(%0000000),px(%0011110)
        .byte   px(%0000000),px(%0001100),px(%0000001),PX(%1111111),px(%1111110)
        .byte   px(%0000000),px(%0000011),px(%0000001),px(%1000000),px(%0011110)
        .byte   px(%0000000),px(%0000000),px(%1100110),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0011000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)

app_mask:
        .byte   px(%0000000),px(%0000000),px(%0011000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%1111110),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000011),px(%1111111),px(%1000000),px(%0000000)
        .byte   px(%0000000),px(%0001111),px(%1111111),px(%1110000),px(%0000000)
        .byte   px(%0000000),px(%0111111),px(%1111111),px(%1111100),px(%0000000)
        .byte   px(%0000001),px(%1111111),px(%1111111),px(%1111111),px(%0000000)
        .byte   px(%0000111),px(%1111111),px(%1111111),px(%1111111),px(%1100000)
        .byte   px(%0011111),px(%1111111),px(%1111111),px(%1111111),px(%1111000)
        .byte   px(%1111111),px(%1111111),px(%1111111),px(%1111111),px(%1111110)
        .byte   px(%0011111),px(%1111111),px(%1111111),px(%1111111),px(%1111100)
        .byte   px(%0000111),px(%1111111),px(%1111111),px(%1111111),px(%1111000)
        .byte   px(%0000001),px(%1111111),px(%1111111),px(%1111111),px(%1111000)
        .byte   px(%0000000),px(%0111111),px(%1111111),px(%1111100),px(%1111000)
        .byte   px(%0000000),px(%0001111),px(%1111111),px(%1111000),px(%0000000)
        .byte   px(%0000000),px(%0000011),px(%1111111),px(%1000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%1111110),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0011000),px(%0000000),px(%0000000)
        .byte   px(%0000000),px(%0000000),px(%0000000),px(%0000000),px(%0000000)

        .res    70
.endproc
        desktop_LD05E := desktop::LD05E
        desktop_A2D_RELAY := desktop::A2D_RELAY
        desktop_win18_state := desktop::win18::state
