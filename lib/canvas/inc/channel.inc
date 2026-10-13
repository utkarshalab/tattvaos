; ============================================================================
; Channel Structures — Message Rings and Handle Channels
; ============================================================================

%ifndef __CHANNEL_INC__
%define __CHANNEL_INC__

%define MsgHdr_obj      0
%define MsgHdr_opcode   4
%define MsgHdr_flags    6
%define MsgHdr_len      8
%define MsgHdr_size     12

%define MsgFlag_NEED_ACK     0x0001
%define MsgFlag_HAS_HANDLES  0x0002
%define MsgFlag_IS_EVENT     0x0004
%define MsgFlag_TRANSACTION  0x0008

%define MAX_PAYLOAD_SIZE  65536

struc Channel
    .msg_ring:      resq 1
    .handle_ring:   resq 1
    .client:        resq 1
    .server:        resq 1
endstruc

struc ChannelPair
    .server_to_client:           resq 1
    .client_to_server:           resq 1
    .server_to_client_handles:   resq 1
    .client_to_server_handles:   resq 1
    .arena:                      resq 1
endstruc

%endif
