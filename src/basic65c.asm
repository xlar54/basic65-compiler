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
; Unsupported statements become assembly comments so the generated output
; remains inspectable and assemblable.
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
TOK_POKE                = $97
TOK_PRINT_HASH          = $98
TOK_PRINT               = $99
TOK_SYS                 = $9E
TOK_TO                  = $A4
TOK_THEN                = $A7
TOK_STEP                = $A9
TOK_PLUS                = $AA
TOK_MINUS               = $AB
TOK_MUL                 = $AC
TOK_DIV                 = $AD
TOK_GT                  = $B1
TOK_EQUAL               = $B2
TOK_LT                  = $B3
TOK_GO                  = $CB
TOK_EXT_CE              = $CE
TOK_EXT_FE              = $FE

COND_EQ                 = 1
COND_NE                 = 2
COND_LT                 = 3
COND_LE                 = 4
COND_GT                 = 5
COND_GE                 = 6

ASCII_UPPER_A           = $41
ASCII_UPPER_F           = $46
ASCII_UPPER_Z           = $5A
ASCII_LOWER_A           = $61
ASCII_LOWER_F           = $66

LINE_BUF_MAX            = 240
LINE_MAX                = 240
BRANCH_MAX              = 128
FOR_STACK_MAX           = 16
IF_STACK_MAX            = 16
FOR_MAX                 = 64
ARRAY_RANK_MAX          = 6
DATA_MAX                = 128

SYM_MAX                 = 128
VAR_KIND_SCALAR         = 0
VAR_KIND_ARRAY1         = 1
VAR_TYPE_INT            = 1
VAR_TYPE_FLOAT          = 2
VAR_TYPE_STRING         = 3
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
        sta sym_count
        sta line_count
        sta branch_count
        sta data_count
        sta if_label_next_lo
        sta if_label_next_hi
        sta array_label_next_lo
        sta array_label_next_hi
        sta for_label_next
        sta for_sp
        sta if_sp
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
        jsr validate_branch_targets

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
        jsr emit_generated_tail

        jsr KERNAL_CLRCHN
        lda #LFN_OUT
        jsr KERNAL_CLOSE
        jsr KERNAL_CLRCHN
        lda #13
        jsr KERNAL_CHROUT

        lda compile_error
        beq _main_done_ok
        lda #<msg_compile_warn
        ldy #>msg_compile_warn
        jsr screen_zstr
        rts

_main_done_ok:
        lda #<msg_done
        ldy #>msg_done
        jsr screen_zstr
        rts

show_compile_line:
        jsr KERNAL_CLRCHN
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
        jsr KERNAL_CLRCHN
        lda #<msg_compiling_start
        ldy #>msg_compiling_start
        jsr screen_zstr
        ldx #LFN_OUT
        jsr KERNAL_CHKOUT
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

load_source:
        lda #SOURCE_BANK
        ldx #0
        jsr KERNAL_SETBNK

        lda #0
        ldx #DEVICE_DISK
        ldy #0
        jsr KERNAL_SETLFS

        lda #source_name_end - source_name
        ldx #<source_name
        ldy #>source_name
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
        bcs _scratch_output_done
        ldx #LFN_CMD
        jsr KERNAL_CHKOUT
        bcs _scratch_output_done
        ldy #0
_scratch_cmd_loop:
        lda scratch_name,y
        jsr KERNAL_CHROUT
        iny
        cpy #scratch_name_end - scratch_name
        bne _scratch_cmd_loop

_scratch_output_done:
        jsr KERNAL_CLRCHN
        lda #LFN_CMD
        jsr KERNAL_CLOSE
        jsr KERNAL_CLRCHN
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
        lda #<out_comment_load_addr
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
        lda #1
        sta compile_error
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
        cmp #VAR_TYPE_INT
        bne _scan_dim_bad

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
        beq _scan_data_empty
        cmp #'"'
        beq _scan_data_string

        jsr line_parse_signed_number
        bcs _scan_data_skip_item
        jsr record_data_number
        bcs _scan_data_bad
        bra _scan_data_after_item

_scan_data_empty:
        jsr line_get
        bra _scan_data_next

_scan_data_string:
        jsr line_get
        jsr scan_skip_string
        bra _scan_data_after_item

_scan_data_skip_item:
        jsr scan_skip_data_item

_scan_data_after_item:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _scan_data_done
        jsr line_get
        cmp #','
        beq _scan_data_next

_scan_data_bad:
        lda #1
        sta compile_error
        jsr line_skip_to_stmt_end

