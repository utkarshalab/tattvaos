; ============================================================================
; Tattva Entropy Service Binding — tv_entropy.asm
; Hardware random numbers for tokens, keys, capability generation
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

; ---------------------------------------------------------------------------
; tv_entropy_get
;   Fill buffer with cryptographic random bytes
;   IN:  rdi = buffer pointer
;        rsi = length
;   OUT: rax = 0 OK, negative error (EAGAIN if pool low)
; ---------------------------------------------------------------------------
global tv_entropy_get
tv_entropy_get:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    mov rax, SYS_ENTROPY_GET
    syscall
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; tv_entropy_u64
;   Get 64 random bits (fast path for tokens)
;   OUT: rax = u64 random
; ---------------------------------------------------------------------------
global tv_entropy_u64
tv_entropy_u64:
    PROLOGUE
    mov rax, SYS_ENTROPY_U64
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; tv_entropy_siphash_key
;   Get 256-bit key for siphash (32 bytes)
;   IN:  rdi = buffer[32]
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global tv_entropy_siphash_key
tv_entropy_siphash_key:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    mov rax, SYS_ENTROPY_KEY
    syscall
    EPILOGUE_RESTORE rbx

section .data

global tv_entropy_version
tv_entropy_version: dq 0x010000

section .note.tattva_contract
    db "TATTVA_ENTROPY_CONTRACT", 0