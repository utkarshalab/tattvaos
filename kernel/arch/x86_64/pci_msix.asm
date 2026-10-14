; =============================================================================
; Tattva OS — strict one-vector MSI-X ownership
; =============================================================================
; Owns entry zero only. Device-specific code remains responsible for BAR
; sizing/mapping, PCI Command, source masking/acknowledgement, and keeping the
; table mapped until restore completes.

%ifndef KERNEL_ARCH_X86_64_PCI_MSIX_ASM
%define KERNEL_ARCH_X86_64_PCI_MSIX_ASM

[BITS 64]

KPCI_CAP_ID_MSIX                 equ 0x11
KPCI_MSIX_ENABLE                 equ 1 << 15
KPCI_MSIX_FUNCTION_MASK          equ 1 << 14
KPCI_MSIX_RESERVED_MASK          equ 0x3800
KPCI_MSIX_TABLE_SIZE_MASK        equ 0x07FF
KPCI_MSIX_VECTOR_MASK            equ 1

KPCI_MSIX_LAYOUT_CAP             equ 0
KPCI_MSIX_LAYOUT_CONTROL         equ 4
KPCI_MSIX_LAYOUT_COUNT           equ 8
KPCI_MSIX_LAYOUT_TABLE_BIR       equ 12
KPCI_MSIX_LAYOUT_TABLE_OFFSET    equ 16
KPCI_MSIX_LAYOUT_TABLE_BYTES     equ 20
KPCI_MSIX_LAYOUT_PBA_BIR         equ 24
KPCI_MSIX_LAYOUT_PBA_OFFSET      equ 28
KPCI_MSIX_LAYOUT_PBA_BYTES       equ 32
KPCI_MSIX_LAYOUT_SIZE            equ 36

KPCI_MSIX_OWNER_LOCK             equ 0
KPCI_MSIX_OWNER_STATE            equ 4
KPCI_MSIX_OWNER_BDF              equ 8
KPCI_MSIX_OWNER_CAP              equ 12
KPCI_MSIX_OWNER_VECTOR           equ 16
KPCI_MSIX_OWNER_DESTINATION      equ 20
KPCI_MSIX_OWNER_GATE_PUBLISHED   equ 24
KPCI_MSIX_OWNER_SAVED_CONTROL    equ 28
KPCI_MSIX_OWNER_TABLE            equ 32
KPCI_MSIX_OWNER_PBA              equ 40
KPCI_MSIX_OWNER_SAVED_ADDR_LOW   equ 48
KPCI_MSIX_OWNER_SAVED_ADDR_HIGH  equ 52
KPCI_MSIX_OWNER_SAVED_DATA       equ 56
KPCI_MSIX_OWNER_SAVED_VECTOR_CTL equ 60
KPCI_MSIX_OWNER_MESSAGE_ADDR     equ 64
KPCI_MSIX_OWNER_SIZE             equ 72

KPCI_MSIX_STATE_EMPTY            equ 0
KPCI_MSIX_STATE_PREPARED         equ 1
KPCI_MSIX_STATE_ARMED            equ 2
KPCI_MSIX_STATE_QUIESCED         equ 3
KPCI_MSIX_STATE_RESTORED         equ 4
KPCI_MSIX_STATE_FAILED           equ 5

%ifdef KPCI_MSIX_TEST_LOCKS
; Native userspace tests cannot change IF.
%macro KPCI_MSIX_LOCK 2
    xor %1, %1
%%spin:
    mov eax, 1
    xchg eax, [%2 + KPCI_MSIX_OWNER_LOCK]
    test eax, eax
    jz %%held
    pause
    jmp %%spin
%%held:
%endmacro

%macro KPCI_MSIX_UNLOCK 2
    mov dword [%1 + KPCI_MSIX_OWNER_LOCK], 0
%endmacro
%else
%macro KPCI_MSIX_LOCK 2
    pushfq
    pop %1
    cli
%%spin:
    mov eax, 1
    xchg eax, [%2 + KPCI_MSIX_OWNER_LOCK]
    test eax, eax
    jz %%held
    pause
    jmp %%spin
%%held:
%endmacro

%macro KPCI_MSIX_UNLOCK 2
    mov dword [%1 + KPCI_MSIX_OWNER_LOCK], 0
    push %2
    popfq
%endmacro
%endif

section .text

