; =============================================================================
; Tattva OS — lib/ulog/context/fields_schema.inc
; =============================================================================
; The structured-fields wire format. A fields blob is self-describing (a
; count header, then that many fixed-size entries) so record_encode.asm can
; size it without consulting log_record_t.fields_cnt, and so a future schema
; version can add a val_type without breaking readers that only understand
; the ones that exist today.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_CONTEXT_FIELDS_SCHEMA_INC
%define LIB_ULOG_CONTEXT_FIELDS_SCHEMA_INC

%define FIELD_TYPE_INT      0
%define FIELD_TYPE_UINT     1
%define FIELD_TYPE_HEX      2
%define FIELD_TYPE_STR      3
%define FIELD_TYPE_BOOL     4

struc fields_blob_hdr_t
    .count       resq 1
endstruc

struc field_entry_t
    .key_ptr     resq 1      ; +0   static null-terminated string, never owned
    .val_type    resb 1      ; +8   FIELD_TYPE_*
    .reserved    resb 7      ; +9
    .val         resq 1      ; +16  int64, or a pointer for FIELD_TYPE_STR
endstruc
%define FIELD_ENTRY_SIZE   24

%define FIELDS_MAX_ENTRIES  16    ; a fields blob buffer is sized for this many

%endif ; LIB_ULOG_CONTEXT_FIELDS_SCHEMA_INC
