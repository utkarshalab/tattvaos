; =============================================================================
; Utkarsha OS — lib/input/core/dev.asm
; =============================================================================
; The device list. Each driver adds its devices here and tags its events
; with the ID it gets back. IDs start at 1 and follow the order drivers add
; devices in, so the built-in keyboard, added first at every boot, keeps the
; same ID. IDs from hardware paths (ACPI, PCI, USB) come with those drivers.
; =============================================================================

%ifndef LIB_INPUT_CORE_DEV_ASM
%define LIB_INPUT_CORE_DEV_ASM

section .bss
alignb 8
global input_devs
input_devs:         resb INPUT_MAX_DEVICES * input_dev_size

section .text

; -----------------------------------------------------------------------------
; input_dev_reset — forget every device (start-up and tests)
; Clobbers: RAX, RCX, RDI
; -----------------------------------------------------------------------------
global input_dev_reset
input_dev_reset:
    lea rdi, [rel input_devs]
    mov ecx, INPUT_MAX_DEVICES * input_dev_size
    xor eax, eax
    rep stosb
    ret

; -----------------------------------------------------------------------------
; input_dev_add — add a device
; Input:  RDI = name (NUL-terminated; longer names are cut), ESI = bus,
;         RDX = capabilities, ECX = vendor << 16 | product
; Output: EAX = the new device's ID (1 or more), or -INPUT_ENOSPC
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global input_dev_add
input_dev_add:
    lea r8, [rel input_devs]
    xor r9d, r9d                        ; slot
.find:
    test dword [r8 + input_dev.flags], INPUT_DEV_PRESENT
    jz .free
    add r8, input_dev_size
    inc r9d
    cmp r9d, INPUT_MAX_DEVICES
    jb .find
    mov eax, -INPUT_ENOSPC
    ret
.free:
    ; clear the slot, then fill it
    push rdi
    push rcx
    mov rdi, r8
    mov ecx, input_dev_size
    xor eax, eax
    rep stosb
    pop rcx
    pop rdi

    lea eax, [r9 + 1]
    mov [r8 + input_dev_info.id], eax
    mov [r8 + input_dev_info.bus], esi
    mov [r8 + input_dev_info.caps], rdx
    mov eax, ecx
    mov [r8 + input_dev_info.product], ax
    shr eax, 16
    mov [r8 + input_dev_info.vendor], ax

    ; copy the name
    lea r10, [r8 + input_dev.name]
    mov [r8 + input_dev_info.name], r10
    xor ecx, ecx
    test rdi, rdi
    jz .named
.copy:
    cmp ecx, INPUT_NAME_MAX - 1
    jae .named
    mov al, [rdi + rcx]
    test al, al
    jz .named
    mov [r10 + rcx], al
    inc ecx
    jmp .copy
.named:
    mov byte [r10 + rcx], 0
    mov dword [r8 + input_dev.flags], INPUT_DEV_PRESENT
    lea eax, [r9 + 1]
    ret

; -----------------------------------------------------------------------------
; input_dev_find — the record for an ID
; Input:  EDI = device ID
; Output: RAX = input_dev*, or 0 when no such device is present
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
global input_dev_find
input_dev_find:
    mov ecx, edi
    dec ecx
    cmp ecx, INPUT_MAX_DEVICES
    jae .none                           ; also catches ID 0
    imul ecx, ecx, input_dev_size
    lea rax, [rel input_devs]
    add rax, rcx
    test dword [rax + input_dev.flags], INPUT_DEV_PRESENT
    jz .none
    ret
.none:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; input_dev_remove — remove a device; its ID is free for the next one
; Input:  EDI = device ID
; Output: EAX = 0, or -INPUT_ENODEV
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
global input_dev_remove
input_dev_remove:
    call input_dev_find
    test rax, rax
    jz .none
    mov dword [rax + input_dev.flags], 0
    xor eax, eax
    ret
.none:
    mov eax, -INPUT_ENODEV
    ret

%endif ; LIB_INPUT_CORE_DEV_ASM