_scan_data_done:
        rts

scan_skip_data_item:
_scan_skip_data_loop:
        jsr line_at_end
        bcs _scan_skip_data_done
        jsr line_peek
        cmp #':'
        beq _scan_skip_data_done
        cmp #','
        beq _scan_skip_data_done
        cmp #'"'
        beq _scan_skip_data_string
        inc line_idx
        bra _scan_skip_data_loop

_scan_skip_data_string:
        jsr line_get
        jsr scan_skip_string
        bra _scan_skip_data_loop

_scan_skip_data_done:
        rts

record_data_number:
        ldx data_count
        cpx #DATA_MAX
        bcs _record_data_fail
        lda number_lo
        sta data_table_lo,x
        lda number_hi
        sta data_table_hi,x
        inc data_count
        clc
        rts

_record_data_fail:
        sec
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

;=======================================================================================
; Line compiler
;=======================================================================================

compile_line:
        lda line_overflow
        beq +
        lda #1
        sta compile_error
        lda #<out_line_overflow
        ldy #>out_line_overflow
        jsr out_zstr
+       lda #0
        sta line_idx
        jsr compile_line_statements
        jsr out_cr
        rts

compile_line_statements:
_compile_line_loop:
        jsr line_skip_spaces_colons
        jsr line_at_end
        bcs _compile_line_done

        jsr line_get
        cmp #TOK_FOR
        beq _compile_for
        cmp #TOK_NEXT
        beq _compile_next
        cmp #TOK_PRINT
        beq _compile_print
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
        cmp #TOK_PRINT_HASH
        beq _compile_unsupported_token
        cmp #TOK_EXT_CE
        beq _compile_unsupported_extended_token
        cmp #TOK_EXT_FE
        beq _compile_unsupported_extended_token

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

_compile_print:
        jsr compile_print
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
        lda #<out_rts
        ldy #>out_rts
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

_compile_assignment_from_token:
        lda token_value
        jsr compile_assignment_with_first_char
        bra _compile_line_loop

_compile_unsupported_token:
        sta token_value
_compile_unsupported_token_stored:
        lda #1
        sta compile_error
        lda #<out_unsupported_token
        ldy #>out_unsupported_token
        jsr out_zstr
        lda token_value
        jsr out_hex_byte
        jsr out_cr
        jsr line_skip_to_stmt_end
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
        lda #1
        sta compile_error
        lda #<out_unsupported_token
        ldy #>out_unsupported_token
        jsr out_zstr
        lda token_prefix
        jsr out_hex_byte
        lda token_value
        jsr out_hex_byte
        jsr out_cr
        jsr line_skip_to_stmt_end
        bra _compile_line_loop

_compile_unsupported_statement:
        lda #1
        sta compile_error
        lda #<out_unsupported_statement
        ldy #>out_unsupported_statement
        jsr out_zstr
        jsr line_skip_to_stmt_end
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
        cmp #VAR_TYPE_INT
        bne compile_assignment_bad
        jsr line_skip_spaces
        jsr line_at_end
        bcs compile_assignment_bad
        jsr line_peek
        cmp #'('
        beq _compile_array_assignment

        jsr resolve_var
        bcs compile_assignment_bad
        lda current_var_data_lo
        sta assign_var_data_lo
        lda current_var_data_hi
        sta assign_var_data_hi
        jsr line_get
        cmp #TOK_EQUAL
        beq _compile_assignment_expr
        cmp #'='
        bne compile_assignment_bad

_compile_assignment_expr:
        jsr compile_expression
        bcs compile_assignment_bad
        jsr emit_store_var
        rts

_compile_array_assignment:
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

compile_assignment_bad:
        lda #1
        sta compile_error
        lda #<out_bad_assignment
        ldy #>out_bad_assignment
        jsr out_zstr
        jsr line_skip_to_stmt_end
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
        cmp #VAR_TYPE_INT
        bne compile_for_bad
        jsr resolve_var
        bcs compile_for_bad
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
        lda #1
        sta compile_error
        lda #<out_bad_for
        ldy #>out_bad_for
        jsr out_zstr
        jsr line_skip_to_stmt_end
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
        cmp #VAR_TYPE_INT
        bne compile_next_bad
        jsr resolve_var
        bcs compile_next_bad
        lda current_var_data_lo
        cmp current_for_var_data_lo
        bne compile_next_bad
        lda current_var_data_hi
        cmp current_for_var_data_hi
        bne compile_next_bad

