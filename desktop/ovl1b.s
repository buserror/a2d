;;; ============================================================
;;; Overlay for Disk Copy - $D000 - $F1FF (file 3/4)
;;; ============================================================

.proc disk_copy_overlay3
        .org $D000

.scope disk_copy_overlay4
.scope on_line_params2
unit_num        := $0C42
.endscope
.scope on_line_params
unit_num        := $0C46
.endscope
        on_line_buffer := $0C49
.scope block_params
unit_num       := $0C5A
data_buffer    := $0C5B
block_num      := $0C5D
.endscope

just_rts        := $0C83
quit    := $0C84
L0CAF   := $0CAF
eject_disk      := $0CED
L0D26   := $0D26
L0D51   := $0D51
L0D5F   := $0D5F
L0DB5   := $0DB5
L0EB2   := $0EB2
L0ED7   := $0ED7
L10FB   := $10FB
L127E   := $127E
L1291   := $1291
L129B   := $129B
L12A5   := $12A5
L12AF   := $12AF
.endscope

.macro MGTK_RELAY_CALL2 call, params
    .if .paramcount > 1
        yax_call MGTK_RELAY2, call, params
    .else
        yax_call MGTK_RELAY2, call, 0
    .endif
.endmacro

        jmp     LD5E1

;;; ============================================================
;;; Resources

pencopy:        .byte   0
penOR:          .byte   1
penXOR:         .byte   2
penBIC:         .byte   3
notpencopy:     .byte   4
notpenOR:       .byte   5
notpenXOR:      .byte   6
notpenBIC:      .byte   7

LD00B:  .byte   0

.proc hilitemenu_params
menu_id   := * + 0
.endproc
.proc menuselect_params
menu_id   := * + 0
menu_item := * + 1
.endproc
.proc menukey_params
menu_id   := * + 0
menu_item := * + 1
which_key := * + 2
key_mods  := * + 3
.endproc
        .res    4, 0



        .byte   0
        .byte   0
        .byte   0
        .byte   0
        .byte   0

;;; ============================================================
;;; Menu definition

        menu_id_apple := 1
        menu_id_file := 2
        menu_id_facilities := 3

menu_definition:
        DEFINE_MENU_BAR 3
        DEFINE_MENU_BAR_ITEM menu_id_apple, label_apple, menu_apple
        DEFINE_MENU_BAR_ITEM menu_id_file, label_file, menu_file
        DEFINE_MENU_BAR_ITEM menu_id_facilities, label_facilities, menu_facilities

menu_apple:
        DEFINE_MENU 5
        DEFINE_MENU_ITEM label_desktop
        DEFINE_MENU_ITEM label_blank
        DEFINE_MENU_ITEM label_copyright1
        DEFINE_MENU_ITEM label_copyright2
        DEFINE_MENU_ITEM label_rights

menu_file:
        DEFINE_MENU 1
        DEFINE_MENU_ITEM label_quit, 'Q', 'q'

label_apple:
        PASCAL_STRING GLYPH_SAPPLE

menu_facilities:
        DEFINE_MENU 2
        DEFINE_MENU_ITEM label_quick_copy
        DEFINE_MENU_ITEM label_disk_copy

label_file:
        PASCAL_STRING "File"
label_facilities:
        PASCAL_STRING "Facilities"

label_desktop:
        PASCAL_STRING .sprintf("Apple II DeskTop version %d.%d",::VERSION_MAJOR,::VERSION_MINOR)
label_blank:
        PASCAL_STRING " "
label_copyright1:
        PASCAL_STRING "Copyright Apple Computer Inc., 1986 "
label_copyright2:
        PASCAL_STRING "Copyright Version Soft, 1985 - 1986 "
label_rights:
        PASCAL_STRING "All Rights reserved"

label_quit:
        PASCAL_STRING "Quit"

label_quick_copy:
        PASCAL_STRING "Quick Copy "

label_disk_copy:
        PASCAL_STRING "Disk Copy "

;;; ============================================================

disablemenu_params:
        .byte   3
LD129:  .byte   0

checkitem_params:
        .byte   3
LD12B:  .byte   0
LD12C:  .byte   0

event_params := *
        event_kind := event_params + 0
        ;;  if kind is key_down
        event_key := event_params + 1
        event_modifiers := event_params + 2
        ;;  if kind is no_event, button_down/up, drag, or apple_key:
        event_coords := event_params + 1
        event_xcoord := event_params + 1
        event_ycoord := event_params + 3
        ;;  if kind is update:
        event_window_id := event_params + 1

screentowindow_params := *
        screentowindow_window_id := screentowindow_params + 0
        screentowindow_screenx := screentowindow_params + 1
        screentowindow_screeny := screentowindow_params + 3
        screentowindow_windowx := screentowindow_params + 5
        screentowindow_windowy := screentowindow_params + 7

findwindow_params := * + 1    ; offset to x/y overlap event_params x/y
        findwindow_mousex := findwindow_params + 0
        findwindow_mousey := findwindow_params + 2
        findwindow_which_area := findwindow_params + 4
        findwindow_window_id := findwindow_params + 5


        .byte   0
        .byte   0
LD12F:  .byte   0
        .byte   0
        .byte   0
        .byte   0

LD133:  .byte   0

LD134:  .byte   0
        .byte   0
        .byte   0

grafport:  .res .sizeof(MGTK::GrafPort), 0

.proc getwinport_params
window_id:      .byte   0
port:           .addr   grafport_win
.endproc

grafport_win:  .res    .sizeof(MGTK::GrafPort), 0

        ;; Rest of a winfo???
        .byte   $06, $EA, 0, 0, 0, 0, $88, 0, $08, 0, $08

.proc winfo_dialog
window_id:      .byte   1
options:        .byte   MGTK::Option::dialog_box
title:          .addr   0
hscroll:        .byte   MGTK::Scroll::option_none
vscroll:        .byte   MGTK::Scroll::option_none
hthumbmax:      .byte   0
hthumbpos:      .byte   0
vthumbmax:      .byte   0
vthumbpos:      .byte   0
status:         .byte   0
reserved:       .byte   0
mincontwidth:   .word   150
mincontlength:  .word   50
maxcontwidth:   .word   500
maxcontlength:  .word   140
port:
viewloc:        DEFINE_POINT 25, 20
mapbits:        .addr   MGTK::screen_mapbits
mapwidth:       .word   MGTK::screen_mapwidth
cliprect:       DEFINE_RECT 0, 0, 500, 150
penpattern:     .res    8, $FF
colormasks:     .byte   MGTK::colormask_and, MGTK::colormask_or
penloc:         DEFINE_POINT 0, 0
penwidth:       .byte   1
penheight:      .byte   1
penmode:        .byte   0
textbg:         .byte   MGTK::textbg_white
fontptr:        .addr   DEFAULT_FONT
nextwinfo:      .addr   0
.endproc

.proc winfo_drive_select
window_id:      .byte   $02
options:        .byte   MGTK::Option::dialog_box
title:          .addr   0
hscroll:        .byte   MGTK::Scroll::option_none
vscroll:        .byte   MGTK::Scroll::option_present
hthumbmax:      .byte   0
hthumbpos:      .byte   0
vthumbmax:      .byte   3
vthumbpos:      .byte   0
status:         .byte   0
reserved:       .byte   0
mincontwidth:   .word   100
mincontlength:  .word   50
maxcontwidth:   .word   150
maxcontlength:  .word   150
port:
viewloc:        DEFINE_POINT 45, 50
mapbits:        .addr   MGTK::screen_mapbits
mapwidth:       .word   MGTK::screen_mapwidth
cliprect:       DEFINE_RECT 0, 0, 150, 70
penpattern:     .res    8, $FF
colormasks:     .byte   MGTK::colormask_and, MGTK::colormask_or
penloc:         DEFINE_POINT 0, 0
penwidth:       .byte   1
penheight:      .byte   1
penmode:        .byte   0
textbg:         .byte   MGTK::textbg_white
fontptr:        .addr   DEFAULT_FONT
nextwinfo:      .addr   0
.endproc

rect_outer_frame:      DEFINE_RECT 4, 2, 496, 148
rect_inner_frame:      DEFINE_RECT 5, 3, 495, 147
rect_D211:      DEFINE_RECT 6, 20, 494, 102
rect_D219:      DEFINE_RECT 6, 103, 494, 145
rect_D221:      DEFINE_RECT 350, 90, 450, 101
rect_D229:      DEFINE_RECT 210, 90, 310, 101
point_ok_label:     DEFINE_POINT 355, 100

str_ok_label:
        PASCAL_STRING {"OK            ",CHAR_RETURN}

;;; Label positions
point_read_drive:     DEFINE_POINT 215, 100
point_D249:     DEFINE_POINT 0, 15
point_slot_drive_name:     DEFINE_POINT 20, 28
point_select_source:     DEFINE_POINT 270, 46
rect_D255:      DEFINE_RECT 270, 38, 420, 46
point_formatting:     DEFINE_POINT 210, 68
point_writing:     DEFINE_POINT 210, 68
point_reading:     DEFINE_POINT 210, 68

str_read_drive:
        PASCAL_STRING "Read Drive   D"
str_disk_copy_padded:
        PASCAL_STRING "     Disk Copy    "
str_quick_copy_padded:
        PASCAL_STRING "Quick Copy      "
str_slot_drive_name:
        PASCAL_STRING "Slot, Drive, Name"
str_select_source:
        PASCAL_STRING "Select source disk"
str_select_destination:
        PASCAL_STRING "Select destination disk"
str_formatting:
        PASCAL_STRING "Formatting the disk ...."
str_writing:
        PASCAL_STRING "Writing ....   "
str_reading:
        PASCAL_STRING "Reading ....    "
