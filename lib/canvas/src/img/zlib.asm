; ============================================================================
; zlib — RFC1950 Framing (header check + inflate + Adler-32 verify)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; ---------------------------------------------------------------------------
; zlib_decompress
;   IN: rdi=arena, rsi=src, rdx=src_len, rcx=out, r8=out_cap
;   OUT: rax = bytes written, negative error
; ---------------------------------------------------------------------------
global zlib_decompress
zlib_decompress:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi        ; arena
    mov r12, rsi        ; src
    mov r13, rdx        ; src_len
    mov r14, rcx        ; out
    mov r15, r8         ; out_cap
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r14
    cmp r13, 6
    jb .fail
    movzx eax, byte [r12]
    movzx edx, byte [r12 + 1]
    and eax, 0x0F
    cmp eax, 8
    jne .fail
    movzx eax, byte [r12]
    shl eax, 8
    or eax, edx
    mov ecx, 31
    xor edx, edx
    div ecx
    test edx, edx
    jnz .fail
    movzx eax, byte [r12 + 1]
    test eax, 0x20
    jnz .fail
    ; stored adler (BE) at end
    mov eax, [r12 + r13 - 4]
    bswap eax
    push rax
    ; inflate body
    mov rdi, rbx
    mov rsi, r12
    add rsi, 2
    mov rdx, r13
    sub rdx, 6
    mov rcx, r14
    mov r8, r15
    call inflate
    test rax, rax
    js .fail2
    mov r13, rax  ; out len
    ; verify Adler-32
    mov rdi, r14
    mov rsi, r13
    mov rdx, 1
    call adler32
    pop rdx
    cmp eax, edx
    jne .adler_fail
    mov rax, r13
    ret
.fail2:
    add rsp, 8
.fail:
    RETURN_ERROR EINVAL
.adler_fail:
    RETURN_ERROR EINVAL
