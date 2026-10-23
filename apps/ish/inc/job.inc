; =============================================================================
; File     : apps/ish/inc/job.inc
; Project  : Utkarsha OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Job control structures (&, bg, fg, jobs, kill).
; =============================================================================

%ifndef JOB_INC
%define JOB_INC

%include "inc/ish.inc"

; -----------------------------------------------------------------------------
; Job States
; -----------------------------------------------------------------------------
JOB_STATE_RUNNING         equ 0
JOB_STATE_STOPPED         equ 1
JOB_STATE_DONE            equ 2
JOB_STATE_KILLED          equ 3

; -----------------------------------------------------------------------------
; Job Table Entry
; -----------------------------------------------------------------------------
struc job_entry_t
    .magic                resd 1      ; 0x4A4F4201 ("JOB\x01")
    .job_id               resd 1      ; sequential job number
    .fiber_ptr            resq 1      ; ptr to fiber control block
    .state                resd 1      ; JOB_STATE_*
    .cmd_line             resq 1      ; command string
    .exit_code            resd 1      ; exit code when done
    .next                 resq 1
endstruc

JOB_ENTRY_SIZE            equ 48

%endif ; JOB_INC