str_unknown:
        PASCAL_STRING "Unknown"
str_select_quit:
        PASCAL_STRING {"Select Quit from the file menu (",GLYPH_OAPPLE,"Q) to go back to the DeskTop"}

bg_black:
        .byte   0
bg_white:
        .byte   $7F

rect_D35B: DEFINE_RECT 0, 0, $96, 0, rect_D35B

        ;; TODO: Identify data
LD363:  .byte   0
        .byte   0
        .byte   0
        .byte   0
LD367:  .byte   0
LD368:  .byte   0
        .byte   0
        .byte   0
        .byte   0
        .byte   0

point_D36D:  DEFINE_POINT 0, 0, point_D36D
        .byte   0
        .byte   0
        .byte   $47
        .byte   0
LD375:  .byte   0
LD376:  .byte   0

LD377:  .res    128, 0
LD3F7:  .res    8, 0
LD3FF:  .res    8, 0
LD407:  .res    16, 0

LD417:  .byte   0
LD418:  .byte   0

str_d:  PASCAL_STRING 0
str_s:  PASCAL_STRING 0
LD41D:  .byte   0
LD41E:  .byte   0
LD41F:  .byte   0
LD420:  .byte   0
LD421:  .word   0
LD423:  .byte   0
LD424:  .word   0
LD426:  .byte   0
LD427:  .word   0
LD429:  .byte   0

rect_D42A:      DEFINE_RECT 18, 20, 490, 88
rect_D432:      DEFINE_RECT 19, 29, 195, 101

LD43A:  .res 18, 0
LD44C:  .byte   0
LD44D:  .byte   0
LD44E:  .byte   0
        .byte   0
        .byte   0
LD451:  .byte   0, 1, 0

str_2_spaces:   PASCAL_STRING "  "
str_7_spaces:   PASCAL_STRING "       "

;;; Label positions
point_blocks_read:     DEFINE_POINT 300, 125
point_blocks_written:     DEFINE_POINT 300, 135
point_source:     DEFINE_POINT 300, 115
point_source2:     DEFINE_POINT 40, 125
point_slot_drive:     DEFINE_POINT 110, 125
point_destination:     DEFINE_POINT 40, 135
point_slot_drive2:     DEFINE_POINT 110, 135
point_disk_copy:     DEFINE_POINT 40, 115
point_select_quit:     DEFINE_POINT 20, 145
rect_D483:      DEFINE_RECT 20, 136, 400, 145
point_escape_stop_copy:     DEFINE_POINT 300, 145
point_error_writing:     DEFINE_POINT 40, 100
point_error_reading:     DEFINE_POINT 40, 90

slot_char:      .byte   10
drive_char:     .byte   14

str_blocks_read:
        PASCAL_STRING "Blocks Read: "
str_blocks_written:
        PASCAL_STRING "Blocks Written: "
str_blocks_to_transfer:
        PASCAL_STRING "Blocks to transfer: "
str_source:
        PASCAL_STRING "Source "
str_destination:
        PASCAL_STRING "Destination "
str_slot:
        PASCAL_STRING "Slot "
str_drive:
        PASCAL_STRING "  Drive "

str_dos33_s_d:
        PASCAL_STRING "DOS 3.3 S , D  "

str_dos33_disk_copy:
        PASCAL_STRING "DOS 3.3 disk copy"

str_pascal_disk_copy:
        PASCAL_STRING "Pascal disk copy"

str_prodos_disk_copy:
        PASCAL_STRING "ProDOS disk copy"

str_escape_stop_copy:
        PASCAL_STRING " ESC stop the copy"

str_error_writing:
        PASCAL_STRING "Error when writing block "

str_error_reading:
        PASCAL_STRING "Error when reading block "

;;; ============================================================

        ;; cursor definition - pointer
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

        ;; Cursor definition - watch
watch_cursor:
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

;;; ============================================================

LD5E0:  .byte   0
LD5E1:  jsr     LDF73
        MGTK_RELAY_CALL2 MGTK::SetMenu, menu_definition
        jsr     set_cursor_pointer
        copy16  #$0101, LD12B
        MGTK_RELAY_CALL2 MGTK::CheckItem, checkitem_params
        lda     #$01
        sta     LD129
        MGTK_RELAY_CALL2 MGTK::DisableMenu, disablemenu_params
        lda     #$00
        sta     LD451
        sta     LD5E0
        jsr     LDFA0
LD61C:  lda     #$00
        sta     LD367
        sta     LD368
        sta     LD44C
        lda     #$FF
        sta     LD363
        lda     #$81
        sta     LD44D
        lda     #$00
        sta     LD129
        MGTK_RELAY_CALL2 MGTK::DisableMenu, disablemenu_params
        lda     #$01
        sta     LD12C
        MGTK_RELAY_CALL2 MGTK::CheckItem, checkitem_params
        jsr     LDFDD
        MGTK_RELAY_CALL2 MGTK::OpenWindow, winfo_drive_select
        lda     #$00
        sta     LD429
        lda     #$FF
        sta     LD44C
        jsr     LE16C
        lda     LD5E0
        bne     LD66E
        jsr     LE3A3
LD66E:  jsr     LE28D
        inc     LD5E0
LD674:  jsr     LD986
        bmi     LD674
        beq     LD687
        MGTK_RELAY_CALL2 MGTK::CloseWindow, winfo_drive_select
        jmp     LD61C

LD687:  lda     LD363
        bmi     LD674
        lda     #$01
        sta     LD129
        MGTK_RELAY_CALL2 MGTK::DisableMenu, disablemenu_params
        lda     LD363
        sta     LD417
        lda     winfo_drive_select
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::SetPenMode, pencopy
        MGTK_RELAY_CALL2 MGTK::PaintRect, winfo_drive_select::cliprect
        lda     winfo_dialog::window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::SetPenMode, pencopy
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D255
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_select_source
        addr_call draw_text, str_select_destination
        jsr     LE559
        jsr     LE2B1
LD6E6:  jsr     LD986
        bmi     LD6E6
        beq     LD6F9
        MGTK_RELAY_CALL2 MGTK::CloseWindow, winfo_drive_select
        jmp     LD61C

LD6F9:  lda     LD363
        bmi     LD6E6
        tax
        lda     LD3FF,x
        sta     LD418
        lda     #$00
        sta     LD44C
        lda     winfo_dialog::window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::SetPenMode, pencopy
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D211
        MGTK_RELAY_CALL2 MGTK::CloseWindow, winfo_drive_select
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D432
LD734:  addr_call LEB84, $0000
        beq     LD740
        jmp     LD61C

LD740:  lda     #$00
        sta     LD44D
        ldx     LD417
        lda     LD3F7,x
        sta     disk_copy_overlay4::on_line_params2::unit_num
        jsr     disk_copy_overlay4::L1291
        beq     LD77E
        cmp     #$52
        bne     LD763
        jsr     disk_copy_overlay4::L0D5F
        jsr     LE674
        jsr     LE559
        jmp     LD7AD

LD763:  lda     winfo_dialog::window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::SetPenMode, pencopy
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D42A
        jmp     LD734

LD77E:  lda     $1300
        and     #$0F
        bne     LD798
        lda     $1301
        cmp     #$52
        bne     LD763
        jsr     disk_copy_overlay4::L0D5F
        jsr     LE674
        jsr     LE559
        jmp     LD7AD

LD798:  lda     $1300
        and     #$0F
        sta     $1300
        addr_call adjust_case, $1300
        jsr     LE674
        jsr     LE559
LD7AD:  lda     LD417
        jsr     LE3B8
        jsr     LE5E1
        jsr     LE63F
        ldx     LD418
        lda     LD3F7,x
        tay
        ldx     #$00
        lda     #$01
        jsr     LEB84
        beq     LD7CC
        jmp     LD61C

LD7CC:  ldx     LD418
        lda     LD3F7,x
        sta     disk_copy_overlay4::on_line_params2::unit_num
        jsr     disk_copy_overlay4::L1291
        beq     LD7E1
        cmp     #$52
        beq     LD7F2
        jmp     LD852

LD7E1:  lda     $1300
        and     #$0F
        bne     LD7F2
        lda     $1301
        cmp     #$52
        beq     LD7F2
        jmp     LD852

LD7F2:  ldx     LD418
        lda     LD3F7,x
        and     #$0F
        beq     LD817
        lda     LD3F7,x
        jsr     disk_copy_overlay4::L0D26
        ldy     #$FF
        lda     ($06),y
        beq     LD817
        cmp     #$FF
        beq     LD817
        ldy     #$FE
        lda     ($06),y
        and     #$08
        bne     LD817
        jmp     LD8A9

LD817:  lda     $1300
        and     #$0F
        bne     LD82C
        ldx     LD418
        lda     LD3F7,x
        and     #$F0
        tax
        lda     #$07
        jmp     LD83C

LD82C:  sta     $1300
        addr_call adjust_case, $1300
        ldx     #$00
        ldy     #$13
        lda     #$02
LD83C:  jsr     LEB84
        cmp     #$01
        beq     LD847
        cmp     #$02
        beq     LD84A
LD847:  jmp     LD61C

LD84A:  lda     LD451
        bne     LD852
        jmp     LD8A9

LD852:  ldx     LD418
        lda     LD3F7,x
        and     #$0F
        beq     LD87C
        lda     LD3F7,x
        jsr     disk_copy_overlay4::L0D26
        ldy     #$FE
        lda     ($06),y
        and     #$08
        bne     LD87C
        ldy     #$FF
        lda     ($06),y
        beq     LD87C
        cmp     #$FF
        beq     LD87C
        lda     #$03
        jsr     LEB84
        jmp     LD61C

