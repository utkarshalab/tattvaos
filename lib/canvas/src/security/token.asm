; ============================================================================
; Token — Unguessable Capability Tokens (SipHash-based)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

%define TOKEN_TYPE_CAPABILITY   1
%define TOKEN_TYPE_SESSION      2
%define TOKEN_TYPE_CAPTURE      3
%define TOKEN_TYPE_INJECT       4
%define TOKEN_TYPE_POLICY       5
%define TOKEN_DEFAULT_TTL       (3600 * 1000000000)  ; 1 hour in ns

section .text

; ---------------------------------------------------------------------------
; token_init
;   Initialize token subsystem
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global token_init
token_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Keep the signing key in arena-backed server state.
    mov rdi, r12
    mov rsi, 32
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + Server.token_key], rax
    mov rdi, rax
    call tv_entropy_siphash_key
    test rax, rax
    js .error

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

.error:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; token_create
;   Create new capability token
;   IN:  rdi = server*, rsi = client*, rdx = type,
;        rcx = capabilities, r8 = ttl_ns (0 = default)
;   OUT: rax = token*, negative error
; ---------------------------------------------------------------------------
global token_create
token_create:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi      ; client
    mov r13, rdx      ; type
    mov r14, rcx      ; capabilities
    mov r15, r8       ; ttl
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; A token may never amplify the issuing client's authority.
    mov rax, r14
    mov rdx, [r12 + Client.caps]
    not rdx
    and rax, rdx
    jnz .cap_denied

    ; Allocate token
    mov rdi, [rbx + Server.arena]
    mov rsi, Token_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rsp], rax

    mov rdi, rax
    mov dword [rdi + Token.type], r13d
    mov qword [rdi + Token.capabilities], r14
    mov rax, [r12 + Client.id]
    mov qword [rdi + Token.issued_to], rax
    mov qword [rdi + Token.issued_by], 0
    call tv_time_now_ns
    mov rdi, [rsp]
    mov qword [rdi + Token.issued_at], rax
    test r15, r15
    jnz .have_ttl
    mov r15, TOKEN_DEFAULT_TTL
.have_ttl:
    add rax, r15
    jc .bad_ttl
    mov qword [rdi + Token.expires], rax

    ; Authenticate every field except value itself.
    add rdi, Token.type
    mov rsi, Token.issued_at + 8 - Token.type
    mov rdx, [rbx + Server.token_key]
    call siphash24
    mov rdi, [rsp]
    mov [rdi + Token.value], rax

    mov rax, rdi
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.cap_denied:
    mov rax, -(ESEC_CAP)
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.bad_ttl:
    mov rax, -(EINVAL)
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    mov rax, -(ENOMEM)
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; token_verify
;   Verify and consume token
; ---------------------------------------------------------------------------
global token_verify
token_verify:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ASSERT_PTR r12
    mov r13, [r12 + Token.value]
    test r13, r13
    jz .invalid

    mov rdi, r12
    add rdi, Token.type
    mov rsi, Token.issued_at + 8 - Token.type
    mov rdx, [rbx + Server.token_key]
    call siphash24
    cmp rax, r13
    jne .invalid

    call tv_time_now_ns
    cmp rax, [r12 + Token.expires]
    jae .invalid

    ; Capability tokens are single-use.
    mov qword [r12 + Token.value], 0
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.invalid:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; token_revoke
;   Revoke token
; ---------------------------------------------------------------------------
global token_revoke
token_revoke:
    PROLOGUE
    ASSERT_PTR rsi
    mov qword [rsi + Token.value], 0
    xor rax, rax
    leave
    ret

section .data
global token_version
token_version: dq 0x010000
