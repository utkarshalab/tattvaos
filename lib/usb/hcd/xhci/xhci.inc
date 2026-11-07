; =============================================================================
; Utkarsha OS — lib/usb/hcd/xhci/xhci.inc — xHCI registers, TRBs, records
; =============================================================================
; Names follow the xHCI 1.2 specification's register and field names.
; =============================================================================

%ifndef LIB_USB_HCD_XHCI_XHCI_INC
%define LIB_USB_HCD_XHCI_XHCI_INC

; ---- Capability registers (from the BAR) ------------------------------------
%define XHCI_CAPLENGTH      0x00    ; byte; HCIVERSION word at 0x02
%define XHCI_HCSPARAMS1     0x04    ; MaxSlots 0-7, MaxIntrs 8-18, MaxPorts 24-31
%define XHCI_HCSPARAMS2     0x08    ; ERST Max 4-7, scratchpads hi 21-25, lo 27-31
%define XHCI_HCSPARAMS3     0x0C
%define XHCI_HCCPARAMS1     0x10    ; AC64 0, CSZ 2, xECP 16-31 (dwords)
%define XHCI_DBOFF          0x14
%define XHCI_RTSOFF         0x18

; ---- Operational registers (BAR + CAPLENGTH) --------------------------------
%define XHCI_USBCMD         0x00
%define XHCI_USBSTS         0x04
%define XHCI_PAGESIZE       0x08
%define XHCI_DNCTRL         0x14
%define XHCI_CRCR           0x18
%define XHCI_DCBAAP         0x30
%define XHCI_CONFIG         0x38
%define XHCI_PORTSC         0x400   ; + 0x10 * (port - 1)

%define CMD_RS              (1 << 0)
%define CMD_HCRST           (1 << 1)
%define CMD_INTE            (1 << 2)
%define CMD_HSEE            (1 << 3)

%define STS_HCH             (1 << 0)
%define STS_HSE             (1 << 2)
%define STS_EINT            (1 << 3)
%define STS_PCD             (1 << 4)
%define STS_CNR             (1 << 11)
%define STS_HCE             (1 << 12)

%define CRCR_RCS            (1 << 0)
%define CRCR_CA             (1 << 2)
%define CRCR_CRR            (1 << 3)

; PORTSC
%define PORT_CCS            (1 << 0)
%define PORT_PED            (1 << 1)    ; write 1: disable
%define PORT_OCA            (1 << 3)
%define PORT_PR             (1 << 4)
%define PORT_PLS_SHIFT      5
%define PORT_PP             (1 << 9)
%define PORT_SPEED_SHIFT    10
%define PORT_LWS            (1 << 16)
%define PORT_CSC            (1 << 17)
%define PORT_PEC            (1 << 18)
%define PORT_WRC            (1 << 19)
%define PORT_OCC            (1 << 20)
%define PORT_PRC            (1 << 21)
%define PORT_PLC            (1 << 22)
%define PORT_CEC            (1 << 23)
%define PORT_WPR            0x80000000
%define PORT_CHANGES        (PORT_CSC | PORT_PEC | PORT_WRC | PORT_OCC | PORT_PRC | PORT_PLC | PORT_CEC)
; bits written back as read: port power, indicators, wake enables
%define PORT_PRESERVE       (PORT_PP | (3 << 14) | (7 << 25))

; ---- Runtime registers (BAR + RTSOFF) ---------------------------------------
%define XHCI_IR0            0x20    ; interrupter 0; + 0x20 each
%define IR_IMAN             0x00    ; IP 0 (write 1 to clear), IE 1
%define IR_IMOD             0x04
%define IR_ERSTSZ           0x08
%define IR_ERSTBA           0x10
%define IR_ERDP             0x18    ; EHB 3 (write 1 to clear)
%define IMAN_IP             (1 << 0)
%define IMAN_IE             (1 << 1)
%define ERDP_EHB            (1 << 3)

; ---- Extended capabilities --------------------------------------------------
%define XECP_LEGACY         1       ; USBLEGSUP: BIOS owned 16, OS owned 24
%define XECP_PROTOCOL       2       ; supported protocol
%define LEGSUP_BIOS         (1 << 16)
%define LEGSUP_OS           (1 << 24)

; ---- TRBs ---------------------------------------------------------------------
%define TRB_CYCLE           (1 << 0)
%define TRB_TC              (1 << 1)    ; link: toggle cycle
%define TRB_ENT             (1 << 1)
%define TRB_ISP             (1 << 2)
%define TRB_CH              (1 << 4)
%define TRB_IOC             (1 << 5)
%define TRB_IDT             (1 << 6)
%define TRB_DIR_IN          (1 << 16)
%define TRB_TYPE_SHIFT      10

