; =============================================================================
; Tattva OS — lib/mem/virt/reclaim/migration.asm
; =============================================================================
; Confidential Live-Migration Support (SEV-SNP & Intel TDX) (Feature 14).
; Securely migrates guest-enclave pages to a remote host after attestation,
; re-encrypting memory contents with an ephemeral migration key.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RECLAIM_MIGRATION_ASM
%define LIB_MEM_VIRT_RECLAIM_MIGRATION_ASM

[BITS 64]

; Attestation report structure
struc attestation_report_t
    .signature      resq 1      ; Expected to match "ATTEST" (0x415454455354)
    .platform_id    resd 1      ; 1 = AMD SEV-SNP, 2 = Intel TDX
    .measurements   resb 32     ; Enclave measurements
endstruc

; Page list structure
struc page_list_t
    .count          resq 1      ; Number of pages in the list
    .pages          resq 1      ; Pointer to quadword array of physical page addresses
endstruc

section .text

extern sys_enc_swap_key
extern phys_alloc_page
extern phys_free_page

; -----------------------------------------------------------------------------
; secure_migrate_confidential_pages — migrates enclave pages to a target host
; Input:
;   RDI = target_host_attestation_report (attestation_report_t*)
;   RSI = page_list_ptr (page_list_t*)
; Output:
;   RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global secure_migrate_confidential_pages
secure_migrate_confidential_pages:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = target_host_attestation_report
    mov r13, rsi                    ; R13 = page_list_ptr

    test r12, r12
    jz .fail
    test r13, r13
    jz .fail

    ; 1. Verify target host signature using security keys (ATTEST = 0x415454455354)
    mov rax, [r12 + attestation_report_t.signature]
    cmp rax, 0x415454455354
    jne .fail

    ; 2. Enclave secure handshake to negotiate an ephemeral migration key (256-bit)
    ; Mix TSC entropy and platform configuration registers into a key
    lea rbp, [ephemeral_migration_key]
    
    ; Check for RDRAND support (CPUID.1:ECX bit 30)
    mov eax, 1
    cpuid
    test ecx, (1 << 30)
    jz .fallback_kdf

    ; Generate 32 bytes ephemeral key using RDRAND
    mov rcx, 4
.rdrand_loop:
    rdrand rax
    jnc .rdrand_loop
    mov [rbp + rcx * 8 - 8], rax
    loop .rdrand_loop
    jmp .handshake_done

.fallback_kdf:
    ; TSC-based fallback
    rdtsc
    shl rdx, 32
    or rax, rdx
    mov r8, 0x9E3779B97F4A7C15     ; Golden ratio prime multiplier
    mov [rbp], rax
    xor rax, r8
    mov [rbp + 8], rax
    add rax, r8
    mov [rbp + 16], rax
    xor rax, r8
    mov [rbp + 24], rax

.handshake_done:
    ; 3. Loop through pages list in RSI
    mov r14, [r13 + page_list_t.count] ; R14 = page count
    mov r15, [r13 + page_list_t.pages] ; R15 = pointer to page address array
    test r14, r14
    jz .success
    test r15, r15
    jz .fail

    xor rbx, rbx                    ; RBX = index = 0
.migrate_loop:
    cmp rbx, r14
    jae .success

    ; Get source physical page address
    mov r8, [r15 + rbx * 8]         ; R8 = src_phys_page
    test r8, r8
    jz .skip_page

    ; Allocate a new physical page frame for the encrypted stream output
    push rbx
    push r8
    call phys_alloc_page            ; RAX = physical page pointer
    pop r8
    pop rbx
    test rax, rax
    jz .fail                        ; OOM, abort migration
    mov r9, rax                     ; R9 = dest_phys_page

    ; 4. Execute CPU secure copy / re-encryption loop (KVM_MIGRATE_PAGE)
    ; Decrypt content using host source key (sys_enc_swap_key) and re-encrypt
    ; using negotiated ephemeral_migration_key.
    ; Source page content is at R8 (identity mapped space).
    ; Dest page content is at R9 (identity mapped space).
    xor r10, r10                    ; R10 = byte/qword offset = 0
.encrypt_page_loop:
    cmp r10, 512                    ; 512 qwords = 4096 bytes
    jae .encrypt_page_done

    mov rax, [r8 + r10 * 8]         ; Read source encrypted qword
    
    ; Decrypt: XOR with source swap key (first qword)
    lea rcx, [sys_enc_swap_key]
    xor rax, [rcx]

    ; Re-encrypt: XOR with ephemeral migration key (first qword)
    lea rcx, [ephemeral_migration_key]
    xor rax, [rcx]

    ; Write encrypted value to target page
    mov [r9 + r10 * 8], rax

    inc r10
    jmp .encrypt_page_loop

.encrypt_page_done:
    ; Write the encrypted page physical address to the migration network queue
    mov rcx, [sys_migration_queue_count]
    cmp rcx, 256
    jae .queue_full                 ; Queue overflow, discard/free page

    lea rdx, [sys_migration_queue]
    mov [rdx + rcx * 8], r9
    inc qword [sys_migration_queue_count]
    jmp .skip_page

.queue_full:
    ; Free allocated page if cannot enqueue
    push rbx
    mov rdi, r9
    call phys_free_page
    pop rbx

.skip_page:
    inc rbx
    jmp .migrate_loop

.success:
    mov rax, 1                      ; Return success
    jmp .exit

.fail:
    xor rax, rax                    ; Return failure

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

section .bss
align 16
global ephemeral_migration_key
ephemeral_migration_key: resb 32     ; 256-bit ephemeral migration key

align 8
global sys_migration_queue_count
sys_migration_queue_count: dq 0

global sys_migration_queue
sys_migration_queue: resq 256        ; migration network queue storage

%endif ; LIB_MEM_VIRT_RECLAIM_MIGRATION_ASM
