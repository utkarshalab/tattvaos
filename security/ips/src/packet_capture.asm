%ifndef GUARD_SECURITY_IPS_SRC_PACKET_CAPTURE_ASM
%define GUARD_SECURITY_IPS_SRC_PACKET_CAPTURE_ASM

; =============================================================================
; File     : security/ips/src/packet_capture.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IPS Packet Capture - PCAP export and forensic capture.
;              Captures packets matching filter criteria for offline
;              analysis, evidence collection, and incident response.
; Status   : PREMIUM ENTERPRISE - capture filters, ring buffer,
;             PCAP export defined.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ips.inc"

section .bss
alignb 16
ips_packet_capture_state:     resb ips_state_base_t_size
ips_packet_capture_active:    resb 1      ; capture is active flag
ips_packet_capture_filter_ptr: resq 1    ; capture filter expression
ips_packet_capture_filter_len: resd 1
ips_packet_capture_max_packets: resq 1   ; max packets to capture
ips_packet_capture_captured:   resq 1   ; packets captured so far
ips_packet_capture_ring_head:  resq 1   ; capture ring buffer head
ips_packet_capture_ring_tail:  resq 1   ; capture ring buffer tail

section .data
alignb 16
ips_packet_capture_version_str: db IPS_VERSION_STR, 0

section .text

; =============================================================================
; ips_packet_capture_init - Initialize packet capture component
; Input:  none
; Output: rax = 0 on success, negative on failure
; =============================================================================
global ips_packet_capture_init
ips_packet_capture_init:
    push    rbx

    mov     dword [ips_packet_capture_state + ips_state_base_t.magic], IPS_STATE_MAGIC
    mov     dword [ips_packet_capture_state + ips_state_base_t.version], IPS_VERSION_MAJOR
    mov     byte [ips_packet_capture_state + ips_state_base_t.enabled], 1

    mov     byte [ips_packet_capture_active], 0
    mov     qword [ips_packet_capture_filter_ptr], 0
    mov     qword [ips_packet_capture_filter_len], 0
    mov     qword [ips_packet_capture_max_packets], 0
    mov     qword [ips_packet_capture_captured], 0
    mov     qword [ips_packet_capture_ring_head], 0
    mov     qword [ips_packet_capture_ring_tail], 0

    ; STUB: allocate capture ring buffer
    ; STUB: initialize capture filter engine
    ; STUB: allocate PCAP file writer

    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ips_packet_capture_shutdown - Shut down packet capture component
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ips_packet_capture_shutdown
ips_packet_capture_shutdown:
    push    rbx

    mov     eax, [ips_packet_capture_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init

    ; STUB: stop active capture
    ; STUB: free capture ring buffer
    ; STUB: close PCAP file writer

    mov     dword [ips_packet_capture_state + ips_state_base_t.magic], IPS_STATE_MAGIC_FREED
    mov     byte [ips_packet_capture_state + ips_state_base_t.enabled], 0

    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ips_packet_capture_status - Return current status
; Input:  none
; Output: rax = status code
; =============================================================================
global ips_packet_capture_status
ips_packet_capture_status:
    mov     eax, [ips_packet_capture_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ips_packet_capture_state + ips_state_base_t.enabled]
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
; ips_packet_capture_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ips_packet_capture_version
ips_packet_capture_version:
    mov     rax, ips_packet_capture_version_str
    ret

; =============================================================================
; ips_packet_capture_start - Start packet capture
; Input:  rdi = filter expression pointer (NUL-terminated, BPF syntax),
;         rsi = filter length, rdx = max packets to capture
; Output: rax = 0 on success, negative on failure
; =============================================================================
global ips_packet_capture_start
ips_packet_capture_start:
    push    rbx

    mov     eax, [ips_packet_capture_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid

    ; STUB: compile BPF filter expression
    ; STUB: attach capture hook to network interface
    ; STUB: set active flag
    ; STUB: start packet capture timer

    mov     byte [ips_packet_capture_active], 1
    xor     eax, eax
    pop     rbx
    ret

.err_component_down:
    mov     rax, -2
    pop     rbx
    ret
.err_invalid:
    mov     rax, -3
    pop     rbx
    ret

; =============================================================================
; ips_packet_capture_stop - Stop packet capture
; Input:  none
; Output: rax = number of packets captured, negative on error
; =============================================================================
global ips_packet_capture_stop
ips_packet_capture_stop:
    push    rbx

    mov     eax, [ips_packet_capture_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    ; STUB: remove capture hook from network interface
    ; STUB: flush capture ring buffer to PCAP file
    ; STUB: clear active flag

    mov     byte [ips_packet_capture_active], 0
    mov     rax, [ips_packet_capture_captured]
    pop     rbx
    ret

.err_component_down:
    mov     rax, -2
    pop     rbx
    ret

%endif
