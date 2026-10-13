; ============================================================================
; Inflate + PNG Unit Tests
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

extern inflate
extern adler32
extern crc32
extern png_probe
extern huff_build

section .text

global test_inflate_suite
test_inflate_suite:
    TEST_SUITE_BEGIN test_inflate_suite

    TEST_CASE test_inflate_stored
        ; stored block: BFINAL=1,BTYPE=00, LEN=5, NLEN, "hello"
        sub rsp, 2112
        lea rdi, [rsp + 2080]   ; arena struct
        lea rsi, [rsp + 0]      ; base
        mov rdx, 2048
        call arena_init
        TEST_ASSERT_OK rax
        ; build stored block at rsp+1024
        lea rdi, [rsp + 1024]
        mov byte [rdi + 0], 0x01
        mov word [rdi + 1], 5
        mov word [rdi + 3], 0xFFFA
        mov dword [rdi + 5], 0x6C6C6568
        mov byte [rdi + 9], 0x6F
        ; out at rsp+1536
        lea rdi, [rsp + 2080]
        lea rsi, [rsp + 1024]
        mov rdx, 10
        lea rcx, [rsp + 1536]
        mov r8, 512
        call inflate
        cmp rax, 5
        jne .inf_fail
        mov rdi, adler_data
        lea rsi, [rsp + 1536]
        mov rdx, 5
        call memcmp_t
        cmp rax, 0
        je .inf_ok
.inf_fail:
        call test_assert_fail
        jmp .inf_done
.inf_ok:
        call test_assert_pass
.inf_done:
        add rsp, 2112
    TEST_END

    TEST_CASE test_adler32_known
        mov rdi, adler_data
        mov rsi, 5
        mov rdx, 1
        call adler32
        ; adler32("hello") = 0x062C0215
        cmp eax, 0x062C0215
        je .adler_ok
        call test_assert_fail
        jmp .adler_done
.adler_ok:
        call test_assert_pass
.adler_done:
    TEST_END

    TEST_CASE test_png_probe
        mov rdi, png_sig
        mov rsi, 8
        call png_probe
        TEST_ASSERT_EQ rax, 1
    TEST_END

    TEST_CASE test_png_probe_reject
        mov rdi, adler_data
        mov rsi, 8
        call png_probe
        TEST_ASSERT_EQ rax, 0
    TEST_END

    TEST_SUITE_END

memcmp_t:
    PROLOGUE_SAVE rbx, rcx
    mov rbx, rdi
    xor rax, rax
.loop:
    test rdx, rdx
    jz .done
    mov cl, [rbx]
    cmp cl, [rsi]
    jne .diff
    inc rbx
    inc rsi
    dec rdx
    jmp .loop
.diff:
    mov rax, 1
.done:
    EPILOGUE_RESTORE rbx, rcx
    ret

section .rodata
adler_data: db "hello", 0
png_sig: db 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A
