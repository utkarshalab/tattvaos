; Native failure-injection validation for the conventional MSI owner.
[BITS 64]
default rel

KPCI_CONFIG_SPACE_BYTES equ 256
%define KPCI_MSI_TEST_LOCKS 1
%include "kernel/arch/x86_64/pci_msi.asm"

section .text
global _start
_start:
    call reset_fixture
    mov dword [rel mock_fail_writes], 1
    lea rdi, [rel test_owner]
    mov esi, 0x0008
    lea rdx, [rel mock_isr]
    mov ecx, 1
    call kpci_msi_prepare
    jnc fail_retained
    cmp dword [rel test_owner + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_FAILED
    jne fail_retained
    cmp dword [rel test_owner + KPCI_MSI_OWNER_VECTOR], 0x40
    jne fail_retained
    cmp dword [rel test_owner + KPCI_MSI_OWNER_GATE_PUBLISHED], 0
    jne fail_retained
    cmp dword [rel mock_vector_free_count], 0
    jne fail_retained
    cmp dword [rel mock_control_write_count], 2
    jne fail_retained
    cmp dword [rel mock_addr_write_count], 0
    jne fail_retained
    cmp dword [rel mock_data_write_count], 0
    jne fail_retained

    lea rdi, [rel test_owner]
    call kpci_msi_restore
    jnc fail_retry
    cmp dword [rel test_owner + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_FAILED
    jne fail_retry
    cmp dword [rel test_owner + KPCI_MSI_OWNER_VECTOR], 0x40
    jne fail_retry
    cmp dword [rel mock_vector_free_count], 0
    jne fail_retry
    cmp dword [rel mock_control_write_count], 4
    jne fail_retry
    cmp dword [rel mock_addr_write_count], 0
    jne fail_retry
    cmp dword [rel mock_data_write_count], 0
    jne fail_retry

    mov dword [rel mock_fail_writes], 0
    lea rdi, [rel test_owner]
    call kpci_msi_restore
    jc fail_retry
    cmp dword [rel test_owner + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_RESTORED
    jne fail_retry
    cmp dword [rel test_owner + KPCI_MSI_OWNER_VECTOR], 0
    jne fail_retry
    cmp dword [rel mock_vector_free_count], 1
    jne fail_retry

    call reset_fixture
    lea rdi, [rel test_owner]
    mov esi, 0x0008
    lea rdx, [rel mock_isr]
    mov ecx, 2
    call kpci_msi_prepare
    jc fail_happy_prepare
    cmp eax, 0x40
    jne fail_happy_prepare
    cmp dword [rel test_owner + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_PREPARED
    jne fail_happy_prepare
    cmp dword [rel test_owner + KPCI_MSI_OWNER_GATE_PUBLISHED], 1
    jne fail_happy_prepare
    cmp dword [rel mock_gate_count], 1
    jne fail_happy_prepare

    lea rdi, [rel test_owner]
    call kpci_msi_arm
    jc fail_happy_arm
    cmp dword [rel test_owner + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_ARMED
    jne fail_happy_arm
    test dword [rel mock_control], KPCI_MSI_ENABLE
    jz fail_happy_arm

    lea rdi, [rel test_owner]
    call kpci_msi_quiesce
    jc fail_happy_quiesce
    cmp dword [rel test_owner + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_QUIESCED
    jne fail_happy_quiesce
    test dword [rel mock_control], KPCI_MSI_ENABLE
    jnz fail_happy_quiesce

    lea rdi, [rel test_owner]
    call kpci_msi_restore
    jc fail_happy_restore
    cmp dword [rel test_owner + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_RESTORED
    jne fail_happy_restore
    cmp dword [rel test_owner + KPCI_MSI_OWNER_VECTOR], 0x40
    jne fail_happy_restore
    cmp dword [rel mock_vector_free_count], 0
    jne fail_happy_restore
    cmp dword [rel mock_addr_low], 0x11111111
    jne fail_happy_restore
    cmp dword [rel mock_addr_high], 0x22222222
    jne fail_happy_restore
    cmp dword [rel mock_data], 0x33
    jne fail_happy_restore

    xor edi, edi
    jmp exit

fail_retained:       mov edi, 1
                     jmp exit
fail_retry:          mov edi, 2
                     jmp exit
fail_happy_prepare:  mov edi, 3
                     jmp exit
fail_happy_arm:      mov edi, 4
                     jmp exit
fail_happy_quiesce:  mov edi, 5
                     jmp exit
fail_happy_restore:  mov edi, 6

exit:
    mov eax, 60
    syscall

reset_fixture:
    lea rdi, [rel test_owner]
    mov ecx, KPCI_MSI_OWNER_SIZE / 8
    xor eax, eax
    rep stosq
    mov dword [rel mock_fail_writes], 0
    mov dword [rel mock_vector_free_count], 0
    mov dword [rel mock_gate_count], 0
    mov dword [rel mock_control_write_count], 0
    mov dword [rel mock_addr_write_count], 0
    mov dword [rel mock_data_write_count], 0
    mov dword [rel mock_control], KPCI_MSI_64BIT
    mov dword [rel mock_addr_low], 0x11111111
    mov dword [rel mock_addr_high], 0x22222222
    mov dword [rel mock_data], 0x33
    ret

; The snapshot parser itself is covered by pci_unit.asm.
kpci_find_capability_snapshot:
    mov eax, 0x40
    clc
    ret

kpci_cfg_snapshot:
    mov r8, rsi
    mov rdi, rsi
    mov ecx, KPCI_CONFIG_SPACE_BYTES / 8
    xor eax, eax
    rep stosq
    mov dword [r8], 0x12348086
    or word [r8 + 0x06], 1 << 4
    mov byte [r8 + 0x34], 0x40
    mov byte [r8 + 0x40], KPCI_CAP_ID_MSI
    mov eax, [rel mock_control]
    mov [r8 + 0x42], ax
    mov eax, [rel mock_addr_low]
    mov [r8 + 0x44], eax
    mov eax, [rel mock_addr_high]
    mov [r8 + 0x48], eax
    mov eax, [rel mock_data]
    mov [r8 + 0x4C], ax
    mov eax, 1
    clc
    ret

kpci_cfg_write:
    cmp esi, 0x42
    je .count_control
    cmp esi, 0x44
    je .count_addr
    cmp esi, 0x48
    je .count_addr
    cmp esi, 0x4C
    je .count_data
    jmp .counted
.count_control:
    inc dword [rel mock_control_write_count]
    jmp .counted
.count_addr:
    inc dword [rel mock_addr_write_count]
    jmp .counted
.count_data:
    inc dword [rel mock_data_write_count]
.counted:
    cmp dword [rel mock_fail_writes], 0
    jne .failed
    cmp esi, 0x42
    je .control
    cmp esi, 0x44
    je .addr_low
    cmp esi, 0x48
    je .addr_high
    cmp esi, 0x4C
    je .data
    jmp .failed
.control:
    movzx ecx, cx
    mov [rel mock_control], ecx
    jmp .done
.addr_low:
    mov [rel mock_addr_low], ecx
    jmp .done
.addr_high:
    mov [rel mock_addr_high], ecx
    jmp .done
.data:
    movzx ecx, cx
    mov [rel mock_data], ecx
.done:
    mov eax, 1
    clc
    ret
.failed:
    xor eax, eax
    stc
    ret

kpci_cfg_read:
    cmp esi, 0x42
    je .control
    cmp esi, 0x44
    je .addr_low
    cmp esi, 0x48
    je .addr_high
    cmp esi, 0x4C
    je .data
    xor eax, eax
    stc
    ret
.control:
    mov eax, [rel mock_control]
    jmp .done
.addr_low:
    mov eax, [rel mock_addr_low]
    jmp .done
.addr_high:
    mov eax, [rel mock_addr_high]
    jmp .done
.data:
    mov eax, [rel mock_data]
.done:
    clc
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
test_owner:                resb KPCI_MSI_OWNER_SIZE
mock_fail_writes:          resd 1
mock_vector_free_count:    resd 1
mock_gate_count:           resd 1
mock_control_write_count:  resd 1
mock_addr_write_count:     resd 1
mock_data_write_count:     resd 1
mock_control:              resd 1
mock_addr_low:             resd 1
mock_addr_high:            resd 1
mock_data:                 resd 1
