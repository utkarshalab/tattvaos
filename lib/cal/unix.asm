; =============================================================================
; lib/cal/unix.asm
; Unix epoch date and time conversions.
;
; Implements Gregorian-to-Epoch seconds conversions (cal_to_epoch) and
; Epoch-to-Gregorian date-time decompositions (cal_from_epoch).
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CAL_UNIX_ASM
%define IO_CAL_UNIX_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/cal/cal.inc"

section .text

global cal_to_epoch
global cal_from_epoch


; =============================================================================
; cal_to_epoch — Convert Gregorian Date structure to Unix Epoch seconds
; In : RDI = -> tm_t input structure
; Out: RAX = 64-bit seconds since 1970-01-01 00:00:00 UTC
; =============================================================================
IO_FUNC cal_to_epoch
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

    mov     r12, rdi                ; r12 = -> tm_t

    ; 1. Calculate days elapsed in years from 1970 to (year - 1)
    xor     r13, r13                ; r13 = accumulated days count
    mov     r14, 1970               ; r14 = year iterator
    mov     r15, [r12 + tm_t.year]  ; r15 = target year

.year_loop:
    cmp     r14, r15
    jae     .year_done

    mov     rdi, r14
    call    cal_is_leap_year
    test    rax, rax
    jz      .add_normal_year
    add     r13, 366
    jmp     .next_year

.add_normal_year:
    add     r13, 365

.next_year:
    inc     r14
    jmp     .year_loop

.year_done:
    ; 2. Calculate days elapsed in months of target year
    mov     r14, 1                  ; r14 = month iterator
    mov     r15, [r12 + tm_t.month] ; r15 = target month

.month_loop:
    cmp     r14, r15
    jae     .month_done

    mov     rdi, [r12 + tm_t.year]
    mov     rsi, r14
    call    cal_days_in_month
    add     r13, rax

    inc     r14
    jmp     .month_loop

.month_done:
    ; 3. Add days of the current month (day - 1)
    mov     rax, [r12 + tm_t.day]
    dec     rax
    add     r13, rax                ; r13 = total elapsed days since epoch

    ; 4. Convert total days to seconds: seconds = days * 86400
    mov     rax, r13
    mov     rcx, SECONDS_PER_DAY
    mul     rcx                     ; RDX:RAX = days * 86400
    mov     r13, rax                ; r13 = accumulated seconds

    ; 5. Add time of day: hours * 3600 + minutes * 60 + seconds
    mov     rax, [r12 + tm_t.hour]
    mov     rcx, SECONDS_PER_HOUR
    mul     rcx
    add     r13, rax

    mov     rax, [r12 + tm_t.minute]
    mov     rcx, SECONDS_PER_MINUTE
    mul     rcx
    add     r13, rax

    mov     rax, [r12 + tm_t.second]
    add     rax, r13                ; RAX = final Unix epoch timestamp

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC cal_to_epoch

; =============================================================================
; cal_from_epoch — Decompose Unix Epoch timestamp into tm_t structure
; In : RDI = 64-bit seconds since Unix epoch
;      RSI = -> tm_t output structure to populate
; =============================================================================
IO_FUNC cal_from_epoch
    guard_null rsi
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi                ; r12 = epoch seconds
    mov     r13, rsi                ; r13 = -> output tm_t

    ; 1. Extract days and time of day
    mov     rax, r12
    xor     rdx, rdx
    mov     rcx, SECONDS_PER_DAY
    div     rcx                     ; RAX = days since 1970, RDX = seconds of day
    
    mov     r14, rax                ; r14 = days since epoch
    mov     r15, rdx                ; r15 = seconds of day

    ; Extract hours from seconds of day
    mov     rax, r15
    xor     rdx, rdx
    mov     rcx, SECONDS_PER_HOUR
    div     rcx                     ; RAX = hours, RDX = remaining seconds
    mov     [r13 + tm_t.hour], rax
    mov     r15, rdx

    ; Extract minutes and seconds
    mov     rax, r15
    xor     rdx, rdx
    mov     rcx, SECONDS_PER_MINUTE
    div     rcx                     ; RAX = minutes, RDX = seconds
    mov     [r13 + tm_t.minute], rax
    mov     [r13 + tm_t.second], rdx

    ; 2. Decompose days since epoch (r14) to Year
    mov     r15, 1970               ; r15 = year counter

.calc_year:
    mov     rdi, r15
    call    cal_is_leap_year
    mov     rcx, 365
    test    rax, rax
    jz      .sub_year
    mov     rcx, 366

.sub_year:
    cmp     r14, rcx
    jb      .year_found
    sub     r14, rcx
    inc     r15
    jmp     .calc_year

.year_found:
    mov     [r13 + tm_t.year], r15

    ; 3. Decompose remaining days in year (r14) to Month
    mov     r15, 1                  ; r15 = month counter

.calc_month:
    mov     rdi, [r13 + tm_t.year]
    mov     rsi, r15
    call    cal_days_in_month       ; RAX = days in month
    
    cmp     r14, rax
    jb      .month_found
    sub     r14, rax
    inc     r15
    jmp     .calc_month

.month_found:
    mov     [r13 + tm_t.month], r15

    ; 4. Remaining days represent Day of Month (r14 + 1)
    inc     r14
    mov     [r13 + tm_t.day], r14

    ; Clear nanoseconds
    mov     qword [r13 + tm_t.nanosecond], 0

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC cal_from_epoch

%endif ; IO_CAL_UNIX_ASM
