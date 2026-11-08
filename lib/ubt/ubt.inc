; =============================================================================
; Utkarsha OS — lib/ubt/ubt.inc — Bluetooth: HCI and the adapter record
; =============================================================================
; Names follow the Bluetooth Core specification, volume 4 part E.
; =============================================================================

%ifndef LIB_UBT_UBT_INC
%define LIB_UBT_UBT_INC

; ---- Errors (negative in EAX; HCI status codes are positive) ----------------
%define UBT_ETIMEOUT        1       ; no Command Complete or Status in time
%define UBT_EIO             2       ; the transport failed
%define UBT_EBUSY           3
%define UBT_EDOWN           4       ; the adapter is not up
%define UBT_ENOMEM          5

; ---- HCI packet types (H4 numbering, used for the hooks) --------------------
%define HCI_COMMAND_PKT     1
%define HCI_ACL_PKT         2
%define HCI_SCO_PKT         3
%define HCI_EVENT_PKT       4
%define HCI_ISO_PKT         5

; ---- Commands (OGF << 10 | OCF) ---------------------------------------------
%define HCI_SET_EVENT_MASK      0x0C01
%define HCI_RESET               0x0C03
%define HCI_READ_LOCAL_VERSION  0x1001
%define HCI_READ_LOCAL_COMMANDS 0x1002
%define HCI_READ_LOCAL_FEATURES 0x1003
%define HCI_READ_BUFFER_SIZE    0x1005
%define HCI_READ_BD_ADDR        0x1009
%define HCI_LE_SET_EVENT_MASK   0x2001
%define HCI_LE_READ_BUFFER_SIZE 0x2002
%define HCI_CREATE_CONN         0x0405
%define HCI_DISCONNECT          0x0406
%define HCI_ACCEPT_CONN         0x0409
%define HCI_LE_CREATE_CONN      0x200D
%define HCI_LE_CONN_UPDATE      0x2013
; discovery and names
%define HCI_INQUIRY             0x0401
%define HCI_INQUIRY_CANCEL      0x0402
%define HCI_REMOTE_NAME_REQ     0x0419
%define HCI_WRITE_LOCAL_NAME    0x0C13
%define HCI_WRITE_SCAN_ENABLE   0x0C1A
%define HCI_WRITE_CLASS         0x0C24
%define HCI_WRITE_INQUIRY_MODE  0x0C45
%define HCI_WRITE_EIR           0x0C52
; LE advertising and scanning
%define HCI_LE_SET_RANDOM_ADDR  0x2005
%define HCI_LE_SET_ADV_PARAMS   0x2006
%define HCI_LE_SET_ADV_DATA     0x2008
%define HCI_LE_SET_SCAN_RSP     0x2009
%define HCI_LE_SET_ADV_ENABLE   0x200A
%define HCI_LE_SET_SCAN_PARAMS  0x200B
%define HCI_LE_SET_SCAN_ENABLE  0x200C
; security
%define HCI_LINK_KEY_REPLY      0x040B
%define HCI_LINK_KEY_NEG_REPLY  0x040C
%define HCI_PIN_REPLY           0x040D
%define HCI_PIN_NEG_REPLY       0x040E
%define HCI_AUTH_REQUESTED      0x0411
%define HCI_SET_CONN_ENCRYPT    0x0413
%define HCI_IO_CAP_REPLY        0x042B
%define HCI_USER_CONFIRM_REPLY  0x042C
%define HCI_USER_CONFIRM_NEG    0x042D
%define HCI_USER_PASSKEY_REPLY  0x042E
%define HCI_USER_PASSKEY_NEG    0x042F
%define HCI_IO_CAP_NEG_REPLY    0x0434
%define HCI_WRITE_SSP_MODE      0x0C56
%define HCI_WRITE_SC_SUPPORT    0x0C7A
%define HCI_LE_START_ENC        0x2019
%define HCI_LE_LTK_REPLY        0x201A
%define HCI_LE_LTK_NEG_REPLY    0x201B

