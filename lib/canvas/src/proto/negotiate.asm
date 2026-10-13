; ============================================================================
; Negotiate — Capability Negotiation at Connect
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/caps.inc"

section .text

; ---------------------------------------------------------------------------
; negotiate_capabilities
;   Negotiate capabilities between client and server
;   IN:  rdi = client_wanted, rsi = server_available, rdx = trust_profile
;   OUT: rax = granted_capabilities
; ---------------------------------------------------------------------------
global negotiate_capabilities
negotiate_capabilities:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi        ; client_wanted
    mov r12, rsi        ; server_available
    ASSERT_PTR rdx      ; trust_profile (for future use)

    ; Grant = client_wanted & server_available
    mov rax, rbx
    and rax, r12

    ; Always grant core capabilities
    or rax, CAP_DISPLAY | CAP_BUFFER | CAP_SURFACE | CAP_PRESENT

    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; negotiate_check_cap
;   Check if capability is granted
;   IN:  rdi = granted_caps, rsi = cap_to_check
;   OUT: rax = 1 if granted, 0 if not
; ---------------------------------------------------------------------------
global negotiate_check_cap
negotiate_check_cap:
    PROLOGUE
    test rdi, rsi
    jz .not_granted
    mov rax, 1
    leave
    ret
.not_granted:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; negotiate_filter_interface
;   Filter interface visibility based on capabilities
;   IN:  rdi = granted_caps, rsi = interface_id
;   OUT: rax = 1 if visible, 0 if hidden
; ---------------------------------------------------------------------------
global negotiate_filter_interface
negotiate_filter_interface:
    PROLOGUE
    ; Map interface_id to required capability
    ; For now, all interfaces visible if core caps granted
    test rdi, CAP_DISPLAY
    jz .hidden
    mov rax, 1
    leave
    ret
.hidden:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; negotiate_get_interface_cap
;   Get capability bit required for interface
;   IN:  rdi = interface_id
;   OUT: rax = capability bit
; ---------------------------------------------------------------------------
global negotiate_get_interface_cap
negotiate_get_interface_cap:
    PROLOGUE
    ; Interface ID to capability mapping
    ; 1 = cw_display -> CAP_DISPLAY
    ; 2 = cw_buffer -> CAP_BUFFER
    ; 3 = cw_surface -> CAP_SURFACE
    ; 4 = cw_present -> CAP_PRESENT
    ; 5 = cw_output -> CAP_OUTPUT
    ; 6 = cw_seat -> CAP_SEAT
    ; 7 = cw_pointer -> CAP_POINTER
    ; 8 = cw_keyboard -> CAP_KEYBOARD
    ; 9 = cw_touch -> CAP_TOUCH
    ; 10 = cw_tablet -> CAP_TABLET
    ; 11 = cw_shell -> CAP_SHELL
    ; 12 = cw_layer -> CAP_LAYER
    ; 13 = cw_decoration -> CAP_DECORATION
    ; 14 = cw_data -> CAP_DATA
    ; 15 = cw_text -> CAP_TEXT
    ; 16 = cw_a11y -> CAP_A11Y
    ; 17 = cw_capture -> CAP_CAPTURE
    ; 18 = cw_inject -> CAP_INJECT
    ; 19 = cw_policy -> CAP_POLICY
    ; 20 = cw_debug -> CAP_DEBUG
    ; 21 = cw_session -> CAP_SESSION
    ; 22 = cw_remote -> CAP_REMOTE

    cmp rdi, 1
    je .cap_display
    cmp rdi, 2
    je .cap_buffer
    cmp rdi, 3
    je .cap_surface
    cmp rdi, 4
    je .cap_present
    cmp rdi, 5
    je .cap_output
    cmp rdi, 6
    je .cap_seat
    cmp rdi, 7
    je .cap_pointer
    cmp rdi, 8
    je .cap_keyboard
    cmp rdi, 9
    je .cap_touch
    cmp rdi, 10
    je .cap_tablet
    cmp rdi, 11
    je .cap_shell
    cmp rdi, 12
    je .cap_layer
    cmp rdi, 13
    je .cap_decoration
    cmp rdi, 14
    je .cap_data
    cmp rdi, 15
    je .cap_text
    cmp rdi, 16
    je .cap_a11y
    cmp rdi, 17
    je .cap_capture
    cmp rdi, 18
    je .cap_inject
    cmp rdi, 19
    je .cap_policy
    cmp rdi, 20
    je .cap_debug
    cmp rdi, 21
    je .cap_session
    cmp rdi, 22
    je .cap_remote

    xor rax, rax
    leave
    ret

.cap_display:   mov rax, CAP_DISPLAY; ret
.cap_buffer:    mov rax, CAP_BUFFER; ret
.cap_surface:   mov rax, CAP_SURFACE; ret
.cap_present:   mov rax, CAP_PRESENT; ret
.cap_output:    mov rax, CAP_OUTPUT; ret
.cap_seat:      mov rax, CAP_SEAT; ret
.cap_pointer:   mov rax, CAP_POINTER; ret
.cap_keyboard:  mov rax, CAP_KEYBOARD; ret
.cap_touch:     mov rax, CAP_TOUCH; ret
.cap_tablet:    mov rax, CAP_TABLET; ret
.cap_shell:     mov rax, CAP_SHELL; ret
.cap_layer:     mov rax, CAP_LAYER; ret
.cap_decoration: mov rax, CAP_DECORATION; ret
.cap_data:      mov rax, CAP_DATA; ret
.cap_text:      mov rax, CAP_TEXT; ret
.cap_a11y:      mov rax, CAP_A11Y; ret
.cap_capture:   mov rax, CAP_CAPTURE; ret
.cap_inject:    mov rax, CAP_INJECT; ret
.cap_policy:    mov rax, CAP_POLICY; ret
.cap_debug:     mov rax, CAP_DEBUG; ret
.cap_session:   mov rax, CAP_SESSION; ret
.cap_remote:    mov rax, CAP_REMOTE; ret

section .data

global negotiate_version
negotiate_version: dq 0x010000
