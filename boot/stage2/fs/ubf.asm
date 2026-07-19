; =============================================================================
; Tattva OS — boot/stage2/fs/ubf.asm
; =============================================================================
; UBF (Utkarsha Boot Format) — unified boot image container.
;
; UBF is a multi-component boot container that packages the kernel,
; initrd, device tree, and configuration into a single sequential
; image. Designed for verified, deterministic boot sequences.
;
; UBF image layout:
;   Sector 0-1:   UBF header (1024 bytes)
;   Sector 2+:    Component data (sequential, sector-aligned)
;
; UBF header format (1024 bytes):
;   Offset  Size  Field
;   0x000   8     Magic ("UBFORMAT" = 0x54414D524F465255)
;   0x008   4     Version (1)
;   0x00C   4     Total image size in sectors
;   0x010   4     Component count (1-8)
;   0x014   4     Header CRC32
;   0x018   4     Flags (bit 0: all components signed)
;   0x01C   4     Reserved
;   0x020   512   Component table (up to 8 entries, 64 bytes each)
;   0x220   288   Padding / future extensions
;
; Component table entry (64 bytes each):
;   Offset  Size  Field
;   0x00    4     Component type (see UBF_COMP_* constants)
;   0x04    4     Start sector (relative to image start)
;   0x08    4     Size in bytes
;   0x0C    4     Load address (physical)
;   0x10    4     Entry offset (relative to load address, for kernel)
;   0x14    4     Flags
;   0x18    32    SHA-256 hash
;   0x38    8     Reserved
;
; Author:  Utkarsha Labs
; Target:  x86-64, long mode (64-bit)
; =============================================================================

%ifndef UBF_ASM
%define UBF_ASM

[BITS 64]

; UBF constants
UBF_MAGIC           equ 0x54414D524F465255  ; "UBFORMAT" in little-endian
UBF_VERSION          equ 1
UBF_HEADER_SECTORS   equ 2                  ; header = 1024 bytes = 2 sectors
UBF_MAX_COMPONENTS   equ 8

; UBF header field offsets
UBF_HDR_MAGIC        equ 0x000
UBF_HDR_VERSION      equ 0x008
UBF_HDR_TOTAL_SECTS  equ 0x00C
UBF_HDR_COMP_COUNT   equ 0x010
UBF_HDR_CRC32        equ 0x014
UBF_HDR_FLAGS        equ 0x018
UBF_HDR_COMP_TABLE   equ 0x020

; Component types
UBF_COMP_KERNEL      equ 1          ; kernel binary
UBF_COMP_INITRD      equ 2          ; initial ramdisk
UBF_COMP_DTB         equ 3          ; device tree blob
UBF_COMP_CONFIG      equ 4          ; boot configuration
UBF_COMP_MODULE      equ 5          ; loadable module
UBF_COMP_FIRMWARE    equ 6          ; firmware blob (GPU, NIC, etc.)

; Component entry field offsets (within 64-byte entry)
UBF_CE_TYPE          equ 0x00
UBF_CE_START_SECT    equ 0x04
UBF_CE_SIZE          equ 0x08
UBF_CE_LOAD_ADDR     equ 0x0C
UBF_CE_ENTRY_OFF     equ 0x10
UBF_CE_FLAGS         equ 0x14
UBF_CE_SHA256        equ 0x18
UBF_CE_SIZE_ENTRY    equ 64         ; size of each component entry

; Scratch buffer
UBF_SCRATCH          equ 0x54000

; =============================================================================
; ubf_detect — check if a partition contains a UBF image
; Input:  RAX = starting LBA of partition
; Output: CF clear = valid UBF detected
;         CF set   = not a UBF image
;         [ubf_part_lba] = partition start LBA (if valid)
; Clobbers: RAX, RCX, RDX, RSI, RDI
; =============================================================================
ubf_detect:
    push rbx

    mov [ubf_part_lba], rax

    ; Read first 2 sectors (1024 bytes = UBF header)
    mov rdi, UBF_SCRATCH
    mov ecx, UBF_HEADER_SECTORS
    call ubf_read_sectors
    jc .not_ubf

    ; Validate 8-byte magic
    mov rsi, UBF_SCRATCH
    mov rax, [rsi + UBF_HDR_MAGIC]
    mov rbx, UBF_MAGIC
    cmp rax, rbx
    jne .not_ubf

    ; Validate version
    mov eax, [rsi + UBF_HDR_VERSION]
    cmp eax, UBF_VERSION
    jne .not_ubf

    ; Validate component count (1-8)
    mov eax, [rsi + UBF_HDR_COMP_COUNT]
    test eax, eax
    jz .not_ubf
    cmp eax, UBF_MAX_COMPONENTS
    ja .not_ubf

    ; Store component count
    mov [ubf_comp_count], eax

    pop rbx
    clc
    ret