; ---- Events -------------------------------------------------------------------
%define HCI_EV_INQUIRY_DONE     0x01
%define HCI_EV_INQUIRY_RESULT   0x02
%define HCI_EV_CONN_COMPLETE    0x03
%define HCI_EV_CONN_REQUEST     0x04
%define HCI_EV_DISCONNECT       0x05
%define HCI_EV_AUTH_COMPLETE    0x06
%define HCI_EV_REMOTE_NAME      0x07
%define HCI_EV_ENCRYPT_CHANGE   0x08
%define HCI_EV_CMD_COMPLETE     0x0E
%define HCI_EV_CMD_STATUS       0x0F
%define HCI_EV_HW_ERROR         0x10
%define HCI_EV_NUM_COMPLETED    0x13
%define HCI_EV_PIN_REQUEST      0x16
%define HCI_EV_LINK_KEY_REQUEST 0x17
%define HCI_EV_LINK_KEY_NOTIFY  0x18
%define HCI_EV_INQUIRY_RSSI     0x22
%define HCI_EV_INQUIRY_EXT      0x2F
%define HCI_EV_KEY_REFRESH      0x30
%define HCI_EV_IO_CAP_REQUEST   0x31
%define HCI_EV_IO_CAP_RESPONSE  0x32
%define HCI_EV_USER_CONFIRM     0x33
%define HCI_EV_USER_PASSKEY     0x34
%define HCI_EV_SSP_COMPLETE     0x36
%define HCI_EV_PASSKEY_NOTIFY   0x3B
%define HCI_EV_LE_META          0x3E
%define HCI_LE_EV_CONN_COMPLETE 0x01    ; LE meta subevents
%define HCI_LE_EV_ENH_CONN_COMPLETE 0x0A
%define HCI_LE_EV_ADV_REPORT    0x02
%define HCI_LE_EV_LTK_REQUEST   0x05
%define HCI_LE_EV_EXT_ADV_REPORT 0x0D

; ---- What the GAP hook hears (adapter.gap_fn, ESI) ------------------------------
%define UBT_GAP_FOUND       1       ; RDX = ubt_found
%define UBT_GAP_INQUIRY_DONE 2      ; RDX = 0
%define UBT_GAP_NAME        3       ; RDX = ubt_name
%define UBT_GAP_CONFIRM     4       ; RDX = ubt_pairing: compare its number
%define UBT_GAP_PASSKEY     5       ; ... enter the passkey the peer shows
%define UBT_GAP_SHOW        6       ; ... show this passkey
%define UBT_GAP_PIN         7       ; ... a legacy PIN is wanted
%define UBT_GAP_PAIRED      8       ; ... done: its status (0 bonded)
%define UBT_GAP_JUST_WORKS  9       ; ... nothing to compare: allow it?

; ubt_found.kind
%define UBT_FOUND_LE        1       ; an advertisement
%define UBT_FOUND_LE_RSP    2       ; a scan response
%define UBT_FOUND_BR        3       ; an inquiry response

; ACL packet boundary flags (bits 12-13 of the handle word)
%define ACL_PB_CONT             1       ; a continuing fragment
%define ACL_PB_START_AUTO       2       ; BR/EDR: first, automatically flushable
%define ACL_PB_START_NOFLUSH    0       ; LE (and BR/EDR non-flushable): first

; LMP features: byte 4 bit 6 "LE supported (controller)"
%define HCI_FEAT_LE_BYTE        4
%define HCI_FEAT_LE_BIT         6

; ---- Adapters -------------------------------------------------------------------
%define UBT_MAX_ADAPTERS    4
%define UBT_EVENT_MAX       (2 + 255)
%define UBT_ACL_MAX         (4 + 1021)  ; header and the largest BR/EDR payload
%define UBT_CMD_TIMEOUT_US  1000000
%define UBT_MAX_CONNS       8       ; ACL links per adapter
%define UBT_CMDQ            8       ; commands sent without waiting, queued
%define UBT_CMDQ_SIZE       80      ; bytes each (opcode, length, parameters)
%define UBT_L2CAP_RX_MAX    4096    ; the largest L2CAP frame put back together
%define UBT_MAX_CHANS       32      ; L2CAP channels per adapter

