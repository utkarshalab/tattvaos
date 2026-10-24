; =============================================================================
; Utkarsha OS — pkg/format/upk.inc
; =============================================================================
; The UPK package layout (docs/UPK_SPEC.md), the opened-package record, and
; the verifier's errors.
; =============================================================================

%ifndef GUARD_PKG_FORMAT_UPK_INC
%define GUARD_PKG_FORMAT_UPK_INC

UPK_MAGIC               equ 0x004B5055      ; "UPK\0"
UPK_VERSION             equ 1
UPK_HEADER_SIZE         equ 144
UPK_FLAG_SIGNED         equ 1
UPK_MAX_ENTRIES         equ 4096
UPK_MAX_MANIFEST        equ 64 * 1024
UPK_MAX_NAME            equ 32

; header field offsets
UPK_H_MAGIC             equ 0x00
UPK_H_VERSION           equ 0x04            ; word
UPK_H_HSIZE             equ 0x06            ; word
UPK_H_FLAGS             equ 0x08
UPK_H_COUNT             equ 0x0C
UPK_H_ENTRY_OFF         equ 0x10
UPK_H_STR_OFF           equ 0x14
UPK_H_STR_SIZE          equ 0x18
UPK_H_MAN_OFF           equ 0x1C
UPK_H_MAN_SIZE          equ 0x20
UPK_H_FILE_SIZE         equ 0x28            ; qword
UPK_H_SIGNER            equ 0x30            ; 32 bytes
UPK_H_SIGNATURE         equ 0x50            ; 64 bytes

; entry (64 bytes)
UPK_E_PATH              equ 0x00
UPK_E_KIND              equ 0x04
UPK_E_DATA_OFF          equ 0x08            ; qword
UPK_E_SIZE              equ 0x10            ; qword
UPK_E_SHA256            equ 0x18            ; 32 bytes
UPK_ENTRY_SIZE          equ 64

UPK_KIND_MAIN           equ 1
UPK_KIND_LIB            equ 2
UPK_KIND_CMD            equ 3
UPK_KIND_RES            equ 4
UPK_KIND_CONF           equ 5
UPK_KIND_MODEL          equ 6

; package kinds (the manifest's `kind`)
UPK_PKG_APP             equ 1
UPK_PKG_LIB             equ 2
UPK_PKG_CMD             equ 3

; upk_open errors (negative)
UPK_ERR_FORMAT          equ -1      ; header or tables malformed
UPK_ERR_UNSIGNED        equ -2      ; not signed, and unsigned was not allowed
UPK_ERR_UNTRUSTED       equ -3      ; signed by a key not in the trusted list
UPK_ERR_SIGNATURE       equ -4      ; the signature does not verify
UPK_ERR_DIGEST          equ -5      ; a file's SHA-256 does not match
UPK_ERR_MANIFEST        equ -6      ; the manifest is malformed or incomplete
UPK_ERR_PATH            equ -7      ; an entry's path is not a package path

; An opened package (pointers into the package's own bytes)
struc upk_pkg_t
    .data:          resq 1      ; the package
    .size:          resq 1
    .entries:       resq 1      ; its entry table
    .count:         resq 1
    .strtab:        resq 1
    .kind:          resd 1      ; UPK_PKG_*
    .signed:        resd 1      ; 1: signed by a trusted key
    .name:          resq 1      ; the manifest's name (not NUL-terminated)
    .name_len:      resq 1
    .version:       resq 1
    .version_len:   resq 1
    .entry:         resq 1      ; the entry file's upk entry, or 0 (a library)
endstruc

%endif ; GUARD_PKG_FORMAT_UPK_INC
