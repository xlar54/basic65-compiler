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

LFN_OUT                 = 2
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
TOK_EXT_CE              = $CE
TOK_EXT_FE              = $FE
TOK_CE_WPEEK            = $10
TOK_FE_WPOKE            = $1D

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
FILENAME_MAX            = 31
LINE_MAX                = 240
BRANCH_MAX              = 128
FOR_STACK_MAX           = 16
IF_STACK_MAX            = 16
DO_STACK_MAX            = 16
FOR_MAX                 = 64
DO_MAX                  = 64
ARRAY_RANK_MAX          = 6
DATA_MAX                = 128
DATA_LINE_MAX           = LINE_MAX
DATA_TYPE_INT           = 0
DATA_TYPE_STRING        = 1
STRING_MAX              = 240
STRING_POOL_MAX         = $1000

SYM_MAX                 = 128
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
        jsr close_work_files
        lda #0
        sta compile_error
        sta error_count
        sta sym_count
        sta line_count
        sta branch_count
        sta data_count
        sta data_line_count
        sta string_count
        sta string_pool_next_lo
        sta string_pool_next_hi
        sta backend_mode
        sta backend_error
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

+       lda #<msg_scanning_in
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

        lda #<msg_opening_out
        ldy #>msg_opening_out
        jsr screen_zstr
        jsr open_output
        bcc +
        jsr KERNAL_CLRCHN
        lda #<msg_open_out_fail
        ldy #>msg_open_out_fail
        jsr screen_zstr
        rts

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

        jsr KERNAL_CLRCHN
        lda #LFN_OUT
        jsr KERNAL_CLOSE
        jsr KERNAL_CLRCHN
        jsr finalize_output
        bcc +
        lda #<msg_finalize_fail
        ldy #>msg_finalize_fail
        jsr screen_zstr
        rts

+       lda #13
        jsr KERNAL_CHROUT

_main_done_ok:
        lda #<msg_done
        ldy #>msg_done
        jsr screen_zstr
        rts

_main_compile_failed:
        lda #<msg_compile_failed
        ldy #>msg_compile_failed
        jsr screen_zstr
        rts

_main_output_failed:
        jsr KERNAL_CLRCHN
        lda #LFN_OUT
        jsr KERNAL_CLOSE
        jsr scratch_output
        jsr KERNAL_CLRCHN
        lda #13
        jsr KERNAL_CHROUT
        lda #<msg_compile_failed
        ldy #>msg_compile_failed
        jsr screen_zstr
        rts

show_compile_line:
        ldx backend_mode
        beq +
        rts
+       jsr KERNAL_CLRCHN
        lda line_no_lo
        sta screen_num_lo
        lda line_no_hi
        sta screen_num_hi
        jsr screen_uint
        lda #'.'
        jsr KERNAL_CHROUT
        lda #'.'
        jsr KERNAL_CHROUT
        ldx #LFN_OUT
        jsr KERNAL_CHKOUT
        rts

show_compile_start:
        ldx backend_mode
        beq +
        rts
+       jsr KERNAL_CLRCHN
        lda #<msg_compiling_start
        ldy #>msg_compiling_start
        jsr screen_zstr
        ldx #LFN_OUT
        jsr KERNAL_CHKOUT
        rts

; per-emission-pass label allocation state; the size pass and the text pass
; must allocate identical label ids, so both start from a clean slate
reset_emit_counters:
        lda #0
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
        sta line_emit_idx
        sta pending_kind
        rts

; walk pass 2 in size mode: no output, but every template record and patch
; slot advances bin_pc, line addresses are recorded, and the tail table
; addresses are captured for the future emit pass
run_size_pass:
        lda #BK_SIZE
        sta backend_mode
        jsr reset_emit_counters
        lda #<$4000
        sta bin_pc
        lda #>$4000
        sta bin_pc+1
        jsr emit_generated_header
        jsr init_source_reader
        jsr compile_program
        lda compile_error
        bne _run_size_pass_done
        jsr emit_generated_tail
_run_size_pass_done:
        lda #BK_TEXT
        sta backend_mode
        jsr reset_emit_counters
        rts

report_size_pass:
        lda backend_error
        beq +
        lda #<msg_backend_error
        ldy #>msg_backend_error
        jsr screen_zstr
        rts
+       lda #<msg_bin_size
        ldy #>msg_bin_size
        jsr screen_zstr
        lda bin_pc+1
        jsr out_hex_byte
        lda bin_pc
        jsr out_hex_byte
        lda #13
        jsr KERNAL_CHROUT
        rts

fatal_error_zstr:
        sta diag_msg_lo
        sty diag_msg_hi
        lda #1
        sta compile_error
        inc error_count
        jsr KERNAL_CLRCHN
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
        jsr KERNAL_CHROUT
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
        jsr KERNAL_CHROUT

_screen_digit_return:
        rts

select_output:
        ldx #LFN_OUT
        jsr KERNAL_CHKOUT
        rts

;=======================================================================================
; File I/O
;=======================================================================================

prompt_source_name:
        jsr KERNAL_CLRCHN
        lda #<msg_source_prompt
        ldy #>msg_source_prompt
        jsr screen_zstr
        lda #0
        sta source_filename_len
        ldx #0

_prompt_source_loop:
        jsr KERNAL_CHRIN
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
        jsr KERNAL_CHROUT
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
        jsr KERNAL_CLRCHN
        lda #<msg_loading_source_prefix
        ldy #>msg_loading_source_prefix
        jsr screen_zstr
        lda #<source_filename_buf
        ldy #>source_filename_buf
        jsr screen_zstr
        lda #13
        jsr KERNAL_CHROUT
        rts

load_source:
        lda #SOURCE_BANK
        ldx #0
        jsr KERNAL_SETBNK

        lda #0
        ldx #DEVICE_DISK
        ldy #0
        jsr KERNAL_SETLFS

        lda source_filename_len
        ldx #<source_filename_buf
        ldy #>source_filename_buf
        jsr KERNAL_SETNAM

        lda #$40                         ; raw load to X/Y, PRG header included
        ldx #<SOURCE_BUF
        ldy #>SOURCE_BUF
        jsr KERNAL_LOAD
        bcs _load_source_fail
        stx source_end_lo
        sty source_end_hi
        jsr KERNAL_CLRCHN
        clc
        rts

_load_source_fail:
        jsr KERNAL_CLRCHN
        sec
        rts

open_output:
        jsr close_work_files
        jsr scratch_output

        lda #LFN_OUT
        ldx #DEVICE_DISK
        ldy #1
        jsr KERNAL_SETLFS

        lda #0
        ldx #0
        jsr KERNAL_SETBNK

        lda #output_name_end - output_name
        ldx #<output_name
        ldy #>output_name
        jsr KERNAL_SETNAM

        jsr KERNAL_OPEN
        bcs _open_output_fail
        jsr KERNAL_READST
        bne _open_output_fail

        ldx #LFN_OUT
        jsr KERNAL_CHKOUT
        bcs _open_output_fail
        jsr KERNAL_READST
        bne _open_output_fail
        clc
        rts

_open_output_fail:
        jsr close_work_files
        sec
        rts

close_work_files:
        jsr KERNAL_CLRCHN
        lda #LFN_OUT
        jsr KERNAL_CLOSE
        lda #LFN_CMD
        jsr KERNAL_CLOSE
        jsr KERNAL_CLRCHN
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
        jsr KERNAL_CLRCHN
        lda #LFN_CMD
        ldx #DEVICE_DISK
        ldy #LFN_CMD
        jsr KERNAL_SETLFS

        lda #0
        ldx #0
        jsr KERNAL_SETBNK

        lda #0
        ldx #0
        ldy #0
        jsr KERNAL_SETNAM

        jsr KERNAL_OPEN
        bcs _disk_command_fail
        ldx #LFN_CMD
        jsr KERNAL_CHKOUT
        bcs _disk_command_fail
        ldy #0
_disk_command_loop:
        cpy byte_value
        beq _disk_command_sent
        lda (str_ptr),y
        jsr KERNAL_CHROUT
        iny
        bra _disk_command_loop

_disk_command_sent:
        jsr KERNAL_READST
        bne _disk_command_fail
        lda #0
        sta disk_status
        bra _disk_command_done

_disk_command_fail:
        lda #1
        sta disk_status

_disk_command_done:
        jsr KERNAL_CLRCHN
        lda #LFN_CMD
        jsr KERNAL_CLOSE
        jsr KERNAL_CLRCHN
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
        lda #VAR_KIND_ARRAY1
        sta var_kind
        jsr resolve_existing_var
        bcs _scan_vars_fail
        bra _scan_vars_loop

_scan_vars_scalar:
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
        jsr scan_skip_token_argument
        bra _scan_vars_loop

_scan_vars_fail:
        lda #1
        sta compile_error
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
        ldx #0
_record_line_find:
        cpx line_count
        beq _record_line_create
        lda line_table_lo,x
        cmp line_no_lo
        bne _record_line_next
        lda line_table_hi,x
        cmp line_no_hi
        beq _record_line_fail
_record_line_next:
        inx
        bra _record_line_find

_record_line_create:
        cpx #LINE_MAX
        bcs _record_line_fail
        lda line_no_lo
        sta line_table_lo,x
        lda line_no_hi
        sta line_table_hi,x
        inc line_count
        clc
        rts

_record_line_fail:
        lda #1
        sta compile_error
        sec
        rts

record_branch_target:
        ldx #0
_record_branch_find:
        cpx branch_count
        beq _record_branch_create
        lda branch_table_lo,x
        cmp number_lo
        bne _record_branch_next
        lda branch_table_hi,x
        cmp number_hi
        beq _record_branch_done
_record_branch_next:
        inx
        bra _record_branch_find

_record_branch_create:
        cpx #BRANCH_MAX
        bcs _record_branch_fail
        lda number_lo
        sta branch_table_lo,x
        lda number_hi
        sta branch_table_hi,x
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
        lda branch_table_lo,x
        sta number_lo
        lda branch_table_hi,x
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
        ldx #0
_line_exists_loop:
        cpx line_count
        beq _line_exists_no
        lda line_table_lo,x
        cmp number_lo
        bne _line_exists_next
        lda line_table_hi,x
        cmp number_hi
        beq _line_exists_yes
