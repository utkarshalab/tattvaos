; =============================================================================
; Tattva OS — storage/ubxp/ubxp.inc
; =============================================================================
; Master Schema Header for UBXP (Unikernel Binary eXchange Protocol).
;
; Wire-format constants, frame layout and type codes shared by every UBXP
; module.
;
; NOTE: every symbol here is prefixed UBXP_/ubxp_ deliberately. The unrelated
; boot-time format in boot/stage2/fs/bxp.asm ("BXP — Boot eXecution Package")
; owns the bare BXP_ prefix; the two must never collide.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef UBXP_INC
%define UBXP_INC

%define UBXP_MAGIC                   0x50584255          ; "UBXP" little-endian
%define UBXP_VERSION                 1                   ; Current wire version
%define UBXP_HEADER_SIZE             24                  ; Frame header bytes
%define UBXP_MAX_NESTING             32                  ; Container recursion cap
%define UBXP_MAX_PAYLOAD             0x01000000          ; 16MB frame ceiling
%define UBXP_VARINT_MAX_BYTES        10                  ; 64-bit LEB128 worst case
%define UBXP_MAX_FIELD_NUMBER        0x1FFFFFFF          ; 29-bit tag space

; Width of the fixed-size length placeholder reserved by a submessage open and
; patched shut on close. Four LEB128 bytes address 2^28-1, comfortably above
; UBXP_MAX_PAYLOAD, so a nested body can always be back-patched in place
; without shifting the buffer. The cost is a deliberately non-minimal varint,
; which is exactly what ubxp_canonical_check flags when canonical form matters.
%define UBXP_LEN_RESERVE             4
%define UBXP_LEN_RESERVE_MAX         0x0FFFFFFF

; -----------------------------------------------------------------------------
; Wire Types — the low 3 bits of a field tag. These are the only shapes a
; decoder must understand in order to skip a field it has no schema for, which
; is what makes forward compatibility possible.
; -----------------------------------------------------------------------------
%define UBXP_WIRE_VARINT             0                   ; LEB128 integer
%define UBXP_WIRE_FIXED64            1                   ; 8 raw bytes
%define UBXP_WIRE_BYTES              2                   ; varint length + payload
%define UBXP_WIRE_CONTAINER          3                   ; Nested frame, len-prefixed
%define UBXP_WIRE_FIXED32            5                   ; 4 raw bytes
%define UBXP_WIRE_MASK               0x07

; -----------------------------------------------------------------------------
; Logical Types — carried in schema descriptors, not on the wire.
; -----------------------------------------------------------------------------
%define UBXP_TYPE_NULL               0
%define UBXP_TYPE_BOOL               1
%define UBXP_TYPE_INT                2                   ; Zig-zag signed
%define UBXP_TYPE_UINT               3
%define UBXP_TYPE_FLOAT64            4
%define UBXP_TYPE_STRING             5                   ; UTF-8
%define UBXP_TYPE_BYTES              6
%define UBXP_TYPE_ARRAY              7
%define UBXP_TYPE_MAP                8
%define UBXP_TYPE_STRUCT             9

; -----------------------------------------------------------------------------
; Frame Flags
; -----------------------------------------------------------------------------
%define UBXP_FLAG_COMPRESSED         (1 << 0)
%define UBXP_FLAG_ENCRYPTED          (1 << 1)
%define UBXP_FLAG_CRC_PRESENT        (1 << 2)
%define UBXP_FLAG_SCHEMA_TAGGED      (1 << 3)

; -----------------------------------------------------------------------------
; Result Codes — negative errno values, matching the convention used by uxfs.
; -----------------------------------------------------------------------------
%define UBXP_OK                      0
%define UBXP_ERR_NOSPC              -28                  ; Output buffer exhausted
%define UBXP_ERR_INVAL              -22                  ; Malformed argument
%define UBXP_ERR_NESTING            -40                  ; ELOOP: too deeply nested
%define UBXP_ERR_PROTO              -71                  ; EPROTO: bad magic/version
%define UBXP_ERR_TRUNCATED          -74                  ; EBADMSG: input ran out
%define UBXP_ERR_OVERFLOW           -75                  ; EOVERFLOW: varint too long
%define UBXP_ERR_NODEV              -19                  ; ENODEV: no SSE4.2 for CRC32C

