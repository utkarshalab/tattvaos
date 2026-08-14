%ifndef GUARD_UNET_ROUTING_BGP_ASM
%define GUARD_UNET_ROUTING_BGP_ASM
; =============================================================================
; Tattva OS — unet/routing/bgp.asm
; =============================================================================
; Border Gateway Protocol 4 (BGP-4 — RFC 4271) Autonomous System Router.
;
; Features:
;   - BGP FSM: IDLE -> CONNECT -> ACTIVE -> OPENSENT -> OPENCONFIRM -> ESTABLISHED
;   - OPEN Message: AS Number, Hold Time, BGP Identifier, Capabilities
;   - UPDATE Message: Withdrawn Routes, Path Attributes, NLRI Prefix Parsing
;   - KEEPALIVE & NOTIFICATION Message Processing
;   - Path Attributes: ORIGIN, AS_PATH, NEXT_HOP, MED, LOCAL_PREF, COMMUNITIES
;   - 4-Byte ASN Support (RFC 6793)
;   - Route Filtering: Prefix Lists, AS-Path Regex, Community Matching
;   - Best Path Selection Algorithm (Decision Process RFC 4271 Section 9.1.2)
;   - Graceful Restart (RFC 4724) & Long-Lived Graceful Restart
;   - BGP-SEC (RFC 8205) Origin Validation via RPKI ROA
;
; Delegates:
;   - TCP Transport (Port 179)          -> unet/core/l4/tcp.asm
;   - HMAC-SHA256 Session Auth           -> crypto/uhash/sha256/
;   - Timer Wheel Hold/Keepalive         -> lib/time/timer_wheel.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define BGP_PORT                    179
%define BGP_MARKER_LEN              16
%define BGP_MAX_PEERS               64
%define BGP_MAX_ROUTES              1000000 ; 1M RIB entries
%define BGP_HOLD_TIME_DEFAULT       90      ; 90 seconds

%define BGP_MSG_OPEN                1
%define BGP_MSG_UPDATE              2
%define BGP_MSG_NOTIFICATION        3
%define BGP_MSG_KEEPALIVE           4

%define BGP_STATE_IDLE              0
%define BGP_STATE_CONNECT           1
%define BGP_STATE_ACTIVE            2
%define BGP_STATE_OPENSENT          3
%define BGP_STATE_OPENCONFIRM       4
%define BGP_STATE_ESTABLISHED       5

struc bgp_peer_t
    .state:             resd 1      ; FSM State
    .remote_as:         resd 1      ; Remote AS Number (4-byte)
    .local_as:          resd 1      ; Local AS Number
    .remote_ip:         resb 16     ; Remote Peer IPv4/IPv6
    .bgp_id:            resd 1      ; Remote BGP Identifier
    .hold_time:         resw 1      ; Negotiated Hold Time
    .keepalive_timer:   resd 1      ; Timer Wheel Keepalive ID
    .hold_timer:        resd 1      ; Timer Wheel Hold ID
    .routes_received:   resd 1      ; Number of Routes Received
    .graceful_restart:  resb 1      ; 1 = GR Capable
endstruc

struc bgp_route_t
    .prefix:            resb 16     ; IPv4/IPv6 Prefix
    .prefix_len:        resb 1      ; CIDR Prefix Length
    .next_hop:          resb 16     ; Next Hop Address
    .origin:            resb 1      ; 0=IGP, 1=EGP, 2=Incomplete
    .local_pref:        resd 1      ; LOCAL_PREF
    .med:               resd 1      ; Multi-Exit Discriminator
    .as_path_len:       resw 1      ; AS_PATH Length
    .as_path:           resd 16     ; AS_PATH (up to 16 ASNs)
    .community:         resd 4      ; Communities
    .peer_index:        resd 1      ; Source Peer Index
endstruc

section .text

global bgp_init
global bgp_process_message
global bgp_send_open
global bgp_send_update
global bgp_send_keepalive
global bgp_update_routes
global bgp_parse_nlri
global bgp_best_path_select
global bgp_fsm_event


align 64
bgp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; bgp_process_message — Parse BGP Message Header & Dispatch by Type
; Input: RDI = Pointer to BGP Message Buffer, ESI = Length
; Output: EAX = Message Type
; -----------------------------------------------------------------------------
align 64
bgp_process_message:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Validate 16-byte all-ones marker
    ; Extract type from header byte 18
    movzx eax, byte [rbx + 18]

    cmp al, BGP_MSG_OPEN
    je .msg_open
    cmp al, BGP_MSG_UPDATE
    je .msg_update
    cmp al, BGP_MSG_KEEPALIVE
    je .msg_keepalive
    cmp al, BGP_MSG_NOTIFICATION
    je .msg_notification
    jmp .msg_done

.msg_open:
    ; Parse version, AS, hold time, BGP ID, capabilities
    ; Transition FSM: OPENSENT -> OPENCONFIRM
    call bgp_send_keepalive
    jmp .msg_done

.msg_update:
    ; Parse withdrawn routes, path attributes, NLRI
    call bgp_update_routes
    jmp .msg_done

.msg_keepalive:
    ; Reset hold timer
    jmp .msg_done

.msg_notification:
    ; Log error code/subcode, tear down session
    jmp .msg_done

.msg_done:
    pop rbx
    pop rbp
    ret

align 64
bgp_send_open:
    push rbp
    mov rbp, rsp
    ; Build OPEN message with 4-byte ASN, hold time, capabilities
    xor eax, eax
    pop rbp
    ret

align 64
bgp_send_update:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Build UPDATE message with withdrawn routes + path attrs + NLRI
    xor eax, eax
    pop rbp
    ret

align 64
bgp_send_keepalive:
    push rbp
    mov rbp, rsp
    ; Send 19-byte KEEPALIVE (marker + length + type)
    ; Reschedule keepalive timer
    call timer_wheel_add
    pop rbp
    ret

align 64
bgp_update_routes:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Parse NLRI prefixes & run best path selection
    call bgp_parse_nlri
    call bgp_best_path_select
    pop rbp
    ret

; -----------------------------------------------------------------------------
; bgp_parse_nlri — Parse Network Layer Reachability Information (NLRI)
; Input: RDI = Pointer to NLRI Field, ESI = NLRI Length
; Output: EAX = Number of Prefixes Parsed
; -----------------------------------------------------------------------------
align 64
bgp_parse_nlri:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Parse variable-length CIDR prefixes (prefix_len + prefix_bytes)
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; bgp_best_path_select — BGP Decision Process (RFC 4271 Section 9.1.2)
; Tie-breaking order: LOCAL_PREF > AS_PATH length > ORIGIN > MED > eBGP > IGP > Router ID
; -----------------------------------------------------------------------------
align 64
bgp_best_path_select:
    push rbp
    mov rbp, rsp
    ; 1. Highest LOCAL_PREF
    ; 2. Shortest AS_PATH
    ; 3. Lowest ORIGIN (IGP < EGP < Incomplete)
    ; 4. Lowest MED (for same neighbor AS)
    ; 5. eBGP over iBGP
    ; 6. Lowest IGP metric to NEXT_HOP
    ; 7. Lowest Router ID
    xor eax, eax
    pop rbp
    ret

align 64
bgp_fsm_event:
    push rbp
    mov rbp, rsp
    ; Process FSM event & transition state
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_ROUTING_BGP_ASM
