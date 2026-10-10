%ifndef GUARD_LIB_UMATH_CPUID_FALLBACK_ASM
%define GUARD_LIB_UMATH_CPUID_FALLBACK_ASM
; =============================================================================
; umath - unified math library
; cpuid/fallback.asm - run-anywhere versions of umath's non-SSE2 instructions
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; umath may use instructions beyond the x86-64 baseline (SSE2): SSSE3,
; SSE4.1/4.2, POPCNT, LZCNT, BMI1/BMI2. Each such instruction is written as
; a macro from this file (um_roundsd, um_popcnt, ...). The macro checks the
; feature byte that cpuid/cpuid.asm caches; when the feature is present it
; runs the real instruction, otherwise it calls an SSE2-only helper that
; computes the identical result:
;
;   um_roundss/sd/ps/pd    SSE4.1  (|x| + 2^52) - 2^52 is exact round-to-
;                                  nearest-even; floor/ceil/trunc adjust by
;                                  one and restore the sign of x, so signed
;                                  zeros match (ceil(-0.7) = -0.0), NaN is
;                                  quieted like the hardware does. Assumes
;                                  the default MXCSR rounding mode (umath
;                                  only uses immediates 0-3).
;   um_pminsd, um_pmaxsd   SSE4.1  per-lane signed int32 min/max
;   um_pabsd               SSSE3   per-lane int32 abs (INT32_MIN stays)
;   um_pcmpgtq             SSE4.2  per-lane signed int64 compare mask
;   um_popcnt              POPCNT
;   um_lzcnt               LZCNT   (without LZCNT the encoding silently runs
;                                   as BSR and gives wrong answers, so this
;                                   one matters even though it never faults)
;   um_tzcnt               BMI1    (likewise silently BSF)
;   um_pdep, um_pext       BMI2
;
; Fast-path cost: one cmp against the cached byte and a predicted branch.
; The fallback passes operands through a stack slot and preserves every
; register except the destination (flags are clobbered; no umath call site
; keeps flags live across these instructions). The first fallback call
; also runs CPU detection, so umath_cpu_init is optional.
; =============================================================================

bits 64

%include "lib/umath/cpuid/cpuid.asm"

section .rodata
align 16
umath__emu_abs:     dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF
umath__emu_sign:    dq 0x8000000000000000, 0x8000000000000000
umath__emu_two52:   dq 4503599627370496.0
umath__emu_one:     dq 1.0

section .text

; -----------------------------------------------------------------------------
; fallback macros: %1 = destination, %2 = source[, %3 = third operand]
; -----------------------------------------------------------------------------
%macro um_roundss 3
    cmp     byte [rel umath__has_sse41], 0
    je      %%slow
    roundss %1, %2, %3
    jmp     %%done
%%slow:
    sub     rsp, 32
    movdqu  [rsp], %1
    movdqu  [rsp + 16], %2
    push    (%3) | (0 << 8)
    call    umath__emu_round
    add     rsp, 8
    movdqu  %1, [rsp]
    add     rsp, 32
%%done:
%endmacro

%macro um_roundsd 3
    cmp     byte [rel umath__has_sse41], 0
    je      %%slow
    roundsd %1, %2, %3
    jmp     %%done
%%slow:
    sub     rsp, 32
    movdqu  [rsp], %1
    movdqu  [rsp + 16], %2
    push    (%3) | (1 << 8)
    call    umath__emu_round
    add     rsp, 8
    movdqu  %1, [rsp]
    add     rsp, 32
%%done:
%endmacro

%macro um_roundps 3
    cmp     byte [rel umath__has_sse41], 0
    je      %%slow
    roundps %1, %2, %3
    jmp     %%done
%%slow:
    sub     rsp, 32
    movdqu  [rsp], %1
    movdqu  [rsp + 16], %2
    push    (%3) | (2 << 8)
    call    umath__emu_round
    add     rsp, 8
    movdqu  %1, [rsp]
    add     rsp, 32
%%done:
%endmacro

%macro um_roundpd 3
    cmp     byte [rel umath__has_sse41], 0
    je      %%slow
    roundpd %1, %2, %3
    jmp     %%done
