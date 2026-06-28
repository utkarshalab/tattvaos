; =============================================================================
; str/format/humanize.asm
; Duration and relative time formatting functions.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/copy.asm  (str_copy_bytes)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_copy_bytes

section .rodata

_str_just_now:   db "just now", 0
_str_second:     db "second", 0
_str_minute:     db "minute", 0
_str_hour:       db "hour", 0
_str_day:        db "day", 0
_str_ago:        db " ago", 0
_str_in:         db "in ", 0

section .text

; -----------------------------------------------------------------------------
; str_format_duration
;
; Format duration in seconds into human readable format: e.g. "1h 1m 5s".
;
; Signature:
;   int64_t str_format_duration(uint64_t seconds, uint8_t *dst,
;                               uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — seconds (uint64_t)
;   RSI  — dst (uint8_t*)
;   RDX  — cap (uint64_t)
;   RCX  — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_format_duration
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 40             ; temp digits buffer

    mov     rbx, rdi            ; seconds
    mov     r12, rsi            ; dst
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out_len

    xor     r15, r15            ; dst_offset = 0

    test    rbx, rbx
    jnz     .decompose

    ; seconds is 0 -> "0s"
    cmp     r13, 2
    jb      .too_small
    mov     byte [r12], '0'
    mov     byte [r12 + 1], 's'
    mov     qword [r14], 2
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.decompose:
    ; days = seconds / 86400
    mov     rax, rbx
    xor     rdx, rdx
    mov     rcx, 86400
    div     rcx                 ; RAX = days, RDX = rem
    push    rdx                 ; save rem
    push    rax                 ; save days

    ; hours = rem / 3600
    pop     r10                 ; days
    pop     rax                 ; rem
    xor     rdx, rdx
    mov     rcx, 3600
    div     rcx                 ; RAX = hours, RDX = rem
    push    rdx
    push    rax                 ; hours
    push    r10                 ; days

    ; minutes = rem / 60, secs = rem % 60
    pop     r10                 ; days
    pop     r11                 ; hours
    pop     rax                 ; rem
    xor     rdx, rdx
    mov     rcx, 60
    div     rcx                 ; RAX = minutes, RDX = secs

    ; Now we have:
    ;   r10 = days
    ;   r11 = hours
    ;   rax = minutes
    ;   rdx = secs
    ; Let's push all four on stack
    push    rdx                 ; secs
    push    rax                 ; minutes
    push    r11                 ; hours
    push    r10                 ; days

    ; Iterate over 4 units: days (0), hours (1), minutes (2), secs (3)
    xor     rbx, rbx            ; unit_idx = 0

.unit_loop:
    cmp     rbx, 4
    je      .done

    mov     rax, [rsp + rbx*8]  ; get unit value
    test    rax, rax
    jz      .next_unit

    ; write space separator if dst_offset > 0
    test    r15, r15
    jz      .write_val

    cmp     r15, r13
    jae     .too_small
    mov     byte [r12 + r15], ' '
    inc     r15

.write_val:
    ; format RAX to stack [rsp+32..]
    push    rbx
    mov     rcx, 10
    lea     r8, [rsp + 40]      ; offset adjusted for pushed rbx (was 32, now 40)
.dig_loop:
    test    rax, rax
    jz      .dig_done
    xor     rdx, rdx
    div     rcx
    dec     r8
    add     dl, '0'
    mov     [r8], dl
    jmp     .dig_loop

.dig_done:
    lea     rax, [rsp + 40]
    sub     rax, r8             ; len
    mov     rcx, rax

    ; check capacity: dst_offset + len + 1 (unit suffix) <= cap
    mov     rdx, r15
    add     rdx, rcx
    inc     rdx
    cmp     rdx, r13
    ja      .too_small_pop

    ; copy digits
    push    rcx
    mov     rdi, r12
    add     rdi, r15
    mov     rsi, r8
    mov     rdx, rcx
    call    str_copy_bytes
    pop     rcx
    add     r15, rcx

    pop     rbx                 ; restore unit_idx

    ; append unit char
    cmp     rbx, 0
    je      .append_d
    cmp     rbx, 1
    je      .append_h
    cmp     rbx, 2
    je      .append_m
    mov     byte [r12 + r15], 's'
    jmp     .unit_written

.append_d:
    mov     byte [r12 + r15], 'd'
    jmp     .unit_written
.append_h:
    mov     byte [r12 + r15], 'h'
    jmp     .unit_written
.append_m:
    mov     byte [r12 + r15], 'm'

.unit_written:
    inc     r15
    jmp     .unit_next

.too_small_pop:
    pop     rbx
    jmp     .too_small

.next_unit:
.unit_next:
    inc     rbx
    jmp     .unit_loop

.done:
    mov     [r14], r15
    add     rsp, 72             ; 40 bytes temp digits + 32 bytes decomp values
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    add     rsp, 72
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_format_duration

; -----------------------------------------------------------------------------
; str_format_relative_time
;
; Format relative time (e.g. -5 -> "5 seconds ago", 120 -> "in 2 minutes").
;
; Signature:
;   int64_t str_format_relative_time(int64_t seconds_offset, uint8_t *dst,
;                                    uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_format_relative_time
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 48             ; temp digits [rsp..31], flags/params [rsp+32..47]

    mov     rbx, rdi            ; seconds_offset
    mov     r12, rsi            ; dst
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out_len

    ; Determine future/past
    xor     r15, r15            ; is_future = 0
    mov     rax, rbx
    test    rax, rax
    jge     .is_future
    neg     rax                 ; abs_val = -seconds_offset
    jmp     .thresholds

.is_future:
    test    rax, rax
    jz      .thresholds
    mov     r15, 1              ; is_future = 1

.thresholds:
    ; RAX = abs_val
    cmp     rax, 10
    jb      .just_now

    cmp     rax, 60
    jb      .secs

    cmp     rax, 3600
    jb      .mins

    cmp     rax, 86400
    jb      .hours

    ; days
    xor     rdx, rdx
    mov     rcx, 86400
    div     rcx                 ; RAX = days
    lea     rsi, [rel _str_day]
    jmp     .format_time

.secs:
    lea     rsi, [rel _str_second]
    jmp     .format_time

.mins:
    xor     rdx, rdx
    mov     rcx, 60
    div     rcx                 ; RAX = minutes
    lea     rsi, [rel _str_minute]
    jmp     .format_time

.hours:
    xor     rdx, rdx
    mov     rcx, 3600
    div     rcx                 ; RAX = hours
    lea     rsi, [rel _str_hour]
    jmp     .format_time

.just_now:
    ; copy "just now"
    lea     rsi, [rel _str_just_now]
    xor     rdx, rdx
.jn_len:
    cmp     byte [rsi + rdx], 0
    je      .jn_len_done
    inc     rdx
    jmp     .jn_len
.jn_len_done:
    ; rdx = length
    cmp     rdx, r13
    ja      .too_small

    mov     rdi, r12
    call    str_copy_bytes
    mov     [r14], rdx
    add     rsp, 48
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.format_time:
    ; RAX = value, RSI = unit string
    ; Save value at [rsp+32], unit string at [rsp+40]
    mov     [rsp + 32], rax
    mov     [rsp + 40], rsi

    ; format RAX (value) to stack [rsp..]
    mov     rcx, 10
    lea     r8, [rsp + 32]
.dig_loop:
    test    rax, rax
    jz      .dig_done
    xor     rdx, rdx
    div     rcx
    dec     r8
    add     dl, '0'
    mov     [r8], dl
    jmp     .dig_loop

.dig_done:
    lea     rax, [rsp + 32]
    sub     rax, r8             ; val_len
    push    rax                 ; save val_len on stack (shifts offset!)
    ; wait, pushing RAX shifts rsp by 8!
    ; Let's just store val_len in R10. No push.

    ; Let's write this cleanly:
    ; R10 = val_len
    lea     r10, [rsp + 32]
    sub     r10, r8             ; val_len
    mov     [rsp + 40], r8      ; save digits ptr at [rsp+40]

    ; 1. Calculate total length needed
    ; If future: "in " (3) + val_len + " " (1) + unit_len + "s"? (1)
    ; If past: val_len + " " (1) + unit_len + "s"? (1) + " ago" (4)
    ; Find unit length
    mov     rsi, [rsp + 48]     ; unit string ptr (was 40, shifted by digits save? No, let's keep track: [rsp+32] = val, [rsp+40] = digits_ptr, [rsp+48] = unit_ptr)
    ; Let's write unit_len count
    xor     rcx, rcx
.unit_len:
    cmp     byte [rsi + rcx], 0
    je      .unit_len_done
    inc     rcx
    jmp     .unit_len
.unit_len_done:
    ; rcx = unit_len

    ; check if plural: if value > 1
    mov     rax, [rsp + 32]     ; value
    xor     r9, r9              ; plural offset = 0
    cmp     rax, 1
    jbe     .plural_done
    mov     r9, 1               ; +1 byte for "s"
.plural_done:

    xor     r8, r8              ; total_len = 0
    test    r15, r15
    jz      .past_len

    ; future: "in " (3) + val_len + " " (1) + unit_len + plural_len
    lea     r8, [3 + r10 + 1 + rcx + r9]
    jmp     .cap_check

.past_len:
    ; past: val_len + " " (1) + unit_len + plural_len + " ago" (4)
    lea     r8, [r10 + 1 + rcx + r9 + 4]

.cap_check:
    cmp     r8, r13
    ja      .too_small

    ; 2. Build output
    xor     rdx, rdx            ; dst_offset = 0
    test    r15, r15
    jz      .write_val

    ; future: write "in "
    mov     byte [r12], 'i'
    mov     byte [r12 + 1], 'n'
    mov     byte [r12 + 2], ' '
    mov     rdx, 3

.write_val:
    ; copy digits
    push    rcx
    push    r8
    push    r9
    mov     rdi, r12
    add     rdi, rdx            ; dst + dst_offset
    mov     rsi, [rsp + 40 + 24] ; digits ptr (offset adjusted by 3 pushes = 24 bytes)
    mov     rdx, r10            ; val_len
    call    str_copy_bytes
    pop     r9
    pop     r8
    pop     rcx
    add     rdx, r10            ; advance dst_offset

    ; write space
    mov     byte [r12 + rdx], ' '
    inc     rdx

    ; copy unit
    push    rcx
    push    r8
    push    r9
    push    rdx
    mov     rdi, r12
    add     rdi, rdx
    mov     rsi, [rsp + 48 + 32] ; unit_ptr (4 pushes = 32 bytes)
    mov     rdx, rcx            ; unit_len
    call    str_copy_bytes
    pop     rdx
    pop     r9
    pop     r8
    pop     rcx
    add     rdx, rcx

    ; write "s" if plural
    test    r9, r9
    jz      .write_suffix
    mov     byte [r12 + rdx], 's'
    inc     rdx

.write_suffix:
    test    r15, r15
    jnz     .finalize

    ; past: write " ago"
    mov     byte [r12 + rdx], ' '
    mov     byte [r12 + rdx + 1], 'a'
    mov     byte [r12 + rdx + 2], 'g'
    mov     byte [r12 + rdx + 3], 'o'
    add     rdx, 4

.finalize:
    mov     rax, [r14]          ; wait! r14 is out_len ptr!
    mov     [r14], r8           ; write total_len
    add     rsp, 48
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    add     rsp, 48
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_format_relative_time