.not_ubf:
    pop rbx
    stc
    ret

; =============================================================================
; ubf_find_component — find a component by type in the UBF header
; Input:  EDI = component type to find (e.g. UBF_COMP_KERNEL)
; Output: RSI = pointer to component entry in UBF_SCRATCH (or 0 if not found)
;         CF clear = found, CF set = not found
; Clobbers: RAX, RCX, RDX
;
; Prerequisite: ubf_detect must have been called successfully.
; =============================================================================
ubf_find_component:
    push rbx

    mov ecx, [ubf_comp_count]
    lea rsi, [UBF_SCRATCH + UBF_HDR_COMP_TABLE]

.search:
    test ecx, ecx
    jz .comp_not_found

    mov eax, [rsi + UBF_CE_TYPE]
    cmp eax, edi
    je .comp_found

    add rsi, UBF_CE_SIZE_ENTRY      ; next entry
    dec ecx
    jmp .search

.comp_found:
    pop rbx
    clc
    ret

.comp_not_found:
    xor rsi, rsi
    pop rbx
    stc
    ret

; =============================================================================
; ubf_load_kernel — find and load the kernel component
; Input:  none (uses ubf_part_lba from ubf_detect)
; Output: RAX = kernel entry point (physical address)
;         RCX = kernel size in bytes
;         CF clear = success, CF set = failure
; Clobbers: RDX, RSI, RDI
; =============================================================================
ubf_load_kernel:
    push rbx
    push r12
    push r13

    ; Re-read header
    mov rax, [ubf_part_lba]
    mov rdi, UBF_SCRATCH
    mov ecx, UBF_HEADER_SECTORS
    call ubf_read_sectors
    jc .kern_fail

    ; Find kernel component
    mov edi, UBF_COMP_KERNEL
    call ubf_find_component
    jc .kern_fail                    ; no kernel component

    ; Extract component fields
    mov r12d, [rsi + UBF_CE_SIZE]        ; R12D = kernel size
    mov ebx, [rsi + UBF_CE_LOAD_ADDR]    ; EBX = load address
    mov r13d, [rsi + UBF_CE_ENTRY_OFF]   ; R13D = entry offset
    mov eax, [rsi + UBF_CE_START_SECT]   ; EAX = start sector (relative)

    ; Calculate absolute LBA
    xor rdx, rdx
    mov edx, eax
    add rdx, [ubf_part_lba]         ; absolute LBA

    ; Calculate sectors needed
    mov ecx, r12d
    add ecx, 511
    shr ecx, 9                      ; sector count

    ; Load to specified address
    mov rax, rdx
    xor rdi, rdi
    mov edi, ebx                    ; destination = load address
    call ubf_read_sectors
    jc .kern_fail

    ; Return entry point
    xor rax, rax
    mov eax, ebx                    ; load address
    add eax, r13d                   ; + entry offset
    mov ecx, r12d                   ; kernel size

    pop r13
    pop r12
    pop rbx
    clc
    ret

.kern_fail:
    pop r13
    pop r12
    pop rbx
    stc
    ret

; =============================================================================
; ubf_load_component — load any component by type
; Input:  EDI = component type
;         RDX = destination buffer (override, 0 = use header's load_addr)
; Output: RAX = bytes loaded
;         CF clear = success, CF set = failure
; Clobbers: RCX, RSI
; =============================================================================
ubf_load_component:
    push rbx
    push r12

    call ubf_find_component
    jc .comp_fail

    mov r12d, [rsi + UBF_CE_SIZE]
    mov eax, [rsi + UBF_CE_START_SECT]

    ; Determine destination
    test rdx, rdx
    jnz .use_override
    xor rdi, rdi
    mov edi, [rsi + UBF_CE_LOAD_ADDR]
    jmp .do_load
.use_override:
    mov rdi, rdx

.do_load:
    xor rdx, rdx
    mov edx, eax
    add rdx, [ubf_part_lba]

    mov ecx, r12d
    add ecx, 511
    shr ecx, 9

    mov rax, rdx
    call ubf_read_sectors
    jc .comp_fail

    xor rax, rax
    mov eax, r12d                   ; bytes loaded

    pop r12
    pop rbx
    clc
    ret

.comp_fail:
    pop r12
    pop rbx
    stc
    ret

; =============================================================================
; ubf_read_sectors — read sectors from disk
; Input:  RAX = starting LBA (absolute)
;         RDI = destination buffer
;         ECX = number of sectors
; Output: CF clear = success, CF set = failure
; =============================================================================
ubf_read_sectors:
    ; TODO: Connect to hw/disk.asm disk_read_sectors_64
    stc
    ret

; =============================================================================
; Data
; =============================================================================
ubf_part_lba:       dq 0            ; UBF partition start LBA
ubf_comp_count:     dd 0            ; number of components in image

[BITS 16]

%endif ; UBF_ASM
