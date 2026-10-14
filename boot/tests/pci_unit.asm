; Native validation for kernel-owned PCI config composition and cap walking.
[BITS 64]
default rel

%include "kernel/arch/x86_64/pci.asm"

section .text
global _start
_start:
    mov edi, 0xABCD
    mov esi, 0x13
    mov edx, 1
    call kpci_cfg_compose
    jc fail_compose_byte
    cmp eax, 0x80ABCD10
    jne fail_compose_byte
    cmp ecx, KPCI_CONFIG_DATA_PORT + 3
    jne fail_compose_byte

    mov edi, 0xFFFF
    mov esi, 0xFE
    mov edx, 2
    call kpci_cfg_compose
    jc fail_compose_word
    cmp eax, 0x80FFFFFC
    jne fail_compose_word
    cmp ecx, KPCI_CONFIG_DATA_PORT + 2
    jne fail_compose_word

    xor edi, edi
    mov esi, 0xFC
    mov edx, 4
    call kpci_cfg_compose
    jc fail_compose_dword
    cmp eax, 0x800000FC
    jne fail_compose_dword
    cmp ecx, KPCI_CONFIG_DATA_PORT
    jne fail_compose_dword

    mov edi, 0x10000
    xor esi, esi
    mov edx, 4
    call kpci_cfg_compose
    jnc fail_compose_bdf

    xor edi, edi
    mov esi, 1
    mov edx, 2
    call kpci_cfg_compose
    jnc fail_compose_alignment
    mov esi, 2
    mov edx, 4
    call kpci_cfg_compose
    jnc fail_compose_alignment

    mov esi, 0xFF
    mov edx, 2
    call kpci_cfg_compose
    jnc fail_compose_span
    mov esi, 0xFD
    mov edx, 4
    call kpci_cfg_compose
    jnc fail_compose_span

    xor esi, esi
    mov edx, 3
    call kpci_cfg_compose
    jnc fail_compose_size

    ; A normal type-0 header can follow a non-monotonic but acyclic list.
    call reset_snapshot
    mov byte [rel config_snapshot + 0x34], 0x70
    mov byte [rel config_snapshot + 0x70], 0x01
    mov byte [rel config_snapshot + 0x71], 0x40
    mov byte [rel config_snapshot + 0x40], 0x05
    mov byte [rel config_snapshot + 0x41], 0
    mov edx, 0x05
    call parse_snapshot
    jc fail_cap_valid
    cmp eax, 0x40
    jne fail_cap_valid

    ; Header type 1 uses the same pointer; multifunction is orthogonal.
    mov byte [rel config_snapshot + 0x0E], 0x81
    mov edx, 0x01
    call parse_snapshot
    jc fail_cap_type1
    cmp eax, 0x70
    jne fail_cap_type1

    ; CardBus headers own their capability pointer at 0x14.
    call reset_snapshot
    mov byte [rel config_snapshot + 0x0E], 2
    mov byte [rel config_snapshot + 0x14], 0x48
    mov byte [rel config_snapshot + 0x48], 0x11
    mov byte [rel config_snapshot + 0x49], 0
    mov edx, 0x11
    call parse_snapshot
    jc fail_cap_cardbus
    cmp eax, 0x48
    jne fail_cap_cardbus

    ; A clear status bit is a clean absence even if stale bytes look linked.
    and word [rel config_snapshot + 0x06], ~KPCI_CAP_STATUS_BIT
    mov edx, 0x11
    call parse_snapshot
    jc fail_cap_absent
    test eax, eax
    jnz fail_cap_absent

    call reset_snapshot
    mov byte [rel config_snapshot + 0x34], 0x41
    mov edx, 0x05
    call parse_snapshot
    jnc fail_cap_misaligned

    call reset_snapshot
    mov byte [rel config_snapshot + 0x34], 0x3C
    mov edx, 0x05
    call parse_snapshot
    jnc fail_cap_header_alias

    call reset_snapshot
    mov byte [rel config_snapshot + 0x0E], 3
    mov edx, 0x05
    call parse_snapshot
    jnc fail_cap_header_type

    call reset_snapshot
    mov byte [rel config_snapshot + 0x34], 0x40
    mov byte [rel config_snapshot + 0x40], 0x01
    mov byte [rel config_snapshot + 0x41], 0x44
    mov byte [rel config_snapshot + 0x44], 0x10
    mov byte [rel config_snapshot + 0x45], 0x40
    mov edx, 0x05
    call parse_snapshot
    jnc fail_cap_cycle

    call reset_snapshot
    mov byte [rel config_snapshot + 0x34], 0x40
    mov byte [rel config_snapshot + 0x40], 0x05
    mov byte [rel config_snapshot + 0x41], 0x40
    mov edx, 0x05
    call parse_snapshot
    jnc fail_cap_cycle

    call reset_snapshot
    mov byte [rel config_snapshot + 0x34], 0x40
    mov byte [rel config_snapshot + 0x40], 0x01
    mov byte [rel config_snapshot + 0x41], 0x43
    mov edx, 0x05
    call parse_snapshot
    jnc fail_cap_next_alignment

    ; Null capabilities are valid list members and must be skipped.
    call reset_snapshot
    mov byte [rel config_snapshot + 0x34], 0x40
    mov byte [rel config_snapshot + 0x40], 0
    mov byte [rel config_snapshot + 0x41], 0x44
    mov byte [rel config_snapshot + 0x44], 0x05
    mov byte [rel config_snapshot + 0x45], 0
    mov edx, 0x05
    call parse_snapshot
    jc fail_cap_null
    cmp eax, 0x44
    jne fail_cap_null

    call reset_snapshot
    mov byte [rel config_snapshot + 0x34], 0x40
    mov byte [rel config_snapshot + 0x40], 0xFF
    mov byte [rel config_snapshot + 0x41], 0
    mov edx, 0x05
    call parse_snapshot
    jnc fail_cap_reserved_id

    call reset_snapshot
    mov byte [rel config_snapshot + 0x34], 0xFC
    mov byte [rel config_snapshot + 0xFC], 0x11
    mov byte [rel config_snapshot + 0xFD], 0
    mov edx, 0x11
    call parse_snapshot
    jc fail_cap_last_slot
    cmp eax, 0xFC
    jne fail_cap_last_slot

    xor edx, edx
    call parse_snapshot
    jnc fail_cap_target
    mov edx, 0xFF
    call parse_snapshot
    jnc fail_cap_target
    mov edx, 0x100
    call parse_snapshot
    jnc fail_cap_target

    lea rdi, [rel config_snapshot]
    mov esi, KPCI_CONFIG_SPACE_BYTES - 1
    mov edx, 0x11
    call kpci_find_capability_snapshot
    jnc fail_cap_span

    call reset_snapshot
    mov word [rel config_snapshot], 0xFFFF
    mov edx, 0x11
    call parse_snapshot
    jc fail_cap_no_function
    test eax, eax
    jnz fail_cap_no_function

    xor edi, edi
    mov esi, KPCI_CONFIG_SPACE_BYTES
    call kpci_find_capability_snapshot
    jnc fail_cap_input

    mov rdi, -128
    mov esi, KPCI_CONFIG_SPACE_BYTES
    mov edx, 0x11
    call kpci_find_capability_snapshot
    jnc fail_cap_input

    call reset_snapshot
    mov word [rel config_snapshot + 0x0A], 0x0200
    xor esi, esi
    mov edx, 0xFF
    call route_snapshot
    jc fail_route_endpoint
    test eax, eax
    jnz fail_route_endpoint

    call reset_snapshot
    mov word [rel config_snapshot + 0x0A], 0x0604
    mov byte [rel config_snapshot + 0x0E], 1
    mov byte [rel config_snapshot + 0x18], 2
    mov byte [rel config_snapshot + 0x19], 3
    mov byte [rel config_snapshot + 0x1A], 5
    mov esi, 2
    mov edx, 7
    call route_snapshot
    jc fail_route_type1
    cmp eax, 0x0503
    jne fail_route_type1

    call reset_snapshot
    mov word [rel config_snapshot + 0x0A], 0x0607
    mov byte [rel config_snapshot + 0x0E], 0x82
    mov byte [rel config_snapshot + 0x18], 4
    mov byte [rel config_snapshot + 0x19], 5
    mov byte [rel config_snapshot + 0x1A], 6
    mov esi, 4
    mov edx, 6
    call route_snapshot
    jc fail_route_type2
    cmp eax, 0x0605
    jne fail_route_type2

    call reset_snapshot
    mov word [rel config_snapshot + 0x0A], 0x0604
    mov byte [rel config_snapshot + 0x0E], 1
    mov esi, 2
    mov edx, 7
    call route_snapshot
    jc fail_route_unconfigured
    test eax, eax
    jnz fail_route_unconfigured

    mov byte [rel config_snapshot + 0x18], 1
    mov byte [rel config_snapshot + 0x19], 3
    mov byte [rel config_snapshot + 0x1A], 5
    call route_snapshot
    jnc fail_route_primary

    call reset_snapshot
    mov word [rel config_snapshot + 0x0A], 0x0604
    xor esi, esi
    mov edx, 0xFF
    call route_snapshot
    jnc fail_route_header_class

    call reset_snapshot
    mov word [rel config_snapshot + 0x0A], 0x0604
    mov byte [rel config_snapshot + 0x0E], 1
    mov byte [rel config_snapshot + 0x18], 2
    mov byte [rel config_snapshot + 0x1A], 5
    mov esi, 2
    mov edx, 7
    call route_snapshot
    jnc fail_route_one_zero

    mov byte [rel config_snapshot + 0x19], 5
    mov byte [rel config_snapshot + 0x1A], 4
    call route_snapshot
    jnc fail_route_order

    mov byte [rel config_snapshot + 0x19], 2
    mov byte [rel config_snapshot + 0x1A], 3
    call route_snapshot
    jnc fail_route_cycle

    mov byte [rel config_snapshot + 0x19], 3
    mov byte [rel config_snapshot + 0x1A], 8
    call route_snapshot
    jnc fail_route_window

    mov esi, 8
    mov edx, 7
    call route_snapshot
    jnc fail_route_input

    xor edi, edi
    jmp exit

