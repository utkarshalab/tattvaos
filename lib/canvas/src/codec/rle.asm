; ============================================================================
; RLE — Run-Length Codec (packbits-style) for Flat Remote Tiles
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

section .text

; ---------------------------------------------------------------------------
; rle_encode
;   IN: rdi=src, rsi=src_len, rdx=dst, rcx=dst_cap
;   OUT: rax = bytes written
; ---------------------------------------------------------------------------
global rle_encode
rle_encode:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r13
    xor r15, r15
    test r12, r12
    jz .done
.loop:
    test r12, r12
    jz .done
    ; run length of same byte
    mov al, [rbx]
    mov rcx, 1
.run:
    cmp rcx, r12
    jae .emit_run
    cmp rcx, 128
    jae .emit_run
    cmp [rbx + rcx], al
    jne .emit_run
    inc rcx
    jmp .run
.emit_run:
    cmp rcx, 2
    jb .literal
    ; run: len = rcx (2..128), need 2 bytes
    cmp r15, r14
    jae .full
    mov rdx, rcx
    dec rdx
    neg dl
    dec dl  ; -(n-1)-? packbits: header = 1-n
    ; header = -(rcx-1)
    mov eax, ecx
    dec eax
    neg al
    mov [r13 + r15], al
    inc r15
    cmp r15, r14
    jae .full
    mov [r13 + r15], al
    mov al, [rbx]
    mov [r13 + r15], al
    inc r15
    add rbx, rcx
    sub r12, rcx
    jmp .loop
.literal:
    ; gather literal run up to 128 or until run of 3+
    mov rcx, 1
.lit:
    cmp rcx, r12
    jae .emit_lit
    cmp rcx, 128
    jae .emit_lit
    mov al, [rbx + rcx]
    cmp rcx, 2
    jb .lit_next
    cmp al, [rbx + rcx - 1]
    jne .lit_next
    cmp al, [rbx + rcx - 2]
    je .emit_lit  ; run of 3 starts
.lit_next:
    inc rcx
    jmp .lit
.emit_lit:
    ; need 1 + rcx bytes
    mov rax, rcx
    inc rax
    add rax, r15
    cmp rax, r14
    ja .full
    mov eax, ecx
    dec eax
    mov [r13 + r15], al
    inc r15
    mov rdi, r13
    add rdi, r15
    mov rsi, rbx
    mov rdx, rcx
    call memcopy
    add rbx, rcx
    add r15, rcx
    sub r12, rcx
    jmp .loop
.done:
    mov rax, r15
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.full:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; rle_decode
; ---------------------------------------------------------------------------
global rle_decode
rle_decode:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r13
    xor r15, r15
.loop:
    test r12, r12
    jz .done
    movsx eax, byte [rbx]
    inc rbx
    dec r12
    test eax, eax
    js .run
    ; literal: n = eax+1
    inc eax
    cmp rax, r12
    ja .fail
    cmp rax, r14
    sub r14, r15
    cmp rax, r14
    ja .fail
    add r14, r15
    mov rdi, r13
    add rdi, r15
    mov rsi, rbx
    mov rdx, rax
    call memcopy
    add rbx, rax
    sub r12, rax
    add r15, rax
    jmp .loop
.run:
    neg eax
    inc eax  ; n
    test r12, r12
    jz .fail
    mov cl, [rbx]
    inc rbx
    dec r12
    cmp rax, r14
    sub r14, r15
    cmp rax, r14
    ja .fail
    add r14, r15
    mov rdi, r13
    add rdi, r15
    mov rsi, rax
.fill:
    test rsi, rsi
    jz .filled
    mov [rdi], cl
    inc rdi
    dec rsi
    jmp .fill
.filled:
    add r15, rax
    jmp .loop
.done:
    mov rax, r15
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global rle_version
rle_version: dq 0x010000
