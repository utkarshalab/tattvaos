; =============================================================================
; Utkarsha OS — boot/stage2/hw/uart/uart_hex.asm
; =============================================================================
; Print values in hexadecimal via COM1 UART.
; Essential for debugging addresses, registers, error codes.
;
; Functions:
;   uart_print_hex8   — print 8-bit value  as "0x##"
;   uart_print_hex16  — print 16-bit value as "0x####"
;   uart_print_hex32  — print 32-bit value as "0x########"
;   uart_print_hex64  — print 64-bit value as "0x################"
;   uart_print_reg    — print "NAME = 0x################" + CRLF
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode + protected mode + long mode
; =============================================================================

%ifndef UART_HEX_ASM
%define UART_HEX_ASM

%include "uart.asm"
%include "uart_print.asm"

; hex digit lookup table
hex_chars: db "0123456789ABCDEF"

; =============================================================================
; uart_print_hex_nibble — print single hex nibble (0-F)
; Input:  AL = nibble value (0-15)
; Output: nothing
; Clobbers: AL, DX
; =============================================================================
uart_print_hex_nibble:
    push bx
    and al, 0x0F                    ; isolate lower nibble
    mov bh, 0
    mov bl, al
    mov al, [hex_chars + bx]
    call uart_putc
    pop bx
    ret

; =============================================================================
; uart_print_hex8 — print 8-bit value as "0x##"
; Input:  AL = value
; Output: nothing
; Clobbers: AL, DX, SI
; =============================================================================
uart_print_hex8:
    push ax

    ; print "0x" prefix
    push ax
    mov si, str_0x
    call uart_print
    pop ax

    ; print high nibble
    push ax
    shr al, 4
    call uart_print_hex_nibble
    pop ax

    ; print low nibble
    call uart_print_hex_nibble

    pop ax
    ret

; =============================================================================
; uart_print_hex16 — print 16-bit value as "0x####"
; Input:  AX = value
; Output: nothing
; Clobbers: AL, DX, SI
; =============================================================================
uart_print_hex16:
    push ax

    ; print "0x" prefix
    push ax
    mov si, str_0x
    call uart_print
    pop ax

    ; print high byte
    push ax
    mov al, ah
    push ax
    shr al, 4
    call uart_print_hex_nibble
    pop ax
    call uart_print_hex_nibble
    pop ax

    ; print low byte
    push ax
    shr al, 4
    call uart_print_hex_nibble
    pop ax
    call uart_print_hex_nibble

    pop ax
    ret

; =============================================================================
; uart_print_hex32 — print 32-bit value as "0x########"
; Input:  EAX = value
; Output: nothing
; Clobbers: AL, DX, SI, ECX
; =============================================================================
uart_print_hex32:
    push eax
    mov si, str_0x
    call uart_print
    pop eax
    call uart_print_hex32_raw
    ret

; uart_print_hex32_raw — print exactly eight hex digits with no prefix.
; Input: EAX = value. Preserves EAX/ECX/EDX.
uart_print_hex32_raw:
    push eax
    push ecx
    push edx
    mov edx, eax
    mov ecx, 8
.raw_loop32:
    rol edx, 4
    push edx                        ; uart_putc uses DX for the UART port
    movzx eax, dl
    and eax, 0x0F
    mov al, [hex_chars + eax]
    call uart_putc
    pop edx
    loop .raw_loop32
    pop edx
    pop ecx
    pop eax
    ret

; uart_print_hex64_16 — print EDX:EAX as one fixed-width 64-bit hex value.
; This is the real-mode counterpart of uart_print_hex64 below.
uart_print_hex64_16:
    push si
    push eax
    push edx
    mov si, str_0x
    call uart_print
    pop edx                         ; restore high half after UART clobbered DX
    pop eax                         ; restore low half
    push eax                        ; keep low half across high-half rendering
    mov eax, edx
    call uart_print_hex32_raw
    pop eax
    call uart_print_hex32_raw
    pop si
    ret

[BITS 64]
; =============================================================================
; uart_print_hex64 — print 64-bit value as "0x################"
; Input:  RAX = value (64-bit, long mode only)
; Output: nothing
; Clobbers: RAX, RDX, RSI, RCX
; =============================================================================
uart_print_hex64:
    push rax
    push rcx
    push rdx

    ; print "0x" prefix
    push rax
    mov rsi, str_0x
    call uart_print_64
    pop rax

    ; print 16 nibbles from high to low
    mov rcx, 60                     ; start shift amount

.loop64:
    push rax
    push rcx
    mov rdx, rax
    shr rdx, cl                     ; shift right by cl
    and rdx, 0x0F                   ; isolate nibble
    mov al, [hex_chars + edx]
    call uart_putc_64
    pop rcx
    pop rax
    sub rcx, 4                      ; next nibble
    cmp rcx, 0
    jge .loop64

    pop rdx
    pop rcx
    pop rax
    ret
[BITS 16]

; =============================================================================
; uart_print_addr — print address with label
; Input:  SI  = pointer to label string
;         EAX = address (32-bit) or RAX (64-bit in long mode)
; Output: nothing
; Example output: "kernel_entry = 0x00100000\r\n"
; =============================================================================
uart_print_addr:
    push ax

    call uart_print                 ; print label
    mov si, str_eq
    call uart_print                 ; print " = "
    pop ax
    call uart_print_hex32           ; print address
    mov al, 0x0D
    call uart_putc                  ; CR
    mov al, 0x0A
    call uart_putc                  ; LF
    ret

; =============================================================================
; Strings
; =============================================================================
str_0x:     db "0x", 0
str_eq:     db " = ", 0

%endif ; UART_HEX_ASM