; link types
%define UBT_LINK_BREDR      0
%define UBT_LINK_LE         1

; ubt_adapter.conn_fn events (ESI)
%define UBT_CONN_UP         1
%define UBT_CONN_DOWN       2
%define UBT_CONN_FAILED     3       ; an outgoing connection did not come up

; adapter states
%define UBT_DOWN            0
%define UBT_UP              1
%define UBT_NEED_FIRMWARE   2       ; a controller that runs nothing until its
                                    ; vendor's patch is loaded (MediaTek)
%define UBT_FAILED          3       ; bring-up did not complete
%define UBT_GONE            4

struc ubt_adapter
    .dev:           resq 1          ; usb_device*
    .index:         resd 1          ; hciN
    .state:         resd 1          ; UBT_*
    .iface:         resd 1
    .credits:       resd 1          ; commands the controller will take
    .failed_op:     resd 1          ; the bring-up command that failed
    .failed_status: resd 1          ; ... and what it returned
    ; the command being waited for
    .wait_op:       resd 1
    .wait_done:     resd 1
    .wait_status:   resd 1          ; its HCI status
    .wait_len:      resd 1          ; return parameters kept
    .wait_buf:      resb 72         ; ... (after the status byte)
    ; what the controller is
    .hci_version:   resb 1
    .lmp_version:   resb 1
    .hci_revision:  resw 1
    .manufacturer:  resw 1
    .lmp_subversion: resw 1
    .bdaddr:        resb 6
    .le:            resb 1          ; LE supported
    .pad0:          resb 1
    .features:      resb 8
    .commands:      resb 64
    .acl_mtu:       resw 1
    .sco_mtu:       resb 1
    .pad1:          resb 1
    .acl_count:     resw 1
    .sco_count:     resw 1
    .le_mtu:        resw 1
    .le_count:      resb 1
    .pad2:          resb 1
    ; counters
    .events:        resd 1
    .acl_rx:        resd 1
    .acl_tx:        resd 1
    .errors:        resd 1
    .hw_errors:     resd 1
    ; upper layers
    .event_fn:      resq 1          ; (adapter, event, length) for events
                                    ; not answering a waited-for command
    .acl_fn:        resq 1          ; (adapter, ACL packet, length)
    .conn_fn:       resq 1          ; (adapter, ESI = UBT_CONN_*, RDX = conn)
    .fixed_fn:      resq 1          ; (conn, ESI = fixed CID, RDX = data,
                                    ;  ECX = length): ATT, SMP, connectionless
    ; the transport: how commands and ACL go out, and events come in while
    ; a command is waited for
    .tr_cmd:        resq 1          ; (adapter, bytes, length) → EAX < 0 failed
    .tr_acl:        resq 1          ; (adapter, packet, length) → 0, -UBT_EBUSY
    .tr_poll:       resq 1          ; (adapter)
    .tr_ctx:        resq 1          ; the transport's own
    ; commands sent without waiting
    .cmdq_head:     resd 1
    .cmdq_tail:     resd 1
    .cmdq:          resb UBT_CMDQ * UBT_CMDQ_SIZE
    ; ACL links
    .conns:         resq UBT_MAX_CONNS
    .acl_free:      resd 1          ; controller buffers free: BR/EDR
    .le_free:       resd 1          ; ... LE (shared with BR/EDR when le_count 0)
    .connecting:    resb 6          ; the address of an outgoing BR/EDR
    .connecting_on: resb 1          ; connection, while it is made
    .pad4:          resb 1
    ; L2CAP
    .chans:         resq UBT_MAX_CHANS
    .rtx_ms:        resd 1          ; signalling response timeout
    .in_event:      resd 1          ; handling an event: queued commands wait
    ; the transport (USB)
    .ev_xfer:       resb usb_xfer_size
    .ev_pkt:        resb 64         ; one interrupt packet
    .ev_buf:        resb UBT_EVENT_MAX + 1
    .pad3:          resb 2
    .ev_len:        resd 1          ; bytes of the event gathered so far
    .acl_xfer:      resb usb_xfer_size
    .acl_buf:       resb UBT_ACL_MAX + 3
    .acl_len:       resd 1
    .out_xfer:      resb usb_xfer_size
    .out_buf:       resb UBT_ACL_MAX + 3
    .out_busy:      resd 1
    .ev_ep:         resb 1
    .acl_in_ep:     resb 1
    .acl_out_ep:    resb 1
    .flags:         resb 1          ; 1: the event endpoint needs recovery
                                    ; 2: the ACL endpoint does
    alignb 8
    ; GAP and security
    .gap_fn:        resq 1          ; (adapter, ESI = UBT_GAP_*, RDX = record)
    .io_cap:        resb 1          ; ours: 0 display only, 1 display yes/no,
                                    ; 2 keyboard only, 3 none, 4 keyboard+display
    .bondable:      resb 1
    .sc_only:       resb 1          ; Secure Connections only
    .legacy:        resb 1          ; never offer Secure Connections (as an
                                    ; older device: for testing against)
    .pad5:          resb 4
    .gatt:          resq 1          ; the GATT database served on this adapter