_compile_next_emit:
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
        lda #1
        sta compile_error
        lda #<out_bad_next
        ldy #>out_bad_next
        jsr out_zstr
        jsr line_skip_to_stmt_end
        rts

compile_if:
        jsr alloc_if_labels
        jsr compile_expression
        bcs compile_if_bad
        jsr emit_push_expr
        jsr parse_if_compare_op
        bcs compile_if_bad
        jsr compile_expression
        bcs compile_if_bad

        jsr line_skip_spaces
        jsr line_at_end
        bcs compile_if_bad
        jsr line_get
        cmp #TOK_THEN
        bne compile_if_bad

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
        jsr emit_if_comparison
        jsr push_if_labels
        jsr compile_line_statements
        jsr pop_if_labels
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
        lda #1
        sta compile_error
        lda #<out_bad_if
        ldy #>out_bad_if
        jsr out_zstr
        jsr line_skip_to_end
        rts

parse_if_compare_op:
        jsr line_skip_spaces
        jsr line_at_end
        bcs _parse_if_compare_fail
        jsr line_get
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
        lda #COND_EQ
        sta cond_op
        clc
        rts

_parse_if_compare_lt:
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
        cmp #VAR_TYPE_INT
        bne _factor_fail
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
        jsr line_at_end_or_colon
        bcs _print_finish

        jsr line_peek
        cmp #'"'
        beq _print_string
        cmp #';'
        beq _print_semicolon
        cmp #','
        beq _print_comma
        bra _print_expression

_print_expression:
        jsr compile_expression
        bcs _print_expression_bad
        lda #<out_jsr_printuint
        ldy #>out_jsr_printuint
        jsr out_zstr
        lda #0
        sta print_suppress_cr
        bra _print_loop

_print_expression_bad:
        lda #1
        sta compile_error
        lda #<out_unsupported_print
        ldy #>out_unsupported_print
        jsr out_zstr
        jsr line_skip_to_stmt_end
        bra _print_finish

_print_string:
        jsr line_get                         ; opening quote
        lda #0
        sta print_suppress_cr
_print_string_loop:
        jsr line_at_end
        bcs _print_finish
        jsr line_get
        cmp #'"'
        beq _print_loop
        jsr emit_chout_imm
        bra _print_string_loop

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

_print_finish:
        lda print_suppress_cr
        bne _print_done
        lda #13
        jsr emit_chout_imm
_print_done:
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
        lda #1
        sta compile_error
        lda #<out_bad_goto
        ldy #>out_bad_goto
        jsr out_zstr
        jsr line_skip_to_stmt_end
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
        lda #1
        sta compile_error
        lda #<out_bad_gosub
        ldy #>out_bad_gosub
        jsr out_zstr
        jsr line_skip_to_stmt_end
        rts

compile_go:
        jsr line_skip_spaces
        jsr line_get
        cmp #TOK_TO
        beq compile_goto
        cmp #TOK_SYS
        beq compile_sys
        sta token_value
        lda #1
        sta compile_error
        lda #<out_unsupported_go
        ldy #>out_unsupported_go
        jsr out_zstr
        lda token_value
        jsr out_hex_byte
        jsr out_cr
        jsr line_skip_to_stmt_end
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
        lda #1
        sta compile_error
        lda #<out_bad_sys
        ldy #>out_bad_sys
        jsr out_zstr
        jsr line_skip_to_stmt_end
        rts

compile_poke:
        jsr compile_expression
        bcs _poke_bad
        jsr emit_expr_to_rtptr
        jsr line_skip_spaces
        jsr line_at_end
        bcs _poke_bad
        jsr line_get
        cmp #','
        bne _poke_bad
        jsr compile_expression
        bcs _poke_bad
        jsr emit_poke_expr_to_rtptr
        rts

_poke_bad:
        lda #1
        sta compile_error
        lda #<out_bad_poke
        ldy #>out_bad_poke
        jsr out_zstr
        jsr line_skip_to_stmt_end
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
        cmp #VAR_TYPE_INT
        bne _compile_read_bad

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
        jsr emit_read_int
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
        jsr emit_read_int
        jsr emit_store_ptr

_compile_read_after_target:
        jsr line_skip_spaces
        jsr line_at_end_or_colon
        bcs _compile_read_done
        jsr line_get
        cmp #','
        beq _compile_read_next

_compile_read_bad:
        lda #1
        sta compile_error
        lda #<out_bad_read
        ldy #>out_bad_read
        jsr out_zstr
        jsr line_skip_to_stmt_end

