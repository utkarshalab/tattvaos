; =============================================================================
; lib/io/core/smap.asm
; Supervisor Mode Access Prevention (SMAP) & User Pointer Validation.
;
; Implements security validation checks for buffers passed from user mode and
; EFLAGS AC controls (STAC/CLAC) to protect supervisor mode page accesses.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CORE_SMAP_ASM
%define IO_CORE_SMAP_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/error/codes.asm"

USER_SPACE_LIMIT    equ 0x0000800000000000

section .text

global io_validate_user_buffer
global io_enable_smap
global io_disable_smap

; =============================================================================
; io_validate_user_buffer — Validate user-space buffer boundaries
; In : RDI = Virtual base address of the buffer
;      RSI = Length in bytes
; Out: RAX = 0 on success, or IO_ERR_BADARG if range overlaps kernel space
; =============================================================================
IO_FUNC io_validate_user_buffer
    test    rsi, rsi
    jz      .err

    mov     rax, rdi
    add     rax, rsi                ; RAX = virtual_addr + length
    jc      .err                    ; Overflow check

    mov     rcx, USER_SPACE_LIMIT
    cmp     rax, rcx
    ja      .err                    ; Crosses user-space boundary

    xor     rax, rax                ; Return 0 (Success)
    ret

.err:
    mov     rax, IO_ERR_BADARG
IO_ENDFUNC io_validate_user_buffer

; =============================================================================
; io_enable_smap — Enable Supervisor Access to User Pages (executes STAC)
; =============================================================================
IO_FUNC io_enable_smap
    stac                            ; Set AC flag in EFLAGS to allow user page access
IO_ENDFUNC io_enable_smap

; =============================================================================
; io_disable_smap — Disable Supervisor Access to User Pages (executes CLAC)
; =============================================================================
IO_FUNC io_disable_smap
    clac                            ; Clear AC flag in EFLAGS to prevent user page access
IO_ENDFUNC io_disable_smap

%endif ; IO_CORE_SMAP_ASM
