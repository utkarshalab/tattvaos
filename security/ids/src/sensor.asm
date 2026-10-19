%ifndef GUARD_SECURITY_IDS_SRC_SENSOR_ASM
%define GUARD_SECURITY_IDS_SRC_SENSOR_ASM

; =============================================================================
; File     : security/ids/src/sensor.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IDS Sensor - packet capture, syscall audit, log ingestion.
;              Raw data acquisition layer: captures packets from network
;              interfaces and system events from audit/log sources.
; Status   : PREMIUM SKELETON - capture pipeline, interface management,
;              buffer ring structures defined. Logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ids.inc"

section .bss
alignb 16
ids_sensor_state:     resb ids_state_base_t_size
ids_sensor_ring_head: resq 1      ; packet capture ring buffer head
ids_sensor_ring_tail: resq 1      ; packet capture ring buffer tail
ids_sensor_ring_size: resq 1      ; ring buffer capacity
ids_sensor_iface_count: resq 1    ; number of monitored interfaces
ids_sensor_packets_dropped: resq 1 ; packets dropped by sensor (overrun)

section .data
alignb 16
ids_sensor_version_str: db IDS_VERSION_STR, 0

; Default interface capture configuration (STUB)
sensor_default_ifaces:
    db "eth0", 0
    db "eth1", 0

section .text

; =============================================================================
; ids_sensor_init - Initialize sensor component
; Input:  none
; Output: rax = 0 on success, negative on failure
; =============================================================================
global ids_sensor_init
ids_sensor_init:
    push    rbx

    mov     dword [ids_sensor_state + ids_state_base_t.magic], IDS_STATE_MAGIC
    mov     dword [ids_sensor_state + ids_state_base_t.version], IDS_VERSION_MAJOR
    mov     byte [ids_sensor_state + ids_state_base_t.enabled], 1

    mov     qword [ids_sensor_ring_head], 0
    mov     qword [ids_sensor_ring_tail], 0
    mov     qword [ids_sensor_ring_size], 0
    mov     qword [ids_sensor_iface_count], 0
    mov     qword [ids_sensor_packets_dropped], 0

    ; STUB: allocate packet capture ring buffer
    ; STUB: open network interfaces for promiscuous capture
    ; STUB: register syscall audit hooks
    ; STUB: register log file watchers

    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ids_sensor_shutdown - Shut down sensor component
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ids_sensor_shutdown
ids_sensor_shutdown:
    push    rbx

    mov     eax, [ids_sensor_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .not_init

    ; STUB: close network interfaces
    ; STUB: free ring buffer
    ; STUB: unregister audit/log hooks

    mov     dword [ids_sensor_state + ids_state_base_t.magic], IDS_STATE_MAGIC_FREED
    mov     byte [ids_sensor_state + ids_state_base_t.enabled], 0

    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ids_sensor_status - Return current sensor status
; Input:  none
; Output: rax = status code
; =============================================================================
global ids_sensor_status
ids_sensor_status:
    mov     eax, [ids_sensor_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ids_sensor_state + ids_state_base_t.enabled]
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
; ids_sensor_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ids_sensor_version
ids_sensor_version:
    mov     rax, ids_sensor_version_str
    ret

; =============================================================================
; ids_sensor_capture - Capture and validate a packet
; Input:  rdi = packet_ctx pointer (ids_packet_ctx_t*) to fill
; Output: rax = 0 if packet captured, negative if no packet / error
; =============================================================================
global ids_sensor_capture
ids_sensor_capture:
    push    rbx

    mov     eax, [ids_sensor_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid

    ; STUB: read next packet from ring buffer
    ; STUB: fill ids_packet_ctx_t fields (src/dst IP, ports, protocol, payload)
    ; STUB: validate packet checksums
    ; STUB: mark fragmented/retransmitted/encrypted packets

    ; For skeleton: return "no packet available"
    mov     rax, -1   ; STUB: no packet in ring buffer
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
