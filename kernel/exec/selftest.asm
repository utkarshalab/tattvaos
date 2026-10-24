; =============================================================================
; Utkarsha OS — kernel/exec/selftest.asm
; =============================================================================
; Boot self-test of the program loader and the package verifier.
;
; UBF: loads kernel/tests/ubf/hello.ubf, checks the record, runs the entry
; point (here, synchronously: the test is about loading, not scheduling) and
; expects 42; then loads a copy with one byte changed and expects
; UBF_ERR_DIGEST, before anything is allocated.
;
; UPK: opens kernel/tests/ubf/hello.upk (signed with the test-only key
; kernel/tests/ubf/test-only.key) trusting that key, takes its main binary,
; loads and runs it, expects 42; then expects a copy with one manifest byte
; changed to fail its signature, and the package to be refused when no key
; is trusted.
;
; Milestones (boot/tests/test_boot_qemu.sh):
;   "UBF loader: hello.ubf loaded, ran and returned 42: PASS"
;   "UBF loader: tampered image refused: PASS"
;   "UPK: hello.upk verified, its main loaded, ran and returned 42: PASS"
;   "UPK: tampered package refused: PASS"
;   "UPK: package from an untrusted key refused: PASS"
; =============================================================================

%ifndef KERNEL_EXEC_SELFTEST_ASM
%define KERNEL_EXEC_SELFTEST_ASM

%include "kernel/exec/ubf.inc"

section .rodata
ubf_selftest_image:
    incbin "kernel/tests/ubf/hello.ubf"
ubf_selftest_image_len equ $ - ubf_selftest_image
upk_selftest_pkg:
    incbin "kernel/tests/ubf/hello.upk"
upk_selftest_pkg_len equ $ - upk_selftest_pkg
upk_selftest_key:                   ; TEST ONLY: never a key to trust for real
    incbin "kernel/tests/ubf/test-only.key.pub"
upk_selftest_main:  db "main", 0

msg_ubf_pass:       db "UBF loader: hello.ubf loaded, ran and returned 42: PASS", 0x0D, 0x0A, 0
msg_ubf_tamper:     db "UBF loader: tampered image refused: PASS", 0x0D, 0x0A, 0
msg_ubf_fail_load:  db "UBF loader: FAIL: ubf_load returned ", 0
msg_ubf_fail_rec:   db "UBF loader: FAIL: the loaded record is wrong", 0x0D, 0x0A, 0
msg_ubf_fail_ret:   db "UBF loader: FAIL: the program returned ", 0
msg_ubf_fail_tamp:  db "UBF loader: FAIL: a tampered image loaded (or failed otherwise): ", 0
msg_ubf_nl:         db 0x0D, 0x0A, 0
msg_upk_pass:       db "UPK: hello.upk verified, its main loaded, ran and returned 42: PASS", 0x0D, 0x0A, 0
msg_upk_tamper:     db "UPK: tampered package refused: PASS", 0x0D, 0x0A, 0
msg_upk_untrusted:  db "UPK: package from an untrusted key refused: PASS", 0x0D, 0x0A, 0
msg_upk_fail_open:  db "UPK: FAIL: upk_open returned ", 0
msg_upk_fail_main:  db "UPK: FAIL: no main binary, or it did not load and return 42: ", 0
msg_upk_fail_tamp:  db "UPK: FAIL: a tampered package was not refused for its signature: ", 0
msg_upk_fail_trust: db "UPK: FAIL: an untrusted package was not refused as untrusted: ", 0
align 8, db 0                       ; the ULF image stays a multiple of 8 bytes

section .bss
alignb 16
ubf_selftest_prog:  resb ubf_prog_t_size
ubf_selftest_copy:  resb ubf_selftest_image_len
alignb 16
upk_selftest_rec:   resb upk_pkg_t_size
upk_selftest_copy:  resb upk_selftest_pkg_len

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
    call upk_selftest
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

; -----------------------------------------------------------------------------
; upk_selftest — the package half of the self-test (see the top of the file)
; -----------------------------------------------------------------------------
upk_selftest:
    push rbx
    push r12
    sub rsp, 8

    ; ---- open hello.upk, trusting the test key ----
    lea rdi, [rel upk_selftest_pkg]
    mov rsi, upk_selftest_pkg_len
    lea rdx, [rel upk_selftest_key]
    mov ecx, 1
    lea r8, [rel upk_selftest_rec]
    xor r9d, r9d                    ; unsigned not accepted
    call upk_open
    test eax, eax
    jnz .open_failed

    ; ---- its main binary, loaded and run ----
    lea rdi, [rel upk_selftest_rec]
    lea rsi, [rel upk_selftest_main]
    call upk_file
    test rax, rax
    jz .main_failed
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rel ubf_selftest_prog]
    call ubf_load
    test eax, eax
    jnz .main_failed
    xor edi, edi
    call [rel ubf_selftest_prog + ubf_prog_t.entry]
    cmp eax, 42
    jne .main_failed
    lea rsi, [rel msg_upk_pass]
    call uart_print_str

    ; ---- one manifest byte changed: the signature fails ----
    lea rsi, [rel upk_selftest_pkg]
    lea rdi, [rel upk_selftest_copy]
    mov ecx, upk_selftest_pkg_len
    rep movsb
    lea rdi, [rel upk_selftest_copy]
    mov eax, [rdi + UPK_H_MAN_OFF]
    xor byte [rdi + rax], 0x01
    mov rsi, upk_selftest_pkg_len
    lea rdx, [rel upk_selftest_key]
    mov ecx, 1
    lea r8, [rel upk_selftest_rec]
    xor r9d, r9d
    call upk_open
    cmp eax, UPK_ERR_SIGNATURE
    jne .tamper_failed
    lea rsi, [rel msg_upk_tamper]
    call uart_print_str

    ; ---- no trusted key: refused as untrusted ----
    lea rdi, [rel upk_selftest_pkg]
    mov rsi, upk_selftest_pkg_len
    lea rdx, [rel upk_selftest_key]
    xor ecx, ecx
    lea r8, [rel upk_selftest_rec]
    xor r9d, r9d
    call upk_open
    cmp eax, UPK_ERR_UNTRUSTED
    jne .trust_failed
    lea rsi, [rel msg_upk_untrusted]
    call uart_print_str
    jmp .ret

.open_failed:
    lea rsi, [rel msg_upk_fail_open]
    jmp .print_code
.main_failed:
    lea rsi, [rel msg_upk_fail_main]
    jmp .print_code
.tamper_failed:
    lea rsi, [rel msg_upk_fail_tamp]
    jmp .print_code
.trust_failed:
    lea rsi, [rel msg_upk_fail_trust]
.print_code:
    call uart_print_str
    call uart_print_hex32
    lea rsi, [rel msg_ubf_nl]
    call uart_print_str
.ret:
    add rsp, 8
    pop r12
    pop rbx
    ret

%endif ; KERNEL_EXEC_SELFTEST_ASM
