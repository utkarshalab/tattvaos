; Stable content-defined chunking ABI and format constants.
%ifndef VCS_CHUNK_INC
%define VCS_CHUNK_INC

VCS_CHUNK_MIN          equ 2048
VCS_CHUNK_AVERAGE      equ 8192
VCS_CHUNK_MAX          equ 32768
VCS_CHUNK_MASK         equ VCS_CHUNK_AVERAGE-1
VCS_CHUNK_MIX          equ 0x9e3779b185ebca87
VCS_CHUNK_ERR_INVALID  equ -1
VCS_CHUNK_ERR_CAPACITY equ -2

; rdi=data, rsi=byte length, rdx=exclusive-end qword bounds,
; rcx=bound capacity. rax=count or VCS_CHUNK_ERR_*.
%ifndef VCS_CHUNK_IMPLEMENTATION
extern vcs_chunk
extern vcs_chunk_count
%endif

%endif
