%ifndef GUARD_UNET_CORE_L4_QUIC_ASM
%define GUARD_UNET_CORE_L4_QUIC_ASM
; =============================================================================
; Utkarsha OS — unet/core/l4/quic.asm
; =============================================================================
; QUIC Protocol Support (RFC 9000) - Stub Implementation
;
; QUIC is a multiplexed, encrypted transport protocol over UDP.
; This is a stub implementation providing the basic structure.
;
; Features (to be implemented):
;   - QUIC packet types (Initial, Handshake, 0-RTT, Retry, etc.)
;   - Connection IDs and stateless retry
;   - TLS 1.3 integration for handshake
;   - Stream multiplexing with flow control
;   - Loss detection and congestion control (NewReno/CUBIC)
;   - Connection migration
;   - 0-RTT and 1-RTT data
;   - Path validation and migration
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/unet/unet.inc"

%define QUIC_VERSION_1              0x00000001
%define QUIC_VERSION_DRAFT_29       0xff00001d

%define QUIC_PACKET_INITIAL         0xc0
%define QUIC_PACKET_HANDSHAKE       0xe0
%define QUIC_PACKET_0RTT            0xd0
%define QUIC_PACKET_RETRY           0xf0
%define QUIC_PACKET_1RTT            0x40
%define QUIC_PACKET_VERSION_NEG     0x80

%define QUIC_FRAME_PADDING          0x00
%define QUIC_FRAME_PING             0x01
%define QUIC_FRAME_ACK              0x02
%define QUIC_FRAME_RESET_STREAM     0x04
%define QUIC_FRAME_STOP_SENDING     0x05
%define QUIC_FRAME_CRYPTO           0x06
%define QUIC_FRAME_NEW_TOKEN        0x07
%define QUIC_FRAME_STREAM           0x08
%define QUIC_FRAME_MAX_DATA         0x10
%define QUIC_FRAME_MAX_STREAM_DATA  0x11
%define QUIC_FRAME_MAX_STREAMS_BIDI 0x12
%define QUIC_FRAME_MAX_STREAMS_UNI  0x13
%define QUIC_FRAME_DATA_BLOCKED     0x14
%define QUIC_FRAME_STREAM_DATA_BLOCKED 0x15
%define QUIC_FRAME_STREAMS_BLOCKED_BIDI 0x16
%define QUIC_FRAME_STREAMS_BLOCKED_UNI 0x17
%define QUIC_FRAME_NEW_CONNECTION_ID 0x18
%define QUIC_FRAME_RETIRE_CONNECTION_ID 0x19
%define QUIC_FRAME_PATH_CHALLENGE   0x1a
%define QUIC_FRAME_PATH_RESPONSE    0x1b
%define QUIC_FRAME_CONNECTION_CLOSE 0x1c
%define QUIC_FRAME_HANDSHAKE_DONE   0x1d

%define QUIC_MAX_PACKET_SIZE        1350
%define QUIC_MAX_CID_LEN            20
%define QUIC_MAX_STREAMS_BIDI       100
%define QUIC_MAX_STREAMS_UNI        100

struc quic_conn_t
    .version:           resd 1
    .dcid:              resb QUIC_MAX_CID_LEN
    .dcid_len:          resb 1
    .scid:              resb QUIC_MAX_CID_LEN
    .scid_len:          resb 1
    .state:             resb 1
    .flags:             resb 1
    .pad0:              resw 1
    .local_max_data:    resq 1
    .remote_max_data:   resq 1
    .local_max_stream_data_bidi: resq 1
    .remote_max_stream_data_bidi: resq 1
    .local_max_stream_data_uni: resq 1
    .remote_max_stream_data_uni: resq 1
    .local_max_streams_bidi: resd 1
    .remote_max_streams_bidi: resd 1
    .local_max_streams_uni: resd 1
    .remote_max_streams_uni: resd 1
    .initial_keys:      resq 1
    .handshake_keys:    resq 1
    .app_keys:          resq 1
    .tls_conn:          resq 1
    .streams:           resq 1
    .sent_packets:      resq 1
    .ack_queue:         resq 1
    .pto_count:         resb 1
    .pad1:              resb 7
endstruc

%define QUIC_STATE_INIT           0
%define QUIC_STATE_HANDSHAKE      1
%define QUIC_STATE_ESTABLISHED    2
%define QUIC_STATE_CLOSING        3
%define QUIC_STATE_DRAINING       3
%define QUIC_STATE_CLOSED         4

