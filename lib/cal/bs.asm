; =============================================================================
; lib/cal/bs.asm
; Bikram Sambat (BS) Nepali calendar conversions.
;
; Implements AD-to-BS (cal_ad_to_bs) and BS-to-AD (cal_bs_to_ad) solar calendar
; conversions using a month-lengths lookup table starting at epoch base
; BS 2080 (Baisakh 1, 2080 BS = April 14, 2023 AD).
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CAL_BS_ASM
%define IO_CAL_BS_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/cal/cal.inc"
%include "lib/io/error/codes.asm"

; Conversion Base Constants
BS_BASE_YEAR        equ 2080
BS_BASE_AD_SECONDS  equ 1681430400  ; April 14, 2023 00:00:00 UTC (2080-01-01 BS)
BS_SUPPORTED_YEARS  equ 6           ; 2080 to 2085 BS

section .rodata
; Table of month lengths (12 bytes per year) from BS 2080 to 2085
bs_month_table:
    db 31, 32, 31, 32, 31, 30, 30, 30, 29, 30, 29, 30 ; BS 2080
    db 31, 31, 32, 32, 31, 30, 30, 29, 30, 29, 30, 30 ; BS 2081
    db 31, 32, 31, 32, 31, 30, 30, 30, 29, 30, 29, 30 ; BS 2082
    db 31, 31, 32, 32, 31, 30, 30, 29, 30, 30, 29, 30 ; BS 2083
    db 31, 32, 31, 32, 31, 30, 30, 30, 29, 30, 29, 30 ; BS 2084
    db 31, 31, 32, 32, 31, 30, 30, 29, 30, 29, 30, 30 ; BS 2085

section .text

global cal_ad_to_bs
global cal_bs_to_ad

extern cal_to_epoch
extern cal_from_epoch

; =============================================================================
; cal_ad_to_bs — Convert Gregorian AD Date structure to Bikram Sambat (BS)
; In : RDI = -> tm_t Gregorian input structure
;      RSI = -> tm_t Bikram Sambat output structure
; Out: RAX = 0 on success, or negative error code (IO_ERR_BADARG)
; =============================================================================
IO_FUNC cal_ad_to_bs
    guard_null rdi
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

    mov     r12, rdi                ; r12 = -> ad_in
    mov     r13, rsi                ; r13 = -> bs_out

    ; 1. Convert input AD time to Unix epoch seconds
    mov     rdi, r12
    call    cal_to_epoch            ; RAX = epoch seconds

    ; Check bounds: must be >= BS_BASE_AD_SECONDS
    cmp     rax, BS_BASE_AD_SECONDS
    jb      .err_bounds

    sub     rax, BS_BASE_AD_SECONDS ; RAX = elapsed seconds since base
    xor     rdx, rdx
    mov     rcx, SECONDS_PER_DAY
    div     rcx                     ; RAX = elapsed days, RDX = remainder seconds

    mov     r14, rax                ; r14 = elapsed days count
    mov     r15, rdx                ; r15 = remainder seconds (time of day)

    ; 2. Traverse month table from BS 2080 Baisakh 1, subtracting days
    lea     rbx, [rel bs_month_table]
    xor     rcx, rcx                ; RCX = index in table (year * 12 + month)

.sub_loop:
    ; Check if index exceeds supported bounds
    cmp     rcx, BS_SUPPORTED_YEARS * 12
    jae     .err_bounds

    movzx   rax, byte [rbx + rcx]   ; RAX = days in current BS month
    cmp     r14, rax
    jb      .decompose_done         ; Remaining days fits in current month

    sub     r14, rax                ; Subtract days
    inc     rcx                     ; Move to next month
    jmp     .sub_loop

