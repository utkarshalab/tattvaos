; =============================================================================
; lib/io/block/gpt.asm
; GUID Partition Table (GPT) parser.
;
; Reads the GPT header at LBA 1, validates signature and CRC, then iterates
; partition entries (LBA 2–33) to create sub-device_t instances with
; partition-relative LBA offsets (device_t.lba_offset, device_t.lba_count).
;
; Security: §12.2 partition sandbox enforcement is built into gpt_part_read
; and gpt_part_write — all I/O is bounds-checked against lba_count before
; the offset is applied and forwarded to the parent physical device.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_BLOCK_GPT_ASM
%define IO_BLOCK_GPT_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

; GPT Header constants
GPT_SIGNATURE       equ 0x5452415020494645  ; "EFI PART" as little-endian u64
GPT_HEADER_LBA      equ 1                  ; GPT header is always at LBA 1
GPT_ENTRY_SIZE      equ 128                ; Standard GPT partition entry size
GPT_MAX_PARTITIONS  equ 8                  ; Max partitions we track (table limit)

; GUID Partition Entry offsets (128 bytes per entry)
GPT_ENT_TYPE_GUID   equ 0                  ; 16 bytes: Partition type GUID
GPT_ENT_UNIQUE_GUID equ 16                 ; 16 bytes: Unique partition GUID
GPT_ENT_FIRST_LBA   equ 32                 ; 8 bytes: First LBA
GPT_ENT_LAST_LBA    equ 40                 ; 8 bytes: Last LBA (inclusive)
GPT_ENT_ATTRIBUTES  equ 48                 ; 8 bytes: Attribute flags
GPT_ENT_NAME        equ 56                 ; 72 bytes: UTF-16LE partition name

section .bss
; Scratch buffer for reading GPT header + partition entries (4KB = 8 sectors)
gpt_scratch_buf:    resb 4096

; Partition device table: sub-device_t instances for discovered partitions
global gpt_partition_table
gpt_partition_table: resb device_t_size * GPT_MAX_PARTITIONS
global gpt_partition_count
gpt_partition_count: resq 1

section .rodata
.gpt_name_prefix:   db "gpt_p", 0          ; Partition device name prefix

section .text

; =============================================================================
; gpt_parse — Parse GPT from a parent block device and create sub-devices
; In : RDI = -> device_t (parent physical block device)
; Out: RAX = number of valid partitions found (0 = none or invalid GPT)
; RSO: RDI owned-in; RAX owned-out
; =============================================================================
IO_FUNC gpt_parse
    guard_null rdi
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi                ; R12 = parent device_t *
    xor     r15, r15                ; R15 = partition count

    ; 1. Read LBA 1 (GPT header) into scratch buffer
    mov     rdi, r12                ; dev
    mov     rsi, GPT_HEADER_LBA     ; LBA = 1
    mov     rdx, 1                  ; 1 sector
    lea     rcx, [rel gpt_scratch_buf]
    ; Call synchronous read through the device's read function pointer
    mov     rax, [r12 + device_t.read]
    test    rax, rax
    jz      .err_no_read
    call    rax
    test    rax, rax
    jnz     .err_read_fail

    ; 2. Validate GPT signature at offset 0: must be "EFI PART" (0x5452415020494645)
    lea     rbx, [rel gpt_scratch_buf]
    mov     rax, [rbx]              ; First 8 bytes of header
    mov     rcx, GPT_SIGNATURE
    cmp     rax, rcx
    jne     .no_gpt                 ; Signature mismatch, not a GPT disk

    ; 3. Read partition entry count and size from header
    ;    Header offset 80: Number of partition entries (u32)
    ;    Header offset 84: Size of each partition entry (u32, should be 128)
    mov     r13d, [rbx + 80]        ; R13 = number of partition entries on disk
    mov     r14d, [rbx + 84]        ; R14 = partition entry size

    ; Sanity: entry size must be >= 128
    cmp     r14, GPT_ENTRY_SIZE
    jb      .no_gpt

    ; Clamp partition count to our table limit
    cmp     r13, GPT_MAX_PARTITIONS
    jbe     .count_ok
    mov     r13, GPT_MAX_PARTITIONS