LD87C:  MGTK_RELAY_CALL2 MGTK::MoveTo, point_formatting
        addr_call draw_text, str_formatting
        jsr     disk_copy_overlay4::L0CAF
        bcc     LD8A9
        cmp     #$2B
        beq     LD89F
        lda     #$04
        jsr     LEB84
        beq     LD852
        jmp     LD61C

LD89F:  lda     #$05
        jsr     LEB84
        beq     LD852
        jmp     LD61C

LD8A9:  lda     winfo_dialog::window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::SetPenMode, pencopy
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D211
        lda     LD417
        cmp     LD418
        bne     LD8DF
        tax
        lda     LD3F7,x
        pha
        jsr     disk_copy_overlay4::eject_disk
        pla
        tay
        ldx     #$80
        lda     #$00
        jsr     LEB84
        beq     LD8DF
        jmp     LD61C

LD8DF:  jsr     disk_copy_overlay4::L0DB5
        lda     #$00
        sta     LD421
        sta     LD421+1
        lda     #$07
        sta     LD423
        jsr     LE4BF
        jsr     LE4EC
        jsr     LE507
        jsr     LE694
LD8FB:  jsr     LE4A8
        lda     #$00
        jsr     disk_copy_overlay4::L0ED7
        cmp     #$01
        beq     LD97A
        jsr     LE4EC
        lda     LD417
        cmp     LD418
        bne     LD928
        tax
        lda     LD3F7,x
        pha
        jsr     disk_copy_overlay4::eject_disk
        pla
        tay
        ldx     #$80
        lda     #$01
        jsr     LEB84
        beq     LD928
        jmp     LD61C

LD928:  jsr     LE491
        lda     #$80
        jsr     disk_copy_overlay4::L0ED7
        bmi     LD955
        bne     LD97A
        jsr     LE507
        lda     LD417
        cmp     LD418
        bne     LD8FB
        tax
        lda     LD3F7,x
        pha
        jsr     disk_copy_overlay4::eject_disk
        pla
        tay
        ldx     #$80
        lda     #$00
        jsr     LEB84
        beq     LD8FB
        jmp     LD61C

LD955:  jsr     LE507
        jsr     disk_copy_overlay4::L10FB
        ldx     LD417
        lda     LD3F7,x
        jsr     disk_copy_overlay4::eject_disk
        ldx     LD418
        cpx     LD417
        beq     LD972
        lda     LD3F7,x
        jsr     disk_copy_overlay4::eject_disk
LD972:  lda     #$09
        jsr     LEB84
        jmp     LD61C

LD97A:  jsr     disk_copy_overlay4::L10FB
        lda     #$0A
        jsr     LEB84
        jmp     LD61C

        .byte   0
LD986:  MGTK_RELAY_CALL2 MGTK::InitPort, grafport
        MGTK_RELAY_CALL2 MGTK::SetPort, grafport
LD998:  bit     LD368
        bpl     LD9A7
        dec     LD367
        bne     LD9A7
        lda     #$00
        sta     LD368
LD9A7:  MGTK_RELAY_CALL2 MGTK::GetEvent, event_params
        lda     event_kind
        cmp     #MGTK::EventKind::button_down
        bne     LD9BA
        jmp     LDAB1

LD9BA:  cmp     #MGTK::EventKind::key_down
        bne     LD998
        jmp     LD9D5

LD9C1:  .addr   disk_copy_overlay4::just_rts
        .addr   disk_copy_overlay4::just_rts
        .addr   disk_copy_overlay4::just_rts
        .addr   disk_copy_overlay4::just_rts
        .addr   disk_copy_overlay4::just_rts
        .addr   disk_copy_overlay4::quit
        .addr   LDA3C
        .addr   LDA77

LD9D1:  .byte   0, $A, $C, $10

LD9D5:  lda     event_modifiers
        bne     LD9E6
        lda     event_key
        and     #CHAR_MASK
        cmp     #CHAR_ESCAPE
        beq     LD9E6
        jmp     LDBFC

LD9E6:  lda     #$01
        sta     LD12F
        lda     event_key
        sta     menukey_params::which_key
        lda     event_modifiers
        sta     menukey_params::key_mods
        MGTK_RELAY_CALL2 MGTK::MenuKey, menukey_params
LDA00:  ldx     menukey_params::menu_id
        bne     LDA06
        rts

LDA06:  dex
        lda     LD9D1,x
        tax
        ldy     $D00D
        dey
        tya
        asl     a
        sta     jump_addr
        txa
        clc
        adc     jump_addr
        tax
        copy16  LD9C1,x, jump_addr
        jsr     LDA35
        MGTK_RELAY_CALL2 MGTK::HiliteMenu, hilitemenu_params
        jmp     LD986

LDA35:  tsx
        stx     LD00B
        jump_addr := *+1
        jmp     dummy1234

LDA3C:  lda     LD451
        bne     LDA42
        rts

LDA42:  lda     #$00
        sta     LD12C
        MGTK_RELAY_CALL2 MGTK::CheckItem, checkitem_params
        lda     LD451
        sta     LD12B
        lda     #$01
        sta     LD12C
        MGTK_RELAY_CALL2 MGTK::CheckItem, checkitem_params
        lda     #$00
        sta     LD451
        lda     winfo_dialog::window_id
        jsr     LE137
        addr_call LE0B4, str_quick_copy_padded
        rts

LDA77:  lda     LD451
        beq     LDA7D
        rts

LDA7D:  lda     #$00
        sta     LD12C
        MGTK_RELAY_CALL2 MGTK::CheckItem, checkitem_params
        copy16  #$0102, LD12B
        MGTK_RELAY_CALL2 MGTK::CheckItem, checkitem_params
        lda     #$01
        sta     LD451
        lda     winfo_dialog::window_id
        jsr     LE137
        addr_call LE0B4, str_disk_copy_padded
        rts

LDAB1:  MGTK_RELAY_CALL2 MGTK::FindWindow, event_xcoord
        lda     findwindow_which_area
        bne     LDAC0
        rts

LDAC0:  cmp     #$01
        bne     LDAD0
        MGTK_RELAY_CALL2 MGTK::MenuSelect, menuselect_params
        jmp     LDA00

LDAD0:  cmp     #$02
        bne     LDAD7
        jmp     LDADA

LDAD7:  return  #$FF

LDADA:  lda     LD133
        cmp     winfo_dialog::window_id
        bne     LDAE5
        jmp     LDAEE

LDAE5:  cmp     winfo_drive_select
        bne     LDAED
        jmp     LDB55

LDAED:  rts

LDAEE:  lda     winfo_dialog::window_id
        sta     screentowindow_window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::ScreenToWindow, screentowindow_params
        MGTK_RELAY_CALL2 MGTK::MoveTo, screentowindow_windowx
        MGTK_RELAY_CALL2 MGTK::InRect, rect_D221
        cmp     #MGTK::inrect_inside
        beq     LDB19
        jmp     LDB2F

LDB19:  MGTK_RELAY_CALL2 MGTK::SetPenMode, penXOR
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D221
        jsr     LDD38
        rts

LDB2F:  MGTK_RELAY_CALL2 MGTK::InRect, rect_D229
        cmp     #MGTK::inrect_inside
        bne     LDB52
        MGTK_RELAY_CALL2 MGTK::SetPenMode, penXOR
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D229
        jsr     LDCAC
        rts

LDB52:  return  #$FF

LDB55:  lda     winfo_drive_select
        sta     screentowindow_window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::ScreenToWindow, screentowindow_params
        MGTK_RELAY_CALL2 MGTK::MoveTo, screentowindow_windowx
        lsr16   screentowindow_windowy
        lsr16   screentowindow_windowy
        lsr16   screentowindow_windowy
        lda     screentowindow_windowy
        cmp     LD375
        bcc     LDB98
        lda     LD363
        jsr     LE14D
        lda     #$FF
        sta     LD363
        jmp     LDBCA

LDB98:  cmp     LD363
        bne     LDBCD
        bit     LD368
        bpl     LDBC0
        MGTK_RELAY_CALL2 MGTK::SetPenMode, penXOR
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D221
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D221
        return  #$00

LDBC0:  lda     #$FF
        sta     LD368
        lda     #$64
        sta     LD367
LDBCA:  return  #$FF

LDBCD:  pha
        lda     LD363
        bmi     LDBD6
        jsr     LE14D
LDBD6:  pla
        sta     LD363
        jsr     LE14D
        jmp     LDBC0

.proc MGTK_RELAY2
        sty     LDBF2
        stax    LDBF3
        sta     RAMRDON
        sta     RAMWRTON
        jsr     MGTK::MLI
LDBF2:  .byte   0
LDBF3:  .addr   0
        sta     RAMRDOFF
        sta     RAMWRTOFF
        rts
.endproc

LDBFC:  lda     event_key
        and     #CHAR_MASK
        cmp     #'D'
        beq     LDC09
        cmp     #'d'
        bne     LDC2D
LDC09:  lda     winfo_dialog::window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::SetPenMode, penXOR
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D229
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D229
        return  #$01

LDC2D:  cmp     #CHAR_RETURN
        bne     LDC55
        lda     winfo_dialog::window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::SetPenMode, penXOR
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D221
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D221
        return  #$00

LDC55:  bit     LD44C
        bmi     LDC5D
        jmp     LDCA9

LDC5D:  cmp     #CHAR_DOWN
        bne     LDC85
        lda     winfo_drive_select
        jsr     LE137
        lda     LD363
        bmi     LDC6F
        jsr     LE14D
LDC6F:  inc     LD363
        lda     LD363
        cmp     LD375
        bcc     LDC7F
        lda     #$00
        sta     LD363
LDC7F:  jsr     LE14D
        jmp     LDCA9

