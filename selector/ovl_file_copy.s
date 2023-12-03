;;; ============================================================
;;; Recursive File Copy - Overlay #2
;;;
;;; Compiled as part of selector.s
;;; ============================================================

        BEGINSEG OverlayCopyDialog

.scope file_copier

.proc Exec
        sta     selected_index
        jsr     OpenWindow

        lda     selected_index
        jsr     app::GetSelectorListPathAddr
        jsr     PrepSrcAndDstPaths
        jsr     EnumerateFiles
        bne     skip

        jsr     DrawWindowContent

        lda     selected_index
        jsr     app::GetSelectorListPathAddr
        jsr     PrepSrcAndDstPaths
        jsr     CopyFiles

skip:
        pha
        jsr     CloseWindow
        pla

        rts

selected_index:
        .byte   $00
.endproc ; Exec

;;; ============================================================
;;; Recursive Enumerate & Copy Logic
;;; ============================================================

        DEFINE_OPEN_PARAMS open_params, pathname_src, $800

        ;; 4 bytes is .sizeof(SubdirectoryHeader) - .sizeof(FileEntry)
        kBlockPointersSize = 4
        .assert .sizeof(SubdirectoryHeader) - .sizeof(FileEntry) = kBlockPointersSize, error, "bad structs"
        DEFINE_READ_PARAMS read_block_pointers_params, buf_block_pointers, kBlockPointersSize ; For skipping prev/next pointers in directory data
buf_block_pointers:
        .res    kBlockPointersSize, 0

        DEFINE_CLOSE_PARAMS close_params
        DEFINE_CLOSE_PARAMS close_everything_params ; used in case of error

        DEFINE_READ_PARAMS read_fileentry_params, file_entry, .sizeof(FileEntry)

        ;; Blocks are 512 bytes, 13 entries of 39 bytes each leaves 5 bytes between.
        ;; Except first block, directory header is 39+4 bytes, leaving 1 byte, but then
        ;; block pointers are the next 4.
        kMaxPaddingBytes = 5
        DEFINE_READ_PARAMS read_padding_bytes_params, buf_padding_bytes, kMaxPaddingBytes
buf_padding_bytes:
        .res    kMaxPaddingBytes, 0

        DEFINE_CLOSE_PARAMS close_params_src
        DEFINE_CLOSE_PARAMS close_params_dst

        io_buf_src = $D00
        io_buf_dst = $1100
        data_buf = $1500

        DEFINE_OPEN_PARAMS open_params_src, pathname_src, io_buf_src
        DEFINE_OPEN_PARAMS open_params_dst, pathname_dst, io_buf_dst

        kDirCopyBufSize = $B00

        DEFINE_READ_PARAMS read_params_src, data_buf, kDirCopyBufSize
        DEFINE_WRITE_PARAMS write_params_dst, data_buf, kDirCopyBufSize

        DEFINE_CREATE_PARAMS create_params2, pathname_dst, ACCESS_DEFAULT

        DEFINE_CREATE_PARAMS create_params, pathname_dst

        DEFINE_GET_FILE_INFO_PARAMS get_src_file_info_params, pathname_src

        DEFINE_GET_FILE_INFO_PARAMS get_dst_file_info_params, pathname_dst

file_entry:
        .res    48, 0

addr_table:

;;; Jump table - populated by operation
op_jt_addrs:
op_jt_addr1:  .addr   CopyVisitFile
op_jt_addr2:  .addr   PopDstSegment
op_jt_addr3:  .addr   NoOp2

NoOp2:  rts

;;; Specific file paths during copy
pathname_dst:
        .res    ::kPathBufferSize, 0
pathname_src:
        .res    ::kPathBufferSize, 0

;;; Paths for overall operation
dst_path:       .res    64, 0
src_path:       .res    64, 0
filename:       .res    16, 0

;;; ============================================================

recursion_depth:        .byte   0 ; How far down the directory structure are we
entries_per_block:      .byte   0
ref_num:                .byte   0
entry_index_in_dir:     .word   0
target_index:           .word   0