_line_exists_next:
        inx
        bra _line_exists_loop

_line_exists_yes:
        clc
        rts

_line_exists_no:
        sec
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

        jsr line_get
        cmp #TOK_FOR
        beq _compile_for
        cmp #TOK_NEXT
        beq _compile_next
        cmp #TOK_DO
        beq _compile_do
        cmp #TOK_LOOP
        beq _compile_loop
        cmp #TOK_EXIT
        beq _compile_exit
        cmp #TOK_PRINT
        beq _compile_print
        cmp #TOK_INPUT
        beq _compile_input
        cmp #TOK_GET
        beq _compile_get
        cmp #TOK_GOTO
        beq _compile_goto
        cmp #TOK_GOSUB
        beq _compile_gosub
        cmp #TOK_RETURN
        beq _compile_return
        cmp #TOK_END
        beq _compile_end
        cmp #TOK_STOP
        beq _compile_end
        cmp #TOK_REM
        beq _compile_rem
        cmp #TOK_SYS
        beq _compile_sys
        cmp #TOK_POKE
        beq _compile_poke
        cmp #TOK_GO
        beq _compile_go
        cmp #TOK_ON
        beq _compile_on
        cmp #TOK_DATA
        beq _compile_data
        cmp #TOK_DIM
        beq _compile_dim
        cmp #TOK_READ
        beq _compile_read
        cmp #TOK_RESTORE
        beq _compile_restore
        cmp #TOK_LET
        beq _compile_let
        cmp #TOK_IF
        beq _compile_if
        cmp #TOK_ELSE
        beq _compile_else
        cmp #TOK_PRINT_HASH
        beq _compile_unsupported_token
        cmp #TOK_EXT_CE
        beq _compile_unsupported_extended_token
        cmp #TOK_EXT_FE
        beq _compile_extended_fe

        sta token_value
        lda token_value
        bmi _compile_unsupported_token_stored
        jsr is_var_start
        bcc _compile_assignment_from_token
        bra _compile_unsupported_statement

_compile_for:
        jsr compile_for
        bra _compile_line_loop

_compile_next:
        jsr compile_next
        bra _compile_line_loop

_compile_do:
        jsr compile_do
        bra _compile_line_loop

_compile_loop:
        jsr compile_loop
        bra _compile_line_loop

_compile_exit:
        jsr compile_exit
        bra _compile_line_loop

_compile_print:
        jsr compile_print
        bra _compile_line_loop

_compile_input:
        jsr compile_input
        bra _compile_line_loop

_compile_get:
        jsr compile_get
        bra _compile_line_loop

_compile_goto:
        jsr compile_goto
        bra _compile_line_loop

_compile_gosub:
        jsr compile_gosub
        bra _compile_line_loop

_compile_return:
        lda #<out_rts
        ldy #>out_rts
        jsr out_zstr
        bra _compile_line_loop

_compile_end:
        lda #<out_jmp_rtexit
        ldy #>out_jmp_rtexit
        jsr out_zstr
        jsr line_skip_to_end
        bra _compile_line_loop

_compile_rem:
        jsr compile_rem
        bra _compile_line_loop

_compile_sys:
        jsr compile_sys
        bra _compile_line_loop

_compile_poke:
        jsr compile_poke
        bra _compile_line_loop

_compile_go:
        jsr compile_go
        bra _compile_line_loop

_compile_on:
        jsr compile_on
        bra _compile_line_loop

_compile_data:
        lda #<out_data_comment
        ldy #>out_data_comment
        jsr out_zstr
        jsr line_skip_to_stmt_end
        bra _compile_line_loop

_compile_dim:
        lda #<out_dim_comment
        ldy #>out_dim_comment
        jsr out_zstr
        jsr line_skip_to_stmt_end
        bra _compile_line_loop

_compile_read:
        jsr compile_read
        bra _compile_line_loop

_compile_restore:
        jsr compile_restore
        bra _compile_line_loop

_compile_let:
        jsr compile_let
        bra _compile_line_loop

_compile_if:
        jsr compile_if
        bra _compile_line_loop

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
        bra _compile_line_loop

_compile_assignment_from_token:
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
        jsr line_at_end
        bcs _compile_unsupported_extended_fe
        jsr line_peek
        cmp #TOK_FE_WPOKE
        beq _compile_wpoke

_compile_unsupported_extended_fe:
        lda #TOK_EXT_FE
        bra _compile_unsupported_extended_token

_compile_wpoke:
        jsr line_get
        jsr compile_wpoke
        bra _compile_line_loop

_compile_unsupported_statement:
        lda #<msg_error_unsupported_statement
        ldy #>msg_error_unsupported_statement
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
        lda assign_var_type
        cmp #VAR_TYPE_FLOAT
        bne _compile_assignment_integer_expr
        jsr try_compile_float_literal_assignment
        bcc _compile_assignment_done

_compile_assignment_integer_expr:
        jsr compile_expression
        bcs compile_assignment_bad
        jsr emit_store_var
_compile_assignment_done:
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
        jsr compile_array_index
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
        jsr emit_push_expr
        jsr compile_string_factor
        bcs _string_expr_fail
        jsr emit_pop_lhs
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
        cmp #TOK_STR_STR
        beq _string_factor_str
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
        jsr compile_array_index
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
        jsr emit_push_expr
        jsr parse_comma
        bcs _compile_left_fail
        jsr compile_expression
        bcs _compile_left_fail
        jsr parse_close_paren
        bcs _compile_left_fail
        jsr emit_pop_lhs
        jsr emit_string_left
        clc
        rts

_compile_left_fail:
        sec
        rts

compile_right_string_function:
        jsr parse_open_paren
        bcs _compile_right_fail
        jsr compile_string_expression
        bcs _compile_right_fail
        jsr emit_push_expr
        jsr parse_comma
        bcs _compile_right_fail
        jsr compile_expression
        bcs _compile_right_fail
        jsr parse_close_paren
        bcs _compile_right_fail
        jsr emit_pop_lhs
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
        jsr emit_push_expr
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
        jsr emit_pop_lhs
        jsr emit_string_mid_tail
        clc
        rts

_compile_mid_with_len:
        jsr compile_expression
        bcs _compile_mid_fail
        jsr parse_close_paren
        bcs _compile_mid_fail
        jsr emit_pop_lhs
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
        lda current_var_data_lo
        sta array_base_lo
        lda current_var_data_hi
        sta array_base_hi
        jsr compile_array_index
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
        jsr compile_expression
        bcs compile_assignment_bad
        jsr emit_restore_arrayptr
        jsr emit_store_ptr
        rts

try_compile_float_literal_assignment:
        lda line_idx
        sta line_idx_save
        jsr parse_float_literal_to_string_temp
        bcs _try_float_assign_restore_fail
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcc _try_float_assign_restore_fail
        jsr intern_string_temp
        bcs _try_float_assign_restore_fail
        jsr emit_store_float_literal_current
        clc
        rts

_try_float_assign_restore_fail:
        lda line_idx_save
        sta line_idx
        sec
        rts

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
        jsr emit_push_expr
        jsr emit_load_forstep
        jsr emit_pop_lhs
        jsr emit_add_lhs_expr
        jsr emit_store_var

        lda #<out_lda_label
        ldy #>out_lda_label
        jsr out_zstr
        jsr out_forstep_ref
        jsr out_plus_one_cr
        lda #<out_bmi_label
        ldy #>out_bmi_label
        jsr out_zstr
        jsr out_forneg_ref
        jsr out_cr

        lda current_for_var_data_lo
        sta current_var_data_lo
        lda current_for_var_data_hi
        sta current_var_data_hi
        jsr emit_load_var
        jsr emit_push_expr
        jsr emit_load_forend
        jsr emit_pop_lhs
        lda #<out_jsr_cmple
        ldy #>out_jsr_cmple
        jsr out_zstr
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr out_zstr
        jsr out_forcont_ref
        jsr out_cr
        jsr emit_jmp_fordone

        jsr emit_forneg_label_def
        lda current_for_var_data_lo
        sta current_var_data_lo
        lda current_for_var_data_hi
        sta current_var_data_hi
        jsr emit_load_var
        jsr emit_push_expr
        jsr emit_load_forend
        jsr emit_pop_lhs
        lda #<out_jsr_cmpge
        ldy #>out_jsr_cmpge
        jsr out_zstr
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr out_zstr
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

compile_exit:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_exit_do
        jsr line_peek
        cmp #TOK_FOR
        beq _compile_exit_for
        cmp #TOK_ELSE
        beq _compile_exit_do
        bra compile_exit_bad

_compile_exit_do:
        jsr peek_do_frame
        bcs compile_exit_bad
        jsr emit_jmp_dodone
        rts

_compile_exit_for:
        jsr line_get
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_exit_for_emit
        jsr line_peek
        cmp #TOK_ELSE
        bne compile_exit_bad

_compile_exit_for_emit:
        jsr peek_for_frame
        bcs compile_exit_bad
        jsr emit_jmp_fordone
        rts

compile_exit_bad:
        lda #<msg_error_bad_exit
        ldy #>msg_error_bad_exit
        jsr fatal_statement_error
        rts

compile_loop_condition_lhs:
        jsr compile_condition_expression
        bcs _compile_loop_condition_fail
        jsr emit_push_expr
        jsr emit_pop_lhs
        clc
        rts

_compile_loop_condition_fail:
        sec
        rts

compile_if:
        jsr alloc_if_labels
        jsr compile_condition_expression
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
        lda #1
        sta compile_stop_on_else
        lda #0
        sta compile_found_else
        jsr compile_line_statements
        lda compile_found_else
        sta if_else_found
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

_cond_or_done:
        clc
        rts

_cond_or_take:
        jsr line_get
        jsr emit_push_expr
        jsr compile_condition_and
        bcs _cond_or_fail
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
        jsr emit_push_expr
        jsr compile_condition_not
        bcs _cond_and_fail
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
        jsr compile_expression
        bcs _cond_compare_fail
        jsr parse_if_compare_op
        bcs _cond_compare_done
        jsr emit_push_expr
        jsr compile_expression
        bcs _cond_compare_fail
        jsr emit_pop_lhs
        jsr emit_compare_expr_to_bool

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
        jsr emit_push_expr
        jsr compile_string_expression
        bcs _cond_compare_fail
        jsr emit_pop_lhs
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

