; =============================================================================
; Utkarsha OS — lib/usb/usb.inc — public structures and constants
; =============================================================================
; Descriptor types and fields (USB 2.0 chapter 9, USB 3.2 chapter 9), the
; parsed forms core/desc.asm fills, and the device and transfer records the
; core and host controller drivers share (ROADMAP.md §5).
; =============================================================================

%ifndef LIB_USB_USB_INC
%define LIB_USB_USB_INC

; ---- Errors (returned negated) ----------------------------------------------
%define USB_EDESC           1       ; a descriptor is malformed
%define USB_ETRUNC          2       ; wTotalLength is more than was read
%define USB_ETOOMANY        3       ; more interfaces or endpoints than kept
%define USB_ESTALL          4       ; the endpoint stalled
%define USB_ETIMEOUT        5
%define USB_EXACT           6       ; transaction error, babble, CRC
%define USB_ENODEV          7       ; the device went away
%define USB_ENOMEM          8
%define USB_EHC             9       ; the host controller failed
%define USB_EBUSY           10      ; a transfer is already on the endpoint
%define USB_EINVAL          11

; ---- Descriptor types -------------------------------------------------------
%define USB_DT_DEVICE           0x01
%define USB_DT_CONFIG           0x02
%define USB_DT_STRING           0x03
%define USB_DT_INTERFACE        0x04
%define USB_DT_ENDPOINT         0x05
%define USB_DT_QUALIFIER        0x06
%define USB_DT_OTHER_SPEED      0x07
%define USB_DT_OTG              0x09
%define USB_DT_DEBUG            0x0A
%define USB_DT_IAD              0x0B
%define USB_DT_BOS              0x0F
%define USB_DT_DEV_CAP          0x10
%define USB_DT_HID              0x21
%define USB_DT_HID_REPORT       0x22
%define USB_DT_CS_INTERFACE     0x24
%define USB_DT_CS_ENDPOINT      0x25
%define USB_DT_HUB              0x29
%define USB_DT_SS_HUB           0x2A
%define USB_DT_SS_EP_COMP       0x30
%define USB_DT_SSP_ISOC_COMP    0x31

; BOS device capability types
%define USB_CAP_USB2_EXT        0x02
%define USB_CAP_SS              0x03
%define USB_CAP_CONTAINER_ID    0x04
%define USB_CAP_SSP             0x0A

; ---- Standard requests ------------------------------------------------------
%define USB_REQ_GET_STATUS      0x00
%define USB_REQ_CLEAR_FEATURE   0x01
%define USB_REQ_SET_FEATURE     0x03
%define USB_REQ_SET_ADDRESS     0x05
%define USB_REQ_GET_DESCRIPTOR  0x06
%define USB_REQ_SET_DESCRIPTOR  0x07
%define USB_REQ_GET_CONFIG      0x08
%define USB_REQ_SET_CONFIG      0x09
%define USB_REQ_GET_INTERFACE   0x0A
%define USB_REQ_SET_INTERFACE   0x0B
%define USB_REQ_SET_SEL         0x30
%define USB_REQ_SET_ISOCH_DELAY 0x31

; bmRequestType
%define USB_DIR_IN              0x80
%define USB_TYPE_STANDARD       0x00
%define USB_TYPE_CLASS          0x20
%define USB_TYPE_VENDOR         0x40
%define USB_RECIP_DEVICE        0x00
%define USB_RECIP_INTERFACE     0x01
%define USB_RECIP_ENDPOINT      0x02

; features
%define USB_FEAT_ENDPOINT_HALT  0
%define USB_FEAT_REMOTE_WAKEUP  1

; ---- Speeds (the xHCI port speed IDs of the default table) -----------------
%define USB_SPEED_FULL          1   ; 12 Mbit/s
%define USB_SPEED_LOW           2   ; 1.5 Mbit/s
%define USB_SPEED_HIGH          3   ; 480 Mbit/s
%define USB_SPEED_SUPER         4   ; 5 Gbit/s
%define USB_SPEED_SUPER_PLUS    5   ; 10 Gbit/s (Gen 2x1)
%define USB_SPEED_SUPER_PLUS_X2 6   ; 20 Gbit/s (Gen 2x2)

; ---- Endpoint attributes ------------------------------------------------------
%define USB_EP_CONTROL          0
%define USB_EP_ISOC             1
%define USB_EP_BULK             2
%define USB_EP_INTERRUPT        3
%define USB_EP_TYPE_MASK        3
%define USB_EP_DIR_IN           0x80
%define USB_EP_NUM_MASK         0x0F

