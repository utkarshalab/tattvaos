; ============================================================================
; Adler-32 — zlib Checksum
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"

; struct offsets (hoisted above use)
%define ADLER_MOD  65521

section .text


; ---------------------------------------------------------------------------
; adler32
;   IN: rdi = data, rsi = len, rdx = initial (1 for fresh)
;   OUT: rax = checksum
; ---------------------------------------------------------------------------
global adler32
adler32:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    mov eax, edx
    shr eax, 16
    mov r13d, eax  ; s2
    and edx, 0xFFFF
    mov r11d, edx  ; s1
    mov rcx, r12
    test rcx, rcx
    jz .done
.sloop:
    movzx edx, byte [rbx]
    add r11d, edx
    cmp r11d, ADLER_MOD
    jb .s1ok
    sub r11d, ADLER_MOD
.s1ok:
    add r13d, r11d
    cmp r13d, ADLER_MOD
    jb .s2ok
    sub r13d, ADLER_MOD
.s2ok:
    inc rbx
    dec rcx
    jnz .sloop
.done:
    mov eax, r13d
    shl eax, 16
    or eax, r11d
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global adler32_version
adler32_version: dq 0x010000
