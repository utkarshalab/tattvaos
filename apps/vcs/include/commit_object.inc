; Canonical scalable commit validation and ownership planning ABI.
%ifndef VCS_COMMIT_OBJECT_INC
%define VCS_COMMIT_OBJECT_INC

VCS_COMMIT_HEADER       equ 256
VCS_COMMIT_MESSAGE_MAX  equ 65535
VCS_COMMIT_MERGE        equ 1
VCS_COMMIT_SIGNED       equ 2

struc vcs_commit_ownership
    .payload       resq 1
    .length        resq 1
    .commit_id     resq 1 ; expected complete type-4 object ID
    .edges         resq 1 ; caller-owned vcs_ownership_edge array
    .edge_capacity resq 1
    .result_edges  resq 1 ; published only on success
endstruc

%ifndef VCS_COMMIT_OBJECT_IMPLEMENTATION
extern vcs_commit_object_verify
extern vcs_commit_ownership_edges
%endif

%endif
