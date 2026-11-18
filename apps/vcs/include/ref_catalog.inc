; Canonical scalable mutable ref catalog ABI.
%ifndef VCS_REF_CATALOG_INC
%define VCS_REF_CATALOG_INC

VCS_REF_BRANCH    equ 1
VCS_REF_TAG       equ 2
VCS_REF_REMOTE    equ 3
VCS_REF_WORKSPACE equ 4
VCS_REF_PROTECTED equ 1
VCS_REF_SYMBOLIC  equ 2
VCS_REF_HEADER    equ 48
VCS_REF_NAME_MAX  equ 240

struc vcs_ref_root
    .records      resq 1 ; canonical variable records
    .record_bytes resq 1
    .generation   resq 1
    .root_hash    resq 1 ; output for hash, expected value for verify
endstruc

%ifndef VCS_REF_CATALOG_IMPLEMENTATION
extern vcs_ref_catalog_validate
extern vcs_ref_key_hash
extern vcs_ref_root_hash
extern vcs_ref_root_verify
%endif

%endif
