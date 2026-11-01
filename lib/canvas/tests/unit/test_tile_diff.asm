; ============================================================================
; Unit Test — Remote Tile Codecs (src/codec/rle.asm, delta.asm)
; ============================================================================
; test_tile_diff_suite -> eax = failed cases (each case returns 0 / 1).
; RLE: round trips of flat, literal, mixed and longer-than-a-packet data, the
; exact coding of a run, a full output, damaged streams. Delta: no change is
; no bytes, changed pixels round trip, a damaged stream is refused.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern rle_encode
extern rle_decode
extern delta_encode_tile
extern delta_decode_tile
extern memcmp

%define SPACE 8192

%define TILE 16

section .text

global test_tile_diff_suite
global test_tile_diff_main
test_tile_diff_suite:
test_tile_diff_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call %1
    add ebx, eax
%endmacro
    CASE tt_run_coding
    CASE tt_roundtrip_flat
    CASE tt_roundtrip_long
    CASE tt_roundtrip_literal
    CASE tt_roundtrip_mixed
    CASE tt_encode_full
    CASE tt_decode_damaged
    CASE tt_delta_same
    CASE tt_delta_roundtrip
    CASE tt_delta_damaged
    mov eax, ebx
    pop rbx
    ret

%macro PASS 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret
%endmacro

; rle round trip of ebx bytes at src -> rax = 0 when decoded equals src
roundtrip:
    sub rsp, 8
    lea rdi, [rel src]
    mov esi, ebx
    lea rdx, [rel coded]
    mov ecx, SPACE
    call rle_encode
    test rax, rax
    js .bad
    lea rdi, [rel coded]
    mov rsi, rax
    lea rdx, [rel out]
    mov ecx, SPACE
    call rle_decode
    cmp eax, ebx
    jne .bad
    lea rdi, [rel out]
    lea rsi, [rel src]
    mov edx, ebx
    call memcmp
    add rsp, 8
    ret
.bad:
    mov eax, 1
    add rsp, 8
    ret

; ecx bytes at src set to al
%macro FLAT 2
    lea rdi, [rel src]
    mov eax, %1
    mov ecx, %2
    rep stosb
%endmacro

tt_run_coding:
    sub rsp, 8
    FLAT 0x41, 5
    lea rdi, [rel src]
    mov esi, 5
    lea rdx, [rel coded]
    mov ecx, SPACE
    call rle_encode
    cmp rax, 2
    jne .fail
    cmp byte [rel coded], -4            ; 1 - 5
    jne .fail
    cmp byte [rel coded + 1], 0x41
    jne .fail
    PASS

tt_roundtrip_flat:
    push rbx
    FLAT 7, 100
    mov ebx, 100
    call roundtrip
    pop rbx
    ret

tt_roundtrip_long:
    push rbx
    FLAT 9, 1000                        ; several packets
    mov ebx, 1000
    call roundtrip
    pop rbx
    ret

tt_roundtrip_literal:
    push rbx
    lea rdi, [rel src]
    xor ecx, ecx
.fill:
    mov [rdi + rcx], cl                 ; no two neighbours equal
    inc ecx
    cmp ecx, 250
    jb .fill
    mov ebx, 250
    call roundtrip
    pop rbx
    ret

tt_roundtrip_mixed:
    push rbx
    lea rdi, [rel src]
    xor ecx, ecx
.fill:
    mov eax, ecx                        ; runs of 1 .. 8 of changing bytes
    shr eax, 3
    imul eax, eax, 37
    test ecx, 32
    jz .keep
    add eax, ecx
.keep:
    mov [rdi + rcx], al
    inc ecx
    cmp ecx, 2000
    jb .fill
    mov ebx, 2000
    call roundtrip
    pop rbx
    ret

tt_encode_full:
    sub rsp, 8
    FLAT 3, 300                         ; needs 6 bytes
    lea rdi, [rel src]
    mov esi, 300
    lea rdx, [rel coded]
    mov ecx, 3
    call rle_encode
    cmp rax, -(ENOSPC)
    jne .fail
    PASS

tt_decode_damaged:
    sub rsp, 8
    mov byte [rel coded], 10            ; 11 literals, only 1 follows
    mov byte [rel coded + 1], 1
    lea rdi, [rel coded]
    mov esi, 2
    lea rdx, [rel out]
    mov ecx, SPACE
    call rle_decode
    cmp rax, -(EINVAL)
    jne .fail
    mov byte [rel coded], -3            ; a run with no byte
    lea rdi, [rel coded]
    mov esi, 1
    lea rdx, [rel out]
    mov ecx, SPACE
    call rle_decode
    cmp rax, -(EINVAL)
    jne .fail
    mov byte [rel coded], -100          ; 101 bytes into 10
    lea rdi, [rel coded]
    mov esi, 2
    lea rdx, [rel out]
    mov ecx, 10
    call rle_decode
    cmp rax, -(EINVAL)
    jne .fail
    PASS


; prev: pixels i * 3; cur: the same
same_tiles:
    lea rdi, [rel prev]
    lea rsi, [rel cur]
    xor ecx, ecx
.fill:
    imul eax, ecx, 3
    mov [rdi + rcx * 4], eax
    mov [rsi + rcx * 4], eax
    inc ecx
    cmp ecx, TILE
    jb .fill
    ret

tt_delta_same:
    sub rsp, 8
    call same_tiles
    lea rdi, [rel coded]
    mov esi, SPACE
    lea rdx, [rel cur]
    lea rcx, [rel prev]
    mov r8d, TILE
    call delta_encode_tile
    test rax, rax
    jnz .fail
    PASS

tt_delta_roundtrip:
    sub rsp, 8
    call same_tiles
    mov dword [rel cur + 0 * 4], 0xAABBCCDD
    mov dword [rel cur + 7 * 4], 0x12345678
    mov dword [rel cur + 15 * 4], 1
    lea rdi, [rel coded]
    mov esi, SPACE
    lea rdx, [rel cur]
    lea rcx, [rel prev]
    mov r8d, TILE
    call delta_encode_tile
    cmp rax, 18                         ; three changed pixels of 6 bytes
    jne .fail
    lea rdi, [rel prev]
    lea rsi, [rel coded]
    mov rdx, rax
    lea rcx, [rel out]
    mov r8d, TILE
    call delta_decode_tile
    test rax, rax
    jnz .fail
    lea rdi, [rel out]
    lea rsi, [rel cur]
    mov edx, TILE * 4
    call memcmp
    test eax, eax
    jnz .fail
    PASS

tt_delta_damaged:
    sub rsp, 8
    call same_tiles
    mov word [rel coded], TILE          ; index past the tile
    mov dword [rel coded + 2], 1
    lea rdi, [rel prev]
    lea rsi, [rel coded]
    mov edx, 6
    lea rcx, [rel out]
    mov r8d, TILE
    call delta_decode_tile
    cmp rax, -(EINVAL)
    jne .fail
    mov word [rel coded], 0             ; a cut entry
    lea rdi, [rel prev]
    lea rsi, [rel coded]
    mov edx, 5
    lea rcx, [rel out]
    mov r8d, TILE
    call delta_decode_tile
    cmp rax, -(EINVAL)
    jne .fail
    PASS


section .bss
alignb 16
src:    resb SPACE
coded:  resb SPACE
out:    resb SPACE
prev:   resd TILE
cur:    resd TILE
