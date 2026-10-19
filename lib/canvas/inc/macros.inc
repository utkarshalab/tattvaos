; ============================================================================
; Canvas Core Macros — Assert, Trap, Align, Bounds Check
; Pure NASM, no dependencies
; ============================================================================

%ifndef __MACROS_INC__
%define __MACROS_INC__

; ---------------------------------------------------------------------------
; Build-Time Configuration
; ---------------------------------------------------------------------------

%define DEBUG_BUILD     1       ; 1 = debug checks enabled, 0 = release
%define PARANOID_CHECKS 1       ; Extra bounds checks in hot paths
%define TRAP_ON_PANIC   1       ; 1 = int3 on panic, 0 = halt

; ---------------------------------------------------------------------------
; Compile-Time Assertions
; ---------------------------------------------------------------------------

%macro STATIC_ASSERT 2
    %if (%1) == 0
        %error %2
    %endif
%endmacro

%macro ASSERT_SIZE 2
    STATIC_ASSERT ((%1) == (%2)), "Size mismatch: expected %2, got %1"
%endmacro

%macro ASSERT_ALIGN 2
    STATIC_ASSERT ((%1) & ((%2) - 1)) == 0, "Alignment failed: %1 not aligned to %2"
%endmacro

%macro ASSERT_OFFSET 3
    STATIC_ASSERT ((%1) == (%2)), "Offset mismatch for %3: expected %2, got %1"
%endmacro

; ---------------------------------------------------------------------------
; Runtime Assertions (Debug Build Only)
; ---------------------------------------------------------------------------

%macro ASSERT 1
    %if DEBUG_BUILD
        test %1, %1
        jnz %%ok
        call panic_assert_failed
    %%ok:
    %endif
%endmacro

%macro ASSERT_EQ 2
    %if DEBUG_BUILD
        cmp %1, %2
        je %%ok
        call panic_assert_failed
    %%ok:
    %endif
%endmacro

%macro ASSERT_NE 2
    %if DEBUG_BUILD
        cmp %1, %2
        jne %%ok
        call panic_assert_failed
    %%ok:
    %endif
%endmacro

%macro ASSERT_LT 2
    %if DEBUG_BUILD
        cmp %1, %2
        jl %%ok
        call panic_assert_failed
    %%ok:
    %endif
%endmacro

%macro ASSERT_LE 2
    %if DEBUG_BUILD
        cmp %1, %2
        jle %%ok
        call panic_assert_failed
    %%ok:
    %endif
%endmacro

%macro ASSERT_GT 2
    %if DEBUG_BUILD
        cmp %1, %2
        jg %%ok
        call panic_assert_failed
    %%ok:
    %endif
%endmacro

%macro ASSERT_GE 2
    %if DEBUG_BUILD
        cmp %1, %2
        jge %%ok
        call panic_assert_failed
    %%ok:
    %endif
%endmacro

%macro ASSERT_PTR 1
    %if DEBUG_BUILD
        test %1, %1
        jnz %%ok
        call panic_null_ptr
    %%ok:
    %endif
%endmacro

%macro ASSERT_ALIGNED 2
    %if DEBUG_BUILD
        test %1, %2 - 1
        jz %%ok
        call panic_unaligned
    %%ok:
    %endif
%endmacro

%macro ASSERT_BOUNDS 3        ; ptr, offset, size
    %if DEBUG_BUILD || PARANOID_CHECKS
        mov rax, %1
        add rax, %2
        cmp rax, %1
        jb %%overflow
        cmp rax, %3
        ja %%overflow
        jmp %%ok
    %%overflow:
        call panic_bounds
    %%ok:
    %endif
%endmacro

; ---------------------------------------------------------------------------
; Panic / Trap Handlers (defined in log.asm)
; ---------------------------------------------------------------------------

%ifndef PANIC_IMPL
extern panic_assert_failed
extern panic_null_ptr
extern panic_unaligned
extern panic_bounds
extern panic_oom
extern panic_unreachable
%endif

%macro PANIC 0
    %if TRAP_ON_PANIC
        int3
    %else
        hlt
    %endif
%endmacro

%macro UNREACHABLE 0
    call panic_unreachable
    %if TRAP_ON_PANIC
        int3
    %else
        hlt
    %endif
%endmacro

; ---------------------------------------------------------------------------
; Alignment Macros
; ---------------------------------------------------------------------------

%macro ALIGN_UP 2
    ; result in rax: align %1 up to %2 (power of 2)
    mov rax, %1
    add rax, %2 - 1
    and rax, ~(%2 - 1)
%endmacro

%macro ALIGN_DOWN 2
    ; result in rax: align %1 down to %2 (power of 2)
    mov rax, %1
    and rax, ~(%2 - 1)
%endmacro

%macro ALIGN_PTR_UP 2
    ; %1 = register with pointer, %2 = alignment
    add %1, %2 - 1
    and %1, ~(%2 - 1)
%endmacro

%macro ALIGN_PTR_DOWN 2
    and %1, ~(%2 - 1)
%endmacro

; ---------------------------------------------------------------------------
; Memory/Pointer Macros
; ---------------------------------------------------------------------------

%macro PTR_ADD 3
    ; %1 = dest reg, %2 = base reg, %3 = offset
    lea %1, [%2 + %3]
%endmacro

%macro PTR_SUB 3
    lea %1, [%2 - %3]
%endmacro