;;; Stack used when descending directories; keeps track of entry index within
;;; directories.
index_stack:    .res    ::kDirStackBufferSize, 0
stack_index:    .byte   0

entry_index_in_block:   .byte   0

;;; ============================================================

.proc PushIndexToStack
        ldx     stack_index
        lda     target_index
        sta     index_stack,x
        inx
        lda     target_index+1
        sta     index_stack,x
        inx
        stx     stack_index
        rts
.endproc ; PushIndexToStack

;;; ============================================================

.proc PopIndexFromStack
        ldx     stack_index
        dex
        lda     index_stack,x
        sta     target_index+1
        dex
        lda     index_stack,x
        sta     target_index
        stx     stack_index
        rts
.endproc ; PopIndexFromStack

;;; ============================================================

.proc OpenSrcDir
        lda     #$00
        sta     entry_index_in_dir
        sta     entry_index_in_dir+1
        sta     entry_index_in_block
        MLI_CALL OPEN, open_params
        beq     :+
        jmp     HandleErrorCode
:
        lda     open_params::ref_num
        sta     ref_num
        sta     read_block_pointers_params::ref_num
        MLI_CALL READ, read_block_pointers_params
        beq     :+
        jmp     HandleErrorCode
:
        copy    #13, entries_per_block ; so ReadFileEntry doesn't immediately advance
        jsr     ReadFileEntry          ; read the rest of the header

        copy    file_entry-4 + SubdirectoryHeader::entries_per_block, entries_per_block

        rts
.endproc ; OpenSrcDir

;;; ============================================================

.proc DoCloseFile
        lda     ref_num
        sta     close_params::ref_num
        MLI_CALL CLOSE, close_params
        beq     :+
        jmp     HandleErrorCode
:
        rts
.endproc ; DoCloseFile

;;; ============================================================

.proc ReadFileEntry
        inc16   entry_index_in_dir

        ;; Skip entry
        lda     ref_num
        sta     read_fileentry_params::ref_num
        MLI_CALL READ, read_fileentry_params
        beq     :+
        cmp     #ERR_END_OF_FILE
        beq     eof
        jmp     HandleErrorCode
:
        inc     entry_index_in_block
        lda     entry_index_in_block
        cmp     entries_per_block
        bcc     done

        ;; Advance to first entry in next "block"
        lda     #0
        sta     entry_index_in_block
        lda     ref_num
        sta     read_padding_bytes_params::ref_num
        MLI_CALL READ, read_padding_bytes_params
        beq     :+
        jmp     HandleErrorCode
:

done:   return  #0

eof:    return  #$FF
.endproc ; ReadFileEntry

;;; ============================================================

.proc DescendDirectory
        copy16  entry_index_in_dir, target_index
        jsr     DoCloseFile
        jsr     PushIndexToStack
        jsr     AppendFilenameToSrcPathname
        jmp     OpenSrcDir
.endproc ; DescendDirectory

.proc AscendDirectory
        jsr     DoCloseFile
        jsr     op_jt3
        jsr     RemoveSegmentFromSrcPathname
        jsr     PopIndexFromStack
        jsr     OpenSrcDir
        jsr     AdvanceToTargetEntry
        jmp     op_jt2
.endproc ; AscendDirectory

.proc AdvanceToTargetEntry
:       cmp16   entry_index_in_dir, target_index
        bcs     :+
        jsr     ReadFileEntry
        jmp     :-

:       rts
.endproc ; AdvanceToTargetEntry

;;; ============================================================

.proc HandleDirectory
        lda     #$00
        sta     recursion_depth
        jsr     OpenSrcDir
l1:     jsr     ReadFileEntry
        bne     l2

        param_call app::AdjustFileEntryCase, file_entry

        lda     file_entry+FileEntry::storage_type_name_length
        beq     l1
        and     #NAME_LENGTH_MASK
        sta     file_entry+FileEntry::storage_type_name_length
        lda     #$00
        sta     copy_err_flag
        jsr     op_jt1
        lda     copy_err_flag
        bne     l1
        lda     file_entry+FileEntry::file_type
        cmp     #FT_DIRECTORY
        bne     l1
        jsr     DescendDirectory
        inc     recursion_depth
        jmp     l1

