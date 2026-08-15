; =============================================================================
; Tattva OS — lib/hw/ugpu/pcie.asm
; =============================================================================
; PCIe link bandwidth reporting for detected GPUs (ugpu_devices, from
; detect.asm). Reads the same PCIe Capability Link Status/Capabilities
; registers lib/io/pci/link.asm checks for degradation, but that file only
; answers "healthy or retrained?" — it never turns speed+width into a
; throughput number. This does, using encoding-aware per-lane rates instead
; of the raw GT/s figure (8b/10b for Gen1/2, 128b/130b for Gen3+).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_HW_UGPU_PCIE_ASM
%define LIB_HW_UGPU_PCIE_ASM

%include "lib/hw/ugpu/detect.asm"

[BITS 64]

section .data
; Effective MB/s per lane, indexed by PCIe Link speed encoding (1-6).
; Index 0 is the "unrecognized" sentinel and stays 0. Gen1/2 use 8b/10b
; encoding (20% overhead); Gen3+ use 128b/130b (~1.54% overhead); Gen6 is
; approximated as double Gen5 (PAM4 + FLIT encoding, not modeled exactly).
ugpu_lane_mbps: dd 0, 250, 500, 985, 1969, 3938, 7877

section .text

; -----------------------------------------------------------------------------
; ugpu_get_link_info — reads a detected GPU's current PCIe link speed/width
; Input:
;   RDI = index into ugpu_devices
; Output:
;   RAX = 1 if found and the device has a PCIe capability, 0 otherwise
;   RSI = link speed encoding (1-6, see ugpu_lane_mbps)
;   RDX = link width in lanes
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9
; -----------------------------------------------------------------------------
global ugpu_get_link_info
ugpu_get_link_info:
    push rbx
    push r12

    cmp rdi, [rel ugpu_device_count]
    jae .not_found

    mov rax, rdi
    imul rax, ugpu_device_t_size
    lea r12, [rel ugpu_devices + rax]

    mov ebx, [r12 + ugpu_device_t.pcie_cap_off]
    test ebx, ebx
    jz .not_found

    mov edi, [r12 + ugpu_device_t.bus]
    mov esi, [r12 + ugpu_device_t.device]
    mov edx, [r12 + ugpu_device_t.function]
    lea rcx, [rbx + 16]               ; Link Status is at cap offset +0x12;
                                      ; read the dword at +0x10 (Link Control
                                      ; /Link Status) then take the high word
    call hw_pci_cfg_read32
    shr eax, 16                      ; EAX = Link Status word

    mov ecx, eax
    and ecx, 0x0F                    ; ECX = current link speed encoding
    mov edx, eax
    shr edx, 4
    and edx, 0x3F                    ; EDX = current link width (lanes)

    test ecx, ecx
    jz .not_found

    mov esi, ecx
    mov rax, 1
    jmp .done

.not_found:
    xor rax, rax
    xor rsi, rsi
    xor rdx, rdx

.done:
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ugpu_get_bandwidth_mbps — effective PCIe link bandwidth for a detected GPU
; Input:
;   RDI = index into ugpu_devices
; Output:
;   RAX = bandwidth in MB/s, or 0 if the device/link/speed is not resolvable
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10
; -----------------------------------------------------------------------------
global ugpu_get_bandwidth_mbps
ugpu_get_bandwidth_mbps:
    push r12
    push r13

    call ugpu_get_link_info
    test rax, rax
    jz .zero
    mov r12, rsi                     ; R12 = speed encoding
    mov r13, rdx                     ; R13 = width

    cmp r12, 6
    ja .zero                         ; unrecognized encoding

    mov eax, [rel ugpu_lane_mbps + r12 * 4]
    imul eax, r13d                   ; total = per-lane MB/s * lanes
    jmp .done

.zero:
    xor eax, eax

.done:
    pop r13
    pop r12
    ret

%endif ; LIB_HW_UGPU_PCIE_ASM