; RDI=256-byte PCI configuration snapshot, RSI=layout output.
; The first proven envelope requires table and PBA in one standard BAR.
global kpci_msix_snapshot_layout
kpci_msix_snapshot_layout:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .invalid
    test r12, r12
    jz .invalid
    test r12, 3
    jnz .invalid
    mov rax, r12
    add rax, KPCI_MSIX_LAYOUT_SIZE
    jc .invalid

    mov rdi, rbx
    mov esi, KPCI_CONFIG_SPACE_BYTES
    mov edx, KPCI_CAP_ID_MSIX
    call kpci_find_capability_snapshot
    jc .invalid
    test eax, eax
    jz .invalid
    mov r13d, eax
    mov ecx, eax
    add ecx, 12
    jc .invalid
    cmp ecx, KPCI_CONFIG_SPACE_BYTES
    ja .invalid
    cmp byte [rbx + r13], KPCI_CAP_ID_MSIX
    jne .invalid
    movzx eax, word [rbx + r13 + 2]
    test eax, KPCI_MSIX_ENABLE | KPCI_MSIX_RESERVED_MASK
    jnz .invalid

    ; MSI and MSI-X must not be enabled at the same time.
    mov rdi, rbx
    mov esi, KPCI_CONFIG_SPACE_BYTES
    mov edx, KPCI_CAP_ID_MSI
    call kpci_find_capability_snapshot
    jc .invalid
    test eax, eax
    jz .msi_disabled
    mov ecx, eax
    add ecx, 4
    jc .invalid
    cmp ecx, KPCI_CONFIG_SPACE_BYTES
    ja .invalid
    test word [rbx + rax + 2], KPCI_MSI_ENABLE
    jnz .invalid
.msi_disabled:
    movzx eax, word [rbx + r13 + 2]
    mov [r12 + KPCI_MSIX_LAYOUT_CONTROL], eax
    and eax, KPCI_MSIX_TABLE_SIZE_MASK
    inc eax
    cmp eax, 2048
    ja .invalid
    mov [r12 + KPCI_MSIX_LAYOUT_COUNT], eax

    mov ecx, [rbx + r13 + 4]
    mov edx, ecx
    and edx, 7
    cmp edx, 5
    ja .invalid
    mov [r12 + KPCI_MSIX_LAYOUT_TABLE_BIR], edx
    and ecx, 0xFFFFFFF8
    mov [r12 + KPCI_MSIX_LAYOUT_TABLE_OFFSET], ecx
    mov ecx, eax
    shl ecx, 4
    mov [r12 + KPCI_MSIX_LAYOUT_TABLE_BYTES], ecx

    mov ecx, [rbx + r13 + 8]
    mov edx, ecx
    and edx, 7
    cmp edx, 5
    ja .invalid
    cmp edx, [r12 + KPCI_MSIX_LAYOUT_TABLE_BIR]
    jne .invalid
    mov [r12 + KPCI_MSIX_LAYOUT_PBA_BIR], edx
    and ecx, 0xFFFFFFF8
    mov [r12 + KPCI_MSIX_LAYOUT_PBA_OFFSET], ecx
    add eax, 63
    shr eax, 6
    shl eax, 3
    mov [r12 + KPCI_MSIX_LAYOUT_PBA_BYTES], eax
    mov [r12 + KPCI_MSIX_LAYOUT_CAP], r13d

    mov eax, r13d
    pop r13
    pop r12
    pop rbx
    clc
    ret
.invalid:
    pop r13
    pop r12
    pop rbx
    xor eax, eax
    stc
    ret

