%ifndef KERNEL_ARCH_X86_64_PCI_MSI_ASM
%define KERNEL_ARCH_X86_64_PCI_MSI_ASM
; =============================================================================
; Kernel-owned conventional PCI MSI lifecycle.
;
; This deliberately owns only the proven common envelope: one 64-bit message,
; one permanent vector/gate, no per-vector mask, and a direct physical APIC
; destination. Device MMIO, PCI Command, source masking/ack, and bus mastering
; remain the device driver's responsibility.
; =============================================================================

[BITS 64]

KPCI_CAP_ID_MSI                 equ 0x05
KPCI_MSI_ENABLE                 equ 1 << 0
KPCI_MSI_MMC_MASK               equ 7 << 1
KPCI_MSI_MME_MASK               equ 7 << 4
KPCI_MSI_64BIT                  equ 1 << 7
KPCI_MSI_MASK_CAPABLE           equ 1 << 8

KPCI_MSI_OWNER_LOCK             equ 0
KPCI_MSI_OWNER_STATE            equ 4
KPCI_MSI_OWNER_BDF              equ 8
KPCI_MSI_OWNER_CAP              equ 12
KPCI_MSI_OWNER_VECTOR           equ 16
KPCI_MSI_OWNER_DESTINATION      equ 20
KPCI_MSI_OWNER_SAVED_CONTROL    equ 24
KPCI_MSI_OWNER_SAVED_ADDR_LOW   equ 28
KPCI_MSI_OWNER_SAVED_ADDR_HIGH  equ 32
KPCI_MSI_OWNER_SAVED_DATA       equ 36
KPCI_MSI_OWNER_MESSAGE_ADDR     equ 40
KPCI_MSI_OWNER_GATE_PUBLISHED   equ 44
KPCI_MSI_OWNER_SIZE             equ 48

KPCI_MSI_STATE_EMPTY            equ 0
KPCI_MSI_STATE_PREPARED         equ 1
KPCI_MSI_STATE_ARMED            equ 2
KPCI_MSI_STATE_QUIESCED         equ 3
KPCI_MSI_STATE_RESTORED         equ 4
KPCI_MSI_STATE_FAILED           equ 5

%ifdef KPCI_MSI_TEST_LOCKS
; Native failure-injection tests cannot change IF at ring 3.
%macro KPCI_MSI_LOCK 2
    xor %1, %1
%%spin:
    mov eax, 1
    xchg eax, [%2 + KPCI_MSI_OWNER_LOCK]
    test eax, eax
    jz %%held
    pause
    jmp %%spin
%%held:
%endmacro

%macro KPCI_MSI_UNLOCK 2
    mov dword [%1 + KPCI_MSI_OWNER_LOCK], 0
%endmacro
%else
%macro KPCI_MSI_LOCK 2
    pushfq
    pop %1
    cli
%%spin:
    mov eax, 1
    xchg eax, [%2 + KPCI_MSI_OWNER_LOCK]
    test eax, eax
    jz %%held
    pause
    jmp %%spin
%%held:
%endmacro

%macro KPCI_MSI_UNLOCK 2
    mov dword [%1 + KPCI_MSI_OWNER_LOCK], 0
    push %2
    popfq
%endmacro
%endif

section .text

; RDI=256-byte conventional configuration snapshot.
; CF=0/EAX=validated 64-bit single-message MSI capability offset.
; CF=1/EAX=0 when absent, malformed, enabled, or outside the owned envelope.
global kpci_msi_snapshot_cap
kpci_msi_snapshot_cap:
    push rbx
    test rdi, rdi
    jz .invalid
    mov rbx, rdi
    mov esi, KPCI_CONFIG_SPACE_BYTES
    mov edx, KPCI_CAP_ID_MSI
    call kpci_find_capability_snapshot
    jc .invalid
    test eax, eax
    jz .invalid
    mov ecx, eax
    add ecx, 14
    jc .invalid
    cmp ecx, KPCI_CONFIG_SPACE_BYTES
    ja .invalid
    cmp byte [rbx + rax], KPCI_CAP_ID_MSI
    jne .invalid
    movzx edx, word [rbx + rax + 2]
    test edx, KPCI_MSI_ENABLE | KPCI_MSI_MMC_MASK | KPCI_MSI_MME_MASK
    jnz .invalid
    test edx, KPCI_MSI_64BIT
    jz .invalid
    test edx, KPCI_MSI_MASK_CAPABLE
    jnz .invalid
    pop rbx
    clc
    ret
.invalid:
    pop rbx
    xor eax, eax
    stc
    ret