l2:     lda     recursion_depth
        beq     l3
        jsr     AscendDirectory
        dec     recursion_depth
        jmp     l1

l3:     jmp     DoCloseFile
.endproc ; HandleDirectory

;;; ============================================================

copy_err_flag:  .byte   0

;;; ============================================================

op_jt1: jmp     (op_jt_addr1)
op_jt2: jmp     (op_jt_addr2)
op_jt3: jmp     (op_jt_addr3)

;;; ============================================================

;;; Jump table for `CopyFiles`
copy_jt:
        .addr   CopyVisitFile
        .addr   PopDstSegment
        .addr   NoOp2

;;; ============================================================

.proc CopyFiles
        ;; Prepare jump table
        ldy     #5
:       lda     copy_jt,y
        sta     op_jt_addrs,y
        dey
        bpl     :-

        tsx
        stx     saved_stack

        lda     #$FF
        sta     LA4F9
        jsr     CopyPathsFromBufsToSrcAndDst
        MLI_CALL GET_FILE_INFO, get_dst_file_info_params
        beq     :+
        jmp     HandleErrorCode
:
        ;; Is there enough space?
        sub16   get_dst_file_info_params::aux_type, get_dst_file_info_params::blocks_used, blocks
        cmp16   blocks, blocks_total
        bcs     :+
        jmp     ShowDiskFullError
:
        ;; Append `filename` to `pathname_dst`
        ldx     pathname_dst
        lda     #'/'
        sta     pathname_dst+1,x
        inc     pathname_dst
        ldy     #0
        ldx     pathname_dst
:       iny
        inx
        lda     filename,y
        sta     pathname_dst,x
        cpy     filename
        bne     :-
        stx     pathname_dst

        MLI_CALL GET_FILE_INFO, get_dst_file_info_params
        beq     check_src
        cmp     #ERR_FILE_NOT_FOUND
        beq     check_src
        cmp     #ERR_VOL_NOT_FOUND
        beq     check_src
        cmp     #ERR_PATH_NOT_FOUND
        beq     check_src
        bne     error           ; always

check_src:
        MLI_CALL GET_FILE_INFO, get_src_file_info_params
        beq     LA491
        cmp     #ERR_VOL_NOT_FOUND
        beq     LA488
        cmp     #ERR_FILE_NOT_FOUND
        bne     error
LA488:  jsr     ShowInsertSourceDiskAlert
        jmp     check_src       ; retry

error:  jmp     HandleErrorCode

LA491:  lda     get_src_file_info_params::storage_type
        cmp     #ST_VOLUME_DIRECTORY
        beq     is_dir
        cmp     #ST_LINKED_DIRECTORY
        beq     is_dir
        lda     #0
        beq     LA4A2
is_dir: lda     #$FF
LA4A2:  sta     is_dir_flag

        ldy     #$07
:       lda     get_src_file_info_params,y
        sta     create_params,y
        dey
        cpy     #$02
        bne     :-

        lda     #ACCESS_DEFAULT
        sta     create_params::access
        jsr     CheckSpace2
        bcc     LA4BF
        jmp     ShowDiskFullError

        ;; Copy creation date/time
LA4BF:  ldy     #(get_src_file_info_params::create_time+1 - get_src_file_info_params)
        ldx     #(create_params::create_time+1 - create_params)
:       lda     get_src_file_info_params,y
        sta     create_params,x
        dex
        dey
        cpy     #(get_src_file_info_params::create_date-1 - get_src_file_info_params)
        bne     :-

        lda     create_params::storage_type
        cmp     #ST_VOLUME_DIRECTORY
        bne     :+
        lda     #ST_LINKED_DIRECTORY
        sta     create_params::storage_type
