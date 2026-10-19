%ifndef GUARD_SECURITY_IDS_SRC_REASSEMBLER_ASM
%define GUARD_SECURITY_IDS_SRC_REASSEMBLER_ASM

; =============================================================================
; File     : security/ids/src/reassembler.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IDS Packet Reassembler - TCP stream reassembly, IP fragment
;              defragmentation. Reorders out-of-order packets and reassembles
;              complete streams for protocol analysis.
; Status   : PREMIUM SKELETON - stream table, reassembly buffer, timeout
;              management defined. Logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ids.inc"

section .bss
alignb 16
ids_reassembler_state:   resb ids_state_base_t_size
ids_reassembler_stream_head: resq 1   ; active stream linked list head
ids_reassembler_stream_count: resq 1
ids_reassembler_expire_head: resq 1   ; TTL expiry queue head (STUB)
ids_reassembler_buffers_free: resq 1  ; free reassembly buffer count

section .data
alignb 16
ids_reassembler_version_str: db IDS_VERSION_STR, 0

section .text

; =============================================================================
; ids_reassembler_init - Initialize reassembler component
; Input:  none
; Output: rax = 0 on success, negative on failure
; =============================================================================
global ids_reassembler_init
ids_reassembler_init:
    push    rbx

    mov     dword [ids_reassembler_state + ids_state_base_t.magic], IDS_STATE_MAGIC
    mov     dword [ids_reassembler_state + ids_state_base_t.version], IDS_VERSION_MAJOR
    mov     byte [ids_reassembler_state + ids_state_base_t.enabled], 1

    mov     qword [ids_reassembler_stream_head], 0
    mov     qword [ids_reassembler_stream_count], 0
    mov     qword [ids_reassembler_expire_head], 0
    mov     qword [ids_reassembler_buffers_free], 0

    ; STUB: allocate reassembly buffer pool
    ; STUB: initialize stream hash table for O(1) lookup by 5-tuple
    ; STUB: initialize TTL expiry wheel for stream timeout
    ; STUB: load reassembly timeout from config

    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ids_reassembler_shutdown - Shut down reassembler component
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ids_reassembler_shutdown
ids_reassembler_shutdown:
    push    rbx

    mov     eax, [ids_reassembler_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .not_init

    ; STUB: flush all incomplete streams
    ; STUB: free reassembly buffer pool
    ; STUB: free stream hash table

    mov     dword [ids_reassembler_state + ids_state_base_t.magic], IDS_STATE_MAGIC_FREED
    mov     byte [ids_reassembler_state + ids_state_base_t.enabled], 0

    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ids_reassembler_status - Return current status
; Input:  none
; Output: rax = status code
; =============================================================================
global ids_reassembler_status
ids_reassembler_status:
    mov     eax, [ids_reassembler_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ids_reassembler_state + ids_state_base_t.enabled]
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
; ids_reassembler_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ids_reassembler_version
ids_reassembler_version:
    mov     rax, ids_reassembler_version_str
    ret

; =============================================================================
; ids_reassembler_add_packet - Add packet to reassembly stream
; Input:  rdi = packet_ctx pointer (ids_packet_ctx_t*)
; Output: rax = stream_id if stream created/updated, 0 if no reassembly needed,
;         negative on error
; =============================================================================
global ids_reassembler_add_packet
ids_reassembler_add_packet:
    push    rbx

    mov     eax, [ids_reassembler_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid

    ; STUB: extract 5-tuple from packet_ctx
    ; STUB: lookup existing stream in hash table
    ; STUB: if not found, create new stream (ids_stream_t)
    ; STUB: insert packet into reassembly buffer at correct sequence offset
    ; STUB: check if stream is complete (all bytes received)
    ; STUB: check stream timeout (last_seen_ns vs current time)
    ; STUB: if complete, return stream_id for protocol analysis

    ; For skeleton: no reassembly needed (single packet)
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

%endif
