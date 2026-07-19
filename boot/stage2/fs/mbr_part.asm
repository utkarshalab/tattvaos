; =============================================================================
; Tattva OS — boot/stage2/fs/mbr_part.asm
; =============================================================================
; MBR partition table parser.
;
; Scans the 4 MBR partition entries (at offset 446 in the MBR sector)
; to find the active boot partition or a partition by type byte.
;
; MBR partition entry layout (16 bytes each, 4 entries):
;   Offset  Size  Field
;   0x00    1     Status (0x80 = active/bootable, 0x00 = inactive)
;   0x01    3     CHS of first sector
;   0x04    1     Partition type
;   0x05    3     CHS of last sector
;   0x08    4     LBA of first sector
;   0x0C    4     Size in sectors
;
; Common partition types:
;   0x01 = FAT12
;   0x04 = FAT16 (<32MB)
;   0x06 = FAT16 (>32MB)
;   0x07 = NTFS / exFAT
;   0x0B = FAT32 (CHS)
;   0x0C = FAT32 (LBA)
;   0x82 = Linux swap
;   0x83 = Linux native
;   0xEE = GPT protective MBR
;   0xEF = EFI System Partition
;
; Author:  Utkarsha Labs
; Target:  x86-64, long mode (64-bit)
; =============================================================================

%ifndef MBR_PART_ASM
%define MBR_PART_ASM

[BITS 64]

; Partition entry offsets within a 16-byte entry
MBR_PE_STATUS       equ 0x00       ; boot status byte
MBR_PE_TYPE         equ 0x04       ; partition type
MBR_PE_LBA_START    equ 0x08       ; starting LBA (dword)
MBR_PE_LBA_SIZE     equ 0x0C       ; size in sectors (dword)
MBR_PE_SIZE         equ 16         ; entry size
MBR_PE_COUNT        equ 4          ; number of entries
MBR_PT_OFFSET       equ 446        ; offset of partition table in MBR

; =============================================================================
; mbr_find_active — find the active (bootable) partition
; Input:  RSI = pointer to MBR sector data (512 bytes)
; Output: RAX = starting LBA of active partition (0 if none found)
;         RCX = size of partition in sectors (0 if none found)
;         RDX = partition type byte (zero-extended)
; Clobbers: RBX
; =============================================================================
mbr_find_active:
    push rsi
    push rdi

    lea rsi, [rsi + MBR_PT_OFFSET]  ; point to partition table
    mov ecx, MBR_PE_COUNT           ; 4 entries to scan

.scan_active:
    mov al, [rsi + MBR_PE_STATUS]   ; read status byte
    cmp al, 0x80                    ; active/bootable?
    je .found

    add rsi, MBR_PE_SIZE            ; next entry
    dec ecx
    jnz .scan_active

    ; No active partition found
    xor rax, rax
    xor rcx, rcx
    xor rdx, rdx

    pop rdi
    pop rsi
    ret

.found:
    ; Extract partition details
    xor rax, rax
    mov eax, [rsi + MBR_PE_LBA_START]   ; starting LBA

    xor rcx, rcx
    mov ecx, [rsi + MBR_PE_LBA_SIZE]    ; size in sectors

    xor rdx, rdx
    mov dl, [rsi + MBR_PE_TYPE]          ; partition type

    pop rdi
    pop rsi
    ret

; =============================================================================
; mbr_find_type — find a partition by type byte
; Input:  RSI = pointer to MBR sector data (512 bytes)
;         DIL = partition type to search for (e.g. 0x83 for Linux)
; Output: RAX = starting LBA of matching partition (0 if not found)
;         RCX = size of partition in sectors (0 if not found)
; Clobbers: RDX
; =============================================================================
mbr_find_type:
    push rsi
    push rbx

    lea rsi, [rsi + MBR_PT_OFFSET]  ; point to partition table
    mov ecx, MBR_PE_COUNT           ; 4 entries

.scan_type:
    mov al, [rsi + MBR_PE_TYPE]     ; read type byte
    cmp al, dil                     ; match requested type?
    je .type_found

    add rsi, MBR_PE_SIZE            ; next entry
    dec ecx
    jnz .scan_type

    ; Not found
    xor rax, rax
    xor rcx, rcx

    pop rbx
    pop rsi
    ret

.type_found:
    xor rax, rax
    mov eax, [rsi + MBR_PE_LBA_START]

    xor rcx, rcx
    mov ecx, [rsi + MBR_PE_LBA_SIZE]

    pop rbx
    pop rsi
    ret

; =============================================================================
; mbr_is_gpt_protective — check if MBR is a GPT protective MBR
; Input:  RSI = pointer to MBR sector data (512 bytes)
; Output: RAX = 1 if GPT protective MBR, 0 otherwise
; Clobbers: none
;
; A GPT protective MBR has a single partition entry with type 0xEE
; that spans the entire disk. This tells legacy MBR tools not to
; modify the disk.
; =============================================================================
mbr_is_gpt_protective:
    push rsi

    lea rsi, [rsi + MBR_PT_OFFSET]

    ; Check first partition entry for type 0xEE
    mov al, [rsi + MBR_PE_TYPE]
    cmp al, 0xEE
    jne .not_gpt

    mov rax, 1
    pop rsi
    ret

.not_gpt:
    xor rax, rax
    pop rsi
    ret

; =============================================================================
; mbr_count_partitions — count non-empty partition entries
; Input:  RSI = pointer to MBR sector data (512 bytes)
; Output: EAX = number of non-empty partitions (0-4)
; Clobbers: none
; =============================================================================
mbr_count_partitions:
    push rsi
    push rcx
    push rdx

    lea rsi, [rsi + MBR_PT_OFFSET]
    xor eax, eax                    ; count = 0
    mov ecx, MBR_PE_COUNT           ; 4 entries

.count_loop:
    mov dl, [rsi + MBR_PE_TYPE]     ; type byte
    test dl, dl                     ; type 0 = empty
    jz .count_skip
    inc eax                         ; count non-empty
.count_skip:
    add rsi, MBR_PE_SIZE
    dec ecx
    jnz .count_loop

    pop rdx
    pop rcx
    pop rsi
    ret

[BITS 16]

%endif ; MBR_PART_ASM