LDC85:  cmp     #CHAR_UP
        bne     LDCA9
        lda     winfo_drive_select
        jsr     LE137
        lda     LD363
        bmi     LDC9C
        jsr     LE14D
        dec     LD363
        bpl     LDCA3
LDC9C:  ldx     LD375
        dex
        stx     LD363
LDCA3:  lda     LD363
        jsr     LE14D
LDCA9:  return  #$FF

LDCAC:  lda     #$00
        sta     LDD37
LDCB1:  MGTK_RELAY_CALL2 MGTK::GetEvent, event_params
        lda     event_kind
        cmp     #MGTK::EventKind::button_up
        beq     LDD14
        lda     winfo_dialog::window_id
        sta     screentowindow_window_id
        MGTK_RELAY_CALL2 MGTK::ScreenToWindow, screentowindow_params
        MGTK_RELAY_CALL2 MGTK::MoveTo, screentowindow_windowx
        MGTK_RELAY_CALL2 MGTK::InRect, rect_D229
        cmp     #MGTK::inrect_inside
        beq     LDCEE
        lda     LDD37
        beq     LDCF6
        jmp     LDCB1

LDCEE:  lda     LDD37
        bne     LDCF6
        jmp     LDCB1

LDCF6:  MGTK_RELAY_CALL2 MGTK::SetPenMode, penXOR
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D229
        lda     LDD37
        clc
        adc     #$80
        sta     LDD37
        jmp     LDCB1

LDD14:  lda     LDD37
        beq     LDD1C
        return  #$FF

LDD1C:  lda     winfo_dialog::window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::SetPenMode, penXOR
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D229
        return  #$01

LDD37:  .byte   0
LDD38:  lda     #$00
        sta     LDDC3
LDD3D:  MGTK_RELAY_CALL2 MGTK::GetEvent, event_params
        lda     event_kind
        cmp     #MGTK::EventKind::button_up
        beq     LDDA0
        lda     winfo_dialog::window_id
        sta     screentowindow_window_id
        MGTK_RELAY_CALL2 MGTK::ScreenToWindow, screentowindow_params
        MGTK_RELAY_CALL2 MGTK::MoveTo, screentowindow_windowx
        MGTK_RELAY_CALL2 MGTK::InRect, rect_D221
        cmp     #MGTK::inrect_inside
        beq     LDD7A
        lda     LDDC3
        beq     LDD82
        jmp     LDD3D

LDD7A:  lda     LDDC3
        bne     LDD82
        jmp     LDD3D

LDD82:  MGTK_RELAY_CALL2 MGTK::SetPenMode, penXOR
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D221
        lda     LDDC3
        clc
        adc     #$80
        sta     LDDC3
        jmp     LDD3D

LDDA0:  lda     LDDC3
        beq     LDDA8
        return  #$FF

LDDA8:  lda     winfo_dialog::window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::SetPenMode, penXOR
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D221
        return  #$00

LDDC3:  .byte   0

;;; ============================================================

.proc set_cursor_watch
        MGTK_RELAY_CALL2 MGTK::HideCursor
        MGTK_RELAY_CALL2 MGTK::SetCursor, watch_cursor
        MGTK_RELAY_CALL2 MGTK::ShowCursor
        rts
.endproc

;;; ============================================================

.proc set_cursor_pointer
        MGTK_RELAY_CALL2 MGTK::HideCursor
        MGTK_RELAY_CALL2 MGTK::SetCursor, pointer_cursor
        MGTK_RELAY_CALL2 MGTK::ShowCursor
        rts
.endproc

;;; ============================================================

LDDFC:  sta     disk_copy_overlay4::block_params::unit_num
        lda     #$00
        sta     disk_copy_overlay4::block_params::block_num
        sta     disk_copy_overlay4::block_params::block_num+1
        copy16  #$1C00, disk_copy_overlay4::block_params::data_buffer
        jsr     disk_copy_overlay4::L12AF
        beq     LDE19
        return  #$FF

LDE19:  lda     $1C01
        cmp     #$E0
        beq     LDE23
        jmp     LDE4D

LDE23:  lda     $1C02
        cmp     #$70
        beq     LDE31
        cmp     #$60
        beq     LDE31
LDE2E:  return  #$FF

LDE31:  lda     LD375
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #<LD377
        tay
        lda     #>LD377
        adc     #0
        tax
        tya
        jsr     LDE9F
        lda     #$80
        sta     LD44E
        return  #$00

LDE4D:  cmp     #$A5
        bne     LDE2E
        lda     $1C02
        cmp     #$27
        bne     LDE2E
        lda     disk_copy_overlay4::block_params::unit_num
        and     #$70
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     #'0'
        ldx     slot_char
        sta     str_dos33_s_d,x
        lda     disk_copy_overlay4::block_params::unit_num
        and     #$80
        asl     a
        rol     a
        adc     #$31
        ldx     drive_char
        sta     str_dos33_s_d,x
        lda     LD375
        asl     a
        asl     a
        asl     a
        asl     a
        tay
        ldx     #$00
LDE83:  lda     str_dos33_s_d,x
        sta     LD377,y
        iny
        inx
        cpx     str_dos33_s_d
        bne     LDE83
        lda     str_dos33_s_d,x
        sta     LD377,y
        lda     #$43
        sta     $0300
        return  #$00

        .byte   0
LDE9F:  stax    $06
        copy16  #$0002, disk_copy_overlay4::block_params::block_num
        jsr     disk_copy_overlay4::L12AF
        beq     LDEBE
        ldy     #$00
        lda     #$01
        sta     ($06),y
        iny
        lda     #$20
        sta     ($06),y
        rts

LDEBE:  ldy     #$00
        ldx     #$00
LDEC2:  lda     $1C06,x
        sta     ($06),y
        inx
        iny
        cpx     $1C06
        bne     LDEC2
        lda     $1C06,x
        sta     ($06),y
        lda     $1C06
        cmp     #$0F
        bcs     LDEE6
        ldy     #$00
        lda     ($06),y
        clc
        adc     #$01
        sta     ($06),y
        lda     ($06),y
        tay
LDEE6:  lda     #$3A
        sta     ($06),y
        rts

LDEEB:  stax    LDF6F
        ldx     #$07
        lda     #$20
LDEF5:  sta     str_7_spaces,x
        dex
        bne     LDEF5
        lda     #$00
        sta     LDF72
        ldy     #$00
        ldx     #$00
LDF04:  lda     #$00
        sta     LDF71
LDF09:  lda     LDF6F
        cmp     LDF67,x
        lda     LDF70
        sbc     LDF68,x
        bpl     LDF45
        lda     LDF71
        bne     LDF25
        bit     LDF72
        bmi     LDF25
        lda     #$20
        bne     LDF38
LDF25:  cmp     #$0A
        bcc     LDF2F
        clc
        adc     #$37
        jmp     LDF31

LDF2F:  adc     #'0'
LDF31:  pha
        lda     #$80
        sta     LDF72
        pla
LDF38:  sta     str_7_spaces+2,y
        iny
        inx
        inx
        cpx     #$08
        beq     LDF5E
        jmp     LDF04

LDF45:  inc     LDF71
        lda     LDF6F
        sec
        sbc     LDF67,x
        sta     LDF6F
        lda     LDF70
        sbc     LDF68,x
        sta     LDF70
        jmp     LDF09

LDF5E:  lda     LDF6F
        ora     #'0'
        sta     str_7_spaces+2,y
        rts

LDF67:  .byte   $10
LDF68:  .byte   $27
        inx
        .byte   $03
        .byte   $64
        .byte   0
        asl     a
        .byte   0
LDF6F:  .byte   0
LDF70:  .byte   0
LDF71:  .byte   0
LDF72:  .byte   0
LDF73:  ldx     DEVCNT
LDF76:  lda     DEVLST,x
        cmp     #$BF
        beq     LDF81
        dex
        bpl     LDF76
        rts

LDF81:  lda     DEVLST+1,x
        sta     DEVLST,x
        cpx     DEVCNT
        beq     LDF90
        inx
        jmp     LDF81

LDF90:  dec     DEVCNT
        rts

LDF94:  inc     DEVCNT
        ldx     DEVCNT
        lda     #$BF
        sta     DEVLST,x
        rts

LDFA0:  MGTK_RELAY_CALL2 MGTK::OpenWindow, winfo_dialog
        lda     winfo_dialog::window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::SetPenMode, penXOR
        MGTK_RELAY_CALL2 MGTK::FrameRect, rect_outer_frame
        MGTK_RELAY_CALL2 MGTK::FrameRect, rect_inner_frame

        MGTK_RELAY_CALL2 MGTK::InitPort, grafport
        MGTK_RELAY_CALL2 MGTK::SetPort, grafport
        rts

LDFDD:  lda     winfo_dialog::window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::SetPenMode, pencopy
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D211
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D219
        lda     LD451
        bne     LE00D
        addr_call LE0B4, str_quick_copy_padded
        jmp     LE014

LE00D:  addr_call LE0B4, str_disk_copy_padded
LE014:  MGTK_RELAY_CALL2 MGTK::SetPenMode, penXOR
        MGTK_RELAY_CALL2 MGTK::FrameRect, rect_D221
        MGTK_RELAY_CALL2 MGTK::FrameRect, rect_D229
        jsr     LE078
        jsr     LE089
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_slot_drive_name
        addr_call draw_text, str_slot_drive_name
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_select_source
        addr_call draw_text, str_select_source
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_select_quit
        addr_call draw_text, str_select_quit

        MGTK_RELAY_CALL2 MGTK::InitPort, grafport
        MGTK_RELAY_CALL2 MGTK::SetPort, grafport
        rts

LE078:  MGTK_RELAY_CALL2 MGTK::MoveTo, point_ok_label
        addr_call draw_text, str_ok_label
        rts

