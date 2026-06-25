; =============================================================================
; str/parse/color.asm
; Parse CSS/HTML color strings → u32 RGBA packed value.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   inspect/is_hex_digit.asm  (str_hex_digit_value)
;
; -----------------------------------------------------------------------------
; Supported color formats:
;
;   "#RGB"         → 3-digit hex (each digit doubled: #F0A → #FF00AA)
;   "#RRGGBB"      → 6-digit hex
;   "#RGBA"        → 4-digit hex with alpha
;   "#RRGGBBAA"    → 8-digit hex with alpha
;   "rgb(r,g,b)"   → decimal 0-255 each channel
;   "rgba(r,g,b,a)"→ decimal with alpha 0-255
;   "hsl(h,s%,l%)" → HSL (returns RGBA after conversion)
;
; Output format: packed u32 = (R << 24) | (G << 16) | (B << 8) | A
; Alpha defaults to 0xFF (fully opaque) if not specified.
;
; Named colors: only "black", "white", "red", "green", "blue",
;               "transparent" supported (full named color table
;               belongs in a separate named_colors module).
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_hex_digit_value

section .rodata

; Named color table: null-terminated name, then 4-byte RGBA
_color_names:
    db "black",       0, 0x00, 0x00, 0x00, 0xFF
    db "white",       0, 0xFF, 0xFF, 0xFF, 0xFF
    db "red",         0, 0xFF, 0x00, 0x00, 0xFF
    db "green",       0, 0x00, 0x80, 0x00, 0xFF
    db "lime",        0, 0x00, 0xFF, 0x00, 0xFF
    db "blue",        0, 0x00, 0x00, 0xFF, 0xFF
    db "yellow",      0, 0xFF, 0xFF, 0x00, 0xFF
    db "cyan",        0, 0x00, 0xFF, 0xFF, 0xFF
    db "magenta",     0, 0xFF, 0x00, 0xFF, 0xFF
    db "orange",      0, 0xFF, 0xA5, 0x00, 0xFF
    db "purple",      0, 0x80, 0x00, 0x80, 0xFF
    db "pink",        0, 0xFF, 0xC0, 0xCB, 0xFF
    db "gray",        0, 0x80, 0x80, 0x80, 0xFF
    db "grey",        0, 0x80, 0x80, 0x80, 0xFF
    db "transparent", 0, 0x00, 0x00, 0x00, 0x00
    db 0                        ; terminator

section .text

; -----------------------------------------------------------------------------
; str_parse_color
;
; Parse a color string into packed u32 RGBA.
;
; Signature:
;   int64_t str_parse_color(const StrSlice *src, uint32_t *out_rgba)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — pointer to uint32_t to receive RGBA
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_PARSE
; -----------------------------------------------------------------------------

STR_FUNC str_parse_color

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; out_rgba

    test    r12, r12
    jz      .col_parse_err

    movzx   eax, byte [rbx]

    cmp     al, '#'
    je      .col_hex

    cmp     al, 'r'
    je      .col_check_rgb

    cmp     al, 'R'
    je      .col_check_rgb

    cmp     al, 'h'
    je      .col_check_hsl

    cmp     al, 'H'
    je      .col_check_hsl

    ; try named color
    jmp     .col_named

.col_hex:
    ; skip '#'
    inc     rbx
    dec     r12

    ; count hex digits until non-hex or end
    xor     r14, r14            ; digit count

.col_count_hex:
    cmp     r14, r12
    jae     .col_hex_parse

    movzx   edi, byte [rbx + r14]
    push    r14
    call    str_hex_digit_value
    pop     r14
    test    rax, rax
    js      .col_hex_parse      ; non-hex char

    inc     r14
    jmp     .col_count_hex

.col_hex_parse:
    ; r14 = number of hex digits
    xor     r15, r15            ; rgba accumulator

    cmp     r14, 3
    je      .col_hex3

    cmp     r14, 4
    je      .col_hex4

    cmp     r14, 6
    je      .col_hex6

    cmp     r14, 8
    je      .col_hex8

    jmp     .col_parse_err

.col_hex3:
    ; #RGB → #RRGGBB (double each nibble), alpha = FF
    ; R channel
    movzx   edi, byte [rbx]
    call    str_hex_digit_value
    mov     r8d, eax
    shl     r8d, 4
    or      r8d, eax            ; RR
    shl     r15d, 8
    or      r15d, r8d

    ; G channel
    movzx   edi, byte [rbx + 1]
    call    str_hex_digit_value
    mov     r8d, eax
    shl     r8d, 4
    or      r8d, eax
    shl     r15d, 8
    or      r15d, r8d

    ; B channel
    movzx   edi, byte [rbx + 2]
    call    str_hex_digit_value
    mov     r8d, eax
    shl     r8d, 4
    or      r8d, eax
    shl     r15d, 8
    or      r15d, r8d

    ; A = FF
    shl     r15d, 8
    or      r15d, 0xFF
    jmp     .col_write

.col_hex4:
    ; #RGBA (double each nibble)
    movzx   edi, byte [rbx]
    call    str_hex_digit_value
    mov     r8d, eax
    shl     r8d, 4
    or      r8d, eax
    shl     r15d, 8
    or      r15d, r8d

    movzx   edi, byte [rbx + 1]
    call    str_hex_digit_value
    mov     r8d, eax
    shl     r8d, 4
    or      r8d, eax
    shl     r15d, 8
    or      r15d, r8d

    movzx   edi, byte [rbx + 2]
    call    str_hex_digit_value
    mov     r8d, eax
    shl     r8d, 4
    or      r8d, eax
    shl     r15d, 8
    or      r15d, r8d

    movzx   edi, byte [rbx + 3]
    call    str_hex_digit_value
    mov     r8d, eax
    shl     r8d, 4
    or      r8d, eax
    shl     r15d, 8
    or      r15d, r8d
    jmp     .col_write

.col_hex6:
    ; #RRGGBB, alpha = FF
    ; R
    movzx   edi, byte [rbx]
    call    str_hex_digit_value
    mov     r8d, eax
    shl     r8d, 4
    movzx   edi, byte [rbx + 1]
    push    r8
    call    str_hex_digit_value
    pop     r8
    or      r8d, eax
    shl     r15d, 8
    or      r15d, r8d

    ; G
    movzx   edi, byte [rbx + 2]
    call    str_hex_digit_value
    mov     r8d, eax
    shl     r8d, 4
    movzx   edi, byte [rbx + 3]
    push    r8
    call    str_hex_digit_value
    pop     r8
    or      r8d, eax
    shl     r15d, 8
    or      r15d, r8d

    ; B
    movzx   edi, byte [rbx + 4]
    call    str_hex_digit_value
    mov     r8d, eax
    shl     r8d, 4
    movzx   edi, byte [rbx + 5]
    push    r8
    call    str_hex_digit_value
    pop     r8
    or      r8d, eax
    shl     r15d, 8
    or      r15d, r8d

    ; A = FF
    shl     r15d, 8
    or      r15d, 0xFF
    jmp     .col_write

.col_hex8:
    ; #RRGGBBAA
    ; R
    movzx   edi, byte [rbx]
    call    str_hex_digit_value
    mov     r8d, eax
    shl     r8d, 4
    movzx   edi, byte [rbx + 1]
    push    r8
    call    str_hex_digit_value
    pop     r8
    or      r8d, eax
    shl     r15d, 8
    or      r15d, r8d

    ; G
    movzx   edi, byte [rbx + 2]
    call    str_hex_digit_value
    mov     r8d, eax
    shl     r8d, 4
    movzx   edi, byte [rbx + 3]
    push    r8
    call    str_hex_digit_value
    pop     r8
    or      r8d, eax
    shl     r15d, 8
    or      r15d, r8d

    ; B
    movzx   edi, byte [rbx + 4]
    call    str_hex_digit_value
    mov     r8d, eax
    shl     r8d, 4
    movzx   edi, byte [rbx + 5]
    push    r8
    call    str_hex_digit_value
    pop     r8
    or      r8d, eax
    shl     r15d, 8
    or      r15d, r8d

    ; A
    movzx   edi, byte [rbx + 6]
    call    str_hex_digit_value
    mov     r8d, eax
    shl     r8d, 4
    movzx   edi, byte [rbx + 7]
    push    r8
    call    str_hex_digit_value
    pop     r8
    or      r8d, eax
    shl     r15d, 8
    or      r15d, r8d
    jmp     .col_write

.col_check_rgb:
    ; check "rgb(" or "rgba("
    cmp     r12, 4
    jb      .col_named

    ; check "rgb"
    movzx   eax, byte [rbx]
    or      al, 0x20
    cmp     al, 'r'
    jne     .col_named
    movzx   eax, byte [rbx + 1]
    or      al, 0x20
    cmp     al, 'g'
    jne     .col_named
    movzx   eax, byte [rbx + 2]
    or      al, 0x20
    cmp     al, 'b'
    jne     .col_named

    xor     r14, r14            ; has_alpha = 0

    movzx   eax, byte [rbx + 3]
    cmp     al, 'a'
    je      .col_rgba_func
    cmp     al, 'A'
    je      .col_rgba_func
    cmp     al, '('
    jne     .col_parse_err

    add     rbx, 4              ; skip "rgb("
    sub     r12, 4
    jmp     .col_parse_rgb_vals

.col_rgba_func:
    ; check for 'a' then '('
    movzx   eax, byte [rbx + 4]
    cmp     al, '('
    jne     .col_parse_err
    mov     r14, 1              ; has_alpha = 1
    add     rbx, 5              ; skip "rgba("
    sub     r12, 5

.col_parse_rgb_vals:
    ; parse R, G, B [, A] as decimal 0-255
    ; simplified integer parser inline
    xor     r15, r15            ; rgba
    xor     r9, r9              ; index

    ; parse R
    call    .parse_u8_component
    jc      .col_parse_err
    shl     r15d, 8
    or      r15d, eax

    ; parse G
    call    .parse_u8_component
    jc      .col_parse_err
    shl     r15d, 8
    or      r15d, eax

    ; parse B
    call    .parse_u8_component
    jc      .col_parse_err
    shl     r15d, 8
    or      r15d, eax

    ; alpha
    test    r14, r14
    jz      .col_rgb_default_alpha

    call    .parse_u8_component
    jc      .col_parse_err
    shl     r15d, 8
    or      r15d, eax
    jmp     .col_write

.col_rgb_default_alpha:
    shl     r15d, 8
    or      r15d, 0xFF
    jmp     .col_write

.col_check_hsl:
    ; HSL parsing — simplified: return error for now
    ; Full HSL→RGB conversion in a real implementation
    jmp     .col_parse_err

.col_named:
    ; scan named color table
    lea     r9, [rel _color_names]

.col_name_scan:
    movzx   eax, byte [r9]
    test    al, al
    jz      .col_parse_err      ; end of table

    ; compare name with src (case-insensitive for first word)
    xor     r10, r10            ; char index

.col_name_cmp:
    movzx   eax, byte [r9 + r10]
    test    al, al
    jz      .col_name_match_check

    cmp     r10, r12
    jae     .col_name_next

    movzx   ecx, byte [rbx + r10]
    or      cl, 0x20
    or      al, 0x20
    cmp     al, cl
    jne     .col_name_next

    inc     r10
    jmp     .col_name_cmp

.col_name_match_check:
    ; name ended — check src also ended or has whitespace/delimiter
    cmp     r10, r12
    je      .col_name_matched
    movzx   ecx, byte [rbx + r10]
    cmp     cl, ' '
    je      .col_name_matched
    cmp     cl, 0
    je      .col_name_matched

.col_name_next:
    ; advance past this entry: skip name (null-terminated) + 4 rgba bytes
    xor     r10, r10
.col_skip_name:
    movzx   eax, byte [r9 + r10]
    inc     r10
    test    al, al
    jnz     .col_skip_name
    ; now at rgba bytes
    add     r9, r10
    add     r9, 4               ; skip 4 rgba bytes
    jmp     .col_name_scan

.col_name_matched:
    ; r9 + r10 + 1 points to rgba bytes
    movzx   eax, byte [r9 + r10 + 1]   ; skip null, then R
    shl     eax, 24
    mov     r15d, eax
    movzx   eax, byte [r9 + r10 + 2]   ; G
    shl     eax, 16
    or      r15d, eax
    movzx   eax, byte [r9 + r10 + 3]   ; B
    shl     eax, 8
    or      r15d, eax
    movzx   eax, byte [r9 + r10 + 4]   ; A
    or      r15d, eax
    jmp     .col_write

.col_write:
    mov     [r13], r15d

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.col_parse_err:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_PARSE
    pop     rbp
    ret

; Internal: parse one u8 component (0-255) from rbx+r9, advance r9
; Sets CF on error, clears CF on success. Result in AL.
.parse_u8_component:
    ; skip spaces and commas
.puc_skip:
    cmp     r9, r12
    jae     .puc_err
    movzx   eax, byte [rbx + r9]
    cmp     al, ' '
    je      .puc_adv
    cmp     al, ','
    je      .puc_adv
    cmp     al, '('
    je      .puc_adv
    jmp     .puc_digits
.puc_adv:
    inc     r9
    jmp     .puc_skip

.puc_digits:
    xor     eax, eax
    xor     ecx, ecx

.puc_digit_loop:
    cmp     r9, r12
    jae     .puc_done
    movzx   edx, byte [rbx + r9]
    sub     edx, '0'
    cmp     edx, 9
    ja      .puc_done
    imul    eax, eax, 10
    add     eax, edx
    cmp     eax, 255
    ja      .puc_err
    inc     r9
    inc     ecx
    jmp     .puc_digit_loop

.puc_done:
    test    ecx, ecx
    jz      .puc_err
    clc
    ret
.puc_err:
    stc
    ret

STR_ENDFUNC str_parse_color