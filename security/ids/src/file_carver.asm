%ifndef GUARD_SECURITY_IDS_SRC_FILE_CARVER_ASM
%define GUARD_SECURITY_IDS_SRC_FILE_CARVER_ASM

; =============================================================================
; File     : security/ids/src/file_carver.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IDS File Carver - extracts files from network traffic
;              (HTTP, FTP, SMTP, SMB) for malware analysis, reconstructs
;              fragmented file transfers, and calculates file hashes.
; Status   : PREMIUM ENTERPRISE - full API surface, logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ids.inc"

section .bss
alignb 16
ids_file_carver_state:      resb ids_state_base_t_size
ids_file_carver_transfer_head: resq 1
ids_file_carver_transfer_count: resq 1

section .data
alignb 16
ids_file_carver_version_str: db IDS_VERSION_STR, 0

section .text

; =============================================================================
; ids_file_carver_init - Initialize file carver
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global ids_file_carver_init
ids_file_carver_init:
    push    rbx
    mov     dword [ids_file_carver_state + ids_state_base_t.magic], IDS_STATE_MAGIC
    mov     dword [ids_file_carver_state + ids_state_base_t.version], IDS_VERSION_MAJOR
    mov     byte [ids_file_carver_state + ids_state_base_t.enabled], 1
    mov     qword [ids_file_carver_transfer_head], 0
    mov     qword [ids_file_carver_transfer_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ids_file_carver_shutdown - Shut down file carver
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ids_file_carver_shutdown
ids_file_carver_shutdown:
    push    rbx
    mov     eax, [ids_file_carver_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .not_init
    mov     dword [ids_file_carver_state + ids_state_base_t.magic], IDS_STATE_MAGIC_FREED
    mov     byte [ids_file_carver_state + ids_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ids_file_carver_status - Return current file carver status
; Input:  none
; Output: rax = status code
; =============================================================================
global ids_file_carver_status
ids_file_carver_status:
    mov     eax, [ids_file_carver_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ids_file_carver_state + ids_state_base_t.enabled]
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
; ids_file_carver_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ids_file_carver_version
ids_file_carver_version:
    mov     rax, ids_file_carver_version_str
    ret

; =============================================================================
; ids_file_carve - Extract file from network traffic stream
; Input:  rdi = stream context pointer, rsi = file type hint,
;         rdx = data pointer, rcx = data length
; Output: rax = file ID on success, rbx = file size, negative on failure
; =============================================================================
global ids_file_carve
ids_file_carve:
    push    rbx
    push    r12

    mov     eax, [ids_file_carver_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save stream context pointer

    ; STUB: identify file boundaries in traffic stream
    ; STEP: reassemble fragmented file transfers
    ; STEP: calculate SHA-256/MD5 hashes of extracted files
    ; STEP: store extracted file for malware analysis
    ; STEP: return file ID and file size

    mov     rax, 1                ; STUB: return file ID 1
    xor     rbx, rbx              ; file size unknown
    jmp     .done

.err_component_down:
    mov     rax, -1
    xor     rbx, rbx
    jmp     .done
.err_invalid_arg:
    mov     rax, -2
    xor     rbx, rbx
    jmp     .done

.done:
    pop     r12
    pop     rbx
    ret

; STUB: ids_file_carver_get_file - retrieve extracted file by ID
; STUB: ids_file_carver_list_transfers - list active file transfers
; STUB: ids_file_carver_verify_hash - verify file integrity hash
; STUB: ids_file_carver_get_stats - return carving statistics

%endif