:       MLI_CALL CREATE, create_params
        beq     :+
        cmp     #ERR_DUPLICATE_FILENAME
        beq     :+
        jmp     HandleErrorCode
:
        lda     is_dir_flag
        beq     do_file
        jmp     HandleDirectory

blocks: .word   0

do_file:
        jmp     CopyFile

is_dir_flag:
        .byte   0

LA4F9:  .byte   0
.endproc ; CopyFiles

;;; ============================================================

src_path_slash_index:           ; TODO: Written but never read?
        .byte   0

saved_stack:
        .byte   0

PopDstSegment:
        jmp     RemoveSegmentFromDstPathname

;;; ============================================================

.proc CopyVisitFile
        jsr     CheckEscapeKeyDown
        jne     RestoreStackAndReturn

        lda     file_entry+FileEntry::file_type
        cmp     #FT_DIRECTORY
        bne     is_file

        ;; --------------------------------------------------
        ;; Directory
        jsr     AppendFilenameToSrcPathname
        jsr     draw_window_content_ep2
        MLI_CALL GET_FILE_INFO, get_src_file_info_params
        beq     LA528
        jmp     HandleErrorCode

err:    jsr     RemoveSegmentFromDstPathname
        jsr     RemoveSegmentFromSrcPathname
        lda     #$FF
        sta     copy_err_flag
        rts

LA528:  jsr     AppendFilenameToDstPathname
        jsr     CreateDstFile
        bcs     err
        jmp     RemoveSegmentFromSrcPathname

        ;; --------------------------------------------------
        ;; Regular File
is_file:
        jsr     AppendFilenameToDstPathname
        jsr     AppendFilenameToSrcPathname
        jsr     draw_window_content_ep2
        MLI_CALL GET_FILE_INFO, get_src_file_info_params
        beq     :+
        jmp     HandleErrorCode
:
        jsr     CheckSpace2
        bcc     :+
        jmp     ShowDiskFullError
:
        jsr     RemoveSegmentFromSrcPathname
        jsr     CreateDstFile
        bcs     CheckSpace
        jsr     AppendFilenameToSrcPathname
        jsr     CopyFile
        jsr     RemoveSegmentFromSrcPathname
        jsr     RemoveSegmentFromDstPathname
        rts

.endproc ; CopyVisitFile

;;; ============================================================

.proc CheckSpace
        jsr     RemoveSegmentFromDstPathname

ep2:    MLI_CALL GET_FILE_INFO, get_src_file_info_params
        beq     :+
        jmp     HandleErrorCode
:
        copy16  #0, existing_blocks
        MLI_CALL GET_FILE_INFO, get_dst_file_info_params
        beq     exists
        cmp     #ERR_FILE_NOT_FOUND
        beq     LA5A1
        jmp     HandleErrorCode

exists: copy16  get_dst_file_info_params::blocks_used, existing_blocks

LA5A1:  copy    pathname_dst, saved_length
        ;; Strip to vol name - either end of string or next slash
        ldy     #1
:       iny
        cpy     pathname_dst
        bcs     has_room
        lda     pathname_dst,y
        cmp     #'/'
        bne     :-
        tya
        sta     pathname_dst

        ;; Total blocks/used blocks on destination volume
        MLI_CALL GET_FILE_INFO, get_dst_file_info_params
        beq     :+
        jmp     HandleErrorCode
:
        ;; aux = total blocks
        sub16   get_dst_file_info_params::aux_type, get_dst_file_info_params::blocks_used, blocks_free
        add16   blocks_free, existing_blocks, blocks_free
        cmp16   blocks_free, get_src_file_info_params::blocks_used
        bcs     has_room

        ;; Not enough room
        sec
        bcs     LA603
has_room:
        clc

LA603:  lda     saved_length
        sta     pathname_dst
        rts

blocks_free:              ; Blocks free on volume
        .word   0
saved_length:
        .byte   0
existing_blocks:          ; Blocks taken by file that will be replaced
        .word   0
.endproc ; CheckSpace
CheckSpace2 := CheckSpace::ep2

;;; ============================================================

