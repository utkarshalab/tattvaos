; ============================================================================
; Capabilities — Capability Bit Definitions and Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define CAP_DISPLAY     (1 << 0)
%define CAP_BUFFER      (1 << 1)
%define CAP_SURFACE     (1 << 2)
%define CAP_PRESENT     (1 << 3)
%define CAP_OUTPUT      (1 << 4)
%define CAP_SEAT        (1 << 5)
%define CAP_POINTER     (1 << 6)
%define CAP_KEYBOARD    (1 << 7)
%define CAP_TOUCH       (1 << 8)
%define CAP_TABLET      (1 << 9
%define CAP_SHELL       (1 << 10)
%define CAP_LAYER       (1 << 11)
%define CAP_DECORATION  (1 << 12)
%define CAP_DATA        (1 << 13)
%define CAP_TEXT        (1 << 14)
%define CAP_A11Y        (1 << 15)
%define CAP_CAPTURE     (1 << 32)
%define CAP_INJECT      (1 << 33)
%define CAP_POLICY      (1 << 34)
%define CAP_DEBUG       (1 << 35)
%define CAP_SESSION     (1 << 36)
%define CAP_REMOTE      (1 << 37)

section .text

; Capability bits (from inc/caps.inc)

%define CORE_CAPS       (CAP_DISPLAY | CAP_BUFFER | CAP_SURFACE | CAP_PRESENT)
%define STANDARD_CAPS   (CORE_CAPS | CAP_OUTPUT | CAP_SEAT | CAP_POINTER | CAP_KEYBOARD | CAP_TOUCH | CAP_TABLET | CAP_SHELL | CAP_LAYER | CAP_DECORATION | CAP_DATA | CAP_TEXT | CAP_A11Y)

; ---------------------------------------------------------------------------
; caps_init
; ---------------------------------------------------------------------------
global caps_init
caps_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.cap_table], 0
    mov qword [rbx + Server.arena], r12

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; caps_check
;   Check if client has capability
;   IN:  rdi = server*, rsi = client*, rdx = cap
;   OUT: rax = 1 if granted, 0 if not
; ---------------------------------------------------------------------------
global caps_check
caps_check:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi

    mov rax, [rsi + Client.caps]
    test rax, rdx
    jz .not_granted
    mov rax, 1
    leave
    ret

.not_granted:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; caps_grant
;   Grant capability to client
; ---------------------------------------------------------------------------
global caps_grant
caps_grant:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ASSERT_PTR rsi

    mov rax, [rsi + Client.caps]
    or rax, rdx
    mov [rsi + Client.caps], rax

    ; Log grant
    call caps_log_grant

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; caps_revoke
;   Revoke capability from client
; ---------------------------------------------------------------------------
global caps_revoke
caps_revoke:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ASSERT_PTR rsi

    mov rax, [rsi + Client.caps]
    and rax, ~rdx
    mov [rsi + Client.caps], rax

    ; Log revocation
    call caps_log_revoke

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; caps_has
;   Check if capability is in set
; ---------------------------------------------------------------------------
global caps_has
caps_has:
    PROLOGUE
    test rdi, rsi
    jz .no
    mov rax, 1
    leave
    ret
.no:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; caps_get_granted
;   Get all granted capabilities for client
; ---------------------------------------------------------------------------
global caps_get_granted
caps_get_granted:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Client.caps]
    leave
    ret

; ---------------------------------------------------------------------------
; caps_intersect
;   Intersect two capability sets
; ---------------------------------------------------------------------------
global caps_intersect
caps_intersect:
    PROLOGUE
    mov rax, rdi
    and rax, rsi
    leave
    ret

; ---------------------------------------------------------------------------
; caps_union
; ---------------------------------------------------------------------------
global caps_union
caps_union:
    PROLOGUE
    mov rax, rdi
    or rax, rsi
    leave
    ret

; ---------------------------------------------------------------------------
; caps_log_grant
; ---------------------------------------------------------------------------
caps_log_grant:
    PROLOGUE
    ; TODO: Log to audit
    leave
    ret

; ---------------------------------------------------------------------------
; caps_log_revoke
; ---------------------------------------------------------------------------
caps_log_revoke:
    PROLOGUE
    ; TODO: Log to audit
    leave
    ret

section .data
global caps_version
caps_version: dq 0x010000