; -----------------------------------------------------------------------------
; Frame Header (24 bytes, little-endian)
;
;   payload_len, crc32 and field_count are written as zero by
;   ubxp_frame_write_header and patched in by ubxp_frame_finalize once the
;   body length is known.
; -----------------------------------------------------------------------------
struc ubxp_frame_header_t
    .magic:             resd 1      ; UBXP_MAGIC
    .version:           resb 1      ; UBXP_VERSION
    .flags:             resb 1      ; UBXP_FLAG_* bitmask
    .reserved:          resw 1      ; Must be zero
    .payload_len:       resd 1      ; Body byte length, excluding this header
    .schema_id:         resd 1      ; Schema identifier for evolution rules
    .crc32:             resd 1      ; CRC32 of body (0 when flag absent)
    .field_count:       resd 1      ; Top-level field count
endstruc

; -----------------------------------------------------------------------------
; Cursor — a bounds-checked read/write position over a caller-owned buffer.
;
; `limit` is an absolute one-past-the-end pointer, so a bounds check is a
; single compare against base+pos. `error` is sticky: once set, every
; subsequent operation short-circuits and returns it, so callers may encode a
; whole message and check for failure exactly once at the end.
; -----------------------------------------------------------------------------
struc ubxp_cursor_t
    .base:              resq 1      ; Buffer base pointer
    .limit:             resq 1      ; One past the last valid byte
    .pos:               resq 1      ; Current offset from base
    .depth:             resd 1      ; Container nesting depth
    .error:             resd 1      ; Sticky result code
endstruc

; -----------------------------------------------------------------------------
; Byte-slice view returned by the zero-copy readers.
; -----------------------------------------------------------------------------
struc ubxp_slice_t
    .ptr:               resq 1      ; Pointer into the source buffer
    .len:               resq 1      ; Length in bytes
endstruc

; -----------------------------------------------------------------------------
; Field Descriptor Flags — schema-side attributes, never on the wire.
; -----------------------------------------------------------------------------
%define UBXP_FIELD_OPTIONAL          (1 << 0)
%define UBXP_FIELD_REQUIRED          (1 << 1)    ; Absence is a decode error
%define UBXP_FIELD_REPEATED          (1 << 2)
%define UBXP_FIELD_PACKED            (1 << 3)    ; Repeated scalars in one blob
%define UBXP_FIELD_DEPRECATED        (1 << 4)    ; Retired; never reuse the number

; -----------------------------------------------------------------------------
; Field Descriptor — one static row per declared field. Descriptor tables stand
; in for the generated accessors a .proto compiler would emit: they let a
; decoder validate wire types, enforce required fields and dump a frame
; without any generated code.
; -----------------------------------------------------------------------------
struc ubxp_field_desc_t
    .number:            resd 1      ; Field number
    .wire:              resb 1      ; Expected UBXP_WIRE_*
    .type:              resb 1      ; Logical UBXP_TYPE_*
    .flags:             resb 1      ; UBXP_FIELD_* bitmask
    .reserved:          resb 1
    .name:              resq 1      ; Pointer to a NUL-terminated field name
endstruc

; -----------------------------------------------------------------------------
; Message Descriptor — a named table of field descriptors.
; -----------------------------------------------------------------------------
struc ubxp_msg_desc_t
    .name:              resq 1      ; Pointer to a NUL-terminated message name
    .fields:            resq 1      ; Pointer to ubxp_field_desc_t[]
    .field_count:       resd 1      ; Number of rows
    .schema_id:         resd 1      ; Matches ubxp_frame_header_t.schema_id
endstruc

; -----------------------------------------------------------------------------
; Enum Descriptor — a permitted-value set for a UBXP_TYPE_INT/UINT field.
; -----------------------------------------------------------------------------
struc ubxp_enum_desc_t
    .name:              resq 1      ; Pointer to a NUL-terminated enum name
    .values:            resq 1      ; Pointer to int64 permitted values
    .value_count:       resd 1
    .reserved:          resd 1
endstruc

; -----------------------------------------------------------------------------
; Unknown-Field Store — retains fields the reader has no descriptor for so a
; relay can re-emit them verbatim instead of silently dropping data. Backed by
; a plain cursor over caller-owned memory.
; -----------------------------------------------------------------------------
struc ubxp_unknown_t
    .sink:              resq 1      ; Pointer to a ubxp_cursor_t used as storage
    .count:             resd 1      ; Fields retained
    .truncated:         resd 1      ; Non-zero once the sink overflowed
endstruc

%endif ; UBXP_INC
