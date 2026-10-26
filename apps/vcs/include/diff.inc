%ifndef VCS_DIFF_INC
%define VCS_DIFF_INC
%include "include/vcs.inc"
VCS_DIFF_LINES equ 256
VCS_DIFF_BYTES equ 1048576
VCS_DIFF_SCRATCH equ 8192 + 257*257*4
VCS_DIFF_EQUAL equ 0
VCS_DIFF_DELETE equ 1
VCS_DIFF_INSERT equ 2
struc vcs_diff_request
 .old: resq 1
 .old_size: resq 1
 .new: resq 1
 .new_size: resq 1
 .scratch: resq 1
 .scratch_size: resq 1
 .output: resq 1
 .capacity: resq 1
endstruc
struc vcs_diff_record
 .kind: resq 1
 .old_offset: resq 1
 .new_offset: resq 1
 .length: resq 1
endstruc
%endif
