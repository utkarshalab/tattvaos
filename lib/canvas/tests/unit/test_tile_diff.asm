; ============================================================================
; Tile-Diff + RFB Unit Tests
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

extern tile_diff_init
extern tile_diff_update
extern tile_diff_is_dirty
extern rle_encode
extern rle_decode
extern delta_encode_tile
extern delta_decode_tile
extern adaptive_init
extern adaptive_choose

section .text

global test_tile_diff_suite
test_tile_diff_suite:
    TEST_SUITE_BEGIN test_tile_diff_suite

    TEST_CASE test_rle_roundtrip
        sub rsp, 256
        ; src: 64 bytes: 16 zeros, 8 0xAB, rest pattern
        mov rdi, rsp
        mov rcx, 64
        xor rax, rax
.z:
        mov byte [rdi + rax], 0
        inc rax
        cmp rax, rcx
        jb .z
        mov rcx, 8
        mov rax, 16
.fill_ab:
        mov byte [rsp + rax], 0xAB
        inc rax
        dec rcx
        jnz .fill_ab
        ; encode
        mov rdi, rsp
        mov rsi, 64
        lea rdx, [rsp + 64]
        mov rcx, 128
        call rle_encode
        TEST_ASSERT_OK rax
        mov rbx, rax
        ; decode
        lea rdi, [rsp + 64]
        mov rsi, rbx
        lea rdx, [rsp + 192]
        mov rcx, 64
        call rle_decode
        TEST_ASSERT_EQ rax, 64
        ; compare
        mov rdi, rsp
        lea rsi, [rsp + 192]
        mov rcx, 64
        call memcmp_test
        TEST_ASSERT_EQ rax, 0
        add rsp, 256
    TEST_END

    TEST_CASE test_delta_all_same
        sub rsp, 256
        ; prev == cur (16 pixels)
        mov rdi, rsp
        mov rcx, 16
        mov eax, 0x11223344
.fill1:
        mov [rdi], eax
        add rdi, 4
        dec rcx
        jnz .fill1
        mov rdi, rsp
        mov rsi, rsp
        mov rdx, 16
        shl rdx, 2
        call memcopy
        ; encode: cur=rsp, prev=rsp+64
        lea rdi, [rsp + 128]
        mov rsi, 128
        mov rdx, rsp
        lea rcx, [rsp + 64]
        mov r8, 16
        call delta_encode_tile
        TEST_ASSERT_OK rax
        TEST_ASSERT_EQ rax, 0
        add rsp, 256
    TEST_END

    TEST_CASE test_delta_one_pixel
        sub rsp, 256
        mov rdi, rsp
        mov rcx, 32
        xor eax, eax
.z3:
        mov [rdi], eax
        add rdi, 4
        dec rcx
        jnz .z3
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 128
        mov rdx, 128
        call memcopy
        mov dword [rsp + 128 + 5 * 4], 0xDEADBEEF
        lea rdi, [rsp + 192]
        mov rsi, 64
        mov rdx, rsp
        add rdx, 128
        lea rcx, [rsp + 0]
        mov r8, 32
        call delta_encode_tile
        TEST_ASSERT_EQ rax, 6
        add rsp, 256
    TEST_END

    TEST_CASE test_adaptive_flat_chooses_rle
        sub rsp, 64
        mov rdi, rsp
        mov rsi, 56
        call adaptive_init
        TEST_ASSERT_OK rax
        mov rbx, rax
        mov rdi, rbx
        mov rsi, 4096
        mov rdx, 100
        mov rcx, 1
        call adaptive_choose
        TEST_ASSERT_EQ rax, 1
        add rsp, 64
    TEST_END

    TEST_SUITE_END

memcmp_test:
    PROLOGUE_SAVE rbx, rcx
    mov rbx, rdi
    xor rax, rax
.loop:
    test rcx, rcx
    jz .done
    mov dl, [rbx]
    cmp dl, [rsi]
    jne .diff
    inc rbx
    inc rsi
    dec rcx
    jmp .loop
.diff:
    mov rax, 1
.done:
    EPILOGUE_RESTORE rbx, rcx
    ret