; Restore saved message data/address/control, with the disabled control last.
; Caller holds the owner lock and has already quiesced the device source.
kpci_msi_restore_fields:
    push r12
    mov r12, rdi

    mov edi, [r12 + KPCI_MSI_OWNER_BDF]
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 12
    mov edx, 2
    mov ecx, [r12 + KPCI_MSI_OWNER_SAVED_DATA]
    call kpci_cfg_write
    jc .failed
    mov edi, [r12 + KPCI_MSI_OWNER_BDF]
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 8
    mov edx, 4
    mov ecx, [r12 + KPCI_MSI_OWNER_SAVED_ADDR_HIGH]
    call kpci_cfg_write
    jc .failed
    mov edi, [r12 + KPCI_MSI_OWNER_BDF]
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 4
    mov edx, 4
    mov ecx, [r12 + KPCI_MSI_OWNER_SAVED_ADDR_LOW]
    call kpci_cfg_write
    jc .failed
    mov edi, [r12 + KPCI_MSI_OWNER_BDF]
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 2
    mov edx, 2
    mov ecx, [r12 + KPCI_MSI_OWNER_SAVED_CONTROL]
    call kpci_cfg_write
    jc .failed

    mov edi, [r12 + KPCI_MSI_OWNER_BDF]
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 12
    mov edx, 2
    call kpci_cfg_read
    jc .failed
    cmp eax, [r12 + KPCI_MSI_OWNER_SAVED_DATA]
    jne .failed
    mov edi, [r12 + KPCI_MSI_OWNER_BDF]
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 8
    mov edx, 4
    call kpci_cfg_read
    jc .failed
    cmp eax, [r12 + KPCI_MSI_OWNER_SAVED_ADDR_HIGH]
    jne .failed
    mov edi, [r12 + KPCI_MSI_OWNER_BDF]
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 4
    mov edx, 4
    call kpci_cfg_read
    jc .failed
    cmp eax, [r12 + KPCI_MSI_OWNER_SAVED_ADDR_LOW]
    jne .failed
    mov edi, [r12 + KPCI_MSI_OWNER_BDF]
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 2
    mov edx, 2
    call kpci_cfg_read
    jc .failed
    cmp eax, [r12 + KPCI_MSI_OWNER_SAVED_CONTROL]
    jne .failed
    pop r12
    clc
    ret
.failed:
    pop r12
    stc
    ret

; Prove that the prepared, disabled message image is still intact.
kpci_msi_verify_programmed:
    push r12
    mov r12, rdi
    mov edi, [r12 + KPCI_MSI_OWNER_BDF]
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 2
    mov edx, 2
    call kpci_cfg_read
    jc .failed
    cmp eax, [r12 + KPCI_MSI_OWNER_SAVED_CONTROL]
    jne .failed
    mov edi, [r12 + KPCI_MSI_OWNER_BDF]
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 4
    mov edx, 4
    call kpci_cfg_read
    jc .failed
    cmp eax, [r12 + KPCI_MSI_OWNER_MESSAGE_ADDR]
    jne .failed
    mov edi, [r12 + KPCI_MSI_OWNER_BDF]
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 8
    mov edx, 4
    call kpci_cfg_read
    jc .failed
    test eax, eax
    jnz .failed
    mov edi, [r12 + KPCI_MSI_OWNER_BDF]
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 12
    mov edx, 2
    call kpci_cfg_read
    jc .failed
    cmp eax, [r12 + KPCI_MSI_OWNER_VECTOR]
    jne .failed
    pop r12
    clc
    ret
.failed:
    pop r12
    stc
    ret

; Disable MSI and prove the complete saved control word was restored.
kpci_msi_disable:
    push r12
    mov r12, rdi
    mov edi, [r12 + KPCI_MSI_OWNER_BDF]
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 2
    mov edx, 2
    mov ecx, [r12 + KPCI_MSI_OWNER_SAVED_CONTROL]
    call kpci_cfg_write
    jc .failed
    mov edi, [r12 + KPCI_MSI_OWNER_BDF]
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 2
    mov edx, 2
    call kpci_cfg_read
    jc .failed
    cmp eax, [r12 + KPCI_MSI_OWNER_SAVED_CONTROL]
    jne .failed
    pop r12
    clc
    ret
.failed:
    pop r12
    stc
    ret

