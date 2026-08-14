%ifndef KERNEL_STREAM_ASM
%define KERNEL_STREAM_ASM
; =============================================================================
; Tattva OS — boot/stage2/fs/kernel_stream.asm
; =============================================================================
; Streams the whole ULF kernel image from raw disk sectors to KERNEL_LOAD (1MB).
;
; Why this exists: the kernel is 9.3MB and BIOS INT 13h can only land data
; inside the first megabyte, so it cannot be read to its final home directly.
; The previous path read KERNEL_SECTORS (64 sectors = 32KB) into a real-mode
; buffer and copied that fixed amount up in long mode — enough for a stub
; kernel, three orders of magnitude short of this one.
;
; The loop here reads a 32KB chunk into the KERNEL_TEMP bounce buffer, then
; copies that chunk above 1MB from real mode through a flat ES descriptor
; ("unreal mode"): enter protected mode with interrupts off, load ES from a
; 4GB-limit data descriptor, leave protected mode again. Clearing CR0.PE does
; not reload the segment descriptor cache, so ES keeps the large limit and a
; 32-bit-addressed `rep movsd` through it reaches anywhere in the first 4GB
; while the BIOS still sees ordinary real mode on the next INT 13h.
;
; The image length is not a build-time constant. The first sector is read on
; its own and the ULF header's size field says how many more to fetch, so the
; loader stays correct across kernel rebuilds with nothing to update here.
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit) with unreal-mode data access
; =============================================================================

[BITS 16]

KS_CHUNK_SECTORS equ 64             ; 32KB per INT 13h call. AH=42h is only
                                    ; specified up to 127 sectors and some
                                    ; BIOSes cap lower; 64 is universally safe
                                    ; and keeps a whole chunk inside the 64KB
                                    ; real-mode window the bounce buffer sits in.
KS_SEL_FLAT      equ 0x08           ; index 1 of ks_gdt
KS_ULF_MAGIC     equ 0x00464C55     ; "ULF\0"
KS_MAX_BYTES     equ 32 * 1024 * 1024

; =============================================================================
; kernel_stream_load — load the ULF image from LBA KERNEL_LBA to KERNEL_LOAD.
; Input:  [boot_drive]
; Output: AX = 1 on success, 0 on failure. Prints progress on the UART.
; =============================================================================
kernel_stream_load:
    pushad
    push es

    ; -------------------------------------------------------------------------
    ; Read the first sector alone to learn how long the image is.
    ; -------------------------------------------------------------------------
    mov dword [ks_lba], KERNEL_LBA
    mov word [ks_count], 1
    call ks_read_chunk
    jc .fail_read

    mov ax, KERNEL_TEMP >> 4
    mov es, ax
    cmp dword [es:0], KS_ULF_MAGIC
    jne .fail_magic
    mov eax, [es:4]                 ; ULF header +4: image length in bytes

    cmp eax, 32                     ; smaller than its own header
    jb .fail_size
    cmp eax, KS_MAX_BYTES
    ja .fail_size

    add eax, 511                    ; round up to whole sectors
    shr eax, 9
    mov [ks_left], eax

    ; -------------------------------------------------------------------------
    ; Stream the image a chunk at a time. Sector zero is read a second time as
    ; part of chunk zero; one redundant 512-byte read is worth not having a
    ; special case for the first chunk.
    ; -------------------------------------------------------------------------
    mov dword [ks_lba], KERNEL_LBA
    mov dword [ks_dest], KERNEL_LOAD
    mov word [ks_tick], 0

.next:
    mov eax, [ks_left]
    test eax, eax
    jz .done
    cmp eax, KS_CHUNK_SECTORS
    jbe .tail
    mov eax, KS_CHUNK_SECTORS
.tail:
    mov [ks_count], ax

    call ks_read_chunk
    jc .fail_read
    call ks_flush_chunk

    movzx eax, word [ks_count]
    add [ks_lba], eax
    sub [ks_left], eax
    shl eax, 9
    add [ks_dest], eax

    ; A dot per megabyte. Without it a stalled controller looks identical to a
    ; hang in the copy, and this loop runs for 300 BIOS calls.
    inc word [ks_tick]
    test word [ks_tick], 31
    jnz .next
    mov al, '.'
    call uart_putc
    jmp .next

.done:
    pop es
    popad
    mov ax, 1
    ret

.fail_magic:
    mov si, ks_msg_magic
    jmp .fail
.fail_size:
    mov si, ks_msg_size
    jmp .fail
.fail_read:
    mov si, ks_msg_read
.fail:
    call uart_println
    pop es
    popad
    xor ax, ax
    ret

