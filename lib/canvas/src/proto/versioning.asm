; ============================================================================
; Versioning — Protocol Version Negotiation
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; ---------------------------------------------------------------------------
; versioning_negotiate
;   Negotiate protocol version
;   IN:  rdi = client_version (major.minor.patch), rsi = server_version
;   OUT: rax = negotiated_version, 0 if incompatible
; ---------------------------------------------------------------------------
global versioning_negotiate
versioning_negotiate:
    PROLOGUE
    ; Major version must match
    mov rax, rdi
    shr rax, 32
    mov rcx, rsi
    shr rcx, 32
    cmp rax, rcx
    jne .incompatible

    ; Minor: use minimum
    mov rax, rdi
    shr rax, 16
    and rax, 0xFFFF
    mov rcx, rsi
    shr rcx, 16
    and rcx, 0xFFFF
    cmp rax, rcx
    cmovg rax, rcx
    shl rax, 16

    ; Patch: use minimum
    mov rcx, rdi
    and rcx, 0xFFFF
    mov rdx, rsi
    and rdx, 0xFFFF
    cmp rcx, rdx
    cmovg rcx, rdx
    or rax, rcx

    leave
    ret

.incompatible:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; versioning_check_interface
;   Check if interface version is supported
;   IN:  rdi = interface_version, rsi = client_requested_version
;   OUT: rax = 1 if supported, 0 if not
; ---------------------------------------------------------------------------
global versioning_check_interface
versioning_check_interface:
    PROLOGUE
    ; Interface version: major.minor
    ; Client requests <= server provides
    cmp rsi, rdi
    jbe .supported
    xor rax, rax
    leave
    ret
.supported:
    mov rax, 1
    leave
    ret

; ---------------------------------------------------------------------------
; versioning_encode
;   Encode version as major<<32 | minor<<16 | patch
; ---------------------------------------------------------------------------
global versioning_encode
versioning_encode:
    PROLOGUE
    ; rdi = major, rsi = minor, rdx = patch
    mov rax, rdi
    shl rax, 32
    mov rcx, rsi
    shl rcx, 16
    or rax, rcx
    or rax, rdx
    leave
    ret

; ---------------------------------------------------------------------------
; versioning_decode
;   Decode version
; ---------------------------------------------------------------------------
global versioning_decode
versioning_decode:
    PROLOGUE
    ; rdi = version, rsi = major*, rdx = minor*, rcx = patch*
    mov rax, rdi
    shr rax, 32
    mov [rsi], eax
    mov rax, rdi
    shr rax, 16
    and rax, 0xFFFF
    mov [rdx], eax
    mov rax, rdi
    and rax, 0xFFFF
    mov [rcx], eax
    xor rax, rax
    leave
    ret

section .data

global versioning_version
versioning_version: dq 0x010000