compile_expression:
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
        jsr emit_push_expr
        jsr compile_term
        bcs _expr_fail
        jsr emit_pop_lhs
        jsr emit_add_lhs_expr
        bra _expr_loop

_expr_sub:
        jsr line_get
        jsr emit_push_expr
        jsr compile_term
        bcs _expr_fail
        jsr emit_pop_lhs
        jsr emit_sub_lhs_expr
        bra _expr_loop

_expr_fail:
        sec
        rts

compile_term:
        jsr compile_factor
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
        jsr emit_push_expr
        jsr compile_factor
        bcs _term_fail
        jsr emit_pop_lhs
        jsr emit_mul_lhs_expr
        bra _term_loop

_term_div:
        jsr line_get
        jsr emit_push_expr
        jsr compile_factor
        bcs _term_fail
        jsr emit_pop_lhs
        jsr emit_div_lhs_expr
        bra _term_loop

_term_fail:
        sec
        rts

compile_factor:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _factor_fail
        jsr line_peek
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
        cmp #TOK_EXT_CE
        beq _factor_ext_ce
        jsr is_var_start
        bcc _factor_variable
_factor_fail:
        sec
        rts

_factor_number:
        jsr line_parse_number
        bcs _factor_fail
        jsr emit_load_number
        clc
        rts

_factor_variable:
        jsr line_get
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
        jsr resolve_var
        bcs _factor_fail
        jsr emit_load_var
        clc
        rts

_factor_array_variable:
        lda #VAR_KIND_ARRAY1
        sta var_kind
        jsr resolve_existing_var
        bcs _factor_fail
        lda current_var_data_lo
        sta array_base_lo
        lda current_var_data_hi
        sta array_base_hi
        jsr compile_array_index
        bcs _factor_fail
        lda array_base_lo
        sta current_var_data_lo
        lda array_base_hi
        sta current_var_data_hi
        jsr emit_set_arrayptr_current
        jsr emit_load_ptr
        clc
        rts

_factor_paren:
        jsr line_get
        jsr compile_expression
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
        jsr emit_neg_expr
        clc
        rts

_factor_unary_not:
        jsr line_get
        jsr compile_factor
        bcs _factor_fail
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
        jsr compile_expression
        bcs _factor_fail
        jsr parse_close_paren
        bcs _factor_fail
        jsr emit_abs_expr
        clc
        rts

_factor_sgn:
        jsr line_get
        jsr parse_open_paren
        bcs _factor_fail
        jsr compile_expression
        bcs _factor_fail
        jsr parse_close_paren
        bcs _factor_fail
        jsr emit_sgn_expr
        clc
        rts

_factor_int:
        jsr line_get
        jsr parse_open_paren
        bcs _factor_fail
        jsr compile_expression
        bcs _factor_fail
        jsr parse_close_paren
        bcs _factor_fail
        clc
        rts

_factor_peek:
        jsr line_get
        jsr parse_open_paren
        bcs _factor_fail
        jsr compile_expression
        bcs _factor_fail
        jsr parse_close_paren
        bcs _factor_fail
        jsr emit_peek_expr
        clc
        rts

_factor_ext_ce:
        jsr line_get
        jsr line_at_end
        bcs _factor_fail
        jsr line_get
        cmp #TOK_CE_WPEEK
        bne _factor_fail
        jsr parse_open_paren
        bcs _factor_fail
        jsr compile_expression
        bcs _factor_fail
        jsr parse_close_paren
        bcs _factor_fail
        jsr emit_wpeek_expr
        clc
        rts

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
        bra _print_expression

_print_expression:
        jsr try_compile_print_string_var
        bcc _print_string_var_done
        jsr try_compile_print_numeric_var
        bcc _print_string_var_done
        jsr try_compile_print_float_literal
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
        jsr compile_expression
        bcs _print_expression_bad
        lda #<out_jsr_printuint
        ldy #>out_jsr_printuint
        jsr out_zstr

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

compile_input_target:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_input_target_bad
        jsr line_get
        jsr is_var_start
        bcs _compile_input_target_bad
        jsr parse_variable_with_first_char
        bcs _compile_input_target_bad
        lda var_type
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
        jsr compile_array_index
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
        jsr emit_restore_arrayptr
        jsr emit_store_ptr
        clc
        rts

_compile_input_target_bad:
        sec
        rts

compile_get:
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
        jsr compile_array_index
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
        jsr emit_restore_arrayptr
        jsr emit_store_ptr
        clc
        rts

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
        jsr compile_array_index
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
        jsr emit_print_num_var_current
        clc
        rts

_try_print_num_var_restore_fail:
        lda line_idx_save
        sta line_idx

_try_print_num_var_fail:
        sec
        rts

try_compile_print_float_literal:
        lda line_idx
        sta line_idx_save
        jsr parse_float_literal_to_string_temp
        bcs _try_print_float_restore_fail
        jsr try_print_item_end
        bcs _try_print_float_restore_fail
        jsr intern_string_temp
        bcs _try_print_float_restore_fail
        jsr emit_print_float_literal_current
        clc
        rts

_try_print_float_restore_fail:
        lda line_idx_save
        sta line_idx
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
        lda #<out_jmp_label
        ldy #>out_jmp_label
        jsr out_zstr
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
        lda #<out_jsr_label
        ldy #>out_jsr_label
        jsr out_zstr
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
        lda #<out_jsr_abs
        ldy #>out_jsr_abs
        jsr out_zstr
        jsr out_hex_word_number
        jsr out_cr
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
        jsr compile_array_index
        bcs _compile_read_bad
        lda array_base_lo
        sta current_var_data_lo
        lda array_base_hi
        sta current_var_data_hi
        jsr emit_set_arrayptr_current
        jsr emit_save_arrayptr
        jsr emit_read_for_target
        jsr emit_restore_arrayptr
        jsr emit_store_ptr

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
        lda #<out_jsr_datainit
        ldy #>out_jsr_datainit
        jsr out_zstr
        jsr line_skip_to_stmt_end
        rts

_compile_restore_bad:
        lda #<msg_error_bad_restore
        ldy #>msg_error_bad_restore
        jsr fatal_statement_error
        rts

compile_rem:
        lda #<out_rem
        ldy #>out_rem
        jsr out_zstr

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
        asl work2_lo
        rol work2_hi
        bcs _create_array_fail

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
        bcs _parse_float_fail
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
        bne _parse_float_fail
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
        lda string_off_lo,x
        sta string_read_lo
        lda string_off_hi,x
        sta string_read_hi
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
        lda string_pool_next_lo
        sta string_off_lo,x
        lda string_pool_next_hi
        sta string_off_hi,x
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

string_pool_append_byte:
        lda string_pool_next_hi
        cmp #>STRING_POOL_MAX
        bcs _string_pool_append_fail
        lda #<string_pool
        clc
        adc string_pool_next_lo
        sta str_ptr
        lda #>string_pool
        adc string_pool_next_hi
        sta str_ptr+1
        lda byte_value
        ldy #0
        sta (str_ptr),y
        inc string_pool_next_lo
        bne +
        inc string_pool_next_hi
+       clc
        rts

_string_pool_append_fail:
        sec
        rts

string_pool_read_byte:
        lda #<string_pool
        clc
        adc string_read_lo
        sta str_ptr
        lda #>string_pool
        adc string_read_hi
        sta str_ptr+1
        ldy #0
        lda (str_ptr),y
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
        lda #<out_header
        ldy #>out_header
        jsr out_zstr
        rts

_emit_generated_header_bin:
        ; program header at progbase: start, varheapend, datastart, dataend,
        ; strroots vectors (5 words); start label sits right after them
        lda #10
        jmp bin_add_pc

emit_generated_tail:
        lda #<out_tail
        ldy #>out_tail
        jsr out_zstr
        jsr emit_varheapend
        jsr emit_string_pool
        jsr emit_data_table
        jsr emit_string_roots
        jsr emit_for_storage
        lda #<out_size_guard
        ldy #>out_size_guard
        jsr out_zstr
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
+       lda #<out_for_storage_header
        ldy #>out_for_storage_header
        jsr out_zstr
        lda #0
        sta for_storage_idx

_emit_for_storage_loop:
        lda for_storage_idx
        cmp for_label_next
        bcs _emit_for_storage_done
        sta current_for_id
        jsr out_forend_ref
        lda #<out_for_word_storage
        ldy #>out_for_word_storage
        jsr out_zstr
        jsr out_forstep_ref
        lda #<out_for_word_storage
        ldy #>out_for_word_storage
        jsr out_zstr
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
        lda #<out_data_byte_prefix
        ldy #>out_data_byte_prefix
        jsr out_zstr
        ldx data_emit_idx
        lda data_table_type,x
        jsr out_hex_byte
        ldx data_emit_idx
        lda data_table_type,x
        cmp #DATA_TYPE_STRING
        beq _emit_data_string_record

        lda #<out_data_byte_sep
        ldy #>out_data_byte_sep
        jsr out_zstr
        ldx data_emit_idx
        lda data_table_lo,x
        jsr out_hex_byte
        lda #<out_data_byte_sep
        ldy #>out_data_byte_sep
        jsr out_zstr
        ldx data_emit_idx
        lda data_table_hi,x
        jsr out_hex_byte
        jsr out_cr
        inc data_emit_idx
        bra _emit_data_table_loop

_emit_data_string_record:
        jsr out_cr
        lda #<out_data_word_prefix
        ldy #>out_data_word_prefix
        jsr out_zstr
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
        lda #<out_data_byte_prefix
        ldy #>out_data_byte_prefix
        jsr out_zstr
        lda number_lo
        jsr out_hex_byte
        lda #<out_data_byte_sep
        ldy #>out_data_byte_sep
        jsr out_zstr
        lda number_hi
        jsr out_hex_byte
        lda #<out_data_byte_sep
        ldy #>out_data_byte_sep
        jsr out_zstr
        lda work2_lo
        jsr out_hex_byte
        lda #<out_data_byte_sep
        ldy #>out_data_byte_sep
        jsr out_zstr
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
        lda string_off_lo,x
        sta string_read_lo
        lda string_off_hi,x
        sta string_read_hi