; RDI=zeroed owner, ESI=BDF, RDX=static ISR, ECX=physical APIC ID.
; Programs and verifies one disabled 64-bit MSI message, then publishes its
; permanent vector/gate. CF=0/EAX=vector; CF=1/EAX=0.
global kpci_msi_prepare
kpci_msi_prepare:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, KPCI_CONFIG_SPACE_BYTES
    mov r12, rdi
    mov r13d, esi
    mov r14, rdx
    mov r15d, ecx

    test r12, r12
    jz .input_invalid
    test r12, 3
    jnz .input_invalid
    mov rax, r12
    add rax, KPCI_MSI_OWNER_SIZE
    jc .input_invalid
    test r13d, 0xFFFF0000
    jnz .input_invalid
    test r14, r14
    jz .input_invalid
    cmp r15d, 0xFE
    ja .input_invalid

    KPCI_MSI_LOCK rbx, r12
    cmp dword [r12 + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_EMPTY
    jne .locked_reject
    mov dword [r12 + KPCI_MSI_OWNER_BDF], r13d
    mov dword [r12 + KPCI_MSI_OWNER_VECTOR], 0
    mov dword [r12 + KPCI_MSI_OWNER_DESTINATION], r15d
    mov dword [r12 + KPCI_MSI_OWNER_GATE_PUBLISHED], 0

    mov edi, r13d
    mov rsi, rsp
    call kpci_cfg_snapshot
    jc .prepare_failed
    cmp word [rsp], 0xFFFF
    je .prepare_failed
    mov rdi, rsp
    call kpci_msi_snapshot_cap
    jc .prepare_failed
    mov [r12 + KPCI_MSI_OWNER_CAP], eax
    movzx ecx, word [rsp + rax + 2]
    mov [r12 + KPCI_MSI_OWNER_SAVED_CONTROL], ecx
    mov ecx, [rsp + rax + 4]
    mov [r12 + KPCI_MSI_OWNER_SAVED_ADDR_LOW], ecx
    mov ecx, [rsp + rax + 8]
    mov [r12 + KPCI_MSI_OWNER_SAVED_ADDR_HIGH], ecx
    movzx ecx, word [rsp + rax + 12]
    mov [r12 + KPCI_MSI_OWNER_SAVED_DATA], ecx
    mov eax, r15d
    shl eax, 12
    or eax, 0xFEE00000
    mov [r12 + KPCI_MSI_OWNER_MESSAGE_ADDR], eax

    call vector_alloc
    cmp eax, 0x40
    jb .prepare_failed
    cmp eax, 0xEF
    ja .prepare_failed
    mov [r12 + KPCI_MSI_OWNER_VECTOR], eax

    mov edi, r13d
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 2
    mov edx, 2
    mov ecx, [r12 + KPCI_MSI_OWNER_SAVED_CONTROL]
    call kpci_cfg_write
    jc .program_failed
    mov edi, r13d
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 4
    mov edx, 4
    mov ecx, [r12 + KPCI_MSI_OWNER_MESSAGE_ADDR]
    call kpci_cfg_write
    jc .program_failed
    mov edi, r13d
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 8
    mov edx, 4
    xor ecx, ecx
    call kpci_cfg_write
    jc .program_failed
    mov edi, r13d
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 12
    mov edx, 2
    mov ecx, [r12 + KPCI_MSI_OWNER_VECTOR]
    call kpci_cfg_write
    jc .program_failed
    mov rdi, r12
    call kpci_msi_verify_programmed
    jc .program_failed

    mov edi, [r12 + KPCI_MSI_OWNER_VECTOR]
    mov rsi, r14
    xor edx, edx
    call register_idt_handler
    mov dword [r12 + KPCI_MSI_OWNER_GATE_PUBLISHED], 1
    mov dword [r12 + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_PREPARED
    KPCI_MSI_UNLOCK r12, rbx
    mov eax, [r12 + KPCI_MSI_OWNER_VECTOR]
    add rsp, KPCI_CONFIG_SPACE_BYTES
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    clc
    ret

.program_failed:
    mov rdi, r12
    call kpci_msi_disable
    jc .prepare_failed
    mov rdi, r12
    call kpci_msi_restore_fields
    jc .prepare_failed
    mov edi, [r12 + KPCI_MSI_OWNER_VECTOR]
    call vector_free
    mov dword [r12 + KPCI_MSI_OWNER_VECTOR], 0
.prepare_failed:
    mov dword [r12 + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_FAILED
.locked_reject:
    KPCI_MSI_UNLOCK r12, rbx
.input_invalid:
    add rsp, KPCI_CONFIG_SPACE_BYTES
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    xor eax, eax
    stc
    ret

; RDI=prepared owner. Caller has already validated its device and enabled only
; the PCI Command bits required for delivery. MSI Enable is written last.
global kpci_msi_arm
kpci_msi_arm:
    push rbx
    push r12
    push r13
    mov r12, rdi
    test r12, r12
    jz .input_invalid
    test r12, 3
    jnz .input_invalid
    KPCI_MSI_LOCK rbx, r12
    cmp dword [r12 + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_PREPARED
    jne .locked_failed
    mov rdi, r12
    call kpci_msi_verify_programmed
    jc .contain
    mov edi, [r12 + KPCI_MSI_OWNER_BDF]
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 2
    mov edx, 2
    mov ecx, [r12 + KPCI_MSI_OWNER_SAVED_CONTROL]
    or ecx, KPCI_MSI_ENABLE
    call kpci_cfg_write
    jc .contain
    mov edi, [r12 + KPCI_MSI_OWNER_BDF]
    mov esi, [r12 + KPCI_MSI_OWNER_CAP]
    add esi, 2
    mov edx, 2
    call kpci_cfg_read
    jc .contain
    mov ecx, [r12 + KPCI_MSI_OWNER_SAVED_CONTROL]
    or ecx, KPCI_MSI_ENABLE
    cmp eax, ecx
    jne .contain
    mov dword [r12 + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_ARMED
    KPCI_MSI_UNLOCK r12, rbx
    pop r13
    pop r12
    pop rbx
    mov eax, 1
    clc
    ret
.contain:
    mov rdi, r12
    call kpci_msi_disable
    jc .contain_failed
    mov dword [r12 + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_QUIESCED
    jmp .locked_failed
.contain_failed:
    mov dword [r12 + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_FAILED
.locked_failed:
    KPCI_MSI_UNLOCK r12, rbx
.input_invalid:
    pop r13
    pop r12
    pop rbx
    xor eax, eax
    stc
    ret

; RDI=armed owner. Device-specific source containment remains caller-owned.
global kpci_msi_quiesce
kpci_msi_quiesce:
    push rbx
    push r12
    push r13
    mov r12, rdi
    test r12, r12
    jz .input_invalid
    test r12, 3
    jnz .input_invalid
    KPCI_MSI_LOCK rbx, r12
    cmp dword [r12 + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_ARMED
    jne .locked_failed
    mov rdi, r12
    call kpci_msi_disable
    jc .disable_failed
    mov dword [r12 + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_QUIESCED
    KPCI_MSI_UNLOCK r12, rbx
    pop r13
    pop r12
    pop rbx
    mov eax, 1
    clc
    ret
.disable_failed:
    mov dword [r12 + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_FAILED
.locked_failed:
    KPCI_MSI_UNLOCK r12, rbx
.input_invalid:
    pop r13
    pop r12
    pop rbx
    xor eax, eax
    stc
    ret

; RDI=prepared/quiesced owner (FAILED is retryable only after vector publish).
; Restores the exact firmware-owned message image; the vector/gate is retained.
global kpci_msi_restore
kpci_msi_restore:
    push rbx
    push r12
    push r13
    mov r12, rdi
    test r12, r12
    jz .input_invalid
    test r12, 3
    jnz .input_invalid
    KPCI_MSI_LOCK rbx, r12
    mov eax, [r12 + KPCI_MSI_OWNER_STATE]
    cmp eax, KPCI_MSI_STATE_RESTORED
    je .success
    cmp eax, KPCI_MSI_STATE_PREPARED
    je .restore
    cmp eax, KPCI_MSI_STATE_QUIESCED
    je .restore
    cmp eax, KPCI_MSI_STATE_FAILED
    jne .locked_failed
    mov eax, [r12 + KPCI_MSI_OWNER_VECTOR]
    cmp eax, 0x40
    jb .locked_failed
    cmp eax, 0xEF
    ja .locked_failed
.restore:
    ; Never rewrite message fields while delivery might still be enabled.
    mov rdi, r12
    call kpci_msi_disable
    jc .restore_failed
    mov rdi, r12
    call kpci_msi_restore_fields
    jc .restore_failed
    cmp dword [r12 + KPCI_MSI_OWNER_GATE_PUBLISHED], 0
    jne .restored
    mov edi, [r12 + KPCI_MSI_OWNER_VECTOR]
    call vector_free
    mov dword [r12 + KPCI_MSI_OWNER_VECTOR], 0
.restored:
    mov dword [r12 + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_RESTORED
.success:
    KPCI_MSI_UNLOCK r12, rbx
    pop r13
    pop r12
    pop rbx
    mov eax, 1
    clc
    ret
.restore_failed:
    mov rdi, r12
    call kpci_msi_disable
    mov dword [r12 + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_FAILED
.locked_failed:
    KPCI_MSI_UNLOCK r12, rbx
.input_invalid:
    pop r13
    pop r12
    pop rbx
    xor eax, eax
    stc
    ret

%unmacro KPCI_MSI_LOCK 2
%unmacro KPCI_MSI_UNLOCK 2

%endif ; KERNEL_ARCH_X86_64_PCI_MSI_ASM
