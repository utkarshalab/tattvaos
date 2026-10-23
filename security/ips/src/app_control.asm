%ifndef GUARD_SECURITY_IPS_SRC_APP_CONTROL_ASM
%define GUARD_SECURITY_IPS_SRC_APP_CONTROL_ASM

; =============================================================================
; File     : security/ips/src/app_control.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IPS Application Control - application-layer allow/deny.
;              Detects applications by signature (HTTP User-Agent, TLS SNI,
;              protocol fingerprints) and enforces application allow/deny lists.
; Status   : PREMIUM ENTERPRISE - application signatures, category filtering,
;             allow/deny enforcement defined.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ips.inc"

section .bss
alignb 16
ips_app_control_state:     resb ips_state_base_t_size
ips_app_control_app_head:  resq 1      ; application signature linked list
ips_app_control_app_count: resq 1
ips_app_control_blocked_apps_head: resq 1   ; blocked app ID list
ips_app_control_blocked_count: resq 1

section .data
alignb 16
ips_app_control_version_str: db IPS_VERSION_STR, 0

section .text

; =============================================================================
; ips_app_control_init - Initialize application control component
; Input:  none
; Output: rax = 0 on success, negative on failure
; =============================================================================
global ips_app_control_init
ips_app_control_init:
    push    rbx

    mov     dword [ips_app_control_state + ips_state_base_t.magic], IPS_STATE_MAGIC
    mov     dword [ips_app_control_state + ips_state_base_t.version], IPS_VERSION_MAJOR
    mov     byte [ips_app_control_state + ips_state_base_t.enabled], 1

    mov     qword [ips_app_control_app_head], 0
    mov     qword [ips_app_control_app_count], 0
    mov     qword [ips_app_control_blocked_apps_head], 0
    mov     qword [ips_app_control_blocked_count], 0

    ; STUB: allocate application signature memory pool
    ; STUB: load application signatures (User-Agent, SNI, protocol fingerprints)
    ; STUB: load allowed/blocked application lists from config

    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ips_app_control_shutdown - Shut down application control component
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ips_app_control_shutdown
ips_app_control_shutdown:
    push    rbx

    mov     eax, [ips_app_control_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init

    ; STUB: free all application signatures
    ; STUB: free blocked apps list

    mov     dword [ips_app_control_state + ips_state_base_t.magic], IPS_STATE_MAGIC_FREED
    mov     byte [ips_app_control_state + ips_state_base_t.enabled], 0

    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ips_app_control_status - Return current status
; Input:  none
; Output: rax = status code
; =============================================================================
global ips_app_control_status
ips_app_control_status:
    mov     eax, [ips_app_control_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ips_app_control_state + ips_state_base_t.enabled]
    test    al, al
    jz      .disabled
    xor     eax, eax
    ret
.disabled:
    mov     eax, -1
    ret
.not_init:
    mov     eax, -2
    ret

; =============================================================================
; ips_app_control_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ips_app_control_version
ips_app_control_version:
    mov     rax, ips_app_control_version_str
    ret

; =============================================================================
; ips_app_control_detect - Detect application from traffic context
; Input:  rdi = enforce_ctx pointer (ips_enforce_ctx_t*)
; Output: rax = app_id (positive) or 0 if unknown,
;         rbx = app_category code
; =============================================================================
global ips_app_control_detect
ips_app_control_detect:
    push    rbx

    mov     eax, [ips_app_control_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid

    ; STUB: inspect traffic for application signatures
    ;   - HTTP User-Agent header
    ;   - TLS SNI extension
    ;   - Protocol fingerprints
    ;   - Application-specific patterns
    ; STUB: match against application signature database
    ; For skeleton: unknown application
    xor     rax, rax   ; app_id = 0 (unknown)
    xor     rbx, rbx   ; category = 0 (unknown)
    jmp .done

.err_component_down:
    mov     rax, -2
    xor     rbx, rbx
    jmp .done
.err_invalid:
    mov     rax, -3
    xor     rbx, rbx
    jmp .done

.done:
    pop     rbx
    ret

; =============================================================================
; ips_app_control_is_allowed - Check if application is allowed
; Input:  rdi = app_id
; Output: rax = 1 if allowed, 0 if blocked, negative on error
; =============================================================================
global ips_app_control_is_allowed
ips_app_control_is_allowed:
    push    rbx

    mov     eax, [ips_app_control_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid

    ; STUB: check if app_id is in blocked applications list
    ; STUB: check app category against blocked categories
    ; For skeleton: all applications allowed
    mov     rax, 1   ; allowed
    xor     rbx, rbx
    jmp .done

.err_component_down:
    mov     rax, -2
    xor     rbx, rbx
    jmp .done
.err_invalid:
    mov     rax, -3
    xor     rbx, rbx
    jmp .done

.done:
    pop     rbx
    ret

%endif