; ---- Classes ----------------------------------------------------------------
%define USB_CLASS_PER_IFACE     0x00
%define USB_CLASS_AUDIO         0x01
%define USB_CLASS_CDC           0x02
%define USB_CLASS_HID           0x03
%define USB_CLASS_PHYSICAL      0x05
%define USB_CLASS_IMAGE         0x06
%define USB_CLASS_PRINTER       0x07
%define USB_CLASS_STORAGE       0x08
%define USB_CLASS_HUB           0x09
%define USB_CLASS_CDC_DATA      0x0A
%define USB_CLASS_CCID          0x0B
%define USB_CLASS_VIDEO         0x0E
%define USB_CLASS_BILLBOARD     0x11
%define USB_CLASS_TYPEC_BRIDGE  0x12
%define USB_CLASS_WIRELESS      0xE0    ; Bluetooth
%define USB_CLASS_MISC          0xEF
%define USB_CLASS_APP           0xFE    ; DFU, IrDA, USBTMC
%define USB_CLASS_VENDOR        0xFF

; ---- Device descriptor (raw, 18 bytes) --------------------------------------
struc usb_device_desc
    .bLength:           resb 1
    .bDescriptorType:   resb 1
    .bcdUSB:            resw 1
    .bDeviceClass:      resb 1
    .bDeviceSubClass:   resb 1
    .bDeviceProtocol:   resb 1
    .bMaxPacketSize0:   resb 1
    .idVendor:          resw 1
    .idProduct:         resw 1
    .bcdDevice:         resw 1
    .iManufacturer:     resb 1
    .iProduct:          resb 1
    .iSerialNumber:     resb 1
    .bNumConfigurations: resb 1
endstruc

; ---- Setup packet (8 bytes) -------------------------------------------------
struc usb_setup
    .bmRequestType:     resb 1
    .bRequest:          resb 1
    .wValue:            resw 1
    .wIndex:            resw 1
    .wLength:           resw 1
endstruc

; ---- A configuration, parsed (core/desc.asm usb_config_parse) ---------------
%define USB_MAX_IFACES      32      ; interfaces and their alternate settings
%define USB_MAX_EPS         64
%define USB_MAX_IADS        8
%define USB_NO_FUNC         0xFF    ; usb_iface.func: not in an association

; usb_config.warn: odd but usable
%define USB_WARN_EP_ORPHAN  (1 << 0)    ; an endpoint before any interface
%define USB_WARN_EP_COUNT   (1 << 1)    ; bNumEndpoints differs from found
%define USB_WARN_IFACES     (1 << 2)    ; bNumInterfaces differs from found
%define USB_WARN_IADS       (1 << 3)    ; more associations than kept

struc usb_iface
    .number:        resb 1
    .alt:           resb 1
    .class:         resb 1
    .subclass:      resb 1
    .protocol:      resb 1
    .string:        resb 1
    .num_ep:        resb 1          ; bNumEndpoints
    .ep_count:      resb 1          ; endpoints found
    .first_ep:      resb 1          ; index in usb_config.eps
    .func:          resb 1          ; index in usb_config.iads, or USB_NO_FUNC
    .hid_country:   resb 1
    .hid_count:     resb 1          ; class descriptors the HID one names
    .hid_report_len: resw 1         ; the report descriptor's length, or 0
    .body_off:      resw 1          ; what follows the interface descriptor,
    .body_len:      resw 1          ; to the next one: class descriptors and
    .pad:           resb 6          ; endpoints, for class drivers to walk
endstruc                            ; 24 bytes

struc usb_ep
    .address:       resb 1          ; number, and USB_EP_DIR_IN
    .attributes:    resb 1          ; type in bits 0-1; isochronous sync and
    .max_packet:    resw 1          ; usage; high-speed extra transactions
    .interval:      resb 1          ; in bits 11-12 of max_packet
    .iface:         resb 1          ; index in usb_config.ifaces
    .ss_burst:      resb 1          ; SuperSpeed companion: bMaxBurst,
    .ss_attr:       resb 1          ; bmAttributes (streams, Mult)
    .ss_bpi:        resd 1          ; bytes per interval (SSP isochronous: 32 bits)
    .refresh:       resb 1          ; audio class 1 endpoints (9 bytes)
    .synch:         resb 1
    .pad:           resw 1
endstruc                            ; 16 bytes