_compile_read_done:
        rts

compile_restore:
        lda #<out_jsr_datainit
        ldy #>out_jsr_datainit
        jsr out_zstr
        jsr line_skip_to_stmt_end
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

parse_variable_with_first_char:
        sta var_name_1
        lda #0
        sta var_name_2
        sta var_kind
        lda #VAR_TYPE_INT
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
_skip_sc_loop:
        jsr line_at_end
        bcs _skip_sc_done
        jsr line_peek
        cmp #' '
        beq _skip_sc_take
        cmp #':'
        bne _skip_sc_done
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

line_parse_signed_number:
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
        jsr line_parse_number
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
        clc
        rts

_pop_for_fail:
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
        lda if_tmp_lo
        sta if_stack_tmp_lo,x
        lda if_tmp_hi
        sta if_stack_tmp_hi,x
        inc if_sp
        clc
        rts

_push_if_fail:
        lda #1
        sta compile_error
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
        lda #1
        sta compile_error
        sec
        rts

emit_generated_header:
        lda #<out_header
        ldy #>out_header
        jsr out_zstr
        rts

emit_generated_tail:
        lda #<out_tail
        ldy #>out_tail
        jsr out_zstr
        jsr emit_variable_runtime
        lda #<out_runtime_math
        ldy #>out_runtime_math
        jsr out_zstr
        lda #<out_runtime_compare
        ldy #>out_runtime_compare
        jsr out_zstr
        lda #<out_runtime_print
        ldy #>out_runtime_print
        jsr out_zstr
        lda #<out_runtime_data
        ldy #>out_runtime_data
        jsr out_zstr
        jsr emit_data_table
        lda #<out_runtime_array_bounds
        ldy #>out_runtime_array_bounds
        jsr out_zstr
        jsr emit_for_storage
        lda #<out_runtime_storage
        ldy #>out_runtime_storage
        jsr out_zstr
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
        lda #<out_data_table_start
        ldy #>out_data_table_start
        jsr out_zstr
        lda #0
        sta data_emit_idx

_emit_data_table_loop:
        lda data_emit_idx
        cmp data_count
        bcs _emit_data_table_done
        lda #<out_data_byte_prefix
        ldy #>out_data_byte_prefix
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

_emit_data_table_done:
        lda #<out_data_table_end
        ldy #>out_data_table_end
        jsr out_zstr
        rts

emit_variable_runtime:
        lda #<out_var_runtime_header
        ldy #>out_var_runtime_header
        jsr out_zstr
        lda var_heap_next_hi
        jsr out_hex_byte
        lda var_heap_next_lo
        jsr out_hex_byte
        jsr out_cr
        jsr out_cr
        lda #<out_var_runtime
        ldy #>out_var_runtime
        jsr out_zstr
        rts

emit_line_label:
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

out_label_from_number:
        lda #'l'
        jsr KERNAL_CHROUT
        jsr out_hex_word_number
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

emit_print_comma:
        lda #<out_jsr_printcomma
        ldy #>out_jsr_printcomma
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
        lda #<out_jsr_loadintvar
        ldy #>out_jsr_loadintvar
        jsr out_zstr
        rts

emit_store_var:
        lda assign_var_data_lo
        sta current_var_data_lo
        lda assign_var_data_hi
        sta current_var_data_hi
        jsr emit_set_varptr_current
        jsr emit_store_ptr
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
        lda number_hi
        jsr out_hex_byte
        jsr out_cr
        lda #<out_bcc_label
        ldy #>out_bcc_label
        jsr out_zstr
        jsr out_array_ok_ref
        jsr out_cr
        lda #<out_bne_arraybounds
        ldy #>out_bne_arraybounds
        jsr out_zstr
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

emit_expr_to_rtptr:
        lda #<out_expr_to_rtptr
        ldy #>out_expr_to_rtptr
        jsr out_zstr
        rts

emit_poke_expr_to_rtptr:
        lda #<out_poke_expr_to_rtptr
        ldy #>out_poke_expr_to_rtptr
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

emit_if_comparison:
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

_emit_if_cmp_done:
        jsr emit_if_skip_label_def
        jsr emit_jmp_if_end
        jsr emit_if_true_label_def
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

emit_if_true_label_def:
        jsr out_if_true_ref
        bra emit_label_suffix

emit_if_skip_label_def:
        jsr out_if_skip_ref
        bra emit_label_suffix

emit_if_end_label_def:
        jsr out_if_end_ref
        bra emit_label_suffix

