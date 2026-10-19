; ============================================================================
; Huffman — Canonical Huffman Decoder (LSB-first codes, deflate order)
; Tables built from code-length arrays; decode walks lengths 1..15
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

; struct offsets (hoisted above use)
%define HuffDec_SIZE    304

section .text

; HuffDec struct layout (manual offsets to avoid NASM preprocessor issues)
; Offsets defined in inc/struct_offsets.inc

; ------------------
; ---------------------------------------------------------------------------
; huff_build
;   IN: rdi = HuffDec*, rsi = lengths[n], rdx = n (<=288)
; ---------------------------------------------------------------------------
global huff_build
huff_build:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    cmp r13, 288
    ja .fail
    ; zero counts
    mov rdi, rbx
    mov rcx, 16
    xor eax, eax
    rep stosb
    ; count + validate, over-subscribed check
    xor r14d, r14d
    xor ecx, ecx  ; left = 1
    mov ecx, 1
.count:
    cmp r14, r13
    jae .check_done
    movzx eax, byte [r12 + r14]
    cmp eax, 15
    ja .fail
    test eax, eax
    jz .next_c
    inc byte [rbx + rax - 1]
.next_c:
    inc r14
    jmp .count
.check_done:
    ; left = 1; for len 1..15: left <<= 1; left -= counts[len]
    mov ecx, 1
    xor r14d, r14d
.check:
    cmp r14d, 15
    jae .check_ok
    shl ecx, 1
    movzx eax, byte [rbx + r14]
    sub ecx, eax
    js .fail
    inc r14d
    jmp .check
.check_ok:
    test ecx, ecx
    jnz .fail  ; incomplete (except single-symbol edge handled by caller)
    ; place symbols grouped by length (stable)
    mov rdi, rbx
    add rdi, 16
    xor r14d, r14d  ; out index
    mov r9d, 1      ; len
.len_loop:
    cmp r9d, 15
    ja .done
    xor r10d, r10d  ; sym index
.sym_loop:
    cmp r10, r13
    jae .next_len
    movzx eax, byte [r12 + r10]
    cmp eax, r9d
    jne .next_sym
    mov [rdi + r14], r10b
    inc r14d
.next_sym:
    inc r10d
    jmp .sym_loop
.next_len:
    inc r9d
    jmp .len_loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.fail:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; huff_decode
;   IN: rdi=HuffDec*, rsi=bitstate* {buf:u64 @0, nbits @8, src @16, remain @24}
;   OUT: rax = symbol
; ---------------------------------------------------------------------------
global huff_decode
huff_decode:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    xor r13d, r13d  ; code
    xor r14d, r14d  ; first
    xor r15d, r15d  ; index
    mov r9d, 1      ; len
.len:
    cmp r9d, 15
    ja .fail
    ; ensure 1 bit
    mov rax, [r12 + 8]
    test rax, rax
    jz .refill
.have:
    mov rax, [r12 + 0]
    and eax, 1
    shr qword [r12 + 0], 1
    dec qword [r12 + 8]
    or r13d, eax
    movzx eax, byte [rbx + r9 - 1]  ; count
    mov edx, r13d
    sub edx, r14d
    cmp edx, eax
    jb .found
    add r15d, eax
    add r14d, eax
    shl r14d, 1
    shl r13d, 1
    inc r9d
    jmp .len
.found:
    lea rax, [rbx + 16]
    mov rsi, rax
    add rsi, r15
    add rsi, rdx
    movzx eax, byte [rsi]
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.refill:
    ; load up to 8 bytes LSB-first into buf
    mov rax, [r12 + 24]
    test rax, rax
    jz .fail
    cmp rax, 8
    jbe .load_n
    mov rax, 8
.load_n:
    xor ecx, ecx
.load:
    test rax, rax
    jz .loaded
    mov rdx, [r12 + 16]
    movzx edx, byte [rdx]
    inc qword [r12 + 16]
    dec qword [r12 + 24]
    shl rdx, cl
    or [r12 + 0], rdx
    add ecx, 8
    add qword [r12 + 8], 8
    dec rax
    jmp .load
.loaded:
    jmp .have
.fail:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global huffman_version
huffman_version: dq 0x010000
