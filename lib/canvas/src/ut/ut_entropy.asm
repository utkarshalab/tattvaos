; ============================================================================
; Utkarsha Entropy Service Binding — ut_entropy.asm
; Hardware random numbers for tokens, keys, capability generation
; ============================================================================

%define UT_BINDING_IMPL 1
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"

section .text

; ---------------------------------------------------------------------------
; ut_entropy_get
;   Fill buffer with cryptographic random bytes
;   IN:  rdi = buffer pointer
;        rsi = length
;   OUT: rax = 0 OK, negative error (EAGAIN if pool low)
; ---------------------------------------------------------------------------
global ut_entropy_get
ut_entropy_get:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    mov rax, SYS_ENTROPY_GET
    syscall
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; ut_entropy_u64
;   Get 64 random bits (fast path for tokens)
;   OUT: rax = u64 random
; ---------------------------------------------------------------------------
global ut_entropy_u64
ut_entropy_u64:
    PROLOGUE
    mov rax, SYS_ENTROPY_U64
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; ut_entropy_siphash_key
;   Get 256-bit key for siphash (32 bytes)
;   IN:  rdi = buffer[32]
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global ut_entropy_siphash_key
ut_entropy_siphash_key:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    mov rax, SYS_ENTROPY_KEY
    syscall
    EPILOGUE_RESTORE rbx

section .data

global ut_entropy_version
ut_entropy_version: dq 0x010000

section .note.ut_contract
    db "UT_ENTROPY_CONTRACT", 0