fail_compose_byte:      mov edi, 1
                        jmp exit
fail_compose_word:      mov edi, 2
                        jmp exit
fail_compose_dword:     mov edi, 3
                        jmp exit
fail_compose_bdf:       mov edi, 4
                        jmp exit
fail_compose_alignment: mov edi, 5
                        jmp exit
fail_compose_span:      mov edi, 6
                        jmp exit
fail_compose_size:      mov edi, 7
                        jmp exit
fail_cap_valid:         mov edi, 8
                        jmp exit
fail_cap_type1:         mov edi, 9
                        jmp exit
fail_cap_cardbus:       mov edi, 10
                        jmp exit
fail_cap_absent:        mov edi, 11
                        jmp exit
fail_cap_misaligned:    mov edi, 12
                        jmp exit
fail_cap_header_alias:  mov edi, 13
                        jmp exit
fail_cap_header_type:   mov edi, 14
                        jmp exit
fail_cap_cycle:         mov edi, 15
                        jmp exit
fail_cap_next_alignment: mov edi, 16
                         jmp exit
fail_cap_null:          mov edi, 17
                        jmp exit
fail_cap_reserved_id:   mov edi, 18
                        jmp exit
fail_cap_last_slot:     mov edi, 19
                        jmp exit
fail_cap_target:        mov edi, 20
                        jmp exit