struc usb_iad
    .first:         resb 1
    .count:         resb 1
    .class:         resb 1
    .subclass:      resb 1
    .protocol:      resb 1
    .string:        resb 1
    .pad:           resw 1
endstruc                            ; 8 bytes

struc usb_config
    .total:         resw 1          ; wTotalLength
    .num_ifaces:    resb 1          ; bNumInterfaces
    .value:         resb 1          ; bConfigurationValue
    .string:        resb 1
    .attributes:    resb 1          ; bit 6 self-powered, bit 5 remote wakeup
    .max_power:     resb 1          ; 2 mA units (8 mA at SuperSpeed)
    .iface_count:   resb 1
    .ep_count:      resb 1
    .iad_count:     resb 1
    .other:         resb 1          ; descriptors not parsed here (class ones)
    .warn:          resb 1          ; USB_WARN_*
    .pad:           resd 1
    .ifaces:        resb USB_MAX_IFACES * usb_iface_size
    .eps:           resb USB_MAX_EPS * usb_ep_size
    .iads:          resb USB_MAX_IADS * usb_iad_size
endstruc

; ---- BOS, parsed (usb_bos_parse) --------------------------------------------
struc usb_bos
    .caps:          resb 1          ; capabilities found
    .lpm:           resb 1          ; USB 2 link power management
    .besl:          resb 1          ; ... with BESL values
    .ss:            resb 1          ; a SuperSpeed capability
    .ss_speeds:     resw 1          ; wSpeedsSupported
    .ss_func:       resb 1          ; bFunctionalitySupport (lowest speed)
    .u1_lat:        resb 1          ; µs
    .u2_lat:        resw 1          ; µs
    .ssp:           resb 1          ; a SuperSpeedPlus capability
    .has_container: resb 1
    .ssp_max_mbps:  resd 1          ; the fastest sublink, Mbit/s
    .container:     resb 16         ; container ID
endstruc                            ; 32 bytes

; ---- Devices and transfers (the core and host controller drivers) -----------
%define USB_MAX_DEVICES     127

struc usb_device
    .hc:            resq 1          ; the host controller (usb_hc*)
    .parent:        resq 1          ; the hub it hangs off, or 0 (root port)
    .slot:          resb 1          ; xHCI slot ID
    .port:          resb 1          ; port on the parent (1-based)
    .root_port:     resb 1
    .speed:         resb 1          ; USB_SPEED_*
    .route:         resd 1          ; route string (four bits a tier)
    .depth:         resb 1          ; hubs above it
    .address:       resb 1          ; the bus address
    .state:         resb 1          ; USB_DEV_*
    .config_value:  resb 1          ; the configuration set, or 0
    .max_packet0:   resw 1          ; endpoint 0's packet size
    .flags:         resw 1          ; USB_DEVF_*
    .desc:          resb usb_device_desc_size
    .config_len:    resw 1          ; bytes at config_raw
    .tt:            resd 1          ; its transaction translator: hub slot
                                    ; 0-7, hub port 8-15, multi-TT 16
    .config:        resq 1          ; usb_config* (parsed)
    .config_raw:    resq 1          ; the bytes it was parsed from
    .driver:        resq 1          ; called as driver(dev) when it goes
    .driver_data:   resq 1
endstruc

%define USB_DEV_ATTACHED    1
%define USB_DEV_ADDRESSED   2
%define USB_DEV_CONFIGURED  3
%define USB_DEV_SUSPENDED   4
%define USB_DEV_GONE        5

%define USB_DEVF_AUTHORISED (1 << 0)
%define USB_DEVF_HUB        (1 << 1)

struc usb_xfer
    .dev:           resq 1          ; usb_device*
    .endpoint:      resb 1          ; address (0 for control)
    .type:          resb 1          ; USB_EP_*
    .flags:         resw 1          ; USB_XF_*
    .length:        resd 1
    .buffer:        resq 1          ; physical and virtual are the same
    .setup:         resb usb_setup_size
    .status:        resd 1          ; 0, or a negative USB_E*
    .actual:        resd 1          ; bytes moved
    .done:          resq 1          ; called as done(xfer) on completion
    .context:       resq 1
    .hc_data:       resq 1          ; the controller's own (TRB address)
endstruc

%define USB_XF_SHORT_OK     (1 << 0)    ; a short IN transfer is not an error
%define USB_XF_ZERO_PACKET  (1 << 1)    ; end an OUT with a zero-length packet

%endif ; LIB_USB_USB_INC