%%slow:
    sub     rsp, 32
    movdqu  [rsp], %1
    movdqu  [rsp + 16], %2
    push    (%3) | (3 << 8)
    call    umath__emu_round
    add     rsp, 8
    movdqu  %1, [rsp]
    add     rsp, 32
%%done:
%endmacro

%macro um_pminsd 2
    cmp     byte [rel umath__has_sse41], 0
    je      %%slow
    pminsd %1, %2
    jmp     %%done
%%slow:
    sub     rsp, 32
    movdqu  [rsp], %1
    movdqu  [rsp + 16], %2
    push    0
    call    umath__emu_simd_int
    add     rsp, 8
    movdqu  %1, [rsp]
    add     rsp, 32
%%done:
%endmacro

%macro um_pmaxsd 2
    cmp     byte [rel umath__has_sse41], 0
    je      %%slow
    pmaxsd %1, %2
    jmp     %%done
%%slow:
    sub     rsp, 32
    movdqu  [rsp], %1
    movdqu  [rsp + 16], %2
    push    1
    call    umath__emu_simd_int
    add     rsp, 8
    movdqu  %1, [rsp]
    add     rsp, 32
%%done:
%endmacro

%macro um_pabsd 2
    cmp     byte [rel umath__has_ssse3], 0
    je      %%slow
    pabsd %1, %2
    jmp     %%done
%%slow:
    sub     rsp, 32
    movdqu  [rsp], %1
    movdqu  [rsp + 16], %2
    push    2
    call    umath__emu_simd_int
    add     rsp, 8
    movdqu  %1, [rsp]
    add     rsp, 32
%%done:
%endmacro

%macro um_pcmpgtq 2
    cmp     byte [rel umath__has_sse42], 0
    je      %%slow
    pcmpgtq %1, %2
    jmp     %%done
%%slow:
    sub     rsp, 32
    movdqu  [rsp], %1
    movdqu  [rsp + 16], %2
    push    3
    call    umath__emu_simd_int
    add     rsp, 8
    movdqu  %1, [rsp]
    add     rsp, 32
%%done:
%endmacro

; um__wide = 0 if %1 is a 32-bit general register, 1 otherwise
%macro um__width 1
    %assign um__wide 1
    %ifidni %1, eax
        %assign um__wide 0
    %elifidni %1, ebx
        %assign um__wide 0
    %elifidni %1, ecx
        %assign um__wide 0
    %elifidni %1, edx
        %assign um__wide 0
    %elifidni %1, esi
        %assign um__wide 0
    %elifidni %1, edi
        %assign um__wide 0
    %elifidni %1, ebp
        %assign um__wide 0
    %elifidni %1, esp
        %assign um__wide 0
    %elifidni %1, r8d
        %assign um__wide 0
    %elifidni %1, r9d
        %assign um__wide 0
    %elifidni %1, r10d
        %assign um__wide 0
    %elifidni %1, r11d
        %assign um__wide 0
    %elifidni %1, r12d
        %assign um__wide 0
    %elifidni %1, r13d
        %assign um__wide 0
    %elifidni %1, r14d
        %assign um__wide 0
    %elifidni %1, r15d
        %assign um__wide 0
    %endif
%endmacro

%macro um_popcnt 2
    cmp     byte [rel umath__has_popcnt], 0
    je      %%slow
    popcnt  %1, %2
    jmp     %%done
%%slow:
    um__width %1
    mov     %1, %2              ; value in the destination's width
    sub     rsp, 16
    mov     qword [rsp], 0      ; zero-extend a 32-bit value
    mov     [rsp], %1
    push    0
    call    umath__emu_gpr
    add     rsp, 8
    mov     %1, [rsp]
    add     rsp, 16
%%done:
%endmacro

%macro um_lzcnt 2
    cmp     byte [rel umath__has_lzcnt], 0
    je      %%slow
    lzcnt  %1, %2
    jmp     %%done
%%slow:
    um__width %1
    mov     %1, %2              ; value in the destination's width
    sub     rsp, 16
    mov     qword [rsp], 0      ; zero-extend a 32-bit value
    mov     [rsp], %1
    push    1 + um__wide
    call    umath__emu_gpr
    add     rsp, 8
    mov     %1, [rsp]
    add     rsp, 16
%%done:
%endmacro

