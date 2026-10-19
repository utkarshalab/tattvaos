%ifndef GUARD_SECURITY_DIGITAL_FORENSICS_ACQUIRER_ASM
%define GUARD_SECURITY_DIGITAL_FORENSICS_ACQUIRER_ASM

; =============================================================================
; File     : security/digital_forensics/src/acquirer.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: forensic evidence acquirer (write-blocked disk/memory imaging)
; Status   : PREMIUM ENTERPRISE SKELETON - full API surface, logic bodies
;              marked STUB for implementation.
; =============================================================================

bits 64
DEFAULT REL

%include "include/dfir.inc"

section .bss
alignb 16
dfir_acquirer_state:    resb dfir_state_base_t_size
dfir_acquirer_acq_head: resq 1
dfir_acquirer_acq_count:resq 1

section .data
alignb 16
dfir_acquirer_version_str: db DFIR_VERSION_STR, 0

section .text

; =============================================================================
; dfir_acquirer_init - Initialize forensic evidence acquirer
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global dfir_acquirer_init
dfir_acquirer_init:
    push    rbx
    mov     dword [dfir_acquirer_state + dfir_state_base_t.magic], DFIR_STATE_MAGIC
    mov     dword [dfir_acquirer_state + dfir_state_base_t.version], DFIR_VERSION_MAJOR
    mov     byte [dfir_acquirer_state + dfir_state_base_t.enabled], 1
    mov     qword [dfir_acquirer_acq_head], 0
    mov     qword [dfir_acquirer_acq_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; dfir_acquirer_shutdown - Shut down forensic evidence acquirer
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global dfir_acquirer_shutdown
dfir_acquirer_shutdown:
    push    rbx
    mov     eax, [dfir_acquirer_state + dfir_state_base_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .not_init
    mov     dword [dfir_acquirer_state + dfir_state_base_t.magic], DFIR_STATE_MAGIC_FREED
    mov     byte [dfir_acquirer_state + dfir_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; dfir_acquirer_status - Return current forensic evidence acquirer status
; Input:  none
; Output: rax = status code
; =============================================================================
global dfir_acquirer_status
dfir_acquirer_status:
    mov     eax, [dfir_acquirer_state + dfir_state_base_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .not_init
    mov     al, [dfir_acquirer_state + dfir_state_base_t.enabled]
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
; dfir_acquirer_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global dfir_acquirer_version
dfir_acquirer_version:
    mov     rax, dfir_acquirer_version_str
    ret

; =============================================================================
; dfir_acquirer_acquire_disk - Acquire physical disk image (write-blocked)
; Input:  rdi = source device pointer, rsi = destination path pointer,
;         rdx = destination path length
; Output: rax = evidence ID on success, negative error code on failure
; =============================================================================
global dfir_acquirer_acquire_disk
dfir_acquirer_acquire_disk:
    push    rbx
    push    r12

    mov     eax, [dfir_acquirer_state + dfir_state_base_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .err_not_init

    test    rdi, rdi
    jz      .err_invalid_arg
    test    rsi, rsi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save source device pointer

    ; STUB: verify write-blocker is engaged
    ; STUB: compute hash of source device in streaming fashion
    ; STUB: create bitstream image to destination
    ; STUB: verify image hash matches source hash
    ; STUB: create custody entry for acquisition

    mov     rax, 1               ; STUB: return evidence ID 1
    jmp     .done

.err_not_init:
    mov     rax, DFIR_ERR_NOT_INIT
    jmp     .done
.err_invalid_arg:
    mov     rax, DFIR_ERR_INVALID_ARG
    jmp     .done

.done:
    pop     r12
    pop     rbx
    ret

; =============================================================================
; dfir_acquirer_acquire_memory - Acquire RAM memory image
; Input:  rdi = destination path pointer, rsi = destination path length
; Output: rax = evidence ID on success, negative error code on failure
; =============================================================================
global dfir_acquirer_acquire_memory
dfir_acquirer_acquire_memory:
    push    rbx

    mov     eax, [dfir_acquirer_state + dfir_state_base_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .err_not_init

    ; STUB: enumerate physical memory ranges
    ; STUB: read memory via kernel interface
    ; STUB: compute hash of memory image
    ; STUB: write memory image to destination
    ; STUB: create custody entry

    mov     rax, 2               ; STUB: return evidence ID 2
    jmp     .done

.err_not_init:
    mov     rax, DFIR_ERR_NOT_INIT
    jmp     .done

.done:
    pop     rbx
    ret

; =============================================================================
; dfir_acquirer_acquire_file - Acquire individual file(s)
; Input:  rdi = source path pointer, rsi = source path length,
;         rdx = destination path pointer
; Output: rax = evidence ID on success, negative error code on failure
; =============================================================================
global dfir_acquirer_acquire_file
dfir_acquirer_acquire_file:
    push    rbx

    mov     eax, [dfir_acquirer_state + dfir_state_base_t.magic]
    cmp     eax, DFIR_STATE_MAGIC
    jnz     .err_not_init

    ; STUB: stat source file (size, inode, timestamps)
    ; STUB: copy file to destination preserving metadata
    ; STUB: compute file hash
    ; STUB: create custody entry

    mov     rax, 3               ; STUB: return evidence ID 3
    jmp     .done

.err_not_init:
    mov     rax, DFIR_ERR_NOT_INIT
    jmp     .done

.done:
    pop     rbx
    ret

; STUB: dfir_acquirer_verify_write_blocked - verify write-blocker status
; STUB: dfir_acquirer_compute_hash_stream - stream hash of acquisition source
; STUB: dfir_acquirer_create_image - create forensic image file
; STUB: dfir_acquirer_verify_image - verify image hash matches source
; STUB: dfir_acquirer_get_acquisition_stats - return acquisition statistics
; STUB: dfir_acquirer_cancel_acquisition - cancel in-progress acquisition
; STUB: dfir_acquirer_resume_acquisition - resume interrupted acquisition
; STUB: dfir_acquirer_acquire_network_tap - acquire from network tap
; STUB: dfir_acquirer_acquire_cloud_snapshot - acquire cloud VM snapshot
; STUB: dfir_acquirer_acquire_removable_media - acquire USB/removable media

%endif