; =============================================================================
; str/interp/escape_seq.asm
; ANSI/VT100 terminal escape sequence generation and stripping.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   convert/int.asm  (str_u64_to_str)
;
; -----------------------------------------------------------------------------
; ANSI escape sequences: ESC [ params m  (CSI = Control Sequence Introducer)
;
; Color codes:
;   30-37  = foreground colors (black red green yellow blue magenta cyan white)
;   40-47  = background colors
;   90-97  = bright foreground
;   100-107 = bright background
;
; Attribute codes:
;   0  = reset all
;   1  = bold
;   2  = dim
;   3  = italic
;   4  = underline
;   5  = blink
;   7  = reverse
;   8  = hidden
;   9  = strikethrough
;
; Functions:
;   str_ansi_color        — write \033[Nm color code
;   str_ansi_rgb          — write \033[38;2;R;G;Bm true-color code
;   str_ansi_reset        — write \033[0m
;   str_ansi_strip        — remove all ANSI sequences from a string
;   str_ansi_visible_len  — length of string excluding ANSI sequences
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_u64_to_str

; ANSI color constants
ANSI_RESET          equ 0
ANSI_BOLD           equ 1
ANSI_DIM            equ 2
ANSI_ITALIC         equ 3
ANSI_UNDERLINE      equ 4
ANSI_BLINK          equ 5
ANSI_REVERSE        equ 7
ANSI_HIDDEN         equ 8
ANSI_STRIKE         equ 9

ANSI_FG_BLACK       equ 30
ANSI_FG_RED         equ 31
ANSI_FG_GREEN       equ 32
ANSI_FG_YELLOW      equ 33
ANSI_FG_BLUE        equ 34
ANSI_FG_MAGENTA     equ 35
ANSI_FG_CYAN        equ 36
ANSI_FG_WHITE       equ 37

ANSI_BG_BLACK       equ 40
ANSI_BG_RED         equ 41
ANSI_BG_GREEN       equ 42
ANSI_BG_YELLOW      equ 43
ANSI_BG_BLUE        equ 44
ANSI_BG_MAGENTA     equ 45
ANSI_BG_CYAN        equ 46
ANSI_BG_WHITE       equ 47

ANSI_FG_BR_BLACK    equ 90
ANSI_FG_BR_RED      equ 91
ANSI_FG_BR_GREEN    equ 92
ANSI_FG_BR_YELLOW   equ 93
ANSI_FG_BR_BLUE     equ 94
ANSI_FG_BR_MAGENTA  equ 95
ANSI_FG_BR_CYAN     equ 96
ANSI_FG_BR_WHITE    equ 97

ESC                 equ 0x1B

section .text

; -----------------------------------------------------------------------------
; str_ansi_color
;
; Write an ANSI color/attribute escape sequence: \033[Nm
;
; Signature:
;   int64_t str_ansi_color(uint64_t code, uint8_t *dst,
;                           uint64_t dst_cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — ANSI code (0-107)
;   RSI  — destination buffer
;   RDX  — capacity (need at least 7: \033[NNNm)
;   RCX  — out_len
; -----------------------------------------------------------------------------

STR_FUNC str_ansi_color

    guard_null rsi, STR_ERR_NULL

    cmp     rdx, 7
    jb      .ac_too_small

    push_regs rbx, r12, r13

    mov     rbx, rdi            ; code
    mov     r12, rsi            ; dst
    mov     r13, rcx            ; out_len

    ; write ESC [
    mov     byte [r12 + 0], ESC
    mov     byte [r12 + 1], '['

    ; format code number
    mov     rdi, rbx
    lea     rsi, [r12 + 2]
    mov     rdx, 4
    sub     rsp, 8
    and     rsp, -8
    mov     rcx, rsp
    call    str_u64_to_str
    mov     r9, [rsp]           ; digits written
    add     rsp, 8

    ; write 'm'
    mov     rax, r9
    add     rax, 2
    mov     byte [r12 + rax], 'm'
    inc     rax

    test    r13, r13
    jz      .ac_ok
    mov     [r13], rax

.ac_ok:
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ac_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_ansi_color

; -----------------------------------------------------------------------------
; str_ansi_reset
;
; Write \033[0m reset sequence.
;
; Signature:
;   int64_t str_ansi_reset(uint8_t *dst, uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_ansi_reset

    guard_null rdi, STR_ERR_NULL

    cmp     rsi, 4
    jb      .ar_too_small

    mov     byte [rdi + 0], ESC
    mov     byte [rdi + 1], '['
    mov     byte [rdi + 2], '0'
    mov     byte [rdi + 3], 'm'

    test    rdx, rdx
    jz      .ar_ok
    mov     qword [rdx], 4

.ar_ok:
    xor     eax, eax
    pop     rbp
    ret

.ar_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_ansi_reset

; -----------------------------------------------------------------------------
; str_ansi_rgb
;
; Write true-color RGB escape: \033[38;2;R;G;Bm (foreground)
; or \033[48;2;R;G;Bm (background)
;
; Signature:
;   int64_t str_ansi_rgb(uint8_t r, uint8_t g, uint8_t b, uint8_t bg,
;                         uint8_t *dst, uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   DIL  — red (0-255)
;   SIL  — green (0-255)
;   DL   — blue (0-255)
;   CL   — 0=foreground, 1=background
;   R8   — destination buffer
;   R9   — capacity
;   [rsp+8] — out_len
; -----------------------------------------------------------------------------

STR_FUNC str_ansi_rgb

    guard_null r8, STR_ERR_NULL

    cmp     r9, 20              ; worst case: \033[48;2;255;255;255m = 20 bytes
    jb      .argb_too_small

    push_regs rbx, r12, r13, r14, r15

    movzx   rbx, dil            ; r
    movzx   r12, sil            ; g
    movzx   r13, dl             ; b
    movzx   r14d, cl            ; bg flag
    mov     r15, r8             ; dst
    push    r9                  ; cap
    push    qword [rsp + 56]    ; out_len

    xor     r9, r9              ; write offset

    mov     byte [r15 + r9], ESC
    inc     r9
    mov     byte [r15 + r9], '['
    inc     r9

    ; "38;" or "48;"
    test    r14d, r14d
    jz      .argb_fg
    mov     byte [r15 + r9], '4'
    jmp     .argb_prefix
.argb_fg:
    mov     byte [r15 + r9], '3'
.argb_prefix:
    inc     r9
    mov     byte [r15 + r9], '8'
    inc     r9
    mov     byte [r15 + r9], ';'
    inc     r9
    mov     byte [r15 + r9], '2'
    inc     r9
    mov     byte [r15 + r9], ';'
    inc     r9

    ; write R;G;B values
    %macro WRITE_COMPONENT 1    ; %1 = value register
        mov     rdi, %1
        lea     rsi, [r15 + r9]
        mov     rdx, 4
        sub     rsp, 8
        and     rsp, -8
        mov     rcx, rsp
        push    r9
        call    str_u64_to_str
        mov     r8, [rsp]
        add     rsp, 8
        pop     r9
        add     r9, r8
        mov     byte [r15 + r9], ';'
        inc     r9
    %endmacro

    WRITE_COMPONENT rbx
    WRITE_COMPONENT r12
    ; blue: no trailing ';'
    mov     rdi, r13
    lea     rsi, [r15 + r9]
    mov     rdx, 4
    sub     rsp, 8
    and     rsp, -8
    mov     rcx, rsp
    push    r9
    call    str_u64_to_str
    mov     r8, [rsp]
    add     rsp, 8
    pop     r9
    add     r9, r8

    mov     byte [r15 + r9], 'm'
    inc     r9

    pop     rcx                 ; out_len
    pop     r8                  ; cap (discard)

    test    rcx, rcx
    jz      .argb_ok
    mov     [rcx], r9

.argb_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.argb_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_ansi_rgb

; -----------------------------------------------------------------------------
; str_ansi_strip
;
; Remove all ANSI escape sequences from a string.
; ESC [ ... m sequences are stripped completely.
;
; Signature:
;   int64_t str_ansi_strip(const StrSlice *src, uint8_t *dst,
;                           uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_ansi_strip

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx

    xor     r9, r9
    xor     r10, r10

.as_loop:
    cmp     r9, r12
    jae     .as_done

    movzx   eax, byte [rbx + r9]

    cmp     al, ESC
    je      .as_escape

    cmp     r10, r14
    jae     .as_overflow
    mov     [r13 + r10], al
    inc     r9
    inc     r10
    jmp     .as_loop

.as_escape:
    inc     r9
    cmp     r9, r12
    jae     .as_loop

    movzx   eax, byte [rbx + r9]

    cmp     al, '['             ; CSI
    je      .as_csi
    cmp     al, 'c'             ; reset
    je      .as_skip_one
    ; ESC + other char: skip both
    inc     r9
    jmp     .as_loop

.as_skip_one:
    inc     r9
    jmp     .as_loop

.as_csi:
    inc     r9
    ; skip until final byte (0x40-0x7E)

.as_csi_scan:
    cmp     r9, r12
    jae     .as_done

    movzx   eax, byte [rbx + r9]
    inc     r9

    cmp     al, 0x40
    jb      .as_csi_scan        ; parameter/intermediate byte
    cmp     al, 0x7E
    jbe     .as_loop            ; final byte — done with escape

    jmp     .as_csi_scan

.as_done:
    test    r15, r15
    jz      .as_ok
    mov     [r15], r10

.as_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.as_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_ansi_strip

; -----------------------------------------------------------------------------
; str_ansi_visible_len
;
; Return the visible length (in bytes) of a string excluding ANSI sequences.
;
; Signature:
;   uint64_t str_ansi_visible_len(const StrSlice *src)
; -----------------------------------------------------------------------------

STR_FUNC str_ansi_visible_len

    test    rdi, rdi
    jz      .avl_zero

    push_regs rbx, r12

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]

    xor     r9, r9              ; index
    xor     r10, r10            ; visible count

.avl_loop:
    cmp     r9, r12
    jae     .avl_done

    movzx   eax, byte [rbx + r9]

    cmp     al, ESC
    je      .avl_esc

    inc     r9
    inc     r10
    jmp     .avl_loop

.avl_esc:
    inc     r9
    cmp     r9, r12
    jae     .avl_done

    movzx   eax, byte [rbx + r9]
    cmp     al, '['
    je      .avl_csi

    inc     r9
    jmp     .avl_loop

.avl_csi:
    inc     r9

.avl_csi_scan:
    cmp     r9, r12
    jae     .avl_done
    movzx   eax, byte [rbx + r9]
    inc     r9
    cmp     al, 0x40
    jb      .avl_csi_scan
    cmp     al, 0x7E
    jbe     .avl_loop
    jmp     .avl_csi_scan

.avl_done:
    mov     rax, r10
    pop_regs r12, rbx
    pop     rbp
    ret

.avl_zero:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_ansi_visible_len