.proc CopyFile
        MLI_CALL OPEN, open_params_src
        beq     :+
        jsr     HandleErrorCode
:
        MLI_CALL OPEN, open_params_dst
        beq     :+
        jmp     HandleErrorCode
:
        lda     open_params_src::ref_num
        sta     read_params_src::ref_num
        sta     close_params_src::ref_num
        lda     open_params_dst::ref_num
        sta     write_params_dst::ref_num
        sta     close_params_dst::ref_num

loop:
        copy16  #kDirCopyBufSize, read_params_src::request_count
        MLI_CALL READ, read_params_src
        beq     :+
        cmp     #ERR_END_OF_FILE
        beq     done
        jmp     HandleErrorCode
:
        copy16  read_params_src::trans_count, write_params_dst::request_count
        ora     read_params_src::trans_count
        beq     done
        MLI_CALL WRITE, write_params_dst
        beq     :+
        jmp     HandleErrorCode
:
        lda     write_params_dst::trans_count
        cmp     #<kDirCopyBufSize
        bne     done
        lda     write_params_dst::trans_count+1
        cmp     #>kDirCopyBufSize
        beq     loop

done:
        MLI_CALL CLOSE, close_params_dst
        MLI_CALL CLOSE, close_params_src
        rts
.endproc ; CopyFile

;;; ============================================================

.proc CreateDstFile
        ;; Copy `file_type`, `aux_type`, and `storage_type`
        ldx     #(get_src_file_info_params::storage_type - get_src_file_info_params)
:       lda     get_src_file_info_params,x
        sta     create_params2,x
        dex
        cpx     #(get_src_file_info_params::file_type - get_src_file_info_params) - 1
        bne     :-

        MLI_CALL CREATE, create_params2
        beq     :+
        cmp     #ERR_DUPLICATE_FILENAME
        jne     HandleErrorCode
:       clc                     ; treated as success
        rts
.endproc ; CreateDstFile

;;; ============================================================

;;; Jump table for `EnumerateFiles`
enum_jt:
        .addr   EnumerateVisitFile
        .addr   NoOp
        .addr   NoOp2

;;; ============================================================

.proc EnumerateFiles
        ;; Prepare jump table
        ldy     #5
:       lda     enum_jt,y
        sta     addr_table,y
        dey
        bpl     :-

        tsx
        stx     saved_stack

        lda     #$00
        sta     file_count
        sta     file_count+1
        sta     blocks_total
        sta     blocks_total+1

        jsr     CopyPathsFromBufsToSrcAndDst
LA6E3:  MLI_CALL GET_FILE_INFO, get_src_file_info_params
        beq     LA6FF
        cmp     #ERR_VOL_NOT_FOUND
        beq     LA6F6
        cmp     #ERR_FILE_NOT_FOUND
        bne     LA6FC
LA6F6:  jsr     ShowInsertSourceDiskAlert
        jmp     LA6E3           ; retry

LA6FC:  jmp     HandleErrorCode

LA6FF:  lda     get_src_file_info_params::storage_type
        sta     storage_type
        cmp     #ST_VOLUME_DIRECTORY
        beq     is_dir
        cmp     #ST_LINKED_DIRECTORY
        beq     is_dir
        lda     #$00
        beq     set
is_dir: lda     #$FF
set:    sta     is_dir_flag
        beq     visit
        jsr     HandleDirectory
        lda     storage_type
        cmp     #ST_VOLUME_DIRECTORY
        bne     visit

        ;; If copying a volume dir to RAMCard, the volume dir
        ;; will not be counted as a file during enumeration but
        ;; will be counted during copy, so include it to avoid
        ;; off-by-one.
        ;; https://github.com/a2stuff/a2d/issues/564
        inc16   file_count
        jsr     UpdateFileCountDisplay
        return  #0

is_dir_flag:
        .byte   0
storage_type:
        .byte   0

visit:  jsr     EnumerateVisitFile
        return  #0
.endproc ; EnumerateFiles

;;; ============================================================

.proc NoOp
        rts
