; Exact scalable ownership edges and explicit reclamation proof ABI.
%ifndef VCS_OWNERSHIP_INC
%define VCS_OWNERSHIP_INC

VCS_OWNER_IMMUTABLE    equ 1
VCS_OWNER_REF          equ 2
VCS_OWNER_SNAPSHOT     equ 3
VCS_OWNER_OPERATION    equ 4
VCS_OWNER_TRANSACTION  equ 5
VCS_OWNER_MIGRATION    equ 6

struc vcs_ownership_edge
    .owner_kind resd 1
    .child_type resd 1
    .owner_key  resb 32
    .child_id   resb 32
    .flags      resq 1
endstruc

struc vcs_file_ownership
    .file          resq 1 ; validated through vcs_file_object_verify
    .edges         resq 1
    .edge_capacity resq 1
    .result_edges  resq 1
endstruc

struc vcs_reclaim_check
    .object_id      resq 1
    .catalog        resq 1
    .catalog_count  resq 1
    .active_readers resq 1 ; target-specific reader-pin count
endstruc

%ifndef VCS_OWNERSHIP_IMPLEMENTATION
extern vcs_ownership_edge_validate
extern vcs_ownership_catalog_validate
extern vcs_file_ownership_edges
extern vcs_ownership_reclaimable
%endif

%endif
