; Whole-file content-defined chunk planning and object-write ABI.
%ifndef VCS_CHUNK_PIPELINE_INC
%define VCS_CHUNK_PIPELINE_INC

VCS_FILE_CHUNK_EXISTING equ 1
VCS_FILE_CHUNK_PRIOR    equ 2

struc vcs_chunk_record
    .id     resb 32
    .data   resq 1
    .length resq 1
endstruc

struc vcs_file_chunk
    .id            resb 32
    .offset        resq 1
    .length        resq 1
    .storage_index resq 1
    .flags         resq 1
endstruc

struc vcs_chunk_pipeline
    .data            resq 1
    .length          resq 1
    .bounds          resq 1
    .bounds_capacity resq 1
    .entries         resq 1
    .entry_capacity  resq 1
    .existing        resq 1
    .existing_count  resq 1
    .new_ios         resq 1
    .new_capacity    resq 1
    .result_count    resq 1
    .result_new      resq 1
endstruc

; Existing records and all caller-owned buffers must be valid and disjoint.
; New-I/O slots arrive with envelope, extent, locator, capacity and transaction
; fields configured. The pipeline fills their payload and object-ID fields.
; Result counters publish only after every new object has been written.
; On failure the caller discards entry and unpublished new-I/O staging buffers;
; their contents are deliberately not treated as a committed transaction.
%ifndef VCS_CHUNK_PIPELINE_IMPLEMENTATION
extern vcs_file_chunks_write
%endif

%endif