fail_cap_span:          mov edi, 21
                        jmp exit
fail_cap_no_function:   mov edi, 22
                        jmp exit
fail_cap_input:         mov edi, 23
                        jmp exit
fail_route_endpoint:    mov edi, 24
                        jmp exit
fail_route_type1:       mov edi, 25
                        jmp exit
fail_route_type2:       mov edi, 26
                        jmp exit
fail_route_unconfigured: mov edi, 27
                         jmp exit
fail_route_primary:     mov edi, 28
                        jmp exit
fail_route_header_class: mov edi, 29
                         jmp exit
fail_route_one_zero:    mov edi, 30
                        jmp exit
fail_route_order:       mov edi, 31
                        jmp exit
fail_route_cycle:       mov edi, 32
                        jmp exit
fail_route_window:      mov edi, 33
                        jmp exit
fail_route_input:       mov edi, 34

exit:
    mov eax, 60
    syscall

parse_snapshot:
    lea rdi, [rel config_snapshot]
    mov esi, KPCI_CONFIG_SPACE_BYTES
    jmp kpci_find_capability_snapshot

route_snapshot:
    lea rdi, [rel config_snapshot]
    jmp kpci_snapshot_bridge_route

reset_snapshot:
    lea rdi, [rel config_snapshot]
    mov ecx, KPCI_CONFIG_SPACE_BYTES / 8
    xor eax, eax
    rep stosq
    or word [rel config_snapshot + 0x06], KPCI_CAP_STATUS_BIT
    ret

section .bss
alignb 16
config_snapshot: resb KPCI_CONFIG_SPACE_BYTES
