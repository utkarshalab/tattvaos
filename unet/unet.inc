; =============================================================================
; Tattva OS — unet/unet.inc
; =============================================================================
; Master Schema Header for unet (64-Bit Assembly Zero-Copy Network Stack Engine).
;
; Defines data structures for:
;   - Ethernet II & 802.1Q VLAN Tagging
;   - ARP Request/Reply & ACD Conflict Detection
;   - IPv4 20-byte & IPv6 40-byte Headers
;   - UDP 8-byte Header & Checksums
;   - TCP 20-byte Header, 11-State Machine, Options (SACK, Window Scale, Timestamps)
;   - POSIX BSD Socket & Epoll Event Notification
;   - HTTP/1.1 (GET, POST, PUT, DELETE, HEAD, OPTIONS, QUERY - RFC 10008)
;   - Zero-Copy 2048-Byte Packet Ring Buffer (`net_pkt_t`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef UNET_INC
%define UNET_INC

%define UNET_ETH_TYPE_IPV4          0x0800
%define UNET_ETH_TYPE_ARP           0x0806
%define UNET_ETH_TYPE_VLAN          0x8100
%define UNET_ETH_TYPE_IPV6          0x86DD

%define UNET_IP_PROTO_ICMP          1
%define UNET_IP_PROTO_TCP           6
%define UNET_IP_PROTO_UDP           17
%define UNET_IP_PROTO_ESP           50                  ; IPsec ESP

; POSIX Socket Types
%define UNET_SOCK_STREAM            1                   ; TCP
%define UNET_SOCK_DGRAM             2                   ; UDP
%define UNET_SOCK_RAW               3                   ; Raw Packet

; TCP State Machine Enum
%define TCP_STATE_CLOSED            0
%define TCP_STATE_LISTEN            1
%define TCP_STATE_SYN_SENT          2
%define TCP_STATE_SYN_RCVD          3
%define TCP_STATE_ESTABLISHED       4
%define TCP_STATE_FIN_WAIT_1        5
%define TCP_STATE_FIN_WAIT_2        6
%define TCP_STATE_CLOSE_WAIT        7
%define TCP_STATE_CLOSING           8
%define TCP_STATE_LAST_ACK          9
%define TCP_STATE_TIME_WAIT         10

; HTTP Request Methods (Includes RFC 10008 QUERY Method)
%define HTTP_METHOD_GET             1
%define HTTP_METHOD_POST            2
%define HTTP_METHOD_PUT             3
%define HTTP_METHOD_DELETE          4
%define HTTP_METHOD_HEAD            5
%define HTTP_METHOD_OPTIONS         6
%define HTTP_METHOD_QUERY           7                   ; RFC 10008 HTTP QUERY Method

%define UNET_PKT_BUF_SIZE           2048
%define UNET_MAX_SOCKETS            512

; -----------------------------------------------------------------------------
; Zero-Copy Packet Descriptor (`net_pkt_t`)
; -----------------------------------------------------------------------------
struc net_pkt_t
    .phys_addr:         resq 1      ; 64-bit DMA Physical Address
    .virt_addr:         resq 1      ; 64-bit Virtual Address
    .headroom_offset:   resd 1      ; Offset to start of headers
    .data_len:          resd 1      ; Payload length in bytes
    .total_capacity:    resd 1      ; 2048 bytes
    .ref_count:         resd 1      ; Shared zero-copy reference counter
    .next_pkt:          resq 1      ; Linked list pointer for packet chains
endstruc

; -----------------------------------------------------------------------------
; Ethernet II Header (14 bytes)
; -----------------------------------------------------------------------------
struc eth_header_t
    .dest_mac:          resb 6      ; Destination MAC Address
    .src_mac:           resb 6      ; Source MAC Address
    .ethertype:         resw 1      ; 0x0800 IPv4, 0x0806 ARP, 0x86DD IPv6 (big-endian)
endstruc

; -----------------------------------------------------------------------------
; ARP Packet Structure (28 bytes)
; -----------------------------------------------------------------------------
struc arp_packet_t
    .hw_type:           resw 1      ; 1 = Ethernet
    .proto_type:        resw 1      ; 0x0800 = IPv4
    .hw_len:            resb 1      ; 6
    .proto_len:         resb 1      ; 4
    .opcode:            resw 1      ; 1 = Request, 2 = Reply
    .sender_mac:        resb 6
    .sender_ip:         resd 1
    .target_mac:        resb 6
    .target_ip:         resd 1
endstruc

; -----------------------------------------------------------------------------
; IPv4 Header (20 bytes)
; -----------------------------------------------------------------------------
struc ipv4_header_t
    .ver_ihl:           resb 1      ; Version (4) & IHL (5 = 20 bytes)
    .tos:               resb 1      ; Type of Service / DSCP / ECN
    .total_len:         resw 1      ; Total packet length (big-endian)
    .id:                resw 1      ; Identification
    .flags_fragment:    resw 1      ; Flags & Fragment Offset
    .ttl:               resb 1      ; Time to Live (e.g. 64)
    .protocol:          resb 1      ; 6=TCP, 17=UDP, 1=ICMP
    .checksum:          resw 1      ; 16-bit Internet Ones' Complement Checksum
    .src_ip:            resd 1      ; Source IPv4 address
    .dest_ip:           resd 1      ; Destination IPv4 address
endstruc

; -----------------------------------------------------------------------------
; IPv6 Header (40 bytes)
; -----------------------------------------------------------------------------
struc ipv6_header_t
    .ver_tc_fl:         resd 1      ; Version (6), Traffic Class, Flow Label
    .payload_len:       resw 1      ; Payload length in bytes
    .next_header:       resb 1      ; 6=TCP, 17=UDP, 58=ICMPv6
    .hop_limit:         resb 1      ; Hop Limit (64)
    .src_ip6:           resb 16     ; Source 128-bit IPv6 address
    .dest_ip6:          resb 16     ; Destination 128-bit IPv6 address
endstruc

; -----------------------------------------------------------------------------
; UDP Header (8 bytes)
; -----------------------------------------------------------------------------
struc udp_header_t
    .src_port:          resw 1      ; Source Port (big-endian)
    .dest_port:         resw 1      ; Destination Port (big-endian)
    .length:            resw 1      ; Header + Data length in bytes
    .checksum:          resw 1      ; UDP 16-bit Checksum (Optional for IPv4, mandatory IPv6)
endstruc

; -----------------------------------------------------------------------------
; TCP Header (20 bytes + options)
; -----------------------------------------------------------------------------
struc tcp_header_t
    .src_port:          resw 1      ; Source Port (big-endian)
    .dest_port:         resw 1      ; Destination Port (big-endian)
    .seq_num:           resd 1      ; 32-bit Sequence Number (big-endian)
    .ack_num:           resd 1      ; 32-bit Acknowledgment Number (big-endian)
    .data_offset_flags: resw 1      ; Data Offset (4 bits) + Flags (URG, ACK, PSH, RST, SYN, FIN)
    .window_size:       resw 1      ; 16-bit Window Size
    .checksum:          resw 1      ; 16-bit TCP Checksum
    .urgent_ptr:        resw 1      ; Urgent Pointer
endstruc

; -----------------------------------------------------------------------------
; BSD Socket Structure (256 bytes)
; -----------------------------------------------------------------------------
struc socket_t
    .sock_id:           resd 1      ; Socket file descriptor ID (3, 4, 5...)
    .sock_type:         resd 1      ; UNET_SOCK_STREAM (TCP) / UNET_SOCK_DGRAM (UDP)
    .state:             resd 1      ; TCP State (LISTEN, ESTABLISHED, CLOSED...)
    .local_port:        resw 1
    .remote_port:       resw 1
    .local_ip:          resd 1
    .remote_ip:         resd 1
    .seq_num:           resd 1      ; Local SEQ number
    .ack_num:           resd 1      ; Remote ACK number
    .window_scale:      resb 1
    .rx_buffer_phys:    resq 1      ; Physical RX Ring Buffer Address
    .tx_buffer_phys:    resq 1      ; Physical TX Ring Buffer Address
    .reserved:          resb 191
endstruc

%endif ; UNET_INC
