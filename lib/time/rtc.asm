; =============================================================================
; lib/time/rtc.asm
; CMOS Real-Time Clock (RTC) parser.
;
; Accesses CMOS hardware ports 0x70/0x71 to retrieve current date/time,
; parses BCD structures, and formats 12/24 hour and century parameters.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_TIME_RTC_ASM
%define IO_TIME_RTC_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/time/time.inc"
%include "lib/io/error/codes.asm"

section .text

global rtc_read_time

; =============================================================================
; rtc_read_time — Read wall clock from CMOS RTC and fill tm_t structure
; In : RDI = -> tm_t structure to populate
; Out: RAX = 0 on success, or negative error code (IO_ERR_BADARG)
; =============================================================================
IO_FUNC rtc_read_time
    guard_null rdi

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi                     ; Save tm_t * output pointer
    push    r12
    push    r13
    push    r14
    push    r15

    ; 1. Spin-wait until UIP (Update In Progress) is 0 in Status Register A
.wait_uip:
    mov     al, CMOS_REG_STATUS_A
    out     CMOS_PORT_INDEX, al
    in      al, CMOS_PORT_DATA
    test    al, CMOS_STATUS_A_UIP   ; Test UIP bit (0x80)
    jnz     .wait_uip

    ; 2. Temporarily disable interrupts for consistent register read sweep
    pushf
    cli

    ; Read Status Register B (contains format configuration)
    mov     al, CMOS_REG_STATUS_B
    out     CMOS_PORT_INDEX, al
    in      al, CMOS_PORT_DATA
    movzx   r12, al                 ; R12 = Status Register B value

    ; Read Raw Values
    mov     al, CMOS_REG_SECONDS
    out     CMOS_PORT_INDEX, al
    in      al, CMOS_PORT_DATA
    movzx   r13, al                 ; r13 = raw seconds

    mov     al, CMOS_REG_MINUTES
    out     CMOS_PORT_INDEX, al
    in      al, CMOS_PORT_DATA
    movzx   r14, al                 ; r14 = raw minutes    
    mov     al, CMOS_REG_HOURS
    out     CMOS_PORT_INDEX, al
    in      al, CMOS_PORT_DATA
    movzx   r15, al                 ; r15 = raw hours
    mov     r8, r15                 ; r8 = original raw hours for PM checks

    mov     al, CMOS_REG_DAY_MONTH
    out     CMOS_PORT_INDEX, al
    in      al, CMOS_PORT_DATA
    movzx   rbx, al                 ; rbx = raw day of month

    mov     al, CMOS_REG_MONTH
    out     CMOS_PORT_INDEX, al
    in      al, CMOS_PORT_DATA
    movzx   rsi, al                 ; rsi = raw month

    mov     al, CMOS_REG_YEAR
    out     CMOS_PORT_INDEX, al
    in      al, CMOS_PORT_DATA
    movzx   rcx, al                 ; rcx = raw year

    mov     al, CMOS_REG_CENTURY
    out     CMOS_PORT_INDEX, al
    in      al, CMOS_PORT_DATA
    movzx   rdx, al                 ; rdx = raw century

    ; Restore interrupt flag state
    popf

    ; 3. Convert formats from BCD to Binary if required
    test    r12b, CMOS_STATUS_B_BIN ; Test bit 2 (1 = Binary, 0 = BCD)
    jnz     .decode_hours           ; Already binary, skip BCD conversion

    ; Convert BCD registers
    mov     al, r13b
    call    .bcd_to_bin
    movzx   r13, al                 ; r13 = binary seconds

    mov     al, r14b
    call    .bcd_to_bin
    movzx   r14, al                 ; r14 = binary minutes

    mov     al, r15b                ; Special BCD hours conversion
    ; Hour BCD conversion: mask PM bit first if 12-hour format
    test    r12b, CMOS_STATUS_B_24H ; Test bit 1 (1 = 24H, 0 = 12H)
    jnz     .bcd_hours_24
    and     al, 0x7F                ; Clear PM bit for BCD decoding
.bcd_hours_24:
    call    .bcd_to_bin
    movzx   r15, al                 ; r15 = binary hours

    mov     al, bl                  ; BL is bottom byte of RBX
    call    .bcd_to_bin
    movzx   rbx, al                 ; rbx = binary day

    mov     al, sil                 ; SI bottom byte
    call    .bcd_to_bin
    movzx   rsi, al                 ; rsi = binary month

    mov     al, cl
    call    .bcd_to_bin
    movzx   rcx, al                 ; rcx = binary year

    mov     al, dl
    call    .bcd_to_bin
    movzx   rdx, al                 ; rdx = binary century

.decode_hours:
    ; 4. Adjust hours if configured in 12-hour format
    test    r12b, CMOS_STATUS_B_24H
    jnz     .decode_year            ; 24-hour format, proceed to year

    ; 12-hour format: PM bit is bit 7 (0x80) of original raw register hours (in r8)
    test    r8b, 0x80
    jz      .hours_am

    ; PM mode
    cmp     r15, 12                 ; 12 PM is 12
    je      .decode_year
    add     r15, 12                 ; 1 PM -> 13, etc.
    jmp     .decode_year

.hours_am:
    cmp     r15, 12                 ; 12 AM is 00:00
    jne     .decode_year
    xor     r15, r15                ; 12 AM -> 0

.decode_year:
    ; 5. Format full year using century
    test    rdx, rdx
    jnz     .century_ok
    mov     rdx, 20                 ; Default century to 20 (year 2000+)
.century_ok:
    imul    rdx, 100
    add     rcx, rdx                ; RCX = century * 100 + year

    ; 6. Populate target tm_t structure (inverse push order pops)
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi                     ; RDI = -> tm_t pointer
    
    mov     [rdi + tm_t.year], rcx
    mov     [rdi + tm_t.month], rsi
    mov     [rdi + tm_t.day], rbx
    mov     [rdi + tm_t.hour], r15
    mov     [rdi + tm_t.minute], r14
    mov     [rdi + tm_t.second], r13
    mov     qword [rdi + tm_t.nanosecond], 0

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.done:
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; Helper: .bcd_to_bin
; Input: AL = BCD encoded byte
; Output: AL = decoded binary byte
; -----------------------------------------------------------------------------
.bcd_to_bin:
    push    rcx
    mov     cl, al
    and     al, 0x0F                ; AL = units
    shr     cl, 4
    and     cl, 0x0F                ; CL = tens
    imul    cx, 10                  ; CX = tens * 10
    add     al, cl                  ; AL = units + (tens * 10)
    pop     rcx
    ret
IO_ENDFUNC rtc_read_time

%endif ; IO_TIME_RTC_ASM
