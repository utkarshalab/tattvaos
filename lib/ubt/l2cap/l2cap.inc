; =============================================================================
; Utkarsha OS — lib/ubt/l2cap/l2cap.inc — L2CAP
; =============================================================================
; Names follow the Bluetooth Core specification, volume 3 part A.
; =============================================================================

%ifndef LIB_UBT_L2CAP_L2CAP_INC
%define LIB_UBT_L2CAP_L2CAP_INC

; ---- Channel identifiers --------------------------------------------------------
%define L2CAP_CID_SIGNALING     0x0001  ; BR/EDR signalling
%define L2CAP_CID_CONNLESS      0x0002  ; connectionless data
%define L2CAP_CID_ATT           0x0004
%define L2CAP_CID_LE_SIGNALING  0x0005
%define L2CAP_CID_LE_SMP        0x0006
%define L2CAP_CID_BR_SMP        0x0007
%define L2CAP_CID_DYN_START     0x0040
%define L2CAP_CID_LE_DYN_END    0x007F  ; LE dynamic CIDs stop here

; ---- Signalling commands ----------------------------------------------------------
%define L2CAP_COMMAND_REJ       0x01
%define L2CAP_CONN_REQ          0x02
%define L2CAP_CONN_RSP          0x03
%define L2CAP_CONF_REQ          0x04
%define L2CAP_CONF_RSP          0x05
%define L2CAP_DISCONN_REQ       0x06
%define L2CAP_DISCONN_RSP       0x07
%define L2CAP_ECHO_REQ          0x08
%define L2CAP_ECHO_RSP          0x09
%define L2CAP_INFO_REQ          0x0A
%define L2CAP_INFO_RSP          0x0B
%define L2CAP_CONN_PARAM_REQ    0x12
%define L2CAP_CONN_PARAM_RSP    0x13
%define L2CAP_LE_CONN_REQ       0x14
%define L2CAP_LE_CONN_RSP       0x15
%define L2CAP_LE_CREDITS        0x16
%define L2CAP_ECRED_CONN_REQ    0x17
%define L2CAP_ECRED_CONN_RSP    0x18
%define L2CAP_ECRED_RECONF_REQ  0x19
%define L2CAP_ECRED_RECONF_RSP  0x1A

; Command Reject reasons
%define L2CAP_REJ_NOT_UNDERSTOOD 0x0000
%define L2CAP_REJ_MTU_EXCEEDED  0x0001
%define L2CAP_REJ_INVALID_CID   0x0002

; Connection Response results
%define L2CAP_CR_SUCCESS        0x0000
%define L2CAP_CR_PENDING        0x0001
%define L2CAP_CR_BAD_PSM        0x0002
%define L2CAP_CR_SEC_BLOCK      0x0003
%define L2CAP_CR_NO_MEM         0x0004
%define L2CAP_CR_INVALID_SCID   0x0006
%define L2CAP_CR_SCID_IN_USE    0x0007

; LE and enhanced Credit Based Connection Response results
%define L2CAP_LE_SUCCESS        0x0000
%define L2CAP_LE_BAD_PSM        0x0002
%define L2CAP_LE_NO_MEM         0x0004
%define L2CAP_LE_INVALID_SCID   0x0009
%define L2CAP_LE_SCID_IN_USE    0x000A
%define L2CAP_LE_UNACCEPT       0x000B
%define L2CAP_LE_INVALID        0x000C  ; enhanced: the whole request

; Credit Based Reconfigure Response results
%define L2CAP_RECONF_OK         0x0000
%define L2CAP_RECONF_MTU        0x0001  ; an MTU made smaller
%define L2CAP_RECONF_MPS        0x0002  ; an MPS made smaller, several channels
%define L2CAP_RECONF_CID        0x0003  ; a CID that is not a channel
%define L2CAP_RECONF_UNACCEPT   0x0004

; Configuration Response results
%define L2CAP_CONF_SUCCESS      0x0000
%define L2CAP_CONF_UNACCEPT     0x0001
%define L2CAP_CONF_REJECT       0x0002
%define L2CAP_CONF_UNKNOWN      0x0003

; configuration options
%define L2CAP_OPT_MTU           0x01
%define L2CAP_OPT_FLUSH_TO      0x02
%define L2CAP_OPT_QOS           0x03
%define L2CAP_OPT_RFC           0x04
%define L2CAP_OPT_FCS           0x05
%define L2CAP_OPT_EFS           0x06
%define L2CAP_OPT_EWS           0x07
%define L2CAP_OPT_HINT          0x80

; Information Request types
%define L2CAP_IT_CL_MTU         0x0001
%define L2CAP_IT_FEAT_MASK      0x0002
%define L2CAP_IT_FIXED_CHAN     0x0003

