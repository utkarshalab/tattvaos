[BITS 64]

KPCI_CONFIG_SPACE_BYTES equ 256
KPCI_CAP_ID_MSI         equ 0x05
KPCI_MSI_ENABLE         equ 1
%define KPCI_MSIX_TEST_LOCKS 1
%include "kernel/arch/x86_64/pci_msix.asm"

section .text
global _start
_start:
    ; Per-entry masking addresses only the selected entry and preserves bits.
    lea rdi, [rel mask_test_table]
    mov esi, 3
    mov edx, 1
    mov ecx, 1
    call kpci_msix_set_entry_mask
    jc fail_entry_mask
    cmp dword [rel mask_test_table + 28], 0xA5
    jne fail_entry_mask
    cmp dword [rel mask_test_table + 12], 0x10
    jne fail_entry_mask
    lea rdi, [rel mask_test_table]
    mov ecx, 0
    call kpci_msix_set_entry_mask
    jc fail_entry_mask
    cmp dword [rel mask_test_table + 28], 0xA4
    jne fail_entry_mask
    lea rdi, [rel mask_test_table]
    mov edx, 3
    call kpci_msix_set_entry_mask
    jnc fail_entry_mask
    lea rdi, [rel mask_test_table]
    mov edx, 1
    mov ecx, 2
    call kpci_msix_set_entry_mask
    jnc fail_entry_mask

    ; A failed Function-Mask write must retain recovery ownership and must not
    ; restore payload fields until containment can be proven.
    call reset_fixture
    mov dword [rel mock_fail_control], 1
    call prepare_owner
    jnc fail_prepare_containment
    cmp dword [rel test_owner + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_FAILED
    jne fail_prepare_containment
    cmp dword [rel test_owner + KPCI_MSIX_OWNER_VECTOR], 0x40
    jne fail_prepare_containment
    cmp dword [rel test_owner + KPCI_MSIX_OWNER_GATE_PUBLISHED], 0
    jne fail_prepare_containment
    cmp dword [rel mock_vector_free_count], 0
    jne fail_prepare_containment
    cmp dword [rel test_table], 0x11111111
    jne fail_prepare_containment
    cmp dword [rel test_table + 4], 0x22222222
    jne fail_prepare_containment
    cmp dword [rel test_table + 8], 0x33333333
    jne fail_prepare_containment
    cmp dword [rel test_table + 12], 0x11
    jne fail_prepare_containment
    cmp dword [rel mock_control_attempts], 5
    jne fail_prepare_containment

    lea rdi, [rel test_owner]
    call kpci_msix_restore
    jnc fail_restore_containment
    cmp dword [rel test_owner + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_FAILED
    jne fail_restore_containment
    cmp dword [rel test_owner + KPCI_MSIX_OWNER_VECTOR], 0x40
    jne fail_restore_containment
    cmp dword [rel mock_vector_free_count], 0
    jne fail_restore_containment
    cmp dword [rel test_table], 0x11111111
    jne fail_restore_containment
    cmp dword [rel test_table + 4], 0x22222222
    jne fail_restore_containment
    cmp dword [rel test_table + 8], 0x33333333
    jne fail_restore_containment
    cmp dword [rel mock_control_attempts], 9
    jne fail_restore_containment

    mov dword [rel mock_fail_control], 0
    lea rdi, [rel test_owner]
    call kpci_msix_restore
    jc fail_restore_retry
    cmp dword [rel test_owner + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_RESTORED
    jne fail_restore_retry
    cmp dword [rel test_owner + KPCI_MSIX_OWNER_VECTOR], 0
    jne fail_restore_retry
    cmp dword [rel mock_vector_free_count], 1
    jne fail_restore_retry
    call assert_original_image
    jc fail_restore_retry

    ; Once a gate is published, a failed quiesce/restore retains the vector and
    ; programmed payload until a later retry proves global disable.
    call reset_fixture
    call prepare_owner
    jc fail_happy_prepare
    cmp dword [rel mock_gate_count], 1
    jne fail_happy_prepare
    lea rdi, [rel test_owner]
    call kpci_msix_arm
    jc fail_happy_arm
    cmp dword [rel test_owner + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_ARMED
    jne fail_happy_arm
    cmp dword [rel mock_control], 0x8004
    jne fail_happy_arm
    cmp dword [rel test_table], 0xFEE02000
    jne fail_happy_arm
    cmp dword [rel test_table + 4], 0
    jne fail_happy_arm
    cmp dword [rel test_table + 8], 0x40
    jne fail_happy_arm
    cmp dword [rel test_table + 12], 0x10
    jne fail_happy_arm

    mov dword [rel mock_fail_control], 1
    lea rdi, [rel test_owner]
    call kpci_msix_quiesce
    jnc fail_quiesce_containment
    cmp dword [rel test_owner + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_FAILED
    jne fail_quiesce_containment
    cmp dword [rel test_table], 0xFEE02000
    jne fail_quiesce_containment
    cmp dword [rel test_table + 8], 0x40
    jne fail_quiesce_containment
    cmp dword [rel test_table + 12], 0x11
    jne fail_quiesce_containment
    cmp dword [rel mock_vector_free_count], 0
    jne fail_quiesce_containment

    lea rdi, [rel test_owner]
    call kpci_msix_restore
    jnc fail_published_restore
    cmp dword [rel test_table], 0xFEE02000
    jne fail_published_restore
    cmp dword [rel test_table + 8], 0x40
    jne fail_published_restore
    cmp dword [rel mock_vector_free_count], 0
    jne fail_published_restore
    mov dword [rel mock_fail_control], 0
    lea rdi, [rel test_owner]
    call kpci_msix_restore
    jc fail_published_restore
    cmp dword [rel test_owner + KPCI_MSIX_OWNER_VECTOR], 0x40
    jne fail_published_restore
    cmp dword [rel mock_vector_free_count], 0
    jne fail_published_restore
    call assert_original_image
    jc fail_published_restore

    ; Complete successful lifecycle, including pending-bit containment.
    call reset_fixture
    call prepare_owner
    jc fail_happy_lifecycle
    mov dword [rel test_pba], 1
    lea rdi, [rel test_owner]
    call kpci_msix_arm
    jnc fail_pending
    cmp dword [rel test_owner + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_QUIESCED
    jne fail_pending
    test dword [rel mock_control], KPCI_MSIX_ENABLE
    jnz fail_pending
    test dword [rel mock_control], KPCI_MSIX_FUNCTION_MASK
    jz fail_pending
    lea rdi, [rel test_owner]
    call kpci_msix_restore
    jnc fail_pending
    cmp dword [rel test_owner + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_FAILED
    jne fail_pending
    cmp dword [rel test_owner + KPCI_MSIX_OWNER_VECTOR], 0x40
    jne fail_pending
    cmp dword [rel test_table], 0xFEE02000
    jne fail_pending
    mov dword [rel test_pba], 0
    lea rdi, [rel test_owner]
    call kpci_msix_restore
    jc fail_pending

    call reset_fixture
    call prepare_owner
    jc fail_happy_lifecycle
    lea rdi, [rel test_owner]
    call kpci_msix_arm
    jc fail_happy_lifecycle
    lea rdi, [rel test_owner]
    call kpci_msix_quiesce
    jc fail_happy_lifecycle
    cmp dword [rel test_owner + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_QUIESCED
    jne fail_happy_lifecycle
    cmp dword [rel mock_control], 0x4004
    jne fail_happy_lifecycle
    cmp dword [rel test_table + 12], 0x11
    jne fail_happy_lifecycle
    lea rdi, [rel test_owner]
    call kpci_msix_restore
    jc fail_happy_lifecycle
    cmp dword [rel test_owner + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_RESTORED
    jne fail_happy_lifecycle
    cmp dword [rel test_owner + KPCI_MSIX_OWNER_VECTOR], 0x40
    jne fail_happy_lifecycle
    call assert_original_image
    jc fail_happy_lifecycle

    xor edi, edi
    jmp exit

fail_prepare_containment: mov edi, 1
                          jmp exit
fail_restore_containment: mov edi, 2
                          jmp exit
fail_restore_retry:       mov edi, 3
                          jmp exit
fail_happy_prepare:       mov edi, 4
                          jmp exit
fail_happy_arm:           mov edi, 5
                          jmp exit
fail_quiesce_containment: mov edi, 6
                          jmp exit
fail_published_restore:   mov edi, 7
                          jmp exit
fail_pending:             mov edi, 8
                          jmp exit
fail_happy_lifecycle:     mov edi, 9
                          jmp exit
fail_entry_mask:          mov edi, 10

exit:
    mov eax, 60
    syscall

prepare_owner:
    lea rdi, [rel test_owner]
    mov esi, 0x0008
    lea rdx, [rel test_table]
    lea rcx, [rel test_pba]
    lea r8, [rel mock_isr]
    mov r9d, 2
    jmp kpci_msix_prepare

assert_original_image:
    cmp dword [rel mock_control], 4
    jne .failed
    cmp dword [rel test_table], 0x11111111
    jne .failed
    cmp dword [rel test_table + 4], 0x22222222
    jne .failed
    cmp dword [rel test_table + 8], 0x33333333
    jne .failed
    cmp dword [rel test_table + 12], 0x10
    jne .failed
    clc
    ret
.failed:
    stc
    ret

reset_fixture:
    lea rdi, [rel test_owner]
    mov ecx, KPCI_MSIX_OWNER_SIZE / 8
    xor eax, eax
    rep stosq
    mov dword [rel mock_control], 4
    mov dword [rel mock_fail_control], 0
    mov dword [rel mock_control_attempts], 0
    mov dword [rel mock_vector_free_count], 0
    mov dword [rel mock_gate_count], 0
    mov dword [rel test_table], 0x11111111
    mov dword [rel test_table + 4], 0x22222222
    mov dword [rel test_table + 8], 0x33333333
    mov dword [rel test_table + 12], 0x10
    mov qword [rel test_pba], 0
    ret

kpci_find_capability_snapshot:
    cmp edx, KPCI_CAP_ID_MSIX
    je .msix
    cmp edx, KPCI_CAP_ID_MSI
    je .absent
    xor eax, eax
    stc
    ret
.msix:
    mov eax, 0x40
    clc
    ret
.absent:
    xor eax, eax
    clc
    ret

kpci_cfg_snapshot:
    mov r8, rsi
    mov rdi, rsi
    mov ecx, KPCI_CONFIG_SPACE_BYTES / 8
    xor eax, eax
    rep stosq
    mov dword [r8], 0x10D38086
    or word [r8 + 0x06], 1 << 4
    mov byte [r8 + 0x34], 0x40
    mov byte [r8 + 0x40], KPCI_CAP_ID_MSIX
    mov eax, [rel mock_control]
    mov [r8 + 0x42], ax
    mov dword [r8 + 0x44], 3
    mov dword [r8 + 0x48], 0x2003
    mov eax, 1
    clc
    ret

kpci_cfg_write:
    cmp esi, 0x42
    jne .failed
    cmp edx, 2
    jne .failed
    inc dword [rel mock_control_attempts]
    cmp dword [rel mock_fail_control], 0
    jne .failed
    movzx ecx, cx
    mov [rel mock_control], ecx
    mov eax, 1
    clc
    ret
.failed:
    xor eax, eax
    stc
    ret

kpci_cfg_read:
    cmp esi, 0x42
    jne .failed
    cmp edx, 2
    jne .failed
    mov eax, [rel mock_control]
    clc
    ret
.failed:
    mov eax, -1
    stc
    ret

vector_alloc:
    mov eax, 0x40
    ret

vector_free:
    inc dword [rel mock_vector_free_count]
    ret

register_idt_handler:
    inc dword [rel mock_gate_count]
    ret

mock_isr:
    ret

section .bss
alignb 16
test_owner:                resb KPCI_MSIX_OWNER_SIZE
test_table:                resd 4
alignb 8
test_pba:                  resq 1
mock_control:              resd 1
mock_fail_control:         resd 1
mock_control_attempts:     resd 1
mock_vector_free_count:    resd 1
mock_gate_count:           resd 1

section .data
align 16
mask_test_table:
    dd 0, 0, 0, 0x10
    dd 0, 0, 0, 0xA4
    dd 0, 0, 0, 0x32