LE089:  MGTK_RELAY_CALL2 MGTK::MoveTo, point_read_drive
        addr_call draw_text, str_read_drive
        rts

.proc draw_text
        ptr := $0A

        stax    ptr
        ldy     #$00
        lda     (ptr),y
        sta     ptr+2
        inc16   ptr
        MGTK_RELAY_CALL2 MGTK::DrawText, ptr
        rts
.endproc

LE0B4:  stax    $06
        ldy     #$00
        lda     ($06),y
        sta     $08
        inc16   $06
        MGTK_RELAY_CALL2 MGTK::TextWidth, $06
        lsr16   $09
        lda     #>500
        sta     LE0FD
        lda     #<500
        lsr     LE0FD
        ror     a
        sec
        sbc     $09
        sta     point_D249
        lda     LE0FD
        sbc     $09+1
        sta     point_D249+1
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_D249
        MGTK_RELAY_CALL2 MGTK::DrawText, $06
        rts

LE0FD:  .byte   0

;;; ============================================================

.proc adjust_case
        ptr := $A

        stx     ptr+1
        sta     ptr
        ldy     #0
        lda     (ptr),y
        tay
        bne     next
        rts

next:   dey
        beq     done
        bpl     :+
done:   rts

:       lda     (ptr),y
        and     #CHAR_MASK      ; convert to ASCII
        cmp     #'/'
        beq     skip
        cmp     #'.'
        bne     check_alpha
skip:   dey
        jmp     next

check_alpha:
        iny
        lda     (ptr),y
        and     #CHAR_MASK
        cmp     #'A'
        bcc     :+
        cmp     #'Z'+1
        bcs     :+
        clc
        adc     #('a' - 'A')    ; convert to lower case
        sta     (ptr),y
:       dey
        jmp     next
.endproc

;;; ============================================================

        .byte   0
LE137:  sta     getwinport_params::window_id
        MGTK_RELAY_CALL2 MGTK::GetWinPort, getwinport_params
        MGTK_RELAY_CALL2 MGTK::SetPort, grafport_win
        rts

LE14D:  asl     a               ; * 8
        asl     a
        asl     a
        sta     rect_D35B::y1
        clc
        adc     #7
        sta     rect_D35B::y2
        MGTK_RELAY_CALL2 MGTK::SetPenMode, penXOR
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D35B
        rts

LE16C:  lda     #$00
        sta     LD44E
        sta     disk_copy_overlay4::on_line_params2::unit_num
        jsr     disk_copy_overlay4::L1291
        beq     LE17A
        .byte   0
LE17A:  lda     #$00
        sta     LE263
        sta     LD375
LE182:  lda     #$13
        sta     $07
        lda     #$00
        sta     $06
        sta     LE264
        lda     LE263
        asl     a
        rol     LE264
        asl     a
        rol     LE264
        asl     a
        rol     LE264
        asl     a
        rol     LE264
        clc
        adc     $06
        sta     $06
        lda     LE264
        adc     $07
        sta     $07
        ldy     #$00
        lda     ($06),y
        and     #$0F
        bne     LE20D
        lda     ($06),y
        beq     LE1CC
        iny
        lda     ($06),y
        cmp     #$28
        bne     LE1CD
        dey
        lda     ($06),y
        jsr     LE265
        lda     #$28
        bcc     LE1CD
        jmp     LE255

LE1CC:  rts

LE1CD:  pha
        ldy     #$00
        lda     ($06),y
        jsr     LE285
        ldx     LD375
        sta     LD3F7,x
        pla
        cmp     #$52
        bne     LE1EA
        lda     LD3F7,x
        and     #$F0
        jsr     LDDFC
        beq     LE207
LE1EA:  lda     LD375
        asl     a
        asl     a
        asl     a
        asl     a
        tay
        ldx     #$00
LE1F4:  lda     str_unknown,x
        sta     LD377,y
        iny
        inx
        cpx     str_unknown
        bne     LE1F4
        lda     str_unknown,x
        sta     LD377,y
LE207:  inc     LD375
        jmp     LE255

LE20D:  ldx     LD375
        ldy     #$00
        lda     ($06),y
        and     #$70
        cmp     #$30
        bne     LE21D
        jmp     LE255

LE21D:  ldy     #$00
        lda     ($06),y
        jsr     LE285
        ldx     LD375
        sta     LD3F7,x
        lda     LD375
        asl     a
        asl     a
        asl     a
        asl     a
        tax
        ldy     #$00
        lda     ($06),y
        and     #$0F
        sta     LD377,x
        sta     LE264
LE23E:  inx
        iny
        cpy     LE264
        beq     LE24D
        lda     ($06),y
        sta     LD377,x
        jmp     LE23E

LE24D:  lda     ($06),y
        sta     LD377,x
        inc     LD375
LE255:  inc     LE263
        lda     LE263
        cmp     #$08
        beq     LE262
        jmp     LE182

LE262:  rts

LE263:  .byte   0
LE264:  .byte   0
LE265:  and     #$F0
        sta     LE28C
        ldx     DEVCNT
LE26D:  lda     DEVLST,x
        and     #$F0
        cmp     LE28C
        beq     LE27C
        dex
        bpl     LE26D
LE27A:  sec
        rts

LE27C:  lda     DEVLST,x
        and     #$0F
        bne     LE27A
        clc
        rts

LE285:  jsr     LE265
        lda     DEVLST,x
        rts

LE28C:  .byte   0
LE28D:  lda     winfo_drive_select
        jsr     LE137
        lda     #$00
        sta     LE2B0
LE298:  lda     LE2B0
        jsr     LE39A
        lda     LE2B0
        jsr     LE31B
        inc     LE2B0
        lda     LE2B0
        cmp     LD375
        bne     LE298
        rts

LE2B0:  .byte   0
LE2B1:  lda     winfo_drive_select
        jsr     LE137
        lda     LD363
        asl     a
        tax
        lda     LD407,x
        sta     LE318
        lda     LD407+1,x
        sta     LE319
        lda     LD375
        sta     LD376
        lda     #$00
        sta     LD375
        sta     LE317
LE2D6:  lda     LE317
        asl     a
        tax
        lda     LD407,x
        cmp     LE318
        bne     LE303
        lda     LD407+1,x
        cmp     LE319
        bne     LE303
        lda     LE317
        ldx     LD375
        sta     LD3FF,x
        lda     LD375
        jsr     LE39A
        lda     LE317
        jsr     LE31B
        inc     LD375
LE303:  inc     LE317
        lda     LE317
        cmp     LD376
        beq     LE311
        jmp     LE2D6

LE311:  lda     #$FF
        sta     LD363
        rts

LE317:  .byte   0
LE318:  .byte   0
LE319:  .byte   0
        .byte   0
LE31B:  sta     LE399
        lda     #8
        sta     point_D36D::xcoord
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_D36D
        ldx     LE399
        lda     LD3F7,x
        and     #$70
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     #'0'
        sta     str_s + 1
        addr_call draw_text, str_s
        lda     #40
        sta     point_D36D::xcoord
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_D36D
        ldx     LE399
        lda     LD3F7,x
        and     #$80
        asl     a
        rol     a
        clc
        adc     #'1'
        sta     str_d + 1
        addr_call draw_text, str_d
        lda     #65
        sta     point_D36D::xcoord
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_D36D
        lda     LE399
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #$77
        sta     $06
        lda     #$D3
        adc     #$00
        sta     $07
        lda     $06
        ldx     $07
        jsr     adjust_case
        lda     $06
        ldx     $07
        jsr     draw_text
        rts

LE399:  .byte   0
LE39A:  asl     a
        asl     a
        asl     a
        adc     #8
        sta     point_D36D::ycoord
        rts

LE3A3:  lda     #$00
        sta     LE3B7
LE3A8:  jsr     LE3B8
        inc     LE3B7
        lda     LE3B7
        cmp     LD375
        bne     LE3A8
        rts

LE3B7:  .byte   0
LE3B8:  pha
        tax
        lda     LD3F7,x
        and     #$0F
        beq     LE3CC
        lda     LD3F7,x
        and     #$F0
        jsr     disk_copy_overlay4::L0D26
        jmp     LE3DA

LE3CC:  pla
        asl     a
        tax
        lda     #$18
        sta     LD407,x
        lda     #$01
        sta     LD407+1,x
        rts

LE3DA:  ldy     #$07
        lda     ($06),y
        bne     LE3E3
        jmp     LE44A

LE3E3:  lda     #$00
        sta     LE448
        ldy     #$FC
        lda     ($06),y
        sta     LE449
        beq     LE3F6
        lda     #$80
        sta     LE448
LE3F6:  ldy     #$FD
        lda     ($06),y
        tax
        bne     LE402
        bit     LE448
        bpl     LE415
LE402:  stx     LE448
        pla
        asl     a
        tax
        lda     LE448
        sta     LD407,x
        lda     LE449
        sta     LD407+1,x
        rts

LE415:  ldy     #$FF
        lda     ($06),y
        sta     $06
        lda     #$00
        sta     $42
        sta     $44
        sta     $45
        sta     $46
        sta     $47
        pla
        pha
        tax
        lda     LD3F7,x
        and     #$F0
        sta     $43
        jsr     LE445
        stx     LE448
        pla
        asl     a
        tax
        lda     LE448
        sta     LD407,x
        tya
        sta     LD407+1,x
        rts

LE445:  jmp     ($06)

LE448:  .byte   0
LE449:  .byte   0
LE44A:  ldy     #$FF
        lda     ($06),y
        clc
        adc     #$03
        sta     $06
        pla
        pha
        tax
        lda     LD3F7,x
        and     #$F0
        jsr     disk_copy_overlay4::L0D51
        sta     LE47D
        jsr     indirect_jump
        .byte   0
        .byte   $7C
        cpx     $68
        asl     a
        tax
        lda     LE482
        sta     LD407,x
        lda     LE483
        sta     LD407+1,x
        rts

