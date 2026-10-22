; ============================================================================
; Deflate — Compressor for Remote Display (stored + fixed Huffman)
; Matches inflate/zlib decoder path used for PNG
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern memcopy
%include "inc/canvas_client.inc"

; struct offsets (hoisted above use)
%define DEFLATE_STORED     0
%define DEFLATE_FIXED      1

section .text


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
    ; Stored blocks are the canonical deterministic path. Higher-level codec
    ; selection is handled by adaptive.asm, which avoids claiming compression
    ; when a tile is incompressible.
.stored:
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    mov rcx, r15
    call deflate_stored
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.empty:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
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
    mov r10, r13
    cmp r10, 65535
    jbe .blk
    mov r10, 65535
.blk:
    ; need 5 + block_length bytes
    mov rdx, r10
    add rdx, 5
    mov rcx, r14
    sub rcx, r15
    cmp rdx, rcx
    ja .full
    ; header
    cmp r10, r13
    jne .not_final
    mov byte [rbx + r15], 1  ; BFINAL=1, BTYPE=00
    jmp .hdr_done
.not_final:
    mov byte [rbx + r15], 0
.hdr_done:
    inc r15
    mov [rbx + r15], r10w
    mov eax, r10d
    not eax
    mov [rbx + r15 + 2], ax
    add r15, 4
    ; copy
    mov rdi, rbx
    add rdi, r15
    mov rsi, r12
    mov rcx, r10
    push r10
    call memcopy
    pop r10
    add r12, r10
    add r15, r10
    sub r13, r10
    jnz .loop
.done:
    mov rax, r15
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.full:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global deflate_version
deflate_version: dq 0x010000
