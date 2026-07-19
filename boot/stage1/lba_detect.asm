; =============================================================================
; Tattva OS — boot/stage1/lba_detect.asm
; =============================================================================
; LBA extensions detection using BIOS INT 13h AH=41h.
;
; LBA (Logical Block Addressing) is the modern way to address disk sectors.
; CHS (Cylinder-Head-Sector) is the legacy fallback for pre-1996 hardware.
; Almost all hardware since 1996 supports LBA, but we detect it to be safe.
;
; This is a standalone reference module. entry.asm has this logic inlined.
;
; Author:  Utkarsha Labs
; Target:  x86, real mode (16-bit)
; =============================================================================

%ifndef S1_LBA_DETECT_ASM
%define S1_LBA_DETECT_ASM

[BITS 16]

; =============================================================================
; s1_lba_detect — check if BIOS supports LBA extensions
; Input:  DL = drive number (e.g. 0x80 for first hard drive)
; Output: CF clear = LBA supported, CF set = LBA not supported
;         [s1_lba_flag] = 1 if LBA supported, 0 otherwise
; Clobbers: AX, BX, CX, DX
;
; INT 13h AH=41h contract:
;   Input:  AH = 41h, BX = 55AAh, DL = drive
;   Output: CF clear + BX = AA55h → LBA supported
;           CF set → LBA not supported
;           CX = bitmap of supported extensions
; =============================================================================
s1_lba_detect:
    mov ah, 0x41                    ; check extensions present
    mov bx, 0x55AA                  ; magic input value
    int 0x13                        ; call BIOS disk services

    jc .no_lba                      ; carry set = not supported

    cmp bx, 0xAA55                  ; BIOS flips the magic
    jne .no_lba                     ; if not flipped, not real LBA

    ; LBA supported — optionally check CX for feature subset:
    ;   CX bit 0: extended disk access (read/write via AH=42h/43h)
    ;   CX bit 1: removable drive support
    ;   CX bit 2: EDD-3.0 (Enhanced Disk Drive) support
    test cx, 0x01                   ; at minimum, need extended read
    jz .no_lba

    mov byte [s1_lba_flag], 1       ; mark LBA available
    clc                             ; clear carry = success
    ret

.no_lba:
    mov byte [s1_lba_flag], 0       ; LBA not available
    stc                             ; set carry = failure
    ret

; Storage
s1_lba_flag:    db 0                ; 1 = LBA supported, 0 = CHS only

%endif ; S1_LBA_DETECT_ASM
