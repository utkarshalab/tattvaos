; =============================================================================
; Utkarsha OS — boot/stage2/gdt/gdt_verify.asm
; =============================================================================
; Verify the GDT was loaded correctly after gdt_setup.
; Reads back the GDT register and checks key descriptor fields.
; Halts with error if anything is wrong.
;
; Checks:
;   1. GDTR base address matches gdt_start
;   2. GDTR limit matches expected size
;   3. Every boot descriptor matches its exact access/flag encoding
;   4. Active protected-mode selectors are the expected ring-0 entries
;   5. Null descriptor is actually zero
;
; Call after gdt_setup, before switching to long mode. This is a mandatory
; transition gate: malformed descriptors are never safe to continue past.
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit)
; =============================================================================

%ifndef GDT_VERIFY_ASM
%define GDT_VERIFY_ASM

; temporary buffer for sgdt result (6 bytes)
gdt_verify_buf: times 6 db 0

; =============================================================================
; gdt_verify — verify GDT register and key descriptors
; Input:  GDT loaded by gdt_setup
; Output: CF=0 all checks passed
;         CF=1 verification failed (caller should halt)
; Clobbers: EAX, EBX, ECX, ESI
; =============================================================================
[BITS 32]
gdt_verify:
    push eax
    push ebx
    push ecx
    push esi

    ; -------------------------------------------------------------------------
    ; Check 1: Read back GDTR using SGDT instruction
    ; SGDT stores 6 bytes: 2-byte limit + 4-byte base
    ; -------------------------------------------------------------------------
    sgdt [gdt_verify_buf]

    ; check limit = GDT_SIZE - 1
    mov ax, [gdt_verify_buf]        ; limit word
    cmp ax, GDT_SIZE - 1
    jne .verify_fail_limit

    ; check base = gdt_start address
    mov eax, [gdt_verify_buf + 2]   ; base dword
    cmp eax, gdt_start
    jne .verify_fail_base

    ; -------------------------------------------------------------------------
    ; Check 2: Null descriptor must be all zeros
    ; -------------------------------------------------------------------------
    mov esi, gdt_start
    mov eax, [esi]                  ; low dword of null descriptor
    mov ebx, [esi + 4]              ; high dword of null descriptor
    or eax, ebx
    jnz .verify_fail_null           ; non-zero = corrupted GDT

    ; Compare complete encodings, not one selected feature bit.
    cmp dword [gdt_code64], 0x0000FFFF
    jne .verify_fail_descriptor
    cmp dword [gdt_code64 + 4], 0x00AF9B00
    jne .verify_fail_descriptor
    cmp dword [gdt_data64], 0x0000FFFF
    jne .verify_fail_descriptor
    cmp dword [gdt_data64 + 4], 0x00CF9300
    jne .verify_fail_descriptor
    cmp dword [gdt_code16], 0x0000FFFF
    jne .verify_fail_descriptor
    cmp dword [gdt_code16 + 4], 0x00009B00
    jne .verify_fail_descriptor
    cmp dword [gdt_code32], 0x0000FFFF
    jne .verify_fail_descriptor
    cmp dword [gdt_code32 + 4], 0x00CF9B00
    jne .verify_fail_descriptor

    mov ax, cs
    cmp ax, SEL_CODE32
    jne .verify_fail_selector
    mov ax, ds
    cmp ax, SEL_DATA64
    jne .verify_fail_selector
    mov ax, ss
    cmp ax, SEL_DATA64
    jne .verify_fail_selector

    ; -------------------------------------------------------------------------
    ; All checks passed
    ; -------------------------------------------------------------------------
    mov esi, msg_gdt_verify_ok
    call uart_print_pm              ; protected mode UART print
    clc
    jmp .verify_done

.verify_fail_limit:
    mov esi, msg_gdt_fail_limit
    call uart_print_pm
    stc
    jmp .verify_done

.verify_fail_base:
    mov esi, msg_gdt_fail_base
    call uart_print_pm
    stc
    jmp .verify_done

.verify_fail_null:
    mov esi, msg_gdt_fail_null
    call uart_print_pm
    stc
    jmp .verify_done

.verify_fail_descriptor:
    mov esi, msg_gdt_fail_descriptor
    call uart_print_pm
    stc
    jmp .verify_done

.verify_fail_selector:
    mov esi, msg_gdt_fail_selector
    call uart_print_pm
    stc

.verify_done:
    pop esi
    pop ecx
    pop ebx
    pop eax
    ret

; =============================================================================
; uart_print_pm — print null-terminated string in 32-bit protected mode
; In protected mode we can still use port I/O for UART
; but we need a 32-bit version since real mode BIOS calls are gone
; Input:  ESI = pointer to string
; Clobbers: AL, EDX
; =============================================================================
uart_print_pm:
    push eax
    push ebx
    push edx
    push esi
    cld                             ; Clear direction flag for lodsb

.pm_print_loop:
    lodsb                           ; AL = [ESI], ESI++
    test al, al
    jz .pm_print_done

    mov bl, al                      ; save character in BL

    ; wait for THRE (transmitter empty)
.pm_wait:
    mov edx, UART_COM1 + 5          ; LSR register
    in al, dx
    test al, 0x20
    jz .pm_wait

    mov al, bl                      ; restore character
    mov edx, UART_COM1
    out dx, al

    jmp .pm_print_loop

.pm_print_done:
    pop esi
    pop edx
    pop ebx
    pop eax
    ret

; =============================================================================
; Strings
; =============================================================================
msg_gdt_verify_ok:      db "GDT verify: OK", 0x0D, 0x0A, 0
msg_gdt_fail_limit:     db "GDT verify: FAIL limit mismatch", 0x0D, 0x0A, 0
msg_gdt_fail_base:      db "GDT verify: FAIL base mismatch", 0x0D, 0x0A, 0
msg_gdt_fail_null:      db "GDT verify: FAIL null descriptor not zero", 0x0D, 0x0A, 0
msg_gdt_fail_descriptor: db "GDT verify: FAIL descriptor encoding", 0x0D, 0x0A, 0
msg_gdt_fail_selector:   db "GDT verify: FAIL active selectors", 0x0D, 0x0A, 0

[BITS 16]

%endif ; GDT_VERIFY_ASM
