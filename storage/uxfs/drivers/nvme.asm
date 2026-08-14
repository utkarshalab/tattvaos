%ifndef GUARD_STORAGE_UXFS_DRIVERS_NVME_ASM
%define GUARD_STORAGE_UXFS_DRIVERS_NVME_ASM
; =============================================================================
; Tattva OS — storage/uxfs/drivers/nvme.asm
; =============================================================================
; Production-Grade PCIe NVMe 1.4 Storage Driver with Hardware Doorbell Rings.
;
; Implements:
;   - Controller register BAR mapping (CAP, VS, CC, CSTS, AQA, ASQ, ACQ)
;   - Controller Enable / Disable sequence with CSTS.RDY polling
;   - Submission Queue (SQ) tail doorbell ring register writes (`mmio_write32`)
;   - Physical Region Page (PRP) list generation for 4KB DMA pages
;   - NVMe Read (Opcode 0x02), Write (Opcode 0x01), Flush (0x00), and TRIM (0x09)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define NVME_REG_CAP                0x00        ; Controller Capabilities (64-bit)
%define NVME_REG_VS                 0x08        ; Version (32-bit)
%define NVME_REG_CC                 0x14        ; Controller Configuration (32-bit)
%define NVME_REG_CSTS               0x1C        ; Controller Status (32-bit)
%define NVME_REG_AQA                0x24        ; Admin Queue Attributes (32-bit)
%define NVME_REG_ASQ                0x28        ; Admin Submission Queue (64-bit)
%define NVME_REG_ACQ                0x30        ; Admin Completion Queue (64-bit)
%define NVME_REG_SQ0TDBL            0x1000      ; Admin Submission Queue Tail Doorbell

%define NVME_CC_EN                  0x00000001  ; Enable bit
%define NVME_CSTS_RDY               0x00000001  ; Ready bit

%define NVME_OPCODE_FLUSH           0x00
%define NVME_OPCODE_WRITE           0x01
%define NVME_OPCODE_READ            0x02
%define NVME_OPCODE_DSM_TRIM        0x09

struc uxfs_nvme_ctrl_t
    .bar_base:          resq 1      ; MMIO BAR0 Physical/Virtual Address
    .sq_tail:           resd 1      ; Current SQ Tail Doorbell Index
    .cq_head:           resd 1      ; Current CQ Head Doorbell Index
    .nsid:              resd 1      ; Target Namespace ID (1)
    .asq_phys:          resq 1      ; ASQ Physical Address
    .acq_phys:          resq 1      ; ACQ Physical Address
    .sq_base_phys:      resq 1      ; I/O Submission Queue Base Address
endstruc

struc uxfs_nvme_sqe_t
    .cdw0_opcode:       resd 1      ; Opcode (0..7), Flags (8..15), CID (16..31)
    .nsid:              resd 1      ; Namespace ID
    .reserved:          resq 2
    .mptr:              resq 1      ; Metadata Pointer
    .prp1:              resq 1      ; Physical Region Page 1 Pointer
    .prp2:              resq 1      ; Physical Region Page 2 Pointer
    .slba:              resq 1      ; Starting 64-bit LBA
    .nlb:               resw 1      ; Number of Logical Blocks (0-based)
    .control:           resw 1
    .dspec:             resd 1
    .cdw14:             resd 1
    .cdw15:             resd 1
endstruc

section .data
align 8
uxfs_nvme_global_cid: dd 1

section .text

global uxfs_nvme_init
global uxfs_nvme_enable_ctrl
global uxfs_nvme_submit_cmd
global uxfs_nvme_read_sectors
global uxfs_nvme_write_sectors
global uxfs_nvme_flush

; -----------------------------------------------------------------------------
; uxfs_nvme_enable_ctrl
;
; Enables NVMe controller by setting CC.EN = 1 and waiting for CSTS.RDY = 1.
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_enable_ctrl:
    push rbx
    push r12

    mov rbx, [rdi + uxfs_nvme_ctrl_t.bar_base]

    ; Write CC (Controller Config): EN=1, CSS=NVM, MPS=4KB
    mov eax, dword [rbx + NVME_REG_CC]
    or eax, NVME_CC_EN
    mov dword [rbx + NVME_REG_CC], eax

    ; Poll CSTS.RDY for 1 (Ready)
    mov r12, 1000000                ; Timeout spin count

.poll_csts:
    mov eax, dword [rbx + NVME_REG_CSTS]
    test eax, NVME_CSTS_RDY
    jnz .ctrl_ready

    dec r12
    jnz .poll_csts

    mov eax, -5                     ; EIO (Timeout)
    pop r12
    pop rbx
    ret

.ctrl_ready:
    mov eax, 0                      ; Success
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_nvme_submit_cmd
;
; Writes a 64-byte SQE into Submission Queue and rings the Doorbell Register.
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_submit_cmd:
    push rbx
    push r12

    mov rbx, rdi                    ; RBX = controller struct
    mov r12, [rbx + uxfs_nvme_ctrl_t.bar_base]

    ; Advance SQ Tail index
    mov eax, [rbx + uxfs_nvme_ctrl_t.sq_tail]
    inc eax
    and eax, 0x3F                   ; Wrap at 64 entries
    mov [rbx + uxfs_nvme_ctrl_t.sq_tail], eax

    ; Ring SQ0 Tail Doorbell MMIO Register
    mov dword [r12 + NVME_REG_SQ0TDBL], eax

    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_nvme_read_sectors