struc quic_packet_t
    .type:              resb 1
    .flags:             resb 1
    .dcid:              resb QUIC_MAX_CID_LEN
    .dcid_len:          resb 1
    .scid:              resb QUIC_MAX_CID_LEN
    .scid_len:          resb 1
    .version:           resd 1
    .packet_number:     resq 1
    .payload:           resb 1
endstruc

struc quic_frame_t
    .type:              resb 1
    .flags:             resb 1
    .length:            resw 1
    .payload:           resb 1
endstruc

%define QUIC_MAX_PKT_NUM      0xFFFFFFFFFFFFFFFF

section .bss
alignb 64
quic_conn_pool:        resb kmem_cache_t_size
quic_packet_pool:      resb kmem_cache_t_size

section .data
quic_conn_cache_name:  db "quic_conn", 0
quic_packet_cache_name: db "quic_packet", 0

section .text

global quic_init
global quic_connection_create
global quic_connection_destroy
global quic_input
global quic_output
global quic_send_initial
global quic_send_handshake
global quic_send_1rtt
global quic_process_initial
global quic_process_handshake
global quic_process_0rtt
global quic_process_1rtt
global quic_send_ack
global quic_on_ack

; =============================================================================
; quic_init — Initialize QUIC subsystem
; -----------------------------------------------------------------------------
align 64
quic_init:
    push rbp
    mov rbp, rsp
    push rbx

    ; Create connection pool
    lea rdi, [quic_conn_pool]
    lea rsi, [quic_conn_cache_name]
    mov rdx, quic_conn_t_size
    mov rcx, 64
    xor r8, r8
    xor r9, r9
    call kmem_cache_create_in_place

    ; Create packet pool
    lea rdi, [quic_packet_pool]
    lea rsi, [quic_packet_cache_name]
    mov rdx, QUIC_MAX_PACKET_SIZE
    mov rcx, 64
    xor r8, r8
    xor r9, r9
    call kmem_cache_create_in_place

    xor eax, eax
    pop rbx
    pop rbp
    ret

; =============================================================================
; quic_connection_create — Create new QUIC connection
; Input: EDI = version, RSI = dcid, EDX = dcid_len, RCX = scid, R8D = scid_len
;        (each connection ID at most QUIC_MAX_CID_LEN bytes)
; Output: RAX = quic_conn_t* or 0
; -----------------------------------------------------------------------------
align 64
quic_connection_create:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, edi           ; version
    mov r13, rsi            ; dcid
    mov r14, rcx            ; scid
    movzx r15d, dl          ; dcid_len
    shl r8d, 8
    or r15d, r8d            ; R15D = scid_len << 8 | dcid_len

    cmp r15b, QUIC_MAX_CID_LEN
    ja .fail
    mov eax, r15d
    shr eax, 8
    cmp eax, QUIC_MAX_CID_LEN
    ja .fail

    lea rdi, [quic_conn_pool]
    call kmem_cache_alloc
    test rax, rax
    jz .fail
    mov rbx, rax

    mov [rbx + quic_conn_t.version], r12d
    mov byte [rbx + quic_conn_t.state], QUIC_STATE_INIT
    mov byte [rbx + quic_conn_t.flags], 0

    ; Copy connection IDs
    movzx ecx, r15b
    mov [rbx + quic_conn_t.dcid_len], cl
    lea rdi, [rbx + quic_conn_t.dcid]
    mov rsi, r13
    rep movsb

    mov ecx, r15d
    shr ecx, 8
    mov [rbx + quic_conn_t.scid_len], cl
    lea rdi, [rbx + quic_conn_t.scid]
    mov rsi, r14
    rep movsb

    ; Initialize flow control
    mov qword [rbx + quic_conn_t.local_max_data], 10485760  ; 10 MB
    mov qword [rbx + quic_conn_t.remote_max_data], 0
    mov qword [rbx + quic_conn_t.local_max_stream_data_bidi], 1048576
    mov qword [rbx + quic_conn_t.remote_max_stream_data_bidi], 0
    mov qword [rbx + quic_conn_t.local_max_stream_data_uni], 1048576
    mov qword [rbx + quic_conn_t.remote_max_stream_data_uni], 0
    mov dword [rbx + quic_conn_t.local_max_streams_bidi], QUIC_MAX_STREAMS_BIDI
    mov dword [rbx + quic_conn_t.remote_max_streams_bidi], 0
    mov dword [rbx + quic_conn_t.local_max_streams_uni], QUIC_MAX_STREAMS_UNI
    mov dword [rbx + quic_conn_t.remote_max_streams_uni], 0

    mov rax, rbx
    jmp .done

