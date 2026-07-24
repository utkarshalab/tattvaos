; =============================================================================
; Tattva OS — kernel/sched/fiber_guard.inc
; =============================================================================
; Enterprise Fault Isolation and Crash Telemetry Schemas.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef FIBER_GUARD_INC
%define FIBER_GUARD_INC

MAX_CRASH_LOGS equ 32

; Crash Telemetry Record Structure (64 bytes)
struc crash_record_t
    .timestamp    resq 1            ; +00: RDTSC clock timestamp
    .fiber_id     resq 1            ; +08: ID of crashed fiber
    .fiber_name   resq 1            ; +16: ASCIIZ Name pointer
    .cpu_id       resd 1            ; +24: CPU Core ID
    .vector       resd 1            ; +28: Hardware Exception Vector
    .error_code   resq 1            ; +32: Hardware Error Code
    .fault_rip    resq 1            ; +40: Instruction Pointer (RIP)
    .fault_rsp    resq 1            ; +48: Stack Pointer (RSP)
    .fault_cr2    resq 1            ; +56: Faulting memory address (CR2)
endstruc

crash_record_t_size equ 64

%endif ; FIBER_GUARD_INC
