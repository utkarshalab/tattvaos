; =============================================================================
; Tattva OS — lib/mem/virt/hardware/mktme.asm
; =============================================================================
; Multi-Key Memory Encryption (MKTME) Configuration & Mappings (Feature 19).
; Configures multi-tenant hardware encryption keys and stamps key IDs on PML4/PTEs.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_HARDWARE_MKTME_ASM
%define LIB_MEM_VIRT_HARDWARE_MKTME_ASM

[BITS 64]

; Key structure definition
struc mktme_key_t
    .key_data   resb 32      ; 256-bit cryptographic key
    .valid      resq 1       ; Valid flag (1 = active)
endstruc

; -----------------------------------------------------------------------------
; Section .text
; -----------------------------------------------------------------------------
section .text

; -----------------------------------------------------------------------------
; mktme_configure_key — assigns key details to a target key_id in mock MSR registers
; Input:
;   RDI = key_id (0 to 3)
;   RSI = key_ptr (pointer to 32-byte key data)
; Output:
;   RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
global mktme_configure_key
mktme_configure_key:
    push rbx
    push rbp

    cmp rdi, 3
    ja .fail                        ; Key ID must be between 0 and 3
    test rsi, rsi
    jz .fail                        ; Null pointer check

    ; Locate corresponding key slot in sys_mktme_keys table
    mov rax, rdi
    imul rax, mktme_key_t_size
    lea rbx, [sys_mktme_keys + rax]

    ; Copy 32-byte key to the slot
    mov rbp, [rsi]
    mov [rbx + mktme_key_t.key_data], rbp
    mov rbp, [rsi + 8]
    mov [rbx + mktme_key_t.key_data + 8], rbp
    mov rbp, [rsi + 16]
    mov [rbx + mktme_key_t.key_data + 16], rbp
    mov rbp, [rsi + 24]
    mov [rbx + mktme_key_t.key_data + 24], rbp

    ; Set valid flag
    mov qword [rbx + mktme_key_t.valid], 1

    ; Simulate configuration of CPU MKTME key programming MSR (0x983)
    mov [sys_mktme_msr_value], rdi

    mov rax, 1
    jmp .exit

.fail:
    xor rax, rax

.exit:
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; mktme_set_pte_key — encodes target key_id into bits 51-52 of a PTE entry
; Input:
;   RDI = pte_ptr (Pointer to PTE entry)
;   RSI = key_id (0 to 3)
; Output:
;   RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
global mktme_set_pte_key
mktme_set_pte_key:
    test rdi, rdi
    jz .fail                        ; Null pointer check
    cmp rsi, 3
    ja .fail                        ; Key ID must be between 0 and 3

    mov rax, [rdi]                  ; Load PTE value

    ; Clear bits 51-52
    mov rcx, 3
    shl rcx, 51                     ; RCX = 3 << 51
    not rcx
    and rax, rcx                    ; Clear existing key ID bits

    ; OR key_id shifted to bits 51-52
    mov rcx, rsi
    shl rcx, 51
    or rax, rcx                     ; Merge key ID

    mov [rdi], rax                  ; Write back to PTE
    mov rax, 1
    ret

.fail:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; Section .data
; -----------------------------------------------------------------------------
section .data

align 8
global sys_mktme_msr_value
sys_mktme_msr_value: dq 0

; -----------------------------------------------------------------------------
; Section .bss
; -----------------------------------------------------------------------------
section .bss

alignb 32
global sys_mktme_keys
sys_mktme_keys: resb 4 * mktme_key_t_size

section .text

%endif ; LIB_MEM_VIRT_HARDWARE_MKTME_ASM
