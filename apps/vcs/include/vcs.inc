; =============================================================================
; File     : include/vcs.inc
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Shared NASM macros, constants, and struct layouts for the VCS.
; =============================================================================

%ifndef VCS_INC
%define VCS_INC

; -----------------------------------------------------------------------------
; Architecture targets
; -----------------------------------------------------------------------------
VCS_ARCH_X86_64   equ 1
VCS_ARCH_AARCH64  equ 2
VCS_ARCH_RISCV64  equ 3

%ifndef VCS_ARCH
%define VCS_ARCH VCS_ARCH_X86_64
%endif

; -----------------------------------------------------------------------------
; VCS object types (domain-separated from UFS subtree hashes)
; -----------------------------------------------------------------------------
VCS_OBJ_UNKNOWN   equ 0
VCS_OBJ_CHUNK     equ 1
VCS_OBJ_FILE      equ 2
VCS_OBJ_TREE      equ 3
VCS_OBJ_COMMIT    equ 4
VCS_OBJ_CHANGE    equ 5
VCS_OBJ_CONFLICT  equ 6
VCS_OBJ_OPERATION equ 7
VCS_OBJ_SIGNATURE equ 8

; -----------------------------------------------------------------------------
; Content-type classifier categories
; -----------------------------------------------------------------------------
VCS_CT_UNKNOWN    equ 0
VCS_CT_ASM        equ 1       ; assembly source (semantic diff/merge)
VCS_CT_LINKER     equ 2       ; linker scripts, layout files
VCS_CT_DOC        equ 3       ; specs, docs, markdown
VCS_CT_WEB_TEST   equ 4       ; HTML, CSS, JS, JSON, SVG, XML (opaque text)
VCS_CT_DATA       equ 5       ; Unicode data, CSV, generated tables
VCS_CT_IMAGE      equ 6       ; PNG, JPEG, WebP, GIF, BMP (binary)
VCS_CT_AUDIO      equ 7       ; WAV, FLAC, MP3, Ogg, Opus, AAC
VCS_CT_VIDEO      equ 8       ; MP4, WebM, MKV, AVI
VCS_CT_FONT       equ 9       ; TTF, OTF, WOFF, WOFF2
VCS_CT_CERT       equ 10      ; PEM, DER, test certificates
VCS_CT_BINARY     equ 11      ; ELF, flat binaries, object files
VCS_CT_ARCHIVE    equ 12      ; zip, gz, xz, tar
VCS_CT_CONFIG     equ 13      ; TOML, INI, key=value
VCS_CT_GENERATED  equ 14      ; generated files, excluded from blame

; -----------------------------------------------------------------------------
; Return codes
; -----------------------------------------------------------------------------
VCS_OK            equ 0
VCS_ERR_GENERIC   equ 1
VCS_ERR_NOT_FOUND equ 2
VCS_ERR_NO_MEM    equ 3
VCS_ERR_IO        equ 4
VCS_ERR_CORRUPT   equ 5
VCS_ERR_CONFLICT  equ 6
VCS_ERR_PERM      equ 7

; -----------------------------------------------------------------------------
; UFS integration: result codes from UFS calls
; -----------------------------------------------------------------------------
UFS_OK            equ 0
UFS_ERR_NOT_FOUND equ 1
UFS_ERR_IO        equ 2
UFS_ERR_LOCKED    equ 3

; -----------------------------------------------------------------------------
; Standard command ABI: rax = cmd_func(argc in edi, argv in rsi)
; All commands preserve callee-saved registers (rbx, rbp, r12-r15).
; -----------------------------------------------------------------------------
%define VCS_CMD_FUNC(name) \
global name; \
name:

; -----------------------------------------------------------------------------
; Include guard end
; -----------------------------------------------------------------------------
%endif ; VCS_INC