; RDI=validated layout, RSI=size of its referenced BAR.
; Proves the complete advertised table and PBA footprints are in-bounds and
; non-overlapping. CF=0/EAX=1; CF=1/EAX=0.
global kpci_msix_validate_layout
kpci_msix_validate_layout:
    test rdi, rdi
    jz .invalid
    test rdi, 3
    jnz .invalid
    test rsi, rsi
    jz .invalid
    mov eax, [rdi + KPCI_MSIX_LAYOUT_COUNT]
    test eax, eax
    jz .invalid
    cmp eax, 2048
    ja .invalid
    mov ecx, eax
    shl ecx, 4
    cmp ecx, [rdi + KPCI_MSIX_LAYOUT_TABLE_BYTES]
    jne .invalid
    add eax, 63
    shr eax, 6
    shl eax, 3
    cmp eax, [rdi + KPCI_MSIX_LAYOUT_PBA_BYTES]
    jne .invalid
    mov eax, [rdi + KPCI_MSIX_LAYOUT_TABLE_BIR]
    cmp eax, 5
    ja .invalid
    cmp eax, [rdi + KPCI_MSIX_LAYOUT_PBA_BIR]
    jne .invalid

    mov eax, [rdi + KPCI_MSIX_LAYOUT_TABLE_OFFSET]
    test eax, 7
    jnz .invalid
    cmp rax, rsi
    ja .invalid
    mov edx, [rdi + KPCI_MSIX_LAYOUT_TABLE_BYTES]
    mov rcx, rsi
    sub rcx, rax
    cmp rdx, rcx
    ja .invalid
    add rdx, rax                    ; table end

    mov eax, [rdi + KPCI_MSIX_LAYOUT_PBA_OFFSET]
    test eax, 7
    jnz .invalid
    cmp rax, rsi
    ja .invalid
    mov r8d, [rdi + KPCI_MSIX_LAYOUT_PBA_BYTES]
    mov rcx, rsi
    sub rcx, rax
    cmp r8, rcx
    ja .invalid
    add r8, rax                     ; PBA end

    ; [table_offset, table_end) and [pba_offset, pba_end) must not overlap.
    cmp rdx, rax
    jbe .valid
    mov ecx, [rdi + KPCI_MSIX_LAYOUT_TABLE_OFFSET]
    cmp rcx, r8
    jb .invalid
.valid:
    mov eax, 1
    clc
    ret
.invalid:
    xor eax, eax
    stc
    ret

; RDI=owner, ECX=complete MSI-X Message Control value.
kpci_msix_write_control:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13d, ecx
    mov edi, [r12 + KPCI_MSIX_OWNER_BDF]
    mov esi, [r12 + KPCI_MSIX_OWNER_CAP]
    add esi, 2
    mov edx, 2
    call kpci_cfg_write
    jc .failed
    mov edi, [r12 + KPCI_MSIX_OWNER_BDF]
    mov esi, [r12 + KPCI_MSIX_OWNER_CAP]
    add esi, 2
    mov edx, 2
    call kpci_cfg_read
    jc .failed
    cmp eax, r13d
    jne .failed
    pop r14
    pop r13
    pop r12
    clc
    ret
.failed:
    pop r14
    pop r13
    pop r12
    stc
    ret

; RDI=owner. Mask entry zero and verify its complete Vector Control dword.
kpci_msix_mask_entry:
    mov rdx, [rdi + KPCI_MSIX_OWNER_TABLE]
    mov eax, [rdx + 12]
    or eax, KPCI_MSIX_VECTOR_MASK
    mov [rdx + 12], eax
    mfence
    cmp eax, [rdx + 12]
    jne .failed
    clc
    ret
.failed:
    stc
    ret

; RDI=owner. Entry zero's pending bit must be clear.
kpci_msix_pba_clear:
    mfence
    mov rax, [rdi + KPCI_MSIX_OWNER_PBA]
    test dword [rax], 1
    jnz .failed
    clc
    ret
.failed:
    stc
    ret

; RDI=owner. Verify the prepared payload and mask without changing hardware.
kpci_msix_verify_programmed:
    mov rdx, [rdi + KPCI_MSIX_OWNER_TABLE]
    mov eax, [rdi + KPCI_MSIX_OWNER_MESSAGE_ADDR]
    cmp eax, [rdx]
    jne .failed
    cmp dword [rdx + 4], 0
    jne .failed
    mov eax, [rdi + KPCI_MSIX_OWNER_VECTOR]
    cmp eax, [rdx + 8]
    jne .failed
    mov eax, [rdi + KPCI_MSIX_OWNER_SAVED_VECTOR_CTL]
    or eax, KPCI_MSIX_VECTOR_MASK
    cmp eax, [rdx + 12]
    jne .failed
    jmp kpci_msix_pba_clear
.failed:
    stc
    ret

; RDI=owner. Best-effort Function Mask, entry mask, then proven disable.
; The caller has already masked the device-specific interrupt source.
kpci_msix_contain:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov edi, [r12 + KPCI_MSIX_OWNER_BDF]
    mov esi, [r12 + KPCI_MSIX_OWNER_CAP]
    add esi, 2
    mov edx, 2
    call kpci_cfg_read
    jc .use_saved
    mov ecx, eax
    or ecx, KPCI_MSIX_FUNCTION_MASK
    jmp .mask_function
.use_saved:
    mov ecx, [r12 + KPCI_MSIX_OWNER_SAVED_CONTROL]
    or ecx, KPCI_MSIX_FUNCTION_MASK
