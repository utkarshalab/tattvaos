; =============================================================================
; Tattva OS — boot/stage1/print.asm
; =============================================================================
; BIOS INT 10h print utilities for stage1 debugging.
;
; These are standalone callable routines. entry.asm already has print_str
; inlined — this file exists as a reference module for future refactoring
; and provides additional helpers (hex byte, CRLF).
;
; Functions:
;   s1_print_str   — print null-terminated string
;   s1_print_hex8  — print single byte as 2-digit hex
;   s1_print_crlf  — print carriage return + line feed
;
; All functions use BIOS INT 10h AH=0Eh (teletype output).
; Safe to call in 16-bit real mode only.
;
; Author:  Utkarsha Labs
; Target:  x86, real mode (16-bit)
; =============================================================================

%ifndef S1_PRINT_ASM
%define S1_PRINT_ASM

[BITS 16]

; =============================================================================
; s1_print_str — print null-terminated string via BIOS teletype
; Input:  SI = pointer to null-terminated string
; Output: none
; Clobbers: AX, BX, SI
; =============================================================================
s1_print_str:
    cld                             ; ensure forward direction for lodsb
    mov ah, 0x0E                    ; BIOS teletype function
    mov bh, 0                       ; video page 0
    mov bl, 0x07                    ; light grey on black

.loop:
    lodsb                           ; AL = [SI], SI++
    test al, al                     ; null terminator?
    jz .done
    int 0x10                        ; print character
    jmp .loop

.done:
    ret

; =============================================================================
; s1_print_hex8 — print a single byte as 2-digit hexadecimal
; Input:  AL = byte to print
; Output: none
; Clobbers: AX, BX, CX
;
; Example: AL = 0x80 → prints "80"
; =============================================================================
s1_print_hex8:
    push ax                         ; save original byte

    ; Print high nibble
    shr al, 4                       ; AL = high nibble (0x0-0xF)
    call .print_nibble

    ; Print low nibble
    pop ax                          ; restore original byte
    and al, 0x0F                    ; AL = low nibble (0x0-0xF)
    call .print_nibble

    ret

.print_nibble:
    cmp al, 10                      ; is it A-F?
    jb .digit
    add al, 'A' - 10               ; convert 10-15 to 'A'-'F'
    jmp .emit
.digit:
    add al, '0'                     ; convert 0-9 to '0'-'9'
.emit:
    mov ah, 0x0E                    ; BIOS teletype
    mov bh, 0
    mov bl, 0x07
    int 0x10
    ret

; =============================================================================
; s1_print_crlf — print carriage return + line feed
; Input:  none
; Output: none
; Clobbers: AX, BX
; =============================================================================
s1_print_crlf:
    mov ah, 0x0E
    mov bh, 0
    mov bl, 0x07
    mov al, 0x0D                    ; carriage return
    int 0x10
    mov al, 0x0A                    ; line feed
    int 0x10
    ret

%endif ; S1_PRINT_ASM