_emit_string_byte_loop:
        jsr string_pool_read_byte
        sta byte_value
        lda #<out_data_byte_prefix
        ldy #>out_data_byte_prefix
        jsr out_zstr
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

emit_line_label:
        ldx backend_mode
        bne _emit_line_label_bin
        lda #'l'
        jsr KERNAL_CHROUT
        lda line_no_hi
        jsr out_hex_byte
        lda line_no_lo
        jsr out_hex_byte
        lda #':'
        jsr KERNAL_CHROUT
        jsr out_cr
        rts

_emit_line_label_bin:
        ldx line_emit_idx
        lda bin_pc
        sta line_addr_lo,x
        lda bin_pc+1
        sta line_addr_hi,x
        inc line_emit_idx
        rts

out_label_from_number:
        lda #'l'
        jsr out_char
        jsr out_hex_word_number
        rts

out_data_line_ref:
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
        lda #<out_lda_imm_hex
        ldy #>out_lda_imm_hex
        jsr out_zstr
        lda byte_value
        jsr out_hex_byte
        jsr out_cr
        lda #<out_jsr_chout
        ldy #>out_jsr_chout
        jsr out_zstr
        rts

emit_print_string_current:
        jsr emit_set_rtptr_string_current
        lda #<out_jsr_printstr
        ldy #>out_jsr_printstr
        jsr out_zstr
        rts

emit_set_rtptr_string_current:
        lda #<out_lda_label_lo_imm
        ldy #>out_lda_label_lo_imm
        jsr out_zstr
        jsr out_string_ref
        jsr out_cr
        lda #<out_sta_rtptr
        ldy #>out_sta_rtptr
        jsr out_zstr
        lda #<out_lda_label_hi_imm
        ldy #>out_lda_label_hi_imm
        jsr out_zstr
        jsr out_string_ref
        jsr out_cr
        lda #<out_sta_rtptr_1
        ldy #>out_sta_rtptr_1
        jsr out_zstr
        rts

emit_load_string_ref_to_expr:
        lda #<out_lda_label_lo_imm
        ldy #>out_lda_label_lo_imm
        jsr out_zstr
        jsr out_string_ref
        jsr out_cr
        lda #<out_sta_exprlo
        ldy #>out_sta_exprlo
        jsr out_zstr
        lda #<out_lda_label_hi_imm
        ldy #>out_lda_label_hi_imm
        jsr out_zstr
        jsr out_string_ref
        jsr out_cr
        lda #<out_sta_exprhi
        ldy #>out_sta_exprhi
        jsr out_zstr
        rts

emit_string_literal_to_heap_expr:
        lda #<out_lda_label_lo_imm
        ldy #>out_lda_label_lo_imm
        jsr out_zstr
        jsr out_string_ref
        jsr out_cr
        lda #<out_sta_rtptr
        ldy #>out_sta_rtptr
        jsr out_zstr
        lda #<out_lda_label_hi_imm
        ldy #>out_lda_label_hi_imm
        jsr out_zstr
        jsr out_string_ref
        jsr out_cr
        lda #<out_sta_rtptr_1
        ldy #>out_sta_rtptr_1
        jsr out_zstr
        lda #<out_jsr_strfromlit
        ldy #>out_jsr_strfromlit
        jsr out_zstr
        rts

emit_print_string_var_current:
        jsr emit_load_var
        ; FALLTHROUGH

emit_print_string_expr:
        lda #<out_jsr_printheapstr
        ldy #>out_jsr_printheapstr
        jsr out_zstr
        rts

emit_copy_string_expr:
        lda #<out_jsr_strcopyexpr
        ldy #>out_jsr_strcopyexpr
        jsr out_zstr
        rts

emit_concat_strings:
        lda #<out_jsr_concatstr
        ldy #>out_jsr_concatstr
        jsr out_zstr
        rts

emit_string_len_expr:
        lda #<out_jsr_strlenexpr
        ldy #>out_jsr_strlenexpr
        jsr out_zstr
        rts

emit_string_from_int:
        lda #<out_jsr_strfromint
        ldy #>out_jsr_strfromint
        jsr out_zstr
        rts

emit_val_string_expr:
        lda #<out_jsr_valstr
        ldy #>out_jsr_valstr
        jsr out_zstr
        rts

emit_string_temp_mark:
        lda #<out_jsr_strmark
        ldy #>out_jsr_strmark
        jsr out_zstr
        rts

emit_string_temp_release:
        lda #<out_jsr_strrelease
        ldy #>out_jsr_strrelease
        jsr out_zstr
        rts

emit_string_left:
        jsr emit_set_strarg1_one
        bra emit_string_mid

emit_string_right:
        lda #<out_jsr_strright
        ldy #>out_jsr_strright
        jsr out_zstr
        rts

emit_string_mid:
        lda #<out_jsr_strsub
        ldy #>out_jsr_strsub
        jsr out_zstr
        rts

emit_string_mid_tail:
        lda #$FF
        sta number_lo
        lda #0
        sta number_hi
        jsr emit_load_number
        bra emit_string_mid

emit_set_strarg1_one:
        lda #<out_lda_imm_hex
        ldy #>out_lda_imm_hex
        jsr out_zstr
        lda #1
        jsr out_hex_byte
        jsr out_cr
        lda #<out_sta_strarg1lo
        ldy #>out_sta_strarg1lo
        jsr out_zstr
        lda #<out_lda_imm_hex
        ldy #>out_lda_imm_hex
        jsr out_zstr
        lda #0
        jsr out_hex_byte
        jsr out_cr
        lda #<out_sta_strarg1hi
        ldy #>out_sta_strarg1hi
        jsr out_zstr
        rts

emit_save_expr_to_strarg1:
        lda #<out_lda_exprlo
        ldy #>out_lda_exprlo
        jsr out_zstr
        lda #<out_sta_strarg1lo
        ldy #>out_sta_strarg1lo
        jsr out_zstr
        lda #<out_lda_exprhi
        ldy #>out_lda_exprhi
        jsr out_zstr
        lda #<out_sta_strarg1hi
        ldy #>out_sta_strarg1hi
        jsr out_zstr
        rts

emit_print_comma:
        lda #<out_jsr_printcomma
        ldy #>out_jsr_printcomma
        jsr out_zstr
        rts

emit_print_uint_expr:
        lda #<out_jsr_printuint
        ldy #>out_jsr_printuint
        jsr out_zstr
        rts

emit_print_char_expr:
        lda #<out_lda_exprlo
        ldy #>out_lda_exprlo
        jsr out_zstr
        lda #<out_jsr_chout
        ldy #>out_jsr_chout
        jsr out_zstr
        rts

emit_load_number:
        lda #<out_lda_imm_hex
        ldy #>out_lda_imm_hex
        jsr out_zstr
        lda number_lo
        jsr out_hex_byte
        jsr out_cr
        lda #<out_sta_exprlo
        ldy #>out_sta_exprlo
        jsr out_zstr

        lda #<out_lda_imm_hex
        ldy #>out_lda_imm_hex
        jsr out_zstr
        lda number_hi
        jsr out_hex_byte
        jsr out_cr
        lda #<out_sta_exprhi
        ldy #>out_sta_exprhi
        jsr out_zstr
        rts

emit_load_var:
        jsr emit_set_varptr_current
        ldx current_sym_index
        lda sym_type,x
        cmp #VAR_TYPE_FLOAT
        beq _emit_load_num_var
        lda #<out_jsr_loadintvar
        ldy #>out_jsr_loadintvar
        jsr out_zstr
        rts

_emit_load_num_var:
        lda #<out_jsr_loadnumvar
        ldy #>out_jsr_loadnumvar
        jsr out_zstr
        rts

emit_store_var:
        lda assign_var_data_lo
        sta current_var_data_lo
        lda assign_var_data_hi
        sta current_var_data_hi
        jsr emit_set_varptr_current
        lda assign_var_type
        cmp #VAR_TYPE_FLOAT
        beq _emit_store_num_var
        jsr emit_store_ptr
        rts

_emit_store_num_var:
        lda #<out_jsr_storenumvar
        ldy #>out_jsr_storenumvar
        jsr out_zstr
        rts

emit_store_float_literal_current:
        lda assign_var_data_lo
        sta current_var_data_lo
        lda assign_var_data_hi
        sta current_var_data_hi
        jsr emit_set_varptr_current
        jsr emit_set_rtptr_string_current
        lda #<out_jsr_storefloatref
        ldy #>out_jsr_storefloatref
        jsr out_zstr
        rts

emit_print_float_literal_current:
        jsr emit_set_rtptr_string_current
        lda #<out_jsr_printfloatref
        ldy #>out_jsr_printfloatref
        jsr out_zstr
        rts

emit_print_num_var_current:
        jsr emit_set_varptr_current
        lda #<out_jsr_printnumvar
        ldy #>out_jsr_printnumvar
        jsr out_zstr
        rts

emit_load_ptr:
        lda #<out_jsr_loadintvar
        ldy #>out_jsr_loadintvar
        jsr out_zstr
        rts

emit_store_ptr:
        lda #<out_jsr_storeintvar
        ldy #>out_jsr_storeintvar
        jsr out_zstr
        rts

emit_read_int:
        lda #<out_jsr_readint
        ldy #>out_jsr_readint
        jsr out_zstr
        rts

emit_read_string:
        lda #<out_jsr_readstr
        ldy #>out_jsr_readstr
        jsr out_zstr
        rts

emit_input_line:
        lda #<out_jsr_inputline
        ldy #>out_jsr_inputline
        jsr out_zstr
        rts

emit_input_int:
        lda #<out_jsr_inputint
        ldy #>out_jsr_inputint
        jsr out_zstr
        rts

emit_input_string:
        lda #<out_jsr_inputstr
        ldy #>out_jsr_inputstr
        jsr out_zstr
        rts

emit_get_key:
        lda #<out_jsr_getkey
        ldy #>out_jsr_getkey
        jsr out_zstr
        rts

emit_get_string:
        lda #<out_jsr_getstr
        ldy #>out_jsr_getstr
        jsr out_zstr
        rts

