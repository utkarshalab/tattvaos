; Canonical scalable file-page/root construction and verified reconstruction.
%ifndef VCS_FILE_OBJECT_INC
%define VCS_FILE_OBJECT_INC

VCS_FILE_PAGE_BYTES       equ 4064
VCS_FILE_PAGE_HEADER      equ 64
VCS_FILE_PAGE_ENTRY       equ 40
VCS_FILE_PAGE_MAX_ENTRIES equ 100
VCS_FILE_ROOT_BYTES       equ 128
VCS_FILE_MODE_MASK        equ 0x1ff
VCS_FILE_FLAGS_MASK       equ 3

struc vcs_file_build
    .data             resq 1
    .length           resq 1
    .entries          resq 1 ; ordered vcs_file_chunk array
    .entry_count      resq 1
    .mode             resq 1
    .flags            resq 1
    .pages            resq 1 ; page_capacity slots of 4,064 bytes
    .page_capacity    resq 1
    .page_ids         resq 1 ; page_capacity complete 32-byte IDs
    .page_lengths     resq 1 ; page_capacity u64 canonical lengths
    .root             resq 1 ; 128-byte canonical payload
    .root_id          resq 1 ; 32-byte output
    .result_pages     resq 1
endstruc

struc vcs_file_read
    .root            resq 1
    .root_id         resq 1
    .pages           resq 1 ; chain-ordered vcs_chunk_record array
    .page_count      resq 1
    .chunks          resq 1 ; file-ordered vcs_chunk_record array
    .chunk_count     resq 1
    .output          resq 1
    .output_capacity resq 1
    .result_length   resq 1
endstruc

%ifndef VCS_FILE_OBJECT_IMPLEMENTATION
extern vcs_file_bytes_hash
extern vcs_file_object_build
extern vcs_file_object_read
%endif

%endif
