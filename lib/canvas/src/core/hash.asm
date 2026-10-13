; ============================================================================
; Hash — FNV-1a and String Hashing
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"

section .text

; ---------------------------------------------------------------------------
; fnv1a_hash
;   FNV-1a 64-bit hash
;   IN:  rdi = data ptr, rsi = length
;   OUT: rax = hash
; ---------------------------------------------------------------------------
global fnv1a_hash
fnv1a_hash:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rax, 0xcbf29ce484222325
    test r12, r12
    jz .done
.loop:
    movzx rdi, byte [rbx]
    xor rax, rdi
    mov rdi, 0x100000001b3
    mul rdi
    inc rbx
    dec r12
    jnz .loop
.done:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; fnv1a_hash_str
;   FNV-1a hash of null-terminated string
;   IN:  rdi = string
;   OUT: rax = hash
; ---------------------------------------------------------------------------
global fnv1a_hash_str
fnv1a_hash_str:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, 0xcbf29ce484222325
.loop:
    movzx rdi, byte [rbx]
    test rdi, rdi
    jz .done
    xor rax, rdi
    mov rdi, 0x100000001b3
    mul rdi
    inc rbx
    jmp .loop
.done:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; hash_combine
;   Combine two hashes
;   IN:  rdi = hash1, rsi = hash2
;   OUT: rax = combined
; ---------------------------------------------------------------------------
global hash_combine
hash_combine:
    PROLOGUE
    mov rax, rdi
    xor rax, rsi
    mov rdi, 0x9e3779b97f4a7c15
    mul rdi
    leave
    ret

section .data
global hash_version
hash_version: dq 0x010000
