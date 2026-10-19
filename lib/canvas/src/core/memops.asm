; ============================================================================
; Memory Operations — memcopy, memset, memcmp
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; ---------------------------------------------------------------------------
; memcopy
;   Copy memory (non-overlapping)
;   IN:  rdi = dest, rsi = src, rdx = count
;   OUT: rax = dest
; ---------------------------------------------------------------------------
global memcopy
memcopy:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r13, r13
    jz .done
    
    ; Check alignment for fast path
    test rdi, 15
    jnz .byte_loop
    test rsi, 15
    jnz .byte_loop
    test rdx, 15
    jnz .byte_loop
    
    ; 16-byte aligned fast path
    shr r13, 4
    jz .done
.aligned_loop:
    movdqu xmm0, [r12]
    movdqu [rbx], xmm0
    add r12, 16
    add rbx, 16
    dec r13
    jnz .aligned_loop
    jmp .done
    
.byte_loop:
    mov al, [r12]
    mov [rbx], al
    inc r12
    inc rbx
    dec r13
    jnz .byte_loop
    
.done:
    mov rax, rdi
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; memmove
;   Copy memory (handles overlapping)
;   IN:  rdi = dest, rsi = src, rdx = count
;   OUT: rax = dest
; ---------------------------------------------------------------------------
global memmove
memmove:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r13, r13
    jz .done
    
    cmp rbx, r12
    jae .forward
    
    ; dest < src: copy forward
    mov rdi, rbx
    mov rsi, r12
    call memcopy
    jmp .done
    
.forward:
    ; dest > src: copy backward
    lea rdi, [rbx + r13 - 1]
    lea rsi, [r12 + r13 - 1]
    std
    rep movsb
    cld
    
.done:
    mov rax, rdi
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; memset
;   Fill memory with byte value
;   IN:  rdi = dest, rsi = value (byte), rdx = count
;   OUT: rax = dest
; ---------------------------------------------------------------------------
global memset
memset:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12b, sil
    ASSERT_PTR rbx
    test rdx, rdx
    jz .done
    
    mov al, r12b
    mov rcx, rdx
    rep stosb
    
.done:
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; memcmp
;   Compare memory
;   IN:  rdi = ptr1, rsi = ptr2, rdx = count
;   OUT: rax = 0 if equal, negative/positive if different
; ---------------------------------------------------------------------------
global memcmp
memcmp:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r13, r13
    jz .equal
    
.loop:
    mov al, [rbx]
    cmp al, [r12]
    jne .diff
    inc rbx
    inc r12
    dec r13
    jnz .loop
    
.equal:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
    
.diff:
    sbb rax, rax
    or rax, 1
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global memops_version
memops_version: dq 0x010000