indirect_jump:
        jmp     ($06)

        ;; TODO: Identify data
        .byte   0
        .byte   0
        .byte   $03
LE47D:  .byte   1, $81
        .byte   $E4, 0
        .byte   0
LE482:  .byte   0
LE483:  .byte   0
        .byte   0
        .byte   0
        .byte   0
        .byte   0
        .byte   0
        .byte   0
        .byte   0
        .byte   0
        .byte   0
        .byte   0
        .byte   0
        .byte   0
        .byte   0

LE491:  lda     winfo_dialog::window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_writing
        addr_call draw_text, str_writing
        rts

LE4A8:  lda     winfo_dialog::window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_reading
        addr_call draw_text, str_reading
        rts

LE4BF:  lda     winfo_dialog::window_id
        jsr     LE137
        lda     LD417
        asl     a
        tay
        lda     LD407+1,y
        tax
        lda     LD407,y
        jsr     LDEEB
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_source
        addr_call draw_text, str_blocks_to_transfer
        addr_call draw_text, str_7_spaces
        rts

LE4EC:  jsr     LE522
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_blocks_read
        addr_call draw_text, str_blocks_read
        .byte   $A9
LE500:  .byte   $57
        ldx     #$D4
        jsr     draw_text
        rts

LE507:  jsr     LE522
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_blocks_written
        addr_call draw_text, str_blocks_written
        addr_call draw_text, str_7_spaces
        rts

LE522:  lda     winfo_dialog::window_id
        jsr     LE137
        lda     LD421+1
        sta     LE558
        lda     LD421
        asl     a
        rol     LE558
        asl     a
        rol     LE558
        asl     a
        rol     LE558
        ldx     LD423
        clc
        adc     LE550,x
        tay
        lda     LE558
        adc     #$00
        tax
        tya
        jsr     LDEEB
        rts

LE550:  .byte   7,6,5,4,3,2,1,0

LE558:  .byte   0
LE559:  lda     winfo_dialog::window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_source2
        addr_call draw_text, str_source
        ldx     LD417
        lda     LD3F7,x
        and     #$70
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     #'0'
        sta     str_s + 1
        ldx     LD417
        lda     LD3F7,x
        and     #$80
        clc
        rol     a
        rol     a
        clc
        adc     #'1'
        sta     str_d + 1
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_slot_drive
        addr_call draw_text, str_slot
        addr_call draw_text, str_s
        addr_call draw_text, str_drive
        addr_call draw_text, str_d
        bit     LD44D
        bpl     LE5C6
        bvc     LE5C5
        lda     LD44D
        and     #$0F
        beq     LE5C6
LE5C5:  rts

LE5C6:  addr_call draw_text, str_2_spaces
        ldx     $1300
LE5D0:  lda     $1300,x
        sta     LD43A,x
        dex
        bpl     LE5D0
        addr_call draw_text, LD43A
        rts

LE5E1:  lda     winfo_dialog::window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_destination
        addr_call draw_text, str_destination
        ldx     LD418
        lda     LD3F7,x
        and     #$70
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     #'0'
        sta     str_s + 1
        ldx     LD418
        lda     LD3F7,x
        and     #$80
        asl     a
        rol     a
        clc
        adc     #'1'
        sta     str_d + 1
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_slot_drive2
        addr_call draw_text, str_slot
        addr_call draw_text, str_s
        addr_call draw_text, str_drive
        addr_call draw_text, str_d
        rts

LE63F:  lda     winfo_dialog::window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_disk_copy
        bit     LD44D
        bmi     LE65B
        addr_call draw_text, str_prodos_disk_copy
        rts

LE65B:  bvs     LE665
        addr_call draw_text, str_dos33_disk_copy
        rts

LE665:  lda     LD44D
        and     #$0F
        bne     LE673
        addr_call draw_text, str_pascal_disk_copy
LE673:  rts

LE674:  lda     LD44D
        cmp     #$C0
        beq     LE693
        lda     winfo_dialog::window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::SetPenMode, pencopy
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_D483
LE693:  rts

LE694:  lda     winfo_dialog::window_id
        jsr     LE137
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_escape_stop_copy
        addr_call draw_text, str_escape_stop_copy
        rts

LE6AB:  lda     winfo_dialog::window_id
        jsr     LE137
        copy16  #$800A, LE6FB
LE6BB:  dec     LE6FB
        beq     LE6F1
        lda     LE6FC
        eor     #$80
        sta     LE6FC
        beq     LE6D5
        MGTK_RELAY_CALL2 MGTK::SetTextBG, bg_white
        beq     LE6DE
LE6D5:  MGTK_RELAY_CALL2 MGTK::SetTextBG, bg_black
LE6DE:  MGTK_RELAY_CALL2 MGTK::MoveTo, point_escape_stop_copy
        addr_call draw_text, str_escape_stop_copy
        jmp     LE6BB

LE6F1:  MGTK_RELAY_CALL2 MGTK::SetTextBG, bg_white
        rts

LE6FB:  .byte   0
LE6FC:  .byte   0
LE6FD:  stx     LE765

        cmp     #$2B
        bne     LE71A
        jsr     disk_copy_overlay4::L127E
        lda     #$05
        jsr     LEB84
        bne     LE714
        jsr     LE491
        return  #$01

LE714:  jsr     disk_copy_overlay4::L10FB
        return  #$80

LE71A:  jsr     disk_copy_overlay4::L127E
        lda     winfo_dialog::window_id
        jsr     LE137
        lda     disk_copy_overlay4::block_params::block_num
        ldx     disk_copy_overlay4::block_params::block_num+1
        jsr     LDEEB
        lda     LE765
        bne     LE74B
        MGTK_RELAY_CALL2 MGTK::MoveTo, point_error_reading
        addr_call draw_text, str_error_reading
        addr_call draw_text, str_7_spaces
        return  #$00

LE74B:  MGTK_RELAY_CALL2 MGTK::MoveTo, point_error_writing
        addr_call draw_text, str_error_writing
        addr_call draw_text, str_7_spaces
        return  #$00

LE765:  .byte   0
LE766:  sta     $06
        sta     $08
        stx     $07
        stx     $09
        inc     $09
        copy16  #$1C00, disk_copy_overlay4::block_params::data_buffer
LE77A:  jsr     disk_copy_overlay4::L12AF
        beq     LE789
        ldx     #$00
        jsr     LE6FD
        beq     LE789
        bpl     LE77A
        rts

LE789:  sta     RAMRDOFF
        sta     RAMWRTON
        ldy     #$FF
        iny
LE792:  lda     $1C00,y
        sta     ($06),y
        lda     $1D00,y
        sta     ($08),y
        iny
        bne     LE792
        sta     RAMRDOFF
        sta     RAMWRTOFF
        lda     #$00
        rts

LE7A8:  sta     $06
        sta     $08
        stx     $07
        stx     $09
        inc     $09
        copy16  #$1C00, disk_copy_overlay4::block_params::data_buffer
        .byte   $8D
        .byte   $03
        cpy     #$8D
        .byte   $04
        cpy     #$A0
        .byte   $FF
        iny
LE7C5:  lda     ($06),y
        sta     $1C00,y
        lda     ($08),y
        sta     $1D00,y
        iny
        bne     LE7C5
        sta     RAMRDOFF
        sta     RAMWRTOFF
LE7D8:  jsr     disk_copy_overlay4::L12A5
        beq     LE7E6
        ldx     #$80
        jsr     LE6FD
        beq     LE7E6
        bpl     LE7D8
LE7E6:  rts

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

.proc alert_bitmap_mapinfo
viewloc:        DEFINE_POINT 20, 8
mapbits:        .addr   alert_bitmap
mapwidth:       .byte   7
reserved:       .byte   0
maprect:        DEFINE_RECT 0, 0, 36, 23
.endproc

rect_E89F:      DEFINE_RECT 65, 45, 485, 100
rect_E8A7:      DEFINE_RECT 4, 2, 416, 53
rect_E8AF:      DEFINE_RECT 5, 3, 415, 52

.proc portbits1
viewloc:        DEFINE_POINT 65, 45, viewloc
mapbits:        .addr   MGTK::screen_mapbits
mapwidth:       .byte   MGTK::screen_mapwidth
reserved:       .byte   0
maprect:        DEFINE_RECT 0, 0, 420, 55
.endproc

.proc portbits2
viewloc:        DEFINE_POINT 0, 0
mapbits:        .addr   MGTK::screen_mapbits
mapwidth:       .byte   MGTK::screen_mapwidth
reserved:       .byte   0
maprect:        DEFINE_RECT 0, 0, 559, 191
.endproc

str_ok_btn:
        PASCAL_STRING {"OK            ",GLYPH_RETURN}

str_cancel_btn:
        PASCAL_STRING "Cancel     Esc"

str_try_again_btn:
        PASCAL_STRING "Try Again     A"

str_yes_btn:
        PASCAL_STRING "Yes"

str_no_btn:
        PASCAL_STRING "No"

yes_rect:  DEFINE_RECT 250, 37, 300, 48
yes_pos:  DEFINE_POINT 255, 47

no_rect:  DEFINE_RECT 350, 37, 400, 48
no_pos:  DEFINE_POINT 355, 47

ok_try_again_rect:  DEFINE_RECT 300, 37, 400, 48
ok_try_again_pos:  DEFINE_POINT 305, 47

cancel_rect:  DEFINE_RECT 20, 37, 120, 48
cancel_pos:  DEFINE_POINT 25, 47

LE93D:  DEFINE_POINT 100, 24

LE941:  .byte   0
LE942:  .addr   0

