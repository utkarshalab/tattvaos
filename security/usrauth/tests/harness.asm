; =============================================================================
; Tattva OS — security/usrauth/tests/harness.asm
; =============================================================================
; Test harness: kernel-service doubles and result reporting.
;
; This file is for the hosted test build ONLY. It is never included by
; kernel/entry.asm, where the real `mono_get_nanos` is provided by lib/time.
;
; ONLY THE CLOCK IS SUBSTITUTED. Entropy comes from the real lib/urand, because
; substituting it is precisely what hid a CSPRNG that faulted on its first
; store and, once that was fixed, returned the same bytes on every call. A test
; double for a security primitive tests the double.
;
; THE CLOCK ADVANCES BY 1ns PER READ. A frozen clock would be simpler, but it
; makes every token minted in the same test run share an `issued_ns`, and
; individual revocation is keyed on exactly that field — so a frozen clock
; would let a test claiming to revoke ONE token actually revoke all of them and
; still pass. The increment is 1ns rather than something larger so that the
; TTL tests, which use absolute deadlines, stay on the intended side of their
; boundaries no matter how many calls the suite makes.
;
; THE RESULT IS WRITTEN, NOT RETURNED AS AN EXIT CODE. A Linux exit status is
; truncated to 8 bits, so a suite reporting failures as a bitmask silently
; loses every test past the eighth. The mask goes out as four raw bytes on
; stdout instead, and the runner decodes it.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM), hosted (Linux syscall ABI)
; =============================================================================

section .data
align 8

usrauth_test_clock:     dq 1000000
usrauth_test_result:    dd 0

section .text

global mono_get_nanos
global usrauth_test_report

; -----------------------------------------------------------------------------
; mono_get_nanos — monotonic, and strictly increasing across calls.
; -----------------------------------------------------------------------------
align 32
mono_get_nanos:
    mov rax, [usrauth_test_clock]
    inc qword [usrauth_test_clock]
    ret

; -----------------------------------------------------------------------------
; usrauth_test_report — emit the failure bitmask and exit.
;
; Inputs:
;   EDI = Failure bitmask (0 = every test passed)
; Does not return.
; -----------------------------------------------------------------------------
align 32
usrauth_test_report:
    mov [usrauth_test_result], edi

    mov eax, 1                      ; write
    mov edi, 1                      ; stdout
    lea rsi, [usrauth_test_result]
    mov edx, 4
    syscall

    xor edi, edi
    mov eax, 60                     ; exit
    syscall