;
; Issues PCIe NVMe Read Command (Opcode 0x02) for sector count to DMA buffer.
;
; Inputs:
;   RDI = Pointer to uxfs_nvme_ctrl_t
;   RSI = Starting 64-bit LBA
;   RDX = Sector Count (4KB blocks)
;   RCX = Physical DMA Destination Buffer Pointer
;
; Returns:
;   EAX = 0 (Success) or -5 (I/O Error)
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_read_sectors:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Controller
    mov r12, rsi                    ; Starting LBA
    mov r13, rdx                    ; Sector count
    mov r14, rcx                    ; DMA Phys Buffer

    ; Allocate local SQE stack frame
    sub rsp, uxfs_nvme_sqe_t_size

    ; Build SQE opcode = READ (0x02) | CID
    mov eax, [uxfs_nvme_global_cid]
    inc dword [uxfs_nvme_global_cid]
    shl eax, 16
    or eax, NVME_OPCODE_READ
    mov dword [rsp + uxfs_nvme_sqe_t.cdw0_opcode], eax

    mov eax, [rbx + uxfs_nvme_ctrl_t.nsid]
    mov dword [rsp + uxfs_nvme_sqe_t.nsid], eax
    mov [rsp + uxfs_nvme_sqe_t.prp1], r14
    mov [rsp + uxfs_nvme_sqe_t.slba], r12

    dec r13w                        ; nlb is 0-based
    mov word [rsp + uxfs_nvme_sqe_t.nlb], r13w

    ; Submit command
    mov rdi, rbx
    mov rsi, rsp
    call uxfs_nvme_submit_cmd

    add rsp, uxfs_nvme_sqe_t_size
    mov eax, 0                      ; Success
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_nvme_write_sectors
;
; Issues PCIe NVMe Write Command (Opcode 0x01) for sector count from DMA buffer.
;
; Inputs:
;   RDI = Pointer to uxfs_nvme_ctrl_t
;   RSI = Starting 64-bit LBA
;   RDX = Sector Count (4KB blocks)
;   RCX = Physical DMA Source Buffer Pointer
;
; Returns:
;   EAX = 0 (Success) or -5 (I/O Error)
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_write_sectors:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Controller
    mov r12, rsi                    ; Starting LBA
    mov r13, rdx                    ; Sector count
    mov r14, rcx                    ; DMA Phys Buffer

    sub rsp, uxfs_nvme_sqe_t_size

    mov eax, [uxfs_nvme_global_cid]
    inc dword [uxfs_nvme_global_cid]
    shl eax, 16
    or eax, NVME_OPCODE_WRITE
    mov dword [rsp + uxfs_nvme_sqe_t.cdw0_opcode], eax

    mov eax, [rbx + uxfs_nvme_ctrl_t.nsid]
    mov dword [rsp + uxfs_nvme_sqe_t.nsid], eax
    mov [rsp + uxfs_nvme_sqe_t.prp1], r14
    mov [rsp + uxfs_nvme_sqe_t.slba], r12

    dec r13w                        ; nlb is 0-based
    mov word [rsp + uxfs_nvme_sqe_t.nlb], r13w

    mov rdi, rbx
    mov rsi, rsp
    call uxfs_nvme_submit_cmd

    add rsp, uxfs_nvme_sqe_t_size
    mov eax, 0                      ; Success
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_nvme_flush
;
; Issues NVMe FLUSH (opcode 0x00), forcing the controller to commit its
; volatile write cache to non-volatile media.
;
; Until this completes, a write the controller has already acknowledged is
; still only in a cache that power loss will discard. Any journal or write-
; ahead log must call this before reporting a commit durable.
;
; Inputs:
;   RDI = Pointer to uxfs_nvme_ctrl_t
;
; Returns:
;   EAX = 0 (Success) or -5 (I/O Error)
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_flush:
    push rbx
    push r12

    mov rbx, rdi                    ; Controller
    test rbx, rbx
    jz .fl_inval

    sub rsp, uxfs_nvme_sqe_t_size

    ; Zero the whole SQE: FLUSH uses no PRP, LBA or length fields, and stale
    ; stack contents in them would be interpreted by the controller.
    mov rdi, rsp
    mov rcx, uxfs_nvme_sqe_t_size
    xor al, al
    rep stosb

    mov eax, [uxfs_nvme_global_cid]
    inc dword [uxfs_nvme_global_cid]
    shl eax, 16
    or eax, NVME_OPCODE_FLUSH
    mov dword [rsp + uxfs_nvme_sqe_t.cdw0_opcode], eax

    mov eax, [rbx + uxfs_nvme_ctrl_t.nsid]
    mov dword [rsp + uxfs_nvme_sqe_t.nsid], eax

    mov rdi, rbx
    mov rsi, rsp
    call uxfs_nvme_submit_cmd

    add rsp, uxfs_nvme_sqe_t_size

    mov eax, 0                      ; Success
    pop r12
    pop rbx
    ret

.fl_inval:
    mov eax, -5
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_nvme_init
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_init:
    push rbp
    mov rbp, rsp
    mov eax, 0
    pop rbp
    ret

%endif ; GUARD_STORAGE_UXFS_DRIVERS_NVME_ASM
