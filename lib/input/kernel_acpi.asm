; =============================================================================
; Utkarsha OS — lib/input/kernel_acpi.asm
; =============================================================================
; The ACPI lid and buttons as input devices. Included by kernel/entry.asm
; after the AML interpreter's kernel glue and lib/input.
;
; input_acpi_init, after acpi_kernel_init: an "ACPI lid" switch device and
; an "ACPI buttons" device, and the hooks ACPI events call:
;   the lid    → INPUT_SWITCH, switch 0 (lid), 1 closed / 0 open; its state
;                at start-up is sent once
;   power      → KEY_POWER pressed and released
;   sleep      → KEY_SLEEP pressed and released
; The hooks run on the fiber that services ACPI events, so they post with
; input_post_safe.
; =============================================================================

%ifndef LIB_INPUT_KERNEL_ACPI_ASM
%define LIB_INPUT_KERNEL_ACPI_ASM

%define KEY_POWER           116
%define KEY_SLEEP           142
%define INPUT_SWITCH_LID    0

section .rodata
iac_name_lid:       db "ACPI lid", 0
iac_name_buttons:   db "ACPI buttons", 0

section .bss
alignb 4
global iac_lid_dev
iac_lid_dev:        resd 1
global iac_button_dev
iac_button_dev:     resd 1

section .text

; -----------------------------------------------------------------------------
; input_acpi_init — the devices and hooks
; -----------------------------------------------------------------------------
global input_acpi_init
input_acpi_init:
    push rbx
    mov dword [rel iac_lid_dev], 0
    mov dword [rel iac_button_dev], 0
    cmp dword [rel acpi_ready], 1
    jne .out
    ; buttons: always worth having, fixed or control-method
    lea rdi, [rel iac_name_buttons]
    mov esi, INPUT_BUS_PLATFORM
    mov edx, INPUT_CAP_KEYBOARD
    xor ecx, ecx
    call input_dev_add
    test eax, eax
    js .lid
    mov [rel iac_button_dev], eax
    lea rax, [rel iac_button]
    mov [rel acpi_button_fn], rax
.lid:
    cmp qword [rel acpi_lid_node], 0
    je .out
    lea rdi, [rel iac_name_lid]
    mov esi, INPUT_BUS_PLATFORM
    mov edx, INPUT_CAP_SWITCH
    xor ecx, ecx
    call input_dev_add
    test eax, eax
    js .out
    mov [rel iac_lid_dev], eax
    lea rax, [rel iac_lid]
    mov [rel acpi_lid_fn], rax
    ; where the lid is now
    call acpi_lid_state
    test eax, eax
    js .out
    mov edi, eax
    call iac_lid
.out:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; iac_lid — acpi_lid_fn: EDI = 1 closed, 0 open
; -----------------------------------------------------------------------------
iac_lid:
    mov edx, edi
    mov edi, INPUT_SWITCH
    mov esi, INPUT_SWITCH_LID
    mov ecx, [rel iac_lid_dev]
    jmp input_post_safe

; -----------------------------------------------------------------------------
; iac_button — acpi_button_fn: EDI = 1 power, 2 sleep; a press and release
; -----------------------------------------------------------------------------
iac_button:
    push rbx
    mov ebx, KEY_POWER
    cmp edi, 1
    je .key
    mov ebx, KEY_SLEEP
.key:
    mov edi, INPUT_KEY
    mov esi, ebx
    mov edx, 1
    mov ecx, [rel iac_button_dev]
    call input_post_safe
    mov edi, INPUT_KEY
    mov esi, ebx
    xor edx, edx
    mov ecx, [rel iac_button_dev]
    call input_post_safe
    pop rbx
    ret

%endif ; LIB_INPUT_KERNEL_ACPI_ASM