emit_restore_data_line:
        lda #<out_lda_label_lo_imm
        ldy #>out_lda_label_lo_imm
        jsr out_zstr
        jsr out_data_line_ref
        jsr out_cr
        lda #<out_sta_dataptrlo
        ldy #>out_sta_dataptrlo
        jsr out_zstr
        lda #<out_lda_label_hi_imm
        ldy #>out_lda_label_hi_imm
        jsr out_zstr
        jsr out_data_line_ref
        jsr out_cr
        lda #<out_sta_dataptrhi
        ldy #>out_sta_dataptrhi
        jsr out_zstr
        rts

emit_save_arrayptr:
        lda #<out_save_arrayptr
        ldy #>out_save_arrayptr
        jsr out_zstr
        rts

emit_restore_arrayptr:
        lda #<out_restore_arrayptr
        ldy #>out_restore_arrayptr
        jsr out_zstr
        rts

emit_array_bounds_check:
        jsr alloc_array_ok_label
        lda #<out_array_check_start
        ldy #>out_array_check_start
        jsr out_zstr
        jsr out_array_nonneg_ref
        jsr out_cr
        lda #<out_jmp_arraybounds
        ldy #>out_jmp_arraybounds
        jsr out_zstr
        jsr out_array_nonneg_ref
        jsr emit_label_suffix
        lda #<out_cmp_exprhi_imm
        ldy #>out_cmp_exprhi_imm
        jsr out_zstr
        lda number_hi
        jsr out_hex_byte
        jsr out_cr
        lda #<out_bcc_label
        ldy #>out_bcc_label
        jsr out_zstr
        jsr out_array_ok_ref
        jsr out_cr
        lda #<out_beq_label
        ldy #>out_beq_label
        jsr out_zstr
        jsr out_array_hieq_ref
        jsr out_cr
        lda #<out_jmp_arraybounds
        ldy #>out_jmp_arraybounds
        jsr out_zstr
        jsr out_array_hieq_ref
        jsr emit_label_suffix
        lda #<out_cmp_exprlo_imm
        ldy #>out_cmp_exprlo_imm
        jsr out_zstr
        lda number_lo
        jsr out_hex_byte
        jsr out_cr
        lda #<out_bcc_label
        ldy #>out_bcc_label
        jsr out_zstr
        jsr out_array_ok_ref
        jsr out_cr
        lda #<out_jmp_arraybounds
        ldy #>out_jmp_arraybounds
        jsr out_zstr
        jsr out_array_ok_ref
        bra emit_label_suffix

emit_set_varptr_current:
        lda #<out_lda_imm_hex
        ldy #>out_lda_imm_hex
        jsr out_zstr
        lda current_var_data_lo
        jsr out_hex_byte
        jsr out_cr
        lda #<out_sta_varptr
        ldy #>out_sta_varptr
        jsr out_zstr

        lda #<out_lda_imm_hex
        ldy #>out_lda_imm_hex
        jsr out_zstr
        lda current_var_data_hi
        jsr out_hex_byte
        jsr out_cr
        lda #<out_sta_varptr_1
        ldy #>out_sta_varptr_1
        jsr out_zstr

        lda #<out_lda_imm_hex
        ldy #>out_lda_imm_hex
        jsr out_zstr
        lda #VAR_BANK
        jsr out_hex_byte
        jsr out_cr
        lda #<out_sta_varptr_2
        ldy #>out_sta_varptr_2
        jsr out_zstr

        lda #<out_lda_imm_hex
        ldy #>out_lda_imm_hex
        jsr out_zstr
        lda #VAR_MB
        jsr out_hex_byte
        jsr out_cr
        lda #<out_sta_varptr_3
        ldy #>out_sta_varptr_3
        jsr out_zstr
        rts

emit_set_arrayptr_current:
        lda #<out_array_index_shift
        ldy #>out_array_index_shift
        jsr out_zstr
        lda #<out_adc_imm_hex
        ldy #>out_adc_imm_hex
        jsr out_zstr
        lda current_var_data_lo
        jsr out_hex_byte
        jsr out_cr
        lda #<out_sta_varptr
        ldy #>out_sta_varptr
        jsr out_zstr

        lda #<out_lda_exprhi
        ldy #>out_lda_exprhi
        jsr out_zstr
        lda #<out_adc_imm_hex
        ldy #>out_adc_imm_hex
        jsr out_zstr
        lda current_var_data_hi
        jsr out_hex_byte
        jsr out_cr
        lda #<out_sta_varptr_1
        ldy #>out_sta_varptr_1
        jsr out_zstr

        lda #<out_lda_imm_hex
        ldy #>out_lda_imm_hex
        jsr out_zstr
        lda #VAR_BANK
        jsr out_hex_byte
        jsr out_cr
        lda #<out_sta_varptr_2
        ldy #>out_sta_varptr_2
        jsr out_zstr

        lda #<out_lda_imm_hex
        ldy #>out_lda_imm_hex
        jsr out_zstr
        lda #VAR_MB
        jsr out_hex_byte
        jsr out_cr
        lda #<out_sta_varptr_3
        ldy #>out_sta_varptr_3
        jsr out_zstr
        rts

emit_push_expr:
        lda #<out_push_expr
        ldy #>out_push_expr
        jsr out_zstr
        rts

emit_pop_lhs:
        lda #<out_pop_lhs
        ldy #>out_pop_lhs
        jsr out_zstr
        rts

emit_add_lhs_expr:
        lda #<out_add_lhs_expr
        ldy #>out_add_lhs_expr
        jsr out_zstr
        rts

emit_sub_lhs_expr:
        lda #<out_sub_lhs_expr
        ldy #>out_sub_lhs_expr
        jsr out_zstr
        rts

emit_mul_lhs_expr:
        lda #<out_jsr_mul16
        ldy #>out_jsr_mul16
        jsr out_zstr
        rts

emit_div_lhs_expr:
        lda #<out_jsr_div16
        ldy #>out_jsr_div16
        jsr out_zstr
        rts

emit_neg_expr:
        lda #<out_neg_expr
        ldy #>out_neg_expr
        jsr out_zstr
        rts

emit_abs_expr:
        jsr alloc_if_tmp_label
        lda #<out_lda_exprhi
        ldy #>out_lda_exprhi
        jsr out_zstr
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

        lda #<out_lda_exprlo
        ldy #>out_lda_exprlo
        jsr out_zstr
        lda #<out_ora_exprhi
        ldy #>out_ora_exprhi
        jsr out_zstr
        lda #<out_beq_label
        ldy #>out_beq_label
        jsr emit_branch_if_tmp

        lda #<out_lda_exprhi
        ldy #>out_lda_exprhi
        jsr out_zstr
        lda #<out_bmi_label
        ldy #>out_bmi_label
        jsr out_zstr
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
        lda #<out_lda_exprlo
        ldy #>out_lda_exprlo
        jsr out_zstr
        lda #<out_ora_exprhi
        ldy #>out_ora_exprhi
        jsr out_zstr
        lda #<out_beq_label
        ldy #>out_beq_label
        jsr out_zstr
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
        lda #<out_lda_imm_hex
        ldy #>out_lda_imm_hex
        jsr out_zstr
        lda byte_value
        jsr out_hex_byte
        jsr out_cr
        lda #<out_sta_strarg1lo
        ldy #>out_sta_strarg1lo
        jsr out_zstr
        rts

emit_set_strarg1hi_imm:
        sta byte_value
        lda #<out_lda_imm_hex
        ldy #>out_lda_imm_hex
        jsr out_zstr
        lda byte_value
        jsr out_hex_byte
        jsr out_cr
        lda #<out_sta_strarg1hi
        ldy #>out_sta_strarg1hi
        jsr out_zstr
        rts

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
        lda #<out_sta_exprlo
        ldy #>out_sta_exprlo
        jsr out_zstr
        lda #<out_lda_imm_hex
        ldy #>out_lda_imm_hex
        jsr out_zstr
        lda #0
        jsr out_hex_byte
        jsr out_cr
        lda #<out_sta_exprhi
        ldy #>out_sta_exprhi
        jsr out_zstr
        rts

emit_bool_and_lhs_expr:
        jsr alloc_on_label
        lda on_label_lo
        sta on_done_lo
        lda on_label_hi
        sta on_done_hi
        jsr alloc_on_label
        lda #<out_lda_lhslo
        ldy #>out_lda_lhslo
        jsr out_zstr
        lda #<out_ora_lhshi
        ldy #>out_ora_lhshi
        jsr out_zstr
        lda #<out_beq_label
        ldy #>out_beq_label
        jsr out_zstr
        jsr out_onnext_ref
        jsr out_cr
        lda #<out_lda_exprlo
        ldy #>out_lda_exprlo
        jsr out_zstr
        lda #<out_ora_exprhi
        ldy #>out_ora_exprhi
        jsr out_zstr
        lda #<out_beq_label
        ldy #>out_beq_label
        jsr out_zstr
        jsr out_onnext_ref
        jsr out_cr
        lda #1
        sta number_lo
        lda #0
        sta number_hi
        jsr emit_load_number
        jsr emit_jmp_ondone
        jsr emit_onnext_label_def
        lda #0
        sta number_lo
        sta number_hi
        jsr emit_load_number
        jsr emit_ondone_label_def
        rts

emit_bool_or_lhs_expr:
        jsr alloc_on_label
        lda on_label_lo
        sta on_done_lo
        lda on_label_hi
        sta on_done_hi
        jsr alloc_on_label
        lda #<out_lda_lhslo
        ldy #>out_lda_lhslo
        jsr out_zstr
        lda #<out_ora_lhshi
        ldy #>out_ora_lhshi
        jsr out_zstr
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr out_zstr
        jsr out_onnext_ref
        jsr out_cr
        lda #<out_lda_exprlo
        ldy #>out_lda_exprlo
        jsr out_zstr
        lda #<out_ora_exprhi
        ldy #>out_ora_exprhi
        jsr out_zstr
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr out_zstr
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

emit_expr_to_rtptr:
        lda #<out_expr_to_rtptr
        ldy #>out_expr_to_rtptr
        jsr out_zstr
        rts

