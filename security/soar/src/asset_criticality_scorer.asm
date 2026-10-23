%ifndef GUARD_SECURITY_SOAR_SRC_ASSET_CRITICALITY_SCORER_ASM
%define GUARD_SECURITY_SOAR_SRC_ASSET_CRITICALITY_SCORER_ASM

; =============================================================================
; File     : security/soar/src/asset_criticality_scorer.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: SOAR Asset Criticality Scorer - calculates criticality scores
;              for assets based on business function, data sensitivity,
;              network position, and dependency relationships.
; Status   : PREMIUM ENTERPRISE - full API surface, logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/soar.inc"

section .bss
alignb 16
soar_criticality_state:       resb soar_state_base_t_size
soar_criticality_score_head:  resq 1
soar_criticality_score_count: resq 1

section .data
alignb 16
soar_criticality_version_str: db SOAR_VERSION_STR, 0

section .text

; =============================================================================
; soar_asset_criticality_init - Initialize asset criticality scorer
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global soar_asset_criticality_init
soar_asset_criticality_init:
    push    rbx
    mov     dword [soar_criticality_state + soar_state_base_t.magic], SOAR_STATE_MAGIC
    mov     dword [soar_criticality_state + soar_state_base_t.version], SOAR_VERSION_MAJOR
    mov     byte [soar_criticality_state + soar_state_base_t.enabled], 1
    mov     qword [soar_criticality_score_head], 0
    mov     qword [soar_criticality_score_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; soar_asset_criticality_shutdown - Shut down asset criticality scorer
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global soar_asset_criticality_shutdown
soar_asset_criticality_shutdown:
    push    rbx
    mov     eax, [soar_criticality_state + soar_state_base_t.magic]
    cmp     eax, SOAR_STATE_MAGIC
    jnz     .not_init
    mov     dword [soar_criticality_state + soar_state_base_t.magic], SOAR_STATE_MAGIC_FREED
    mov     byte [soar_criticality_state + soar_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; soar_asset_criticality_status - Return current asset criticality scorer status
; Input:  none
; Output: rax = status code
; =============================================================================
global soar_asset_criticality_status
soar_asset_criticality_status:
    mov     eax, [soar_criticality_state + soar_state_base_t.magic]
    cmp     eax, SOAR_STATE_MAGIC
    jnz     .not_init
    mov     al, [soar_criticality_state + soar_state_base_t.enabled]
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
; soar_asset_criticality_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global soar_asset_criticality_version
soar_asset_criticality_version:
    mov     rax, soar_criticality_version_str
    ret

; =============================================================================
; soar_asset_criticality_score - Calculate asset criticality score
; Input:  rdi = asset context pointer, rsi = business function score,
;         rdx = data sensitivity score, rcx = network exposure score
; Output: rax = criticality score (0-100)
; =============================================================================
global soar_asset_criticality_score
soar_asset_criticality_score:
    push    rbx

    mov     eax, [soar_criticality_state + soar_state_base_t.magic]
    cmp     eax, SOAR_STATE_MAGIC
    jnz     .err_component_down

    ; STUB: calculate criticality = f(business, data, network, dependencies)
    ; STEP: weight business function by organizational importance
    ; STEP: factor in data sensitivity and regulatory requirements
    ; STEP: consider network position and attack surface
    ; STEP: account for dependency relationships with other assets
    ; STEP: return composite criticality score (0-100)

    mov     eax, 50                 ; STUB: default medium criticality
    pop     rbx
    ret

.err_component_down:
    mov     rax, -1
    pop     rbx
    ret

; STUB: soar_asset_criticality_update - update criticality after changes
; STUB: soar_asset_criticality_get_top - get top N most critical assets
; STUB: soar_asset_criticality_list - list all scored assets
; STUB: soar_asset_criticality_get_stats - return scoring statistics

%endif