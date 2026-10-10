%ifndef KERNEL_ARCH_X86_64_DMAR_ASM
%define KERNEL_ARCH_X86_64_DMAR_ASM
; =============================================================================
; Intel DMA Remapping Reporting (DMAR) platform-policy validation.
; =============================================================================

[BITS 64]

DMAR_SIGNATURE             equ 0x52414D44
DMAR_HEADER_BYTES          equ 48
DMAR_MAX_TABLE_BYTES       equ 1024 * 1024
DMAR_FLAG_INTR_REMAP       equ 1 << 0
DMAR_FLAG_X2APIC_OPT_OUT   equ 1 << 1

section .text

; RDI=DMAR, RSI=exclusive mapped limit.
; CF=0/EAX=validated flags. CF=1 means the table cannot guide APIC policy.
global smp_dmar_policy_parse
smp_dmar_policy_parse:
    test rdi, rdi
    jz .invalid
    mov rdx, rdi
    add rdx, 36
    jc .invalid
    cmp rdx, rsi
    ja .invalid
    cmp dword [rdi], DMAR_SIGNATURE
    jne .invalid
    mov ecx, [rdi + 4]
    cmp ecx, DMAR_HEADER_BYTES
    jb .invalid
    cmp ecx, DMAR_MAX_TABLE_BYTES
    ja .invalid
    mov rdx, rdi
    add rdx, rcx
    jc .invalid
    cmp rdx, rsi
    ja .invalid
    cmp byte [rdi + 8], 1
    jne .invalid
    cmp byte [rdi + 36], 63
    ja .invalid
    mov al, [rdi + 37]
    test al, 0xF8
    jnz .invalid
    test al, DMAR_FLAG_X2APIC_OPT_OUT
    jz .flags_valid
    test al, DMAR_FLAG_INTR_REMAP
    jz .invalid
.flags_valid:
    cmp qword [rdi + 38], 0
    jne .invalid
    cmp word [rdi + 46], 0
    jne .invalid

    xor eax, eax
    mov rdx, rdi
.checksum:
    add al, [rdx]
    inc rdx
    dec ecx
    jnz .checksum
    test al, al
    jnz .invalid
    movzx eax, byte [rdi + 37]
    clc
    ret
.invalid:
    xor eax, eax
    stc
    ret

%endif
