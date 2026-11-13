; Recoverable scalable repository publication coordinator ABI.
%ifndef VCS_PUBLICATION_INC
%define VCS_PUBLICATION_INC

VCS_PUBLISH_NONE       equ 0
VCS_PUBLISH_BEGUN      equ 1
VCS_PUBLISH_OBJECTS    equ 2
VCS_PUBLISH_OWNERSHIP  equ 3
VCS_PUBLISH_ROOT       equ 4
VCS_PUBLISH_FLUSHED    equ 5
VCS_PUBLISH_COMMITTED  equ 6
VCS_PUBLISH_POISONED   equ 7
VCS_PUBLISH_ABORTED    equ 8

struc vcs_publish_object
    .id      resb 32
    .type    resd 1
    .flags   resd 1
    .payload resq 1
    .length  resq 1
endstruc

; All callbacks return a VCS status except poison, whose result is ignored.
; begin(ctx, tx_sequence, object_count, edge_count)
; put_object(ctx, vcs_publish_object*)
; put_edge(ctx, vcs_ownership_edge*)
; stage_root(ctx, root_bytes, root_length, generation, object_index_root_hash)
; flush(ctx), publish(ctx), abort(ctx), poison(ctx)
struc vcs_publish_backend
    .context    resq 1
    .begin      resq 1
    .put_object resq 1
    .put_edge   resq 1
    .stage_root resq 1
    .flush      resq 1
    .publish    resq 1
    .abort      resq 1
    .poison     resq 1
endstruc

struc vcs_publication
    .backend       resq 1
    .previous_root resq 1 ; prior validated 512-byte superblock, null for genesis
    .objects       resq 1
    .object_count  resq 1
    .edges         resq 1
    .edge_count    resq 1
    .root          resq 1
    .root_length   resq 1
    .tx_sequence   resq 1
    .generation    resq 1
    .index_root    resq 1 ; authenticated vcs_object_index_root
    .result_phase  resq 1
endstruc

%ifndef VCS_PUBLICATION_IMPLEMENTATION
extern vcs_publication_commit
%endif

%endif
