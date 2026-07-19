; =============================================================================
; lib/io/pci/link.asm
; PCIe Link status verification and hardware link retraining control.
;
; Monitors PCIe Link speeds and widths, triggering active hardware retraining
; on degraded links to recover physical lane throughput capacity.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_PCI_LINK_ASM
%define IO_PCI_LINK_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .text

global pci_verify_link_status

extern pci_find_capability
extern pci_config_read
extern pci_config_write

; =============================================================================
; pci_verify_link_status — Verify link configuration and retrain if degraded
; In : RDI = Bus
;      RSI = Device
;      RDX = Function
; Out: RAX = 0 if normal, 1 if retrained successfully, or negative error
; =============================================================================
IO_FUNC pci_verify_link_status
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi                ; r12 = Bus
    mov     r13, rsi                ; r13 = Device
    mov     r14, rdx                ; r14 = Function

    ; 1. Locate PCIe Capability structure (ID = 0x10)
    mov     rcx, 0x10               ; PCIe Capability ID
    call    pci_find_capability
    test    rax, rax
    jz      .err_no_pcie
    mov     rbx, rax                ; RBX = PCIe capability base offset

    ; 2. Read Link Capabilities register (offset +0x0C inside capability block)
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    lea     rcx, [rbx + 12]
    mov     r8, 4
    call    pci_config_read         ; EAX = Link Capabilities
    
    mov     r10, rax
    and     r10, 0x0F               ; R10 = Max Link Speed (bits 3:0)
    mov     r11, rax
    shr     r11, 4
    and     r11, 0x3F               ; R11 = Max Link Width (bits 9:4)

    ; 3. Read Link Status register (offset +0x12 inside capability block)
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    lea     rcx, [rbx + 18]
    mov     r8, 2
    call    pci_config_read         ; AX = Link Status

    mov     r15, rax
    and     r15, 0x0F               ; R15 = Current Link Speed (bits 3:0)
    mov     rsi, rax
    shr     rsi, 4
    and     rsi, 0x3F               ; RSI = Current Link Width (bits 9:4)

    ; 4. Check if degraded (current speed < max speed OR current width < max width)
    cmp     r15, r10
    jb      .retrain
    cmp     rsi, r11
    jb      .retrain

    xor     rax, rax                ; Link is healthy, return 0
    jmp     .done

.retrain:
    ; 5. Read Link Control register (offset +0x10 inside capability block)
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    lea     rcx, [rbx + 16]
    mov     r8, 2
    call    pci_config_read         ; AX = Link Control

    or      ax, 0x0020              ; Set Bit 5 (Retrain Link)
    mov     rsi, rax

    ; Write updated Link Control back to initiate hardware retraining
    mov     rdi, r12
    mov     rsi, rax                ; (RSI is already loaded)
    mov     rdx, r14
    lea     rcx, [rbx + 16]
    mov     r8, 2
    call    pci_config_write

    ; 6. Spin-wait until Link Training bit (bit 11 of Link Status) becomes 0
.wait_retrain:
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    lea     rcx, [rbx + 18]
    mov     r8, 2
    call    pci_config_read         ; AX = Link Status
    test    ax, 0x0800              ; Test bit 11 (Link Training active)
    jnz     .wait_retrain           ; Loop until training completes

    mov     rax, 1                  ; Return 1 (Retrained)
    jmp     .done

.err_no_pcie:
    mov     rax, IO_ERR_NO_DEVICE

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC pci_verify_link_status

%endif ; IO_PCI_LINK_ASM
