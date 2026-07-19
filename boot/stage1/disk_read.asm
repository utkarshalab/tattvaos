; =============================================================================
; Tattva OS — boot/stage1/disk_read.asm
; =============================================================================
; Reusable BIOS disk read with retry logic.
;
; Provides a single entry point that handles both LBA (INT 13h AH=42h)
; and CHS (INT 13h AH=02h) reads with automatic 3-retry and disk reset
; on each failure attempt.
;
; This is a standalone reference module. entry.asm has similar logic inlined.
;
; Author:  Utkarsha Labs
; Target:  x86, real mode (16-bit)
; =============================================================================

%ifndef S1_DISK_READ_ASM
%define S1_DISK_READ_ASM

[BITS 16]

; =============================================================================
; s1_disk_read_lba — read sectors using LBA extended read (INT 13h AH=42h)
; Input:  DL = drive number
;         SI = pointer to Disk Address Packet (DAP)
;              DAP format (16 bytes):
;                [0]  db 0x10          packet size
;                [1]  db 0x00          reserved
;                [2]  dw count         sectors to read
;                [4]  dw offset        buffer offset
;                [6]  dw segment       buffer segment
;                [8]  dq lba           starting LBA
; Output: CF clear = success, CF set = failure after all retries
; Clobbers: AX, CX
; =============================================================================
s1_disk_read_lba:
    push cx                         ; save caller's CX

    mov cx, DISK_RETRY              ; CX = retry count (3)

.lba_retry:
    push cx                         ; save retry counter
    mov ah, 0x42                    ; extended read
    int 0x13                        ; call BIOS
    pop cx                          ; restore retry counter

    jnc .lba_success                ; if no carry, read succeeded

    ; Read failed — reset disk subsystem and retry
    call .reset_disk
    dec cx
    jnz .lba_retry                  ; retry if attempts remain

    ; All retries exhausted
    pop cx                          ; restore caller's CX
    stc                             ; set carry = failure
    ret

.lba_success:
    pop cx                          ; restore caller's CX
    clc                             ; clear carry = success
    ret

; =============================================================================
; s1_disk_read_chs — read sectors using CHS (INT 13h AH=02h)
; Input:  AL = number of sectors to read
;         CH = cylinder (low 8 bits)
;         CL = sector (bits 0-5) | cylinder high bits (bits 6-7)
;         DH = head
;         DL = drive number
;         ES:BX = buffer address
; Output: CF clear = success, CF set = failure after all retries
; Clobbers: AX, SI
;
; Note: CHS parameters must be set by caller. This function only adds
;       the retry+reset loop around the raw INT 13h call.
; =============================================================================
s1_disk_read_chs:
    push si                         ; save SI (used as retry counter)
    push ax                         ; save sector count

    mov si, DISK_RETRY              ; SI = retry count

.chs_retry:
    pop ax                          ; restore AH=02h, AL=count
    push ax                         ; keep it on stack for next retry

    mov ah, 0x02                    ; BIOS read sectors
    int 0x13

    jnc .chs_success                ; no carry = success

    ; Read failed — reset disk and retry
    call .reset_disk
    dec si
    jnz .chs_retry

    ; All retries exhausted
    pop ax                          ; clean stack
    pop si
    stc
    ret

.chs_success:
    pop ax                          ; clean stack (saved sector count)
    pop si
    clc
    ret

; =============================================================================
; .reset_disk — reset disk subsystem (INT 13h AH=00h)
; Input:  DL = drive number (must be preserved by caller)
; Output: none
; Clobbers: AX
;
; Reset is required between retry attempts. Without it, the BIOS disk
; controller may stay in an error state and all subsequent reads will fail.
; =============================================================================
.reset_disk:
    push dx                         ; save DL (drive number)
    xor ax, ax                      ; AH = 00h (reset disk)
    int 0x13                        ; reset
    pop dx                          ; restore drive number
    ret

%endif ; S1_DISK_READ_ASM
