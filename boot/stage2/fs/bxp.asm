; =============================================================================
; Tattva OS — boot/stage2/fs/bxp.asm
; =============================================================================
; BXP (Boot eXecution Package) — Tattva native boot format.
;
; BXP is a simple, flat boot image format designed for fast, verified
; kernel loading. It prioritizes simplicity and integrity over features.
;
; BXP volume layout:
;   Sector 0:     BXP header (512 bytes)
;   Sector 1-N:   Kernel image (raw binary, padded to sector boundary)
;
; BXP header format (512 bytes):
;   Offset  Size  Field
;   0x00    4     Magic ("BXP\0" = 0x00505842)
;   0x04    4     Version (1)
;   0x08    4     Header size (512)
;   0x0C    4     Kernel size in bytes
;   0x10    4     Kernel load address (physical)
;   0x14    4     Kernel entry offset (relative to load address)
;   0x18    4     Flags (bit 0: compressed, bit 1: signed)
;   0x1C    4     CRC32 of kernel image (0 = unchecked)
;   0x20    32    SHA-256 hash of kernel (all zeros = unchecked)
;   0x40    64    Reserved (must be zero)
;   0x80    128   Build string (null-terminated ASCII, e.g. "TattvaOS v0.1")
;   0x100   256   Padding (zero)
;
; Author:  Utkarsha Labs
; Target:  x86-64, long mode (64-bit)
; =============================================================================

%ifndef BXP_ASM
%define BXP_ASM

[BITS 64]

; BXP constants
BXP_MAGIC           equ 0x00505842  ; "BXP\0" in little-endian
BXP_VERSION          equ 1
BXP_HEADER_SIZE      equ 512

; BXP header field offsets
BXP_HDR_MAGIC        equ 0x00
BXP_HDR_VERSION      equ 0x04
BXP_HDR_HEADER_SZ    equ 0x08
BXP_HDR_KERNEL_SZ    equ 0x0C
BXP_HDR_LOAD_ADDR    equ 0x10
BXP_HDR_ENTRY_OFF    equ 0x14
BXP_HDR_FLAGS        equ 0x18
BXP_HDR_CRC32        equ 0x1C
BXP_HDR_SHA256       equ 0x20
BXP_HDR_BUILD_STR    equ 0x80

; BXP flags
BXP_FLAG_COMPRESSED  equ (1 << 0)   ; kernel image is compressed
BXP_FLAG_SIGNED      equ (1 << 1)   ; kernel image is signed (SHA-256)

; Scratch buffer for BXP header reads
BXP_SCRATCH          equ 0x52000

; =============================================================================
; bxp_detect — check if a partition contains a BXP volume
; Input:  RAX = starting LBA of partition
; Output: CF clear = valid BXP volume detected
;         CF set   = not a BXP volume
;         [bxp_part_lba] = partition start LBA (if valid)
; Clobbers: RAX, RCX, RDX, RSI, RDI
; =============================================================================
bxp_detect:
    push rbx

    mov [bxp_part_lba], rax         ; save partition start

    ; Read first sector (BXP header)
    mov rdi, BXP_SCRATCH
    mov ecx, 1                      ; 1 sector = 512 bytes
    call bxp_read_sectors
    jc .not_bxp

    ; Validate magic
    mov rsi, BXP_SCRATCH
    mov eax, [rsi + BXP_HDR_MAGIC]
    cmp eax, BXP_MAGIC
    jne .not_bxp

    ; Validate version
    mov eax, [rsi + BXP_HDR_VERSION]
    cmp eax, BXP_VERSION
    jne .not_bxp                    ; unsupported version

    ; Validate header size
    mov eax, [rsi + BXP_HDR_HEADER_SZ]
    cmp eax, BXP_HEADER_SIZE
    jne .not_bxp

    ; Validate kernel size is non-zero and reasonable (< 16MB)
    mov eax, [rsi + BXP_HDR_KERNEL_SZ]
    test eax, eax
    jz .not_bxp
    cmp eax, 16 * 1024 * 1024       ; 16MB max
    ja .not_bxp

    pop rbx
    clc                              ; valid BXP
    ret

.not_bxp:
    pop rbx
    stc                              ; not BXP
    ret

; =============================================================================
; bxp_load_kernel — load kernel from BXP volume
; Input:  none (uses [bxp_part_lba] set by bxp_detect)
; Output: RAX = kernel entry point (physical address)
;         RCX = kernel size in bytes
;         CF clear = success, CF set = failure
; Clobbers: RDX, RSI, RDI
;
; Loads the kernel image from sectors 1+ of the BXP volume into
; the physical address specified in the BXP header (BXP_HDR_LOAD_ADDR).
; =============================================================================
bxp_load_kernel:
    push rbx
    push r12
    push r13

    ; Re-read header (may have been overwritten)
    mov rax, [bxp_part_lba]
    mov rdi, BXP_SCRATCH
    mov ecx, 1
    call bxp_read_sectors
    jc .load_fail

    mov rsi, BXP_SCRATCH

    ; Extract kernel parameters
    mov r12d, [rsi + BXP_HDR_KERNEL_SZ]     ; R12D = kernel size
    mov eax, [rsi + BXP_HDR_LOAD_ADDR]      ; EAX = load address
    mov r13d, [rsi + BXP_HDR_ENTRY_OFF]      ; R13D = entry offset

    ; Calculate sectors needed: (kernel_size + 511) / 512
    mov ecx, r12d
    add ecx, 511
    shr ecx, 9                      ; ECX = sector count

    ; Read kernel data from LBA = partition_start + 1
    mov rax, [bxp_part_lba]
    inc rax                         ; skip header sector

    ; Load to the address specified in header
    xor rdi, rdi
    mov edi, [BXP_SCRATCH + BXP_HDR_LOAD_ADDR]
    call bxp_read_sectors
    jc .load_fail

    ; Verify CRC32 if non-zero
    mov eax, [BXP_SCRATCH + BXP_HDR_CRC32]
    test eax, eax
    jz .skip_crc                    ; CRC = 0 means unchecked

    ; TODO: implement CRC32 verification
    ; For now, skip CRC check

.skip_crc:
    ; Return entry point and size
    xor rax, rax
    mov eax, [BXP_SCRATCH + BXP_HDR_LOAD_ADDR]
    add eax, r13d                   ; entry = load_addr + entry_offset
    mov ecx, r12d                   ; size

    pop r13
    pop r12
    pop rbx
    clc
    ret

.load_fail:
    pop r13
    pop r12
    pop rbx
    stc
    ret

; =============================================================================
; bxp_read_sectors — read sectors from BXP partition
; Input:  RAX = starting LBA (absolute)
;         RDI = destination buffer
;         ECX = number of sectors
; Output: CF clear = success, CF set = failure
; =============================================================================
bxp_read_sectors:
    ; TODO: Connect to hw/disk.asm disk_read_sectors_64
    stc
    ret

; =============================================================================
; Data
; =============================================================================
bxp_part_lba:       dq 0            ; BXP partition start LBA

[BITS 16]

%endif ; BXP_ASM
