; ============================================================================
; fuzz_media — Media + Remote Parser Fuzz Targets (png/jpeg/gif/ttf/icc/rfb)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

global fuzz_png_run
fuzz_png_run:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    mov rdi, rbx
    mov rsi, r12
    call fuzz_target_png
    xor rax, rax
    ret

global fuzz_jpeg_run
fuzz_jpeg_run:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    mov rdi, rbx
    mov rsi, r12
    call fuzz_target_jpeg
    xor rax, rax
    ret

global fuzz_gif_run
fuzz_gif_run:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    mov rdi, rbx
    mov rsi, r12
    call fuzz_target_gif
    xor rax, rax
    ret

global fuzz_ttf_run
fuzz_ttf_run:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    mov rdi, rbx
    mov rsi, r12
    call fuzz_target_ttf
    xor rax, rax
    ret

global fuzz_icc_run
fuzz_icc_run:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    mov rdi, rbx
    mov rsi, r12
    call fuzz_target_icc
    xor rax, rax
    ret

global fuzz_rfb_run
fuzz_rfb_run:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    mov rdi, rbx
    mov rsi, r12
    call fuzz_target_rfb
    xor rax, rax
    ret

section .data
global fuzz_media_version
fuzz_media_version: dq 0x010000
