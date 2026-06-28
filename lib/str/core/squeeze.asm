; =============================================================================
; str/core/squeeze.asm
; Whitespace and character squeezing functions.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; Helper to check if a byte is ASCII whitespace: space, tab, LF, CR
_is_ascii_whitespace:
    cmp     dil, 0x20           ; space
    je      .yes
    cmp     dil, 0x09           ; tab
    je      .yes
    cmp     dil, 0x0A           ; LF
    je      .yes
    cmp     dil, 0x0D           ; CR
    je      .yes
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; -----------------------------------------------------------------------------
; str_squeeze_whitespace
;
; Collapse consecutive ASCII whitespace characters to a single space,
; and trim leading/trailing whitespace.
;
; Signature:
;   int64_t str_squeeze_whitespace(const StrSlice *src, uint8_t *dst,
;                                  uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — dst (uint8_t*)
;   RDX  — cap (uint64_t)
;   RCX  — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_squeeze_whitespace
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]   ; src.ptr
    mov     r12, [rdi + StrSlice.len]   ; src.len
    mov     r13, rsi                    ; dst
    mov     r14, rdx                    ; cap
    mov     r15, rcx                    ; out_len

    ; check if empty
    test    r12, r12
    jz      .empty_output

    ; 1. Trim leading whitespace
    xor     rcx, rcx                    ; leading offset
.lead_loop:
    cmp     rcx, r12
    je      .empty_output

    movzx   edi, byte [rbx + rcx]
    call    _is_ascii_whitespace
    test    rax, rax
    jz      .lead_done
    inc     rcx
    jmp     .lead_loop

.lead_done:
    ; rcx = leading trimmed offset

    ; 2. Trim trailing whitespace
    mov     rdx, r12                    ; trailing offset (starts at len)
.trail_loop:
    cmp     rdx, rcx
    je      .empty_output

    movzx   edi, byte [rbx + rdx - 1]
    call    _is_ascii_whitespace
    test    rax, rax
    jz      .trail_done
    dec     rdx
    jmp     .trail_loop

.trail_done:
    ; Trimmed range: [rbx + rcx .. rbx + rdx)
    ; Output offset = 0
    xor     r8, r8                      ; dst_offset = 0
    xor     r9, r9                      ; in_ws_run = 0

.squeeze_loop:
    cmp     rcx, rdx
    je      .done

    movzx   r10d, byte [rbx + rcx]
    mov     edi, r10d
    push    rcx
    push    rdx
    call    _is_ascii_whitespace
    pop     rdx
    pop     rcx

    test    rax, rax
    jz      .non_ws

    ; It is whitespace
    test    r9, r9
    jnz     .skip_char                  ; if already in ws run, skip

    ; Collapse run to single space
    cmp     r8, r14
    jae     .too_small
    mov     byte [r13 + r8], 0x20
    inc     r8
    mov     r9, 1                       ; in_ws_run = 1
    jmp     .char_processed

.non_ws:
    cmp     r8, r14
    jae     .too_small
    mov     byte [r13 + r8], r10b
    inc     r8
    xor     r9, r9                      ; in_ws_run = 0

.char_processed:
.skip_char:
    inc     rcx
    jmp     .squeeze_loop

.done:
    mov     [r15], r8                   ; write out_len
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.empty_output:
    mov     qword [r15], 0
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_squeeze_whitespace

; -----------------------------------------------------------------------------
; str_squeeze_char
;
; Collapse consecutive occurrences of `ch` to a single occurrence.
;
; Signature:
;   int64_t str_squeeze_char(const StrSlice *src, uint8_t ch, uint8_t *dst,
;                            uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — ch (uint8_t)
;   RDX  — dst (uint8_t*)
;   RCX  — cap (uint64_t)
;   R8   — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_squeeze_char
    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rdx                    ; dst
    mov     r14, rcx                    ; cap
    mov     r15, r8                     ; out_len

    xor     r10, r10                    ; dst_offset = 0
    xor     r11, r11                    ; in_run = 0
    xor     rcx, rcx                    ; src_offset = 0

.loop:
    cmp     rcx, r12
    je      .done

    movzx   eax, byte [rbx + rcx]
    cmp     al, sil                     ; is it equal to ch?
    jne     .non_match

    ; matched char
    test    r11, r11
    jnz     .skip_char                  ; if in run, skip

    cmp     r10, r14
    jae     .too_small
    mov     [r13 + r10], al
    inc     r10
    mov     r11, 1                      ; in_run = 1
    jmp     .char_processed

.non_match:
    cmp     r10, r14
    jae     .too_small
    mov     [r13 + r10], al
    inc     r10
    xor     r11, r11                    ; in_run = 0

.char_processed:
.skip_char:
    inc     rcx
    jmp     .loop

.done:
    mov     [r15], r10
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_squeeze_char