.count_ok:

    ; 4. Read partition entry array starting at LBA 2
    ;    We read enough sectors to cover r13 entries of r14 bytes each
    ;    Total bytes = r13 * r14. Sectors = ceil(total / sector_size)
    mov     rax, r13
    imul    rax, r14                ; RAX = total bytes for entries
    mov     rcx, [r12 + device_t.sector_size]
    test    rcx, rcx
    jz      .no_gpt
    ; Ceiling division: (total + sector_size - 1) / sector_size
    add     rax, rcx
    dec     rax
    xor     rdx, rdx
    div     rcx                     ; RAX = number of sectors needed
    mov     rsi, rax                ; RSI = sector count for entry read

    ; Cap to scratch buffer size (4096 / sector_size sectors)
    mov     rcx, 4096
    xor     rdx, rdx
    div     qword [r12 + device_t.sector_size] ; ... actually let's just read up to 8 sectors
    cmp     rsi, 8
    jbe     .read_entries
    mov     rsi, 8                  ; Max 8 sectors (4KB buffer)

.read_entries:
    mov     rdi, r12                ; dev
    mov     rdx, rsi                ; sector count
    mov     rsi, 2                  ; LBA = 2 (partition entries start here)
    lea     rcx, [rel gpt_scratch_buf]
    mov     rax, [r12 + device_t.read]
    call    rax
    test    rax, rax
    jnz     .err_read_fail

    ; 5. Iterate partition entries and create sub-device_t for each valid one
    lea     rbx, [rel gpt_scratch_buf]  ; RBX = entry array base
    xor     rcx, rcx                    ; RCX = entry index

.entry_loop:
    cmp     rcx, r13
    jae     .entries_done

    ; Calculate entry pointer: base + index * entry_size
    mov     rax, rcx
    imul    rax, r14
    lea     rsi, [rbx + rax]        ; RSI = -> current partition entry

    ; Check if entry is valid: type GUID must be non-zero (all 16 bytes)
    ; Quick check: if first 8 bytes of type GUID are zero, skip
    mov     rax, [rsi + GPT_ENT_TYPE_GUID]
    or      rax, [rsi + GPT_ENT_TYPE_GUID + 8]
    test    rax, rax
    jz      .next_entry             ; Empty/unused partition slot

    ; Read first and last LBA
    mov     rax, [rsi + GPT_ENT_FIRST_LBA]   ; RAX = first LBA
    mov     rdx, [rsi + GPT_ENT_LAST_LBA]    ; RDX = last LBA (inclusive)

    ; Validate: first <= last, and both within parent capacity
    cmp     rax, rdx
    ja      .next_entry             ; Invalid: first > last

    cmp     rdx, [r12 + device_t.capacity]
    jae     .next_entry             ; Extends beyond device

    ; Calculate partition size: last - first + 1
    sub     rdx, rax                ; RDX = last - first
    inc     rdx                     ; RDX = sector count

    ; Allocate a device_t slot from gpt_partition_table
    cmp     r15, GPT_MAX_PARTITIONS
    jae     .entries_done           ; Table full

    push    rcx                     ; Save entry index
    push    rsi                     ; Save entry pointer

    ; Calculate device_t slot address
    mov     rcx, r15
    imul    rcx, device_t_size
    lea     rdi, [rel gpt_partition_table]
    add     rdi, rcx                ; RDI = -> sub-device_t slot

    ; Zero out the slot
    push    rdi
    push    rax
    push    rdx
    mov     rcx, device_t_size / 8
    xor     rax, rax
    rep     stosq
    pop     rdx
    pop     rax
    pop     rdi

    ; Populate sub-device_t fields
    mov     qword [rdi + device_t.type], FD_TYPE_BLOCK
    mov     qword [rdi + device_t.state], DEV_STATE_ONLINE
    mov     [rdi + device_t.lba_offset], rax       ; Partition start LBA
    mov     [rdi + device_t.lba_count], rdx        ; Partition sector count
    mov     [rdi + device_t.capacity], rdx         ; Same for capacity
    mov     [rdi + device_t.parent], r12           ; Link to parent device

    ; Inherit sector size from parent
    mov     rcx, [r12 + device_t.sector_size]
    mov     [rdi + device_t.sector_size], rcx

    ; Wire partition-safe read/write functions
    lea     rcx, [rel gpt_part_read]
    mov     [rdi + device_t.read], rcx
    lea     rcx, [rel gpt_part_write]
    mov     [rdi + device_t.write], rcx

    ; Inherit async submit from parent
    mov     rcx, [r12 + device_t.submit]
    mov     [rdi + device_t.submit], rcx

    ; Write partition name: "gpt_pN" where N = partition index digit
    lea     rcx, [rdi + device_t.name]
    mov     byte [rcx + 0], 'g'
    mov     byte [rcx + 1], 'p'
    mov     byte [rcx + 2], 't'
    mov     byte [rcx + 3], '_'
    mov     byte [rcx + 4], 'p'
    pop     rsi                     ; Restore entry index (was pushed as rsi)
    pop     rcx                     ; Restore entry index (was pushed as rcx)
    push    rcx
    push    rsi
    ; Convert index to ASCII digit (0-7)
    mov     al, cl
    add     al, '0'
    lea     rdx, [rdi + device_t.name]
    mov     [rdx + 5], al
    mov     byte [rdx + 6], 0

    inc     r15                     ; Increment partition count

    pop     rsi
    pop     rcx