.endproc ; NoOp

;;; ============================================================

.proc EnumerateVisitFile
        jsr     CheckEscapeKeyDown
        jne     RestoreStackAndReturn

        jsr     AppendFilenameToSrcPathname
        MLI_CALL GET_FILE_INFO, get_src_file_info_params
        bne     :+
        add16   blocks_total, get_src_file_info_params::blocks_used, blocks_total
:       inc16   file_count
        jsr     RemoveSegmentFromSrcPathname
        jmp     UpdateFileCountDisplay
.endproc ; EnumerateVisitFile

;;; ============================================================

file_count:
        .word   0
blocks_total:
        .word   0

;;; ============================================================

.proc AppendFilenameToSrcPathname
        lda     file_entry+FileEntry::storage_type_name_length
        RTS_IF_ZERO

        ldx     #$00
        ldy     pathname_src
        lda     #'/'
        sta     pathname_src+1,y
        iny
l2:     cpx     file_entry+FileEntry::storage_type_name_length
        bcs     l3
        lda     file_entry+FileEntry::file_name,x
        sta     pathname_src+1,y
        inx
        iny
        jmp     l2

l3:     sty     pathname_src
        rts
.endproc ; AppendFilenameToSrcPathname

;;; ============================================================

.proc RemoveSegmentFromSrcPathname
        ldx     pathname_src
        RTS_IF_ZERO

:       lda     pathname_src,x
        cmp     #'/'
        beq     :+
        dex
        bne     :-
        stx     pathname_src
        rts

:       dex
        stx     pathname_src
        rts
.endproc ; RemoveSegmentFromSrcPathname

;;; ============================================================

.proc AppendFilenameToDstPathname
        lda     file_entry+FileEntry::storage_type_name_length
        RTS_IF_ZERO

        ldx     #$00
        ldy     pathname_dst
        lda     #'/'
        sta     pathname_dst+1,y
        iny
l2:     cpx     file_entry+FileEntry::storage_type_name_length
        bcs     l3
        lda     file_entry+FileEntry::file_name,x
        sta     pathname_dst+1,y
        inx
        iny
        jmp     l2

l3:     sty     pathname_dst
        rts
.endproc ; AppendFilenameToDstPathname

;;; ============================================================

.proc RemoveSegmentFromDstPathname
        ldx     pathname_dst
        RTS_IF_ZERO

l1:     lda     pathname_dst,x
        cmp     #'/'
        beq     l2
        dex
        bne     l1
        stx     pathname_dst
        rts

l2:     dex
        stx     pathname_dst
        rts
.endproc ; RemoveSegmentFromDstPathname

;;; ============================================================
;;; Copy `src_path` to `pathname_src` and `dst_path` to `pathname_dst`
;;; and note last '/' in src.

.proc CopyPathsFromBufsToSrcAndDst
        ldy     #0
        sta     src_path_slash_index
        dey

        ;; Copy `src_path` to `pathname_src`
        ;; ... but record index of last '/'
loop:   iny
        lda     src_path,y
        cmp     #'/'
        bne     :+
        sty     src_path_slash_index
:       sta     pathname_src,y
        cpy     src_path
        bne     loop

        ;; Copy `dst_path` to `pathname_dst`
        ldy     dst_path
:       lda     dst_path,y
        sta     pathname_dst,y
        dey
        bpl     :-

        rts
.endproc ; CopyPathsFromBufsToSrcAndDst

;;; ============================================================
;;; Input: A,X = pointer to entry path to copy

.proc PrepSrcAndDstPaths
        ptr := $06

        stax    ptr
        ldy     #0
        lda     (ptr),y
        tay
:       lda     (ptr),y
        sta     src_path,y
        dey
        bpl     :-

        ldy     src_path
l2:     lda     src_path,y
        cmp     #'/'
        beq     l3
        dey
        bne     l2
l3:     dey
        sty     src_path

l4:     lda     src_path,y
        cmp     #'/'
        beq     l5
        dey
        bpl     l4
l5:
        ldx     #0