%macro PTR_DIFF 3
    ; %1 = dest reg, %2 = ptr1, %3 = ptr2
    mov %1, %2
    sub %1, %3
%endmacro

%macro READ_U8 2
    ; %1 = dest, %2 = src ptr
    movzx %1, byte [%2]
%endmacro

%macro READ_U16 2
    movzx %1, word [%2]
%endmacro

%macro READ_U32 2
    mov %1, dword [%2]
%endmacro

%macro READ_U64 2
    mov %1, qword [%2]
%endmacro

%macro WRITE_U8 2
    mov byte [%1], %2
%endmacro

%macro WRITE_U16 2
    mov word [%1], %2
%endmacro

%macro WRITE_U32 2
    mov dword [%1], %2
%endmacro

%macro WRITE_U64 2
    mov qword [%1], %2
%endmacro

; ---------------------------------------------------------------------------
; Bit Manipulation
; ---------------------------------------------------------------------------

%macro BIT_SET 2
    or %1, (1 << %2)
%endmacro

%macro BIT_CLEAR 2
    and %1, ~(1 << %2)
%endmacro

%macro BIT_TEST 2
    test %1, (1 << %2)
%endmacro

%macro BIT_TOGGLE 2
    xor %1, (1 << %2)
%endmacro

%macro BSF 2
    ; %1 = dest, %2 = source (find first set)
    bsf %1, %2
%endmacro

%macro BSR 2
    ; %1 = dest, %2 = source (find last set)
    bsr %1, %2
%endmacro

%macro POPCNT 2
    popcnt %1, %2
%endmacro

; ---------------------------------------------------------------------------
; Loop / Branch Hints
; ---------------------------------------------------------------------------

%macro LIKELY 1
    %ifidn %1, jmp
        jmp
    %else
        %1
    %endif
%endmacro

%macro UNLIKELY 1
    %1
%endmacro

; ---------------------------------------------------------------------------
; String / Memory Operations (Inline for Small Sizes)
; ---------------------------------------------------------------------------

%macro MEMZERO 2
    ; %1 = ptr, %2 = size (compile-time constant)
    %if %2 <= 8
        mov qword [%1], 0
    %elif %2 <= 16
        mov qword [%1], 0
        mov qword [%1 + 8], 0
    %elif %2 <= 32
        mov qword [%1], 0
        mov qword [%1 + 8], 0
        mov qword [%1 + 16], 0
        mov qword [%1 + 24], 0
    %else
        push rdi
        push rcx
        mov rdi, %1
        mov rcx, %2 / 8
        xor rax, rax
        rep stosq
        mov rcx, %2 & 7
        rep stosb
        pop rcx
        pop rdi
    %endif
%endmacro

%macro MEMCOPY 3
    ; %1 = dst, %2 = src, %3 = size
    %if %3 <= 8
        mov rax, [%2]
        mov [%1], rax
    %elif %3 <= 16
        mov rax, [%2]
        mov rdx, [%2 + 8]
        mov [%1], rax
        mov [%1 + 8], rdx
    %else
        push rsi
        push rdi
        push rcx
        mov rsi, %2
        mov rdi, %1
        mov rcx, %3
        rep movsb
        pop rcx
        pop rdi
        pop rsi
    %endif
%endmacro

%macro MEMEQUAL 4
    ; %1 = ptr1, %2 = ptr2, %3 = size, %4 = result reg (0=equal, 1=diff)
    %if %3 <= 8
        mov rax, [%1]
        xor rax, [%2]
        test rax, rax
        setnz %4b
    %elif %3 <= 16
        mov rax, [%1]
        mov rdx, [%1 + 8]
        xor rax, [%2]
        xor rdx, [%2 + 8]
        or rax, rdx
        setnz %4b
    %else
        push rsi
        push rdi
        push rcx
        mov rsi, %1
        mov rdi, %2
        mov rcx, %3
        repe cmpsb
        setne %4b
        pop rcx
        pop rdi
        pop rsi
    %endif
%endmacro

; ---------------------------------------------------------------------------
; Integer Math Helpers
; ---------------------------------------------------------------------------

%macro MUL_DIV 4
    ; %1 = result, %2 = numerator, %3 = multiplier, %4 = divisor
    ; Computes: result = (numerator * multiplier) / divisor
    mov rax, %2
    mul %3
    div %4
    mov %1, rax
%endmacro

%macro DIV_ROUND_UP 3
    ; %1 = result, %2 = numerator, %3 = denominator
    mov rax, %2
    add rax, %3 - 1
    xor rdx, rdx
    div %3
    mov %1, rax
%endmacro

%macro ALIGN_DIV 3
    ; %1 = result, %2 = value, %3 = alignment (power of 2)
    mov rax, %2
    add rax, %3 - 1
    and rax, ~(%3 - 1)
    mov %1, rax
%endmacro

; ---------------------------------------------------------------------------
; Function Attribute Markers (for documentation)
; ---------------------------------------------------------------------------

%macro PURE 0
    ; No side effects, result depends only on args
%endmacro

%macro CONST 0
    ; No side effects, result depends only on args, no memory reads
%endmacro

%macro NORETURN 0
    ; Function never returns
%endmacro

%macro HOT 0
    ; Hot path - optimize aggressively
%endmacro

%macro COLD 0
    ; Cold path - optimize for size
%endmacro

%endif ; __MACROS_INC__
