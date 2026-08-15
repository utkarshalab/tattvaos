; =============================================================================
; Tattva OS — lib/ulog/sinks/net_format.asm
; =============================================================================
; RFC 5424 PRI field shaping — the one piece of syslog wire format that
; belongs on this side of the lib/unet boundary, since it's a pure function
; of ulog's own level constants and doesn't need anything unet/services/
; syslog.asm owns. Facility is fixed at "local0" (16); Tattva has no
; multi-facility story yet.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_SINKS_NET_FORMAT_ASM
%define LIB_ULOG_SINKS_NET_FORMAT_ASM

[BITS 64]

%include "lib/ulog/level/level_defs.inc"

%define SYSLOG_FACILITY_LOCAL0  16

section .text

; -----------------------------------------------------------------------------
; net_format_pri — ulog level -> syslog PRI (facility*8 + severity)
; Input:  RDI = level
; Output: RAX = PRI value
; -----------------------------------------------------------------------------
global net_format_pri
net_format_pri:
    ; ulog's LVL_TRACE..LVL_FATAL (0..5) doesn't map 1:1 onto syslog's
    ; EMERG..DEBUG (0..7, most-severe-first) — ulog runs least-severe-first.
    ; Table lookup beats arithmetic here; the two scales just don't line up.
    cmp edi, LVL_TRACE
    je .sev_debug
    cmp edi, LVL_DEBUG
    je .sev_debug
    cmp edi, LVL_INFO
    je .sev_info
    cmp edi, LVL_WARN
    je .sev_warning
    cmp edi, LVL_ERROR
    je .sev_err
    cmp edi, LVL_FATAL
    je .sev_crit
    mov eax, 7                       ; unknown -> DEBUG severity
    jmp .apply_facility
.sev_debug:
    mov eax, 7
    jmp .apply_facility
.sev_info:
    mov eax, 6
    jmp .apply_facility
.sev_warning:
    mov eax, 4
    jmp .apply_facility
.sev_err:
    mov eax, 3
    jmp .apply_facility
.sev_crit:
    mov eax, 2

.apply_facility:
    push rax
    mov eax, SYSLOG_FACILITY_LOCAL0
    imul eax, eax, 8
    pop rdx
    add eax, edx
    ret

%endif ; LIB_ULOG_SINKS_NET_FORMAT_ASM