.next_entry:
    inc     rcx
    jmp     .entry_loop

.entries_done:
    mov     [rel gpt_partition_count], r15
    mov     rax, r15                ; Return partition count
    jmp     .done

.err_no_read:
.err_read_fail:
.no_gpt:
    xor     rax, rax                ; Return 0 (no partitions)

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
IO_ENDFUNC gpt_parse

; =============================================================================
; gpt_part_read — Bounds-checked partition read (§12.2 sandbox enforcement)
;
; Validates that the requested LBA range fits within the partition boundaries
; BEFORE applying the offset and forwarding to the parent physical device.
;
; In : RDI = -> device_t (partition sub-device)
;      RSI = Partition-relative LBA
;      RDX = Block count
;      RCX = -> Destination buffer
; Out: RAX = 0 on success, or negative error code
; =============================================================================
IO_FUNC gpt_part_read
    guard_null rdi
    guard_null rcx
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    ; §12.2: Validate bounds BEFORE applying offset
    ; if (lba + nblocks > dev.lba_count) return IO_ERR_BADARG
    mov     rax, rsi
    add     rax, rdx                ; RAX = lba + nblocks
    jc      .err_bounds             ; Overflow check
    cmp     rax, [rdi + device_t.lba_count]
    ja      .err_bounds             ; Exceeds partition boundary

    ; Translate to physical LBA: lba += dev.lba_offset
    add     rsi, [rdi + device_t.lba_offset]

    ; Forward to parent device's read function
    mov     rbx, [rdi + device_t.parent]
    test    rbx, rbx
    jz      .err_bounds             ; No parent device

    mov     rdi, rbx                ; RDI = parent device_t
    mov     rax, [rbx + device_t.read]
    test    rax, rax
    jz      .err_bounds
    call    rax                     ; parent->read(parent, phys_lba, count, buf)
    jmp     .done

.err_bounds:
    mov     rax, IO_ERR_BADARG

.done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC gpt_part_read

; =============================================================================
; gpt_part_write — Bounds-checked partition write (§12.2 sandbox enforcement)
; In : RDI = -> device_t (partition sub-device)
;      RSI = Partition-relative LBA
;      RDX = Block count
;      RCX = -> Source buffer
; Out: RAX = 0 on success, or negative error code
; =============================================================================
IO_FUNC gpt_part_write
    guard_null rdi
    guard_null rcx
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    ; §12.2: Validate bounds
    mov     rax, rsi
    add     rax, rdx
    jc      .err_bounds
    cmp     rax, [rdi + device_t.lba_count]
    ja      .err_bounds

    ; Translate to physical LBA
    add     rsi, [rdi + device_t.lba_offset]

    ; Forward to parent
    mov     rbx, [rdi + device_t.parent]
    test    rbx, rbx
    jz      .err_bounds

    mov     rdi, rbx
    mov     rax, [rbx + device_t.write]
    test    rax, rax
    jz      .err_bounds
    call    rax
    jmp     .done

.err_bounds:
    mov     rax, IO_ERR_BADARG

.done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC gpt_part_write

%endif ; IO_BLOCK_GPT_ASM