;=======================================================================================
; basic65c.asm -- tokenized BASIC 65 PRG to 64tass 45GS02 assembly
;=======================================================================================
;
; Build: 64tass --cbm-prg -a src/basic65c.asm -o target/basic65c
;
; Runtime contract:
;   input:  source.prg      (tokenized BASIC PRG on unit 8)
;   output: out.asm,s,w     (64tass-compatible source on unit 8)
;
; This is a bootstrap compiler pass. It KERNAL_LOADs the tokenized BASIC PRG
; into a staging buffer, reads the PRG load address and line chain from RAM, and
; emits real assembly for the core BASIC65 token subset: integer
; variables/expressions, PRINT string literals and integer expressions, GOTO,
; GO TO, GOSUB, RETURN, END/STOP, SYS, POKE, and REM comments. Token values
; follow docs/basic65-tokens.md, including the CE xx and FE xx two-byte
; families.
; Unsupported or malformed statements become fatal line-numbered compiler
; diagnostics, and OUT.ASM is only replaced after a clean compile.
;=======================================================================================

        .cpu "45gs02"

;=======================================================================================
; KERNAL
;=======================================================================================

KERNAL_READST           = $FFB7
KERNAL_SETBNK           = $FF6B
KERNAL_SETLFS           = $FFBA
KERNAL_SETNAM           = $FFBD
KERNAL_OPEN             = $FFC0
KERNAL_CLOSE            = $FFC3
KERNAL_CHKIN            = $FFC6
KERNAL_CHKOUT           = $FFC9
KERNAL_CLRCHN           = $FFCC
KERNAL_CHRIN            = $FFCF
KERNAL_CHROUT           = $FFD2
KERNAL_LOAD             = $FFD5

source_ptr              = $F7
str_ptr                 = $FB
POOL_BANK               = $04
POOL_BASE               = $C000 ; above any realistic tokenized source
LINETAB_B4              = $F400 ; line records, bank 4 ($e000 = LBLTAB, $f000-$f3ff = string/branch tables; $f400+ is free)

LFN_OUT                 = 2
LFN_RT                  = 3
LFN_CMD                 = 15
DEVICE_DISK             = 8

SOURCE_BANK             = $04
SOURCE_BUF              = $0000
SOURCE_BODY             = SOURCE_BUF + 2

TOK_END                 = $80
TOK_FOR                 = $81
TOK_NEXT                = $82
TOK_DATA                = $83
TOK_INPUT               = $85
TOK_READ                = $87
TOK_DIM                 = $86
TOK_LET                 = $88
TOK_GOTO                = $89
TOK_IF                  = $8B
TOK_RESTORE             = $8C
TOK_GOSUB               = $8D
TOK_RETURN              = $8E
TOK_REM                 = $8F
TOK_STOP                = $90
TOK_ON                  = $91
TOK_POKE                = $97
TOK_PRINT_HASH          = $98
TOK_PRINT               = $99
TOK_SYS                 = $9E
TOK_GET                 = $A1
TOK_PEEK                = $C2
TOK_RND                 = $BB
TOK_SQR                 = $BA
TOK_ASC                 = $C6
TOK_POS                 = $B9
TOK_TAB                 = $A3
TOK_POW                 = $AE
TOK_CLR                 = $9C
TOK_HEX_STR             = $D2
TOK_DEC                 = $D1
TOK_INSTR               = $D4
TOK_OPEN                = $9F
TOK_CLOSE               = $A0
TOK_INPUT_HASH          = $84
TOK_TRAP                = $D7
TOK_RESUME              = $D6
TOK_SOUND               = $DA
TOK_JOY                 = $CF
TOK_XOR                 = $E9
TOK_HEADER              = $F1
TOK_SCRATCH             = $F2
TOK_COLLECT             = $F3
TOK_COPY                = $F4
TOK_RENAME              = $F5
TOK_COLOR               = $E7
TOK_EXT_E0              = $E0
TOK_WAIT                = $92
TOK_FRE                 = $B8
TOK_USR                 = $B7
TOK_ERR_STR             = $D3
TOK_LOG                 = $BC
TOK_EXP_FN              = $BD
TOK_COS                 = $BE
TOK_SIN                 = $BF
TOK_TAN                 = $C0
TOK_ATN                 = $C1

.weak
TEXT_EMITTER = 1
.endweak
TOK_VOL                 = $DB
TOK_SPC                 = $A6
TOK_LEN                 = $C3
TOK_STR_STR             = $C4
TOK_VAL                 = $C5
TOK_SGN                 = $B4
TOK_INT                 = $B5
TOK_ABS                 = $B6
TOK_CHR_STR             = $C7
TOK_LEFT_STR            = $C8
TOK_RIGHT_STR           = $C9
TOK_MID_STR             = $CA
TOK_TO                  = $A4
TOK_THEN                = $A7
TOK_NOT                 = $A8
TOK_STEP                = $A9
TOK_PLUS                = $AA
TOK_MINUS               = $AB
TOK_MUL                 = $AC
TOK_DIV                 = $AD
TOK_AND                 = $AF
TOK_OR                  = $B0
TOK_GT                  = $B1
TOK_EQUAL               = $B2
TOK_LT                  = $B3
TOK_GO                  = $CB
TOK_ELSE                = $D5
TOK_DO                  = $EB
TOK_LOOP                = $EC
TOK_EXIT                = $ED
TOK_UNTIL               = $FC
TOK_WHILE               = $FD
TOK_KEY                 = $F9
TOK_EXT_CE              = $CE
TOK_EXT_FE              = $FE
TOK_CE_WPEEK            = $10
TOK_FE_WPOKE            = $1D
TOK_FE_BEGIN            = $18
TOK_FE_BEND             = $19

COND_EQ                 = 1
COND_NE                 = 2
COND_LT                 = 3
COND_LE                 = 4
COND_GT                 = 5
COND_GE                 = 6
COND_TRUTH              = 7
ON_MODE_GOTO            = 1
ON_MODE_GOSUB           = 2

ASCII_UPPER_A           = $41
ASCII_UPPER_F           = $46
ASCII_UPPER_Z           = $5A
ASCII_LOWER_A           = $61
ASCII_LOWER_F           = $66

LINE_BUF_MAX            = 240
DEF_MAX                 = 16
FILENAME_MAX            = 31
.if TEXT_EMITTER
LINE_MAX                = 400   ; checked build: tables extend past $c000
.else
LINE_MAX                = 400
.fi
BRANCH_MAX              = 128
FOR_STACK_MAX           = 16
IF_STACK_MAX            = 16
DO_STACK_MAX            = 16
FOR_MAX                 = 64
DO_MAX                  = 64
ARRAY_RANK_MAX          = 6
.if TEXT_EMITTER
DATA_MAX                = 128   ; checked build: tables extend past $c000
.else
DATA_MAX                = 128
.fi
.if TEXT_EMITTER
DATA_LINE_MAX           = 64    ; checked build: tables extend past $c000
.else
DATA_LINE_MAX           = 64
.fi
DATA_TYPE_INT           = 0
DATA_TYPE_STRING        = 1
STRING_MAX              = 240 ; offset tables live in bank 4
STRING_POOL_MAX         = $2000 ; pool lives in bank 4, not the image

.if TEXT_EMITTER
SYM_MAX                 = 64    ; checked build: tables extend past $c000
.else
SYM_MAX                 = 128
.fi
VAR_KIND_SCALAR         = 0
VAR_KIND_ARRAY1         = 1
VAR_TYPE_INT            = 1
; Plain numeric variables are tracked as FLOAT so A and A% are distinct.
; Plain numeric scalars use a tagged slot; decimal float math is still future work.
VAR_TYPE_FLOAT          = 2
VAR_TYPE_STRING         = 3
NUM_TAG_INT             = 0
NUM_TAG_FLOAT_REF       = 1
STRING_REF_HEAP         = 0
STRING_REF_LITERAL      = 1
VAR_BANK                = $01
VAR_MB                  = $00
; Bank 1 reserved: $0000-$1fff for C65 KERNAL/DOS, $f800-$ffff for color RAM.
VAR_HEAP_START          = $2000
VAR_HEAP_LIMIT          = $F800
VAR_DESC_SIZE           = 16
VAR_DESC_VALUE_OFFSET   = 8

;=======================================================================================
; BASIC 65 stub - BANK 0 : SYS 8210 ($2012)
;=======================================================================================

        * = $2001

        .word (+), 2026
        .byte $fe, $02, $30
        .byte ':'
        .byte $9e
        .text "8210"
        .byte 0
+       .word 0

        * = $2012

;=======================================================================================
; Main
;=======================================================================================

main:
        cld
        cli
        lda $d030               ; ROM state before anything else: the
        sta d030_save           ; CC_ wrappers key off it
        lda #0
        sta cc_mode             ; 0 = ROMs stay as booted
        ldx #0                  ; the $c000 table block is not
        txa                     ; reliably loaded -- give the compiler
_main_clr_hi:                   ; the zero-init state it expects
        sta $c000,x
        sta $c100,x
        sta $c200,x
        sta $c300,x
        sta $c400,x
        sta $c500,x
        sta $c600,x
        sta $c700,x
        sta $c800,x
        sta $c900,x
        sta $ca00,x
        sta $cb00,x
        sta $cc00,x
        sta $cd00,x
        sta $ce00,x
        sta $cf00,x
        inx
        bne _main_clr_hi
        jsr close_work_files
        lda #0
        sta compile_error
        sta error_count
        sta sym_count
        sta line_count
        sta line_count+1
        sta branch_count
        sta data_count
        sta data_line_count
        sta string_count
        sta string_pool_next_lo
        sta string_pool_next_hi
        sta backend_mode
        sta backend_error
        sta flt_lit_count
        sta trap_used
        sta snd_used
        sta col_used
        sta fio_used
        sta math_used
        sta fgoto_used
        sta bank_used
        sta gfx_used
        sta def_count
        lda #>RT_PROGBASE
        sta prog_base_hi
        jsr reset_emit_counters
        lda #<VAR_HEAP_START
        sta var_heap_next_lo
        lda #>VAR_HEAP_START
        sta var_heap_next_hi

        lda #<msg_banner
        ldy #>msg_banner
        jsr screen_zstr

        lda #<msg_opening_in
        ldy #>msg_opening_in
        jsr screen_zstr
        jsr prompt_source_name
        jsr show_loading_source
        jsr load_source
        bcc +
        lda #<msg_open_in_fail
        ldy #>msg_open_in_fail
        jsr screen_zstr
        rts

+       lda d030_save           ; the ROM shadow at $c000 hides the
        and #%11000111          ; scratch tables (reads see ROM, writes
        sta $d030               ; fall through) -- bank $8000/$a000/
        lda #1                  ; $c000 out for the compile; keyboard
        sta cc_mode             ; input is done. The CC_ wrappers put
        lda #<msg_scanning_in   ; the ROMs back around KERNAL file ops
        ldy #>msg_scanning_in
        jsr screen_zstr
        jsr read_prg_header
        jsr init_source_reader
        jsr scan_program
        lda compile_error
        bne _main_compile_failed
        jsr validate_branch_targets
        lda compile_error
        bne _main_compile_failed
        jsr run_size_pass
        lda compile_error
        bne _main_compile_failed
        jsr report_size_pass
        lda compile_error       ; the size report enforces the window
        bne _main_compile_failed

.if TEXT_EMITTER
        lda #<msg_opening_out
        ldy #>msg_opening_out
        jsr screen_zstr
        jsr open_output
        bcc +
        jsr CC_CLRCHN
        lda #<msg_open_out_fail
        ldy #>msg_open_out_fail
        jsr screen_zstr
        jmp _main_rom_in

+       jsr select_output
        jsr emit_generated_header
        jsr emit_prg_header_comment
        jsr show_compile_start
        jsr init_source_reader
        jsr compile_program
        lda compile_error
        bne _main_output_failed
        jsr emit_generated_tail
        lda compile_error
        bne _main_output_failed

        jsr CC_CLRCHN
        lda #LFN_OUT
        jsr CC_CLOSE
        jsr CC_CLRCHN
        jsr finalize_output
        bcc +
        lda #<msg_finalize_fail
        ldy #>msg_finalize_fail
        jsr screen_zstr
        jmp _main_rom_in

+       lda #13
        jsr CC_CHROUT
.fi

        lda #<msg_writing_prg
        ldy #>msg_writing_prg
        jsr screen_zstr
        jsr emit_binary_output
        bcc _main_prg_ok
        lda #<msg_bin_write_fail
        ldy #>msg_bin_write_fail
        jsr screen_zstr
        lda backend_error       ; code + context for diagnosis
        jsr out_hex_byte
        lda #' '+0
        jsr CC_CHROUT
        lda backend_error_ptr+1
        jsr out_hex_byte
        lda backend_error_ptr
        jsr out_hex_byte
        lda #13
        jsr CC_CHROUT
        bra _main_done_ok

_main_prg_ok:
        lda #<msg_wrote_prg
        ldy #>msg_wrote_prg
        jsr screen_zstr

_main_done_ok:
.if TEXT_EMITTER
        lda #<msg_done
        ldy #>msg_done
        jsr screen_zstr
.fi
        jmp _main_rom_in

_main_compile_failed:
        lda #<msg_compile_failed
        ldy #>msg_compile_failed
        jsr screen_zstr
_main_rom_in:
        lda #0
        sta cc_mode
        lda d030_save
        sta $d030
        rts


_main_output_failed:
        jsr CC_CLRCHN
        lda #LFN_OUT
        jsr CC_CLOSE
        jsr scratch_output
        jsr CC_CLRCHN
        lda #13
        jsr CC_CHROUT
        lda #<msg_compile_failed
        ldy #>msg_compile_failed
        jsr screen_zstr
        jmp _main_rom_in

; KERNAL channel/file calls need the boot ROM set (the C65 DOS lives
; there); table access needs it banked out. Each wrapper banks in,
; calls, and returns to whatever the current mode wants, preserving
; A and all flags (open/read status travel in carry and Z).
cc_rom_in:
        pha
        lda d030_save
        sta $d030
        pla
        rts
cc_rom_out:
        pha
        lda cc_mode
        beq _ccro_plain
        lda d030_save
        and #%11000111
        sta $d030
        pla
        rts
_ccro_plain:
        lda d030_save
        sta $d030
        pla
        rts

CC_OPEN:
        jsr cc_rom_in
        jsr KERNAL_OPEN
        php
        jsr cc_rom_out
        plp
        rts
CC_CLOSE:
        jsr cc_rom_in
        jsr KERNAL_CLOSE
        php
        jsr cc_rom_out
        plp
        rts
CC_CHKIN:
        jsr cc_rom_in
        jsr KERNAL_CHKIN
        php
        jsr cc_rom_out
        plp
        rts
CC_CHKOUT:
        jsr cc_rom_in
        jsr KERNAL_CHKOUT
        php
        jsr cc_rom_out
        plp
        rts
CC_CLRCHN:
        jsr cc_rom_in
        jsr KERNAL_CLRCHN
        php
        jsr cc_rom_out
        plp
        rts
CC_CHRIN:
        jsr cc_rom_in
        jsr KERNAL_CHRIN
        php
        jsr cc_rom_out
        plp
        rts
CC_CHROUT:
        jsr cc_rom_in
        jsr KERNAL_CHROUT
        php
        jsr cc_rom_out
        plp
        rts
CC_LOAD:
        jsr cc_rom_in
        jsr KERNAL_LOAD
        php
        jsr cc_rom_out
        plp
        rts
; these four only store KERNAL state and should not enter the DOS,
; but real-hardware ROMs may differ from xemu -- wrapped on principle
CC_SETLFS:
        jsr cc_rom_in
        jsr KERNAL_SETLFS
        php
        jsr cc_rom_out
        plp
        rts
CC_SETNAM:
        jsr cc_rom_in
        jsr KERNAL_SETNAM
        php
        jsr cc_rom_out
        plp
        rts
CC_SETBNK:
        jsr cc_rom_in
        jsr KERNAL_SETBNK
        php
        jsr cc_rom_out
        plp
        rts
CC_READST:
        jsr cc_rom_in
        jsr KERNAL_READST
        php
        jsr cc_rom_out
        plp
        rts

show_compile_line:
        ldx backend_mode
        beq +
        rts
+       jsr CC_CLRCHN
        lda line_no_lo
        sta screen_num_lo
        lda line_no_hi
        sta screen_num_hi
        jsr screen_uint
        lda #'.'
        jsr CC_CHROUT
        lda #'.'
        jsr CC_CHROUT
        ldx #LFN_OUT
        jsr CC_CHKOUT
        rts

show_compile_start:
        ldx backend_mode
        beq +
        rts
+       jsr CC_CLRCHN
        lda #<msg_compiling_start
        ldy #>msg_compiling_start
        jsr screen_zstr
        ldx #LFN_OUT
        jsr CC_CHKOUT
        rts

; per-emission-pass label allocation state; the size pass and the text pass
; must allocate identical label ids, so both start from a clean slate
reset_emit_counters:
        lda #0
        sta seg_has_elig        ; overlay planner state (size pass)
        sta seg_base_hi         ; hi 0 = not yet started
        ldx #1
        stx seg_count
        sta if_label_next_lo
        sta if_label_next_hi
        sta array_label_next_lo
        sta array_label_next_hi
        sta on_label_next_lo
        sta on_label_next_hi
        sta for_label_next
        sta do_label_next
        sta for_sp
        sta do_sp
        sta if_sp
        jsr lea_rst
        sta pending_kind
        sta const_state
        sta expr_type
        sta begin_sp
        sta if_begin_taken
        rts

; walk pass 2 in size mode: no output, but every template record and patch
; slot advances bin_pc, line addresses are recorded, and the tail table
; addresses are captured for the future emit pass
run_size_pass:
        lda #BK_SIZE
        sta backend_mode
        jsr reset_emit_counters
        ldx #0                  ; runtime level: highest section needed
        lda fio_used
        beq +
        ldx #1
+       lda math_used
        beq +
        ldx #2
+       lda snd_used
        beq +
        ldx #3
+       stx rt_level
        lda rtpbtab,x
        sta prog_base_hi
        lda rttrunclo,x
        sta rt_trunc
        lda rttrunchi,x
        sta rt_trunc+1
        lda #0
        sta bin_pc
        lda prog_base_hi
        sta bin_pc+1
        jsr emit_generated_header
        jsr init_source_reader
        jsr compile_program
        lda compile_error
        bne _run_size_pass_done
        jsr emit_generated_tail
_run_size_pass_done:
        lda bin_pc
        sta bin_size_end
        lda bin_pc+1
        sta bin_size_end+1
        lda seg_count           ; preserve the overlay plan across the
        sta seg_plan_result     ; trailing counter reset
        lda #BK_TEXT
        sta backend_mode
        jsr reset_emit_counters
        rts

;=======================================================================================
; Native OUT.PRG writer: stream runtime.prg from disk (its load address is
; the PRG header), pad zeros up to progbase, then run pass 2 in emit mode.
; The result must land exactly on the size-pass prediction.
;=======================================================================================

emit_binary_output:
        jsr open_binary_output
        bcc +
        lda #<msg_bin_disk_fail
        ldy #>msg_bin_disk_fail
        jsr screen_zstr
        bra _ebo_open_fail
+       jsr copy_runtime_image
        bcs _ebo_write_fail
        lda #BK_EMIT
        sta backend_mode
        jsr reset_emit_counters
        jsr select_output
        jsr emit_generated_header
        jsr init_source_reader
        jsr compile_program
        jsr emit_generated_tail
        lda #BK_TEXT
        sta backend_mode
        lda backend_error
        bne _ebo_write_fail
        lda bin_pc
        cmp bin_size_end
        bne _ebo_mismatch
        lda bin_pc+1
        cmp bin_size_end+1
        bne _ebo_mismatch
        jsr close_binary_files
        jsr finalize_binary_output
        bcc +
        lda #<msg_bin_disk_fail
        ldy #>msg_bin_disk_fail
        jsr screen_zstr
        bra _ebo_open_fail
+       clc
        rts

_ebo_mismatch:
        jsr close_binary_files
        lda #<msg_bin_mismatch
        ldy #>msg_bin_mismatch
        jsr screen_zstr
        sec
        rts

_ebo_write_fail:
        lda #BK_TEXT
        sta backend_mode
        jsr close_binary_files
_ebo_open_fail:
        sec
        rts

close_binary_files:
        jsr CC_CLRCHN
        lda #LFN_OUT
        jsr CC_CLOSE
        lda #LFN_RT
        jsr CC_CLOSE
        jsr CC_CLRCHN
        rts

; open the command channel, read DS into screen output; C set on a
; nonzero DOS status (first digit != '0')
check_ds:
        jsr CC_CLRCHN
        lda #LFN_CMD
        ldx #DEVICE_DISK
        ldy #LFN_CMD
        jsr CC_SETLFS
        lda #0
        ldx #0
        jsr CC_SETBNK
        lda #0
        jsr CC_SETNAM
        jsr CC_OPEN
        bcs _check_ds_bad
        ldx #LFN_CMD
        jsr CC_CHKIN
        bcs _check_ds_bad
        jsr CC_CHRIN
        sta ds_first
        pha
        cmp #'1'                ; 0x = OK; 1x.. = error
        bcc _check_ds_drain
        jsr CC_CLRCHN           ; error: echo the full status line
        lda #13
        jsr CC_CHROUT
        ldx #LFN_CMD
        jsr CC_CHKIN
        pla
        pha
_check_ds_echo:
        pha
        jsr CC_CLRCHN
        pla
        jsr CC_CHROUT
        ldx #LFN_CMD
        jsr CC_CHKIN
        jsr CC_CHRIN
        cmp #13
        bne _check_ds_echo
        jsr CC_CLRCHN
        lda #13
        jsr CC_CHROUT
        bra _check_ds_close
_check_ds_drain:
        jsr CC_CHRIN            ; consume the rest of the line
        cmp #13
        bne _check_ds_drain
_check_ds_close:
        jsr CC_CLRCHN
        lda #LFN_CMD
        jsr CC_CLOSE
        jsr CC_CLRCHN
        pla
        cmp #'1'
        bcs _check_ds_err
        clc
        rts
_check_ds_err:
        sec
        rts
_check_ds_bad:
        jsr CC_CLRCHN
        lda #LFN_CMD
        jsr CC_CLOSE
        jsr CC_CLRCHN
        sec
        rts

open_binary_output:
        lda #<scratch_outb_name
        ldy #>scratch_outb_name
        ldx #scratch_outb_name_end - scratch_outb_name
        jsr disk_command
        jsr check_ds            ; write-protect/disk-full surfaces on
        bcs _open_binary_fail   ; the scratch, echoed in DOS's words

        lda #LFN_OUT
        ldx #DEVICE_DISK
        ldy #1
        jsr CC_SETLFS

        lda #0
        ldx #0
        jsr CC_SETBNK

        lda #outb_name_end - outb_name
        ldx #<outb_name
        ldy #>outb_name
        jsr CC_SETNAM

        jsr CC_OPEN
        bcs _open_binary_fail
        jsr CC_READST
        bne _open_binary_fail
        clc
        rts

_open_binary_fail:
        jsr close_binary_files
        sec
        rts

finalize_binary_output:
        lda #<scratch_prg_name
        ldy #>scratch_prg_name
        ldx #scratch_prg_name_end - scratch_prg_name
        jsr disk_command
        bcs _finalize_binary_fail
        lda #<rename_prg_name
        ldy #>rename_prg_name
        ldx #rename_prg_name_end - rename_prg_name
        jsr disk_command
        rts

_finalize_binary_fail:
        sec
        rts

; stream runtime.prg verbatim (load address first) into the output file,
; then pad with zeros until bin_pc reaches progbase ($5000)
copy_runtime_image:
        lda #0
        sta rt_first_chunk
        sta rt_first_write
        lda #LFN_RT
        ldx #DEVICE_DISK
        ldy #4
        jsr CC_SETLFS

        lda #0
        ldx #0
        jsr CC_SETBNK

        lda #rt_name_end - rt_name
        ldx #<rt_name
        ldy #>rt_name
        jsr CC_SETNAM

        jsr CC_OPEN
        bcs _copy_runtime_fail
        jsr CC_READST
        bne _copy_runtime_fail

        ; the file's two load-address bytes become the PRG header
        lda #<($2001 - 2)
        sta bin_pc
        lda #>($2001 - 2)
        sta bin_pc+1

_copy_runtime_chunk:
        ldx #LFN_RT
        jsr CC_CHKIN
        bcs _copy_runtime_fail
        ldy #0
_copy_runtime_read:
        jsr CC_CHRIN
        sta line_buf,y
        iny
        jsr CC_READST
        sta rt_status
        bne _copy_runtime_read_done
        cpy #LINE_BUF_MAX
        bcc _copy_runtime_read
_copy_runtime_read_done:
        sty rt_chunk_len
        lda rt_first_chunk
        bne _crc_not_first
        lda #1
        sta rt_first_chunk
        lda rt_chunk_len        ; a real runtime image is KBs; a
        cmp #16                 ; missing file reads as 0-1 bytes
        bcc _copy_runtime_missing
_crc_not_first:
        jsr CC_CLRCHN
        ldx #LFN_OUT
        jsr CC_CHKOUT           ; a failed write-open (full or
        bcs _copy_runtime_wfail ; protected disk) surfaces here
        ldy #0
_copy_runtime_write:
        cpy rt_chunk_len
        beq _copy_runtime_written
        lda bin_pc+1            ; truncate at this level's boundary
        cmp rt_trunc+1
        bcc _copy_runtime_keep
        bne _copy_runtime_written
        lda bin_pc
        cmp rt_trunc
        bcs _copy_runtime_written
_copy_runtime_keep:
        lda bin_pc+1
        cmp #>RT_PBHI
        bne _copy_runtime_plain
        lda bin_pc
        cmp #<RT_PBHI
        bne _copy_runtime_plain
        lda prog_base_hi        ; patch rtpbhi with this program's base
        bra _copy_runtime_put
_copy_runtime_plain:
        lda line_buf,y
_copy_runtime_put:
        jsr bin_write_byte
        lda rt_first_write      ; the DOS reports a failed write-open
        bne _crw_checked        ; (protected/full disk) only once data
        lda #1                  ; flows: probe ST on the first byte
        sta rt_first_write
        jsr CC_READST
        bne _copy_runtime_wfail
_crw_checked:
        iny
        bra _copy_runtime_write
_copy_runtime_written:
        lda rt_status
        beq _copy_runtime_chunk
        and #$40
        beq _copy_runtime_fail   ; error bits without EOF

_copy_runtime_pad:
        lda bin_pc+1
        cmp prog_base_hi
        bcs _copy_runtime_done
        lda #0
        jsr bin_write_byte
        bra _copy_runtime_pad

_copy_runtime_done:
        clc
        rts

_copy_runtime_wfail:
        jsr CC_CLRCHN
        lda #<msg_bin_disk_fail
        ldy #>msg_bin_disk_fail
        jsr screen_zstr
        bra _copy_runtime_fail
_copy_runtime_missing:
        lda #<msg_rt_missing
        ldy #>msg_rt_missing
        jsr screen_zstr
_copy_runtime_fail:
        sec
        rts

report_size_pass:
        lda backend_error
        beq +
        pha
        lda #<msg_backend_error
        ldy #>msg_backend_error
        jsr screen_zstr
        pla
        jsr out_hex_byte
        lda #' '
        jsr CC_CHROUT
        lda backend_error_ptr+1
        jsr out_hex_byte
        lda backend_error_ptr
        jsr out_hex_byte
        lda #13
        jsr CC_CHROUT
        rts
+       lda #<msg_bin_size
        ldy #>msg_bin_size
        jsr screen_zstr
        lda bin_pc+1
        jsr out_hex_byte
        lda bin_pc
        jsr out_hex_byte
        lda #13
        jsr CC_CHROUT
        ; enforce the program-window cap natively too: the emitted
        ; .cerror only protects PC-side links, and an on-device
        ; compile must not silently write an image that runs into
        ; the i/o space (or the $c000 screen codes in gfx programs)
        ldx #$d0
        lda gfx_used
        beq +
        ldx #$c0
+       stx size_cap_hi
        lda bin_pc+1
        cmp size_cap_hi
        bcc _rsp_fits
        bne _rsp_over
        lda bin_pc              ; exactly at the cap is still legal
        beq _rsp_fits
_rsp_over:
        lda #<msg_error_too_large
        ldy #>msg_error_too_large
        jsr screen_zstr
        lda #<msg_overlay_plan  ; "overlay: $NN" segments, or $00
        ldy #>msg_overlay_plan  ; when one structure exceeds the window
        jsr screen_zstr
        lda seg_plan_result
        jsr out_hex_byte
        lda #13
        jsr CC_CHROUT
        lda #1
        sta compile_error
        inc error_count
_rsp_fits:
        rts
size_cap_hi:
        .byte 0

fatal_error_zstr:
        sta diag_msg_lo
        sty diag_msg_hi
        lda #1
        sta compile_error
        inc error_count
        jsr CC_CLRCHN
        lda #<msg_error_line
        ldy #>msg_error_line
        jsr screen_zstr
        lda line_no_lo
        sta screen_num_lo
        lda line_no_hi
        sta screen_num_hi
        jsr screen_uint
        lda #<msg_error_colon
        ldy #>msg_error_colon
        jsr screen_zstr
        lda diag_msg_lo
        ldy diag_msg_hi
        jsr screen_zstr
        rts

fatal_statement_error:
        jsr fatal_error_zstr
        jsr line_skip_to_stmt_end
        rts

fatal_line_error:
        jsr fatal_error_zstr
        jsr line_skip_to_end
        rts

screen_uint:
        lda #0
        sta screen_started
        lda #<$2710
        ldy #>$2710
        jsr screen_digit
        lda #<$03e8
        ldy #>$03e8
        jsr screen_digit
        lda #<$0064
        ldy #>$0064
        jsr screen_digit
        lda #<$000a
        ldy #>$000a
        jsr screen_digit
        lda screen_num_lo
        clc
        adc #'0'
        jsr CC_CHROUT
        rts

screen_digit:
        sta screen_div_lo
        sty screen_div_hi
        lda #'0'
        sta screen_digit_value

_screen_digit_loop:
        lda screen_num_hi
        cmp screen_div_hi
        bcc _screen_digit_done
        bne _screen_digit_sub
        lda screen_num_lo
        cmp screen_div_lo
        bcc _screen_digit_done

_screen_digit_sub:
        sec
        lda screen_num_lo
        sbc screen_div_lo
        sta screen_num_lo
        lda screen_num_hi
        sbc screen_div_hi
        sta screen_num_hi
        inc screen_digit_value
        bra _screen_digit_loop

_screen_digit_done:
        lda screen_digit_value
        cmp #'0'
        bne _screen_digit_emit
        lda screen_started
        beq _screen_digit_return
        lda screen_digit_value

_screen_digit_emit:
        sta screen_digit_value
        lda #1
        sta screen_started
        lda screen_digit_value
        jsr CC_CHROUT

_screen_digit_return:
        rts

select_output:
        ldx #LFN_OUT
        jsr CC_CHKOUT
        rts

;=======================================================================================
; File I/O
;=======================================================================================

prompt_source_name:
        jsr CC_CLRCHN
        lda #<msg_source_prompt
        ldy #>msg_source_prompt
        jsr screen_zstr
        lda #0
        sta source_filename_len
        ldx #0

_prompt_source_loop:
        jsr CC_CHRIN
        cmp #13
        beq _prompt_source_done
        cpx #FILENAME_MAX
        bcs _prompt_source_loop
        sta source_filename_buf,x
        inx
        stx source_filename_len
        bra _prompt_source_loop

_prompt_source_done:
        lda #13
        jsr CC_CHROUT
        lda source_filename_len
        bne _prompt_source_terminate
        jsr use_default_source_name

_prompt_source_terminate:
        ldx source_filename_len
        lda #0
        sta source_filename_buf,x
        rts

use_default_source_name:
        ldx #0

_default_source_loop:
        cpx #source_name_end - source_name
        beq _default_source_done
        lda source_name,x
        sta source_filename_buf,x
        inx
        bra _default_source_loop

_default_source_done:
        stx source_filename_len
        rts

show_loading_source:
        jsr CC_CLRCHN
        lda #<msg_loading_source_prefix
        ldy #>msg_loading_source_prefix
        jsr screen_zstr
        lda #<source_filename_buf
        ldy #>source_filename_buf
        jsr screen_zstr
        lda #13
        jsr CC_CHROUT
        rts

load_source:
        lda #SOURCE_BANK
        ldx #0
        jsr CC_SETBNK

        lda #0
        ldx #DEVICE_DISK
        ldy #0
        jsr CC_SETLFS

        lda source_filename_len
        ldx #<source_filename_buf
        ldy #>source_filename_buf
        jsr CC_SETNAM

        lda #$40                         ; raw load to X/Y, PRG header included
        ldx #<SOURCE_BUF
        ldy #>SOURCE_BUF
        jsr CC_LOAD
        bcs _load_source_fail
        stx source_end_lo
        sty source_end_hi
        jsr CC_CLRCHN
        clc
        rts

_load_source_fail:
        jsr CC_CLRCHN
        sec
        rts

open_output:
        jsr close_work_files
        jsr scratch_output

        lda #LFN_OUT
        ldx #DEVICE_DISK
        ldy #1
        jsr CC_SETLFS

        lda #0
        ldx #0
        jsr CC_SETBNK

        lda #output_name_end - output_name
        ldx #<output_name
        ldy #>output_name
        jsr CC_SETNAM

        jsr CC_OPEN
        bcs _open_output_fail
        jsr CC_READST
        bne _open_output_fail

        ldx #LFN_OUT
        jsr CC_CHKOUT
        bcs _open_output_fail
        jsr CC_READST
        bne _open_output_fail
        clc
        rts

_open_output_fail:
        jsr close_work_files
        sec
        rts

close_work_files:
        jsr CC_CLRCHN
        lda #LFN_OUT
        jsr CC_CLOSE
        lda #LFN_RT
        jsr CC_CLOSE
        lda #LFN_CMD
        jsr CC_CLOSE
        jsr CC_CLRCHN
        rts

scratch_output:
        lda #<scratch_name
        ldy #>scratch_name
        ldx #scratch_name_end - scratch_name
        jsr disk_command
        rts

finalize_output:
        lda #<scratch_final_name
        ldy #>scratch_final_name
        ldx #scratch_final_name_end - scratch_final_name
        jsr disk_command
        bcs _finalize_fail
        lda #<rename_name
        ldy #>rename_name
        ldx #rename_name_end - rename_name
        jsr disk_command
        rts

_finalize_fail:
        sec
        rts

disk_command:
        sta str_ptr
        sty str_ptr+1
        stx byte_value
        jsr CC_CLRCHN
        lda #LFN_CMD
        ldx #DEVICE_DISK
        ldy #LFN_CMD
        jsr CC_SETLFS

        lda #0
        ldx #0
        jsr CC_SETBNK

        lda #0
        ldx #0
        ldy #0
        jsr CC_SETNAM

        jsr CC_OPEN
        bcs _disk_command_fail
        ldx #LFN_CMD
        jsr CC_CHKOUT
        bcs _disk_command_fail
        ldy #0
_disk_command_loop:
        cpy byte_value
        beq _disk_command_sent
        lda (str_ptr),y
        jsr CC_CHROUT
        iny
        bra _disk_command_loop

_disk_command_sent:
        jsr CC_READST
        bne _disk_command_fail
        lda #0
        sta disk_status
        bra _disk_command_done

_disk_command_fail:
        lda #1
        sta disk_status

_disk_command_done:
        jsr CC_CLRCHN
        lda #LFN_CMD
        jsr CC_CLOSE
        jsr CC_CLRCHN
        lda disk_status
        beq _disk_command_ok
        sec
        rts

_disk_command_ok:
        clc
        rts

read_byte:
        ldz #0
        lda [source_ptr],z
        inc source_ptr
        bne +
        inc source_ptr+1
        bne +
        inc source_ptr+2
+       rts

init_source_raw_reader:
        lda #<SOURCE_BUF
        sta source_ptr
        lda #>SOURCE_BUF
        sta source_ptr+1
        lda #SOURCE_BANK
        sta source_ptr+2
        lda #0
        sta source_ptr+3
        rts

init_source_reader:
        lda #<SOURCE_BODY
        sta source_ptr
        lda #>SOURCE_BODY
        sta source_ptr+1
        lda #SOURCE_BANK
        sta source_ptr+2
        lda #0
        sta source_ptr+3
        rts

;=======================================================================================
; PRG reader
;=======================================================================================

read_prg_header:
        jsr init_source_raw_reader
        jsr read_byte
        sta prg_load_lo
        jsr read_byte
        sta prg_load_hi
        rts

emit_prg_header_comment:
        ldx backend_mode
        beq +
        rts
+       lda #<out_comment_load_addr
        ldy #>out_comment_load_addr
        jsr out_zstr
        lda prg_load_hi
        jsr out_hex_byte
        lda prg_load_lo
        jsr out_hex_byte
        jsr out_cr
        jsr out_cr
        rts

compile_program:
_compile_program_next:
        jsr read_byte
        sta next_line_lo
        jsr read_byte
        sta next_line_hi
        lda next_line_lo
        ora next_line_hi
        beq _compile_program_done

        jsr read_byte
        sta line_no_lo
        sta number_lo
        jsr read_byte
        sta line_no_hi
        sta number_hi

        jsr read_line_body
        jsr show_compile_line
        jsr emit_line_label
        jsr emit_line_track
        jsr compile_line
        lda compile_error
        bne _compile_program_done
        bra _compile_program_next

_compile_program_done:
        rts

read_line_body:
        lda #0
        sta line_len
        sta line_overflow
_read_line_loop:
        jsr read_byte
        cmp #0
        beq _read_line_done

        ldx line_len
        cpx #LINE_BUF_MAX
        bcs _read_line_overflow
        sta line_buf,x
        inc line_len
        bra _read_line_loop

_read_line_overflow:
        lda #1
        sta line_overflow
        bra _read_line_loop

_read_line_done:
        rts

;=======================================================================================
; Pass 1 scanner
;=======================================================================================

scan_program:
_scan_program_next:
        jsr read_byte
        sta next_line_lo
        jsr read_byte
        sta next_line_hi
        lda next_line_lo
        ora next_line_hi
        beq _scan_program_done

        jsr read_byte
        sta line_no_lo
        jsr read_byte
        sta line_no_hi

        jsr read_line_body
        lda line_overflow
        beq +
        lda #<msg_error_line_overflow
        ldy #>msg_error_line_overflow
        jsr fatal_error_zstr
+       jsr record_line_number
        jsr scan_line_variables
        jsr scan_line_branches
        bra _scan_program_next

_scan_program_done:
        rts

scan_line_variables:
        lda #0
        sta line_idx
        sta scan_pmode

_scan_vars_loop:
        jsr line_at_end
        bcs _scan_vars_done
        jsr line_get
        cmp #'"'
        beq _scan_vars_string
        cmp #'$'
        beq _scan_vars_hex
        cmp #'0'
        bcc _scan_vars_not_decimal
        cmp #'9' + 1
        bcc _scan_vars_decimal

_scan_vars_not_decimal:
        cmp #TOK_DIM
        beq _scan_vars_dim
        cmp #TOK_REM
        beq _scan_vars_done
        cmp #TOK_DATA
        beq _scan_vars_data
        cmp #TOK_EXT_CE
        beq _scan_vars_extended
        cmp #TOK_EXT_FE
        beq _scan_vars_extended
        cmp #TOK_TRAP
        bne _scan_vars_no_trap
        ldx #1
        stx trap_used
_scan_vars_no_trap:
        cmp #TOK_SOUND
        beq _scan_vars_snd
        cmp #TOK_VOL
        beq _scan_vars_snd
        cmp #TOK_JOY
        bne _scan_vars_no_snd
_scan_vars_snd:
        ldx #1
        stx snd_used
_scan_vars_no_snd:
        cmp #TOK_OPEN
        beq _scan_vars_fio
        cmp #TOK_CLOSE
        beq _scan_vars_fio
        cmp #TOK_PRINT_HASH
        beq _scan_vars_fio
        cmp #TOK_INPUT_HASH
        beq _scan_vars_fio
        cmp #TOK_HEADER         ; $f1-$f5 disk verbs
        bcc _scan_vars_no_fio
        cmp #TOK_RENAME+1
        bcs _scan_vars_no_fio
_scan_vars_fio:
        ldx #1
        stx fio_used
_scan_vars_no_fio:
        cmp #$de                ; GRAPHIC PAINT load the banked blob
        beq _scan_vars_gfx
        cmp #$df
        beq _scan_vars_gfx
        cmp #$e1                ; BOX CIRCLE
        beq _scan_vars_gfx
        cmp #$e2
        beq _scan_vars_gfx
        cmp #$e5                ; LINE draws; the INPUT forms do not
        bne _scan_vars_no_line
        jsr line_peek
        cmp #$84                ; LINE INPUT# reads records
        beq _scan_vars_fio
        cmp #$85                ; LINE INPUT: keyboard, core runtime
        beq _scan_vars_no_gfx
        lda #$e5
        bra _scan_vars_gfx
_scan_vars_no_line:
        cmp #$e3                ; PASTE
        beq _scan_vars_gfx
        cmp #$e4                ; CUT
        beq _scan_vars_gfx
        cmp #$cc                ; RGRAPHIC()
        beq _scan_vars_gfx
        cmp #$e0                ; bare CHAR draws; CHARDEF ($e0 $96)
        bne _scan_vars_no_char  ; does not need the blob
        jsr line_peek
        cmp #$96
        beq _scan_vars_no_gfx
        lda #$e0
        bra _scan_vars_gfx
_scan_vars_no_char:
        cmp #$e8                ; SCNCLR colour = graphics clear
        bne _scan_vars_no_gfx
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _scan_vars_no_gfx   ; bare form: text clear, no blob
        lda #$e8
_scan_vars_gfx:
        ldx #1
        stx gfx_used
_scan_vars_no_gfx:
        cmp #$bc                ; LOG EXP COS SIN TAN ATN
        bcc _scan_vars_no_math
        cmp #$c1+1
        bcs _scan_vars_no_math
        ldx #1
        stx math_used
_scan_vars_no_math:
        cmp #$a5                ; FN name( -- swallow the name so it
        bne _scan_vars_no_fn    ; does not register as an array (the
        jsr line_skip_spaces    ; parameter/argument still scan)
        jsr line_at_end
        bcs _scan_vars_jloop
        jsr line_get
_svfn_tail:
        jsr line_at_end
        bcs _scan_vars_jloop
        jsr line_peek
        jsr is_var_tail
        bcs _scan_vars_jloop
        jsr line_get
        bra _svfn_tail
_scan_vars_jloop:
        jmp _scan_vars_loop
_scan_vars_no_fn:

        sta token_value
        lda token_value
        bmi _scan_vars_loop
        jsr is_var_start
        bcs _scan_vars_loop

        lda token_value
        jsr parse_variable_with_first_char
        bcs _scan_vars_fail
        jsr line_skip_spaces
        jsr line_at_end
        bcs _scan_vars_scalar
        jsr line_peek
        cmp #'('
        bne _scan_vars_scalar
        lda scan_pmode          ; BSAVE/BLOAD on this line: a lone
        beq _scan_vars_array    ; P( is an address prefix, not an
        lda var_name_1          ; array -- skip the P, the inner
        cmp #$50                ; expression scans normally
        bne _scan_vars_array
        lda var_name_2
        bne _scan_vars_array
        jmp _scan_vars_loop
_scan_vars_array:
        lda #VAR_KIND_ARRAY1
        sta var_kind
        jsr resolve_existing_var
        bcs _scan_vars_fail
        bra _scan_vars_loop

_scan_vars_scalar:
        lda var_name_1
        cmp #$53                ; ST
        bne _svs_not_st
        lda var_name_2
        cmp #$54
        bne _svs_resolve
        lda #1
        sta fio_used
        bra _svs_resolve
_svs_not_st:
        cmp #$44                ; DS / DS$
        bne _svs_resolve
        lda var_name_2
        cmp #$53
        bne _svs_resolve
        lda #1
        sta fio_used
_svs_resolve:
        jsr resolve_var
        bcs _scan_vars_fail
        bra _scan_vars_loop

_scan_vars_string:
        jsr scan_skip_string
        bra _scan_vars_loop

_scan_vars_hex:
        jsr scan_skip_hex_literal
        bra _scan_vars_loop

_scan_vars_decimal:
        jsr scan_skip_decimal_literal
        bra _scan_vars_loop

_scan_vars_data:
        jsr scan_data_statement
        bra _scan_vars_loop

_scan_vars_dim:
        jsr scan_dim_statement
        bra _scan_vars_loop

_scan_vars_extended:
        sta scan_ext_prefix
        jsr line_at_end
        bcs _scan_vars_loop
        jsr line_peek
        ldx scan_ext_prefix
        cpx #TOK_EXT_FE
        bne _scan_ext_ce
        cmp #$02                ; BANK gates far peek/poke emission
        bne +                   ; (checked before the $04 early-out:
        ldx #1                  ; $02/$03 sit below it)
        stx bank_used
+       cmp #$03                ; FILTER needs the sound section
        beq _scan_ext_snd
        cmp #$04                ; PLAY TEMPO MOVSPR SPRITE SPRCOLOR
        bcc _scan_ext_skip
        cmp #$08+1
        bcc _scan_ext_snd
        cmp #$0a                ; ENVELOPE
        beq _scan_ext_snd
        cmp #$3e                ; MOUSE / RMOUSE
        beq _scan_ext_snd
        cmp #$3f
        beq _scan_ext_snd
        cmp #$17                ; COLLISION
        beq _scan_ext_col
        cmp #$10                ; BSAVE/BLOAD: P(expr) addresses
        beq _scan_ext_pmode     ; follow -- P( is not an array ref
        cmp #$11
        bne _scan_ext_no_pmode
_scan_ext_pmode:
        ldx #1
        stx scan_pmode
_scan_ext_no_pmode:
        cmp #$0d                ; DOPEN..DCLEAR, ERASE, CHDIR
        bcc _scan_ext_skip
        cmp #$15+1
        bcc _scan_ext_fio
        cmp #$2a
        beq _scan_ext_fio
        cmp #$4b
        beq _scan_ext_fio
        cmp #$37                ; FORMAT (HEADER alias)
        beq _scan_ext_fio
        cmp #$40                ; DISK
        beq _scan_ext_fio
        cmp #$1b                ; BOOT
        beq _scan_ext_fio
        cmp #$47                ; FGOTO / FGOSUB need the line table
        beq _scan_ext_fg
        cmp #$48
        beq _scan_ext_fg
        cmp #$2e                ; SCREEN..PALETTE graphics block
        bcc _scan_ext_skip      ; ($2e-$34: SCREEN POLYGON SCNCLR
        cmp #$34+1              ; VIEWPORT GCOPY ELLIPSE PALETTE)
        bcs _scan_ext_skip
        bra _scan_ext_gfx
_scan_ext_gfx2:
_scan_ext_gfx:
        ldx #1
        stx gfx_used
        bra _scan_ext_skip
_scan_ext_col:
        ldx #1
        stx col_used
        bra _scan_ext_snd
_scan_ext_fio:
        ldx #1
        stx fio_used
        bra _scan_ext_skip
_scan_ext_fg:
        ldx #1
        stx fgoto_used
        bra _scan_ext_skip
_scan_ext_ce:
        cmp #$0c                ; PIXEL reads through the blob
        bne +
        ldx #1
        stx gfx_used
        bra _scan_ext_skip
+       cmp #$08                ; LOG10
        beq _scan_ext_math
        cmp #$16                ; LOG2
        bne +
_scan_ext_math:
        ldx #1
        stx math_used
        bra _scan_ext_skip
+       cmp #$02                ; POT..RSPCOLOR live in the slab
        bcc _scan_ext_skip
        cmp #$07+1
        bcc _scan_ext_snd
        cmp #$0f                ; RPLAY
        bne _scan_ext_skip
_scan_ext_snd:
        ldx #1
        stx snd_used
_scan_ext_skip:
        jsr scan_skip_token_argument
        bra _scan_vars_loop

_scan_vars_fail:
        lda #<msg_error_scan_var
        ldy #>msg_error_scan_var
        jsr fatal_error_zstr
        bra _scan_vars_loop

_scan_vars_done:
        rts

scan_line_branches:
        lda #0
        sta line_idx

_scan_branch_loop:
        jsr line_at_end
        bcs _scan_branch_done
        jsr line_get
        cmp #'"'
        beq _scan_branch_string
        cmp #TOK_REM
        beq _scan_branch_done
        cmp #TOK_DATA
        beq _scan_branch_data
        cmp #TOK_EXT_CE
        beq _scan_branch_extended
        cmp #TOK_EXT_FE
        beq _scan_branch_extended
        cmp #TOK_GOTO
        beq _scan_branch_direct
        cmp #TOK_GOSUB
        beq _scan_branch_direct
        cmp #TOK_GO
        beq _scan_branch_go
        cmp #TOK_THEN
        beq _scan_branch_then
        cmp #TOK_ON
        beq _scan_branch_on
        bra _scan_branch_loop

_scan_branch_direct:
        jsr scan_parse_branch_target
        bra _scan_branch_loop

_scan_branch_go:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _scan_branch_loop
        jsr line_get
        cmp #TOK_TO
        beq _scan_branch_direct
        bra _scan_branch_loop

_scan_branch_then:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _scan_branch_loop
        jsr line_peek
        cmp #TOK_GOTO
        beq _scan_branch_then_direct
        cmp #TOK_GOSUB
        beq _scan_branch_then_direct
        cmp #TOK_GO
        beq _scan_branch_then_go
        cmp #'0'
        bcc _scan_branch_loop
        cmp #'9' + 1
        bcs _scan_branch_loop
        jsr scan_parse_branch_target
        bra _scan_branch_loop

_scan_branch_then_direct:
        jsr line_get
        jsr scan_parse_branch_target
        bra _scan_branch_loop

_scan_branch_then_go:
        jsr line_get
        bra _scan_branch_go

_scan_branch_on:
        jsr scan_on_branch_targets
        bra _scan_branch_loop

_scan_branch_string:
        jsr scan_skip_string
        bra _scan_branch_loop

_scan_branch_data:
        jsr line_skip_to_stmt_end
        bra _scan_branch_loop

_scan_branch_extended:
        jsr scan_skip_token_argument
        bra _scan_branch_loop

_scan_branch_done:
        rts


scan_dim_statement:
_scan_dim_next:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _scan_dim_bad
        jsr line_get
        jsr is_var_start
        bcs _scan_dim_bad
        jsr parse_variable_with_first_char
        bcs _scan_dim_bad
        lda var_type
        jsr var_type_is_numeric
        bcc +
        cmp #VAR_TYPE_STRING
        bne _scan_dim_bad
+

        jsr line_skip_spaces
        jsr line_at_end
        bcs _scan_dim_bad
        jsr line_get
        cmp #'('
        bne _scan_dim_bad

        lda #0
        sta array_rank

_scan_dim_dim_loop:
        lda array_rank
        cmp #ARRAY_RANK_MAX
        bcs _scan_dim_bad
        jsr line_parse_number
        bcs _scan_dim_bad
        lda number_lo
        sta array_dim_lo
        lda number_hi
        sta array_dim_hi
        inc array_dim_lo
        bne +
        inc array_dim_hi
        beq _scan_dim_bad
+       ldx array_rank
        lda array_dim_lo
        sta array_dims_lo,x
        lda array_dim_hi
        sta array_dims_hi,x
        inc array_rank

        jsr line_skip_spaces
        jsr line_at_end
        bcs _scan_dim_bad
        jsr line_get
        cmp #','
        beq _scan_dim_dim_loop
        cmp #')'
        bne _scan_dim_bad

        lda array_rank
        beq _scan_dim_bad

        lda #VAR_KIND_ARRAY1
        sta var_kind
        jsr create_array_var
        bcs _scan_dim_bad

        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _scan_dim_done
        jsr line_get
        cmp #','
        beq _scan_dim_next

_scan_dim_bad:
        lda #1
        sta compile_error
        jsr line_skip_to_stmt_end

_scan_dim_done:
        rts

scan_data_statement:
_scan_data_next:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _scan_data_done
        jsr line_peek
        cmp #','
        beq _scan_data_bad_item
        cmp #'"'
        beq _scan_data_string

        jsr line_parse_signed_decimal_number
        bcs _scan_data_bad_item
        jsr record_data_line_if_needed
        bcs _scan_data_too_many
        jsr record_data_number
        bcs _scan_data_too_many
        bra _scan_data_after_item

_scan_data_string:
        jsr line_get
        jsr add_string_literal
        bcs _scan_data_bad_item
        jsr record_data_line_if_needed
        bcs _scan_data_too_many
        jsr record_data_string
        bcs _scan_data_too_many

_scan_data_after_item:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _scan_data_done
        jsr line_get
        cmp #','
        beq _scan_data_next

_scan_data_bad_item:
        lda #<msg_error_bad_data
        ldy #>msg_error_bad_data
        jsr fatal_error_zstr
        jsr line_skip_to_stmt_end
        bra _scan_data_done

_scan_data_too_many:
        lda #<msg_error_too_many_data
        ldy #>msg_error_too_many_data
        jsr fatal_error_zstr
        jsr line_skip_to_stmt_end

_scan_data_done:
        rts

record_data_number:
        ldx data_count
        cpx #DATA_MAX
        bcs record_data_fail
        lda #DATA_TYPE_INT
        sta data_table_type,x
        lda number_lo
        sta data_table_lo,x
        lda number_hi
        sta data_table_hi,x
        inc data_count
        clc
        rts

record_data_string:
        ldx data_count
        cpx #DATA_MAX
        bcs record_data_fail
        lda #DATA_TYPE_STRING
        sta data_table_type,x
        lda current_string_id
        sta data_table_lo,x
        lda #0
        sta data_table_hi,x
        inc data_count
        clc
        rts

record_data_fail:
        sec
        rts

record_data_line_if_needed:
        ldx #0
_record_data_line_find:
        cpx data_line_count
        beq _record_data_line_create
        lda data_line_lo,x
        cmp line_no_lo
        bne _record_data_line_next
        lda data_line_hi,x
        cmp line_no_hi
        beq _record_data_line_done
_record_data_line_next:
        inx
        bra _record_data_line_find

_record_data_line_create:
        cpx #DATA_LINE_MAX
        bcs _record_data_line_fail
        lda line_no_lo
        sta data_line_lo,x
        lda line_no_hi
        sta data_line_hi,x
        lda data_count
        sta data_line_index,x
        inc data_line_count

_record_data_line_done:
        clc
        rts

_record_data_line_fail:
        sec
        rts

scan_on_branch_targets:
_scan_on_find_branch:
        jsr line_at_end_or_colon
        bcs _scan_on_done
        jsr line_get
        cmp #'"'
        beq _scan_on_string
        cmp #TOK_REM
        beq _scan_on_done
        cmp #TOK_DATA
        beq _scan_on_done
        cmp #TOK_GOTO
        beq _scan_on_list
        cmp #TOK_GOSUB
        beq _scan_on_list
        cmp #TOK_GO
        beq _scan_on_go
        bra _scan_on_find_branch

_scan_on_go:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _scan_on_done
        jsr line_get
        cmp #TOK_TO
        beq _scan_on_list
        bra _scan_on_find_branch

_scan_on_string:
        jsr scan_skip_string
        bra _scan_on_find_branch

_scan_on_list:
        jsr line_parse_number
        bcs _scan_on_done
        jsr record_branch_target

_scan_on_list_next:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _scan_on_done
        jsr line_get
        cmp #','
        bne _scan_on_done
        jsr line_parse_number
        bcs _scan_on_done
        jsr record_branch_target
        bra _scan_on_list_next

_scan_on_done:
        rts

scan_parse_branch_target:
        jsr line_parse_number
        bcs _scan_branch_bad
        jsr record_branch_target
        rts

_scan_branch_bad:
        lda #1
        sta compile_error
        rts

scan_skip_string:
_scan_skip_string_loop:
        jsr line_at_end
        bcs _scan_skip_string_done
        jsr line_get
        cmp #'"'
        bne _scan_skip_string_loop
_scan_skip_string_done:
        rts

scan_skip_token_argument:
        jsr line_at_end
        bcs _scan_skip_token_done
        inc line_idx
_scan_skip_token_done:
        rts

scan_skip_hex_literal:
_scan_skip_hex_loop:
        jsr line_at_end
        bcs _scan_skip_hex_done
        jsr line_peek
        jsr hex_to_nibble
        bcs _scan_skip_hex_done
        inc line_idx
        bra _scan_skip_hex_loop

_scan_skip_hex_done:
        rts

scan_skip_decimal_literal:
_scan_skip_decimal_loop:
        jsr line_at_end
        bcs _scan_skip_decimal_done
        jsr line_peek
        cmp #'0'
        bcc _scan_skip_decimal_dot
        cmp #'9' + 1
        bcs _scan_skip_decimal_dot
        inc line_idx
        bra _scan_skip_decimal_loop

_scan_skip_decimal_dot:
        cmp #'.'
        bne _scan_skip_decimal_exp
        inc line_idx
        bra _scan_skip_decimal_loop

_scan_skip_decimal_exp:
        cmp #'E'
        beq _scan_skip_decimal_exp_take
        cmp #'e'
        bne _scan_skip_decimal_done

_scan_skip_decimal_exp_take:
        inc line_idx
        jsr line_at_end
        bcs _scan_skip_decimal_done
        jsr line_peek
        cmp #TOK_PLUS
        beq _scan_skip_decimal_sign
        cmp #TOK_MINUS
        bne _scan_skip_decimal_loop

_scan_skip_decimal_sign:
        inc line_idx
        bra _scan_skip_decimal_loop

_scan_skip_decimal_done:
        rts

record_line_number:
        lda line_no_lo
        sta lsrch_lo
        lda line_no_hi
        sta lsrch_hi
        jsr linefind
        bcs _record_line_dup
        lda line_count+1        ; room? (16-bit against LINE_MAX)
        cmp #>LINE_MAX
        bcc _record_line_room
        bne _record_line_full
        lda line_count
        cmp #<LINE_MAX
        bcs _record_line_full
_record_line_room:
        lda #0                  ; linefind left the walker at the
        ldy line_no_lo          ; append slot
        jsr lf_write
        lda #1
        ldy line_no_hi
        jsr lf_write
        inc line_count
        bne +
        inc line_count+1
+       clc
        rts

_record_line_dup:
        lda #<msg_error_dup_line
        ldy #>msg_error_dup_line
        bra _record_line_fail
_record_line_full:
        lda #<msg_error_many_lines
        ldy #>msg_error_many_lines
_record_line_fail:
        jsr fatal_error_zstr
        sec
        rts

; ---- 16-bit line-record walker: 4-byte records (number lo/hi,
; address lo/hi) at LINETAB_B4 in bank 4, so programs can exceed 255
; lines without costing bank-0 image space. lf_base is the bank-4
; address of the current record.
lf_rst:
        lda #<LINETAB_B4
        sta lf_base
        lda #>LINETAB_B4
        sta lf_base+1
        lda #0
        sta lf_i
        sta lf_i+1
        rts

; A = field offset 0-3 -> A = that byte of the current record
; (records live in bank 4; the source pointer is borrowed around the
; access, same discipline as the string pool)
lf_read:
        pha
        jsr pool_ptr_save
        pla
        clc
        adc lf_base
        sta source_ptr
        lda lf_base+1
        adc #0
        sta source_ptr+1
        ldz #0
        lda [source_ptr],z
        jmp pool_ptr_restore    ; A survives

; A = field offset, Y = value: write into the current record
lf_write:
        pha
        jsr pool_ptr_save
        pla
        clc
        adc lf_base
        sta source_ptr
        lda lf_base+1
        adc #0
        sta source_ptr+1
        ldz #0
        tya
        sta [source_ptr],z
        jmp pool_ptr_restore

lf_next:
        clc
        lda lf_base
        adc #4
        sta lf_base
        bcc +
        inc lf_base+1
+       inc lf_i
        bne +
        inc lf_i+1
+       rts

; Z set when the walker sits at line_count (one past the last record)
lf_atend:
        lda lf_i
        cmp line_count
        bne _lfa_done
        lda lf_i+1
        cmp line_count+1
_lfa_done:
        rts

; search for lsrch_lo/hi; C set = found (walker at the record),
; C clear = missing (walker at the append slot)
linefind:
        jsr lf_rst
_lf_loop:
        jsr lf_atend
        beq _lf_miss
        lda #0
        jsr lf_read
        cmp lsrch_lo
        bne _lf_next2
        lda #1
        jsr lf_read
        cmp lsrch_hi
        beq _lf_hit
_lf_next2:
        jsr lf_next
        bra _lf_loop
_lf_hit:
        sec
        rts
_lf_miss:
        clc
        rts

lf_base:
        .byte 0, 0
lf_i:
        .byte 0, 0
lsrch_lo:
        .byte 0
lsrch_hi:
        .byte 0

record_branch_target:
        ldx #0
_record_branch_find:
        cpx branch_count
        beq _record_branch_create
        jsr brtabload
        lda brtab_lo
        cmp number_lo
        bne _record_branch_next
        lda brtab_hi
        cmp number_hi
        beq _record_branch_done
_record_branch_next:
        inx
        bra _record_branch_find

_record_branch_create:
        cpx #BRANCH_MAX
        bcs _record_branch_fail
        jsr brtabstore
        inc branch_count
_record_branch_done:
        clc
        rts

_record_branch_fail:
        lda #1
        sta compile_error
        sec
        rts

validate_branch_targets:
        ldx #0
_validate_branch_loop:
        cpx branch_count
        beq _validate_branch_done
        stx byte_value
        jsr brtabload
        lda brtab_lo
        sta number_lo
        lda brtab_hi
        sta number_hi
        jsr line_number_exists
        bcc _validate_branch_next
        lda #1
        sta compile_error
_validate_branch_next:
        ldx byte_value
        inx
        bra _validate_branch_loop

_validate_branch_done:
        rts

line_number_exists:
        lda number_lo
        sta lsrch_lo
        lda number_hi
        sta lsrch_hi
        jsr linefind
        bcs _line_exists_yes
        sec
        rts
_line_exists_yes:
        clc
        rts

data_line_number_exists:
        ldx #0
_data_line_exists_loop:
        cpx data_line_count
        beq _data_line_exists_no
        lda data_line_lo,x
        cmp number_lo
        bne _data_line_exists_next
        lda data_line_hi,x
        cmp number_hi
        beq _data_line_exists_yes
_data_line_exists_next:
        inx
        bra _data_line_exists_loop

_data_line_exists_yes:
        clc
        rts

_data_line_exists_no:
        sec
        rts

;=======================================================================================
; Line compiler
;=======================================================================================

compile_line:
        lda line_overflow
        beq +
        lda #<msg_error_line_overflow
        ldy #>msg_error_line_overflow
        jsr fatal_line_error
        rts
+       lda #0
        sta line_idx
        jsr compile_line_statements
        jsr out_cr
        rts

compile_line_statements:
_compile_line_loop:
        lda compile_error
        bne _compile_line_done
        jsr line_skip_spaces_colons
        jsr line_at_end
        bcs _compile_line_done
        lda col_used            ; COLLISION dispatches between statements
        beq +
        jsr emit_tmpl
        .word out_jsr_colcheck
+
        jsr line_get
        cmp #TOK_ELSE           ; ELSE returns out of the line loop, so
        beq _compile_else       ; it stays outside the jsr dispatch
        cmp #TOK_EXT_CE
        beq _compile_unsupported_extended_token
        cmp #TOK_EXT_FE
        beq _compile_extended_fe
        ldx #(_stab_end - _stab) - 1
_compile_stmt_scan:
        cmp _stab,x
        beq _compile_stmt_hit
        dex
        bpl _compile_stmt_scan

        sta token_value
        lda token_value
        bmi _compile_unsupported_token_stored
        jsr is_var_start
        bcc _compile_assignment_from_token
        bra _compile_unsupported_statement

_compile_stmt_hit:
        pha                     ; index -> jump table offset while keeping
        txa                     ; the token in A (compile_diskcmd picks its
        asl a                   ; DOS prefix from it)
        tax
        pla
        jsr _compile_stmt_call
        jmp _compile_line_loop
_compile_stmt_call:
        jmp (_stmt_jtab,x)

_compile_else:
        lda compile_stop_on_else
        beq _compile_else_bad
        lda line_had_colon
        beq _compile_else_bad
        lda #1
        sta compile_found_else
        rts

_compile_else_bad:
        lda #<msg_error_bad_else
        ldy #>msg_error_bad_else
        jsr fatal_statement_error
        jmp _compile_line_loop

; statement tokens, index-paired with handlers; handlers follow the
; jsr convention (rts returns to the line loop)
_stab:
        .byte TOK_FOR, TOK_NEXT, TOK_DO, TOK_LOOP, TOK_EXIT, TOK_PRINT
        .byte TOK_INPUT, TOK_GET, TOK_GOTO, TOK_GOSUB, TOK_RETURN
        .byte TOK_END, TOK_STOP, TOK_REM, TOK_SYS, TOK_POKE, TOK_GO
        .byte TOK_ON, TOK_DATA, TOK_DIM, TOK_READ, TOK_RESTORE, TOK_LET
        .byte TOK_CLR, TOK_IF, TOK_PRINT_HASH, TOK_OPEN, TOK_CLOSE
        .byte TOK_INPUT_HASH, TOK_TRAP, TOK_RESUME, TOK_SOUND, TOK_VOL
        .byte TOK_WAIT, TOK_SCRATCH, TOK_HEADER, TOK_COLLECT, TOK_COPY
        .byte TOK_RENAME, TOK_COLOR, TOK_EXT_E0, TOK_KEY, $DE
        .byte $DF, $E1, $E2, $E5, $E8, $E3, $96, $E4
_stab_end:
_stmt_jtab:
        .word compile_for, compile_next, compile_do, compile_loop
        .word compile_exit, compile_print, compile_input, compile_get
        .word compile_goto, compile_gosub, _stmt_return, _stmt_end
        .word _stmt_end, compile_rem, compile_sys, compile_poke
        .word compile_go, compile_on, _stmt_data, _stmt_dim
        .word compile_read, compile_restore, compile_let, _stmt_clr
        .word compile_if, compile_print_hash, compile_open, compile_close
        .word compile_input_hash, compile_trap, compile_resume
        .word compile_sound, compile_vol, compile_wait, compile_diskcmd
        .word compile_diskcmd, compile_diskcmd, compile_diskcmd
        .word compile_diskcmd, compile_attr_fg, compile_e0
        .word compile_key, compile_graphic
        .word compile_paint, compile_box, compile_circle, compile_gline
        .word compile_scnclr, compile_paste, compile_def, compile_cut

_stmt_return:
        jsr emit_tmpl_done
        .word out_rts

_stmt_end:
        jsr emit_tmpl
        .word out_jmp_rtexit
        jmp line_skip_to_end

_stmt_data:
        lda #<out_data_comment
        ldy #>out_data_comment
        bra _stmt_skipstmt

_stmt_dim:
        lda #<out_dim_comment
        ldy #>out_dim_comment
_stmt_skipstmt:
        jsr out_zstr
        jmp line_skip_to_stmt_end

_stmt_clr:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _stmt_clr_plain
        jsr line_peek
        cmp #TOK_EXT_FE         ; CLR + BIT pair = CLRBIT
        bne +
        jsr line_get
        lda #<out_jsr_clrbitgo
        ldy #>out_jsr_clrbitgo
        jmp compile_bitargs
+       cmp #$54                ; CLR TI resets the seconds timer
        bne _stmt_clr_plain
        jsr line_get
        jsr line_get
        cmp #$49
        bne _stmt_clr_plain
        jsr emit_tmpl_done
        .word out_jsr_clrti
_stmt_clr_plain:
        jsr emit_tmpl_done
        .word out_jsr_rtclr

_compile_assignment_from_token:
        lda token_value
        jsr scrarr_probe
        bcs _compile_assign_plain
        jsr compile_scrarr_store
        bra _compile_line_loop
_compile_assign_plain:
        lda token_value
        jsr compile_assignment_with_first_char
        bra _compile_line_loop

_compile_unsupported_token:
        sta token_value
_compile_unsupported_token_stored:
        lda #<msg_error_unsupported_token
        ldy #>msg_error_unsupported_token
        jsr fatal_statement_error
        bra _compile_line_loop

_compile_unsupported_extended_token:
        sta token_prefix
        lda #0
        sta token_value
        jsr line_at_end
        bcs _compile_unsupported_extended_emit
        jsr line_get
        sta token_value

_compile_unsupported_extended_emit:
        lda #<msg_error_unsupported_token
        ldy #>msg_error_unsupported_token
        jsr fatal_statement_error
        bra _compile_line_loop

_compile_extended_fe:
        jsr compile_ext_fe
        bcs +
        jmp _compile_line_loop
+       lda #TOK_EXT_FE
        bra _compile_unsupported_extended_token

_compile_unsupported_statement:
        lda token_value         ; patch the offending byte into the message
        lsr a
        lsr a
        lsr a
        lsr a
        jsr _diag_nib
        sta msg_unsup_hex
        lda token_value
        and #$0f
        jsr _diag_nib
        sta msg_unsup_hex+1
        lda #<msg_error_unsupported_statement
        ldy #>msg_error_unsupported_statement
        bra _compile_unsup_go
_diag_nib:
        cmp #10
        bcc +
        adc #6
+       adc #$30
        rts
_compile_unsup_go:
        jsr fatal_statement_error
        bra _compile_line_loop

_compile_line_done:
        rts

compile_let:
        jsr line_skip_spaces
        jsr line_at_end
        bcs compile_assignment_bad
        jsr line_get
        ; FALLTHROUGH

compile_assignment_with_first_char:
        jsr parse_variable_with_first_char
        bcs compile_assignment_bad
        lda var_type
        cmp #VAR_TYPE_STRING
        beq _compile_string_assignment
        lda var_type
        jsr var_type_is_numeric
        bcs compile_assignment_bad
        jsr line_skip_spaces
        jsr line_at_end
        bcs compile_assignment_bad
        jsr line_peek
        cmp #'('
        beq compile_array_assignment

        jsr resolve_var
        bcs compile_assignment_bad
        lda current_var_data_lo
        sta assign_var_data_lo
        lda current_var_data_hi
        sta assign_var_data_hi
        lda var_type
        sta assign_var_type
        jsr line_get
        cmp #TOK_EQUAL
        beq _compile_assignment_expr
        cmp #'='
        bne compile_assignment_bad

_compile_assignment_expr:
        jsr compile_condition_expression
        bcs compile_assignment_bad
        lda assign_var_type
        cmp #VAR_TYPE_FLOAT
        beq _compile_assignment_float
        lda expr_type
        beq _compile_assignment_int
        jsr emit_qint_expr
_compile_assignment_int:
        jsr emit_store_var
        rts

_compile_assignment_float:
        lda expr_type
        bne _compile_assignment_fac
        jsr emit_tmpl
        .word out_jsr_float16
_compile_assignment_fac:
        jsr emit_store_var_fac
        rts

_compile_string_assignment:
        jsr line_skip_spaces
        jsr line_at_end
        bcs compile_assignment_bad
        jsr line_peek
        cmp #'('
        beq compile_string_array_assignment

        jsr resolve_var
        bcs compile_assignment_bad
        lda current_var_data_lo
        sta assign_var_data_lo
        lda current_var_data_hi
        sta assign_var_data_hi
        lda var_type
        sta assign_var_type
        jsr line_get
        cmp #TOK_EQUAL
        beq _compile_string_assignment_value
        cmp #'='
        bne compile_assignment_bad

_compile_string_assignment_value:
        jsr compile_string_expression
        bcs compile_assignment_bad
        jsr emit_store_var
        rts

compile_string_array_assignment:
        lda #VAR_KIND_ARRAY1
        sta var_kind
        jsr resolve_existing_var
        bcs compile_assignment_bad
        lda current_var_data_lo
        sta array_base_lo
        lda current_var_data_hi
        sta array_base_hi
        lda current_sym_index
        pha
        jsr compile_array_index
        pla
        sta array_sym_index
        bcs compile_assignment_bad
        lda array_base_lo
        sta current_var_data_lo
        lda array_base_hi
        sta current_var_data_hi
        jsr emit_set_arrayptr_current
        jsr emit_save_arrayptr

        jsr line_skip_spaces
        jsr line_at_end
        bcs compile_assignment_bad
        jsr line_get
        cmp #TOK_EQUAL
        beq _compile_string_array_assignment_value
        cmp #'='
        bne compile_assignment_bad

_compile_string_array_assignment_value:
        jsr compile_string_expression
        bcs compile_assignment_bad
        jsr emit_restore_arrayptr
        jsr emit_store_ptr
        rts

; string-context park/unpark: GC-visible temp stack, not the CPU stack
emit_push_sexpr:
        jsr emit_tmpl_done
        .word out_jsr_strtpush
emit_pop_slhs:
        jsr emit_tmpl_done
        .word out_jsr_strtpop

compile_string_expression:
        jsr compile_string_factor
        bcc _string_expr_loop
        rts

_string_expr_loop:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _string_expr_done
        jsr line_peek
        cmp #TOK_PLUS
        bne _string_expr_done
        jsr line_get
        jsr emit_push_sexpr
        jsr compile_string_factor
        bcs _string_expr_fail
        jsr emit_pop_slhs
        jsr emit_concat_strings
        bra _string_expr_loop

_string_expr_done:
        clc
        rts

_string_expr_fail:
        sec
        rts

compile_string_factor:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _string_factor_fail
        jsr line_get
        cmp #'"'
        bne _string_factor_var
        jsr add_string_literal
        bcs _string_factor_fail
        jsr emit_string_literal_to_heap_expr
        clc
        rts

_string_factor_var:
        cmp #TOK_EXT_CE
        beq _string_factor_ce
        cmp #TOK_STR_STR
        beq _string_factor_str
        cmp #TOK_CHR_STR
        beq _string_factor_chr
        cmp #TOK_HEX_STR
        beq _string_factor_hex
        cmp #TOK_ERR_STR
        beq _string_factor_err
        cmp #TOK_LEFT_STR
        beq _string_factor_left
        cmp #TOK_RIGHT_STR
        beq _string_factor_right
        cmp #TOK_MID_STR
        beq _string_factor_mid
        jsr is_var_start
        bcs _string_factor_fail
        jsr parse_variable_with_first_char
        bcs _string_factor_fail
        lda var_type
        cmp #VAR_TYPE_STRING
        bne _string_factor_fail
        jsr line_skip_spaces
        jsr line_at_end
        bcs _string_factor_scalar_var
        jsr line_peek
        cmp #'('
        beq _string_factor_array_var

_string_factor_scalar_var:
        lda var_name_1
        cmp #$44                ; DS$ is the drive status text
        bne _string_factor_nods
        lda var_name_2
        cmp #$53
        bne _string_factor_nods
        jsr emit_tmpl_done
        .word out_jsr_dsstrf
_string_factor_nods:
        lda var_name_1
        cmp #$54                ; TI$ reads the RTC as "hh:mm:ss"
        bne _string_factor_resolve
        lda var_name_2
        cmp #$49
        bne _string_factor_resolve
        jsr emit_tmpl_done
        .word out_jsr_tistr
_string_factor_resolve:
        jsr resolve_existing_var
        bcs _string_factor_fail
        jsr emit_load_var
        jsr emit_copy_string_expr
        clc
        rts

_string_factor_array_var:
        lda #VAR_KIND_ARRAY1
        sta var_kind
        jsr resolve_existing_var
        bcs _string_factor_fail
        lda current_var_data_lo
        sta array_base_lo
        lda current_var_data_hi
        sta array_base_hi
        lda current_sym_index
        pha
        jsr compile_array_index
        pla
        sta array_sym_index
        bcs _string_factor_fail
        lda array_base_lo
        sta current_var_data_lo
        lda array_base_hi
        sta current_var_data_hi
        jsr emit_set_arrayptr_current
        jsr emit_load_ptr
        jsr emit_copy_string_expr
        clc
        rts

_string_factor_fail:
        sec
        rts

_string_factor_str:
        jsr compile_str_string_function
        rts

_string_factor_chr:
        jsr parse_paren_expr
        bcs _string_factor_fail
        jsr emit_tmpl_done
        .word out_jsr_chrstrf

_string_factor_ce:
        jsr line_at_end         ; the CE byte is already consumed
        bcs _string_factor_fail
        jsr line_get
        cmp #$14                ; RPT$
        bne _string_factor_no_rpt
        jmp compile_rpt_string_function
_string_factor_no_rpt:
        cmp #$12                ; STRBIN$
        bne _string_factor_fail
        jsr parse_open_paren
        bcs _string_factor_fail
        jsr compile_expression
        bcs _string_factor_fail
        jsr parse_close_paren
        bcs _string_factor_fail
        jsr emit_tmpl_done
        .word out_jsr_strbinf

_string_factor_err:
        jsr parse_open_paren
        bcs _string_factor_fail
        jsr compile_expression
        bcs _string_factor_fail
        jsr parse_close_paren
        bcs _string_factor_fail
        jsr emit_tmpl_done
        .word out_jsr_errstrf

_string_factor_hex:
        jsr parse_open_paren
        bcs _string_factor_fail
        jsr compile_expression
        bcs _string_factor_fail
        jsr parse_close_paren
        bcs _string_factor_fail
        jsr emit_tmpl_done
        .word out_jsr_hexstr

_string_factor_left:
        jsr compile_left_string_function
        rts

_string_factor_right:
        jsr compile_right_string_function
        rts

_string_factor_mid:
        jsr compile_mid_string_function
        rts

string_expression_starts:
        lda line_idx
        sta line_idx_save
        jsr line_skip_spaces
        jsr line_at_end
        bcs _string_expr_starts_no
        jsr line_peek
        cmp #'"'
        beq _string_expr_starts_yes
        cmp #TOK_STR_STR
        beq _string_expr_starts_yes
        cmp #TOK_HEX_STR
        beq _string_expr_starts_yes
        cmp #TOK_EXT_CE
        beq _string_expr_starts_ce
        cmp #TOK_ERR_STR
        beq _string_expr_starts_yes
        cmp #TOK_LEFT_STR
        beq _string_expr_starts_yes
        cmp #TOK_RIGHT_STR
        beq _string_expr_starts_yes
        cmp #TOK_MID_STR
        beq _string_expr_starts_yes
        jsr is_var_start
        bcs _string_expr_starts_no
        jsr line_get
        jsr parse_variable_with_first_char
        bcs _string_expr_starts_no
        lda var_type
        cmp #VAR_TYPE_STRING
        beq _string_expr_starts_yes

_string_expr_starts_no:
        lda line_idx_save
        sta line_idx
        sec
        rts

_string_expr_starts_ce:
        lda line_idx            ; peek the sub-token without consuming
        pha
        jsr line_get
        jsr line_peek
        tax
        pla
        sta line_idx
        cpx #$12                ; STRBIN$
        beq _string_expr_starts_yes
        cpx #$14                ; RPT$
        beq _string_expr_starts_yes
        sec
        rts

_string_expr_starts_yes:
        lda line_idx_save
        sta line_idx
        clc
        rts

compile_str_string_function:
        jsr parse_open_paren
        bcs _compile_str_fail
        jsr compile_expression
        bcs _compile_str_fail
        jsr parse_close_paren
        bcs _compile_str_fail
        jsr emit_string_from_int
        clc
        rts

_compile_str_fail:
        sec
        rts

compile_left_string_function:
        jsr parse_open_paren
        bcs _compile_left_fail
        jsr compile_string_expression
        bcs _compile_left_fail
        jsr emit_push_sexpr
        jsr parse_comma
        bcs _compile_left_fail
        jsr compile_expression
        bcs _compile_left_fail
        jsr parse_close_paren
        bcs _compile_left_fail
        jsr emit_pop_slhs
        jsr emit_string_left
        clc
        rts

_compile_left_fail:
        sec
        rts

; RPT$(s$, count): the RIGHT$ parse shape with the repeat runtime
compile_rpt_string_function:
        jsr parse_open_paren
        bcs _compile_rpt_fail
        jsr compile_string_expression
        bcs _compile_rpt_fail
        jsr emit_push_sexpr
        jsr parse_comma
        bcs _compile_rpt_fail
        jsr compile_expression
        bcs _compile_rpt_fail
        jsr parse_close_paren
        bcs _compile_rpt_fail
        jsr emit_pop_slhs
        jsr emit_tmpl_done
        .word out_jsr_rptf
_compile_rpt_fail:
        sec
        rts

compile_right_string_function:
        jsr parse_open_paren
        bcs _compile_right_fail
        jsr compile_string_expression
        bcs _compile_right_fail
        jsr emit_push_sexpr
        jsr parse_comma
        bcs _compile_right_fail
        jsr compile_expression
        bcs _compile_right_fail
        jsr parse_close_paren
        bcs _compile_right_fail
        jsr emit_pop_slhs
        jsr emit_string_right
        clc
        rts

_compile_right_fail:
        sec
        rts

compile_mid_string_function:
        jsr parse_open_paren
        bcs _compile_mid_fail
        jsr compile_string_expression
        bcs _compile_mid_fail
        jsr emit_push_sexpr
        jsr parse_comma
        bcs _compile_mid_fail
        jsr compile_expression
        bcs _compile_mid_fail
        jsr emit_save_expr_to_strarg1
        jsr line_skip_spaces
        jsr line_at_end
        bcs _compile_mid_fail
        jsr line_get
        cmp #','
        beq _compile_mid_with_len
        cmp #')'
        bne _compile_mid_fail
        jsr emit_pop_slhs
        jsr emit_string_mid_tail
        clc
        rts

_compile_mid_with_len:
        jsr compile_expression
        bcs _compile_mid_fail
        jsr parse_close_paren
        bcs _compile_mid_fail
        jsr emit_pop_slhs
        jsr emit_string_mid
        clc
        rts

_compile_mid_fail:
        sec
        rts

parse_open_paren:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _parse_open_paren_fail
        jsr line_get
        cmp #'('
        bne _parse_open_paren_fail
        clc
        rts

_parse_open_paren_fail:
        sec
        rts

parse_close_paren:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _parse_close_paren_fail
        jsr line_get
        cmp #')'
        bne _parse_close_paren_fail
        clc
        rts

_parse_close_paren_fail:
        sec
        rts

parse_comma:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _parse_comma_fail
        jsr line_get
        cmp #','
        bne _parse_comma_fail
        clc
        rts

_parse_comma_fail:
        sec
        rts

compile_array_assignment:
        lda #VAR_KIND_ARRAY1
        sta var_kind
        jsr resolve_existing_var
        bcs compile_assignment_bad
        ldx current_sym_index
        lda sym_type,x
        sta assign_var_type     ; target array type, safe from nested indexes
        lda current_var_data_lo
        sta array_base_lo
        lda current_var_data_hi
        sta array_base_hi
        lda current_sym_index
        pha
        jsr compile_array_index
        pla
        sta array_sym_index
        bcs compile_assignment_bad
        lda array_base_lo
        sta current_var_data_lo
        lda array_base_hi
        sta current_var_data_hi
        jsr emit_set_arrayptr_current
        jsr emit_save_arrayptr

        jsr line_skip_spaces
        jsr line_at_end
        bcs compile_assignment_bad
        jsr line_get
        cmp #TOK_EQUAL
        beq _compile_array_assignment_expr
        cmp #'='
        bne compile_assignment_bad

_compile_array_assignment_expr:
        jsr compile_condition_expression
        bcs compile_assignment_bad
        lda assign_var_type
        cmp #VAR_TYPE_FLOAT
        beq _compile_array_assign_flt
        lda expr_type
        beq _compile_array_assign_int
        jsr emit_qint_expr
_compile_array_assign_int:
        jsr emit_restore_arrayptr
        jsr emit_store_ptr
        rts

_compile_array_assign_flt:
        lda expr_type
        bne _compile_array_assign_fac
        jsr emit_tmpl
        .word out_jsr_float16
_compile_array_assign_fac:
        jsr emit_restore_arrayptr
        jsr emit_tmpl_done
        .word out_jsr_fstorevar


compile_assignment_bad:
        lda #<msg_error_bad_assignment
        ldy #>msg_error_bad_assignment
        jsr fatal_statement_error
        rts

compile_for:
        jsr alloc_for_label
        bcs compile_for_bad

        jsr line_skip_spaces
        jsr line_at_end
        bcs compile_for_bad
        jsr line_get
        jsr parse_variable_with_first_char
        bcs compile_for_bad
        lda var_type
        jsr var_type_is_numeric
        bcs compile_for_bad
        jsr resolve_var
        bcs compile_for_bad
        lda var_type
        sta current_for_var_type
        sta assign_var_type
        lda current_var_data_lo
        sta current_for_var_data_lo
        sta assign_var_data_lo
        lda current_var_data_hi
        sta current_for_var_data_hi
        sta assign_var_data_hi

        jsr line_skip_spaces
        jsr line_at_end
        bcs compile_for_bad
        jsr line_get
        cmp #TOK_EQUAL
        beq _compile_for_start
        cmp #'='
        bne compile_for_bad

_compile_for_start:
        jsr compile_expression
        bcs compile_for_bad
        jsr emit_store_var

        jsr line_skip_spaces
        jsr line_at_end
        bcs compile_for_bad
        jsr line_get
        cmp #TOK_TO
        bne compile_for_bad

        jsr compile_expression
        bcs compile_for_bad
        jsr emit_store_expr_to_forend

        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_for_default_step
        jsr line_peek
        cmp #TOK_STEP
        bne _compile_for_default_step
        jsr line_get
        jsr compile_expression
        bcs compile_for_bad
        bra _compile_for_store_step

_compile_for_default_step:
        lda #1
        sta number_lo
        lda #0
        sta number_hi
        jsr emit_load_number

_compile_for_store_step:
        jsr emit_store_expr_to_forstep
        jsr push_for_frame
        bcs compile_for_bad
        jsr emit_for_initial_check
        jsr emit_for_top_label_def
        rts

compile_for_bad:
        lda #<msg_error_bad_for
        ldy #>msg_error_bad_for
        jsr fatal_statement_error
        rts

compile_next:
        jsr pop_for_frame
        bcs compile_next_bad

        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_next_emit
        jsr line_get
        jsr parse_variable_with_first_char
        bcs compile_next_bad
        lda var_type
        jsr var_type_is_numeric
        bcs compile_next_bad
        jsr resolve_var
        bcs compile_next_bad
        lda current_var_data_lo
        cmp current_for_var_data_lo
        bne compile_next_bad
        lda current_var_data_hi
        cmp current_for_var_data_hi
        bne compile_next_bad

_compile_next_emit:
        lda current_for_var_type
        sta assign_var_type
        lda current_for_var_data_lo
        sta current_var_data_lo
        sta assign_var_data_lo
        lda current_for_var_data_hi
        sta current_var_data_hi
        sta assign_var_data_hi
        jsr emit_load_var
        jsr emit_move_expr_to_lhs
        jsr emit_load_forstep
        jsr emit_add_lhs_expr
        jsr emit_store_var

        jsr emit_tmpl
        .word out_lda_label
        jsr out_forstep_ref
        jsr out_plus_one_cr
        jsr emit_tmpl
        .word out_bmi_label
        jsr out_forneg_ref
        jsr out_cr

        lda current_for_var_data_lo
        sta current_var_data_lo
        lda current_for_var_data_hi
        sta current_var_data_hi
        jsr emit_load_var
        jsr emit_move_expr_to_lhs
        jsr emit_load_forend
        jsr emit_tmpl
        .word out_jsr_cmple
        jsr emit_tmpl
        .word out_bne_label
        jsr out_forcont_ref
        jsr out_cr
        jsr emit_jmp_fordone

        jsr emit_forneg_label_def
        lda current_for_var_data_lo
        sta current_var_data_lo
        lda current_for_var_data_hi
        sta current_var_data_hi
        jsr emit_load_var
        jsr emit_move_expr_to_lhs
        jsr emit_load_forend
        jsr emit_tmpl
        .word out_jsr_cmpge
        jsr emit_tmpl
        .word out_bne_label
        jsr out_forcont_ref
        jsr out_cr
        jsr emit_jmp_fordone

        jsr emit_forcont_label_def
        jsr emit_jmp_fortop
        jsr emit_fordone_label_def
        rts

compile_next_bad:
        lda #<msg_error_bad_next
        ldy #>msg_error_bad_next
        jsr fatal_statement_error
        rts

compile_do:
        jsr alloc_do_label
        bcs compile_do_bad
        jsr emit_do_top_label_def

        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_do_push
        jsr line_peek
        cmp #TOK_WHILE
        beq _compile_do_while
        cmp #TOK_UNTIL
        beq _compile_do_until
        bra compile_do_bad

_compile_do_while:
        jsr line_get
        jsr compile_loop_condition_lhs
        bcs compile_do_bad
        jsr emit_do_pretest_while
        bra _compile_do_check_tail

_compile_do_until:
        jsr line_get
        jsr compile_loop_condition_lhs
        bcs compile_do_bad
        jsr emit_do_pretest_until

_compile_do_check_tail:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcc compile_do_bad

_compile_do_push:
        jsr push_do_frame
        bcs compile_do_bad
        rts

compile_do_bad:
        lda #<msg_error_bad_do
        ldy #>msg_error_bad_do
        jsr fatal_statement_error
        rts

compile_loop:
        jsr pop_do_frame
        bcs compile_loop_bad

        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_loop_plain
        jsr line_peek
        cmp #TOK_UNTIL
        beq _compile_loop_until
        cmp #TOK_WHILE
        beq _compile_loop_while
        bra compile_loop_bad

_compile_loop_until:
        jsr line_get
        jsr compile_loop_condition_lhs
        bcs compile_loop_bad
        jsr emit_do_posttest_until
        bra _compile_loop_check_tail

_compile_loop_while:
        jsr line_get
        jsr compile_loop_condition_lhs
        bcs compile_loop_bad
        jsr emit_do_posttest_while
        bra _compile_loop_check_tail

_compile_loop_plain:
        jsr emit_jmp_dotop
        jsr emit_do_done_label_def
        rts

_compile_loop_check_tail:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcc compile_loop_bad
        jsr emit_do_done_label_def
        rts

compile_loop_bad:
        lda #<msg_error_bad_loop
        ldy #>msg_error_bad_loop
        jsr fatal_statement_error
        rts

; EXIT leaves the current DO..LOOP only (the book's spec; the
; interpreter has no EXIT FOR, so neither do we)
compile_exit:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_exit_do
        jsr line_peek
        cmp #TOK_ELSE
        beq _compile_exit_do
        bra compile_exit_bad

_compile_exit_do:
        jsr peek_do_frame
        bcs compile_exit_bad
        jsr emit_jmp_dodone
        rts

compile_exit_bad:
        lda #<msg_error_bad_exit
        ldy #>msg_error_bad_exit
        jsr fatal_statement_error
        rts

compile_loop_condition_lhs:
        jsr compile_condition_boolean
        bcs _compile_loop_condition_fail
        jsr emit_move_expr_to_lhs
        clc
        rts

_compile_loop_condition_fail:
        sec
        rts

; IF ... THEN BEGIN defers the false-branch labels to a matching BEND on
; a later line. BEGIN records the enclosing IF's else/end label ids on the
; begin stack and flags the IF to skip its end-of-line definitions.
compile_begin:
        lda compile_stop_on_else
        bne +
        lda #<msg_error_bad_begin
        ldy #>msg_error_bad_begin
        jsr fatal_statement_error
        rts
+       ldx begin_sp
        cpx #BEGIN_STACK_MAX
        bcc +
        lda #<msg_error_bad_begin
        ldy #>msg_error_bad_begin
        jsr fatal_statement_error
        rts
+       lda if_else_lo
        sta begin_stack_else_lo,x
        lda if_else_hi
        sta begin_stack_else_hi,x
        lda if_end_lo
        sta begin_stack_end_lo,x
        lda if_end_hi
        sta begin_stack_end_hi,x
        inc begin_sp
        lda #1
        sta if_begin_taken
        rts

compile_bend:
        lda begin_sp
        bne +
        lda #<msg_error_bad_bend
        ldy #>msg_error_bad_bend
        jsr fatal_statement_error
        rts
+       dec begin_sp
        ; define the deferred labels without disturbing any IF that is
        ; active on this line
        lda if_else_lo
        pha
        lda if_else_hi
        pha
        lda if_end_lo
        pha
        lda if_end_hi
        pha
        ldx begin_sp
        lda begin_stack_else_lo,x
        sta if_else_lo
        lda begin_stack_else_hi,x
        sta if_else_hi
        lda begin_stack_end_lo,x
        sta if_end_lo
        lda begin_stack_end_hi,x
        sta if_end_hi
        jsr emit_if_else_label_def
        jsr emit_if_end_label_def
        pla
        sta if_end_hi
        pla
        sta if_end_lo
        pla
        sta if_else_hi
        pla
        sta if_else_lo
        rts

compile_if:
        jsr alloc_if_labels
        jsr compile_condition_boolean
        bcs compile_if_bad
        jsr emit_push_expr
        lda #COND_TRUTH
        sta cond_op
        jsr parse_then_token
        bcs compile_if_bad

        jsr line_skip_spaces
        jsr line_at_end
        bcs compile_if_bad
        jsr line_peek
        cmp #'0'
        bcc _compile_if_inline
        cmp #'9' + 1
        bcc _compile_if_line_target

_compile_if_inline:
        jsr emit_pop_lhs
        jsr emit_if_comparison_inline_start
        jsr push_if_labels
        bcs compile_if_bad
        lda compile_stop_on_else
        pha
        lda compile_found_else
        pha
        lda if_begin_taken
        pha
        lda #1
        sta compile_stop_on_else
        lda #0
        sta compile_found_else
        sta if_begin_taken
        jsr compile_line_statements
        lda compile_found_else
        sta if_else_found
        lda if_begin_taken
        sta if_block_open
        pla
        sta if_begin_taken
        pla
        sta compile_found_else
        pla
        sta compile_stop_on_else
        lda compile_error
        beq +
        jsr pop_if_labels
        rts
+       jsr pop_if_labels
        bcs compile_if_bad
        lda if_block_open
        beq _compile_if_not_block
        rts                     ; labels are defined by the matching BEND
_compile_if_not_block:
        lda if_else_found
        beq _compile_if_no_else
        jsr emit_jmp_if_end
        jsr emit_if_else_label_def
        jsr push_if_labels
        bcs compile_if_bad
        jsr compile_line_statements
        lda compile_error
        beq +
        jsr pop_if_labels
        rts
+       jsr pop_if_labels
        bcs compile_if_bad
        jsr emit_if_end_label_def
        rts

_compile_if_no_else:
        jsr emit_if_else_label_def
        jsr emit_if_end_label_def
        rts

_compile_if_line_target:
        jsr line_parse_number
        bcs compile_if_bad
        jsr line_number_exists
        bcs compile_if_bad
        lda number_lo
        sta if_target_lo
        lda number_hi
        sta if_target_hi
        jsr emit_pop_lhs
        jsr emit_if_comparison
        jsr emit_jmp_if_target
        jsr emit_if_end_label_def
        jsr line_skip_to_end
        rts

compile_if_bad:
        lda #<msg_error_bad_if
        ldy #>msg_error_bad_if
        jsr fatal_line_error
        rts

parse_then_token:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _parse_then_fail
        jsr line_get
        cmp #TOK_THEN
        beq _parse_then_done

_parse_then_fail:
        sec
        rts

_parse_then_done:
        clc
        rts

parse_if_compare_op:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _parse_if_compare_fail
        jsr line_peek
        cmp #TOK_EQUAL
        beq _parse_if_compare_eq
        cmp #'='
        beq _parse_if_compare_eq
        cmp #TOK_LT
        beq _parse_if_compare_lt
        cmp #'<'
        beq _parse_if_compare_lt
        cmp #TOK_GT
        beq _parse_if_compare_gt
        cmp #'>'
        beq _parse_if_compare_gt

_parse_if_compare_fail:
        sec
        rts

_parse_if_compare_eq:
        jsr line_get
        lda #COND_EQ
        sta cond_op
        clc
        rts

_parse_if_compare_lt:
        jsr line_get
        lda #COND_LT
        sta cond_op
        jsr line_at_end
        bcs _parse_if_compare_done
        jsr line_peek
        cmp #TOK_EQUAL
        beq _parse_if_compare_le
        cmp #'='
        beq _parse_if_compare_le
        cmp #TOK_GT
        beq _parse_if_compare_ne
        cmp #'>'
        beq _parse_if_compare_ne
        bra _parse_if_compare_done

_parse_if_compare_le:
        jsr line_get
        lda #COND_LE
        sta cond_op
        bra _parse_if_compare_done

_parse_if_compare_ne:
        jsr line_get
        lda #COND_NE
        sta cond_op
        bra _parse_if_compare_done

_parse_if_compare_gt:
        jsr line_get
        lda #COND_GT
        sta cond_op
        jsr line_at_end
        bcs _parse_if_compare_done
        jsr line_peek
        cmp #TOK_EQUAL
        beq _parse_if_compare_ge
        cmp #'='
        beq _parse_if_compare_ge
        bra _parse_if_compare_done

_parse_if_compare_ge:
        jsr line_get
        lda #COND_GE
        sta cond_op

_parse_if_compare_done:
        clc
        rts

; boolean context: a float condition value becomes 1/0
compile_condition_boolean:
        jsr compile_condition_or
        bcs +
        lda expr_type
        beq +
        jsr emit_tmpl
        .word out_jsr_ftruth
        lda #0
        sta expr_type
        clc
+       rts

compile_condition_expression:
        jsr compile_condition_or
        rts

compile_condition_or:
        jsr compile_condition_and
        bcc _cond_or_loop
        rts

_cond_or_loop:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _cond_or_done
        jsr line_peek
        cmp #TOK_OR
        beq _cond_or_take
        cmp #TOK_XOR
        beq _cond_xor_take

_cond_or_done:
        clc
        rts

_cond_xor_take:
        jsr line_get
        jsr emit_qint_if_float
        jsr emit_push_expr
        jsr compile_condition_and
        bcs _cond_or_fail
        jsr emit_qint_if_float
        jsr emit_pop_lhs
        jsr emit_tmpl
        .word out_xor_lhs_expr
        lda #0
        sta const_state
        sta expr_type
        bra _cond_or_loop

_cond_or_take:
        jsr line_get
        jsr emit_qint_if_float
        jsr emit_push_expr
        jsr compile_condition_and
        bcs _cond_or_fail
        jsr emit_qint_if_float
        jsr emit_pop_lhs
        jsr emit_bool_or_lhs_expr
        bra _cond_or_loop

_cond_or_fail:
        sec
        rts

compile_condition_and:
        jsr compile_condition_not
        bcc _cond_and_loop
        rts

_cond_and_loop:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _cond_and_done
        jsr line_peek
        cmp #TOK_AND
        beq _cond_and_take

_cond_and_done:
        clc
        rts

_cond_and_take:
        jsr line_get
        jsr emit_qint_if_float
        jsr emit_push_expr
        jsr compile_condition_not
        bcs _cond_and_fail
        jsr emit_qint_if_float
        jsr emit_pop_lhs
        jsr emit_bool_and_lhs_expr
        bra _cond_and_loop

_cond_and_fail:
        sec
        rts

compile_condition_not:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _cond_not_fail
        jsr line_peek
        cmp #TOK_NOT
        beq _cond_not_take
        jsr compile_condition_compare
        rts

_cond_not_take:
        jsr line_get
        jsr line_skip_spaces
        jsr line_at_end
        bcs _cond_not_fail
        jsr line_peek
        cmp #'('
        beq _cond_not_paren
        jsr compile_condition_not
        bcs _cond_not_fail
        jsr emit_qint_if_float
        jsr emit_not_expr
        clc
        rts

_cond_not_paren:
        jsr line_get
        jsr compile_condition_expression
        bcs _cond_not_fail
        jsr line_skip_spaces
        jsr line_at_end
        bcs _cond_not_fail
        jsr line_get
        cmp #')'
        bne _cond_not_fail
        jsr emit_not_expr
        clc
        rts

_cond_not_fail:
        sec
        rts

compile_condition_compare:
        jsr string_expression_starts
        bcc _cond_compare_string
        jsr compile_num_expression
        bcs _cond_compare_fail
        jsr parse_if_compare_op
        bcs _cond_compare_truthy
        lda expr_type
        bne _cond_compare_flhs
        ldx #2
        jsr probe_simple_rhs
        bcs _cond_compare_general
        jsr emit_move_expr_to_lhs
        jsr compile_num_expression
        bcs _cond_compare_fail
        jsr emit_compare_expr_to_bool
        bra _cond_compare_done

_cond_compare_general:
        jsr emit_push_expr
        jsr compile_num_expression
        bcs _cond_compare_fail
        lda expr_type
        bne _cond_compare_int_flt
        jsr emit_pop_lhs
        jsr emit_compare_expr_to_bool
        bra _cond_compare_done

_cond_compare_int_flt:
        jsr emit_pop_promote_lhs
        jsr emit_fcompare_bool
        bra _cond_compare_done

_cond_compare_flhs:
        jsr emit_fpush_expr
        jsr compile_num_expression
        bcs _cond_compare_fail
        lda expr_type
        bne _cond_compare_ff
        jsr emit_float16_expr
_cond_compare_ff:
        jsr emit_fpoparg_expr
        jsr emit_fcompare_bool
        bra _cond_compare_done

_cond_compare_truthy:
_cond_compare_done:
        clc
        rts

_cond_compare_string:
        jsr try_compile_empty_string_compare
        bcc _cond_compare_done
        jsr try_compile_string_ref_compare
        bcc _cond_compare_done
        jsr emit_string_temp_mark
        jsr compile_string_expression
        bcs _cond_compare_fail
        jsr parse_if_compare_op
        bcs _cond_compare_fail
        jsr emit_push_sexpr
        jsr compile_string_expression
        bcs _cond_compare_fail
        jsr emit_pop_slhs
        jsr emit_string_compare_to_bool
        jsr emit_string_temp_release
        clc
        rts

_cond_compare_fail:
        sec
        rts

try_compile_empty_string_compare:
        lda line_idx
        sta line_idx_save
        jsr parse_scalar_string_var_probe
        bcs _try_empty_left_literal
        jsr parse_if_compare_op
        bcs _try_empty_restore_fail
        jsr parse_empty_string_literal
        bcs _try_empty_restore_fail
        lda #0
        sta byte_value
        jsr emit_empty_string_compare
        bcs _try_empty_restore_fail
        clc
        rts

_try_empty_left_literal:
        lda line_idx_save
        sta line_idx
        jsr parse_empty_string_literal
        bcs _try_empty_restore_fail
        jsr parse_if_compare_op
        bcs _try_empty_restore_fail
        jsr parse_scalar_string_var_probe
        bcs _try_empty_restore_fail
        lda #1
        sta byte_value
        jsr emit_empty_string_compare
        bcs _try_empty_restore_fail
        clc
        rts

_try_empty_restore_fail:
        lda line_idx_save
        sta line_idx

_try_empty_fail:
        sec
        rts

parse_scalar_string_var_probe:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _parse_scalar_string_fail
        jsr line_get
        jsr is_var_start
        bcs _parse_scalar_string_fail
        jsr parse_variable_with_first_char
        bcs _parse_scalar_string_fail
        lda var_type
        cmp #VAR_TYPE_STRING
        bne _parse_scalar_string_fail
        jsr line_skip_spaces
        jsr line_at_end
        bcs _parse_scalar_string_ok
        jsr line_peek
        cmp #'('
        beq _parse_scalar_string_fail
        cmp #TOK_PLUS
        beq _parse_scalar_string_fail

_parse_scalar_string_ok:
        clc
        rts

_parse_scalar_string_fail:
        sec
        rts

parse_empty_string_literal:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _parse_empty_string_fail
        jsr line_get
        cmp #'"'
        bne _parse_empty_string_fail
        jsr line_at_end
        bcs _parse_empty_string_fail
        jsr line_get
        cmp #'"'
        bne _parse_empty_string_fail
        jsr line_skip_spaces
        jsr line_at_end
        bcs _parse_empty_string_ok
        jsr line_peek
        cmp #TOK_PLUS
        beq _parse_empty_string_fail

_parse_empty_string_ok:
        clc
        rts

_parse_empty_string_fail:
        sec
        rts

try_compile_string_ref_compare:
        lda line_idx
        sta line_idx_save
        jsr parse_simple_string_ref_probe
        bcs _try_strref_restore_fail
        lda string_ref_type
        sta string_ref_left_type
        jsr parse_if_compare_op
        bcs _try_strref_restore_fail
        jsr parse_simple_string_ref_probe
        bcs _try_strref_restore_fail
        lda string_ref_type
        sta string_ref_right_type

        lda line_idx_save
        sta line_idx
        jsr compile_simple_string_ref_operand
        bcs _try_strref_fail
        lda string_ref_type
        sta string_ref_left_type
        jsr emit_expr_to_lhs
        lda string_ref_left_type
        jsr emit_set_strarg1lo_imm
        jsr parse_if_compare_op
        bcs _try_strref_fail
        jsr compile_simple_string_ref_operand
        bcs _try_strref_fail
        lda string_ref_type
        sta string_ref_right_type
        jsr emit_set_strarg1hi_imm
        jsr emit_string_ref_compare_to_bool
        clc
        rts

_try_strref_restore_fail:
        lda line_idx_save
        sta line_idx

_try_strref_fail:
        sec
        rts

parse_simple_string_ref_probe:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _parse_strref_probe_fail
        jsr line_peek
        cmp #'"'
        beq _parse_strref_probe_literal
        jsr line_get
        jsr is_var_start
        bcs _parse_strref_probe_fail
        jsr parse_variable_with_first_char
        bcs _parse_strref_probe_fail
        lda var_type
        cmp #VAR_TYPE_STRING
        bne _parse_strref_probe_fail
        jsr simple_string_ref_check_var_tail
        bcs _parse_strref_probe_fail
        lda #STRING_REF_HEAP
        sta string_ref_type
        clc
        rts

_parse_strref_probe_literal:
        jsr line_get
        jsr add_string_literal
        bcs _parse_strref_probe_fail
        jsr simple_string_ref_check_tail
        bcs _parse_strref_probe_fail
        lda #STRING_REF_LITERAL
        sta string_ref_type
        clc
        rts

_parse_strref_probe_fail:
        sec
        rts

compile_simple_string_ref_operand:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _compile_strref_operand_fail
        jsr line_peek
        cmp #'"'
        beq _compile_strref_literal
        jsr line_get
        jsr is_var_start
        bcs _compile_strref_operand_fail
        jsr parse_variable_with_first_char
        bcs _compile_strref_operand_fail
        lda var_type
        cmp #VAR_TYPE_STRING
        bne _compile_strref_operand_fail
        jsr simple_string_ref_check_var_tail
        bcs _compile_strref_operand_fail
        lda #VAR_KIND_SCALAR
        sta var_kind
        jsr resolve_var
        bcs _compile_strref_operand_fail
        jsr emit_load_var
        lda #STRING_REF_HEAP
        sta string_ref_type
        clc
        rts

_compile_strref_literal:
        jsr line_get
        jsr add_string_literal
        bcs _compile_strref_operand_fail
        jsr simple_string_ref_check_tail
        bcs _compile_strref_operand_fail
        jsr emit_load_string_ref_to_expr
        lda #STRING_REF_LITERAL
        sta string_ref_type
        clc
        rts

_compile_strref_operand_fail:
        sec
        rts

simple_string_ref_check_var_tail:
        jsr line_skip_spaces
        jsr line_at_end
        bcs simple_strref_tail_ok
        jsr line_peek
        cmp #'('
        beq simple_strref_tail_fail
        bra simple_string_ref_check_tail_peeked

simple_string_ref_check_tail:
        jsr line_skip_spaces
        jsr line_at_end
        bcs simple_strref_tail_ok
        jsr line_peek

simple_string_ref_check_tail_peeked:
        cmp #TOK_PLUS
        beq simple_strref_tail_fail
        cmp #'+'
        beq simple_strref_tail_fail

simple_strref_tail_ok:
        clc
        rts

simple_strref_tail_fail:
        sec
        rts

; public entry: constants surviving to this boundary are emitted here, so
; every consumer still finds the value in exprlo/exprhi
compile_expression:
        jsr compile_num_expression
        bcs +
        lda expr_type
        beq +
        jsr emit_qint_expr
        clc
+       rts

emit_qint_expr:
        lda #0
        sta expr_type
        jsr emit_tmpl_done
        .word out_jsr_qint

emit_qint_if_float:
        lda expr_type
        beq +
        jsr emit_qint_expr
+       rts

compile_num_expression:
        jsr compile_expression_inner
        bcs +
        jsr materialize_const
        clc
+       rts

materialize_const:
        lda const_state
        beq +
        lda #0
        sta const_state
        lda const_lo
        sta number_lo
        lda const_hi
        sta number_hi
        jmp emit_load_number
+       rts

compile_expression_inner:
        jsr compile_term
        bcc _expr_loop
        rts

_expr_loop:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _expr_done
        jsr line_peek
        cmp #TOK_PLUS
        beq _expr_add
        cmp #TOK_MINUS
        beq _expr_sub
_expr_done:
        clc
        rts

_expr_add:
        jsr line_get
        lda const_state
        bne _expr_add_constlhs
        lda expr_type
        bne _expr_add_flhs
        ldx #1
        jsr probe_simple_rhs
        bcs _expr_add_general
        jsr emit_move_expr_to_lhs
        jsr compile_term
        bcs _expr_fail
        jsr materialize_const
        jsr emit_add_lhs_expr
        bra _expr_loop

_expr_add_general:
        jsr emit_push_expr
        jsr compile_term
        bcs _expr_fail
        jsr materialize_const
        lda expr_type
        bne _expr_add_int_flt
        jsr emit_pop_lhs
        jsr emit_add_lhs_expr
        bra _expr_loop

_expr_add_int_flt:
        jsr emit_pop_promote_lhs
        jsr emit_fadd_op
        jmp _expr_loop

_expr_add_flhs:
        jsr emit_fpush_expr
        jsr compile_term
        bcs _expr_fail
        jsr materialize_const
        lda expr_type
        bne _expr_add_ff
        jsr emit_float16_expr
_expr_add_ff:
        jsr emit_fpoparg_expr
        jsr emit_fadd_op
        jmp _expr_loop

_expr_add_constlhs:
        jsr fold_save_lhs
        jsr compile_term
        bcs _expr_constlhs_fail
        jsr fold_restore_lhs
        lda expr_type
        bne _expr_add_const_flt
        lda const_state
        beq _expr_add_mixed
        clc                     ; fold: left + right with 16-bit wrap
        lda fold_lhs_lo
        adc const_lo
        sta const_lo
        lda fold_lhs_hi
        adc const_hi
        sta const_hi
        jmp _expr_loop

_expr_add_const_flt:
        jsr emit_load_lhs_const
        jsr emit_pop_promote_lhs_none
        jsr emit_fadd_op
        jmp _expr_loop

_expr_add_mixed:
        jsr emit_load_lhs_const
        jsr emit_add_lhs_expr
        jmp _expr_loop

_expr_sub:
        jsr line_get
        lda const_state
        bne _expr_sub_constlhs
        lda expr_type
        bne _expr_sub_flhs
        ldx #1
        jsr probe_simple_rhs
        bcs _expr_sub_general
        jsr emit_move_expr_to_lhs
        jsr compile_term
        bcs _expr_fail
        jsr materialize_const
        jsr emit_sub_lhs_expr
        bra _expr_loop

_expr_sub_general:
        jsr emit_push_expr
        jsr compile_term
        bcs _expr_fail
        jsr materialize_const
        lda expr_type
        bne _expr_sub_int_flt
        jsr emit_pop_lhs
        jsr emit_sub_lhs_expr
        bra _expr_loop

_expr_sub_int_flt:
        jsr emit_pop_promote_lhs
        jsr emit_fsub_op
        jmp _expr_loop

_expr_sub_flhs:
        jsr emit_fpush_expr
        jsr compile_term
        bcs _expr_fail
        jsr materialize_const
        lda expr_type
        bne _expr_sub_ff
        jsr emit_float16_expr
_expr_sub_ff:
        jsr emit_fpoparg_expr
        jsr emit_fsub_op
        jmp _expr_loop

_expr_sub_constlhs:
        jsr fold_save_lhs
        jsr compile_term
        bcs _expr_constlhs_fail
        jsr fold_restore_lhs
        lda expr_type
        bne _expr_sub_const_flt
        lda const_state
        beq _expr_sub_mixed
        sec                     ; fold: left - right with 16-bit wrap
        lda fold_lhs_lo
        sbc const_lo
        sta const_lo
        lda fold_lhs_hi
        sbc const_hi
        sta const_hi
        jmp _expr_loop

_expr_sub_const_flt:
        jsr emit_load_lhs_const
        jsr emit_pop_promote_lhs_none
        jsr emit_fsub_op
        jmp _expr_loop

_expr_sub_mixed:
        jsr emit_load_lhs_const
        jsr emit_sub_lhs_expr
        jmp _expr_loop

_expr_constlhs_fail:
        pla                     ; discard the saved left constant
        pla
_expr_fail:
        sec
        rts

; stash the constant left operand on the CPU stack around the right-hand
; compile (expressions nest, so plain variables would be clobbered)
fold_save_lhs:
        pla                     ; return address
        sta fold_ret_lo
        pla
        sta fold_ret_hi
        lda const_lo
        pha
        lda const_hi
        pha
        lda #0
        sta const_state
        lda fold_ret_hi
        pha
        lda fold_ret_lo
        pha
        rts

fold_restore_lhs:
        pla
        sta fold_ret_lo
        pla
        sta fold_ret_hi
        pla
        sta fold_lhs_hi
        pla
        sta fold_lhs_lo
        lda fold_ret_hi
        pha
        lda fold_ret_lo
        pha
        rts


; left operand was integer and already pushed on the CPU stack; right side
; turned out to be float: pop the integer and promote it into ARG
emit_pop_promote_lhs:
        jsr emit_pop_lhs
        jsr emit_tmpl_done
        .word out_jsr_fpromotelhs

; right side is integer but a float operation is needed
emit_float16_expr:
        lda #1
        sta expr_type
        jsr emit_tmpl_done
        .word out_jsr_float16

emit_fpush_expr:
        jsr emit_tmpl_done
        .word out_jsr_fpush

emit_fpoparg_expr:
        jsr emit_tmpl_done
        .word out_jsr_fpoparg

; promote the folded-constant left operand (already in lhslo/hi via
; emit_load_lhs_const) into ARG while the float right side sits in FAC
emit_pop_promote_lhs_none:
        jsr emit_tmpl_done
        .word out_jsr_fpromotelhs

emit_fadd_op:
        jsr emit_tmpl_done
        .word out_jsr_fadd

emit_fsub_op:
        jsr emit_tmpl_done
        .word out_jsr_fsub

emit_fmul_op:
        jsr emit_tmpl_done
        .word out_jsr_fmul

emit_fdiv_op:
        jsr emit_tmpl_done
        .word out_jsr_fdiv

compile_term:
        jsr compile_pfactor
        bcc _term_loop
        rts

_term_loop:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _term_done
        jsr line_peek
        cmp #TOK_MUL
        beq _term_mul
        cmp #TOK_DIV
        beq _term_div
_term_done:
        clc
        rts

_term_mul:
        jsr line_get
        lda const_state
        bne _term_mul_constlhs
        lda expr_type
        bne _term_mul_flhs
        ldx #0
        jsr probe_simple_rhs
        bcs _term_mul_general
        jsr emit_move_expr_to_lhs
        jsr compile_pfactor
        bcs _term_fail
        jsr materialize_const
        jsr emit_mul_lhs_expr
        bra _term_loop

_term_mul_general:
        jsr emit_push_expr
        jsr compile_pfactor
        bcs _term_fail
        jsr materialize_const
        lda expr_type
        bne _term_mul_int_flt
        jsr emit_pop_lhs
        jsr emit_mul_lhs_expr
        bra _term_loop

_term_mul_int_flt:
        jsr emit_pop_promote_lhs
        jsr emit_fmul_op
        jmp _term_loop

_term_mul_flhs:
        jsr emit_fpush_expr
        jsr compile_factor
        bcs _term_fail
        jsr materialize_const
        lda expr_type
        bne _term_mul_ff
        jsr emit_float16_expr
_term_mul_ff:
        jsr emit_fpoparg_expr
        jsr emit_fmul_op
        jmp _term_loop

_term_mul_constlhs:
        jsr fold_save_lhs
        jsr compile_pfactor
        bcs _term_constlhs_fail
        jsr fold_restore_lhs
        lda expr_type
        bne _term_mul_const_flt
        lda const_state
        beq _term_mul_mixed
        jsr fold_mul16          ; const = fold_lhs * const (low 16, like mul16)
        jmp _term_loop

_term_mul_const_flt:
        jsr emit_load_lhs_const
        jsr emit_pop_promote_lhs_none
        jsr emit_fmul_op
        jmp _term_loop

_term_mul_mixed:
        jsr emit_load_lhs_const
        jsr emit_mul_lhs_expr
        jmp _term_loop

; division always produces a float, matching interpreted BASIC
_term_div:
        jsr line_get
        lda const_state
        bne _term_div_constlhs
        lda expr_type
        bne _term_div_flhs
        jsr emit_push_expr
        jsr compile_pfactor
        bcs _term_fail
        jsr materialize_const
        lda expr_type
        bne _term_div_rhs_f
        jsr emit_float16_expr
_term_div_rhs_f:
        jsr emit_pop_promote_lhs
        jsr emit_fdiv_op
        jmp _term_loop

_term_div_flhs:
        jsr emit_fpush_expr
        jsr compile_pfactor
        bcs _term_fail
        jsr materialize_const
        lda expr_type
        bne _term_div_ff
        jsr emit_float16_expr
_term_div_ff:
        jsr emit_fpoparg_expr
        jsr emit_fdiv_op
        jmp _term_loop

_term_div_constlhs:
        jsr fold_save_lhs
        jsr compile_pfactor
        bcs _term_constlhs_fail
        jsr fold_restore_lhs
        jsr materialize_const   ; a constant right side must land in expr
        lda expr_type
        bne _term_div_cf
        jsr emit_float16_expr
_term_div_cf:
        jsr emit_load_lhs_const
        jsr emit_pop_promote_lhs_none
        jsr emit_fdiv_op
        jmp _term_loop

_term_constlhs_fail:
        pla                     ; discard the saved left constant
        pla
_term_fail:
        sec
        rts

; compile-time replicas of the runtime's mul16/div16 so folded results are
; bit-exact with emitted code: low 16 bits of the product, and unsigned
; restoring division where divide-by-zero yields 0

fold_mul16:
        lda #0
        sta fold_res_lo
        sta fold_res_hi
        ldx #16
_fold_mul_loop:
        lda const_lo
        and #1
        beq _fold_mul_skip
        clc
        lda fold_res_lo
        adc fold_lhs_lo
        sta fold_res_lo
        lda fold_res_hi
        adc fold_lhs_hi
        sta fold_res_hi
_fold_mul_skip:
        asl fold_lhs_lo
        rol fold_lhs_hi
        lsr const_hi
        ror const_lo
        dex
        bne _fold_mul_loop
        lda fold_res_lo
        sta const_lo
        lda fold_res_hi
        sta const_hi
        rts

; load the folded left operand straight into lhslo/lhshi (no stack traffic)
emit_load_lhs_const:
        jsr emit_tmpl
        .word out_lda_imm_hex
        lda fold_lhs_lo
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl
        .word out_sta_lhslo
        jsr emit_tmpl
        .word out_lda_imm_hex
        lda fold_lhs_hi
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl_done
        .word out_sta_lhshi

; exponentiation binds tighter than * and / and is left-associative;
; both operands promote to float, the exponent is truncated by fpowi
compile_pfactor:
        jsr compile_factor
        bcc _pfactor_loop
        rts

_pfactor_loop:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _pfactor_done
        jsr line_peek
        cmp #TOK_POW
        beq _pfactor_pow
_pfactor_done:
        clc
        rts

_pfactor_pow:
        jsr line_get
        jsr materialize_const
        lda expr_type
        bne _pfactor_base_f
        jsr emit_tmpl
        .word out_jsr_float16
_pfactor_base_f:
        jsr emit_tmpl
        .word out_jsr_fpush
        jsr compile_factor
        bcs _pfactor_fail
        jsr materialize_const
        lda expr_type
        bne _pfactor_exp_f
        jsr emit_tmpl
        .word out_jsr_float16
_pfactor_exp_f:
        jsr emit_tmpl
        .word out_jsr_fpoparg
        jsr emit_tmpl
        .word out_jsr_fpowi
        lda #1
        sta expr_type
        bra _pfactor_loop

_pfactor_fail:
        sec
        rts

compile_factor:
        lda #0
        sta const_state         ; every factor kind except literals emits
        sta expr_type
        jsr line_skip_spaces
        jsr line_at_end
        bcs _factor_fail
        jsr line_peek
        cmp #'.'
        beq _factor_number      ; leading-dot float literal
        cmp #'$'
        beq _factor_number
        cmp #'0'
        bcc _factor_not_number
        cmp #'9' + 1
        bcc _factor_number

_factor_not_number:
        cmp #'('
        beq _factor_paren
        cmp #TOK_MINUS
        beq _factor_unary_minus
        cmp #TOK_NOT
        beq _factor_unary_not
        cmp #TOK_ABS
        beq _factor_abs
        cmp #TOK_SGN
        beq _factor_sgn
        cmp #TOK_INT
        beq _factor_int
        cmp #TOK_LEN
        beq _factor_len
        cmp #TOK_VAL
        beq _factor_val
        cmp #TOK_PEEK
        beq _factor_peek
        cmp #TOK_RND
        beq _factor_rnd
        cmp #$ff                ; pi
        beq _factor_pi
        cmp #TOK_SQR
        beq _factor_sqr
        cmp #TOK_ASC
        beq _factor_asc
        cmp #TOK_POS
        beq _factor_pos
        cmp #TOK_DEC
        beq _factor_dec
        cmp #TOK_INSTR
        beq _factor_instr
        cmp #TOK_EXT_CE
        beq _factor_ext_ce
        cmp #TOK_JOY
        beq _factor_joy
        cmp #TOK_FRE
        beq _factor_fre
        cmp #TOK_USR
        beq _factor_usr
        cmp #TOK_SIN
        beq _factor_sin
        cmp #TOK_COS
        beq _factor_cos
        cmp #TOK_TAN
        beq _factor_tan
        cmp #TOK_ATN
        beq _factor_atn
        cmp #TOK_LOG
        beq _factor_log
        cmp #TOK_EXP_FN
        beq _factor_exp
        cmp #$a5                ; FN
        bne +
        jmp _factor_fn
+       cmp #$d0                ; RPEN
        bne +
        jmp _factor_rpen
+       cmp #$cd                ; RCOLOR
        bne +
        jmp _factor_rcolor
+       cmp #$cc                ; RGRAPHIC
        bne +
        jmp _factor_rgraphic
+       jsr is_var_start
        bcc _factor_variable
_factor_fail:
        sec
        rts

_factor_pi:
        jsr line_get            ; consume the pi token
        jsr emit_tmpl
        .word out_jsr_pif
        lda #1
        sta expr_type
        clc
        rts

_factor_number:
        lda line_idx
        sta flt_saved_idx
        jsr parse_float_literal_to_string_temp
        bcc _factor_float_literal
        lda flt_saved_idx
        sta line_idx
        jsr line_parse_number
        bcs _factor_number_fail
        lda number_lo
        sta const_lo
        lda number_hi
        sta const_hi
        lda #1
        sta const_state
        clc
        rts

_factor_float_literal:
        jsr intern_string_temp
        bcs _factor_number_fail
        jsr flt_slot_for_string
        bcs _factor_number_fail
        jsr emit_set_varptr_current
        jsr emit_tmpl
        .word out_jsr_floadvar
        lda #1
        sta expr_type
        clc
        rts

_factor_number_fail:
        sec
        rts

_factor_variable:
        jsr line_get
        jsr scrarr_probe        ; T@&( / C@&( reserved screen arrays
        bcc _factor_scrarr
        jsr parse_variable_with_first_char
        bcs _factor_fail
        lda var_type
        jsr var_type_is_numeric
        bcs _factor_fail
        jsr line_skip_spaces
        jsr line_at_end
        bcs _factor_scalar_variable
        jsr line_peek
        cmp #'('
        beq _factor_array_variable

_factor_scalar_variable:
        lda var_name_1
        cmp #$54                ; letter T in tokenized source
        bne _factor_scalar_plain
        lda var_name_2
        cmp #$49                ; letter I
        bne _factor_scalar_plain
        lda var_type
        cmp #VAR_TYPE_FLOAT
        bne _factor_scalar_plain
        jsr emit_tmpl      ; TI reads the jiffy clock
        .word out_jsr_rdti
        lda #1
        sta expr_type
        clc
        rts
_factor_scalar_plain:
        lda var_name_1
        cmp #$53                ; letter S
        bne _factor_scalar_var2
        lda var_name_2
        cmp #$54                ; letter T
        bne _factor_scalar_var2
        lda var_type
        cmp #VAR_TYPE_FLOAT
        bne _factor_scalar_var2
        jsr emit_tmpl_done      ; ST reads the KERNAL status byte
        .word out_jsr_rdst
_factor_scalar_var2:
        lda var_name_1
        cmp #$44                ; letter D
        bne _factor_scalar_var2e
        lda var_name_2
        cmp #$53                ; letter S -> DS drive status
        bne _factor_scalar_var2e
        lda var_type
        cmp #VAR_TYPE_FLOAT
        bne _factor_scalar_var2e
        jsr emit_tmpl_done
        .word out_jsr_rdds
_factor_scalar_var2e:
        lda var_name_1
        cmp #$45                ; letter E
        bne _factor_scalar_var3
        lda var_type
        cmp #VAR_TYPE_FLOAT
        bne _factor_scalar_var3
        lda var_name_2
        cmp #$52                ; letter R -> ER
        beq _factor_er
        cmp #$4c                ; letter L -> EL
        beq _factor_el
_factor_scalar_var3:
        jsr resolve_var
        bcs _factor_fail
        jsr emit_load_var_typed
        clc
        rts

_factor_er:
        jsr emit_tmpl_done
        .word out_jsr_rder

_factor_el:
        jsr emit_tmpl_done
        .word out_jsr_rdel

_factor_array_variable:
        lda #VAR_KIND_ARRAY1
        sta var_kind
        jsr resolve_existing_var
        bcs _factor_fail
        lda current_var_data_lo
        sta array_base_lo
        lda current_var_data_hi
        sta array_base_hi
        lda current_sym_index   ; index expressions may contain other arrays
        pha
        jsr compile_array_index
        pla
        sta array_sym_index
        bcs _factor_fail
        lda array_base_lo
        sta current_var_data_lo
        lda array_base_hi
        sta current_var_data_hi
        jsr emit_set_arrayptr_current
        ldx array_sym_index
        lda sym_type,x
        cmp #VAR_TYPE_FLOAT
        beq _factor_array_float
        jsr emit_load_ptr
        clc
        rts

_factor_array_float:
        jsr emit_tmpl
        .word out_jsr_floadvar
        lda #1
        sta expr_type
        clc
        rts

_factor_paren:
        jsr line_get
        jsr compile_condition_expression ; full value grammar inside parens,
                                         ; so (X AND 2)=2 and (A=B)+1 work;
                                         ; plain arith still folds constants
        bcs _factor_fail
        jsr line_skip_spaces
        jsr line_at_end
        bcs _factor_fail
        jsr line_get
        cmp #')'
        bne _factor_fail
        clc
        rts

_factor_unary_minus:
        jsr line_get
        jsr compile_factor
        bcs _factor_fail
        lda const_state
        beq _factor_minus_emit
        sec                            ; fold: 0 - value, same wrap as runtime
        lda #0
        sbc const_lo
        sta const_lo
        lda #0
        sbc const_hi
        sta const_hi
        clc
        rts
_factor_minus_emit:
        lda expr_type
        beq _factor_minus_int
        jsr emit_tmpl_done
        .word out_jsr_fneg
_factor_minus_int:
        jsr emit_neg_expr
        clc
        rts

_factor_unary_not:
        jsr line_get
        jsr compile_factor
        bcs _factor_fail
        lda const_state
        beq _factor_not_emit
        lda const_lo                   ; fold: 1 if zero, 0 if nonzero
        ora const_hi
        beq _factor_not_one
        lda #0
        bra _factor_not_store
_factor_not_one:
        lda #1
_factor_not_store:
        sta const_lo
        lda #0
        sta const_hi
        clc
        rts
_factor_not_emit:
        lda expr_type
        beq _factor_not_int
        jsr emit_qint_expr
_factor_not_int:
        jsr emit_not_expr
        clc
        rts

_factor_len:
        jsr line_get
        jsr line_skip_spaces
        jsr line_at_end
        bcs _factor_fail
        jsr line_get
        cmp #'('
        bne _factor_fail
        jsr emit_string_temp_mark
        jsr compile_string_expression
        bcs _factor_fail
        jsr line_skip_spaces
        jsr line_at_end
        bcs _factor_fail
        jsr line_get
        cmp #')'
        bne _factor_fail
        jsr emit_string_len_expr
        jsr emit_string_temp_release
        clc
        rts

_factor_val:
        jsr line_get
        jsr parse_open_paren
        bcs _factor_fail
        jsr emit_string_temp_mark
        jsr compile_string_expression
        bcs _factor_fail
        jsr parse_close_paren
        bcs _factor_fail
        jsr emit_val_string_expr
        jsr emit_string_temp_release
        clc
        rts

_factor_abs:
        jsr line_get
        jsr parse_open_paren
        bcs _factor_fail
        jsr compile_num_expression
        bcs _factor_fail
        jsr parse_close_paren
        bcs _factor_fail
        lda expr_type
        beq _factor_abs_int
        jsr emit_tmpl_done
        .word out_jsr_fabsf
_factor_abs_int:
        jsr emit_abs_expr
        clc
        rts

_factor_sgn:
        jsr line_get
        jsr parse_open_paren
        bcs _factor_fail
        jsr compile_num_expression
        bcs _factor_fail
        jsr parse_close_paren
        bcs _factor_fail
        lda expr_type
        beq _factor_sgn_int
        jsr emit_tmpl_done
        .word out_jsr_fsgnf
_factor_sgn_int:
        jsr emit_sgn_expr
        clc
        rts

_factor_int:
        jsr line_get
        jsr parse_open_paren
        bcs _factor_fail
        jsr compile_num_expression
        bcs _factor_fail
        jsr parse_close_paren
        bcs _factor_fail
        lda expr_type
        beq _factor_int_done
        jsr emit_tmpl
        .word out_jsr_fintf
_factor_int_done:
        clc
        rts

_factor_peek:
        jsr line_get
        jsr parse_paren_expr
        bcs _factor_fail
        jsr emit_peek_expr
        clc
        rts

; RND(x): the argument is evaluated and ignored; every call steps the
; generator (interpreted RND(0)/RND(-x) semantics are not modeled)
_factor_rnd:
        jsr line_get
        jsr parse_paren_expr
        bcs _factor_fail
        jsr emit_tmpl
        .word out_jsr_rndf
        lda #1
        sta expr_type
        clc
        rts

_factor_sqr:
        jsr line_get
        jsr parse_open_paren
        bcs _factor_fail
        jsr compile_num_expression
        bcs _factor_fail
        jsr parse_close_paren
        bcs _factor_fail
        lda expr_type
        bne _factor_sqr_f
        jsr emit_tmpl
        .word out_jsr_float16
_factor_sqr_f:
        jsr emit_tmpl
        .word out_jsr_sqrf
        lda #1
        sta expr_type
        clc
        rts

_factor_asc:
        jsr line_get
        jsr parse_open_paren
        bcs _factor_fail
        jsr emit_string_temp_mark
        jsr compile_string_expression
        bcs _factor_fail
        jsr parse_close_paren
        bcs _factor_fail
        jsr emit_tmpl
        .word out_jsr_ascstr
        jsr emit_string_temp_release
        clc
        rts

_factor_pos:
        jsr line_get
        jsr parse_paren_expr
        bcs _factor_fail
        jsr emit_tmpl_done
        .word out_jsr_posf

_factor_dec:
        jsr line_get
        jsr parse_open_paren
        bcs _factor_dec_fail
        jsr emit_string_temp_mark
        jsr compile_string_expression
        bcs _factor_dec_fail
        jsr parse_close_paren
        bcs _factor_dec_fail
        jsr emit_tmpl
        .word out_jsr_decstr
        jsr emit_string_temp_release
        clc
        rts

_factor_dec_fail:
        sec
        rts

_factor_instr:
        jsr line_get
        jsr parse_open_paren
        bcs _factor_dec_fail
        jsr emit_string_temp_mark
        jsr compile_string_expression
        bcs _factor_dec_fail
        jsr emit_push_sexpr
        jsr parse_comma
        bcs _factor_dec_fail
        jsr compile_string_expression
        bcs _factor_dec_fail
        jsr parse_close_paren
        bcs _factor_dec_fail
        jsr emit_pop_slhs
        jsr emit_tmpl
        .word out_jsr_instrf
        jsr emit_string_temp_release
        clc
        rts

_factor_ext_ce:
        jsr line_get
        jsr line_at_end
        bcs _factor_fail
        jsr line_get
        cmp #TOK_CE_WPEEK
        beq _factor_wpeek
        cmp #$03                ; BUMP
        beq +
        cmp #$0f                ; RPLAY
        beq _factor_rplay
        cmp #$08                ; LOG10
        beq _factor_log10
        cmp #$16                ; LOG2
        beq _factor_log2
        cmp #$0b                ; MOD
        beq _factor_mod
        cmp #$02                ; POT
        beq _factor_pot
        cmp #$04                ; LPEN
        beq _factor_lpen
        cmp #$0c                ; PIXEL
        bne _factor_no_pixel
        jmp _factor_pixel
_factor_no_pixel:
        cmp #$13                ; HASBIT
        bne _factor_no_hasbit
        jmp _factor_hasbit
_factor_no_hasbit:
        cmp #$09                ; RWINDOW
        bne _factor_no_rwin
        jmp _factor_rwindow
_factor_no_rwin:
        cmp #$05                ; RSPPOS
        beq _factor_rsppos
        cmp #$06                ; RSPRITE
        beq _factor_rsprite
        cmp #$07                ; RSPCOLOR
        beq _factor_rspcolor
        cmp #$11                ; DECBIN
        beq _factor_decbin
        bra _factor_fail
+
        jsr parse_paren_expr
        bcs _factor_fail
        jsr emit_tmpl_done
        .word out_jsr_bumpf

_factor_wpeek:
        jsr parse_paren_expr
        bcs _factor_fail
        jsr emit_wpeek_expr
        clc
        rts

_factor_log10:
        lda #<out_jsr_log10f
        ldy #>out_jsr_log10f
        jmp _factor_ffn_arg

_factor_log2:
        lda #<out_jsr_log2f
        ldy #>out_jsr_log2f
        jmp _factor_ffn_arg

_factor_mod:
        jsr parse_open_paren
        bcs _factor_fail
        jsr compile_expression
        bcs _factor_fail
        jsr emit_tmpl
        .word out_jsr_modseta
        jsr parse_comma
        bcs _factor_fail
        jsr compile_expression
        bcs _factor_fail
        jsr parse_close_paren
        bcs _factor_fail
        jsr emit_tmpl_done
        .word out_jsr_modf

_factor_rsppos:
        jsr parse_open_paren
        bcs _factor_fail
        jsr compile_expression
        bcs _factor_fail
        jsr emit_tmpl
        .word out_jsr_rspset
        jsr parse_comma
        bcs _factor_fail
        jsr compile_expression
        bcs _factor_fail
        jsr parse_close_paren
        bcs _factor_fail
        jsr emit_tmpl_done
        .word out_jsr_rspposf

_factor_rsprite:
        jsr parse_open_paren
        bcs _factor_fail
        jsr compile_expression
        bcs _factor_fail
        jsr emit_tmpl
        .word out_jsr_rspset
        jsr parse_comma
        bcs _factor_fail
        jsr compile_expression
        bcs _factor_fail
        jsr parse_close_paren
        bcs _factor_fail
        jsr emit_tmpl_done
        .word out_jsr_rspritef

_factor_decbin:
        jsr parse_open_paren
        bcs _factor_fail
        jsr emit_string_temp_mark
        jsr compile_string_expression
        bcs _factor_fail
        jsr parse_close_paren
        bcs _factor_fail
        jsr emit_tmpl
        .word out_jsr_decbinf
        jsr emit_string_temp_release
        clc
        rts

_factor_pot:
        lda #<out_jsr_potf
        ldy #>out_jsr_potf
        bra _factor_one
_factor_lpen:
        lda #<out_jsr_lpenf
        ldy #>out_jsr_lpenf
        bra _factor_one
_factor_rspcolor:
        lda #<out_jsr_rspcolorf
        ldy #>out_jsr_rspcolorf

; one-arg int functions
_factor_one:
        pha
        phy
        jsr parse_open_paren
        bcs _factor_one_fail
        jsr compile_expression
        bcs _factor_one_fail
        jsr parse_close_paren
        bcs _factor_one_fail
        ply
        pla
        jmp out_zstr_ok
_factor_one_fail:
        ply
        pla
        sec
        rts

; FN name(arg): argument to FAC, call the DEF body
_factor_fn:
        jsr line_get            ; consume the FN token
        jsr parse_fn_name
        bcs _ffn_fail
        jsr fn_lookup
        bcs _ffn_fail           ; FN before its DEF line
        phx
        jsr parse_open_paren
        bcs _ffn_fail_pop
        jsr compile_num_expression
        bcs _ffn_fail_pop
        jsr parse_close_paren
        bcs _ffn_fail_pop
        lda expr_type
        bne _ffn_flt
        jsr emit_tmpl
        .word out_jsr_float16
_ffn_flt:
        pla
        jsr fn_set_ref
        jsr emit_tmpl
        .word out_jsr_label
        jsr out_fn_ref
        jsr out_cr
        lda #1
        sta expr_type
        clc
        rts
_ffn_fail_pop:
        plx
_ffn_fail:
        sec
        rts

_factor_rwindow:
        lda #<out_jsr_rwindowf
        ldy #>out_jsr_rwindowf
        bra _factor_one

_factor_rpen:
        jsr line_get            ; consume the RPEN token
        lda #<out_jsr_rpenf
        ldy #>out_jsr_rpenf
        bra _factor_one

_factor_rcolor:
        jsr line_get            ; consume the RCOLOR token
        lda #<out_jsr_rcolorf
        ldy #>out_jsr_rcolorf
        bra _factor_one

; RGRAPHIC(screen, parameter) reads screen state through the blob
; (fn 22); stages through the DMA arg slots like PIXEL
_factor_rgraphic:
        jsr line_get            ; consume the RGRAPHIC token
        jsr emit_tmpl
        .word out_jsr_dmarst
        jsr parse_open_paren
        bcs _frg_fail
        jsr cglcoord
        bcs _frg_fail
        jsr parse_comma
        bcs _frg_fail
        jsr cglcoord
        bcs _frg_fail
        jsr parse_close_paren
        bcs _frg_fail
        lda #22
        jsr emit_lda_imm
        jsr emit_tmpl
        .word out_jsr_gfxcall
        lda #0
        sta expr_type
        jsr emit_tmpl_done
        .word out_pixel_res
_frg_fail:
        sec
        rts

; PIXEL(x,y) reads a pixel through the blob (fn 8); note it stages
; through the DMA arg slots, so PIXEL inside a DMA statement's own
; argument list is not supported
_factor_pixel:
        jsr emit_tmpl
        .word out_jsr_dmarst
        jsr parse_open_paren
        bcs _fpix_fail
        jsr cglcoord
        bcs _fpix_fail
        jsr parse_comma
        bcs _fpix_fail
        jsr cglcoord
        bcs _fpix_fail
        jsr parse_close_paren
        bcs _fpix_fail
        lda #8
        jsr emit_lda_imm
        jsr emit_tmpl
        .word out_jsr_gfxcall
        lda #0
        sta expr_type
        jsr emit_tmpl_done
        .word out_pixel_res
_fpix_fail:
        sec
        rts

; HASBIT(address, bit) -- SETBIT's address resolution, then a read
_factor_hasbit:
        jsr parse_open_paren
        bcs _fhb_fail
        jsr compile_num_expression
        bcs _fhb_fail
        lda expr_type
        beq _fhb_a16
        jsr emit_tmpl
        .word out_jsr_bitadr32
        bra _fhb_bit
_fhb_a16:
        jsr emit_tmpl
        .word out_jsr_bitadr16
_fhb_bit:
        jsr parse_comma
        bcs _fhb_fail
        jsr compile_expression
        bcs _fhb_fail
        jsr parse_close_paren
        bcs _fhb_fail
        lda #0
        sta expr_type
        jsr emit_tmpl_done
        .word out_jsr_hasbitf
_fhb_fail:
        sec
        rts

_factor_rplay:
        jsr parse_paren_expr
        bcs _factor_fail
        jsr emit_tmpl_done
        .word out_jsr_rplayf

_factor_sin:
        lda #<out_jsr_sinf
        ldy #>out_jsr_sinf
        bra _factor_ffn_entry
_factor_cos:
        lda #<out_jsr_cosf
        ldy #>out_jsr_cosf
        bra _factor_ffn_entry
_factor_tan:
        lda #<out_jsr_tanf
        ldy #>out_jsr_tanf
        bra _factor_ffn_entry
_factor_atn:
        lda #<out_jsr_atnf
        ldy #>out_jsr_atnf
        bra _factor_ffn_entry
_factor_log:
        lda #<out_jsr_logf
        ldy #>out_jsr_logf
        bra _factor_ffn_entry
_factor_exp:
        lda #<out_jsr_expf
        ldy #>out_jsr_expf
        bra _factor_ffn_entry

; shared: FN(x) over a float argument; A/Y = the jsr template.
; The template pointer rides the CPU stack: the argument may contain
; nested math functions that reuse this handler.
_factor_ffn_entry:
        pha
        phy
        jsr line_get            ; consume the function token
        bra _factor_ffn_paren
_factor_ffn_arg:
        pha
        phy
_factor_ffn_paren:
        jsr parse_open_paren
        bcs _factor_ffn_fail
        jsr compile_num_expression
        bcs _factor_ffn_fail
        jsr parse_close_paren
        bcs _factor_ffn_fail
        lda expr_type
        bne _factor_ffn_flt
        jsr emit_tmpl
        .word out_jsr_float16
_factor_ffn_flt:
        ply
        pla
        jsr out_zstr
        lda #1
        sta expr_type
        clc
        rts
_factor_ffn_fail:
        ply
        pla
        sec
        rts

_factor_usr:
        jsr line_get
        jsr parse_paren_expr
        bcs _factor_fail
        jsr emit_tmpl_done
        .word out_jsr_usrf

_factor_fre:
        jsr line_get
        jsr parse_paren_expr
        bcs _factor_fail
        jsr emit_tmpl
        .word out_jsr_fref
        lda #1
        sta expr_type           ; FRE exceeds signed 16 bits: float
        clc
        rts

_factor_scrarr:
        jsr compile_scrarr_index
        bcs _factor_fail
        lda scrarr_kind
        bne _factor_scrarr_c
        lda #<out_jsr_tscrf
        ldy #>out_jsr_tscrf
        bra _factor_scrarr_emit
_factor_scrarr_c:
        lda #<out_jsr_cscrf
        ldy #>out_jsr_cscrf
_factor_scrarr_emit:
        jmp out_zstr_ok

_factor_joy:
        jsr line_get            ; consume the JOY token
        jsr parse_paren_expr
        bcs _factor_fail
        jsr emit_tmpl_done
        .word out_jsr_joyf

compile_array_index:
        lda current_sym_index
        sta array_sym_index
        jsr line_skip_spaces
        jsr line_at_end
        bcs _compile_array_index_fail
        jsr line_get
        cmp #'('
        bne _compile_array_index_fail
        jsr compile_expression
        bcs _compile_array_index_fail
        lda #0
        sta array_dim_index
        jsr load_current_array_extent
        bcs _compile_array_index_fail
        jsr emit_array_bounds_check
        lda #1
        sta array_dim_index

_compile_array_index_next:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _compile_array_index_fail
        jsr line_get
        cmp #','
        beq _compile_array_index_more
        cmp #')'
        bne _compile_array_index_fail
        ldx array_sym_index
        lda array_dim_index
        cmp sym_rank,x
        bne _compile_array_index_fail
        clc
        rts

_compile_array_index_more:
        ldx array_sym_index
        lda array_dim_index
        cmp sym_rank,x
        bcs _compile_array_index_fail
        jsr emit_push_expr
        jsr load_current_array_extent
        bcs _compile_array_index_fail
        jsr emit_load_number
        jsr emit_pop_lhs
        jsr emit_mul_lhs_expr
        jsr emit_push_expr
        jsr compile_expression
        bcs _compile_array_index_fail
        jsr load_current_array_extent
        bcs _compile_array_index_fail
        jsr emit_array_bounds_check
        jsr emit_pop_lhs
        jsr emit_add_lhs_expr
        inc array_dim_index
        bra _compile_array_index_next

_compile_array_index_fail:
        sec
        rts

load_current_array_extent:
        ldx array_sym_index
        lda array_dim_index
        beq _load_array_dim0
        cmp #1
        beq _load_array_dim1
        cmp #2
        beq _load_array_dim2
        cmp #3
        beq _load_array_dim3
        cmp #4
        beq _load_array_dim4
        cmp #5
        beq _load_array_dim5
        sec
        rts

_load_array_dim0:
        lda sym_dim0_lo,x
        sta number_lo
        lda sym_dim0_hi,x
        sta number_hi
        clc
        rts

_load_array_dim1:
        lda sym_dim1_lo,x
        sta number_lo
        lda sym_dim1_hi,x
        sta number_hi
        clc
        rts

_load_array_dim2:
        lda sym_dim2_lo,x
        sta number_lo
        lda sym_dim2_hi,x
        sta number_hi
        clc
        rts

_load_array_dim3:
        lda sym_dim3_lo,x
        sta number_lo
        lda sym_dim3_hi,x
        sta number_hi
        clc
        rts

_load_array_dim4:
        lda sym_dim4_lo,x
        sta number_lo
        lda sym_dim4_hi,x
        sta number_hi
        clc
        rts

_load_array_dim5:
        lda sym_dim5_lo,x
        sta number_lo
        lda sym_dim5_hi,x
        sta number_hi
        clc
        rts

compile_print:
        lda #0
        sta print_suppress_cr

_print_loop:
        jsr line_skip_spaces
        jsr line_at_print_end
        bcs _print_finish

        jsr line_peek
        cmp #'"'
        beq _print_string
        cmp #';'
        beq _print_semicolon
        cmp #','
        beq _print_comma
        cmp #TOK_CHR_STR
        beq _print_chr
        cmp #TOK_TAB
        beq _print_tab
        cmp #TOK_SPC
        beq _print_spc
        bra _print_expression

_print_expression:
        jsr try_compile_print_string_var
        bcc _print_string_var_done
        jsr try_compile_print_numeric_var
        bcc _print_string_var_done
        jsr string_expression_starts
        bcs _print_numeric_expression
        jsr emit_string_temp_mark
        jsr compile_string_expression
        bcs _print_expression_bad
        jsr emit_print_string_expr
        jsr emit_string_temp_release
        bra _print_string_var_done

_print_numeric_expression:
        jsr compile_condition_expression
        bcs _print_expression_bad
        lda expr_type
        bne _print_numeric_float
        jsr emit_tmpl
        .word out_jsr_printuint
        bra _print_string_var_done

_print_numeric_float:
        jsr emit_tmpl
        .word out_jsr_printflt

_print_string_var_done:
        lda #0
        sta print_suppress_cr
        bra _print_loop

_print_expression_bad:
        lda #<msg_error_unsupported_print
        ldy #>msg_error_unsupported_print
        jsr fatal_statement_error
        rts

_print_string:
        jsr line_get                         ; opening quote
        lda #0
        sta print_suppress_cr
        jsr add_string_literal
        bcs _print_expression_bad
        jsr emit_print_string_current
        bra _print_loop

_print_semicolon:
        jsr line_get
        lda #1
        sta print_suppress_cr
        bra _print_loop

_print_comma:
        jsr line_get
        jsr emit_print_comma
        lda #0
        sta print_suppress_cr
        bra _print_loop

_print_tab:
        jsr line_get                         ; TAB( token includes the paren
        jsr compile_expression
        bcs _print_expression_bad
        jsr line_skip_spaces
        jsr line_get
        cmp #')'
        bne _print_expression_bad
        jsr emit_tmpl
        .word out_jsr_tabto
        lda #0
        sta print_suppress_cr
        jmp _print_loop

_print_spc:
        jsr line_get                         ; SPC( token includes the paren
        jsr compile_expression
        bcs _print_expression_bad
        jsr line_skip_spaces
        jsr line_get
        cmp #')'
        bne _print_expression_bad
        jsr emit_tmpl
        .word out_jsr_spcn
        lda #0
        sta print_suppress_cr
        jmp _print_loop

_print_chr:
        jsr line_get                         ; CHR$
        jsr line_skip_spaces
        jsr line_get
        cmp #'('
        bne _print_expression_bad
        jsr compile_expression
        bcs _print_expression_bad
        jsr line_skip_spaces
        jsr line_get
        cmp #')'
        bne _print_expression_bad
        jsr emit_print_char_expr
        lda #0
        sta print_suppress_cr
        bra _print_loop

_print_finish:
        lda print_suppress_cr
        bne _print_done
        lda #13
        jsr emit_chout_imm
_print_done:
        rts

; TI, ST, ER, EL read live machine state; carry clear when the parsed
; plain variable is one of them (they must go through the factor
; intercepts, not variable fast paths)
is_special_numeric_var:
        lda var_type
        cmp #VAR_TYPE_FLOAT
        bne _special_var_no
        lda var_name_1
        cmp #$44                ; D
        bne _special_var_t
        lda var_name_2
        cmp #$53                ; DS reads the drive status
        beq _special_var_yes
        bra _special_var_no
_special_var_t:
        cmp #$54                ; T
        bne _special_var_e_s
        lda var_name_2
        cmp #$49                ; TI
        beq _special_var_yes
        bra _special_var_no
_special_var_e_s:
        cmp #$53                ; S
        bne _special_var_e
        lda var_name_2
        cmp #$54                ; ST
        beq _special_var_yes
        bra _special_var_no
_special_var_e:
        cmp #$45                ; E
        bne _special_var_no
        lda var_name_2
        cmp #$52                ; ER
        beq _special_var_yes
        cmp #$4c                ; EL
        beq _special_var_yes
_special_var_no:
        sec
        rts
_special_var_yes:
        clc
        rts

; TRAP line arms the handler (address resolved at compile time);
; bare TRAP disarms. RESUME line clears ER and jumps; bare RESUME and
; RESUME NEXT would need per-statement addresses and stay unsupported.
compile_trap:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcc _compile_trap_arm
        jsr emit_tmpl_done
        .word out_jsr_trapoff

_compile_trap_arm:
        jsr line_parse_number
        bcs compile_trap_bad
        jsr line_number_exists
        bcs compile_trap_bad
        jsr emit_tmpl
        .word out_lda_label_lo_imm
        jsr out_label_from_number
        jsr out_cr
        jsr emit_tmpl
        .word out_sta_traplo
        jsr emit_tmpl
        .word out_lda_label_hi_imm
        jsr out_label_from_number
        jsr out_cr
        jsr emit_tmpl_done
        .word out_sta_traphi

; dispatch the $FE second byte for music/sprite statements; carry set
; hands anything else back to the legacy handler (WPOKE, BEGIN, BEND)
compile_ext_fe:
        jsr line_at_end
        bcs _compile_ext_other
        jsr line_peek
        ldx #(_cef_tab_end - _cef_tab) - 1
_compile_ext_scan:
        cmp _cef_tab,x
        beq _compile_ext_take
        dex
        bpl _compile_ext_scan
_compile_ext_other:
        sec
        rts
_compile_ext_take:
        phx                     ; line_get clobbers X (the table index)
        jsr line_get            ; consume the second byte
        plx
        txa
        asl a
        tax
        jmp (_cef_jtab,x)

; accepted FE second bytes, index-paired with their handlers below
_cef_tab:
        .byte $03, $04, $05, $0a, $0b, $3e, $3f, $0d
        .byte $0e, $0f, $10, $11, $15, $2a, $4b, $17
        .byte $39, $3b, $3c, $06, $07, $08, $13, $37
        .byte $1d, $18, $19, $41, $42, $1a, $40, $47, $48
        .byte $1f, $21, $02, $09, $54, $1b, $16, $2d
        .byte $2e, $30, $33, $34, $2f, $32, $31, $4c
_cef_tab_end:
_cef_jtab:
        .word compile_filter, compile_play, compile_tempo, compile_envelope
        .word compile_sleep, compile_mouse, compile_rmouse, _compile_ext_dopen
        .word _compile_ext_append, compile_dclose, compile_bsave, compile_bload
        .word _compile_ext_dclear, _compile_ext_erase, _compile_ext_chdir, compile_collision
        .word compile_attr_fg, _compile_ext_bkg, _compile_ext_bdr, compile_movspr
        .word compile_sprite, compile_sprcolor, compile_concat, _compile_ext_format
        .word compile_wpoke, compile_begin, compile_bend
        .word compile_cursor, compile_rcursor, compile_window
        .word compile_diskstmt, compile_fgoto, compile_fgosub
        .word compile_dma, compile_edma
        .word compile_bank, compile_rreg, compile_vsync
        .word compile_boot, compile_sprsav, compile_setbit
        .word compile_screen, compile_ellipse, compile_pen, compile_palette
        .word compile_polygon, compile_gcopy, compile_viewport, compile_dot
_compile_ext_format:
        lda #3                  ; FORMAT and HEADER are ROM aliases
        jmp compile_cmdname
_compile_ext_dopen:
        lda #$52
        jmp compile_dopen
_compile_ext_append:
        lda #$41
        jmp compile_dopen_append
_compile_ext_dclear:
        lda #6
        jmp compile_cmdbare
_compile_ext_erase:
        lda #0
        jmp compile_cmdname
_compile_ext_chdir:
        lda #4
        jmp compile_cmdname
_compile_ext_bkg:
        lda #<out_jsr_bkgset
        ldy #>out_jsr_bkgset
        jmp compile_attr_one
_compile_ext_bdr:
        lda #<out_jsr_bdrset
        ldy #>out_jsr_bdrset
        jmp compile_attr_one

; PLAY [string1 ... string6]: argument position selects the voice;
; bare PLAY silences everything
compile_play:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcc _compile_playargs
        jsr emit_tmpl_done
        .word out_jsr_playoff
_compile_playargs:
        lda #0
        sta play_track_no
_compile_play_loop:
        jsr emit_string_temp_mark
        jsr compile_string_expression
        bcs _compile_play_bad
        jsr emit_tmpl
        .word out_lda_imm_hex
        lda play_track_no
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl
        .word out_sta_playarg
        jsr emit_tmpl
        .word out_jsr_playtrk
        jsr emit_string_temp_release
        jsr parse_opt_comma
        bcs _compile_play_done
        inc play_track_no
        lda play_track_no
        cmp #6
        bcc _compile_play_loop
_compile_play_bad:
        lda #<msg_error_bad_play
        ldy #>msg_error_bad_play
        jsr fatal_statement_error
        rts
_compile_play_done:
        clc
        rts

; FILTER sid [, freq, lp, bp, hp, res]: trailing args optional
compile_filter:
        jsr compile_expression
        bcs compile_env_bad
        jsr emit_tmpl
        .word out_jsr_fltsetn
        ldx #0
_compile_flt_loop:
        phx
        jsr parse_opt_comma
        bcs _compile_flt_done
        jsr compile_expression
        bcs _compile_flt_badx
        plx
        phx
        lda fltsetterlo,x
        ldy fltsetterhi,x
        jsr out_zstr
        plx
        inx
        cpx #5
        bcc _compile_flt_loop
        clc
        rts
_compile_flt_done:
        plx
        clc
        rts
_compile_flt_badx:
        plx
        jmp compile_env_bad

fltsetterlo:
        .byte <out_jsr_fltsetf, <out_jsr_fltsetlp, <out_jsr_fltsetbp
        .byte <out_jsr_fltsethp, <out_jsr_fltsetres
fltsetterhi:
        .byte >out_jsr_fltsetf, >out_jsr_fltsetlp, >out_jsr_fltsetbp
        .byte >out_jsr_fltsethp, >out_jsr_fltsetres

; FOREGROUND / COLOR: text colour via the runtime table
compile_attr_fg:
        lda #<out_jsr_fgset
        ldy #>out_jsr_fgset

; shared one-expression attribute statement; A/Y = the setter template
compile_attr_one:
        pha
        phy
        jsr compile_expression
        bcs _cao_bad
        ply
        pla
        jmp out_zstr_ok
_cao_bad:
        ply
        pla
        jmp compile_env_bad

; $E0-prefixed statements: only CHARDEF ($96) is supported
compile_e0:
        jsr line_at_end
        bcs _ce0_bad
        jsr line_peek
        cmp #$96
        bne _ce0_char
        jsr line_get
        jsr compile_expression
        bcs _ce0_bad
        jsr emit_tmpl
        .word out_jsr_chsetidx
_ce0_bytes:
        jsr parse_opt_comma
        bcs _ce0_done
        jsr compile_expression
        bcs _ce0_bad
        jsr emit_tmpl
        .word out_jsr_chputb
        bra _ce0_bytes
_ce0_char:
        ; CHAR col,row,h,w,dir,string[,charset]
        jsr emit_tmpl
        .word out_jsr_dmarst
        lda #0
        sta cdma_i
        ldx #5
_ce0_args:
        phx
        jsr cglcoord
        plx
        bcs _ce0_bad2
        dex
        beq _ce0_str
        phx
        jsr parse_comma
        plx
        bcs _ce0_bad2
        bra _ce0_args
_ce0_str:
        jsr parse_comma
        bcs _ce0_bad2
        jsr compile_string_expression
        bcs _ce0_bad2
        jsr emit_tmpl
        .word out_jsr_charstage
        jsr parse_opt_comma
        bcs _ce0_go
        jsr cglcoord
        bcs _ce0_bad2
_ce0_go:
        lda #18
        jmp emit_gfxcall
_ce0_bad2:
        jmp compile_env_bad

_ce0_done:
        clc
        rts
_ce0_bad:
        jmp compile_env_bad

; probe for the reserved screen arrays: A = first char (consumed);
; carry clear when the stream continues "@&(", with kind staged
; (0 = T@& screen code, 1 = C@& colour) -- position left after the char
scrarr_probe:
        ldx #0
        cmp #$54                ; T
        beq _sap_check
        inx
        cmp #$43                ; C
        bne _sap_no
_sap_check:
        stx scrarr_kind
        sta scrarr_chr          ; callers pass the first char in A and
        lda line_idx            ; expect it back untouched on a miss
        sta scrarr_save
        jsr line_at_end
        bcs _sap_restore
        jsr line_get
        cmp #$40                ; @
        bne _sap_restore
        jsr line_at_end
        bcs _sap_restore
        jsr line_get
        cmp #$26                ; &
        bne _sap_restore
        clc
        rts
_sap_restore:
        lda scrarr_save
        sta line_idx
        lda scrarr_chr          ; without this, A was the line index and
_sap_no:                        ; every T/C variable in expression
        sec                     ; context resolved to a column-keyed
        rts                     ; phantom slot (source.bas E=10 border)

; "(col, row)" -> emitted setters
compile_scrarr_index:
        jsr parse_open_paren
        bcs _csi_bad
        jsr compile_expression
        bcs _csi_bad
        jsr emit_tmpl
        .word out_jsr_tcsetc
        jsr parse_comma
        bcs _csi_bad
        jsr compile_expression
        bcs _csi_bad
        jsr emit_tmpl
        .word out_jsr_tcsetr
        jmp parse_close_paren
_csi_bad:
        sec
        rts

; assignment form: index, '=', value expression, store
compile_scrarr_store:
        jsr compile_scrarr_index
        bcs _css_bad
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _css_bad
        jsr line_get
        cmp #TOK_EQUAL
        bne _css_bad
        jsr compile_expression
        bcs _css_bad
        lda scrarr_kind
        bne _css_c
        lda #<out_jsr_tscrw
        ldy #>out_jsr_tscrw
        bra _css_emit
_css_c:
        lda #<out_jsr_cscrw
        ldy #>out_jsr_cscrw
_css_emit:
        jsr out_zstr
        rts
_css_bad:
        jmp compile_env_bad

; COLLISION type [, line]: with a line, arm the handler (compile-time
; line label, like TRAP); without, disarm that type
compile_collision:
        jsr compile_expression
        bcs _compile_col_bad
        jsr emit_tmpl
        .word out_jsr_colsett
        jsr parse_opt_comma
        bcs _compile_col_off
        jsr line_parse_number
        bcs _compile_col_bad
        jsr line_number_exists
        bcs _compile_col_bad
        jsr emit_tmpl
        .word out_lda_label_lo_imm
        jsr out_label_from_number
        jsr out_cr
        jsr emit_tmpl
        .word out_sta_coltmp
        jsr emit_tmpl
        .word out_lda_label_hi_imm
        jsr out_label_from_number
        jsr out_cr
        jsr emit_tmpl
        .word out_sta_coltmp1
        jsr emit_tmpl_done
        .word out_jsr_colarm
_compile_col_off:
        jsr emit_tmpl_done
        .word out_jsr_coloff
_compile_col_bad:
        jmp compile_env_bad

; single-byte disk verbs share shapes: A = command prefix index
compile_diskcmd:
        cmp #TOK_SCRATCH
        bne +
        lda #0
        bra compile_cmdname
+       cmp #TOK_HEADER
        bne +
        lda #3
        bra compile_cmdname
+       cmp #TOK_COLLECT
        bne +
        lda #5
        bra compile_cmdbare
+       cmp #TOK_COPY
        bne +
        lda #2
        bra compile_cmd2
+       lda #1                  ; RENAME

; CONCAT append TO target -> "C0:target=target,append" (the DOS combine
; form the ROM also emits); shares cmd2 apart from the tail template
compile_concat:
        lda #2
        ldx #<out_jsr_cmdcat
        ldy #>out_jsr_cmdcat
        bra cmd2entry

; two-name commands: first TO second -> prefix + second + '=' + first
compile_cmd2:
        ldx #<out_jsr_cmdstashout
        ldy #>out_jsr_cmdstashout
cmd2entry:
        stx cmd2_tail
        sty cmd2_tail+1
        pha
        jsr emit_string_temp_mark
        jsr compile_string_expression
        bcs compilecmd2bad
        jsr emit_tmpl
        .word out_jsr_cmdstash
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs compilecmd2bad
        jsr line_get
        cmp #TOK_TO
        bne compilecmd2bad
        jsr emit_string_temp_mark
        jsr compile_string_expression
        bcs compilecmd2bad
        pla
        jsr emit_lda_imm
        jsr emit_tmpl
        .word out_jsr_cmdpre
        jsr emit_tmpl
        .word out_jsr_cmdstr
        jsr emit_tmpl
        .word out_jsr_cmdeq
        lda cmd2_tail
        ldy cmd2_tail+1
        jsr out_zstr
        jsr emit_string_temp_release
        jsr emit_string_temp_release
        bra compile_cmd_go
compilecmd2bad:
        pla
        jmp compile_env_bad

; prefix + one name + go
compile_cmdname:
        pha
        jsr emit_string_temp_mark
        jsr compile_string_expression
        bcs compilecmd2bad
        pla
        jsr emit_lda_imm
        jsr emit_tmpl
        .word out_jsr_cmdpre
        jsr emit_tmpl
        .word out_jsr_cmdstr
        jsr emit_string_temp_release
        bra compile_cmd_go

; prefix only (COLLECT, DCLEAR)
compile_cmdbare:
        jsr emit_lda_imm
        jsr emit_tmpl
        .word out_jsr_cmdpre
compile_cmd_go:
        jsr emit_tmpl_done
        .word out_jsr_cmdgo

; emit the template whose address follows the jsr as an inline .word
; (2 bytes saved per call site; the far-pointer zp is borrowed briefly)
emit_tmpl:
        pla
        sta et_ret
        pla
        sta et_ret+1
        lda source_ptr
        pha
        lda source_ptr+1
        pha
        lda et_ret
        sta source_ptr
        lda et_ret+1
        sta source_ptr+1
        ldy #1
        lda (source_ptr),y
        sta et_tmpl
        iny
        lda (source_ptr),y
        sta et_tmpl+1
        pla
        sta source_ptr+1
        pla
        sta source_ptr
        clc
        lda et_ret
        adc #2
        tax
        lda et_ret+1
        adc #0
        pha
        phx
        lda et_tmpl
        ldy et_tmpl+1
        jmp out_zstr

et_ret:
        .byte 0,0
et_tmpl:
        .byte 0,0

; terminal variant: emit the inline-word template, then return success
; to the caller's caller (replaces lda/ldy/jmp out_zstr_ok tails)
emit_tmpl_done:
        pla
        sta et_ret
        pla
        sta et_ret+1
        lda source_ptr
        pha
        lda source_ptr+1
        pha
        lda et_ret
        sta source_ptr
        lda et_ret+1
        sta source_ptr+1
        ldy #1
        lda (source_ptr),y
        sta et_tmpl
        iny
        lda (source_ptr),y
        sta et_tmpl+1
        pla
        sta source_ptr+1
        pla
        sta source_ptr
        lda et_tmpl
        ldy et_tmpl+1
        jsr out_zstr
        clc
        rts

; shared "( expression )" parse; C set on any failure
parse_paren_expr:
        jsr parse_open_paren
        bcs +
        jsr compile_expression
        bcs +
        jmp parse_close_paren
+       rts

; shared tail: emit a template and return success
out_zstr_ok:
        jsr out_zstr
        clc
        rts

; emit "lda #$XX" from A
emit_lda_imm:
        pha
        jsr emit_tmpl
        .word out_lda_imm_hex
        pla
        jsr out_hex_byte
        jmp out_cr

; DOPEN# ch, name [,W] / APPEND# ch, name; A = default mode letter
compile_dopen:
        pha
        jsr compile_dopen_head
        bcs compiledopenbad
        jsr parse_opt_comma
        bcs compiledopenmode
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs compiledopenmode
        jsr line_get
        cmp #$57                ; W
        bne compiledopenbad
        pla
        lda #$57
        pha
compiledopenmode:
        pla
        jsr emit_lda_imm
        jsr emit_tmpl_done
        .word out_jsr_dopmode
compiledopenbad:
        pla
        jmp compile_env_bad

compile_dopen_append:
        pha
        jsr compile_dopen_head
        bcs compiledopenbad
        bra compiledopenmode

; shared: # channel , name -> fiosetlf + cmdpre 7 + cmdstr
compile_dopen_head:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _cdh_bad
        jsr line_get
        cmp #'#'
        bne _cdh_bad
        jsr compile_expression
        bcs _cdh_bad
        jsr emit_tmpl
        .word out_jsr_fiosetlf
        jsr parse_comma
        bcs _cdh_bad
        jsr emit_string_temp_mark
        jsr compile_string_expression
        bcs _cdh_bad
        lda #7
        jsr emit_lda_imm
        jsr emit_tmpl
        .word out_jsr_cmdpre
        jsr emit_tmpl
        .word out_jsr_cmdstr
        jsr emit_string_temp_release
        clc
        rts
_cdh_bad:
        sec
        rts

compile_dclose:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_dclose_bad
        jsr line_get
        cmp #'#'
        bne _compile_dclose_bad
        jsr compile_expression
        bcs _compile_dclose_bad
        jsr emit_tmpl
        .word out_jsr_fiosetlf
        jsr emit_tmpl_done
        .word out_jsr_dclosech
_compile_dclose_bad:
        jmp compile_env_bad

; BLOAD name, P address
compile_bload:
        jsr compile_bname
        bcs compilebloadbad
        jsr compile_pexpr
        bcs compilebloadbad
        jsr emit_tmpl
        .word out_jsr_bladdr
        jsr emit_tmpl_done
        .word out_jsr_bloadgo
compilebloadbad:
        jmp compile_env_bad

; BSAVE name, P start TO P end
compile_bsave:
        jsr compile_bname
        bcs compilebloadbad
        jsr compile_pexpr
        bcs compilebloadbad
        jsr emit_tmpl
        .word out_jsr_bladdr
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs compilebloadbad
        jsr line_get
        cmp #TOK_TO
        bne compilebloadbad
        jsr compile_pexpr_nocomma
        bcs compilebloadbad
        jsr emit_tmpl
        .word out_jsr_blend
        jsr emit_tmpl_done
        .word out_jsr_bsavego

; name into cmdbuf with the empty prefix
compile_bname:
        jsr emit_string_temp_mark
        jsr compile_string_expression
        bcs _cbn_bad
        lda #7
        jsr emit_lda_imm
        jsr emit_tmpl
        .word out_jsr_cmdpre
        jsr emit_tmpl
        .word out_jsr_cmdstr
        jsr emit_string_temp_release
        clc
        rts
_cbn_bad:
        sec
        rts

; ", P expr" (the letter prefix the disk syntax uses)
compile_pexpr:
        jsr parse_comma
        bcs cpxbad
compile_pexpr_nocomma:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs cpxbad
        jsr line_get
        cmp #$50                ; P
        bne cpxbad
        jmp compile_expression
cpxbad:
        sec
        rts

; MOUSE ON [, port [, sprite [, x, y]]] | MOUSE OFF
compile_mouse:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_mouse_bad
        jsr line_peek
        cmp #TOK_ON
        beq _compile_mouse_on
        cmp #TOK_EXT_FE
        bne _compile_mouse_bad
        jsr line_get
        jsr line_get            ; OFF is $fe $24
        cmp #$24
        bne _compile_mouse_bad
        jsr emit_tmpl_done
        .word out_jsr_mouseoff
_compile_mouse_on:
        jsr line_get
        jsr parse_opt_comma
        bcs _compile_mouse_go
        jsr compile_expression
        bcs _compile_mouse_bad
        jsr emit_tmpl
        .word out_jsr_mousetp
        jsr parse_opt_comma
        bcs _compile_mouse_go
        jsr compile_expression
        bcs _compile_mouse_bad
        jsr emit_tmpl
        .word out_jsr_mousets
        jsr parse_opt_comma
        bcs _compile_mouse_go
        jsr compile_expression
        bcs _compile_mouse_bad
        jsr emit_tmpl
        .word out_jsr_mousetx
        jsr parse_comma
        bcs _compile_mouse_bad
        jsr compile_expression
        bcs _compile_mouse_bad
        jsr emit_tmpl
        .word out_jsr_mousety
_compile_mouse_go:
        jsr emit_tmpl_done
        .word out_jsr_mouseon
_compile_mouse_bad:
        jmp compile_env_bad

; RMOUSE xvar, yvar, btnvar: snapshot then store into three numerics
compile_rmouse:
        jsr emit_tmpl
        .word out_jsr_rmousef
        jsr compile_input_target_numeric
        bcs _compile_rmouse_bad
        jsr emit_tmpl
        .word out_ld_mourx
        jsr emit_store_var
        jsr parse_comma
        bcs _compile_rmouse_bad
        jsr compile_input_target_numeric
        bcs _compile_rmouse_bad
        jsr emit_tmpl
        .word out_ld_moury
        jsr emit_store_var
        jsr parse_comma
        bcs _compile_rmouse_bad
        jsr compile_input_target_numeric
        bcs _compile_rmouse_bad
        jsr emit_tmpl
        .word out_ld_mourb
        jsr emit_store_var
        clc
        rts
_compile_rmouse_bad:
        jmp compile_env_bad

; CURSOR [col][,row]: position only -- the ROM's ON/OFF/style forms are
; not supported (they error). Omitted arguments keep the current value.
compile_cursor:
        jsr emit_tmpl
        .word out_jsr_curinit
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _cursor_go
        jsr line_peek
        cmp #$2c                ; leading comma: column omitted
        beq _cursor_row
        jsr compile_expression
        bcs _cursor_bad
        jsr emit_tmpl
        .word out_jsr_cursetc
_cursor_row:
        jsr parse_opt_comma
        bcs _cursor_go
        jsr compile_expression
        bcs _cursor_bad
        jsr emit_tmpl
        .word out_jsr_cursetr
_cursor_go:
        jsr emit_tmpl_done
        .word out_jsr_curgo
_cursor_bad:
        jmp compile_env_bad

; SETBIT addr, bit ($FE $2D $FE $4E) / CLRBIT ($9C $FE $4E): the
; shared argument compiler follows the BIT token pair
compile_setbit:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _cbit_bad
        jsr line_get
        cmp #TOK_EXT_FE
        bne _cbit_bad
        lda #<out_jsr_setbitgo
        ldy #>out_jsr_setbitgo
        bra compile_bitargs
_cbit_bad:
        jmp compile_env_bad

compile_bitargs:
        sta cdma_go
        sty cdma_go+1
        jsr line_at_end
        bcs _cbit_bad2
        jsr line_get
        cmp #$4e                ; the BIT token's second byte
        bne _cbit_bad2
        jsr compile_num_expression
        bcs _cbit_bad2
        lda expr_type
        beq _cbit_a16
        jsr emit_tmpl
        .word out_jsr_bitadr32
        bra _cbit_comma
_cbit_a16:
        jsr emit_tmpl
        .word out_jsr_bitadr16
_cbit_comma:
        jsr parse_comma
        bcs _cbit_bad2
        jsr compile_expression
        bcs _cbit_bad2
        lda cdma_go
        ldy cdma_go+1
        jmp out_zstr_ok
_cbit_bad2:
        jmp compile_env_bad

; SPRSAV source, destination: each side is a sprite number or a
; string variable (probed by type; anything else parses numerically)
compile_sprsav:
        jsr sprsav_probe_string
        bcc _csp_src_str
        jsr compile_expression
        bcs _csp_bad
        jsr emit_tmpl
        .word out_jsr_sprsava
        bra _csp_dest
_csp_src_str:
        jsr compile_string_factor
        bcs _csp_bad
        jsr emit_tmpl
        .word out_jsr_sprsavs
_csp_dest:
        jsr parse_comma
        bcs _csp_bad
        jsr sprsav_probe_string
        bcc _csp_dst_str
        jsr compile_expression
        bcs _csp_bad
        jsr emit_tmpl_done
        .word out_jsr_sprsavdn
_csp_dst_str:
        jsr line_get            ; first char of the target variable
        jsr parse_variable_with_first_char
        bcs _csp_bad
        jsr line_skip_spaces
        jsr line_at_end
        bcs +
        jsr line_peek
        cmp #'('                ; array cells unsupported as targets
        beq _csp_bad
+       jsr resolve_var
        bcs _csp_bad
        lda current_var_data_lo
        sta assign_var_data_lo
        lda current_var_data_hi
        sta assign_var_data_hi
        lda var_type
        sta assign_var_type
        jsr emit_tmpl
        .word out_jsr_sprsavstr
        jsr emit_store_var
        clc
        rts
_csp_bad:
        jmp compile_env_bad

; peek ahead: C clear if a string variable ($ suffix) starts here;
; the line position is restored either way
sprsav_probe_string:
        jsr line_skip_spaces
        lda line_idx
        sta sprsav_save
        jsr line_at_end
        bcs _spp_no
        jsr line_get
        jsr is_var_start
        bcs _spp_no
        jsr parse_variable_with_first_char
        bcs _spp_no
        lda var_type
        cmp #VAR_TYPE_STRING
        bne _spp_no
        lda sprsav_save
        sta line_idx
        clc
        rts
_spp_no:
        lda sprsav_save
        sta line_idx
        sec
        rts

; BOOT filename$ chain-loads a PRG (header address) and never returns;
; the SYS/bare/,B/,P/,D/,U forms are unsupported
compile_boot:
        jsr emit_string_temp_mark
        jsr compile_string_expression
        bcs +
        jsr emit_tmpl
        .word out_jsr_bootgo
        jmp emit_string_temp_release
+       jmp compile_env_bad

; BANK n / VSYNC raster: one expression, one runtime call
compile_bank:
        jsr compile_expression
        bcs +
        jsr emit_tmpl_done
        .word out_jsr_bankset
+       jmp compile_env_bad
compile_vsync:
        jsr compile_expression
        bcs +
        jsr emit_tmpl_done
        .word out_jsr_vsync
+       jmp compile_env_bad

; RREG a[,x[,y[,z[,s]]]]: store the captured post-SYS registers
compile_rreg:
        lda #0
        sta cdma_i
_crr_loop:
        jsr compile_input_target_numeric
        bcs _crr_bad
        lda cdma_i
        jsr emit_lda_imm
        jsr emit_tmpl
        .word out_jsr_rregn
        jsr emit_store_var
        inc cdma_i
        lda cdma_i
        cmp #5
        bcs _crr_done
        jsr parse_opt_comma
        bcs _crr_done
        bra _crr_loop
_crr_done:
        clc
        rts
_crr_bad:
        jmp compile_env_bad

; DMA / EDMA: stage up to seven arguments (16-bit results zero-extend,
; float results convert to 32-bit for 28-bit addresses), then trigger
compile_dma:
        lda #<out_jsr_dmago
        ldy #>out_jsr_dmago
        bra cdmacommon
compile_edma:
        lda #<out_jsr_edmago
        ldy #>out_jsr_edmago
cdmacommon:
        sta cdma_go
        sty cdma_go+1
        jsr emit_tmpl
        .word out_jsr_dmarst
        lda #0
        sta cdma_i
_cdma_loop:
        jsr compile_num_expression
        bcs _cdma_bad
        lda expr_type
        beq _cdma_a16
        jsr emit_tmpl
        .word out_jsr_dmaa32
        bra _cdma_next
_cdma_a16:
        jsr emit_tmpl
        .word out_jsr_dmaa16
_cdma_next:
        inc cdma_i
        lda cdma_i
        cmp #7
        bcs _cdma_go
        jsr parse_opt_comma
        bcs _cdma_go
        bra _cdma_loop
_cdma_go:
        lda cdma_go
        ldy cdma_go+1
        jmp out_zstr_ok
_cdma_bad:
        jmp compile_env_bad

; FGOTO / FGOSUB expr: computed jumps via the emitted line table
compile_fgoto:
        jsr compile_expression
        bcs +
        jsr emit_tmpl
        .word out_jsr_fgoto
        clc
        rts
+       jmp compile_env_bad
compile_fgosub:
        jsr compile_expression
        bcs +
        jsr emit_tmpl
        .word out_jsr_fgosub
        clc
        rts
+       jmp compile_env_bad

; DISK command$ sends a raw DOS command (empty prefix slot); bare
; DISK reads and prints the drive status. ,U units unsupported.
compile_diskstmt:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _cdisk_bare
        lda #7                  ; raw string, no DOS prefix
        jmp compile_cmdname
_cdisk_bare:
        jsr emit_tmpl_done
        .word out_jsr_dskst

; GRAPHIC CLR initialises the banked graphics system (fn 0)
compile_graphic:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _cgfx_bad
        jsr line_get
        cmp #$9c                ; the CLR token
        bne _cgfx_bad
        lda #0
        jsr emit_lda_imm
        jsr emit_tmpl_done
        .word out_jsr_gfxcall
_cgfx_bad:
        jmp compile_env_bad

; shared graphics argument staging: dmarst zeroes the slots (optional
; trailing args default to 0), then each expression lands in the next
; 4-byte slot; count is left in cdma_i
compile_gfxargs:
        jsr emit_tmpl
        .word out_jsr_dmarst
        lda #0
        sta cdma_i
_cga_loop:
        jsr compile_num_expression
        bcs _cga_bad
        lda expr_type
        beq _cga_a16
        jsr emit_tmpl
        .word out_jsr_dmaa32
        bra _cga_next
_cga_a16:
        jsr emit_tmpl
        .word out_jsr_dmaa16
_cga_next:
        inc cdma_i
        lda cdma_i
        cmp #9
        bcs _cga_done
        jsr parse_opt_comma
        bcs _cga_done
        bra _cga_loop
_cga_done:
        clc
        rts
_cga_bad:
        sec
        rts

; A = blob function index (args already staged)
emit_gfxcall:
        jsr emit_lda_imm
        jsr emit_tmpl_done
        .word out_jsr_gfxcall

; shared arg-count validator for the fixed-shape graphics statements:
; X = table index (min, max, blob fn per entry)
cgfx_stmt:
        stx cgfx_idx            ; compile_gfxargs clobbers X (the
        jsr compile_gfxargs     ; recurring X-across-parse bug class)
        bcs _cgs_bad
        ldx cgfx_idx
        lda cdma_i
        cmp cgfx_tab,x
        bcc _cgs_bad
        cmp cgfx_tab+1,x
        bcs _cgs_bad
        lda cgfx_tab+2,x
        jmp emit_gfxcall
_cgs_bad:
        jmp compile_env_bad
cgfx_idx:
        .byte 0
def_count:
        .byte 0
cfn_n1:
        .byte 0
cfn_n2:
        .byte 0
cfn_ref_lo:
        .byte 0
cfn_ref_hi:
        .byte 0
cdef_idx:
        .byte 0
cdef_skip_lo:
        .byte 0
cdef_skip_hi:
        .byte 0
cdef_parm_lo:
        .byte 0
cdef_parm_hi:
        .byte 0
cgfx_tab:
        .byte 4, 5+1, 3         ; 0: BOX
        .byte 3, 6+1, 4         ; 3: CIRCLE (arcs: +start,stop)
        .byte 4, 7+1, 5         ; 6: ELLIPSE (arcs: +start,stop)
        .byte 2, 4+1, 6         ; 9: PAINT
        .byte 5, 9+1, 13        ; 12: POLYGON
        .byte 4, 4+1, 20        ; 15: GCOPY
        .byte 2, 2+1, 21        ; 18: PASTE
        .byte 4, 4+1, 23        ; 21: CUT
        .byte 2, 2+1, 9         ; 24: DOT (single-pixel plot)

; LINE x,y draws a pixel; each further pair extends the path with a
; segment from the previous point (gfxlnext shifts the staged end
; coordinates into the start slots between calls)
compile_gline:
        jsr line_skip_spaces    ; LINE INPUT / LINE INPUT# ride the
        jsr line_at_end         ; LINE token ($e5 $85 / $e5 $84)
        bcs _cgl_draw
        jsr line_peek
        cmp #$85
        bne +
        jmp compile_line_input
+       cmp #$84
        bne _cgl_draw
        jmp compile_line_input_hash
_cgl_draw:
        jsr emit_tmpl
        .word out_jsr_dmarst
        jsr cglcoord            ; x0
        bcs _cgl_bad
        jsr parse_comma
        bcs _cgl_bad
        jsr cglcoord            ; y0
        bcs _cgl_bad
        jsr parse_opt_comma
        bcs _cgl_plot           ; one pair: a pixel
_cgl_seg:
        jsr cglcoord            ; xn
        bcs _cgl_bad
        jsr parse_comma
        bcs _cgl_bad
        jsr cglcoord            ; yn
        bcs _cgl_bad
        lda #2                  ; draw the segment
        jsr emit_lda_imm
        jsr emit_tmpl
        .word out_jsr_gfxcall
        jsr parse_opt_comma
        bcs _cgl_done
        jsr emit_tmpl           ; this end = next start
        .word out_jsr_gfxlnext
        bra _cgl_seg
_cgl_done:
        clc
        rts
_cgl_plot:
        lda #9
        jmp emit_gfxcall
_cgl_bad:
        jmp compile_env_bad

; stage one numeric expression into the next DMA arg slot (int or
; float); shared by LINE and PIXEL()
cglcoord:
        jsr compile_num_expression
        bcs _cglc_fail
        lda expr_type
        beq _cglc_a16
        jsr emit_tmpl
        .word out_jsr_dmaa32
        clc
        rts
_cglc_a16:
        jsr emit_tmpl
        .word out_jsr_dmaa16
        clc
        rts
_cglc_fail:
        sec
        rts

; SCNCLR bare clears the text screen; SCNCLR colour fills the
; graphics bitmap
compile_scnclr:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _cscn_text
        jsr compile_gfxargs
        bcs _cscn_bad
        lda cdma_i
        cmp #1
        bne _cscn_bad
        lda #12
        jmp emit_gfxcall
_cscn_text:
        lda #$93
        jsr emit_lda_imm
        jsr emit_tmpl_done
        .word out_jsr_chout
_cscn_bad:
        jmp compile_env_bad

; BOX x0,y0,x2,y2[,solid] (4-corner form unsupported), CIRCLE
; xc,yc,r[,flags] (no arcs), ELLIPSE xc,yc,xr,yr[,flags] (no arcs),
; PAINT x,y[,mode[,border]] (mode-0 semantics)
compile_box:
        jsr compile_gfxargs
        bcs _cbox_bad
        lda cdma_i
        cmp #4
        beq _cbox_two
        cmp #5
        beq _cbox_two
        cmp #8
        beq _cbox_four
        cmp #9
        bne _cbox_bad
_cbox_four:
        lda #19
        jmp emit_gfxcall
_cbox_two:
        lda #3
        jmp emit_gfxcall
_cbox_bad:
        jmp compile_env_bad
compile_box_unused:
        ldx #0
        bra cgfx_stmt_go
compile_circle:
        ldx #3
        bra cgfx_stmt_go
compile_ellipse:
        ldx #6
        bra cgfx_stmt_go
compile_paint:
        ldx #9
        bra cgfx_stmt_go
compile_gcopy:
        ldx #15
        bra cgfx_stmt_go
compile_paste:
        ldx #18
        bra cgfx_stmt_go
compile_cut:
        ldx #21
        bra cgfx_stmt_go
compile_dot:
        ldx #24
cgfx_stmt_go:
        jmp cgfx_stmt

; VIEWPORT DEF x,y,w,h (clip region) / VIEWPORT CLR (fill it with the
; current pen)
compile_viewport:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _cvp_bad
        jsr line_get
        cmp #$96                ; DEF
        beq _cvp_def
        cmp #$9c                ; CLR
        bne _cvp_bad
        jsr emit_tmpl           ; CLR takes no arguments
        .word out_jsr_dmarst
        lda #25
        jmp emit_gfxcall
_cvp_def:
        jsr compile_gfxargs
        bcs _cvp_bad
        lda cdma_i
        cmp #4
        bne _cvp_bad
        lda #24
        jmp emit_gfxcall
_cvp_bad:
        jmp compile_env_bad

; PEN [pen,] colour -- resident: just stores the colour
compile_pen:
        jsr compile_gfxargs
        bcs _cpen_bad
        lda cdma_i
        beq _cpen_bad
        cmp #2+1
        bcs _cpen_bad
        jsr emit_tmpl_done
        .word out_jsr_penset
_cpen_bad:
        jmp compile_env_bad

; POLYGON x,y,xrad,yrad,sides[,drawsides,subtend,angle,solid]
compile_polygon:
        ldx #12
        jmp cgfx_stmt

; PALETTE screen,c,r,g,b or PALETTE COLOR c,r,g,b (RESTORE unsupported)
compile_palette:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _cpal_bad
        jsr line_peek
        cmp #TOK_COLOR
        bne _cpal_scr
        jsr line_get
        jsr compile_gfxargs
        bcs _cpal_bad
        lda cdma_i
        cmp #4
        bne _cpal_bad
        lda #11
        jmp emit_gfxcall
_cpal_scr:
        jsr compile_gfxargs
        bcs _cpal_bad
        lda cdma_i
        cmp #5
        bne _cpal_bad
        lda #7
        jmp emit_gfxcall
_cpal_bad:
        jmp compile_env_bad

; SCREEN [screen,]w,h,d / CLR c / DEF s,wf,hf,d / SET d,v / OPEN [s] /
; CLOSE [s]. Every screen renders 320x200x256 (VIC-IV FCM, not
; VIC-III bitplanes); screens 0-3 are attic-backed, bank 4 shows the
; viewed one.
compile_screen:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _cscr_bad
        jsr line_peek
        cmp #TOK_CLOSE
        beq _cscr_close_kw
        cmp #$9c                ; CLR: same as SCNCLR colour
        beq _cscr_clr
        cmp #$96                ; DEF
        beq _cscr_def
        cmp #TOK_OPEN           ; OPEN
        beq _cscr_sopen
        cmp #TOK_EXT_FE         ; SET arrives as $fe $2d
        beq _cscr_set
        jsr compile_gfxargs     ; numeric: [s,]w,h,d
        bcs _cscr_bad
        lda cdma_i
        cmp #3
        beq _cscr_simple3
        cmp #4
        bne _cscr_bad
        lda #17                 ; s,w,h,d
        jmp emit_gfxcall
_cscr_simple3:
        lda #10                 ; w,h,d (screen 0)
        jmp emit_gfxcall
_cscr_close_kw:
        jsr line_get
        jsr emit_tmpl           ; bare CLOSE means screen 0 -- without
        .word out_jsr_dmarst    ; this the staged args are stale
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _cscr_close
        jsr cglcoord            ; one screen-number expression
        bcs _cscr_bad
_cscr_close:
        lda #1
        jmp emit_gfxcall
_cscr_clr:
        jsr line_get
        jsr compile_gfxargs
        bcs _cscr_bad
        lda cdma_i
        cmp #1
        bne _cscr_bad
        lda #12
        jmp emit_gfxcall
_cscr_def:
        jsr line_get
        jsr compile_gfxargs
        bcs _cscr_bad
        lda cdma_i
        cmp #4
        bne _cscr_bad
        lda #16
        jmp emit_gfxcall
_cscr_sopen:
        jsr line_get
        jsr emit_tmpl
        .word out_jsr_dmarst
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _cscr_sopen_go      ; bare OPEN: screen 0
        jsr cglcoord            ; the screen number
        bcs _cscr_bad
_cscr_sopen_go:
        lda #15
        jsr emit_lda_imm
        jsr emit_tmpl
        .word out_jsr_gfxcall
        jsr parse_opt_comma     ; optional result variable: our OPEN
        bcs _cscr_sopen_done    ; cannot fail, so it reads 0
        jsr compile_input_target_numeric
        bcs _cscr_bad
        lda #0
        sta number_lo
        sta number_hi
        jsr emit_load_number
        jsr emit_store_var
_cscr_sopen_done:
        clc
        rts
_cscr_set:
        jsr line_get            ; the $fe prefix
        jsr line_get
        cmp #$2d                ; SET
        bne _cscr_bad
        jsr compile_gfxargs
        bcs _cscr_bad
        lda cdma_i
        cmp #2
        bne _cscr_bad
        lda #14
        jmp emit_gfxcall
_cscr_bad:
        jmp compile_env_bad

; ---- DEF FN name(param) = expression ----
; The body compiles in place as a subroutine bracketed by a jump-over:
; entry stashes the (float) parameter variable, stores the argument
; (arriving in FAC), evaluates the body, restores the variable, and
; returns with the result in FAC. FN calls must appear textually after
; their DEF (matching interpreter execution order in practice); the
; definition is static -- a re-DEF at runtime is not supported.
; Body labels use LBL_IF ids 368+ (the IF counter grows from 0; they
; can only clash in programs with ~70+ IF statements).

; parse an FN name into cfn_n1/cfn_n2 (1-2 chars)
parse_fn_name:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _pfn_bad
        jsr line_get
        jsr is_var_start
        bcs _pfn_bad
        sta cfn_n1
        lda #0
        sta cfn_n2
        jsr line_at_end
        bcs _pfn_ok
        jsr line_peek
        jsr is_var_tail
        bcs _pfn_ok
        jsr line_get
        sta cfn_n2
_pfn_ok:
        clc
        rts
_pfn_bad:
        sec
        rts

; find cfn_n1/n2 in the DEF table -> X, C clear; C set when absent
fn_lookup:
        ldx #0
_fnl_scan:
        cpx def_count
        beq _fnl_miss
        lda def_n1,x
        cmp cfn_n1
        bne _fnl_next
        lda def_n2,x
        cmp cfn_n2
        beq _fnl_hit
_fnl_next:
        inx
        bra _fnl_scan
_fnl_hit:
        clc
        rts
_fnl_miss:
        sec
        rts

; cfn_ref = the body label id for def index in A (368 + index)
fn_set_ref:
        clc
        adc #$70
        sta cfn_ref_lo
        lda #$01
        sta cfn_ref_hi
        rts

; label reference/definition: LBL_IF id in cfn_ref (text: fnlabXXXX)
out_fn_ref:
        ldx backend_mode
        beq +
        lda #LBL_IF
        ldx cfn_ref_lo
        ldy cfn_ref_hi
        jmp bin_label
+       lda #<out_fnlab_prefix
        ldy #>out_fnlab_prefix
        jsr out_zstr
        lda cfn_ref_hi
        jsr out_hex_byte
        lda cfn_ref_lo
        jsr out_hex_byte
        rts

; emit "fnlabXXXX:" on its own line (a definition site)
emit_fn_label_line:
        jsr out_fn_ref
        lda #':'
        jsr out_char
        jmp out_cr

compile_def:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _cdef_bad
        jsr line_get
        cmp #$a5                ; FN
        bne _cdef_bad
        jsr parse_fn_name
        bcs _cdef_bad
        jsr fn_lookup
        bcc _cdef_have          ; pass 2 finds the pass-1 entry
        ldx def_count
        cpx #DEF_MAX
        bcs _cdef_bad
        lda cfn_n1
        sta def_n1,x
        lda cfn_n2
        sta def_n2,x
        lda var_heap_next_hi    ; a 5-byte heap stash for the shadowed
        cmp #>VAR_HEAP_LIMIT    ; parameter (allocated once: passes
        bcs _cdef_bad           ; dedupe by name)
        lda var_heap_next_lo
        sta def_stash_lo,x
        lda var_heap_next_hi
        sta def_stash_hi,x
        clc
        lda var_heap_next_lo
        adc #5
        sta var_heap_next_lo
        bcc +
        inc var_heap_next_hi
+       inc def_count
_cdef_have:
        stx cdef_idx
        jsr line_skip_spaces
        jsr line_at_end
        bcs _cdef_bad
        jsr line_get
        cmp #'('
        bne _cdef_bad
        jsr line_skip_spaces
        jsr line_at_end
        bcs _cdef_bad
        jsr line_get
        jsr parse_variable_with_first_char
        bcs _cdef_bad
        lda var_type
        cmp #VAR_TYPE_FLOAT
        bne _cdef_bad
        jsr resolve_var         ; parse only names the variable; this
        bcs _cdef_bad           ; sets current_var_data to its slot
        ldx cdef_idx
        lda current_var_data_lo
        sta def_parm_lo,x
        sta cdef_parm_lo
        lda current_var_data_hi
        sta def_parm_hi,x
        sta cdef_parm_hi
        jsr line_skip_spaces
        jsr line_at_end
        bcs _cdef_bad
        jsr line_get
        cmp #')'
        bne _cdef_bad
        jsr line_skip_spaces
        jsr line_at_end
        bcs _cdef_bad
        jsr line_get
        cmp #TOK_EQUAL
        beq _cdef_body
        cmp #'='
        bne _cdef_bad
_cdef_body:
        lda if_label_next_lo    ; the jump-over label comes from the
        sta cdef_skip_lo        ; shared counter (monotonic, so it
        lda if_label_next_hi    ; never collides with an IF's ids)
        sta cdef_skip_hi
        jsr inc_if_label_next
        jsr emit_tmpl           ; jmp past the body
        .word out_jmp_label
        lda cdef_skip_lo
        sta cfn_ref_lo
        lda cdef_skip_hi
        sta cfn_ref_hi
        jsr out_fn_ref
        jsr out_cr
        lda cdef_idx            ; the body entry label
        jsr fn_set_ref
        jsr emit_fn_label_line
        ldx cdef_idx            ; entry: stash the parameter variable
        lda def_stash_lo,x
        sta number_lo
        lda def_stash_hi,x
        sta number_hi
        jsr emit_load_number
        jsr emit_set_varptr_current
        jsr emit_tmpl
        .word out_jsr_fnsave
        jsr emit_set_varptr_current
        jsr emit_tmpl           ; the argument arrives in FAC
        .word out_jsr_fstorevar
        jsr compile_num_expression
        bcs _cdef_bad
        lda expr_type
        bne _cdef_flt
        jsr emit_tmpl           ; int body: result still lands in FAC
        .word out_jsr_float16
_cdef_flt:
        lda cdef_parm_lo        ; restore the shadowed variable
        sta current_var_data_lo
        lda cdef_parm_hi
        sta current_var_data_hi
        ldx cdef_idx
        lda def_stash_lo,x
        sta number_lo
        lda def_stash_hi,x
        sta number_hi
        jsr emit_load_number
        jsr emit_set_varptr_current
        jsr emit_tmpl
        .word out_jsr_fnrest
        jsr emit_tmpl
        .word out_rts
        lda cdef_skip_lo        ; land here at runtime
        sta cfn_ref_lo
        lda cdef_skip_hi
        sta cfn_ref_hi
        jsr emit_fn_label_line
        clc
        rts
_cdef_bad:
        lda #<msg_error_bad_def
        ldy #>msg_error_bad_def
        jsr fatal_statement_error
        rts

; KEY number, string (the ON/OFF/LOAD/SAVE and bare forms are not
; supported -- they only matter interactively)
compile_key:
        jsr compile_expression
        bcs _ckey_bad
        jsr emit_tmpl
        .word out_jsr_keysetn
        jsr parse_comma
        bcs _ckey_bad
        jsr emit_string_temp_mark
        jsr compile_string_expression
        bcs _ckey_bad
        jsr emit_tmpl
        .word out_jsr_keysetgo
        jmp emit_string_temp_release
_ckey_bad:
        jmp compile_env_bad

; WINDOW left, top, right, bottom [, clear]
compile_window:
        jsr emit_tmpl
        .word out_jsr_winrst
        ldx #0
_cw_loop:
        phx
        jsr compile_expression
        bcs _cw_badx
        jsr emit_tmpl
        .word out_jsr_winarg
        plx
        inx
        cpx #4
        bcc _cw_comma           ; args 1-3: comma required
        bne _cw_go              ; arg 5 taken: done
        phx                     ; the parsers clobber X (the arg count)
        jsr parse_opt_comma     ; after arg 4 the clear flag is optional
        plx
        bcs _cw_go
        bra _cw_loop
_cw_comma:
        phx
        jsr parse_comma
        plx
        bcs _cw_bad
        bra _cw_loop
_cw_go:
        jsr emit_tmpl_done
        .word out_jsr_wingo
_cw_badx:
        plx
_cw_bad:
        jmp compile_env_bad

; RCURSOR colvar, rowvar
compile_rcursor:
        jsr compile_input_target_numeric
        bcs _rcursor_bad
        jsr emit_tmpl
        .word out_jsr_curcolf
        jsr emit_store_var
        jsr parse_comma
        bcs _rcursor_bad
        jsr compile_input_target_numeric
        bcs _rcursor_bad
        jsr emit_tmpl
        .word out_jsr_currowf
        jsr emit_store_var
        clc
        rts
_rcursor_bad:
        jmp compile_env_bad

; parse a scalar numeric variable target into assign_var_* (RMOUSE)
compile_input_target_numeric:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _citn_bad
        jsr line_get
        jsr is_var_start
        bcs _citn_bad
        jsr parse_variable_with_first_char
        bcs _citn_bad
        lda var_type
        jsr var_type_is_numeric
        bcs _citn_bad
        pha
        jsr resolve_var
        bcs _citn_badp
        lda current_var_data_lo
        sta assign_var_data_lo
        lda current_var_data_hi
        sta assign_var_data_hi
        pla
        sta assign_var_type
        clc
        rts
_citn_badp:
        pla
_citn_bad:
        sec
        rts

; SLEEP seconds: float expression, frame-granular in the runtime
compile_sleep:
        jsr compile_num_expression
        bcs compile_env_bad
        lda expr_type
        bne _compile_sleep_f
        jsr emit_tmpl
        .word out_jsr_float16
_compile_sleep_f:
        jsr emit_tmpl_done
        .word out_jsr_sleepf

; WAIT address, andmask [, xormask]
compile_wait:
        jsr compile_expression
        bcs compile_env_bad
        jsr emit_tmpl
        .word out_jsr_waitseta
        jsr parse_comma
        bcs compile_env_bad
        jsr compile_expression
        bcs compile_env_bad
        jsr emit_tmpl
        .word out_jsr_waitsetm
        jsr parse_opt_comma
        bcs _compile_wait_go
        jsr compile_expression
        bcs compile_env_bad
        jsr emit_tmpl
        .word out_jsr_waitsetx
_compile_wait_go:
        jsr emit_tmpl_done
        .word out_jsr_waitgo

compile_tempo:
        jsr compile_expression
        bcs compile_env_bad
        jsr emit_tmpl_done
        .word out_jsr_tempof

; ENVELOPE n [, attack, decay, sustain, release, waveform, pw] --
; each optional argument patches the slot immediately
compile_envelope:
        jsr compile_expression
        bcs compile_env_bad
        jsr emit_tmpl
        .word out_jsr_envsetn
        ldx #0
_compile_env_loop:
        phx
        jsr parse_opt_comma
        bcs _compile_env_done
        jsr compile_expression
        bcs _compile_env_badx
        plx
        phx
        lda envsetterlo,x
        ldy envsetterhi,x
        jsr out_zstr
        plx
        inx
        cpx #6
        bcc _compile_env_loop
        clc
        rts
_compile_env_done:
        plx
        clc
        rts
_compile_env_badx:
        plx
compile_env_bad:
        lda #<msg_error_bad_play
        ldy #>msg_error_bad_play
        jsr fatal_statement_error
        rts

envsetterlo:
        .byte <out_jsr_envseta, <out_jsr_envsetd, <out_jsr_envsetss
        .byte <out_jsr_envsetr, <out_jsr_envsetw, <out_jsr_envsetpw
envsetterhi:
        .byte >out_jsr_envseta, >out_jsr_envsetd, >out_jsr_envsetss
        .byte >out_jsr_envsetr, >out_jsr_envsetw, >out_jsr_envsetpw

; MOVSPR num, position: absolute x,y; +/- relative; angle#speed;
; and start TO end, speed (IRQ-tick interpolation)
compile_movspr:
        jsr compile_expression
        bcs compile_sprite_bad
        jsr emit_tmpl
        .word out_jsr_sprsetn
        jsr parse_comma
        bcs compile_sprite_bad
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs compile_sprite_bad
        jsr line_peek
        cmp #TOK_PLUS
        beq _movspr_relx
        cmp #TOK_MINUS
        beq _movspr_relx
        jsr compile_expression
        bcs compile_sprite_bad
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs compile_sprite_bad
        jsr line_peek
        cmp #'#'
        beq _movspr_angle
        jsr emit_tmpl
        .word out_jsr_sprsetx
        bra _movspr_y
_movspr_relx:
        cmp #TOK_PLUS           ; the + is the relative marker, not a
        bne +                   ; unary operator; - compiles as unary
        jsr line_get
+       jsr compile_expression
        bcs compile_sprite_bad
        jsr emit_tmpl
        .word out_jsr_sprsetxr
_movspr_y:
        jsr parse_comma
        bcs compile_sprite_bad
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs compile_sprite_bad
        jsr line_peek
        cmp #TOK_PLUS
        beq _movspr_rely
        cmp #TOK_MINUS
        beq _movspr_rely
        jsr compile_expression
        bcs compile_sprite_bad
        bra _movspr_place
_movspr_rely:
        cmp #TOK_PLUS
        bne +
        jsr line_get
+       jsr compile_expression
        bcs compile_sprite_bad
        jsr emit_tmpl
        .word out_jsr_sprsetyr
_movspr_place:
        jsr emit_tmpl
        .word out_jsr_movsprgo
        ; optional: TO endx, endy, speed
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _movspr_done
        jsr line_peek
        cmp #TOK_TO
        bne _movspr_done
        jsr line_get
        jsr compile_expression
        bcs compile_sprite_bad
        jsr emit_tmpl
        .word out_jsr_sprsettx
        jsr parse_comma
        bcs compile_sprite_bad
        jsr compile_expression
        bcs compile_sprite_bad
        jsr emit_tmpl
        .word out_jsr_sprsetty
        jsr parse_comma
        bcs compile_sprite_bad
        jsr compile_expression
        bcs compile_sprite_bad
        jsr emit_tmpl
        .word out_jsr_sprgoto
_movspr_done:
        clc
        rts
_movspr_angle:
        jsr emit_tmpl   ; the angle stages through spr_x
        .word out_jsr_sprsetx
        jsr line_get            ; consume #
        jsr compile_expression
        bcs compile_sprite_bad
        jsr emit_tmpl_done
        .word out_jsr_sprgoang

compile_sprite_bad:
        lda #<msg_error_bad_sprite
        ldy #>msg_error_bad_sprite
        jsr fatal_statement_error
        rts

compile_sprcolor:
        jsr compile_expression
        bcs compile_sprite_bad
        jsr emit_tmpl
        .word out_jsr_sprmc1
        jsr parse_comma
        bcs compile_sprite_bad
        jsr compile_expression
        bcs compile_sprite_bad
        jsr emit_tmpl_done
        .word out_jsr_sprmc2

; SPRITE num [{, switch, colour, prio, expx, expy, mode}] -- empty slots
; (adjacent commas) leave that attribute unchanged, like the interpreter
compile_sprite:
        jsr compile_expression
        bcs compile_sprite_bad
        jsr emit_tmpl
        .word out_jsr_sprsetn
        jsr sprite_slot
        bcs _compile_sprite_done
        bne _compile_sprite_1
        jsr emit_tmpl
        .word out_jsr_sprswitch
_compile_sprite_1:
        jsr sprite_slot
        bcs _compile_sprite_done
        bne _compile_sprite_2
        jsr emit_tmpl
        .word out_jsr_sprsetfg
_compile_sprite_2:
        jsr sprite_slot
        bcs _compile_sprite_done
        bne _compile_sprite_3
        jsr emit_tmpl
        .word out_jsr_sprsetprio
_compile_sprite_3:
        jsr sprite_slot
        bcs _compile_sprite_done
        bne _compile_sprite_4
        jsr emit_tmpl
        .word out_jsr_sprsetexpx
_compile_sprite_4:
        jsr sprite_slot
        bcs _compile_sprite_done
        bne _compile_sprite_5
        jsr emit_tmpl
        .word out_jsr_sprsetexpy
_compile_sprite_5:
        jsr sprite_slot
        bcs _compile_sprite_done
        bne _compile_sprite_done
        jsr emit_tmpl
        .word out_jsr_sprsetmode
_compile_sprite_done:
        clc
        rts

; parse one optional SPRITE slot: carry set = no more arguments;
; carry clear + Z set = expression compiled (emit the setter);
; carry clear + Z clear = empty slot, attribute untouched
sprite_slot:
        jsr parse_opt_comma
        bcs _sprite_slot_end
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _sprite_slot_end
        jsr line_peek
        cmp #','
        beq _sprite_slot_empty
        jsr compile_expression
        bcs _sprite_slot_bad
        lda #0
        clc
        rts
_sprite_slot_empty:
        lda #1
        clc
        rts
_sprite_slot_end:
        sec
        rts
_sprite_slot_bad:
        pla
        pla
        jmp compile_sprite_bad

; SOUND voice, freq, dur [, dir [, min [, sweep [, wave [, pulse]]]]]
compile_sound:
        jsr compile_expression
        bcs compile_sound_bad
        jsr emit_tmpl
        .word out_jsr_sndsetv
        jsr parse_comma
        bcs compile_sound_bad
        jsr compile_expression
        bcs compile_sound_bad
        jsr emit_tmpl
        .word out_jsr_sndsetf
        jsr parse_comma
        bcs compile_sound_bad
        jsr compile_expression
        bcs compile_sound_bad
        jsr emit_tmpl
        .word out_jsr_sndsetd
        jsr parse_opt_comma
        bcs _compile_sound_go
        jsr compile_expression
        bcs compile_sound_bad
        jsr emit_tmpl
        .word out_jsr_sndsetdr
        jsr parse_opt_comma
        bcs _compile_sound_go
        jsr compile_expression
        bcs compile_sound_bad
        jsr emit_tmpl
        .word out_jsr_sndsetm
        jsr parse_opt_comma
        bcs _compile_sound_go
        jsr compile_expression
        bcs compile_sound_bad
        jsr emit_tmpl
        .word out_jsr_sndsets
        jsr parse_opt_comma
        bcs _compile_sound_go
        jsr compile_expression
        bcs compile_sound_bad
        jsr emit_tmpl
        .word out_jsr_sndsetw
        jsr parse_opt_comma
        bcs _compile_sound_go
        jsr compile_expression
        bcs compile_sound_bad
        jsr emit_tmpl
        .word out_jsr_sndsetp
_compile_sound_go:
        jsr emit_tmpl_done
        .word out_jsr_sndgo

compile_sound_bad:
        lda #<msg_error_bad_sound
        ldy #>msg_error_bad_sound
        jsr fatal_statement_error
        rts

compile_vol:
        jsr compile_expression
        bcs compile_sound_bad
        jsr emit_tmpl_done
        .word out_jsr_volsnd

compile_trap_bad:
        lda #<msg_error_bad_trap
        ldy #>msg_error_bad_trap
        jsr fatal_statement_error
        rts

compile_resume:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs compile_trap_bad
        jsr line_parse_number
        bcs compile_trap_bad
        jsr line_number_exists
        bcs compile_trap_bad
        jsr emit_tmpl
        .word out_jsr_trapresume
        jsr emit_tmpl
        .word out_jmp_label
        jsr out_label_from_number
        jsr out_cr
        rts

compile_open:
        jsr emit_tmpl
        .word out_jsr_fiodefaults
        jsr compile_expression
        bcs _compile_open_bad
        jsr emit_tmpl
        .word out_jsr_fiosetlf
        jsr parse_opt_comma
        bcs _compile_open_done
        jsr compile_expression
        bcs _compile_open_bad
        jsr emit_tmpl
        .word out_jsr_fiosetdev
        jsr parse_opt_comma
        bcs _compile_open_done
        jsr compile_expression
        bcs _compile_open_bad
        jsr emit_tmpl
        .word out_jsr_fiosetsa
        jsr parse_opt_comma
        bcs _compile_open_done
        jsr emit_string_temp_mark
        jsr compile_string_expression
        bcs _compile_open_bad
        jsr emit_tmpl
        .word out_jsr_fiosetname
        jsr emit_tmpl
        .word out_jsr_fopen
        jsr emit_string_temp_release
        clc
        rts

_compile_open_done:
        jsr emit_tmpl_done
        .word out_jsr_fopen

_compile_open_bad:
        lda #<msg_error_bad_open
        ldy #>msg_error_bad_open
        jsr fatal_statement_error
        rts

; consume a comma between OPEN arguments; carry set at statement end
parse_opt_comma:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs parse_opt_comma_end
        jsr line_get
        cmp #','
        bne parse_opt_comma_end
        clc
        rts
parse_opt_comma_end:
        sec
        rts

compile_close:
        jsr compile_expression
        bcs _compile_close_bad
        jsr emit_tmpl_done
        .word out_jsr_fclose

_compile_close_bad:
        lda #<msg_error_bad_open
        ldy #>msg_error_bad_open
        jsr fatal_statement_error
        rts

compile_print_hash:
        jsr compile_expression
        bcs _compile_print_hash_bad
        jsr emit_tmpl
        .word out_jsr_fiochkout
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_print_hash_items
        jsr line_peek
        cmp #','
        bne _compile_print_hash_items
        jsr line_get
_compile_print_hash_items:
        jsr compile_print
        jsr emit_tmpl_done
        .word out_jsr_fiodone

_compile_print_hash_bad:
        lda #<msg_error_bad_open
        ldy #>msg_error_bad_open
        jsr fatal_statement_error
        rts

compile_input_hash:
        jsr compile_expression
        bcs _compile_input_hash_bad
        jsr emit_tmpl
        .word out_jsr_fiochkin
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_input_hash_bad
        jsr line_get
        cmp #','
        bne _compile_input_hash_bad
        lda #1
        sta io_from_file
        jsr emit_input_line
        jsr _compile_input_hash_targets
        lda #0
        sta io_from_file
        jsr emit_tmpl_done
        .word out_jsr_fiodone

_compile_input_hash_targets:
        jsr compile_input_target
        bcs _compile_input_hash_tbad
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_input_hash_tdone
        jsr line_get
        cmp #','
        beq _compile_input_hash_targets
_compile_input_hash_tbad:
        lda #<msg_error_bad_input
        ldy #>msg_error_bad_input
        jsr fatal_statement_error
_compile_input_hash_tdone:
        rts

_compile_input_hash_bad:
        lda #<msg_error_bad_input
        ldy #>msg_error_bad_input
        jsr fatal_statement_error
        rts

compile_input:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_input_bad
        jsr line_peek
        cmp #'"'
        bne _compile_input_emit_line

        jsr line_get                         ; opening quote
        jsr add_string_literal
        bcs _compile_input_bad
        jsr emit_print_string_current
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_input_bad
        jsr line_get
        cmp #';'
        beq _compile_input_emit_line
        cmp #','
        bne _compile_input_bad

_compile_input_emit_line:
        jsr emit_input_line

_compile_input_target_loop:
        jsr compile_input_target
        bcs _compile_input_bad
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_input_done
        jsr line_get
        cmp #','
        beq _compile_input_target_loop

_compile_input_bad:
        lda #<msg_error_bad_input
        ldy #>msg_error_bad_input
        jsr fatal_statement_error

_compile_input_done:
        rts

; LINE INPUT ["prompt" <,|;>] v$ [, v$ ...] -- each variable takes a
; whole keyboard line verbatim. A comma after the prompt suppresses
; the question mark, a semicolon keeps it; every further variable
; prompts "??" like the ROM. Prompts are literals (as with INPUT).
compile_line_input:
        jsr line_get            ; consume the INPUT token
        lda #1
        sta input_raw_mode
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _cli_bad
        jsr line_peek
        cmp #'"'
        bne _cli_first_q
        jsr line_get            ; opening quote
        jsr add_string_literal
        bcs _cli_bad
        jsr emit_print_string_current
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _cli_bad
        jsr line_get
        cmp #','
        beq _cli_first_nq
        cmp #';'
        beq _cli_first_q
        bra _cli_bad
_cli_first_nq:
        jsr emit_tmpl
        .word out_jsr_inputlinenq
        bra _cli_target
_cli_first_q:
        jsr emit_tmpl
        .word out_jsr_inputline
_cli_target:
        jsr compile_input_target
        bcs _cli_bad
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _cli_done
        jsr line_get
        cmp #','
        bne _cli_bad
        jsr emit_tmpl
        .word out_jsr_inputline2q
        bra _cli_target
_cli_bad:
        lda #0
        sta input_raw_mode
        lda #<msg_error_bad_input
        ldy #>msg_error_bad_input
        jsr fatal_statement_error
        rts
_cli_done:
        lda #0
        sta input_raw_mode
        rts

; LINE INPUT# channel, v$ [, v$ ...] -- one CR-terminated record per
; variable, verbatim (quotes are data; an empty record gives "")
compile_line_input_hash:
        jsr line_get            ; consume the INPUT# token
        jsr compile_expression
        bcs _clih_bad
        jsr emit_tmpl
        .word out_jsr_fiochkin
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _clih_bad
        jsr line_get
        cmp #','
        bne _clih_bad
        lda #1
        sta io_from_file
        sta input_raw_mode
_clih_target:
        jsr emit_input_line     ; one record per variable
        jsr compile_input_target
        bcs _clih_tbad
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _clih_done
        jsr line_get
        cmp #','
        beq _clih_target
_clih_tbad:
        lda #0
        sta io_from_file
        sta input_raw_mode
_clih_bad:
        lda #<msg_error_bad_input
        ldy #>msg_error_bad_input
        jsr fatal_statement_error
        rts
_clih_done:
        lda #0
        sta io_from_file
        sta input_raw_mode
        jsr emit_tmpl_done
        .word out_jsr_fiodone

compile_input_target:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_input_target_bad
        jsr line_get
        jsr is_var_start
        bcs _compile_input_target_bad
        jsr parse_variable_with_first_char
        bcs _compile_input_target_bad
        lda input_raw_mode      ; LINE INPUT: strings only (the book
        beq +                   ; raises TYPE MISMATCH; we reject at
        lda var_type            ; compile time)
        cmp #VAR_TYPE_STRING
        bne _compile_input_target_bad
+       lda var_type
        jsr var_type_is_numeric
        bcc _compile_input_type_ok
        cmp #VAR_TYPE_STRING
        bne _compile_input_target_bad
_compile_input_type_ok:
        sta read_target_type
        jsr line_skip_spaces
        jsr line_at_end
        bcs _compile_input_scalar
        jsr line_peek
        cmp #'('
        beq _compile_input_array

_compile_input_scalar:
        jsr resolve_var
        bcs _compile_input_target_bad
        lda current_var_data_lo
        sta assign_var_data_lo
        lda current_var_data_hi
        sta assign_var_data_hi
        lda read_target_type
        sta assign_var_type
        lda read_target_type
        cmp #VAR_TYPE_STRING
        beq _compile_input_string_scalar
        jsr emit_input_int
        jsr emit_store_var
        clc
        rts

_compile_input_string_scalar:
        jsr emit_input_string
        jsr emit_store_var
        clc
        rts

_compile_input_array:
        lda #VAR_KIND_ARRAY1
        sta var_kind
        jsr resolve_existing_var
        bcs _compile_input_target_bad
        lda current_var_data_lo
        sta array_base_lo
        lda current_var_data_hi
        sta array_base_hi
        lda current_sym_index
        pha
        jsr compile_array_index
        pla
        sta array_sym_index
        bcs _compile_input_target_bad
        lda array_base_lo
        sta current_var_data_lo
        lda array_base_hi
        sta current_var_data_hi
        jsr emit_set_arrayptr_current
        jsr emit_save_arrayptr
        lda read_target_type
        cmp #VAR_TYPE_STRING
        beq _compile_input_string_array
        jsr emit_input_int
        bra _compile_input_array_store

_compile_input_string_array:
        jsr emit_input_string

_compile_input_array_store:
        lda read_target_type
        cmp #VAR_TYPE_FLOAT
        beq _compile_input_array_flt
        jsr emit_restore_arrayptr
        jsr emit_store_ptr
        clc
        rts

_compile_input_array_flt:
        jsr emit_tmpl
        .word out_jsr_float16
        jsr emit_restore_arrayptr
        jsr emit_tmpl_done
        .word out_jsr_fstorevar

_compile_input_target_bad:
        sec
        rts

compile_get:
        lda #0
        sta get_blocking
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_get_target_loop
        jsr line_peek
        cmp #TOK_KEY            ; GETKEY tokenizes as GET + KEY
        bne _compile_get_nokey
        jsr line_get
        lda #1
        sta get_blocking
        bra _compile_get_target_loop
_compile_get_nokey:
        cmp #'#'
        bne _compile_get_target_loop
        jsr line_get
        jsr compile_expression
        bcs _compile_get_hash_bad
        jsr emit_tmpl
        .word out_jsr_fiochkin
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_get_hash_bad
        jsr line_get
        cmp #','
        bne _compile_get_hash_bad
        lda #1
        sta io_from_file
        jsr _compile_get_loop_entry
        lda #0
        sta io_from_file
        jsr emit_tmpl_done
        .word out_jsr_fiodone

_compile_get_hash_bad:
        lda #<msg_error_bad_get
        ldy #>msg_error_bad_get
        jsr fatal_statement_error
        rts

_compile_get_loop_entry:
_compile_get_target_loop:
        jsr compile_get_target
        bcs _compile_get_bad
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_get_done
        jsr line_get
        cmp #','
        beq _compile_get_target_loop

_compile_get_bad:
        lda #<msg_error_bad_get
        ldy #>msg_error_bad_get
        jsr fatal_statement_error

_compile_get_done:
        rts

compile_get_target:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_get_target_bad
        jsr line_get
        jsr is_var_start
        bcs _compile_get_target_bad
        jsr parse_variable_with_first_char
        bcs _compile_get_target_bad
        lda var_type
        jsr var_type_is_numeric
        bcc _compile_get_type_ok
        cmp #VAR_TYPE_STRING
        bne _compile_get_target_bad
_compile_get_type_ok:
        sta read_target_type
        jsr line_skip_spaces
        jsr line_at_end
        bcs _compile_get_scalar
        jsr line_peek
        cmp #'('
        beq _compile_get_array

_compile_get_scalar:
        jsr resolve_var
        bcs _compile_get_target_bad
        lda current_var_data_lo
        sta assign_var_data_lo
        lda current_var_data_hi
        sta assign_var_data_hi
        lda read_target_type
        sta assign_var_type
        lda read_target_type
        cmp #VAR_TYPE_STRING
        beq _compile_get_string_scalar
        jsr emit_get_key
        jsr emit_store_var
        clc
        rts

_compile_get_string_scalar:
        jsr emit_get_string
        jsr emit_store_var
        clc
        rts

_compile_get_array:
        lda #VAR_KIND_ARRAY1
        sta var_kind
        jsr resolve_existing_var
        bcs _compile_get_target_bad
        lda current_var_data_lo
        sta array_base_lo
        lda current_var_data_hi
        sta array_base_hi
        lda current_sym_index
        pha
        jsr compile_array_index
        pla
        sta array_sym_index
        bcs _compile_get_target_bad
        lda array_base_lo
        sta current_var_data_lo
        lda array_base_hi
        sta current_var_data_hi
        jsr emit_set_arrayptr_current
        jsr emit_save_arrayptr
        lda read_target_type
        cmp #VAR_TYPE_STRING
        beq _compile_get_string_array
        jsr emit_get_key
        bra _compile_get_array_store

_compile_get_string_array:
        jsr emit_get_string

_compile_get_array_store:
        lda read_target_type
        cmp #VAR_TYPE_FLOAT
        beq _compile_get_array_flt
        jsr emit_restore_arrayptr
        jsr emit_store_ptr
        clc
        rts

_compile_get_array_flt:
        jsr emit_tmpl
        .word out_jsr_float16
        jsr emit_restore_arrayptr
        jsr emit_tmpl_done
        .word out_jsr_fstorevar

_compile_get_target_bad:
        sec
        rts

try_compile_print_string_var:
        lda line_idx
        sta line_idx_save
        jsr line_at_end
        bcs _try_print_string_var_fail
        jsr line_peek
        jsr is_var_start
        bcs _try_print_string_var_fail
        jsr line_get
        jsr parse_variable_with_first_char
        bcs _try_print_string_var_restore_fail
        lda var_type
        cmp #VAR_TYPE_STRING
        bne _try_print_string_var_restore_fail
        lda var_name_1
        cmp #$54                ; TI$ and DS$ read live state and must
        bne _tps_not_ti         ; go through the string factor
        lda var_name_2
        cmp #$49
        beq _try_print_string_var_restore_fail
_tps_not_ti:
        lda var_name_1
        cmp #$44
        bne _tps_not_ds
        lda var_name_2
        cmp #$53
        beq _try_print_string_var_restore_fail
_tps_not_ds:
        jsr line_skip_spaces
        jsr try_print_item_end
        bcc _try_print_string_var_scalar
        jsr line_peek
        cmp #'('
        beq _try_print_string_var_array
        bra _try_print_string_var_restore_fail

_try_print_string_var_scalar:
        jsr resolve_existing_var
        bcs _try_print_string_var_restore_fail
        jsr emit_print_string_var_current
        clc
        rts

_try_print_string_var_array:
        lda #VAR_KIND_ARRAY1
        sta var_kind
        jsr resolve_existing_var
        bcs _try_print_string_var_restore_fail
        lda current_var_data_lo
        sta array_base_lo
        lda current_var_data_hi
        sta array_base_hi
        lda current_sym_index
        pha
        jsr compile_array_index
        pla
        sta array_sym_index
        bcs _try_print_string_var_restore_fail
        lda array_base_lo
        sta current_var_data_lo
        lda array_base_hi
        sta current_var_data_hi
        jsr emit_set_arrayptr_current
        jsr emit_load_ptr
        jsr emit_print_string_expr
        clc
        rts

_try_print_string_var_restore_fail:
        lda line_idx_save
        sta line_idx

_try_print_string_var_fail:
        sec
        rts

try_compile_print_numeric_var:
        lda line_idx
        sta line_idx_save
        jsr line_at_end
        bcs _try_print_num_var_fail
        jsr line_peek
        jsr is_var_start
        bcs _try_print_num_var_fail
        jsr line_get
        jsr parse_variable_with_first_char
        bcs _try_print_num_var_restore_fail
        jsr is_special_numeric_var
        bcc _try_print_num_var_restore_fail
        lda var_type
        cmp #VAR_TYPE_STRING
        beq _try_print_num_var_restore_fail
        jsr var_type_is_numeric
        bcs _try_print_num_var_restore_fail
        jsr line_skip_spaces
        jsr line_at_print_end
        bcs _try_print_num_var_scalar
        jsr line_peek
        cmp #'('
        beq _try_print_num_var_restore_fail
        jsr try_print_item_end
        bcs _try_print_num_var_restore_fail

_try_print_num_var_scalar:
        jsr resolve_var
        bcs _try_print_num_var_restore_fail
        lda var_type
        cmp #VAR_TYPE_FLOAT
        beq _try_print_num_var_float
        jsr emit_load_var
        jsr emit_print_uint_expr
        clc
        rts

_try_print_num_var_float:
        jsr emit_set_varptr_current
        jsr emit_tmpl
        .word out_jsr_floadvar
        jsr emit_tmpl_done
        .word out_jsr_printflt

_try_print_num_var_restore_fail:
        lda line_idx_save
        sta line_idx

_try_print_num_var_fail:
        sec
        rts


try_print_item_end:
        jsr line_skip_spaces
        jsr line_at_print_end
        bcs _try_print_item_end_yes
        jsr line_peek
        cmp #';'
        beq _try_print_item_end_yes
        cmp #','
        beq _try_print_item_end_yes
        sec
        rts

_try_print_item_end_yes:
        clc
        rts

compile_goto:
        jsr line_parse_number
        bcs _goto_bad
        jsr line_number_exists
        bcs _goto_bad
        jsr emit_tmpl
        .word out_jmp_label
        jsr out_label_from_number
        jsr out_cr
        jsr line_skip_to_stmt_end
        rts

_goto_bad:
        lda #<msg_error_bad_goto
        ldy #>msg_error_bad_goto
        jsr fatal_statement_error
        rts

compile_gosub:
        jsr line_parse_number
        bcs _gosub_bad
        jsr line_number_exists
        bcs _gosub_bad
        jsr emit_tmpl
        .word out_jsr_label
        jsr out_label_from_number
        jsr out_cr
        jsr line_skip_to_stmt_end
        rts

_gosub_bad:
        lda #<msg_error_bad_gosub
        ldy #>msg_error_bad_gosub
        jsr fatal_statement_error
        rts

compile_go:
        jsr line_skip_spaces
        jsr line_get
        cmp #TOK_TO
        beq compile_goto
        cmp #TOK_SYS
        beq compile_sys
        sta token_value
        lda #<msg_error_unsupported_go
        ldy #>msg_error_unsupported_go
        jsr fatal_statement_error
        rts

compile_on:
        jsr compile_expression
        bcs _on_bad
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _on_bad
        jsr line_get
        cmp #TOK_GOTO
        beq _on_goto
        cmp #TOK_GOSUB
        beq _on_gosub
        cmp #TOK_GO
        beq _on_go
        bra _on_bad

_on_go:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _on_bad
        jsr line_get
        cmp #TOK_TO
        bne _on_bad

_on_goto:
        lda #ON_MODE_GOTO
        sta on_mode
        bra _on_list_start

_on_gosub:
        lda #ON_MODE_GOSUB
        sta on_mode
        jsr alloc_on_label
        lda on_label_lo
        sta on_done_lo
        lda on_label_hi
        sta on_done_hi

_on_list_start:
        lda #1
        sta on_target_index

_on_list_loop:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _on_bad
        jsr line_parse_number
        bcs _on_bad
        jsr line_number_exists
        bcs _on_bad
        lda number_lo
        sta on_target_lo
        lda number_hi
        sta on_target_hi
        jsr alloc_on_label
        jsr emit_on_compare
        lda on_mode
        cmp #ON_MODE_GOSUB
        beq _on_emit_gosub
        jsr emit_jmp_on_target
        bra _on_after_emit

_on_emit_gosub:
        jsr emit_jsr_on_target
        jsr emit_jmp_ondone

_on_after_emit:
        jsr emit_onnext_label_def
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _on_done
        jsr line_get
        cmp #','
        bne _on_bad
        inc on_target_index
        bne _on_list_loop

_on_bad:
        lda #<msg_error_bad_on
        ldy #>msg_error_bad_on
        jsr fatal_statement_error
        rts

_on_done:
        lda on_mode
        cmp #ON_MODE_GOSUB
        bne _on_return
        jsr emit_ondone_label_def

_on_return:
        rts

compile_sys:
        jsr line_parse_number
        bcs _sys_bad
        jsr emit_tmpl
        .word out_jsr_abs
        jsr out_hex_word_number
        jsr out_cr
        jsr emit_tmpl
        .word out_jsr_sysregsave
        jsr line_skip_to_stmt_end
        rts

_sys_bad:
        lda #<msg_error_bad_sys
        ldy #>msg_error_bad_sys
        jsr fatal_statement_error
        rts

compile_poke:
        jsr compile_expression
        bcs poke_bad
        jsr emit_expr_to_rtptr
        jsr emit_save_rtptr
        jsr line_skip_spaces
        jsr line_at_end
        bcs poke_bad
        jsr line_get
        cmp #','
        bne poke_bad
        jsr compile_expression
        bcs poke_bad
        jsr emit_restore_rtptr
        jsr emit_poke_expr_to_rtptr
        rts

compile_wpoke:
        jsr compile_expression
        bcs wpoke_bad
        jsr emit_expr_to_rtptr
        jsr emit_save_rtptr
        jsr line_skip_spaces
        jsr line_at_end
        bcs wpoke_bad
        jsr line_get
        cmp #','
        bne wpoke_bad
        jsr compile_expression
        bcs wpoke_bad
        jsr emit_restore_rtptr
        jsr emit_wpoke_expr_to_rtptr
        rts

poke_bad:
        lda #<msg_error_bad_poke
        ldy #>msg_error_bad_poke
        jsr fatal_statement_error
        rts

wpoke_bad:
        lda #<msg_error_bad_poke
        ldy #>msg_error_bad_poke
        jsr fatal_statement_error
        rts

compile_read:
_compile_read_next:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_read_bad
        jsr line_get
        jsr is_var_start
        bcs _compile_read_bad
        jsr parse_variable_with_first_char
        bcs _compile_read_bad
        lda var_type
        jsr var_type_is_numeric
        bcc _compile_read_type_ok
        cmp #VAR_TYPE_STRING
        bne _compile_read_bad
_compile_read_type_ok:
        sta read_target_type

        jsr line_skip_spaces
        jsr line_at_end
        bcs _compile_read_scalar
        jsr line_peek
        cmp #'('
        beq _compile_read_array

_compile_read_scalar:
        jsr resolve_var
        bcs _compile_read_bad
        lda current_var_data_lo
        sta assign_var_data_lo
        lda current_var_data_hi
        sta assign_var_data_hi
        lda read_target_type
        sta assign_var_type
        jsr emit_read_for_target
        jsr emit_store_var
        bra _compile_read_after_target

_compile_read_array:
        lda #VAR_KIND_ARRAY1
        sta var_kind
        jsr resolve_existing_var
        bcs _compile_read_bad
        lda current_var_data_lo
        sta array_base_lo
        lda current_var_data_hi
        sta array_base_hi
        lda current_sym_index
        pha
        jsr compile_array_index
        pla
        sta array_sym_index
        bcs _compile_read_bad
        lda array_base_lo
        sta current_var_data_lo
        lda array_base_hi
        sta current_var_data_hi
        jsr emit_set_arrayptr_current
        jsr emit_save_arrayptr
        jsr emit_read_for_target
        lda read_target_type
        cmp #VAR_TYPE_FLOAT
        beq _compile_read_array_flt
        jsr emit_restore_arrayptr
        jsr emit_store_ptr
        bra _compile_read_after_target

_compile_read_array_flt:
        jsr emit_tmpl
        .word out_jsr_float16
        jsr emit_restore_arrayptr
        jsr emit_tmpl
        .word out_jsr_fstorevar

_compile_read_after_target:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_read_done
        jsr line_get
        cmp #','
        beq _compile_read_next

_compile_read_bad:
        lda #<msg_error_bad_read
        ldy #>msg_error_bad_read
        jsr fatal_statement_error

_compile_read_done:
        rts

emit_read_for_target:
        lda read_target_type
        cmp #VAR_TYPE_STRING
        beq emit_read_string
        bra emit_read_int

compile_restore:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_restore_all
        jsr line_parse_number
        bcs _compile_restore_bad
        jsr data_line_number_exists
        bcs _compile_restore_bad
        jsr emit_restore_data_line
        jsr line_skip_to_stmt_end
        rts

_compile_restore_all:
        jsr emit_tmpl
        .word out_jsr_datainit
        jsr line_skip_to_stmt_end
        rts

_compile_restore_bad:
        lda #<msg_error_bad_restore
        ldy #>msg_error_bad_restore
        jsr fatal_statement_error
        rts

compile_rem:
        jsr emit_tmpl
        .word out_rem

_rem_loop:
        jsr line_at_end
        bcs _rem_done
        jsr line_get
        jsr out_comment_char
        bra _rem_loop

_rem_done:
        jsr out_cr
        rts

;=======================================================================================
; Line buffer helpers
;=======================================================================================

is_var_start:
        cmp #ASCII_UPPER_A
        bcc _is_var_start_no
        cmp #ASCII_UPPER_Z + 1
        bcs _is_var_start_no
        clc
        rts

_is_var_start_no:
        sec
        rts

is_var_tail:
        cmp #ASCII_UPPER_A
        bcc _is_var_tail_digit
        cmp #ASCII_UPPER_Z + 1
        bcc _is_var_tail_yes

_is_var_tail_digit:
        cmp #'0'
        bcc _is_var_tail_no
        cmp #'9' + 1
        bcs _is_var_tail_no

_is_var_tail_yes:
        clc
        rts

_is_var_tail_no:
        sec
        rts

var_type_is_numeric:
        cmp #VAR_TYPE_INT
        beq _var_type_numeric_yes
        cmp #VAR_TYPE_FLOAT
        beq _var_type_numeric_yes
        sec
        rts

_var_type_numeric_yes:
        clc
        rts

parse_variable_with_first_char:
        sta var_name_1
        lda #0
        sta var_name_2
        sta var_kind
        lda #VAR_TYPE_FLOAT
        sta var_type

        jsr line_at_end
        bcs _parse_var_done
        jsr line_peek
        jsr is_var_tail
        bcs _parse_var_suffix
        jsr line_get
        sta var_name_2

_parse_var_suffix:
        jsr line_at_end
        bcs _parse_var_done
        jsr line_peek
        cmp #'%'
        beq _parse_var_int_suffix
        cmp #'$'
        beq _parse_var_string_suffix

_parse_var_done:
        clc
        rts

_parse_var_int_suffix:
        jsr line_get
        lda #VAR_TYPE_INT
        sta var_type
        clc
        rts

_parse_var_string_suffix:
        jsr line_get
        lda #VAR_TYPE_STRING
        sta var_type
        clc
        rts

resolve_var:
        ldx #0
_resolve_var_loop:
        cpx sym_count
        beq _resolve_var_create
        lda sym_name_1,x
        cmp var_name_1
        bne _resolve_var_next
        lda sym_name_2,x
        cmp var_name_2
        bne _resolve_var_next
        lda sym_kind,x
        cmp var_kind
        bne _resolve_var_next
        lda sym_type,x
        cmp var_type
        bne _resolve_var_next
        lda sym_data_lo,x
        sta current_var_data_lo
        lda sym_data_hi,x
        sta current_var_data_hi
        stx current_sym_index
        clc
        rts

_resolve_var_next:
        inx
        bra _resolve_var_loop

_resolve_var_create:
        lda var_kind
        cmp #VAR_KIND_SCALAR
        bne _resolve_var_fail
        cpx #SYM_MAX
        bcs _resolve_var_fail

        lda var_heap_next_lo
        clc
        adc #VAR_DESC_SIZE
        sta work_lo
        lda var_heap_next_hi
        adc #0
        sta work_hi
        lda work_hi
        cmp #>VAR_HEAP_LIMIT
        bcc _resolve_var_room
        bne _resolve_var_fail
        lda work_lo
        bne _resolve_var_fail

_resolve_var_room:
        lda var_heap_next_lo
        clc
        adc #VAR_DESC_VALUE_OFFSET
        sta current_var_data_lo
        lda var_heap_next_hi
        adc #0
        sta current_var_data_hi

        ldx sym_count
        lda var_name_1
        sta sym_name_1,x
        lda var_name_2
        sta sym_name_2,x
        lda var_kind
        sta sym_kind,x
        lda var_type
        sta sym_type,x
        lda #0
        sta sym_rank,x
        lda current_var_data_lo
        sta sym_data_lo,x
        lda current_var_data_hi
        sta sym_data_hi,x
        lda #0
        sta sym_dim0_lo,x
        sta sym_dim0_hi,x
        inc sym_count
        stx current_sym_index

        lda work_lo
        sta var_heap_next_lo
        lda work_hi
        sta var_heap_next_hi
        clc
        rts

_resolve_var_fail:
        sec
        rts

resolve_existing_var:
        ldx #0
_resolve_existing_loop:
        cpx sym_count
        beq _resolve_existing_fail
        lda sym_name_1,x
        cmp var_name_1
        bne _resolve_existing_next
        lda sym_name_2,x
        cmp var_name_2
        bne _resolve_existing_next
        lda sym_kind,x
        cmp var_kind
        bne _resolve_existing_next
        lda sym_type,x
        cmp var_type
        bne _resolve_existing_next
        lda sym_data_lo,x
        sta current_var_data_lo
        lda sym_data_hi,x
        sta current_var_data_hi
        stx current_sym_index
        clc
        rts

_resolve_existing_next:
        inx
        bra _resolve_existing_loop

_resolve_existing_fail:
        sec
        rts

create_array_var:
        ldx #0
_create_array_find:
        cpx sym_count
        beq _create_array_new
        lda sym_name_1,x
        cmp var_name_1
        bne _create_array_next
        lda sym_name_2,x
        cmp var_name_2
        bne _create_array_next
        lda sym_kind,x
        cmp #VAR_KIND_ARRAY1
        bne _create_array_next
        lda sym_type,x
        cmp var_type
        beq _create_array_fail
_create_array_next:
        inx
        bra _create_array_find

_create_array_new:
        cpx #SYM_MAX
        bcs _create_array_fail

        jsr compute_array_element_count
        bcs _create_array_fail
        lda var_type
        cmp #VAR_TYPE_FLOAT
        beq _create_array_float
        asl work2_lo
        rol work2_hi
        bcs _create_array_fail
        bra _create_array_sized
_create_array_float:
        lda work2_lo            ; bytes = count*4 + count
        sta work_lo
        lda work2_hi
        sta work_hi
        asl work2_lo
        rol work2_hi
        bcs _create_array_fail
        asl work2_lo
        rol work2_hi
        bcs _create_array_fail
        clc
        lda work2_lo
        adc work_lo
        sta work2_lo
        lda work2_hi
        adc work_hi
        sta work2_hi
        bcs _create_array_fail
_create_array_sized:

        lda var_heap_next_lo
        clc
        adc #VAR_DESC_SIZE
        sta current_var_data_lo
        lda var_heap_next_hi
        adc #0
        bcs _create_array_fail
        sta current_var_data_hi

        lda current_var_data_lo
        clc
        adc work2_lo
        sta work2_lo
        lda current_var_data_hi
        adc work2_hi
        bcs _create_array_fail
        sta work2_hi

        lda work2_hi
        cmp #>VAR_HEAP_LIMIT
        bcc _create_array_room
        bne _create_array_fail
        lda work2_lo
        bne _create_array_fail

_create_array_room:
        ldx sym_count
        lda var_name_1
        sta sym_name_1,x
        lda var_name_2
        sta sym_name_2,x
        lda #VAR_KIND_ARRAY1
        sta sym_kind,x
        lda var_type
        sta sym_type,x
        lda array_rank
        sta sym_rank,x
        lda current_var_data_lo
        sta sym_data_lo,x
        lda current_var_data_hi
        sta sym_data_hi,x
        lda array_dims_lo+0
        sta sym_dim0_lo,x
        lda array_dims_hi+0
        sta sym_dim0_hi,x
        lda array_dims_lo+1
        sta sym_dim1_lo,x
        lda array_dims_hi+1
        sta sym_dim1_hi,x
        lda array_dims_lo+2
        sta sym_dim2_lo,x
        lda array_dims_hi+2
        sta sym_dim2_hi,x
        lda array_dims_lo+3
        sta sym_dim3_lo,x
        lda array_dims_hi+3
        sta sym_dim3_hi,x
        lda array_dims_lo+4
        sta sym_dim4_lo,x
        lda array_dims_hi+4
        sta sym_dim4_hi,x
        lda array_dims_lo+5
        sta sym_dim5_lo,x
        lda array_dims_hi+5
        sta sym_dim5_hi,x
        inc sym_count
        stx current_sym_index

        lda work2_lo
        sta var_heap_next_lo
        lda work2_hi
        sta var_heap_next_hi
        clc
        rts

_create_array_fail:
        sec
        rts

compute_array_element_count:
        lda #1
        sta work2_lo
        lda #0
        sta work2_hi
        sta array_dim_index

_compute_array_count_loop:
        lda array_dim_index
        cmp array_rank
        beq _compute_array_count_done
        tax
        lda array_dims_lo,x
        sta work_lo
        lda array_dims_hi,x
        sta work_hi
        jsr multiply_work2_by_work
        bcs _compute_array_count_fail
        inc array_dim_index
        bra _compute_array_count_loop

_compute_array_count_done:
        clc
        rts

_compute_array_count_fail:
        sec
        rts

multiply_work2_by_work:
        lda #0
        sta array_product_lo
        sta array_product_hi
        ldx #16

_mul_work_loop:
        lda work_lo
        ora work_hi
        beq _mul_work_done
        lda work_lo
        and #1
        beq _mul_work_skip_add
        clc
        lda array_product_lo
        adc work2_lo
        sta array_product_lo
        lda array_product_hi
        adc work2_hi
        sta array_product_hi
        bcs _mul_work_fail

_mul_work_skip_add:
        lsr work_hi
        ror work_lo
        lda work_lo
        ora work_hi
        beq _mul_work_done
        asl work2_lo
        rol work2_hi
        bcs _mul_work_fail
        dex
        bne _mul_work_loop

_mul_work_fail:
        sec
        rts

_mul_work_done:
        lda array_product_lo
        sta work2_lo
        lda array_product_hi
        sta work2_hi
        clc
        rts

line_at_end:
        ldx line_idx
        cpx line_len
        bcs _line_at_end_yes
        clc
        rts

_line_at_end_yes:
        sec
        rts

line_at_end_or_colon:
        jsr line_at_end
        bcs _line_end_or_colon_yes
        jsr line_peek
        cmp #':'
        beq _line_end_or_colon_yes
        clc
        rts

_line_end_or_colon_yes:
        sec
        rts

line_at_print_end:
        jsr line_at_end_or_colon
        bcs _line_print_end_yes
        lda compile_stop_on_else
        beq _line_print_end_no
        jsr line_peek
        cmp #TOK_ELSE
        beq _line_print_end_yes

_line_print_end_no:
        clc
        rts

_line_print_end_yes:
        sec
        rts

line_peek:
        ldx line_idx
        lda line_buf,x
        rts

line_get:
        ldx line_idx
        lda line_buf,x
        inc line_idx
        rts

line_skip_spaces:
_skip_spaces_loop:
        jsr line_at_end
        bcs _skip_spaces_done
        jsr line_peek
        cmp #' '
        bne _skip_spaces_done
        inc line_idx
        bra _skip_spaces_loop
_skip_spaces_done:
        rts

line_skip_spaces_colons:
        lda #0
        sta line_had_colon
_skip_sc_loop:
        jsr line_at_end
        bcs _skip_sc_done
        jsr line_peek
        cmp #' '
        beq _skip_sc_take
        cmp #':'
        bne _skip_sc_done
        lda #1
        sta line_had_colon
_skip_sc_take:
        inc line_idx
        bra _skip_sc_loop
_skip_sc_done:
        rts

line_skip_to_stmt_end:
_skip_stmt_loop:
        jsr line_at_end
        bcs _skip_stmt_done
        jsr line_peek
        cmp #':'
        beq _skip_stmt_done
        cmp #'"'
        beq _skip_stmt_string
        inc line_idx
        bra _skip_stmt_loop

_skip_stmt_string:
        jsr line_get
        jsr scan_skip_string
        bra _skip_stmt_loop

_skip_stmt_done:
        rts

line_skip_to_end:
        lda line_len
        sta line_idx
        rts

line_parse_number:
        jsr line_skip_spaces
        lda #0
        sta number_lo
        sta number_hi
        sta number_digits

        jsr line_at_end
        bcs _parse_number_fail
        jsr line_peek
        cmp #'$'
        beq _parse_hex_number

_parse_dec_loop:
        jsr line_at_end
        bcs _parse_dec_done
        jsr line_peek
        cmp #'0'
        bcc _parse_dec_done
        cmp #'9' + 1
        bcs _parse_dec_done

        jsr line_get
        sec
        sbc #'0'
        sta digit_value
        jsr number_mul10_add_digit
        inc number_digits
        bra _parse_dec_loop

_parse_dec_done:
        lda number_digits
        beq _parse_number_fail
        clc
        rts

_parse_hex_number:
        jsr line_get                         ; '$'
_parse_hex_loop:
        jsr line_at_end
        bcs _parse_hex_done
        jsr line_peek
        jsr hex_to_nibble
        bcs _parse_hex_done
        sta digit_value
        jsr line_get
        jsr number_shl4_add_digit
        inc number_digits
        bra _parse_hex_loop

_parse_hex_done:
        lda number_digits
        beq _parse_number_fail
        clc
        rts

_parse_number_fail:
        sec
        rts

line_parse_decimal_number:
        jsr line_skip_spaces
        lda #0
        sta number_lo
        sta number_hi
        sta number_digits

_parse_decimal_only_loop:
        jsr line_at_end
        bcs _parse_decimal_only_done
        jsr line_peek
        cmp #'0'
        bcc _parse_decimal_only_done
        cmp #'9' + 1
        bcs _parse_decimal_only_done

        jsr line_get
        sec
        sbc #'0'
        sta digit_value
        jsr number_mul10_add_digit
        inc number_digits
        bra _parse_decimal_only_loop

_parse_decimal_only_done:
        lda number_digits
        beq _parse_decimal_only_fail
        clc
        rts

_parse_decimal_only_fail:
        sec
        rts

line_parse_signed_decimal_number:
        jsr line_skip_spaces
        lda #0
        sta data_sign
        jsr line_at_end
        bcs _parse_signed_fail
        jsr line_peek
        cmp #TOK_MINUS
        beq _parse_signed_minus
        cmp #'-'
        beq _parse_signed_minus
        cmp #TOK_PLUS
        beq _parse_signed_plus
        cmp #'+'
        bne _parse_signed_value

_parse_signed_plus:
        jsr line_get
        bra _parse_signed_value

_parse_signed_minus:
        jsr line_get
        lda #1
        sta data_sign

_parse_signed_value:
        jsr line_parse_decimal_number
        bcs _parse_signed_fail
        lda data_sign
        beq _parse_signed_done
        sec
        lda #0
        sbc number_lo
        sta number_lo
        lda #0
        sbc number_hi
        sta number_hi

_parse_signed_done:
        clc
        rts

_parse_signed_fail:
        sec
        rts

add_string_literal:
        lda #0
        sta string_temp_len

_add_string_loop:
        jsr line_at_end
        bcs _add_string_fail
        jsr line_get
        cmp #'"'
        beq _add_string_done
        ldx string_temp_len
        cpx #LINE_BUF_MAX
        bcs _add_string_fail
        sta string_temp,x
        inc string_temp_len
        bra _add_string_loop

_add_string_done:
        ldx string_temp_len
        lda #0
        sta string_temp,x
        jsr find_string_literal
        bcc _add_string_found
        jsr append_string_temp
        bcs _add_string_fail

_add_string_found:
        clc
        rts

_add_string_fail:
        sec
        rts

parse_float_literal_to_string_temp:
        jsr line_skip_spaces
        lda #0
        sta string_temp_len
        sta number_digits
        sta byte_value

        jsr line_at_end
        bcs _parse_float_fail
        jsr line_peek
        cmp #TOK_MINUS
        beq _parse_float_minus
        cmp #'-'
        beq _parse_float_minus
        cmp #TOK_PLUS
        beq _parse_float_plus
        cmp #'+'
        beq _parse_float_plus
        bra _parse_float_before

_parse_float_plus:
        jsr line_get
        bra _parse_float_before

_parse_float_minus:
        jsr line_get
        lda #'-'
        jsr string_temp_append_a
        bcs _parse_float_fail

_parse_float_before:
        jsr line_at_end
        bcs _parse_float_intend ; digits ran to end of line
        jsr line_peek
        cmp #'0'
        bcc _parse_float_dot_check
        cmp #'9' + 1
        bcs _parse_float_dot_check
        jsr line_get
        jsr string_temp_append_a
        bcs _parse_float_fail
        inc number_digits
        bra _parse_float_before

_parse_float_dot_check:
        cmp #'.'
        beq _parse_float_dot
        ; no dot: a plain integer. Values past 16 bits must ride the
        ; float-literal path (the int path wraps) -- the digits are
        ; already in string_temp, so just accept.
_parse_float_intend:
        lda number_digits
        cmp #6
        bcs _parse_float_bigint
        cmp #5
        bne _parse_float_fail
        ldx string_temp_len     ; five digits: lexical compare against
        dex                     ; 65535, most significant first
        dex
        dex
        dex
        dex
        ldy #0
_pf_cmp5:
        lda string_temp,x
        cmp _pf_65535,y
        bcc _parse_float_fail   ; below: fits, the int path takes it
        bne _parse_float_bigint ; above: 16-bit overflow, go float
        inx
        iny
        cpy #5
        bne _pf_cmp5
        bra _parse_float_fail   ; exactly 65535 still fits
_parse_float_bigint:
        clc
        rts
_pf_65535:
        .text "65535"
_parse_float_dot:
        jsr line_get
        lda #'.'
        jsr string_temp_append_a
        bcs _parse_float_fail

_parse_float_after:
        jsr line_at_end
        bcs _parse_float_after_done
        jsr line_peek
        cmp #'0'
        bcc _parse_float_after_done
        cmp #'9' + 1
        bcs _parse_float_after_done
        jsr line_get
        jsr string_temp_append_a
        bcs _parse_float_fail
        inc byte_value
        bra _parse_float_after

_parse_float_after_done:
        lda byte_value
        beq _parse_float_fail
        clc
        rts

_parse_float_fail:
        sec
        rts

string_temp_append_a:
        ldx string_temp_len
        cpx #LINE_BUF_MAX
        bcs _string_temp_append_fail
        sta string_temp,x
        inc string_temp_len
        clc
        rts

_string_temp_append_fail:
        sec
        rts

; find or allocate the bank-1 5-byte slot for the float literal whose text
; was just interned as current_string_id; result in current_var_data_lo/hi
flt_slot_for_string:
        ldx #0
_flt_slot_scan:
        cpx flt_lit_count
        beq _flt_slot_new
        lda flt_lit_sid,x
        cmp current_string_id
        beq _flt_slot_found
        inx
        bra _flt_slot_scan
_flt_slot_found:
        lda flt_lit_addr_lo,x
        sta current_var_data_lo
        lda flt_lit_addr_hi,x
        sta current_var_data_hi
        clc
        rts
_flt_slot_new:
        cpx #FLT_LIT_MAX
        bcs _flt_slot_fail
        lda var_heap_next_hi
        cmp #>VAR_HEAP_LIMIT
        bcs _flt_slot_fail
        lda current_string_id
        sta flt_lit_sid,x
        lda var_heap_next_lo
        sta flt_lit_addr_lo,x
        sta current_var_data_lo
        lda var_heap_next_hi
        sta flt_lit_addr_hi,x
        sta current_var_data_hi
        inc flt_lit_count
        clc
        lda var_heap_next_lo
        adc #5
        sta var_heap_next_lo
        bcc _flt_slot_done
        inc var_heap_next_hi
_flt_slot_done:
        clc
        rts
_flt_slot_fail:
        sec
        rts

intern_string_temp:
        ldx string_temp_len
        lda #0
        sta string_temp,x
        jsr find_string_literal
        bcc _intern_string_temp_done
        jsr append_string_temp
        bcs _intern_string_temp_fail

_intern_string_temp_done:
        clc
        rts

_intern_string_temp_fail:
        sec
        rts

find_string_literal:
        lda #0
        sta string_match_idx

_find_string_loop:
        lda string_match_idx
        cmp string_count
        bcs _find_string_none
        jsr string_literal_matches
        bcc _find_string_found
        inc string_match_idx
        bra _find_string_loop

_find_string_found:
        lda string_match_idx
        sta current_string_id
        clc
        rts

_find_string_none:
        sec
        rts

string_literal_matches:
        ldx string_match_idx
        jsr stroffload
        lda #0
        sta string_temp_idx

_string_match_loop:
        ldx string_temp_idx
        lda string_temp,x
        sta byte_value
        jsr string_pool_read_byte
        cmp byte_value
        bne _string_match_no
        lda byte_value
        beq _string_match_yes
        inc string_temp_idx
        jsr inc_string_read
        bra _string_match_loop

_string_match_yes:
        clc
        rts

_string_match_no:
        sec
        rts

append_string_temp:
        lda string_count
        cmp #STRING_MAX
        bcs _append_string_fail
        sta current_string_id
        tax
        jsr stroffstore
        lda #0
        sta string_temp_idx

_append_string_loop:
        ldx string_temp_idx
        lda string_temp,x
        sta byte_value
        jsr string_pool_append_byte
        bcs _append_string_fail
        lda byte_value
        beq _append_string_done
        inc string_temp_idx
        bra _append_string_loop

_append_string_done:
        inc string_count
        clc
        rts

_append_string_fail:
        sec
        rts

; the pool lives in bank 4; borrow source_ptr ($f7, only safe far
; pointer) and restore it -- new zero page is off limits, the KERNAL
; screen editor owns most of $90-$ff ($f3/$f4 is its color pointer)
string_pool_append_byte:
        lda string_pool_next_hi
        cmp #>STRING_POOL_MAX
        bcs _string_pool_append_fail
        jsr pool_ptr_save
        lda #<POOL_BASE
        clc
        adc string_pool_next_lo
        sta source_ptr
        lda #>POOL_BASE
        adc string_pool_next_hi
        sta source_ptr+1
        ldz #0
        lda byte_value
        sta [source_ptr],z
        jsr pool_ptr_restore
        inc string_pool_next_lo
        bne +
        inc string_pool_next_hi
+       clc
        rts

_string_pool_append_fail:
        sec
        rts

string_pool_read_byte:
        jsr pool_ptr_save
        lda #<POOL_BASE
        clc
        adc string_read_lo
        sta source_ptr
        lda #>POOL_BASE
        adc string_read_hi
        sta source_ptr+1
        ldz #0
        lda [source_ptr],z
        jmp pool_ptr_restore    ; A survives, restores the pointer

; string offset tables live in bank 4 at $f000/$f100, one page each,
; through the same borrowed pointer as the pool
; branch target table in bank 4 at $f200/$f300 (X preserved)
brtabload:
        phx
        jsr pool_ptr_save
        plx
        phx
        stx source_ptr
        lda #$f2
        sta source_ptr+1
        ldz #0
        lda [source_ptr],z
        sta brtab_lo
        inc source_ptr+1
        lda [source_ptr],z
        sta brtab_hi
        jsr pool_ptr_restore
        plx
        rts

brtabstore:
        phx
        jsr pool_ptr_save
        plx
        phx
        stx source_ptr
        lda #$f2
        sta source_ptr+1
        ldz #0
        lda number_lo
        sta [source_ptr],z
        inc source_ptr+1
        lda number_hi
        sta [source_ptr],z
        jsr pool_ptr_restore
        plx
        rts

stroffload:
        phx                     ; pool_ptr_save clobbers X
        jsr pool_ptr_save
        plx
        stx source_ptr
        lda #$f0
        sta source_ptr+1
        ldz #0
        lda [source_ptr],z
        sta string_read_lo
        inc source_ptr+1
        lda [source_ptr],z
        sta string_read_hi
        jmp pool_ptr_restore

stroffstore:
        phx                     ; pool_ptr_save clobbers X
        jsr pool_ptr_save
        plx
        stx source_ptr
        lda #$f0
        sta source_ptr+1
        ldz #0
        lda string_pool_next_lo
        sta [source_ptr],z
        inc source_ptr+1
        lda string_pool_next_hi
        sta [source_ptr],z
        jmp pool_ptr_restore

pool_ptr_save:
        ldx source_ptr
        stx pool_save
        ldx source_ptr+1
        stx pool_save+1
        ldx source_ptr+2
        stx pool_save+2
        ldx source_ptr+3
        stx pool_save+3
        ldx #POOL_BANK
        stx source_ptr+2
        ldx #0
        stx source_ptr+3
        rts

pool_ptr_restore:
        ldx pool_save
        stx source_ptr
        ldx pool_save+1
        stx source_ptr+1
        ldx pool_save+2
        stx source_ptr+2
        ldx pool_save+3
        stx source_ptr+3
        rts

inc_string_read:
        inc string_read_lo
        bne +
        inc string_read_hi
+       rts

number_mul10_add_digit:
        lda number_lo
        sta work_lo
        lda number_hi
        sta work_hi

        asl number_lo                         ; value * 2
        rol number_hi

        lda work_lo                            ; work = original * 8
        sta work2_lo
        lda work_hi
        sta work2_hi
        asl work2_lo
        rol work2_hi
        asl work2_lo
        rol work2_hi
        asl work2_lo
        rol work2_hi

        clc
        lda number_lo
        adc work2_lo
        sta number_lo
        lda number_hi
        adc work2_hi
        sta number_hi

        clc
        lda number_lo
        adc digit_value
        sta number_lo
        lda number_hi
        adc #0
        sta number_hi
        rts

number_shl4_add_digit:
        asl number_lo
        rol number_hi
        asl number_lo
        rol number_hi
        asl number_lo
        rol number_hi
        asl number_lo
        rol number_hi
        clc
        lda number_lo
        adc digit_value
        sta number_lo
        lda number_hi
        adc #0
        sta number_hi
        rts

hex_to_nibble:
        cmp #'0'
        bcc _hex_bad
        cmp #'9' + 1
        bcc _hex_digit
        cmp #ASCII_UPPER_A
        bcc _hex_lower_check
        cmp #ASCII_UPPER_F + 1
        bcc _hex_upper
_hex_lower_check:
        cmp #ASCII_LOWER_A
        bcc _hex_bad
        cmp #ASCII_LOWER_F + 1
        bcs _hex_bad
        sec
        sbc #ASCII_LOWER_A - 10
        clc
        rts
_hex_upper:
        sec
        sbc #ASCII_UPPER_A - 10
        clc
        rts
_hex_digit:
        sec
        sbc #'0'
        clc
        rts
_hex_bad:
        sec
        rts

;=======================================================================================
; Output helpers
;=======================================================================================

alloc_for_label:
        lda for_label_next
        cmp #FOR_MAX
        bcs _alloc_for_label_fail
        sta current_for_id
        inc for_label_next
        clc
        rts

_alloc_for_label_fail:
        sec
        rts

alloc_do_label:
        lda do_label_next
        cmp #DO_MAX
        bcs _alloc_do_label_fail
        sta current_do_id
        inc do_label_next
        clc
        rts

_alloc_do_label_fail:
        sec
        rts

push_for_frame:
        ldx for_sp
        cpx #FOR_STACK_MAX
        bcs _push_for_fail
        lda current_for_id
        sta for_stack_id,x
        lda current_for_var_data_lo
        sta for_stack_var_data_lo,x
        lda current_for_var_data_hi
        sta for_stack_var_data_hi,x
        lda current_for_var_type
        sta for_stack_var_type,x
        inc for_sp
        clc
        rts

_push_for_fail:
        sec
        rts

pop_for_frame:
        lda for_sp
        beq _pop_for_fail
        dec for_sp
        ldx for_sp
        lda for_stack_id,x
        sta current_for_id
        lda for_stack_var_data_lo,x
        sta current_for_var_data_lo
        lda for_stack_var_data_hi,x
        sta current_for_var_data_hi
        lda for_stack_var_type,x
        sta current_for_var_type
        clc
        rts

_pop_for_fail:
        sec
        rts

peek_for_frame:
        lda for_sp
        beq _peek_for_fail
        tax
        dex
        lda for_stack_id,x
        sta current_for_id
        lda for_stack_var_data_lo,x
        sta current_for_var_data_lo
        lda for_stack_var_data_hi,x
        sta current_for_var_data_hi
        lda for_stack_var_type,x
        sta current_for_var_type
        clc
        rts

_peek_for_fail:
        sec
        rts

push_do_frame:
        ldx do_sp
        cpx #DO_STACK_MAX
        bcs _push_do_fail
        lda current_do_id
        sta do_stack_id,x
        inc do_sp
        clc
        rts

_push_do_fail:
        sec
        rts

pop_do_frame:
        lda do_sp
        beq _pop_do_fail
        dec do_sp
        ldx do_sp
        lda do_stack_id,x
        sta current_do_id
        clc
        rts

_pop_do_fail:
        sec
        rts

peek_do_frame:
        lda do_sp
        beq _peek_do_fail
        tax
        dex
        lda do_stack_id,x
        sta current_do_id
        clc
        rts

_peek_do_fail:
        sec
        rts

alloc_if_labels:
        lda if_label_next_lo
        sta if_true_lo
        lda if_label_next_hi
        sta if_true_hi
        jsr inc_if_label_next

        lda if_label_next_lo
        sta if_skip_lo
        lda if_label_next_hi
        sta if_skip_hi
        jsr inc_if_label_next

        lda if_label_next_lo
        sta if_end_lo
        lda if_label_next_hi
        sta if_end_hi
        jsr inc_if_label_next

        lda if_label_next_lo
        sta if_else_lo
        lda if_label_next_hi
        sta if_else_hi
        jsr inc_if_label_next

        lda if_label_next_lo
        sta if_tmp_lo
        lda if_label_next_hi
        sta if_tmp_hi
        jsr inc_if_label_next
        rts

inc_if_label_next:
        inc if_label_next_lo
        bne +
        inc if_label_next_hi
+       rts

alloc_array_ok_label:
        lda array_label_next_lo
        sta array_ok_lo
        lda array_label_next_hi
        sta array_ok_hi
        inc array_label_next_lo
        bne +
        inc array_label_next_hi
+       rts

alloc_on_label:
        lda on_label_next_lo
        sta on_label_lo
        lda on_label_next_hi
        sta on_label_hi
        inc on_label_next_lo
        bne +
        inc on_label_next_hi
+       rts

push_if_labels:
        ldx if_sp
        cpx #IF_STACK_MAX
        bcs _push_if_fail
        lda if_true_lo
        sta if_stack_true_lo,x
        lda if_true_hi
        sta if_stack_true_hi,x
        lda if_skip_lo
        sta if_stack_skip_lo,x
        lda if_skip_hi
        sta if_stack_skip_hi,x
        lda if_end_lo
        sta if_stack_end_lo,x
        lda if_end_hi
        sta if_stack_end_hi,x
        lda if_else_lo
        sta if_stack_else_lo,x
        lda if_else_hi
        sta if_stack_else_hi,x
        lda if_tmp_lo
        sta if_stack_tmp_lo,x
        lda if_tmp_hi
        sta if_stack_tmp_hi,x
        inc if_sp
        clc
        rts

_push_if_fail:
        sec
        rts

pop_if_labels:
        lda if_sp
        beq _pop_if_fail
        dec if_sp
        ldx if_sp
        lda if_stack_tmp_hi,x
        sta if_tmp_hi
        lda if_stack_tmp_lo,x
        sta if_tmp_lo
        lda if_stack_end_hi,x
        sta if_end_hi
        lda if_stack_end_lo,x
        sta if_end_lo
        lda if_stack_else_hi,x
        sta if_else_hi
        lda if_stack_else_lo,x
        sta if_else_lo
        lda if_stack_skip_hi,x
        sta if_skip_hi
        lda if_stack_skip_lo,x
        sta if_skip_lo
        lda if_stack_true_hi,x
        sta if_true_hi
        lda if_stack_true_lo,x
        sta if_true_lo
        clc
        rts

_pop_if_fail:
        sec
        rts

emit_generated_header:
        ldx backend_mode
        bne _emit_generated_header_bin
        jsr emit_tmpl
        .word out_rtlevel_pre
        lda rt_level
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl
        .word out_gfxflag_pre
        lda gfx_used
        jsr out_hex_byte
        jsr out_cr
_emit_header_text:
        jsr emit_tmpl
        .word out_rtpb_pre
        lda prog_base_hi
        jsr out_hex_byte
        jsr emit_tmpl
        .word out_rtpb_post
        jsr emit_tmpl
        .word out_header_pre
        lda prog_base_hi
        jsr out_hex_byte
        jsr emit_tmpl_done
        .word out_header_post

_emit_generated_header_bin:
        ; program header at progbase: start, varheapend, datastart, dataend,
        ; strroots, fltinit vectors (6 words); start label follows them
        cpx #BK_EMIT
        beq _emit_header_vectors
        lda #16
        jmp bin_add_pc

_emit_header_vectors:
        lda #$10                ; start = progbase + $10
        jsr bin_write_byte
        lda prog_base_hi
        jsr bin_write_byte
        lda var_heap_next_lo
        jsr bin_write_byte
        lda var_heap_next_hi
        jsr bin_write_byte
        lda datastart_addr
        jsr bin_write_byte
        lda datastart_addr+1
        jsr bin_write_byte
        lda dataend_addr
        jsr bin_write_byte
        lda dataend_addr+1
        jsr bin_write_byte
        lda strroots_addr
        jsr bin_write_byte
        lda strroots_addr+1
        jsr bin_write_byte
        lda fltinit_addr
        jsr bin_write_byte
        lda fltinit_addr+1
        jsr bin_write_byte
        lda linetab_addr
        jsr bin_write_byte
        lda linetab_addr+1
        jsr bin_write_byte
        lda gfx_used
        jsr bin_write_byte
        lda #0
        jmp bin_write_byte

emit_generated_tail:
        jsr emit_tmpl
        .word out_tail
        jsr emit_varheapend
        jsr emit_string_pool
        jsr emit_data_table
        jsr emit_string_roots
        jsr emit_line_number_tab
        jsr emit_flt_table
        jsr emit_for_storage
        lda gfx_used            ; 640x200 screen codes live at
        bne _esg_gfx            ; $c000, so graphics programs stop
        jsr emit_tmpl_done      ; there; others may run to $d000
        .word out_size_guard
_esg_gfx:
        jsr emit_tmpl_done
        .word out_size_guard_gfx

emit_flt_table:
        ldx backend_mode
        beq _emit_flt_text
        lda bin_pc
        sta fltinit_addr
        lda bin_pc+1
        sta fltinit_addr+1
_emit_flt_text:
        jsr emit_tmpl
        .word out_fltinit_label
        lda #0
        sta root_emit_idx
_emit_flt_loop:
        lda root_emit_idx
        cmp flt_lit_count
        bcs _emit_flt_term
        tax
        lda flt_lit_addr_lo,x
        sta number_lo
        lda flt_lit_addr_hi,x
        sta number_hi
        lda flt_lit_sid,x
        sta current_string_id
        jsr emit_tmpl
        .word out_word_hex_prefix
        jsr out_hex_word_number
        jsr out_cr
        jsr emit_tmpl
        .word out_data_word_prefix
        jsr out_string_ref
        jsr out_cr
        inc root_emit_idx
        bra _emit_flt_loop
_emit_flt_term:
        lda #0
        sta number_lo
        sta number_hi
        jsr emit_tmpl
        .word out_word_hex_prefix
        jsr out_hex_word_number
        jsr out_cr
        jsr emit_tmpl
        .word out_word_hex_prefix
        jsr out_hex_word_number
        jsr out_cr
        jsr out_cr
        rts

emit_varheapend:
        ldx backend_mode
        beq +
        rts                     ; binary: value goes into the header vector
+       lda #<out_varheapend_def
        ldy #>out_varheapend_def
        jsr out_zstr
        lda var_heap_next_hi
        jsr out_hex_byte
        lda var_heap_next_lo
        jsr out_hex_byte
        jsr out_cr
        jsr out_cr
        rts

emit_for_storage:
        lda for_label_next
        bne +
        rts
+       ldx backend_mode
        beq _emit_for_storage_text
        lda bin_pc
        sta for_storage_addr
        lda bin_pc+1
        sta for_storage_addr+1
_emit_for_storage_text:
        jsr emit_tmpl
        .word out_for_storage_header
        lda #0
        sta for_storage_idx

_emit_for_storage_loop:
        lda for_storage_idx
        cmp for_label_next
        bcs _emit_for_storage_done
        sta current_for_id
        jsr out_forend_ref
        jsr emit_tmpl
        .word out_for_word_storage
        jsr out_forstep_ref
        jsr emit_tmpl
        .word out_for_word_storage
        inc for_storage_idx
        bra _emit_for_storage_loop

_emit_for_storage_done:
        jsr out_cr
        rts

emit_data_table:
        ldx backend_mode
        beq +
        lda bin_pc
        sta datastart_addr
        lda bin_pc+1
        sta datastart_addr+1
+       lda #<out_data_table_start
        ldy #>out_data_table_start
        jsr out_zstr
        lda #0
        sta data_emit_idx

_emit_data_table_loop:
        lda data_emit_idx
        cmp data_count
        bcs _emit_data_table_done
        jsr emit_data_labels_for_current_index
        jsr emit_tmpl
        .word out_data_byte_prefix
        ldx data_emit_idx
        lda data_table_type,x
        jsr out_hex_byte
        ldx data_emit_idx
        lda data_table_type,x
        cmp #DATA_TYPE_STRING
        beq _emit_data_string_record

        jsr emit_tmpl
        .word out_data_byte_sep
        ldx data_emit_idx
        lda data_table_lo,x
        jsr out_hex_byte
        jsr emit_tmpl
        .word out_data_byte_sep
        ldx data_emit_idx
        lda data_table_hi,x
        jsr out_hex_byte
        jsr out_cr
        inc data_emit_idx
        bra _emit_data_table_loop

_emit_data_string_record:
        jsr out_cr
        jsr emit_tmpl
        .word out_data_word_prefix
        ldx data_emit_idx
        lda data_table_lo,x
        sta current_string_id
        jsr out_string_ref
        jsr out_cr
        inc data_emit_idx
        bra _emit_data_table_loop

_emit_data_table_done:
        ldx backend_mode
        beq +
        lda bin_pc
        sta dataend_addr
        lda bin_pc+1
        sta dataend_addr+1
+       lda #<out_data_table_end
        ldy #>out_data_table_end
        jsr out_zstr
        rts

; line-number -> address table for FGOTO/FGOSUB: "linetab:" then a
; word count and count (line#, address) word pairs. Programs without
; FGOTO/FGOSUB get just a zero count so the header vector always
; resolves. Text rows reference l#### labels; the native path writes
; the recorded line addresses directly.
emit_line_number_tab:
        ldx backend_mode
        beq _elt_text
        lda bin_pc              ; both native passes record the address
        sta linetab_addr
        lda bin_pc+1
        sta linetab_addr+1
        cpx #BK_EMIT
        beq _elt_emit
        lda #2                  ; sizing pass: count word...
        jsr bin_add_pc
        lda fgoto_used
        beq _elt_done
        lda line_count          ; ...plus four bytes per line
        sta elt_i
        lda line_count+1
        sta elt_i+1
_elt_size_loop:
        lda elt_i
        ora elt_i+1
        beq _elt_done
        lda #4
        jsr bin_add_pc
        lda elt_i
        bne +
        dec elt_i+1
+       dec elt_i
        bra _elt_size_loop
_elt_done:
        rts
_elt_emit:
        lda fgoto_used
        bne +
        lda #0
        jsr bin_write_byte
        lda #0
        jmp bin_write_byte
+       lda line_count
        jsr bin_write_byte
        lda line_count+1
        jsr bin_write_byte
        jsr lf_rst
_elt_emit_loop:
        jsr lf_atend
        beq _elt_done
        lda #0
        jsr lf_read
        jsr bin_write_byte
        lda #1
        jsr lf_read
        jsr bin_write_byte
        lda #2
        jsr lf_read
        jsr bin_write_byte
        lda #3
        jsr lf_read
        jsr bin_write_byte
        jsr lf_next
        bra _elt_emit_loop
_elt_text:
        jsr emit_tmpl
        .word out_linetab_label
        lda fgoto_used
        bne +
        jsr emit_tmpl
        .word out_word_pre
        lda #0
        jsr out_hex_byte
        lda #0                  ; out_hex_byte returns the nibble char
        jsr out_hex_byte
        jmp out_cr
+       jsr emit_tmpl
        .word out_word_pre
        lda line_count+1
        jsr out_hex_byte
        lda line_count
        jsr out_hex_byte
        jsr out_cr
        jsr lf_rst
_elt_text_loop:
        jsr lf_atend
        beq _elt_text_done
        jsr emit_tmpl
        .word out_word_pre
        lda #1
        jsr lf_read
        jsr out_hex_byte
        lda #0
        jsr lf_read
        jsr out_hex_byte
        jsr emit_tmpl
        .word out_lineref_sep
        lda #1
        jsr lf_read
        jsr out_hex_byte
        lda #0
        jsr lf_read
        jsr out_hex_byte
        jsr out_cr
        jsr lf_next
        bra _elt_text_loop
_elt_text_done:
        rts

elt_i:
        .byte 0, 0

emit_string_roots:
        ldx backend_mode
        beq +
        lda bin_pc
        sta strroots_addr
        lda bin_pc+1
        sta strroots_addr+1
+       lda #<out_strroots_start
        ldy #>out_strroots_start
        jsr out_zstr
        lda #0
        sta root_emit_idx

_emit_string_roots_loop:
        lda root_emit_idx
        cmp sym_count
        bcs _emit_string_roots_done
        tax
        lda sym_type,x
        cmp #VAR_TYPE_STRING
        bne _emit_string_roots_next
        lda sym_kind,x
        cmp #VAR_KIND_SCALAR
        beq _emit_string_root_scalar
        cmp #VAR_KIND_ARRAY1
        beq _emit_string_root_array
        bra _emit_string_roots_next

_emit_string_root_scalar:
        jsr emit_root_name_comment
        ldx root_emit_idx
        lda sym_data_lo,x
        sta number_lo
        lda sym_data_hi,x
        sta number_hi
        lda #2
        sta work2_lo
        lda #0
        sta work2_hi
        jsr emit_string_root_record
        bra _emit_string_roots_next

_emit_string_root_array:
        jsr emit_root_name_comment
        jsr load_root_array_dims
        bcs _emit_string_roots_next
        jsr compute_array_element_count
        bcs _emit_string_roots_next
        asl work2_lo
        rol work2_hi
        ldx root_emit_idx
        lda sym_data_lo,x
        sta number_lo
        lda sym_data_hi,x
        sta number_hi
        jsr emit_string_root_record

_emit_string_roots_next:
        inc root_emit_idx
        bra _emit_string_roots_loop

_emit_string_roots_done:
        lda #0
        sta number_lo
        sta number_hi
        sta work2_lo
        sta work2_hi
        jsr emit_string_root_record
        jsr out_cr
        rts

; text mode only: tag each root record with its variable's name so
; the emitted table is self-describing (comments cost nothing binary)
emit_root_name_comment:
        ldx backend_mode
        beq +
        rts
+       lda #';'
        jsr CC_CHROUT
        ldx root_emit_idx
        lda sym_name_1,x
        jsr CC_CHROUT
        ldx root_emit_idx
        lda sym_name_2,x
        beq +
        jsr CC_CHROUT
+       ldx root_emit_idx
        lda sym_kind,x
        beq +
        lda #'('
        jsr CC_CHROUT
+       jsr out_cr
        rts

load_root_array_dims:
        ldx root_emit_idx
        lda sym_rank,x
        sta array_rank
        lda sym_dim0_lo,x
        sta array_dims_lo+0
        lda sym_dim0_hi,x
        sta array_dims_hi+0
        lda sym_dim1_lo,x
        sta array_dims_lo+1
        lda sym_dim1_hi,x
        sta array_dims_hi+1
        lda sym_dim2_lo,x
        sta array_dims_lo+2
        lda sym_dim2_hi,x
        sta array_dims_hi+2
        lda sym_dim3_lo,x
        sta array_dims_lo+3
        lda sym_dim3_hi,x
        sta array_dims_hi+3
        lda sym_dim4_lo,x
        sta array_dims_lo+4
        lda sym_dim4_hi,x
        sta array_dims_hi+4
        lda sym_dim5_lo,x
        sta array_dims_lo+5
        lda sym_dim5_hi,x
        sta array_dims_hi+5
        clc
        rts

emit_string_root_record:
        jsr emit_tmpl
        .word out_data_byte_prefix
        lda number_lo
        jsr out_hex_byte
        jsr emit_tmpl
        .word out_data_byte_sep
        lda number_hi
        jsr out_hex_byte
        jsr emit_tmpl
        .word out_data_byte_sep
        lda work2_lo
        jsr out_hex_byte
        jsr emit_tmpl
        .word out_data_byte_sep
        lda work2_hi
        jsr out_hex_byte
        jsr out_cr
        rts

emit_string_pool:
        lda string_count
        bne +
        rts
+       lda #<out_string_pool_header
        ldy #>out_string_pool_header
        jsr out_zstr
        lda #0
        sta string_emit_idx

_emit_string_pool_loop:
        lda string_emit_idx
        cmp string_count
        bcs _emit_string_pool_done
        sta current_string_id
        jsr out_string_ref
        jsr emit_label_suffix
        ldx string_emit_idx
        jsr stroffload

_emit_string_byte_loop:
        jsr string_pool_read_byte
        sta byte_value
        jsr emit_tmpl
        .word out_data_byte_prefix
        lda byte_value
        jsr out_hex_byte
        jsr out_cr
        lda byte_value
        beq _emit_string_next
        jsr inc_string_read
        bra _emit_string_byte_loop

_emit_string_next:
        inc string_emit_idx
        bra _emit_string_pool_loop

_emit_string_pool_done:
        jsr out_cr
        rts

emit_data_labels_for_current_index:
        lda #0
        sta data_line_emit_idx

_emit_data_label_loop:
        lda data_line_emit_idx
        cmp data_line_count
        bcs _emit_data_label_done
        tax
        lda data_line_index,x
        cmp data_emit_idx
        bne _emit_data_label_next
        lda data_line_lo,x
        sta number_lo
        lda data_line_hi,x
        sta number_hi
        jsr out_data_line_ref
        jsr emit_label_suffix

_emit_data_label_next:
        inc data_line_emit_idx
        bra _emit_data_label_loop

_emit_data_label_done:
        rts

; ---- overlay planner: during the native size pass, track where the
; program could be cut (line boundaries with no open FOR/DO/BEGIN)
; and how many window-sized segments it would need. Informational in
; milestone 1: the plan is reported when a program exceeds the
; window; emission is unchanged. See docs/overlays.md.
seg_plan_line:
        lda seg_base_hi         ; first line: open segment 0, capture
        bne _spl_run            ; the window (gfx cap $c000 else $d000,
        lda #$5a                ; minus progbase + resident allowance)
        ldx gfx_used
        beq +
        lda #$4a
+       sta seg_win_hi
        lda bin_pc
        sta seg_base_lo
        lda bin_pc+1
        sta seg_base_hi
_spl_run:
        sec                     ; running segment size (hi vs window)
        lda bin_pc+1
        sbc seg_base_hi
        cmp seg_win_hi
        bcc _spl_elig
        lda seg_has_elig        ; cut at the last eligible boundary
        beq _spl_elig           ; (M2 flags a structure too big here)
        lda seg_elig_lo
        sta seg_base_lo
        lda seg_elig_hi
        sta seg_base_hi
        lda #0
        sta seg_has_elig
        inc seg_count
_spl_elig:
        lda for_sp              ; a legal cut point: no open structure
        ora do_sp
        ora begin_sp
        bne _spl_done
        lda bin_pc
        sta seg_elig_lo
        lda bin_pc+1
        sta seg_elig_hi
        lda #1
        sta seg_has_elig
_spl_done:
        rts

emit_line_label:
        ldx backend_mode
        bne _emit_line_label_bin
        lda #'l'
        jsr CC_CHROUT
        lda line_no_hi
        jsr out_hex_byte
        lda line_no_lo
        jsr out_hex_byte
        lda #':'
        jsr CC_CHROUT
        jsr out_cr
        rts

_emit_line_label_bin:
        lda backend_mode
        cmp #BK_SIZE
        bne +
        jsr seg_plan_line       ; overlay planner rides the size pass
+       jsr pool_ptr_save
        lda lea_base
        sta source_ptr
        lda lea_base+1
        sta source_ptr+1
        ldz #2                  ; record fields 2/3 = binary address
        lda bin_pc
        sta [source_ptr],z
        inz
        lda bin_pc+1
        sta [source_ptr],z
        ldz #0                  ; ambient-Z convention: the native
        jsr pool_ptr_restore    ; emitter far-reads depend on Z = 0
        clc                     ; advance one record
        lda lea_base
        adc #4
        sta lea_base
        bcc +
        inc lea_base+1
+       rts

; reset the address-append walker (per pass); returns with A = 0 for
; the reset chain it sits in
lea_rst:
        lda #<LINETAB_B4
        sta lea_base
        lda #>LINETAB_B4
        sta lea_base+1
        lda #0
        rts

lea_base:
        .byte 0, 0

; keep curline current for EL when any TRAP exists in the program;
; also run the collision dispatcher at line starts when armed anywhere
emit_line_track:
        lda trap_used
        bne +
        rts
+       lda #<out_lda_imm_hex
        ldy #>out_lda_imm_hex
        jsr out_zstr
        lda line_no_lo
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl
        .word out_sta_curline
        jsr emit_tmpl
        .word out_lda_imm_hex
        lda line_no_hi
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl_done
        .word out_sta_curline_1

out_label_from_number:
        ldx backend_mode
        beq _out_label_number_text
        ; resolve the BASIC line number in number_lo/hi to its binary address
        lda number_lo
        sta lsrch_lo
        lda number_hi
        sta lsrch_hi
        jsr linefind
        bcc _out_label_number_bad
        lda #2
        jsr lf_read
        sta pending_value
        lda #3
        jsr lf_read
        sta pending_value+1
        rts
_out_label_number_bad:
        lda #3
        sta backend_error
        rts
_out_label_number_text:
        lda #'l'
        jsr out_char
        jsr out_hex_word_number
        rts

out_data_line_ref:
        ldx backend_mode
        beq _out_data_line_text
        ; find the data-line slot for the line number in number_lo/hi
        ldx #0
_out_data_line_scan:
        cpx data_line_count
        beq _out_data_line_bad
        lda data_line_lo,x
        cmp number_lo
        bne _out_data_line_next
        lda data_line_hi,x
        cmp number_hi
        beq _out_data_line_found
_out_data_line_next:
        inx
        bra _out_data_line_scan
_out_data_line_found:
        lda pending_kind
        beq _out_data_line_def
        lda data_line_addr_lo,x
        sta pending_value
        lda data_line_addr_hi,x
        sta pending_value+1
        rts
_out_data_line_def:
        lda bin_pc
        sta data_line_addr_lo,x
        lda bin_pc+1
        sta data_line_addr_hi,x
        rts
_out_data_line_bad:
        lda #4
        sta backend_error
        rts
_out_data_line_text:
        lda #'d'
        jsr out_char
        lda #'a'
        jsr out_char
        lda #'t'
        jsr out_char
        lda #'a'
        jsr out_char
        jsr out_hex_word_number
        rts

out_string_ref:
        ldx backend_mode
        beq _out_string_ref_text
        ldx current_string_id
        lda pending_kind
        beq _out_string_ref_def
        lda string_addr_lo,x
        sta pending_value
        lda string_addr_hi,x
        sta pending_value+1
        rts
_out_string_ref_def:
        lda bin_pc
        sta string_addr_lo,x
        lda bin_pc+1
        sta string_addr_hi,x
        rts
_out_string_ref_text:
        lda #'s'
        jsr out_char
        lda #'t'
        jsr out_char
        lda #'r'
        jsr out_char
        lda #0
        jsr out_hex_byte
        lda current_string_id
        jsr out_hex_byte
        rts

emit_chout_imm:
        sta byte_value
        jsr emit_tmpl
        .word out_lda_imm_hex
        lda byte_value
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl_done
        .word out_jsr_chout

emit_print_string_current:
        jsr emit_set_rtptr_string_current
        jsr emit_tmpl_done
        .word out_jsr_printstr

emit_set_rtptr_string_current:
        jsr emit_tmpl
        .word out_lda_label_lo_imm
        jsr out_string_ref
        jsr out_cr
        jsr emit_tmpl
        .word out_sta_rtptr
        jsr emit_tmpl
        .word out_lda_label_hi_imm
        jsr out_string_ref
        jsr out_cr
        jsr emit_tmpl_done
        .word out_sta_rtptr_1

emit_load_string_ref_to_expr:
        jsr emit_tmpl
        .word out_lda_label_lo_imm
        jsr out_string_ref
        jsr out_cr
        jsr emit_tmpl
        .word out_sta_exprlo
        jsr emit_tmpl
        .word out_lda_label_hi_imm
        jsr out_string_ref
        jsr out_cr
        jsr emit_tmpl_done
        .word out_sta_exprhi

emit_string_literal_to_heap_expr:
        jsr emit_tmpl
        .word out_lda_label_lo_imm
        jsr out_string_ref
        jsr out_cr
        jsr emit_tmpl
        .word out_sta_rtptr
        jsr emit_tmpl
        .word out_lda_label_hi_imm
        jsr out_string_ref
        jsr out_cr
        jsr emit_tmpl
        .word out_sta_rtptr_1
        jsr emit_tmpl_done
        .word out_jsr_strfromlit

emit_print_string_var_current:
        jsr emit_load_var
        ; FALLTHROUGH

emit_print_string_expr:
        jsr emit_tmpl_done
        .word out_jsr_printheapstr

emit_copy_string_expr:
        jsr emit_tmpl_done
        .word out_jsr_strcopyexpr

emit_concat_strings:
        jsr emit_tmpl_done
        .word out_jsr_concatstr

emit_string_len_expr:
        jsr emit_tmpl_done
        .word out_jsr_strlenexpr

emit_string_from_int:
        jsr emit_tmpl_done
        .word out_jsr_strfromint

emit_val_string_expr:
        jsr emit_tmpl_done
        .word out_jsr_valstr

emit_string_temp_mark:
        jsr emit_tmpl_done
        .word out_jsr_strmark

emit_string_temp_release:
        jsr emit_tmpl_done
        .word out_jsr_strrelease

emit_string_left:
        jsr emit_set_strarg1_one
        bra emit_string_mid

emit_string_right:
        jsr emit_tmpl_done
        .word out_jsr_strright

emit_string_mid:
        jsr emit_tmpl_done
        .word out_jsr_strsub

emit_string_mid_tail:
        lda #$FF
        sta number_lo
        lda #0
        sta number_hi
        jsr emit_load_number
        bra emit_string_mid

emit_set_strarg1_one:
        jsr emit_tmpl
        .word out_lda_imm_hex
        lda #1
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl
        .word out_sta_strarg1lo
        jsr emit_tmpl
        .word out_lda_imm_hex
        lda #0
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl_done
        .word out_sta_strarg1hi

emit_save_expr_to_strarg1:
        jsr emit_tmpl
        .word out_lda_exprlo
        jsr emit_tmpl
        .word out_sta_strarg1lo
        jsr emit_tmpl
        .word out_lda_exprhi
        jsr emit_tmpl_done
        .word out_sta_strarg1hi

emit_print_comma:
        jsr emit_tmpl_done
        .word out_jsr_printcomma

emit_print_uint_expr:
        jsr emit_tmpl_done
        .word out_jsr_printuint

emit_print_char_expr:
        jsr emit_tmpl
        .word out_lda_exprlo
        jsr emit_tmpl_done
        .word out_jsr_chout

emit_load_number:
        jsr emit_tmpl
        .word out_lda_imm_hex
        lda number_lo
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl
        .word out_sta_exprlo

        jsr emit_tmpl
        .word out_lda_imm_hex
        lda number_hi
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl_done
        .word out_sta_exprhi

; integer-semantics load: float variables convert through qint, so FOR,
; READ, INPUT, and GET keep their 16-bit machinery
emit_load_var:
        jsr emit_set_varptr_current
        ldx current_sym_index
        lda sym_type,x
        cmp #VAR_TYPE_FLOAT
        beq _emit_load_var_float
        jsr emit_tmpl_done
        .word out_jsr_loadintvar

_emit_load_var_float:
        jsr emit_tmpl
        .word out_jsr_floadvar
        jsr emit_tmpl_done
        .word out_jsr_qint

; typed load for expression factors: float variables land in FAC
emit_load_var_typed:
        jsr emit_set_varptr_current
        ldx current_sym_index
        lda sym_type,x
        cmp #VAR_TYPE_FLOAT
        beq _emit_load_var_typed_f
        jsr emit_tmpl_done
        .word out_jsr_loadintvar

_emit_load_var_typed_f:
        jsr emit_tmpl
        .word out_jsr_floadvar
        lda #1
        sta expr_type
        rts

; integer-source store: float variables convert through float16
emit_store_var:
        lda assign_var_data_lo
        sta current_var_data_lo
        lda assign_var_data_hi
        sta current_var_data_hi
        jsr emit_set_varptr_current
        lda assign_var_type
        cmp #VAR_TYPE_FLOAT
        beq _emit_store_var_float
        jsr emit_store_ptr
        rts

_emit_store_var_float:
        jsr emit_tmpl
        .word out_jsr_float16
        jsr emit_tmpl_done
        .word out_jsr_fstorevar

; float-source store (assignment right side already in FAC)
emit_store_var_fac:
        lda assign_var_data_lo
        sta current_var_data_lo
        lda assign_var_data_hi
        sta current_var_data_hi
        jsr emit_set_varptr_current
        jsr emit_tmpl_done
        .word out_jsr_fstorevar

emit_load_ptr:
        jsr emit_tmpl_done
        .word out_jsr_loadintvar

emit_store_ptr:
        jsr emit_tmpl_done
        .word out_jsr_storeintvar

emit_read_int:
        jsr emit_tmpl_done
        .word out_jsr_readint

emit_read_string:
        jsr emit_tmpl_done
        .word out_jsr_readstr

emit_input_line:
        lda io_from_file
        bne _emit_input_line_file
        jsr emit_tmpl_done
        .word out_jsr_inputline
_emit_input_line_file:
        jsr emit_tmpl_done
        .word out_jsr_fioreadline

emit_input_int:
        jsr emit_tmpl_done
        .word out_jsr_inputint

emit_input_string:
        lda input_raw_mode      ; LINE INPUT: the whole line, verbatim
        bne _emit_input_raw
        jsr emit_tmpl_done
        .word out_jsr_inputstr
_emit_input_raw:
        jsr emit_tmpl_done
        .word out_jsr_inputraw

emit_get_key:
        lda get_blocking
        beq _emit_get_key_poll
        jsr emit_tmpl_done
        .word out_jsr_getkeyw
_emit_get_key_poll:
        lda io_from_file
        bne _emit_get_key_file
        jsr emit_tmpl_done
        .word out_jsr_getkey
_emit_get_key_file:
        jsr emit_tmpl_done
        .word out_jsr_fiogetbyte

emit_get_string:
        lda get_blocking
        beq _emit_get_string_poll
        jsr emit_tmpl_done
        .word out_jsr_getstrw
_emit_get_string_poll:
        lda io_from_file
        bne _emit_get_string_file
        jsr emit_tmpl_done
        .word out_jsr_getstr
_emit_get_string_file:
        jsr emit_tmpl_done
        .word out_jsr_fiogetstr

emit_restore_data_line:
        jsr emit_tmpl
        .word out_lda_label_lo_imm
        jsr out_data_line_ref
        jsr out_cr
        jsr emit_tmpl
        .word out_sta_dataptrlo
        jsr emit_tmpl
        .word out_lda_label_hi_imm
        jsr out_data_line_ref
        jsr out_cr
        jsr emit_tmpl_done
        .word out_sta_dataptrhi

emit_save_arrayptr:
        jsr emit_tmpl_done
        .word out_save_arrayptr

emit_restore_arrayptr:
        jsr emit_tmpl_done
        .word out_restore_arrayptr

emit_array_bounds_check:
        jsr alloc_array_ok_label
        jsr emit_tmpl
        .word out_array_check_start
        jsr out_array_nonneg_ref
        jsr out_cr
        jsr emit_tmpl
        .word out_jmp_arraybounds
        jsr out_array_nonneg_ref
        jsr emit_label_suffix
        jsr emit_tmpl
        .word out_cmp_exprhi_imm
        lda number_hi
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl
        .word out_bcc_label
        jsr out_array_ok_ref
        jsr out_cr
        jsr emit_tmpl
        .word out_beq_label
        jsr out_array_hieq_ref
        jsr out_cr
        jsr emit_tmpl
        .word out_jmp_arraybounds
        jsr out_array_hieq_ref
        jsr emit_label_suffix
        jsr emit_tmpl
        .word out_cmp_exprlo_imm
        lda number_lo
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl
        .word out_bcc_label
        jsr out_array_ok_ref
        jsr out_cr
        jsr emit_tmpl
        .word out_jmp_arraybounds
        jsr out_array_ok_ref
        bra emit_label_suffix

; varptr+2/+3 (bank/megabyte) are set once by rtinit and preserved by every
; runtime path, so per-access setup only writes the 16-bit bank-1 offset
emit_set_varptr_current:
        jsr emit_tmpl
        .word out_lda_imm_hex
        lda current_var_data_lo
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl
        .word out_sta_varptr

        jsr emit_tmpl
        .word out_lda_imm_hex
        lda current_var_data_hi
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl_done
        .word out_sta_varptr_1

emit_set_arrayptr_current:
        ldx array_sym_index
        lda sym_type,x
        cmp #VAR_TYPE_FLOAT
        beq _emit_set_arrayptr_f
        jsr emit_tmpl
        .word out_array_index_shift
        bra _emit_set_arrayptr_add
_emit_set_arrayptr_f:
        jsr emit_tmpl
        .word out_array_index_shift5
_emit_set_arrayptr_add:
        jsr emit_tmpl
        .word out_adc_imm_hex
        lda current_var_data_lo
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl
        .word out_sta_varptr

        jsr emit_tmpl
        .word out_lda_exprhi
        jsr emit_tmpl
        .word out_adc_imm_hex
        lda current_var_data_hi
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl_done
        .word out_sta_varptr_1

emit_push_expr:
        jsr emit_tmpl_done
        .word out_push_expr

emit_move_expr_to_lhs:
        jsr emit_tmpl_done
        .word out_move_expr_to_lhs

; Decide whether the upcoming right-hand operand is a single numeric literal
; or scalar numeric variable, so the caller can skip the push/pop around it
; (loading such a factor cannot clobber lhslo/lhshi). X selects how much
; lookahead context must stay simple:
;   X=0  factor context (a following * or / belongs to the caller's loop)
;   X=1  term context: reject a following * or /
;   X=2  expression context: reject a following + - * /
; Returns carry clear when simple; line_idx is always restored.
probe_simple_rhs:
        stx probe_mode
        lda line_idx
        sta probe_saved_idx
        jsr line_skip_spaces
        jsr line_at_end
        bcs _probe_fail
        jsr line_peek
        cmp #'$'
        beq _probe_number
        cmp #'0'
        bcc _probe_not_number
        cmp #'9' + 1
        bcc _probe_number

_probe_not_number:
        jsr is_var_start
        bcs _probe_fail
        jsr line_get
        jsr parse_variable_with_first_char
        bcs _probe_fail
        lda var_type
        cmp #VAR_TYPE_INT
        bne _probe_fail
        jsr line_skip_spaces
        jsr line_at_end
        bcs _probe_ok
        jsr line_peek
        cmp #'('
        beq _probe_fail
        bra _probe_follower

_probe_number:
        jsr line_parse_number
        bcs _probe_fail
        jsr line_at_end
        bcs _probe_ok
        jsr line_peek
        cmp #'.'
        beq _probe_fail
        cmp #$65                ; ASCII 'e'
        beq _probe_fail
        cmp #$45                ; PETSCII 'e'
        beq _probe_fail
        jsr line_skip_spaces
        jsr line_at_end
        bcs _probe_ok
        jsr line_peek

_probe_follower:
        cmp #TOK_POW
        beq _probe_fail
        ldx probe_mode
        beq _probe_ok
        cmp #TOK_MUL
        beq _probe_fail
        cmp #TOK_DIV
        beq _probe_fail
        cpx #2
        bne _probe_ok
        cmp #TOK_PLUS
        beq _probe_fail
        cmp #TOK_MINUS
        beq _probe_fail

_probe_ok:
        lda probe_saved_idx
        sta line_idx
        clc
        rts

_probe_fail:
        lda probe_saved_idx
        sta line_idx
        sec
        rts

emit_pop_lhs:
        jsr emit_tmpl_done
        .word out_pop_lhs

emit_add_lhs_expr:
        jsr emit_tmpl_done
        .word out_add_lhs_expr

emit_sub_lhs_expr:
        jsr emit_tmpl_done
        .word out_sub_lhs_expr

emit_mul_lhs_expr:
        jsr emit_tmpl_done
        .word out_jsr_mul16

emit_neg_expr:
        jsr emit_tmpl_done
        .word out_neg_expr

emit_abs_expr:
        jsr alloc_if_tmp_label
        jsr emit_tmpl
        .word out_lda_exprhi
        lda #<out_bpl_label
        ldy #>out_bpl_label
        jsr emit_branch_if_tmp
        jsr emit_neg_expr
        jsr emit_if_tmp_label_def
        rts

emit_sgn_expr:
        jsr alloc_if_tmp_label
        jsr alloc_on_label
        lda on_label_lo
        sta on_done_lo
        lda on_label_hi
        sta on_done_hi
        jsr alloc_on_label

        jsr emit_tmpl
        .word out_lda_exprlo
        jsr emit_tmpl
        .word out_ora_exprhi
        lda #<out_beq_label
        ldy #>out_beq_label
        jsr emit_branch_if_tmp

        jsr emit_tmpl
        .word out_lda_exprhi
        jsr emit_tmpl
        .word out_bmi_label
        jsr out_onnext_ref
        jsr out_cr

        lda #1
        sta number_lo
        lda #0
        sta number_hi
        jsr emit_load_number
        jsr emit_jmp_ondone

        jsr emit_onnext_label_def
        lda #$FF
        sta number_lo
        sta number_hi
        jsr emit_load_number
        jsr emit_jmp_ondone

        jsr emit_if_tmp_label_def
        lda #0
        sta number_lo
        sta number_hi
        jsr emit_load_number

        jsr emit_ondone_label_def
        rts

emit_not_expr:
        jsr alloc_on_label
        lda on_label_lo
        sta on_done_lo
        lda on_label_hi
        sta on_done_hi
        jsr alloc_on_label
        jsr emit_tmpl
        .word out_lda_exprlo
        jsr emit_tmpl
        .word out_ora_exprhi
        jsr emit_tmpl
        .word out_beq_label
        jsr out_onnext_ref
        jsr out_cr
        lda #0
        sta number_lo
        sta number_hi
        jsr emit_load_number
        jsr emit_jmp_ondone
        jsr emit_onnext_label_def
        lda #1
        sta number_lo
        lda #0
        sta number_hi
        jsr emit_load_number
        jsr emit_ondone_label_def
        rts

emit_fcompare_bool:
        lda #0
        sta expr_type
        lda cond_op
        cmp #COND_EQ
        beq _emit_fbool_eq
        cmp #COND_NE
        beq _emit_fbool_ne
        cmp #COND_LT
        beq _emit_fbool_lt
        cmp #COND_LE
        beq _emit_fbool_le
        cmp #COND_GT
        beq _emit_fbool_gt
        cmp #COND_GE
        beq _emit_fbool_ge
        rts
_emit_fbool_eq:
        jsr emit_tmpl_done
        .word out_jsr_fcmpeqb
_emit_fbool_ne:
        jsr emit_tmpl_done
        .word out_jsr_fcmpneb
_emit_fbool_lt:
        jsr emit_tmpl_done
        .word out_jsr_fcmpltb
_emit_fbool_le:
        jsr emit_tmpl_done
        .word out_jsr_fcmpleb
_emit_fbool_gt:
        jsr emit_tmpl_done
        .word out_jsr_fcmpgtb
_emit_fbool_ge:
        jsr emit_tmpl_done
        .word out_jsr_fcmpgeb

emit_compare_expr_to_bool:
        lda cond_op
        cmp #COND_EQ
        beq _emit_bool_cmp_eq
        cmp #COND_NE
        beq _emit_bool_cmp_ne
        cmp #COND_LT
        beq _emit_bool_cmp_lt
        cmp #COND_LE
        beq _emit_bool_cmp_le
        cmp #COND_GT
        beq _emit_bool_cmp_gt
        cmp #COND_GE
        beq _emit_bool_cmp_ge
        rts

_emit_bool_cmp_eq:
        lda #<out_jsr_cmpeq
        ldy #>out_jsr_cmpeq
        bra _emit_bool_cmp_call

_emit_bool_cmp_ne:
        lda #<out_jsr_cmpne
        ldy #>out_jsr_cmpne
        bra _emit_bool_cmp_call

_emit_bool_cmp_lt:
        lda #<out_jsr_cmplt
        ldy #>out_jsr_cmplt
        bra _emit_bool_cmp_call

_emit_bool_cmp_le:
        lda #<out_jsr_cmple
        ldy #>out_jsr_cmple
        bra _emit_bool_cmp_call

_emit_bool_cmp_gt:
        lda #<out_jsr_cmpgt
        ldy #>out_jsr_cmpgt
        bra _emit_bool_cmp_call

_emit_bool_cmp_ge:
        lda #<out_jsr_cmpge
        ldy #>out_jsr_cmpge

_emit_bool_cmp_call:
        jsr out_zstr
        jsr emit_store_a_to_expr_bool
        rts

emit_string_compare_to_bool:
        lda cond_op
        cmp #COND_EQ
        beq _emit_str_cmp_eq
        cmp #COND_NE
        beq _emit_str_cmp_ne
        cmp #COND_LT
        beq _emit_str_cmp_lt
        cmp #COND_LE
        beq _emit_str_cmp_le
        cmp #COND_GT
        beq _emit_str_cmp_gt
        cmp #COND_GE
        beq _emit_str_cmp_ge
        rts

_emit_str_cmp_eq:
        lda #<out_jsr_streq
        ldy #>out_jsr_streq
        bra _emit_str_cmp_call

_emit_str_cmp_ne:
        lda #<out_jsr_strne
        ldy #>out_jsr_strne
        bra _emit_str_cmp_call

_emit_str_cmp_lt:
        lda #<out_jsr_strlt
        ldy #>out_jsr_strlt
        bra _emit_str_cmp_call

_emit_str_cmp_le:
        lda #<out_jsr_strle
        ldy #>out_jsr_strle
        bra _emit_str_cmp_call

_emit_str_cmp_gt:
        lda #<out_jsr_strgt
        ldy #>out_jsr_strgt
        bra _emit_str_cmp_call

_emit_str_cmp_ge:
        lda #<out_jsr_strge
        ldy #>out_jsr_strge

_emit_str_cmp_call:
        jsr out_zstr
        jsr emit_store_a_to_expr_bool
        rts

emit_string_ref_compare_to_bool:
        lda cond_op
        cmp #COND_EQ
        beq _emit_strref_cmp_eq
        cmp #COND_NE
        beq _emit_strref_cmp_ne
        cmp #COND_LT
        beq _emit_strref_cmp_lt
        cmp #COND_LE
        beq _emit_strref_cmp_le
        cmp #COND_GT
        beq _emit_strref_cmp_gt
        cmp #COND_GE
        beq _emit_strref_cmp_ge
        rts

_emit_strref_cmp_eq:
        lda #<out_jsr_strrefeq
        ldy #>out_jsr_strrefeq
        bra _emit_strref_cmp_call

_emit_strref_cmp_ne:
        lda #<out_jsr_strrefne
        ldy #>out_jsr_strrefne
        bra _emit_strref_cmp_call

_emit_strref_cmp_lt:
        lda #<out_jsr_strreflt
        ldy #>out_jsr_strreflt
        bra _emit_strref_cmp_call

_emit_strref_cmp_le:
        lda #<out_jsr_strrefle
        ldy #>out_jsr_strrefle
        bra _emit_strref_cmp_call

_emit_strref_cmp_gt:
        lda #<out_jsr_strrefgt
        ldy #>out_jsr_strrefgt
        bra _emit_strref_cmp_call

_emit_strref_cmp_ge:
        lda #<out_jsr_strrefge
        ldy #>out_jsr_strrefge

_emit_strref_cmp_call:
        jsr out_zstr
        jsr emit_store_a_to_expr_bool
        rts

emit_expr_to_lhs:
        jsr emit_push_expr
        jsr emit_pop_lhs
        rts

emit_set_strarg1lo_imm:
        sta byte_value
        jsr emit_tmpl
        .word out_lda_imm_hex
        lda byte_value
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl_done
        .word out_sta_strarg1lo

emit_set_strarg1hi_imm:
        sta byte_value
        jsr emit_tmpl
        .word out_lda_imm_hex
        lda byte_value
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl_done
        .word out_sta_strarg1hi

emit_empty_string_compare:
        lda #VAR_KIND_SCALAR
        sta var_kind
        jsr resolve_var
        bcs _emit_empty_cmp_fail
        jsr emit_load_var
        jsr emit_string_len_expr
        lda byte_value
        bne _emit_empty_cmp_empty_left

        lda cond_op
        cmp #COND_EQ
        beq _emit_empty_cmp_len_eq_zero
        cmp #COND_NE
        beq _emit_empty_cmp_len_ne_zero
        cmp #COND_LT
        beq _emit_empty_cmp_false
        cmp #COND_LE
        beq _emit_empty_cmp_len_eq_zero
        cmp #COND_GT
        beq _emit_empty_cmp_len_ne_zero
        cmp #COND_GE
        beq _emit_empty_cmp_true
        bra _emit_empty_cmp_fail

_emit_empty_cmp_empty_left:
        lda cond_op
        cmp #COND_EQ
        beq _emit_empty_cmp_len_eq_zero
        cmp #COND_NE
        beq _emit_empty_cmp_len_ne_zero
        cmp #COND_LT
        beq _emit_empty_cmp_len_ne_zero
        cmp #COND_LE
        beq _emit_empty_cmp_true
        cmp #COND_GT
        beq _emit_empty_cmp_false
        cmp #COND_GE
        beq _emit_empty_cmp_len_eq_zero
        bra _emit_empty_cmp_fail

_emit_empty_cmp_len_eq_zero:
        lda #COND_EQ
        sta cond_op
        bra _emit_empty_cmp_len_zero

_emit_empty_cmp_len_ne_zero:
        lda #COND_NE
        sta cond_op

_emit_empty_cmp_len_zero:
        jsr emit_push_expr
        lda #0
        sta number_lo
        sta number_hi
        jsr emit_load_number
        jsr emit_pop_lhs
        jsr emit_compare_expr_to_bool
        clc
        rts

_emit_empty_cmp_true:
        lda #1
        sta number_lo
        lda #0
        sta number_hi
        jsr emit_load_number
        clc
        rts

_emit_empty_cmp_false:
        lda #0
        sta number_lo
        sta number_hi
        jsr emit_load_number
        clc
        rts

_emit_empty_cmp_fail:
        sec
        rts

emit_store_a_to_expr_bool:
        jsr emit_tmpl
        .word out_sta_exprlo
        jsr emit_tmpl
        .word out_lda_imm_hex
        lda #0
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl_done
        .word out_sta_exprhi

emit_bool_and_lhs_expr:
        jsr emit_tmpl_done
        .word out_and_lhs_expr

emit_bool_or_lhs_expr:
        jsr emit_tmpl_done
        .word out_or_lhs_expr

emit_expr_to_rtptr:
        jsr emit_tmpl_done
        .word out_expr_to_rtptr

emit_save_rtptr:
        jsr emit_tmpl_done
        .word out_save_rtptr

emit_restore_rtptr:
        jsr emit_tmpl_done
        .word out_restore_rtptr

emit_poke_expr_to_rtptr:
        lda bank_used
        beq +
        jsr emit_tmpl_done
        .word out_jsr_pokebk
+       jsr emit_tmpl
        .word out_poke_expr_to_rtptr
        rts

emit_wpoke_expr_to_rtptr:
        lda bank_used
        beq +
        jsr emit_tmpl_done
        .word out_jsr_wpokebk
+       jsr emit_tmpl
        .word out_wpoke_expr_to_rtptr
        rts

emit_peek_expr:
        lda bank_used
        beq +
        jsr emit_tmpl_done
        .word out_jsr_peekbk
+       jsr emit_tmpl
        .word out_peek_expr
        rts

emit_wpeek_expr:
        lda bank_used
        beq +
        jsr emit_tmpl_done
        .word out_jsr_wpeekbk
+       jsr emit_tmpl
        .word out_wpeek_expr
        rts

emit_store_expr_to_forend:
        jsr emit_tmpl
        .word out_lda_exprlo
        jsr emit_tmpl
        .word out_sta_label
        jsr out_forend_ref
        jsr out_cr
        jsr emit_tmpl
        .word out_lda_exprhi
        jsr emit_tmpl
        .word out_sta_label
        jsr out_forend_ref
        jsr out_plus_one_cr
        rts

emit_store_expr_to_forstep:
        jsr emit_tmpl
        .word out_lda_exprlo
        jsr emit_tmpl
        .word out_sta_label
        jsr out_forstep_ref
        jsr out_cr
        jsr emit_tmpl
        .word out_lda_exprhi
        jsr emit_tmpl
        .word out_sta_label
        jsr out_forstep_ref
        jsr out_plus_one_cr
        rts

emit_load_forend:
        jsr emit_tmpl
        .word out_lda_label
        jsr out_forend_ref
        jsr out_cr
        jsr emit_tmpl
        .word out_sta_exprlo
        jsr emit_tmpl
        .word out_lda_label
        jsr out_forend_ref
        jsr out_plus_one_cr
        jsr emit_tmpl_done
        .word out_sta_exprhi

emit_load_forstep:
        jsr emit_tmpl
        .word out_lda_label
        jsr out_forstep_ref
        jsr out_cr
        jsr emit_tmpl
        .word out_sta_exprlo
        jsr emit_tmpl
        .word out_lda_label
        jsr out_forstep_ref
        jsr out_plus_one_cr
        jsr emit_tmpl_done
        .word out_sta_exprhi

emit_for_initial_check:
        jsr emit_tmpl
        .word out_lda_label
        jsr out_forstep_ref
        jsr out_plus_one_cr
        jsr emit_tmpl
        .word out_bmi_label
        jsr out_forinitneg_ref
        jsr out_cr

        lda current_for_var_data_lo
        sta current_var_data_lo
        lda current_for_var_data_hi
        sta current_var_data_hi
        jsr emit_load_var
        jsr emit_move_expr_to_lhs
        jsr emit_load_forend
        jsr emit_tmpl
        .word out_jsr_cmple
        jsr emit_tmpl
        .word out_bne_label
        jsr out_fortop_ref
        jsr out_cr
        jsr emit_jmp_fordone

        jsr emit_forinitneg_label_def
        lda current_for_var_data_lo
        sta current_var_data_lo
        lda current_for_var_data_hi
        sta current_var_data_hi
        jsr emit_load_var
        jsr emit_move_expr_to_lhs
        jsr emit_load_forend
        jsr emit_tmpl
        .word out_jsr_cmpge
        jsr emit_tmpl
        .word out_bne_label
        jsr out_fortop_ref
        jsr out_cr
        jsr emit_jmp_fordone
        rts

emit_for_top_label_def:
        jsr out_fortop_ref
        bra emit_label_suffix

emit_forneg_label_def:
        jsr out_forneg_ref
        bra emit_label_suffix

emit_forinitneg_label_def:
        jsr out_forinitneg_ref
        bra emit_label_suffix

emit_forcont_label_def:
        jsr out_forcont_ref
        bra emit_label_suffix

emit_fordone_label_def:
        jsr out_fordone_ref
        bra emit_label_suffix

emit_jmp_fortop:
        jsr emit_tmpl
        .word out_jmp_label
        jsr out_fortop_ref
        jsr out_cr
        rts

emit_jmp_fordone:
        jsr emit_tmpl
        .word out_jmp_label
        jsr out_fordone_ref
        jsr out_cr
        rts

emit_do_top_label_def:
        jsr out_dotop_ref
        bra emit_label_suffix

emit_do_done_label_def:
        jsr out_dodone_ref
        bra emit_label_suffix

emit_jmp_dotop:
        jsr emit_tmpl
        .word out_jmp_label
        jsr out_dotop_ref
        jsr out_cr
        rts

emit_jmp_dodone:
        jsr emit_tmpl
        .word out_jmp_label
        jsr out_dodone_ref
        jsr out_cr
        rts

alloc_if_tmp_label:
        lda if_label_next_lo
        sta if_tmp_lo
        lda if_label_next_hi
        sta if_tmp_hi
        jsr inc_if_label_next
        rts

emit_lhs_truth_test:
        jsr emit_tmpl
        .word out_lda_lhslo
        jsr emit_tmpl_done
        .word out_ora_lhshi

emit_do_pretest_while:
        jsr alloc_if_tmp_label
        jsr emit_lhs_truth_test
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr emit_branch_if_tmp
        jsr emit_jmp_dodone
        jsr emit_if_tmp_label_def
        rts

emit_do_pretest_until:
        jsr alloc_if_tmp_label
        jsr emit_lhs_truth_test
        lda #<out_beq_label
        ldy #>out_beq_label
        jsr emit_branch_if_tmp
        jsr emit_jmp_dodone
        jsr emit_if_tmp_label_def
        rts

emit_do_posttest_until:
        jsr alloc_if_tmp_label
        jsr emit_lhs_truth_test
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr emit_branch_if_tmp
        jsr emit_jmp_dotop
        jsr emit_if_tmp_label_def
        rts

emit_do_posttest_while:
        jsr alloc_if_tmp_label
        jsr emit_lhs_truth_test
        lda #<out_beq_label
        ldy #>out_beq_label
        jsr emit_branch_if_tmp
        jsr emit_jmp_dotop
        jsr emit_if_tmp_label_def
        rts

emit_if_comparison:
        jsr emit_if_condition_branches
        jsr emit_if_skip_label_def
        jsr emit_jmp_if_end
        jsr emit_if_true_label_def
        rts

emit_if_comparison_inline_start:
        jsr emit_if_condition_branches
        jsr emit_if_skip_label_def
        jsr emit_jmp_if_else
        jsr emit_if_true_label_def
        rts

emit_if_condition_branches:
        lda cond_op
        cmp #COND_EQ
        beq _emit_if_cmp_eq
        cmp #COND_NE
        beq _emit_if_cmp_ne
        cmp #COND_LT
        beq _emit_if_cmp_lt
        cmp #COND_LE
        beq _emit_if_cmp_le
        cmp #COND_GT
        beq _emit_if_cmp_gt
        cmp #COND_GE
        beq _emit_if_cmp_ge
        cmp #COND_TRUTH
        beq _emit_if_truth
        rts

_emit_if_cmp_eq:
        jsr emit_if_cmp_eq
        bra _emit_if_cmp_done

_emit_if_cmp_ne:
        jsr emit_if_cmp_ne
        bra _emit_if_cmp_done

_emit_if_cmp_lt:
        jsr emit_if_cmp_lt
        bra _emit_if_cmp_done

_emit_if_cmp_le:
        jsr emit_if_cmp_le
        bra _emit_if_cmp_done

_emit_if_cmp_gt:
        jsr emit_if_cmp_gt
        bra _emit_if_cmp_done

_emit_if_cmp_ge:
        jsr emit_if_cmp_ge
        bra _emit_if_cmp_done

_emit_if_truth:
        jsr emit_if_truth

_emit_if_cmp_done:
        rts

emit_if_cmp_eq:
        jsr emit_cmp_lhshi_exprhi
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr emit_branch_if_skip
        jsr emit_cmp_lhslo_exprlo
        lda #<out_beq_label
        ldy #>out_beq_label
        jsr emit_branch_if_true
        jsr emit_jmp_if_skip
        rts

emit_if_cmp_ne:
        jsr emit_cmp_lhshi_exprhi
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr emit_branch_if_true
        jsr emit_cmp_lhslo_exprlo
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr emit_branch_if_true
        jsr emit_jmp_if_skip
        rts

emit_if_cmp_lt:
        jsr emit_if_signed_prefix_lhs_negative_true
        jsr emit_cmp_lhshi_exprhi
        lda #<out_bcc_label
        ldy #>out_bcc_label
        jsr emit_branch_if_true
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr emit_branch_if_skip
        jsr emit_cmp_lhslo_exprlo
        lda #<out_bcc_label
        ldy #>out_bcc_label
        jsr emit_branch_if_true
        jsr emit_jmp_if_skip
        rts

emit_if_cmp_le:
        jsr emit_if_signed_prefix_lhs_negative_true
        jsr emit_cmp_lhshi_exprhi
        lda #<out_bcc_label
        ldy #>out_bcc_label
        jsr emit_branch_if_true
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr emit_branch_if_skip
        jsr emit_cmp_lhslo_exprlo
        lda #<out_bcc_label
        ldy #>out_bcc_label
        jsr emit_branch_if_true
        lda #<out_beq_label
        ldy #>out_beq_label
        jsr emit_branch_if_true
        jsr emit_jmp_if_skip
        rts

emit_if_cmp_gt:
        jsr emit_if_signed_prefix_lhs_positive_true
        jsr emit_cmp_lhshi_exprhi
        lda #<out_bcc_label
        ldy #>out_bcc_label
        jsr emit_branch_if_skip
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr emit_branch_if_true
        jsr emit_cmp_lhslo_exprlo
        lda #<out_bcc_label
        ldy #>out_bcc_label
        jsr emit_branch_if_skip
        lda #<out_beq_label
        ldy #>out_beq_label
        jsr emit_branch_if_skip
        jsr emit_jmp_if_true
        rts

emit_if_cmp_ge:
        jsr emit_if_signed_prefix_lhs_positive_true
        jsr emit_cmp_lhshi_exprhi
        lda #<out_bcc_label
        ldy #>out_bcc_label
        jsr emit_branch_if_skip
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr emit_branch_if_true
        jsr emit_cmp_lhslo_exprlo
        lda #<out_bcs_label
        ldy #>out_bcs_label
        jsr emit_branch_if_true
        jsr emit_jmp_if_skip
        rts

emit_if_truth:
        jsr emit_tmpl
        .word out_lda_lhslo
        jsr emit_tmpl
        .word out_ora_lhshi
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr emit_branch_if_true
        jsr emit_jmp_if_skip
        rts

emit_if_signed_prefix_lhs_negative_true:
        jsr emit_tmpl
        .word out_sign_xor_lhshi_exprhi
        lda #<out_bpl_label
        ldy #>out_bpl_label
        jsr emit_branch_if_tmp
        jsr emit_tmpl
        .word out_lda_lhshi
        lda #<out_bmi_label
        ldy #>out_bmi_label
        jsr emit_branch_if_true
        jsr emit_jmp_if_skip
        jsr emit_if_tmp_label_def
        rts

emit_if_signed_prefix_lhs_positive_true:
        jsr emit_tmpl
        .word out_sign_xor_lhshi_exprhi
        lda #<out_bpl_label
        ldy #>out_bpl_label
        jsr emit_branch_if_tmp
        jsr emit_tmpl
        .word out_lda_lhshi
        lda #<out_bmi_label
        ldy #>out_bmi_label
        jsr emit_branch_if_skip
        jsr emit_jmp_if_true
        jsr emit_if_tmp_label_def
        rts

emit_cmp_lhshi_exprhi:
        jsr emit_tmpl_done
        .word out_cmp_lhshi_exprhi

emit_cmp_lhslo_exprlo:
        jsr emit_tmpl_done
        .word out_cmp_lhslo_exprlo

emit_branch_if_true:
        jsr out_zstr
        jsr out_if_true_ref
        jsr out_cr
        rts

emit_branch_if_skip:
        jsr out_zstr
        jsr out_if_skip_ref
        jsr out_cr
        rts

emit_branch_if_tmp:
        jsr out_zstr
        jsr out_if_tmp_ref
        jsr out_cr
        rts

emit_jmp_if_true:
        jsr emit_tmpl
        .word out_jmp_label
        jsr out_if_true_ref
        jsr out_cr
        rts

emit_jmp_if_skip:
        jsr emit_tmpl
        .word out_jmp_label
        jsr out_if_skip_ref
        jsr out_cr
        rts

emit_jmp_if_end:
        jsr emit_tmpl
        .word out_jmp_label
        jsr out_if_end_ref
        jsr out_cr
        rts

emit_jmp_if_else:
        jsr emit_tmpl
        .word out_jmp_label
        jsr out_if_else_ref
        jsr out_cr
        rts

emit_jmp_if_target:
        jsr emit_tmpl
        .word out_jmp_label
        lda if_target_lo
        sta number_lo
        lda if_target_hi
        sta number_hi
        jsr out_label_from_number
        jsr out_cr
        rts

emit_on_compare:
        jsr emit_tmpl
        .word out_lda_exprhi
        jsr emit_tmpl
        .word out_cmp_imm_hex
        lda #0
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl
        .word out_bne_label
        jsr out_onnext_ref
        jsr out_cr
        jsr emit_tmpl
        .word out_cmp_exprlo_imm
        lda on_target_index
        jsr out_hex_byte
        jsr out_cr
        jsr emit_tmpl
        .word out_bne_label
        jsr out_onnext_ref
        jsr out_cr
        rts

emit_jmp_on_target:
        jsr emit_tmpl
        .word out_jmp_label
        lda on_target_lo
        sta number_lo
        lda on_target_hi
        sta number_hi
        jsr out_label_from_number
        jsr out_cr
        rts

emit_jsr_on_target:
        jsr emit_tmpl
        .word out_jsr_label
        lda on_target_lo
        sta number_lo
        lda on_target_hi
        sta number_hi
        jsr out_label_from_number
        jsr out_cr
        rts

emit_jmp_ondone:
        jsr emit_tmpl
        .word out_jmp_label
        jsr out_ondone_ref
        jsr out_cr
        rts

emit_onnext_label_def:
        jsr out_onnext_ref
        bra emit_label_suffix

emit_ondone_label_def:
        jsr out_ondone_ref
        bra emit_label_suffix

emit_if_true_label_def:
        jsr out_if_true_ref
        bra emit_label_suffix

emit_if_skip_label_def:
        jsr out_if_skip_ref
        bra emit_label_suffix

emit_if_end_label_def:
        jsr out_if_end_ref
        bra emit_label_suffix

emit_if_else_label_def:
        jsr out_if_else_ref
        bra emit_label_suffix

emit_if_tmp_label_def:
        jsr out_if_tmp_ref

emit_label_suffix:
        lda #':'
        jsr out_char
        jsr out_cr
        rts

out_if_true_ref:
        ldx backend_mode
        beq +
        lda #LBL_IF
        ldx if_true_lo
        ldy if_true_hi
        jmp bin_label
+       lda #<out_iftrue_prefix
        ldy #>out_iftrue_prefix
        jsr out_zstr
        lda if_true_hi
        jsr out_hex_byte
        lda if_true_lo
        jsr out_hex_byte
        rts

out_if_skip_ref:
        ldx backend_mode
        beq +
        lda #LBL_IF
        ldx if_skip_lo
        ldy if_skip_hi
        jmp bin_label
+       lda #<out_ifskip_prefix
        ldy #>out_ifskip_prefix
        jsr out_zstr
        lda if_skip_hi
        jsr out_hex_byte
        lda if_skip_lo
        jsr out_hex_byte
        rts

out_if_end_ref:
        ldx backend_mode
        beq +
        lda #LBL_IF
        ldx if_end_lo
        ldy if_end_hi
        jmp bin_label
+       lda #<out_ifend_prefix
        ldy #>out_ifend_prefix
        jsr out_zstr
        lda if_end_hi
        jsr out_hex_byte
        lda if_end_lo
        jsr out_hex_byte
        rts

out_if_else_ref:
        ldx backend_mode
        beq +
        lda #LBL_IF
        ldx if_else_lo
        ldy if_else_hi
        jmp bin_label
+       lda #<out_ifelse_prefix
        ldy #>out_ifelse_prefix
        jsr out_zstr
        lda if_else_hi
        jsr out_hex_byte
        lda if_else_lo
        jsr out_hex_byte
        rts

out_if_tmp_ref:
        ldx backend_mode
        beq +
        lda #LBL_IF
        ldx if_tmp_lo
        ldy if_tmp_hi
        jmp bin_label
+       lda #<out_iftmp_prefix
        ldy #>out_iftmp_prefix
        jsr out_zstr
        lda if_tmp_hi
        jsr out_hex_byte
        lda if_tmp_lo
        jsr out_hex_byte
        rts

out_array_ok_ref:
        ldx backend_mode
        beq +
        lda #LBL_ARRAYOK
        ldx array_ok_lo
        ldy array_ok_hi
        jmp bin_label
+       lda #<out_arrayok_prefix
        ldy #>out_arrayok_prefix
        jsr out_zstr
        lda array_ok_hi
        jsr out_hex_byte
        lda array_ok_lo
        jsr out_hex_byte
        rts

out_array_nonneg_ref:
        ldx backend_mode
        beq +
        lda #LBL_ARRAYPOS
        ldx array_ok_lo
        ldy array_ok_hi
        jmp bin_label
+       lda #<out_arraynonneg_prefix
        ldy #>out_arraynonneg_prefix
        jsr out_zstr
        lda array_ok_hi
        jsr out_hex_byte
        lda array_ok_lo
        jsr out_hex_byte
        rts

out_array_hieq_ref:
        ldx backend_mode
        beq +
        lda #LBL_ARRAYHIEQ
        ldx array_ok_lo
        ldy array_ok_hi
        jmp bin_label
+       lda #<out_arrayhieq_prefix
        ldy #>out_arrayhieq_prefix
        jsr out_zstr
        lda array_ok_hi
        jsr out_hex_byte
        lda array_ok_lo
        jsr out_hex_byte
        rts

out_onnext_ref:
        ldx backend_mode
        beq +
        lda #LBL_ON
        ldx on_label_lo
        ldy on_label_hi
        jmp bin_label
+       lda #<out_onnext_prefix
        ldy #>out_onnext_prefix
        jsr out_zstr
        lda on_label_hi
        jsr out_hex_byte
        lda on_label_lo
        jsr out_hex_byte
        rts

out_ondone_ref:
        ldx backend_mode
        beq +
        lda #LBL_ON
        ldx on_done_lo
        ldy on_done_hi
        jmp bin_label
+       lda #<out_ondone_prefix
        ldy #>out_ondone_prefix
        jsr out_zstr
        lda on_done_hi
        jsr out_hex_byte
        lda on_done_lo
        jsr out_hex_byte
        rts

; forend/forstep are FOR storage slots in the tail: address = storage base +
; id*4 (+2 for the step word). Definitions happen implicitly when the tail
; captures for_storage_addr, so the binary path only resolves references.
out_forend_ref:
        ldx backend_mode
        beq +
        lda #0
        jmp bin_for_storage_ref
+       lda #<out_forend_prefix
        ldy #>out_forend_prefix
        jsr out_zstr
        bra out_current_for_id

out_forstep_ref:
        ldx backend_mode
        beq +
        lda #2
        jmp bin_for_storage_ref
+       lda #<out_forstep_prefix
        ldy #>out_forstep_prefix
        jsr out_zstr
        bra out_current_for_id

bin_for_storage_ref:
        ldx pending_kind
        beq _bin_for_storage_done  ; definition context in the tail: no bytes
        clc
        adc for_storage_addr
        sta pending_value
        lda for_storage_addr+1
        adc #0
        sta pending_value+1
        lda current_for_id
        asl
        asl                        ; id*4, ids < 64 so no carry
        clc
        adc pending_value
        sta pending_value
        bcc _bin_for_storage_done
        inc pending_value+1
_bin_for_storage_done:
        rts

out_fortop_ref:
        ldx backend_mode
        beq +
        lda #LBL_FORTOP
        bra bin_for_label
+       lda #<out_fortop_prefix
        ldy #>out_fortop_prefix
        jsr out_zstr
        bra out_current_for_id

out_forneg_ref:
        ldx backend_mode
        beq +
        lda #LBL_FORNEG
        bra bin_for_label
+       lda #<out_forneg_prefix
        ldy #>out_forneg_prefix
        jsr out_zstr
        bra out_current_for_id

out_forinitneg_ref:
        ldx backend_mode
        beq +
        lda #LBL_FORINITNEG
        bra bin_for_label
+       lda #<out_forinitneg_prefix
        ldy #>out_forinitneg_prefix
        jsr out_zstr
        bra out_current_for_id

out_forcont_ref:
        ldx backend_mode
        beq +
        lda #LBL_FORCONT
        bra bin_for_label
+       lda #<out_forcont_prefix
        ldy #>out_forcont_prefix
        jsr out_zstr
        bra out_current_for_id

out_fordone_ref:
        ldx backend_mode
        beq +
        lda #LBL_FORDONE
        bra bin_for_label
+       lda #<out_fordone_prefix
        ldy #>out_fordone_prefix
        jsr out_zstr

out_current_for_id:
        lda #0
        jsr out_hex_byte
        lda current_for_id
        jsr out_hex_byte
        rts

bin_for_label:
        ldx current_for_id
        ldy #0
        jmp bin_label

out_dotop_ref:
        ldx backend_mode
        beq +
        lda #LBL_DOTOP
        bra bin_do_label
+       lda #<out_dotop_prefix
        ldy #>out_dotop_prefix
        jsr out_zstr
        bra out_current_do_id

out_dodone_ref:
        ldx backend_mode
        beq +
        lda #LBL_DODONE
        bra bin_do_label
+       lda #<out_dodone_prefix
        ldy #>out_dodone_prefix
        jsr out_zstr

out_current_do_id:
        lda #0
        jsr out_hex_byte
        lda current_do_id
        jsr out_hex_byte
        rts

bin_do_label:
        ldx current_do_id
        ldy #0
        jmp bin_label

out_plus_one_cr:
        ldx backend_mode
        beq _out_plus_one_text
        inc pending_value       ; label address + 1, then finalize like out_cr
        bne +
        inc pending_value+1
+       jmp bin_finalize_pending
_out_plus_one_text:
        lda #'+'
        jsr out_char
        lda #'1'
        jsr out_char
        jsr out_cr
        rts

out_hex_word_number:
        ldx backend_mode
        beq _out_hex_word_text
        cpx #BK_EMIT
        bne _out_hex_word_done
        ldx pending_kind
        beq _out_hex_word_done
        lda number_lo
        sta pending_value
        lda number_hi
        sta pending_value+1
_out_hex_word_done:
        rts
_out_hex_word_text:
        lda number_hi
        jsr out_hex_byte
        lda number_lo
        jsr out_hex_byte
        rts

out_hex_byte:
        ldx backend_mode
        beq _out_hex_byte_text
        cpx #BK_EMIT
        bne _out_hex_byte_done
        ldx pending_kind
        cpx #1                  ; byte operand patch
        bne _out_hex_byte_done
        sta pending_value
_out_hex_byte_done:
        rts
_out_hex_byte_text:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr out_hex_nibble
        pla
        and #$0f
        jsr out_hex_nibble
        rts

out_hex_nibble:
        cmp #10
        bcc +
        clc
        adc #'a' - 10
        bra _out_hex_nibble_emit
+       clc
        adc #'0'
_out_hex_nibble_emit:
        jsr CC_CHROUT
        rts

out_comment_char:
        ldx backend_mode
        bne _comment_done
        cmp #13
        beq _comment_space
        cmp #'"'
        beq _comment_printable
        cmp #' '
        bcc _comment_hex
        cmp #$7f
        bcc _comment_printable
_comment_hex:
        pha
        lda #'<'
        jsr CC_CHROUT
        lda #'$'
        jsr CC_CHROUT
        pla
        jsr out_hex_byte
        lda #'>'
        jsr CC_CHROUT
_comment_done:
        rts
_comment_space:
        lda #' '
_comment_printable:
        jsr CC_CHROUT
        rts

; emit a single character of program text; silent outside text mode
out_char:
        ldx backend_mode
        bne +
        jsr CC_CHROUT
+       rts

out_cr:
        ldx backend_mode
        beq +
        jmp bin_finalize_pending
+       lda #13
        jsr CC_CHROUT
        rts

out_zstr:
        ldx backend_mode
        beq +
        jmp bin_zstr
+       sta str_ptr
        sty str_ptr+1
        ldy #0
_out_zstr_loop:
        lda (str_ptr),y
        beq _out_zstr_done
        jsr CC_CHROUT
        iny
        bne _out_zstr_loop
        inc str_ptr+1
        bra _out_zstr_loop
_out_zstr_done:
        rts

;=======================================================================================
; Binary backend engine (size pass today; emit pass will extend it)
;
; Emission is a stream of template records plus operand/label fills. A record
; with a patch kind arms pending_kind; the operand or label reference that
; follows supplies the value (ignored while sizing), and out_cr finalizes the
; patch bytes into bin_pc. See docs\native-backend.md and
; src\gen\bin-templates.inc.
;=======================================================================================

BK_TEXT = 0
BK_SIZE = 1
BK_EMIT = 2

bin_ptr = $FD

; A/Y = text template pointer; look up the derived binary record
bin_zstr:
        sta bin_key_lo
        sty bin_key_hi
        lda #<bt_map
        sta bin_ptr
        lda #>bt_map
        sta bin_ptr+1
_bin_map_loop:
        ldy #0
        lda (bin_ptr),y
        ldy #1
        ora (bin_ptr),y
        beq _bin_map_missing
        lda (bin_ptr),y
        cmp bin_key_hi
        bne _bin_map_next
        ldy #0
        lda (bin_ptr),y
        cmp bin_key_lo
        beq _bin_map_found
_bin_map_next:
        clc
        lda bin_ptr
        adc #4
        sta bin_ptr
        bcc _bin_map_loop
        inc bin_ptr+1
        bra _bin_map_loop

_bin_map_found:
        ldy #2
        lda (bin_ptr),y
        tax
        iny
        lda (bin_ptr),y
        sta bin_ptr+1
        stx bin_ptr
        ldy #0
        lda (bin_ptr),y         ; record kind
        cmp #6                  ; name fragment: no bytes, keep pending armed
        beq _bin_zstr_done
        cmp #0
        beq _bin_zstr_code
        pha                     ; patch record: close any armed patch first
        jsr bin_finalize_pending
        pla
        sta pending_kind
        tax
        ldy #1
        lda (bin_ptr),y         ; record length includes the patch slot
        sec
        sbc bin_patch_size-1,x
        bra _bin_zstr_out

_bin_zstr_code:
        ldy #1
        lda (bin_ptr),y

_bin_zstr_out:
        ldx backend_mode
        cpx #BK_EMIT
        beq bin_copy_record
        jmp bin_add_pc

_bin_zstr_done:
        rts

_bin_map_missing:
        lda #1
        sta backend_error
        lda bin_key_lo
        sta backend_error_ptr
        lda bin_key_hi
        sta backend_error_ptr+1
        rts

; copy A record bytes (starting at record offset 2) to the binary output
bin_copy_record:
        sta bin_copy_cnt
        cmp #0
        beq +
        ldy #2
_bin_copy_loop:
        lda (bin_ptr),y
        jsr bin_write_byte
        iny
        dec bin_copy_cnt
        bne _bin_copy_loop
+       rts

; patch slot sizes indexed by kind-1: byte, word, lo, hi, rel8
bin_patch_size:
        .byte 1, 2, 1, 1, 1

bin_finalize_pending:
        ldx pending_kind
        bne +
        rts
+       lda #0
        sta pending_kind
        lda backend_mode
        cmp #BK_EMIT
        beq bin_fin_emit
        lda bin_patch_size-1,x
        ; FALLTHROUGH
bin_add_pc:
        clc
        adc bin_pc
        sta bin_pc
        bcc +
        inc bin_pc+1
+       rts

bin_fin_emit:
        cpx #2
        beq _bin_fin_word
        cpx #4
        beq _bin_fin_hi
        cpx #5
        beq _bin_fin_rel8
        lda pending_value       ; byte and lo patches
        jmp bin_write_byte
_bin_fin_word:
        lda pending_value
        jsr bin_write_byte
        lda pending_value+1
        jmp bin_write_byte
_bin_fin_hi:
        lda pending_value+1
        jmp bin_write_byte
_bin_fin_rel8:
        ; displacement = target - (address after the operand byte),
        ; computed 16-bit: a branch past rel8 range fails the backend
        ; (error 5) instead of silently wrapping -- 64tass rejects the
        ; far branch on the text side, but the on-device OUT.PRG has
        ; no second assembler to save it
        sec
        lda pending_value
        sbc bin_pc
        sta bin_rel_lo
        lda pending_value+1
        sbc bin_pc+1
        sta bin_rel_hi
        lda bin_rel_lo
        bne +
        dec bin_rel_hi
+       dec bin_rel_lo
        lda bin_rel_hi          ; in range iff hi/lo read as one
        beq _bfr_hi0            ; signed byte: $00 with bit7 clear,
        cmp #$ff                ; or $ff with bit7 set
        bne _bfr_far
        lda bin_rel_lo
        bmi _bfr_write
        bra _bfr_far
_bfr_hi0:
        lda bin_rel_lo
        bmi _bfr_far
_bfr_write:
        lda bin_rel_lo
        jmp bin_write_byte
_bfr_far:
        lda #5                  ; rel8 branch out of range at bin_pc
        sta backend_error
        lda bin_pc
        sta backend_error_ptr
        lda bin_pc+1
        sta backend_error_ptr+1
        lda bin_rel_lo          ; still write a byte so bin_pc stays
        jmp bin_write_byte      ; in step with the label map
bin_rel_lo:
        .byte 0
bin_rel_hi:
        .byte 0

; write one byte of the native program image and advance bin_pc; the binary
; output channel is selected while the emit pass runs
bin_write_byte:
        jsr CC_CHROUT
        inc bin_pc
        bne +
        inc bin_pc+1
+       rts

; A = label table id, X/Y = label id lo/hi. With no patch pending this is a
; definition site: record bin_pc. With a patch pending it is a reference:
; fetch the recorded address into pending_value (the size pass never reads
; the value, so both passes share this path).
bin_label:
        sta bin_tbl
        txa
        asl
        sta bin_ptr
        tya
        rol
        sta bin_ptr+1           ; bin_ptr = id*2
        ldx bin_tbl
        cpx #LBL_ON
        bcc _bin_label_cap_if
        beq _bin_label_cap_on
        cpx #LBL_FORTOP
        bcc _bin_label_cap_array
        lda bin_ptr+1           ; for/do tables
        bne _bin_label_ovf
        lda bin_ptr
        cmp #LBL_FORDO_MAX * 2
        bcs _bin_label_ovf
        bra _bin_label_go
_bin_label_cap_if:
        lda bin_ptr+1
        cmp #>(LBL_IF_IDS * 2)
        bcs _bin_label_ovf
        bra _bin_label_go
_bin_label_cap_on:
        lda bin_ptr+1
        cmp #>(LBL_ON_IDS * 2)
        bcs _bin_label_ovf
        bra _bin_label_go
_bin_label_cap_array:
        lda bin_ptr+1
        cmp #>(LBL_ARRAY_IDS * 2)
        bcs _bin_label_ovf
_bin_label_go:
        ldx bin_tbl
        clc
        lda bin_ptr
        adc lbladdr_base_lo,x
        sta bin_ptr
        lda bin_ptr+1
        adc lbladdr_base_hi,x
        sta bin_ptr+1
        jsr pool_ptr_save       ; tables are in bank 4, like the pool
        lda bin_ptr
        sta source_ptr
        lda bin_ptr+1
        sta source_ptr+1
        lda pending_kind
        beq _bin_label_def
        ldz #0
        lda [source_ptr],z
        sta pending_value
        inz
        lda [source_ptr],z
        sta pending_value+1
        jmp pool_ptr_restore
_bin_label_def:
        ldz #0
        lda bin_pc
        sta [source_ptr],z
        inz
        lda bin_pc+1
        sta [source_ptr],z
        jmp pool_ptr_restore
_bin_label_ovf:
        lda #2
        sta backend_error
        lda bin_tbl
        sta backend_error_ptr
        stx backend_error_ptr+1
        rts

screen_zstr:
        sta str_ptr
        sty str_ptr+1
        ldy #0
_screen_zstr_loop:
        lda (str_ptr),y
        beq _screen_zstr_done
        jsr CC_CHROUT
        iny
        bne _screen_zstr_loop
        inc str_ptr+1
        bra _screen_zstr_loop
_screen_zstr_done:
        rts

;=======================================================================================
; Strings
;=======================================================================================

source_name:
        .text "source.prg"
source_name_end:

output_name:
        .text "0:out.tmp,s,w"
output_name_end:

scratch_name:
        .text "s0:out.tmp"
        .byte 13
scratch_name_end:

scratch_final_name:
        .text "s0:out.asm"
        .byte 13
scratch_final_name_end:

rename_name:
        .text "r0:out.asm=out.tmp"
        .byte 13
rename_name_end:

outb_name:
        .text "0:outb.tmp,p,w"
outb_name_end:

rt_name:
        .text "runtime.prg"
rt_name_end:

scratch_outb_name:
        .text "s0:outb.tmp"
        .byte 13
scratch_outb_name_end:

scratch_prg_name:
        .text "s0:out.prg"
        .byte 13
scratch_prg_name_end:

rename_prg_name:
        .text "r0:out.prg=outb.tmp"
        .byte 13
rename_prg_name_end:

msg_banner:
        .byte 13
        .text "basic65c: source.prg -> out.asm"
        .byte 13, 0
msg_opening_in:
        .text "source file? "
        .byte 0
msg_source_prompt:
        .text "(return=source.prg) "
        .byte 0
msg_loading_source_prefix:
        .text "loading "
        .byte 0
msg_scanning_in:
        .text "scanning source"
        .byte 13, 0
msg_opening_out:
        .text "opening out.asm"
        .byte 13, 0
msg_open_in_fail:
        .text "basic65c: cannot load source file"
        .byte 13, 0
msg_open_out_fail:
        .text "basic65c: cannot open out.asm"
        .byte 13, 0
msg_finalize_fail:
        .text "basic65c: cannot rename out.tmp"
        .byte 13, 0
msg_error_bad_play:
        .text "bad play"
        .byte 13, 0
msg_error_bad_sprite:
        .text "bad sprite/movspr"
        .byte 13, 0
msg_error_bad_sound:
        .text "bad sound/vol"
        .byte 13, 0
msg_error_bad_trap:
        .text "bad trap/resume"
        .byte 13, 0
msg_error_bad_open:
        .text "bad open/close"
        .byte 13, 0
msg_error_bad_begin:
        .text "bad begin"
        .byte 13, 0
msg_error_bad_bend:
        .text "bad bend"
        .byte 13, 0
msg_bin_size:
        .text "native size: ends $"
        .byte 0
msg_backend_error:
        .text "basic65c: backend error "
        .byte 0
msg_writing_prg:
        .text "writing out.prg"
        .byte 13, 0
msg_wrote_prg:
        .text "basic65c: wrote out.prg"
        .byte 13, 0
msg_error_bad_def:
        .byte 13
        .text "bad def fn"
        .byte 0
msg_bin_disk_fail:
        .byte 13
        .text "cannot write out file (disk full or write protected?)"
        .byte 13, 0
msg_rt_missing:
        .byte 13
        .text "runtime.prg missing or unreadable on this disk"
        .byte 13, 0
msg_bin_write_fail:
        .text "basic65c: native out.prg failed"
        .byte 13, 0
msg_bin_mismatch:
        .text "basic65c: native size mismatch"
        .byte 13, 0
msg_done:
        .text "basic65c: wrote out.asm"
        .byte 13, 0
msg_compile_failed:
        .text "basic65c: compilation halted"
        .byte 13, 0
msg_compiling_start:
        .text "compiling:"
        .byte 13, 0
msg_error_line:
        .text "basic65c: error line "
        .byte 0
msg_error_colon:
        .text ": "
        .byte 0
msg_error_bad_data:
        .text "bad data item"
        .byte 13, 0
msg_error_too_many_data:
        .text "too many data items"
        .byte 13, 0
msg_error_line_overflow:
        .text "line too long"
        .byte 13, 0
msg_error_dup_line:
        .text "duplicate line number"
        .byte 13, 0
msg_error_many_lines:
        .text "too many lines"
        .byte 13, 0
msg_error_scan_var:
        .text "cannot resolve variable (out of symbols?)"
        .byte 13, 0
msg_overlay_plan:
        .text "overlay: $"
        .byte 0
msg_error_too_large:
        .text "basic65c: program too large for the memory window"
        .byte 13, 0
msg_error_unsupported_token:
        .text "unsupported token"
        .byte 13, 0
msg_error_unsupported_statement:
        .text "unsupported statement $"
msg_unsup_hex:
        .text "00"
        .byte 13, 0
msg_error_unsupported_print:
        .text "unsupported print"
        .byte 13, 0
msg_error_bad_input:
        .text "bad input"
        .byte 13, 0
msg_error_bad_get:
        .text "bad get"
        .byte 13, 0
msg_error_unsupported_go:
        .text "unsupported go"
        .byte 13, 0
msg_error_bad_goto:
        .text "bad goto"
        .byte 13, 0
msg_error_bad_gosub:
        .text "bad gosub"
        .byte 13, 0
msg_error_bad_sys:
        .text "bad sys"
        .byte 13, 0
msg_error_bad_poke:
        .text "bad poke"
        .byte 13, 0
msg_error_bad_read:
        .text "bad read"
        .byte 13, 0
msg_error_bad_restore:
        .text "bad restore"
        .byte 13, 0
msg_error_bad_assignment:
        .text "bad assignment"
        .byte 13, 0
msg_error_bad_if:
        .text "bad if"
        .byte 13, 0
msg_error_bad_else:
        .text "bad else"
        .byte 13, 0
msg_error_bad_for:
        .text "bad for"
        .byte 13, 0
msg_error_bad_next:
        .text "bad next"
        .byte 13, 0
msg_error_bad_on:
        .text "bad on"
        .byte 13, 0
msg_error_bad_do:
        .text "bad do"
        .byte 13, 0
msg_error_bad_loop:
        .text "bad loop"
        .byte 13, 0
msg_error_bad_exit:
        .text "bad exit"
        .byte 13, 0

out_header_pre:
.if TEXT_EMITTER
        .text "; generated by basic65c"
        .byte 13
        .text "; link: 64tass --cbm-prg --m45gs02 runtime.asm out.asm -o out.prg"
        .byte 13
        .text "        .enc ""none"""
        .byte 13, 13
        .text "        * = $"
        .byte 0
.else
        .byte 0
.fi
out_header_post:
.if TEXT_EMITTER
        .text "00"
        .byte 13
        .text "        .word start"
        .byte 13
        .text "        .word varheapend"
        .byte 13
        .text "        .word datastart"
        .byte 13
        .text "        .word dataend"
        .byte 13
        .text "        .word strroots"
        .byte 13
        .text "        .word fltlits"
        .byte 13
        .text "        .word linetab"
        .byte 13
        .text "        .word gfxflag"
        .byte 13, 13
        .text "start:"
        .byte 13
        .byte 0
.else
        .byte 0
.fi
out_rtlevel_pre:
.if TEXT_EMITTER
        .text "rtlevel = $"
        .byte 0
.else
        .byte 0
.fi

out_comment_load_addr:
.if TEXT_EMITTER
        .text "; input prg load address: $"
        .byte 0
.else
        .byte 0
.fi

out_tail:
.if TEXT_EMITTER
        .text "        jmp rtexit"
        .byte 13
        .byte 13
        .byte 0
.else
        .byte 0
.fi

out_varheapend_def:
.if TEXT_EMITTER
        .text "varheapend = $"
        .byte 0
.else
        .byte 0
.fi

out_size_guard_gfx:
.if TEXT_EMITTER
        .text "        .cerror * > $c000, ""program too large: 640-mode screen codes live at $c000"""
        .byte 13
        .byte 0
.else
        .byte 0
.fi
out_size_guard:
.if TEXT_EMITTER
        .text "        .cerror * > $d000, ""program too large: runs into i/o space"""
        .byte 13
        .byte 0
.else
        .byte 0
.fi

out_data_table_start:
.if TEXT_EMITTER
        .text "datastart:"
        .byte 13, 0
.else
        .byte 0
.fi
out_data_byte_prefix:
.if TEXT_EMITTER
        .text "        .byte $"
        .byte 0
.else
        .byte 0
.fi
out_data_byte_sep:
.if TEXT_EMITTER
        .text ",$"
        .byte 0
.else
        .byte 0
.fi
out_data_word_prefix:
.if TEXT_EMITTER
        .text "        .word "
        .byte 0
.else
        .byte 0
.fi
out_data_table_end:
.if TEXT_EMITTER
        .text "dataend:"
        .byte 13
        .byte 13
        .byte 0
.else
        .byte 0
.fi
out_string_pool_header:
.if TEXT_EMITTER
        .text "; string literals"
        .byte 13, 0
.else
        .byte 0
.fi

out_strroots_start:
.if TEXT_EMITTER
        .text "; string gc roots: rootlo, roothi, bytelenlo, bytelenhi"
        .byte 13
        .text "strroots:"
        .byte 13, 0
.else
        .byte 0
.fi

out_for_storage_header:
.if TEXT_EMITTER
        .text "; for/next runtime storage"
        .byte 13, 0
.else
        .byte 0
.fi

out_for_word_storage:
.if TEXT_EMITTER
        .text ":       .byte 0,0"
        .byte 13, 0
.else
        .byte 0
.fi

out_lda_imm_hex:
.if TEXT_EMITTER
        .text "        lda #$"
        .byte 0
.else
        .byte 0
.fi
out_lda_label_lo_imm:
.if TEXT_EMITTER
        .text "        lda #<"
        .byte 0
.else
        .byte 0
.fi
out_lda_label_hi_imm:
.if TEXT_EMITTER
        .text "        lda #>"
        .byte 0
.else
        .byte 0
.fi
out_adc_imm_hex:
.if TEXT_EMITTER
        .text "        adc #$"
        .byte 0
.else
        .byte 0
.fi
out_cmp_imm_hex:
.if TEXT_EMITTER
        .text "        cmp #$"
        .byte 0
.else
        .byte 0
.fi
out_jsr_chout:
.if TEXT_EMITTER
        .text "        jsr printch"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_printuint:
.if TEXT_EMITTER
        .text "        jsr printuint"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_printstr:
.if TEXT_EMITTER
        .text "        jsr printstr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_printheapstr:
.if TEXT_EMITTER
        .text "        jsr printheapstr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strfromlit:
.if TEXT_EMITTER
        .text "        jsr strfromlit"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strcopyexpr:
.if TEXT_EMITTER
        .text "        jsr strcopyexpr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_concatstr:
.if TEXT_EMITTER
        .text "        jsr concatstr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strlenexpr:
.if TEXT_EMITTER
        .text "        jsr strlenexpr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strfromint:
.if TEXT_EMITTER
        .text "        jsr strfromint"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_valstr:
.if TEXT_EMITTER
        .text "        jsr valstr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strmark:
.if TEXT_EMITTER
        .text "        jsr strmark"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strrelease:
.if TEXT_EMITTER
        .text "        jsr strrelease"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strsub:
.if TEXT_EMITTER
        .text "        jsr strsub"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strright:
.if TEXT_EMITTER
        .text "        jsr strright"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_streq:
.if TEXT_EMITTER
        .text "        jsr streq"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strne:
.if TEXT_EMITTER
        .text "        jsr strne"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strlt:
.if TEXT_EMITTER
        .text "        jsr strlt"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strle:
.if TEXT_EMITTER
        .text "        jsr strle"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strgt:
.if TEXT_EMITTER
        .text "        jsr strgt"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strge:
.if TEXT_EMITTER
        .text "        jsr strge"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strrefeq:
.if TEXT_EMITTER
        .text "        jsr strrefeq"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strrefne:
.if TEXT_EMITTER
        .text "        jsr strrefne"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strreflt:
.if TEXT_EMITTER
        .text "        jsr strreflt"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strrefle:
.if TEXT_EMITTER
        .text "        jsr strrefle"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strrefgt:
.if TEXT_EMITTER
        .text "        jsr strrefgt"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strrefge:
.if TEXT_EMITTER
        .text "        jsr strrefge"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_printcomma:
.if TEXT_EMITTER
        .text "        jsr printcomma"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_loadintvar:
.if TEXT_EMITTER
        .text "        jsr loadintvar"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_storeintvar:
.if TEXT_EMITTER
        .text "        jsr storeintvar"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_floadvar:
.if TEXT_EMITTER
        .text "        jsr floadvar"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fstorevar:
.if TEXT_EMITTER
        .text "        jsr fstorevar"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_float16:
.if TEXT_EMITTER
        .text "        jsr float16"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_qint:
.if TEXT_EMITTER
        .text "        jsr qint"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_printflt:
.if TEXT_EMITTER
        .text "        jsr printflt"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fpush:
.if TEXT_EMITTER
        .text "        jsr fpush"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fpoparg:
.if TEXT_EMITTER
        .text "        jsr fpoparg"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fadd:
.if TEXT_EMITTER
        .text "        jsr fadd"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fsub:
.if TEXT_EMITTER
        .text "        jsr fsub"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fmul:
.if TEXT_EMITTER
        .text "        jsr fmul"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fdiv:
.if TEXT_EMITTER
        .text "        jsr fdiv"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fneg:
.if TEXT_EMITTER
        .text "        jsr fneg"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fabsf:
.if TEXT_EMITTER
        .text "        jsr fabsf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fsgnf:
.if TEXT_EMITTER
        .text "        jsr fsgnf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fintf:
.if TEXT_EMITTER
        .text "        jsr fintf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_ftruth:
.if TEXT_EMITTER
        .text "        jsr ftruth"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fpromotelhs:
.if TEXT_EMITTER
        .text "        jsr fpromotelhs"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fcmpeqb:
.if TEXT_EMITTER
        .text "        jsr fcmpeqb"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fcmpneb:
.if TEXT_EMITTER
        .text "        jsr fcmpneb"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fcmpltb:
.if TEXT_EMITTER
        .text "        jsr fcmpltb"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fcmpleb:
.if TEXT_EMITTER
        .text "        jsr fcmpleb"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fcmpgtb:
.if TEXT_EMITTER
        .text "        jsr fcmpgtb"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fcmpgeb:
.if TEXT_EMITTER
        .text "        jsr fcmpgeb"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sndsetv:
.if TEXT_EMITTER
        .text "        jsr sndsetv"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sndsetf:
.if TEXT_EMITTER
        .text "        jsr sndsetf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sndsetd:
.if TEXT_EMITTER
        .text "        jsr sndsetd"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sinf:
.if TEXT_EMITTER
        .text "        jsr sinf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cosf:
.if TEXT_EMITTER
        .text "        jsr cosf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_tanf:
.if TEXT_EMITTER
        .text "        jsr tanf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_atnf:
.if TEXT_EMITTER
        .text "        jsr atnf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_logf:
.if TEXT_EMITTER
        .text "        jsr logf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_expf:
.if TEXT_EMITTER
        .text "        jsr expf"
        .byte 13, 0
.else
        .byte 0
.fi
out_rtpb_pre:
.if TEXT_EMITTER
        .text "rtpb = $"
        .byte 0
.else
        .byte 0
.fi
out_rtpb_post:
.if TEXT_EMITTER
        .text "00"
        .byte 13
        .byte 0
.else
        .byte 0
.fi
out_jsr_log10f:
.if TEXT_EMITTER
        .text "        jsr log10f"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_log2f:
.if TEXT_EMITTER
        .text "        jsr log2f"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_modseta:
.if TEXT_EMITTER
        .text "        jsr modseta"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_modf:
.if TEXT_EMITTER
        .text "        jsr modf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sleepf:
.if TEXT_EMITTER
        .text "        jsr sleepf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_waitseta:
.if TEXT_EMITTER
        .text "        jsr waitseta"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_waitsetm:
.if TEXT_EMITTER
        .text "        jsr waitsetm"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_waitsetx:
.if TEXT_EMITTER
        .text "        jsr waitsetx"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_waitgo:
.if TEXT_EMITTER
        .text "        jsr waitgo"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fref:
.if TEXT_EMITTER
        .text "        jsr fref"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_errstrf:
.if TEXT_EMITTER
        .text "        jsr errstrf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_potf:
.if TEXT_EMITTER
        .text "        jsr potf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_lpenf:
.if TEXT_EMITTER
        .text "        jsr lpenf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_rspset:
.if TEXT_EMITTER
        .text "        jsr rspset"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_rspposf:
.if TEXT_EMITTER
        .text "        jsr rspposf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_rspritef:
.if TEXT_EMITTER
        .text "        jsr rspritef"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_rspcolorf:
.if TEXT_EMITTER
        .text "        jsr rspcolorf"
        .byte 13, 0
.else
        .byte 0
.fi
out_xor_lhs_expr:
.if TEXT_EMITTER
        .text "        lda lhslo"
        .byte 13
        .text "        eor exprlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        eor exprhi"
        .byte 13
        .text "        sta exprhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fltsetn:
.if TEXT_EMITTER
        .text "        jsr fltsetn"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fltsetf:
.if TEXT_EMITTER
        .text "        jsr fltsetf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fltsetlp:
.if TEXT_EMITTER
        .text "        jsr fltsetlp"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fltsetbp:
.if TEXT_EMITTER
        .text "        jsr fltsetbp"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fltsethp:
.if TEXT_EMITTER
        .text "        jsr fltsethp"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fltsetres:
.if TEXT_EMITTER
        .text "        jsr fltsetres"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_tempof:
.if TEXT_EMITTER
        .text "        jsr tempof"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_envsetn:
.if TEXT_EMITTER
        .text "        jsr envsetn"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_envseta:
.if TEXT_EMITTER
        .text "        jsr envseta"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_envsetd:
.if TEXT_EMITTER
        .text "        jsr envsetd"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_envsetss:
.if TEXT_EMITTER
        .text "        jsr envsetss"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_envsetr:
.if TEXT_EMITTER
        .text "        jsr envsetr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_envsetw:
.if TEXT_EMITTER
        .text "        jsr envsetw"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_envsetpw:
.if TEXT_EMITTER
        .text "        jsr envsetpw"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_rplayf:
.if TEXT_EMITTER
        .text "        jsr rplayf"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_playarg:
.if TEXT_EMITTER
        .text "        sta playarg"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_playtrk:
.if TEXT_EMITTER
        .text "        jsr playtrk"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_playoff:
.if TEXT_EMITTER
        .text "        jsr playoff"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprsetn:
.if TEXT_EMITTER
        .text "        jsr sprsetn"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprswitch:
.if TEXT_EMITTER
        .text "        jsr sprswitch"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprsetfg:
.if TEXT_EMITTER
        .text "        jsr sprsetfg"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprsetprio:
.if TEXT_EMITTER
        .text "        jsr sprsetprio"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprsetexpx:
.if TEXT_EMITTER
        .text "        jsr sprsetexpx"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprsetexpy:
.if TEXT_EMITTER
        .text "        jsr sprsetexpy"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprsetmode:
.if TEXT_EMITTER
        .text "        jsr sprsetmode"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprsetx:
.if TEXT_EMITTER
        .text "        jsr sprsetx"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_movsprgo:
.if TEXT_EMITTER
        .text "        jsr movsprgo"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprmc1:
.if TEXT_EMITTER
        .text "        jsr sprmc1"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprmc2:
.if TEXT_EMITTER
        .text "        jsr sprmc2"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_joyf:
.if TEXT_EMITTER
        .text "        jsr joyf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_bumpf:
.if TEXT_EMITTER
        .text "        jsr bumpf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sndsetdr:
.if TEXT_EMITTER
        .text "        jsr sndsetdr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sndsetm:
.if TEXT_EMITTER
        .text "        jsr sndsetm"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sndsets:
.if TEXT_EMITTER
        .text "        jsr sndsets"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sndsetw:
.if TEXT_EMITTER
        .text "        jsr sndsetw"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sndsetp:
.if TEXT_EMITTER
        .text "        jsr sndsetp"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sndgo:
.if TEXT_EMITTER
        .text "        jsr sndgo"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_volsnd:
.if TEXT_EMITTER
        .text "        jsr volsnd"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_traplo:
.if TEXT_EMITTER
        .text "        sta traplo"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_traphi:
.if TEXT_EMITTER
        .text "        sta traphi"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_curline:
.if TEXT_EMITTER
        .text "        sta curline"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_curline_1:
.if TEXT_EMITTER
        .text "        sta curline+1"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_trapoff:
.if TEXT_EMITTER
        .text "        jsr trapoff"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_trapresume:
.if TEXT_EMITTER
        .text "        jsr trapresume"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_rder:
.if TEXT_EMITTER
        .text "        jsr rder"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_rdel:
.if TEXT_EMITTER
        .text "        jsr rdel"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fiodefaults:
.if TEXT_EMITTER
        .text "        jsr fiodefaults"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fiosetlf:
.if TEXT_EMITTER
        .text "        jsr fiosetlf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fiosetdev:
.if TEXT_EMITTER
        .text "        jsr fiosetdev"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fiosetsa:
.if TEXT_EMITTER
        .text "        jsr fiosetsa"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fiosetname:
.if TEXT_EMITTER
        .text "        jsr fiosetname"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fopen:
.if TEXT_EMITTER
        .text "        jsr fopen"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fclose:
.if TEXT_EMITTER
        .text "        jsr fclose"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fiochkout:
.if TEXT_EMITTER
        .text "        jsr fiochkout"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fiochkin:
.if TEXT_EMITTER
        .text "        jsr fiochkin"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fiodone:
.if TEXT_EMITTER
        .text "        jsr fiodone"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fioreadline:
.if TEXT_EMITTER
        .text "        jsr fioreadline"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fiogetbyte:
.if TEXT_EMITTER
        .text "        jsr fiogetbyte"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fiogetstr:
.if TEXT_EMITTER
        .text "        jsr fiogetstr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_rdst:
.if TEXT_EMITTER
        .text "        jsr rdst"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fpowi:
.if TEXT_EMITTER
        .text "        jsr fpowi"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_rdti:
.if TEXT_EMITTER
        .text "        jsr rdti"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_mousetp:
.if TEXT_EMITTER
        .text "        jsr mousetp"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_mousets:
.if TEXT_EMITTER
        .text "        jsr mousets"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_mousetx:
.if TEXT_EMITTER
        .text "        jsr mousetx"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_mousety:
.if TEXT_EMITTER
        .text "        jsr mousety"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_mouseon:
.if TEXT_EMITTER
        .text "        jsr mouseon"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_mouseoff:
.if TEXT_EMITTER
        .text "        jsr mouseoff"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_rmousef:
.if TEXT_EMITTER
        .text "        jsr rmousef"
        .byte 13, 0
.else
        .byte 0
.fi
out_ld_mourx:
.if TEXT_EMITTER
        .text "        lda mourx"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda mourx+1"
        .byte 13
        .text "        sta exprhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_ld_moury:
.if TEXT_EMITTER
        .text "        lda moury"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda moury+1"
        .byte 13
        .text "        sta exprhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_ld_mourb:
.if TEXT_EMITTER
        .text "        lda mourb"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda mourb+1"
        .byte 13
        .text "        sta exprhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cmdpre:
.if TEXT_EMITTER
        .text "        jsr cmdpre"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cmdstr:
.if TEXT_EMITTER
        .text "        jsr cmdstr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cmdeq:
.if TEXT_EMITTER
        .text "        jsr cmdeq"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_curinit:
.if TEXT_EMITTER
        .text "        jsr curinit"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cursetc:
.if TEXT_EMITTER
        .text "        jsr cursetc"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cursetr:
.if TEXT_EMITTER
        .text "        jsr cursetr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_curgo:
.if TEXT_EMITTER
        .text "        jsr curgo"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_curcolf:
.if TEXT_EMITTER
        .text "        jsr curcolf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_currowf:
.if TEXT_EMITTER
        .text "        jsr currowf"
        .byte 13, 0
.else
        .byte 0
.fi
out_linetab_label:
.if TEXT_EMITTER
        .text "linetab:"
        .byte 13
        .byte 0
.else
        .byte 0
.fi
out_word_pre:
.if TEXT_EMITTER
        .text "        .word $"
        .byte 0
.else
        .byte 0
.fi
out_lineref_sep:
.if TEXT_EMITTER
        .text ", l"
        .byte 0
.else
        .byte 0
.fi
out_gfxflag_pre:
.if TEXT_EMITTER
        .text "gfxflag = $"
        .byte 0
.else
        .byte 0
.fi
out_jsr_gfxlnext:
.if TEXT_EMITTER
        .text "        jsr gfxlnext"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_rpenf:
.if TEXT_EMITTER
        .text "        jsr rpenf"
        .byte 13, 0
.else
        .byte 0
.fi
out_pixel_res:
.if TEXT_EMITTER
        .text "        lda gfxres"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .byte 0
.else
        .byte 0
.fi
out_jsr_rcolorf:
.if TEXT_EMITTER
        .text "        jsr rcolorf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_getkeyw:
.if TEXT_EMITTER
        .text "        jsr getkeyw"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_getstrw:
.if TEXT_EMITTER
        .text "        jsr getstrw"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_charstage:
.if TEXT_EMITTER
        .text "        jsr charstage"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_hasbitf:
.if TEXT_EMITTER
        .text "        jsr hasbitf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_rwindowf:
.if TEXT_EMITTER
        .text "        jsr rwindowf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_rptf:
.if TEXT_EMITTER
        .text "        jsr rptf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fnsave:
.if TEXT_EMITTER
        .text "        jsr fnsave"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fnrest:
.if TEXT_EMITTER
        .text "        jsr fnrest"
        .byte 13, 0
.else
        .byte 0
.fi
out_fnlab_prefix:
.if TEXT_EMITTER
        .text "fnlab"
        .byte 0
.else
        .byte 0
.fi
out_jsr_penset:
.if TEXT_EMITTER
        .text "        jsr penset"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_gfxcall:
.if TEXT_EMITTER
        .text "        jsr gfxcall"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strtpush:
.if TEXT_EMITTER
        .text "        jsr strtpush"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strtpop:
.if TEXT_EMITTER
        .text "        jsr strtpop"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_bitadr16:
.if TEXT_EMITTER
        .text "        jsr bitadr16"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_bitadr32:
.if TEXT_EMITTER
        .text "        jsr bitadr32"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_setbitgo:
.if TEXT_EMITTER
        .text "        jsr setbitgo"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_clrbitgo:
.if TEXT_EMITTER
        .text "        jsr clrbitgo"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprsava:
.if TEXT_EMITTER
        .text "        jsr sprsava"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprsavs:
.if TEXT_EMITTER
        .text "        jsr sprsavs"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprsavdn:
.if TEXT_EMITTER
        .text "        jsr sprsavdn"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprsavstr:
.if TEXT_EMITTER
        .text "        jsr sprsavstr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_bootgo:
.if TEXT_EMITTER
        .text "        jsr bootgo"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_vsync:
.if TEXT_EMITTER
        .text "        jsr vsync"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_bankset:
.if TEXT_EMITTER
        .text "        jsr bankset"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_pokebk:
.if TEXT_EMITTER
        .text "        jsr pokebk"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_wpokebk:
.if TEXT_EMITTER
        .text "        jsr wpokebk"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_peekbk:
.if TEXT_EMITTER
        .text "        jsr peekbk"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_wpeekbk:
.if TEXT_EMITTER
        .text "        jsr wpeekbk"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sysregsave:
.if TEXT_EMITTER
        .text "        jsr sysregsave"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_rregn:
.if TEXT_EMITTER
        .text "        jsr rregn"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_dmarst:
.if TEXT_EMITTER
        .text "        jsr dmarst"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_dmaa16:
.if TEXT_EMITTER
        .text "        jsr dmaa16"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_dmaa32:
.if TEXT_EMITTER
        .text "        jsr dmaa32"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_dmago:
.if TEXT_EMITTER
        .text "        jsr dmago"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_edmago:
.if TEXT_EMITTER
        .text "        jsr edmago"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fgoto:
.if TEXT_EMITTER
        .text "        jsr fgoto"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fgosub:
.if TEXT_EMITTER
        .text "        jsr fgosub"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_pif:
.if TEXT_EMITTER
        .text "        jsr pif"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_dskst:
.if TEXT_EMITTER
        .text "        jsr dskst"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_chrstrf:
.if TEXT_EMITTER
        .text "        jsr chrstrf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_keysetn:
.if TEXT_EMITTER
        .text "        jsr keysetn"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_keysetgo:
.if TEXT_EMITTER
        .text "        jsr keysetgo"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_winrst:
.if TEXT_EMITTER
        .text "        jsr winrst"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_winarg:
.if TEXT_EMITTER
        .text "        jsr winarg"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_wingo:
.if TEXT_EMITTER
        .text "        jsr wingo"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cmdcat:
.if TEXT_EMITTER
        .text "        jsr cmdcat"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cmdstash:
.if TEXT_EMITTER
        .text "        jsr cmdstash"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cmdstashout:
.if TEXT_EMITTER
        .text "        jsr cmdstashout"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cmdgo:
.if TEXT_EMITTER
        .text "        jsr cmdgo"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_rdds:
.if TEXT_EMITTER
        .text "        jsr rdds"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_dsstrf:
.if TEXT_EMITTER
        .text "        jsr dsstrf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_bladdr:
.if TEXT_EMITTER
        .text "        jsr bladdr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_blend:
.if TEXT_EMITTER
        .text "        jsr blend"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_bloadgo:
.if TEXT_EMITTER
        .text "        jsr bloadgo"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_bsavego:
.if TEXT_EMITTER
        .text "        jsr bsavego"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_dopmode:
.if TEXT_EMITTER
        .text "        jsr dopmode"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_dclosech:
.if TEXT_EMITTER
        .text "        jsr dclosech"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_decbinf:
.if TEXT_EMITTER
        .text "        jsr decbinf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_strbinf:
.if TEXT_EMITTER
        .text "        jsr strbinf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprsetxr:
.if TEXT_EMITTER
        .text "        jsr sprsetxr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprsetyr:
.if TEXT_EMITTER
        .text "        jsr sprsetyr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprsettx:
.if TEXT_EMITTER
        .text "        jsr sprsettx"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprsetty:
.if TEXT_EMITTER
        .text "        jsr sprsetty"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprgoto:
.if TEXT_EMITTER
        .text "        jsr sprgoto"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sprgoang:
.if TEXT_EMITTER
        .text "        jsr sprgoang"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_bdrset:
.if TEXT_EMITTER
        .text "        jsr bdrset"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_bkgset:
.if TEXT_EMITTER
        .text "        jsr bkgset"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_fgset:
.if TEXT_EMITTER
        .text "        jsr fgset"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_chsetidx:
.if TEXT_EMITTER
        .text "        jsr chsetidx"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_chputb:
.if TEXT_EMITTER
        .text "        jsr chputb"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_tcsetc:
.if TEXT_EMITTER
        .text "        jsr tcsetc"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_tcsetr:
.if TEXT_EMITTER
        .text "        jsr tcsetr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_tscrf:
.if TEXT_EMITTER
        .text "        jsr tscrf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_tscrw:
.if TEXT_EMITTER
        .text "        jsr tscrw"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cscrf:
.if TEXT_EMITTER
        .text "        jsr cscrf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cscrw:
.if TEXT_EMITTER
        .text "        jsr cscrw"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_colsett:
.if TEXT_EMITTER
        .text "        jsr colsett"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_colarm:
.if TEXT_EMITTER
        .text "        jsr colarm"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_coloff:
.if TEXT_EMITTER
        .text "        jsr coloff"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_colcheck:
.if TEXT_EMITTER
        .text "        jsr colcheck"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_coltmp:
.if TEXT_EMITTER
        .text "        sta coltmp"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_coltmp1:
.if TEXT_EMITTER
        .text "        sta coltmp+1"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_usrf:
.if TEXT_EMITTER
        .text "        jsr usrf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_tistr:
.if TEXT_EMITTER
        .text "        jsr tistr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_clrti:
.if TEXT_EMITTER
        .text "        jsr clrti"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_rtclr:
.if TEXT_EMITTER
        .text "        jsr rtclr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_hexstr:
.if TEXT_EMITTER
        .text "        jsr hexstr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_decstr:
.if TEXT_EMITTER
        .text "        jsr decstr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_instrf:
.if TEXT_EMITTER
        .text "        jsr instrf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_rndf:
.if TEXT_EMITTER
        .text "        jsr rndf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_sqrf:
.if TEXT_EMITTER
        .text "        jsr sqrf"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_ascstr:
.if TEXT_EMITTER
        .text "        jsr ascstr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_tabto:
.if TEXT_EMITTER
        .text "        jsr tabto"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_spcn:
.if TEXT_EMITTER
        .text "        jsr spcn"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_posf:
.if TEXT_EMITTER
        .text "        jsr posf"
        .byte 13, 0
.else
        .byte 0
.fi
out_fltinit_label:
.if TEXT_EMITTER
        .text "; float literal slots"
        .byte 13
        .text "fltlits:"
        .byte 13, 0
.else
        .byte 0
.fi
out_word_hex_prefix:
.if TEXT_EMITTER
        .text "        .word $"
        .byte 0
.else
        .byte 0
.fi
out_jsr_readint:
.if TEXT_EMITTER
        .text "        jsr readint"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_readstr:
.if TEXT_EMITTER
        .text "        jsr readstr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_inputline:
.if TEXT_EMITTER
        .text "        jsr inputline"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_inputlinenq:
.if TEXT_EMITTER
        .text "        jsr inputlinenq"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_inputline2q:
.if TEXT_EMITTER
        .text "        jsr inputline2q"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_inputraw:
.if TEXT_EMITTER
        .text "        jsr inputraw"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_inputint:
.if TEXT_EMITTER
        .text "        jsr inputint"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_inputstr:
.if TEXT_EMITTER
        .text "        jsr inputstr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_getkey:
.if TEXT_EMITTER
        .text "        jsr getkey"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_getstr:
.if TEXT_EMITTER
        .text "        jsr getstr"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_datainit:
.if TEXT_EMITTER
        .text "        jsr datainit"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cmpeq:
.if TEXT_EMITTER
        .text "        jsr cmpeq"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cmpne:
.if TEXT_EMITTER
        .text "        jsr cmpne"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cmplt:
.if TEXT_EMITTER
        .text "        jsr cmplt"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cmple:
.if TEXT_EMITTER
        .text "        jsr cmple"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cmpgt:
.if TEXT_EMITTER
        .text "        jsr cmpgt"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_cmpge:
.if TEXT_EMITTER
        .text "        jsr cmpge"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_varptr:
.if TEXT_EMITTER
        .text "        sta varptr"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_varptr_1:
.if TEXT_EMITTER
        .text "        sta varptr+1"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_exprlo:
.if TEXT_EMITTER
        .text "        sta exprlo"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_exprhi:
.if TEXT_EMITTER
        .text "        sta exprhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_dataptrlo:
.if TEXT_EMITTER
        .text "        sta dataptrlo"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_dataptrhi:
.if TEXT_EMITTER
        .text "        sta dataptrhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_rtptr:
.if TEXT_EMITTER
        .text "        sta rtptr"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_rtptr_1:
.if TEXT_EMITTER
        .text "        sta rtptr+1"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_strarg1lo:
.if TEXT_EMITTER
        .text "        sta strarg1lo"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_strarg1hi:
.if TEXT_EMITTER
        .text "        sta strarg1hi"
        .byte 13, 0
.else
        .byte 0
.fi
out_lda_exprlo:
.if TEXT_EMITTER
        .text "        lda exprlo"
        .byte 13, 0
.else
        .byte 0
.fi
out_lda_exprhi:
.if TEXT_EMITTER
        .text "        lda exprhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_array_check_start:
.if TEXT_EMITTER
        .text "        lda exprhi"
        .byte 13
        .text "        bpl "
        .byte 0
.else
        .byte 0
.fi
out_cmp_exprhi_imm:
.if TEXT_EMITTER
        .text "        cmp #$"
        .byte 0
.else
        .byte 0
.fi
out_cmp_exprlo_imm:
.if TEXT_EMITTER
        .text "        lda exprlo"
        .byte 13
        .text "        cmp #$"
        .byte 0
.else
        .byte 0
.fi
out_jmp_arraybounds:
.if TEXT_EMITTER
        .text "        jmp arraybounds"
        .byte 13, 0
.else
        .byte 0
.fi
out_array_index_shift5:
.if TEXT_EMITTER
        .text "        lda exprlo"
        .byte 13
        .text "        sta lhslo"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sta lhshi"
        .byte 13
        .text "        asl exprlo"
        .byte 13
        .text "        rol exprhi"
        .byte 13
        .text "        asl exprlo"
        .byte 13
        .text "        rol exprhi"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        adc lhslo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        adc lhshi"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        lda exprlo"
        .byte 13, 0
.else
        .byte 0
.fi

out_array_index_shift:
.if TEXT_EMITTER
        .text "        asl exprlo"
        .byte 13
        .text "        rol exprhi"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        lda exprlo"
        .byte 13, 0
.else
        .byte 0
.fi
out_save_arrayptr:
.if TEXT_EMITTER
        .text "        lda varptr"
        .byte 13
        .text "        sta arrptrlo"
        .byte 13
        .text "        lda varptr+1"
        .byte 13
        .text "        sta arrptrhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_restore_arrayptr:
.if TEXT_EMITTER
        .text "        lda arrptrlo"
        .byte 13
        .text "        sta varptr"
        .byte 13
        .text "        lda arrptrhi"
        .byte 13
        .text "        sta varptr+1"
        .byte 13, 0
.else
        .byte 0
.fi
out_lda_label:
.if TEXT_EMITTER
        .text "        lda "
        .byte 0
.else
        .byte 0
.fi
out_sta_label:
.if TEXT_EMITTER
        .text "        sta "
        .byte 0
.else
        .byte 0
.fi
out_forend_prefix:
.if TEXT_EMITTER
        .text "forend"
        .byte 0
.else
        .byte 0
.fi
out_forstep_prefix:
.if TEXT_EMITTER
        .text "forstep"
        .byte 0
.else
        .byte 0
.fi
out_fortop_prefix:
.if TEXT_EMITTER
        .text "fortop"
        .byte 0
.else
        .byte 0
.fi
out_forneg_prefix:
.if TEXT_EMITTER
        .text "forneg"
        .byte 0
.else
        .byte 0
.fi
out_forinitneg_prefix:
.if TEXT_EMITTER
        .text "forinitneg"
        .byte 0
.else
        .byte 0
.fi
out_forcont_prefix:
.if TEXT_EMITTER
        .text "forcont"
        .byte 0
.else
        .byte 0
.fi
out_fordone_prefix:
.if TEXT_EMITTER
        .text "fordone"
        .byte 0
.else
        .byte 0
.fi
out_dotop_prefix:
.if TEXT_EMITTER
        .text "dotop"
        .byte 0
.else
        .byte 0
.fi
out_dodone_prefix:
.if TEXT_EMITTER
        .text "dodone"
        .byte 0
.else
        .byte 0
.fi
out_iftrue_prefix:
.if TEXT_EMITTER
        .text "iftrue"
        .byte 0
.else
        .byte 0
.fi
out_ifskip_prefix:
.if TEXT_EMITTER
        .text "ifskip"
        .byte 0
.else
        .byte 0
.fi
out_ifend_prefix:
.if TEXT_EMITTER
        .text "ifend"
        .byte 0
.else
        .byte 0
.fi
out_ifelse_prefix:
.if TEXT_EMITTER
        .text "ifelse"
        .byte 0
.else
        .byte 0
.fi
out_iftmp_prefix:
.if TEXT_EMITTER
        .text "iftmp"
        .byte 0
.else
        .byte 0
.fi
out_arrayok_prefix:
.if TEXT_EMITTER
        .text "arrayok"
        .byte 0
.else
        .byte 0
.fi
out_arraynonneg_prefix:
.if TEXT_EMITTER
        .text "arraypos"
        .byte 0
.else
        .byte 0
.fi
out_arrayhieq_prefix:
.if TEXT_EMITTER
        .text "arrayhieq"
        .byte 0
.else
        .byte 0
.fi
out_onnext_prefix:
.if TEXT_EMITTER
        .text "onnext"
        .byte 0
.else
        .byte 0
.fi
out_ondone_prefix:
.if TEXT_EMITTER
        .text "ondone"
        .byte 0
.else
        .byte 0
.fi
out_push_expr:
.if TEXT_EMITTER
        .text "        lda exprlo"
        .byte 13
        .text "        pha"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        pha"
        .byte 13, 0
.else
        .byte 0
.fi
out_pop_lhs:
.if TEXT_EMITTER
        .text "        pla"
        .byte 13
        .text "        sta lhshi"
        .byte 13
        .text "        pla"
        .byte 13
        .text "        sta lhslo"
        .byte 13, 0
.else
        .byte 0
.fi
out_and_lhs_expr:
.if TEXT_EMITTER
        .text "        lda lhslo"
        .byte 13
        .text "        and exprlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        and exprhi"
        .byte 13
        .text "        sta exprhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_or_lhs_expr:
.if TEXT_EMITTER
        .text "        lda lhslo"
        .byte 13
        .text "        ora exprlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        ora exprhi"
        .byte 13
        .text "        sta exprhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_move_expr_to_lhs:
.if TEXT_EMITTER
        .text "        lda exprlo"
        .byte 13
        .text "        sta lhslo"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sta lhshi"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_lhslo:
.if TEXT_EMITTER
        .text "        sta lhslo"
        .byte 13, 0
.else
        .byte 0
.fi
out_sta_lhshi:
.if TEXT_EMITTER
        .text "        sta lhshi"
        .byte 13, 0
.else
        .byte 0
.fi
out_add_lhs_expr:
.if TEXT_EMITTER
        .text "        clc"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        adc exprlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        adc exprhi"
        .byte 13
        .text "        sta exprhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_sub_lhs_expr:
.if TEXT_EMITTER
        .text "        sec"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        sbc exprlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        sbc exprhi"
        .byte 13
        .text "        sta exprhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_mul16:
.if TEXT_EMITTER
        .text "        jsr mul16"
        .byte 13, 0
.else
        .byte 0
.fi
out_jsr_div16:
.if TEXT_EMITTER
        .text "        jsr div16"
        .byte 13, 0
.else
        .byte 0
.fi
out_neg_expr:
.if TEXT_EMITTER
        .text "        sec"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sbc exprlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sbc exprhi"
        .byte 13
        .text "        sta exprhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_expr_to_rtptr:
.if TEXT_EMITTER
        .text "        lda exprlo"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13, 0
.else
        .byte 0
.fi
out_save_rtptr:
.if TEXT_EMITTER
        .text "        lda rtptr"
        .byte 13
        .text "        sta arrptrlo"
        .byte 13
        .text "        lda rtptr+1"
        .byte 13
        .text "        sta arrptrhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_restore_rtptr:
.if TEXT_EMITTER
        .text "        lda arrptrlo"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda arrptrhi"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13, 0
.else
        .byte 0
.fi
out_poke_expr_to_rtptr:
.if TEXT_EMITTER
        .text "        lda exprlo"
        .byte 13
        .text "        ldy #0"
        .byte 13
        .text "        sta (rtptr),y"
        .byte 13, 0
.else
        .byte 0
.fi
out_wpoke_expr_to_rtptr:
.if TEXT_EMITTER
        .text "        lda exprlo"
        .byte 13
        .text "        ldy #0"
        .byte 13
        .text "        sta (rtptr),y"
        .byte 13
        .text "        iny"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sta (rtptr),y"
        .byte 13, 0
.else
        .byte 0
.fi
out_peek_expr:
.if TEXT_EMITTER
        .text "        lda exprlo"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13
        .text "        ldy #0"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_wpeek_expr:
.if TEXT_EMITTER
        .text "        lda exprlo"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13
        .text "        ldy #0"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        iny"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        sta exprhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_cmp_lhshi_exprhi:
.if TEXT_EMITTER
        .text "        lda lhshi"
        .byte 13
        .text "        cmp exprhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_cmp_lhslo_exprlo:
.if TEXT_EMITTER
        .text "        lda lhslo"
        .byte 13
        .text "        cmp exprlo"
        .byte 13, 0
.else
        .byte 0
.fi
out_sign_xor_lhshi_exprhi:
.if TEXT_EMITTER
        .text "        lda lhshi"
        .byte 13
        .text "        eor exprhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_lda_lhshi:
.if TEXT_EMITTER
        .text "        lda lhshi"
        .byte 13, 0
.else
        .byte 0
.fi
out_lda_lhslo:
.if TEXT_EMITTER
        .text "        lda lhslo"
        .byte 13, 0
.else
        .byte 0
.fi
out_ora_lhshi:
.if TEXT_EMITTER
        .text "        ora lhshi"
        .byte 13, 0
.else
        .byte 0
.fi
out_ora_exprhi:
.if TEXT_EMITTER
        .text "        ora exprhi"
        .byte 13, 0
.else
        .byte 0
.fi
out_jmp_label:
.if TEXT_EMITTER
        .text "        jmp "
        .byte 0
.else
        .byte 0
.fi
out_jsr_label:
.if TEXT_EMITTER
        .text "        jsr "
        .byte 0
.else
        .byte 0
.fi
out_bne_label:
.if TEXT_EMITTER
        .text "        bne "
        .byte 0
.else
        .byte 0
.fi
out_beq_label:
.if TEXT_EMITTER
        .text "        beq "
        .byte 0
.else
        .byte 0
.fi
out_bcc_label:
.if TEXT_EMITTER
        .text "        bcc "
        .byte 0
.else
        .byte 0
.fi
out_bcs_label:
.if TEXT_EMITTER
        .text "        bcs "
        .byte 0
.else
        .byte 0
.fi
out_bpl_label:
.if TEXT_EMITTER
        .text "        bpl "
        .byte 0
.else
        .byte 0
.fi
out_bmi_label:
.if TEXT_EMITTER
        .text "        bmi "
        .byte 0
.else
        .byte 0
.fi
out_jsr_abs:
.if TEXT_EMITTER
        .text "        jsr $"
        .byte 0
.else
        .byte 0
.fi
out_sta_abs:
.if TEXT_EMITTER
        .text "        sta $"
        .byte 0
.else
        .byte 0
.fi
out_rts:
.if TEXT_EMITTER
        .text "        rts"
        .byte 13, 0
.else
        .byte 0
.fi
out_jmp_rtexit:
.if TEXT_EMITTER
        .text "        jmp rtexit"
        .byte 13, 0
.else
        .byte 0
.fi
out_rem:
.if TEXT_EMITTER
        .text "        ; rem"
        .byte 0
.else
        .byte 0
.fi
out_data_comment:
.if TEXT_EMITTER
        .text "        ; data skipped"
        .byte 13, 0
.else
        .byte 0
.fi
out_dim_comment:
.if TEXT_EMITTER
        .text "        ; dim allocated in variable heap"
        .byte 13, 0
.else
        .byte 0
.fi
;=======================================================================================
; State
;=======================================================================================

prg_load_lo:
        .byte 0
prg_load_hi:
        .byte 0
source_end_lo:
        .byte 0
source_end_hi:
        .byte 0
next_line_lo:
        .byte 0
next_line_hi:
        .byte 0
line_no_lo:
        .byte 0
line_no_hi:
        .byte 0
line_len:
        .byte 0
line_idx:
        .byte 0
line_idx_save:
        .byte 0
line_had_colon:
        .byte 0
line_overflow:
        .byte 0
compile_error:
        .byte 0
error_count:
        .byte 0
compile_stop_on_else:
        .byte 0
compile_found_else:
        .byte 0
if_else_found:
        .byte 0
token_value:
        .byte 0
token_prefix:
        .byte 0
var_name_1:
        .byte 0
var_name_2:
        .byte 0
var_kind:
        .byte 0
var_type:
        .byte 0
current_var_data_lo:
        .byte 0
current_var_data_hi:
        .byte 0
current_sym_index:
        .byte 0
array_base_lo:
        .byte 0
array_base_hi:
        .byte 0
array_rank:
        .byte 0
array_dim_index:
        .byte 0
array_sym_index:
        .byte 0
array_dim_lo:
        .byte 0
array_dim_hi:
        .byte 0
array_product_lo:
        .byte 0
array_product_hi:
        .byte 0
assign_var_data_lo:
        .byte 0
assign_var_data_hi:
        .byte 0
assign_var_type:
        .byte 0
var_heap_next_lo:
        .byte 0
var_heap_next_hi:
        .byte 0
sym_count:
        .byte 0
line_count:
        .byte 0, 0
branch_count:
        .byte 0
cond_op:
        .byte 0
if_label_next_lo:
        .byte 0
if_label_next_hi:
        .byte 0
array_label_next_lo:
        .byte 0
array_label_next_hi:
        .byte 0
on_label_next_lo:
        .byte 0
on_label_next_hi:
        .byte 0
array_ok_lo:
        .byte 0
array_ok_hi:
        .byte 0
on_label_lo:
        .byte 0
on_label_hi:
        .byte 0
on_done_lo:
        .byte 0
on_done_hi:
        .byte 0
on_target_lo:
        .byte 0
on_target_hi:
        .byte 0
on_target_index:
        .byte 0
on_mode:
        .byte 0
if_true_lo:
        .byte 0
if_true_hi:
        .byte 0
if_skip_lo:
        .byte 0
if_skip_hi:
        .byte 0
if_end_lo:
        .byte 0
if_end_hi:
        .byte 0
if_else_lo:
        .byte 0
if_else_hi:
        .byte 0
if_tmp_lo:
        .byte 0
if_tmp_hi:
        .byte 0
if_target_lo:
        .byte 0
if_target_hi:
        .byte 0
if_sp:
        .byte 0
for_label_next:
        .byte 0
do_label_next:
        .byte 0
for_sp:
        .byte 0
do_sp:
        .byte 0
for_storage_idx:
        .byte 0
data_count:
        .byte 0
data_line_count:
        .byte 0
data_emit_idx:
        .byte 0
data_line_emit_idx:
        .byte 0
root_emit_idx:
        .byte 0
data_sign:
        .byte 0
read_target_type:
        .byte 0
string_count:
        .byte 0
string_emit_idx:
        .byte 0
current_string_id:
        .byte 0
string_match_idx:
        .byte 0
string_temp_idx:
        .byte 0
string_temp_len:
        .byte 0
string_ref_type:
        .byte 0
string_ref_left_type:
        .byte 0
string_ref_right_type:
        .byte 0
string_pool_next_lo:
        .byte 0
string_pool_next_hi:
        .byte 0
string_read_lo:
        .byte 0
string_read_hi:
        .byte 0
strheaplo:
        .byte 0
strheaphi:
        .byte 0
strlen:
        .byte 0
strlen1:
        .byte 0
strlen2:
        .byte 0
stridx:
        .byte 0
strdstidx:
        .byte 0
strsrc1lo:
        .byte 0
strsrc1hi:
        .byte 0
strsrc2lo:
        .byte 0
strsrc2hi:
        .byte 0
strdstlo:
        .byte 0
strdsthi:
        .byte 0
current_for_id:
        .byte 0
current_do_id:
        .byte 0
current_for_var_data_lo:
        .byte 0
current_for_var_data_hi:
        .byte 0
current_for_var_type:
        .byte 0
number_lo:
        .byte 0
number_hi:
        .byte 0
number_digits:
        .byte 0
digit_value:
        .byte 0
work_lo:
        .byte 0
work_hi:
        .byte 0
work2_lo:
        .byte 0
work2_hi:
        .byte 0
byte_value:
        .byte 0
disk_status:
        .byte 0
print_suppress_cr:
        .byte 0
poke_addr_lo:
        .byte 0
poke_addr_hi:
        .byte 0
screen_num_lo:
        .byte 0
screen_num_hi:
        .byte 0
screen_div_lo:
        .byte 0
screen_div_hi:
        .byte 0
screen_digit_value:
        .byte 0
screen_started:
        .byte 0
diag_msg_lo:
        .byte 0
diag_msg_hi:
        .byte 0
backend_mode:
        .byte 0
backend_error:
        .byte 0
backend_error_ptr:
        .word 0
pending_kind:
        .byte 0
pending_value:
        .word 0
bin_pc:
        .word 0
bin_size_end:
        .word 0
bin_key_lo:
        .byte 0
bin_key_hi:
        .byte 0
bin_tbl:
        .byte 0
bin_copy_cnt:
        .byte 0
for_storage_addr:
        .word 0
rt_status:
        .byte 0
rt_chunk_len:
        .byte 0
probe_mode:
        .byte 0
BEGIN_STACK_MAX = 8
begin_sp:
        .byte 0
io_from_file:
        .byte 0
input_raw_mode:
        .byte 0
trap_used:
        .byte 0
play_track_no:
        .byte 0
snd_used:
        .byte 0
col_used:
        .byte 0
fio_used:
        .byte 0
math_used:
        .byte 0
fgoto_used:
        .byte 0
bank_used:
        .byte 0
gfx_used:
        .byte 0
cdma_i:
        .byte 0
sprsav_save:
        .byte 0
cdma_go:
        .byte 0,0
cmd2_tail:
        .byte 0,0
scrarr_kind:
        .byte 0
scrarr_save:
        .byte 0
scrarr_chr:
        .byte 0
brtab_lo:
        .byte 0
brtab_hi:
        .byte 0
pool_save:
        .byte 0,0,0,0
scan_ext_prefix:
        .byte 0
scan_pmode:
        .byte 0
d030_save:
        .byte 0
get_blocking:
        .byte 0
rt_first_chunk:
        .byte 0
rt_first_write:
        .byte 0
ds_first:
        .byte 0
cc_mode:
        .byte 0
prog_base_hi:
        .byte 0
rt_level:
        .byte 0
rt_trunc:
        .byte 0,0
rtpbtab:
        .byte >((RT_END_CORE + $00ff) & $ff00)
        .byte >((RT_END_FIO + $00ff) & $ff00)
        .byte >((RT_END_MATH + $00ff) & $ff00)
        .byte >((RT_END_SOUND + $00ff) & $ff00)
rttrunclo:
        .byte <RT_END_CORE, <RT_END_FIO, <RT_END_MATH, <RT_END_SOUND
rttrunchi:
        .byte >RT_END_CORE, >RT_END_FIO, >RT_END_MATH, >RT_END_SOUND

if_begin_taken:
        .byte 0
if_block_open:
        .byte 0
begin_stack_else_lo:
        .fill BEGIN_STACK_MAX, 0
begin_stack_else_hi:
        .fill BEGIN_STACK_MAX, 0
begin_stack_end_lo:
        .fill BEGIN_STACK_MAX, 0
begin_stack_end_hi:
        .fill BEGIN_STACK_MAX, 0
probe_saved_idx:
        .byte 0
const_state:
        .byte 0
const_lo:
        .byte 0
const_hi:
        .byte 0
fold_lhs_lo:
        .byte 0
fold_lhs_hi:
        .byte 0
fold_res_lo:
        .byte 0
fold_res_hi:
        .byte 0
fold_rem_lo:
        .byte 0
fold_rem_hi:
        .byte 0
fold_ret_lo:
        .byte 0
fold_ret_hi:
        .byte 0
expr_type:
        .byte 0
flt_saved_idx:
        .byte 0
flt_lit_count:
        .byte 0
fltinit_addr:
        .word 0
FLT_LIT_MAX = 64
datastart_addr:
        .word 0
dataend_addr:
        .word 0
strroots_addr:
        .word 0
linetab_addr:
        .word 0
; (scratch tables moved to the image tail -- see below)
string_pool:

;=======================================================================================
; Binary backend label address tables, filled during the size pass and read
; during the emit pass. Generated-label ids above LBL_ID_MAX set
; backend_error (the text backend is unaffected).
;=======================================================================================

LBL_IF_IDS      = 384
LBL_ON_IDS      = 128
LBL_ARRAY_IDS   = 256
.if TEXT_EMITTER
LBL_FORDO_MAX   = 48            ; checked build: restored (tables live high)
.else
LBL_FORDO_MAX   = 48
.fi

; iftrue/ifskip/ifend/ifelse/iftmp draw distinct ids from one shared counter,
; so a single table keyed by id covers all five kinds; same for onnext/ondone.
; The three array labels of one bounds check share a single id, so they need
; a table per kind.
LBL_IF          = 0
LBL_ON          = 1
LBL_ARRAYOK     = 2
LBL_ARRAYPOS    = 3
LBL_ARRAYHIEQ   = 4
LBL_FORTOP      = 5
LBL_FORNEG      = 6
LBL_FORINITNEG  = 7
LBL_FORCONT     = 8
LBL_FORDONE     = 9
LBL_DOTOP       = 10
LBL_DODONE      = 11

; label tables live in bank 4 at LBLTAB_BASE; these are offsets
LBLTAB_BASE     = $E000
lbloff_if        = 0
lbloff_on        = lbloff_if + LBL_IF_IDS * 2
lbloff_arrayok   = lbloff_on + LBL_ON_IDS * 2
lbloff_arraypos  = lbloff_arrayok + LBL_ARRAY_IDS * 2
lbloff_arrayhieq = lbloff_arraypos + LBL_ARRAY_IDS * 2
lbloff_fortop    = lbloff_arrayhieq + LBL_ARRAY_IDS * 2
lbloff_forneg    = lbloff_fortop + LBL_FORDO_MAX * 2
lbloff_forinitneg = lbloff_forneg + LBL_FORDO_MAX * 2
lbloff_forcont   = lbloff_forinitneg + LBL_FORDO_MAX * 2
lbloff_fordone   = lbloff_forcont + LBL_FORDO_MAX * 2
lbloff_dotop     = lbloff_fordone + LBL_FORDO_MAX * 2
lbloff_dodone    = lbloff_dotop + LBL_FORDO_MAX * 2

lbladdr_base_lo:
        .byte <(LBLTAB_BASE+lbloff_if), <(LBLTAB_BASE+lbloff_on)
        .byte <(LBLTAB_BASE+lbloff_arrayok), <(LBLTAB_BASE+lbloff_arraypos), <(LBLTAB_BASE+lbloff_arrayhieq)
        .byte <(LBLTAB_BASE+lbloff_fortop), <(LBLTAB_BASE+lbloff_forneg), <(LBLTAB_BASE+lbloff_forinitneg)
        .byte <(LBLTAB_BASE+lbloff_forcont), <(LBLTAB_BASE+lbloff_fordone)
        .byte <(LBLTAB_BASE+lbloff_dotop), <(LBLTAB_BASE+lbloff_dodone)
lbladdr_base_hi:
        .byte >(LBLTAB_BASE+lbloff_if), >(LBLTAB_BASE+lbloff_on)
        .byte >(LBLTAB_BASE+lbloff_arrayok), >(LBLTAB_BASE+lbloff_arraypos), >(LBLTAB_BASE+lbloff_arrayhieq)
        .byte >(LBLTAB_BASE+lbloff_fortop), >(LBLTAB_BASE+lbloff_forneg), >(LBLTAB_BASE+lbloff_forinitneg)
        .byte >(LBLTAB_BASE+lbloff_forcont), >(LBLTAB_BASE+lbloff_fordone)
        .byte >(LBLTAB_BASE+lbloff_dotop), >(LBLTAB_BASE+lbloff_dodone)

;=======================================================================================
; Derived binary template records (regenerated by tools\gen-bin-templates.py)
;=======================================================================================

        .include "gen/bin-templates.inc"

; ---- scratch tables: pure zero-fill, placed at the image tail so in
; the checked build they may spill past $c000 -- the chain-load does
; not reliably deliver bytes up there (probe-proven: the native
; templates died past $c000 while the compiler itself ran fine), but
; these don't care: main clears $c000-$cfff at startup, and everything
; below $c000 loads normally. All VALUED content (code, templates)
; must stay below $c000.
;
; EXCEPTION: the source filename is read at prompt time, BEFORE the
; ROMs are banked out -- $c000-$cfff reads see the ROM shadow ($ff
; padding) until then, so these two must stay below $c000 (writes
; always land in RAM, which is why the startup clear and the prompt's
; stores masked this until the block crossed the boundary).
source_filename_len:
        .byte 0
source_filename_buf:
        .fill FILENAME_MAX + 1, 0
        .cerror * >= $c000, "loaded content (code/templates) must stay below $c000"
def_n1:
        .fill DEF_MAX, 0
def_n2:
        .fill DEF_MAX, 0
def_parm_lo:
        .fill DEF_MAX, 0
def_parm_hi:
        .fill DEF_MAX, 0
def_stash_lo:
        .fill DEF_MAX, 0
def_stash_hi:
        .fill DEF_MAX, 0
seg_base_lo:  .byte 0
seg_base_hi:  .byte 0
seg_elig_lo:  .byte 0
seg_elig_hi:  .byte 0
seg_win_hi:   .byte 0
seg_has_elig: .byte 0
seg_count:    .byte 0
seg_plan_result: .byte 0
flt_lit_sid:
        .fill FLT_LIT_MAX, 0
flt_lit_addr_lo:
        .fill FLT_LIT_MAX, 0
flt_lit_addr_hi:
        .fill FLT_LIT_MAX, 0
string_addr_lo:  .fill STRING_MAX, 0
string_addr_hi:  .fill STRING_MAX, 0
data_line_addr_lo: .fill DATA_LINE_MAX, 0
data_line_addr_hi: .fill DATA_LINE_MAX, 0
line_buf:
        .fill LINE_BUF_MAX, 0
for_stack_id:
        .fill FOR_STACK_MAX, 0
for_stack_var_data_lo:
        .fill FOR_STACK_MAX, 0
for_stack_var_data_hi:
        .fill FOR_STACK_MAX, 0
for_stack_var_type:
        .fill FOR_STACK_MAX, 0
do_stack_id:
        .fill DO_STACK_MAX, 0
if_stack_true_lo:
        .fill IF_STACK_MAX, 0
if_stack_true_hi:
        .fill IF_STACK_MAX, 0
if_stack_skip_lo:
        .fill IF_STACK_MAX, 0
if_stack_skip_hi:
        .fill IF_STACK_MAX, 0
if_stack_end_lo:
        .fill IF_STACK_MAX, 0
if_stack_end_hi:
        .fill IF_STACK_MAX, 0
if_stack_else_lo:
        .fill IF_STACK_MAX, 0
if_stack_else_hi:
        .fill IF_STACK_MAX, 0
if_stack_tmp_lo:
        .fill IF_STACK_MAX, 0
if_stack_tmp_hi:
        .fill IF_STACK_MAX, 0
array_dims_lo:
        .fill ARRAY_RANK_MAX, 0
array_dims_hi:
        .fill ARRAY_RANK_MAX, 0
sym_name_1:
        .fill SYM_MAX, 0
sym_name_2:
        .fill SYM_MAX, 0
sym_kind:
        .fill SYM_MAX, 0
sym_type:
        .fill SYM_MAX, 0
sym_rank:
        .fill SYM_MAX, 0
sym_data_lo:
        .fill SYM_MAX, 0
sym_data_hi:
        .fill SYM_MAX, 0
sym_dim0_lo:
        .fill SYM_MAX, 0
sym_dim0_hi:
        .fill SYM_MAX, 0
sym_dim1_lo:
        .fill SYM_MAX, 0
sym_dim1_hi:
        .fill SYM_MAX, 0
sym_dim2_lo:
        .fill SYM_MAX, 0
sym_dim2_hi:
        .fill SYM_MAX, 0
sym_dim3_lo:
        .fill SYM_MAX, 0
sym_dim3_hi:
        .fill SYM_MAX, 0
sym_dim4_lo:
        .fill SYM_MAX, 0
sym_dim4_hi:
        .fill SYM_MAX, 0
sym_dim5_lo:
        .fill SYM_MAX, 0
sym_dim5_hi:
        .fill SYM_MAX, 0
data_table_lo:
        .fill DATA_MAX, 0
data_table_hi:
        .fill DATA_MAX, 0
data_table_type:
        .fill DATA_MAX, 0
data_line_lo:
        .fill DATA_LINE_MAX, 0
data_line_hi:
        .fill DATA_LINE_MAX, 0
data_line_index:
        .fill DATA_LINE_MAX, 0
string_temp:
        .fill LINE_BUF_MAX + 1, 0

; On the MEGA65 the $c000-$cfff block is unmapped RAM in the compiler's
; execution context (the editor lives in the bank-3 ROM via MAPHI, not
; a $c000 shadow); only the I/O space at $d000 is a hard limit.
        .cerror * >= $d000, "resident compiler grew into i/o space"