%macro um_tzcnt 2
    cmp     byte [rel umath__has_bmi1], 0
    je      %%slow
    tzcnt  %1, %2
    jmp     %%done
%%slow:
    um__width %1
    mov     %1, %2              ; value in the destination's width
    sub     rsp, 16
    mov     qword [rsp], 0      ; zero-extend a 32-bit value
    mov     [rsp], %1
    push    3 + um__wide
    call    umath__emu_gpr
    add     rsp, 8
    mov     %1, [rsp]
    add     rsp, 16
%%done:
%endmacro

%macro um_pdep 3
    cmp     byte [rel umath__has_bmi2], 0
    je      %%slow
    pdep    %1, %2, %3
    jmp     %%done
%%slow:
    sub     rsp, 16
    mov     qword [rsp], 0
    mov     qword [rsp + 8], 0
    mov     [rsp], %2           ; source bits (zero-extended)
    mov     [rsp + 8], %3       ; mask (zero-extended)
    push    5
    call    umath__emu_gpr
    add     rsp, 8
    mov     %1, [rsp]
    add     rsp, 16
%%done:
%endmacro

%macro um_pext 3
    cmp     byte [rel umath__has_bmi2], 0
    je      %%slow
    pext    %1, %2, %3
    jmp     %%done
%%slow:
    sub     rsp, 16
    mov     qword [rsp], 0
    mov     qword [rsp + 8], 0
    mov     [rsp], %2           ; source bits (zero-extended)
    mov     [rsp + 8], %3       ; mask (zero-extended)
    push    6
    call    umath__emu_gpr
    add     rsp, 8
    mov     %1, [rsp]
    add     rsp, 16
%%done:
%endmacro

; -----------------------------------------------------------------------------
; um_need - whole-function dispatch: continue when the feature byte %1 is
;           set, otherwise jump to %2 (a fallback taking the same arguments).
;           Runs detection first if it has not run yet, preserving every
;           argument register, so the very first call already takes the fast
;           path on a capable CPU. Clobbers flags only.
; -----------------------------------------------------------------------------
%macro um_need 2
    cmp     byte [rel %1], 0
    jne     %%ok
    call    umath__cpu_detect_keep
    cmp     byte [rel %1], 0
    je      %2
%%ok:
%endmacro

; -----------------------------------------------------------------------------
; umath__cpu_detect_keep - internal: umath_cpu_init if it has not run yet,
;                          preserving all registers but rax and flags
; -----------------------------------------------------------------------------
umath__cpu_detect_keep:
    cmp     byte [rel umath__cpu_ready], 0
    jne     .done
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    call    umath_cpu_init
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
.done:
    ret

; -----------------------------------------------------------------------------
; helpers: called with [rsp+8] = operation code and the operand slots above
; it; they preserve every register (the macro reloads the destination)
; -----------------------------------------------------------------------------

%macro umath__emu_save 0
    push    rbp
    mov     rbp, rsp            ; [rbp+16] code, [rbp+24] first slot
    push    rax
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    sub     rsp, 64
    movdqu  [rsp], xmm0
    movdqu  [rsp + 16], xmm1
    movdqu  [rsp + 32], xmm2
    movdqu  [rsp + 48], xmm3
    cmp     byte [rel umath__cpu_ready], 0
    jne     %%ready
    call    umath_cpu_init      ; first fallback: detect, so later calls can
%%ready:                        ; take the fast path when the CPU allows
%endmacro

%macro umath__emu_restore 0
    movdqu  xmm0, [rsp]
    movdqu  xmm1, [rsp + 16]
    movdqu  xmm2, [rsp + 32]
    movdqu  xmm3, [rsp + 48]
    add     rsp, 64
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    pop     rbp
%endmacro