; =============================================================================
; ks_read_chunk — read [ks_count] sectors from LBA [ks_lba] into KERNEL_TEMP.
; Output: CF clear on success, CF set after DISK_RETRY failed attempts.
;         On failure the last BIOS status byte is left in [ks_bios_err].
; =============================================================================
ks_read_chunk:
    pushad

    mov ax, [ks_count]
    mov [ks_dap.sectors], ax
    mov eax, [ks_lba]
    mov [ks_dap.lba], eax
    mov dword [ks_dap.lba + 4], 0

    mov cx, DISK_RETRY
.attempt:
    push cx
    mov si, ks_dap
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    pop cx
    jnc .ok

    mov [ks_bios_err], ah

    ; Reset the controller before retrying. A latched error status makes every
    ; subsequent read fail even when the media is fine.
    push cx
    xor ax, ax
    mov dl, [boot_drive]
    int 0x13
    pop cx
    dec cx
    jnz .attempt

    popad
    stc
    ret

.ok:
    popad
    clc
    ret

; =============================================================================
; ks_flush_chunk — copy [ks_count] * 512 bytes from KERNEL_TEMP to [ks_dest].
;
; The destination is above 1MB, which no real-mode segment can reach, so ES is
; loaded from a 4GB-limit descriptor during a brief excursion into protected
; mode. CS is never reloaded, so execution continues straight through; only ES
; picks up the new limit, and it keeps it after CR0.PE goes back to zero.
;
; Interrupts stay off across the whole copy. An interrupt taken while ES holds
; the flat descriptor would run a BIOS handler that reloads ES with a real-mode
; value, silently shrinking the limit back to 64KB and truncating the copy.
; =============================================================================
ks_flush_chunk:
    pushad
    push ds
    push es

    ; Read the parameters while DS still addresses stage2's data.
    movzx ecx, word [ks_count]
    shl ecx, 7                      ; sectors * 512 / 4 = dwords to move
    mov edi, [ks_dest]

    cli
    lgdt [ks_gdtr]
    mov eax, cr0
    or al, 1
    mov cr0, eax                    ; protected mode; CS descriptor cache intact
    mov bx, KS_SEL_FLAT
    mov es, bx                      ; ES.base = 0, ES.limit = 4GB
    and al, 0xFE
    mov cr0, eax                    ; real mode again; ES cache survives

    mov ax, KERNEL_TEMP >> 4
    mov ds, ax                      ; source stays inside DS's 64KB real limit
    xor esi, esi
    cld
    a32 rep movsd

    pop es
    pop ds
    sti
    popad
    ret

; =============================================================================
; ks_report_error — print the BIOS status byte behind a read failure.
; Uses the description table in stage2/hw/disk_errors.asm.
; =============================================================================
ks_report_error:
    pusha
    mov si, ks_msg_err_prefix
    call uart_print
    mov al, [ks_bios_err]
    call uart_print_hex8
    mov si, ks_msg_err_dash
    call uart_print

    mov dl, [ks_bios_err]
    mov si, bios_error_table
.lookup:
    mov al, [si]
    test al, al
    jz .unknown
    cmp al, dl
    je .found
    add si, 3                       ; 1 byte code + 2 byte string pointer
    jmp .lookup
.found:
    mov si, [si + 1]
    jmp .print
.unknown:
    mov si, err_str_unknown
.print:
    call uart_print
    mov si, ks_msg_err_suffix
    call uart_println
    popa
    ret

; =============================================================================
; Data
; =============================================================================
align 4
ks_dap:                             ; INT 13h AH=42h disk address packet
    db 0x10                         ; packet size
    db 0                            ; reserved
.sectors:
    dw 0
    dw 0                            ; buffer offset
    dw KERNEL_TEMP >> 4             ; buffer segment
.lba:
    dq 0

align 16
ks_gdt:
    dq 0x0000000000000000           ; null descriptor
    dq 0x00CF92000000FFFF           ; flat data: base 0, limit 4GB, RW, G=1, B=1
ks_gdt_end:

align 4
ks_gdtr:
    dw ks_gdt_end - ks_gdt - 1
    dd ks_gdt                       ; stage2 runs with all segment bases at 0,
                                    ; so the ORG-relative label is already the
                                    ; linear address LGDT wants

align 4
ks_lba:         dd 0                ; LBA of the chunk being read
ks_dest:        dd 0                ; physical address the chunk lands at
ks_left:        dd 0                ; sectors still to fetch
ks_count:       dw 0                ; sectors in the current chunk
ks_tick:        dw 0                ; chunks done, for the progress dots
ks_bios_err:    db 0                ; last INT 13h status byte

ks_msg_read:        db "FAIL (disk read error)", 0
ks_msg_magic:       db "FAIL (no ULF magic at kernel LBA)", 0
ks_msg_size:        db "FAIL (implausible ULF image size)", 0
ks_msg_err_prefix:  db "  BIOS status 0x", 0
ks_msg_err_dash:    db " - ", 0
ks_msg_err_suffix:  db "", 0

%endif ; KERNEL_STREAM_ASM