emit_if_tmp_label_def:
        jsr out_if_tmp_ref

emit_label_suffix:
        lda #':'
        jsr KERNAL_CHROUT
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

out_plus_one_cr:
        lda #'+'
        jsr KERNAL_CHROUT
        lda #'1'
        jsr KERNAL_CHROUT
        jsr out_cr
        rts

out_var_label:
        lda #<out_var_prefix
        ldy #>out_var_prefix
        jsr out_zstr
        lda var_name_1
        jsr KERNAL_CHROUT
        rts

out_hex_word_number:
        lda number_hi
        jsr out_hex_byte
        lda number_lo
        jsr out_hex_byte
        rts

out_hex_byte:
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
        jsr KERNAL_CHROUT
        rts

out_comment_char:
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
        rts
_comment_space:
        lda #' '
_comment_printable:
        jsr KERNAL_CHROUT
        rts

out_cr:
        lda #13
        jsr KERNAL_CHROUT
        rts

out_zstr:
        sta str_ptr
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
        .text "0:out.asm,s,w"
output_name_end:

scratch_name:
        .text "s0:out.asm"
        .byte 13
scratch_name_end:

msg_banner:
        .byte 13
        .text "basic65c: source.prg -> out.asm"
        .byte 13, 0
msg_opening_in:
        .text "loading source.prg"
        .byte 13, 0
msg_scanning_in:
        .text "scanning source.prg"
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
msg_done:
        .text "basic65c: wrote out.asm"
        .byte 13, 0
msg_compile_warn:
        .text "basic65c: wrote out.asm with warnings"
        .byte 13, 0
msg_compiling_start:
        .text "compiling:"
        .byte 13, 0

out_header:
        .text "; generated by basic65c"
        .byte 13
        .text "        .enc ""none"""
        .byte 13, 13
        .text "kernalchrout = $ffd2"
        .byte 13
        .text "varptr = $f7"
        .byte 13
        .text "rtptr = $fb"
        .byte 13, 13
        .text "        * = $2001"
        .byte 13
        .text "        .word (+), 2026"
        .byte 13
        .text "        .byte $fe, $02, $30"
        .byte 13
        .text "        .byte ':'"
        .byte 13
        .text "        .byte $9e"
        .byte 13
        .text "        .text ""8210"""
        .byte 13
        .text "        .byte 0"
        .byte 13
        .text "+       .word 0"
        .byte 13, 13
        .text "        * = $2012"
        .byte 13
        .text "start:"
        .byte 13
        .text "        jsr varinit"
        .byte 13
        .text "        jsr datainit"
        .byte 13
        .byte 0

out_comment_load_addr:
        .text "; input prg load address: $"
        .byte 0

out_tail:
        .text "        rts"
        .byte 13
        .byte 13
        .byte 0

out_var_runtime_header:
        .text "; variable heap runtime"
        .byte 13
        .text "; bank-1 variable heap: $12000-$1f7ff"
        .byte 13
        .text "; descriptor size 16 bytes; scalar value starts at descriptor + 8"
        .byte 13
        .text "varheapstart = $2000"
        .byte 13
        .text "varheapend = $"
        .byte 0

out_var_runtime:
        .text "varinit:"
        .byte 13
        .text "        lda #<varheapstart"
        .byte 13
        .text "        sta varptr"
        .byte 13
        .text "        lda #>varheapstart"
        .byte 13
        .text "        sta varptr+1"
        .byte 13
        .text "        lda #$01"
        .byte 13
        .text "        sta varptr+2"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta varptr+3"
        .byte 13
        .text "varinitloop:"
        .byte 13
        .text "        lda varptr+1"
        .byte 13
        .text "        cmp #>varheapend"
        .byte 13
        .text "        bne varinitclear"
        .byte 13
        .text "        lda varptr"
        .byte 13
        .text "        cmp #<varheapend"
        .byte 13
        .text "        beq varinitdone"
        .byte 13
        .text "varinitclear:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        inc varptr"
        .byte 13
        .text "        bne varinitloop"
        .byte 13
        .text "        inc varptr+1"
        .byte 13
        .text "        jmp varinitloop"
        .byte 13
        .text "varinitdone:"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .text "loadintvar:"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        ldz #1"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .text "storeintvar:"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        ldz #1"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .byte 0

