; ============================================================================
; Channel Structures — Message Rings and Handle Channels
; ============================================================================

%ifndef __CHANNEL_INC__
%define __CHANNEL_INC__

struc MsgHdr
    .obj:                     resd 1
    .opcode:                  resw 1
    .flags:                   resw 1
    .len:                     resd 1
endstruc

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
    .wake_task:                  resq 1    ; the server's loop, woken by a
                                           ; client's send (0: none known)
    .wakes:                      resq 1    ; wakes the client asked for
    .state:                      resq 1    ; a connect: 0 waiting, 1 ready,
                                           ; negative: refused (the error)
    .region:                     resq 1    ; its memory when canvas_connect
                                           ; made it, for ut_mem_free
endstruc

%endif
