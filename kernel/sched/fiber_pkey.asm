; =============================================================================
; Tattva OS — kernel/sched/fiber_pkey.asm
; =============================================================================
; Intel/AMD Protection Keys (PKEYs / MPK) Hardware Memory Protection Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "sched/fiber.inc"

section .text

; -----------------------------------------------------------------------------
; pkey_init — Initialize Intel PKEY hardware support
; Input:  none
; Output: RAX = 1 if supported and enabled, 0 if unsupported (fallback)
; -----------------------------------------------------------------------------
pkey_init:
    push rbx
    push rcx
    push rdx

    ; Check CPUID EAX=7, ECX=0 for OSPKE (ECX bit 4)
    mov eax, 7
    xor ecx, ecx
    cpuid
    test ecx, (1 << 4)
    jz .unsupported

    ; Enable CR4.PKEY (bit 24)
    mov rax, cr4
    or rax, (1 << 24)
    mov cr4, rax

    mov byte [pkey_supported], 1
    mov rax, 1
    jmp .done

.unsupported:
    mov byte [pkey_supported], 0
    xor rax, rax

.done:
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; pkey_alloc — Allocate a 4-bit PKEY for a fiber (1..15)
; Input:  none
; Output: EAX = PKEY index (0 if none available or unsupported)
; -----------------------------------------------------------------------------
pkey_alloc:
    cmp byte [pkey_supported], 1
    jne .none

    mov eax, [next_pkey_idx]
    inc dword [next_pkey_idx]
    and eax, 0x0F                   ; Wrap 1..15
    jnz .valid
    mov eax, 1                      ; Avoid PKEY 0 (default kernel key)
.valid:
    ret

.none:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; pkey_switch — Perform WRPKRU hardware key switch during context switch
; Input:  EDI = Target Fiber PKEY (0..15)
; Output: none
; -----------------------------------------------------------------------------
pkey_switch:
    cmp byte [pkey_supported], 1
    jne .done

    ; WRPKRU instruction updates PKRU register:
    ; EAX = PKRU value (bits 2i = disable access, bits 2i+1 = disable write)
    ; ECX = 0, EDX = 0
    xor ecx, ecx
    xor edx, edx

    ; Build PKRU mask: Allow access ONLY to PKEY 0 and target PKEY (EDI)
    ; Disable access (0x55555555) for all keys, then clear bits for EDI & 0
    mov eax, 0x55555555             ; Disable access for all keys 0..15
    
    ; Clear disable bits for PKEY 0 (bits 0,1)
    and eax, ~0x03
    
    ; Clear disable bits for PKEY EDI (bits 2*EDI, 2*EDI+1)
    mov ecx, edi
    shl ecx, 1                      ; shift = 2 * EDI
    mov r8d, 0x03
    shl r8d, cl
    not r8d
    and eax, r8d

    xor ecx, ecx
    xor edx, edx
    wrpkru                          ; Update hardware PKRU register

.done:
    ret

section .data
pkey_supported: db 0
next_pkey_idx:  dd 1
