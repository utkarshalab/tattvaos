; ============================================================================
; Token — Unguessable Capability Tokens (SipHash-based)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/siphash.asm"

section .text

struc Token {
    .value:       resq 1
    .type:        resd 1
    .capabilities: resq 1
    .expires:     resq 1
    .issued_to:   resq 1
    .issued_by:   resq 1
    .issued_at:   resq 1
}
%define Token_size    56

%define TOKEN_TYPE_CAPABILITY   1
%define TOKEN_TYPE_SESSION      2
%define TOKEN_TYPE_CAPTURE      3
%define TOKEN_TYPE_INJECT       4
%define TOKEN_TYPE_POLICY       5

%define TOKEN_DEFAULT_TTL       (3600 * 1000000000)  ; 1 hour in ns

; ---------------------------------------------------------------------------
; token_init
; ---------------------------------------------------------------------------
global token_init
token_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Generate siphash key for token signing
    mov rdi, r12
    sub rsp, 32
    mov rdi, rsp
    call tv_entropy_siphash_key
    add rsp, 32

    ; Store key
    mov rdi, [rbx + Server.arena]
    mov rsi, 32
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rdi + Server.token_key], rax
    mov rdi, rax
    mov rsi, rsp
    mov rdx, 32
    call memcopy
    add rsp, 32

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; token_create
;   Create new capability token
;   IN:  rdi = server*, rsi = client*, rdx = type, rcx = capabilities, r8 = ttl_ns (0 = default)
;   OUT: rax = token*, negative error
; ---------------------------------------------------------------------------
global token_create
token_create:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Validate capabilities against client's granted caps
    mov rax, [r12 + Client.caps]
    test rax, r14
    jz .cap_denied

    ; Allocate token
    mov rdi, [rbx + Server.arena]
    mov rsi, Token_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Generate token value (siphash of random + client_id + timestamp)
    call tv_time_now_ns
    mov r13, rax
    call tv_entropy_u64
    mov r14, rax

    ; Sign with siphash
    mov rdi, [rdi + Server.token_key]
    mov rsi, r12
    mov rdx, [r12 + Client.id]
    mov rcx, r13
    mov r8, r14
    call siphash24
    mov qword [rbx + Token.value], rax

    mov dword [rbx + Token.type], r13d
    mov qword [rbx + Token.capabilities], r14
    call tv_time_now_ns
    add rax, r8
    cmp r8, 0
    jne .has_ttl
    add rax, TOKEN_DEFAULT_TTL
.has_ttl:
    mov qword [rbx + Token.expires], rax
    mov qword [rbx + Token.issued_to], [r12 + Client.id]
    mov qword [rbx + Token.issued_by], 0  ; server
    mov qword [rbx + Token.issued_at], r13

    mov rax, rbx
    ret

.cap_denied:
    RETURN_ERROR ESEC_CAP
.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; token_verify
;   Verify token validity
;   IN:  rdi = server*, rsi = token_value
;   OUT: rax = token* if valid, 0 if invalid/expired
; ---------------------------------------------------------------------------
global token_verify
token_verify:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Lookup token by value
    ; TODO: Implement token lookup (hash table)
    ; For now, just verify signature

    ; Verify siphash
    mov rdi, [rdi + Server.token_key]
    mov rsi, r12  ; client
    ; TODO: Reconstruct signed data
    call siphash24_verify
    test rax, rax
    jz .invalid

    ; Check expiration
    call tv_time_now_ns
    cmp rax, [r12 + Token.expires]
    ja .expired

    mov rax, r12
    ret

.invalid:
    xor rax, rax
    ret

.expired:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; token_revoke
; ---------------------------------------------------------------------------
global token_revoke
token_revoke:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Mark as revoked
    mov qword [r12 + Token.expires], 0

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; token_extend
; ---------------------------------------------------------------------------
global token_extend
token_extend:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    call tv_time_now_ns
    add rax, r13
    mov [r12 + Token.expires], rax
    xor rax, rax
    ret

section .data
global token_version
token_version: dq 0x010000