; =============================================================================
; lib/io/pci/mps.asm
; PCIe Max Payload Size (MPS) auto-tuning driver.
;
; Traverses PCIe capabilities to parse maximum supported payload sizes and
; configures the Device Control register to align packet transmissions safely.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_PCI_MPS_ASM
%define IO_PCI_MPS_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .text

global pci_tune_mps



; =============================================================================
; pci_tune_mps — Negotiate and write PCIe Max Payload Size
; In : RDI = Bus
;      RSI = Device
;      RDX = Function
; Out: RAX = 0 on success, or negative error code (IO_ERR_NO_DEVICE)
; =============================================================================
IO_FUNC pci_tune_mps
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14

    mov     r12, rdi                ; r12 = Bus
    mov     r13, rsi                ; r13 = Device
    mov     r14, rdx                ; r14 = Function

    ; 1. Locate PCIe Capability structure (ID = 0x10)
    mov     rcx, 0x10               ; PCIe Capability ID
    call    pci_find_capability
    test    rax, rax
    jz      .err_no_pcie
    mov     rbx, rax                ; RBX = PCIe capability base offset

    ; 2. Read Device Capabilities register (offset +4 inside capability block)
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    lea     rcx, [rbx + 4]
    mov     r8, 4                   ; Read 4 bytes
    call    pci_config_read         ; EAX = Device Capabilities

    ; Max_Payload_Size_Supported is in bits [2:0]
    ; Codes: 000=128B, 001=256B, 010=512B, 011=1024B, 100=2048B, 101=4096B
    and     rax, 0x07               ; RAX = max supported code
    
    ; Commodity limit safety: cap maximum configuration to 256 bytes (code 1)
    ; to ensure maximum routing compatibility across legacy PCIe switches
    cmp     rax, 1
    jbe     .set_mps
    mov     rax, 1                  ; Cap at 256 bytes

.set_mps:
    mov     r15, rax                ; R15 = negotiated MPS code (0 or 1)

    ; 3. Read Device Control register (offset +8 inside capability block)
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    lea     rcx, [rbx + 8]
    mov     r8, 2                   ; Read 2 bytes
    call    pci_config_read         ; AX = Device Control

    ; Max_Payload_Size field is in bits [7:5] of Device Control register
    and     ax, 0xFF1F              ; Clear bits 7, 6, 5
    shl     r15w, 5                 ; Shift negotiated code to bits [7:5]
    or      ax, r15w                ; Combine with Control value
    mov     rsi, rax                ; RSI = updated register value

    ; Write updated Device Control back
    mov     rdi, r12
    mov     rsi, r13                ; (RSI is already loaded)
    mov     rdx, r14
    lea     rcx, [rbx + 8]
    mov     r8, 2
    call    pci_config_write

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_no_pcie:
    mov     rax, IO_ERR_NO_DEVICE

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC pci_tune_mps

%endif ; IO_PCI_MPS_ASM
