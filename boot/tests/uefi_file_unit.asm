; Native userspace harness for uefi_file_read_exact.
; It exercises the real loop against a small mocked EFI_FILE_PROTOCOL.Read.

[BITS 64]
default rel

%include "boot/uefi/file.asm"

MODE_SHORT     equ 0
MODE_ZERO      equ 1
MODE_OVERSIZED equ 2
MODE_ERROR     equ 3

section .text
global _start
_start:
    ; Successful firmware reads may be short and must be retried to completion.
    mov dword [rel read_mode], MODE_SHORT
    mov dword [rel read_calls], 0
    lea rcx, [rel file_protocol]
    lea rdx, [rel output]
    mov r8d, 10
    call uefi_file_read_exact
    test rax, rax
    jnz .fail_1
    cmp dword [rel read_calls], 4
    jne .fail_1
    lea r9, [rel output]
    mov ecx, 10
.check_output:
    cmp byte [r9], 0xA5
    jne .fail_1
    inc r9
    dec ecx
    jnz .check_output

    ; A successful zero-byte transfer before completion is a truncated file.
    mov dword [rel read_mode], MODE_ZERO
    lea rcx, [rel file_protocol]
    lea rdx, [rel output]
    mov r8d, 8
    call uefi_file_read_exact
    mov r10, EFI_END_OF_FILE
    cmp rax, r10
    jne .fail_2

    ; Firmware may never claim more bytes than the caller supplied.
    mov dword [rel read_mode], MODE_OVERSIZED
    lea rcx, [rel file_protocol]
    lea rdx, [rel output]
    mov r8d, 8
    call uefi_file_read_exact
    mov r10, EFI_COMPROMISED_DATA
    cmp rax, r10
    jne .fail_3

    ; Real firmware errors propagate without being collapsed into EOF.
    mov dword [rel read_mode], MODE_ERROR
    lea rcx, [rel file_protocol]
    lea rdx, [rel output]
    mov r8d, 8
    call uefi_file_read_exact
    mov r10, EFI_DEVICE_ERROR
    cmp rax, r10
    jne .fail_4

    ; An exact zero-byte request succeeds without touching the protocol.
    mov dword [rel read_mode], MODE_SHORT
    mov dword [rel read_calls], 0
    lea rcx, [rel file_protocol]
    lea rdx, [rel output]
    xor r8d, r8d
    call uefi_file_read_exact
    test rax, rax
    jnz .fail_5
    cmp dword [rel read_calls], 0
    jne .fail_5

    xor edi, edi
    jmp .exit
.fail_1:
    mov edi, 1
    jmp .exit
.fail_2:
    mov edi, 2
    jmp .exit
.fail_3:
    mov edi, 3
    jmp .exit
.fail_4:
    mov edi, 4
    jmp .exit
.fail_5:
    mov edi, 5
.exit:
    mov eax, 60
    syscall

; Microsoft-x64 callback used through EFI_FILE_PROTOCOL.Read.
; RCX = This, RDX = in/out byte count, R8 = destination.
fake_file_read:
    inc dword [rel read_calls]
    mov eax, [rel read_mode]
    cmp eax, MODE_ZERO
    je .zero
    cmp eax, MODE_OVERSIZED
    je .oversized
    cmp eax, MODE_ERROR
    je .error

    mov r9, [rdx]
    cmp r9, 3
    jbe .short_ready
    mov r9d, 3
.short_ready:
    mov [rdx], r9
    mov r10, r9
.fill:
    test r10, r10
    jz .success
    mov byte [r8], 0xA5
    inc r8
    dec r10
    jmp .fill
.success:
    xor eax, eax
    ret

.zero:
    mov qword [rdx], 0
    xor eax, eax
    ret
.oversized:
    mov rax, [rdx]
    inc rax
    mov [rdx], rax
    xor eax, eax
    ret
.error:
    mov rax, EFI_DEVICE_ERROR
    ret

section .data
align 8
file_protocol:
    times FILE_READ / 8 dq 0
    dq fake_file_read
read_mode:  dd 0
read_calls: dd 0

section .bss align=16
output: resb 16
