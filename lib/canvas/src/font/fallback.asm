; ============================================================================
; Fallback — Multi-Font Glyph Resolution Chain
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

; struct offsets (hoisted above use)
%define FontChain_SIZE    24

section .text

struc FontChain
    .fonts:         resq 1
    .count:         resq 1
    .cap:           resq 1
endstruc

; ---------------------------------------------------------------------------
; fallback_init
; ---------------------------------------------------------------------------
global fallback_init
fallback_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, r12
    mov rsi, FontChain_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov rdi, r12
    mov rsi, 8 * 8
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + FontChain.fonts], rax
    mov qword [rbx + FontChain.count], 0
    mov qword [rbx + FontChain.cap], 8
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; fallback_add
; ---------------------------------------------------------------------------
global fallback_add
fallback_add:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rax, [rbx + FontChain.count]
    cmp rax, [rbx + FontChain.cap]
    jae .full
    mov rdx, [rbx + FontChain.fonts]
    mov [rdx + rax * 8], r12
    inc qword [rbx + FontChain.count]
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.full:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; fallback_resolve
;   IN: rdi = chain, rsi = codepoint — OUT: rax = font*, rdx = glyph id
; ---------------------------------------------------------------------------
global fallback_resolve
fallback_resolve:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx
    mov r13, [rbx + FontChain.fonts]
    mov r14, [rbx + FontChain.count]
    xor r15d, r15d
.loop:
    cmp r15, r14
    jae .missing
    mov rdi, [r13 + r15 * 8]
    mov esi, r12d
    call cmap_glyph_id
    test eax, eax
    jnz .found
    inc r15
    jmp .loop
.found:
    mov edx, eax
    mov rax, [r13 + r15 * 8]
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.missing:
    xor rax, rax
    xor rdx, rdx
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global fallback_version
fallback_version: dq 0x010000
