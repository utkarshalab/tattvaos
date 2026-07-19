; =============================================================================
; Tattva OS — boot/stage1/load_stage2.asm
; =============================================================================
; Stage2 loading orchestrator.
;
; Detects LBA support, loads stage2 from disk to STAGE2_LOAD (0x8000),
; and verifies the STAGE2_MAGIC signature. This is the complete loading
; sequence as a single callable function.
;
; This is a standalone reference module. entry.asm has this logic inlined.
; If used, requires: disk_read.asm, lba_detect.asm, print.asm, config.asm
;
; Author:  Utkarsha Labs
; Target:  x86, real mode (16-bit)
; =============================================================================

%ifndef S1_LOAD_STAGE2_ASM
%define S1_LOAD_STAGE2_ASM

[BITS 16]

; =============================================================================
; s1_load_stage2 — detect LBA, load stage2, verify magic
; Input:  DL = boot drive number
; Output: CF clear = stage2 loaded and verified
;         CF set   = load or verify failed (caller should halt)
; Clobbers: AX, BX, CX, DX, SI, ES
;
; On success, stage2 is in memory at STAGE2_LOAD and first 4 bytes
; match STAGE2_MAGIC. Caller can jump to (STAGE2_LOAD + 4) to execute.
; =============================================================================
s1_load_stage2:
    push di

    ; -----------------------------------------------------------------
    ; Step 1: Detect LBA support
    ; -----------------------------------------------------------------
    call s1_lba_detect              ; CF set if LBA not supported
    jc .try_chs                     ; no LBA → fall back to CHS

    ; -----------------------------------------------------------------
    ; Step 2a: Load via LBA (INT 13h AH=42h)
    ; -----------------------------------------------------------------
    mov si, s1_stage2_dap           ; DAP for stage2 sectors
    mov dl, [boot_drive]
    call s1_disk_read_lba
    jc .load_failed                 ; all LBA retries failed
    jmp .verify

.try_chs:
    ; -----------------------------------------------------------------
    ; Step 2b: Load via CHS (INT 13h AH=02h)
    ; -----------------------------------------------------------------
    ; Stage2 starts at LBA 1 → CHS: cylinder 0, head 0, sector 2
    xor ax, ax
    mov es, ax                      ; ES = 0x0000
    mov bx, STAGE2_LOAD             ; ES:BX = 0x0000:0x8000

    mov ah, 0x02                    ; read sectors
    mov al, STAGE2_SECTORS          ; number of sectors
    mov ch, 0                       ; cylinder 0
    mov cl, 2                       ; sector 2 (1-indexed, sector 1 = MBR)
    mov dh, 0                       ; head 0
    mov dl, [boot_drive]
    call s1_disk_read_chs
    jc .load_failed

.verify:
    ; -----------------------------------------------------------------
    ; Step 3: Verify stage2 magic number
    ; -----------------------------------------------------------------
    ; First 4 bytes of stage2 must be STAGE2_MAGIC (0x32535442 "BTS2")
    mov eax, [STAGE2_LOAD]          ; read first dword
    cmp eax, STAGE2_MAGIC           ; compare to expected
    jne .bad_magic

    ; Success
    pop di
    clc                             ; CF clear = success
    ret

.load_failed:
    pop di
    stc                             ; CF set = disk error
    ret

.bad_magic:
    pop di
    stc                             ; CF set = magic mismatch
    ret

; =============================================================================
; DAP (Disk Address Packet) for loading stage2
; =============================================================================
align 2
s1_stage2_dap:
    db 0x10                         ; packet size = 16 bytes
    db 0x00                         ; reserved
    dw STAGE2_SECTORS               ; number of sectors to read
    dw STAGE2_LOAD                  ; memory offset  (0x8000)
    dw 0x0000                       ; memory segment (0x0000)
    dq 0x0000000000000001           ; LBA start = sector 1 (after MBR)

%endif ; S1_LOAD_STAGE2_ASM
