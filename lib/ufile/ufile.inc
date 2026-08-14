; =============================================================================
; Tattva OS — lib/ufile/ufile.inc
; =============================================================================
; Universal File Format Inspection Container (ufile_meta_t) & Constants.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_UFILE_UFILE_INC
%define LIB_UFILE_UFILE_INC

; -----------------------------------------------------------------------------
; Format Category IDs
; -----------------------------------------------------------------------------
UFILE_CAT_UNKNOWN   equ 0
UFILE_CAT_FS        equ 1           ; Filesystems & Boot partitions (FAT32, EXT, GPT...)
UFILE_CAT_AI_MODEL  equ 2           ; AI / ML Models (GGUF, Safetensors, ONNX...)
UFILE_CAT_EXEC      equ 3           ; Executables (ULF, ELF64, PE/COFF...)
UFILE_CAT_ARCHIVE   equ 4           ; Archives (ZIP, TAR, GZIP, ZSTD...)
UFILE_CAT_MEDIA     equ 5           ; Media & Images (PNG, JPEG, WEBP, BMP...)

; -----------------------------------------------------------------------------
; Specific Format Type IDs
; -----------------------------------------------------------------------------
UFILE_TYPE_UNKNOWN  equ 0

; Filesystems & Boot
UFILE_TYPE_FAT32    equ 10
UFILE_TYPE_EXT2     equ 11
UFILE_TYPE_EXT3     equ 12
UFILE_TYPE_EXT4     equ 13
UFILE_TYPE_GPT      equ 14
UFILE_TYPE_MBR      equ 15
UFILE_TYPE_ISO9660  equ 16
UFILE_TYPE_UBF      equ 17

; AI / ML Models
UFILE_TYPE_GGUF     equ 30
UFILE_TYPE_SAFETENSORS equ 31
UFILE_TYPE_ONNX     equ 32

; Executables
UFILE_TYPE_ULF      equ 50
UFILE_TYPE_ELF64    equ 51
UFILE_TYPE_PECOFF   equ 52

; Archives
UFILE_TYPE_ZIP      equ 70
UFILE_TYPE_TAR      equ 71
UFILE_TYPE_GZIP     equ 72
UFILE_TYPE_ZSTD     equ 73

; Media
UFILE_TYPE_PNG      equ 90
UFILE_TYPE_JPEG     equ 91
UFILE_TYPE_WEBP     equ 92
UFILE_TYPE_BMP      equ 93

; Entropy Classifications
UFILE_ENTROPY_TEXT       equ 0      ; H < 5.0 (Raw text/code)
UFILE_ENTROPY_COMPRESSED equ 1      ; 5.0 <= H <= 7.5 (Compressed data)
UFILE_ENTROPY_ENCRYPTED  equ 2      ; H > 7.8 (High-entropy / encrypted)

; -----------------------------------------------------------------------------
; Enterprise Metadata Container Structure (ufile_meta_t)
; Offset layout: 256 bytes total size (L1 Cache Line Aligned)
; -----------------------------------------------------------------------------
struc ufile_meta_t
    .type_id       resd 1           ; +000: Format Type ID
    .category      resd 1           ; +004: Category ID (1=FS, 2=AI, 3=EXEC, 4=ARCH, 5=MEDIA)
    .flags         resq 1           ; +008: Security & Status Flags (Bit 0=Verified, Bit 1=Hardened)
    .size_bytes    resq 1           ; +016: Total payload/file size in bytes
    .entropy_q16   resd 1           ; +024: Fixed-point Q16.16 Shannon Entropy value
    .entropy_type  resd 1           ; +028: Entropy classification
    .mime_str      resq 1           ; +032: Pointer to ASCIIZ MIME string
    .ext_str       resq 1           ; +040: Pointer to default extension string
    
    ; Category-Specific Parameters (+048 .. +172)
    .param1        resq 1           ; +048: FS: Cluster Size | AI: Tensor Count | EXEC: Entry RIP
    .param2        resq 1           ; +056: FS: Total Sectors| AI: Quant Type   | EXEC: Section Count
    .param3        resq 1           ; +064: FS: FAT Offset   | AI: Layer Count   | ARCH: Uncompressed Size
    .param4        resq 1           ; +072: FS: Root Cluster | AI: Context Size  | MEDIA: Width (pixels)
    .param5        resq 1           ; +080: FS: Volume Label | AI: Model Arch    | MEDIA: Height (pixels)
    ; These three RESERVE space; they do not emit it. `times N db 0` inside a
    ; struc assembles bytes into absolute space instead of advancing the offset
    ; counter, which both breaks the enclosing section and leaves the generated
    ; size short by exactly these 80 bytes.
    .guid          resb 16          ; +088: 16-byte Partition GUID
    .label_str     resb 32          ; +104: Sanitized 32-byte ASCII Label Name
    .sha256_digest resb 32          ; +136: 32-byte SHA256 / BLAKE3 Header Hash Digest
    .version       resd 1           ; +168: Format Version (e.g. GGUF v3, FAT32)
    .reserved      resb 84          ; +172..+256: pad the record to 256 bytes
endstruc


%endif ; LIB_UFILE_UFILE_INC