emit_save_rtptr:
        lda #<out_save_rtptr
        ldy #>out_save_rtptr
        jsr out_zstr
        rts

emit_restore_rtptr:
        lda #<out_restore_rtptr
        ldy #>out_restore_rtptr
        jsr out_zstr
        rts

emit_poke_expr_to_rtptr:
        lda #<out_poke_expr_to_rtptr
        ldy #>out_poke_expr_to_rtptr
        jsr out_zstr
        rts

emit_wpoke_expr_to_rtptr:
        lda #<out_wpoke_expr_to_rtptr
        ldy #>out_wpoke_expr_to_rtptr
        jsr out_zstr
        rts

emit_peek_expr:
        lda #<out_peek_expr
        ldy #>out_peek_expr
        jsr out_zstr
        rts

emit_wpeek_expr:
        lda #<out_wpeek_expr
        ldy #>out_wpeek_expr
        jsr out_zstr
        rts

emit_store_expr_to_forend:
        lda #<out_lda_exprlo
        ldy #>out_lda_exprlo
        jsr out_zstr
        lda #<out_sta_label
        ldy #>out_sta_label
        jsr out_zstr
        jsr out_forend_ref
        jsr out_cr
        lda #<out_lda_exprhi
        ldy #>out_lda_exprhi
        jsr out_zstr
        lda #<out_sta_label
        ldy #>out_sta_label
        jsr out_zstr
        jsr out_forend_ref
        jsr out_plus_one_cr
        rts

emit_store_expr_to_forstep:
        lda #<out_lda_exprlo
        ldy #>out_lda_exprlo
        jsr out_zstr
        lda #<out_sta_label
        ldy #>out_sta_label
        jsr out_zstr
        jsr out_forstep_ref
        jsr out_cr
        lda #<out_lda_exprhi
        ldy #>out_lda_exprhi
        jsr out_zstr
        lda #<out_sta_label
        ldy #>out_sta_label
        jsr out_zstr
        jsr out_forstep_ref
        jsr out_plus_one_cr
        rts

emit_load_forend:
        lda #<out_lda_label
        ldy #>out_lda_label
        jsr out_zstr
        jsr out_forend_ref
        jsr out_cr
        lda #<out_sta_exprlo
        ldy #>out_sta_exprlo
        jsr out_zstr
        lda #<out_lda_label
        ldy #>out_lda_label
        jsr out_zstr
        jsr out_forend_ref
        jsr out_plus_one_cr
        lda #<out_sta_exprhi
        ldy #>out_sta_exprhi
        jsr out_zstr
        rts

emit_load_forstep:
        lda #<out_lda_label
        ldy #>out_lda_label
        jsr out_zstr
        jsr out_forstep_ref
        jsr out_cr
        lda #<out_sta_exprlo
        ldy #>out_sta_exprlo
        jsr out_zstr
        lda #<out_lda_label
        ldy #>out_lda_label
        jsr out_zstr
        jsr out_forstep_ref
        jsr out_plus_one_cr
        lda #<out_sta_exprhi
        ldy #>out_sta_exprhi
        jsr out_zstr
        rts

emit_for_initial_check:
        lda #<out_lda_label
        ldy #>out_lda_label
        jsr out_zstr
        jsr out_forstep_ref
        jsr out_plus_one_cr
        lda #<out_bmi_label
        ldy #>out_bmi_label
        jsr out_zstr
        jsr out_forinitneg_ref
        jsr out_cr

        lda current_for_var_data_lo
        sta current_var_data_lo
        lda current_for_var_data_hi
        sta current_var_data_hi
        jsr emit_load_var
        jsr emit_push_expr
        jsr emit_load_forend
        jsr emit_pop_lhs
        lda #<out_jsr_cmple
        ldy #>out_jsr_cmple
        jsr out_zstr
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr out_zstr
        jsr out_fortop_ref
        jsr out_cr
        jsr emit_jmp_fordone

        jsr emit_forinitneg_label_def
        lda current_for_var_data_lo
        sta current_var_data_lo
        lda current_for_var_data_hi
        sta current_var_data_hi
        jsr emit_load_var
        jsr emit_push_expr
        jsr emit_load_forend
        jsr emit_pop_lhs
        lda #<out_jsr_cmpge
        ldy #>out_jsr_cmpge
        jsr out_zstr
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr out_zstr
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
        lda #<out_jmp_label
        ldy #>out_jmp_label
        jsr out_zstr
        jsr out_fortop_ref
        jsr out_cr
        rts

emit_jmp_fordone:
        lda #<out_jmp_label
        ldy #>out_jmp_label
        jsr out_zstr
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
        lda #<out_jmp_label
        ldy #>out_jmp_label
        jsr out_zstr
        jsr out_dotop_ref
        jsr out_cr
        rts

emit_jmp_dodone:
        lda #<out_jmp_label
        ldy #>out_jmp_label
        jsr out_zstr
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
        lda #<out_lda_lhslo
        ldy #>out_lda_lhslo
        jsr out_zstr
        lda #<out_ora_lhshi
        ldy #>out_ora_lhshi
        jsr out_zstr
        rts

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
        lda #<out_lda_lhslo
        ldy #>out_lda_lhslo
        jsr out_zstr
        lda #<out_ora_lhshi
        ldy #>out_ora_lhshi
        jsr out_zstr
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr emit_branch_if_true
        jsr emit_jmp_if_skip
        rts

emit_if_signed_prefix_lhs_negative_true:
        lda #<out_sign_xor_lhshi_exprhi
        ldy #>out_sign_xor_lhshi_exprhi
        jsr out_zstr
        lda #<out_bpl_label
        ldy #>out_bpl_label
        jsr emit_branch_if_tmp
        lda #<out_lda_lhshi
        ldy #>out_lda_lhshi
        jsr out_zstr
        lda #<out_bmi_label
        ldy #>out_bmi_label
        jsr emit_branch_if_true
        jsr emit_jmp_if_skip
        jsr emit_if_tmp_label_def
        rts

emit_if_signed_prefix_lhs_positive_true:
        lda #<out_sign_xor_lhshi_exprhi
        ldy #>out_sign_xor_lhshi_exprhi
        jsr out_zstr
        lda #<out_bpl_label
        ldy #>out_bpl_label
        jsr emit_branch_if_tmp
        lda #<out_lda_lhshi
        ldy #>out_lda_lhshi
        jsr out_zstr
        lda #<out_bmi_label
        ldy #>out_bmi_label
        jsr emit_branch_if_skip
        jsr emit_jmp_if_true
        jsr emit_if_tmp_label_def
        rts

emit_cmp_lhshi_exprhi:
        lda #<out_cmp_lhshi_exprhi
        ldy #>out_cmp_lhshi_exprhi
        jsr out_zstr
        rts

emit_cmp_lhslo_exprlo:
        lda #<out_cmp_lhslo_exprlo
        ldy #>out_cmp_lhslo_exprlo
        jsr out_zstr
        rts

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
        lda #<out_jmp_label
        ldy #>out_jmp_label
        jsr out_zstr
        jsr out_if_true_ref
        jsr out_cr
        rts

emit_jmp_if_skip:
        lda #<out_jmp_label
        ldy #>out_jmp_label
        jsr out_zstr
        jsr out_if_skip_ref
        jsr out_cr
        rts

emit_jmp_if_end:
        lda #<out_jmp_label
        ldy #>out_jmp_label
        jsr out_zstr
        jsr out_if_end_ref
        jsr out_cr
        rts

emit_jmp_if_else:
        lda #<out_jmp_label
        ldy #>out_jmp_label
        jsr out_zstr
        jsr out_if_else_ref
        jsr out_cr
        rts

emit_jmp_if_target:
        lda #<out_jmp_label
        ldy #>out_jmp_label
        jsr out_zstr
        lda if_target_lo
        sta number_lo
        lda if_target_hi
        sta number_hi
        jsr out_label_from_number
        jsr out_cr
        rts

emit_on_compare:
        lda #<out_lda_exprhi
        ldy #>out_lda_exprhi
        jsr out_zstr
        lda #<out_cmp_imm_hex
        ldy #>out_cmp_imm_hex
        jsr out_zstr
        lda #0
        jsr out_hex_byte
        jsr out_cr
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr out_zstr
        jsr out_onnext_ref
        jsr out_cr
        lda #<out_cmp_exprlo_imm
        ldy #>out_cmp_exprlo_imm
        jsr out_zstr
        lda on_target_index
        jsr out_hex_byte
        jsr out_cr
        lda #<out_bne_label
        ldy #>out_bne_label
        jsr out_zstr
        jsr out_onnext_ref
        jsr out_cr
        rts

emit_jmp_on_target:
        lda #<out_jmp_label
        ldy #>out_jmp_label
        jsr out_zstr
        lda on_target_lo
        sta number_lo
        lda on_target_hi
        sta number_hi
        jsr out_label_from_number
        jsr out_cr
        rts

emit_jsr_on_target:
        lda #<out_jsr_label
        ldy #>out_jsr_label
        jsr out_zstr
        lda on_target_lo
        sta number_lo
        lda on_target_hi
        sta number_hi
        jsr out_label_from_number
        jsr out_cr
        rts

emit_jmp_ondone:
        lda #<out_jmp_label
        ldy #>out_jmp_label
        jsr out_zstr
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
        lda #<out_iftrue_prefix
        ldy #>out_iftrue_prefix
        jsr out_zstr
        lda if_true_hi
        jsr out_hex_byte
        lda if_true_lo
        jsr out_hex_byte
        rts

out_if_skip_ref:
        lda #<out_ifskip_prefix
        ldy #>out_ifskip_prefix
        jsr out_zstr
        lda if_skip_hi
        jsr out_hex_byte
        lda if_skip_lo
        jsr out_hex_byte
        rts

out_if_end_ref:
        lda #<out_ifend_prefix
        ldy #>out_ifend_prefix
        jsr out_zstr
        lda if_end_hi
        jsr out_hex_byte
        lda if_end_lo
        jsr out_hex_byte
        rts

out_if_else_ref:
        lda #<out_ifelse_prefix
        ldy #>out_ifelse_prefix
        jsr out_zstr
        lda if_else_hi
        jsr out_hex_byte
        lda if_else_lo
        jsr out_hex_byte
        rts

