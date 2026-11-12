; Canonical scalable paged-tree construction and verified traversal.
%ifndef VCS_TREE_OBJECT_INC
%define VCS_TREE_OBJECT_INC

VCS_TREE_PAGE_BYTES       equ 4064
VCS_TREE_PAGE_HEADER      equ 64
VCS_TREE_PAGE_MAX_ENTRIES equ 64
VCS_TREE_NAME_MAX         equ 240
VCS_TREE_ENTRY_BASE       equ 48

struc vcs_tree_entry
    .name        resq 1
    .name_length resq 1
    .target_id   resb 32
    .target_size resq 1
    .kind        resq 1
    .mode        resq 1
    .flags       resq 1
endstruc

struc vcs_tree_build
    .entries         resq 1
    .entry_count     resq 1
    .pages           resq 1
    .page_capacity   resq 1
    .page_ids        resq 1
    .page_lengths    resq 1
    .page_starts     resq 1
    .page_counts     resq 1
    .root            resq 1
    .root_id         resq 1
    .result_pages    resq 1
endstruc

struc vcs_tree_read
    .root            resq 1
    .root_id         resq 1
    .pages           resq 1 ; chain-ordered vcs_chunk_record array
    .page_count      resq 1
    .entries         resq 1 ; optional decoded vcs_tree_entry array
    .entry_capacity  resq 1
    .result_entries  resq 1
endstruc

%ifndef VCS_TREE_OBJECT_IMPLEMENTATION
extern vcs_tree_object_build
extern vcs_tree_object_read
extern vcs_tree_object_verify
%endif

%endif
