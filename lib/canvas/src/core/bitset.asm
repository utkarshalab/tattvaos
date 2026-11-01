; ============================================================================
; Bitset — Fixed-Size Bit Array Operations
; ============================================================================
; A Bitset is { words: u64*, bits: u64 } (16 bytes); the words come from an
; arena, (bits + 63) / 64 of them, zeroed. Bits past the count stay 0.
;
;   bitset_init(set, bit_count, arena)    -> 0, -EINVAL (no bits), -ENOMEM
;   bitset_set / _clear / _flip(set, i)   -> 0, -ERANGE (i out of range)
;   bitset_test(set, i)                   -> 1 / 0, -ERANGE
;   bitset_count(set)                     -> bits set
;   bitset_find_first(set)                -> lowest set bit, -1 none
;   bitset_clear_all(set)                 -> 0
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern arena_alloc

struc Bitset
    .words:                   resq 1
    .count:                   resq 1
endstruc

section .text

; ---------------------------------------------------------------------------
; bitset_init — rdi = Bitset*, rsi = bit_count, rdx = arena -> rax
; ---------------------------------------------------------------------------
global bitset_init
bitset_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r13
    test r12, r12
    jz .bad
    lea rsi, [r12 + 63]
    shr rsi, 6
    shl rsi, 3                          ; bytes of words
    mov rdi, r13
    push rsi
    sub rsp, 8
    call arena_alloc
    add rsp, 8
    pop rcx
    test rax, rax
    jz .oom
    mov [rbx + Bitset.words], rax
    mov [rbx + Bitset.count], r12
    mov rdi, rax
    shr rcx, 3
    xor eax, eax
    rep stosq
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.bad:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; the bit operations: rdi = Bitset*, rsi = index -> rcx = its word's address,
; rsi = its bit; jae %1 when the index is out of range
%macro BIT_ADDRESS 1
    cmp rsi, [rdi + Bitset.count]
    jae %1
    mov rcx, rsi
    shr rcx, 6
    shl rcx, 3
    add rcx, [rdi + Bitset.words]
    and esi, 63
%endmacro

global bitset_set
bitset_set:
    BIT_ADDRESS .oob
    bts [rcx], rsi
    xor eax, eax
    ret
.oob:
    mov rax, -(ERANGE)
    ret

global bitset_clear
bitset_clear:
    BIT_ADDRESS .oob
    btr [rcx], rsi
    xor eax, eax
    ret
.oob:
    mov rax, -(ERANGE)
    ret

global bitset_flip
bitset_flip:
    BIT_ADDRESS .oob
    btc [rcx], rsi
    xor eax, eax
    ret
.oob:
    mov rax, -(ERANGE)
    ret

global bitset_test
bitset_test:
    BIT_ADDRESS .oob
    xor eax, eax
    bt [rcx], rsi
    setc al
    ret
.oob:
    mov rax, -(ERANGE)
    ret

; ---------------------------------------------------------------------------
; bitset_count — rdi = Bitset* -> rax = bits set
; ---------------------------------------------------------------------------
global bitset_count
bitset_count:
    mov rsi, [rdi + Bitset.words]
    mov rcx, [rdi + Bitset.count]
    add rcx, 63
    shr rcx, 6
    xor eax, eax
.loop:
    test rcx, rcx
    jz .done
    popcnt rdx, [rsi]
    add rax, rdx
    add rsi, 8
    dec rcx
    jmp .loop
.done:
    ret

; ---------------------------------------------------------------------------
; bitset_find_first — rdi = Bitset* -> rax = lowest set bit, -1 none
; ---------------------------------------------------------------------------
global bitset_find_first
bitset_find_first:
    mov rsi, [rdi + Bitset.words]
    mov rcx, [rdi + Bitset.count]
    add rcx, 63
    shr rcx, 6
    xor eax, eax                        ; the word's first bit
.loop:
    test rcx, rcx
    jz .none
    bsf rdx, [rsi]
    jnz .found
    add rax, 64
    add rsi, 8
    dec rcx
    jmp .loop
.found:
    add rax, rdx
    ret
.none:
    mov rax, -1
    ret

; ---------------------------------------------------------------------------
; bitset_clear_all — rdi = Bitset* -> rax = 0
; ---------------------------------------------------------------------------
global bitset_clear_all
bitset_clear_all:
    mov rcx, [rdi + Bitset.count]
    add rcx, 63
    shr rcx, 6
    mov rdi, [rdi + Bitset.words]
    xor eax, eax
    rep stosq
    xor eax, eax
    ret

section .data
global bitset_version
bitset_version: dq 0x010100
