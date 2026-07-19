; =============================================================================
; Tattva OS — boot/tpm/tpm_extend.asm
; =============================================================================
; Higher-level TPM PCR extension helpers.
;
; Wraps the low-level tpm_extend_pcr (from tpm.asm) with convenience
; functions that hash a memory region and extend the result into a
; specific PCR register. Completes the measured boot chain alongside
; tpm_measure.asm.
;
; PCR allocation (Tattva OS convention):
;   PCR 0: Stage 1 (MBR) measurement
;   PCR 1: Stage 2 configuration / boot parameters
;   PCR 4: Stage 2 code + kernel (handled by tpm_measure.asm)
;   PCR 5: Boot configuration (config.asm constants, boot flags)
;   PCR 7: Secure boot policy (future)
;
; Author:  Utkarsha Labs
; Target:  x86-64, long mode (64-bit)
; =============================================================================

%ifndef TPM_EXTEND_ASM
%define TPM_EXTEND_ASM

[BITS 64]

; =============================================================================
; tpm_extend_hash — hash memory region and extend into PCR
; Input:  RSI = pointer to memory region to measure
;         RCX = size of region in bytes
;         EDX = PCR index to extend
; Output: RAX = 1 if extended successfully, 0 if failed
; Clobbers: RDI
;
; This is the primary workhorse: SHA-256 hash → PCR extend.
; =============================================================================
tpm_extend_hash:
    push rbx
    push rcx
    push rdx
    push rsi
    push r12

    mov r12d, edx                   ; save PCR index

    ; Step 1: Hash the memory region
    ; sha256_hash: RSI=data, RCX=length, RDI=output (32 bytes)
    lea rdi, [rel tpm_ext_digest]
    call sha256_hash

    ; Step 2: Extend the hash into the specified PCR
    mov ecx, r12d                   ; PCR index
    lea rsi, [rel tpm_ext_digest]   ; digest pointer
    call tpm_extend_pcr             ; from tpm.asm

    ; RAX already set by tpm_extend_pcr (1=success, 0=fail)

    pop r12
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; =============================================================================
; tpm_extend_stage1 — measure Stage 1 (MBR) into PCR 0
; Input:  none
; Output: RAX = 1 if extended, 0 if failed or TPM not present
; Clobbers: RCX, RDX, RSI, RDI
;
; Measures the entire 512-byte MBR at its relocated address (STAGE1_RELOC).
; Should be called early in stage2 after TPM is initialized.
; =============================================================================
tpm_extend_stage1:
    push rbx

    ; Verify TPM is available
    call tpm_init
    test rax, rax
    jz .stage1_done                 ; no TPM

    mov rsi, STAGE1_RELOC           ; MBR relocated to 0x0600
    mov rcx, 512                    ; full MBR size
    mov edx, 0                      ; PCR 0
    call tpm_extend_hash

.stage1_done:
    pop rbx
    ret

; =============================================================================
; tpm_extend_config — measure boot configuration into PCR 5
; Input:  RSI = pointer to configuration data
;         RCX = size of configuration data in bytes
; Output: RAX = 1 if extended, 0 if failed
; Clobbers: RDX, RDI
;
; Measures boot-time configuration (e.g. the BootInfo structure at 0x7000,
; or config constants). This allows the kernel to verify that boot
; parameters were not tampered with.
;
; Typical usage:
;   mov rsi, BOOT_INFO_ADDR        ; 0x7000
;   mov rcx, 88                    ; BootInfo structure size
;   call tpm_extend_config
; =============================================================================
tpm_extend_config:
    mov edx, 5                      ; PCR 5
    call tpm_extend_hash
    ret

; =============================================================================
; tpm_extend_stage2 — measure Stage 2 code into PCR 1
; Input:  none
; Output: RAX = 1 if extended, 0 if failed
; Clobbers: RCX, RDX, RSI, RDI
;
; Measures stage2 code region for integrity verification.
; Complements tpm_measure.asm which measures into PCR 4.
; This separate PCR 1 measurement allows independent policy
; decisions on stage2 vs kernel trust.
; =============================================================================
tpm_extend_stage2:
    push rbx

    call tpm_init
    test rax, rax
    jz .stage2_done

    mov rsi, STAGE2_LOAD            ; 0x8000
    mov rcx, STAGE2_SECTORS * 512   ; stage2 size
    mov edx, 1                      ; PCR 1
    call tpm_extend_hash

.stage2_done:
    pop rbx
    ret

; =============================================================================
; tpm_extend_all — convenience: measure all boot components
; Input:  none
; Output: RAX = number of successful extensions (0-3)
; Clobbers: all general-purpose registers
;
; Measures:
;   PCR 0 ← Stage 1 (MBR)
;   PCR 1 ← Stage 2 code
;   PCR 5 ← BootInfo configuration
;
; Note: PCR 4 (kernel) is handled by tpm_measure.asm after kernel load.
; =============================================================================
tpm_extend_all:
    push r12

    xor r12d, r12d                  ; success counter = 0

    ; PCR 0: Stage 1
    call tpm_extend_stage1
    add r12d, eax                   ; +1 if successful

    ; PCR 1: Stage 2
    call tpm_extend_stage2
    add r12d, eax                   ; +1 if successful

    ; PCR 5: BootInfo config
    mov rsi, BOOT_INFO_ADDR         ; 0x7000
    mov rcx, 88                     ; BootInfo structure size (22 dwords)
    call tpm_extend_config
    add r12d, eax                   ; +1 if successful

    mov eax, r12d                   ; return count

    pop r12
    ret

; =============================================================================
; Data — digest buffer for intermediate SHA-256 results
; =============================================================================
align 8
tpm_ext_digest:     times 32 db 0   ; 32-byte SHA-256 digest buffer

%endif ; TPM_EXTEND_ASM
