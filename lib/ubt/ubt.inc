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

; ---- Events -------------------------------------------------------------------
%define HCI_EV_DISCONNECT       0x05
%define HCI_EV_CMD_COMPLETE     0x0E
%define HCI_EV_CMD_STATUS       0x0F
%define HCI_EV_HW_ERROR         0x10
%define HCI_EV_NUM_COMPLETED    0x13
%define HCI_EV_LE_META          0x3E

; LMP features: byte 4 bit 6 "LE supported (controller)"
%define HCI_FEAT_LE_BYTE        4
%define HCI_FEAT_LE_BIT         6

; ---- Adapters -------------------------------------------------------------------
%define UBT_MAX_ADAPTERS    4
%define UBT_EVENT_MAX       (2 + 255)
%define UBT_ACL_MAX         (4 + 1021)  ; header and the largest BR/EDR payload
%define UBT_CMD_TIMEOUT_US  1000000

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
endstruc

%endif ; LIB_UBT_UBT_INC
