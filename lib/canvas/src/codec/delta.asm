; ============================================================================
; Delta — Inter-Frame Delta Encoding (changed tiles only)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; ---------------------------------------------------------------------------
; delta_encode_tile
;   XOR current tile with previous tile; RLE the result
;   IN: rdi=dst, rsi=dst_cap, rdx=cur, rcx=prev, r8=pixels
;   OUT: rax = bytes written
; ---------------------------------------------------------------------------
global delta_encode_tile
delta_encode_tile:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r13
    ASSERT_PTR r14
    xor eax, eax  ; out pos
    xor ecx, ecx  ; pixel index
.loop:
    cmp rcx, r15
    jae .done
    mov edx, [r13 + rcx * 4]
    xor edx, [r14 + rcx * 4]
    test edx, edx
    jz .skip
    ; changed pixel: emit index (u16) + value (u32) = 6 bytes
    cmp rax, r12
    jae .full
    mov r8d, ecx
    cmp r8d, 65535
    ja .full
    mov r9, rax
    add r9, 6
    cmp r9, r12
    ja .full
    mov [rbx + rax], r8w
    mov [rbx + rax + 2], edx
    mov dword [rbx + rax + 2], edx
    add rax, 6
.skip:
    inc rcx
    jmp .loop
.done:
    ret
.full:
    RETURN_ERROR ENOSPC

; ---------------------------------------------------------------------------
; delta_decode_tile
;   IN: rdi=prev, rsi=delta, rdx=delta_len, rcx=out, r8=pixels
; ---------------------------------------------------------------------------
global delta_decode_tile
delta_decode_tile:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r14
    ; copy prev -> out
    mov rdi, r14
    mov rsi, rbx
    mov rdx, r15
    shl rdx, 2
    call memcopy
    xor eax, eax
.loop:
    cmp rax, r13
    jae .done
    mov r8d, r13d
    sub r8d, eax
    cmp r8d, 6
    jb .fail
    movzx ecx, word [r12 + rax]
    mov edx, [r12 + rax + 2]
    cmp rcx, r15
    jae .fail
    mov [r14 + rcx * 4], edx
    add rax, 6
    jmp .loop
.done:
    xor rax, rax
    ret
.fail:
    RETURN_ERROR EINVAL

section .data
global delta_version
delta_version: dq 0x010000
