; =============================================================================
; lib/cal/jdn.asm
; Julian Day Number (JDN) conversions.
;
; Implements Gregorian-to-Julian Day Number (cal_to_jdn) and Julian-to-Gregorian
; date conversions (cal_from_jdn) in O(1) time complexity.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CAL_JDN_ASM
%define IO_CAL_JDN_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/cal/cal.inc"

section .text

global cal_to_jdn
global cal_from_jdn

; =============================================================================
; cal_to_jdn — Convert Gregorian date to Julian Day Number (JDN)
; In : RDI = Year
;      RSI = Month (1-12)
;      RDX = Day (1-31)
; Out: RAX = 64-bit Julian Day Number
; =============================================================================
IO_FUNC cal_to_jdn
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9

    mov     r8, rdi                 ; r8 = year
    mov     r9, rsi                 ; r9 = month
    ; RDX remains day

    ; 1. Calculate a = (14 - month) / 12
    mov     rax, 14
    sub     rax, r9                 ; RAX = 14 - month
    xor     rdx, rdx
    mov     rcx, 12
    div     rcx                     ; RAX = a (1 if month is 1 or 2, else 0)
    mov     rbx, rax                ; RBX = a

    ; 2. Calculate y = year + 4800 - a
    mov     rcx, r8
    add     rcx, 4800
    sub     rcx, rbx                ; RCX = y

    ; 3. Calculate m = month + 12 * a - 3
    mov     rax, rbx
    imul    rax, 12
    add     rax, r9
    sub     rax, 3                  ; RAX = m

    ; Save m, y, and day
    push    rax                     ; [rsp+16] = m
    push    rcx                     ; [rsp+8]  = y
    mov     rdx, [rsp + 40]         ; Fetch original day from stack frame
    push    rdx                     ; [rsp]    = day

    ; 4. JDN = day + (153 * m + 2) / 5 + 365 * y + y/4 - y/100 + y/400 - 32045
    ; Compute (153 * m + 2) / 5
    mov     rax, [rsp + 16]         ; RAX = m
    imul    rax, 153
    add     rax, 2
    xor     rdx, rdx
    mov     rsi, 5
    div     rsi                     ; RAX = (153 * m + 2) / 5
    mov     r8, rax                 ; R8 = term1

    ; Add day
    add     r8, [rsp]               ; R8 = day + term1

    ; Add 365 * y
    mov     rax, [rsp + 8]          ; RAX = y
    imul    rax, 365
    add     r8, rax                 ; R8 = day + term1 + 365*y

    ; Add y/4
    mov     rax, [rsp + 8]          ; RAX = y
    shr     rax, 2                  ; RAX = y/4
    add     r8, rax

    ; Subtract y/100
    mov     rax, [rsp + 8]          ; RAX = y
    xor     rdx, rdx
    mov     rsi, 100
    div     rsi                     ; RAX = y/100
    sub     r8, rax

    ; Add y/400
    mov     rax, [rsp + 8]          ; RAX = y
    xor     rdx, rdx
    mov     rsi, 400
    div     rsi                     ; RAX = y/400
    add     r8, rax

    ; Subtract 32045
    sub     r8, 32045
    mov     rax, r8                 ; RAX = JDN

    add     rsp, 24                 ; Clean local stack arguments
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC cal_to_jdn

; =============================================================================
; cal_from_jdn — Convert Julian Day Number back to Gregorian date
; In : RDI = Julian Day Number
;      RSI = -> tm_t structure to write date fields
; =============================================================================
IO_FUNC cal_from_jdn
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

    mov     r12, rdi                ; r12 = JDN
    mov     r13, rsi                ; r13 = -> tm_t

    ; 1. L = JDN + 68569
    mov     r14, r12
    add     r14, 68569              ; R14 = L

    ; 2. N = (4 * L) / 146097
    mov     rax, r14
    shl     rax, 2                  ; RAX = 4 * L
    xor     rdx, rdx
    mov     rcx, 146097
    div     rcx                     ; RAX = N, RDX = remainder
    mov     r15, rax                ; r15 = N

    ; 3. L = L - (146097 * N + 3) / 4
    mov     rax, r15
    imul    rax, 146097
    add     rax, 3
    shr     rax, 2                  ; RAX = (146097 * N + 3) / 4
    sub     r14, rax                ; R14 = L (updated)

    ; 4. I = (4000 * (L + 1)) / 1461001
    mov     rax, r14
    inc     rax
    imul    rax, 4000
    xor     rdx, rdx
    mov     rcx, 1461001
    div     rcx                     ; RAX = I
    mov     rbx, rax                ; RBX = I

    ; 5. L = L - (1461 * I) / 4 + 31
    mov     rax, rbx
    imul    rax, 1461
    shr     rax, 2                  ; RAX = (1461 * I) / 4
    sub     r14, rax
    add     r14, 31                 ; R14 = L (updated)

    ; 6. J = (80 * L) / 2447
    mov     rax, r14
    imul    rax, 80
    xor     rdx, rdx
    mov     rcx, 2447
    div     rcx                     ; RAX = J
    mov     rsi, rax                ; RSI = J

    ; 7. day = L - (2447 * J) / 80
    mov     rax, rsi
    imul    rax, 2447
    xor     rdx, rdx
    mov     rcx, 80
    div     rcx                     ; RAX = (2447 * J) / 80
    mov     rdx, r14
    sub     rdx, rax                ; RDX = day

    ; 8. L_temp = J / 11
    mov     rax, rsi
    xor     rdx, rdx
    mov     rcx, 11
    div     rcx                     ; RAX = L_temp

    ; 9. month = J + 2 - 12 * L_temp
    mov     rcx, rax
    imul    rcx, 12
    mov     rdi, rsi
    add     rdi, 2
    sub     rdi, rcx                ; RDI = month

    ; 10. year = 100 * (N - 49) + I + L_temp
    mov     rcx, r15
    sub     rcx, 49
    imul    rcx, 100
    add     rcx, rbx
    add     rcx, rax                ; RCX = year

    ; Save fields to target tm_t
    mov     [r13 + tm_t.year], rcx
    mov     [r13 + tm_t.month], rdi
    mov     [r13 + tm_t.day], rdx

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
IO_ENDFUNC cal_from_jdn

%endif ; IO_CAL_JDN_ASM