; -----------------------------------------------------------------------------
; umath__emu_round1 - round one double without SSE4.1
; args:    xmm0 = x (not NaN), edx = mode (0 nearest-even, 1 floor, 2 ceil,
;          3 trunc)
; returns: xmm0 = rounded value, bit-identical to roundsd
; Clobbers rax, xmm1-xmm3.
; -----------------------------------------------------------------------------
umath__emu_round1:
    movapd  xmm1, xmm0
    andpd   xmm1, [rel umath__emu_abs]  ; a = |x|
    ucomisd xmm1, [rel umath__emu_two52]
    jae     .keep               ; |x| >= 2^52 (or Inf): already integral
    movapd  xmm2, xmm1
    addsd   xmm2, [rel umath__emu_two52]
    subsd   xmm2, [rel umath__emu_two52]  ; r = round-to-nearest-even(a)
    test    edx, edx
    jz      .sign
    movapd  xmm3, xmm2          ; floor(a) = r > a ? r - 1 : r
    ucomisd xmm3, xmm1
    jbe     .floor_ok
    subsd   xmm3, [rel umath__emu_one]
.floor_ok:
    ucomisd xmm2, xmm1          ; ceil(a) = r < a ? r + 1 : r
    jae     .ceil_ok
    addsd   xmm2, [rel umath__emu_one]
.ceil_ok:
    movq    rax, xmm0           ; sign of x in bit 63
    cmp     edx, 3
    je      .use_floor          ; trunc(x) = sign * floor(|x|)
    cmp     edx, 1
    jne     .ceil_mode
    test    rax, rax            ; floor(x): -ceil(|x|) when x < 0
    js      .sign
    jmp     .use_floor
.ceil_mode:
    test    rax, rax            ; ceil(x): -floor(|x|) when x < 0
    jns     .sign
.use_floor:
    movapd  xmm2, xmm3
.sign:
    movapd  xmm1, xmm0
    andpd   xmm1, [rel umath__emu_sign]
    orpd    xmm2, xmm1          ; magnitude with the sign of x (keeps -0.0)
    movapd  xmm0, xmm2
.keep:
    ret

; -----------------------------------------------------------------------------
; umath__emu_round - fallback for um_roundss/sd/ps/pd
; stack:   [rbp+16] = mode | kind << 8 (kind 0 ss, 1 sd, 2 ps, 3 pd),
;          [rbp+24] = destination slot (16 bytes, updated),
;          [rbp+40] = source slot (16 bytes)
; -----------------------------------------------------------------------------
umath__emu_round:
    umath__emu_save
    movzx   edx, byte [rbp + 16]    ; mode
    movzx   r8d, byte [rbp + 17]    ; kind
    lea     rsi, [rbp + 40]
    lea     rdi, [rbp + 24]
    mov     r9d, 1                  ; element count
    cmp     r8d, 2
    jb      .count_ok
    mov     r9d, 4                  ; ps
    je      .count_ok
    mov     r9d, 2                  ; pd
.count_ok:
    test    r8d, 1
    jnz     .doubles
.floats:
    mov     eax, [rsi]
    mov     ecx, eax
    and     ecx, 0x7FFFFFFF
    cmp     ecx, 0x7F800000
    jbe     .float_num
    or      eax, 0x00400000         ; NaN: quiet it, as roundss does
    mov     [rdi], eax
    jmp     .float_next
.float_num:
    cvtss2sd xmm0, [rsi]            ; exact
    call    umath__emu_round1
    cvtsd2ss xmm0, xmm0             ; exact: an integer or the input itself
    movss   [rdi], xmm0
.float_next:
    add     rsi, 4
    add     rdi, 4
    dec     r9d
    jnz     .floats
    jmp     .out
.doubles:
    mov     rax, [rsi]
    mov     rcx, rax
    btr     rcx, 63
    mov     rbx, 0x7FF0000000000000
    cmp     rcx, rbx
    jbe     .double_num
    bts     rax, 51                 ; NaN: quiet it, as roundsd does
    mov     [rdi], rax
    jmp     .double_next
.double_num:
    movsd   xmm0, [rsi]
    call    umath__emu_round1
    movsd   [rdi], xmm0
.double_next:
    add     rsi, 8
    add     rdi, 8
    dec     r9d
    jnz     .doubles
.out:
    umath__emu_restore
    ret

; -----------------------------------------------------------------------------
; umath__emu_simd_int - fallback for um_pminsd/pmaxsd/pabsd/pcmpgtq
; stack:   [rbp+16] = op (0 pminsd, 1 pmaxsd, 2 pabsd, 3 pcmpgtq),
;          [rbp+24] = destination slot (updated), [rbp+40] = source slot
; -----------------------------------------------------------------------------
umath__emu_simd_int:
    umath__emu_save
    mov     edx, [rbp + 16]
    lea     rsi, [rbp + 40]
    lea     rdi, [rbp + 24]
    cmp     edx, 3
    je      .cmpgtq
    xor     ecx, ecx
