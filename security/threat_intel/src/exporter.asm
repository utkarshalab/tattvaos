%ifndef GUARD_SECURITY_THREAT_INTEL_EXPORTER_ASM
%define GUARD_SECURITY_THREAT_INTEL_EXPORTER_ASM

; =============================================================================
; File     : security/threat_intel/src/exporter.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Intel exporter (SIEM, peer sharing)
; Status   : PREMIUM ENTERPRISE SKELETON - full API surface, logic bodies
;              marked STUB for implementation.
; =============================================================================

bits 64
DEFAULT REL

%include "include/threat_intel.inc"

section .bss
alignb 16
threat_intel_export_state:        resb threat_intel_state_base_t_size
threat_intel_export_sink_head:    resq 1
threat_intel_export_sink_count:   resq 1

section .data
alignb 16
threat_intel_export_version_str:  db THREAT_INTEL_VERSION_STR, 0

section .text

; =============================================================================
; threat_intel_exporter_init - Initialize intel exporter
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global threat_intel_exporter_init
threat_intel_exporter_init:
    push    rbx
    mov     dword [threat_intel_export_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC
    mov     dword [threat_intel_export_state + threat_intel_state_base_t.version], THREAT_INTEL_VERSION_MAJOR
    mov     byte [threat_intel_export_state + threat_intel_state_base_t.enabled], 1
    mov     qword [threat_intel_export_sink_head], 0
    mov     qword [threat_intel_export_sink_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; threat_intel_exporter_shutdown - Shut down intel exporter
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global threat_intel_exporter_shutdown
threat_intel_exporter_shutdown:
    push    rbx
    mov     eax, [threat_intel_export_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     dword [threat_intel_export_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC_FREED
    mov     byte [threat_intel_export_state + threat_intel_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; threat_intel_exporter_status - Return current intel exporter status
; Input:  none
; Output: rax = status code
; =============================================================================
global threat_intel_exporter_status
threat_intel_exporter_status:
    mov     eax, [threat_intel_export_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     al, [threat_intel_export_state + threat_intel_state_base_t.enabled]
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
; threat_intel_exporter_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global threat_intel_exporter_version
threat_intel_exporter_version:
    mov     rax, threat_intel_export_version_str
    ret

; =============================================================================
; threat_intel_exporter_share_ioc - Share a single IOC with a peer
; Input:  rdi = IOC pointer (ti_ioc_t*), rsi = peer ID
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global threat_intel_exporter_share_ioc
threat_intel_exporter_share_ioc:
    push    rbx
    push    r12

    mov     eax, [threat_intel_export_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save IOC pointer

    ; STUB: serialize IOC to sharing format (STIX/TAXII/JSON)
    ; STEP: sign the serialized IOC with exporter key
    ; STEP: transmit to peer via authenticated channel
    ; STEP: update export statistics
    ; STEP: increment total_exports counter

    xor     eax, eax
    jmp     .done

.err_not_init:
    mov     rax, THREAT_INTEL_ERR_NOT_INIT
    jmp     .done
.err_invalid_arg:
    mov     rax, THREAT_INTEL_ERR_INVALID_ARG
    jmp     .done

.done:
    pop     r12
    pop     rbx
    ret

; =============================================================================
; threat_intel_exporter_push_siem - Push IOCs to a SIEM system
; Input:  rdi = SIEM endpoint pointer, rsi = IOC batch pointer,
;         rdx = IOC batch length
; Output: rax = number of IOCs pushed, negative on failure
; =============================================================================
global threat_intel_exporter_push_siem
threat_intel_exporter_push_siem:
    push    rbx

    mov     eax, [threat_intel_export_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    ; STUB: serialize IOC batch to SIEM format (CEF, LEEF, JSON, etc.)
    ; STEP: authenticate with SIEM
    ; STEP: push IOCs to SIEM endpoint
    ; STEP: return number of IOCs pushed

    xor     eax, eax
    pop     rbx
    ret

.err_not_init:
    mov     rax, THREAT_INTEL_ERR_NOT_INIT
    pop     rbx
    ret

; =============================================================================
; threat_intel_exporter_pull_peer - Pull intel from a peer organization
; Input:  rdi = peer endpoint pointer, rsi = peer credentials,
;         rdx = credential length
; Output: rax = number of IOCs pulled, negative on failure
; =============================================================================
global threat_intel_exporter_pull_peer
threat_intel_exporter_pull_peer:
    push    rbx

    mov     eax, [threat_intel_export_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    ; STUB: authenticate with peer
    ; STEP: request intel updates since last sync
    ; STEP: verify signatures on received IOCs
    ; STEP: store verified IOCs via threat_intel_add_ioc()
    ; STEP: return number of IOCs pulled

    xor     eax, eax
    pop     rbx
    ret

.err_not_init:
    mov     rax, THREAT_INTEL_ERR_NOT_INIT
    pop     rbx
    ret

; STUB: threat_intel_exporter_register_sink - register an export sink
; STUB: threat_intel_exporter_unregister_sink - unregister an export sink
; STUB: threat_intel_exporter_export_batch - export a batch of IOCs to all sinks
; STUB: threat_intel_exporter_sign_ioc - sign an IOC with exporter key
; STUB: threat_intel_exporter_verify_peer - verify peer identity before sharing

%endif