.decompose_done:
    ; 3. Convert table index (rcx) back to Year and Month
    mov     rax, rcx
    xor     rdx, rdx
    mov     rsi, 12
    div     rsi                     ; RAX = years since base, RDX = month index (0-11)

    add     rax, BS_BASE_YEAR       ; BS Year
    inc     rdx                     ; BS Month (1-12)

    mov     [r13 + tm_t.year], rax
    mov     [r13 + tm_t.month], rdx
    
    inc     r14                     ; Remaining days + 1 = Day of Month
    mov     [r13 + tm_t.day], r14

    ; 4. Copy time-of-day fields from input AD date
    mov     rax, [r12 + tm_t.hour]
    mov     [r13 + tm_t.hour], rax

    mov     rax, [r12 + tm_t.minute]
    mov     [r13 + tm_t.minute], rax

    mov     rax, [r12 + tm_t.second]
    mov     [r13 + tm_t.second], rax

    mov     rax, [r12 + tm_t.nanosecond]
    mov     [r13 + tm_t.nanosecond], rax

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_bounds:
    mov     rax, IO_ERR_BADARG

.done:
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
IO_ENDFUNC cal_ad_to_bs

; =============================================================================
; cal_bs_to_ad — Convert Bikram Sambat (BS) to Gregorian AD Date structure
; In : RDI = -> tm_t Bikram Sambat input structure
;      RSI = -> tm_t Gregorian output structure
; Out: RAX = 0 on success, or negative error code (IO_ERR_BADARG)
; =============================================================================
IO_FUNC cal_bs_to_ad
    guard_null rdi
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

    mov     r12, rdi                ; r12 = -> bs_in
    mov     r13, rsi                ; r13 = -> ad_out

    ; Verify year bounds
    mov     rax, [r12 + tm_t.year]
    cmp     rax, BS_BASE_YEAR
    jb      .err_bounds
    mov     rcx, BS_BASE_YEAR + BS_SUPPORTED_YEARS
    cmp     rax, rcx
    jae     .err_bounds

    ; Calculate table index limit for the target date: (year - BS_BASE_YEAR) * 12 + (month - 1)
    sub     rax, BS_BASE_YEAR
    imul    rax, 12                 ; RAX = years offset * 12
    mov     rcx, [r12 + tm_t.month]
    dec     rcx                     ; RCX = month - 1
    add     rax, rcx                ; RAX = target index limit

    ; Sum days of prior BS months in table
    xor     r14, r14                ; r14 = day accumulator
    xor     rcx, rcx                ; rcx = table index
    lea     rbx, [rel bs_month_table]

.sum_loop:
    cmp     rcx, rax
    jae     .sum_done

    movzx   rsi, byte [rbx + rcx]
    add     r14, rsi
    inc     rcx
    jmp     .sum_loop

.sum_done:
    ; Add days of the current month (day - 1)
    mov     rax, [r12 + tm_t.day]
    dec     rax
    add     r14, rax                ; r14 = total elapsed days since base date

    ; Convert elapsed days to seconds
    mov     rax, r14
    mov     rcx, SECONDS_PER_DAY
    mul     rcx                     ; RDX:RAX = days * 86400
    
    ; Add base AD timestamp
    add     rax, BS_BASE_AD_SECONDS ; RAX = UTC epoch timestamp for day base

    ; Add time of day: hours * 3600 + minutes * 60 + seconds
    mov     rcx, rax                ; rcx = epoch seconds

    mov     rax, [r12 + tm_t.hour]
    mov     rsi, SECONDS_PER_HOUR
    mul     rsi
    add     rcx, rax

    mov     rax, [r12 + tm_t.minute]
    mov     rsi, SECONDS_PER_MINUTE
    mul     rsi
    add     rcx, rax

    mov     rax, [r12 + tm_t.second]
    add     rcx, rax                ; rcx = final epoch seconds

    ; Re-populate Gregorian structure fields
    mov     rdi, rcx
    mov     rsi, r13
    call    cal_from_epoch          ; Fills ad_out with Gregorian fields

    ; Copy nanoseconds from input BS date
    mov     rax, [r12 + tm_t.nanosecond]
    mov     [r13 + tm_t.nanosecond], rax

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_bounds:
    mov     rax, IO_ERR_BADARG

.done:
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
IO_ENDFUNC cal_bs_to_ad

%endif ; IO_CAL_BS_ASM
