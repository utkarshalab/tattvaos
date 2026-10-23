; ============================================================================
; Native PCI Discovery — Display Controller Enumeration
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

; struct offsets (hoisted above use)
%define PciDevice_class_code    0x0E
%define PciDevice.class_code 0x0E
%define PciDevice_subclass      0x0F
%define PciDevice.subclass 0x0F
%define PciDevice_bar0          0x10
%define PciDevice.bar0 0x10
%define PciDevice_bar2          0x28
%define PciDevice.bar2 0x28
%define PciDevice_irq           0x3C
%define PciDevice.irq 0x3C
%define PCI_CLASS_DISPLAY       0x03
%define PCI_SUBCLASS_VGA        0x00
%define PCI_SUBCLASS_XGA        0x01
%define PCI_SUBCLASS_3D         0x02
%define PCI_SUBCLASS_DISPLAY    0x80
%define Server_fb_base       0x100
%define Server.fb_base 0x100
%define Server_fb_size       0x108
%define Server.fb_size 0x108
%define Server_mmio_base     0x110
%define Server.mmio_base 0x110
%define Server_mmio_size     0x118
%define Server.mmio_size 0x118
%define Server_pci_dev       0x120
%define Server.pci_dev 0x120
%define Server_irq           0x128
%define Server.irq 0x128
%define Server_arena         0x130
%define Server.arena 0x130
%define Server_controller    0x138
%define Controller_state       0
%define Controller.state 0
%define Controller_pci_dev     8
%define Controller.pci_dev 8
%define Controller_mmio_base   16
%define Controller.mmio_base 16
%define Controller_fb_base     24
%define Controller.fb_base 24
%define Controller_fb_size     32
%define Controller.fb_size 32
%define Controller_family      40
%define Controller.family 40
%define Controller_outputs     48
%define Controller.outputs 48
%define Controller_output_count 56
%define Controller.output_count 56
%define Controller_state_size  64
%define Controller_family_detected 72
%define Controller.family_detected 72

section .text

; ---------------------------------------------------------------------------
; native_pci_discover
;   Discover display controllers on PCI bus
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = count of discovered controllers, negative error
; ---------------------------------------------------------------------------
global native_pci_discover
native_pci_discover:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Iterate all PCI devices
    mov rdi, native_pci_callback
    mov rsi, rbx
    call ut_pci_for_each
    test rax, rax
    jnz .done

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.done:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; native_pci_callback (internal)
;   Callback for each PCI device
;   IN:  rdi = PciDevice*, rsi = server*
; ---------------------------------------------------------------------------
native_pci_callback:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi        ; PciDevice*
    mov r12, rsi        ; server*
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Check class code: Display controller (0x03)
    movzx eax, byte [rbx + PciDevice.class_code]
    cmp al, PCI_CLASS_DISPLAY
    jne .not_display

    ; Check subclass: VGA (0x00), XGA (0x01), 3D (0x02), Display (0x80)
    movzx eax, byte [rbx + PciDevice.subclass]
    cmp al, PCI_SUBCLASS_VGA
    je .is_display
    cmp al, PCI_SUBCLASS_XGA
    je .is_display
    cmp al, PCI_SUBCLASS_3D
    je .is_display
    cmp al, PCI_SUBCLASS_DISPLAY
    je .is_display
    jmp .not_display

.is_display:
    ; Found display controller - allocate and initialize
    call native_init_controller
    test rax, rax
    jnz .fail

    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.not_display:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.fail:
    mov rax, -EIO
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; native_init_controller
;   Initialize display controller
;   IN:  rbx = PciDevice*, r12 = server*
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
native_init_controller:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    ; rbx = PciDevice*, r12 = server*

    ; Enable device (memory/IO/BusMaster)
    mov rdi, rbx
    call ut_pci_enable_device
    test rax, rax
    jnz .fail

    ; Map BARs
    ; BAR0: usually framebuffer or MMIO
    ; BAR2: usually MMIO registers
    mov r13, rbx
    mov r14, r12

    ; Map BAR0 (framebuffer)
    movzx eax, word [r13 + PciDevice.bar0 + 0]  ; type
    test eax, eax
    jz .skip_bar0

    mov rax, [r13 + PciDevice.bar0 + 8]  ; base
    mov rdx, [r13 + PciDevice.bar0 + 16] ; size
    mov rdi, rax
    mov rsi, rdx
    mov rdx, MEM_WC
    call ut_mmio_map
    test rax, rax
    js .fail
    mov [r14 + Server.fb_base], rax
    mov [r14 + Server.fb_size], rdx

.skip_bar0:
    ; Map BAR2 (MMIO registers)
    movzx eax, word [r13 + PciDevice.bar2 + 0]
    test eax, eax
    jz .skip_bar2

    mov rax, [r13 + PciDevice.bar2 + 8]
    mov rdx, [r13 + PciDevice.bar2 + 16]
    mov rdi, rax
    mov rsi, rdx
    mov rdx, MEM_UNCACHED
    call ut_mmio_map
    test rax, rax
    js .fail
    mov [r14 + Server.mmio_base], rax
    mov [r14 + Server.mmio_size], rdx

.skip_bar2:
    ; Store controller info
    mov [r14 + Server.pci_dev], r13
    mov [r14 + Server.irq], 0
    movzx eax, byte [r13 + PciDevice.irq]
    mov [r14 + Server.irq], rax

    ; Allocate controller state
    mov rdi, [r14 + Server.arena]
    mov rsi, 512
    call arena_alloc
    test rax, rax
    jz .oom
    mov [r14 + Controller.state], rax
    mov r15, rax

    ; Fill controller state
    mov qword [r15 + Controller.pci_dev], r13
    mov rax, [r14 + Server.mmio_base]
    mov qword [r15 + Controller.mmio_base], rax
    mov rax, [r14 + Server.fb_base]
    mov qword [r15 + Controller.fb_base], rax
    mov rax, [r14 + Server.fb_size]
    mov qword [r15 + Controller.fb_size], rax
    mov qword [r15 + Controller.outputs], 0
    mov qword [r15 + Controller.output_count], 0

    ; Detect family and initialize
    call native_detect_family
    test rax, rax
    jnz .fail

    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.fail:
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; native_detect_family
;   Detect display engine family (DCN version)
;   IN:  r15 = Controller.state*
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
native_detect_family:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, r15
    mov r12, [rbx + Controller.mmio_base]

    ; Read DCN version from register
    ; DCN_VERSION register at offset 0x0000 (example)
    mov eax, [r12 + 0x0000]
    mov [rbx + Controller.family], eax

    ; Check for DCN family
    mov eax, [rbx + Controller.family]
    cmp eax, 0x0000  ; DCN 1.0
    je .dcn10
    cmp eax, 0x1000  ; DCN 2.0
    je .dcn20
    cmp eax, 0x2000  ; DCN 3.0
    je .dcn30
    cmp eax, 0x3000  ; DCN 3.1
    je .dcn31
    cmp eax, 0x4000  ; DCN 3.2
    je .dcn32
    cmp eax, 0x5000  ; DCN 3.5
    je .dcn35

    ; Unknown family
    mov rax, -(ENOTSUP)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.dcn10:
.dcn20:
.dcn30:
.dcn31:
.dcn32:
.dcn35:
    mov byte [rbx + Controller.family_detected], 1
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data





global native_pci_version
native_pci_version: dq 0x010000