str_insert_source:
        PASCAL_STRING "Insert source disk and click OK."
str_insert_dest:
        PASCAL_STRING "Insert destination disk and click OK."
str_confirm_erase0:
        PASCAL_STRING "Do you want to erase "
LE9A1:  .res    18, 0
str_dest_format_fail:
        PASCAL_STRING "The destination disk cannot be formated !"
str_format_error:
        PASCAL_STRING "Error during formating."
str_dest_protected:
        PASCAL_STRING "The destination volume is write protected !"
str_confirm_erase1:
        PASCAL_STRING "Do you want to erase "
        .res    18, 0
str_confirm_erase2:
        PASCAL_STRING "Do you want to  erase  the disk in slot   drive   ?"
str_confirm_erase3:
        PASCAL_STRING "Do you want to erase the disk in slot   drive   ?"
str_copy_success:
        PASCAL_STRING "The copy was successful."
str_copy_fail:
        PASCAL_STRING "The copy was not completed."
str_insert_source_or_cancel:
        PASCAL_STRING "Insert source disk or press Escape to cancel."
str_insert_dest_or_cancel:
        PASCAL_STRING "Insert destination disk or press Escape to cancel."

char_space:
        .byte   ' '
char_question_mark:
        .byte   '?'

slot_char_str_confirm_erase2:   .byte   41
drive_char_str_confirm_erase2:  .byte   49

slot_char_str_confirm_erase3:   .byte   39
drive_char_str_confirm_erase3:  .byte   47

len_confirm_erase0:  .byte   23
len_confirm_erase1:  .byte   21

LEB4D:  .byte   0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12

LEB5A:  .addr   str_insert_source, str_insert_dest
        .addr   str_confirm_erase0, str_dest_format_fail
        .addr   str_format_error, str_dest_protected
        .addr   str_confirm_erase1, str_confirm_erase2
        .addr   str_confirm_erase3, str_copy_success
        .addr   str_copy_fail, str_insert_source_or_cancel
        .addr   str_insert_dest_or_cancel

LEB74:  .byte   $C0, $C0, $81, $00, $80, $80, $81, $81
        .byte   $81, $00, $00, $00, $00

LEB81:  .addr   0
LEB83:  .byte   0

LEB84:  stax    LEB81
        sty     LEB83
        MGTK_RELAY_CALL2 MGTK::InitPort, grafport
        MGTK_RELAY_CALL2 MGTK::SetPort, grafport
        MGTK_RELAY_CALL2 MGTK::SetPenMode, pencopy
        MGTK_RELAY_CALL2 MGTK::PaintRect, rect_E89F
        jsr     LF0DF
        MGTK_RELAY_CALL2 MGTK::FrameRect, rect_E89F
        MGTK_RELAY_CALL2 MGTK::SetPortBits, portbits1
        MGTK_RELAY_CALL2 MGTK::FrameRect, rect_E8A7
        MGTK_RELAY_CALL2 MGTK::FrameRect, rect_E8AF
        MGTK_RELAY_CALL2 MGTK::SetPenMode, pencopy
        MGTK_RELAY_CALL2 MGTK::HideCursor
        MGTK_RELAY_CALL2 MGTK::PaintBits, alert_bitmap_mapinfo
        MGTK_RELAY_CALL2 MGTK::ShowCursor
        lda     #$00
        sta     LD41E
        lda     LEB81
        jsr     LF1CC
        ldy     LEB83
        ldx     LEB81+1
        lda     LEB81
        bne     LEC1F
        cpx     #$00
        beq     LEC5E
        jsr     LF185
        beq     LEC5E
        lda     #$0B
        bne     LEC5E
LEC1F:  cmp     #$01
        bne     LEC34
        cpx     #$00
        beq     LEC5E
        jsr     LF185
        beq     LEC30
        lda     #$0C
        bne     LEC5E
LEC30:  lda     #$01
        bne     LEC5E
LEC34:  cmp     #$02
        bne     LEC3F
        jsr     LF0E9
        lda     #$02
        bne     LEC5E
LEC3F:  cmp     #$06
        bne     :+
        jsr     LF119
        lda     #$06
        bne     LEC5E
:       cmp     #$07
        bne     LEC55
        jsr     LF149
        lda     #$07
        bne     LEC5E
LEC55:  cmp     #$08
        bne     LEC5E
        jsr     LF167
        lda     #$08
LEC5E:  ldy     #$00
LEC60:  cmp     LEB4D,y
        beq     LEC6C
        iny
        cpy     #$1E
        bne     LEC60
        ldy     #$00
LEC6C:  tya
        asl     a
        tay
        lda     LEB5A,y
        sta     LE942
        lda     LEB5A+1,y
        sta     LE942+1
        tya
        lsr     a
        tay
        lda     LEB74,y
        sta     LE941
        bit     LD41E
        bpl     LEC8C
        jmp     LED23

LEC8C:  jsr     LF0DF
        bit     LE941
        bpl     draw_ok_btn
        MGTK_RELAY_CALL2 MGTK::FrameRect, cancel_rect
        MGTK_RELAY_CALL2 MGTK::MoveTo, cancel_pos
        addr_call draw_text, str_cancel_btn
        bit     LE941
        bvs     draw_ok_btn
        lda     LE941
        and     #$0F
        beq     draw_try_again_btn

        MGTK_RELAY_CALL2 MGTK::FrameRect, yes_rect
        MGTK_RELAY_CALL2 MGTK::MoveTo, yes_pos
        addr_call draw_text, str_yes_btn

        MGTK_RELAY_CALL2 MGTK::FrameRect, no_rect
        MGTK_RELAY_CALL2 MGTK::MoveTo, no_pos
        addr_call draw_text, str_no_btn
        jmp     LED23

draw_try_again_btn:
        MGTK_RELAY_CALL2 MGTK::FrameRect, ok_try_again_rect
        MGTK_RELAY_CALL2 MGTK::MoveTo, ok_try_again_pos
        addr_call draw_text, str_try_again_btn
        jmp     LED23

draw_ok_btn:
        MGTK_RELAY_CALL2 MGTK::FrameRect, ok_try_again_rect
        MGTK_RELAY_CALL2 MGTK::MoveTo, ok_try_again_pos
        addr_call draw_text, str_ok_btn

LED23:  MGTK_RELAY_CALL2 MGTK::MoveTo, LE93D
        addr_call_indirect draw_text, LE942
LED35:  bit     LD41E
        bpl     LED45
        jsr     LF192
        bne     LED42
        jmp     LEDF2

LED42:  jmp     LED79

LED45:  MGTK_RELAY_CALL2 MGTK::GetEvent, event_params
        lda     event_kind
        cmp     #MGTK::EventKind::button_down
        bne     LED58
        jmp     LEDFA

LED58:  cmp     #MGTK::EventKind::key_down
        bne     LED35
        lda     event_key
        and     #CHAR_MASK
        bit     LE941
        bmi     LED69
        jmp     LEDE2

LED69:  cmp     #CHAR_ESCAPE
        bne     LED7E
        jsr     LF0DF
        MGTK_RELAY_CALL2 MGTK::PaintRect, cancel_rect
LED79:  lda     #$01
        jmp     LEE6A

LED7E:  bit     LE941
        bvs     LEDE2
        pha
        lda     LE941
        and     #$0F
        beq     LEDC1
        pla
        cmp     #'N'
        beq     LED9F
        cmp     #'n'
        beq     LED9F
        cmp     #'Y'
        beq     LEDB0
        cmp     #'y'
        beq     LEDB0
        jmp     LED35

LED9F:  jsr     LF0DF
        MGTK_RELAY_CALL2 MGTK::PaintRect, no_rect
        lda     #$03
        jmp     LEE6A

LEDB0:  jsr     LF0DF
        MGTK_RELAY_CALL2 MGTK::PaintRect, yes_rect
        lda     #$02
        jmp     LEE6A

LEDC1:  pla
        cmp     #$61
        bne     LEDD7
LEDC6:  jsr     LF0DF
        MGTK_RELAY_CALL2 MGTK::PaintRect, ok_try_again_rect
        lda     #$00
        jmp     LEE6A

LEDD7:  cmp     #$41
        beq     LEDC6
        cmp     #$0D
        beq     LEDC6
        jmp     LED35

LEDE2:  cmp     #$0D
        bne     LEDF7
        jsr     LF0DF
        MGTK_RELAY_CALL2 MGTK::PaintRect, ok_try_again_rect
LEDF2:  lda     #$00
        jmp     LEE6A

LEDF7:  jmp     LED35

LEDFA:  jsr     LF0B8
        MGTK_RELAY_CALL2 MGTK::MoveTo, event_coords
        bit     LE941
        bpl     LEE57
        MGTK_RELAY_CALL2 MGTK::InRect, cancel_rect
        cmp     #MGTK::inrect_inside
        bne     LEE1B
        jmp     LEEF8

LEE1B:  bit     LE941
        bvs     LEE57
        lda     LE941
        and     #$0F
        beq     LEE47
        MGTK_RELAY_CALL2 MGTK::InRect, no_rect
        cmp     #MGTK::inrect_inside
        bne     LEE37
        jmp     LEFD8

LEE37:  MGTK_RELAY_CALL2 MGTK::InRect, yes_rect
        cmp     #MGTK::inrect_inside
        bne     LEE67
        jmp     LF048

LEE47:  MGTK_RELAY_CALL2 MGTK::InRect, ok_try_again_rect
        cmp     #MGTK::inrect_inside
        bne     LEE67
        jmp     LEE88

LEE57:  MGTK_RELAY_CALL2 MGTK::InRect, ok_try_again_rect
        cmp     #MGTK::inrect_inside
        bne     LEE67
        jmp     LEF68

LEE67:  jmp     LED35

