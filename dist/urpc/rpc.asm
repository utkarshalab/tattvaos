%ifndef GUARD_DIST_URPC_RPC_ASM
%define GUARD_DIST_URPC_RPC_ASM
; =============================================================================
; File     : dist/urpc/rpc.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: RPC framework — BXP-based async RPC between Tattva OS nodes.
; =============================================================================

bits 64

section .text

; -----------------------------------------------------------------------------
; urpc_init — Initialize RPC framework
; Input:  none
; Output: rax = 0 on success
; -----------------------------------------------------------------------------
global urpc_init
urpc_init:
    ret

; -----------------------------------------------------------------------------
; urpc_call — Make async RPC call to remote node
; Input:  rdi = target node, rsi = procedure ID, rdx = args
; Output: rax = call ID or error
; -----------------------------------------------------------------------------
global urpc_call
urpc_call:
    ret

%endif ; GUARD_DIST_URPC_RPC_ASM