.mask_function:
    mov rdi, r12
    call kpci_msix_write_control

    xor r13d, r13d
    mov rdi, r12
    call kpci_msix_mask_entry
    jc .disable
    mov r13d, 1
.disable:
    mov ecx, [r12 + KPCI_MSIX_OWNER_SAVED_CONTROL]
    and ecx, ~KPCI_MSIX_ENABLE
    or ecx, KPCI_MSIX_FUNCTION_MASK
    mov rdi, r12
    call kpci_msix_write_control
    jc .failed
    test r13d, r13d
    jz .failed
    pop r13
    pop r12
    pop rbx
    mov eax, 1
    clc
    ret
.failed:
    pop r13
    pop r12
    pop rbx
    xor eax, eax
    stc
    ret

; RDI=contained owner. Restore entry payload first and Vector Control last.
kpci_msix_restore_entry:
    mov rdx, [rdi + KPCI_MSIX_OWNER_TABLE]
    mov eax, [rdi + KPCI_MSIX_OWNER_SAVED_DATA]
    mov [rdx + 8], eax
    mfence
    cmp eax, [rdx + 8]
    jne .failed
    mov eax, [rdi + KPCI_MSIX_OWNER_SAVED_ADDR_HIGH]
    mov [rdx + 4], eax
    mfence
    cmp eax, [rdx + 4]
    jne .failed
    mov eax, [rdi + KPCI_MSIX_OWNER_SAVED_ADDR_LOW]
    mov [rdx], eax
    mfence
    cmp eax, [rdx]
    jne .failed
    mov eax, [rdi + KPCI_MSIX_OWNER_SAVED_VECTOR_CTL]
    mov [rdx + 12], eax
    mfence
    cmp eax, [rdx + 12]
    jne .failed
    clc
    ret
.failed:
    stc
    ret

; RDI=owner with complete recovery metadata.
kpci_msix_restore_exact:
    push r12
    mov r12, rdi
    call kpci_msix_contain
    jc .failed
    mov rdi, r12
    call kpci_msix_pba_clear
    jc .failed
    mov rdi, r12
    call kpci_msix_restore_entry
    jc .failed
    mov ecx, [r12 + KPCI_MSIX_OWNER_SAVED_CONTROL]
    mov rdi, r12
    call kpci_msix_write_control
    jc .failed
    pop r12
    clc
    ret
.failed:
    mov rdi, r12
    call kpci_msix_contain
    pop r12
    stc
    ret

