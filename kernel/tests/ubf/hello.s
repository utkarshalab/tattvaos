; =============================================================================
; Utkarsha OS — kernel/tests/ubf/hello.s
; =============================================================================
; The program the boot self-test loads (kernel/exec/selftest.asm). Built with
;
;     utasm -f ubf kernel/tests/ubf/hello.s -o kernel/tests/ubf/hello.ubf
;
; and committed as hello.ubf, since the kernel is assembled by NASM, which
; cannot write UBF. It touches each thing the loader does: a call through an
; import's stub, a read of an import's slot (..gotpcrel), a pointer fixed by
; an ABS64 relocation, writable data and bss. It returns 42.
; =============================================================================

bits 64
default rel

extern ut_console_print
global _start

section .text
_start:
    mov     rdi, [greeting_ptr]                     ; ABS64-relocated pointer
    call    ut_console_print                        ; through the stub
    lea     rdi, [second]
    mov     rax, [rel ut_console_print wrt ..gotpcrel]  ; through the slot
    call    rax
    mov     dword [counter], 40                     ; bss
    mov     eax, [counter]
    add     eax, [two]                              ; data
    ret

section .rodata
greeting:   db "UBF app: hello from a loaded program", 0x0D, 0x0A, 0
second:     db "UBF app: imports, relocations and data work", 0x0D, 0x0A, 0

section .data
greeting_ptr:   dq greeting
two:            dd 2

section .bss
counter:        resd 1