l6:     iny
        inx
        lda     src_path,y
        sta     filename,x
        cpy     src_path
        bne     l6
        stx     filename

        param_call app::CopyRAMCardPrefix, dst_path

        rts
.endproc ; PrepSrcAndDstPaths

;;; ============================================================
;;; Copy Progress UI
;;; ============================================================

.params winfo
        kWindowId = $0B
        kWidth = 350
        kHeight = 70
window_id:      .byte   kWindowId
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
mincontheight:  .word   50
maxcontwidth:   .word   500
maxcontheight:  .word   140
port:
        DEFINE_POINT viewloc, 100, 50
mapbits:        .addr   MGTK::screen_mapbits
mapwidth:       .byte   MGTK::screen_mapwidth
reserved2:      .byte   0
        DEFINE_RECT maprect, 0, 0, kWidth, kHeight
pattern:        .res    8, $FF
colormasks:     .byte   MGTK::colormask_and, MGTK::colormask_or
        DEFINE_POINT penloc, 0, 0
penwidth:       .byte   1
penheight:      .byte   1
penmode:        .byte   MGTK::pencopy
textback:       .byte   $7F
textfont:       .addr   FONT
nextwinfo:      .addr   0
        REF_WINFO_MEMBERS
.endparams

        DEFINE_RECT_FRAME rect_frame, winfo::kWidth, winfo::kHeight

        DEFINE_LABEL download, res_string_label_download, 116, 16

        DEFINE_POINT pos_copying, 20, 32
        DEFINE_POINT pos_remaining, 20, 45

str_copying:
        PASCAL_STRING res_string_label_copying

        DEFINE_RECT rect_clear_count, 18, 24, winfo::kWidth-kBorderDX*2, 32
        DEFINE_RECT rect_clear_details, kBorderDX*2, 24, winfo::kWidth-kBorderDX*2, winfo::kHeight-kBorderDY*2

.params setportbits_params
        DEFINE_POINT viewloc, 100, 50
mapbits:        .addr   MGTK::screen_mapbits
mapwidth:       .byte   MGTK::screen_mapwidth
reserved:       .byte   0
        DEFINE_RECT maprect, 0, 0, 340, 66
pattern:        .res    8, $FF
colormasks:     .byte   $FF, $00
penloc:         .word   0, 0
penwidth:       .byte   1
penheight:      .byte   1
penmode:        .byte   MGTK::pencopy
textback:       .byte   $7F
textfont:       .addr   FONT
        REF_GRAFPORT_MEMBERS
.endparams

str_files_to_copy:
        PASCAL_STRING res_string_label_files_to_copy
str_files_remaining:
        PASCAL_STRING res_string_label_files_remaining
str_spaces:
        PASCAL_STRING "    "
str_space:
        PASCAL_STRING " "

;;; ============================================================

.proc OpenWindow
        MGTK_CALL MGTK::OpenWindow, winfo
        lda     #winfo::kWindowId
        jsr     app::GetWindowPort

        MGTK_CALL MGTK::SetPenMode, notpencopy
        MGTK_CALL MGTK::SetPenSize, app::pensize_frame
        MGTK_CALL MGTK::FrameRect, rect_frame
        MGTK_CALL MGTK::SetPenSize, app::pensize_normal

        MGTK_CALL MGTK::MoveTo, download_label_pos
        param_call app::DrawString, download_label_str
        rts
.endproc ; OpenWindow

;;; ============================================================

.proc DrawWindowContent
        lda     #winfo::kWindowId
        jsr     app::GetWindowPort
        MGTK_CALL MGTK::SetPenMode, pencopy
        MGTK_CALL MGTK::PaintRect, rect_clear_details

ep2:    dec     file_count
        lda     file_count
        cmp     #$FF
        bne     :+
        dec     file_count+1
