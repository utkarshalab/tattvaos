%ifndef GUARD_SECURITY_IPS_SRC_BLOCKLIST_ASM
%define GUARD_SECURITY_IPS_SRC_BLOCKLIST_ASM

; =============================================================================
; File     : security/ips/src/blocklist.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IPS Blocklist - IP/domain blacklist management. Maintains list
;              of blocked endpoints with optional expiry times.
; Status   : PREMIUM SKELETON - blocklist table, add/remove/check operations
;              defined. Logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ips.inc"

section .bss
alignb 16
ips_blocklist_state:     resb ips_state_base_t_size
ips_blocklist_entry_head: resq 1   ; blocklist entry linked list
ips_blocklist_entry_count: resq 1

section .data
alignb 16
ips_blocklist_version_str: db IPS_VERSION_STR, 0

section .text

; =============================================================================
; ips_blocklist_init - Initialize blocklist component
; Input:  none
; Output: rax = 0 on success, negative on failure
; =============================================================================
global ips_blocklist_init
ips_blocklist_init:
    push    rbx

    mov     dword [ips_blocklist_state + ips_state_base_t.magic], IPS_STATE_MAGIC
    mov     dword [ips_blocklist_state + ips_state_base_t.version], IPS_VERSION_MAJOR
    mov     byte [ips_blocklist_state + ips_state_base_t.enabled], 1

    mov     qword [ips_blocklist_entry_head], 0
    mov     qword [ips_blocklist_entry_count], 0

    ; STUB: allocate blocklist memory pool
    ; STUB: load blocklist from config/file
    ; STUB: initialize hash table for O(1) IP lookup

    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ips_blocklist_shutdown - Shut down blocklist component
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ips_blocklist_shutdown
ips_blocklist_shutdown:
    push    rbx

    mov     eax, [ips_blocklist_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init

    ; STUB: free all blocklist entries

    mov     dword [ips_blocklist_state + ips_state_base_t.magic], IPS_STATE_MAGIC_FREED
    mov     byte [ips_blocklist_state + ips_state_base_t.enabled], 0

    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ips_blocklist_status - Return current status
; Input:  none
; Output: rax = status code
; =============================================================================
global ips_blocklist_status
ips_blocklist_status:
    mov     eax, [ips_blocklist_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ips_blocklist_state + ips_state_base_t.enabled]
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
; ips_blocklist_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ips_blocklist_version
ips_blocklist_version:
    mov     rax, ips_blocklist_version_str
    ret

; =============================================================================
; ips_blocklist_add - Add an IP to the blocklist
; Input:  rdi = IP address, rsi = reason_code, rdx = expires_ns (0 = permanent)
; Output: rax = 0 on success, negative on failure
; =============================================================================
global ips_blocklist_add
ips_blocklist_add:
    push    rbx

    mov     eax, [ips_blocklist_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid

    ; STUB: allocate ips_blocklist_entry_t from pool
    ; STUB: fill entry fields (ip, reason_code, blocked_ns, expires_ns)
    ; STUB: insert into blocklist linked list / hash table

    ; For skeleton: add successful
    xor     eax, eax
    jmp .done

.err_component_down:
    mov     rax, -2
    jmp .done
.err_invalid:
    mov     rax, -3
    jmp .done

.done:
    pop     rbx
    ret

; =============================================================================
; ips_blocklist_remove - Remove an IP from the blocklist
; Input:  rdi = IP address
; Output: rax = 0 on success, negative if not found
; =============================================================================
global ips_blocklist_remove
ips_blocklist_remove:
    push    rbx

    mov     eax, [ips_blocklist_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid

    ; STUB: lookup blocklist entry for IP
    ; STUB: remove from blocklist
    ; STUB: free entry back to pool

    ; For skeleton: remove successful
    xor     eax, eax
    jmp .done

.err_component_down:
    mov     rax, -2
    jmp .done
.err_invalid:
    mov     rax, -3
    jmp .done

.done:
    pop     rbx
    ret

; =============================================================================
; ips_blocklist_check - Check if an IP is blocked
; Input:  rdi = IP address
; Output: rax = 0 if not blocked, 1 if blocked, negative on error
;         rbx = reason_code if blocked
; =============================================================================
global ips_blocklist_check
ips_blocklist_check:
    push    rbx

    mov     eax, [ips_blocklist_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid

    ; STUB: lookup blocklist entry for IP
    ; STUB: check if expires_ns has passed (entry is stale)
    ; For skeleton: not blocked
    xor     rax, rax   ; not blocked
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
