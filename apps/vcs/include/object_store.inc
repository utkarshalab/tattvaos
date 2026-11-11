; Scalable immutable-object storage codec ABI.
%ifndef VCS_OBJECT_STORE_INC
%define VCS_OBJECT_STORE_INC

VCS_OBJECT_ENVELOPE_BYTES equ 128
VCS_OBJECT_EXTENT_BYTES   equ 4096
VCS_OBJECT_EXTENT_HEADER  equ 64
VCS_OBJECT_EXTENT_PAYLOAD equ 4032
VCS_OBJECT_HASH_BYTES     equ 32
VCS_CHUNK_OBJECT_MAX      equ 32768

struc vcs_chunk_io
    .payload         resq 1 ; write source
    .payload_length  resq 1
    .envelope        resq 1 ; 128 bytes
    .extents         resq 1 ; extent_capacity contiguous 4 KiB blocks
    .locators        resq 1 ; extent_capacity u64 physical locators
    .extent_capacity resq 1
    .transaction     resq 1
    .object_id       resq 1 ; 32-byte output on write, expected ID on read
    .output          resq 1 ; read destination; ignored by verify
    .output_capacity resq 1
    .result_length   resq 1 ; set only after successful read
endstruc

; All pointed-to regions must be valid for their declared sizes and mutually
; disjoint. Write publishes envelope, extents, object_id and result_length only
; after preflight. Read validates the complete chain before publishing output
; and result_length. Verify never writes output or result_length.

%ifndef VCS_OBJECT_STORE_IMPLEMENTATION
extern vcs_object_id
extern vcs_chunk_object_id
extern vcs_chunk_object_write
extern vcs_chunk_object_read
extern vcs_chunk_object_verify
%endif

%endif