:

        jsr     PopulateCount
        MGTK_CALL MGTK::SetPortBits, setportbits_params
        MGTK_CALL MGTK::SetPenMode, pencopy
        MGTK_CALL MGTK::PaintRect, rect_clear_count
        MGTK_CALL MGTK::MoveTo, pos_copying
        param_call app::DrawString, str_copying
        param_call app::DrawString, str_space
        param_call app::DrawString, pathname_src
        MGTK_CALL MGTK::MoveTo, pos_remaining
        param_call app::DrawString, str_files_remaining
        param_call app::DrawString, str_count
        param_call app::DrawString, str_spaces
        rts
.endproc ; DrawWindowContent
        draw_window_content_ep2 := DrawWindowContent::ep2
;;; ============================================================

.proc UpdateFileCountDisplay
        jsr     PopulateCount
        MGTK_CALL MGTK::SetPortBits, setportbits_params
        MGTK_CALL MGTK::MoveTo, pos_copying
        param_call app::DrawString, str_files_to_copy
        param_call app::DrawString, str_count
        param_call app::DrawString, str_spaces
        rts
.endproc ; UpdateFileCountDisplay

;;; ============================================================

.proc ShowInsertSourceDiskAlert
        lda     #AlertID::insert_source_disk
        jsr     app::ShowAlert
        .assert kAlertResultCancel <> 0, error, "Branch assumes enum value"
        bne     :+              ; `kAlertResultCancel` = 1
        jmp     app::SetCursorWatch ; try again

:       jmp     RestoreStackAndReturn
.endproc ; ShowInsertSourceDiskAlert

;;; ============================================================

.proc ShowDiskFullError
        lda     #AlertID::not_enough_room
        jsr     app::ShowAlert
        jmp     RestoreStackAndReturn
.endproc ; ShowDiskFullError

;;; ============================================================

.proc HandleErrorCode
        lda     #AlertID::copy_incomplete
        jsr     app::ShowAlert
        jmp     RestoreStackAndReturn
.endproc ; HandleErrorCode

;;; ============================================================

.proc RestoreStackAndReturn
        MLI_CALL CLOSE, close_everything_params
        ldx     saved_stack
        txs
        return  #$FF
.endproc ; RestoreStackAndReturn

;;; ============================================================

.proc CloseWindow
        MGTK_CALL MGTK::CloseWindow, winfo
        rts
.endproc ; CloseWindow

;;; ============================================================

.proc CheckEscapeKeyDown
        MGTK_CALL MGTK::GetEvent, event_params
        lda     event_params::kind
        cmp     #MGTK::EventKind::key_down
        bne     nope
        lda     event_params::key
        cmp     #CHAR_ESCAPE
        bne     nope
        lda     #$FF
        bne     done
nope:   lda     #$00
done:   rts
.endproc ; CheckEscapeKeyDown

;;; ============================================================

.proc PopulateCount
        copy16  file_count, value
        ldx     #7
        lda     #' '
:       sta     str_count,x
        dex
        bne     :-
        lda     #0
        sta     nonzero_flag
        ldy     #0
        ldx     #0

loop:   lda     #0
        sta     digit
sloop:  cmp16   value, powers,x
        bcs     subtract
        lda     digit
        bne     not_pad
        bit     nonzero_flag
        bmi     not_pad
        lda     #' '
        bne     store
not_pad:
        ora     #$30            ; to ASCII digit
        pha
        lda     #$80
        sta     nonzero_flag
        pla
store:  sta     str_count+2,y
        iny
        inx
        inx
        cpx     #8
        beq     done
        jmp     loop

subtract:
        inc     digit
        lda     value
        sec
        sbc     powers,x
        sta     value
        lda     value+1
        sbc     powers+1,x
        sta     value+1
        jmp     sloop

done:   lda     value
        ora     #$30            ; number to ASCII digit
        sta     str_count+2,y
        rts

powers: .word   10000, 1000, 100, 10
value:  .word   0
digit:  .byte   0
nonzero_flag:
        .byte   0
.endproc ; PopulateCount

str_count:
        PASCAL_STRING "       "

;;; ============================================================

.endscope ; file_copier

file_copier__Exec   := file_copier::Exec

        ENDSEG OverlayCopyDialog
