%ifndef GUARD_SECURITY_THREAT_INTEL_STORE_ASM
%define GUARD_SECURITY_THREAT_INTEL_STORE_ASM

; =============================================================================
; File     : security/threat_intel/src/store.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IOC database (IPs, domains, hashes, YARA, TTPs)
; Status   : PREMIUM ENTERPRISE SKELETON - full API surface, logic bodies
;              marked STUB for implementation.
; =============================================================================

bits 64
DEFAULT REL

%include "include/threat_intel.inc"

section .bss
alignb 16
threat_intel_store_state:      resb threat_intel_state_base_t_size
threat_intel_ioc_head:         resq 1
threat_intel_ioc_count:        resq 1

section .data
alignb 16
threat_intel_store_version_str: db THREAT_INTEL_VERSION_STR, 0

section .text

; =============================================================================
; threat_intel_store_init - Initialize IOC database
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global threat_intel_store_init
threat_intel_store_init:
    push    rbx
    mov     dword [threat_intel_store_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC
    mov     dword [threat_intel_store_state + threat_intel_state_base_t.version], THREAT_INTEL_VERSION_MAJOR
    mov     byte [threat_intel_store_state + threat_intel_state_base_t.enabled], 1
    mov     qword [threat_intel_ioc_head], 0
    mov     qword [threat_intel_ioc_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; threat_intel_store_shutdown - Shut down IOC database
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global threat_intel_store_shutdown
threat_intel_store_shutdown:
    push    rbx
    mov     eax, [threat_intel_store_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     dword [threat_intel_store_state + threat_intel_state_base_t.magic], THREAT_INTEL_STATE_MAGIC_FREED
    mov     byte [threat_intel_store_state + threat_intel_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; threat_intel_store_status - Return current IOC database status
; Input:  none
; Output: rax = status code
; =============================================================================
global threat_intel_store_status
threat_intel_store_status:
    mov     eax, [threat_intel_store_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .not_init
    mov     al, [threat_intel_store_state + threat_intel_state_base_t.enabled]
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
; threat_intel_store_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global threat_intel_store_version
threat_intel_store_version:
    mov     rax, threat_intel_store_version_str
    ret

; =============================================================================
; threat_intel_add_ioc - Add an IOC to the store
; Input:  rdi = IOC pointer (ti_ioc_t*)
; Output: rax = assigned IOC ID on success, negative error code on failure
; =============================================================================
global threat_intel_add_ioc
threat_intel_add_ioc:
    push    rbx
    push    r12

    mov     eax, [threat_intel_store_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save IOC pointer

    ; STUB: validate IOC type field
    ; STUB: check for duplicate indicator
    ; STUB: assign IOC ID (increment counter)
    ; STUB: insert into IOC linked list
    ; STUB: set first_seen and last_seen timestamps
    ; STUB: increment total_iocs counter

    mov     rax, 1               ; STUB: return IOC ID 1
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
; threat_intel_lookup_ioc - Look up an IOC in the store
; Input:  rdi = indicator pointer, rsi = indicator length,
;         rdx = IOC type (TI_IOC_TYPE_*)
; Output: rax = verdict (TI_VERDICT_*),
;         rbx = IOC ID (0 if not found),
;         rcx = confidence score
; =============================================================================
global threat_intel_lookup_ioc
threat_intel_lookup_ioc:
    push    rbx
    push    r12

    mov     eax, [threat_intel_store_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save indicator pointer

    ; STUB: compute hash of indicator
    ; STUB: lookup in hash table
    ; STEP: on match, verify indicator equality (constant-time compare)
    ; STEP: on match, return verdict, IOC ID, confidence
    ; STEP: on no match, return TI_VERDICT_UNKNOWN

    mov     eax, TI_VERDICT_UNKNOWN
    xor     rbx, rbx
    xor     rcx, rcx
    jmp     .done

.err_not_init:
    mov     rax, THREAT_INTEL_ERR_NOT_INIT
    xor     rbx, rbx
    xor     rcx, rcx
    jmp     .done
.err_invalid_arg:
    mov     rax, THREAT_INTEL_ERR_INVALID_ARG
    xor     rbx, rbx
    xor     rcx, rcx
    jmp     .done

.done:
    pop     r12
    pop     rbx
    ret

; =============================================================================
; threat_intel_remove_ioc - Mark an IOC as stale (soft delete)
; Input:  rdi = IOC ID
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global threat_intel_remove_ioc
threat_intel_remove_ioc:
    push    rbx

    mov     eax, [threat_intel_store_state + threat_intel_state_base_t.magic]
    cmp     eax, THREAT_INTEL_STATE_MAGIC
    jnz     .err_not_init

    ; STUB: locate IOC by ID
    ; STEP: mark expires field as current time (soft delete)
    ; STEP: decrement hit_count tracking
    ; STEP: return success

    xor     eax, eax
    pop     rbx
    ret

.err_not_init:
    mov     rax, THREAT_INTEL_ERR_NOT_INIT
    pop     rbx
    ret

; =============================================================================
; threat_intel_get_ioc_count - Return current IOC count
; Input:  none
; Output: rax = IOC count
; =============================================================================
global threat_intel_get_ioc_count
threat_intel_get_ioc_count:
    mov     rax, [threat_intel_ioc_count]
    ret

; STUB: threat_intel_iterate - iterate over all IOCs
; STUB: threat_intel_get_by_type - retrieve IOCs by type
; STUB: threat_intel_get_by_severity - retrieve IOCs by severity
; STUB: threat_intel_purge_stale - remove expired IOCs
; STUB: threat_intel_import - bulk import IOCs from file
; STUB: threat_intel_export - bulk export IOCs to file
; STUB: threat_intel_verify_integrity - verify store integrity

%endif