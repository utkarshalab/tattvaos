; =============================================================================
; Utkarsha OS — lib/input/hid/hid.inc
; =============================================================================
; The parsed form of a HID report descriptor, shared by every transport
; (USB, Bluetooth, I2C, SPI). Plan: lib/input/ROADMAP.md §6.2.
; =============================================================================

%ifndef LIB_INPUT_HID_HID_INC
%define LIB_INPUT_HID_HID_INC

%define HID_MAX_FIELDS      256
%define HID_MAX_USAGES      1024    ; explicit usages, all fields together
%define HID_MAX_COLLECTIONS 64
%define HID_MAX_DEPTH       16      ; nested collections
%define HID_MAX_PUSH        4       ; Push without Pop
%define HID_MAX_REPORTS     256     ; report IDs 0-255
%define HID_MAX_REPORT_BITS (4096 * 8)

; field kinds
%define HID_INPUT           1
%define HID_OUTPUT          2
%define HID_FEATURE         3

; main item data bits (hid_field.flags)
%define HID_F_CONST         (1 << 0)
%define HID_F_VARIABLE      (1 << 1)    ; else an array of usage indexes
%define HID_F_RELATIVE      (1 << 2)

; usages: page << 16 | usage
%define HID_USAGE(p, u)     (((p) << 16) | (u))

; One field: Report Count elements of Report Size bits each.
; A variable field's element i has usage usages[i] (an explicit list) or
; usage_min + i (a range), the last one repeating. An array field's
; elements hold usage indexes: usage = usage_min + value - logical_min, or
; the list entry at value - logical_min.
struc hid_field
    .report_id:     resb 1
    .kind:          resb 1          ; HID_INPUT, HID_OUTPUT, HID_FEATURE
    .flags:         resw 1          ; main item data bits
    .bit_offset:    resd 1          ; in the report, after the ID byte
    .size:          resw 1          ; bits per element (1-32)
    .count:         resw 1          ; elements
    .usage_min:     resd 1          ; page << 16 | usage
    .usage_max:     resd 1
    .usage_list:    resw 1          ; first entry in hid_desc.usages
    .usage_count:   resw 1          ; entries (0: use the range)
    .logical_min:   resd 1          ; signed
    .logical_max:   resd 1
    .physical_min:  resd 1
    .physical_max:  resd 1
    .unit:          resd 1
    .unit_exp:      resb 1          ; signed, -8 to 7
    .pad:           resb 1
    .collection:    resw 1          ; innermost collection
    .application:   resd 1          ; its application collection's usage
endstruc                            ; 52 bytes

struc hid_collection
    .usage:         resd 1
    .type:          resb 1          ; 0 physical, 1 application, 2 logical...
    .pad:           resb 1
    .parent:        resw 1          ; 0xFFFF for none
endstruc                            ; 8 bytes

struc hid_desc
    .field_count:   resd 1
    .usage_count:   resd 1
    .coll_count:    resd 1
    .uses_ids:      resd 1          ; 1 when reports carry an ID byte
    .report_bits:   resd HID_MAX_REPORTS * 3   ; bits per ID and kind
    .fields:        resb HID_MAX_FIELDS * hid_field_size
    .usages:        resd HID_MAX_USAGES
    .collections:   resb HID_MAX_COLLECTIONS * hid_collection_size
endstruc

; errors (negative in EAX)
%define HID_EINVAL          22      ; a malformed descriptor
%define HID_ENOSPC          28      ; more than the limits above
%define HID_ERANGE          34      ; a field outside the report

%endif ; LIB_INPUT_HID_HID_INC
