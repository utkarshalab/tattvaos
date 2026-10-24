; =============================================================================
; Utkarsha OS — kernel/exec/ubf.inc
; =============================================================================
; The UBF (Utkarsha Binary Format) layout the program loader reads
; (docs/UBF_SPEC.md), the loaded-program record, and the loader's errors.
; =============================================================================

%ifndef KERNEL_EXEC_UBF_INC
%define KERNEL_EXEC_UBF_INC

UBF_MAGIC               equ 0x00464255      ; "UBF\0"
UBF_VERSION             equ 1
UBF_HEADER_SIZE         equ 128
UBF_ARCH_X86_64         equ 1

UBF_KIND_APP            equ 1
UBF_KIND_LIB            equ 2
UBF_KIND_CMD            equ 3
UBF_FLAG_ENTRY          equ 1               ; header flags bit 0

UBF_MAX_SEGMENTS        equ 8
UBF_MAX_MEM             equ 1 << 30         ; 1 GiB
UBF_MAX_NAME            equ 255
UBF_PAGE                equ 4096

; header field offsets
UBF_H_MAGIC             equ 0x00
UBF_H_VERSION           equ 0x04            ; word
UBF_H_HSIZE             equ 0x06            ; word
UBF_H_KIND              equ 0x08            ; word
UBF_H_ARCH              equ 0x0A            ; word
UBF_H_FLAGS             equ 0x0C
UBF_H_MEM_SIZE          equ 0x10            ; qword
UBF_H_ENTRY             equ 0x18            ; qword
UBF_H_STACK             equ 0x20
UBF_H_SEG_COUNT         equ 0x24
UBF_H_SEG_OFF           equ 0x28
UBF_H_REL_OFF           equ 0x2C
UBF_H_REL_COUNT         equ 0x30
UBF_H_IMP_OFF           equ 0x34
UBF_H_IMP_COUNT         equ 0x38
UBF_H_EXP_OFF           equ 0x3C
UBF_H_EXP_COUNT         equ 0x40
UBF_H_STR_OFF           equ 0x44
UBF_H_STR_SIZE          equ 0x48
UBF_H_CPU               equ 0x4C
UBF_H_FILE_SIZE         equ 0x50
UBF_H_SHA256            equ 0x58            ; 32 bytes

; segment entry (32 bytes)
UBF_SEG_TYPE            equ 0x00
UBF_SEG_PROT            equ 0x04
UBF_SEG_FILE_OFF        equ 0x08
UBF_SEG_FILE_SIZE       equ 0x0C
UBF_SEG_MEM_OFF         equ 0x10            ; qword
UBF_SEG_MEM_SIZE        equ 0x18            ; qword
UBF_SEG_ENTRY_SIZE      equ 32

UBF_SEG_TEXT            equ 1
UBF_SEG_RODATA          equ 2
UBF_SEG_DATA            equ 3
UBF_SEG_BSS             equ 4

UBF_PROT_R              equ 1
UBF_PROT_W              equ 2
UBF_PROT_X              equ 4

; relocation entry (8 bytes)
UBF_REL_ENTRY_SIZE      equ 8
UBF_REL_ABS64           equ 1

; import entry (16 bytes)
UBF_IMP_NAME            equ 0x00
UBF_IMP_HASH            equ 0x04
UBF_IMP_SLOT            equ 0x08
UBF_IMP_FLAGS           equ 0x0C
UBF_IMP_ENTRY_SIZE      equ 16
UBF_IMP_WEAK            equ 1

; export entry (16 bytes)
UBF_EXP_NAME            equ 0x00
UBF_EXP_HASH            equ 0x04
UBF_EXP_OFFSET          equ 0x08            ; qword
UBF_EXP_ENTRY_SIZE      equ 16

; cpu_features bits
UBF_CPU_SSE42           equ 1 << 0
UBF_CPU_AVX             equ 1 << 1
UBF_CPU_AVX2            equ 1 << 2
UBF_CPU_BMI             equ 1 << 3
UBF_CPU_AVX512F         equ 1 << 4
UBF_CPU_AVX512BW        equ 1 << 5
UBF_CPU_AES             equ 1 << 6
UBF_CPU_SHA             equ 1 << 7
UBF_CPU_KNOWN           equ 0xFF

; Programs are mapped with 4 KiB pages in their own window, above the
; identity map and the DMA window (both below 1 TiB).
UBF_WINDOW_BASE         equ 0x0000010000000000      ; 1 TiB
UBF_WINDOW_LIMIT        equ 0x0000020000000000      ; 2 TiB

; ubf_load errors (negative)
UBF_ERR_FORMAT          equ -1      ; header, bounds or table malformed
UBF_ERR_DIGEST          equ -2      ; SHA-256 does not match
UBF_ERR_CPU             equ -3      ; needs a CPU feature this CPU lacks
UBF_ERR_NOMEM           equ -4      ; no pages, or the window is full
UBF_ERR_IMPORT          equ -5      ; an import no export provides
UBF_ERR_MAP             equ -6      ; mapping a page failed

; The loaded program
struc ubf_prog_t
    .base:      resq 1      ; virtual address it runs at
    .phys:      resq 1      ; physical address of its pages
    .size:      resq 1      ; mem_size, bytes
    .entry:     resq 1      ; virtual address of the entry point, or 0
    .kind:      resd 1      ; UBF_KIND_*
    .stack:     resd 1      ; stack size it asked for, 0 = default
    .exports:   resq 1      ; its export table (in the file it came from)
    .nexports:  resq 1
    .strtab:    resq 1      ; its string table (in the file)
    .missing:   resq 1      ; on UBF_ERR_IMPORT: the name that was missing
endstruc

; One entry of an export table the loader resolves imports against
struc ubf_export_t
    .hash:      resd 1      ; FNV-1a 32-bit of the name
    .len:       resd 1      ; name length
    .name:      resq 1      ; -> name (NUL-terminated)
    .addr:      resq 1      ; the symbol
endstruc

%endif ; KERNEL_EXEC_UBF_INC