out_runtime_math:
        .text "; integer math runtime"
        .byte 13
        .text "mul16:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta resultlo"
        .byte 13
        .text "        sta resulthi"
        .byte 13
        .text "        ldx #16"
        .byte 13
        .text "mul16loop:"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        and #1"
        .byte 13
        .text "        beq mul16skip"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        lda resultlo"
        .byte 13
        .text "        adc lhslo"
        .byte 13
        .text "        sta resultlo"
        .byte 13
        .text "        lda resulthi"
        .byte 13
        .text "        adc lhshi"
        .byte 13
        .text "        sta resulthi"
        .byte 13
        .text "mul16skip:"
        .byte 13
        .text "        asl lhslo"
        .byte 13
        .text "        rol lhshi"
        .byte 13
        .text "        lsr exprhi"
        .byte 13
        .text "        ror exprlo"
        .byte 13
        .text "        dex"
        .byte 13
        .text "        bne mul16loop"
        .byte 13
        .text "        lda resultlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda resulthi"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .text "div16:"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        ora exprhi"
        .byte 13
        .text "        beq div16zero"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta quotlo"
        .byte 13
        .text "        sta quothi"
        .byte 13
        .text "        sta remlo"
        .byte 13
        .text "        sta remhi"
        .byte 13
        .text "        ldx #16"
        .byte 13
        .text "div16loop:"
        .byte 13
        .text "        asl lhslo"
        .byte 13
        .text "        rol lhshi"
        .byte 13
        .text "        rol remlo"
        .byte 13
        .text "        rol remhi"
        .byte 13
        .text "        asl quotlo"
        .byte 13
        .text "        rol quothi"
        .byte 13
        .text "        lda remhi"
        .byte 13
        .text "        cmp exprhi"
        .byte 13
        .text "        bcc div16next"
        .byte 13
        .text "        bne div16sub"
        .byte 13
        .text "        lda remlo"
        .byte 13
        .text "        cmp exprlo"
        .byte 13
        .text "        bcc div16next"
        .byte 13
        .text "div16sub:"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        lda remlo"
        .byte 13
        .text "        sbc exprlo"
        .byte 13
        .text "        sta remlo"
        .byte 13
        .text "        lda remhi"
        .byte 13
        .text "        sbc exprhi"
        .byte 13
        .text "        sta remhi"
        .byte 13
        .text "        inc quotlo"
        .byte 13
        .text "div16next:"
        .byte 13
        .text "        dex"
        .byte 13
        .text "        bne div16loop"
        .byte 13
        .text "        lda quotlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda quothi"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        rts"
        .byte 13
        .text "div16zero:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .byte 0

out_runtime_compare:
        .text "; signed integer comparison runtime"
        .byte 13
        .text "cmple:"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        eor exprhi"
        .byte 13
        .text "        bpl cmplesame"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        bmi cmptrue"
        .byte 13
        .text "        jmp cmpfalse"
        .byte 13
        .text "cmplesame:"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        cmp exprhi"
        .byte 13
        .text "        bcc cmptrue"
        .byte 13
        .text "        bne cmpfalse"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        cmp exprlo"
        .byte 13
        .text "        bcc cmptrue"
        .byte 13
        .text "        beq cmptrue"
        .byte 13
        .text "        jmp cmpfalse"
        .byte 13
        .byte 13
        .text "cmpge:"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        eor exprhi"
        .byte 13
        .text "        bpl cmpgesame"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        bmi cmpfalse"
        .byte 13
        .text "        jmp cmptrue"
        .byte 13
        .text "cmpgesame:"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        cmp exprhi"
        .byte 13
        .text "        bcc cmpfalse"
        .byte 13
        .text "        bne cmptrue"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        cmp exprlo"
        .byte 13
        .text "        bcs cmptrue"
        .byte 13
        .text "        jmp cmpfalse"
        .byte 13
        .byte 13
        .text "cmptrue:"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        rts"
        .byte 13
        .text "cmpfalse:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .byte 0

