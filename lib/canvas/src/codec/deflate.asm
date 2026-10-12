; ============================================================================
; Deflate — Compressor for Remote Display (stored + fixed Huffman)
; Matches inflate/zlib decoder path used for PNG
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

%define DEFLATE_STORED     0
%define DEFLATE_FIXED      1

; ---------------------------------------------------------------------------
; deflate_compress
;   IN: rdi=arena, rsi=src, rdx=src_len, rcx=dst, r8=dst_cap, r9=level
;   OUT: rax = bytes written, negative error
; ---------------------------------------------------------------------------
global deflate_compress
deflate_compress:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r14
    test r13, r13
    jz .empty
    ; level 0 = stored blocks
    cmp r9d, 0
    je .stored
    ; TODO: fixed-Huffman LZ77 (C27 adaptive); fall back to stored
.stored:
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    mov rcx, r15
    call deflate_stored
    ret
.empty:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; deflate_stored
; ---------------------------------------------------------------------------
global deflate_stored
deflate_stored:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    xor r15, r15  ; written
    test r13, r13
    jz .done
.loop:
    mov rax, r13
    cmp rax, 65535
    jbe .blk
    mov rax, 65535
.blk:
    ; need 5 + rax bytes
    mov rdx, rax
    add rdx, 5
    mov rcx, r14
    sub rcx, r15
    cmp rdx, rcx
    ja .full
    ; header
    cmp rax, r13
    jne .not_final
    mov byte [rbx + r15], 1  ; BFINAL=1, BTYPE=00
    jmp .hdr_done
.not_final:
    mov byte [rbx + r15], 0
.hdr_done:
    inc r15
    mov [rbx + r15], ax
    shr eax, 16
    mov [rbx + r15 + 2], ax
    mov eax, [rbx + r15]
    not eax
    mov [rbx + r15 + 2], ax
    add r15, 4
    ; copy
    mov rdi, rbx
    add rdi, r15
    mov rsi, r12
    mov rdx, rax
    and edx, 0xFFFF
    mov rcx, rdx
    call memcopy
    add r12, rcx
    add r15, rcx
    sub r13, rcx
    jnz .loop
.done:
    mov rax, r15
    ret
.full:
    RETURN_ERROR ENOSPC

section .data
global deflate_version
deflate_version: dq 0x010000