endstruc

; ---- An ACL link ----------------------------------------------------------------
struc ubt_conn
    .adapter:       resq 1
    .handle:        resw 1
    .type:          resb 1          ; UBT_LINK_*
    .role:          resb 1          ; 0 central, 1 peripheral
    .peer:          resb 6
    .peer_type:     resb 1          ; LE address type
    .state:         resb 1          ; 1 up, 2 going
    .pad0:          resd 1
    .tx_head:       resq 1          ; ubt_txb queue
    .tx_tail:       resq 1
    .in_flight:     resd 1          ; packets the controller has of ours
    .rx_len:        resd 1          ; bytes of the frame put together so far
    .rx_need:       resd 1          ; ... of how many
    .ident:         resb 1          ; the next signalling identifier
    .info_state:    resb 1          ; L2CAP: 0 not asked, 1 asked, 2 known
    .info_ident:    resb 1
    .pad:           resb 1
    .ext_features:  resd 1          ; the peer's L2CAP extended features
    .pad2:          resd 1
    .fixed_chans:   resq 1          ; ... and fixed channels
    .rx_buf:        resq 1          ; UBT_L2CAP_RX_MAX bytes, while needed
    .user:          resq 1
    ; upper layers
    .att:           resq 1          ; ATT bearer state
    .smp:           resq 1          ; SMP pairing in progress
    .pair:          resq 1          ; BR/EDR pairing in progress
    .rfcomm:        resq 1          ; RFCOMM session
    .sec:           resb 1          ; 0 open, 1 encrypted, 2 + authenticated
                                    ; (MITM), 3 + Secure Connections
    .key_size:      resb 1
    .pad3:          resb 6
endstruc

; ---- A device heard (UBT_GAP_FOUND) -----------------------------------------------
struc ubt_found
    .kind:          resb 1          ; UBT_FOUND_*
    .addr_type:     resb 1          ; LE: 0 public, 1 random
    .event_type:    resw 1          ; LE: the report's type or properties
    .addr:          resb 6
    .rssi:          resb 1          ; dBm (127: not known)
    .pad:           resb 1
    .class:         resd 1          ; BR/EDR: class of device
    .data_len:      resd 1          ; advertising data or EIR
    .pad3:          resd 1
    .data:          resq 1
    .tx_power:      resb 1          ; extended reports (127: not known)
    .phy:           resb 1
    .sid:           resb 1
    .pad2:          resb 5
endstruc

; ---- A remote name (UBT_GAP_NAME) --------------------------------------------------
struc ubt_name
    .addr:          resb 6
    .status:        resb 1
    .pad:           resb 1
    .len:           resd 1
    .pad2:          resd 1
    .name:          resq 1
endstruc

; ---- One ACL fragment waiting for a controller buffer --------------------------------
struc ubt_txb
    .next:          resq 1
    .len:           resd 1          ; the ACL packet's length (header included)
    .size:          resd 1          ; the block's size, for giving it back
    .data:                          ; the packet
endstruc

%endif ; LIB_UBT_UBT_INC