out_runtime_print:
        .text "; integer print runtime"
        .byte 13
        .text "printch:"
        .byte 13
        .text "        pha"
        .byte 13
        .text "        jsr kernalchrout"
        .byte 13
        .text "        pla"
        .byte 13
        .text "        cmp #$0d"
        .byte 13
        .text "        beq printchcr"
        .byte 13
        .text "        inc printcol"
        .byte 13
        .text "        lda printcol"
        .byte 13
        .text "        cmp #10"
        .byte 13
        .text "        bcc printchdone"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta printcol"
        .byte 13
        .text "printchdone:"
        .byte 13
        .text "        rts"
        .byte 13
        .text "printchcr:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta printcol"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .text "printcomma:"
        .byte 13
        .text "        lda #$20"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda printcol"
        .byte 13
        .text "        bne printcomma"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .text "printuint:"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        bpl printpos"
        .byte 13
        .text "        lda #'-'"
        .byte 13
        .text "        jsr printch"
        .byte 13
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
        .byte 13
        .text "        jmp printdigits"
        .byte 13
        .text "printpos:"
        .byte 13
        .text "        lda #' '"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "printdigits:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta printstarted"
        .byte 13
        .text "        lda #<$2710"
        .byte 13
        .text "        ldy #>$2710"
        .byte 13
        .text "        jsr printdigit"
        .byte 13
        .text "        lda #<$03e8"
        .byte 13
        .text "        ldy #>$03e8"
        .byte 13
        .text "        jsr printdigit"
        .byte 13
        .text "        lda #<$0064"
        .byte 13
        .text "        ldy #>$0064"
        .byte 13
        .text "        jsr printdigit"
        .byte 13
        .text "        lda #<$000a"
        .byte 13
        .text "        ldy #>$000a"
        .byte 13
        .text "        jsr printdigit"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        adc #'0'"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #' '"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .text "printdigit:"
        .byte 13
        .text "        sta divlo"
        .byte 13
        .text "        sty divhi"
        .byte 13
        .text "        lda #'0'"
        .byte 13
        .text "        sta digit"
        .byte 13
        .text "pdloop:"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        cmp divhi"
        .byte 13
        .text "        bcc pddone"
        .byte 13
        .text "        bne pdsub"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        cmp divlo"
        .byte 13
        .text "        bcc pddone"
        .byte 13
        .text "pdsub:"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        sbc divlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sbc divhi"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        inc digit"
        .byte 13
        .text "        jmp pdloop"
        .byte 13
        .text "pddone:"
        .byte 13
        .text "        lda digit"
        .byte 13
        .text "        cmp #'0'"
        .byte 13
        .text "        bne pdemit"
        .byte 13
        .text "        lda printstarted"
        .byte 13
        .text "        beq pdreturn"
        .byte 13
        .text "        lda digit"
        .byte 13
        .text "pdemit:"
        .byte 13
        .text "        sta digit"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        sta printstarted"
        .byte 13
        .text "        lda digit"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "pdreturn:"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .byte 0

out_runtime_data:
        .text "; data/read runtime"
        .byte 13
        .text "datainit:"
        .byte 13
        .text "        lda #<datastart"
        .byte 13
        .text "        sta dataptrlo"
        .byte 13
        .text "        lda #>datastart"
        .byte 13
        .text "        sta dataptrhi"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .text "readint:"
        .byte 13
        .text "        lda dataptrhi"
        .byte 13
        .text "        cmp #>dataend"
        .byte 13
        .text "        bne readintok"
        .byte 13
        .text "        lda dataptrlo"
        .byte 13
        .text "        cmp #<dataend"
        .byte 13
        .text "        bne readintok"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        jmp outofdata"
        .byte 13
        .text "readintok:"
        .byte 13
        .text "        lda dataptrlo"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda dataptrhi"
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
        .byte 13
        .text "        clc"
        .byte 13
        .text "        lda dataptrlo"
        .byte 13
        .text "        adc #2"
        .byte 13
        .text "        sta dataptrlo"
        .byte 13
        .text "        lda dataptrhi"
        .byte 13
        .text "        adc #0"
        .byte 13
        .text "        sta dataptrhi"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .text "outofdata:"
        .byte 13
        .text "        lda #$4f"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$55"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$54"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$20"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$4f"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$46"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$20"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$44"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$41"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$54"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$41"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$0d"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        rts"
        .byte 13
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
out_data_table_end:
        .text "dataend:"
        .byte 13
        .byte 13
        .byte 0

out_for_storage_header:
        .text "; for/next runtime storage"
        .byte 13, 0

out_for_word_storage:
        .text ":       .byte 0,0"
        .byte 13, 0