.fail:
    xor eax, eax

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; quic_input — Process incoming QUIC packet
; Input: RDI = net_pkt_t* (headroom_offset at the QUIC header),
;        RSI = quic_conn_t* (optional, 0 if unknown)
; Output: EAX = 0 (handled) or -1 (dropped)
; -----------------------------------------------------------------------------
align 64
quic_input:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi            ; net_pkt_t*
    mov r12, [rbx + net_pkt_t.virt_addr]
    mov eax, [rbx + net_pkt_t.headroom_offset]
    add r12, rax            ; R12 = first byte of the QUIC header

    mov ecx, [rbx + net_pkt_t.data_len]
    sub ecx, eax            ; ECX = bytes available
    jz .drop

    movzx eax, byte [r12]
    test al, 0x80
    jz .short_header

    ; Long header: first byte, then a 4-byte version
    cmp ecx, 5
    jb .drop
    cmp dword [r12 + 1], 0
    je .version_neg         ; version 0 marks Version Negotiation

    ; Packet type is bits 4-5 (1 1 T T x x x x)
    and al, 0xF0
    cmp al, QUIC_PACKET_INITIAL
    je .process_initial
    cmp al, QUIC_PACKET_0RTT
    je .process_0rtt
    cmp al, QUIC_PACKET_HANDSHAKE
    je .process_handshake
    jmp .process_retry      ; 0xF0 is the only type left

.short_header:
    call quic_process_1rtt
    jmp .done

.process_initial:
    call quic_process_initial
    jmp .done

.process_handshake:
    call quic_process_handshake
    jmp .done

.process_0rtt:
    call quic_process_0rtt
    jmp .done

.process_retry:
    ; TODO: Retry — restart the handshake with the server's token
    jmp .drop

.version_neg:
    ; TODO: Version Negotiation — pick a common version or abort
    jmp .drop

.drop:
    mov eax, -1

.done:
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; quic_output — Send QUIC packet
; -----------------------------------------------------------------------------
align 64
quic_output:
    ret

; =============================================================================
; quic_send_initial — Send Initial packet
; -----------------------------------------------------------------------------
align 64
quic_send_initial:
    ret

; =============================================================================
; quic_send_handshake — Send Handshake packet
; -----------------------------------------------------------------------------
align 64
quic_send_handshake:
    ret

; =============================================================================
; quic_send_1rtt — Send 1-RTT packet
; -----------------------------------------------------------------------------
align 64
quic_send_1rtt:
    ret

; =============================================================================
; quic_process_initial — Process Initial packet
; -----------------------------------------------------------------------------
align 64
quic_process_initial:
    ; Input: RDI = net_pkt_t*, RSI = quic_conn_t* (optional)
    ; TODO: decrypt and process the frames; dropped until then
    mov eax, -1
    ret

; =============================================================================
; quic_process_handshake — Process Handshake packet
; -----------------------------------------------------------------------------
align 64
quic_process_handshake:
    ; Input: RDI = net_pkt_t*, RSI = quic_conn_t* (optional)
    ; TODO: decrypt and process the frames; dropped until then
    mov eax, -1
    ret

; =============================================================================
; quic_process_0rtt — Process 0-RTT packet
; -----------------------------------------------------------------------------
align 64
quic_process_0rtt:
    ; Input: RDI = net_pkt_t*, RSI = quic_conn_t* (optional)
    ; TODO: accept early data once session resumption exists; dropped until then
    mov eax, -1
    ret

; =============================================================================
; quic_process_1rtt — Process 1-RTT packet
; -----------------------------------------------------------------------------
align 64
quic_process_1rtt:
    ; Input: RDI = net_pkt_t*, RSI = quic_conn_t* (optional)
    ; TODO: decrypt and process the frames; dropped until then
    mov eax, -1
    ret

; =============================================================================
; quic_send_ack — Send ACK frame
; -----------------------------------------------------------------------------
align 64
quic_send_ack:
    ret

; =============================================================================
; quic_on_ack — Process incoming ACK
; -----------------------------------------------------------------------------
align 64
quic_on_ack:
    ret

%endif ; GUARD_UNET_CORE_L4_QUIC_ASM