.dword:
    movsxd  rax, dword [rdi + rcx * 4]  ; destination lane
    movsxd  rbx, dword [rsi + rcx * 4]  ; source lane
    cmp     edx, 1
    je      .max
    ja      .abs
    cmp     rbx, rax                    ; pminsd
    cmovl   rax, rbx
    jmp     .store
.max:
    cmp     rbx, rax                    ; pmaxsd
    cmovg   rax, rbx
    jmp     .store
.abs:
    mov     eax, ebx                    ; pabsd: |source|, INT32_MIN stays
    neg     eax
    cmovs   eax, ebx
.store:
    mov     [rdi + rcx * 4], eax
    inc     ecx
    cmp     ecx, 4
    jb      .dword
    jmp     .out
.cmpgtq:
    xor     ecx, ecx
.qword:
    mov     rax, [rdi + rcx * 8]
    xor     ebx, ebx
    cmp     rax, [rsi + rcx * 8]
    jle     .qword_store
    dec     rbx                         ; all ones where dst > src
.qword_store:
    mov     [rdi + rcx * 8], rbx
    inc     ecx
    cmp     ecx, 2
    jb      .qword
.out:
    umath__emu_restore
    ret

; -----------------------------------------------------------------------------
; umath__emu_gpr - fallback for um_popcnt/lzcnt/tzcnt/pdep/pext
; stack:   [rbp+16] = op (0 popcnt, 1 lzcnt32, 2 lzcnt64, 3 tzcnt32,
;          4 tzcnt64, 5 pdep, 6 pext), [rbp+24] = value (result written
;          back here), [rbp+32] = mask (pdep/pext)
; -----------------------------------------------------------------------------
umath__emu_gpr:
    umath__emu_save
    mov     edx, [rbp + 16]
    mov     rax, [rbp + 24]
    cmp     edx, 5
    jae     .deposit
    cmp     edx, 1
    jb      .popcnt
    cmp     edx, 3
    jb      .lzcnt
    ; tzcnt
    mov     ecx, 32
    cmp     edx, 3
    je      .tz_width
    mov     ecx, 64
.tz_width:
    test    rax, rax
    jz      .count_is_width
    bsf     rax, rax
    jmp     .store
.lzcnt:
    mov     ecx, 32
    cmp     edx, 1
    je      .lz_width
    mov     ecx, 64
.lz_width:
    test    rax, rax
    jz      .count_is_width
    bsr     rbx, rax                    ; index of the highest set bit
    lea     rax, [rcx - 1]
    sub     rax, rbx                    ; lzcnt = (width - 1) - index
    jmp     .store
.count_is_width:
    mov     eax, ecx
    jmp     .store
.popcnt:
    xor     ecx, ecx
.pop_loop:
    test    rax, rax
    jz      .pop_done
    lea     rbx, [rax - 1]
    and     rax, rbx                    ; clear the lowest set bit
    inc     ecx
    jmp     .pop_loop
.pop_done:
    mov     eax, ecx
    jmp     .store
.deposit:
    mov     rsi, [rbp + 32]             ; mask
    xor     edi, edi                    ; result
    mov     r8d, 1                      ; walking bit on the packed side
.dep_loop:
    test    rsi, rsi
    jz      .dep_done
    mov     rbx, rsi
    neg     rbx
    and     rbx, rsi                    ; lowest set bit of the mask
    xor     rsi, rbx
    cmp     edx, 5
    jne     .pext_bit
    test    rax, r8                     ; pdep: next source bit -> mask position
    jz      .dep_next
    or      rdi, rbx
    jmp     .dep_next
.pext_bit:
    test    rax, rbx                    ; pext: bit at mask position -> next slot
    jz      .dep_next
    or      rdi, r8
.dep_next:
    shl     r8, 1
    jmp     .dep_loop
.dep_done:
    mov     rax, rdi
.store:
    mov     [rbp + 24], rax
    umath__emu_restore
    ret

%endif ; GUARD_LIB_UMATH_CPUID_FALLBACK_ASM