%define TRB_NORMAL          1
%define TRB_SETUP           2
%define TRB_DATA            3
%define TRB_STATUS          4
%define TRB_ISOCH           5
%define TRB_LINK            6
%define TRB_NOOP            8
%define TRB_ENABLE_SLOT     9
%define TRB_DISABLE_SLOT    10
%define TRB_ADDRESS_DEVICE  11
%define TRB_CONFIGURE_EP    12
%define TRB_EVALUATE_CTX    13
%define TRB_RESET_EP        14
%define TRB_STOP_EP         15
%define TRB_SET_TR_DEQ      16
%define TRB_RESET_DEVICE    17
%define TRB_NOOP_CMD        23
%define TRB_EV_TRANSFER     32
%define TRB_EV_COMMAND      33
%define TRB_EV_PORT         34
%define TRB_EV_HC           37

%define TRT_NONE            0
%define TRT_OUT             2
%define TRT_IN              3

; completion codes
%define CC_SUCCESS          1
%define CC_DATA_BUFFER      2
%define CC_BABBLE           3
%define CC_TRANSACTION      4
%define CC_TRB              5
%define CC_STALL            6
%define CC_RESOURCE         7
%define CC_BANDWIDTH        8
%define CC_NO_SLOTS         9
%define CC_SHORT_PACKET     13
%define CC_CONTEXT_STATE    19
%define CC_STOPPED          26

; ---- Contexts (32-byte entries; 64 with CSZ, handled through ctx_size) -----
; slot context dword 0: route 0-19, speed 20-23, MTT 25, hub 26, entries 27-31
; dword 1: root hub port 16-23; dword 2: TT hub slot 0-7, TT port 8-15
; dword 3: address 0-7, slot state 27-31
; endpoint context dword 0: state 0-2, interval 16-23; dword 1: CErr 1-2,
; type 3-5, max burst 8-15, max packet 16-31; dwords 2-3: dequeue | DCS;
; dword 4: average TRB length 0-15, max ESIT payload 16-31
%define EP_TYPE_ISOC_OUT    1
%define EP_TYPE_BULK_OUT    2
%define EP_TYPE_INT_OUT     3
%define EP_TYPE_CONTROL     4
%define EP_TYPE_ISOC_IN     5
%define EP_TYPE_BULK_IN     6
%define EP_TYPE_INT_IN      7

; ---- Driver records -----------------------------------------------------------
%define XHCI_MAX_HC         4
%define XHCI_MAX_SLOTS      64      ; slots enabled at most
%define XHCI_RING_TRBS      64      ; per transfer ring (one is the link)
%define XHCI_CMD_TRBS       64
%define XHCI_EVT_TRBS       256
%define XHCI_WAIT_TRIES     2000    ; polls of 50 µs: 100 ms

struc xhci_ring
    .trbs:          resq 1
    .enq:           resd 1
    .cycle:         resd 1
    .size:          resd 1          ; TRBs, the link TRB included
    .pad:           resd 1
    .last:          resq 1          ; the last TRB put (of a whole TD)
endstruc

struc xhci_ep
    .ring:          resq 1
    .xfer:          resq 1          ; usb_xfer* waiting on it (async)
    .last:          resq 1          ; the TRB whose event ends the TD
    .code:          resd 1          ; completion code of the TD
    .residual:      resd 1          ; bytes not moved
    .done:          resd 1
    .type:          resd 1          ; EP_TYPE_*
endstruc                            ; 40 bytes

struc xhci_slot
    .out_ctx:       resq 1
    .in_ctx:        resq 1
    .dev:           resq 1          ; usb_device*
    .port:          resd 1
    .speed:         resd 1
    .hub:           resd 1          ; bit 3 a hub, 2 multi-TT, 0-1 TT think time
    .hub_ports:     resd 1
    .eps:           resb 32 * xhci_ep_size  ; by device context index
endstruc

struc xhci_hc
    .base:          resq 1
    .op:            resq 1
    .rt:            resq 1
    .db:            resq 1
    .max_slots:     resd 1          ; enabled
    .max_ports:     resd 1
    .max_intrs:     resd 1
    .ctx_size:      resd 1          ; 32 or 64
    .scratch:       resd 1          ; scratchpad buffers
    .version:       resd 1
    .dcbaa:         resq 1
    .cmd:           resq 1          ; xhci_ring*
    .evt:           resq 1          ; event ring TRBs
    .evt_deq:       resd 1
    .evt_cycle:     resd 1
    .erst:          resq 1
    .cmd_last:      resq 1          ; the command waited for
    .cmd_code:      resd 1
    .cmd_slot:      resd 1
    .cmd_done:      resd 1
    .hc_events:     resd 1          ; host controller events seen
    .handoff:       resd 1          ; 1 firmware let go, 2 it had to be taken
    .ac64:          resd 1          ; 64-bit addressing
    .port_change:   resb 32         ; bitmap: a port status change event came
    .port_major:    resb 256        ; by port: 2 or 3, from the protocol caps
    .slots:         resq 256        ; xhci_slot* by slot ID
endstruc

%endif ; LIB_USB_HCD_XHCI_XHCI_INC