out_runtime_storage:
        .text "; integer runtime storage"
        .byte 13
        .text "exprlo:       .byte 0"
        .byte 13
        .text "exprhi:       .byte 0"
        .byte 13
        .text "lhslo:        .byte 0"
        .byte 13
        .text "lhshi:        .byte 0"
        .byte 13
        .text "resultlo:     .byte 0"
        .byte 13
        .text "resulthi:     .byte 0"
        .byte 13
        .text "quotlo:       .byte 0"
        .byte 13
        .text "quothi:       .byte 0"
        .byte 13
        .text "remlo:        .byte 0"
        .byte 13
        .text "remhi:        .byte 0"
        .byte 13
        .text "divlo:        .byte 0"
        .byte 13
        .text "divhi:        .byte 0"
        .byte 13
        .text "digit:        .byte 0"
        .byte 13
        .text "printstarted: .byte 0"
        .byte 13
        .text "printcol:     .byte 0"
        .byte 13
        .text "arrptrlo:     .byte 0"
        .byte 13
        .text "arrptrhi:     .byte 0"
        .byte 13
        .text "dataptrlo:    .byte 0"
        .byte 13
        .text "dataptrhi:    .byte 0"
        .byte 13
        .byte 0

out_runtime_array_bounds:
        .text "arraybounds:"
        .byte 13
        .text "        lda #$41"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$52"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$52"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$41"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$59"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$20"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$42"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$4f"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$55"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$4e"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$44"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$53"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$0d"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .byte 0

out_lda_imm_hex:
        .text "        lda #$"
        .byte 0
out_adc_imm_hex:
        .text "        adc #$"
        .byte 0
out_jsr_chout:
        .text "        jsr printch"
        .byte 13, 0
out_jsr_printuint:
        .text "        jsr printuint"
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
out_jsr_readint:
        .text "        jsr readint"
        .byte 13, 0
out_jsr_datainit:
        .text "        jsr datainit"
        .byte 13, 0
out_jsr_cmple:
        .text "        jsr cmple"
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
out_lda_exprlo:
        .text "        lda exprlo"
        .byte 13, 0
out_lda_exprhi:
        .text "        lda exprhi"
        .byte 13, 0
out_array_check_start:
        .text "        lda exprhi"
        .byte 13
        .text "        bmi arraybounds"
        .byte 13
        .text "        cmp #$"
        .byte 0
out_bne_arraybounds:
        .text "        bne arraybounds"
        .byte 13, 0
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
out_var_prefix:
        .text "var"
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
out_iftrue_prefix:
        .text "iftrue"
        .byte 0
out_ifskip_prefix:
        .text "ifskip"
        .byte 0
out_ifend_prefix:
        .text "ifend"
        .byte 0
out_iftmp_prefix:
        .text "iftmp"
        .byte 0
out_arrayok_prefix:
        .text "arrayok"
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
out_poke_expr_to_rtptr:
        .text "        lda exprlo"
        .byte 13
        .text "        ldy #0"
        .byte 13
        .text "        sta (rtptr),y"
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
out_rem:
        .text "        ; rem"
        .byte 0
out_data_comment:
        .text "        ; data skipped"
        .byte 13, 0
out_dim_comment:
        .text "        ; dim allocated in variable heap"
        .byte 13, 0
out_unsupported_token:
        .text "        ; unsupported token $"
        .byte 0
out_unsupported_statement:
        .text "        ; unsupported statement"
        .byte 13, 0
out_unsupported_print:
        .text "        ; unsupported print expression"
        .byte 13, 0
out_unsupported_go:
        .text "        ; unsupported go subtoken $"
        .byte 0
out_bad_goto:
        .text "        ; bad goto target"
        .byte 13, 0
out_bad_gosub:
        .text "        ; bad gosub target"
        .byte 13, 0
out_bad_sys:
        .text "        ; bad sys address"
        .byte 13, 0
out_bad_poke:
        .text "        ; bad poke"
        .byte 13, 0
out_bad_read:
        .text "        ; bad read"
        .byte 13, 0
out_bad_assignment:
        .text "        ; bad integer assignment"
        .byte 13, 0
out_bad_if:
        .text "        ; bad if statement"
        .byte 13, 0
out_bad_for:
        .text "        ; bad for statement"
        .byte 13, 0
out_bad_next:
        .text "        ; bad next statement"
        .byte 13, 0
out_line_overflow:
        .text "        ; line exceeded compiler buffer"
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
line_overflow:
        .byte 0
compile_error:
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
array_ok_lo:
        .byte 0
array_ok_hi:
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
for_sp:
        .byte 0
for_storage_idx:
        .byte 0
data_count:
        .byte 0
data_emit_idx:
        .byte 0
data_sign:
        .byte 0
current_for_id:
        .byte 0
current_for_var_data_lo:
        .byte 0
current_for_var_data_hi:
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

line_buf:
        .fill LINE_BUF_MAX, 0
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

        .cerror * >= $C000, "compiler image is too large for the current bank-0 layout"
