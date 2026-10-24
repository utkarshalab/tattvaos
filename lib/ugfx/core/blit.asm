; ============================================================================
; Blit — Pixel Copy (Src → Dst)
; Simple memcpy with stride handling
; ============================================================================

%include "ugfx.inc"

section .text

; ---------------------------------------------------------------------------
; blit_copy
;   Copy pixel buffer (handles stride)
;   IN:  rdi = dst, rsi = src, rdx = width, rcx = height, r8 = dst_stride, r9 = src_stride
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global blit_copy
blit_copy:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov r10, r9                    ; source stride
    ASSERT_PTR rbx
    ASSERT_PTR r12

    test r13, r13
    jz .done
    test r14, r14
    jz .done

    ; Check if strides match and width*4 == stride (contiguous)
    mov rax, r13
    shl rax, 2
    cmp rax, r15
    jne .strided
    cmp rax, r10
    jne .strided

    ; Contiguous - single memcpy
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    imul rdx, rax
    call memcopy_fast
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.strided:
    ; Per-row copy
.row_loop:
    push r14
    push rbx
    push r12
    mov r14, r13
    shl r14, 2

    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    call memcopy_fast

    pop r12
    pop rbx
    pop r14
    add rbx, r15
    add r12, r10
    dec r14
    jnz .row_loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; blit_copy_sse2
;   SSE2 accelerated copy
; ---------------------------------------------------------------------------
global blit_copy_sse2
blit_copy_sse2:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov r10, r9                    ; source stride
    ASSERT_PTR rbx
    ASSERT_PTR r12

    test r13, r13
    jz .done
    test r14, r14
    jz .done

    ; Check if we can use vector copy
    test r13, 3
    jnz .scalar
    test r15, 15
    jnz .scalar
    test r10, 15
    jnz .scalar

    ; Vector copy 16 bytes at a time
.row_loop:
    push r14
    push rbx
    push r12
    mov r14, r13
    shr r14, 2

.pixel_loop:
    movdqu xmm0, [r12]
    movdqu [rbx], xmm0
    add rbx, 16
    add r12, 16
    dec r14
    jnz .pixel_loop

    pop r12
    pop rbx
    pop r14
    add rbx, r15
    add r12, r10
    dec r14
    jnz .row_loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.scalar:
    call blit_copy
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; memcopy_fast
;   Fast memcpy (rep movsb or vector)
; ---------------------------------------------------------------------------
memcopy_fast:
    PROLOGUE_SAVE rdi, rsi, rcx
    mov rcx, rdx
    test rcx, rcx
    jz .done
    rep movsb
.done:
    EPILOGUE_RESTORE rdi, rsi, rcx
    ret

section .data

global blit_version
blit_version: dq 0x010000
