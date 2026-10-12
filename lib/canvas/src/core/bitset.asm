; ============================================================================
; Bitset — Fixed-Size Bit Array Operations
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

%define Bitset_words    0
%define Bitset_count    8
%define Bitset_size     16

; ---------------------------------------------------------------------------
; bitset_init
;   Initialize bitset
;   IN:  rdi = Bitset*, rsi = bit_count, rdx = arena
;   OUT: rax = 0 OK, negative error
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
    jnz .ok
    RETURN_ERROR EINVAL
.ok:
    ; Calculate words needed
    mov rax, r12
    add rax, 63
    shr rax, 6
    mov r12, rax

    ; Allocate words array
    mov rdi, r13
    mov rsi, rax
    shl rsi, 3
    call arena_alloc
    test rax, rax
    jz .oom

    mov qword [rbx + Bitset_words], rax
    mov qword [rbx + Bitset_count], r12

    ; Zero initialize
    mov rdi, rax
    mov rcx, r12
    xor rax, rax
    rep stosq

    xor rax, rax
    ret
.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; bitset_set
;   Set bit
;   IN:  rdi = Bitset*, rsi = bit_index
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global bitset_set
bitset_set:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    cmp r12, [rbx + Bitset_count]
    jae .oob

    mov rax, r12
    shr rax, 6
    mov rcx, r12
    and rcx, 63
    bts qword [rbx + Bitset_words + rax * 8], rcx
    xor rax, rax
    ret
.oob:
    RETURN_ERROR ERANGE

; ---------------------------------------------------------------------------
; bitset_clear
;   Clear bit
;   IN:  rdi = Bitset*, rsi = bit_index
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global bitset_clear
bitset_clear:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    cmp r12, [rbx + Bitset_count]
    jae .oob

    mov rax, r12
    shr rax, 6
    mov rcx, r12
    and rcx, 63
    btr qword [rbx + Bitset_words + rax * 8], rcx
    xor rax, rax
    ret
.oob:
    RETURN_ERROR ERANGE

; ---------------------------------------------------------------------------
; bitset_test
;   Test bit
;   IN:  rdi = Bitset*, rsi = bit_index
;   OUT: rax = 1 if set, 0 if clear, ERANGE if OOB
; ---------------------------------------------------------------------------
global bitset_test
bitset_test:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    cmp r12, [rbx + Bitset_count]
    jae .oob

    mov rax, r12
    shr rax, 6
    mov rcx, r12
    and rcx, 63
    bt qword [rbx + Bitset_words + rax * 8], rcx
    setc al
    movzx rax, al
    ret
.oob:
    RETURN_ERROR ERANGE

; ---------------------------------------------------------------------------
; bitset_flip
;   Flip bit
;   IN:  rdi = Bitset*, rsi = bit_index
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global bitset_flip
bitset_flip:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    cmp r12, [rbx + Bitset_count]
    jae .oob

    mov rax, r12
    shr rax, 6
    mov rcx, r12
    and rcx, 63
    btc qword [rbx + Bitset_words + rax * 8], rcx
    xor rax, rax
    ret
.oob:
    RETURN_ERROR ERANGE

; ---------------------------------------------------------------------------
; bitset_count
;   Count set bits (population count)
;   IN:  rdi = Bitset*
;   OUT: rax = count
; ---------------------------------------------------------------------------
global bitset_count
bitset_count:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx

    mov r12, [rbx + Bitset_words]
    mov r13, [r12]
    xor rax, rax
    test r13, r13
    jz .done

    mov r12, r13
    mov rcx, [rbx + Bitset_count]
    mov rcx, [rcx + 8]  ; word array pointer? Wait, Bitset_words is at offset 0

    mov rdi, [rbx + Bitset_words]
    mov rcx, [rbx + Bitset_count]
    ; rdi = words array, rcx = word count
    xor rax, rax
.loop:
    popcnt rdx, [rdi]
    add rax, rdx
    add rdi, 8
    dec rcx
    jnz .loop
.done:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; bitset_find_first
;   Find first set bit
;   IN:  rdi = Bitset*
;   OUT: rax = bit index, -1 if none
; ---------------------------------------------------------------------------
global bitset_find_first
bitset_find_first:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx

    mov r12, [rbx + Bitset_words]
    mov r13, [rbx + Bitset_count]
    mov rdi, r12
    xor rax, rax
.loop:
    test r13, r13
    jz .not_found
    bsf rdx, [rdi]
    jnz .found
    add rax, 64
    add rdi, 8
    dec r13
    jnz .loop
.not_found:
    mov rax, -1
    ret
.found:
    add rax, rdx
    ret

; ---------------------------------------------------------------------------
; bitset_clear_all
;   Clear all bits
;   IN:  rdi = Bitset*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global bitset_clear_all
bitset_clear_all:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    mov r12, [rbx + Bitset_count]
    mov rdi, [rbx + Bitset_words]
    xor rax, rax
    rep stosq
    xor rax, rax
    ret

section .data
global bitset_version
bitset_version: dq 0x010000