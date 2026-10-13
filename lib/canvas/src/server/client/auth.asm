; ============================================================================
; Auth — Handshake and Capability Grant
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/caps.inc"
%include "inc/tattva.inc"

section .text

; ---------------------------------------------------------------------------
; auth_handshake
;   Perform client handshake
;   IN:  rdi = client*, rsi = wanted_caps
;   OUT: rax = granted_caps, negative error
; ---------------------------------------------------------------------------
global auth_handshake
auth_handshake:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Get trust profile
    mov r13, [rbx + Client.trust_profile]

    ; Get profile caps
    call auth_get_profile_caps
    mov r13, rax

    ; Grant = wanted & profile_caps
    mov rax, r12
    and rax, r13

    ; Always grant core
    or rax, CAP_DISPLAY | CAP_BUFFER | CAP_SURFACE | CAP_PRESENT

    ; Store granted caps
    mov [rbx + Client.caps], rax

    ; Send capabilities event to client
    ; TODO: Encode cw_display.capabilities event

    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; auth_get_profile_caps
;   Get capability mask for trust profile
;   IN:  rdi = trust_profile
;   OUT: rax = capability mask
; ---------------------------------------------------------------------------
global auth_get_profile_caps
auth_get_profile_caps:
    PROLOGUE
    cmp rdi, TRUST_TRUSTED
    je .trusted
    cmp rdi, TRUST_STANDARD
    je .standard
    cmp rdi, TRUST_SANDBOXED
    je .sandboxed
    cmp rdi, TRUST_REMOTE
    je .remote
    cmp rdi, TRUST_KIOSK
    je .kiosk
    xor rax, rax
    leave
    ret

.trusted:
    mov rax, PROFILE_TRUSTED_CAPS
    leave
    ret
.standard:
    mov rax, PROFILE_STANDARD_CAPS
    leave
    ret
.sandboxed:
    mov rax, PROFILE_SANDBOXED_CAPS
    leave
    ret
.remote:
    mov rax, PROFILE_REMOTE_CAPS
    leave
    ret
.kiosk:
    mov rax, PROFILE_KIOSK_CAPS
    leave
    ret

; ---------------------------------------------------------------------------
; auth_check_cap
;   Check if client has capability
;   IN:  rdi = client*, rsi = cap
;   OUT: rax = 1 if granted, 0 if not
; ---------------------------------------------------------------------------
global auth_check_cap
auth_check_cap:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Client.caps]
    test rax, rsi
    jz .no
    mov rax, 1
    leave
    ret
.no:
    xor rax, rax
    leave
    ret

section .data
global auth_version
auth_version: dq 0x010000