out_if_tmp_ref:
        lda #<out_iftmp_prefix
        ldy #>out_iftmp_prefix
        jsr out_zstr
        lda if_tmp_hi
        jsr out_hex_byte
        lda if_tmp_lo
        jsr out_hex_byte
        rts

out_array_ok_ref:
        lda #<out_arrayok_prefix
        ldy #>out_arrayok_prefix
        jsr out_zstr
        lda array_ok_hi
        jsr out_hex_byte
        lda array_ok_lo
        jsr out_hex_byte
        rts

out_array_nonneg_ref:
        lda #<out_arraynonneg_prefix
        ldy #>out_arraynonneg_prefix
        jsr out_zstr
        lda array_ok_hi
        jsr out_hex_byte
        lda array_ok_lo
        jsr out_hex_byte
        rts

out_array_hieq_ref:
        lda #<out_arrayhieq_prefix
        ldy #>out_arrayhieq_prefix
        jsr out_zstr
        lda array_ok_hi
        jsr out_hex_byte
        lda array_ok_lo
        jsr out_hex_byte
        rts

out_onnext_ref:
        lda #<out_onnext_prefix
        ldy #>out_onnext_prefix
        jsr out_zstr
        lda on_label_hi
        jsr out_hex_byte
        lda on_label_lo
        jsr out_hex_byte
        rts

out_ondone_ref:
        lda #<out_ondone_prefix
        ldy #>out_ondone_prefix
        jsr out_zstr
        lda on_done_hi
        jsr out_hex_byte
        lda on_done_lo
        jsr out_hex_byte
        rts

out_forend_ref:
        lda #<out_forend_prefix
        ldy #>out_forend_prefix
        jsr out_zstr
        bra out_current_for_id

out_forstep_ref:
        lda #<out_forstep_prefix
        ldy #>out_forstep_prefix
        jsr out_zstr
        bra out_current_for_id

out_fortop_ref:
        lda #<out_fortop_prefix
        ldy #>out_fortop_prefix
        jsr out_zstr
        bra out_current_for_id

out_forneg_ref:
        lda #<out_forneg_prefix
        ldy #>out_forneg_prefix
        jsr out_zstr
        bra out_current_for_id

out_forinitneg_ref:
        lda #<out_forinitneg_prefix
        ldy #>out_forinitneg_prefix
        jsr out_zstr
        bra out_current_for_id

out_forcont_ref:
        lda #<out_forcont_prefix
        ldy #>out_forcont_prefix
        jsr out_zstr
        bra out_current_for_id

out_fordone_ref:
        lda #<out_fordone_prefix
        ldy #>out_fordone_prefix
        jsr out_zstr

out_current_for_id:
        lda #0
        jsr out_hex_byte
        lda current_for_id
        jsr out_hex_byte
        rts

out_dotop_ref:
        lda #<out_dotop_prefix
        ldy #>out_dotop_prefix
        jsr out_zstr
        bra out_current_do_id

out_dodone_ref:
        lda #<out_dodone_prefix
        ldy #>out_dodone_prefix
        jsr out_zstr

out_current_do_id:
        lda #0
        jsr out_hex_byte
        lda current_do_id
        jsr out_hex_byte
        rts

out_plus_one_cr:
        lda #'+'
        jsr out_char
        lda #'1'
        jsr out_char
        jsr out_cr
        rts

out_hex_word_number:
        ldx backend_mode
        bne +
        lda number_hi
        jsr out_hex_byte
        lda number_lo
        jsr out_hex_byte
+       rts

out_hex_byte:
        ldx backend_mode
        bne _out_hex_byte_done
        pha
        lsr
        lsr
        lsr
        lsr
        jsr out_hex_nibble
        pla
        and #$0f
        jsr out_hex_nibble
_out_hex_byte_done:
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
        jsr KERNAL_CHROUT
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
        jsr KERNAL_CHROUT
        lda #'$'
        jsr KERNAL_CHROUT
        pla
        jsr out_hex_byte
        lda #'>'
        jsr KERNAL_CHROUT
_comment_done:
        rts
_comment_space:
        lda #' '
_comment_printable:
        jsr KERNAL_CHROUT
        rts

; emit a single character of program text; silent outside text mode
out_char:
        ldx backend_mode
        bne +
        jsr KERNAL_CHROUT
+       rts

out_cr:
        ldx backend_mode
        beq +
        jmp bin_finalize_pending
+       lda #13
        jsr KERNAL_CHROUT
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
        jsr KERNAL_CHROUT
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
        jmp bin_add_pc

_bin_zstr_code:
        ldy #1
        lda (bin_ptr),y
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

; patch slot sizes indexed by kind-1: byte, word, lo, hi, rel8
bin_patch_size:
        .byte 1, 2, 1, 1, 1

bin_finalize_pending:
        ldx pending_kind
        beq +
        lda #0
        sta pending_kind
        lda bin_patch_size-1,x
        ; FALLTHROUGH
bin_add_pc:
        clc
        adc bin_pc
        sta bin_pc
        bcc +
        inc bin_pc+1
+       rts

screen_zstr:
        sta str_ptr
        sty str_ptr+1
        ldy #0
_screen_zstr_loop:
        lda (str_ptr),y
        beq _screen_zstr_done
        jsr KERNAL_CHROUT
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
        .text "basic65c: cannot load source.prg"
        .byte 13, 0
msg_open_out_fail:
        .text "basic65c: cannot open out.asm"
        .byte 13, 0
msg_finalize_fail:
        .text "basic65c: cannot rename out.tmp"
        .byte 13, 0
msg_bin_size:
        .text "native size: ends $"
        .byte 0
msg_backend_error:
        .text "basic65c: bin template map incomplete"
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
msg_error_unsupported_token:
        .text "unsupported token"
        .byte 13, 0
msg_error_unsupported_statement:
        .text "unsupported statement"
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

out_header:
        .text "; generated by basic65c"
        .byte 13
        .text "; link: 64tass --cbm-prg --m45gs02 runtime.asm out.asm -o out.prg"
        .byte 13
        .text "        .enc ""none"""
        .byte 13, 13
        .text "        * = $4000"
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
        .byte 13, 13
        .text "start:"
        .byte 13
        .byte 0

out_comment_load_addr:
        .text "; input prg load address: $"
        .byte 0

out_tail:
        .text "        jmp rtexit"
        .byte 13
        .byte 13
        .byte 0

out_varheapend_def:
        .text "varheapend = $"
        .byte 0

out_size_guard:
        .text "        .cerror * > $d000, ""program too large: runs into i/o space"""
        .byte 13
        .byte 0

out_data_table_start:
        .text "datastart:"
        .byte 13, 0
out_data_byte_prefix:
        .text "        .byte $"
        .byte 0
out_data_byte_sep:
        .text ",$"
        .byte 0
out_data_word_prefix:
        .text "        .word "
        .byte 0
out_data_table_end:
        .text "dataend:"
        .byte 13
        .byte 13
        .byte 0
out_string_pool_header:
        .text "; string literals"
        .byte 13, 0

out_strroots_start:
        .text "; string gc roots: rootlo, roothi, bytelenlo, bytelenhi"
        .byte 13
        .text "strroots:"
        .byte 13, 0

out_for_storage_header:
        .text "; for/next runtime storage"
        .byte 13, 0

out_for_word_storage:
        .text ":       .byte 0,0"
        .byte 13, 0

out_lda_imm_hex:
        .text "        lda #$"
        .byte 0
out_lda_label_lo_imm:
        .text "        lda #<"
        .byte 0
out_lda_label_hi_imm:
        .text "        lda #>"
        .byte 0
out_adc_imm_hex:
        .text "        adc #$"
        .byte 0
out_cmp_imm_hex:
        .text "        cmp #$"
        .byte 0
out_jsr_chout:
        .text "        jsr printch"
        .byte 13, 0
out_jsr_printuint:
        .text "        jsr printuint"
        .byte 13, 0
out_jsr_printstr:
        .text "        jsr printstr"
        .byte 13, 0
out_jsr_printheapstr:
        .text "        jsr printheapstr"
        .byte 13, 0
out_jsr_strfromlit:
        .text "        jsr strfromlit"
        .byte 13, 0
out_jsr_strcopyexpr:
        .text "        jsr strcopyexpr"
        .byte 13, 0
out_jsr_concatstr:
        .text "        jsr concatstr"
        .byte 13, 0
out_jsr_strlenexpr:
        .text "        jsr strlenexpr"
        .byte 13, 0
out_jsr_strfromint:
        .text "        jsr strfromint"
        .byte 13, 0
out_jsr_valstr:
        .text "        jsr valstr"
        .byte 13, 0
out_jsr_strmark:
        .text "        jsr strmark"
        .byte 13, 0
out_jsr_strrelease:
        .text "        jsr strrelease"
        .byte 13, 0
out_jsr_strsub:
        .text "        jsr strsub"
        .byte 13, 0
out_jsr_strright:
        .text "        jsr strright"
        .byte 13, 0
out_jsr_streq:
        .text "        jsr streq"
        .byte 13, 0
out_jsr_strne:
        .text "        jsr strne"
        .byte 13, 0
out_jsr_strlt:
        .text "        jsr strlt"
        .byte 13, 0
out_jsr_strle:
        .text "        jsr strle"
        .byte 13, 0
out_jsr_strgt:
        .text "        jsr strgt"
        .byte 13, 0
out_jsr_strge:
        .text "        jsr strge"
        .byte 13, 0
out_jsr_strrefeq:
        .text "        jsr strrefeq"
        .byte 13, 0
out_jsr_strrefne:
        .text "        jsr strrefne"
        .byte 13, 0
out_jsr_strreflt:
        .text "        jsr strreflt"
        .byte 13, 0
out_jsr_strrefle:
        .text "        jsr strrefle"
        .byte 13, 0
out_jsr_strrefgt:
        .text "        jsr strrefgt"
        .byte 13, 0
out_jsr_strrefge:
        .text "        jsr strrefge"
        .byte 13, 0
out_jsr_printcomma:
        .text "        jsr printcomma"
        .byte 13, 0
out_jsr_loadintvar:
        .text "        jsr loadintvar"
        .byte 13, 0
