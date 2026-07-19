; =============================================================================
; lib/cal/gregorian.asm
; Gregorian calendar arithmetic.
;
; Implements leap year logic, days-per-month determinations, and weekday
; offsets (0=Sunday to 6=Saturday) via Sakamoto's fast bitwise algorithm.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CAL_GREGORIAN_ASM
%define IO_CAL_GREGORIAN_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/cal/cal.inc"

section .rodata
; Sakamoto's weekday offset table for months Jan-Dec
sakamoto_table:     db 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4

; Month days table (index 0 is padding, 1-12 are Jan-Dec days)
month_days:         db 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31

section .text

global cal_is_leap_year
global cal_days_in_month
global cal_weekday

; =============================================================================
; cal_is_leap_year — Check if a year is a leap year
; In : RDI = Year
; Out: RAX = 1 if leap year, 0 if normal year
; =============================================================================
IO_FUNC cal_is_leap_year
    push    rdx
    push    rcx

    mov     rax, rdi
    ; If year % 400 == 0 -> Leap Year
    xor     rdx, rdx
    mov     rcx, 400
    div     rcx
    test    rdx, rdx
    jz      .leap

    ; If year % 100 == 0 -> Normal Year
    mov     rax, rdi
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    test    rdx, rdx
    jz      .normal

    ; If year % 4 == 0 -> Leap Year
    mov     rax, rdi
    xor     rdx, rdx
    mov     rcx, 4
    div     rcx
    test    rdx, rdx
    jz      .leap

.normal:
    xor     rax, rax                ; Return 0
    jmp     .done

.leap:
    mov     rax, 1                  ; Return 1

.done:
    pop     rcx
    pop     rdx
    ret
IO_ENDFUNC cal_is_leap_year

; =============================================================================
; cal_days_in_month — Get count of days in a month for a specific year
; In : RDI = Year
;      RSI = Month (1-12)
; Out: RAX = Days in month (28-31) or 0 if month out of bounds
; =============================================================================
IO_FUNC cal_days_in_month
    push    rbx
    push    rsi
    push    rdi

    ; Range check month (1-12)
    cmp     rsi, 1
    jb      .err_out
    cmp     rsi, 12
    ja      .err_out

    ; If month == 2 (February), check leap year
    cmp     rsi, 2
    jne     .standard_month

    ; Check if year is leap year
    ; RDI is already Year
    call    cal_is_leap_year
    test    rax, rax
    jz      .feb_normal
    mov     rax, 29                 ; Leap year Feb has 29 days
    jmp     .done

.feb_normal:
    mov     rax, 28                 ; Normal year Feb has 28 days
    jmp     .done

.standard_month:
    lea     rbx, [rel month_days]
    movzx   rax, byte [rbx + rsi]   ; Look up standard days
    jmp     .done

.err_out:
    xor     rax, rax                ; Return 0 for invalid months

.done:
    pop     rdi
    pop     rsi
    pop     rbx
    ret
IO_ENDFUNC cal_days_in_month

; =============================================================================
; cal_weekday — Compute weekday of a date (Sakamoto's method)
; In : RDI = Year
;      RSI = Month (1-12)
;      RDX = Day of month (1-31)
; Out: RAX = Weekday (0 = Sunday, 1 = Monday, ..., 6 = Saturday)
; =============================================================================
IO_FUNC cal_weekday
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13

    mov     r12, rdi                ; r12 = Year
    mov     r13, rsi                ; r13 = Month
    ; RDX remains Day of month

    ; Sakamoto: if m < 3, y -= 1
    cmp     r13, 3
    jae     .calc
    dec     r12

.calc:
    ; Formula: (y + y/4 - y/100 + y/400 + t[m-1] + d) % 7
    mov     rax, r12                ; RAX = y

    ; Add y/4
    mov     rbx, r12
    shr     rbx, 2                  ; RBX = y/4
    add     rax, rbx                ; RAX = y + y/4

    ; Subtract y/100
    push    rax
    mov     rax, r12
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx                     ; RAX = y/100
    mov     rbx, rax                ; RBX = y/100
    pop     rax
    sub     rax, rbx                ; RAX = y + y/4 - y/100

    ; Add y/400
    push    rax
    mov     rax, r12
    xor     rdx, rdx
    mov     rcx, 400
    div     rcx                     ; RAX = y/400
    mov     rbx, rax                ; RBX = y/400
    pop     rax
    add     rax, rbx                ; RAX = y + y/4 - y/100 + y/400

    ; Add t[m-1]
    lea     rbx, [rel AlignmentTableDummy] ; Use rel sakamoto_table pointer
    lea     rbx, [rel sakamoto_table]
    mov     rcx, r13
    dec     rcx                     ; RCX = m-1
    movzx   rsi, byte [rbx + rcx]   ; RSI = t[m-1]
    add     rax, rsi                ; RAX = ... + t[m-1]

    ; Add d (restore Day from original register saved on stack, or use RDX)
    ; Since RDX was pushed, retrieve it from the frame
    mov     rdx, [rsp + 16]         ; Pushed order: r13, r12, rdi, rsi, rdx, rcx, rbx
    add     rax, rdx                ; RAX = ... + d

    ; Modulo 7
    xor     rdx, rdx
    mov     rcx, 7
    div     rcx                     ; RDX = remainder (0-6)
    mov     rax, rdx                ; Return remainder on RAX

    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; Dummy alignment label for referencing
AlignmentTableDummy: db 0

IO_ENDFUNC cal_weekday

%endif ; IO_CAL_GREGORIAN_ASM