; RDI=zeroed owner, ESI=BDF, RDX=entry-0 VA, RCX=PBA VA,
; R8=static ISR, R9D=physical APIC ID. Caller has validated BAR bounds.
global kpci_msix_prepare
kpci_msix_prepare:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, KPCI_CONFIG_SPACE_BYTES + 48
    mov r12, rdi
    mov r13d, esi
    mov r14, r8
    mov r15d, r9d
    test r12, r12
    jz .input_invalid
    test r12, 7
    jnz .input_invalid
    mov rax, r12
    add rax, KPCI_MSIX_OWNER_SIZE
    jc .input_invalid
    test r13d, 0xFFFF0000
    jnz .input_invalid
    test rdx, rdx
    jz .input_invalid
    test rdx, 3
    jnz .input_invalid
    test rcx, rcx
    jz .input_invalid
    test rcx, 3
    jnz .input_invalid
    test r14, r14
    jz .input_invalid
    cmp r15d, 0xFE
    ja .input_invalid

    KPCI_MSIX_LOCK rbx, r12
    cmp dword [r12 + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_EMPTY
    jne .locked_reject
    mov [r12 + KPCI_MSIX_OWNER_BDF], r13d
    mov dword [r12 + KPCI_MSIX_OWNER_VECTOR], 0
    mov [r12 + KPCI_MSIX_OWNER_DESTINATION], r15d
    mov dword [r12 + KPCI_MSIX_OWNER_GATE_PUBLISHED], 0
    mov [r12 + KPCI_MSIX_OWNER_TABLE], rdx
    mov [r12 + KPCI_MSIX_OWNER_PBA], rcx

    mov edi, r13d
    mov rsi, rsp
    call kpci_cfg_snapshot
    jc .clean_failure
    cmp word [rsp], 0xFFFF
    je .clean_failure
    mov rdi, rsp
    lea rsi, [rsp + KPCI_CONFIG_SPACE_BYTES]
    call kpci_msix_snapshot_layout
    jc .clean_failure
    mov [r12 + KPCI_MSIX_OWNER_CAP], eax
    mov ecx, [rsp + KPCI_CONFIG_SPACE_BYTES + KPCI_MSIX_LAYOUT_CONTROL]
    mov [r12 + KPCI_MSIX_OWNER_SAVED_CONTROL], ecx

    mov rdx, [r12 + KPCI_MSIX_OWNER_TABLE]
    mov eax, [rdx]
    mov [r12 + KPCI_MSIX_OWNER_SAVED_ADDR_LOW], eax
    mov eax, [rdx + 4]
    mov [r12 + KPCI_MSIX_OWNER_SAVED_ADDR_HIGH], eax
    mov eax, [rdx + 8]
    mov [r12 + KPCI_MSIX_OWNER_SAVED_DATA], eax
    mov eax, [rdx + 12]
    mov [r12 + KPCI_MSIX_OWNER_SAVED_VECTOR_CTL], eax
    mov rdi, r12
    call kpci_msix_pba_clear
    jc .clean_failure

    call vector_alloc
    cmp eax, 0x40
    jb .clean_failure
    cmp eax, 0xEF
    ja .clean_failure
    mov [r12 + KPCI_MSIX_OWNER_VECTOR], eax
    mov ecx, r15d
    shl ecx, 12
    or ecx, 0xFEE00000
    mov [r12 + KPCI_MSIX_OWNER_MESSAGE_ADDR], ecx
    mov dword [r12 + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_FAILED

    mov ecx, [r12 + KPCI_MSIX_OWNER_SAVED_CONTROL]
    or ecx, KPCI_MSIX_FUNCTION_MASK
    mov rdi, r12
    call kpci_msix_write_control
    jc .rollback
    mov rdi, r12
    call kpci_msix_mask_entry
    jc .rollback

    mov rdx, [r12 + KPCI_MSIX_OWNER_TABLE]
    mov eax, [r12 + KPCI_MSIX_OWNER_MESSAGE_ADDR]
    mov [rdx], eax
    mov dword [rdx + 4], 0
    mov eax, [r12 + KPCI_MSIX_OWNER_VECTOR]
    mov [rdx + 8], eax
    mfence
    mov rdi, r12
    call kpci_msix_verify_programmed
    jc .rollback

    mov edi, [r12 + KPCI_MSIX_OWNER_VECTOR]
    mov rsi, r14
    xor edx, edx
    call register_idt_handler
    mov dword [r12 + KPCI_MSIX_OWNER_GATE_PUBLISHED], 1
    mov dword [r12 + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_PREPARED
    mov eax, [r12 + KPCI_MSIX_OWNER_VECTOR]
    KPCI_MSIX_UNLOCK r12, rbx
    add rsp, KPCI_CONFIG_SPACE_BYTES + 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    clc
    ret

.rollback:
    mov rdi, r12
    call kpci_msix_restore_exact
    jc .rollback_failed
    cmp dword [r12 + KPCI_MSIX_OWNER_GATE_PUBLISHED], 0
    jne .rollback_restored
    mov edi, [r12 + KPCI_MSIX_OWNER_VECTOR]
    call vector_free
    mov dword [r12 + KPCI_MSIX_OWNER_VECTOR], 0
.rollback_restored:
    mov dword [r12 + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_RESTORED
    jmp .locked_reject
.rollback_failed:
    mov dword [r12 + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_FAILED
    jmp .locked_reject
.clean_failure:
    mov dword [r12 + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_EMPTY
.locked_reject:
    KPCI_MSIX_UNLOCK r12, rbx
.input_invalid:
    add rsp, KPCI_CONFIG_SPACE_BYTES + 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    xor eax, eax
    stc
    ret

; RDI=prepared owner. Device source remains masked until this returns.
global kpci_msix_arm
kpci_msix_arm:
    push rbx
    push r12
    push r13
    mov r12, rdi
    test r12, r12
    jz .input_invalid
    test r12, 7
    jnz .input_invalid
    KPCI_MSIX_LOCK rbx, r12
    cmp dword [r12 + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_PREPARED
    jne .locked_failed
    mov rdi, r12
    call kpci_msix_verify_programmed
    jc .contain
    mov ecx, [r12 + KPCI_MSIX_OWNER_SAVED_CONTROL]
    or ecx, KPCI_MSIX_ENABLE | KPCI_MSIX_FUNCTION_MASK
    mov rdi, r12
    call kpci_msix_write_control
    jc .contain

    mov rdx, [r12 + KPCI_MSIX_OWNER_TABLE]
    mov eax, [r12 + KPCI_MSIX_OWNER_SAVED_VECTOR_CTL]
    and eax, ~KPCI_MSIX_VECTOR_MASK
    mov [rdx + 12], eax
    mfence
    cmp eax, [rdx + 12]
    jne .contain
    mov rdi, r12
    call kpci_msix_pba_clear
    jc .contain

    mov ecx, [r12 + KPCI_MSIX_OWNER_SAVED_CONTROL]
    or ecx, KPCI_MSIX_ENABLE
    and ecx, ~KPCI_MSIX_FUNCTION_MASK
    mov rdi, r12
    call kpci_msix_write_control
    jc .contain
    mov rdi, r12
    call kpci_msix_pba_clear
    jc .contain
    mov dword [r12 + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_ARMED
    KPCI_MSIX_UNLOCK r12, rbx
    pop r13
    pop r12
    pop rbx
    mov eax, 1
    clc
    ret
.contain:
    mov rdi, r12
    call kpci_msix_contain
    jc .contain_failed
    mov dword [r12 + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_QUIESCED
    jmp .locked_failed
.contain_failed:
    mov dword [r12 + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_FAILED
.locked_failed:
    KPCI_MSIX_UNLOCK r12, rbx
.input_invalid:
    pop r13
    pop r12
    pop rbx
    xor eax, eax
    stc
    ret

; RDI=armed owner. Caller has already masked and acknowledged the source.
global kpci_msix_quiesce
kpci_msix_quiesce:
    push rbx
    push r12
    push r13
    mov r12, rdi
    test r12, r12
    jz .input_invalid
    test r12, 7
    jnz .input_invalid
    KPCI_MSIX_LOCK rbx, r12
    cmp dword [r12 + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_ARMED
    jne .locked_failed
    mov rdi, r12
    call kpci_msix_contain
    jc .failed
    mov dword [r12 + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_QUIESCED
    KPCI_MSIX_UNLOCK r12, rbx
    pop r13
    pop r12
    pop rbx
    mov eax, 1
    clc
    ret
.failed:
    mov dword [r12 + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_FAILED
.locked_failed:
    KPCI_MSIX_UNLOCK r12, rbx
.input_invalid:
    pop r13
    pop r12
    pop rbx
    xor eax, eax
    stc
    ret

; RDI=prepared/quiesced/failed owner. ARMED must be quiesced by its driver.
global kpci_msix_restore
kpci_msix_restore:
    push rbx
    push r12
    push r13
    mov r12, rdi
    test r12, r12
    jz .input_invalid
    test r12, 7
    jnz .input_invalid
    KPCI_MSIX_LOCK rbx, r12
    mov eax, [r12 + KPCI_MSIX_OWNER_STATE]
    cmp eax, KPCI_MSIX_STATE_RESTORED
    je .success
    cmp eax, KPCI_MSIX_STATE_PREPARED
    je .restore
    cmp eax, KPCI_MSIX_STATE_QUIESCED
    je .restore
    cmp eax, KPCI_MSIX_STATE_FAILED
    jne .locked_failed
    mov eax, [r12 + KPCI_MSIX_OWNER_VECTOR]
    cmp eax, 0x40
    jb .locked_failed
    cmp eax, 0xEF
    ja .locked_failed
.restore:
    mov rdi, r12
    call kpci_msix_restore_exact
    jc .restore_failed
    cmp dword [r12 + KPCI_MSIX_OWNER_GATE_PUBLISHED], 0
    jne .restored
    mov edi, [r12 + KPCI_MSIX_OWNER_VECTOR]
    call vector_free
    mov dword [r12 + KPCI_MSIX_OWNER_VECTOR], 0
.restored:
    mov dword [r12 + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_RESTORED
.success:
    KPCI_MSIX_UNLOCK r12, rbx
    pop r13
    pop r12
    pop rbx
    mov eax, 1
    clc
    ret
.restore_failed:
    mov dword [r12 + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_FAILED
.locked_failed:
    KPCI_MSIX_UNLOCK r12, rbx
.input_invalid:
    pop r13
    pop r12
    pop rbx
    xor eax, eax
    stc
    ret

%unmacro KPCI_MSIX_LOCK 2
%unmacro KPCI_MSIX_UNLOCK 2

%endif ; KERNEL_ARCH_X86_64_PCI_MSIX_ASM
