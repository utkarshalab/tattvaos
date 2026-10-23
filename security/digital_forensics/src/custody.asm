%ifndef GUARD_SECURITY_DIGITAL_FORENSICS_CUSTODY_ASM
%define GUARD_SECURITY_DIGITAL_FORENSICS_CUSTODY_ASM

; =============================================================================
; File     : security/digital_forensics/src/custody.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: chain-of-custody evidence journal (signed, tamper-evident)
; Status   : PREMIUM ENTERPRISE SKELETON - full API surface, logic bodies
;              marked STUB for implementation.
; =============================================================================

bits 64
DEFAULT REL

%include "include/dfir.inc"

section .bss
alignb 16
dfir_custody_state:     resb dfir_state_base_t_size
dfir_custody_entry_head: resq 1
dfir_custody_entry_count: resq 1

section .data
alignb 16
dfir_custody_version_str: db DFIR_VERSION_STR, 0

section .text

; =============================================================================
; dfir_custody_init - Initialize chain-of-custody evidence journal
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global dfir_custody_init
dfir_custody_init:
    push    rbx
    mov     dword [dfir_custody_state + dfir_state_base_t.magic], DFIR_STATE_MAGIC
    mov     dword [dfir_custody_state + dfir_state_base_t.version], DFIR_VERSION_MAJOR
    mov     byte [dfir_custody_state + dfir_state_base_t.enabled], 1
    mov     qword [dfir_custody_entry_head], 0
    mov     qword [dfir_custody_entry_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; dfir_custody_shutdown - Shut down chain-of-custody evidence journal
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global dfir_custody_shutdown
dfir_custody_shutdown:
    push    rbx
    mov     eax, [dfir_custody_state + dfir_state_base_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .not_init
    mov     dword [dfir_custody_state + dfir_state_base_t.magic], DFIR_STATE_MAGIC_FREED
    mov     byte [dfir_custody_state + dfir_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; dfir_custody_status - Return current chain-of-custody status
; Input:  none
; Output: rax = status code
; =============================================================================
global dfir_custody_status
dfir_custody_status:
    mov     eax, [dfir_custody_state + dfir_state_base_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .not_init
    mov     al, [dfir_custody_state + dfir_state_base_t.enabled]
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
; dfir_custody_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global dfir_custody_version
dfir_custody_version:
    mov     rax, dfir_custody_version_str
    ret

; =============================================================================
; dfir_custody_log_entry - Log a custody chain entry
; Input:  rdi = evidence ID, rsi = actor pointer,
;         rdx = action (DFIR_CUSTODY_*), rcx = location pointer,
;         r8  = purpose pointer
; Output: rax = entry ID on success, negative error code on failure
; =============================================================================
global dfir_custody_log_entry
dfir_custody_log_entry:
    push    rbx
    push    r12
    push    r13

    mov     eax, [dfir_custody_state + dfir_state_base_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .err_not_init

    test    rsi, rsi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save evidence ID
    mov     r13, rsi              ; save actor pointer

    ; STEP 1: Validate evidence ID exists in store
    ; STEP 2: Allocate custody entry record
    ; STEP 3: Populate entry fields (action, actor, location, purpose)
    ; STEP 4: Set timestamp_ns to current time
    ; STEP 5: Cryptographically sign entry (hash of entry + previous entry hash)
    ; STEP 6: Insert entry into custody linked list
    ; STEP 7: Increment entry count

    mov     rax, 1               ; STUB: return entry ID 1
    jmp     .done

.err_not_init:
    mov     rax, DFIR_ERR_NOT_INIT
    jmp     .done
.err_invalid_arg:
    mov     rax, DFIR_ERR_INVALID_ARG
    jmp     .done

.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; dfir_custody_verify_chain - Verify integrity of custody chain
; Input:  rdi = evidence ID
; Output: rax = 0 if chain valid, negative error code on failure
; =============================================================================
global dfir_custody_verify_chain
dfir_custody_verify_chain:
    push    rbx

    mov     eax, [dfir_custody_state + dfir_state_base_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .err_not_init

    ; STEP 1: Walk custody linked list for evidence ID
    ; STEP 2: Verify each entry's signature against previous entry hash
    ; STEP 3: Verify no gaps in custody timeline
    ; STEP 4: Verify actor authorization for each action
    ; STEP 5: Return 0 if valid, error code if broken

    xor     eax, eax               ; STUB: chain valid
    pop     rbx
    ret

.err_not_init:
    mov     rax, DFIR_ERR_NOT_INIT
    pop     rbx
    ret

; STUB: dfir_custody_get_entry - retrieve custody entry by ID
; STUB: dfir_custody_list_entries - list all entries for evidence
; STUB: dfir_custody_export_chain - export custody chain for legal proceedings
; STUB: dfir_custody_verify_signature - verify entry signature
; STUB: dfir_custody_get_stats - return custody statistics

%endif