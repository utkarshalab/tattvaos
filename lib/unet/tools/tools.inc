; =============================================================================
; Tattva OS — unet/tools/tools.inc
; =============================================================================
; Master Universal `net` CLI Command Registration & Dispatch Table Specification.
;
; Every network CLI command in Tattva OS starts with the `net` prefix:
;   Example: `net ping <host>`, `net traceroute <host>`, `net iperf`, `net route`
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef UNET_TOOLS_INC
%define UNET_TOOLS_INC

struc net_cmd_entry_t
    .cmd_name:          resq 1      ; Pointer to ASCII command string (e.g. "ping")
    .handler:           resq 1      ; Pointer to function entry point
    .category:          resq 1      ; Pointer to Category String (e.g. "diag")
    .description:       resq 1      ; Pointer to Help String
endstruc

%endif ; UNET_TOOLS_INC