LEE6A:  pha
        MGTK_RELAY_CALL2 MGTK::SetPortBits, portbits2
        MGTK_RELAY_CALL2 MGTK::SetPenMode, pencopy
        MGTK_RELAY_CALL2 MGTK::PaintRect, $E89F
        pla
        rts

LEE88:  jsr     LF0DF
        MGTK_RELAY_CALL2 MGTK::PaintRect, ok_try_again_rect
        lda     #$00
        sta     LEEF7
LEE99:  MGTK_RELAY_CALL2 MGTK::GetEvent, event_params
        lda     event_kind
        cmp     #MGTK::EventKind::button_up
        beq     LEEEA
        jsr     LF0B8
        MGTK_RELAY_CALL2 MGTK::MoveTo, event_coords
        MGTK_RELAY_CALL2 MGTK::InRect, ok_try_again_rect
        cmp     #MGTK::inrect_inside
        beq     LEECA
        lda     LEEF7
        beq     LEED2
        jmp     LEE99

LEECA:  lda     LEEF7
        bne     LEED2
        jmp     LEE99

LEED2:  jsr     LF0DF
        MGTK_RELAY_CALL2 MGTK::PaintRect, ok_try_again_rect
        lda     LEEF7
        clc
        adc     #$80
        sta     LEEF7
        jmp     LEE99

LEEEA:  lda     LEEF7
        beq     LEEF2
        jmp     LED35

LEEF2:  lda     #$00
        jmp     LEE6A

LEEF7:  .byte   0
LEEF8:  jsr     LF0DF
        MGTK_RELAY_CALL2 MGTK::PaintRect, cancel_rect
        lda     #$00
        sta     LEF67
LEF09:  MGTK_RELAY_CALL2 MGTK::GetEvent, event_params
        lda     event_kind
        cmp     #MGTK::EventKind::button_up
        beq     LEF5A
        jsr     LF0B8
        MGTK_RELAY_CALL2 MGTK::MoveTo, event_coords
        MGTK_RELAY_CALL2 MGTK::InRect, cancel_rect
        cmp     #MGTK::inrect_inside
        beq     LEF3A
        lda     LEF67
        beq     LEF42
        jmp     LEF09

LEF3A:  lda     LEF67
        bne     LEF42
        jmp     LEF09

LEF42:  jsr     LF0DF
        MGTK_RELAY_CALL2 MGTK::PaintRect, cancel_rect
        lda     LEF67
        clc
        adc     #$80
        sta     LEF67
        jmp     LEF09

LEF5A:  lda     LEF67
        beq     LEF62
        jmp     LED35

LEF62:  lda     #$01
        jmp     LEE6A

LEF67:  .byte   0
LEF68:  lda     #$00
        sta     LEFD7
        jsr     LF0DF
        MGTK_RELAY_CALL2 MGTK::PaintRect, ok_try_again_rect
LEF79:  MGTK_RELAY_CALL2 MGTK::GetEvent, event_params
        lda     event_kind
        cmp     #MGTK::EventKind::button_up
        beq     LEFCA
        jsr     LF0B8
        MGTK_RELAY_CALL2 MGTK::MoveTo, event_coords
        MGTK_RELAY_CALL2 MGTK::InRect, ok_try_again_rect
        cmp     #MGTK::inrect_inside
        beq     LEFAA
        lda     LEFD7
        beq     LEFB2
        jmp     LEF79

LEFAA:  lda     LEFD7
        bne     LEFB2
        jmp     LEF79

LEFB2:  jsr     LF0DF
        MGTK_RELAY_CALL2 MGTK::PaintRect, ok_try_again_rect
        lda     LEFD7
        clc
        adc     #$80
        sta     LEFD7
        jmp     LEF79

LEFCA:  lda     LEFD7
        beq     LEFD2
        jmp     LED35

LEFD2:  lda     #$00
        jmp     LEE6A

LEFD7:  .byte   0
LEFD8:  lda     #$00
        sta     LF047
        jsr     LF0DF
        MGTK_RELAY_CALL2 MGTK::PaintRect, no_rect
LEFE9:  MGTK_RELAY_CALL2 MGTK::GetEvent, event_params
        lda     event_kind
        cmp     #MGTK::EventKind::button_up
        beq     LF03A
        jsr     LF0B8
        MGTK_RELAY_CALL2 MGTK::MoveTo, event_coords
        MGTK_RELAY_CALL2 MGTK::InRect, no_rect
        cmp     #MGTK::inrect_inside
        beq     LF01A
        lda     LF047
        beq     LF022
        jmp     LEFE9

LF01A:  lda     LF047
        bne     LF022
LF01F:  jmp     LEFE9

LF022:  jsr     LF0DF
        MGTK_RELAY_CALL2 MGTK::PaintRect, no_rect
        lda     LF047
        clc
        adc     #$80
        sta     LF047
        jmp     LEFE9

LF03A:  lda     LF047
        beq     LF042
        jmp     LED35

LF042:  lda     #$03
        jmp     LEE6A

LF047:  .byte   0
LF048:  lda     #$00
        sta     LF0B7
        jsr     LF0DF
        MGTK_RELAY_CALL2 MGTK::PaintRect, yes_rect
LF059:  MGTK_RELAY_CALL2 MGTK::GetEvent, event_params
        lda     event_kind
        cmp     #MGTK::EventKind::button_up
        beq     LF0AA
        jsr     LF0B8
        MGTK_RELAY_CALL2 MGTK::MoveTo, event_coords
        MGTK_RELAY_CALL2 MGTK::InRect, yes_rect
        cmp     #MGTK::inrect_inside
        beq     LF08A
        lda     LF0B7
        beq     LF092
        jmp     LF059

LF08A:  lda     LF0B7
        bne     LF092
        jmp     LF059

LF092:  jsr     LF0DF
        MGTK_RELAY_CALL2 MGTK::PaintRect, yes_rect
        lda     LF0B7
        clc
        adc     #$80
        sta     LF0B7
        jmp     LF059

LF0AA:  lda     LF0B7
        beq     LF0B2
        jmp     LED35

LF0B2:  lda     #$02
        jmp     LEE6A

LF0B7:  .byte   0
LF0B8:  sub16   event_xcoord, portbits1::viewloc::xcoord, event_xcoord
        sub16   event_ycoord, portbits1::viewloc::ycoord, event_ycoord
        rts

LF0DF:  MGTK_RELAY_CALL2 MGTK::SetPenMode, penXOR
        rts

LF0E9:  stx     $06
        sty     $07
        ldy     #$00
        lda     ($06),y
        pha
        tay
LF0F3:  lda     ($06),y
        sta     LE9A1-1,y
        dey
        bne     LF0F3
        pla
        clc
        adc     len_confirm_erase0
        sta     str_confirm_erase0
        tay
        inc     str_confirm_erase0
        inc     str_confirm_erase0
        lda     char_space
        iny
        sta     str_confirm_erase0,y
        lda     char_question_mark
        iny
        sta     str_confirm_erase0,y
        rts

LF119:  stx     $06
        sty     $07
        ldy     #$00
        lda     ($06),y
        pha
        tay
LF123:  lda     ($06),y
        sta     $EA36,y
        dey
        bne     LF123
        pla
        clc
        adc     len_confirm_erase1
        sta     str_confirm_erase1
        tay
        inc     str_confirm_erase1
        inc     str_confirm_erase1
        lda     char_space
        iny
        sta     str_confirm_erase1,y
        lda     char_question_mark
        iny
        sta     str_confirm_erase1,y
        rts

LF149:  txa
        and     #$70
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     #'0'
        ldy     slot_char_str_confirm_erase2
        sta     str_confirm_erase2,y
        txa
        and     #$80
        asl     a
        rol     a
        adc     #$31
        ldy     drive_char_str_confirm_erase2
        sta     str_confirm_erase2,y
        rts

LF167:  txa
        and     #$70
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     #'0'
        ldy     slot_char_str_confirm_erase3
        sta     str_confirm_erase3,y
        txa
        and     #$80
        asl     a
        rol     a
        adc     #$31
        ldy     drive_char_str_confirm_erase3
        sta     str_confirm_erase3,y
        rts

LF185:  sty     LD41D
        tya
        jsr     disk_copy_overlay4::L0EB2
        beq     LF191
        sta     LD41E
LF191:  rts

LF192:  lda     LD41D
        sta     disk_copy_overlay4::on_line_params::unit_num
        jsr     disk_copy_overlay4::L129B
        beq     LF1C9
        cmp     #$52
        beq     LF1C9
        lda     disk_copy_overlay4::on_line_buffer
        and     #$0F
        bne     LF1C9
        lda     disk_copy_overlay4::on_line_buffer+1
        cmp     #$52
        beq     LF1C9
        MGTK_RELAY_CALL2 MGTK::GetEvent, event_params
        lda     event_kind
        cmp     #MGTK::EventKind::key_down
        bne     LF192
        lda     event_key
        cmp     #CHAR_ESCAPE
        bne     LF192
        return  #$80

LF1C9:  return  #$00

LF1CC:  cmp     #$03
        bcc     LF1D7
        cmp     #$06
        bcs     LF1D7
        jsr     disk_copy_overlay4::L127E
LF1D7:  rts

;;; ============================================================

;;; Padding ???

.scope
        tya
        lsr     a
        bcs     :+
        bit     $C055
:       tay
        lda     ($28),y
        pha
        cmp     #$E0
        bcc     :+
        sbc     #$20
:       and     #$3F
        sta     ($28),y
        lda     $C000
        bmi     :+
        jmp     $51ED

:       pla
        sta     ($28),y
        bit     $C054
        lda     $C000
        .byte   $2C
        .byte   $10
.endscope

;;; ============================================================

        PAD_TO $F200

.endproc
