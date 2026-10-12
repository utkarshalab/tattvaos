; ============================================================================
; Verifier Hooks — RSO (Register Ownership) Verification Integration
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

; ---------------------------------------------------------------------------
; verifier_init
; ---------------------------------------------------------------------------
global verifier_init
verifier_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.verifier], 0
    mov qword [rbx + Server.arena], r12

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; verifier_verify_client
;   Verify client binary with RSO (Register Ownership) rules
;   IN:  rdi = server*, rsi = client_image_ptr, rdx = image_size
;   OUT: rax = 1 if verified, 0 if failed, negative error
; ---------------------------------------------------------------------------
global verifier_verify_client
verifier_verify_client:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; TODO: Implement RSO verification
    ; RSO (Register Ownership) rules:
    ; 1. All register writes must be to registers the code "owns"
    ; 2. No arbitrary memory access outside allocated regions
    ; 3. Control flow integrity (no arbitrary jumps)
    ; 4. No privileged instructions

    ; For now, check for basic sanity
    test r12, r12
    jz .fail
    test r13, r13
    jz .fail

    ; Check for basic ELF structure
    mov eax, [r12]
    cmp eax, 0x464C457F  ; ELF magic
    jne .fail

    ; TODO: Full RSO verification
    ; - Parse ELF
    ; - Build CFG
    ; - Verify register ownership
    ; - Verify memory safety
    ; - Verify control flow integrity

    ; For now, accept
    mov rax, 1
    ret

.fail:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; verifier_check_instruction
;   Check single instruction for RSO compliance
; ---------------------------------------------------------------------------
global verifier_check_instruction
verifier_check_instruction:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; TODO: Implement per-instruction verification
    ; Check:
    ; - Register writes only to owned registers
    ; - Memory accesses within bounds
    ; - Control flow targets are valid
    ; - No privileged instructions

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; verifier_register_client
;   Register verified client
; ---------------------------------------------------------------------------
global verifier_register_client
verifier_register_client:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Mark client as verified
    mov byte [r12 + Client.verified], 1

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; verifier_is_verified
; ---------------------------------------------------------------------------
global verifier_is_verified
verifier_is_verified:
    PROLOGUE
    ASSERT_PTR rdi
    movzx rax, byte [rdi + Client.verified]
    ret

section .data
global verifier_version
verifier_version: dq 0x010000