; extended features
%define L2CAP_FEAT_ERTM         (1 << 3)
%define L2CAP_FEAT_STREAMING    (1 << 4)
%define L2CAP_FEAT_FCS          (1 << 5)
%define L2CAP_FEAT_FIXED_CHAN   (1 << 7)
%define L2CAP_FEAT_ECRED        (1 << 10)

; ---- Modes ------------------------------------------------------------------------
%define L2CAP_MODE_BASIC        0x00
%define L2CAP_MODE_ERTM         0x03
%define L2CAP_MODE_STREAMING    0x04
%define L2CAP_MODE_LE_CREDITS   0x80    ; not on the air: LE credit-based
%define L2CAP_MODE_ECRED        0x81    ; ... enhanced credit-based

; ---- Our values -----------------------------------------------------------------------
%define L2CAP_MIN_MTU           48
%define L2CAP_DEFAULT_MTU       672     ; when the peer gives none
%define L2CAP_LOCAL_MTU         1017    ; what we take (a 1021-byte frame)
%define L2CAP_MAX_SERVERS       16
%define L2CAP_LE_MIN_MTU        23      ; LE credit based: MTU and MPS at least
%define L2CAP_ECRED_MIN_MTU     64      ; enhanced credit based: the same

; channel states
%define L2CAP_CLOSED            0
%define L2CAP_WAIT_INFO         1       ; outgoing, waiting to know the peer
%define L2CAP_WAIT_CONNECT      2       ; Connection Request sent
%define L2CAP_CONFIG            3
%define L2CAP_OPEN              4
%define L2CAP_WAIT_DISCONNECT   5

; config progress (l2cap_chan.cfg)
%define L2CAP_CFG_SENT          (1 << 0)    ; our request out
%define L2CAP_CFG_OUT_DONE      (1 << 1)    ; ... accepted
%define L2CAP_CFG_IN_DONE       (1 << 2)    ; theirs accepted by us

; events to l2cap_ops.event (ESI)
%define L2CAP_EV_OPEN           1
%define L2CAP_EV_CLOSED         2       ; EDX = why (0 asked, or a result)
%define L2CAP_EV_REFUSED        3       ; EDX = the Connection Response result
%define L2CAP_EV_RECONF         4       ; our reconfiguration answered, EDX = result

%define L2CAP_WHY_TIMEOUT       0x1000  ; the peer did not answer
%define L2CAP_WHY_LINK          0x1001  ; the link went down
%define L2CAP_WHY_PEER          0x1002  ; the peer closed it
%define L2CAP_WHY_MODE          0x1003  ; the peer cannot do the mode asked for

; ERTM and streaming: what we ask of the peer and the timeouts we give it
%define ERTM_TXWIN          10      ; frames we take before acknowledging
%define ERTM_MAXTX          3       ; what we ask the peer to retransmit at most
%define ERTM_MPS            1000    ; payload per frame we take
%define ERTM_RETRANS_MS     2000
%define ERTM_MONITOR_MS     12000

; credit-based channels: what we take per K-frame, the credits we give
%define CRED_MPS            247
%define CRED_CREDITS        10
%define CRED_MAX_CHANS      5       ; channels in one enhanced request

; ---- What a user of a channel provides ----------------------------------------------
struc l2cap_ops
    .recv:          resq 1          ; (chan, data, length): one SDU
    .event:         resq 1          ; (chan, ESI = L2CAP_EV_*, EDX = why)
endstruc

; ---- A channel ------------------------------------------------------------------------
struc l2cap_chan
    .conn:          resq 1          ; ubt_conn*
    .ops:           resq 1
    .user:          resq 1
    .deadline:      resq 1          ; ms: waiting for an answer until then
    .scid:          resw 1          ; ours
    .dcid:          resw 1          ; theirs
    .psm:           resw 1
    .imtu:          resw 1          ; what we take
    .omtu:          resw 1          ; what they take
    .state:         resb 1
    .mode:          resb 1          ; L2CAP_MODE_*
    .ident:         resb 1          ; of the request waiting for an answer
    .cfg:           resb 1          ; L2CAP_CFG_*
    .outgoing:      resb 1          ; we asked for it
    .pad:           resb 1          ; (configuration tries)
    ; what configuration agreed for ERTM and streaming
    .peer_txwin:    resb 1          ; the peer's window, MaxTransmit and
    .peer_maxtx:    resb 1          ; payload size (from its request)
    .peer_mps:      resw 1
    .retrans_ms:    resw 1          ; timeouts (from its response)
    .monitor_ms:    resw 1
    .cred:          resq 1          ; l2cap_cred*, credit-based modes
    .ertm:          resq 1          ; l2cap_ertm*, while open in those modes
endstruc

struc l2cap_srv
    .psm:           resw 1
    .mode:          resb 1
    .pad:           resb 5
    .ops:           resq 1
    .user:          resq 1
endstruc

%endif ; LIB_UBT_L2CAP_L2CAP_INC
