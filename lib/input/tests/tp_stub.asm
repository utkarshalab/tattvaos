; =============================================================================
; lib/input/tests/tp_stub.asm — the touchpad's kernel glue for host tests:
; the ACPI interpreter with its kernel glue and stubs (kstub.asm), the
; GSI routing recorded instead of done (the rest is in kstub.asm), then GPIO, I2C,
; lib/input and kernel_touchpad.asm.
; =============================================================================

%include "lib/io/acpi/aml/tests/kstub.asm"

IOAPIC_GSI_MASKED           equ 1 << 0
IOAPIC_GSI_LEVEL            equ 1 << 1
IOAPIC_GSI_LOW              equ 1 << 2

section .data
align 8
global tp_routes                ; every ioapic_route_gsi: gsi, vector, flags
tp_routes:          times 3 * 16 dd 0
global tp_route_count
tp_route_count:     dd 0
global tp_route_fail
tp_route_fail:      dd 0        ; 1: ioapic_route_gsi fails

section .text

; EDI = GSI, ESI = vector, EDX = destination, ECX = flags; CF = 1 on failure
global ioapic_route_gsi
ioapic_route_gsi:
    cmp dword [rel tp_route_fail], 0
    jne .fail
    mov eax, [rel tp_route_count]
    cmp eax, 16
    jae .ok
    imul eax, eax, 12
    lea r8, [rel tp_routes]
    mov [r8 + rax], edi
    mov [r8 + rax + 4], esi
    mov [r8 + rax + 8], ecx
    inc dword [rel tp_route_count]
.ok:
    clc
    ret
.fail:
    stc
    ret

%include "lib/io/gpio/gpio.asm"
%include "lib/io/i2c/i2c.asm"
%include "lib/input/input.asm"
%include "lib/input/kernel_touchpad.asm"
%include "lib/input/kernel_acpi.asm"
