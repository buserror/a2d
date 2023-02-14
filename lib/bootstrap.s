;;; ============================================================
;;; Bootstrap
;;;
;;; Compiled as part of DeskTop and Selector
;;; ============================================================

        .org MODULE_BOOTSTRAP

;;; Install QuitRoutine to the ProDOS QUIT routine
;;; (Main, LCBANK2) and invoke it.

.proc InstallAsQuit
        MLIEntry := MLI

        ;; Patch the current prefix into `QuitRoutine`
        MLI_CALL GET_PREFIX, prefix_params

        src     := QuitRoutine
        dst     := SELECTOR
        .assert sizeof_QuitRoutine <= $200, error, "too large"

        bit     LCBANK2
        bit     LCBANK2

        ldy     #0
:       lda     src,y
        sta     dst,y
        lda     src+$100,y
        sta     dst+$100,y
        dey
        bne     :-

        bit     ROMIN2

        MLI_CALL QUIT, quit_params
        DEFINE_QUIT_PARAMS quit_params

        prefix_buffer := QuitRoutine + ::QuitRoutine__prefix_buffer_offset
        DEFINE_GET_PREFIX_PARAMS prefix_params, prefix_buffer
.endproc ; InstallAsQuit



;;; New QUIT routine. Gets relocated to $1000 by ProDOS before
;;; being executed.

.proc QuitRoutine
        .org ::SELECTOR_ORG

        MLIEntry := MLI

self:
        ;; --------------------------------------------------
        ;; Show 80-column text screen
        sta     TXTSET
        bit     ROMIN2
        jsr     SETVID
        jsr     SETKBD
        sta     CLR80VID
        sta     SETALTCHAR
        sta     CLR80STORE
        jsr     SLOT3ENTRY

        ;; IIgs: Reset shadowing
        sec
        jsr     IDROUTINE
        bcs     :+
        copy    #0, SHADOW
:
        ;; --------------------------------------------------
        ;; Display the loading string
retry:
        jsr     HOME
        lda     #kSplashVtab
        jsr     VTABZ
        lda     #(80 - kLoadingStringLength)/2
        sta     OURCH

        ldy     #0
:       lda     str_loading+1,y
        ora     #$80
        jsr     COUT
        iny
        cpy     str_loading
        bne     :-

        ;; Close all open files (just in case)
        MLI_CALL CLOSE, close_params

        ;; Initialize system bitmap
        ldx     #BITMAP_SIZE-1
        lda     #0
:       sta     BITMAP,x
        dex
        bpl     :-
        lda     #%00000001      ; ProDOS global page
        sta     BITMAP+BITMAP_SIZE-1
        lda     #%11001111      ; ZP, Stack, Text Page 1
        sta     BITMAP

        ;; Load the target module's loader at $2000
        MLI_CALL SET_PREFIX, prefix_params
        bne     prompt_for_system_disk
        MLI_CALL OPEN, open_params
        bne     ErrorHandler
        lda     open_params__ref_num
        sta     set_mark_params__ref_num
        sta     read_params__ref_num
        MLI_CALL SET_MARK, set_mark_params
        bne     ErrorHandler
        MLI_CALL READ, read_params
        bne     ErrorHandler
        MLI_CALL CLOSE, close_params
        bne     ErrorHandler

        ;; Invoke it
        jmp     kSegmentLoaderAddress

;;; ============================================================
;;; Display a string, and wait for Return keypress

prompt_for_system_disk:
        jsr     HOME
        lda     #kSplashVtab
        jsr     VTABZ
        lda     #(80 - kDiskPromptLength)/2
        sta     OURCH

        ldy     #0
:       lda     str_disk_prompt+1,y
        ora     #$80
        jsr     COUT
        iny
        cpy     str_disk_prompt
        bne     :-

wait:   sta     KBDSTRB
:       lda     KBD
        bpl     :-
        cmp     #CHAR_RETURN | $80
        bne     wait
        jmp     retry

;;; ============================================================
;;; Error Handler

.proc ErrorHandler
        brk                     ; just crash
.endproc ; ErrorHandler

;;; ============================================================
;;; Strings

kDiskPromptLength = .strlen(res_string_prompt_insert_system_disk)
str_disk_prompt:
        PASCAL_STRING res_string_prompt_insert_system_disk

kSplashVtab = 12
kLoadingStringLength = .strlen(QR_LOADSTRING)
str_loading:
        PASCAL_STRING QR_LOADSTRING

;;; ============================================================
;;; ProDOS MLI call param blocks

        io_buf := $1C00
        .assert io_buf + $400 <= kSegmentLoaderAddress, error, "memory overlap"

        DEFINE_OPEN_PARAMS open_params, filename, io_buf
        open_params__ref_num := open_params::ref_num
        DEFINE_SET_MARK_PARAMS set_mark_params, kSegmentLoaderOffset
        set_mark_params__ref_num := set_mark_params::ref_num
        DEFINE_READ_PARAMS read_params, kSegmentLoaderAddress, kSegmentLoaderLength
        read_params__ref_num := read_params::ref_num
        DEFINE_CLOSE_PARAMS close_params
        DEFINE_SET_PREFIX_PARAMS prefix_params, prefix_buffer

filename:
        PASCAL_STRING QR_FILENAME

;;; ============================================================
;;; Populated before this routine is installed
prefix_buffer:
        .res    64, 0

;;; Updated by DeskTop if parts of the path are renamed.
prefix_buffer_offset := prefix_buffer - self

.endproc ; QuitRoutine
sizeof_QuitRoutine = .sizeof(QuitRoutine)
QuitRoutine__prefix_buffer_offset := QuitRoutine::prefix_buffer_offset

;;; ============================================================

.assert .sizeof(QuitRoutine) + .sizeof(InstallAsQuit) <= kModuleBootstrapSize, error, "too large"
