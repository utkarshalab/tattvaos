; Canonical scalable object-index records and atomic merge planning ABI.
%ifndef VCS_OBJECT_INDEX_INC
%define VCS_OBJECT_INDEX_INC

struc vcs_object_index_record
    .object_id      resb 32
    .envelope       resq 1 ; allocator-provided physical locator
    .payload_length resq 1
    .object_type    resd 1
    .flags          resd 1
    .transaction    resq 1
endstruc

struc vcs_object_index_lookup
    .records      resq 1
    .record_count resq 1
    .object_id    resq 1
    .result       resq 1 ; published only on success
endstruc

struc vcs_object_index_merge
    .existing       resq 1
    .existing_count resq 1
    .inserts        resq 1
    .insert_count   resq 1
    .output         resq 1
    .output_capacity resq 1
    .verify_equal   resq 1 ; callback(existing, insert, context) -> VCS status
    .context        resq 1
    .result_count   resq 1 ; published only on success
endstruc

%ifndef VCS_OBJECT_INDEX_IMPLEMENTATION
extern vcs_object_index_validate
extern vcs_object_index_find
extern vcs_object_index_merge_plan
%endif

%endif