out_jsr_storeintvar:
        .text "        jsr storeintvar"
        .byte 13, 0
out_jsr_loadnumvar:
        .text "        jsr loadnumvar"
        .byte 13, 0
out_jsr_storenumvar:
        .text "        jsr storenumvar"
        .byte 13, 0
out_jsr_storefloatref:
        .text "        jsr storefloatref"
        .byte 13, 0
out_jsr_printnumvar:
        .text "        jsr printnumvar"
        .byte 13, 0
out_jsr_printfloatref:
        .text "        jsr printfloatref"
        .byte 13, 0
out_jsr_readint:
        .text "        jsr readint"
        .byte 13, 0
out_jsr_readstr:
        .text "        jsr readstr"
        .byte 13, 0
out_jsr_inputline:
        .text "        jsr inputline"
        .byte 13, 0
out_jsr_inputint:
        .text "        jsr inputint"
        .byte 13, 0
out_jsr_inputstr:
        .text "        jsr inputstr"
        .byte 13, 0
out_jsr_getkey:
        .text "        jsr getkey"
        .byte 13, 0
out_jsr_getstr:
        .text "        jsr getstr"
        .byte 13, 0
out_jsr_datainit:
        .text "        jsr datainit"
        .byte 13, 0
out_jsr_cmpeq:
        .text "        jsr cmpeq"
        .byte 13, 0
out_jsr_cmpne:
        .text "        jsr cmpne"
        .byte 13, 0
out_jsr_cmplt:
        .text "        jsr cmplt"
        .byte 13, 0
out_jsr_cmple:
        .text "        jsr cmple"
        .byte 13, 0
out_jsr_cmpgt:
        .text "        jsr cmpgt"
        .byte 13, 0
out_jsr_cmpge:
        .text "        jsr cmpge"
        .byte 13, 0
out_sta_varptr:
        .text "        sta varptr"
        .byte 13, 0
out_sta_varptr_1:
        .text "        sta varptr+1"
        .byte 13, 0
out_sta_varptr_2:
        .text "        sta varptr+2"
        .byte 13, 0
out_sta_varptr_3:
        .text "        sta varptr+3"
        .byte 13, 0
out_sta_exprlo:
        .text "        sta exprlo"
        .byte 13, 0
out_sta_exprhi:
        .text "        sta exprhi"
        .byte 13, 0
out_sta_dataptrlo:
        .text "        sta dataptrlo"
        .byte 13, 0
out_sta_dataptrhi:
        .text "        sta dataptrhi"
        .byte 13, 0
out_sta_rtptr:
        .text "        sta rtptr"
        .byte 13, 0
out_sta_rtptr_1:
        .text "        sta rtptr+1"
        .byte 13, 0
out_sta_strarg1lo:
        .text "        sta strarg1lo"
        .byte 13, 0
out_sta_strarg1hi:
        .text "        sta strarg1hi"
        .byte 13, 0
out_lda_exprlo:
        .text "        lda exprlo"
        .byte 13, 0
out_lda_exprhi:
        .text "        lda exprhi"
        .byte 13, 0
out_array_check_start:
        .text "        lda exprhi"
        .byte 13
        .text "        bpl "
        .byte 0
out_cmp_exprhi_imm:
        .text "        cmp #$"
        .byte 0
out_cmp_exprlo_imm:
        .text "        lda exprlo"
        .byte 13
        .text "        cmp #$"
        .byte 0
out_jmp_arraybounds:
        .text "        jmp arraybounds"
        .byte 13, 0
out_array_index_shift:
        .text "        asl exprlo"
        .byte 13
        .text "        rol exprhi"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        lda exprlo"
        .byte 13, 0
out_save_arrayptr:
        .text "        lda varptr"
        .byte 13
        .text "        sta arrptrlo"
        .byte 13
        .text "        lda varptr+1"
        .byte 13
        .text "        sta arrptrhi"
        .byte 13, 0
out_restore_arrayptr:
        .text "        lda arrptrlo"
        .byte 13
        .text "        sta varptr"
        .byte 13
        .text "        lda arrptrhi"
        .byte 13
        .text "        sta varptr+1"
        .byte 13
        .text "        lda #$01"
        .byte 13
        .text "        sta varptr+2"
        .byte 13
        .text "        lda #$00"
        .byte 13
        .text "        sta varptr+3"
        .byte 13, 0
out_lda_label:
        .text "        lda "
        .byte 0
out_sta_label:
        .text "        sta "
        .byte 0
out_forend_prefix:
        .text "forend"
        .byte 0
out_forstep_prefix:
        .text "forstep"
        .byte 0
out_fortop_prefix:
        .text "fortop"
        .byte 0
out_forneg_prefix:
        .text "forneg"
        .byte 0
out_forinitneg_prefix:
        .text "forinitneg"
        .byte 0
out_forcont_prefix:
        .text "forcont"
        .byte 0
out_fordone_prefix:
        .text "fordone"
        .byte 0
out_dotop_prefix:
        .text "dotop"
        .byte 0
out_dodone_prefix:
        .text "dodone"
        .byte 0
out_iftrue_prefix:
        .text "iftrue"
        .byte 0
out_ifskip_prefix:
        .text "ifskip"
        .byte 0
out_ifend_prefix:
        .text "ifend"
        .byte 0
out_ifelse_prefix:
        .text "ifelse"
        .byte 0
out_iftmp_prefix:
        .text "iftmp"
        .byte 0
out_arrayok_prefix:
        .text "arrayok"
        .byte 0
out_arraynonneg_prefix:
        .text "arraypos"
        .byte 0
out_arrayhieq_prefix:
        .text "arrayhieq"
        .byte 0
out_onnext_prefix:
        .text "onnext"
        .byte 0
out_ondone_prefix:
        .text "ondone"
        .byte 0
out_push_expr:
        .text "        lda exprlo"
        .byte 13
        .text "        pha"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        pha"
        .byte 13, 0
out_pop_lhs:
        .text "        pla"
        .byte 13
        .text "        sta lhshi"
        .byte 13
        .text "        pla"
        .byte 13
        .text "        sta lhslo"
        .byte 13, 0
out_add_lhs_expr:
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
out_sub_lhs_expr:
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
out_jsr_mul16:
        .text "        jsr mul16"
        .byte 13, 0
out_jsr_div16:
        .text "        jsr div16"
        .byte 13, 0
out_neg_expr:
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
out_expr_to_rtptr:
        .text "        lda exprlo"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13, 0
out_save_rtptr:
        .text "        lda rtptr"
        .byte 13
        .text "        sta arrptrlo"
        .byte 13
        .text "        lda rtptr+1"
        .byte 13
        .text "        sta arrptrhi"
        .byte 13, 0
out_restore_rtptr:
        .text "        lda arrptrlo"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda arrptrhi"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13, 0
out_poke_expr_to_rtptr:
        .text "        lda exprlo"
        .byte 13
        .text "        ldy #0"
        .byte 13
        .text "        sta (rtptr),y"
        .byte 13, 0
out_wpoke_expr_to_rtptr:
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
out_peek_expr:
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
out_wpeek_expr:
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
out_cmp_lhshi_exprhi:
        .text "        lda lhshi"
        .byte 13
        .text "        cmp exprhi"
        .byte 13, 0
out_cmp_lhslo_exprlo:
        .text "        lda lhslo"
        .byte 13
        .text "        cmp exprlo"
        .byte 13, 0
out_sign_xor_lhshi_exprhi:
        .text "        lda lhshi"
        .byte 13
        .text "        eor exprhi"
        .byte 13, 0
out_lda_lhshi:
        .text "        lda lhshi"
        .byte 13, 0
out_lda_lhslo:
        .text "        lda lhslo"
        .byte 13, 0
out_ora_lhshi:
        .text "        ora lhshi"
        .byte 13, 0
out_ora_exprhi:
        .text "        ora exprhi"
        .byte 13, 0
out_jmp_label:
        .text "        jmp "
        .byte 0
out_jsr_label:
        .text "        jsr "
        .byte 0
out_bne_label:
        .text "        bne "
        .byte 0
out_beq_label:
        .text "        beq "
        .byte 0
out_bcc_label:
        .text "        bcc "
        .byte 0
out_bcs_label:
        .text "        bcs "
        .byte 0
out_bpl_label:
        .text "        bpl "
        .byte 0
out_bmi_label:
        .text "        bmi "
        .byte 0
out_jsr_abs:
        .text "        jsr $"
        .byte 0
out_sta_abs:
        .text "        sta $"
        .byte 0
out_rts:
        .text "        rts"
        .byte 13, 0
out_jmp_rtexit:
        .text "        jmp rtexit"
        .byte 13, 0
out_rem:
        .text "        ; rem"
        .byte 0
out_data_comment:
        .text "        ; data skipped"
        .byte 13, 0
out_dim_comment:
        .text "        ; dim allocated in variable heap"
        .byte 13, 0
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
        .byte 0
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
bin_pc:
        .word 0
bin_key_lo:
        .byte 0
bin_key_hi:
        .byte 0
line_emit_idx:
        .byte 0
datastart_addr:
        .word 0
dataend_addr:
        .word 0
strroots_addr:
        .word 0
line_addr_lo:
        .fill LINE_MAX, 0
line_addr_hi:
        .fill LINE_MAX, 0
line_buf:
        .fill LINE_BUF_MAX, 0
source_filename_len:
        .byte 0
source_filename_buf:
        .fill FILENAME_MAX + 1, 0
line_table_lo:
        .fill LINE_MAX, 0
line_table_hi:
        .fill LINE_MAX, 0
branch_table_lo:
        .fill BRANCH_MAX, 0
branch_table_hi:
        .fill BRANCH_MAX, 0
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
string_off_lo:
        .fill STRING_MAX, 0
string_off_hi:
        .fill STRING_MAX, 0
string_temp:
        .fill LINE_BUF_MAX + 1, 0
string_pool:
        .fill STRING_POOL_MAX, 0

;=======================================================================================
; Derived binary template records (regenerated by tools\gen-bin-templates.py)
;=======================================================================================

        .include "gen/bin-templates.inc"

        .cerror * >= $a000, "resident compiler grew past $a000"
