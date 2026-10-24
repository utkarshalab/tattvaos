; =============================================================================
; Utkarsha OS — kernel/exec/selftest.asm
; =============================================================================
; Boot self-test of the program loader. It loads kernel/tests/ubf/hello.ubf,
; checks the record, runs the entry point (here, synchronously: the test is
; about loading, not scheduling) and expects 42; then loads a copy with one
; byte changed and expects UBF_ERR_DIGEST, before anything is allocated.
;
; Milestones (boot/tests/test_boot_qemu.sh):
;   "UBF loader: hello.ubf loaded, ran and returned 42: PASS"
;   "UBF loader: tampered image refused: PASS"
; =============================================================================

%ifndef KERNEL_EXEC_SELFTEST_ASM
%define KERNEL_EXEC_SELFTEST_ASM

%include "kernel/exec/ubf.inc"

section .rodata
ubf_selftest_image:
    incbin "kernel/tests/ubf/hello.ubf"
ubf_selftest_image_len equ $ - ubf_selftest_image

msg_ubf_pass:       db "UBF loader: hello.ubf loaded, ran and returned 42: PASS", 0x0D, 0x0A, 0
msg_ubf_tamper:     db "UBF loader: tampered image refused: PASS", 0x0D, 0x0A, 0
msg_ubf_fail_load:  db "UBF loader: FAIL: ubf_load returned ", 0
msg_ubf_fail_rec:   db "UBF loader: FAIL: the loaded record is wrong", 0x0D, 0x0A, 0
msg_ubf_fail_ret:   db "UBF loader: FAIL: the program returned ", 0
msg_ubf_fail_tamp:  db "UBF loader: FAIL: a tampered image loaded (or failed otherwise): ", 0
msg_ubf_nl:         db 0x0D, 0x0A, 0
align 8, db 0                       ; the ULF image stays a multiple of 8 bytes

section .bss
alignb 16
ubf_selftest_prog:  resb ubf_prog_t_size
ubf_selftest_copy:  resb ubf_selftest_image_len

section .text

; -----------------------------------------------------------------------------
; ubf_selftest — run the loader's boot self-test, printing its milestones
; Input:  none
; Output: none
; -----------------------------------------------------------------------------
global ubf_selftest
ubf_selftest:
    push rbx
    push rsi

    ; ---- load and run hello.ubf ----
    lea rdi, [rel ubf_selftest_image]
    mov rsi, ubf_selftest_image_len
    lea rdx, [rel ubf_selftest_prog]
    call ubf_load
    test eax, eax
    jnz .load_failed

    lea rbx, [rel ubf_selftest_prog]
    cmp dword [rbx + ubf_prog_t.kind], UBF_KIND_APP
    jne .record_bad
    mov rax, [rbx + ubf_prog_t.base]
    mov rcx, UBF_WINDOW_BASE
    cmp rax, rcx
    jb .record_bad
    mov rcx, [rbx + ubf_prog_t.entry]
    cmp rcx, rax
    jb .record_bad
    add rax, [rbx + ubf_prog_t.size]
    cmp rcx, rax
    jae .record_bad

    xor edi, edi                    ; no start block
    call [rbx + ubf_prog_t.entry]
    cmp eax, 42
    jne .returned_wrong
    lea rsi, [rel msg_ubf_pass]
    call uart_print_str

    ; ---- a copy with one byte changed must be refused ----
    lea rsi, [rel ubf_selftest_image]
    lea rdi, [rel ubf_selftest_copy]
    mov ecx, ubf_selftest_image_len
    rep movsb
    lea rdi, [rel ubf_selftest_copy]
    xor byte [rdi + ubf_selftest_image_len - 1], 0x01
    mov rsi, ubf_selftest_image_len
    lea rdx, [rel ubf_selftest_prog]
    call ubf_load
    cmp eax, UBF_ERR_DIGEST
    jne .tamper_loaded
    lea rsi, [rel msg_ubf_tamper]
    call uart_print_str
    jmp .ret

.load_failed:
    lea rsi, [rel msg_ubf_fail_load]
    jmp .print_code
.tamper_loaded:
    lea rsi, [rel msg_ubf_fail_tamp]
.print_code:
    call uart_print_str
    call uart_print_hex32
    lea rsi, [rel msg_ubf_nl]
    call uart_print_str
    jmp .ret
.returned_wrong:
    lea rsi, [rel msg_ubf_fail_ret]
    call uart_print_str
    call uart_print_dec
    lea rsi, [rel msg_ubf_nl]
    call uart_print_str
    jmp .ret
.record_bad:
    lea rsi, [rel msg_ubf_fail_rec]
    call uart_print_str
.ret:
    pop rsi
    pop rbx
    ret

%endif ; KERNEL_EXEC_SELFTEST_ASM
